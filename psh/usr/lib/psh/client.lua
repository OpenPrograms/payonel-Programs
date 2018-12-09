local psh = require("psh")
local thread = require("thread")
local event = require("event")

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

local function write_stdin(socket, data, message)
  if not socket:wait(0) then
    return
  end
  if not data then
    if not message then
      data = 0
    else
      data = false
    end
  end
  psh.push(socket, psh.api.io, {[0]=data})
  return data ~= 0
end

local function send_abort(socket)
  psh.push(socket, psh.api.throw, "aborted")
  socket:close()
  io.stderr:write("aborted")
end

local function socket_handler(socket)
  while socket:wait(0) do
    local ok, eType, packet = pcall(psh.pull, socket, 1)
    if ok then
      if eType == psh.api.io then
        if packet[1] then
          io.write(packet[1])
        elseif packet[2] then
          io.stderr:write(packet[2])
        end
      end
    else
      send_abort(socket)
      break
    end
    if io.stdin:size() > 0 then
      write_stdin(socket, io.stdin:read(io.stdin:size()))
    end
  end
  event.push("interrupted")
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

  local socket_handler_thread = thread.create(socket_handler, socket)

  local ok = pcall(function()
    repeat until not write_stdin(socket, io.read("L"))
  end)
  if not ok then
    send_abort(socket)
  end

  socket_handler_thread:join()
  socket:close()
end

return C
