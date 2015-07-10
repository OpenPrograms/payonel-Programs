local shell = require("shell")
local fs = require("filesystem")

local args, options = shell.parse(...)
if #args == 0 then
  io.write("Usage: rm [-v]  [ [...]]\n")
  io.write(" -v: verbose output.")
  return
end

local function writeline(value)
    io.write(value);
    io.write('\n');
end

local bRec = false;
local bForce = false;
local bVerbose = false;
local pathVec = {};

for k, op in pairs(options) do
    if (k == "r") then
        bRec = true;
    elseif (k == "f") then
        bForce = true;
    elseif (k == "v") then
        bVerbose = true;
    else
        io.stderr:write("rm: error unknown option: " .. k);
    end
end

for i = 1, #args do
    local path = shell.resolve(args[i])
    local bRm = false;
    local bLink = fs.isLink(path);
    
    if (fs.exists(path) or bLink) then
        if (fs.isDirectory(path)) then
            if (bRec or bLink) then
                bRm = true;
            else
                io.stderr:write("rm: cannot remove `" .. args[i] .. "': Is a directory");
            end
        else
            bRm = true; -- always try to remove simple files
        end
        
        if (bRm) then
            if not os.remove(path) then
                io.stderr:write(args[i] .. ": no such file, or permission denied\n")
            elseif (bLink) then
                --local psym = require('persisted_symlinks');
                --local reason = psym.removeLink(path);
                
            --if (reason) then
            --        io.stderr:write(string.format("%s link removal error: %s\n", 
            --            path, reason));
            --    end
            end
            if options.v then
                io.write("removed '" .. args[i] .. "'\n");
            end
        end
    else
        io.stderr:write("rm: no such file or directory `" .. path .. "'");
    end
end


