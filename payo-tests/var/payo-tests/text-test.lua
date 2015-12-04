local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")

local function trim(input, ex)
  local result, reason = text.trim(input)
  testutil.assert('trim:'..input, ex, result, reason)
end

trim("  ", "")
trim("  asdf   ", "asdf")
trim("  asdfas   dfasd fas fs ", "asdfas   dfasd fas fs")
trim("  asdf  asdf", "asdf  asdf")
trim("asdf  asdf  ", "asdf  asdf")

local function split(input, delims, ex, dropDelims)
  local special = dropDelims and '(drop)' or ''
  testutil.assert("split"..special..":"..ser(input)..'-'..ser(delims), ex, 
    text.split(input, delims, dropDelims))
end

testutil.broken.split("abc", {'a'}, {'a','bc'})
testutil.broken.split("abc", {'b'}, {'a','b','c'})
testutil.broken.split("abc", {'c'}, {'ab','c'})
testutil.broken.split("abc", {'d'}, {'abc'})
testutil.broken.split("abc", {'a','b','c'}, {'a','b','c'})
testutil.broken.split("abc", {'b','a','c'}, {'a','b','c'})
testutil.broken.split("abc", {'c','b','a'}, {'a','b','c'})
testutil.broken.split("abbc", {'b', 'bb'}, {'a','b','b','c'})
testutil.broken.split("abbc", {'bb', 'b'}, {'a','bb','c'})
testutil.broken.split("abbcbd", {'bb', 'b'}, {'a','bb','c','b','d'})
testutil.broken.split("babbcbdbb", {'bb', 'b'}, {'b','a','bb','c','b','d','bb'})
testutil.broken.split("abc", {'b'}, {'a', 'c'}, true)

local function find_all(cmd, v, ex)
  testutil.assert("find_all:"..ser(cmd)..':'..ser(v), ex, text.find_all(cmd, v))
end

testutil.broken.find_all('abc', 'd', {})
testutil.broken.find_all('abc', 'b', {2})
testutil.broken.find_all('bbb', 'b', {1,2,3})
testutil.broken.find_all('abbcbdbe', 'b', {2, 3, 5, 7})
testutil.broken.find_all('abbcbdbbe', 'bb', {2,7})

local function tokens(input, delims, quotes, ex)
  local result, treason = text.tokenize(input, delims, quotes)
  local equal, reason = tutil.equal(result, ex)
  if not equal then
    io.stderr:write(
      string.format("tokens:%s:\"%s\"=>%s<>%s,%s\n",
        tostring(reason), tostring(input),
        ser(result), ser(ex),treason))
  end
  testutil.bump(equal)
end

tokens([["]], nil, nil, nil)
tokens([[']], nil, nil, nil)
testutil.broken.tokens([[\']], nil, nil, {[[']]})
tokens([['\'']], nil, nil, nil)
tokens([["\'"]], nil, nil, {[["\'"]]})
tokens([['\']], nil, nil, {[['\']]})

--quoted delimiters should not delimit
testutil.broken.tokens([[echo hi;echo done]],{';'},{{"'","'"}},{'echo','hi',';','echo','done'})
testutil.broken.tokens([[echo hi;echo done]],{';'},{{"'","'",true}},{'echo','hi',';','echo','done'})
testutil.broken.tokens([[echo 'hi;'echo done]],{';'},{{"'","'"}},{'echo',"'hi;'echo",'done'})
testutil.broken.tokens([[echo 'hi;'echo done]],{';'},{{"'","'",true}},{'echo',"'hi;'echo",'done'})

tokens([[echo;]],{';;'},nil,{'echo;'})
testutil.broken.tokens([[';';;;';']],{';;'},nil,{"';'",';;',";';'"})

-- custom quote rules
tokens([[" abc" ' def']],nil,                   nil,{'" abc"', "' def'"})
testutil.broken.tokens([[" abc" ' def']],nil,                    {},{'"', 'abc"', "'", "def'"})
testutil.broken.tokens([[" abc" ' def']],nil,           {{'"','"'}},{'" abc"', "'", "def'"})
testutil.broken.tokens([[" abc" ' def']],nil, {{"'","'"}}          ,{'"', 'abc"', "' def'"})
testutil.broken.tokens([[" abc" ' def']],nil, {{"'","'"},{'"','"'}},{'" abc"', "' def'"})
testutil.broken.tokens('< abc def > ghi jkl',nil, {{"<",">"}},{'< abc def >', 'ghi', 'jkl'})

tokens("", nil, nil, {})
tokens("' '", nil, nil, {"' '"})
tokens('" "', nil, nil, {"\" \""})
tokens("  $this is   a test  ", nil, nil, {"$this", "is", "a", "test"})
tokens("  this is a   | test  ", nil, nil, {"this", "is", "a", "|", "test"})
tokens("  this is   'a test'  ", nil, nil, {"this", "is", "'a test'"})
tokens("  \"this is\"   'a test'  ", nil, nil, {"\"this is\"", "'a test'"})
tokens("  \"this 'bigger' is\" 'a test'  ", nil, nil, {"\"this 'bigger' is\"", "'a test'"})
tokens("  \"this 'bigger' is\" 'a \"smaller\" test'", nil, nil, {"\"this 'bigger' is\"", "'a \"smaller\" test'"})
testutil.broken.tokens([["""]], {}, {}, {[["""]]})

-- new ability to split on custom delim list
testutil.broken.tokens("a|b"    ,{"|"},nil,{'a','|','b'})
testutil.broken.tokens("|a|b|"    ,{"|"},nil,{'|','a','|','b','|'})
testutil.broken.tokens("'|'a'|'b'|'",{"|"},nil,{"'|'a'|'b'|'"})
testutil.broken.tokens("'|'a|b'|'"  ,{"|"},nil,{"'|'a",'|',"b'|'"})
tokens("a|b"    , {""},nil,{'a|b'})
testutil.broken.tokens("a|b"    ,{"a"},nil,{'a','|b'})
testutil.broken.tokens("a|b"    ,{"b"},nil,{'a|','b'})
tokens("a|b"    ,{"c"},nil,{'a|b'})
testutil.broken.tokens("a |b"   ,{"|"},nil,{'a','|','b'})
testutil.broken.tokens("a | b"  ,{"|"},nil,{'a','|','b'})
testutil.broken.tokens(" a | b" ,{"|"},nil,{'a','|','b'})
testutil.broken.tokens("a || b" ,{"|"},nil,{'a','|','|','b'})
testutil.broken.tokens("a | | b",{"|"},nil,{'a','|','|','b'})
testutil.broken.tokens("a||b"   ,{"|"},nil,{'a','|','|','b'})

--multichar delimiter
testutil.broken.tokens("a||b", {"||"}, nil, {'a','||','b'})
testutil.broken.tokens("echo test;echo hello|grep world>>result", 
  {'|','>>','>',';'},
  nil,
  {'echo','test',';','echo','hello','|','grep','world','>>','result'})

testutil.broken.tokens("baaaaababaaaabaabaabaaabaababaaaabab", 
  {'aaaa','aaa','aa','a'},nil,
  {'b','aaaa','a','b','a','b','aaaa','b','aa','b','aa','b','aaa','b','aa','b',
  'a','b','aaaa','b','a','b'})

testutil.broken.tokens("abaaaaaaacaaaaaaaadaaaaeaaaafaaaaaagaaaahaaaaiaaaaajaaaakaaaal", 
  {'l','k','j','i','h','g','f','e','d','c','b','aaaa','aaa','aa','a'},nil,
  {'a','b','aaaa','aaa','c','aaaa','aaaa','d','aaaa','e','aaaa','f',
   'aaaa','aa','g','aaaa','h','aaaa','i','aaaa','a','j','aaaa','k','aaaa','l'})

local function tokensg(input, delims, quotes, ex)
  local result, treason = text.tokenizeGroups(input, delims, quotes)
  local equal, reason = tutil.equal(result, ex)
  if not equal then
    io.stderr:write(
      string.format("tokensg:%s:\"%s\"=>\n\n%s<>\n%s\n%s\n",
        tostring(reason), tostring(input),
        ser(result), ser(ex), treason))
  end
  testutil.bump(equal)
end

testutil.broken.tokensg('|echo hi|grep hi',nil,nil,{{{txt='|'}},{{txt='echo'}},{{txt='hi'}},{{txt='|'}},{{txt='grep'}},{{txt='hi'}}})
testutil.broken.tokensg(";echo ignore;echo hello|grep hello>>result",nil,nil,
{
  {{txt=';'}},
  {{txt='echo'}},{{txt='ignore'}},{{txt=';'}},
  {{txt='echo'}},{{txt='hello'}},{{txt='|'}},
  {{txt='grep'}},{{txt='hello'}},{{txt='>>'}},{{txt='result'}}
})
