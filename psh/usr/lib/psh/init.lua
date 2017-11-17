local component = require("component")
local event = require("event")
local ser = require("serialization")
local tty = require("tty")

local m = component.modem
assert(m)

local lib = {}

lib.listeners = {}

lib.tools = {}
lib.tools.daemon = "pshd"
lib.tools.reader = "/usr/bin/psh/psh-reader"
lib.tools.writer = "/usr/bin/psh/psh-writer"
lib.tools.host   = "/usr/bin/psh/psh-host"
lib.tools.client = "psh"

lib.api = setmetatable({},{__index=function(tbl,key)error("no such api:"..key)end})
lib.api.SEARCH = "SEARCH"
lib.api.AVAILABLE = "AVAILABLE"
lib.api.KEEPALIVE = "KEEPALIVE"
lib.api.ACCEPT = "ACCEPT"
lib.api.CONNECT = "CONNECT"
lib.api.CLOSED = "CLOSED"

lib.api.INVOKE = "INVOKE"

lib.api.started = 1
lib.api.stopped = 2

lib.log = {}
lib.log.window = tty.window
function lib.log.write(level, pipe, ...)
  local p = {}
  for _,v in ipairs(table.pack(...)) do
    p[#p + 1] = tostring(v)
  end
  if level > lib.config.LOGLEVEL then
    return
  end
  cprint(table.concat(p, ","))

  -- local proclib = require("process")
  -- local data = proclib.info().data
  -- local old = data.window
  -- data.window = lib.log.window
  -- local sep = ''
  -- pipe:write("\27[33m")
  -- for _,m in ipairs(table.pack(...)) do
  --   pipe:write(sep..tostring(m))
  --   sep=','
  -- end
  -- pipe:write("\27[m\n")
  -- data.window = old
end
lib.log.error = function(...) lib.log.write(1, io.stderr, ...) end
lib.log.info = function(...) lib.log.write(2, io.stdout, ...) end
lib.log.debug = function(...) lib.log.write(3, io.stdout, ...) end

function lib.reload_config(config_path)
  checkArg(1, config_path, "string", "nil")
  config_path = config_path or "/etc/psh/psh.cfg"
  lib.config = {}
  lib.config.LOGLEVEL = 1
  lib.config.DAEMON_PORT = 10022

  local file, reason = io.open(config_path)
  if file then
    local all = file:read("*a")
    file:close()
    all, reason = ser.unserialize(all)
    if all then
      for k,v in pairs(all) do
        lib.config[k] = v
      end
    end
  end
  if reason then
    lib.log.info("failed to load config file '" .. config_path .. "': " .. tostring(reason))
  end
end

lib.reload_config()

lib.internal = {}

function lib.internal.modem_message_pack(
  event_local_id,
  event_remote_id,
  event_port,
  event_distance,
  token, ...)
  lib.log.debug("packing", token, ...)
  if token then
    if select("#", ...) > 1 then
      lib.log.info("pshd modem messages expect a single pack of args after the token, " .. token .. " recieved too many", ...)
      return
    end
    local args = ...
    if type(args) ~= "string" then
      lib.log.debug(string.format("pshd modem message [%s] missing payload", token), ...)
      return
    end
    local arg_table = ser.unserialize(args)
    if not arg_table then
      lib.log.info(string.format("pshd modem message [%s] tried to deserialize: %s", token, args))
      return
    end
    return
    {
      local_id = event_local_id,
      remote_id = event_remote_id,
      port = event_port,
      distance = event_distance,
      token = token,
    }, arg_table
  end
end

function lib.internal.unsafe_modem_message(...)
  local meta, args = lib.internal.modem_message_pack(...)
  if (meta) then
    lib.log.debug("unsafe_modem_message", table.unpack(args, 1, args.n))

    -- first to consume the event wins
    for mh in pairs(lib.listeners) do
      if mh.port == meta.port then
        local handler = mh.tokens and mh.tokens[meta.token]
        if handler then
          if mh.applicable(meta) and handler(meta, table.unpack(args, 1, args.n)) then
            return true
          end
        end
      end
    end

    lib.log.debug("ignoring message, unhandled token: |" .. meta.token .. '|')
  end
end

function lib.internal.modem_message(ename, ...)
  local result, why = xpcall(lib.internal.unsafe_modem_message, function(err) return debug.traceback(err) end, ...)
  if not result then
    io.stderr:write(tostring(why) .. '\n')
  end
end

function lib.internal.start(modemHandler)
  if not modemHandler or type(modemHandler) ~= "table" then
    return false, "lib.start must be given a modem handler"
  end

  lib.log.debug("starting pshd handler: " .. modemHandler.label)
  if lib.listeners[modemHandler] then
    return false, "modem handler insert denied: already exists in listener group"
  end

  local first = not next(lib.listeners)
  lib.listeners[modemHandler] = true
  lib.log.debug(string.format("checking if [%s] is the first handler: %s", modemHandler.label, tostring(first)))
  if first and not event.listen("modem_message", lib.internal.modem_message) then
    return false, "failed to register handler for modem messages"
  end

  local result = true
  local why

  -- if no port, use config port
  if not modemHandler.port then
    modemHandler.port = lib.config.DAEMON_PORT
  end

  if not m.isOpen(modemHandler.port) then
    result, why = m.open(modemHandler.port)
  end

  if result then
    modemHandler.status = lib.api.started
  end

  return result, why
end

function lib.internal.stop(modemHandler)
  if not modemHandler or type(modemHandler) ~= "table" then
    return false, "lib.stop must be given a modem handler"
  end

  lib.log.debug("Stopping pshd handler: " .. modemHandler.label)
  if not lib.listeners[modemHandler] then
    return false, "modem handler removal denied: does not exist in listener group"
  end

  lib.listeners[modemHandler] = nil
  if next(lib.listeners) then
    lib.log.debug("Not unregistering with modem message because psh still has listeners")
  elseif not event.ignore("modem_message", lib.internal.modem_message) then
    return false, "failed to unregister handler for modem messages"
  end

  -- check if any other connections are using this port
  local portStillNeeded = false
  for h in pairs(lib.listeners) do
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

function lib.new(label)
  local mh = {}

  mh.label = label or ""
  mh.ttl = 0
  mh.status = lib.api.stopped
  mh.tokens = {}

  function mh.isStarted()
    return mh.status == lib.api.started
  end

  function mh.start()
    if mh.isStarted() then
      return false, mh.label .. " already started"
    end

    mh.vstart()
    return lib.internal.start(mh)
  end

  function mh.stop()
    if not mh.isStarted() then
      return false, mh.label .. " already stopped"
    end

    mh.vstop()
    return lib.internal.stop(mh)
  end

  function mh.applicable()
    lib.log.error("modem handler application not implemented", mh.label)
    return false
  end

  return mh
end

function lib.checkDaemon()
  if not lib.pshd then
    lib.pshd = require("psh.daemon").new(lib.new("pshd"))
  end

  return lib.pshd.isStarted()
end

function lib.send(id, port, token, ...)
  local payload = ser.serialize(table.pack(...))
  m.send(id, port, token, payload)
end

function lib.broadcast(port, token, ...)
  local payload = ser.serialize(table.pack(...))
  m.broadcast(port, token, payload)
end

return lib
