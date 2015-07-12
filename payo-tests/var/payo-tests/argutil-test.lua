package.loaded["payo-lib/argutil"]=nil
local util=require("payo-lib/argutil")

local ser=require("serialization")

local function pser(t, name)
  if (t) then
    print(name .. ":" .. ser.serialize(t))
  else
    print(name .. " nil")
  end
end

local function util_test(pack, oc)
  pser(pack, "pack")
  pser(oc, "oc")

  local args, ops, reason = util.parse(pack, oc)

  pser(args, "args")
  pser(ops, "ops")
  pser(reason, "reason")
end

util_test(table.pack("a"))
