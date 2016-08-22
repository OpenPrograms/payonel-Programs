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

local args, options = shell.parse(...)
local address = args[1]
local cmd = args[2]
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

options.l = options.l or options.list
options.f = not options.l and (options.f or options.force)
options.v = options.v or options.verbose
options.h = options.h or options.help

local ec = 0

if not address and (not options.h and not options.f and not options.l) then
  options.h = true
  io.stderr:write("ADDRESS is required unless using --first or --list\n")
  ec = 1
end

address = address or ""

if options.h then
print("Usage: psh OPTIONS [ADDRESS [CMD]]")
print([[OPTIONS
  -f  --first   connect to the first remote host available
  -v  --verbose verbose output
  -l  --list    list available hosts, do not connect
  -h  --help    print this help
ADDRESS
  Any number of starting characters of a remote host computer address.
  Address is optional if
    1. -f (--force) is specified, in which case the first available matching host is used
    2. -l (--list) is given, which overrides --force (if given), and no connection is made
CMD
  The command to run on the remote host. CMD can only be specified if an address is also given.
  It is possible to use an empty string for ADDRESS with -f: `psh -f '' cmd`
  If no command is given, the remote command run is the shell prompt]])
  os.exit(ec)
end

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  return 1
end

local m = component.modem

local psh_cfg = config.load("/etc/psh.cfg") or {}
local remote = {}

remote.DAEMON_PORT = psh_cfg.DAEMON_PORT or 10022

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
  m.send(remote.remote_id, remote.remote_port or remote.DAEMON_PORT, ...)
end

function remote.precache()
  local init = function(name, key, the_type, ...)
    remote.send(core_lib.api.PROXY_META, name, key, the_type, true, ...)
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

function remote.search()

  local lport = remote.DAEMON_PORT + 1
  m.close(lport)
  local local_open = m.open(lport)

  if not local_open then
    return nil, "could not listen for results, close some ports"
  end

  local avails = {}

  m.broadcast(remote.DAEMON_PORT, core_lib.api.SEARCH, lport)

  while (true) do
    local eventID = remote.handleNextEvent(nil, {[core_lib.api.AVAILABLE] =
    function(meta)
      if meta.remote_id:find(address) ~= 1 then
        if options.v then
          print("unmatching: " .. meta.remote_id)
        end
        return
      end
      local responder = {}
      responder.remote_id = meta.remote_id
      avails[#avails + 1] = responder

      if options.l or options.v then
        print("available: " .. responder.remote_id)
      end

    end}, .5)

    if not eventID then
      break
    elseif #avails > 0 and options.f then
      break
    end
  end

  m.close(lport)

  return avails
end

function remote.keepalive_check()
  if (remote.connected and (computer.uptime() - remote.time_of_last_keepalive > remote.delay)) then
    remote.time_of_last_keepalive = computer.uptime()
    remote.send(core_lib.api.KEEPALIVE, 10)

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
    token_handlers = token_handlers or remote.token_handlers or {}
    local handler = token_handlers[token]
    if handler then
      handler(meta, ...)
    elseif token == core_lib.api.KEEPALIVE then
      remote.keepalive_update(...)
    else
      io.stderr:write("ignoring message, unsupported token: " .. token .. '\n')
    end
  end
end

function remote.handleEvent(handlers, token_handlers, eventID, ...)
  handlers = handlers or remote.handlers
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

function remote.handleNextEvent(handler, token_handlers, delay)
  return remote.handleEvent(handler, token_handlers, event.pull(delay or remote.delay))
end

function remote.flushEvents()
  local eventQueue = {}
  while (true) do
    local next = table.pack(event.pull(0))
    if not next or next.n == 0 then
      break
    end
    eventQueue[#eventQueue + 1] = next
  end

  for i,e in ipairs(eventQueue) do
    remote.handleEvent(nil, nil, table.unpack(e))
  end
end

function remote.connect(cmd)
  remote.running = true
  if options.v then
    print("connecting to " .. remote.remote_id)
  end
  term.internal.window().viewport = term.gpu().getViewport
  remote.send(core_lib.api.CONNECT, remote.remote_id, remote.local_port, cmd)
end

remote.handlers = {}
remote.token_handlers = {}

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
  local responders = remote.search()
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

remote.handlers["key_down"] = function(...)
  remote.send(core_lib.api.EVENT, "key_down", ...)
end

remote.token_handlers[core_lib.api.ACCEPT] = function(meta, remote_port)
  if remote.remote_port then
    io.stderr:write("host tried to specify a port twice")
  else
    remote.onConnected(remote_port or core_lib.api.default_port)
  end
end

remote.token_handlers[core_lib.api.CLOSED] = function(meta, msg, cx, cy)
  if msg then
    io.stderr:write("connection closed: " .. tostring(msg) .. "\n")
  end
  remote.connected = false
  if type(cx) == "number" and type(cy) == "number" then
    term.setCursor(cx, cy)
  end
end

local function load_obj(name, key, force_call, ...)
  local obj =
    name == "gpu" and term.gpu() or
    name == "window" and term.internal.window()
  if not obj then
    io.stderr:write("proxy requested for unknown object: " .. tostring(name) .. "\n")
    remote.connected = false
    return
  end
  local value = obj[key]
  local the_type = "string"
  if value ~= nil then
    the_type = type(value)
    if the_type == "table" then
      local mt = getmetatable(value)
      if not mt.__call then
        io.stderr:write("proxy requested uncallable table: " .. tostring(name) .. "\n")
        remote.connected = false
        return
      end
      the_type = "function"
    elseif the_type == "thread" then
      io.stderr:write("proxy requested a thread: " .. tostring(name) .. "\n")
      remote.connected = false
      return
    end
  end

  local storage = false
  if the_type ~= "function" or remote.cachers[name][key] then
    storage = true
  elseif the_type == "function" then
    if key:sub(1, 3) == "get" then
      storage = false -- call each time
    end
  end

  if the_type == "function" then
    if force_call or storage then
      value = table.pack(value(...))
    end
  else
    value = table.pack(value)
  end

  return the_type, storage, value
end

remote.token_handlers[core_lib.api.PROXY] = function(meta, name, key, ...)
  local the_type, storage, value = load_obj(name, key, true, ...)
  if not the_type then
    return true
  end
  remote.send(core_lib.api.PROXY, name, key, table.unpack(value, 1, value.n))
end

remote.token_handlers[core_lib.api.PROXY_META] = function(meta, name, key)
  remote.keepalive_update(5)
  local the_type, storage, value = load_obj(name, key)
  if not the_type then
    return true
  end

  local args = table.pack(core_lib.api.PROXY_META, name, key, the_type, storage)
  if storage then -- we have an initial value
    for i=1,value.n do
      args[args.n+i] = value[i]
    end
    args.n = args.n + value.n
  end

  remote.send(table.unpack(args, 1, args.n))
  return true
end

remote.pickSingleHost()
remote.pickLocalPort()

if options.l then -- list only
  os.exit()
end

remote.connect(cmd)

-- main event loop which processes all events, or sleeps if there is nothing to do
while remote.running do

  if remote.remote_port and not remote.connected then
    remote.onDisconnected()
    remote.running = false
  else
    remote.handleNextEvent()
  end
end

remote.closeLocalPort()
