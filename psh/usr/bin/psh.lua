local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local tty = require("tty")
local computer = require("computer")
local core_lib = require("psh")
local client_lib = require("psh.client")

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  os.exit(1)
end

local args, options = shell.parse(...)
local address = args[1]
local cmd = args[2]
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

options.l = options.l or options.list
options.f = not options.l and (options.f or options.first)
options.v = options.v or options.verbose
options.h = options.h or options.help

local ec = 0

address = address or ""

if address == "" and (not options.h and not options.f and not options.l) then
  options.h = true
  io.stderr:write("ADDRESS is required unless using --first or --list\n")
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
    1. -f (--first) is specified, in which case the first available matching host is used
    2. -l (--list) is given, which overrides --first (if given), and no connection is made
CMD
  The command to run on the remote host. CMD can only be specified if an address is also given.
  It is possible to use an empty string for ADDRESS with -f: `psh -f '' cmd`
  If no command is given, the remote command run is the shell prompt]])
  os.exit(1)
end

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  os.exit(1)
end

local m = component.modem

local client = client_lib.new()
local remote_id
core_lib.config.LOGLEVEL = 3

remote_id = client.search(address, options)

if options.l then -- list only
  os.exit()
end

client.open(remote_id, cmd)

-- HACK to stop debugging
client.handlers.interrupted = client.close

-- main event loop which processes all events, or sleeps if there is nothing to do
while client.isOpen() do
  client.handleNextEvent()
end

client.close()

-- reset screen color?
