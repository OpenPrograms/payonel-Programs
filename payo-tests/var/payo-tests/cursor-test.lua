local testutil = require("testutil")
local ccur = require("core/cursor")
local term = require("term")
local ser = require("serialization").serialize
local unicode = require("unicode")
local gpu = require("component").gpu

testutil.timeout = math.huge

-- return update, move, cut, back
local function scroll(vindex, offset, line, width)
  local len = unicode.len(line)
  if offset > len then
    offset = len
  end
  vindex = math.min(offset, vindex, len - 2)
  if vindex < 1 then
    return line, offset, 0, 0
  end
  local right_edge = vindex + width - 1
  local spaces = math.floor(right_edge - len)
  local back = math.floor(offset - len)
  return line .. (" "):rep(spaces), right_edge, -spaces, back
end

-- st: scroll test
local function st(vindex, offset, line, width, update, move, cut, back, printed, pos)
  io.write("\27[?7l")
  local actuals = table.pack(scroll(vindex, offset, line, width))
  local details = {{vindex=vindex,offset=offset,line=line,width=width},{update=update,move=move,cut=cut,back=back}}
  local dbg =
    actuals[1] ~= update or
    actuals[2] ~=   move or
    actuals[3] ~=    cut or
    actuals[4] ~=   back
  term.clearLine()
  if dbg then
    print("   input:"..ser(details[1]))
    print("expected:"..ser(details[2]))
    print("  actual:"..ser({update=actuals[1],move=actuals[2],cut=actuals[3],back=actuals[4]}))
  end
  local c = ccur.new(nil, ccur.horizontal)
  io.write(update) -- render it
  io.write("\27[800D")
  c:update(update, false)
  c:move(move)
  if cut < 0 then
    c:update(cut)
  end
  if back < 0 then
    c:move(back)
  end
  io.write("\27[?7h")
  testutil.assert("update text",   update, actuals[1], details)
  testutil.assert("move right edge", move, actuals[2], details)
  testutil.assert("cut off end",      cut, actuals[3], details)
  testutil.assert("move back",       back, actuals[4], details)

  local w, _, _, _, _, y = term.getViewport()
  for x = 1, w do    
    local char = gpu.get(x, y)
    testutil.assert(string.format("printed char [%d]", x), (printed:sub(x, x).." "):sub(1, 1), char, details)
  end
  print()
end
                                                                           
-- {vindex, offset, line, width}, {update, move, cut, back}
local line = "abcdef"
local width = 80
st( 0, 0, line, width, line, 0, 0, 0, "abcdef", 1)
st( 0, 1, line, width, line, 1, 0, 0, "abcdef", 2)
st( 0, 2, line, width, line, 2, 0, 0, "abcdef", 3)
st( 0, 3, line, width, line, 3, 0, 0, "abcdef", 4)

-- error checking
st( 1, 0, line, width, line, 0, 0, 0, "abcdef", 1)

st( 1, 1, line, width, line .. (" "):rep(74), 80, -74, -5, "bcdef", 1)
st( 1, 2, line, width, line .. (" "):rep(74), 80, -74, -4, "bcdef", 2)
st( 1, 3, line, width, line .. (" "):rep(74), 80, -74, -3, "bcdef", 3)

st( 2, 1, line, width, line .. (" "):rep(74), 80, -74, -5, "bcdef", 1)
st( 2, 2, line, width, line .. (" "):rep(75), 81, -75, -4,  "cdef", 1)
st( 2, 3, line, width, line .. (" "):rep(75), 81, -75, -3,  "cdef", 2)
st( 2, 4, line, width, line .. (" "):rep(75), 81, -75, -2,  "cdef", 3)
st( 2, 5, line, width, line .. (" "):rep(75), 81, -75, -1,  "cdef", 4)
st( 2, 6, line, width, line .. (" "):rep(75), 81, -75,  0,  "cdef", 5)

-- offset beyond
st( 2, 7, line, width, line .. (" "):rep(75), 81, -75,  0,  "cdef", 5)
st( 2, 8, line, width, line .. (" "):rep(75), 81, -75,  0,  "cdef", 5)

st( 3, 0, line, width,                  line,  0,   0,  0, "abcdef", 1)
st( 3, 1, line, width, line .. (" "):rep(74), 80, -74, -5,  "bcdef", 1)
st( 3, 2, line, width, line .. (" "):rep(75), 81, -75, -4,   "cdef", 1)
st( 3, 3, line, width, line .. (" "):rep(76), 82, -76, -3,    "def", 1)
st( 3, 4, line, width, line .. (" "):rep(76), 82, -76, -2,    "def", 2)
st( 3, 5, line, width, line .. (" "):rep(76), 82, -76, -1,    "def", 3)
st( 3, 6, line, width, line .. (" "):rep(76), 82, -76,  0,    "def", 4)

-- offset beyond
st( 3, 7, line, width, line .. (" "):rep(76), 82, -76,  0,    "def", 4)
st( 3, 8, line, width, line .. (" "):rep(76), 82, -76,  0,    "def", 4)

--max 2 check
st(10,14, line, width, line .. (" "):rep(77), 83, -77,  0,     "ef", 3)

--long lines
local long = ""
for i=1,80 do
  long = string.format("%s.%d", long, i)
end

