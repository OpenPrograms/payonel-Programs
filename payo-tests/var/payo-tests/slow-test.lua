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
local guid = require("guid")
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

local echo_pack = {"/bin/echo.lua",{},n=2}
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

function cmd_test(cmds, files, meta)
  meta = meta or {}
  local exit_code = meta.exit_code
  local tmp_dir_path = mktmp('-d','-q')
  chdir(tmp_dir_path)

  local stdouts = {}
  local stderrs = {}

  local stdout = setmetatable({write = function(self, v)
    if #v > 0 then table.insert(stdouts,v) end
  end}, {__index = io.stdout})

  local stderr = setmetatable({write = function(self, v)
    if #v > 0 then table.insert(stderrs,v) end
  end}, {__index = io.stderr})

  for _,c in ipairs(cmds) do
    if type(c) == "string" then
      local fp = function()os.execute(c)end
      local proc = process.load(fp,nil,nil,"cmd_test:"..c)
      process.info(proc).data.io[1] = stdout
      process.info(proc).data.io[2] = stderr
      while coroutine.status(proc) ~= "dead" do
        coroutine.resume(proc)
      end
    else
      c()
    end
  end

  actual = {}
  local scan = nil
  scan = function(d)
    for it in fs.list(d) do
      local path = (d .. '/' .. it):gsub("/+", "/")
      local key = path:sub(unicode.len(tmp_dir_path)+1):gsub("/*$",""):gsub("^/*", "")
      path = shell.resolve(path)
      if fs.isLink(path) then
        actual[key] = false
      elseif fs.isDirectory(path) then
        actual[key] = true
        scan(path)
      else
        local fh = io.open(path)
        actual[key] = fh:read("*a")
        fh:close()
      end
    end
  end
  
  scan(tmp_dir_path)
  fs.remove(tmp_dir_path)

  local details = ' cmds:' .. ser(cmds,true)
  
  for name,contents in pairs(actual) do
    testutil.assert("wrong file data: " .. name, files[name], contents, tostring(contents) .. details)
    files[name]=nil
  end

  testutil.assert("missing files", {}, files, ser(actual) .. details)
  testutil.assert("exit code", sh.getLastExitCode(), sh.internal.command_result_as_code(exit_code), details)

  function output_check(captures, pattern)
    for _,c in ipairs(captures) do
      if pattern then
        testutil.assert("output capture mismatch", not not c:match(pattern), true, c)
      else
        testutil.assert("unexpected output", c, nil)
      end
    end
  end

  output_check(stdouts, meta[1])
  output_check(stderrs, meta[2])
end

local omit = "omitting directory `/tmp/[^/]+/"
local into_itself = "^cannot copy a directory.+ into itself"
local no_such = "No such file or directory"
local non_dir = "cannot overwrite directory.+with non%-directory"
local same_file = " and .+are the same file\n$"

shell.setAlias("cp")
cmd_test({"echo foo > a", "cp a b"}, {a="foo\n", b="foo\n"})
cmd_test({"echo -n foo > a", "cp a b"}, {a="foo", b="foo"})
cmd_test({"echo -n foo > a", "echo -n bar > b", "cp a b"}, {a="foo", b="foo"})
cmd_test({"echo -n foo > a", "echo -n bar > b", "cp -n a b"}, {a="foo", b="bar"})
cmd_test({"mkdir a"}, {a=true})
cmd_test({"mkdir a", "cp a b"}, {a=true}, {exit_code=1,[1]=omit.."a"})
cmd_test({"mkdir a", "cp -r a b"}, {a=true,b=true})
cmd_test({"mkdir a", "echo -n foo > a/b", "cp -r a b"}, {a=true,b=true,["a/b"]="foo",["b/b"]="foo"})

-- fake fs to give -x a test bed
local fake_fs =
{
  list = function()
    return {"fake_file"}
  end,
  isDirectory = function()
    return false
  end,
  isReadOnly = function()
    return false
  end,
  open = function(path)
    return {consumed = false}
  end,
  exists = function(path)
    return path == "fake_file"
  end,
  read = function(fh)
    if fh.consumed then return nil end
    fh.consumed = true
    return "abc"
  end,
  close = function()end
}

cmd_test({"echo -n data > file"}, {file="data"})
cmd_test({"mkdir a", function()
  fake_fs.path = shell.getWorkingDirectory() .. '/a/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "echo -n data > a/file", "cp -r a b"},
{
  a=true,b=true,
  ["a/fake"]=true,["b/fake"]=true,
  ["a/file"]="data",["b/file"]="data",
  ["a/fake/fake_file"]="abc",["b/fake/fake_file"]="abc",
})

fs.umount(fake_fs.path)

cmd_test({"mkdir a", function()
  fake_fs.path = shell.getWorkingDirectory() .. '/a/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "echo -n data > a/file", "cp -xr a b"},
{
  a=true,b=true,
  ["a/fake"]=true,
  ["a/file"]="data",["b/file"]="data",
  ["a/fake/fake_file"]="abc",
})

fs.umount(fake_fs.path)

cmd_test({"echo -n foo > a", "ln -s a b", "cp b c", "cp -P b d"}, {a="foo",b=false,c="foo",d=false})
cmd_test({"mkdir a", "echo -n foo > a/b", "ln -s a/b a/c", "cp -r a d"}, {a=true,["a/b"]="foo",["a/c"]=false,d=true,["d/b"]="foo",["d/c"]=false})
cmd_test({"mkdir a", "mkdir d", "echo -n foo > a/b", "ln -s a/b a/c", "cp -r a d"},
{
  a=true,d=true,["d/a"]=true,
  ["a/b"]="foo",["d/a/b"]="foo",
  ["a/c"]=false,["d/a/c"]=false
})

cmd_test({"mkdir a", "echo -n foo > a/b", "cp -r a a/../a"}, {a=true,["a/b"]="foo"}, {exit_code=1,[2]=into_itself})
cmd_test({"mkdir a", "cp a b"}, {a=true}, {exit_code=1,[1]=omit.."a"})
cmd_test({"mkdir d", "touch a", "cp d/../a a"}, {d=true,a=""}, {exit_code=1,[2]=" and .+are the same file\n$"})
cmd_test({"mkdir a", "mkdir a/b", "touch b", "cp b a"}, {a=true,["a/b"]=true,b=""}, {exit_code=1,[2]=non_dir})

-- some bugs
cmd_test({"echo foo > b","cp a b"},{b="foo\n"},{exit_code=1,[2]=no_such})
cmd_test({"echo foo > b","cp -u a b"},{b="foo\n"},{exit_code=1,[2]=no_such})

-- /. support!
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w","cp -r a/. b/."},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir a","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir b","echo -n foo > b/w","cp -r a/. b"},{b=true,["b/w"]="foo"},{exit_code=1,[2]=no_such})
cmd_test({"mkdir b","cp -r b/. b"},{b=true},{exit_code=1,[2]=into_itself})
cmd_test({"mkdir b","cp -r b/. b/."},{b=true},{exit_code=1,[2]=into_itself})
cmd_test({"mkdir a","mkdir a/d","mkdir b","echo -n foo > b/d","cp -r b/. a"},{a=true,b=true,["a/d"]=true,["b/d"]="foo"},{exit_code=1,[2]=non_dir})
cmd_test({"mkdir a","mkdir a/d","mkdir b","echo -n foo > a/w","cp -r a/d/.. b"},{a=true,b=true,["a/d"]=true,["b/d"]=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir b","mkdir b/d","mkdir b/d/w","cp -r b/d b/d/w"},{b=true,["b/d"]=true,["b/d/w"]=true},{exit_code=1,[2]=into_itself})
