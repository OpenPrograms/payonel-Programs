local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local computer = require("computer")
local core_lib = require("psh")
local tty = require("tty")

local lib = {}
local m = component.modem

local function pickLocalPort(client)
  if not client.local_port or not m.isOpen(client.local_port) then
    client.local_port = client.DAEMON_PORT + 1
    while m.isOpen(client.local_port) do
      client.local_port = client.local_port + 1
    end
    local ok, why = m.open(client.local_port)
    if not ok then
      return nil, string.format("failed to open local port: %s", tostring(why))
    end
    core_lib.log.debug("port selected:", client.local_port)
  end
  return client.local_port
end

local function closeLocalPort(client)
  if client.local_port and m.isOpen(client.local_port) then
    m.close(client.local_port)
  end
  client.local_port = nil
end

local states = {}

local function set_state(client, state)
  client.state = state
  local handlers = client.handlers.modem_message
  while true do
    local key = next(handlers)
    if key == nil then
      break
    end
    handlers[key] = nil
  end
end

states.init = function(client, next_state, address, options)
  set_state(client, next_state)
  if next_state == states.search then
    local responders = {}
    client.handlers.modem_message[core_lib.api.AVAILABLE] = function(meta)
      if meta.remote_id:find(address) ~= 1 then
        if options.v then
          print("unmatching: " .. meta.remote_id)
        end
        return
      end
      
      if options.l or options.v then
        print("available: " .. meta.remote_id)
      end
      
      table.insert(responders, meta.remote_id)
    end
    local ok, why = pickLocalPort(client)
    if not ok then
      return nil, why
    end
    return responders
  elseif next_state == states.open then
    if not pickLocalPort(client) then
      client.close()
      return nil, "cannot open local port"
    end
    client.remote_id = address
    client.cmd = options or ""
    client.handlers.modem_message[core_lib.api.ACCEPT] = function(meta, remote_port)
      client.keepalive_update(5)
      client.time_of_last_keepalive = computer.uptime()
      client.remote_port = remote_port
      client.state(client, states.run)
      return true
    end
  elseif next_state == states.close then
    -- do nothing
  else
    assert(false, "invalid state change")
  end
end
states.search = function(client, next_state)
  set_state(client, next_state)
  closeLocalPort(client)
  assert(next_state == states.init or next_state == states.close, "invalid state change")
end
states.open = function(client, next_state)
  set_state(client, next_state)
  if next_state == states.run then
    client.handlers.modem_message[core_lib.api.KEEPALIVE] = function(meta)
      client.keepalive_update(10)
    end
    client.handlers.modem_message[core_lib.api.CLOSE] = function(meta, msg)
      if msg then
        io.stderr:write("connection closed: " .. tostring(msg) .. "\n")
      end
      client.connected = false
      -- TODO: reset cursor?
    end
    local cache = {}
    client.handlers.modem_message[core_lib.api.INVOKE] = function(meta, comp, method, ...)
      -- if comp == "gpu" then
      --   return tty.gpu()[method](...)
      -- elseif comp == "stream" then
      --   core_lib.log.info(method)
      --   for _,v in ipairs(table.pack(...)) do
      --     core_lib.log.info("__",require("serialization").serialize(v))
      --   end
      --   return tty.stream[method](tty.stream, ...)
      -- else
        if not cache[comp..method] then
          cache[comp..method] = true
          core_lib.log.info("invoke unknown", comp, method)
        end
      -- end
    end
  elseif next_state == states.close then
    closeLocalPort(client)
  else
    assert(false, "invalid state change")
  end
end
states.run = function(client, next_state)
  set_state(client, next_state)
  closeLocalPort(client)
  assert(next_state == states.close, "invalid state change")
end
states.close = function(client, next_state)
  set_state(client, next_state)
  assert(next_state == states.close, "client is closed")
end

function lib.new()
  local client = {}
  function client.send(...)
    core_lib.send(client.remote_id, client.remote_port, ...)
  end

  client.state = states.init
  client.DAEMON_PORT = core_lib.config.DAEMON_PORT or 10022
  client.delay = 1
  client.time_of_last_keepalive = computer.uptime()
  client.handlers = {}

  client.handlers.modem_message = setmetatable({}, { __call = function(token_handlers, ...)
    local meta, args = core_lib.internal.modem_message_pack(...)
    if not meta then -- not a valid pshd packet
      core_lib.log.debug("modem message not psh data")
      return
    end

    if client.state == states.search then
      if meta.port ~= client.local_port then
        core_lib.log.debug("client state search: response wrong port", meta.port, client.local_port)
        return
      end
    elseif client.state == states.open or  client.state == states.run then
      if meta.remote_id ~= client.remote_id or meta.port ~= client.local_port then
        core_lib.log.debug("client state connect: response wrong remote id or port")
        return
      end
    else
      core_lib.log.debug("client state not expecting modem messages")
      return
    end

    client.keepalive_update(10)
    local handler = token_handlers[meta.token]

    if handler then
      handler(meta, table.unpack(args, 1, args.n))
    else
      core_lib.log.debug("modem message unsupported", meta.token, meta)
    end
  end })

  function client.keepalive_check()
    if client.connected and (computer.uptime() - client.time_of_last_keepalive > client.delay) then
      client.time_of_last_keepalive = computer.uptime()
      client.keepalive_update(client.ttl - 1)
      if client.ttl < 0 then
        io.stderr:write("disconnected: remote timed out\n")
        client.close()
      else
        client.send(core_lib.api.KEEPALIVE)
      end
    end
  end

  function client.keepalive_update(ttl_update)
    client.ttl = ttl_update and tonumber(ttl_update) or 0
  end

  function client.handleEvent(eventID, ...)
    if eventID then -- can be nil if no event was pulled for some time
      core_lib.log.debug(eventID, ...)
      local handler = client.handlers[eventID]
      if handler then
        handler(...)
      end
    end

    -- keep alive is cheap using a timeout to not spam keepalives
    client.keepalive_check()

    return eventID
  end

  function client.handleNextEvent(delay)
  --TODO handler abort
      --io.stderr:write("aborted\n")
      --client.onDisconnected()
      --client.running = false
    local signal = table.pack(xpcall(event.pull, function(msg)
      core_lib.log.info("aborted: ", tostring(msg), debug.traceback())
      return false
    end, delay or client.delay))

    if not signal[1] then
      client.close()
      return
    end

    return client.handleEvent(table.unpack(signal, 2, signal.n))
  end

  function client.search(address, options)
    local responders = client.state(client, states.search, address, options)

    core_lib.broadcast(client.DAEMON_PORT, core_lib.api.SEARCH, client.local_port)
    while client.handleNextEvent(.5) do
      if #responders > 0 and options.f then
        break
      end
    end

    client.state(client, states.init)

    if #responders == 0 then
      return nil, "No hosts found"
    end
    
    if #responders > 1 then
      if not options.l then
        return nil, "Too many hosts"
      end
      return nil
    end

    return responders[1]
  end

  function client.open(remote_id, cmd)
    checkArg(1, remote_id, "string")
    checkArg(2, cmd, "string", "nil")
    client.state(client, states.open, remote_id, cmd)
    if not client.local_port then
      return nil, "failed to open port"
    end
    client.remote_id = remote_id
    client.remote_port = client.DAEMON_PORT
    client.send(core_lib.api.CONNECT, client.local_port, cmd)
    client.remote_port = nil
  end

  function client.close()
    if client.remote_id and client.remote_port then
      client.send(core_lib.api.CLOSE)
    end
    client.remote_id = nil
    client.remote_port = nil
    client.state(client, states.close)
  end

  function client.isOpen()
    return client.state == states.open or client.state == states.run
  end

  return client
end

return lib
