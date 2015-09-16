local component = require("component")
local event = require("event")
local config = require("payo-lib/config")
local tutil = require("payo-lib.tableutil")

local m = component.modem
assert(m)

local host_lib = require("psh.host")

local lib = {}

lib.listeners = {}

lib.tools = {}
lib.tools.daemon = "pshd"
lib.tools.reader = "/usr/bin/psh/psh-reader"
lib.tools.writer = "/usr/bin/psh/psh-writer"
lib.tools.host   = "/usr/bin/psh/psh-host"
lib.tools.client = "psh"

lib.api = {}
lib.api.SEARCH = "SEARCH"
lib.api.AVAILABLE = "AVAILABLE"
lib.api.KEEPALIVE = "KEEPALIVE"
lib.api.INPUT = "INPUT"
lib.api.ACCEPT = "ACCEPT"
lib.api.CONNECT = "CONNECT"
lib.api.OUTPUT = "OUTPUT"
lib.api.INPUT_SIGNAL = "input_update"
lib.api.INPUT = "INPUT"
lib.api.KEEPALIVE = "KEEPALIVE"

lib.api.started = 1
lib.api.stopped = 2

lib.api.port_default = 10022

lib.log = {}
function lib.log.write(pipe, ...)
  for _,m in ipairs(table.pack(...)) do
    pipe:write(tostring(m) .. '\t')
  end
  pipe:write('\n')
end
lib.log.debug = function(...) lib.log.write(io.stdout, ...) end
lib.log.error = function(...) lib.log.write(io.stderr, ...) end
lib.log.info = lib.log.debug

lib.ModemHandler = {}
function lib.ModemHandler.new(label)
  local mh = {}
  mh.label = label or ""
  mh.ttl = 0

  function mh.isStarted()
    return mh.status == lib.api.started
  end

  function mh.start()
    if mh.isStarted() then
      return false, mh.label .. " already started"
    end

    return lib.start(mh)
  end

  function mh.stop()
    if mh.isStarted() then
      return false, mh.label .. " already stopped"
    end

    return lib.stop(mh)
  end

  mh.status = lib.api.stopped
  mh.tokens = {}

  return mh
end

lib.pshd = lib.ModemHandler.new('pshd')
lib.psh = lib.ModemHandler.new('psh')

function lib.start(modemHandler)
  if not modemHandler or type(modemHandler) ~= "table" then
    return false, "lib.start must be given a modem handler"
  end

  if tutil.indexOf(lib.listeners, modemHandler) then
    return false, "modem handler insert denied: already exists in listener group"
  end

  table.insert(lib.listeners, modemHandler)
  if #lib.listeners > 1 then
    lib.log.info("Not registering with modem message because psh library was already registered")
  elseif not event.listen("modem_message", lib.modem_message) then
    return false, "failed to register handler for modem messages"
  end

  local result = true
  local why

  -- if no port, use config port
  if not modemHandler.port then
    modemHandler.port = (config.load("/etc/psh.cfg") or {}).port or lib.api.port_default
  end

  if not m.isOpen(modemHandler.port) then
    result, why = m.open(modemHandler.port)
  end

  if result then
    modemHandler.status = lib.api.started
  end

  return result, why
end

function lib.stop(modemHandler)
  if not modemHandler or type(modemHandler) ~= "table" then
    return false, "lib.stop must be given a modem handler"
  end

  local index = tutil.indexOf(lib.listeners, modemHandler)
  if not index then
    return false, "modem handler removal denied: does not exist in listener group"
  end

  if table.remove(lib.listeners, index) ~= modemHandler then
    return false, "failed to add modem handler to listener group"
  elseif #lib.listeners > 0 then
    lib.log.INFO("Not unregistering with modem message because psh still has listeners")
  elseif not event.ignore("modem_message", lib.modem_message) then
    return false, "failed to unregister handler for modem messages"
  end

  local portStillNeeded = false
  for _,h in ipairs(lib.listeners) do
    if h.port == modemHandler.port then
      portStillNeeded = true
      break
    end
  end

  local result = true
  local why

  if not portStillNeeded then
    result, why = m.close(modemHandler.port)
  end

  if result then
    modemHandler.status = lib.api.stopped
  end

  return result, why
end

function lib.modem_message(ename, ...)
  local packed = table.pack(...)
  local bad = function()
    lib.unsafe_modem_message(table.unpack(packed))
  end

  local result, why = xpcall(bad, function(err) return debug.traceback(err) end)
  if not result then
    io.stderr:write(tostring(why) .. '\n')
  end
end

function lib.unsafe_modem_message(
  event_local_id, 
  event_remote_id, 
  event_port, 
  event_distance, 
  token, ...)

  if (token) then
    local meta =
    {
      local_id = event_local_id,
      remote_id = event_remote_id,
      port = event_port,
      distance = event_distance
    }

    -- first to consume the event wins
    for _,mh in ipairs(lib.listeners) do
      if mh.port == event_port then
        local handler = mh.tokens and mh.tokens[token]
        if handler then
          if handler(meta, ...) then
            return true
          end
        end
      end
    end

    lib.log.debug("ignoring message, unsupported token: " .. token)
  end
end

lib.pshd.tokens[lib.api.SEARCH] = function (meta, p1, p2)
  local remote_port = p2 and tonumber(p2) or nil
  if remote_port then
        
    local wants_us = true
    p1 = (p1 and p1:len() > 0 and p1) or nil
    if p1 then
      local id = meta.local_id:find(p1)
      wants_us = id == 1
    end

    if wants_us then
      lib.log.debug("available, responding to " .. meta.remote_id .. " on " .. tostring(remote_port))
      m.send(meta.remote_id, remote_port, lib.api.AVAILABLE)
      return true -- consume token
    else
      lib.log.debug("ignoring search: does not want us")
    end
  else
    lib.log.debug("search did not send remote port")
  end
end

lib.pshd.tokens[lib.api.CONNECT] = function (meta, p1, p2)
  local remote_port = p2 and tonumber(p2) or nil
    
  if remote_port then
    local wants_us = meta.local_id == p1

    if wants_us then
      lib.log.debug("sending accept: " .. tostring(meta.remote_id)
        ..",".. tostring(remote_port) ..",".. lib.api.ACCEPT)
                
      m.send(meta.remote_id, remote_port, lib.api.ACCEPT)

      local host = lib.ModemHandler.new('pshd-host:' .. meta.remote_id)

      local hostArgs =
      {
        remote_id = meta.remote_id,
        remote_port = remote_port,
        port = meta.port,
        shutdown = function()
          m.send(host.remote_id, host.remote_port, pshlib.api.KEEPALIVE, 0)
          return lib.stop(host)
        end
      }

      local ok, reason = host_lib.init(lib, host, hostArgs)
      if not ok then
        lib.log.error("failed to initialize new host", reason)
      else
        ok, reason = lib.start(host)
        if not ok then
          lib.log.error("failed to register host", reason)
        end
      end

      return true -- consume token
    else
      lib.log.debug("ignoring: does not want us")
    end
  end
end


return lib
