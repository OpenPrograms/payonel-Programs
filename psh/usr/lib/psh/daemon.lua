local component = require("component")
local event = require("event")
local process = require("process")
local computer = require("computer")

local m = component.modem
assert(m)

local core_lib = require("psh")
local host_lib = require("psh.host")

local lib = {}
lib.daemons = {}

local function _pull(...)
  local signal = table.pack(lib.old_pull(...))
  local subs = {}
  for d in pairs(lib.daemons) do
    for h in pairs(d.hosts) do
      table.insert(subs, {d, h})
    end
  end
  for _,p in ipairs(subs) do
    if not p[2].resume(signal) then -- resume fails if host should be free
      p[1].hosts[p[2]] = nil
    end
  end
  return table.unpack(signal)
end

local function check(msg, ok, reason)
  if not ok then
    core_lib.log.error("failed to " .. msg, tostring(reason))
    return false
  end
  return true
end

function lib.new(daemon)
  daemon.hosts = setmetatable({}, {__mode="v"})

  function daemon.applicable(meta)
    return true -- pshd applies to all clients
  end

  function daemon.vstart()
    --intercept computer.pullSignal
    if not lib.old_pull then
      lib.old_pull = computer.pullSignal
      computer.pullSignal = _pull
    end
    lib.daemons[daemon] = true
  end

  function daemon.vstop()
    --reset computer.pullSignal
    lib.daemons[daemon] = nil
    if not next(lib.daemons) and lib.old_pull then
      computer.pullSignal = lib.old_pull
      lib.old_pull = nil
    end
  end

  daemon.tokens[core_lib.api.SEARCH] = function (meta, p1, p2)
    local remote_port = p2 and tonumber(p2) or nil
    if remote_port then

      local wants_us = true
      p1 = (p1 and p1:len() > 0 and p1) or nil
      if p1 then
        local id = meta.local_id:find(p1)
        wants_us = id == 1
      end

      if wants_us then
        core_lib.log.debug("available, responding to " .. meta.remote_id .. " on " .. tostring(remote_port))
        m.send(meta.remote_id, remote_port, core_lib.api.AVAILABLE)
        return true -- consume token
      else
        core_lib.log.debug("ignoring search: does not want us")
      end
    else
      core_lib.log.debug("search did not send remote port")
    end
  end

  daemon.tokens[core_lib.api.CONNECT] = function (meta, p1, p2, p3)
    local remote_port = p2 and tonumber(p2) or nil

    if remote_port then
      local wants_us = meta.local_id == p1

      if wants_us then
        core_lib.log.debug("sending accept: " .. tostring(meta.remote_id)
          ..",".. tostring(remote_port) ..",".. core_lib.api.ACCEPT)

        local hostArgs =
        {
          remote_id = meta.remote_id,
          remote_port = remote_port,
          port = meta.port,
          command = p3,
        }

        local host = host_lib.new(core_lib.new('psh-host:' .. meta.remote_id), hostArgs)
        daemon.hosts[host] = true

        host.start() -- adds host to modem listeners, and host install its proc into the event system

        return true -- consume token
      else
        core_lib.log.debug("ignoring: does not want us")
      end
    end
  end

  return daemon
end

return lib
