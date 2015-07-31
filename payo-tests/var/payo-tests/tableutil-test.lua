local testutil = doile("/var/payo-tests/testutil.lua");
local util = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize

local function test(a, b, pass)
  local ok, reason = util.equal(a, b) and util.equal(b, a);
  if (ok and not pass or not ok and pass) then
    io.stderr:write(string.format("%s ~= %s: %s\n", ser(a), ser(b), tostring(reason)))
  end
end

local function testContainsValue(table, value, has)
  local actual = util.indexOf(table, value)
  if (actual ~= has) then
    io.stderr:write(string.format("%s indexOf %s: %s actual: %s\n", ser(table), tostring(value), tostring(actual), tostring(has)));
  end
  return true;
end

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
