local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")

local function trim(input, ex)
  local result, reason = text.trim(input)
  testutil.assert('trim:'..input, ex, result, reason)
end

trim("  ", "")
trim("  asdf   ", "asdf")
trim("  asdfas   dfasd fas fs ", "asdfas   dfasd fas fs")
trim("  asdf  asdf", "asdf  asdf")
trim("asdf  asdf  ", "asdf  asdf")

testutil.assert('table',3,#text.internal.table_view('abc'))
testutil.assert('table','a',text.internal.table_view('abc')[1])
testutil.assert('table','b',text.internal.table_view('abc')[2])
testutil.assert('table','c',text.internal.table_view('abc')[3])
testutil.assert('table',nil,text.internal.table_view('abc')[4])
testutil.assert('table',{{'c'},{'a'}},
  tx.reverse(tx.partition(text.internal.table_view('abc'),{{'b'}},true)))

local function split(input, delims, ex, dropDelims)
  local special = dropDelims and '(drop)' or ''
  testutil.assert("split"..special..":"..ser(input)..'-'..ser(delims), ex, 
    text.split(input, delims, dropDelims))
end

split("abc", {''}, {'abc'})
split("abc", {}, {'abc'})
split("", {}, {})
split("", {''}, {})
split("", {''}, {}, true)
split("abc", {'a'}, {'a','bc'})
split("abc", {'b'}, {'a','b','c'})
split("abc", {'c'}, {'ab','c'})
split("abc", {'d'}, {'abc'})
split("abc", {'a','b','c'}, {'a','b','c'})
split("abc", {'b','a','c'}, {'a','b','c'})
split("abc", {'c','b','a'}, {'a','b','c'})
split("abbc", {'b', 'bb'}, {'a','b','b','c'})
split("abbc", {'bb', 'b'}, {'a','bb','c'})
split("abbcbd", {'bb', 'b'}, {'a','bb','c','b','d'})
split("babbcbdbb", {'bb', 'b'}, {'b','a','bb','c','b','d','bb'})
split("abc", {'a'}, {'bc'},true)
split("abc", {'b'}, {'a','c'},true)
split("abc", {'c'}, {'ab'},true)
split("abc", {'d'}, {'abc'},true)
split("abc", {'a','b','c'}, {},true)
split("abc", {'b','a','c'}, {},true)
split("abc", {'c','b','a'}, {},true)
split("abbc", {'b', 'bb'}, {'a','c'},true)
split("abbc", {'bb', 'b'}, {'a','c'},true)
split("abbcbd", {'bb', 'b'}, {'a','c','d'},true)
split("babbcbdbb", {'bb', 'b'}, {'a','c','d'},true)
split("11abcb222abcb333abcb", {'abc'}, {'11','b222','b333', 'b'}, true)

local function gsplit(table_, ex)
  testutil.assert('gsplit'..ser(table_), ex, text.internal.splitWords(table_))
end

gsplit({}, {})
gsplit(
{
  {
    {txt='a;'},
    {txt='b',qr={'"','"'}},
    {txt='c'}
  }
},
{
  {
    {txt='a'}
  },
  {
    {txt=';'}
  },
  {
    {txt='b',qr={'"','"'}},
    {txt='c'}
  }
})
gsplit(text.internal.words('a;"b"c'),
{
  {
    {txt='a'}
  },
  {
    {txt=';'}
  },
  {
    {txt='b',qr={'"','"'}},
    {txt='c'}
  }
})
gsplit(text.internal.words('a>>>"b"c'),
{
  {
    {txt='a'}
  },
  {
    {txt='>>'}
  },
  {
    {txt='>'}
  },
  {
    {txt='b',qr={'"','"'}},
    {txt='c'}
  }
})

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
tokens([[\']], nil, nil, {[[']]})
tokens([['\'']], nil, nil, nil)
tokens([["\'"]], nil, nil, {[["\'"]]})
tokens([['\']], nil, nil, {[['\']]})

--quoted delimiters should not delimit
tokens([[echo hi;echo done]],{';'},{{"'","'"}},{'echo','hi',';','echo','done'})
tokens([[echo hi;echo done]],{';'},{{"'","'",true}},{'echo','hi',';','echo','done'})
tokens([[echo 'hi;'echo done]],{';'},{{"'","'"}},{'echo',"'hi;'echo",'done'})
tokens([[echo 'hi;'echo done]],{';'},{{"'","'",true}},{'echo',"'hi;'echo",'done'})

tokens([[echo;]],{';;'},nil,{'echo;'})
tokens([[';';;;';']],{';;'},nil,{"';'",';;',";';'"})

-- custom quote rules
tokens([[w " abc" ' def']],nil,                   nil,{'w', '" abc"', "' def'"})
tokens([[" abc" ' def']],nil,                   nil,{'" abc"', "' def'"})
tokens([[" abc" ' def']],nil,                    {},{'"', 'abc"', "'", "def'"})
tokens([[" abc" ' def']],nil,           {{'"','"'}},{'" abc"', "'", "def'"})
tokens([[" abc" ' def']],nil, {{"'","'"}}          ,{'"', 'abc"', "' def'"})
tokens([[" abc" ' def']],nil, {{"'","'"},{'"','"'}},{'" abc"', "' def'"})
tokens('< abc def > ghi jkl',nil, {{"<",">"}},{'< abc def >', 'ghi', 'jkl'})

tokens("", nil, nil, {})
tokens("' '", nil, nil, {"' '"})
tokens('" "', nil, nil, {"\" \""})
tokens("  $this is   a test  ", nil, nil, {"$this", "is", "a", "test"})
tokens("  this is a   | test  ", nil, nil, {"this", "is", "a", "|", "test"})
tokens("  this is   'a test'  ", nil, nil, {"this", "is", "'a test'"})
tokens("  \"this is\"   'a test'  ", nil, nil, {"\"this is\"", "'a test'"})
tokens("  \"this 'bigger' is\" 'a test'  ", nil, nil, {"\"this 'bigger' is\"", "'a test'"})
tokens("  \"this 'bigger' is\" 'a \"smaller\" test'", nil, nil, {"\"this 'bigger' is\"", "'a \"smaller\" test'"})
tokens([["""]], {}, {}, {[["""]]})

-- new ability to split on custom delim list
tokens("a|b"    ,{"|"},nil,{'a','|','b'})
tokens("|a|b|"    ,{"|"},nil,{'|','a','|','b','|'})
tokens("'|'a'|'b'|'",{"|"},nil,{"'|'a'|'b'|'"})
tokens("'|'a|b'|'"  ,{"|"},nil,{"'|'a",'|',"b'|'"})
tokens("a|b"    , {""},nil,{'a|b'})
tokens("a|b"    ,{"a"},nil,{'a','|b'})
tokens("a|b"    ,{"b"},nil,{'a|','b'})
tokens("a|b"    ,{"c"},nil,{'a|b'})
tokens("a |b"   ,{"|"},nil,{'a','|','b'})
tokens("a | b"  ,{"|"},nil,{'a','|','b'})
tokens(" a | b" ,{"|"},nil,{'a','|','b'})
tokens("a || b" ,{"|"},nil,{'a','|','|','b'})
tokens("a | | b",{"|"},nil,{'a','|','|','b'})
tokens("a||b"   ,{"|"},nil,{'a','|','|','b'})

--multichar delimiter
tokens("a||b", {"||"}, nil, {'a','||','b'})
tokens("echo test;echo hello|grep world>>result", 
  {'|','>>','>',';'},
  nil,
  {'echo','test',';','echo','hello','|','grep','world','>>','result'})

tokens("baaaaababaaaabaabaabaaabaababaaaabab", 
  {'aaaa','aaa','aa','a'},nil,
  {'b','aaaa','a','b','a','b','aaaa','b','aa','b','aa','b','aaa','b','aa','b',
  'a','b','aaaa','b','a','b'})

tokens("abaaaaaaacaaaaaaaadaaaaeaaaafaaaaaagaaaahaaaaiaaaaajaaaakaaaal", 
  {'l','k','j','i','h','g','f','e','d','c','b','aaaa','aaa','aa','a'},nil,
  {'a','b','aaaa','aaa','c','aaaa','aaaa','d','aaaa','e','aaaa','f',
   'aaaa','aa','g','aaaa','h','aaaa','i','aaaa','a','j','aaaa','k','aaaa','l'})

local function tokensg(input, delims, quotes, ex)
  local result, treason = text.tokenize(input, delims, quotes, true)
  local equal, reason = tutil.equal(result, ex)
  if not equal then
    io.stderr:write(
      string.format("tokensg:%s:\"%s\"=>\n\n%s<>\n%s\n%s\n",
        tostring(reason), tostring(input),
        ser(result), ser(ex), treason))
  end
  testutil.bump(equal)
end

tokensg('|echo hi|grep hi',nil,nil,{{{txt='|'}},{{txt='echo'}},{{txt='hi'}},{{txt='|'}},{{txt='grep'}},{{txt='hi'}}})
tokensg(";echo ignore;echo hello|grep hello>>result",nil,nil,
{
  {{txt=';'}},
  {{txt='echo'}},{{txt='ignore'}},{{txt=';'}},
  {{txt='echo'}},{{txt='hello'}},{{txt='|'}},
  {{txt='grep'}},{{txt='hello'}},{{txt='>>'}},{{txt='result'}}
})

