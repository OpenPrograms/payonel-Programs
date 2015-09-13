local component = require("component")
local event = require("event")
local remote = require("psh/remote")
local shell = require("shell")

local m = component.modem
local token_handlers = {}

assert(component and event and remote and m)

local args, ops = shell.parse(...)

local function usage(msg)
  io.stderr:write(msg .. "\nUsage: pshd [start|stop|status]\n")
  os.exit()
end

local command = table.remove(args, 1)
local bInteractiveMode = false

if not command then -- run in interactive mode
  bInteractiveMode = true
elseif #args > 0 then
  usage("too many arguments")
elseif command == "status" then
elseif command == "start" then
elseif command == "stop" then
else
  usage("Unknown command parameter: " .. command)
end
