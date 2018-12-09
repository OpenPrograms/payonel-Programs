local psh = require("psh")
local term = require("term")

local C = {}

-- kernel patches
do
  -- io.dup __newindex fix
  local dup_mt = getmetatable(io.dup({}))
  if not dup_mt.__newindex then
    dup_mt.__newindex = function(dfd, key, value)
      dfd.fd[key] = value
    end
  end
end

function C.run(socket, command, options)
  checkArg(1, socket, "table")
  checkArg(2, command, "string", "nil")
  checkArg(3, options, "table", "nil")
  options = options or {}

  local init = {
    command, -- cmd
    -- timeout,
    -- X
    -- which io is open (1, 2, 3)
    -- which io has tty
  }
  do
    local ret = socket:wait(0)
    if ret == false then
      io.stderr:write("psh client was started before the socket connection was ready")
      os.exit(1)
    elseif not ret then
      io.stderr:write("psh client was started with a closed socket")
      os.exit(1)
    end
  end
  psh.push(socket, psh.api.init, init)

  local function stdin()
    local ok, data, message = pcall(function()
      local input = io.stdin
      if input:size() > 0 then
        return input:read(input:size())
      end
      local data, message = input:read(1)
      if not data then
        return data, message
      end
      if input:size() > 0 then
        data = data .. input:read(input:size())
      end
      return data
    end)
    if not ok then
      psh.push(socket, psh.api.throw, "interrupted")
    else
      if not data then
        if not message then
          data = 0
        else
          data = false
        end
      end
      psh.push(socket, psh.api.io, {[0]=data})
    end
  end

  pcall(function()
    while socket:wait(0) do
      local eType, packet = psh.pull(socket, 1)
      if eType == psh.api.io then
        if packet[0] then
          stdin()
        elseif packet[1] then
          io.write(packet[1])
        elseif packet[2] then
          io.stderr:write(packet[2])
        end
      end
    end
  end)

  socket:close()
end

return C
