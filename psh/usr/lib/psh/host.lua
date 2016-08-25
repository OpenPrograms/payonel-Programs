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
  host.proxies = {}
  host.events = {}
  host.timeout = 5

  local command = hostArgs.command or ""
  if command == "" then
    command = os.getenv("SHELL")
  end
  host.command = command

  host.send = function(...) core_lib.log.debug(...) return m.send(host.remote_id, host.remote_port, ...) end
  host.output = function(...) return host.send(core_lib.api.OUTPUT, ...) end

  function host.applicable(meta)
    if not host.pco then
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

  function host.set_meta(name, key, the_type, storage, ...)
    local initial_value = ...
    -- nil: call and return empty
    -- false: call and do not cache
    -- true: call and cache
    local meta =
    {
      key=key,
      type=the_type,
      storage=storage,
      value=table.pack(...),
      is_cached=storage and select('#', ...) > 0,
    }

    local proxy, mt = host.proxy(name) -- creates on first call
    mt.meta[key] = meta
    return meta
  end

  function host.wait(name, key, checker)
    local timeout = computer.uptime() + host.timeout
    checker = checker or function(m) return m end
    local proxy = host.proxy(name)
    while true do
      local meta = getmetatable(proxy).meta[key]
      if checker(meta) then
        return meta
      elseif timeout < computer.uptime() then
        core_lib.log.info(host.label,"timed out waiting for proxy: " .. name .. "." .. key)
        host.close_msg = "Timed out waiting for proxy: " .. name .. "." .. key
        host.stop()
        os.exit(1)
      end
      host.frozen = true -- waiting for rpc
      event.pull(0)
      host.frozen = false -- waiting for rpc
    end
  end

  function host.get_meta(name, key)
    -- send request for meta
    host.send(core_lib.api.PROXY_META, name, key)

    -- keyboard requests shouldn't fire indefinitely
    if name == "window" and key == "keyboard" then
      return host.set_meta(name, key, "string", true, "")
    end

    -- now wait for it
    return host.wait(name, key)
  end

  function host.call(mt, key, ...)
    local meta = mt.meta[key]
    local name = mt.name

    -- first hack, getBackground() remains cached from setBackground
    --if name == "gpu" then
    --  if key == "setBackground" then
    --  end
    --end

--lib.api.PROXY_META = "PROXY_META"
--lib.api.PROXY_META_RESULT = "PROXY_META_RESULT"
--lib.api.PROXY_ASYNC = "PROXY_ASYNC"
--lib.api.PROXY_SYNC = "PROXY_SYNC"
--lib.api.PROXY_RESULT = "PROXY_RESULT"
    host.send(core_lib.api.PROXY_SYNC, mt.name, key, ...)
    -- wait for result
    host.wait(name, key, function(m) return m.is_cached end)
  end

  function host.proxy_index(proxy, key)
    local mt = getmetatable(proxy)
    local meta = mt.meta[key]
    if not meta then
      meta = host.get_meta(mt.name, key)
    end

    local callback = function(...)
      if not meta.is_cached then
        -- send proxy call
        host.call(mt, key, ...)
      end
      -- it may have been cached by a callback, but not via load
      -- restore acurate storage type
      meta.is_cached = meta.storage
      return table.unpack(meta.value, 1, meta.value.n)
    end

    if meta.type == "function" then
      return callback
    else
      return callback()
    end
  end

  function host.proxy(name, base)
    -- there might already be metadata for this proxy object
    local proxy = host.proxies[name]
    local mt = proxy and getmetatable(proxy) or
    {
      name = name,
      meta = {},
      __index = host.proxy_index,
    }
    proxy = base or proxy or {}
    host.proxies[name] = setmetatable(proxy, mt)
    return proxy, mt
  end

  function host.proc_init(...)
    -- we are now in our process!
    -- finally, tell the client we are ready for events
    m.send(host.remote_id, host.remote_port, core_lib.api.ACCEPT, host.port)

    -- create custom term window
    local window = host.proxy("window", term.internal.open())
    window.gpu = host.proxy("gpu")

    process.info().data.window = window
    term.setViewport(window.viewport())

    return ...
  end

  -- proc is the thread proc of this host
  function host.proc()
    return shell.execute(host.command)
  end

  function host.pull(timeout)
    -- in an attempt to optmize host.pull:
    -- we are behaving quite differently in frozen states vs thawed states
    -- if frozen, run until we have a modem_message that is applicable to pshd
    -- else, run until we have any signal
    local signal = nil

    -- special case - we had an event buffered
    -- if the host is frozen, we cannot return signal or they will be lost
    if not host.frozen and next(host.events) then
      signal = table.remove(host.events, 1)
      return table.unpack(signal, 1, signal.n)
    end

    -- this is the fake computer.pullSignal during host process
    -- timeout is the expected sleep time
    -- and we should return an actual unpacked event signal
    local future = computer.uptime() + timeout

    while true do
      -- wake us back up at least in timeout seconds
      event.register(nil, host.resume, timeout)
      signal = table.pack(host.pco.yield_all()) -- what we pass here is given to resume_all
      timeout = math.max(0, future - computer.uptime())

      if signal[1] == "modem_message" then
        local meta, args = core_lib.internal.modem_message_pack(table.unpack(signal, 2, signal.n))
        -- any modem message sent to pshd's port is not applicable to any shell
        if meta.port == core_lib.pshd.port then
          signal = nil
          if host.frozen then
            return -- good news!
          end
        end
      end

      if signal then -- only nil if was modem_message
        -- buffer this signal if it is meaningful
        -- this is the action to take whether we are frozen or not
        if signal.n > 0 then
          core_lib.log.info("buffering event pull",table.unpack(signal,1,signal.n))
          table.insert(host.events, signal)
        end

        -- the rest is only applicable to thawed threads because ONLY pshd modem_messages can thaw a frozen thread
        if not host.frozen then
          local first_signal = table.remove(host.events, 1)
          -- only use first_signal if not null
          -- we want empty signals to be valid to break this loop
          if first_signal then
            signal = first_signal
          end

          if signal.n > 0 then
            core_lib.log.info("unbuffered event",table.unpack(signal, 1, signal.n))
          end
          return table.unpack(signal, 1, signal.n)
        end
      end
    end
  end

  function host.pco_status()
    if not host.pco or #host.pco.stack == 0 then
      return "dead"
    end
    return host.pco.status(host.pco.top())
  end

  function host.can_proxy()
    return host.screen and host.keyboard and host.viewport
  end

  function host.resume(...)
    -- we may have died (or been killed?) since the last resume
    if not host.pco then -- race condition?
      if not host.doneit then
        core_lib.log.debug(host.label, "potential race condition, host resumed after stop")
      end
      host.doneit = true
      return
    end

    if host.pco_status() == "dead" then
      host.close_msg = "Aborted: thread died"
      host.stop()
      return
    end

    -- intercept all future computer.pullSignals (it should actually yield_all)
    local _pull = computer.pullSignal

    computer.pullSignal = host.pull
    host.pco.resume_all(...) -- should be safe, resume_all pcalls unsafe code
    computer.pullSignal = _pull

    if host.pco_status() == "dead" then
      core_lib.log.info(host.label, "host stopping")
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
    host.pco = pipes.internal.create(host.proc, host.proc_init, host.label)

    -- resume thread on next tick (single timer)
    event.timer(0, host.resume)
  end

  function host.vstop()
    if not host.pco then
      return false, "host is not started"
    end
    host.pco = nil
    local window = host.proxies.window
    local x,y = rawget(window, "x"), rawget(window, "y")
    m.send(host.remote_id, host.remote_port, core_lib.api.CLOSED, host.close_msg, x, y)
  end

  host.tokens[core_lib.api.KEEPALIVE] = function(meta, ...)
    m.send(host.remote_id, host.remote_port, core_lib.api.KEEPALIVE, 10)
    return true
  end

  host.tokens[core_lib.api.PROXY_META_RESULT] = function(meta, name, key, type, storage, ...)
    core_lib.log.info(host.label,"proxy meta update", name, key, type, storage, ...)
    host.set_meta(name, key, type, storage, ...)
    return true
  end

  host.tokens[core_lib.api.EVENT] = function(meta, ...)
    core_lib.log.debug(core_lib.api.EVENT,...)
    event.push(...)
    return true
  end

  host.tokens[core_lib.api.PROXY_RESULT] = function(meta, name, key, ...)
    core_lib.log.info(host.label,"proxy result", name, key, ...)
    local proxy, mt = host.proxy(name)
    local meta = mt.meta[key]
    if not meta then
      core_lib.log.debug(host.label,"proxy result made without meta", name, key, ...)
      host.close_msg = "Proxy result missing meta: " .. name .. "." .. key
      host.stop()
      return true
    end

    -- set the value as cached, but don't alter the storage type
    meta.value = table.pack(...)
    meta.is_cached = true
    return true
  end

  return host
end

return lib
