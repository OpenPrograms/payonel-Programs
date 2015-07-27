local ser = require("serialization").serialize;
local fs = require("filesystem");
local config = require("payo-lib/config");

local lib = "popm-lib/popm"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

local function passed(ok, fail_expected)
  return ok and (not fail_expected) or not ok and not (not fail_expected)
end

local function assert(actual, expected, msg)
  if (actual and expected or not actual and not expected) then
    if (not actual or actual ~= expected) then
      io.stderr:write(msg .. '\n');
    end
  end
end

-- popm can load local files as well as remote
-- it supports http and https via wget
local repos = util.load("https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg");
if (not repos or repos["payonel's programs"] ~= "OpenPrograms/payonel-Programs") then
  io.stderr:write("repos did not contain payonel's programs");
end

-- popm should not crash if the url is bad
local reason;
local result;
result, reason = util.load("http://example.com/404.cfg")
assert(result, nil, "load should return nil on 404");

local testFile = "/tmp/popm-test-3c44c8a9-0613-46a2-ad33-97b6ba2e9d9a";
if (fs.exists(testFile)) then
  fs.remove(testFile);
end

local testData = {a=1,b=2,c={d=true}};
config.save(testData, testFile);
local resultData = util.load(testFile); -- same as config.load
assert(testData, resultData, "result data from local load did not match");

fs.remove(testFile);
