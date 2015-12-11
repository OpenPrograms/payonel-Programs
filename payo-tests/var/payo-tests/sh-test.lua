local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local sh = dofile("/lib/sh.lua")

local function statements(input, ex)
  testutil.assert('states',ex,sh.statements(text.tokenize(input,nil,nil,true)))
end

local function tt(str, quoted)
  local t = {{txt=str}}
  if quoted then
    t[1].qr = {'"','"'}
  end
  return t
end

statements('echo|hi foo bar;', {{tt('echo'),tt('|'),tt('hi'),tt('foo'),tt('bar')}})
statements('echo hi',          {{tt('echo'),tt('hi')}})
statements(';echo hi;',        {{tt('echo'),tt('hi')}})
statements('echo hi|grep hi',  {{tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi')}})
statements('|echo hi|grep hi', {{tt('|'),tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi')}})
statements('echo hi|grep hi|', {{tt('echo'),tt('hi'),tt('|'),tt('grep'),tt('hi'),tt('|')}})
statements('echo hi||grep hi', {{tt('echo'),tt('hi'),tt('|'),tt('|'),tt('grep'),tt('hi')}})
statements('echo hi|;|grep hi',{{tt('echo'),tt('hi'),tt('|')},{tt('|'),tt('grep'),tt('hi')}})
statements('echo hi|>grep hi', {{tt('echo'),tt('hi'),tt('|'),tt('>'),tt('grep'),tt('hi')}})
statements('echo hi|;grep hi', {{tt('echo'),tt('hi'),tt('|')},{tt('grep'),tt('hi')}})
statements('echo hi>>grep hi', {{tt('echo'),tt('hi'),tt('>>'),tt('grep'),tt('hi')}})
statements('echo hi>>>grep hi',{{tt('echo'),tt('hi'),tt('>>'),tt('>'),tt('grep'),tt('hi')}})
statements(';;echo hi;echo hello|grep hello|grep hello>>result;echo hi>result;;',
  {{tt('echo'),tt('hi')},{tt('echo'),tt('hello'),tt('|'),tt('grep'),tt('hello'),tt('|'),tt('grep'),tt('hello'),tt('>>'),tt('result')},{tt('echo'),tt('hi'),tt('>'),tt('result')}})
statements(';result<grep foobar>result;', {{tt('result'),tt('<'),tt('grep'),tt('foobar'),tt('>'),tt('result')}})
statements('',  {})
statements(';', {})
statements(';;;;;;;;;', {})
statements('echo;grep', {{tt('echo')},{tt('grep')}})
statements('echo;g"r"ep', {{tt('echo')},{{tt('g')[1],tt('r',true)[1],tt('ep')[1]}}})
statements('a;"b"c', {{tt('a')},{{tt('b',true)[1],tt('c')[1]}}})

local function vt(cmd, ...)
  local tokens = text.tokenize(cmd, nil, nil, true)
  local states = sh.statements(tokens)

  local ex = {...}
  testutil.assert('vt prep:'..cmd, #ex, #states)

  for _,state in ipairs(states) do
    testutil.assert('vt:'..cmd, ex[_], sh.hasValidPiping(state))
  end
end

vt('echo hi', true)
vt('echo hi;', true)
vt(';echo hi;', true)
vt('echo hi|grep hi', true)
vt('|echo hi|grep hi', false)
vt('echo hi|grep hi|', false)
vt('echo hi||grep hi', false)
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

local function id(name, ex)
  testutil.assert('id:'..tostring(name), ex, sh.isIdentifier(name))
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
  testutil.assert('ps:'..cmd, out, sh.packStatements({}, cmd))
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
