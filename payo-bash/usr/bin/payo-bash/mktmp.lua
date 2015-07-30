local fs = require("filesystem");
local guid = require("payo-lib/guid");
local touch = loadfile("/usr/bin/touch.lua");
local argutil = require("payo-lib/argutil");

local args, ops = argutil.parse(table.pack(...))

if (not fs or not guid or not touch) then
  return nil, "missing tools for mktmp";
end

while (true) do
  local tmp = "/tmp/" .. guid.next();
  if (not fs.exists(tmp)) then
    touch(tmp);

    if (ops.v or ops.verbose) then
      io.write(tmp);
    end

    return tmp;
  end
end
