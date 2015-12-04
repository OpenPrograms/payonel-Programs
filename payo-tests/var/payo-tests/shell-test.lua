local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.broken.assert_process_output("echo hi", "hi\n")

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

local tmp_path = mktmp('-d')

local function ls(args, output)
  testutil.broken.assert_process_output(string.format("ls -p %s", args or ""), output)
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

local function echo(args, ex)
end

echo("", "\n")

local function hint(line, ex, cursor)
  local results = shell.hintHandler(line, cursor or (line:len() + 1))
  local detail = line.."=>"..ser(results)..'<and not>'..ser(ex)
  
  if testutil.assert("result type", "table", type(results), detail) and
     testutil.assert("result size", #ex, #results, detail) then

     for i,v in ipairs(results) do
      local removed = false
      for j,w in ipairs(ex) do
        if v == string.format("%s%s", line, w) then
          table.remove(ex, j)
          removed = true
          break
        end
      end
      if not removed then
        ex[#ex + 1] = v
      end
    end

    testutil.assert("wrong results", true, not next(ex), detail)

  end
end

testutil.broken.hint("", {})
testutil.broken.hint("a", {"ddress ", "lias "})
testutil.broken.hint("c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "p "})
testutil.broken.hint("cd", {" "})

tmp_path = mktmp('-d')

local test_depth = 10
testutil.broken.hint("cd " .. tmp_path:sub(1, test_depth), {tmp_path:sub(test_depth+1) .. '/'})

os.execute("mkdir " .. tmp_path .. '/' .. 'a')

testutil.broken.hint("cd " .. tmp_path .. '/', {"a/"})
local test_dir = os.getenv("PWD")
os.execute("cd " .. tmp_path .. '/a')
testutil.broken.hint("cd ../", {"a/"})
os.execute("cd ..")
testutil.broken.hint(tmp_path, {"/"})
os.execute("mkdir " .. tmp_path .. '/' .. 'a2')
testutil.broken.hint("cd a", {"", "2"})

local pref = "cd ../.." .. tmp_path
testutil.broken.hint("cd ../.." .. tmp_path .. '/', {"a", "a2"})

os.execute("cd a")
testutil.broken.hint("cd ", {})

testutil.broken.hint("mo", {"re ", "unt "})
testutil.broken.hint("/bin/mo", {"re.lua ", "unt.lua "})
testutil.broken.hint("mo ", {})
testutil.broken.hint("/bin/mo ", {})
os.execute("cd ..")
testutil.broken.hint("cd a/", {})
testutil.broken.hint("cd ../ ", {"a", "a2"})
testutil.broken.hint(tmp_path, {"/"})
testutil.broken.hint(tmp_path..'/a/', {})
os.execute("touch .c")
testutil.broken.hint('cat '..tmp_path..'/.',{"c "})
testutil.broken.hint('./.',{'c '})
os.execute("mkdir .d")
testutil.broken.hint('cd .', {'c', 'd'})
fs.remove(tmp_path..'/.c')
testutil.broken.hint('cd .', {'d/'}) -- with / because it is the only one

fs.remove(tmp_path..'/a')
fs.remove(tmp_path)
os.execute("cd " .. test_dir)

local function id(name, ex)
  testutil.assert('id:'..tostring(name), ex, shell.isIdentifier(name))
end

testutil.broken.id('', false)
testutil.broken.id(' ', false)
testutil.broken.id('abc', true)
testutil.broken.id('1abc', false)
testutil.broken.id('abc1', true)
testutil.broken.id(' abc1', false)

local function glob(str, files, exp)
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

  local status, result = pcall(function() return shell.glob(str) end)

  os.execute("cd " .. test_dir)
  fs.remove(tp)  

  testutil.assert('glob:'..str..ser(files),status and exp or '',result)
end

testutil.broken.glob('foobar', {}, {'foobar'})
testutil.broken.glob([[foobar*]], {'foobarbaz'}, {'foobarbaz'})
testutil.broken.glob([[foobar*]], {'.foobarbaz','foobarbaz'}, {'foobarbaz'})
testutil.broken.glob([[foobar*]], {'.foobarbaz','foobar','foobarbaz'}, {'foobar','foobarbaz'})
testutil.broken.glob([[.foobar*]], {'.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})
testutil.broken.glob([[.*]], {'.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})
testutil.broken.glob([[.f*]], {'fff','.b','.foobarbaz','foobar','foobarbaz'}, {'.foobarbaz'})

testutil.broken.glob('a*/b*',{'a1/','a2/','a1/b1','a1/b2','a2/b3','a2/b4'},{'a1/b1','a1/b2','a2/b3','a2/b4'})
testutil.broken.glob('a*/b1',{'a1/','a2/','a1/b1','a1/b2','a2/b1','a2/b2'},{'a1/b1','a2/b1'})
testutil.broken.glob('a1/b*',{'a1/','a2/','a1/b1','a1/b2','a2/b1','a2/b2'},{'a1/b1','a1/b2'})
testutil.broken.glob('a*/c*',{'a1/','a2/','a1/b1','a1/b2','a2/b3','a2/b4'},{'a*/c*'})
testutil.broken.glob('*/*/*.lua',{'a/','a/1.lua','b/','b/q/','b/q/1.lua'},{'b/q/1.lua'})
testutil.broken.glob('*/*/*.lua',{'a/','a/dir.lua/','b/','b/q/','b/q/1.lua'},{'b/q/1.lua'})
testutil.broken.glob('*/*/*.lua',{'a/','a/w/','a/w/dir.lua/','a/w/dir.lua/data','b/','b/q/','b/q/1.lua'},{'a/w/dir.lua','b/q/1.lua'})

-- now glob * where no files exist
testutil.broken.glob([[foobaz*]], {}, {'foobaz*'})

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
testutil.broken.glob([[f?o*]], magicfiles, magicfiles)


-- the following tests simply check if shell.evaluate calls glob
-- we only want globbing on non-quoted strings

local function evalglob(value, exp)

  --hijack glob

  local bk_glob = shell.glob_new
  shell.glob_new = function(v)
    return {'globbed'}
  end

  local status, result = pcall(function()
    local groups, reason = text.tokenizeGroups(value)
    if type(groups) ~= "table" then
      return groups, reason
    end
    return text.foreach(groups, function(g)
      local evals = shell.evaluate_new(g)
      if #evals == 0 then
        return nil
      elseif #evals > 1 then
        return {'too many evals'}
      else
        return evals[1]
      end
    end)
  end)

  --return glob
  shell.glob_new = bk_glob

  testutil.assert('evalglob result:'..value,status and exp or '',result)

end

-- only plaintext * should glob
testutil.broken.evalglob('*', {'globbed'})
testutil.broken.evalglob('*.foo', {'globbed'})
testutil.broken.evalglob('', {})
testutil.broken.evalglob('foo', {'foo'})
testutil.broken.evalglob([["*".foo]], {'*.foo'})
testutil.broken.evalglob([['*'.foo]], {'*.foo'})
testutil.broken.evalglob([['*.fo'o]], {'*.foo'})
testutil.broken.evalglob([['*."f"oo']], {'*.\"f\"oo'})
testutil.broken.evalglob([[**]], {'globbed'})
testutil.broken.evalglob([[* *]], {'globbed','globbed'})
testutil.broken.evalglob([[* * *]], {'globbed','globbed','globbed'})
testutil.broken.evalglob([["* * *"]], {'* * *'})

local function vt(cmd, ex)
  local tokens = text.tokenizeGroups(cmd, text.rules().all,nil)
  testutil.assert('vt:'..cmd, ex, shell.validateTokens(tokens))
end

testutil.broken.vt('echo hi', true)
testutil.broken.vt('echo hi;', true)
testutil.broken.vt(';echo hi;', true)
testutil.broken.vt('echo hi|grep hi', true)
testutil.broken.vt('|echo hi|grep hi', false)
testutil.broken.vt('echo hi|grep hi|', false)
testutil.broken.vt('echo hi||grep hi', false)
testutil.broken.vt('echo hi|;|grep hi', false)
testutil.broken.vt('echo hi|>grep hi', false)
testutil.broken.vt('echo hi|grep hi', true)
testutil.broken.vt('echo hi|;grep hi', false)
testutil.broken.vt('echo hi>>grep hi', true)
testutil.broken.vt('echo hi>>>grep hi', false)
testutil.broken.vt(';;echo hi;echo hello|grep hello|grep hello>>result;echo hi>result;;', true)
testutil.broken.vt(';result<grep foobar>result;', true)
testutil.broken.vt('', true)
testutil.broken.vt(';', true)
testutil.broken.vt(';;;;;;;;;', true)

local function ps(cmd, out)
  testutil.assert('ps:'..cmd, out, shell.parseStatements(cmd))
end

testutil.broken.ps("", true)
testutil.broken.ps("echo", {{{"echo"}}})
testutil.broken.ps("echo hi", {{{"echo", "hi"}}})
testutil.broken.ps("echo 'hi'", {{{"echo", "\'hi\'"}}})
testutil.broken.ps('echo hi "world"', {{{"echo", "hi", "\"world\""}}})
testutil.broken.ps('echo test;echo hello|grep world>>result',
  {
    {{'echo','test'}},
    {{'echo','hello'},{'grep','world','>>','result'}},
  })
testutil.broken.ps('echo test; echo hello |grep world >>result',
  {
    {{'echo','test'}},
    {{'echo','hello'},{'grep','world','>>','result'}},
  })

testutil.broken.ps('|echo', false)
testutil.broken.ps('|echo|', false)
testutil.broken.ps('echo|', false)
testutil.broken.ps('echo||echo', false)
testutil.broken.ps(';', true)
testutil.broken.ps(';;;;;;;', true)
testutil.broken.ps(';echo ignore;echo hello|grep hello>>result',
  {
    {{'echo','ignore'}},
    {{'echo','hello'},{'grep','hello','>>','result'}}
  })

testutil.broken.ps([[echo 'hi']],{{{'echo',[['hi']]}}})
