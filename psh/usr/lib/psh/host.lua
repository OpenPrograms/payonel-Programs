local shell = require("shell")
local buffer = require("buffer")
local process = require("process")
local psh = require("psh")
local term = require("term")
local thread = require("thread")
local event = require("event")
local tty = require("tty")

local H = {}
local shutdown = false

-- kernel patches
do
  -- term.internal.open calls tty.bind(tty.gpu())
  -- which passes nil when there is no gpu
  -- it should use the existing window's gpu instead via window.gpu
  local _bind = tty.bind
  function tty.bind(gpu, ...)
    if gpu then
      return _bind(gpu, ...)
    else
      tty.window.gpu = nil
      tty.window.keyboard = nil
    end
  end

  --openos has an in-process reboot/shutdown
  --which is a poor choice for threads and background actions that may want to reboot
  event.listen("shutdown", function()
    shutdown = true
    return false
  end)
end

local _packet_timeout = 5

local parsers = {}

parsers[psh.api.init] = function(packet_label, packet_body)
  assert(packet_label == psh.api.init)
  return {
    command = packet_body.cmd or "/bin/sh",
    X = packet_body.X or false,
    input_queue = {},
    [0] = packet_body[0],
    [1] = packet_body[1],
    [2] = packet_body[2]
  }
end

local stream_base = {
  write = function(self, ...)
    if self.closed then return nil, "closed" end
    local buf = table.concat({...})
    return psh.push(self.socket, psh.api.io, {[self.id] = buf})
  end,
  read = function(self)
    -- sh input sets the cursor, without sy,tails
    -- and then tty write expects it
    -- it's a dumb mistake, so we set sy and tails here to be safe
    local cursor = tty.window.cursor or {}
    cursor.sy = cursor.sy or 0
    cursor.tails = cursor.tails or {}

    local data = ""
    repeat
      local entry = table.remove(self.context.input_queue, 1)
      if entry ~= nil then -- false is valid
        if entry == false then -- interrupted
          return false, "interrupted"
        elseif entry == 0 then -- close
          self:close()
          if #data > 0 then return data end
          break
        elseif type(entry) == "table" then
          local hint = cursor.hint
          if hint then
            local hint_result = hint(table.unpack(entry))
            psh.push(self.socket, psh.api.hint, hint_result)
          end
        elseif type(entry) == "string" then
          data = data .. entry
        end
      end
    until not entry

    if self.closed then
      return nil, "closed"
    elseif #data == 0 then
      event.pull(1, "modem_message")
    end

    return data
  end,
  close = function(self)
    self.closed = true
  end
}

local function new_stream(socket, context, id)
  local stream = {
    socket = socket,
    context = context,
    id = id
  }

  setmetatable(stream, {__index=stream_base})

  local bs = buffer.new("rw", stream)
  bs.tty = context[id]
  bs:setvbuf("no")
  local closeOnExit = process.closeOnExit or process.addHandle
  closeOnExit(bs)

  context.io = context.io or {}
  context.io[id] = bs

  return bs
end

local function new_gpu(socket, context)
  local gpu = {}
  context.screen = string.format("remote:screen:%s", socket.remote_id)
  context.keyboard = string.format("remote:keyboard:%s", socket.remote_id)

  function gpu.getScreen()
    return context.screen
  end

  function gpu.getViewport()
    if not gpu.width then
      gpu.width, gpu.height = table.unpack(context[1] or {0,0})
    end
    return gpu.width, gpu.height
  end

  function gpu.copy(...)
    -- 1, 25, 80, 0, 0, -24
  end

  function gpu.fill(...)
    -- 1, 1, 80, 24, " "
  end

  return gpu
end

local function socket_handler(socket, context)
  while socket:wait(0) do
    local eType, packet = psh.pull(socket, _packet_timeout)
    if packet then
      if eType == psh.api.io then
        local input = packet[0] -- stdin
        table.insert(context.input_queue, input)
      elseif eType == psh.api.hint then
        table.insert(context.input_queue, packet) -- tab data
      end
    end
  end
end

local function open_window(socket, context)
  -- the request may have provided the preferred resolution for stdout (1)
  local width, height = term.getViewport()
  if context[1] then
    width, height = table.unpack(context[1], 1, 2)
  end
  local window = term.internal.open(0, 0, width, height)

  local mt = getmetatable(window) or {}
  local __index = mt.__index
  mt.__index = function(tbl, key)
    if key == "keyboard" then
      return context.keyboard
    elseif __index then
      return __index(tbl, key)
    end
  end
  setmetatable(window, mt)

  process.info().data.window = window
  term.bind(new_gpu(socket, context))
end

function H.run(socket)
  local ok, msg = pcall(function()
    if not socket:wait(_packet_timeout) then
      return -- host timed out
    end
    -- the socket connection hasn't proven it is for psh
    -- though it is using psh.sockets
    -- give it time to provide the init packet to establish a psh session
    local context = parsers[psh.api.init](psh.pull(socket, _packet_timeout))

    for i=0,2 do
      if context[i] ~= nil then
        io.stream(i, new_stream(socket, context, i))
      else
        io.stream(i):close()
      end
    end

    open_window(socket, context)

    local handler_thread = thread.create(socket_handler, socket, context)
    local cmd_thread = thread.create(shell.getShell(), nil, context.command)

    thread.waitForAny({handler_thread, cmd_thread})
    handler_thread:kill()
    if not shutdown then
      cmd_thread:kill()
    end
  end)

  if not ok then
    event.push("host_crashed", socket:remote_address(), socket:id(), msg)
  end

  socket:close()
end

return H
