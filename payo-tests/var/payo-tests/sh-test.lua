local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local sh = dofile("/lib/sh.lua")

local ser = require('serialization').serialize
local pser = function(...)
  print(table.unpack(tx.select({...}, function(e) 
    return ser(e)
  end)))
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
vt('echo hi|>grep hi', false)
vt('echo hi|grep hi', true)
vt('echo hi|;grep hi', false, true)
vt('echo hi>>grep hi', true)
vt('echo hi>>>grep hi', false)
vt(';;echo hi;echo hello|grep hello|grep hello>>result;echo hi>result;;', true, true, true)
vt(';result<grep foobar>result;', true)
vt('')
vt(';')
vt(';;;;;;;;;')
vt('echo hi >&2', true)

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

local function evalglob(value, exp)

  -- intercept glob
  local real_glob = sh.internal.glob
  sh.internal.glob = function(gp)
    return {gp}
  end

  local status, result = pcall(function()
    local groups, reason = text.internal.tokenize(value)
    if type(groups) ~= "table" then
      return groups, reason
    end
    return tx.foreach(groups, function(g)
      local evals = sh.internal.evaluate(g)
      if #evals == 0 then
        return nil
      elseif #evals > 1 then
        return {'too many evals'}
      else
        return evals[1]
      end
    end)
  end)
  sh.internal.glob = real_glob

  testutil.assert('evalglob result:'..value,status and exp or '',result)
end

-- only plaintext * should glob
evalglob('*', {'.*'})
evalglob('*.foo', {'.*%.foo'})
evalglob('', {})
evalglob('foo', {'foo'})
evalglob([["*".foo]], {'*.foo'})
evalglob([['*'.foo]], {'*.foo'})
evalglob([['*.fo'o]], {'*.foo'})
evalglob([['*."f"oo']], {'*.\"f\"oo'})
evalglob([[**]], {'.*'})
evalglob([[* *]], {'.*','.*'})
evalglob([[* * *]], {'.*','.*','.*'})
evalglob([["* * *"]], {'* * *'})

local function sc(input, rets, ...)
  rets = rets or {}
  local exp_all = {...}
  local states = sh.internal.statements(input)

  if type(states) ~= 'table' then
    testutil.assert('sc:'..ser(input),table.remove(exp_all,1),states)
    return
  end

  local dtxts = {}
  local counter = 0
  tx.foreach(states, function(s, si)
    local chains = sh.internal.groupChains(s)

    sh.internal.boolean_executor(chains, function(chain,chain_index)
      local pipe_parts = sh.internal.splitChains(chain)
      local exp = table.remove(exp_all, 1)

      counter = counter + 1
      testutil.assert('sc:'..ser(input)..','..ser(counter)..','..ser(rets),exp,pipe_parts)
      local result = rets[chain_index]
      return result
    end)
  end)

  testutil.assert('sc:'..ser(input)..ser(rets)..',end of chains',0,#exp_all,ser(exp_all))
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
ps('echo hi|>grep hi', nil)
ps('echo hi|;grep hi', nil)
ps('echo hi>>>grep hi',nil)
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

  local states = sh.internal.statements(input)
  local chains = sh.internal.groupChains(states[1])
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
  local words = text.internal.words(key)
  local actual = sh.internal.evaluate(words[1])[1]
  os.setenv("a")
  testutil.assert("set get:"..ser(key),exp,actual)
end

set("$a","b")
set("'$a'","$a")
set("\"$a\"","b")
set("'$'a","$a")
--set("\\$a","$a")

