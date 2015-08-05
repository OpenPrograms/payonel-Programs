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

testutil.assert("http: prefix check", true, util.isUrl("http://example.com"));
testutil.assert("http prefix check", false, util.isUrl("http//example.com"));
testutil.assert("https: prefix check", true, util.isUrl("https://example.com"));
testutil.assert("https: prefix check missing /", false, util.isUrl("https:/example.com"));
testutil.assert("asdf: prefix check", false, util.isUrl("asdf://example.com"));
testutil.assert("http/file.cfg prefix check", false, util.isUrl("http/file.cfg"));
testutil.assert("absolute normal path check", false, util.isUrl("/path/to/file"));
testutil.assert("empty string url test", false, util.isUrl(""));
testutil.assert("nil check", nil, util.isUrl(nil));
testutil.assert("non string check", nil, util.isUrl({}));

local testFile = mktmp();
local repos_url = "https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg";

local tmp, reason = util.save(repos_url); -- quiet, keep test failures quiet when failures are expected
testutil.assert("tmp path of download not string: " .. tostring(reason), type(""), type(tmp));
testutil.assert("tmp path should be new", true, tmp ~= testFile);
testutil.assert("tmp path of download too short", true, tmp:len() > 0);
testutil.assert("download of repos.cfg dne", true, fs.exists(tmp));

if (fs.exists(tmp)) then
  fs.remove(tmp);
end

tmp = util.save("http://example.com/404.cfg");
testutil.assert("download of 404", nil, tmp);

if (fs.exists(testFile)) then
  fs.remove(testFile)
end

tmp = util.save(repos_url, testFile);
testutil.assert("download should use path given", testFile, tmp);
testutil.assert("download should create path given", true, fs.exists(tmp));

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
testutil.assert("load should return nil on 404", nil, result);

if (fs.exists(testFile)) then
  fs.remove(testFile);
end

local testData = {a=1,b=2,c={d=true}};
config.save(testData, testFile);
local resultData = util.load(testFile); -- same as config.load
testutil.assert("result data from local load did not match", resultData, testData);

fs.remove(testFile);

-- now test in memory download
local repos, reason = util.load(repos_url, true);
if (not repos or 
    not repos["payonel's programs"] or
    repos["payonel's programs"].repo ~= "OpenPrograms/payonel-Programs") then
  io.stderr:write("in memory mode: repos did not contain payonel's programs: " .. tostring(reason));
end

testutil.assert("in memory mode: load should return nil on 404: ", nil, util.load("http://example.com/404.cfg", true));

testutil.assert("popm config path", "/etc/popm/popm.cfg", util.configPath());
testutil.assert("popm database path", "/etc/popm/popm.svd", util.databasePath());

util.migrate(); -- upgrade system from opdata.svd to use popm database world file
local popm_config = util.database();
testutil.assert("confirming world databsae file including payo-tests", false, popm_config.world["payo-tests"].dep);

-- add sync test
testutil.assert("sync", true, util.sync());
