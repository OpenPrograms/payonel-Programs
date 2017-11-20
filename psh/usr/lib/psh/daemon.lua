local component = require("component")
local event = require("event")
local process = require("process")
local computer = require("computer")

local m = component.modem
assert(m)

local core_lib = require("psh")
local host_lib = require("psh.host")

local lib = {}

function lib.new(daemon)
  daemon.hosts = setmetatable({}, {__mode="v"})

  function daemon.applicable(meta)
    return true -- pshd applies to all clients
  end

  function daemon.vstart()
    core_lib.reload_config()
    core_lib.config.LOGLEVEL = 5
  end

  function daemon.vstop()
  end

  daemon.tokens[core_lib.api.SEARCH] = function (meta, p1)
    local remote_port = p1 and tonumber(p1) or nil
    if remote_port and meta.remote_id ~= computer.address() then
      core_lib.log.debug("available, responding to " .. meta.remote_id .. " on " .. tostring(remote_port))
      core_lib.send(meta.remote_id, remote_port, core_lib.api.AVAILABLE)
      return true -- consume token
    else
      core_lib.log.info("search did not send remote port")
    end
  end

  daemon.tokens[core_lib.api.CONNECT] = function (meta, given_port, command_to_run)
    local remote_port = given_port and tonumber(given_port) or nil
    if remote_port then
      local wants_us = meta.port == core_lib.config.DAEMON_PORT

      if wants_us then
        local hostArgs =
        {
          remote_id = meta.remote_id,
          remote_port = remote_port,
          port = meta.port,
          command = command_to_run or "",
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
