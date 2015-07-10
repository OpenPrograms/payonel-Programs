local shell = require("shell")
local fs = require("filesystem");

local args = shell.parse(...)
local path = "";
if #args == 0 then
  path = os.getenv("HOME");
    
  if (not fs.exists(path)) then
    fs.makeDirectory(path);
  end
else
  path = shell.resolve(args[1]);
end

local result, reason = shell.setWorkingDirectory(path);
if not result then
  io.stderr:write(reason)
end


