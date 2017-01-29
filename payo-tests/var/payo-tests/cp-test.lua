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

  local stdout = setmetatable({write = function(self, ...)
    for _,v in ipairs({...}) do
      if #v > 0 then table.insert(stdouts,v) end
    end
  end}, {__index = io.stdout})

  local stderr = setmetatable({write = function(self, ...)
    for _,v in ipairs({...}) do
      if #v > 0 then table.insert(stderrs,v) end
    end
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
      local isLink, linkPath = fs.isLink(path)
      path = fs.realPath(path)
      if isLink then
        actual[key] = {linkPath}
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
    testutil.assert("wrong file data: " .. name, files[name], contents, ser(contents) .. details)
    files[name]=nil
  end

  testutil.assert("missing files", {}, files, ser(actual) .. details)
  testutil.assert("exit code", sh.getLastExitCode(), sh.internal.command_result_as_code(exit_code), details)

  function output_check(captures, pattern)
    local o=captures
    if type(pattern) == "string" then
      pattern = {pattern}
      captures = {table.concat(captures)}
    end
    for _,c in ipairs(captures) do
      if pattern and pattern[_] then
        testutil.assert("output capture mismatch", not not c:match(pattern[_]), true,
        string.format("[%d][%s]: captured output:[%s]", _, details, c)) 
      else
        testutil.assert("unexpected output", nil, c, details .. c)
      end
    end
  end

  output_check(stdouts, meta[1])
  output_check(stderrs, meta[2])
end

local omit = "omitting directory `/tmp/[^/]+/"
local into_itself = "cannot copy a directory.+ into itself"
local no_such = "No such file or directory"
local non_dir = "cannot overwrite directory.+with non%-directory"
local dir_non_dir = "cannot overwrite non%-directory.+with directory"
local same_file = " and .+are the same file\n$"
local overwrite = "overwrite.+%?"
local readonly_fs = "filesystem is readonly"
local cannot_move = "it is a mount point"
local not_a_dir = "is not a directory"
local to_subself = "cannot move '%s' to a subdirectory of itself"

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
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -r b d", "echo -n bye > d/a", "cat d/b"}, {["d/a"]="bye",a="hi",b={"a"},d=true,["d/b"]={"a"}}, {"bye"})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -rv b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}}, {[1]={"removed","^/tmp/[^/]+/b %-> /tmp/[^/]+/d/b"}})
cmd_test({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -nr b d"}, {a="hi",b={"a"},d=true,["d/b"]=""})

cmd_test({"mkdir a", "echo -n foo > a/b", "cd a;ln -s b c;cd ..", "cp -r a d", "echo -n bye > d/c"}, {a=true,["a/b"]="foo",["a/c"]={"b"},d=true,["d/b"]="bye",["d/c"]={"b"}})
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
cmd_test({"mkdir a", "echo -n foo > a/b", "cd a;ln -s b c;cd ..", "cp -r a d", "echo -n bye > d/c"},
{
  a=true,
  ["a/b"]="foo",
  ["a/c"]={"b"},
  d=true,["d/b"]="bye",
  ["d/c"]={"b"}
})
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
cmd_test({"mkdir a","mkdir b","mkdir a/d","echo -n foo > a/w","cp -r a/d/.. b"},{a=true,b=true,["a/d"]=true,["a/w"]="foo",["b/d"]=true,["b/w"]="foo",})
cmd_test({"mkdir a","mkdir b","touch a/...","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/..."]="",["a/w"]="foo",["b/..."]="",["b/w"]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w.","cp -r a/w. b"},{a=true,b=true,["a/w."]="foo",["b/w."]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w..","cp -r a/w.. b"},{a=true,b=true,["a/w.."]="foo",["b/w.."]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r . ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r ./. ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r ./../a/. ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
cmd_test({"mkdir a","echo -n notadir > b","cp -r a/. b/"},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})
cmd_test({"mkdir a","echo -n notadir > b","cp -r a/. b/."},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})
print("todo, fs segments is hiding /.. issues")
--cmd_test({"mkdir a","echo -n notadir > b","cp -r a/. b/.."},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})

-- found weird contents of bug when reworking cp and mv
cmd_test({"echo -n hi > a", "mkdir d", "echo -n foo > d/b", "ln -s a b", "cp -r b/. d"}, {a="hi",b={"a"},d=true,["d/b"]="foo"},{exit_code=1,[2]=not_a_dir})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "cp b c"}, {a="hi", b={"a"}, c=true, ["c/b"]="hi"})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "cp -P b c"}, {a="hi", b={"a"}, c=true, ["c/b"]={"a"}})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp b d"}, {a="hi", b={"a"}, c=true, d={"c"}, ["c/b"]="hi"})
cmd_test({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp -P b d", "echo -n bye > c/a", "cat d/b"},
{
  a="hi",
  b={"a"},
  c=true,
  d={"c"},
  ["c/b"]={"a"},
  ["c/a"]="bye"
},
{"bye"})

-- cp -r to file allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -r b c", "cp -r c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp -P of same file allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -P b c", "cp -P c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp ln to ln not allowed
cmd_test({"echo -n hi > a", "ln a b", "cp -r b c", "cp c b"}, {a="hi", b={"a"}, c={"a"}}, {exit_code=1,[2]=same_file})

-- cp -r of dir with ln allowed with same file
cmd_test({"echo -n hi > a", "mkdir d1", "cd d1;ln ../a;cd ..", "cp -r d1/. d2", "cp -r d1/. d2"}, {a="hi", d1=true, d2=true, ["d1/a"]={"../a"}, ["d2/a"]={"../a"}})

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


-- a regression, of course! copy dir to new name but similar name!
cmd_test({"mkdir a", "echo -n foo > a/b", "cp -r a aa"}, {a=true,aa=true,["a/b"]="foo", ["aa/b"]="foo"})

-- actually a rm test
cmd_test({"rm foo"}, {}, {exit_code=1,[2]=no_such})
cmd_test({"rm -f foo"}, {})

-- test inf loops
local link_err = "link cycle detected"
cmd_test({"mkdir a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cd b"}, {a=true,b={"c"},c={"b"}}, {exit_code=1, [2]="cd.+not a directory"})
cmd_test({"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat c"}, {a="hi",b={"c"},c={"b"}}, {exit_code=1, [2]="cat.+"..link_err})
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "mkdir d", "ln -s d e", "ln -s e f", "rm e", "ln -s f e", "ls", "cat b"},
  {a="hi",b={"c"},c={"b"},d=true,e={"f"},f={"e"}},
  {exit_code=1,[1]="a *b *c *d *e *f",[2]="cat.+"..link_err})

-- should fail to cycle
-- cp to file
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp b w"},
  {a="hi",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to link cycle
cmd_test(
  {"echo -n hi > a", "echo -n bye > w", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp w b"},
  {a="hi",w="bye",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to dir
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "mkdir d", "cp b d/w"},
  {a="hi",b={"c"},c={"b"},d=true},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to cycle with dir notation
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp a b/w"},
  {a="hi",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})

-- should allow cycle
-- cp -P
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp -P b w"},
  {a="hi",b={"c"},c={"b"},w={"c"}})

-- test copy to link cycle as if dir
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp a b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]="cp.+"..link_err})
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp -P a b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]="cp.+"..link_err})

-- touch should complain about link cylce, not permission
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "touch b"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "touch b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})

--saw some errors with cat
cmd_test({"echo hi | cat"},{},{"hi\n"})
cmd_test({"echo -n hi | cat"},{},{"hi"})
cmd_test({"echo hi | cat -"},{},{"hi\n"})
cmd_test({"echo -n hi | cat -"},{},{"hi"})

cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat b"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
cmd_test(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
cmd_test(
  {"echo -n hi > a", "ln -s a b", "cat a"},
  {a="hi",b={"a"}},{"hi"})

-- fs exists check

local assert_txt = "assert(not require('filesystem').exists(require('shell').resolve('b/w')))" 
cmd_test(
  {"echo -n \""..assert_txt.."\" > a",
   "ln a b", "ln b c", "rm b", "ln c b", "./a"},
  {a=assert_txt,b={"c"},c={"b"}},{})

-- listing tests
cmd_test(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "ls b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=2,[2]=link_err})
cmd_test(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "list b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
cmd_test(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "ls -1"},
  {a="hi",b={"c"},c={"b"}},{[1]="a\nb\nc"})

cmd_test(
  {"echo -n foo > a", "cp -r a/. w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

cmd_test(
  {"echo -n foo > a", "cp -r a/ w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

cmd_test(
  {"echo -n data > b", "cp b/ j"},
  {b='data'},{exit_code=1,[2]=not_a_dir})

cmd_test(
  {"echo -n data > b", "cp b/. j"},
  {b='data'},{exit_code=1,[2]=not_a_dir})

cmd_test(
  {"mkdir a", "mkdir d", "echo -n data > a/file", "mkdir d/file", "cp -r a/. d"},
  {a=true,d=true,["a/file"]="data",["d/file"]=true},{exit_code=1,[2]=non_dir})

print("early exit, mv not ready")
os.exit(0)

cmd_test(
  {"echo -n data > b_0", "echo -n more > b_1", "mkdir w", "echo -n old > w/b_1", "/bin/mv b_* w"},
  {w=true,["w/b_0"]="data",["w/b_1"]="more"},{})

cmd_test(
  {"echo -n b > b", "/bin/mv b a"},
  {a='b'},{})

cmd_test(
  {"echo -n b > b", "/bin/mv b"},
  {b='b'},{exit_code=1,[1]='Usage'})

cmd_test(
  {"echo -n b > b", "/bin/mv b ''"},
  {b='b'},{exit_code=1,[2]=no_such})

fake_fs.isReadOnly = function() return true end
cmd_test({"echo -n b > b", function()
  fake_fs.path = shell.getWorkingDirectory() .. '/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "mv b fake/b"},
{
  fake=true,
  ["b"]="b",
  ["fake/fake_file"]="abc",
},{exit_code=1,[2]=readonly_fs})
fs.umount(fake_fs.path)

cmd_test({function()
  fake_fs.path = shell.getWorkingDirectory() .. '/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "mv fake/fake_file b"},
{
  fake=true,
  b="abc", -- copy should work, only rm should fail
  ["fake/fake_file"]="abc",
},{exit_code=1,[2]=readonly_fs})
fs.umount(fake_fs.path)

cmd_test({"/bin/mv /tmp ."}, {exit_code=1,[2]=cannot_move})
cmd_test({"mkdir a", "echo -n b > a/b", "/bin/mv a c"}, {c=true,["c/b"]="b"})
cmd_test({"echo -n b > b", "/bin/mv b /c", "/bin/mv /c w"}, {w="b"})
cmd_test({"mkdir d", "echo -n b > d/b", "/bin/mv d /c", "/bin/mv /c w"},{w=true,["w/b"]="b"})

--overwrites
cmd_test({"echo -n a > a", "echo -n b > b", "/bin/mv b a"},{a="b"})
cmd_test({"echo -n a > a", "echo -n b > b", "yes n | /bin/mv -i b a"},{a="a",b="b"},{"overwrite 'a'?"})
cmd_test({"echo -n a > a", "echo -n b > b", "/bin/mv -i -f b a"},{a="b"})
cmd_test({"echo -n a > a", "echo -n b > b", "/bin/mv -f b a"},{a="b"})
cmd_test({"echo -n a > a", "echo -n b > b", "/bin/mv -v b a"},{a="b"},{"'b' -> 'a'"})

cmd_test({
  "echo -n a > a",
  "ln a b",
  "rm a",
  "ln b c",
  "rm b",
  "ln c b",
  "mv b w",
}, {c={"b"},b={"w"}}, {})

cmd_test(
  {"echo -n a > a", "echo -n b > b", "/bin/mv b a"},
  {a="b",},{})

cmd_test(
  {"echo -n b > b", "/bin/mv b ''"},
  {b='b'},{exit_code=1,[2]=no_such})

cmd_test(
  {"mkdir d", "echo -n data > d/b", "/bin/mv d d"},
  {d=true,["d/b"]="data"},{exit_code=1,[2]=to_subself})

cmd_test(
  {"echo -n data > b", "/bin/mv b b"},
  {b='data'},{exit_code=1,[2]=same_file})

-- actually a mv test
cmd_test({"echo -n foo > bar", "mv -f baz bar"}, {bar="foo"}, {exit_code=1,[2]=no_such})
cmd_test({"echo -n foo > bar", "mv -f '' bar"}, {bar="foo"}, {exit_code=1,[2]=no_such})
cmd_test({"echo -n foo > bar", "mv -f bar ''"}, {bar="foo"}, {exit_code=1,[2]="Cannot move.+"..no_such})
cmd_test({"echo -n foo > bar", "mv -f bar baz"}, {baz="foo"})
cmd_test(
  {"/bin/mv b a"},
  {},{exit_code=1,[2]=no_such})

cmd_test(
  {"echo -n b > b", "mkdir a", "/bin/mv b a"},
  {["a/b"]='b'},{})

cmd_test(
  {"mkdir a", "echo -n data > a/b", "/bin/mv a c"},
  {b=true,["b/c"]='data'},{})

cmd_test(
  {"mkdir a", "echo -n data > b", "/bin/mv a b"},
  {a=true,b='data'},{exit_code=1,[2]=dir_non_dir})

cmd_test(
  {"echo -n b > b", "/bin/mv b a"},
  {a='b'},{})

cmd_test(
  {"echo -n foo > a", "mv a/. w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

cmd_test(
  {"mkdir a", "echo -n data > a/c", "mv a/. b"},
  {a=true,["a/c"]="data"}, {exit_code=1,[2]="invalid move path"})

cmd_test(
  {"mkdir a", "echo -n data > a/c", "mv a/ b"},
  {b=true,["b/c"]="data"}, {})
