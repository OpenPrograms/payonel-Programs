local component = require("component")
local event = require("event")
local lib = require("psh")
local shell = require("shell")
local term = require("term")
assert(component and event and lib)

local m = component.modem
assert(m)

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

  local screenWidth = term.isAvailable() and term.getViewport() or 0
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

function status()
  serviceStatusPrint(0x00FF00, "pshd", lib.checkDaemon, "started", "stopped")
end

function start()
  if lib.checkDaemon() then
    serviceStatusPrint(0xFFFF00, "WARNING: pshd has already been started")
  else
    serviceStatusPrint(0x00FF00, "Starting pshd ...", lib.pshd.start, "ok", "failed")
  end
end

function stop()
  if not lib.checkDaemon() then
    serviceStatusPrint(0xFFFF00, "WARNING: pshd is already stopped")
  else
    serviceStatusPrint(0x00FF00, "Stopping pshd ...", lib.pshd.stop, "ok", "failed")
  end
end
