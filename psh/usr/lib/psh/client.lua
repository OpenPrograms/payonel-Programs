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
  psh.push(socket, psh.api.init, init)

  local function stdin()
    local input = io.read("*L")
    if input then
      psh.push(socket, psh.api.io, {[0]=input})
    end
  end

  local function handle_next_packet()
    local eType, packet = psh.pull(socket)
    if eType == psh.api.io then
      if packet[0] then
        stdin()
      elseif packet[1] then
        io.write(packet[1])
      elseif packet[2] then
        io.stderr:write(packet[2])
      end
    end
    return eType
  end

  repeat until not handle_next_packet()

  socket:close()
end

return C
