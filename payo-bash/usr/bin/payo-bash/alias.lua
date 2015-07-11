
local shell = require("shell")
local argutil = require("payo-lib/argutil");
local args, ops = argutil.parse(table.pack(...))
    
if (next(ops)) then
  print("alias does not take any options");
  return 1;
end

if (not next(args)) then
  for name, value in shell.aliases() do
      io.write(name .. " " .. value .. "\n")
  end
  return 0;
end

for i,arg in ipairs(args) do
  local eIndex = arg:find("=");
  if (not eIndex) then
    local value = shell.getAlias(arg);
    if (value) then
      print(value);
    else
      io.stderr:write("no such alias: " .. arg .. "\n");
    end
  else
    local key = arg:sub(1, eIndex - 1);
    local value = arg:sub(eIndex + 1, #arg);
    shell.setAlias(key, value);
    print("alias created: " .. key .. " -> " .. value);
  end
end
