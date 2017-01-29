  local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local sh = require("sh")
local term = require("term")
local unicode = require("unicode")
local process = require("process")

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.assert_process_output("echo hi", "hi\n")

local test_dir = os.getenv("PWD")
local chdir = shell.setWorkingDirectory

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local touch = loadfile(shell.resolve("touch", "lua"))
if not touch then
  io.stderr:write("bash-test requires touch which could not be found\n")
  return
end

local function word(txt, qri)
  return
  {{
    txt=txt,
    qr=qri and ({{"'","'",true},{'"','"'}})[qri]
  }}
end

-- glob as action!
local function pc(file_prep, input, exp)
  local tp = mktmp('-d','-q')
  chdir(tp)

  file_prep = file_prep or {}
  for _,file in ipairs(file_prep) do
    local f = tp..'/'..file
    if f:sub(-1) == '/' then
      os.execute("mkdir " .. f)
    else
      touch(f)
    end
  end

  local status, result = pcall(function()
    c = table.pack(sh.internal.parseCommand(input))
    if c[1] == nil then
      return nil, c[2]
    end
    return c
  end)

  chdir(test_dir)
  fs.remove(tp)

  result = (exp == nil and result == nil) and 'nil' or result
  exp = exp or 'nil'
  testutil.assert('pc:'..ser(input)..ser(file_prep),status and exp or '',result,ser(result))
end

local echo_pack = {"echo",{},n=3}
pc({}, {word('echo')}, echo_pack)
pc({'echo'}, {word('*')}, echo_pack)

echo_pack[2][1]='echo'
pc({'echo'}, {word('*'),word('*')}, echo_pack)
pc({}, {word('echo'),word('echo')}, echo_pack)
echo_pack[2][1]=';'
pc({}, {word('echo'),word(';',2)}, echo_pack)

local tmp_path = mktmp('-d','-q')

local function ls(args, output)
  testutil.assert_process_output(string.format("ls -p %s", args or ""), output)
end

ls(tmp_path, "")

touch(tmp_path .. "/a")
ls(tmp_path, "a\n")

touch(tmp_path .. "/b")
ls(tmp_path, "a\nb\n") -- ls without tty is ls -1

ls(tmp_path .. ' ' .. tmp_path, 
  string.format("%s:\na\nb\n\n%s:\na\nb\n", tmp_path, tmp_path))

os.execute("mkdir " .. tmp_path .. "/c")
ls(tmp_path, "a\nb\nc/\n")

ls(" -R " .. tmp_path, 
  string.format("%s:\na\nb\nc/\n\n%s/c/:\n", tmp_path, tmp_path))

ls(tmp_path, "a\nb\nc/\n")
touch(tmp_path .. "/.d")
ls(tmp_path, "a\nb\nc/\n")
ls("-a " .. tmp_path, "a\nb\nc/\n.d\n")

ls(string.format("%s/a %s/b", tmp_path, tmp_path), 
  string.format("%s/a\n%s/b\n", tmp_path, tmp_path))
ls("-a " .. tmp_path, "a\nb\nc/\n.d\n")

touch(tmp_path .. "/.e")
os.execute("mkdir " .. tmp_path .. "/.f")
ls(tmp_path, "a\nb\nc/\n")
ls("-a " .. tmp_path, "a\nb\nc/\n.d\n.e\n.f/\n")

fs.remove(tmp_path)

local function glob(str, files, exp, bPrefixAbsPath)
  local tp = mktmp('-d','-q')
  chdir(tp)

  files = files or {}
  for _,file in ipairs(files) do
    local f = tp..'/'..file
    if f:sub(-1) == '/' then
      os.execute("mkdir " .. f)
    else
      touch(f)
    end
  end

  if bPrefixAbsPath then
    str = text.escapeMagic(tp..'/')..str
    for i,v in ipairs(exp) do
      exp[i] = tp..'/'..v
    end
  end

  local status, result = pcall(function() return sh.internal.glob(str) end)

  chdir(test_dir)
  fs.remove(tp)

  local tmp = {}
  for _,file in ipairs(exp) do
    tmp[file] = true
  end
  exp = tmp
  tmp = {}
  for _,file in ipairs(result) do
    if not exp[file] then
      tmp[file] = true
    end
    exp[file] = nil
  end
  result = tmp

  testutil.assert('glob missing files:'..str..ser(exp),not next(exp),true)
  testutil.assert('glob extra files:'..str..ser(result),not next(result),true)
end

-- glob input must already be pattern ready
-- evaluate will be calling glob, and eval prepares the glob pattern
glob('foobar', {}, {})
glob([[foobar.*]], {'foobarbaz'}, {'foobarbaz'})
glob([[foobar.*]], {'.foobarbaz','foobarbaz'}, {'foobarbaz'})
glob([[foobar.*]], {'.foobarbaz','foobar','foobarbaz'}, {'foobar','foobarbaz'})
glob([[%.foobar.*]], {'.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})
glob([[%..*]], {'.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})
glob([[%.f.*]], {'fff','.b','.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})
glob([[.*]], {'.a','.b'}, {})
glob([[%..*]], {'.a','.b'}, {'.a','.b'})

glob('a.*/b.*',{'a1/','a2/','a1/b1','a1/b2','a2/b3','a2/b4'},{'a1/b1','a1/b2','a2/b3','a2/b4'})
glob('a.*/b1',{'a1/','a2/','a1/b1','a1/b2','a2/b1','a2/b2'},{'a1/b1','a2/b1'})
glob('a1/b.*',{'a1/','a2/','a1/b1','a1/b2','a2/b1','a2/b2'},{'a1/b1','a1/b2'})
glob('a.*/c.*',{'a1/','a2/','a1/b1','a1/b2','a2/b3','a2/b4'},{})
glob('.*/.*/.*%.lua',{'a/','a/1.lua','b/','b/q/','b/q/1.lua'},{'b/q/1.lua'})
glob('.*/.*/.*%.lua',{'a/','a/dir.lua/','b/','b/q/','b/q/1.lua'},{'b/q/1.lua'})
glob('.*/.*/.*%.lua',{'a/','a/w/','a/w/dir.lua/','a/w/dir.lua/data','b/','b/q/','b/q/1.lua'},{'a/w/dir.lua','b/q/1.lua'})
glob('.*/.*/.*',{'a1/','a1/.b1/','a1/.b1/c'},{})
glob('.*/%..*/.*',{'a1/','a1/.b1/','a1/.b1/c'},{'a1/.b1/c'})

-- now glob * where no files exist
glob([[foobaz*]], {}, {})

-- glob should not remove absolute path
glob('.*', {'a','b','c'}, {'a','b','c'}, true)

-- glob for all the hard things (magic chars)
-- ().%+-*?[^$
-- having trouble testing on windows the following magic chars
-- ().*?
local magicfiles =
{
  'fao$',
  'fbo%',
  'fco+',
  'fdo-',
  'feo[',
  'ffo^',
}
glob([[f.o.*]], magicfiles, magicfiles)

local buffer_test_file = mktmp('-q')
local f = io.open(buffer_test_file, "w")

local buf_size = f.bufferSize

f:write(("0"):rep(buf_size))
f:write("\n"..("1"):rep(buf_size-1))
f:write("\r"..("2"):rep(buf_size-2).."\r")
f:write("\n"..("3"):rep(buf_size-3).."\r\n")
f:write("\r"..("4"):rep(buf_size-2).."\r")
f:write("\r"..("5"):rep(buf_size-2).."\n")
f:write("6\r")
f:write("7\n")
f:write("8\r\n")
f:write("9\r\r")
f:write("A\n\r\n")

f:close()

function read_line_test(next_line, ending, chop)
  local code = "l"
  if not chop and next_line then
    code = "L"
    next_line = next_line .. ending
  end
  local actual = f:read("*"..code)

  if actual ~= next_line then
    print("bad line", '|'..(actual or "nil"):sub(1,3)..'|', '|'..(next_line or "nil"):sub(1,3)..'|', chop)
  end

end

function read_chop_test(chop)
  f = io.open(buffer_test_file)
  read_line_test(("0"):rep(buf_size), "\n", chop)
  read_line_test(("1"):rep(buf_size-1), "\r", chop)
  read_line_test(("2"):rep(buf_size-2), "\r\n", chop)
  read_line_test(("3"):rep(buf_size-3), "\r\n", chop)
  read_line_test("", "\r", chop)
  read_line_test(("4"):rep(buf_size-2), "\r", chop)
  read_line_test("", "\r", chop)
  read_line_test(("5"):rep(buf_size-2), "\n", chop)
  read_line_test("6", "\r", chop)
  read_line_test("7", "\n", chop)
  read_line_test("8", "\r\n", chop)
  read_line_test("9", "\r", chop)
  read_line_test("", "\r", chop)
  read_line_test("A", "\n", chop)
  read_line_test("", "\r\n", chop)
  read_line_test(nil)
  f:close()
end

read_chop_test(true)
read_chop_test(false)

-- let's test all the same type of things but with only newlines
f = io.open(buffer_test_file, "w")
buf_size = f.bufferSize

f:write(("0"):rep(buf_size))
f:write("\n"..("1"):rep(buf_size-1))
f:write("\n"..("2"):rep(buf_size-2).."\n")
f:write(("3"):rep(buf_size-2).."\n\n")
f:write(("4"):rep(buf_size-1).."\n")
f:write("\n"..("5"):rep(buf_size-2).."\n")
f:write("6\n")
f:write("7\n")
f:write("8\n\n")
f:write("9\n\n")
f:write("A\n\n\n")

f:close()

function read_line_test(next_line, ending, chop)
  local code = "l"
  if not chop and next_line then
    code = "L"
    next_line = next_line .. ending
  end
  local actual = f:read("*"..code)

  if actual ~= next_line then
    print("bad sline", '|'..(actual or "nil"):sub(1,3)..'|', '|'..(next_line or "nil"):sub(1,3)..'|', chop)
  end

end

function simple_read_chop_test(chop)
  f = io.open(buffer_test_file)
  read_line_test(("0"):rep(buf_size), "\n", chop)
  read_line_test(("1"):rep(buf_size-1), "\n", chop)
  read_line_test(("2"):rep(buf_size-2), "\n", chop)
  read_line_test(("3"):rep(buf_size-2), "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test(("4"):rep(buf_size-1), "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test(("5"):rep(buf_size-2), "\n", chop)
  read_line_test("6", "\n", chop)
  read_line_test("7", "\n", chop)
  read_line_test("8", "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test("9", "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test("A", "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test("", "\n", chop)
  read_line_test(nil)
  f:close()
end

simple_read_chop_test(true)
simple_read_chop_test(false)

fs.remove(buffer_test_file)
