local fs = require("filesystem")

local lib = "payo-lib/config"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

-- create local config for test
-- if exists, delete it

local tmpConfig = "/tmp/config-test.cfg"

local function resetConfig()
  if (not fs.exists(tmpConfig)) then
    local ok, reason = fs.remove(tmpConfig);
    if (not ok) then
      error("failed in attempt to delete existing " .. tmpConfig .. ": " .. reason)
    end
  end

  -- create file
  local f, reason = io.open(path, "w");
  if (not f) then
    error("failed in attempt to create " .. tmpConfig .. ": " .. reason)
  end

  f:close();
end

local function config_test()
  resetConfig();
end

local t = {}
