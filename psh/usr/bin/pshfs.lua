local shell = require("shell")
local psh = require("psh")
local fs = require("filesystem")
local client = require("psh.client")
local socket = require("psh.socket")

local args, options = shell.parse(...)

options.l = options.l or options.list
options.f = not options.l and (options.f or options.first)
options.h = options.h or options.help

local remote_arg = table.remove(args, 1) or ""
local local_path = table.remove(args, 1)
local timeout = options.timeout and tonumber(options.timeout) or not options.timeout and math.huge
local port = options.port and tonumber(options.port) or not options.port and psh.port

local address, remote_path = remote_arg:match("^([^:]-):(.-)$")

if address == "" and (not options.h and not options.f and not options.l) then
  io.stderr:write("remote modem address is required unless using --first or --list\n")
  options.h = true
end

if remote_path == "" then
  remote_path = "/home"
end

if not local_path then
  local_path = "./" .. remote_path
end

local_path = shell.resolve(local_path)

if fs.exists(local_path) then
  io.stderr:write(string.format("cannot mount to [%s] because it exists", local_path))
  os.exit(1)
end

if not timeout then
  options.h = true
  io.stderr:write("timeout must be a number\n")
end

if not port then
  options.h = true
  io.stderr:write("port must be a number")
end

if options.f and options.l then
  options.h = true
  io.stderr:write("options --first and --list are mutually exclusive")
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
  address is can be partial, and empty string, or omitted if
    1. -f (--first) is specified, in which case the first available matching host is used
    2. -l (--list) is given, which overrides --first (if given), and no connection is made
cmd:
  The command to run on the remote host. `cmd` can only be specified if an address is also given.
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

local remote_fs_proxy = setmetatable({
  address = string.format("%s:%s", address, remote_path),
  isReadOnly = function() return true end,
  getLabel = function() return "no-label" end,
  list = function() return {} end,
  isDirectory = function(path) return false end,
  exists = function(path) return false end,
  open = function(path, mode) return false, "not impl" end,
}, { __index = function(a, b)
  log(tostring(a), tostring(b))
end})

local ok, why = fs.mount(remote_fs_proxy, local_path)
if not ok then
  local msg = string.format("failed to mount %s at %s: %s\n", remote_arg, local_path, why)
  io.stderr:write(msg)
  os.exit(1)
end

--local ok, why = pcall(client.run, remote_socket, command, options)
--if not ok then
--  io.stderr:write("pshfs mount crashed: ", why, "\n")
--  fs.umount(local_path)
--end

remote_socket:close()

