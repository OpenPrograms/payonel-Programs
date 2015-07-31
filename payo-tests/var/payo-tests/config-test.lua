local testutil = dofile("/var/payo-tests/testutil.lua");
local util = testutil.load("payo-lib/config");
local ser = require("serialization").serialize
local fs = require("filesystem")
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
local tutil = testutil.load("payo-lib/tableutil");

-- create local config for test
-- if exists, delete it

local tmpConfig, reason = mktmp();
if (not tmpConfig) then
  io.stderr:write(string.format("failed to create tmp config for config test: %s\n", reason));
  return false;
end

local function resetConfig()
  if (fs.exists(tmpConfig)) then
    local ok, reason = fs.remove(tmpConfig);
    if (not ok) then
      error("failed in attempt to delete existing " .. tmpConfig .. ": " .. reason)
    end
  end

  -- create file
  local f, reason = io.open(tmpConfig, "w");
  if (not f) then
    error("failed in attempt to create " .. tmpConfig .. ": " .. reason)
  end

  f:close();
end

local function both(a, b)
  return a and b or not a and not b
end

local function config_test(input, fail)
  resetConfig();

  local ok, reason = util.save(input, tmpConfig);
  if (not both(ok, not fail)) then
    io.stderr:write("invalid save " .. tostring(reason) .. "\n");
  end

  local r, reason = util.load(tmpConfig);
  if (not both(r, not fail)) then
    io.stderr:write("invalid load " .. tostring(reason) .. "\n");
  end

  local e, reason = tutil.equal(input, r);
  if (not both(e, not fail)) then
    io.stderr:write("invalid table comparision: " .. tostring(reason) .. "\n");
  end

  resetConfig();
end

config_test({}) -- should save fine, and empty
config_test({a=1})
config_test({a=1,b=2,c={d=3}})

fs.remove(tmpConfig);
