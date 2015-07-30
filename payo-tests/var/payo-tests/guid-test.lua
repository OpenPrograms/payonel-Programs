local lib = "payo-lib/guid"
package.loaded[lib] = nil
local util = require(lib)

local fs = require("filesystem");

if (not util) then
  error("failed to load " .. lib)
end

local function are_equal(a, b, msg)
  if (a ~= b) then
    io.stderr:write(string.format("%s~=%s:%s\n", tostring(a), tostring(b), msg));
  end
end

are_equal(util.toHex(0), '0', '0 hex');
are_equal(util.toHex(1), '1', '1 hex');
are_equal(util.toHex(2), '2', '2 hex');
are_equal(util.toHex(3), '3', '3 hex');
are_equal(util.toHex(4), '4', '4 hex');
are_equal(util.toHex(5), '5', '5 hex');
are_equal(util.toHex(6), '6', '6 hex');
are_equal(util.toHex(7), '7', '7 hex');
are_equal(util.toHex(8), '8', '8 hex');
are_equal(util.toHex(9), '9', '9 hex');
are_equal(util.toHex(10), 'a', '10 hex');
are_equal(util.toHex(11), 'b', '11 hex');
are_equal(util.toHex(12), 'c', '12 hex');
are_equal(util.toHex(13), 'd', '13 hex');
are_equal(util.toHex(14), 'e', '14 hex');
are_equal(util.toHex(15), 'f', '15 hex');

are_equal(util.toHex(-1), '-1', '-1 hex');
are_equal(util.toHex(''), nil, 'string hex');
are_equal(util.toHex(nil), nil, 'nil hex');

-- testing large values
are_equal(util.toHex(4294907295), 'ffff159f', '4294907295 hex');

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

