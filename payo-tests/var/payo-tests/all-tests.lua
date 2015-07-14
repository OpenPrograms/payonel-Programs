local tests =
{
  "argutil-test.lua", 
  "argutil-test.lua", 
  "argutil-test.lua", 
  "argutil-test.lua", 
};

local stringutil = require("payo-lib/stringutil")

local pwd = stringutil.getParentDirectory(os.get("_"))

for _,test in ipairs(tests) do
  dofile(pwd .. test)
end
