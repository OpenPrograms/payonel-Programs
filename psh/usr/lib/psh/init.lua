local component = require("component")
local event = require("event")
local config = require("payo-lib/config")
local tutil = require("payo-lib.tableutil")

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
lib.api.PROXY_META = "PROXY_META"
lib.api.PROXY_META_RESULT = "PROXY_META_RESULT"
lib.api.PROXY_ASYNC = "PROXY_ASYNC"
lib.api.PROXY_SYNC = "PROXY_SYNC"
lib.api.PROXY_RESULT = "PROXY_RESULT"
lib.api.EVENT = "EVENT"

lib.api.started = 1
lib.api.stopped = 2

lib.api.default_port = 10022

lib.config = config.load("/etc/psh.cfg") or {}
lib.config.LOGLEVEL = lib.config.LOGLEVEL or 1
lib.config.DAEMON_PORT = lib.config.DAEMON_PORT or lib.api.default_port

lib.log = {}
lib.log.window = require("term").internal.window()
function lib.log.write(level, pipe, ...)
  if level > lib.config.LOGLEVEL then
    return
  end

  component.ocemu.log(...)
  --local proclib = require("process")
  --local data = proclib.info().data
  --local old = data.window
  --data.window = lib.log.window
  --local sep = ''
  --for _,m in ipairs(table.pack(...)) do
  --  pipe:write(sep..tostring(m))
  --  sep=','
  --end
  --pipe:write('\n')
  --data.window = old
end
lib.log.error = function(...) lib.log.write(1, io.stderr, ...) end
lib.log.info = function(...) lib.log.write(2, io.stdout, ...) end
lib.log.debug = function(...) lib.log.write(3, io.stdout, ...) end

lib.internal = {}

function lib.internal.modem_message_pack(
  event_local_id,
  event_remote_id,
  event_port,
  event_distance,
  token, ...)
  if (token) then
    return
    {
      local_id = event_local_id,
      remote_id = event_remote_id,
      port = event_port,
      distance = event_distance,
      token = token,
    }, table.pack(...)
  end
end

function lib.internal.unsafe_modem_message(...)
  local meta, args = lib.internal.modem_message_pack(...)
  if (meta) then
    lib.log.debug("unsafe_modem_message", table.unpack(args, 1, args.n))

    -- first to consume the event wins
    for _,mh in pairs(lib.listeners) do
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

  if tutil.indexOf(lib.listeners, modemHandler) then
    return false, "modem handler insert denied: already exists in listener group"
  end

  table.insert(lib.listeners, modemHandler)
  if #lib.listeners == 1 and not event.listen("modem_message", lib.internal.modem_message) then
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

  local index = tutil.indexOf(lib.listeners, modemHandler)
  if not index then
    return false, "modem handler removal denied: does not exist in listener group"
  end

  if table.remove(lib.listeners, index) ~= modemHandler then
    return false, "failed to add modem handler to listener group"
  elseif #lib.listeners > 0 then
    lib.log.debug("Not unregistering with modem message because psh still has listeners")
  elseif not event.ignore("modem_message", lib.internal.modem_message) then
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

return lib
