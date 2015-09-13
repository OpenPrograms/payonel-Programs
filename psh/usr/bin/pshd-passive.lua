local component = require("component")
local event = require("event")
local psh_lib = require("psh")
local shell = require("shell")
assert(component and event and psh_lib)

local m = component.modem
assert(m)

local token_handlers = {}
local args, ops = shell.parse(...)

local gpu = component.gpu
local prevColor = gpu and gpu.getForeground() or nil
local setColor = gpu and function(c)
  io.stdout:flush()
  gpu.setForeground(c)
end or function() end

local function revertColor() 
  if gpu and prevColor then
    io.stdout:flush()
    gpu.setForeground(prevColor)
  end
end

local screenWidth = gpu and gpu.getResolution() or 0

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
  local status = psh_lib.pshd_running and "started" or "stopped"
  local scolor = psh_lib.pshd_running and 0x00FF00 or 0xFF0000
  local spacem = '  '
  local openm = '[' .. spacem
  local closem = spacem .. '] '
  io.write(spacem .. 'pshd')
  local numSpaces = 1
  local slen = openm:len() + closem:len() + status:len()
  numSpaces = math.max(1, screenWidth - spacem:len() - 4 - slen)
  io.write(string.rep(' ', numSpaces))
  setColor(0x0000FF)
  io.write(openm)
  setColor(scolor)
  io.write(status)
  setColor(0x0000FF)
  io.write(closem)
  revertColor()
elseif command == "start" then
elseif command == "stop" then
else
  usage("Unknown command parameter: " .. command)
end
