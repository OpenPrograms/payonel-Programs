local util = {}

function util.equal(t1, t2)
  local et1 = type(t1)
  local et2 = type(t2)

  if (et1 ~= et2) then
    return false, "not same types"
  end
  
  if (et1 == type(nil)) then
    return true -- both nil
  end

  if (et1 ~= type({})) then
    return false, "not tables"
  end

  local t1_keys = {}
  local t2_keys = {}
  local key_diff = 0

  for k,_ in pairs(t1) do
    t1_keys[k] = true
    key_diff = key_diff + 1
  end

  for k,_ in pairs(t2) do
    t2_keys[k] = true
    key_diff = key_diff - 1
  end

  if (key_diff ~= 0) then
    return false, "different number of keys"
  end

  for k,_ in pairs(t1_keys) do
    t2_keys[k] = nil
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
  return nil
end

function util.sizeof(t)
  if (type(t) ~= "table") then return nil, "not a table" end

  local s = 0
  for _ in pairs(t) do
    s = s + 1
  end

  return s
end

function util.isarray(t)
  if (type(t) ~= "table") then return nil, "not a table" end
  local s = util.sizeof(t)

  if (type(t.n) == "number") then
    -- n is only valid in arrays if packed
    -- n is packed if n == #t
    -- AND s == #t+1
    return t.n == #t and s == (t.n + 1)
  else
    return #t == s
  end
end

return util
