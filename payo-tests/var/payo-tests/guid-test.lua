local testutil = dofile("/var/payo-tests/testutil.lua");
local util = testutil.load("payo-lib/guid");
local fs = require("filesystem");

testutil.assert('0 hex', '0', util.toHex(0));
testutil.assert('1 hex', '1', util.toHex(1));
testutil.assert('2 hex', '2', util.toHex(2));
testutil.assert('3 hex', '3', util.toHex(3));
testutil.assert('4 hex', '4', util.toHex(4));
testutil.assert('5 hex', '5', util.toHex(5));
testutil.assert('6 hex', '6', util.toHex(6));
testutil.assert('7 hex', '7', util.toHex(7));
testutil.assert('8 hex', '8', util.toHex(8));
testutil.assert('9 hex', '9', util.toHex(9));
testutil.assert('a hex', 'a', util.toHex(a));
testutil.assert('b hex', 'b', util.toHex(b));
testutil.assert('c hex', 'c', util.toHex(c));
testutil.assert('d hex', 'd', util.toHex(d));
testutil.assert('e hex', 'e', util.toHex(e));
testutil.assert('f hex', 'f', util.toHex(f));

testutil.assert('-1', '-1 hex', '-1', util.toHex(-1));
testutil.assert('string hex', nil, util.toHex(''));
testutil.assert('nil hex', nil, util.toHex(nil));

-- testing large values
testutil.assert('4294907295 hex', 'ffff159f', util.toHex(4294907295));

-- we can also test mktmp here
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
if (not mktmp) then
  io.stderr:write("could not find mktmp for testing");
else
  local t,o = mktmp();
  if (not t) then
    io.stderr:write("no tmp file created or returned: " .. tostring(o) .. '\n');
  end
  if (not fs.exists(t)) then
    io.stderr:write("mktmp did not create the tmp file it returned: " .. tostring(t) .. '\n');
  else
    fs.remove(t);
  end
end
