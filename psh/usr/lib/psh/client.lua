local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local computer = require("computer")
local core_lib = require("psh")
local tty = require("tty")

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  os.exit(1)
end

local m = component.modem

local client_gpu = {}

local client_stream = {}

local lib = {}
function lib.new()
  local remote = {}

  remote.DAEMON_PORT = core_lib.config.DAEMON_PORT or 10022

  remote.running = true
  remote.delay = 10
  remote.connected = false
  remote.time_of_last_keepalive = computer.uptime()
  remote.handlers = {}
  remote.handlers.modem_message = setmetatable({}, { __call = function(token_handlers, ...)
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
  end })

  function remote.send(...)
    core_lib.send(remote.remote_id, remote.remote_port or remote.DAEMON_PORT, ...)
  end

  function remote.onConnected(remote_port)
    remote.running = true
    remote.connected = true
    remote.ttl = 5
    remote.remote_port = remote_port
    remote.time_of_last_keepalive = computer.uptime()
    tty.clear()
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
    remote.handlers.modem_message[core_lib.api.AVAILABLE] = function(meta)
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
    end

    while (true) do
      local eventID = remote.handleNextEvent(.5)
      if not eventID then
        break
      elseif #avails > 0 and options.f then
        break
      end
    end

    remote.handlers.modem_message[core_lib.api.AVAILABLE] = nil
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

  function remote.handleEvent(eventID, ...)
    if eventID then -- can be nil if no event was pulled for some time
      core_lib.log.debug(eventID, ...)
      local handler = remote.handlers[eventID]
      if handler then
        handler(...)
      end
    end

    -- keep alive is cheap using a timeout to not spam keepalives
    remote.keepalive_check()

    return eventID
  end

  function remote.handleNextEvent(delay)
  --TODO handler abort
      --io.stderr:write("aborted\n")
      --remote.onDisconnected()
      --remote.running = false
    local signal = table.pack(xpcall(event.pull, function(msg)
      core_lib.log.info("aborted: ", tostring(msg), debug.traceback())
      return false
    end, delay or remote.delay))
    if not signal[1] then
      remote.running = false
      return
    end

    return remote.handleEvent(table.unpack(signal, 2, signal.n))
  end

  function remote.connect(cmd)
    remote.pickLocalPort()
    remote.running = true
    local width, height = tty.getViewport()
    remote.send(core_lib.api.CONNECT, remote.remote_id, remote.local_port, cmd, width, height)
  end

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
    core_lib.log.debug("port selected:", remote.local_port)
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

  remote.handlers.modem_message[core_lib.api.KEEPALIVE] = function(meta, ttl_update)
    remote.keepalive_update(ttl_update)
  end
  
  remote.handlers.modem_message[core_lib.api.ACCEPT] = function(meta, remote_port)
    if remote.remote_port then
      io.stderr:write("host tried to specify a port twice")
    else
      remote.onConnected(remote_port or core_lib.api.default_port)
    end
  end
  
  remote.handlers.modem_message[core_lib.api.CLOSED] = function(meta, msg)
    if msg then
      io.stderr:write("connection closed: " .. tostring(msg) .. "\n")
    end
    remote.connected = false
    -- TODO: reset cursor?
  end

local cache = {}
  remote.handlers.modem_message[core_lib.api.INVOKE] = function(meta, comp, method, ...)
    if comp == "gpu" then
      return tty.gpu()[method](...)
    elseif comp == "stream" then
      core_lib.log.info(method)
      for _,v in ipairs(table.pack(...)) do
        core_lib.log.info("__",require("serialization").serialize(v))
      end
      return tty.stream[method](tty.stream, ...)
    else
      if not cache[comp..method] then
        cache[comp..method] = true
        core_lib.log.info("invoke unknown", comp, method)
      end
    end
  end
  
  return remote
end

return lib
