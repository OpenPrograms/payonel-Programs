local psh = require("psh")
local term = require("term")

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
      io.stderr:write("psh client was started before the socket connection was ready")
      os.exit(1)
    elseif not ret then
      io.stderr:write("psh client was started with a closed socket")
      os.exit(1)
    end
  end
  psh.push(socket, psh.api.init, init)

  local function stdin()
    --[[
      term read is very helpful here because it let's us differentiate ^c from ^d
      ^c: false, "interrupted"
      ^d: nil

      whereas io.read("*L") returns nil in both cases, and io.read() doesn't return the newline we also need

      to make it clear we are passing nil, we'll pass 0 (c-style null)
    ]]
    local ok, input = pcall(term.read)
    if not ok then
      psh.push(socket, psh.api.throw, "interrupted")
    else
      if input == nil then
        input = 0
      end
      psh.push(socket, psh.api.io, {[0]=input})
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
