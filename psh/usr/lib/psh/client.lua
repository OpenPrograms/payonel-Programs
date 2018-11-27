local psh = require("psh")

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

  while true do
    local eType, packet = psh.pull(socket)
    if not eType then
      break
    end
    if eType == psh.api.io then
      if packet[0] then
        psh.push(socket, psh.api.io, {[0]=io.read("L")})
      elseif packet[1] then
        io.write(packet[1])
      elseif packet[2] then
        io.stderr:write(packet[2])
      end
    end
  end

end

return C
