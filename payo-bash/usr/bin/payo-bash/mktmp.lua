local fs = require("filesystem");
local guid = require("payo-lib/guid")
local shell = require("shell")
local touch = loadfile(shell.resolve("touch", "lua"))
local argutil = require("payo-lib/argutil");
local mkdir = loadfile(shell.resolve("mkdir", "lua"))

local args, ops = argutil.parse(table.pack(...))

if (not fs or not guid or not touch) then
  local errorMessage = "missing tools for mktmp"
  io.stderr:write(errorMessage .. '\n');
  return nil, errorMessage;
end

while (true) do
  local tmp = "/tmp/" .. guid.next();
  if (not fs.exists(tmp)) then

    if ops.d or ops.directory then
      mkdir(tmp)
    else
      touch(tmp);
    end

    if (ops.v or ops.verbose) then
      io.write(tmp);
    end

    return tmp;
  end
end
