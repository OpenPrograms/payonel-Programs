local testutil = require("testutil");
local fs = require("filesystem")
local unicode = require("unicode")
local term = require("term")
local process = require("process")
local shell = require("shell")
local log = require("component").sandbox.log

local ls = shell.resolve("ls", "lua")
if not ls then
  io.stderr:write("ls-test requires ls which could not be found\n")
  return
end

local mktmp = loadfile(shell.resolve('mktmp','lua'))
if (not mktmp) then
  io.stderr:write("testutils requires mktmp which could not be found\n")
  return false
end
local chdir = shell.setWorkingDirectory

local real_gpu = term.gpu()

local viewport_width = 20
local viewport_height = 10
local viewport = string.rep(" ", viewport_width * viewport_height)

local function xy_to_index(x, y)
  if y < 1 then return 1 end
  if x > viewport_width then
    x, y = 1, y + 1
  end
  if y > viewport_height then return #viewport+1 end
  if x < 1 then x = 1 end
  return x + ((y - 1) * viewport_width)
end

local function truncate(x, width)
  if x > viewport_width or width < 0 then return end
  local new_x = math.max(x, 1)
  return new_x, math.min(width - new_x + x, viewport_width - new_x + 1)
end

local function show_viewport(...)
  log(unicode.char(0x2552) .. unicode.char(0x2550):rep(viewport_width) .. unicode.char(0x2555))
  for yi=1,viewport_height do
    local from = xy_to_index(1, yi)
    local to = xy_to_index(viewport_width, yi)
    log(unicode.char(0x2502) .. viewport:sub(from, to) .. unicode.char(0x2502))
  end
  log(unicode.char(0x2514) .. unicode.char(0x2500):rep(viewport_width) .. unicode.char(0x2518))
end

local test_gpu = setmetatable({
  setResolution = function() assert(false, "cannot setResolution") end
 ,setViewport = function() assert(false, "cannot setViewport") end
 ,getScreen = real_gpu.getScreen
 ,set = function(x, y, data)
    local value = data
    if y < 1 or y > viewport_height then
      return
    end
    local start_x, write_width = truncate(x, #data)
    if not start_x or write_width < 1 then return end
    local write_value = value:sub(start_x - x + 1):sub(1, write_width)
    viewport = viewport:sub(1, xy_to_index(start_x, y) - 1) .. write_value .. viewport:sub(xy_to_index(start_x + write_width, y))
  end
 ,setForeground = function(...) log("calling setForeground", ...) end
 ,setBackground = function(...) log("calling setBackground", ...) end
 ,copy = function(x, y, width, height, dx, dy)
    if x > viewport_width or y > viewport_height or (x + width) < 1 or (y + height) < 1 then
      return
    end
    local buffer = {}
    if dx == 0 and dy == 0 then return end
    local adjusted_x, adjusted_width = truncate(x, width)
    local adjusted_y = math.max(y, 1)
    local adjusted_height = height - adjusted_y + y
    if adjusted_width < 1 or adjusted_height < 1 then return end
    for yi=adjusted_y,adjusted_y+adjusted_height do
      table.insert(buffer, viewport:sub(xy_to_index(adjusted_x, yi)):sub(1, adjusted_width))
    end
    for yi=adjusted_y,adjusted_y+adjusted_height do
      term.gpu().set(adjusted_x + dx, yi + dy, buffer[yi - adjusted_y + 1])
    end
  end
 ,fill = function(x, y, width, height, char)
    local brush = unicode.sub(char, 1, 1):rep(width)
    for yi=y,y+height-1 do
      term.gpu().set(x, yi, brush)
    end
  end
}, {__index=function(_, ...)
  log("missing gpu method", ...)
end})

local function prepare_files(files)
  local tmp_dir_path = mktmp('-d','-q')
  local home = shell.getWorkingDirectory()
  chdir(tmp_dir_path)

  

  chdir(home)
  return tmp_dir_path
end

local function run(ops, files, output)
  local tmp_dir_path = prepare_files(files)
  local home = shell.getWorkingDirectory()
  chdir(tmp_dir_path)

  local ok = pcall(function()
    --create ls test process
    local pthread = process.load(ls)

    --create test window
    local window = term.internal.open(0, 0, viewport_width, viewport_height)
    process.list[pthread].data.window = window
    term.bind(test_gpu, window)

    --run ls
    process.internal.continue(pthread, table.unpack(ops))
    show_viewport()
  end)

  --compare output
  chdir(home)
  fs.remove(tmp_dir_path)

  assert(ok, "something crashed")
end

run({"--no-color", "-a", "-1"}, {}, [[
                    
                    
                    
                    
                    
                    
                    
                    
                    
                    ]])
--run({"--no-color", "-a", "-1"}, {"a"}, "a\n")
