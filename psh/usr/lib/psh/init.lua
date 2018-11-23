local component = require("component")
local event = require("event")
local ser = require("serialization")
local tty = require("tty")

local init =
{
  daemon = require("psh.daemon"),
}

function init.checkDaemon()
  return init.daemon.status() == "running"
end

function init.startDaemon()
  return init.daemon.start()
end

function init.stopDaemon()
  return init.daemon.stop()
end

return init
