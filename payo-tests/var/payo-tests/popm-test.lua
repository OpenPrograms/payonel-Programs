local testutil = dofile("/var/payo-tests/testutil.lua");
local util = testutil.load("popm-lib/popm");
local tutil = testutil.load("payo-lib/tableutil");

local ser = require("serialization").serialize
local fs = require("filesystem");
local config = require("payo-lib/config");

local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
if (not mktmp) then
  io.stderr:write("popm test requires mktmp which could not be found\n");
  return false;
end

testutil.assert(util.isUrl("http://example.com"), true, "http: prefix check");
testutil.assert(util.isUrl("http//example.com"), false, "http prefix check");
testutil.assert(util.isUrl("https://example.com"), true, "https: prefix check");
testutil.assert(util.isUrl("https:/example.com"), false, "https: prefix check missing /");
testutil.assert(util.isUrl("asdf://example.com"), false, "asdf: prefix check");
testutil.assert(util.isUrl("http/file.cfg"), false, "http/file.cfg prefix check");
testutil.assert(util.isUrl("/path/to/file"), false, "absolute normal path check");
testutil.assert(util.isUrl(""), false, "empty string url test");
testutil.assert(util.isUrl(nil), false, "nil check");
testutil.assert(util.isUrl({}), false, "non string check");

local testFile = mktmp();
local repos_url = "https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg";

local tmp, reason = util.save(repos_url); -- quiet, keep test failures quiet when failures are expected
testutil.assert(type(tmp), type(""), "tmp path of download not string: " .. tostring(reason));
testutil.assert(tmp ~= testFile, true, "tmp path should be new");
testutil.assert(tmp:len() > 0, true, "tmp path of download too short");
testutil.assert(fs.exists(tmp), true, "download of repos.cfg dne");

if (fs.exists(tmp)) then
  fs.remove(tmp);
end

tmp = util.save("http://example.com/404.cfg");
testutil.assert(tmp, nil, "download of 404");

if (fs.exists(testFile)) then
  fs.remove(testFile)
end

tmp = util.save(repos_url, testFile);
testutil.assert(tmp, testFile, "download should use path given");
testutil.assert(fs.exists(tmp), true, "download should create path given");

if (fs.exists(tmp)) then
  fs.remove(tmp);
end

-- popm can load local files as well as remote
-- it supports http and https via wget
local repos = util.load(repos_url);
if (not repos or 
    not repos["payonel's programs"] or
    repos["payonel's programs"].repo ~= "OpenPrograms/payonel-Programs") then
  io.stderr:write("repos did not contain payonel's programs");
end

-- popm should not crash if the url is bad
local reason;
local result;
result, reason = util.load("http://example.com/404.cfg")
testutil.assert(result, nil, "load should return nil on 404");

if (fs.exists(testFile)) then
  fs.remove(testFile);
end

local testData = {a=1,b=2,c={d=true}};
config.save(testData, testFile);
local resultData = util.load(testFile); -- same as config.load
testutil.assert(testData, resultData, "result data from local load did not match");

fs.remove(testFile);

-- now test in memory download
local repos = util.load(repos_url, true);
if (not repos or 
    not repos["payonel's programs"] or
    repos["payonel's programs"].repo ~= "OpenPrograms/payonel-Programs") then
  io.stderr:write("in memory mode: repos did not contain payonel's programs");
end

result, reason = util.load("http://example.com/404.cfg", true)
testutil.assert(result, nil, "in memory mode: load should return nil on 404");
