local testutil = require("testutil")
local ccur = require("core/cursor")
local term = require("term")
local ser = require("serialization").serialize
local tty = require("tty")
local log = require("component").sandbox.log
local process = require("process")
local unicode = require("unicode")

local real_gpu = term.gpu()

local viewport_width = 80
local viewport_height = 10
local viewport = {}

local function viewport_line(y, v)
  v = v or viewport
  assert(y >= 1 and y <= viewport_height, "bad viewport line")
  local line = (v[y] or "")
  line = line .. (" "):rep(viewport_width + 1)
  return unicode.wtrunc(line, viewport_width + 1)
end

local function wsub(data, from, to)
  local data_wlen = unicode.wlen(data)
  to = math.min(to or data_wlen, data_wlen)
  if to < 1 or to < from or from > data_wlen then return "" end
  local current = 1
  local first = from == 1 and 1
  local last = to == 1 and 1
  local index = 1
  local pre, pst = "", ""
  while not last do
    local n = unicode.sub(data, index, index)
    local w = unicode.wlen(n)
    if not first then
      local dx = from - current
      if dx == 0 then
        first = index
      elseif dx <= w then
        first = index + 1
        pre = dx == w and "" or " "
      end
    end
    local dx = to - (current + w) + 1
    if dx <= 0 then
      last = index + dx
      pst = dx < 0 and " " or ""
    end
    index = index + 1
    current = current + w
  end
  return pre .. unicode.sub(data, first, last) .. pst
end

local function show_viewport(...)
  if select("#", ...) > 0 then log({...}) end
  log(unicode.char(0x2552) .. unicode.char(0x2550):rep(viewport_width) .. unicode.char(0x2555))
  for yi=1,viewport_height do
    local line = viewport_line(yi)
    log(unicode.char(0x2502) .. line .. unicode.char(0x2502))
  end
  log(unicode.char(0x2514) .. unicode.char(0x2500):rep(viewport_width) .. unicode.char(0x2518))
end

local test_gpu = setmetatable({
  setResolution = function(w, h)
    viewport_width = w
    viewport_height = h
  end,
  setViewport = function() assert(false, "cannot setViewport") end,
  getScreen = real_gpu.getScreen,
  set = function(x, y, data)
    if y < 1 or y > viewport_height or x > viewport_width then
      return
    end
    local dx = math.max(x, 1) - x
    local ret = wsub(wsub(data, 1 + dx), 1, viewport_width)
    local line = viewport_line(y)
    x = x + dx
    viewport[y] = wsub(line, 1, x - 1) .. ret
      .. wsub(line, x + unicode.wlen(ret))
  end,
  copy = function(x, y, width, height, dx, dy)
    local function in_bounds(_x, _y, _w, _h)
      return _x <= viewport_width and _y <= viewport_height
        and (_x + _w) >= 1 and (_y + _h) >= 1
    end
    local move_x = math.max(x, 1) - x
    local move_y = math.max(y, 1) - y
    x = x + move_x
    y = y + move_y
    width = width - move_x
    height = height - move_y
    dx = dx + move_x
    dy = dy + move_y
    if not in_bounds(x, y, width, height) or
       not in_bounds(x + dx, y + dy, width, height) or
       (width == 0 or height == 0) or
       (dx == 0 and dy == 0) then
      return
    end
    local buffer = {}
    for yi=y,height do
      table.insert(buffer, wsub(viewport_line(yi), x, x + width - 1))
    end
    for yi=y,height do
      table.insert(buffer, wsub(viewport_line(yi), x, x + width - 1))
      term.gpu().set(x + dx, yi + dy, buffer[yi - y + 1])
    end
  end,
  fill = function(x, y, width, height, char)
    local brush = unicode.sub(char, 1, 1):rep(width)
    for yi=y,y+height-1 do
      term.gpu().set(x, yi, brush)
    end
  end,
  fg = real_gpu.getForeground(),
  bg = real_gpu.getBackground()
}, {__index=function(_, ...)
  log("missing gpu method", ...)
end})

function test_gpu.setForeground(c)
  local old = test_gpu.fg
  test_gpu.fg = c
  return old
end
function test_gpu.setBackground(c)
  local old = test_gpu.bg
  test_gpu.bg = c
  return old
end
function test_gpu.getForeground()
  return test_gpu.fg
end
function test_gpu.getBackground()
  return test_gpu.bg
end
function test_gpu.get(x, y)
  return wsub(viewport_line(y), x, x)
end

local function viewport_verify(expected)
  show_viewport()
  for y=1,viewport_height do
      testutil.assert("bad line",
        viewport_line(y, expected),
        viewport_line(y),
        y
    )
  end
end

-- st: scroll test
local function st(vindex, offset, line, printed, pos)
  viewport = {}
  test_gpu.setResolution(80, 2)

  local actual_cursor_position

  local ok, why = pcall(function()
    local pthread = process.load(function()
      local width = term.getViewport()
      assert(width == 80, "these cursor tests require 80 width terminal")
      local c = ccur.new(nil, ccur.horizontal)
      -- optional, maybe needed when we do sy testing
      tty.window.cursor = c
      c:update(line, false)
      c:scroll(vindex, offset)
      actual_cursor_position = term.getCursor()
    end)

    --create test window
    local window = term.internal.open(0, 0, viewport_width, viewport_height)
    process.list[pthread].data.window = window
    term.bind(test_gpu, window)
    
    assert(not process.internal.continue(pthread), "pthread crashed")
  end)
  
  assert(ok, "something crashed: " .. tostring(why))

  local details = ser({vindex=vindex,offset=offset,line=line:sub(1, 20)})
  local expected = viewport_line(1, {printed})
  local actual = viewport_line(1)
  testutil.assert("cursor position", pos, actual_cursor_position, details)
  testutil.assert(string.format("print error [%s]", details), expected, actual)

  show_viewport()
end

-- {vindex, offset, line}
local line = "abcdef"
st( 0, 0, line, "abcdef", 1)
st( 0, 1, line, "abcdef", 2)
st( 0, 2, line, "abcdef", 3)
st( 0, 3, line, "abcdef", 4)

-- error checking
st( 1, 0, line, "abcdef", 1)

st( 1, 1, line, "bcdef", 1)
st( 1, 2, line, "bcdef", 2)
st( 1, 3, line, "bcdef", 3)

st( 2, 1, line, "bcdef", 1)
st( 2, 2, line,  "cdef", 1)
st( 2, 3, line,  "cdef", 2)
st( 2, 4, line,  "cdef", 3)
st( 2, 5, line,  "cdef", 4)
st( 2, 6, line,  "cdef", 5)

-- offset beyond
st( 2, 7, line, "cdef", 5)
st( 2, 8, line, "cdef", 5)

st( 3, 0, line, "abcdef", 1)
st( 3, 1, line,  "bcdef", 1)
st( 3, 2, line,   "cdef", 1)
st( 3, 3, line,    "def", 1)
st( 3, 4, line,    "def", 2)
st( 3, 5, line,    "def", 3)
st( 3, 6, line,    "def", 4)

-- offset beyond
st( 3, 7, line, "def", 4)
st( 3, 8, line, "def", 4)

--long lines
local long = ""
for i=1,200 do
  long = string.format("%s.%d", long, i)
end

-- check offsets in vindex = 0
st(0, 0, long, long:sub(1, 80), 1)
st(0, 10, long, long:sub(1, 80), 11)
st(0, 20, long, long:sub(1, 80), 21)
st(0, 79, long, long:sub(1, 80), 80)

st(0,  80, long, long:sub(2, 81), 80)
st(0, 100, long, long:sub(22, 101), 80)

st(1, 80, long, long:sub(2, 81), 80)
st(2, 81, long, long:sub(3, 82), 80)

st(30, 100, long, long:sub(31, 31+79), 100-30+1)
st(1, #long, long, long:sub(-79, -1).." ", 80)
