local lib = "payo-lib/argutil"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

local ser = require("serialization").serialize

local function pser(t)
  print(ser(t))
end

local function table_equals(t1, t2)

  if (not t1 ~= not t2) then
    return false
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
    return false
  end

  for k,_ in pairs(t1_keys) do
    t2_keys[k] = nil;
  end

  if (next(t2_keys)) then
    return false;
  end

  for k,v in pairs(t1) do
    if (type(t1[k]) ~= type(t2[k])) then
      return false;
    elseif (type(t1[k]) == type({})) then
      if (not table_equals(t1[k], t2[k])) then
        return false;
      end
    elseif (t1[k] ~= t2[k]) then
      return false;
    end
  end

  return true
end

local function util_test(pack, oc, expected_args, expected_ops)

  local dump = {}
  dump.pack = pack
  dump.oc = oc
  dump.expected_args = expected_args
  dump.expected_ops = expected_ops

  local args, ops, reason = util.parse(pack, oc)

  dump.args = args
  dump.ops = ops
  dump.reason = reason

  local bPassed = (args and ops) ~= nil;
  local pass_ok  = bPassed == (expected_args and expected_ops and true or false);
  local equal = table_equals(args, expected_args) and table_equals(ops, expected_ops);

  if (not pass_ok or not equal) then
    print(ser(dump))
  end
end

util_test(table.pack("a"), nil, {"a"}, {})
util_test(table.pack("a", "-b"), nil, {"a"}, {b=true})
util_test(table.pack("a", "-b=1"), nil, {"a"}, {b="1"})
util_test(table.pack("a", "-b=1", "c"), nil, {"a", "c"}, {b="1"})

-- testing fixes for echo
util_test(table.pack("a"), {{'n'},{}}, {"a"}, {})
util_test(table.pack("-n", "a"), {{'n'},{}}, {"a"}, {n=true})

-- testing fixes for du
util_test(table.pack("du", "."), {{"hs"},{}}, {"du", "."}, {})
util_test(table.pack("du", ".", "-s"), {{"hs"},{}}, {"du", "."}, {s=true})
util_test(table.pack("du", ".", "-h"), {{"hs"},{}}, {"du", "."}, {h=true})
util_test(table.pack("du", ".", "-s", "-h"), {{"hs"},{}}, {"du", "."}, {s=true,h=true})
util_test(table.pack("du", ".", "-sh"), {{"hs"},{}}, {"du", "."}, {s=true,h=true})

-- tests for long names in expansion tests
util_test(table.pack("du", ".", "-sh"), {{"", "sh"},{}}, {"du", "."}, {sh=true})
util_test(table.pack("du", ".", "-sh"), {{"", "hs"},{}})
util_test(table.pack("du", ".", "-sh=1"), {{"", '=', "sh"},{}}, {"du", "."}, {sh='1'})
util_test(table.pack("du", ".", "-sh=1"), {{"sh", '=', "sha"},{}})
util_test(table.pack("du", ".", "-abc", "-d=1", "-efg"), {{"abc", 'efg', '=', 'd'},{}}, {"du", "."}, {a=true,b=true,c=true,d='1',efg=true})
