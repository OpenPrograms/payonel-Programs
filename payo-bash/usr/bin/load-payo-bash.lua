local fs = require("filesystem");
local util = require("stringutil");

local function getParentDirectory(filePath)
  return ""
end

local function hijackPath()
  local DELIM = ":";
  local PREF = getParentDirectory(_G._);
    
  local pathText = os.getenv("PATH");
  if (not pathText) then
    io.stderr:write("unexpected failure. PATH has not been set\n");
    return 1;
  end

  local paths, indices = util.split(pathText, DELIM, true);

  -- now let's rebuild the path as we want it
  local path = PREF;
  table.remove(paths, indices[PREF]);
  indices[PREF] = nil;

  for i,p in ipairs(paths) do
    path = path .. DELIM .. p;
  end
    
  os.setenv("PATH", path);
end

hijackPath();
