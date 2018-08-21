--刀
local testutil = require("testutil");
local fs = require("filesystem")
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
    if name ~= "ops" and name ~= "mod" then
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

function pfs.remove(path)
  local segs = fs.segments(path)
  local last = table.remove(segs)
  local node = pfs.files
  for _,seg in ipairs(segs) do
    node = node and node[seg]
  end
  if node then
    node[last] = nil
  end
  return true
end

function pfs.isDirectory(path)
  local node = pfs.find(path)
  if not node then return false end
  if type(node) == "string" then return false end
  if node.file then return false end
  return true
end

function pfs.size(path)
  return pfs.data(path, "size", 0)
end

function pfs.lastModified(path)
  return pfs.data(path, "mod", 0)
end

function pfs.exists(path)
  return not not pfs.find(path)
end

function pfs.spaceTotal()
  return 79552
end

function pfs.spaceUsed()
  return 554433
end

local function F(size, mod)
  local obj = {
    file = true,
    size = size or 0,
    mod = math.max(1, mod or 1),
  }

  return obj
end

local function set_print(list)
  setmetatable(list, {__call = function(tbl, key)
    local decoration = ""
    if not tbl[key].file then
      for _,op in ipairs(tbl.ops or {}) do
        if op == "-p" then
          decoration = "/"
        end
      end
    end
    return "\27[" .. LSC[tbl[key].file and "fi" or "di"] .. "m" .. key .. decoration
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

local function remove_extra_offs(data)
  local current_index = 1
  local last_color
  while current_index <= #data do
    local i, e = data:find("\27%[[^m]*m", current_index)
    if not i then break end
    local color = data:sub(i, e)
    if last_color == OFF and color == OFF then
      data = data:sub(1, i - 1) .. data:sub(e + 1)
    end
    last_color = color
    current_index = i + 1
  end
  return data
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
    
    expected = R(expected)
    stdout_text = remove_extra_offs(R(stdout_text))

    if expected == stdout_text or stdout_text:match("^"..(text.escapeMagic(expected):gsub("\1", "%%s+")).."$") then
      testutil.bump(true)
    else
      testutil.assert("stdout mismatch", expected, stdout_text, S(7))
    end
    testutil.assert("stderr mismatch", "", stderr_text, S(7))
  end)

  assert(ok, "run crashed: " .. tostring(why))
end

local tmp_dir_path = mktmp('-d','-q')
local home = shell.getWorkingDirectory()
fs.mount(pfs, tmp_dir_path)
chdir(tmp_dir_path)

local ok, why = pcall(function()
  local list
  run({"--no-color", "-1"}, {}, "")
  run({"--no-color", "-1"}, {a=F(0)}, "a\n")
  run({}, {a=F(0)}, C("a", "fi").."\n")
  run({"-l"}, {a=F(7)}, OFF.."f-r- 7 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(71)}, OFF.."f-r- 71 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7111)}, OFF.."f-r- 7111 Dec 31 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*33)}, OFF.."f-r- 7 Dec 31 16:33 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 3600)}, OFF.."f-r- 7 Dec 31 17:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*8)}, OFF.."f-r- 7 Jan  1 00:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24)}, OFF.."f-r- 7 Jan  1 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24*32)}, OFF.."f-r- 7 Feb  1 16:00 "..C("a", "fi").."\n")
  run({"-l"}, {a=F(7, 60*60*24*32*11)}, OFF.."f-r- 7 Dec 18 16:00 "..C("a", "fi").."\n")
  run({"--no-color", "-1"}, {a={}}, "a\n")
  run({"--no-color", "-1", "-p"}, {a={}}, "a/\n")

  list = {a={},b=F(0),c={},d=F(0),e={},f=F(0),g={},h=F(0),i={},j=F(0),k={},l=F(0),m={},n=F(0),o={},p=F(0),q={},r=F(0),s={}}
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

  list = {a=F(0),b12345678901234={},c=F(0),d=F(0),}
  run({"--no-color"}, list, "a                c\nb12345678901234  d\n")
  run({"--no-color", "-p"}, list, "a\nb12345678901234/\nc\nd\n")

  list = {a=F(0),b12345678901234={mod=2},c=F(0, 3),d=F(0, 4),}
  run({"--no-color", "-l"}, list, "f-r- 0 Dec 31 16:00 a\nd-r- 0 Dec 31 16:00 b12345678901234\nf-r- 0 Dec 31 16:00 c\nf-r- 0 Dec 31 16:00 d\n")
  list = {a=F(0)}
  run({"--no-color", "-l", "--full-time"}, list, "f-r- 0 1969-12-31 16:00:01 a\n")
  list = {a=F(0, 60*60*(8+24*400) + 4321)}
  run({"--no-color", "-l", "--full-time"}, list, "f-r- 0 1971-02-05 01:12:01 a\n")

  list = {foo=F(375)}
  -- grouped lists
  do
    local line = "f-r- 375 Dec 31 16:00 foo\n"
    run({"--no-color", "-l", "."}, list, line)
    run({"--no-color", "-l", ".", "."}, list, ".:\n" .. line .. ".:\n" .. line)
    run({"--no-color", "-l", ".", "./."}, list, ".:\n" .. line .. "./.:\n" .. line)
    run({"--no-color", "-l", "./.", "."}, list, "./.:\n" .. line .. ".:\n" .. line)
  end

  pfs.ro = false
  run({"-l"}, {a=F(7)}, OFF.."f-rw 7 Dec 31 16:00 "..C("a", "fi").."\n")

  --msft
  list = {a={mod=1},b=F(0),c=F(1),d=F(2),e=F(4)}
  run({"-l", "-M"}, list,
    OFF.."d-rw 0 Dec 31 16:00 "..C("a", "di").."\n"..
         "f-rw 0 Dec 31 16:00 "..C("b", "fi").."\n"..
         "f-rw 1 Dec 31 16:00 "..C("c", "fi").."\n"..
         "f-rw 2 Dec 31 16:00 "..C("d", "fi").."\n"..
         "f-rw 4 Dec 31 16:00 "..C("e", "fi").."\n"..
         "    4 File(s) 7 bytes\n"..
         "    1 Dir(s)\1-474881 bytes free\n"
  )

  run({"-l", "-M", ".", "."}, list,
    OFF..".:\n"..
         "d-rw 0 Dec 31 16:00 "..C("a", "di").."\n"..
         "f-rw 0 Dec 31 16:00 "..C("b", "fi").."\n"..
         "f-rw 1 Dec 31 16:00 "..C("c", "fi").."\n"..
         "f-rw 2 Dec 31 16:00 "..C("d", "fi").."\n"..
         "f-rw 4 Dec 31 16:00 "..C("e", "fi").."\n"..
         "    4 File(s) 7 bytes\n"..
         "    1 Dir(s)\1-474881 bytes free\n\n"..
         ".:\n"..
         "d-rw 0 Dec 31 16:00 "..C("a", "di").."\n"..
         "f-rw 0 Dec 31 16:00 "..C("b", "fi").."\n"..
         "f-rw 1 Dec 31 16:00 "..C("c", "fi").."\n"..
         "f-rw 2 Dec 31 16:00 "..C("d", "fi").."\n"..
         "f-rw 4 Dec 31 16:00 "..C("e", "fi").."\n"..
         "    4 File(s) 7 bytes\n"..
         "    1 Dir(s)\1-474881 bytes free\n"..
         "Total Files Listed:\n"..
         "    8 File(s) 14 bytes\n"..
         "    2 Dir(s)\1-474881 bytes free\n"
  )

  list = {a={b=F(1), c=F(2)}}
  run({"--no-color", "-p", "a"}, list, "b  c\n")
  run({"--no-color", "-p", ".", "a"}, list, ".:\na/\n\na:\nb  c\n")
  run({"--no-color", "-M", ".", "a"}, list,
    ".:\na\n    0 File(s) 0 bytes\n    1 Dir(s)\1-474881 bytes free\n\n"..
    "a:\nb  c\n    2 File(s) 3 bytes\n    0 Dir(s)\1-474881 bytes free\nTotal Files Listed:\n"..
    "    2 File(s) 3 bytes\n    1 Dir(s)\1-474881 bytes free\n"
  )
  run({"--no-color", "-p", "-R"}, list, ".:\na/\n\n./a/:\nb  c\n")
  run({"--no-color", "-p", "-R", "."}, list, ".:\na/\n\n./a/:\nb  c\n")
  run({"--no-color", "-p", "-R", ".", "a"}, list, ".:\na/\n\n./a/:\nb  c\n\na:\nb  c\n")
  run({"--no-color", "-p", "-R", ".", "./././a/"}, list, ".:\na/\n\n./a/:\nb  c\n\n./././a/:\nb  c\n")
  run({"--no-color", "-p", "-R", ".", "./././a/", "./a/b"}, list, "./a/b\n.:\na/\n\n./a/:\nb  c\n\n./././a/:\nb  c\n")
  
  -- link testing
  -- getting a pseudo filesystem to declare its own symlinks takes a bit of tricky
  list = {a={mod=1,b=F(1)}}
  fs.link("a", tmp_dir_path .. "/l")
  run({"--no-color", "-l"}, list, "d-rw 0 Dec 31 16:00 a\nl-rw 0 Dec 31 16:00 l -> a/\n")
  run({"--no-color", "-l", "l"}, list, "f-rw 1 Dec 31 16:00 b\n")
  fs.remove(tmp_dir_path .. "/l")

end)

chdir(home)
fs.umount(tmp_dir_path)
fs.remove(tmp_dir_path)
assert(ok, why)
