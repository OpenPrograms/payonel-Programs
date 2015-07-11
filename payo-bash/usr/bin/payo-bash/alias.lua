
local shell = require("shell")
local raw_args = table.pack(...);

local function usage()
  io.stderr:write("invalid args: alias <k><=| ><v>");
end

if (not next(raw_args)) then
  for name, value in shell.aliases() do
      io.write(name .. " " .. value .. "\n")
  end
  return 0;
elseif (#raw_args > 2) then
  usage();
  os.exit()
end

local key = raw_args[1];
local value = raw_args[2];
local e = key:find('=')

if (e) then
  if (value) then
    usage();
    os.exit()
  end
  value = key:sub(e + 1, key:len())
  key = key:sub(1, e - 1)
elseif (not value) then
  -- allow, print alias
end

if (not key or key:len() == 0 or not value) then
  usage();
  os.exit()
end

-- value can be an empty string, like alias k=

if (not v) then
  v = shell.getAlias(arg);
  if (v) then
    io.write(v .. '\n');
  else
    io.stderr:write("no such alias: " .. k .. "\n");
  end
else  
  shell.setAlias(k, v);
  io.write("alias created: " .. k .. " -> " .. v .. '\n');
end
