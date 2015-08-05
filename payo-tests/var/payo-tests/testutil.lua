local util = {};
local ser = require("serialization").serialize
local tutil = require("payo-lib/tableutil");

function util.load(lib)
  package.loaded[lib] = nil;
  local result = require(lib);

  if (not result) then
    error("failed to load library: " .. result);
    return nil; -- shouldn't happen after an error
  end
  return result;
end

function util.assert(msg, expected, actual, reason)
  local etype = type(expected);
  local atype = type(actual);

  if (etype ~= atype) then
    io.stderr:write(string.format("mismatch type, %s vs %s. expected value: %s: %s. reason: %s\n", etype, atype, ser(expected), msg, reason));
    return false;
  end
  
  -- both same type

  if (etype == nil) then -- both nil
    return true;
  end

  local matching = true;
  if (etype == type({})) then
    if (not tutil.equal(expected, actual)) then
      matching = false;
    end
  elseif (expected ~= actual) then
    matching = false;
  end

  if (not matching) then
    io.stderr:write(string.format("%s ~= %s: %s. reason: %s\n", ser(expected), ser(actual), msg, reason));
  end

  return matching;
end

return util;