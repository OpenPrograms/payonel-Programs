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

local function serviceStatusPrint(starColor, msg, callback, statusMsgOk, statusMsgFail)
  local spacem = '  '

  io.write(spacem)
  setColor(starColor)
  io.write('*')
  revertColor()
  io.write(spacem)

  io.write(msg)

  local bCallbackResult = true
  local additionalMessages = {}
  if callback ~= nil then
    if type(callback) == "boolean" then
      bCallbackResult = callback
    else
      local result = table.pack(callback())
      bCallbackResult = table.remove(result, 1)
      additionalMessages = result
    end
  end

  if bCallbackResult and not statusMsgOk then
    return
  end

  if not bCallbackResult and not statusMsgFail then
    return
  end

  local statusColor = bCallbackResult and 0x00FF00 or 0xFF0000
  local statusMsg   = bCallbackResult and statusMsgOk or statusMsgFail

  local startMsgLen = spacem:len() * 2 + 1 + msg:len()

  local openm = '[' .. spacem
  local closem = spacem .. '] '
  local numSpaces = 1
  local slen = openm:len() + statusMsg:len() + closem:len()

  numSpaces = math.max(1, screenWidth - startMsgLen - slen)
  io.write(string.rep(' ', numSpaces))

  setColor(0x0000FF)
  io.write(openm)
  setColor(statusColor)
  io.write(statusMsg)
  setColor(0x0000FF)
  io.write(closem)
  revertColor()

  -- if additional messages were returned by the callback
  for i,m in ipairs(additionalMessages) do
    serviceStatusPrint(0xFF0000, m)
  end
end

local function usage(msg)
  serviceStatusPrint(0xFF0000, msg)
  io.write('\n')
  serviceStatusPrint(0xFFFF00, "Usage: pshd [start|stop|status]")
  os.exit()
end

local command = table.remove(args, 1)
local bInteractiveMode = false

if not command then -- run in interactive mode
  bInteractiveMode = true
elseif #args > 0 then
  usage("too many arguments")
elseif command == "status" then
  serviceStatusPrint(0x00FF00, "pshd", psh_lib.pshd_running, "started", "stopped")
elseif command == "start" then
  if psh_lib.pshd_running then
    serviceStatusPrint(0xFFFF00, "WARNING: pshd has already been started")
  else
    serviceStatusPrint(0x00FF00, "Starting pshd ...", psh_lib.start, "ok", "failed")
  end
elseif command == "stop" then
  if not psh_lib.pshd_running then
    serviceStatusPrint(0xFFFF00, "WARNING: pshd is already stopped")
  else
    serviceStatusPrint(0x00FF00, "Stopping pshd ...", psh_lib.stop, "ok", "failed")
  end
else
  usage("Unknown command parameter: " .. command)
end

if bInteractiveMode then
  usage("Interactive mode is not yet implemented")
end
