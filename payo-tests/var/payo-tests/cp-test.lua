local testutil = require("testutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = require("shell")

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local omit = "omitting directory.+"
local into_itself = "cannot write a directory.+ into itself"
local no_such = "No such file or directory"
local non_dir = "cannot overwrite directory.+with non%-directory"
local dir_non_dir = "cannot overwrite non%-directory.+with directory"
local same_file = " and .+are the same file\n$"
local overwrite = "overwrite.+%?"
local readonly_fs = "filesystem is readonly"
local cannot_move = "it is a mount point"
local not_a_dir = "is not a directory"

shell.setAlias("cp")

testutil.run_cmd({"echo foo > a", "cp a b"}, {a="foo\n", b="foo\n"})
testutil.run_cmd({"echo -n foo > a", "cp a b"}, {a="foo", b="foo"})
testutil.run_cmd({"echo -n foo > a", "echo -n bar > b", "cp a b"}, {a="foo", b="foo"})
testutil.run_cmd({"echo -n foo > a", "echo -n bar > b", "cp -n a b"}, {a="foo", b="bar"})
testutil.run_cmd({"mkdir a"}, {a=true})
testutil.run_cmd({"mkdir a", "cp a b"}, {a=true}, {exit_code=1,[1]=omit.."a"})
testutil.run_cmd({"mkdir a", "cp -r a b"}, {a=true,b=true})
testutil.run_cmd({"mkdir a", "echo -n foo > a/b", "cp -r a b"}, {a=true,b=true,["a/b"]="foo",["b/b"]="foo"})

testutil.run_cmd({"echo hi > a", "ln a b", "cp a b"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})
testutil.run_cmd({"echo hi > a", "ln a b", "cp b a"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})

testutil.run_cmd({"echo hi > a", "ln a b", "cp -P a b"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})
testutil.run_cmd({"echo hi > a", "ln a b", "cp -P b a"}, {a="hi\n",b={"a"}}, {exit_code=1,[2]=same_file})

testutil.run_cmd({"echo hi > a", "ln a b", "mkdir c", "cp c b"}, {a="hi\n",b={"a"},c=true}, {exit_code=1,[1]=omit.."c"})
testutil.run_cmd({"echo hi > a", "ln a b", "mkdir c", "cp -r c b"}, {a="hi\n",b={"a"},c=true}, {exit_code=1,[2]=dir_non_dir})

testutil.run_cmd({"echo hi > a", "ln a b", "echo bye > c", "cp c b"}, {a="bye\n",b={"a"},c="bye\n"})
testutil.run_cmd({"echo hi > a", "ln a b", "echo bye > c", "cp b c"}, {a="hi\n",b={"a"},c="hi\n"})

testutil.run_cmd({"echo hi > a", "mkdir d", "mkdir d/a", "cp a d"}, {a="hi\n",d=true,["d/a"]=true},{exit_code=1,[2]=non_dir})
testutil.run_cmd({"echo hi > a", "mkdir d", "mkdir d/a", "yes y | cp -i a d"}, {a="hi\n",d=true,["d/a"]=true},{exit_code=1,[1]=overwrite,[2]=non_dir})
testutil.run_cmd({"echo hi > a", "mkdir d", "mkdir d/a", "yes n | cp -i a d"}, {a="hi\n",d=true,["d/a"]=true},{[1]=overwrite})

testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -r b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -r b d", "echo -n bye > d/a", "cat d/b"}, {["d/a"]="bye",a="hi",b={"a"},d=true,["d/b"]={"a"}}, {"bye"})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -rv b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}}, {[1]={"removed 'd/b'","b %->.+d/b"}})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -nr b d"}, {a="hi",b={"a"},d=true,["d/b"]=""})

testutil.run_cmd({"mkdir a", "echo -n foo > a/b", "cd a;ln -s b c;cd ..", "cp -r a d", "echo -n bye > d/c"}, {a=true,["a/b"]="foo",["a/c"]={"b"},d=true,["d/b"]="bye",["d/c"]={"b"}})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -P b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -Pv b d"}, {a="hi",b={"a"},d=true,["d/b"]={"a"}}, {[1]={"removed 'd/b'","b %->.+d/b"}})
testutil.run_cmd({"echo -n hi > a", "mkdir d", "touch d/b", "ln -s a b", "cp -nP b d"}, {a="hi",b={"a"},d=true,["d/b"]=""})

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

testutil.run_cmd({"echo -n data > file"}, {file="data"})
testutil.run_cmd({"mkdir a", function()
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

testutil.run_cmd({"mkdir a", function()
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

testutil.run_cmd({"echo -n foo > a", "ln -s a b", "cp b c", "cp -P b d"}, {a="foo",b={"a"},c="foo",d={"a"}})
testutil.run_cmd({"mkdir a", "echo -n foo > a/b", "cd a;ln -s b c;cd ..", "cp -r a d", "echo -n bye > d/c"},
{
  a=true,
  ["a/b"]="foo",
  ["a/c"]={"b"},
  d=true,["d/b"]="bye",
  ["d/c"]={"b"}
})
testutil.run_cmd({"mkdir a", "mkdir d", "echo -n foo > a/b", "ln -s a/b a/c", "cp -r a d"},
{
  a=true,d=true,["d/a"]=true,
  ["a/b"]="foo",["d/a/b"]="foo",
  ["a/c"]={"a/b"},["d/a/c"]={"a/b"}
})

testutil.run_cmd({"mkdir a", "echo -n foo > a/b", "cp -r a a/../a"}, {a=true,["a/b"]="foo"}, {exit_code=1,[2]=into_itself})
testutil.run_cmd({"mkdir a", "cp a b"}, {a=true}, {exit_code=1,[1]=omit.."a"})
testutil.run_cmd({"mkdir d", "touch a", "cp d/../a a"}, {d=true,a=""}, {exit_code=1,[2]=" and .+are the same file\n$"})
testutil.run_cmd({"mkdir a", "mkdir a/b", "touch b", "cp b a"}, {a=true,["a/b"]=true,b=""}, {exit_code=1,[2]=non_dir})

-- some bugs
testutil.run_cmd({"echo foo > b","cp a b"},{b="foo\n"},{exit_code=1,[2]=no_such})
testutil.run_cmd({"echo foo > b","cp -u a b"},{b="foo\n"},{exit_code=1,[2]=no_such})

-- /. support!
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w","cp -r a/. b/."},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir b","echo -n foo > b/w","cp -r a/. b"},{b=true,["b/w"]="foo"},{exit_code=1,[2]=no_such})
testutil.run_cmd({"mkdir b","cp -r b/. b"},{b=true},{exit_code=1,[2]=into_itself})
testutil.run_cmd({"mkdir b","cp -r b/. b/."},{b=true},{exit_code=1,[2]=into_itself})
testutil.run_cmd({"mkdir a","mkdir a/d","mkdir b","echo -n foo > b/d","cp -r b/. a"},{a=true,b=true,["a/d"]=true,["b/d"]="foo"},{exit_code=1,[2]=non_dir})
testutil.run_cmd({"mkdir a","mkdir a/d","mkdir b","echo -n foo > a/w","cp -r a/d/.. b"},{a=true,b=true,["a/d"]=true,["b/d"]=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir b","mkdir b/d","mkdir b/d/w","cp -r b/d b/d/w"},{b=true,["b/d"]=true,["b/d/w"]=true},{exit_code=1,[2]=into_itself})
testutil.run_cmd({"mkdir a","mkdir b","mkdir a/d","echo -n foo > a/w","cp -r a/d/.. b"},{a=true,b=true,["a/d"]=true,["a/w"]="foo",["b/d"]=true,["b/w"]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","touch a/...","echo -n foo > a/w","cp -r a/. b"},{a=true,b=true,["a/..."]="",["a/w"]="foo",["b/..."]="",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w.","cp -r a/w. b"},{a=true,b=true,["a/w."]="foo",["b/w."]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w..","cp -r a/w.. b"},{a=true,b=true,["a/w.."]="foo",["b/w.."]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r . ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r ./. ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","mkdir b","echo -n foo > a/w","cd a && cp -r ./../a/. ../b"},{a=true,b=true,["a/w"]="foo",["b/w"]="foo",})
testutil.run_cmd({"mkdir a","echo -n notadir > b","cp -r a/. b/"},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})
testutil.run_cmd({"mkdir a","echo -n notadir > b","cp -r a/. b/."},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})
-- print("todo, fs segments is hiding /.. issues")
--testutil.run_cmd({"mkdir a","echo -n notadir > b","cp -r a/. b/.."},{a=true,b="notadir"},{exit_code=1,[2]="not a directory"})

-- found weird contents of bug when reworking cp and mv
testutil.run_cmd({"echo -n hi > a", "mkdir d", "echo -n foo > d/b", "ln -s a b", "cp -r b/. d"}, {a="hi",b={"a"},d=true,["d/b"]="foo"},{exit_code=1,[2]=not_a_dir})
testutil.run_cmd({"echo -n hi > a", "ln a b", "mkdir c", "cp b c"}, {a="hi", b={"a"}, c=true, ["c/b"]="hi"})
testutil.run_cmd({"echo -n hi > a", "ln a b", "mkdir c", "cp -P b c"}, {a="hi", b={"a"}, c=true, ["c/b"]={"a"}})
testutil.run_cmd({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp b d"}, {a="hi", b={"a"}, c=true, d={"c"}, ["c/b"]="hi"})
testutil.run_cmd({"echo -n hi > a", "ln a b", "mkdir c", "ln c d", "cp -P b d", "echo -n bye > c/a", "cat d/b"},
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
testutil.run_cmd({"echo -n hi > a", "ln a b", "cp -r b c", "cp -r c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp -P of same file allowed
testutil.run_cmd({"echo -n hi > a", "ln a b", "cp -P b c", "cp -P c b"}, {a="hi", b={"a"}, c={"a"}})

-- cp ln to ln not allowed
testutil.run_cmd({"echo -n hi > a", "ln a b", "cp -r b c", "cp c b"}, {a="hi", b={"a"}, c={"a"}}, {exit_code=1,[2]=same_file})

-- cp -r of dir with ln allowed with same file
testutil.run_cmd({"echo -n hi > a", "mkdir d1", "cd d1;ln ../a;cd ..", "cp -r d1/. d2", "cp -r d1/. d2"}, {a="hi", d1=true, d2=true, ["d1/a"]={"../a"}, ["d2/a"]={"../a"}})

-- ln of missing file should error
testutil.run_cmd({"ln a b"}, {}, {exit_code=1,[2]=no_such})
testutil.run_cmd({"touch a", "ln a b", "rm a", "ln b c"}, {b={"a"},c={"b"}})

--cp -r . should work the same as cp -r ./.
local function common_result() return {a=true,["a/c"]="hi",["a/d"]=true,["a/d/c"]="np",b=true,["b/c"]="hi",["b/d"]=true,["b/d/c"]="np"} end

testutil.run_cmd({"mkdir b", "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cd .."              }, common_result())
testutil.run_cmd({"mkdir b", "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cp -r . ../b; cd .."}, common_result())
testutil.run_cmd({           "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cd .."              }, common_result())
testutil.run_cmd({           "mkdir a", "echo -n hi > a/c", "mkdir a/d", "echo -n np > a/d/c", "cd a; cp -r . ../b; cp -r . ../b; cd .."}, common_result())

-- this is a glob-test, but the cmd list nature of the testutil.run_cmd will help simplify the setup
testutil.run_cmd({"mkdir a", "mkdir b", "touch b/c", "touch b/d", "cd b; ls *"}, {a=true,b=true,["b/c"]="", ["b/d"]=""}, {[1]={"c","d","\n"}})
testutil.run_cmd({"mkdir a", "mkdir b", "touch b/c", "touch b/d", "cd a; ls ../b/*"}, {a=true,b=true,["b/c"]="", ["b/d"]=""}, {[1]={"../b/c","../b/d","\n"}})


-- a regression, of course! copy dir to new name but similar name!
testutil.run_cmd({"mkdir a", "echo -n foo > a/b", "cp -r a aa"}, {a=true,aa=true,["a/b"]="foo", ["aa/b"]="foo"})

-- actually a rm test
testutil.run_cmd({"rm foo"}, {}, {exit_code=1,[2]=no_such})
testutil.run_cmd({"rm -f foo"}, {})

-- test inf loops
local link_err = "link cycle detected"
testutil.run_cmd({"mkdir a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cd b"}, {a=true,b={"c"},c={"b"}}, {exit_code=1, [2]="cd.+not a directory"})
testutil.run_cmd({"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat c"}, {a="hi",b={"c"},c={"b"}}, {exit_code=1, [2]="cat.+"..link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "mkdir d", "ln -s d e", "ln -s e f", "rm e", "ln -s f e", "ls", "cat b"},
  {a="hi",b={"c"},c={"b"},d=true,e={"f"},f={"e"}},
  {exit_code=1,[1]="a *b *c *d *e *f",[2]="cat.+"..link_err})

-- should fail to cycle
-- cp to file
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp b w"},
  {a="hi",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to link cycle
testutil.run_cmd(
  {"echo -n hi > a", "echo -n bye > w", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp w b"},
  {a="hi",w="bye",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to dir
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "mkdir d", "cp b d/w"},
  {a="hi",b={"c"},c={"b"},d=true},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})
-- cp to cycle with dir notation
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp a b/w"},
  {a="hi",b={"c"},c={"b"}},
  {exit_code=1,[1]="",[2]="cp.+"..link_err})

-- should allow cycle
-- cp -P
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp -P b w"},
  {a="hi",b={"c"},c={"b"},w={"c"}})

-- test copy to link cycle as if dir
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp a b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]="cp.+"..link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cp -P a b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]="cp.+"..link_err})

-- touch should complain about link cylce, not permission
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "touch b"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "touch b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})

--saw some errors with cat
testutil.run_cmd({"echo hi | cat"},{},{"hi\n"})
testutil.run_cmd({"echo -n hi | cat"},{},{"hi"})
testutil.run_cmd({"echo hi | cat -"},{},{"hi\n"})
testutil.run_cmd({"echo -n hi | cat -"},{},{"hi"})

testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat b"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "ln -s b c", "rm b", "ln -s c b", "cat b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln -s a b", "cat a"},
  {a="hi",b={"a"}},{"hi"})

-- fs exists check

local assert_txt = "assert(not require('filesystem').exists(require('shell').resolve('b/w')))" 
testutil.run_cmd(
  {"echo -n \""..assert_txt.."\" > a",
   "ln a b", "ln b c", "rm b", "ln c b", "./a"},
  {a=assert_txt,b={"c"},c={"b"}},{})

-- listing tests
testutil.run_cmd(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "ls b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=2,[2]=link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "list b/w"},
  {a="hi",b={"c"},c={"b"}},{exit_code=1,[2]=link_err})
testutil.run_cmd(
  {"echo -n hi > a", "ln a b", "ln b c", "rm b", "ln c b", "ls -1"},
  {a="hi",b={"c"},c={"b"}},{[1]="a\nb\nc"})

testutil.run_cmd(
  {"echo -n foo > a", "cp -r a/. w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

testutil.run_cmd(
  {"echo -n foo > a", "cp -r a/ w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

testutil.run_cmd(
  {"echo -n data > b", "cp b/ j"},
  {b='data'},{exit_code=1,[2]=not_a_dir})

testutil.run_cmd(
  {"echo -n data > b", "cp b/. j"},
  {b='data'},{exit_code=1,[2]=not_a_dir})

testutil.run_cmd(
  {"mkdir a", "mkdir d", "echo -n data > a/file", "mkdir d/file", "cp -r a/. d"},
  {a=true,d=true,["a/file"]="data",["d/file"]=true},{exit_code=1,[2]=non_dir})

-- rm fails in linked dir
testutil.run_cmd(
  {"echo -n hi > a; ln a b; mkdir c; ln c d; cp -P b d; rm d/b"},
  {a='hi',b={'a'},c=true,d={'c'}}, {})

testutil.run_cmd(
  {"echo -n data > b_0", "echo -n more > b_1", "mkdir w", "echo -n old > w/b_1", "/bin/mv b_* w"},
  {w=true,["w/b_0"]="data",["w/b_1"]="more"},{})

testutil.run_cmd(
  {"echo -n b > b", "/bin/mv b a"},
  {a='b'},{})

testutil.run_cmd(
  {"echo -n b > b", "/bin/mv b"},
  {b='b'},{exit_code=1,[1]='Usage'})

testutil.run_cmd(
  {"echo -n b > b", "/bin/mv b ''"},
  {b='b'},{exit_code=1,[2]=no_such})

fake_fs.address = "i don't have an address"
fake_fs.isReadOnly = function() return true end
fake_fs.getLabel = function() return "still_here" end
testutil.run_cmd({"echo -n b > b", function()
  fake_fs.path = shell.getWorkingDirectory() .. '/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "mv b fake/b"},
{
  fake=true,
  ["b"]="b",
  ["fake/fake_file"]="abc",
},{exit_code=1,[2]=readonly_fs})
fs.umount(fake_fs.path)

testutil.run_cmd({function()
  fake_fs.path = shell.getWorkingDirectory() .. '/fake'
  fs.mount(fake_fs, fake_fs.path)
end, "mv fake/fake_file b"},
{
  fake=true,
  b="abc", -- copy should work, only rm should fail
  ["fake/fake_file"]="abc",
},{exit_code=1,[2]=readonly_fs})
fs.umount(fake_fs.path)

testutil.run_cmd({"/bin/mv /tmp ."}, {}, {exit_code=1,[2]=cannot_move})
testutil.run_cmd({"mkdir a", "echo -n b > a/b", "/bin/mv a c"}, {c=true,["c/b"]="b"})
testutil.run_cmd({"cd /tmp", "echo -n b > b", "/bin/mv b /tmp/c", "/bin/mv /tmp/c w", "cd - >/dev/null", "/bin/mv /tmp/w ."}, {w="b"})
testutil.run_cmd({"mkdir d", "echo -n b > d/b", "/bin/mv d /tmp/c", "/bin/mv /tmp/c w"},{w=true,["w/b"]="b"})

--overwrites
testutil.run_cmd({"echo -n a > a", "echo -n b > b", "/bin/mv b a"},{a="b"})
testutil.run_cmd({"echo -n a > a", "echo -n b > b", "yes n | /bin/mv -i b a"},{a="a",b="b"},{"overwrite 'a'?"})
testutil.run_cmd({"echo -n a > a", "echo -n b > b", "yes y | /bin/mv -i -f b a"},{a="b"})
testutil.run_cmd({"echo -n a > a", "echo -n b > b", "/bin/mv -f b a"},{a="b"})
testutil.run_cmd({"echo -n a > a", "echo -n b > b", "/bin/mv -v b a"},{a="b"},{"b %-> a"})

testutil.run_cmd({
  "echo -n a > a",
  "ln a b",
  "rm a",
  "ln b c",
  "rm b",
  "ln c b",
  "mv b w",
}, {c={"b"},w={"c"}}, {})

testutil.run_cmd(
  {"echo -n a > a", "echo -n b > b", "/bin/mv b a"},
  {a="b",},{})

testutil.run_cmd(
  {"echo -n b > b", "/bin/mv b ''"},
  {b='b'},{exit_code=1,[2]=no_such})

testutil.run_cmd(
  {"mkdir d", "echo -n data > d/b", "/bin/mv d d"},
  {d=true,["d/b"]="data"},{exit_code=1,[2]=into_itself})

testutil.run_cmd(
  {"echo -n data > b", "/bin/mv b b"},
  {b='data'},{exit_code=1,[2]=same_file})

-- actually a mv test
testutil.run_cmd({"echo -n foo > bar", "mv -f baz bar"}, {bar="foo"}, {exit_code=1,[2]=no_such})
testutil.run_cmd({"echo -n foo > bar", "mv -f '' bar"}, {bar="foo"}, {exit_code=1,[2]=no_such})
testutil.run_cmd({"echo -n foo > bar", "mv -f bar ''"}, {bar="foo"}, {exit_code=1,[2]="cannot create.+"..no_such})
testutil.run_cmd({"echo -n foo > bar", "mv -f bar baz"}, {baz="foo"})
testutil.run_cmd(
  {"/bin/mv b a"},
  {},{exit_code=1,[2]=no_such})

testutil.run_cmd(
  {"echo -n b > b", "mkdir a", "/bin/mv b a"},
  {a=true,["a/b"]='b'},{})

testutil.run_cmd(
  {"mkdir a", "echo -n data > a/b", "/bin/mv a c"},
  {c=true,["c/b"]='data'},{})

testutil.run_cmd(
  {"mkdir a", "echo -n data > b", "/bin/mv a b"},
  {a=true,b='data'},{exit_code=1,[2]=dir_non_dir})

testutil.run_cmd(
  {"echo -n b > b", "/bin/mv b a"},
  {a='b'},{})

testutil.run_cmd(
  {"echo -n foo > a", "mv a/. w"},
  {a="foo"}, {exit_code=1,[2]=not_a_dir})

testutil.run_cmd(
  {"mkdir a", "echo -n data > a/c", "mv a/. b"},
  {a=true,["a/c"]="data"}, {exit_code=1,[2]="invalid move path"})

testutil.run_cmd(
  {"mkdir a", "echo -n data > a/c", "mv a/ b"},
  {b=true,["b/c"]="data"}, {})

testutil.run_cmd(
  {"mkdir test test/zz test2 test2/test", "echo -n foo > test/w", "mv -v test test2"},
  {test2=true,["test2/test"]=true,["test2/test/w"]="foo",["test2/test/zz"]=true}, {"test %-> test2/test"})

testutil.run_cmd(
  {"mkdir test test2 test2/test", "echo -n foo > test/w", "mv -v test test2"},
  {test2=true,["test2/test"]=true,["test2/test/w"]="foo"}, {".*test %-> .*test2/test"})

testutil.run_cmd(
  {"mkdir test test2 test2/test", "echo -n foo > test/w", "echo -n bar > test2/test/w", "mv -v test test2"},
  {test=true,test2=true,["test2/test"]=true,["test/w"]="foo",["test2/test/w"]="bar"},
  {exit_code=1,[2]="cannot move.+test.+to.+test2/test.+Directory not empty"})

testutil.run_cmd(
  {"mkdir test test2 test2/test", "echo -n foo > test/w", "echo -n bar > test2/test/j", "mv -v test test2"},
  {test=true,test2=true,["test2/test"]=true,["test/w"]="foo",["test2/test/j"]="bar"},
  {exit_code=1,[2]="cannot move.+test.+to.+test2/test.+Directory not empty"})

testutil.run_cmd(
  {"mkdir test test2 test2/test", "echo -n foo > test/w", "echo -n bar > test2/test/j", "cp -v test test2"},
  {test=true,test2=true,["test2/test"]=true,["test/w"]="foo",["test2/test/j"]="bar"},
  {exit_code=1,omit.."test"})

testutil.run_cmd(
  {"mkdir test test2 test2/test", "echo -n foo > test/w", "echo -n bar > test2/test/j", "cp -rv test test2"},
  {test=true,test2=true,["test2/test"]=true,["test/w"]="foo",["test2/test/j"]="bar",["test2/test/w"]="foo"},
  {"test/w %-> .*test2/test/w"})

testutil.run_cmd({"echo -n hi >'>' bye"}, {[">"]="hi bye"}, {})
testutil.run_cmd({"echo -n hi >'>'bye", "echo -n a * b"}, {[">bye"]="hi"}, {"a >bye b"})
testutil.run_cmd({"echo -n hi >'>'"}, {[">"]="hi"}, {})
testutil.run_cmd({"touch 2", "echo -n hi >*"}, {["2"]="hi"}, {})
testutil.run_cmd({"echo -n hi >2f"}, {["2f"]="hi"}, {})
testutil.run_cmd({"touch 2foo", "echo -n hi >2*"}, {["2foo"]="hi"}, {})
testutil.run_cmd({">&2 echo -n hi"}, {}, {[2]="hi"})
testutil.run_cmd({"> foo echo -n hi"}, {foo="hi"}, {})
testutil.run_cmd({"echo -n hi >'world'"}, {world="hi"}, {})
testutil.run_cmd({"echo -n hi '>' world"}, {}, {"hi > world"})
testutil.run_cmd({"set C='>'", "echo -n hi $C world"}, {}, {"hi > world"})
testutil.run_cmd({"echo -n hi `echo '>'` world"}, {}, {"hi > world"})
testutil.run_cmd({"set C='>'", "echo -n hi \"$C\" world"}, {}, {"hi > world"})
testutil.run_cmd({"touch 1 2", "set C='*'", "echo hi >$C"}, {["1"]="",["2"]=""}, {exit_code=1, [2]="ambiguous redirect"})
testutil.run_cmd({"touch 1", "set C='*'", "echo -n hi >$C"}, {["1"]="hi"}, {})
testutil.run_cmd({"touch 1", "set C='*'", "echo -n hi '>'$C"}, {["1"]=""}, {"hi >*"})
testutil.run_cmd({"echo hi|>grep hi"}, {grep=""}, {exit_code=127,[2]="hi: file not found"})

