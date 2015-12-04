local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize

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
  local equal = tutil.equal(args, expected_args) and tutil.equal(ops, expected_ops);

  testutil.bump(pass_ok and equal)
  if (not pass_ok or not equal) then
    io.stderr:write(ser(dump) .. '\n')
  end
end

util_test(table.pack(), nil, {}, {});
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
