local component = require("component")
local event = require("event")
local process = require("process")
local computer = require("computer")

local m = component.modem
assert(m)

local core_lib = require("psh")
local host_lib = require("psh.host")

local lib = {}

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
  end

  function daemon.vstop()
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
        local hostArgs =
        {
          remote_id = meta.remote_id,
          remote_port = remote_port,
          port = meta.port,
          command = p3,
        }

        local host = host_lib.new(core_lib.new('psh-host:' .. meta.remote_id), hostArgs)
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
