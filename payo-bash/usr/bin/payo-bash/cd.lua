local shell = require("shell")
local fs = require("filesystem");

local args = shell.parse(...)
local path = "";
if #args == 0 then
  path = os.getenv("HOME");
elseif args[1] == '-' then
  local oldpwd = os.getenv("OLDPWD");
  if oldpwd == nil then
    io.stderr:write("bash: cd: OLDPWD not set\n")
  else
    os.execute("cd " .. oldpwd);
    os.execute("pwd");
    return;
  end
else
  path = shell.resolve(args[1]);
end

local oldpwd = shell.getWorkingDirectory()
local result, reason = shell.setWorkingDirectory(path);
if not result then
  io.stderr:write(reason)
else
  os.setenv("OLDPWD", oldpwd)
end
