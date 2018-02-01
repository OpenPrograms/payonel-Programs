local component = require("component")
local shell = require("shell")
local core_lib = require("psh")
local thread = require("thread")
local tty_adapter = require("psh.tty_adapter")

local m = assert(component.modem)

local lib = {}

function lib.new(host, hostArgs)
  -- we have not yet sent the ACCEPT back to th user
  host.port = hostArgs.port
  host.remote_id = hostArgs.remote_id
  host.remote_port = hostArgs.remote_port
  host.proxies = {}
  host.events = {}
  host.timeout = 5
  host.command = hostArgs.command == "" and os.getenv("SHELL") or hostArgs.command

  host.send = function(...) return core_lib.send(host.remote_id, host.remote_port, ...) end
  
  function host.applicable(meta)
    if not host.thread or host.thread:status() == "dead" then
      core_lib.log.error(host.label, "dead host got message")
      return false
    elseif meta.remote_id ~= host.remote_id then
      core_lib.log.debug(host.label, "ignoring msg, wrong id")
      return false
    elseif meta.port ~= host.port then
      core_lib.log.debug(host.label, "ignoring msg, wrong local port")
      return false
    end

    return true
  end

  host.stream =
  {
    read = function(...)
      cprint("!!read!!", ...)
    end,
    write = function(...)
      cprint("!!write!!", ...)
    end,
    close = function(...)
      cprint("!!close!!", ...)
    end,
    size = function(...)
      cprint("!!size!!", ...)
    end
  }

  function host.proc(...)
    -- create remote proxies
    local vgpu = tty_adapter.create_vgpu()
    tty_adapter.open_window(host.stream)

    host.send(core_lib.api.ACCEPT, host.port)
    core_lib.log.info("host command starting", host.command)
    xpcall(shell.execute, function(crash)
      host.send(core_lib.api.CLOSE, "command aborted: " .. tostring(crash))
    end, host.command)
    host.send(core_lib.api.CLOSE)
  end

  function host.vstart()
    if host.thread then
      return false, "host is already started"
    end

    host.thread = thread.create(host.proc)
  end

  function host.vstop()
    core_lib.log.debug("host.vstop")
    if not host.thread then
      return false, "host is not started"
    end
    if host.thread:status() == "dead" then
      return false, "host is already dead"
    end
    host.thread:kill()
    host.send(core_lib.api.CLOSE, host.close_msg, x, y)
  end

  host.tokens[core_lib.api.KEEPALIVE] = function(meta, ...)
    host.send(core_lib.api.KEEPALIVE)
    return true
  end

  return host
end

return lib
