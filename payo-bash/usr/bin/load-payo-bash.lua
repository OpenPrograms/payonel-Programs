local fs = require("filesystem");
local text = require("text");

local function getParentDirectory(filePath)

  local pwd = os.getenv("PWD")

  if (not filePath) then
    return pwd
  end

  local si, ei = filePath:find("/[^/]+$")
  if (not si) then
    return pwd
  end

  return filePath:sub(1, si - 1)
end

local function hijackPath()
  local delim = ":";
  local pref = getParentDirectory(os.getenv("_"));
  pref = pref .. "/payo-bash";

  local pathText = os.getenv("PATH");
  if (not pathText) then
    io.stderr:write("unexpected failure. PATH has not been set\n");
    return 1;
  end

  local paths, indices = text.split(pathText, {delim}, true);

  -- now let's rebuild the path as we want it
  local path = pref;
  table.remove(paths, indices[pref]);
  indices[pref] = nil;

  for i,p in ipairs(paths) do
    path = path .. delim .. p;
  end
    
  os.setenv("PATH", path);
end

hijackPath();
