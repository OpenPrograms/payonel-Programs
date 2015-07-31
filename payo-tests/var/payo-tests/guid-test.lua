local testutil = dofile("/var/payo-tests/testutil.lua");
local util = testutil.load("payo-lib/guid");
local fs = require("filesystem");

testutil.asser(util.toHex(0), '0', '0 hex');
testutil.asser(util.toHex(1), '1', '1 hex');
testutil.asser(util.toHex(2), '2', '2 hex');
testutil.asser(util.toHex(3), '3', '3 hex');
testutil.asser(util.toHex(4), '4', '4 hex');
testutil.asser(util.toHex(5), '5', '5 hex');
testutil.asser(util.toHex(6), '6', '6 hex');
testutil.asser(util.toHex(7), '7', '7 hex');
testutil.asser(util.toHex(8), '8', '8 hex');
testutil.asser(util.toHex(9), '9', '9 hex');
testutil.asser(util.toHex(10), 'a', '10 hex');
testutil.asser(util.toHex(11), 'b', '11 hex');
testutil.asser(util.toHex(12), 'c', '12 hex');
testutil.asser(util.toHex(13), 'd', '13 hex');
testutil.asser(util.toHex(14), 'e', '14 hex');
testutil.asser(util.toHex(15), 'f', '15 hex');

testutil.asser(util.toHex(-1), '-1', '-1 hex');
testutil.asser(util.toHex(''), nil, 'string hex');
testutil.asser(util.toHex(nil), nil, 'nil hex');

-- testing large values
testutil.asser(util.toHex(4294907295), 'ffff159f', '4294907295 hex');

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

