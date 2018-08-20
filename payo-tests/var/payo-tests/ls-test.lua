--刀
local testutil = require("testutil");
local fs = require("filesystem")
local unicode = require("unicode")
local term = require("term")
local process = require("process")
local shell = require("shell")
local text = require("text")
local log = require("component").sandbox.log

testutil.asserts = 0

local ls = assert(loadfile(shell.resolve("ls", "lua")))
local mktmp = assert(loadfile(shell.resolve('mktmp','lua')))
local chdir = shell.setWorkingDirectory

local real_gpu = term.gpu()

local viewport_width = 20
local viewport_height = 10
local viewport = {}

local pfs = setmetatable({
  address = "pfs",
  files = {},
  ro = true,
}, {__index=function(_, ...)
  log("pfs missing", ...)
end})

function pfs.find(path)
  local segs = fs.segments(path)
  local node = pfs.files
  for _,seg in ipairs(segs) do
    node = node and node[seg]
  end
  return node
end

function pfs.list(path)
  local node = pfs.find(path)
  if not node then return {} end
  local names = {}
  for name in pairs(node) do
    table.insert(names, name)
  end
  return names
end

function pfs.data(path, key, def)
  local node = pfs.find(path)
  return node and node[key] or def
end

function pfs.isReadOnly()
  return pfs.ro
end

function pfs.isDirectory(path)
  return pfs.data(path, "dir", false)
end

function pfs.size(path)
  return pfs.data(path, "size", 0)
end

function pfs.lastModified(path)
  return pfs.data(path, "mod", 0)
end

local function F(dir, size, mod)
  return {
    dir = dir,
    size = size,
    mod = mod,
  }
end

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
  setResolution = function() assert(false, "cannot setResolution") end,
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
  test_gpu.fg = c
end
function test_gpu.setBackground(c)
  test_gpu.bg = c
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

local function run(ops, files, output)
  pfs.files = files
  local tmp_stderr_file = mktmp('-q')

  local ok = pcall(function()

    local stdout_text = ""

    local pthread = process.load(function()
      local stdout = text.internal.writer(function(data)
        stdout_text = data
      end)
      stdout.stream.tty = true -- behave like we have tty
      io.output(stdout)
      io.write("test")
      io.error(tmp_stderr_file)
      ls(table.unpack(ops))
    end)

    --create test window
    local window = term.internal.open(0, 0, viewport_width, viewport_height)
    process.list[pthread].data.window = window
    term.bind(test_gpu, window)

    --run ls
    process.internal.continue(pthread)
    viewport_verify(output)
    log({stdout_text})
  end)

  fs.remove(tmp_stderr_file)
  assert(ok, "something crashed")
end

local tmp_dir_path = mktmp('-d','-q')
local home = shell.getWorkingDirectory()
fs.mount(pfs, tmp_dir_path)
chdir(tmp_dir_path)

pcall(function()
  run({"--no-color", "-a", "-1"}, {}, {})
  run({"--no-color", "-a", "-1"}, {a=F()}, {"a"})
  run({}, {a=F()}, {"a"})
  run({"-l"}, {a=F(false, 7, 1)}, {
    "f-r- 7 Dec 31 16:00",
    "a",
  })
  run({"-l"}, {a=F(false, 71, 1)}, {
    "f-r- 71 Dec 31 16:00",
    " a",
  })
  run({"-l"}, {a=F(false, 7111, 1)}, {
    "f-r- 7111 Dec 31 16:",
    "00 a",
  })
end)

chdir(home)
fs.umount(tmp_dir_path)
fs.remove(tmp_dir_path)

