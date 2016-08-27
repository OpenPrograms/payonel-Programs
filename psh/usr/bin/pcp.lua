local component = require("component")
local shell = require("shell")
local ser = require("serialization")
local core_lib = require("psh")
local client = require("psh.client")

local args, options = shell.parse(...)
local local_path = args[1]
local remote_arg = args[2] or ""
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

options.l = options.l or options.list
options.r = options.r or options.recursive
options.f = not options.l and (options.f or options.force)
options.v = options.v or options.verbose
options.h = options.h or options.help

local remote_address, remote_path = remote_arg:match("^([^:]*):.*$")

local ec = 0

if not remote_arg:find(":") and (not options.h and not options.l) then
  options.h = true
  io.stderr:write("The remote address field must have a ':' unless using --list\n")
  ec = 1
elseif remote_address == "" and (not options.h and not options.f and not options.l) then
  options.h = true
  io.stderr:write("At least one prefix character of the remote address is required unless using --first or --list\n")
  ec = 1
elseif options.port and not tonumber(options.port) then
  options.h = true
  io.stderr:write("Invalid port: " .. options.port .. "\n")
  ec = 1
end

if options.h then
  print([[Usage: pcp [OPTIONS] LOCAL_PATH [remote address]:[remote path]
  OPTIONS
  -l  --list        no files are copied, available hosts are listed
  -f  --first       connect to the first available host
  -r  --recursive   copy directory recursively
  -v  --verbose     be verbose during the operations
  -h  --help        print this help
      --port=N      Use a specified port instead of the default
  LOCAL_PATH        local file or directory (if -r) to copy
  [remote address]  Remote address prefix (can be empty if using --first)
  [remote path]     Optional, defaults to /home. Path is relative from /home, unless starting with /

  Example:
    pcp -r my_dir 5bbd:
    pcp -r /tmp/. 5bbd:/tmp/]])
  os.exit(ec)
end

if not component.isAvailable("modem") then
  io.stderr:write("psh requires a modem [a network card, wireless or wired]\n")
  return 1
end

local m = component.modem

local remote = client.new()

remote.pickSingleHost(address, options)

if options.l then -- list only
  os.exit()
end

remote.pickLocalPort()
remote.closeLocalPort()

