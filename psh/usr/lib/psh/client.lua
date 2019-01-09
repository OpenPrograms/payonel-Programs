local psh = require("psh")
local thread = require("thread")
local event = require("event")
local tty = require("tty")

local C = {}

-- kernel patches
do
  -- io.dup __newindex fix, needed for vt100 cursor position
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

local function socket_handler(socket, options)
  while true do
    local ok, eType, packet = pcall(psh.pull, socket, 1)
    if ok then
      if eType == psh.api.io then
        for i=1,2 do
          async_write(io.stream(i), packet[i])
        end
      elseif eType == psh.api.hint then
        local cursor = tty.window.cursor
        if cursor then
          cursor.cache = packet
        end
      elseif not eType then
        if not socket:wait(0) then
          break
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
  -- only push interrupt if stdin_proc is running
  if options.stdin then
    event.push("interrupted")
  end
end

local function stdin_proc(socket)
  repeat
    local result = send_stdin(socket, io.read("L"))
  until not result
end

local function initialize(socket, command, options)
  local ret = socket:wait(0)
  if ret == false then
    io.stderr:write("psh client was started before the socket connection was ready")
    os.exit(1)
  elseif not ret then
    io.stderr:write("psh client was started with a closed socket")
    os.exit(1)
  end
  local init = {
    cmd = command
    -- X
  }
  -- [no tty = false, tty = true, closed = nil]
  if not io.stdin.closed then
    init[0] = io.stdin.tty and true or false
    if init[0] then
      -- if stdin is tty, then we need to help the cursor
      tty.window.cursor = {
        handle = function(self, name, char, code)
          if name == "interrupted" then
            if not socket:wait(0) then
              return
            end
          end
          return self.super.handle(self, name, char, code)
        end,
        hint = function(cursor_data, cursor_index_plus_one)
          psh.push(socket, psh.api.hint, {cursor_data, cursor_index_plus_one})
          while not tty.window.cursor.cache do
            local e = event.pull(0)
            if e == "interrupted" then
              return {}
            end
          end
          return tty.window.cursor.cache
        end
      }
    end
  end
  if not io.stdout.closed then
    if io.stdin.tty then
      options.stdin = true
    end
    if not io.stdout.tty or command then
      init[1] = false
    else
      local width, height = tty.getViewport()
      init[1] = {width, height}
    end
  end
  if not io.stderr.closed then
    init[2] = io.stderr.tty and true or false
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

  local socket_handler_thread = thread.create(socket_handler, socket, options)

  if not pcall(stdin_proc, socket) then
    send_abort(socket)
  end
  options.stdin = nil

  socket_handler_thread:join()
  socket:close()
end

function C.search(port, address, options)
  local function report(...)
    if not options.q then
      io.stderr:write(...)
    end
  end
  report("Searching for available hosts [control+c to stop search]\n")
  local winner
  local socket = require("psh.socket")

  local collector = socket.broadcast(port)
  while true do
    local candidate = collector:accept()
    if not candidate then
      break -- interrupted
    end
    local valid = true
    local remote_address = candidate:remote_address()
    if address then
      if remote_address:find(address) ~= 1 then
        report(remote_address, " [skipped]\n")
        valid = false
      end
    end
    if valid then
      winner = candidate
      if not options.q then
        local msg = "%s"
        if options.f then
          msg = "Connecting to [%s]"
        end
        io.write(string.format(msg, remote_address), "\n")
      end
      if options.f then
        break
      end
    end
    candidate:close()
  end
  collector:close()

  if options.l or not winner then
    if not winner then
      report("no hosts responded\n")
      os.exit(1)
    end
    os.exit(0)
  end

  return winner
end

return C
