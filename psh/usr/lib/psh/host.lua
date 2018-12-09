local shell = require("shell")
local buffer = require("buffer")
local process = require("process")
local psh = require("psh")
local tty = require("tty")
local term = require("term")

local H = {}

local _init_packet_timeout = 5

local parsers = {}

parsers[psh.api.init] = function(packet_label, packet_body)
  assert(packet_label == psh.api.init)
  return {
    command = packet_body[1] or "/bin/sh",
    timeout = packet_body.timeout or _init_packet_timeout,
    X = packet_body.X or false,
  }
end

local stream_base = {
  write = function(self, ...)
    if self.closed then return nil, "closed" end
    local buf = table.concat({...})
    return psh.push(self.socket, psh.api.io, {[self.id] = buf})
  end,
  read = function(self, n)
    if self.closed then return nil, "closed" end
    -- sh input sets the cursor, without sy,tails
    -- and then tty write expects it
    -- it's a dumb mistake, so we set sy and tails here to be safe
    local cursor = tty.window.cursor
    if cursor then
      cursor.sy = cursor.sy or 0
      cursor.tails = cursor.tails or {}
    end

    -- request 0 [stdin:0]
    psh.push(self.socket, psh.api.io, {[self.id]=n})

    while true do
      local eType, packet = psh.pull(self.socket)
      if packet then
        if eType == psh.api.io then
          local input = packet[self.id] -- stdin
          if input ~= nil then -- false is valid
            if input == 0 then -- 0 is an encoded nil
              return
            elseif input == false then -- input is not closed, just interrupted
              return false, "interrupted"
            end
            return input
          end
        elseif eType == psh.api.throw then
          error(packet)
        end
      elseif not self.socket:wait(0) then
        -- failed immediate-wait means the socket is closed/failed
        self:close()
        return
      end
    end
  end,
  close = function(self)
    self.closed = true
  end
}

local function new_stream(socket, _, id)
  local stream = {
    socket = socket,
    id = id
  }

  setmetatable(stream, {__index=stream_base})

  local bs = buffer.new("rw", stream)
  bs.tty = true
  bs:setvbuf("no")
  process.closeOnExit(bs)

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
    tty.window.keyboard = context.keyboard
    if not gpu.width then
      -- save, move, read, and restore cursor position
      io.write("\0277\27[999;999H\27[6n\0278")
      io.flush()
      local esc, height, semi, width, R = io.read(1, "n", 1, "n", 1)
      assert(esc == string.char(0x1b) and semi == ";" and R == "R", "terminal scan pattern failure")
      gpu.width, gpu.height = width, height
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

function H.run(socket)
  local ok, why = pcall(function()
    if not socket:wait(_init_packet_timeout) then
      return -- host timed out
    end
    -- the socket connection hasn't proven it is for psh
    -- though it is using psh.sockets
    -- give it time to provide the init packet to establish a psh session
    local context = parsers[psh.api.init](psh.pull(socket, _init_packet_timeout))

    io.stream(0, new_stream(socket, context, 0))
    io.stream(1, new_stream(socket, context, 1))
    io.stream(2, new_stream(socket, context, 2))

    local window = term.internal.open()
    window.keyboard = context.keyboard
    process.info().data.window = window
    term.bind(new_gpu(socket, context))

    shell.getShell()(nil, context.command)
  end)

  if not ok then
    require("event").push("host_crashed", socket:remote_address(), socket:id(), why)
  end

  socket:close()
end

return H
