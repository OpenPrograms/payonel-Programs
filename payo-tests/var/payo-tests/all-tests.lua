local tests =
{
  "tableutil-test.lua", 
  "stringutil-test.lua", 
  "config-test.lua", 
  "argutil-test.lua", 
};

local stringutil = require("payo-lib/stringutil")

local pwd = stringutil.getParentDirectory(os.getenv("_"))

for _,test in ipairs(tests) do
  print("Running test: " .. test)
  dofile(pwd .. test)
end
