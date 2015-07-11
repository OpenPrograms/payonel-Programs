local shell = require("shell")
local argutil = require("payo-lib/argutil")
local fs = require("filesystem");

local USAGE=[[
du -[sh] path
]]

local args, options, reason = argutil.parse(table.pack(...));
    
local function writeline(value)
  io.write(value);
  io.write('\n');
end

if (not args or not options) then
  writeline(USAGE);
  return 1;
end

if (#args == 0) then
  writeline(USAGE);
  return 1;
end

local humanOpt = options.h;
options.h = nil;

local summaryOpt = options.s;
options.s = nil;

if (#options > 0) then
  writeline(USAGE);
end

local bHuman = humanOpt and humanOpt.short;
local bSummary = summaryOpt and summaryOpt.short;

local function formatSize(size)
  if not bHuman then
      return tostring(size)
  end
  local sizes = {"", "K", "M", "G"}
  local unit = 1
  local power = options.si and 1000 or 1024
  while size > power and unit < #sizes do
    unit = unit + 1
    size = size / power
  end
    
  return math.floor(size * 10) / 10 .. sizes[unit]
end

local function printSize(size, rpath)
  local displaySize = formatSize(size);
  writeline(string.format("%-20s %s", string.format("%+10s", displaySize), rpath));
end

local function visitor(rpath)
  local subtotal = 0;
  local dirs = 0;
  local spath = shell.resolve(rpath);

  if (fs.isDirectory(spath)) then
    local list_result = fs.list(spath);
    for list_item in list_result do
      local vtotal, vdirs = visitor(argutil.addTrailingSlash(rpath) .. list_item);
      subtotal = subtotal + vtotal;
      dirs = dirs + vdirs;
    end
        
    if (dirs == 0) then -- no child dirs
      if (not bSummary) then
        printSize(subtotal, rpath);
      end
    end

  elseif (not fs.isLink(spath)) then
    subtotal = fs.size(spath);
  end

  return subtotal, dirs
end

for i,arg in ipairs(args) do
  local path = shell.resolve(arg);
    
  if (not fs.exists(path)) then
    writeline(string.format("%s does not exist", arg));
  else
    if (fs.isDirectory(path)) then
      local total = visitor(arg);
                
      if (bSummary) then
        printSize(total, arg);
      end
    elseif (fs.isLink(path)) then
      printSize(0, arg);
    else
      printSize(fs.size(path), arg);
    end
  end
end


