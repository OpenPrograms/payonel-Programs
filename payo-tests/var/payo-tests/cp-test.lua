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

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local chdir = shell.setWorkingDirectory

function cmd_test(cmds, files, meta)
  meta = meta or {}
  local exit_code = meta.exit_code
  local tmp_dir_path = mktmp('-d','-q')
  local home = shell.getWorkingDirectory()
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

  local actual = {}
  local scan = nil
  scan = function(d)
    for it in fs.list(d) do
      local path = (d .. '/' .. it):gsub("/+", "/")
      local key = path:sub(unicode.len(tmp_dir_path)+1):gsub("/*$",""):gsub("^/*", "")
      path = shell.resolve(path)
      local isLink, linkTarget = fs.isLink(path)
      if isLink then
        actual[key] = {linkTarget:sub(#tmp_dir_path+2)}
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
  
  chdir(tmp_dir_path)
  scan(tmp_dir_path)
  chdir(home)
  fs.remove(tmp_dir_path)

  local details = ' cmds:' .. ser(cmds,true) .. '\n' .. ser(meta,true) .. '\n'
  
  for name,contents in pairs(actual) do
    testutil.assert("wrong file data: " .. name, files[name], contents, tostring(contents) .. details)
    files[name]=nil
  end

  testutil.assert("missing files", {}, files, ser(actual) .. details)
  testutil.assert("exit code", sh.getLastExitCode(), sh.internal.command_result_as_code(exit_code), details)

  function output_check(captures, pattern)
    if type(pattern) == "string" then
      pattern = {pattern}
    end
    for _,c in ipairs(captures) do
      if pattern and pattern[_] then
        testutil.assert("output capture mismatch", not not c:match(pattern[_]), true, tostring(_) .. details .. c)
      else
        testutil.assert("unexpected output", nil, c, details .. c)
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
local dir_non_dir = "cannot overwrite non%-directory.+with directory"
local same_file = " and .+are the same file\n$"
local overwrite = "overwrite.+%?"

shell.setAlias("cp")
cmd_test({"echo foo > a", "cp a b"}, {a="foo\n", b="foo\n"})
cmd_test({"echo -n foo > a", "cp a b"}, {a="foo", b="foo"})
cmd_test({"echo -n foo > a", "echo -n bar > b", "cp a b"}, {a="foo", b="foo"})
cmd_test({"echo -n foo > a", "echo -n bar > b", "cp -n a b"}, {a="foo", b="bar"})
cmd_test({"mkdir a"}, {a=true})
cmd_test({"mkdir a", "cp a b"}, {a=true}, {exit_code=1,[1]=omit.."a"})
cmd_test({"mkdir a", "cp -r a b"}, {a=true,b=true})
cmd_test({"mkdir a", "echo -n foo > a/b", "cp -r a b"}, {a=true,b=true,["a/b"]="foo",["b/b"]="foo"})

cmd_test({"echo hi > a", "ln a b", "cp a b"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})
cmd_test({"echo hi > a", "ln a b", "cp b a"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})

cmd_test({"echo hi > a", "ln a b", "cp -P a b"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})
cmd_test({"echo hi > a", "ln a b", "cp -P b a"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})

cmd_test({"echo hi > a", "ln a b", "mkdir c", "cp c b"}, {a="hi\n",b={"a"},c=true}, {exit_code=1,[1]=omit.."c"})
cmd_test({"echo hi > a", "ln a b", "mkdir c", "cp -r c b"}, {a="hi\n",b={"a"},c=true}, {exit_code=1,[2]=dir_non_dir})

cmd_test({"echo hi > a", "ln a b", "echo bye > c", "cp c b"}, {a="bye\n",b={"a"},c="bye\n"})
cmd_test({"echo hi > a", "ln a b", "echo bye > c", "cp b c"}, {a="hi\n",b={"a"},c="hi\n"})

cmd_test({"echo hi > a", "mkdir d", "mkdir d/a", "cp a d"}, {a="hi\n",d=true,["d/a"]=true},{exit_code=1,[2]=non_dir})
cmd_test({"echo hi > a", "mkdir d", "mkdir d/a", "yes y | cp -i a d"}, {a="hi\n",d=true,["d/a"]=true},{[1]=overwrite,[2]=non_dir})
cmd_test({"echo hi > a", "mkdir d", "mkdir d/a", "yes n | cp -i a d"}, {a="hi\n",d=true,["d/a"]=true},{[1]=overwrite})

cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -r b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -rv b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}}, {[1]={"removed","^/tmp/[^/]+/b %-> /tmp/[^/]+/d/b"}})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -nr b d"}, {a="hi",b={"a"},d=true,["d/b"]=""})

cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -P b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -Pv b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}}, {[1]={"removed","^/tmp/[^/]+/b %-> /tmp/[^/]+/d/b"}})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -nP b d"}, {a="hi",b={"a"},d=true,["d/b"]=""})

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

cmd_test({"echo -n foo > a", "ln -s a b", "cp b c", "cp -P b d"}, {a="foo",b={"a"},c="foo",d={"a"}})
cmd_test({"mkdir a", "echo -n foo > a/b", "ln -s a/b a/c", "cp -r a d"}, {a=true,["a/b"]="foo",["a/c"]={"a/b"},d=true,["d/b"]="foo",["d/c"]={"a/b"}})
cmd_test({"mkdir a", "mkdir d", "echo -n foo > a/b", "ln -s a/b a/c", "cp -r a d"},
{
  a=true,d=true,["d/a"]=true,
  ["a/b"]="foo",["d/a/b"]="foo",
  ["a/c"]={"a/b"},["d/a/c"]={"a/b"}
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

cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "cp b c"}, {a="hi", b={"a"}, c=true, ["c/b"]="hi"})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "cp -P b c"}, {a="hi", b={"a"}, c=true, ["c/b"]={"a"}})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp b d"}, {a="hi", b={"a"}, c=true, d={"c"}, ["c/b"]="hi"})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp -P b d"}, {a="hi", b={"a"}, c=true, d={"c"}, ["c/b"]={"a"}})

-- cp -r to file allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -r b c", "cp -r c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp -P of same file allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -P b c", "cp -P c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp ln to ln not allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -r b c", "cp c b"}, {a="hi", b={"a"}, c={"a"}}, {exit_code=1,[2]=same_file})

-- cp -r of dir with ln allowed with same file
cmd_test({"echo -n hi > a", "mkdir d1", "ln a d1/a", "cp -r d1/. d2", "cp -r d1/. d2"}, {a="hi", d1=true, d2=true, ["d1/a"]={"a"}, ["d2/a"]={"a"}})

-- let's not allow fs.link to create loops - it breaks the fs until reboot
--cmd_test({"touch a", "ln a b", "ln b c", "rm b", "ln c b", "cd b"}, {a="",b={"c"},c={"b"}}, {exit_code=1})

-- ln of missing file should error
cmd_test({"ln a b"}, {}, {exit_code=1,[2]=no_such})
cmd_test({"touch a", "ln a b", "rm a", "ln b c"}, {b={"a"},c={"b"}})

--cp -r . should work the same as cp -r ./.
local function common_result() return {a=true,["a/c"]="hi",["a/d"]=true,["a/d/c"]="np",b=true,["b/c"]="hi",["b/d"]=true,["b/d/c"]="np"} end

cmd_test({"mkdir b", "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cd .."              }, common_result())
cmd_test({"mkdir b", "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cp -r . ../b; cd .."}, common_result())
cmd_test({           "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cd .."              }, common_result())
cmd_test({           "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cp -r . ../b; cd .."}, common_result())

-- this is a glob-test, but the cmd list nature of the cmd_test will help simplify the setup
cmd_test({"mkdir a", "mkdir b", "touch b/c", "touch b/d", "cd b; ls *"}, {a=true,b=true,["b/c"]="", ["b/d"]=""}, {[1]={"c","d","\n"}})
cmd_test({"mkdir a", "mkdir b", "touch b/c", "touch b/d", "cd a; ls ../b/*"}, {a=true,b=true,["b/c"]="", ["b/d"]=""}, {[1]={"../b/c","../b/d","\n"}})
