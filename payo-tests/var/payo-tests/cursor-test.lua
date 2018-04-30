local testutil = require("testutil")
local ccur = require("core/cursor")
local term = require("term")
local ser = require("serialization").serialize
local unicode = require("unicode")
local gpu = require("component").gpu

testutil.timeout = math.huge

local function scroll(cursor, vindex, offset, line, width)
  local len = unicode.len(line)
  offset = math.min(len, offset)
  vindex = math.min(offset, vindex, len - 2)
  if vindex < 1 then
    cursor:update(line, false)
    cursor:move(offset)
    return
  end
  local right_edge = math.max(offset, vindex + width - 1)
  local spaces = right_edge - len
  cursor:update(line .. (" "):rep(spaces), false)
  cursor:move(right_edge)
  if spaces > 0 then
    cursor:update(-spaces)
    right_edge = len
  end
  if offset < right_edge then
    cursor:move(offset - right_edge)
  end
end

-- st: scroll test
local function st(vindex, offset, line, printed, pos)
  local width = term.getViewport()
  assert(width == 80, "these cursor tests require 80 width terminal")
  local c = ccur.new(nil, ccur.horizontal)
  local prev = term.getCursor()
  term.clearLine()
  io.write("\27[?7l")
  io.write(line) -- render it
  io.write("\27[800D")
  scroll(c, vindex, offset, line, width)
  local details = ser({vindex=vindex,offset=offset,line=line:sub(1, 20)})

  io.write("\27[?7h")
  local actual_cursor_position = term.getCursor()
  print()
  local _, y = term.getCursor()
  y = y - 1
  testutil.assert("cursor position", pos, actual_cursor_position, details)

  local expected = ""
  local actual = ""
  for x = 1, width do    
    local char = gpu.get(x, y)
    actual = actual .. char
    expected = expected .. (printed:sub(x, x).." "):sub(1, 1)
  end
  testutil.assert(string.format("print error [%s]", details), expected, actual)
  term.setCursor(prev, y)
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

--max 2 check
st(10,14, line, "ef", 3)

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

print()
