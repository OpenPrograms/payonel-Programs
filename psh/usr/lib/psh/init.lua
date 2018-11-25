local init =
{
  daemon = require("psh.daemon"),
}

function init.checkDaemon()
  return init.daemon.status() == "running"
end

function init.startDaemon()
  return init.daemon.start(1)
end

function init.stopDaemon()
  return init.daemon.stop()
end

return init
