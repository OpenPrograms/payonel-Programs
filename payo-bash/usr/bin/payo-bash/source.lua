local shell = require("shell");
local fs = require("filesystem");

local args, options = shell.parse(...);

if (#args ~= 1) then
  io.stderr:write("specify a single file to source");
  return 1;
end

local path = shell.resolve(args[1]);
    
local file, reason = io.open(path, "r");

if (not file) then
  if (not options.q) then
    io.stderr:write(string.format("could not source %s because: %s", args[1], reason));
  end
  return 1;
else
  repeat
    local line = file:read("*L")
    if (line) then
      os.execute(line);
    end
  until (not line)
end

file:close();
