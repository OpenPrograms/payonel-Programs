local testutil = require("testutil");
local util = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize

local function test(a, b, pass)
  local ok, reason = util.equal(a, b) and util.equal(b, a);
  testutil.bump(true)
  if (ok and not pass or not ok and pass) then
    io.stderr:write(string.format("%s ~= %s: %s\n", ser(a), ser(b), tostring(reason)))
  end
end

local function testContainsValue(table, value, has)
  local actual = util.indexOf(table, value)
  testutil.bump(actual == has)
  if (actual ~= has) then
    io.stderr:write(string.format("%s indexOf %s: %s actual: %s\n", ser(table), tostring(value), tostring(actual), tostring(has)));
  end
  return true;
end

test(nil, nil, true);
test({}, {}, true)
test(nil, {}, false)
test({1}, {1}, true)
test({1,2}, {1,2}, true)
test({1,2}, {2,1}, false)
test({a=1,b=2}, {b=2,a=1}, true)
test({'a','b',key=10},{key=10,'a','b'}, true)
test({'a','b',key=10},{key=11,'a','b'}, false)
test({'a','b',key=10},{keys=10,'a','b'}, false)
test({'a','b',key=10},{keys=10,'b','a'}, false)
test({'a',{'b'}},{'a',{'b'}}, true)
test({'a',{'b'}},{{'b'},'a'}, false)

test(0, {}, false)
test("", {}, false)
test(function()end, {}, false)

testContainsValue({}, "foobar", nil);
testContainsValue({"a"}, "a", 1);
testContainsValue({"a"}, "b", nil);
testContainsValue({"b"}, "a", nil);
testContainsValue({"1", 2, {}}, 2, 2);

local a =
{
  _a = 1,
  _b = 2,
  _c = "foobar",
  _d = a
};

local b = util.deepCopy(a);
test(a, b, true);
b._a = 2
test(a, b, false);

testutil.assert("table size 1", nil, util.sizeof(0))
testutil.assert("table size 2", nil, util.sizeof(""))
testutil.assert("table size 3", 0, util.sizeof({}))
testutil.assert("table size 4", 2, util.sizeof({1,2}))
testutil.assert("table size 5", 3, util.sizeof({1,2,a='b'}))
testutil.assert("table size 6", 4, util.sizeof({0,1,2,a='b'}))
testutil.assert("table size 7", 5, util.sizeof({w='f',0,1,2,a='b'}))

testutil.assert("table array 1", nil, util.isarray(0))
testutil.assert("table array 2", false, util.isarray({0,1,2,a='b'}))
testutil.assert("table array 3", false, util.isarray({1,2,a='b'}))
testutil.assert("table array 4", true, util.isarray({1,2}))
testutil.assert("table array 5", true, util.isarray(table.pack(1,2,3)))
testutil.assert("table array 6", false, util.isarray({1,2,n=50}))
testutil.assert("table array 7", false, util.isarray({[0]=1}))
testutil.assert("table array 8", true, util.isarray({[1]=1}))
testutil.assert("table array 9", false, util.isarray({[1]=1,[3]=2}))
