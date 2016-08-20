local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local process = require("process")
local core_lib = require("psh")
local term = require("term") -- to create a window and inject proxies

local m = component.modem
assert(m)

local lib = {}

function lib.pipeIt(host, command)
  return
    string.format("/usr/bin/psh/psh-reader.lua" .. " %s %i | ", host.remote_id, host.remote_port) ..
    command ..
    string.format(" | " .. "/usr/bin/psh/psh-writer.lua" .. " %s %i", host.remote_id, host.remote_port)
end

function lib.new(host, hostArgs)
  -- we have not yet sent the ACCEPT back to th user
  host.port = hostArgs.port
  host.remote_id = hostArgs.remote_id
  host.remote_port = hostArgs.remote_port

  local command = hostArgs.command or ""
  if command == "" then
    command = os.getenv("SHELL")
  end
  host.command = command

  host.send = function(...) return m.send(host.remote_id, host.remote_port, ...) end
  -- TODO build remote proxies for gpu (and screen and keyboard?)
  host.output = function(...) return host.send(core_lib.api.OUTPUT, ...) end

  function host.applicable(meta)
    if not host.tick_id then
      core_lib.log.debug(host.lanel, "dead host got message")
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

  -- proc is the thread proc of this host
  function host.proc()
    core_lib.log.debug(host.label, "proc started")
    local data = process.info().data

    -- we are now in our process!
    -- finally, tell the client we are ready for events
    m.send(host.remote_id, host.remote_port, core_lib.api.ACCEPT)

    -- create custom term window
    local host_window = term.internal.open()

    -- event.pull until we have proxies?

    -- TODO set proxies
    --window.gpu = gpu_proxy
    host_window.gpu = term.gpu()
    --window.screen = screen_proxy
    host_window.screen = term.screen()
    --window.keyboard = kb_proxy
    host_window.keyboard = term.keyboard()

    -- TODO set viewport to dimensions of proxy
    local viewport = table.pack(term.getViewport())
    data.window = host_window -- this must be done before term.set (else we need the window defined)
    term.setViewport(table.unpack(viewport))

    return shell.execute(host.command)
  end

  -- resume is called every event tick
  function host.resume()
    -- we may have died (or been killed?) since the last resume
    if not host.thread then -- race condition?
      core_lib.log.debug(host.label, "potential race condition, host resumed after stop")
      return
    end

    if coroutine.status(host.thread) == "dead" then
      core_lib.log.debug(host.label, "potential race condition, host resumed after thread dead")
      host.stop()
      return
    end

    -- intercept all future computer.pullSignals (it should actual yield_all)
    -- resume thread
    local ok, reason = coroutine.resume(host.thread)
    if not ok then
      core_lib.log.debug(host.label, "thread crashed: " .. tostring(reason))
    end

    if coroutine.status(host.thread) == "dead" then
      core_lib.log.debug(host.label, "host closing")
      host.stop()
      return
    end

    return true
  end

  function host.vstart()
    if host.thread then
      return false, "host is already started"
    end
    -- create a coroutine that runs on event ticks
    -- uses event.current_signal to simulate event.pulls
    -- but intercepts computer.pullSignal to use a pco yield_all

    -- the command has to be parsed, and process.load does not parse
    host.thread = coroutine.create(host.proc)
  end

  function host.vstop()
    if not host.thread then
      return false, "host is not started"
    end
    host.thread = nil
    m.send(host.remote_id, host.remote_port, core_lib.api.CLOSED)
  end

  host.tokens[core_lib.api.KEEPALIVE] = function(meta, ...)
    m.send(host.remote_id, host.remote_port, core_lib.api.KEEPALIVE, 10)
    return true
  end

  return host
end

return lib
