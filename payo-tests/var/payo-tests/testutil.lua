local util = {};
local ser = require("serialization").serialize
local tutil = require("payo-lib/tableutil");
local shell = require("shell")
local fs = require("filesystem")

local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua")
if (not mktmp) then
  io.stderr:write("testutils requires mktmp which could not be found\n")
  return false
end

util.asserts = 0
util.assert_max = 10
util.total_tests_run = 0

function util.bump(ok)
  util.total_tests_run = util.total_tests_run + 1
  if ok == true then return true end

  util.asserts = util.asserts + 1
  if util.asserts >= util.assert_max then
    io.stderr:write("Too many asserts")
    os.exit(1)
  end
  return false
end

function util.load(lib)
  package.loaded[lib] = nil;
  local result = require(lib);

  if (not result) then
    error("failed to load library: " .. result);
    return nil; -- shouldn't happen after an error
  end
  return result;
end

util.broken_handler = {}
util.broken_handler.__index = function(table_, key_)
  return function(...) end
end

util.broken = {}
setmetatable(util.broken, util.broken_handler)

function util.assert(msg, expected, actual, detail)
  local etype = type(expected);
  local atype = type(actual);
  local detail_msg = detail and string.format(". detail: %s", detail) or ""

  if (etype ~= atype) then
    io.stderr:write(string.format("%s: mismatch type, %s vs %s. expected value: |%s|. %s\n", msg, etype, atype, ser(expected), detail_msg));
    return util.bump()
  end
  
  -- both same type

  if (etype == nil) then -- both nil
    return true;
  end

  local matching = true;
  if (etype == type({})) then
    if (not tutil.equal(expected, actual)) then
      matching = false;
    end
  elseif (expected ~= actual) then
    matching = false;
  end

  if (not matching) then
    io.stderr:write(string.format("%s: %s ~= %s. %s\n", msg, ser(expected), ser(actual), detail_msg));
  end

  return util.bump(matching)
end

function util.assert_files(file_a, file_b)
  util.bump(true)
  local path_a = shell.resolve(file_a)
  local path_b = shell.resolve(file_b)

  assert(fs.exists(path_a))
  assert(fs.exists(path_b))

  assert(not fs.isDirectory(path_a))
  assert(not fs.isDirectory(path_b))

  local a_handle = io.open(path_a)
  local b_handle = io.open(path_b)

  local a_data = a_handle:read("*a")
  local b_data = b_handle:read("*a")

  a_handle:close()
  b_handle:close()

  assert(type(a_data) == "string")
  assert(type(b_data) == "string")
  assert(a_data == b_data)
end

function util.assert_process_output(cmd, expected_output)
  util.bump(true)
  local piped_file = mktmp()
  local full_cmd = cmd .. " > " .. piped_file
  os.execute(full_cmd)
  assert(fs.exists(piped_file))
  local piped_handle = io.open(piped_file)
  local piped_data = piped_handle:read("*a")
  piped_handle:close()
  fs.remove(piped_file)

  if (piped_data ~= expected_output) then
    io.stderr:write(string.format("lengths: %i, %i:", piped_data:len(), 
      expected_output:len()))
    io.stderr:write(string.format("%s", piped_data:gsub("\n", "\\n")))
    io.stderr:write("[does not equal]")
    io.stderr:write(string.format("%s\n", expected_output:gsub("\n", "\\n")))
    util.bump()
  end
end

return util;
