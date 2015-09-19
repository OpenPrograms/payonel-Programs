local component = require("component")
local event = require("event")
local config = require("payo-lib/config")
local tutil = require("payo-lib.tableutil")

local m = component.modem
assert(m)

local host_lib = require("psh.host")

local lib = {}

function lib.init(pshlib, pshd, args)
  pshd.applicable = function(meta)
    return true -- pshd applies to all clients
  end

  pshd.tokens[pshlib.api.SEARCH] = function (meta, p1, p2)
    local remote_port = p2 and tonumber(p2) or nil
    if remote_port then

      local wants_us = true
      p1 = (p1 and p1:len() > 0 and p1) or nil
      if p1 then
        local id = meta.local_id:find(p1)
        wants_us = id == 1
      end

      if wants_us then
        pshlib.log.debug("available, responding to " .. meta.remote_id .. " on " .. tostring(remote_port))
        m.send(meta.remote_id, remote_port, pshlib.api.AVAILABLE)
        return true -- consume token
      else
        pshlib.log.debug("ignoring search: does not want us")
      end
    else
      pshlib.log.debug("search did not send remote port")
    end
  end

  pshd.tokens[pshlib.api.CONNECT] = function (meta, p1, p2)
    local remote_port = p2 and tonumber(p2) or nil
    
    if remote_port then
      local wants_us = meta.local_id == p1

      if wants_us then
        pshlib.log.debug("sending accept: " .. tostring(meta.remote_id)
          ..",".. tostring(remote_port) ..",".. pshlib.api.ACCEPT)
                
        m.send(meta.remote_id, remote_port, pshlib.api.ACCEPT)

        local host = pshlib.ModemHandler.new('pshd-host:' .. meta.remote_id)

        local hostArgs =
        {
          remote_id = meta.remote_id,
          remote_port = remote_port,
          port = meta.port,
        }

        local ok, reason = host_lib.init(pshlib, host, hostArgs)
        if not ok then
          pshlib.log.error("failed to initialize new host", reason)
        else
          ok, reason = pshlib.start(host)
          if not ok then
            pshlib.log.error("failed to register host", reason)
          end
        end

        return true -- consume token
      else
        pshlib.log.debug("ignoring: does not want us")
      end
    end
  end

  return pshd
end

return lib
