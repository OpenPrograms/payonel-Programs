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

return lib
