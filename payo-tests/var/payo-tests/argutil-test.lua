package.loaded["payo-lib/argutil"]=nil
local util=require("payo-lib/argutil")

local ser=require("serialization")

local function pser(t)
  print(ser.serialize(t))
end

local function table_equals(t1, t2)

  if (not t1 ~= not t2) then
    return false
  end

  local m2 = t2;

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
    m2[k] = nil
  end

  if (next(m2)) then
    return false
  end

  return true
end

local function util_test(pack, oc, expected_args, expected_ops, pass)

  local dump = {}
  dump.pack = pack
  dump.oc = oc
  dump.expected_args = expected_args
  dump.expected_ops = expected_ops

  local args, ops, reason = util.parse(pack, oc)

  dump.args = args
  dump.ops = ops
  dump.reason = reason

  if (not args or not ops) then
    if (pass) then
      print(ser.serialize(dump))
    end
  elseif (not table_equals(args, expected_args) or not table_equals(ops, expected_ops)) then
    print(ser.serialize(dump))
  end
end

io.write("running values from command line\n");
util_test(table.pack(...))

io.write("running additional tests\n");
util_test(table.pack("a"), nil, {"a"}, {})
util_test(table.pack("a", "-b"), nil, {"a"}, {b=true})
util_test(table.pack("a", "-b=1"), nil, {"a"}, {b=1})
util_test(table.pack("a", "-b=1", "c"), nil, {"a", "c"}, {b=1})
