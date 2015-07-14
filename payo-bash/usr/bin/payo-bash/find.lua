local fs = require("filesystem");
local shell = require("shell");
local argutil = require("payo-lib/argutil");
local stringutil = require("payo-lib/stringutil")

local USAGE = 
[===[Usage: find [path] [--type [dfs]] [--[i]name EXPR]
  path:  if not specified, path is assumed to be current working directory
  type:  returns results of a given type, d:directory, f:file, and s:symlinks
  name:  specify the file name pattern. Use quote to include *. iname is 
         case insensitive
]===]

local packedArgs = table.pack(...);
local optionConfiguration = {{'',' ', "type", "name", "iname"},{}};

local args, options, reason = argutil.parse(packedArgs, optionConfiguration);

local function writeline(value, pipe)
  (pipe or io.stdout):write(value);
  (pipe or io.stdout):write('\n');
end

if (not args or not options) then
  writeline(USAGE, io.stderr);
  writeline(reason, io.stderr);
  return 1;
end

if (#args > 1) then
  writeline(USAGE, io.stderr)
  return 1;
end

local path = "."; -- no arg

if (#args == 1) then
  path = args[1];
end

local bDirs = true;
local bFiles = true;
local bSyms = true;

local fileNamePattern = "";
local bCaseSensitive = true;

if (options.iname and options.name) then
  io.stderr:write("find cannot define both iname and name");
  return 1;
end

if (options.type) then
  bDirs = false;
  bFiles = false;
  bSyms = false;

  if (options.type == "f") then
    bFiles = true;
  elseif (options.type == "d") then
    bDirs = true;
  elseif (options.type == "s") then
    bSyms = true;
  else
    writeline(USAGE, io.stderr);
    return 4;
  end
end

if (options.iname or options.name) then
  bCaseSensitive = options.iname ~= nil;
  fileNamePattern = options.iname or options.name
end  

if (not fs.isDirectory(path)) then
  writeline("path is not a directory or does not exist: " .. path);
  return 1;
end

local function isValidType(spath)
  if (not fs.exists(spath)) then
    return false;
  end
    
  if (#fileNamePattern > 0) then
    local segments = fs.segments(spath);
    local fileName = segments[#segments];
        
    -- fileName is false when there are no segments (i.e. / only)
    -- which matches nothing
    if (not fileName) then
      return false;
    end
        
    local caseFileName = fileName;
    local casePattern = fileNamePattern;
        
    if (not bCaseSensitive) then
      caseFileName = caseFileName:lower();
      casePattern = casePattern:lower();
    end
        
    -- prefix any * with . for gnu find glob matching
    casePattern = casePattern:gsub("%*", ".*");
        
    local s, e = caseFileName:find(casePattern);
    if (not s or not e) then
      return false;
    end
        
    if (s ~= 1 or e ~= #caseFileName) then
      return false;
    end
  end

  if (fs.isDirectory(spath)) then
    return bDirs;
  elseif (fs.isLink(spath)) then
    return bSyms;
  else
    return bFiles;
  end
end

local function visit(rpath)
  local spath = shell.resolve(rpath);

  if (isValidType(spath)) then
    writeline(stringutil.removeTrailingSlash(rpath));
  end

  if (fs.isDirectory(spath)) then
    local list_result = fs.list(spath);
    for list_item in list_result do
      visit(stringutil.addTrailingSlash(rpath) .. list_item);
    end
  end
end

visit(path);

return 0;
