local ser = require("serialization").serialize;
local fs = require("filesystem");
local config = require("payo-lib/config");

local lib = "popm-lib/popm"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
if (not mktmp) then
  io.stderr:write("popm test requires mktmp which could not be found\n");
  return false;
end

local function passed(ok, fail_expected)
  return ok and (not fail_expected) or not ok and not (not fail_expected)
end

local function assert(actual, expected, msg)
  if (actual and expected or not actual and not expected) then
    if (actual == nil or actual ~= expected) then
      io.stderr:write(msg .. '\n');
    end
  end
end

assert(util.isUrl("http://example.com"), true, "http: prefix check");
assert(util.isUrl("http//example.com"), false, "http prefix check");
assert(util.isUrl("https://example.com"), true, "https: prefix check");
assert(util.isUrl("https:/example.com"), false, "https: prefix check missing /");
assert(util.isUrl("asdf://example.com"), false, "asdf: prefix check");
assert(util.isUrl("http/file.cfg"), false, "http/file.cfg prefix check");
assert(util.isUrl("/path/to/file"), false, "absolute normal path check");
assert(util.isUrl(""), false, "empty string url test");
assert(util.isUrl(nil), false, "nil check");
assert(util.isUrl({}), false, "non string check");

local testFile = mktmp();
local repos_url = "https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg";

local tmp, reason = util.download(repos_url); -- quiet, keep test failures quiet when failures are expected
assert(type(tmp), type(""), "tmp path of download not string: " .. tostring(reason));
assert(tmp ~= testFile, true, "tmp path should be new");
assert(tmp:len() > 0, true, "tmp path of download too short");
assert(fs.exists(tmp), true, "download of repos.cfg dne");

if (fs.exists(tmp)) then
  fs.remove(tmp);
end

tmp = util.download("http://example.com/404.cfg", nil, nil, true);
assert(tmp, nil, "download of 404");

if (fs.exists(testFile)) then
  fs.remove(testFile)
end

tmp = util.download(repos_url, testFile);
assert(tmp, testFile, "download should use path given");
assert(fs.exists(tmp), true, "download should create path given");

if (fs.exists(tmp)) then
  fs.remove(tmp);
end

-- popm can load local files as well as remote
-- it supports http and https via wget
local repos = util.load(repos_url);
if (not repos or repos["payonel's programs"] ~= "OpenPrograms/payonel-Programs") then
  io.stderr:write("repos did not contain payonel's programs");
end

-- popm should not crash if the url is bad
local reason;
local result;
result, reason = util.load("http://example.com/404.cfg")
assert(result, nil, "load should return nil on 404");

if (fs.exists(testFile)) then
  fs.remove(testFile);
end

local testData = {a=1,b=2,c={d=true}};
config.save(testData, testFile);
local resultData = util.load(testFile); -- same as config.load
assert(testData, resultData, "result data from local load did not match");

fs.remove(testFile);
