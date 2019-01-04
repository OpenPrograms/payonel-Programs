local term = require("term")
local daemon = require("psh.daemon")
local psh = require("psh")

local vtcolors =
{
  black = 30,
  red = 31,
  green = 32,
  yellow = 33,
  blue = 34,
  magenta = 35,
  cyan = 36,
  white = 37
}

local function mkcolor(color)
  if io.stdout.tty and term.isAvailable() then
    return string.format("\27[%dm", color)
  else
    return ""
  end
end

local function serviceStatusPrint(startColor, msg, callback, statusMsgOk, statusMsgFail, ...)
  local spacem = '  '

  io.write(spacem)
  io.write(mkcolor(startColor))
  io.write('*')
  io.write(mkcolor(vtcolors.white))
  io.write(spacem)

  io.write(msg)

  local bCallbackResult = callback
  local additionalMessages = {}
  if type(callback) == "boolean" then
    bCallbackResult = callback
  elseif callback then
    local result = table.pack(callback(...))
    bCallbackResult = table.remove(result, 1)
    additionalMessages = result
  end

  if bCallbackResult and not statusMsgOk then
    print()
    return
  end

  if not bCallbackResult and not statusMsgFail then
    print()
    return
  end

  local statusColor = mkcolor(bCallbackResult and vtcolors.green or vtcolors.red)
  local statusMsg   = bCallbackResult and statusMsgOk or statusMsgFail

  local startMsgLen = spacem:len() * 2 + 1 + msg:len()

  local openm = '[' .. spacem
  local closem = spacem .. '] '
  local slen = openm:len() + statusMsg:len() + closem:len()

  local screenWidth = io.stdout.tty and term.isAvailable() and term.getViewport() or 0
  local numSpaces = math.max(1, screenWidth - startMsgLen - slen)
  io.write(string.rep(' ', numSpaces))

  io.write(mkcolor(vtcolors.blue))
  io.write(openm)
  io.write(statusColor)
  io.write(statusMsg)
  io.write(mkcolor(vtcolors.blue))
  io.write(closem)
  io.write(mkcolor(vtcolors.white))
  print()

  -- if additional messages were returned by the callback
  for _,m in ipairs(additionalMessages) do
    serviceStatusPrint(vtcolors.red, m, true)
  end
end

local function checkDaemon()
  return daemon.status() == "running"
end

--luacheck: globals status
function status()
  serviceStatusPrint(vtcolors.green, "pshd", checkDaemon, "started", "stopped")
end

--luacheck: globals start
function start()
  if checkDaemon() then
    serviceStatusPrint(vtcolors.yellow, "WARNING: pshd has already been started")
  else
    serviceStatusPrint(vtcolors.green, "Starting pshd ...", daemon.start, "ok", "failed", psh.port)
  end
end

--luacheck: globals stop
function stop()
  if not checkDaemon() then
    serviceStatusPrint(vtcolors.yellow, "WARNING: pshd is already stopped")
  else
    serviceStatusPrint(vtcolors.green, "Stopping pshd ...", daemon.stop, "ok", "failed")
  end
end
