local psh = require("psh")
local thread = require("thread")
local event = require("event")
local tty = require("tty")

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

local function send_stdin(socket, data, message)
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

local function async_write(stream, data)
  if not stream or not data then return end
  local cursor = io.stdin.tty and tty.window.cursor
  if cursor then
    cursor:echo(false)
  end
  stream:write(data)
  if cursor then
    cursor:echo()
  end
end

local function send_abort(socket)
  psh.push(socket, psh.api.throw, "aborted")
  socket:close()
  async_write(io.stderr, "\naborted\n")
end

local function socket_handler(socket)
  while socket:wait(0) do
    local ok, eType, packet = pcall(psh.pull, socket, 1)
    if ok then
      if eType == psh.api.io then
        for i=1,2 do
          async_write(io.stream(i), packet[i])
        end
      end
    else
      send_abort(socket)
      break
    end
    if io.stdin:size() > 0 then
      send_stdin(socket, io.stdin:read(io.stdin:size()))
    end
  end
  event.push("interrupted")
end

local function stdin_proc(socket)
  repeat
    local result = send_stdin(socket, io.read("L"))
  until not result
end

local function initialize(socket, command, _)
  local ret = socket:wait(0)
  if ret == false then
    io.stderr:write("psh client was started before the socket connection was ready")
    os.exit(1)
  elseif not ret then
    io.stderr:write("psh client was started with a closed socket")
    os.exit(1)
  end
  local init = {
    command, -- cmd
    -- timeout,
    -- X
    -- which io is open (1, 2, 3)
    -- which io has tty
  }
  -- if stdin is tty, then we need to help the cursor
  if io.stdin.tty then
    tty.window.cursor = {
      handle = function(self, name, char, code)
        if name == "interrupted" then
          if not socket:wait(0) then
            return
          end
        end
        return self.super.handle(self, name, char, code)
      end
    }
  end
  psh.push(socket, psh.api.init, init)
  return true
end

function C.run(socket, command, options)
  checkArg(1, socket, "table")
  checkArg(2, command, "string", "nil")
  checkArg(3, options, "table", "nil")
  options = options or {}

  if not initialize(socket, command, options) then
    return
  end

  local socket_handler_thread = thread.create(socket_handler, socket)

  if not pcall(stdin_proc, socket) then
    send_abort(socket)
  end

  socket_handler_thread:join()
  socket:close()
end

return C
