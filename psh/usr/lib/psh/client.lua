local psh = require("psh")
local thread = require("thread")

local C = {}

function C.run(socket, args, options)
  checkArg(1, socket, "table")
  checkArg(2, args, "table", "nil")
  checkArg(3, options, "table", "nil")
  args = args or {}
  options = options or {}

  local init = {
    args[1], -- cmd
    -- timeout,
    -- X
  }
  psh.push(socket, psh.api.init, init)
  local input_thread = false

  while true do
    local eType, packet = psh.pull(socket)
    if not eType then
      if input_thread then
        input_thread:kill()
      end
      break
    end
    if eType == psh.api.io then
      if packet[0] then
        if not input_thread then
          input_thread = thread.create(function()
            psh.push(socket, psh.api.io, {[0]=io.read("L")})
            input_thread = false
          end)
        end
      elseif packet[1] then
        io.write(packet[1])
      elseif packet[2] then
        io.stderr:write(packet[2])
      end
    end
  end

end

return C
