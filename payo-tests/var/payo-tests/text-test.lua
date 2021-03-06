local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = require("shell")
local text = require("text")
local tx = require("transforms")
local sh = require("sh")
local buffer = require("buffer")

local function trim(input, ex)
  local result, reason = text.trim(input)
  testutil.assert('trim:'..input, ex, result, reason)
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
  testutil.assert('gsplit'..ser(table_), ex, text.internal.splitWords(table_,text.syntax))
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
gsplit(text.internal.words('a b c\\ '),
{
  {
    {txt='a'}
  },
  {
    {txt='b'}
  },
  {
    {txt='c '}
  }
})

local function tokens(input, quotes, delims, ex)
  local result, treason = text.tokenize(input, {quotes=quotes,delimiters=delims})
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
tokens([[echo hi;echo done]]  ,{{"'","'"}}     ,{';'},{'echo','hi',';','echo','done'})
tokens([[echo hi;echo done]]  ,{{"'","'",true}},{';'},{'echo','hi',';','echo','done'})
tokens([[echo 'hi;'echo done]],{{"'","'"}}     ,{';'},{'echo',"'hi;'echo",'done'})
tokens([[echo 'hi;'echo done]],{{"'","'",true}},{';'},{'echo',"'hi;'echo",'done'})

tokens([[echo;]]    ,nil,{';;'},{'echo;'})
tokens([[';';;;';']],nil,{';;'},{"';'",';;',";';'"})

-- custom quote rules
tokens([[w " abc" ' def']]  ,                  nil,nil,{'w', '" abc"', "' def'"})
tokens([[" abc" ' def']]    ,                  nil,nil,{'" abc"', "' def'"})
tokens([[" abc" ' def']]    ,                   {},nil,{'"', 'abc"', "'", "def'"})
tokens([[" abc" ' def']]    ,          {{'"','"'}},nil,{'" abc"', "'", "def'"})
tokens([[" abc" ' def']]    ,{{"'","'"}}          ,nil,{'"', 'abc"', "' def'"})
tokens([[" abc" ' def']]    ,{{"'","'"},{'"','"'}},nil,{'" abc"', "' def'"})
tokens('< abc def > ghi jkl',{{"<",">"}}          ,nil,{'< abc def >', 'ghi', 'jkl'})

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
tokens("a|b"    ,    nil,{"|"},{'a','|','b'})
tokens("|a|b|"    ,  nil,{"|"},{'|','a','|','b','|'})
tokens("'|'a'|'b'|'",nil,{"|"},{"'|'a'|'b'|'"})
tokens("'|'a|b'|'"  ,nil,{"|"},{"'|'a",'|',"b'|'"})
tokens("a|b"    ,    nil, {""},{'a|b'})
tokens("a|b"    ,    nil,{"a"},{'a','|b'})
tokens("a|b"    ,    nil,{"b"},{'a|','b'})
tokens("a|b"    ,    nil,{"c"},{'a|b'})
tokens("a |b"   ,    nil,{"|"},{'a','|','b'})
tokens("a | b"  ,    nil,{"|"},{'a','|','b'})
tokens(" a | b" ,    nil,{"|"},{'a','|','b'})
tokens("a || b" ,    nil,{"|"},{'a','|','|','b'})
tokens("a | | b",    nil,{"|"},{'a','|','|','b'})
tokens("a||b"   ,    nil,{"|"},{'a','|','|','b'})

--multichar delimiter
tokens("a||b",nil,{"||"},{'a','||','b'})
tokens("echo test;echo hello|grep world>>result", 
  nil,
  {'|','>>','>',';'},
  {'echo','test',';','echo','hello','|','grep','world','>>','result'})

tokens("b 9>>&88<b<b 9>>&87b>>b>>b 6>>b>>b<b 9>>&86b<b", 
  nil,nil,
  {'b','9>>&88','<','b','<','b','9>>&87','b','>>','b','>>','b','6>>','b','>>','b',
  '<','b','9>>&86','b','<','b'})

tokens("abaaaaaaacaaaaaaaadaaaaeaaaafaaaaaagaaaahaaaaiaaaaajaaaakaaaal", 
  nil,{'l','k','j','i','h','g','f','e','d','c','b','aaaa','aaa','aa','a'},
  {'a','b','aaaa','aaa','c','aaaa','aaaa','d','aaaa','e','aaaa','f',
   'aaaa','aa','g','aaaa','h','aaaa','i','aaaa','a','j','aaaa','k','aaaa','l'})

local function tokensg(input, quotes, delims, ex)
  local result, treason = text.tokenize(input, {doNotNormalize=true,quotes=quotes,delimiters=delims})
  local equal, reason = tutil.equal(result, ex)
  if not equal then
    io.stderr:write(
      string.format("tokensg:%s:\"%s\"=>\n\n%s<>\n%s\n%s\n",
        tostring(reason), tostring(input),
        ser(result), ser(ex), treason))
  end
  testutil.bump(equal)
end

tokensg('|echo hi|grep hi',nil,{'|'},{{{txt='|'}},{{txt='echo'}},{{txt='hi'}},{{txt='|'}},{{txt='grep'}},{{txt='hi'}}})
tokensg(";echo ignore;echo hello|grep hello>>result",nil,{';','|','>>'},
{
  {{txt=';'}},
  {{txt='echo'}},{{txt='ignore'}},{{txt=';'}},
  {{txt='echo'}},{{txt='hello'}},{{txt='|'}},
  {{txt='grep'}},{{txt='hello'}},{{txt='>>'}},{{txt='result'}}
})

tokensg('a', {{"'","'",true},{'"','"'}}, text.syntax, {{{txt='a'}}})
tokensg('"a"', {{"'","'",true},{'"','"'}}, text.syntax, {{{txt='a',qr={'"','"'}}}})
tokensg('""', {{"'","'",true},{'"','"'}}, text.syntax, {{{txt='',qr={'"','"'}}}})

local function magic(n, o)
  testutil.assert('escape magic'..ser(n), o, text.escapeMagic(n))
  testutil.assert('remove escapes'..ser(o), n, text.removeEscapes(o))
end

magic('', '')
magic('.', '%.')
magic('().%+-*?[^$', '%(%)%.%%%+%-%*%?%[%^%$')
magic('a(a)a.a%a+a-a*a?a[a^a$a', 'a%(a%)a%.a%%a%+a%-a%*a%?a%[a%^a%$a')
magic('a(a)a.a%%a+a-a*a?a[a^a$a', 'a%(a%)a%.a%%%%a%+a%-a%*a%?a%[a%^a%$a')

magic('(','%(')
magic(')','%)')
magic('.','%.')
magic('+','%+')
magic('-','%-')
magic('*','%*')
magic('?','%?')
magic('[','%[')
magic('^','%^')
magic('$','%$')
magic('%','%%')

require("package").loaded["tools/advanced-buffering"] = nil

local function readnum(input, exp, rem, pre)
  local meta = {input, exp, rem, pre}

  local test_stream =
  {
    buf = input,
    read = function(self, size)
      if self.buf == "" then
        self.buf = nil
      end
      if not self.buf then
        return nil
      end
      local n = self.buf:sub(1, size)
      self.buf = self.buf:sub(size+1)
      return n
    end
  }

  local test_buffer = buffer.new("r", test_stream)

  test_buffer.bufferRead = pre or ""

  local result = test_buffer:read("*n")
  local act_rem = test_buffer.bufferRead

  testutil.assert('readnum num check'..ser(meta), exp, result)
  testutil.assert('readnum rem check'..ser(meta), rem, act_rem)
end

readnum("", nil, "")
readnum("\n", nil, "")
readnum("\n123\n", 123, "\n")
readnum("123\n", 123, "\n")
readnum("123 a", 123, " a")

readnum("+123 a", 123, " a")
readnum("+123. a", 123, " a")
readnum("+1.23. a", 1.23, ". a")
readnum("+-123. a", nil, "-123. a")
readnum("+12-3. a", 12, "-3. a")
readnum("+12.3 a", 12.3, " a")
readnum("-123 a",-123, " a")

readnum("0x123 a", 0x123, " a")
readnum("-0x123 a", -0x123, " a")
readnum("-0x123.4 a", -291.25, " a")
readnum("-0x", nil, "")
readnum("-0x\n", nil, "\n")
readnum("-0xg", nil, "g")
readnum("-0xa", -10, "")
readnum("-0xf", -15, "")

readnum("\n1a23\n", 1, "a23\n")
readnum("a23\n", 1, "a23\n", "\n1")
readnum(".23\n", .23, "\n")
readnum(".-23\n", nil, "-23\n")
readnum("+.23\n", .23, "\n")
readnum("023x123\n", 023, "x123\n")
readnum("\t \n023x123\n", 023, "x123\n")
