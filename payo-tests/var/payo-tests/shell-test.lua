local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.assert_process_output("echo hi", "hi\n")

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

local function echo(args, ex)
end

echo("", "\n")

local function hint(line, ex, cursor)
  local results = shell.internal.hintHandler(line, cursor or (line:len() + 1))
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

hint("", {})
hint("a", {"ddress ", "lias "})
hint("c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "p "})
hint("cd", {" "})

local tmp_path = mktmp('-d')

local test_depth = 10
hint("cd " .. tmp_path:sub(1, test_depth), {tmp_path:sub(test_depth+1) .. '/'})

os.execute("mkdir " .. tmp_path .. '/' .. 'a')

hint("cd " .. tmp_path .. '/', {"a/"})
local test_dir = os.getenv("PWD")
os.execute("cd " .. tmp_path .. '/a')
hint("cd ../", {"a/"})
os.execute("cd ..")
hint(tmp_path, {"/"})
os.execute("mkdir " .. tmp_path .. '/' .. 'a2')
hint("cd a", {"", "2"})

local pref = "cd ../.." .. tmp_path
hint("cd ../.." .. tmp_path .. '/', {"a", "a2"})

os.execute("cd a")
hint("cd ", {})

hint("mo", {"re ", "unt "})
hint("/bin/mo", {"re.lua ", "unt.lua "})
hint("mo ", {})
hint("/bin/mo ", {})
os.execute("cd ..")
hint("cd a/", {})
hint("cd ../ ", {"a", "a2"})
hint(tmp_path, {"/"})
hint(tmp_path..'/a/', {})
os.execute("touch .c")
hint('cat '..tmp_path..'/.',{"c "})
hint('./.',{'c '})
os.execute("mkdir .d")
hint('cd .', {'c', 'd'})
fs.remove(tmp_path..'/.c')
hint('cd .', {'d/'}) -- with / because it is the only one

fs.remove(tmp_path..'/a')
fs.remove(tmp_path)
os.execute("cd " .. test_dir)

local function id(name, ex)
  testutil.assert('id:'..tostring(name), ex, shell.isIdentifier(name))
end

id('', false)
id(' ', false)
id('abc', true)
id('1abc', false)
id('abc1', true)
id(' abc1', false)

-- the following tests simply check if shell.evaluate calls glob
-- we only want globbing on non-quoted strings

local function evalglob(value, exp)

  local status, result = pcall(function()
    local groups, reason = text.tokenize(value,nil,nil,true)
    if type(groups) ~= "table" then
      return groups, reason
    end
    return tx.foreach(groups, function(g)
      local evals = shell.internal.evaluate(g)
      if #evals == 0 then
        return nil
      elseif #evals > 1 then
        return {'too many evals'}
      else
        return evals[1]
      end
    end)
  end)

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

local function ps(cmd, out)
  testutil.assert('ps:'..cmd, out, shell.internal.packStatements({}, cmd))
end

ps("", true)
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
