local component = require("component")
local event = require("event")
assert(component and event)

local m = component.modem
local config = require("payo-lib/config")
assert(m and config)

local psh_cfg = config.load("/etc/psh.cfg");
psh_cfg = psh_cfg or {}; -- simplify config checks later on

local lib = {}
lib.pshd_running = false
lib.daemon = {}
lib.daemon.handlers = {}

function lib.start()
  local l = event.listen

  if lib.pshd_running then
    return false, "pshd already running"
  end

  for token,handler in pairs(lib.daemon.handlers) do
    if not l(token, handler) then
      return false, "failed to register pshd daemon handler for " .. tostring(token)
    end
  end

  lib.pshd_running = true
  return m.open(1)
end

function lib.stop()
  local ig = event.ignore

  for token,handler in pairs(lib.daemon.handlers) do
    if not ig(token, handler) then
      return false, "failed to unregister pshd daemon handler for " .. tostring(token)
    end
  end

  lib.pshd_running = false
  return m.close(1)
end

lib.daemon.handlers.modem_message = function(...)
  print("psh_lib.daemon.handlers.modem_message ", ...)
end

return lib
