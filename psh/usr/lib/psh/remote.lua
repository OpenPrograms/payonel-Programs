local m = require("component").modem
local computer = require("computer")
local event = require("event")
local config = require("payo-lib/config")

local psh_cfg = config.load("/etc/psh.cfg")
psh_cfg = psh_cfg or {} -- simplify config checks later on

local remote = {}

remote.DAEMON_PORT = psh_cfg.DAEMON_PORT or 10022

remote.messages = {}

-- tools
remote.tools = {}
remote.tools.daemon = "pshd"
remote.tools.reader = "/usr/bin/psh/psh-reader"
remote.tools.writer = "/usr/bin/psh/psh-writer"
remote.tools.host   = "/usr/bin/psh/psh-host"
remote.tools.client = "psh"

-- sent from both
remote.messages.KEEPALIVE = "KEEPALIVE"

-- sent from server
remote.messages.PROMPT = "PROMPT"
remote.messages.READ = "READ"
remote.messages.AVAILABLE = "AVAILABLE"
remote.messages.OUTPUT = "OUTPUT"
remote.messages.ACCEPT = "ACCEPT"
remote.messages.INPUT_SIGNAL = "input_update"

-- sent from client
remote.messages.SEARCH = "SEARCH"
remote.messages.INPUT = "INPUT"
remote.messages.CONNECT = "CONNECT"

-- connection alive

remote.running = true
remote.delay = 2
remote.connected = false
remote.time_of_last_keepalive = computer.uptime()
remote.buffer = ""
remote.client_side_line_buffering = true

function remote.onConnected(remote_id, remote_port)
  remote.running = true
  remote.connected = true
  remote.ttl = 5
  remote.remote_id = remote_id
  remote.remote_port = remote_port
  remote.time_of_last_keepalive = computer.uptime()
  remote.buffer = ""
end

function remote.onDisconnected()

  if (remote.connected) then
    m.send(remote.remote_id, remote.remote_port, remote.messages.KEEPALIVE, 0)
  end

  remote.connected = false
  remote.ttl = 0
  remote.remote_id = nil
  remote.remote_port = nil
  remote.buffer = ""
end

function remote.search(remote_id_prefix, bFirst, bVerbose)

  local lport = remote.DAEMON_PORT + 1
  m.close(lport)
  local local_open = m.open(lport)

  if (not local_open) then
    return nil, "could not listen for results, close some ports"
  end

  local avails = {}

  m.broadcast(remote.DAEMON_PORT, remote.messages.SEARCH, remote_id_prefix, lport)

  while (true) do
    local eventID = remote.handleNextEvent(nil, {[remote.messages.AVAILABLE] =
    function(meta)
      local responder = {}
      responder.remote_id = meta.remote_id
      avails[#avails + 1] = responder

      if (bVerbose) then
          io.write("available: " .. responder.remote_id .. '\n')
      end

    end})

    if (not eventID) then
      break
    elseif (#avails > 0 and bFirst) then
      break
    end
  end

  m.close(lport)

  return avails
end

function remote.keepalive_check()
  if (remote.connected and (computer.uptime() - remote.time_of_last_keepalive > remote.delay)) then
    remote.time_of_last_keepalive = computer.uptime()
    m.send(remote.remote_id, remote.remote_port, remote.messages.KEEPALIVE, 10)

    remote.ttl = remote.ttl - 1
    if (remote.ttl < 0) then
      io.stderr:write("disconnected: remote timed out\n")
      remote.connected = false
    end
  end
end

function remote.keepalive_update(ttl_update)
  remote.ttl = ttl_update and tonumber(ttl_update) or 0
end

function remote.send_output(text, level)
  if (remote.connected) then
    m.send(remote.remote_id, remote.remote_port, remote.messages.OUTPUT, text, level)
  else
    local out = (level == 1 and io.stdout) or (level == 2 and io.stderr)
    out:write(text or "")
  end
end

function remote.store_input(value)

  if (not remote.ttl or remote.ttl < 10) then
    remote.ttl = 10
  end

  if (type(value) ~= type("")) then
    io.stderr:write("input type not string, " .. type(value) .. '\n')
    return
  end

  if (value:len() == 0) then -- ignore
    return
  end

  remote.buffer = remote.buffer .. value
  local last_char = value:sub(value:len(), value:len())

  if (not remote.client_side_line_buffering) then
    -- it would seem this is for input insertion, but we already have the input buffer on  this side
    remote.send_output(value, 1, false)
  end

  computer.pushSignal(remote.messages.INPUT_SIGNAL, last_char, remote.buffer:len())
end

function remote.read(length)
  local b = remote.buffer:sub(1, length)
  remote.buffer = remote.buffer:sub(length + 1)
  return b
end

local function local_modem_message_handler(token_handlers, event_local_id, event_remote_id, event_port, event_distance, token, ...)

  if (remote.connected) then
    if (event_remote_id ~= remote.remote_id or event_port == remote.DAEMON_PORT) then
      --io.stderr:write("ignoring unexpected modem message\n")
      return --
    end

    if (not remote.ttl or remote.ttl < 10) then
      remote.ttl = 10
    end
  end

  if (token) then
    local meta =
    {
      local_id = event_local_id,
      remote_id = event_remote_id,
      port = event_port,
      distance = event_distance
    }
    local handler = token_handlers and token_handlers[token]
    if (handler) then
      handler(meta, ...)
    elseif (token == remote.messages.KEEPALIVE) then
      remote.keepalive_update(...)
    elseif (token == remote.messages.INPUT) then
      remote.store_input(...)
    else
      io.stderr:write("ignoring message, unsupported token: " .. token .. '\n')
    end
  end
end

function handleEvent(handlers, token_handlers, eventID, ...)
  if (eventID == "interrupted") then
    io.stderr:write("aborted\n")
    remote.onDisconnected()
    remote.running = false
  elseif (eventID) then -- can be nil if no event was pulled for some time
    local handler = handlers and handlers[eventID]
    if (handler) then
      handler(...)
    elseif (eventID == "modem_message") then
      local_modem_message_handler(token_handlers, ...)
    end
  end

  -- keep alive is cheap using a timeout to not spam keepalives
  remote.keepalive_check()

  return eventID
end

function remote.handleNextEvent(handlers, token_handlers)
  return handleEvent(handlers, token_handlers, event.pull(remote.delay))
end

function remote.flushEvents(handlers, token_handlers)
  local eventQueue = {}
  while (true) do
    local next = table.pack(event.pull(0))
    if (not next or next.n == 0) then
      break
    end
    eventQueue[#eventQueue + 1] = next
  end

  for i,e in ipairs(eventQueue) do
    handleEvent(handlers, token_handlers, table.unpack(e))
  end
end

function remote.connect(remote_id, local_port, cmd)
  remote.running = true
  io.write(string.format("connecting to %s\n", remote_id))
  m.send(remote_id, remote.DAEMON_PORT, remote.messages.CONNECT, remote_id, local_port, cmd)
end

return remote
