local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local process = require("process")
local core_lib = require("psh")
local pipes = require("pipes")
local computer = require("computer")
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

  function host.proc_init(...)
    core_lib.log.debug(host.label, "proc_init started")

    local data = process.info().data

    -- we are now in our process!
    -- finally, tell the client we are ready for events
    core_lib.log.debug("sending accept: " .. tostring(host.remote_id) ..",".. tostring(host.remote_port) ..",".. core_lib.api.ACCEPT)
    m.send(host.remote_id, host.remote_port, core_lib.api.ACCEPT, host.port)

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

    core_lib.log.debug(host.label, "proc_init done")

    return ...
  end

  -- proc is the thread proc of this host
  function host.proc()
    core_lib.log.debug(host.label, "proc started")
    return shell.execute(host.command)
  end

  function host.pull(timeout)
    -- this is the fake computer.pullSignal during host process
    -- timeout is the expected sleep time
    -- and we should return an actual unpacked event signal

    -- wake us back up at least in timeout seconds
    event.timer(timeout, host.resume)

    core_lib.log.debug(host.label, "pull yield all")
    local signal = table.pack(host.pco.yield_all())
    core_lib.log.debug(host.label, "pull resumed")

    return table.unpack(signal, 1, signal.n)
  end

  function host.pco_status()
    if not host.pco or #host.pco.stack == 0 then
      return "dead"
    end
    return host.pco.status(host.pco.top())
  end

  -- resume is called as event tick
  function host.resume()
    -- we may have died (or been killed?) since the last resume
    if not host.pco then -- race condition?
      core_lib.log.debug(host.label, "potential race condition, host resumed after stop")
      return
    end

    if host.pco_status() == "dead" then
      core_lib.log.debug(host.label, "potential race condition, host resumed after thread dead")
      host.stop()
      return
    end

    -- sanity check before we lose computer.pullSignal and the current coroutine lib
    local sig = event.current_signal
    assert(type(sig) == "table" and sig.n, "event signal missing, cannot resume host")

    -- intercept all future computer.pullSignals (it should actually yield_all)
    local _pull = computer.pullSignal
    core_lib.log.debug(host.label, "resume pre resume_all")

    computer.pullSignal = host.pull
    local pco_ok, proc_fail = host.pco.resume_all(table.unpack(sig, 1, sig.n)) -- should be safe, resume_all pcalls unsafe code
    computer.pullSignal = _pull

    core_lib.log.debug(host.label, "resume post resume_all")

    if host.pco_status() == "dead" or proc_fail then
      core_lib.log.debug(host.label, "host closing")
      host.stop()
      return
    end

    return true
  end

  function host.vstart()
    if host.pco then
      return false, "host is already started"
    end

    -- all we need is a thread
    -- but in order to invoke custom thread coroutines, we need a process
    -- not to worry, pipes.internal.create can create processes
    host.pco = pipes.internal.create(host.proc, host.proc_init, "psh-" .. host.label)

    -- resume thread on next tick (single timer)
    event.timer(0, host.resume)
  end

  function host.vstop()
    if not host.pco then
      return false, "host is not started"
    end
    host.pco = nil
    m.send(host.remote_id, host.remote_port, core_lib.api.CLOSED)
  end

  host.tokens[core_lib.api.KEEPALIVE] = function(meta, ...)
    m.send(host.remote_id, host.remote_port, core_lib.api.KEEPALIVE, 10)
    return true
  end

  return host
end

return lib
