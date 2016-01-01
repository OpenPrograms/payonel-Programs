--[[

Taken from Wobbo at https://raw.githubusercontent.com/OpenPrograms/Wobbo-Programs/master/grep/grep.lua

]]--

--- POSIX grep for OpenComputers, only difference is that this version uses Lua regex, not POSIX regex.
--
-- Depends on getopt by Wobbo. 

local fs = require("filesystem")
local shell = require("shell")
local process = require("process")

-- Specify the variables for the options
local plain = false
local count = nil
local ignoreCase = false
local writeNamesOnce = false
local linNumber = nil
local quiet = false
local fileError = true
local invert = false
local metchWhole = false
local printNames = false
local recursiveFileSearch = false;

local function write(value)
  local stdout = io.output()
  local stream = stdout and stdout.stream
  if stream then
    stream.wrap = true
    io.write(value)
    stdout:flush()
    stream.wrap = nil
  end
end

local function writeline(value)
  write(value);
  write('\n');
end

-- Table with patterns to check for
local patternList = {}

local function printUsage()
  local process = require("process")
  writeline('Usage: '..process.running()..' [-c|-l|-q][-Finsvx] [-e pattern] [-f patternFile] [pattern] [file...]')
end

-- Resolve the location of a file, without searching the path
local function resolve(file)
  if file:sub(1,1) == '/' then
    return fs.canonical(file)
  else
    if file:sub(1,1) == '.' then
      file = file:sub(3, -1)
    end
    return fs.canonical(fs.concat(shell.getWorkingDirectory(), file))
  end
end

-- Checks if it should error, and errors if that is required
local function fileError(file)
  if fileError then
    writeline(process.running()..': '..file..': No such file or directory')
  end
end

--- Builds a case insensitive pattern, code from stackOverflow (questions/11401890/case-insensitive-lua-pattern-matching)
local function caseInsensitivePattern(pattern)
  -- find an optional '%' (group 1) followed by any character (group 2)
  local p = pattern:gsub("(%%?)(.)", function(percent, letter)
    if percent ~= "" or not letter:match("%a") then
      -- if the '%' matched, or `letter` is not a letter, return "as is"
      return percent .. letter
    else
      -- else, return a case-insensitive character class of the matched letter
      return string.format("[%s%s]", letter:lower(), letter:upper())
    end
  end)
  return p
end

-- Process the command line arguments

local optionConfiguration = { {"ilnvxr"} };
local args, options, reason = shell.parse(...)

if #args < 1 then
  printUsage()
  return 2
end

if (not options) then
  writeline(reason);
  return 1;
end

for opt,v in pairs(options) do
    
--  if (v.dashes ~= 1) then
--    printUsage();
--    return 2;
--  end
    
  if (opt == 'i') then
    ignoreCase = true;
  elseif (opt == 'l') then
    writeNamesOnce = true;
  elseif (opt == 'n') then
    lineNumber = 1;
  elseif (opt == 'v') then
    invert = true;
  elseif (opt == 'x') then
    matchWhole = true;
  elseif (opt == 'r') then
    recursiveFileSearch = true;
    -- if no path given, recusives assumes .
    args[#args+1]=".";
  else
    printUsage();
    return 1;
  end
end

-- Check if there are patterns, if not, get args[1] and add it to the list
if #patternList == 0 then
  if #args < 1 then
    printUsage()
    return 2
  else
    table.insert(patternList, table.remove(args, 1))
  end
end

local function getAllFiles(dir, file_list)
  local spath = shell.resolve(dir);
  for node in fs.list(spath) do
    local node_path = shell.resolve(spath ..'/'.. node);
    if (fs.isDirectory(node_path)) then
      getAllFiles(node_path, file_list)
    else
      file_list[#file_list+1] = node_path;
    end
  end
end

local files = args;

if (recursiveFileSearch) then
  -- treat args as a list of dirs, and get all the files
  files = {};
  for i,arg in ipairs(args) do
    if (fs.isDirectory(arg)) then
      getAllFiles(arg, files);
    end
  end
end

-- remove file duplicates
local set = {};
local buf = {};
for i,file in ipairs(files) do
  if (not set[file]) then
    buf[#buf+1] = file;
    set[file] = true;
  end
end

files = buf;
set = nil;
buf = nil;

-- if not file specified, use stdin
if (#files == 0) then
  files[1] = "-"
end

-- Prepare an iterator for reading files
local readLines =
function()
  local curHand = nil
  local curFile = nil
  return function()
    if not curFile then
      local k,file = next(files);
      if (not file) then
        return false, nil
      end
      files[k] = nil;
      if (file == "-") then
        curFile = file;
        curHand = io.input();
      else
        file = resolve(file);
        if (fs.exists(file)) then
          curFile = file
          curHand = io.open(curFile, 'r')
          if (lineNumber) then
            lineNumber = 1
          end
        else
          fileError(file)
          return false, "file not found"
        end
      end
    end
    local line = nil;
    if (curHand) then
      line = curHand:read("*l");
    end
    if not line then
      curFile = nil
      if (curHand and curHand ~= io.input()) then
        curHand:close();
      end
      if (not next(files)) then
        return nil
      else
        return false, "end of file"
      end
    else
      return line, curFile
    end
  end
end


if (recursiveFileSearch) then
  printNames = true;
end

local matchFile = nil
for line, file in readLines() do
  if not line then
    if file ~= "end of file" then
      return 2
    end
  else
    file = file or '(standard input)'
    if line then
      local match = false
      for _, pattern in pairs(patternList) do
        if ignoreCase then
          pattern = caseInsensitivePattern(pattern)
        end
        local i, j = line:find(pattern, 1, plain)
        if not matchWhole then
          match = i and true or match
        else
          if j == #line and i == 1 then
            match = true
          end
        end
      end
      if match ~= invert then
        if quiet then
          return 0
        end
        if not count then
          if writeNamesOnce then
            if matchFile ~= file then
              writeline(file)
            end
          else
            if printNames then
              write(file..': ')
            end
            if lineNumber then
              write(lineNumber..': ')
            end
            writeline(line)
          end
        elseif matchFile ~= file then
          if printNames then
            write(matchFile': ')
          end
          writeline(count)
          count = 1
        else
          count = count + 1
        end
        matchFile = file
      end
      if lineNumber then
        lineNumber = lineNumber + 1
      end
    end
  end
end

return (matchFile and 0 or 1)

