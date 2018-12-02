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
    viewport = {
      width = packet_body.width or 80,
      height = packet_body.height or 24
    },
  }
end

local function new_stream(socket, context)
  local stream = {handle = socket}

  function stream:write(...)
    local buf = table.concat({...})
    return psh.push(self.handle, psh.api.io, {[1]=buf})
  end

  function stream:read(n)
    -- sh input sets the cursor, without sy,tails
    -- and then tty write expects it
    -- it's a dumb mistake, so we set sy and tails here to be safe
    local cursor = tty.window.cursor
    if cursor then
      cursor.sy = cursor.sy or 0
      cursor.tails = cursor.tails or {}
    end

    -- request 0 [stdin:0]
    psh.push(self.handle, psh.api.io, {[0]=n})

    while true do
     local eType, packet = psh.pull(self.handle)
     if not eType then
      return
     elseif eType == psh.api.io and packet[0] then
      return packet[0] -- stdin
     end
     -- else, handle the packet
    end
  end

  function stream:close()
    self.handle:close()
  end

  local bs = buffer.new("rw", stream)
  bs.tty = true
  bs:setvbuf("no")
  process.closeOnExit(bs)

  return bs
end

local function new_gpu(socket, context)
  local gpu = {}

  function gpu.getScreen()
    return string.format("remote:screen:%s", socket.remote_id)
  end

  function gpu.getViewport()
    return context.viewport.width, context.viewport.height
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
  pcall(function()
    if not socket:wait(_init_packet_timeout) then
      log("host timed out")
      return
    end
    -- the socket connection hasn't proven it is for psh
    -- though it is using psh.sockets
    -- give it time to provide the init packet to establish a psh session
    local context = parsers[psh.api.init](psh.pull(socket, _init_packet_timeout))
    context.socket = socket

    local host_stream = new_stream(socket, context)
    io.input(host_stream)
    io.output(host_stream)
    io.error(host_stream)

    -- TODO: use connection data to define remote terminal size
    local window = term.internal.open()
    process.info().data.window = window
    term.bind(new_gpu(socket, context))
    window.keyboard = string.format("remote:keyboard:%s", socket.remote_id)

    shell.getShell()(nil, context.command)

    host_stream:flush()
  end)

  socket:close()
end

return H
