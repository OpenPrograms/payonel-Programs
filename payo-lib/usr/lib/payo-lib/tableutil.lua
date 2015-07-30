local util = {};

function util.equal(t1, t2)
  if (type(t1) ~= type({}) or type(t2) ~= type({})) then
    return false, "not both tables"
  end

  if (not t1 ~= not t2) then
    return false, "not equally nil"
  end

  if (t1 == nil and t2 == nil) then
    return true;
  end

  local t1_keys = {}
  local t2_keys = {}
  local key_diff = 0;

  for k,_ in pairs(t1) do
    t1_keys[k] = true;
    key_diff = key_diff + 1;
  end

  for k,_ in pairs(t2) do
    t2_keys[k] = true
    key_diff = key_diff - 1;
  end

  if (key_diff ~= 0) then
    return false, "different number of keys"
  end

  for k,_ in pairs(t1_keys) do
    t2_keys[k] = nil;
  end

  if (next(t2_keys)) then
    return false, "different keys"
  end

  for k,v in pairs(t1) do
    if (type(t1[k]) ~= type(t2[k])) then
      return false, string.format("in key [\"%s\"]: values not same type: %s ~= %s", tostring(k), type(t1[k]), type(t2[k]))
    elseif (type(t1[k]) == type({})) then
      local ok, reason = util.equal(t1[k], t2[k])
      if (not ok) then
        return false, string.format("in key [\"%s\"]: ", tostring(k), tostring(reason))
      end
    elseif (t1[k] ~= t2[k]) then
      return false, string.format("in key [\"%s\"]: values not equal: %s ~= %s", tostring(k), tostring(t1[k]), tostring(t2[k]))
    end
  end

  return true
end

function util.indexOf(table, value)
  for i,v in ipairs(table) do
    if (v == value) then  
      return i
    end
  end
  return nil;
end

return util;
