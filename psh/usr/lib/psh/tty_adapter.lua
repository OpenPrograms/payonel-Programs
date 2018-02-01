local buffer = require("buffer")
local tty = require("tty")
local term = require("term")
local process = require("process")
local event = require("event")

local lib = {}

local function build_invoke(comp, method, skip_self)
  return function(...)
    host.send(core_lib.api.INVOKE, comp, method, select(skip_self and 2 or 1, ...))
    local v = table.pack(event.pull(core_lib.api.INVOKE))
    core_lib.log.info("invoke result", table.unpack(v, 1, v.n))
    return table.unpack(v, 1, v.n)
  end
end

function lib.create_vgpu()
  local vgpu = {}
  function vgpu.getScreen()
    return "vgpu_screen." .. tostring(vgpu)
  end
  function vgpu.getBackground()
  end
  return vgpu
end

function lib.open_window(stream)
  stream.window = term.internal.open()
  -- use a metatable on window to make sure it never loses its keyboard
  setmetatable(stream.window, {__index=function(tbl, key)
    if key == "keyboard" then
      return "remote_keyboard:" .. tostring(stream)
    end
  end})

  process.info().data.window = host.window

  stream.gpu = setmetatable({}, {__index=function(tbl, key)
    if key == "getScreen" then
      return function() return "screen:"..host.remote_id end
    end
    core_lib.log.error("missing gpu."..key)
  end})

  tty.bind(host.gpu)

  stream.handle = false
  setmetatable(stream, {__index=function(tbl, key)
    if key == "read" then
      return tty.stream.read
    end
    core_lib.log.error("missing stream."..key)
  end, __metatable = "file"})

  stream.io = {}
  for fh=0,2 do
    local mode = fh == 0 and "r" or "w"
    stream.io[fh] = buffer.new(mode, stream)
    stream.io[fh]:setvbuf("no")
    stream.io[fh].tty = true
    stream.io[fh].close = host.stream.close
    io.stream(fh, host.io[fh], mode)
  end
end

return lib
