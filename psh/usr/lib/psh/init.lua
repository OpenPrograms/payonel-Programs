local component = require("component")
local event = require("event")
assert(component and event)

local m = component.modem
local config = require("payo-lib/config")
assert(m and config)

local psh_cfg = config.load("/etc/psh.cfg")
psh_cfg = psh_cfg or {} -- simplify config checks later on

local lib = {}

lib.listening = false

lib.api = {}
lib.api.SEARCH = "SEARCH"
lib.api.AVAILABLE = "AVAILABLE"
lib.api.KEEPALIVE = "KEEPALIVE"
lib.api.INPUT = "INPUT"
lib.api.ACCEPT = "ACCEPT"
lib.api.CONNECT = "CONNECT"

lib.api.started = 1
lib.api.stopped = 2

lib.api.port = 10022

lib.log = {}
function lib.log.all(pipe, ...)
  for _,m in ipairs(table.pack(...)) do
    pipe:write(tostring(m) .. '\t')
  end
  pipe:write('\n')
end
lib.log.debug = function(...) lib.log.all(io.stdout, ...) end
lib.log.error = function(...) lib.log.all(io.stderr, ...) end
lib.log.info = io.debug

lib.pshd = {}
lib.pshd.status = lib.api.stopped
lib.pshd.tokens = {}

lib.psh = {}
lib.psh.status = lib.api.stopped
lib.psh.tokens = {}

function lib.api.pickLocalPort()
  for i=lib.api.port+1,64000 do
    if not m.isOpen(i) then
      return m.open(i), i
    end
  end
end

function lib.pshd.isStarted()
  return lib.pshd.status == lib.api.started
end

function lib.pshd.start()
  if lib.pshd.isStarted() then
    return false, "pshd already started"
  end

  if lib.listening then
    lib.log.INFO("Not registering with modem message because psh library was already registered")
  elseif event.listen("modem_message", lib.modem_message) then
    lib.listening = true
  else
    return false, "failed to register pshd daemon handler for modem messages"
  end

  local result
  local why
  if not m.isOpen(lib.api.port) then
    result, why = m.open(lib.api.port)
  end

  if result then
    lib.pshd.status = lib.api.started
  end

  return result, why
end

function lib.pshd.stop()
  if lib.pshd.isStarted() then
    return false, "pshd already stopped"
  end

  if not lib.listening then
    lib.log.INFO("Not unregistering with modem message because psh library is not uegistered")
  elseif event.ignore("modem_message", lib.modem_message) then
    lib.listening = false
  else
    return false, "failed to unregister pshd daemon handler for modem messages"
  end

  local result
  local why
  if m.isOpen(lib.api.port) then
    result, why = m.close(lib.api.port)
  end

  if result then
    lib.pshd.status = lib.api.stopped
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
    local handler = lib.pshd.tokens and lib.pshd.tokens[token]
    if handler then
      handler(meta, ...)
    else
      lib.log.debug("ignoring message, unsupported token: " .. token)
    end
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
    else
      lib.log.debug("ignoring search: does not want us")
    end
  else
    lib.log.debug("search did not send remote port")
  end
end

lib.pshd.tokens[lib.api.CONNECT] = function (meta, p1, p2)
  local remote_port = p2 and tonumber(p2) or nil
  local local_port
    
  if remote_port then
        
    local wants_us = meta.local_id == p1

    if wants_us then
            
      local ok
      ok, local_port = lib.api.pickLocalPort()
            
      if not ok then
        lib.log.info("abort: failed to open shell port for remote connect request")
        return false
      end

      lib.log.debug("sending accept: " .. tostring(meta.remote_id) 
        ..",".. tostring(remote_port) ..",".. lib.api.ACCEPT ..",".. tostring(local_port))
                
      m.send(meta.remote_id, remote_port, lib.api.ACCEPT, local_port)
            
      local invoke = string.format("/usr/bin/psh/psh-host" .. " %s %s %s", 
        tostring(local_port),
        tostring(meta.remote_id), 
        tostring(remote_port))
                
      lib.log.debug("request wants us: ", invoke)
            
      local ok, reason = os.execute(invoke)
            
      if not ok then
        lib.log.error("failed to invoke: " .. reason .. "\n")
      else
        lib.log.debug("connection closed with: ", meta.remote_id)
      end

      m.close(local_port)
    else
      lib.log.debug("ignoring: does not want us")
    end
  end
end


return lib
