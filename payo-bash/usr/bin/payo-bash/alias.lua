
local shell = require("shell")
local raw_args = table.pack(...);

local function usage()
  io.stderr:write("invalid args: alias <k><=| ><v>");
end

if (raw_args.n == 0) then
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
  if (e == 1 or value) then
    usage();
    os.exit()
  end
  value = key:sub(e + 1, key:len())
  key = key:sub(1, e - 1)
elseif (not value) then
  -- allow, print alias
else
  -- allow original openos alias format (i.e. no equals)
end

if (not key or key:len() == 0) then
  usage();
  os.exit()
end

-- value can be an empty string, like alias k=

if (not value) then
  value = shell.getAlias(key);
  if (value) then
    io.write(value .. '\n');
  else
    io.stderr:write("no such alias: " .. key .. "\n");
  end
else  
  shell.setAlias(key, value);
  io.write("alias created: " .. key .. " -> " .. value .. '\n');
end
