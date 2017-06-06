local testutil = require("testutil");
local fs = require("filesystem")
local shell = require("shell")
local text = require("text")
local tx = require("transforms")
local sh = require("sh")

-- os.execute(cmd) was breaking env var _ due to process.load throwing it away
do
  local backup__ = os.getenv("_")
  os.setenv("_", "foo")
  os.execute("cd .")
  local value = os.getenv("_")
  os.setenv("_", backup__)
  testutil.assert("_ is lost okay", "foo", value)
end

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local chdir = shell.setWorkingDirectory

local ser = require('serialization').serialize

local function run_in_test_dir(cmds, verify)
  local tmp_dir_path = mktmp('-d','-q')
  local home = shell.getWorkingDirectory()
  chdir(tmp_dir_path)

  for _,cmd in ipairs(cmds) do
    os.execute(cmd)
  end

  local verify_result = table.pack(pcall(verify))
  fs.remove(tmp_dir_path)
  chdir(home)

  testutil.assert("run_in_test_dir", true, table.unpack(verify_result))
end

local function tt(...)
  local pack = {}
  local args = {...}
  if #args == 0 then
    return pack
  end

  local i=1
  while i<=#args do
    local next = {}
    next.txt = args[i]

    if args[i+1] == true then
      next.qr = {'"','"'}
      i = i + 1
    end

    table.insert(pack, next)

    i = i + 1
  end

  return pack
end

local function _s(...)
  local result = {}

  for i,v in pairs({...}) do
    if type(v) == 'string' then
      table.insert(result, tt(v))
    elseif type(v) == 'table' then
      table.insert(result, v)
    end
  end

  return result
end

local function ss(...)
  local s = {}
  -- true moves to the next statement
  for i,v in ipairs({...}) do
    if type(v) == 'string' then
      if #s==0 then s[1]={} end
      table.insert(s[#s], tt(v))
    elseif type(v) == 'table' then
      table.insert(s, v)
    end
  end

  return s
end

local function rtok(input, defs, exp)
  local function resolver(key)
    return defs[key] or key
  end

  local resolved, reason = sh.internal.resolveActions(input, resolver)
  local words = {}
  local norms = {}
  if resolved then
    words = resolved
    resolved = text.internal.normalize(resolved)
    norms = resolved
    resolved = table.concat(resolved, ' ')
  end

  testutil.assert('rtok:'..ser(input), exp, resolved, ser(words)..':'..ser(norms))
end

rtok('', {}, '')
rtok('a', {['a']='b'}, 'b')
rtok('a;c', {['a']='b',['c']='d'}, 'b ; d')
rtok('a;c', {['a']='b',['c']='d',['d']='f'}, 'b ; f')
rtok('a', {['a']='b',['b']='c',['c']='a'}, 'a')
rtok('a b c;d e f', 
  {['a']='b',['b']='c',['c']='d',['d']='e',['e']='f',['f']='g'},
  'g b c ; g e f')
rtok('a e"', {['a']='b "'}, nil)
rtok('a e"', {['a']='b'}, nil) -- parse error at "
rtok('a ;"', {['a']='b "'}, nil)
rtok('q e1" ; q e2"', {['q']='c a"'}, nil)

rtok('a b c d e',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'1 b c d e')
rtok('a b c;d e',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'1 b c ; 4 e')
rtok('a b c;d|e>>f g h;i',
  {['a']='1',['b']='2',['c']='3',['d']='4',['e']='5',['f']='6',['g']='7',['h']='8',['i']='9'},
  '1 b c ; 4 | 5 >> f g h ; 9')
rtok('a b" c;d" e',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'1 b" c;d" e')
rtok('a b" c;d',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},nil)
rtok('"a" b; c',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'"a" b ; 3')
rtok('a b;"" c',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'1 b ; "" c')
rtok('a b;c;"" d',{['a']='1',['b']='2',['c']='3',['d']='4',['e']='5'},'1 b ; 3 ; "" d')
rtok('"',{},nil)
rtok(';a',{['a']='b'},'; b')
rtok(';a ! a a',{['a']='b'},'; b ! a a')
rtok(';;;;;;a',{['a']='b'},'; ; ; ; ; ; b')
rtok(';a||a&&a>a>>a<a ! a;! a',{['a']='b'},'; b || b && b > a >> a < a ! a ; ! b')

local function states(input, ex)
  testutil.assert('states`'..input..'`',ex,sh.internal.splitStatements(text.tokenize(input,{doNotNormalize=true})))
end

local prev_grep = shell.getAlias('grep')
shell.setAlias('grep',nil)

states('echo|hi foo bar;', {{tt('echo'),tt('|'),tt('hi'),tt('foo'),tt('bar')}})
states('echo hi',          {{tt('echo'),tt('hi')}})
states(';echo hi;',        {{tt('echo'),tt('hi')}})
states('echo hi|grep hi',  {{tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi')}})
states('|echo hi|grep hi', {{tt('|'),tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi')}})
states('echo hi|grep hi|', {{tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi'),tt('|')}})
states('echo hi| |grep hi', {{tt('echo'),tt('hi'),tt('|'),tt('|'),tt('grep'),tt('hi')}})
states('echo hi|;|grep hi',{{tt('echo'),tt('hi'),tt('|')},{tt('|'),tt('grep'),tt('hi')}})
states('echo hi|>grep hi', {{tt('echo'),tt('hi'),tt('|'),tt('>'),tt('grep'),tt('hi')}})
states('echo hi|;grep hi', {{tt('echo'),tt('hi'),tt('|')},{tt('grep'),tt('hi')}})
states('echo hi>>grep hi', {{tt('echo'),tt('hi'),tt('>>'),tt('grep'),tt('hi')}})
states('echo hi>>>grep hi',{{tt('echo'),tt('hi'),tt('>>'),tt('>'),tt('grep'),tt('hi')}})
states(';;echo hi;echo hello|grep hello|grep hello>>result;echo hi>result;;',
  {{tt('echo'),tt('hi')},{tt('echo'),tt('hello'),tt('|'),tt('grep'),tt('hello'),tt('|'),tt('grep'),tt('hello'),tt('>>'),tt('result')},{tt('echo'),tt('hi'),tt('>'),tt('result')}})
states(';result<grep foobar>result;', {{tt('result'),tt('<'),tt('grep'),tt('foobar'),tt('>'),tt('result')}})
states('',  {})
states(';', {})
states(';;;;;;;;;', {})
states('";;;;;;;;;"', {{tt(';;;;;;;;;',true)}})
states('echo;grep', {{tt('echo')},{tt('grep')}})
states('echo;g"r"ep', {{tt('echo')},{tt('g', 'r',true,'ep')}})
states('a;"b"c', {{tt('a')},{tt('b',true,'c')}})

local function vt(cmd, ...)
  local tokens = text.internal.tokenize(cmd)
  local states = sh.internal.splitStatements(tokens)

  local ex = {...}
  testutil.assert('vt prep:'..cmd, #ex, #states)

  for _,state in ipairs(states) do
    testutil.assert('vt:'..cmd, ex[_], sh.internal.hasValidPiping(state))
  end
end

vt('echo hi', true)
vt('echo hi;', true)
vt(';echo hi;', true)
vt('echo hi|grep hi', true)
vt('|echo hi|grep hi', false)
vt('echo hi|grep hi|', false)
vt('echo hi| |grep hi', false)
vt('echo hi|;|grep hi', false, false)
vt('echo hi|>grep hi', true)
vt('echo hi|grep hi', true)
vt('echo hi|;grep hi', false, true)
vt('echo hi>>grep hi', true)
vt(';;echo hi;echo hello|grep hello|grep hello>>result;echo hi>result;;', true, true, true)
vt(';result<grep foobar>result;', true)
vt('')
vt(';')
vt(';;;;;;;;;')
vt('echo hi >&2', true)
vt("echo|grep", true)
vt("echo''|grep", true)
vt('echo""|grep', true)
vt("echo|''|grep", true)
vt('echo|""|grep', true)

vt("echo | grep", true)
vt("echo '' | grep", true)
vt('echo "" | grep', true)
vt("echo | '' | grep", true)
vt('echo | "" | grep', true)

vt("echo |grep", true)
vt("echo ''| grep", true)
vt('echo"" |grep', true)
vt("echo |'' | grep", true)
vt('echo | ""|grep', true)
vt('echo "|"|grep', true)

local function id(name, ex)
  testutil.assert('id:'..tostring(name), ex, sh.internal.isIdentifier(name))
end

id('', false)
id(' ', false)
id('abc', true)
id('1abc', false)
id('abc1', true)
id(' abc1', false)

-- the following tests simply check if shell.evaluate calls glob
-- we only want globbing on non-quoted strings

local function evalglob(files, value, exp)
  local touch_all = ""
  if #files > 0 then
    touch_all = "touch " .. table.concat(files, " ")
  end
  run_in_test_dir({touch_all}, function()
    local f = io.popen("echo " .. value)
    local names = text.tokenize(f:read("*a"))
    f:close()

    for _,exp_file in ipairs(exp) do
      local index
      for key,name in pairs(names) do
        if name == exp_file then
          index = key
        end
      end
      testutil.assert("expected file", true, not not index, string.format("[%s] not in [%s]", exp_file, ser(names)))
      names[index] = nil
    end
    testutil.assert("extra files", false, not not next(names), ser(names))
  end)
end

-- only plaintext * should glob
testutil.run_cmd({"touch foo","echo *"}, {foo=""}, {"foo"})
testutil.run_cmd({"echo *"}, {}, {"*"})
testutil.run_cmd({"touch a.foo b.foo c.fo", "echo *.foo", "rm *"}, {}, {"[ab].foo [ab].foo"})
testutil.run_cmd({"touch foo", "echo *", "rm foo"}, {}, {"foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo "*".foo]], "rm *"}, {}, {"*.foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo '*'.foo]], "rm *"}, {}, {"*.foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo '*.fo'o]], "rm *"}, {}, {"*.foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo '*."f"oo']], "rm *"}, {}, {'*.\"f\"oo'})
testutil.run_cmd({"touch a.foo b.foo", [[echo **]], "rm *"}, {}, {"a.foo b.foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo * *]], "rm *"}, {}, {"[ab].foo [ab].foo [ab].foo [ab].foo"})
testutil.run_cmd({"touch a.foo b.foo", [[echo "* * *"]], "rm *"}, {}, {"* * *"})

local function sc(input, rets, ...)
  rets = rets or {}
  local exp_all = {...}
  local states = sh.internal.statements(input)

  if type(states) ~= "table" then
    testutil.assert("sc:"..ser(input),table.remove(exp_all,1),states)
    return
  end

  local counter = 0
  tx.foreach(states, function(s, si)
    local chains = sh.internal.groupChains(s)

    sh.internal.boolean_executor(chains, function(chain,chain_index)
      local pipe_parts = sh.internal.splitChains(chain)
      local exp = table.remove(exp_all, 1)

      counter = counter + 1
      testutil.assert("sc:"..ser(input)..","..ser(counter)..","..ser(rets),exp,pipe_parts)
      local result = rets[chain_index]
      return result
    end)
  end)

  testutil.assert("sc:"..ser(input)..ser(rets)..",end of chains",0,#exp_all,ser(exp_all))
end

sc('',nil,true)
sc('echo hi',nil,{_s('echo','hi')})
sc('echo hi;echo done',nil,{_s('echo','hi')},{_s('echo','done')})
sc('echo hi|echo done',nil,{_s('echo','hi'),_s('echo','done')})
sc('a b|c d',nil,{_s('a','b'),_s('c','d')})
sc('a|b|c|d',nil,{_s('a'),_s('b'),_s('c'),_s('d')})
sc('a b|c;d',nil,{_s('a','b'),_s('c')},{_s('d')})

-- now the idea of chain splitting is actually chain grouping
sc('a||b&&c|d',nil,{_s('a')},{_s('c'),_s('d')})
sc('a&&b||c|d',nil,{_s('a')},{_s('b')})
sc('a||b||c|d',nil,{_s('a')})
sc('a||b&&c|d',{false},{_s('a')},{_s('b')},{_s('c'),_s('d')})
sc('! a||b&&c|d',{true},{_s('a')},{_s('b')},{_s('c'),_s('d')})
sc('!',nil,nil)

local function ps(cmd, out)
  testutil.assert('ps:'..cmd, out, sh.internal.statements(cmd))
end

ps("", true)
ps("|echo hi", nil)
ps('|echo hi|grep hi', nil)
ps('echo hi|grep hi|', nil)
ps('echo hi| |grep hi', nil)
ps('echo hi|;|grep hi',nil)
ps('echo hi|>grep hi', ss("echo","hi","|",">","grep","hi"))
ps('echo hi|;grep hi', nil)
ps('echo hi>>>grep hi', ss("echo","hi",">>",">","grep","hi"))
ps("echo", ss('echo'))
ps("echo hi", ss('echo','hi'))
ps('echo "hi"', ss(_s('echo',tt("hi",true))))
ps('echo hi "world"', ss(_s('echo','hi', tt("world",true))))
ps('echo test;echo hello|grep world>>result',
{
  _s('echo','test'),
  _s('echo','hello','|','grep','world','>>','result'),
})
ps('echo test; echo hello |grep world >>result',
{
  _s('echo','test'),
  _s('echo','hello','|','grep','world','>>','result'),
})

ps('|echo',        nil)
ps('|echo|',       nil)
ps('echo|',        nil)
ps('echo| |echo',   nil)
ps(';',           {})
ps(';;;;;;;',     {})
ps(';echo ignore;echo hello|grep hello>>result',
{
  _s('echo','ignore'),
  _s('echo','hello','|','grep','hello','>>','result'),
})

ps([[echo "hi"]],ss(_s('echo',tt('hi',true))))
ps([[";;;;;;"]],ss(_s(tt(';;;;;;',true))))

ps('echo&&test; echo||hello |grep world >>result',
{
  _s('echo','&&','test'),
  _s('echo','||','hello','|','grep','world','>>','result'),
})

-- new pipe delim tests
ps('||echo',nil)
ps('echo||',nil)
ps('echo|| ||echo',nil)
ps('echo||||echo',nil)
ps('echo||echo',ss('echo','||','echo'))

ps('&&echo',nil)
ps('echo&&',nil)
ps('echo&& &&echo',nil)
ps('echo&&&&echo',nil)
ps('echo&&echo',ss('echo','&&','echo'))

ps('echo&& ||echo',nil)
ps('echo&& |echo',nil)
ps('echo|| &&echo',nil)
ps('echo|| |echo',nil)
ps('echo&& ||echo',nil)
ps('echo| echo&&||',nil)
ps('||&&echo| echo',nil)
ps('||&&echo| echo',nil)

ps('! echo',{_s('!','echo')})

local function gc(input, expected)
  local statement = sh.internal.statements(input)[1]
  testutil.assert('gc:'..ser(input),expected,sh.internal.groupChains(statement))
end

gc('a&&b||c|d', {
  _s('a'),
  _s('&&'),
  _s('b'),
  _s('||'),
  _s('c','|','d')
})

gc('a b|c d', {
  _s('a','b','|','c','d'),
})

local function neg(input, expected,remain)
  local statem = sh.internal.statements(input)
  local chains = sh.internal.groupChains(statem[1])
  local actual = sh.internal.remove_negation(chains[1])
  testutil.assert('neg:'..ser(input),expected,actual)
  testutil.assert('neg remain:'..ser(input),remain,chains[1])
end

neg('! echo',true,{{{txt='echo'}}})
neg('! ! echo',false,{{{txt='echo'}}})
neg('echo',false,{{{txt='echo'}}})
neg('!',true,{})

shell.setAlias('grep',prev_grep)

local function set(key, exp)
  os.setenv("a","b")
  local actual = io.popen("echo -n "..key):read("*a")
  os.setenv("a")
  testutil.assert("set get:"..ser(key),exp,actual)
end

set("$a","b")
set("'$a'","$a")
set("\"$a\"","b")
set("'$'a","$a")
--set("\\$a","$a")

local function check_output(cmd, exp)
  local pipe = io.popen(cmd)
  local output = pipe:read("*a")
  pipe:close()
  testutil.assert("check output:"..cmd, exp, output)
end

check_output("echo hi", "hi\n")
check_output('echo "ls -1 --no-color /init.lua: `ls -1 --no-color /init.lua`"', "ls -1 --no-color /init.lua: /init.lua\n")

check_output("set foo='a    b'; echo -n $foo", "a b")
check_output("set foo='a    b'; echo -n '$foo'", "$foo")
check_output("set foo='a    b'; echo -n \"$foo\"", "a    b")
check_output("echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; cat /tmp/t; rm /tmp/t", "a  b\n\n\n")
check_output("echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo `cat /tmp/t`; rm /tmp/t", "a b\n")
check_output("echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo -n `cat /tmp/t`; rm /tmp/t", "a b")
check_output("echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo \"`cat /tmp/t`\"; rm /tmp/t", "a  b\n")
check_output("echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo -n \"`cat /tmp/t`\"; rm /tmp/t", "a  b")
check_output("set foo='x   y'; echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo \"`cat /tmp/t`\" \"$foo\" $foo; rm /tmp/t", "a  b x   y x y\n")
check_output("set foo='x   y'; echo 'a  b' > /tmp/t; echo '' >> /tmp/t; echo '' >> /tmp/t; echo -n \"`cat /tmp/t`\" \"$foo\" $foo; rm /tmp/t", "a  b x   y x y")

testutil.run_cmd({"echo *"},{},{"*"})
testutil.run_cmd({"echo .*"},{},{".*"})
testutil.run_cmd({"touch p.1 p.2","echo *"},{["p.1"]="",["p.2"]=""},{"p.[12] p.[12]"})
testutil.run_cmd({"touch p.1 p.2","echo p*"},{["p.1"]="",["p.2"]=""},{"p.[12] p.[12]"})
testutil.run_cmd({"touch p.1 p.2","echo p.*"},{["p.1"]="",["p.2"]=""},{"p.[12] p.[12]"})
testutil.run_cmd({"touch p.1 p.2","echo p.1*"},{["p.1"]="",["p.2"]=""},{"p.1"})
testutil.run_cmd({"touch a","echo b"},{a=""},{"b"})
testutil.run_cmd({"touch a","echo a"},{a=""},{"a"})
