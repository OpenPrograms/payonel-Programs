--刀
local testutil = require("testutil");
local fs = require("filesystem")
local unicode = require("unicode")
local term = require("term")
local process = require("process")
local shell = require("shell")
local text = require("text")
local tx = require("transforms")
local log = require("component").sandbox.log

testutil.asserts = 0

local ls = assert(loadfile(shell.resolve("ls", "lua")))
local mktmp = assert(loadfile(shell.resolve('mktmp','lua')))
local chdir = shell.setWorkingDirectory

local LSC = tx.foreach(text.split(os.getenv("LS_COLORS") or "", {":"}, true), function(e)
  local parts = text.split(e, {"="}, true)
  return parts[2], parts[1]
end)

local OFF = "\27[m"

local function C(data, ext)
  return "\27[" .. LSC[ext] .. "m" .. data .. OFF
end

local viewport_width = 20
local viewport_height = 10

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
    if name ~= "ops" then
      table.insert(names, name)
    end
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

local function F(size, mod)
  local obj = {
    dir = size == nil,
    size = size,
    mod = mod,
  }

  return obj
end

local function set_print(list)
  setmetatable(list, {__call = function(tbl, key)
    local decoration = ""
    if tbl[key].dir then
      for _,op in ipairs(tbl.ops or {}) do
        if op == "-p" then
          decoration = "/"
        end
      end
    end
    return "\27[" .. LSC[tbl[key].dir and "di" or "fi"] .. "m" .. key .. decoration
  end})
end

local function S(n)
  n = n or 1
  local reader = text.internal.reader(debug.traceback())
  local lines = {}
  for line in reader:lines() do
    table.insert(lines, line)
  end
  reader:close()
  return lines[n]:match("([^/]+): ")
end

local function R(data)
  local final = "%s*\n"
  local capture = "(.)"
  local literal_off = OFF:gsub("%[", "%%[")
  if data:match(literal_off .. final) then
    capture = "%s*(" .. literal_off .. ")"
  end
  return (data:gsub(capture .. final, "%1\n"))
end

local function run(ops, files, expected)
  pfs.files = files

  local ok, why = pcall(function()

    local stdout_text = ""
    local stderr_text = ""

    local pthread = process.load(function()
      local stdout = text.internal.writer(function(data)
        stdout_text = data
      end)
      stdout.tty = true
      stdout.stream.tty = true -- behave like we have tty
      io.output(stdout)
      local stderr = text.internal.writer(function(data)
        stderr_text = data
      end)
      stdout.stream.tty = true -- behave like we have tty
      io.error(stderr)
      ls(table.unpack(ops))
    end)

    --create test window
    local window = term.internal.open(0, 0, viewport_width, viewport_height)
    process.list[pthread].data.window = window

    --run ls
    process.internal.continue(pthread)
    testutil.assert("stdout mismatch", R(expected), R(stdout_text), S(7))
    testutil.assert("stderr mismatch", "", stderr_text, S(7))
  end)

  assert(ok, "run crashed: " .. tostring(why))
end

local tmp_dir_path = mktmp('-d','-q')
local home = shell.getWorkingDirectory()
fs.mount(pfs, tmp_dir_path)
chdir(tmp_dir_path)

local ok, why = pcall(function()
  run({"--no-color", "-1"}, {}, "")
  run({"--no-color", "-1"}, {a=F(0)}, "a\n")
  run({}, {a=F(0)}, C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 1)}, OFF.."f-r- 7 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(71, 1)}, OFF.."f-r- 71 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7111, 1)}, OFF.."f-r- 7111 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*33)}, OFF.."f-r- 7 Dec 31 16:33 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 3600)}, OFF.."f-r- 7 Dec 31 17:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*8)}, OFF.."f-r- 7 Jan  1 00:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24)}, OFF.."f-r- 7 Jan  1 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24*32)}, OFF.."f-r- 7 Feb  1 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24*32*11)}, OFF.."f-r- 7 Dec 18 16:00 "..C("a", "fi").."\n")
  run({"--no-color", "-1"}, {a=F()}, "a\n")
  run({"--no-color", "-1", "-p"}, {a=F()}, "a/\n")

  local list = {a=F(),b=F(0),c=F(),d=F(0),e=F(),f=F(0),g=F(),h=F(0),i=F(),j=F(0),k=F(),l=F(0),m=F(),n=F(0),o=F(),p=F(0),q=F(),r=F(0),s=F()}
  set_print(list)
  run({"--no-color", "-1"}, list, "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np\nq\nr\ns\n")
  run({"--no-color", "-1", "-p"}, list, "a/\nb\nc/\nd\ne/\nf\ng/\nh\ni/\nj\nk/\nl\nm/\nn\no/\np\nq/\nr\ns/\n")
  run({"--no-color"}, list, "a  e  i  m  q\nb  f  j  n  r\nc  g  k  o  s\nd  h  l  p\n")
  run({"--no-color", "-p"}, list, "a/  e/  i/  m/  q/\nb   f   j   n   r\nc/  g/  k/  o/  s/\nd   h   l   p\n")

  run({}, list, 
    string.format("%s  %s  %s  %s  %s\n%s  %s  %s  %s  %s\n%s  %s  %s  %s  %s\n%s  %s  %s  %s\n",
    list('a'),list('e'),list('i'),list('m'),list('q')..OFF,
    list('b'),list('f'),list('j'),list('n'),list('r')..OFF,
    list('c'),list('g'),list('k'),list('o'),list('s')..OFF,
    list('d'),list('h'),list('l'),list('p')..OFF
  ))
  list.ops = {"-p"}
  run(list.ops, list,
    string.format("%s  %s  %s  %s  %s\n%s   %s   %s   %s   %s\n%s  %s  %s  %s  %s\n%s   %s   %s   %s\n",
    list('a'),list('e'),list('i'),list('m'),list('q')..OFF,
    list('b'),list('f'),list('j'),list('n'),list('r')..OFF,
    list('c'),list('g'),list('k'),list('o'),list('s')..OFF,
    list('d'),list('h'),list('l'),list('p')..OFF
  ))

  list = {a=F(0),b12345678901234=F(),c=F(0),d=F(0),}
  run({"--no-color"}, list, "a                c\nb12345678901234  d\n")
  run({"--no-color", "-p"}, list, "a\nb12345678901234/\nc\nd\n")
  
end)

chdir(home)
fs.umount(tmp_dir_path)
fs.remove(tmp_dir_path)
assert(ok, why)
