local shell = require("shell")
local psh = require("psh")
local client = require("psh.client")
local socket = require("psh.socket")
local thread = require("thread")
local event = require("event")

local args, options = shell.parse(...)
local address = table.remove(args, 1)

options.l = options.l or options.list
options.f = not options.l and (options.f or options.first)
options.v = options.v or options.verbose
options.h = options.h or options.help

address = address or ""

if address == "" and (not options.h and not options.f and not options.l) then
  options.h = true
  io.stderr:write("ADDRESS is required unless using --first or --list\n")
end

local port = options.port and tonumber(options.port) or psh.port
if not port then
  options.h = true
  io.stderr:write("port must be a number")
end

if options.h then
print("Usage: psh OPTIONS [ADDRESS [CMD]]")
print([[OPTIONS
  -f  --first   connect to the first remote host available
  -v  --verbose verbose output
  -l  --list    list available hosts, do not connect
  -h  --help    print this help
  --port=N      use port N and not 22 (default)
ADDRESS
  Any number of starting characters of a remote host computer address.
  Address is optional if
    1. -f (--first) is specified, in which case the first available matching host is used
    2. -l (--list) is given, which overrides --first (if given), and no connection is made
CMD
  The command to run on the remote host. CMD can only be specified if an address is also given.
  It is possible to use an empty string for ADDRESS with -f: `psh -f '' cmd`
  If no command is given, the remote command run is the shell prompt]])
  os.exit(1)
end

local function search(address, options)
  if not options.l and not options.f then
    return address
  end
  
  if options.f then
    address = "2553a215-59c3-629a-939c-f4efd0050984"
  end
  return address
end

local remote_address = search(address, options)

if options.l or not remote_address then -- list only
  os.exit(0)
end

local s = socket.connect(remote_address, port)

if not s then
  io.stderr:write("failed to connect to remote: ", remote_address, ":", remote_port, "\n")
  os.exit(1)
end

local t = thread.create(function()
  event.pull("interrupted")
  s:close()
end)

client.run(s, args, options)

t:kill()
s:close()
