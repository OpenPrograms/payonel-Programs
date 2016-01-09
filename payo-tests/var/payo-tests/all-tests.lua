local tests =
{
  "guid-test.lua",
  "tableutil-test.lua", 
  "config-test.lua", 
  "argutil-test.lua",
  "text-test.lua",
  "pipes-test.lua",
  "transforms-test.lua",
  "shell-test.lua",
  "sh-test.lua",
  "slow-test.lua",
  "popen-test.lua"
  --"popm-test.lua", 
};

local fs = require("filesystem")

local pwd = fs.parentDir(os.getenv("_"))
local total_tests_run = 0

for _,test in ipairs(tests) do
  package.loaded.testutil = nil
  local testutil = require('testutil')
  testutil.total_tests_run = 0

  io.write("Running test: " .. test)
  dofile(pwd .. test)
  local tests_run = testutil.total_tests_run
  io.write(' [' .. tostring(tests_run) .. ']\n')

  total_tests_run = total_tests_run + tests_run
end

print("Total Tests Run", total_tests_run)
