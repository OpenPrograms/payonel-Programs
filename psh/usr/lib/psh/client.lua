local psh = require("psh")
local thread = require("thread")

local C = {}

function C.run(socket, command, options)
  checkArg(1, socket, "table")
  checkArg(2, command, "string", "nil")
  checkArg(3, options, "table", "nil")
  options = options or {}

  local init = {
    command, -- cmd
    -- timeout,
    -- X
  }
  do
    local ret = socket:wait(0)
    if ret == false then
      io.stderr:write("the connection wasn't ready")
      os.exit(1)
    elseif not ret then
      io.stderr:write("the connection was closed")
      os.exit(1)
    end
  end
  psh.push(socket, psh.api.init, init)

  local function stdin()
    local input = io.read("*L")
    if input then
      psh.push(socket, psh.api.io, {[0]=input})
    end
  end

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

  socket:close()
end

return C
