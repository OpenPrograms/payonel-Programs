local shell = require("shell")
local psh = require("psh")
local client = require("psh.client")
local socket = require("psh.socket")

local args, options = shell.parse(...)

options.l = options.l or options.list
options.f = not options.l and (options.f or options.first)
options.h = options.h or options.help

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

local function search()
  print("Searching for available hosts [control+c to stop search]")
  local winner

  local collector = socket.broadcast(port)
  while true do
    local candidate = collector:accept()
    if not candidate then
      break -- interrupted
    end
    local valid = true
    local remote_address = candidate:remote_address()
    io.write(remote_address)
    if address then
      if remote_address:find(address) ~= 1 then
        io.write(" [skipped]")
        valid = false
      end
    end
    print()
    if valid then
      winner = candidate
      if options.f then
        break
      end
    end
    candidate:close()
  end
  collector:close()

  if options.l or not winner then
    if not winner then
      io.stderr:write("no hosts responded\n")
      os.exit(1)
    end
    os.exit(0)
  end

  return winner
end

local remote_socket
if not options.l and not options.f then
  remote_socket = socket.connect(address, port)
else
  remote_socket = search()
end

if not remote_socket then
  os.exit(1)
end

address = remote_socket:remote_address()
if remote_socket:wait() then
  local ok, why = pcall(client.run, remote_socket, command, options)
  if not ok then
    require("tty").window.cursor = nil
    io.stderr:write("psh client crashed: ", why, "\n")
  end
  remote_socket:close()
  if not command then
    print(string.format("Connection to [%s] closed", address))
  end
else
  print("connected aborted")
end
