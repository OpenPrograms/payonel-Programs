local tty = require("tty")
local unicode = require("unicode")
local testutil = require("testutil")
local computer = require("computer")

-- it's too complicated to call os.sleep in a virtual gpu+screen+keyboard state
testutil.last_time = math.huge

-- tty testing is tricky because we'll have to mock the keyboard and screen in some cases
-- rather than use the term library to create windows we'll intercept the window directly
local original_window = tty.window
local original_beep = computer.beep
local ok, why = xpcall(function()

local beeps = 0
computer.beep = function()
  beeps = beeps + 1
end

local width, height, _dx, _dy = 10, 10, 1, 3
local gpu_proxy
gpu_proxy =
{
  screen = {},
  bg = 0,
  fg = 1,
  setForeground = function(_fg)
    local ofg = gpu_proxy.fg
    gpu_proxy.fg = _fg
    return ofg
  end,
  getForeground = function() return gpu_proxy.fg end,
  setBackground = function(_bg)
    local obg = gpu_proxy.bg
    gpu_proxy.bg = _bg
    return obg
  end,
  getBackground = function() return gpu_proxy.bg end,
  new_cell = function(v)
    if type(v) == "string" then
      assert(unicode.len(v) == 1, "v wrong size: " .. unicode.len(v))
      return {txt=v,fg=gpu_proxy.fg,bg=gpu_proxy.bg}
    elseif v == false then
      return false
    else -- table
      return {txt=v.txt,fg=v.fg,bg=v.bg}
    end
  end,
  getScreen = function() return "gpu_proxy_screen" end,
  set = function(x, y, value)
    checkArg(1, x, "number")
    checkArg(2, y, "number")
    checkArg(3, value, "string")
    x = x - _dx
    y = y - _dy
    if y < 1 or y > height then
      return -- do nothing
    end
    local clip = unicode.sub(value, math.max(1, 2 - x))
    clip = unicode.sub(clip, 1, math.min(-1, width - unicode.wlen(clip) - 1))
    for i=1,unicode.len(clip) do
      local sx = math.max(x, 1) + unicode.wlen(unicode.sub(clip, 1, i - 1))
      gpu_proxy.screen[y][sx] = gpu_proxy.new_cell(unicode.sub(clip, i, i))
    end
  end,
  reset = function()
    gpu_proxy.screen = {}
    for y=1,height do
      gpu_proxy.screen[y] = {}
      for x=1,width do
        gpu_proxy.screen[y][x] = false -- unset or cleared
      end
    end
  end,
  verify = function(line, y, remove, start)
    local dx = (start or 1) - 1
    for x=1,math.min(width,unicode.len(line)) do
      local cell = gpu_proxy.screen[y][x + dx]
      local exp = unicode.sub(line, x, x)
      assert(cell ~= false,
        string.format("missing cell [%d, %d] expected ['%s']", x + dx, y, exp))
      assert(cell.txt == exp,
        string.format("bad cell txt [%d, %d] actual['%s'] expected['%s']", x + dx, y, cell.txt, exp))
      if remove then
        gpu_proxy.screen[y][x + dx] = false
      end
      if unicode.wlen(exp) > 1 then
        assert(gpu_proxy.screen[y][x + dx + 1] == false, "cell after wide should be false")
        testutil.bump(true)
        dx = dx + 1
      end
    end
    testutil.bump(true)
  end,
  is_verified = function()
    for y=1,height do
      for x=1,width do
        assert(gpu_proxy.screen[y][x] == false, "gpu did not verify: " .. gpu_proxy.cell_tostring(y, x))
      end
    end
    testutil.bump(true)
    gpu_proxy.bg = 0
    gpu_proxy.fg = 1
  end,
  copy = function(x, y, w, h, dx, dy)
    x = x - _dx
    y = y - _dy
    local xadj = math.max(1, x) - x
    local yadj = math.max(1, y) - y

    x = x + xadj
    y = y + yadj
    w = w - xadj
    h = h - yadj
    dx = dx - xadj
    dy = dy - yadj

    local tx = x + dx
    local ty = y + dy

    if w <= 0 or h <= 0 then
      return true
    end

    if tx > width or ty > height then
      return true
    end

    if (tx + w) < 1 or (ty + h) < 1 then
      return true
    end

    if x > width or y > height then
      return true
    end

    if (x + w) < 1 or (y + h) < 1 then
      return true
    end

    if dx == 0 and dy == 0 then
      return true
    end

    -- truncate width and height so our cells are always non-null
    w = math.min(w, width - x + 1)
    h = math.min(h, height - y + 1)

    local buffer = {}
    for yoffset=0,h-1 do
      for xoffset=0,w-1 do
        local cell = gpu_proxy.screen[y + yoffset][x + xoffset];
        buffer[#buffer + 1] = gpu_proxy.new_cell(cell)
      end
    end

    for yoffset=0,h-1 do
      for xoffset=0,w-1 do
        gpu_proxy.screen[ty + yoffset][tx + xoffset] = table.remove(buffer, 1)
      end
    end
  end,
  fill = function(x, y, w, h, v)
    x = x - _dx
    y = y - _dy
    if unicode.len(v) ~= 1 then
      return nil, "invalid fill value"
    end
    local cell = gpu_proxy.new_cell(v)
    for row=0,h-1 do
      local x_start = x
      for _=1,w do
        gpu_proxy.screen[y + row][x_start] = cell
        if unicode.len(v) > 1 then
          gpu_proxy.screen[y + row][x_start + 1] = false
        end
        x_start = x_start + unicode.wlen(v)
      end
    end

    return true
  end,
  cell_tostring = function(y, x)
    local str = string.format("{%d, %d", x, y)
    local cell = gpu_proxy.screen[y][x]
    if not cell then
      str = str .. ", " .. tostring(cell)
    else
      str = str .. string.format(", '%s'", cell.txt)
    end
    return str .. "}"
  end,
  match = function(exp, x, y, remove)
    local cell = gpu_proxy.screen[y][x]
    if exp == false then
      assert(cell == false, string.format("unexpected cell %s", gpu_proxy.cell_tostring(y, x)))
    else
      assert(cell ~= false, string.format("missing cell at [%d, %d] expected[%s]", x, y, exp.txt))
      assert(exp.txt == cell.txt, string.format("wrong cell text expected[%s] actual[%s]", exp.txt, cell.txt))
      assert(exp.fg == cell.fg, string.format("wrong cell fg expected[%d] actual[%d]", exp.fg, cell.fg))
      assert(exp.bg == cell.bg, string.format("wrong cell bg expected[%d] actual[%d]", exp.bg, cell.bg))
    end
    if remove then
      gpu_proxy.screen[y][x] = false
    end
    testutil.bump(true)
  end
}
gpu_proxy.reset()

-- tty:write tests
tty.window =
{
  gpu = gpu_proxy,
}

tty.setViewport(width, height, _dx, _dy)
tty.setCursor(1,1)
tty:write("123456789ABCD")

gpu_proxy.verify("123456789A", 1, true)
gpu_proxy.verify("BCD", 2, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write((" "):rep(width * height))
for y=1,height do
  gpu_proxy.verify((" "):rep(width), y, true)
end
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write(("a"):rep(width*2 + 2))
tty:write("bbb")
gpu_proxy.verify(("a"):rep(width), 1, true)
gpu_proxy.verify(("a"):rep(width), 2, true)
gpu_proxy.verify("aabbb", 3, true)
gpu_proxy.is_verified()

tty:write("\n123\r\n\t456")
gpu_proxy.verify("123", 4, true)
gpu_proxy.verify("45", 5, true, 9)
gpu_proxy.verify("6", 6, true)
gpu_proxy.is_verified()

tty.setCursor(2, 2)
assert(tty.getCursor() == 2)
assert(select(2, tty.getCursor()) == 2)
tty.clear()
assert(tty.getCursor() == 1)
assert(select(2, tty.getCursor()) == 1)
for y=1,height do
  gpu_proxy.verify((" "):rep(width), y, true)
end
gpu_proxy.is_verified()

tty.setCursor(1, 2)
tty:write("a")
gpu_proxy.verify("a", 2, true)
tty.setCursor(width + 1, 2)
tty:write("b")
gpu_proxy.verify("b", 3, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("a"..(" "):rep(width - 1).."b")
gpu_proxy.verify("a"..(" "):rep(width), 1, true)
gpu_proxy.verify("b", 2, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
local mame_kanji = unicode.char(35910)
tty:write(mame_kanji:rep(width))
gpu_proxy.verify(mame_kanji:rep(width / 2), 1, true)
gpu_proxy.verify(mame_kanji:rep(width / 2), 2, true)
gpu_proxy.is_verified()

local text_value = mame_kanji.."a"
tty.setCursor(1, 1)
tty:write(text_value:rep(width))
gpu_proxy.verify(text_value:rep(3).." ", 1, true)
gpu_proxy.verify(text_value:rep(3).." ", 2, true)
gpu_proxy.verify(text_value:rep(3).." ", 3, true)
gpu_proxy.verify(text_value, 4, true)
gpu_proxy.is_verified()

text_value = "a"..mame_kanji
tty.setCursor(1, 1)
tty:write(text_value:rep(width))
gpu_proxy.verify(text_value:rep(3).."a", 1, true)
gpu_proxy.verify(mame_kanji..text_value:rep(2).."a ", 2, true)
gpu_proxy.verify(mame_kanji..text_value:rep(2).."a ", 3, true)
gpu_proxy.verify(mame_kanji, 4, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("a"..mame_kanji.."b\nc"..mame_kanji.."\r\a"..mame_kanji.."\r\n"..mame_kanji.."\r\r\a"..mame_kanji)
gpu_proxy.verify("a"..mame_kanji.."b", 1, true)
gpu_proxy.verify("c"..mame_kanji, 2, true)
gpu_proxy.verify(mame_kanji, 3, true)
gpu_proxy.verify(mame_kanji, 4, true)
gpu_proxy.verify(mame_kanji, 6, true)
gpu_proxy.is_verified()
assert(beeps == 1, "missing beep")
beeps = 0

tty:write("\a\a\a")
gpu_proxy.is_verified()
assert(beeps == 1, "missing beep")
beeps = 0

tty.setCursor(1, 1)
tty.window.nowrap = true
tty:write(("a"):rep(width*2)) -- nowrap
tty.window.nowrap = nil
gpu_proxy.verify(("a"):rep(width), 1, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write((" "):rep(width))
tty.setCursor(1, 1)
tty:write("ab123\tcd\tef\t")
gpu_proxy.verify("ab123   cd", 1, true)
gpu_proxy.verify("ef", 2, true)
gpu_proxy.is_verified()
assert((tty.getCursor()) == 9, "wrong x cursor position")
assert((select(2, tty.getCursor())) == 2, "wrong y cursor position")

tty.setCursor(1, 1)
tty:write("ab\r\n\rcd")
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 3, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("ab\n\r\ncd")
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 3, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("ab\r\r\ncd")
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 3, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("ab\n\r\rcd")
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 4, true)
gpu_proxy.is_verified()

tty.setCursor(1, 1)
tty:write("ab\r\r\rcd")
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 4, true)
gpu_proxy.is_verified()

--tty:write should remember the state of previous writes that did not complete sequences
--such sequences as \r\n
tty.setCursor(1, 1)
tty:write("ab\r")
tty:write("\ncd") -- SHOULD be one single newline
gpu_proxy.verify("ab", 1, true)
gpu_proxy.verify("cd", 2, true) -- this will fail at the time of this writing
gpu_proxy.is_verified()

-- color verification
gpu_proxy.setForeground(2)
tty.setCursor(1, 1)
tty:write("a")
gpu_proxy.setForeground(3)
tty:write("b")
gpu_proxy.setForeground(4)
tty:write("c")
gpu_proxy.match({txt="a",fg=2,bg=0}, 1, 1, true)
gpu_proxy.match({txt="b",fg=3,bg=0}, 2, 1, true)
gpu_proxy.match({txt="c",fg=4,bg=0}, 3, 1, true)
gpu_proxy.is_verified()
gpu_proxy.setForeground(1)

-- testing scrolling with wide char
tty.setCursor(1,height)
tty:write(mame_kanji:rep(width / 2))
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 1, height, false)
tty:write("a") -- drawing 'a' also scrolls, which also fills with space
gpu_proxy.verify("a"..(" "):rep(width - 1), height, true)
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 1, height - 1, true)
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 3, height - 1, true)
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 5, height - 1, true)
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 7, height - 1, true)
gpu_proxy.match({txt=mame_kanji,fg=1,bg=0}, 9, height - 1, true)
gpu_proxy.is_verified()

-- ansi escape mode testing
tty.setCursor(1, 1)
tty:write("\27[41mtest\27[40m") -- set background color to red, print hello, and reset
-- first just test the ansi escape codes are not printed
gpu_proxy.verify("test", 1, true)
gpu_proxy.is_verified()

-- now verify the color
tty.setCursor(1, 1)
tty:write("\27[41mtest\27[40m") -- set background color to red, print hello, and reset
gpu_proxy.match({txt="t",fg=1,bg=0xff0000}, 1, 1, true)
gpu_proxy.match({txt="e",fg=1,bg=0xff0000}, 2, 1, true)
gpu_proxy.match({txt="s",fg=1,bg=0xff0000}, 3, 1, true)
gpu_proxy.match({txt="t",fg=1,bg=0xff0000}, 4, 1, true)
gpu_proxy.is_verified()

-- verify multiple colors
tty.setCursor(1, 1)
tty:write("\27[32;41mtes\27[30;40mt") -- set background color to red, print hello, and reset
gpu_proxy.match({txt="t",fg=0x00ff00,bg=0xff0000}, 1, 1, true)
gpu_proxy.match({txt="e",fg=0x00ff00,bg=0xff0000}, 2, 1, true)
gpu_proxy.match({txt="s",fg=0x00ff00,bg=0xff0000}, 3, 1, true)
gpu_proxy.match({txt="t",fg=0x000000,bg=0x000000}, 4, 1, true)
gpu_proxy.is_verified()

-- verify failures
tty.setCursor(1, 1)
tty:write("\27[jm")
gpu_proxy.match({txt="\27",fg=1,bg=0}, 1, 1, true)
gpu_proxy.match({txt="[",fg=1,bg=0}, 2, 1, true)
gpu_proxy.match({txt="j",fg=1,bg=0}, 3, 1, true)
gpu_proxy.match({txt="m",fg=1,bg=0}, 4, 1, true)
gpu_proxy.is_verified()

end, debug.traceback)

tty.window = original_window
computer.beep = original_beep
testutil.assert("verifying pcall result", true, ok, why)
