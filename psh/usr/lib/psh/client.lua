local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local computer = require("computer")
local core_lib = require("psh")

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  os.exit(1)
end

local m = component.modem

local lib = {}
function lib.new()
  local remote = {}

  remote.DAEMON_PORT = core_lib.config.DAEMON_PORT or 10022

  remote.running = true
  remote.delay = 2
  remote.connected = false
  remote.time_of_last_keepalive = computer.uptime()

  -- hard coded handlers that can be cached
  remote.cachers = setmetatable({},{__index=function()return{}end})
  remote.cachers.gpu = {}
  remote.cachers.gpu.getDepth = true
  remote.cachers.gpu.getScreen = true
  remote.cachers.gpu.getViewport = true
  remote.cachers.window = {}
  remote.cachers.window.viewport = true

  function remote.send(...)
    core_lib.send(remote.remote_id, remote.remote_port or remote.DAEMON_PORT, ...)
  end

  function remote.precache()
    local init = function(name, key, the_type, ...)
      remote.send(core_lib.api.PROXY_META_RESULT, name, key, the_type, true, ...)
    end

    term.gpu().setc = function(packx)
      local pack = ser.unserialize(packx)
      local back, fore, x, y, value, vert = table.unpack(pack, 1, 2)
      if back.color then
        term.gpu().setBackground(back.color, back.palette)
      end
      if fore.color then
        term.gpu().setForeground(fore.color, fore.palette)
      end
      term.gpu().set(table.unpack(pack, 3, pack.n))
    end

    init("window", "keyboard", "string", term.keyboard())
    init("gpu", "getDepth", "function", term.gpu().getDepth())
    init("gpu", "getScreen", "function", term.gpu().getScreen())
    init("window", "viewport", "function", term.getViewport())
  end

  function remote.onConnected(remote_port)
    remote.running = true
    remote.connected = true
    remote.ttl = 5
    remote.remote_port = remote_port
    remote.time_of_last_keepalive = computer.uptime()

    remote.precache()
  end

  function remote.onDisconnected()
    if (remote.connected) then
      remote.send(core_lib.api.KEEPALIVE, 0)
    end

    remote.connected = false
    remote.ttl = 0
    remote.remote_id = nil
    remote.remote_port = nil
  end

  function remote.search(address, options)
    remote.pickLocalPort()
    local avails = {}

    core_lib.broadcast(remote.DAEMON_PORT, core_lib.api.SEARCH, remote.local_port)

    while (true) do
      local eventID = remote.handleNextEvent({modem_message = {[core_lib.api.AVAILABLE] =
      function(meta)
        if meta.remote_id:find(address) ~= 1 then
          if options.v then
            print("unmatching: " .. meta.remote_id)
          end
          return
        end

        if options.l or options.v then
          print("available: " .. meta.remote_id)
        end

        table.insert(avails, meta.remote_id)

      end}}, .5)

      if not eventID then
        break
      elseif #avails > 0 and options.f then
        break
      end
    end

    remote.closeLocalPort()

    return avails
  end

  function remote.keepalive_check()
    if (remote.connected and (computer.uptime() - remote.time_of_last_keepalive > remote.delay)) then
      remote.time_of_last_keepalive = computer.uptime()
      remote.ttl = remote.ttl - 1
      if (remote.ttl < 0) then
        io.stderr:write("disconnected: remote timed out\n")
        remote.connected = false
      else
        remote.send(core_lib.api.KEEPALIVE, 10)
      end
    end
  end

  function remote.keepalive_update(ttl_update)
    remote.ttl = ttl_update and tonumber(ttl_update) or 0
  end

  function remote.modem_message_handler(token_handlers, ...)
    local meta, args = core_lib.internal.modem_message_pack(...)
    if not meta then -- not a valid pshd packet
      core_lib.log.info("psh received a modem_message that did not have a valid pshd packet", ...)
      return
    end
    if remote.connected then
      if meta.remote_id ~= remote.remote_id or meta.port == remote.DAEMON_PORT then
        core_lib.log.debug("ignoring unexpected modem message\n")
        return --
      end

      if not remote.ttl or remote.ttl < 10 then
        remote.ttl = 10
      end
    end

    local handler = token_handlers[meta.token]
    if handler then
      handler(meta, table.unpack(args, 1, args.n))
    else
      core_lib.log.debug("ignoring unexpected modem message", meta.token, meta)
    end
  end

  function remote.handleEvent(handlers, eventID, ...)
    core_lib.log.debug(eventID, ...)
    handlers = handlers or remote.handlers
    if eventID then -- can be nil if no event was pulled for some time
      local handler = handlers[eventID]
      if handler then
        -- modem_message works with a table to the modem_message_handler
        if eventID == "modem_message" then
          remote.modem_message_handler(handler, ...)
        else
          handler(...)
        end
      end
    end

    -- keep alive is cheap using a timeout to not spam keepalives
    remote.keepalive_check()

    return eventID
  end

  function remote.handleNextEvent(handlers, delay)
  --TODO handler abort
      --io.stderr:write("aborted\n")
      --remote.onDisconnected()
      --remote.running = false
    return remote.handleEvent(handlers, event.pull(delay or remote.delay))
  end

  function remote.connect(cmd)
    remote.running = true
    term.internal.window().viewport = term.gpu().getViewport
    remote.send(core_lib.api.CONNECT, remote.remote_id, remote.local_port, cmd)
  end

  remote.handlers = {}
  remote.handlers.modem_message = {}

  function remote.pickLocalPort()
    remote.local_port = remote.DAEMON_PORT + 1
    while m.isOpen(remote.local_port) do
      remote.local_port = remote.local_port + 1
    end
    local ok, why = m.open(remote.local_port)
    if not ok then
      io.stderr:write("failed to open local port: " .. tostring(why) .. "\n")
      os.exit(1)
    end
  end

  function remote.closeLocalPort()
    if remote.local_port and m.isOpen(remote.local_port) then
      m.close(remote.local_port)
    end
  end

  function remote.pickSingleHost(address, options)
    local responders, why = remote.search(address, options)
    if not responders then
      io.stderr:write("Failed to search for hosts: " .. tostring(why) .. "\n")
      os.exit(1)
    end
    if #responders == 0 then
      io.stderr:write("No hosts found\n")
      os.exit(1)
    end

    if #responders > 1 then
      if not options.l then
        io.stderr:write("Too many hosts\n")
      end
      os.exit(1)
    end

    remote.remote_id = responders[1]
  end

  return remote
end

return lib
