local testutil = require("testutil")
local ccur = require("core/cursor")
local term = require("term")
local ser = require("serialization").serialize
local log = require("component").sandbox.log
local process = require("process")
local unicode = require("unicode")
local kb = require("keyboard")
local keys = kb.keys

do
  local c = ccur.new()
  testutil.assert("new c data", "", c.data)
end

testutil.asserts = 0
local real_gpu = term.gpu()

local viewport_width = 80
local viewport_height = 2
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

local function gpu_sandbox(f)
  test_gpu.setResolution(viewport_width, viewport_height)
  viewport = {}

  local ok, why = pcall(function()
    local pthread = process.load(f)

    --create test window
    local window = term.internal.open(0, 0, viewport_width, viewport_height)
    process.list[pthread].data.window = window
    term.bind(test_gpu, window)
    
    local crash = process.internal.continue(pthread)
    assert(not crash, "pthread crashed:"..tostring(crash))
  end)
  
  assert(ok, "something crashed: " .. tostring(why))
end

-- st: scroll test
local function st(vindex, offset, line, printed, pos)
  local actual_cursor_position

  gpu_sandbox(function()
    local c = ccur.new(nil, ccur.horizontal)
    c:update(line, false)
    c:scroll(vindex, offset)
    actual_cursor_position = term.getCursor()
  end)

  local details = ser({vindex=vindex,offset=offset,line=line:sub(1, 20)})
  local expected = viewport_line(1, {printed})
  local actual = viewport_line(1)
  testutil.assert("cursor position", pos, actual_cursor_position, details)
  testutil.assert(string.format("print error [%s]", details), expected, actual)
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

-- vertical move test
local function v_move_test(before, after, move, expected_result, expected_cmd, expected_num)
  local actual_move_echo_cmd
  local actual_move_echo_num
  local monitor = true
  local c = ccur.new({
    echo = function(self, cmd, num)
      if monitor and (cmd == keys.left or cmd == keys.right) then
        actual_move_echo_cmd = cmd
        actual_move_echo_num = num
      end
      return self.super.echo(self, cmd, num)
    end
  })

  gpu_sandbox(function()
    require("tty").window.cursor = c
    monitor = false
    c:update(before)
    c:update(after, -unicode.len(after))
    monitor = true
    c:move(move)
    monitor = false
    c:update("x")
  end)

  local details = ser({before=before,after=after,move=move,cmd=actual_move_echo_cmd})
  expected_result = viewport_line(1, {expected_result})
  testutil.assert("result", expected_result, viewport_line(1), details)
  testutil.assert("cmd", expected_cmd, actual_move_echo_cmd, details)
  testutil.assert("num", expected_num, actual_move_echo_num, details)
end

for i=-4,4 do
  v_move_test("", "", i, "x", nil, nil)
end
for i=0,4 do
  v_move_test("abc", "", i, "abcx", nil, nil)
end

v_move_test("abc", "", -1, "abxc", keys.left, 1)
v_move_test("abc", "", -2, "axbc", keys.left, 2)
v_move_test("abc", "", -3, "xabc", keys.left, 3)
v_move_test("abc", "", -4, "xabc", keys.left, 3)
v_move_test("abc", "", -5, "xabc", keys.left, 3)

v_move_test("abc", "efg", 0, "abcxefg", nil, nil)

v_move_test("abc", "efg", -1, "abxcefg", keys.left, 1)
v_move_test("abc", "efg", -2, "axbcefg", keys.left, 2)
v_move_test("abc", "efg", -3, "xabcefg", keys.left, 3)
v_move_test("abc", "efg", -4, "xabcefg", keys.left, 3)

v_move_test("abc", "efg",  1, "abcexfg", keys.right, 1)
v_move_test("abc", "efg",  2, "abcefxg", keys.right, 2)
v_move_test("abc", "efg",  3, "abcefgx", keys.right, 3)
v_move_test("abc", "efg",  4, "abcefgx", keys.right, 3)

-- test moving over wide chars
local W = unicode.char(0x5200)
v_move_test(W, "", -1, "x"..W, keys.left, 2)
v_move_test(W, W, -1, "x"..W..W, keys.left, 2)
v_move_test(W, W, 1, W..W.."x", keys.right, 2)

v_move_test(W.."bc", W, -1, string.format("%sbxc%s", W, W), keys.left, 1)
v_move_test(W.."bc", W, -2, string.format("%sxbc%s", W, W), keys.left, 2)
v_move_test(W.."bc", W, -3, string.format("x%sbc%s", W, W), keys.left, 4)
v_move_test(W.."bc", W, -4, string.format("x%sbc%s", W, W), keys.left, 4)

v_move_test(W.."bc", W.."BC", 0, string.format("%sbcx%sBC", W, W))
v_move_test(W.."bc", W.."BC", 1, string.format("%sbc%sxBC", W, W), keys.right, 2)
v_move_test(W.."bc", W.."BC", 2, string.format("%sbc%sBxC", W, W), keys.right, 3)
v_move_test(W.."bc", W.."BC", 3, string.format("%sbc%sBCx", W, W), keys.right, 4)
v_move_test(W.."bc", W.."BC", 3, string.format("%sbc%sBCx", W, W), keys.right, 4)

-- move over the end
viewport_width = 4
viewport_height = 3
local function overlap_test(data, cut, move, e_lines, e_cmd, e_num)

  local goal_wlen = viewport_width + cut - 1
  local before = ""
  while true do
    local len = unicode.len(before)
    local n = unicode.sub(data, len + 1, len + 1)
    if n == "" or unicode.wlen(before) + unicode.wlen(n) > goal_wlen then
      break
    end
    before = before .. n
  end

  local after = unicode.sub(data, unicode.len(before) + 1)

  v_move_test(before, after, move, e_lines[1], e_cmd, e_num)

  local details = ser({before=before,after=after,move=move,cmd=e_cmd})
  for i=2,viewport_height do
    testutil.assert(string.format("result check line %d", i), viewport_line(i, e_lines), viewport_line(i), details)
  end
end

-- 0 is at the end of the line, 'x' will be inserted at the end of the line and the last on that line will be pushed to the next line
overlap_test("aaaaaaaa", 0, 0, {"aaax", "aaaa", "a"}, nil, nil)
overlap_test("aaaaaaaa", 0, 1, {"aaaa", "xaaa", "a"}, keys.right, 1)

overlap_test("aaaaaaaa", 0, -1, {"aaxa", "aaaa", "a"}, keys.left, 1)
overlap_test("aaaaaaaa", 0,  2, {"aaaa", "axaa", "a"}, keys.right, 2)

overlap_test("aaaaaaaa",-1,  2, {"aaaa", "xaaa", "a"}, keys.right, 2)
overlap_test("aaaaaaaa", 1,  2, {"aaaa", "aaxa", "a"}, keys.right, 2)
overlap_test("aaaaaaaa", 1, -1, {"aaax", "aaaa", "a"}, keys.left, 1)
overlap_test("aaaaaaaa", 1, -2, {"aaxa", "aaaa", "a"}, keys.left, 2)

overlap_test("刀刀刀刀", 0, 0, {"刀x", "刀刀", "刀"}, nil, nil)
overlap_test("刀刀刀刀", 0,-1, {"x刀", "刀刀", "刀"}, keys.left, 2)
overlap_test("刀刀刀刀", 0,-2, {"x刀", "刀刀", "刀"}, keys.left, 2)
overlap_test("刀刀刀刀", 0,-3, {"x刀", "刀刀", "刀"}, keys.left, 2)

overlap_test("刀刀刀刀", 1, 0, {"刀刀", "x刀", "刀"}, nil, nil)
overlap_test("刀刀刀刀", 1,-1, {"刀x", "刀刀", "刀"}, keys.left, 2)
overlap_test("刀刀刀刀", 1,-2, {"x刀", "刀刀", "刀"}, keys.left, 4)
overlap_test("刀刀刀刀", 1,-3, {"x刀", "刀刀", "刀"}, keys.left, 4)
overlap_test("刀刀刀刀", 1,-4, {"x刀", "刀刀", "刀"}, keys.left, 4)
overlap_test("刀刀刀刀", 1, 1, {"刀刀", "刀x", "刀"}, keys.right, 2)
overlap_test("刀刀刀刀", 1, 2, {"刀刀", "刀刀", "x"}, keys.right, 4)
overlap_test("刀刀刀刀", 1, 3, {"刀刀", "刀刀", "x"}, keys.right, 4)

--backfill not supported
-- overlap_test("刀z刀刀刀", 0, 0, {"刀zx", "刀刀", "刀"}, nil, nil)
-- overlap_test("刀z刀刀刀", 2,-1, {"刀zx", "刀刀", "刀"}, keys.left, 2)
-- overlap_test("刀z刀刀刀", 100, -3, {"刀zx", "刀刀", "刀"}, keys.left, 6)

overlap_test("刀z刀刀刀", 2,-2, {"刀xz", "刀刀", "刀"}, keys.left, 3)
overlap_test("刀z刀刀刀", 100, -4, {"刀xz", "刀刀", "刀"}, keys.left, 7)
overlap_test("刀z刀刀刀", 100, -5, {"x刀z", "刀刀", "刀"}, keys.left, 9)

overlap_test("刀z刀刀刀", 2, 0, {"刀z", "刀x", "刀刀"}, nil, nil)

overlap_test("刀z刀刀刀", 100, 0, {"刀z", "刀刀", "刀x"}, nil, nil)
overlap_test("刀z刀刀刀", 100, -1, {"刀z", "刀刀", "x刀"}, keys.left, 2)
overlap_test("刀z刀刀刀", 100, -2, {"刀z", "刀x", "刀刀"}, keys.left, 4)

overlap_test("刀z刀刀刀", -100, 0, {"x刀z", "刀刀", "刀"}, nil, nil)

overlap_test("刀z刀刀12", -100, 100, {"刀z", "刀刀", "12x"}, keys.right, 9)

do
  local c = ccur.new()
  gpu_sandbox(function()
    c:update("hello", false)
  end)
  testutil.assert("silent update", viewport_line(1, {}), viewport_line(1))
  testutil.assert("silent data", "hello", c.data)
  testutil.assert("silent len", 5, c.len)
end

local function delete_test(init, move, update, e_data, e_len)
  local c = ccur.new()
  gpu_sandbox(function()
    c:update(init)
    c:move(move)
    c:update(update)
  end)
  testutil.assert("delete test screen", viewport_line(1, {e_data}), viewport_line(1))
  testutil.assert("delete test data", e_data, c.data)
  testutil.assert("delete test len", e_len, c.len)
end

delete_test("hello", 0, 0, "hello", 5)
delete_test("he刀l刀", 0, -1, "he刀l", 4)
delete_test("he刀l刀", 0, -3, "he", 2)
delete_test("he刀l刀", -4, 2, "hl刀", 3)
delete_test("he刀lo", -3, 1, "helo", 4)
delete_test("he刀lo", -2, -1, "helo", 4)
delete_test("he刀lo", 0, 1, "he刀lo", 5)
delete_test("he刀lo",-5,-1, "he刀lo", 5)

do
  viewport_width = 30
  local c = ccur.new()
  gpu_sandbox(function()
    c:update("hello    world how are you ?      ")
    kb.pressedCodes[keys.lcontrol] = true -- hack!
    c:handle("key_down", nil, keys.w)
    kb.pressedCodes[keys.lcontrol] = nil
    c:update("x")
  end)
  local result = {"hello    world how are you x"}
  testutil.assert("ctrl update line 1", viewport_line(1, result), viewport_line(1))
  testutil.assert("ctrl update line 2", viewport_line(2, result), viewport_line(2))
  testutil.assert("ctrl data", result[1], c.data)
  testutil.assert("ctrl len", 28, c.len)
end
