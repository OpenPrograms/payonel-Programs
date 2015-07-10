local shell = require("shell");
local fs =  require("filesystem");

local args = shell.parse(...);

if (#args == 0) then
  print "rmdir: missing operand";
  os.exit()
end

local ec = 0;

for i = 1, #args do
  local path = shell.resolve(args[i]);
        
  if (not fs.exists(path)) then
    io.stderr:write("rmdir: cannot remove " .. args[i] .. ": path does not exist");
    ec = ec + 1;
  elseif (fs.isLink(path) or not fs.isDirectory(path)) then
    io.stderr:write("rmdir: cannot remove " .. args[i] .. ": not a directory");
    ec = ec + 1;
  else
    local list, reason = fs.list(path);
        
    if not list then
      print(reason);
      ec = ec + 1;
    else
      local hasFiles = false;
            
      for f in list do
        hasFiles = true;
        break;
      end
            
      if (hasFiles) then
        print("rmdir: failed to remove " .. path .. ": Directory not empty");
        ec = ec + 1;
      else
        -- path exists and is empty?
        shell.execute("rm -r " .. path);
      end
    end
  end
end

return ec;
