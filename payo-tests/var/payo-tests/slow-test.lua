local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local sh = dofile("/lib/sh.lua")
local term = require('term')

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.assert_process_output("echo hi", "hi\n")

local test_dir = os.getenv("PWD")

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
  os.execute("cd " .. tp)

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

  os.execute("cd " .. test_dir)
  fs.remove(tp)

  result = (exp == nil and result == nil) and 'nil' or result
  exp = exp or 'nil'
  testutil.assert('pc:'..ser(input)..ser(file_prep),status and exp or '',result,ser(result))
end

local echo_pack = {"/bin/echo.lua",{},[3]={},n=3}
pc({}, {word('xxxx')}, nil)
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
  os.execute("cd " .. tp)

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

  os.execute("cd " .. test_dir)
  fs.remove(tp)

  testutil.assert('glob:'..str..ser(files),status and exp or '',result)
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

local grep_tmp_file = mktmp('-q')
local file = io.open(grep_tmp_file, "w")
file:write("hi\n") -- whole word and whole line
file:write("hi world\n")
file:write(" hi \n") -- whole word
file:write("not a match\n")
file:write("high\n") -- not whole word
file:write("hi foo hi bar\n")
file:close()

function grep(pattern, options, result)
  local label = pattern..':'..options..':'..table.concat(result,'|')
  local g = io.popen("grep "..pattern.." "..grep_tmp_file.." "..options, "r")
  while true do
    local line = g:read("*l")
    if not line then break end
    local next = table.remove(result, 1)
    testutil.assert("grep "..label, line, next)
  end
  g:close()
  testutil.assert("not all grep results found "..label, #result, 0)
end

grep("hi", "", {"hi", "hi world", " hi ", "high", "hi foo hi bar"})
grep("hi", "-w", {"hi", "hi world", " hi ", "hi foo hi bar"})
grep("hi", "-wt", {"hi", "hi world", "hi", "hi foo hi bar"})
grep("hI", "-wti", {"hi", "hi world", "hi", "hi foo hi bar"})
grep("hI", "-wtiv", {"not a match", "high"})
grep("hI", "-wix", {"hi"})
grep("hI", "-wixv", {"hi world", " hi ", "not a match", "high", "hi foo hi bar"})
grep("hI", "-wiv", {"not a match", "high"})
grep("hI", "-ion", {"1:hi", "2:hi", "3:hi", "5:hi", "6:hi", "6:hi"})

fs.remove(grep_tmp_file)

-- read line testing

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

function rtest(cmd, files, ex_out)
  local clean_dir = mktmp('-d','-q')
  os.execute("cd " .. clean_dir)

  local sub = io.popen(cmd)
  local out = sub:read("*a")
  sub:close()

  local file_data = {}

  for n,c in pairs(files) do
    local f, reason, x = io.open(clean_dir .. "/" .. n, "r")
    if not f then
      file_data[n] = false
    else
      file_data[n] = f:read("*a")
      f:close()
      fs.remove(clean_dir .. "/" .. n)
    end
  end

  local junk_files = fs.list(clean_dir)
  while true do
    local junk = junk_files()
    if not junk then break end
    file_data[junk] = false
    fs.remove(clean_dir .. "/" .. junk)
  end

  os.execute("cd " .. os.getenv("OLDPWD"))
  os.execute("rmdir " .. clean_dir)

  for k,v in pairs(file_data) do
    local expected_data = files[k]
    if v == false then
      if expected_data then
        testutil.assert("rtest:"..cmd, k, "file missing")
      else
        testutil.assert("rtest:"..cmd, k, "file should not exist")
      end
    else
      testutil.assert("rtest:"..cmd, expected_data, v)
    end
  end

  testutil.assert("rtest:"..cmd.." leak", ex_out or "", out)
end

rtest("echo hi", {}, "hi\n")
rtest("echo hi>a", {a="hi\n"})
rtest("echo hi>>a", {a="hi\n"})
rtest("echo hi>>a;echo hi>>a", {a="hi\nhi\n"})
rtest("echo hi>>a;echo hi>a", {a="hi\n"})
rtest("echo hi>a;echo hi>a", {a="hi\n"})
local ioh = "/var/payo-tests/iohelper.lua "
rtest(ioh.."w a|"..ioh.."r>b", {b="a"})
rtest(ioh.."W a|"..ioh.."R|"..ioh.." r>b", {b="a"})
rtest(ioh.."W a|"..ioh.."R w j|"..ioh.." R r>b", {b="a\nj"})
rtest("echo stuff>a;"..ioh.." R<a>b;echo j>>b", {a="stuff\n",b="stuff\nj\n"})
rtest("echo hello > a|"..ioh.." r", {a="hello\n"}, "[nil]")
rtest(ioh.."w hello > a|"..ioh.." r", {a="hello"}, "[nil]")
rtest(ioh.."w 1 > a|"..ioh.."w 2 > b|"..ioh.."w 3 > c", {a="1",b="2",c="3"}, "")

