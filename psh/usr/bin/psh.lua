local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local unicode = require("unicode")
local computer = require("computer")
local config = require("payo-lib/config")
local core_lib = require("psh")

if not component.isAvailable("modem") then
  print("no modem")
  return 1
end

local args, options = shell.parse(...)
local address = args[1]
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

local m = component.modem

local psh_cfg = config.load("/etc/psh.cfg") or {}
local remote = {}

remote.DAEMON_PORT = psh_cfg.DAEMON_PORT or 10022

remote.running = true
remote.delay = 2
remote.connected = false
remote.time_of_last_keepalive = computer.uptime()

function remote.proxy()
  m.send(remote.remote_id, remote.remote_port, core_lib.api.PROXY, "viewport", term.getViewport())
end

function remote.onConnected(remote_port)
  remote.running = true
  remote.connected = true
  remote.ttl = 5
  remote.remote_port = remote_port
  remote.time_of_last_keepalive = computer.uptime()

  remote.proxy()
end

function remote.onDisconnected()
  if (remote.connected) then
    m.send(remote.remote_id, remote.remote_port, core_lib.api.KEEPALIVE, 0)
  end

  remote.connected = false
  remote.ttl = 0
  remote.remote_id = nil
  remote.remote_port = nil
end

function remote.search(remote_id_prefix, bFirst, bVerbose)

  local lport = remote.DAEMON_PORT + 1
  m.close(lport)
  local local_open = m.open(lport)

  if not local_open then
    return nil, "could not listen for results, close some ports"
  end

  local avails = {}

  m.broadcast(remote.DAEMON_PORT, core_lib.api.SEARCH, remote_id_prefix, lport)

  while (true) do
    local eventID = remote.handleNextEvent(nil, {[core_lib.api.AVAILABLE] =
    function(meta)
      local responder = {}
      responder.remote_id = meta.remote_id
      avails[#avails + 1] = responder

      if (bVerbose) then
          io.write("available: " .. responder.remote_id .. '\n')
      end

    end})

    if not eventID then
      break
    elseif #avails > 0 and bFirst then
      break
    end
  end

  m.close(lport)

  return avails
end

function remote.keepalive_check()
  if (remote.connected and (computer.uptime() - remote.time_of_last_keepalive > remote.delay)) then
    remote.time_of_last_keepalive = computer.uptime()
    m.send(remote.remote_id, remote.remote_port, core_lib.api.KEEPALIVE, 10)

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

local function local_modem_message_handler(token_handlers, event_local_id, event_remote_id, event_port, event_distance, token, ...)
  if remote.connected then
    if event_remote_id ~= remote.remote_id or event_port == remote.DAEMON_PORT then
      --io.stderr:write("ignoring unexpected modem message\n")
      return --
    end

    if not remote.ttl or remote.ttl < 10 then
      remote.ttl = 10
    end
  end

  if token then
    local meta =
    {
      local_id = event_local_id,
      remote_id = event_remote_id,
      port = event_port,
      distance = event_distance
    }
    local handler = token_handlers and token_handlers[token]
    if handler then
      handler(meta, ...)
    elseif token == core_lib.api.KEEPALIVE then
      remote.keepalive_update(...)
    else
      io.stderr:write("ignoring message, unsupported token: " .. token .. '\n')
    end
  end
end

function handleEvent(handlers, token_handlers, eventID, ...)
  if eventID == "interrupted" then
    io.stderr:write("aborted\n")
    remote.onDisconnected()
    remote.running = false
  elseif eventID then -- can be nil if no event was pulled for some time
    local handler = handlers and handlers[eventID]
    if handler then
      handler(...)
    elseif eventID == "modem_message" then
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
    if not next or next.n == 0 then
      break
    end
    eventQueue[#eventQueue + 1] = next
  end

  for i,e in ipairs(eventQueue) do
    handleEvent(handlers, token_handlers, table.unpack(e))
  end
end

function remote.connect(cmd)
  remote.running = true
  io.write(string.format("connecting to %s\n", remote.remote_id))
  m.send(remote.remote_id, remote.DAEMON_PORT, core_lib.api.CONNECT, remote.remote_id, remote.local_port, cmd)
end

local handlers = {}
local token_handlers = {}

function remote.pickLocalPort()
  remote.local_port = remote.DAEMON_PORT + 1
  m.close(remote.local_port)
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

function remote.pickSingleHost()
  local responders = remote.search(address, options.f, true)
  if #responders == 0 then
    io.stderr:write("No hosts found\n")
    os.exit(1)
  end

  if #responders > 1 then
    io.stderr:write("Too many hosts\n")
    os.exit(1)
  end

  remote.remote_id = responders[1].remote_id
end

token_handlers[core_lib.api.ACCEPT] = function(meta, remote_port)
  if remote.remote_port then
    io.stderr:write("host tried to specify a port twice")
  else
    remote.onConnected(remote_port or core_lib.api.default_port)
  end
end

token_handlers[core_lib.api.CLOSED] = function(meta)
  remote.connected = false
end

remote.pickSingleHost()
remote.pickLocalPort()

if options.l then -- list only
  os.exit()
end

remote.connect(args[2])

-- main event loop which processes all events, or sleeps if there is nothing to do
while remote.running do

  if remote.remote_port and not remote.connected then
    remote.onDisconnected()
    remote.running = false
  else
    remote.handleNextEvent(handlers, token_handlers)
  end
end

remote.closeLocalPort()

