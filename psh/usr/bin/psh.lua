local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local computer = require("computer")
local core_lib = require("psh")
local client = require("psh.client")

local args, options = shell.parse(...)
local address = args[1]
local cmd = args[2]
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

options.l = options.l or options.list
options.f = not options.l and (options.f or options.force)
options.v = options.v or options.verbose
options.h = options.h or options.help

local ec = 0

address = address or ""

if address == "" and (not options.h and not options.f and not options.l) then
  options.h = true
  io.stderr:write("ADDRESS is required unless using --first or --list\n")
  ec = 1
end

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
local backpack, forepack = {term.gpu().getBackground()}, {term.gpu().getForeground()}

local remote = client.new()

local function create_event_forward(key)
  remote.handlers[key] = function(...)
    remote.send(core_lib.api.EVENT, key, ...)
  end
end

create_event_forward("key_down")
create_event_forward("key_up")
create_event_forward("touch")
create_event_forward("drag")
create_event_forward("clipboard")
create_event_forward("interrupted")

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

remote.handlers.modem_message[core_lib.api.CLOSED] = function(meta, msg, cx, cy)
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

function remote.proxy_handler(sync, name, key, ...)
  local the_type, storage, value = load_obj(name, key, true, ...)
  remote.keepalive_update(5)
  if sync and the_type then
    remote.send(core_lib.api.PROXY_RESULT, name, key, table.unpack(value, 1, value.n))
  end
end

remote.handlers.modem_message[core_lib.api.PROXY_ASYNC] = function(meta, name, key, ...)
  remote.proxy_handler(false, name, key, ...)
  return true
end

remote.handlers.modem_message[core_lib.api.PROXY_SYNC] = function(meta, name, key, ...)
  remote.proxy_handler(true, name, key, ...)
  return true
end

remote.handlers.modem_message[core_lib.api.PROXY_META] = function(meta, name, key)
  remote.keepalive_update(5)
  local the_type, storage, value = load_obj(name, key)
  if not the_type then
    return true
  end

  local args = table.pack(core_lib.api.PROXY_META_RESULT, name, key, the_type, storage)
  if storage then -- we have an initial value
    for i=1,value.n do
      args[args.n+i] = value[i]
    end
    args.n = args.n + value.n
  end

  remote.send(table.unpack(args, 1, args.n))
  return true
end

remote.pickSingleHost(address, options)

if options.l then -- list only
  os.exit()
end

remote.pickLocalPort()
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

if backpack then
  term.gpu().setBackground(table.unpack(backpack))
end
if forepack then
  term.gpu().setForeground(table.unpack(forepack))
end
