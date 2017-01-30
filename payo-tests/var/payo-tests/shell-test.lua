local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local sh = dofile("/lib/sh.lua")

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.assert_process_output("echo hi", "hi\n")

local touch = loadfile(shell.resolve("touch", "lua"))
if not touch then
  io.stderr:write("bash-test requires touch which could not be found\n")
  return
end

local function execute(...)
  return sh.execute(nil, ...)
end

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local function hint(line, ex, cursor)
  local results = sh.hintHandler(line, cursor or (line:len() + 1))
  local detail = '`'..line..'`'.."=>"..ser(results)..'<and not>'..ser(ex)
  
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
    end

    testutil.assert("wrong results", true, not next(ex), detail)
  end
end

hint("", {})
hint("a", {"ddress ", "lias ", "ll-tests ", "rgutil-test "})
hint("c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "onfig-test ", "p ", "p-test "})
hint("cd", {" "})

hint("/b", {"in", "oot"})

-- test files can come after redirects and equal sign
hint("foo asdf --file=s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf >s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf >>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 1>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 1>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 2>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 2>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf <s", {"h-test.lua", "hell-test.lua", "low-test.lua"})

-- now retest that program are listed after statement separators
hint("foo asdf;c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "onfig-test ", "p ", "p-test "})
hint("foo asdf|c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "onfig-test ", "p ", "p-test "})
hint("foo asdf||c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "onfig-test ", "p ", "p-test "})
hint("foo asdf&&c", {"at ", "d ", "fgemu ", "lear ", "omponents ", "onfig-test ", "p ", "p-test "})

-- confirm quotes are checked
hint("foo asdf';'c", {})
hint("foo asdf\"|\"c", {})
hint("foo asdf'||'c", {})
hint("foo asdf'&&'c", {})

-- and retest that files are searched
hint("echo hello&&foo asdf --file=s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf >s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf >>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 1>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 1>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 2>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 2>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf <s", {"h-test.lua", "hell-test.lua", "low-test.lua"})

local tmp_path = mktmp('-d','-q')

local test_depth = 10
hint("cd " .. tmp_path:sub(1, test_depth), {tmp_path:sub(test_depth+1) .. '/'})

execute("mkdir " .. tmp_path .. '/' .. 'a')

hint("cd " .. tmp_path .. '/', {"a/"})
local test_dir = os.getenv("PWD")
execute("cd " .. tmp_path .. '/a')
hint("cd ../", {"a/"})
execute("cd ..")
hint(tmp_path, {"/"})
execute("mkdir " .. tmp_path .. '/' .. 'a2')
hint("cd a", {"", "2"})

local pref = "cd ../.." .. tmp_path
hint("cd ../.." .. tmp_path .. '/', {"a", "a2"})

execute("cd a")
hint("cd ", {})

hint("mo", {"re ", "unt "})
hint("/bin/mo", {"re.lua", "unt.lua"})
hint("mo ", {})
hint("/bin/mo ", {})
execute("cd ..")
hint("cd a/", {})
hint("cd ../ ", {"a", "a2"})
hint(tmp_path, {"/"})
hint(tmp_path..'/a/', {})
execute("touch .c")
hint('cat '..tmp_path..'/.',{"c "})
hint('./.',{'c '})
execute("mkdir .d")
hint('cd .', {'c', 'd'})
fs.remove(tmp_path..'/.c')
hint('cd .', {'d/'}) -- with / because it is the only one

execute("cd .d")
hint(' ', {})
hint(';', {})
hint('; ', {})
execute("touch foo.lua")
hint(' ca ', {'foo.lua '})
hint('  ca ', {'foo.lua '})
execute("touch bar\\ baz.lua")
hint(' ', {})
hint(';', {})
hint('; ', {})
hint('cat bar', {'\\ baz.lua '})
hint('cat f', {'oo.lua '})
hint('cat bar\\ ', {'baz.lua '})
hint('cat bar ', {'bar\\ baz.lua', 'foo.lua'})
hint('cat bar\\', {})

execute("cd " .. test_dir)
fs.remove(tmp_path..'/.d')

fs.remove(tmp_path..'/a')
fs.remove(tmp_path)

local function hint2(line, ex, cursor)
  local results = sh.hintHandler(line, cursor or (line:len() + 1))
  local detail = line.."=>"..ser(results)..'<and not>'..ser(ex)
  
  if testutil.assert("result type", "table", type(results), detail) then

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

local tilde_support = false

execute("cd") -- home
hint2("cat .", {"shrc "})
hint2("cat ./.", {"shrc "})
if tilde_support then hint2("cat ~/.", {"shrc "}) end
hint2("cat /.", {"prop "})
execute("cd " .. test_dir)

execute("cd /")
hint2("cat .", {"prop "})
hint2("cat ./.", {"prop "})
if tilde_support then hint2("cat ~/.", {"shrc "}) end
hint2("cat /.", {"prop "})
execute("cd " .. test_dir)

execute("cd") -- home
hint2("cat < .", {"shrc "})
hint2("cat < ./.", {"shrc "})
if tilde_support then hint2("cat < ~/.", {"shrc "}) end
hint2("cat < /.", {"prop "})
execute("cd " .. test_dir)

execute("cd /")
hint2("cat < .", {"prop "})
hint2("cat < ./.", {"prop "})
if tilde_support then hint2("cat < ~/.", {"shrc "}) end
hint2("cat < /.", {"prop "})
execute("cd " .. test_dir)
