local shell = require("shell")
local psh = require("psh")
local client = require("psh.client")
local socket = require("psh.socket")

local args, options = shell.parse(...)

options.l = options.l or options.list
options.f = options.f or options.first
options.h = options.h or options.help
options.q = options.q or options.quiet

local address = table.remove(args, 1) or ""
local command = table.remove(args, 1)
local timeout = options.timeout and tonumber(options.timeout) or not options.timeout and math.huge
local port = options.port and tonumber(options.port) or not options.port and psh.port

if address == "" and (not options.h and not options.f and not options.l) then
  io.stderr:write("remote modem address is required unless using --first or --list\n")
  options.h = true
end

if not timeout then
  options.h = true
  io.stderr:write("timeout must be a number\n")
end

if not port then
  options.h = true
  io.stderr:write("port must be a number")
end

if options.h then
print("Usage: psh [options] [address [cmd]]")
print([[OPTIONS
  -f  --first   connect to the first remote host available
  -l  --list    list available hosts, do not connect
  -h  --help    print this help
  --port=N      use port N and not 22 (default)
  --timeout=s   attempt connections for s seconds (default math.huge)
address:
  Any number of starting characters of a remote host computer address.
  address is can be partial, and empty string, or omitted if --first or --list
cmd:
  The command to run on the remote host must come after address
  It is possible to use an empty string for address with -f: `psh -f '' cmd`
  If no command is given, the remote command run is the shell prompt]])
  os.exit(1)
end

local remote_socket
if not options.l and not options.f then
  remote_socket = socket.connect(address, port)
else
  remote_socket = client.search(port, address, options)
end

if not remote_socket or not remote_socket:wait() then
  print("Connection aborted")
  os.exit(1)
end

address = remote_socket:remote_address()
local ok, why = pcall(client.run, remote_socket, command, options)
if not ok then
  require("tty").window.cursor = nil
  io.stderr:write("psh client crashed: ", why, "\n")
end
remote_socket:close()
if not command then
  print(string.format("Connection to [%s] closed", address))
end
