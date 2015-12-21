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
    qr=qri and sh.syntax.quotations[qri]
  }}
end

-- glob as action!
local function pc(file_prep, input, exp)
  local tp = mktmp('-d')
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

local echo_pack = {"/bin/echo.lua",{},[5]="write",n=5}
pc({}, {word('xxxx')}, nil)
pc({}, {word('echo')}, echo_pack)
pc({'echo'}, {word('*')}, echo_pack)

echo_pack[2][1]='echo'
pc({'echo'}, {word('*'),word('*')}, echo_pack)
pc({}, {word('echo'),word('echo')}, echo_pack)
echo_pack[2][1]=';'
pc({}, {word('echo'),word(';',2)}, echo_pack)

local tmp_path = mktmp('-d')

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
  local tp = mktmp('-d')
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

