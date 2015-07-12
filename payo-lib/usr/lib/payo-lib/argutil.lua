-- instead of using =, this parses --type f as 'f' as a value for 'type'

local ser = require("serialization");

local argutil = {};

local function splitSingles(options)
  if (not options or type(options) == "table") then
    return options;
  end
    
  if (not type(options) == "string") then
    return nil;
  end
    
  local result = {};
  for i=1,#options do
    result[i] = options:sub(i, i);
  end

  return result;
end

function argutil.removeTrailingSlash(dirName)
  if (not type(dirName) == "string") then
    return "";
  elseif (#dirName == 0) then
    return "";
  end
    
  local fixedPath = dirName;
  repeat
    local lastChar = fixedPath:sub(#fixedPath, #fixedPath);
        
    if (lastChar ~= '/') then
      break;
    end
        
    fixedPath = fixedPath:sub(1, #fixedPath - 1);
  until (#fixedPath < 1);
    
  return fixedPath;
end

function argutil.addTrailingSlash(dirName)
  if (not type(dirName) == "string") then
    return "";
  end
    
  local lastChar = dirName:sub(#dirName, #dirName);

  local fixedPath = dirName;
  if (lastChar ~= "/") then
    fixedPath = fixedPath .. "/";
  end
    
  return fixedPath;
end

-- pack is a table.pack(...) for the script parameters
-- returns an array of meta data about each param
-- each param consists of:
-- name, the value given in the parameter
-- dashes, the # of dashes preceding the parameter name
-- value, the value following the parameter if specified using =
local function buildDataMeta(pack)
  if (not pack or not pack.n) then
    return nil, "arguments, even if empty, must be packed as an array"
  end

  local meta = {};

  -- split args with =, give them a value already at this point
  for _,a in ipairs(pack) do

    if (type(a) ~= type("")) then
      return nil, "All arguments must be passed as strings";
    end

    local def = {}
    a, def.dashes = a:gsub("^-*", "");

    local eIndex = a:find("=")
    
    if (eIndex) then
      if (def.dashes == 0) then
        return nil, string.format("Error parsing '%s', unexpected =. Arguments cannot have values. use options instead", a)
      end
      def.name = a:sub(1, eIndex - 1)
      def.value = a:sub(eIndex + 1, a:len());
    else
      def.name = a
    end

    meta[#meta + 1] = def;
  end

  return meta;
end

local function buildOptionMeta(pack)
  
  if (not pack) then
    return {}
  end

  local meta = {}

  -- expand first single group
  if (pack[1] and pack[1][1] and pack[1][1]:len() > 1) then
    local opC = pack[1]
    local single_names = splitSingles(opC[1]);

    for i,name in ipairs(single_names) do
      opC[#opC + 1] = name;
    end

    table.remove(opC, 1)
  end

  -- create name table
  for dashes,g in pairs(pack) do
    local assign = false
    meta[dashes] = {}

    if (not g.n) then
      return nil, "option config must only contain arrays"
    end

    for _,n in ipairs(g) do
     
      if (n == " " or n == "=") then
        assign = true
        --continue
      elseif (n:find('=')) then
        return nil, string.format("Error parsing '%s'. option names cannot contain =", n)
      else
        local def = {}
        def.dashes = dashes;
        def.name = n
        def.assign = assign

        meta[#names] = def;
      end
    end
  end
    
  return meta;
end

-- returns currentMetaOption, and reason for failure

local function optionLookup(opMeta, argMeta)

  if (not argMeta or argMeta.dashes < 1) then
    return nil, string.format("FAILURE: %s is not an option", argMeta.name);
  end

  if (not opMeta or not opMeta[argMeta.dashes]) then -- all is allowed
    local adhoc = {}
    adhoc.name = argMeta.name
    adhoc.assign = not not argMeta.value;
    adhoc.dashes = argMeta.dashes
    return adhoc;
  end

  for _,def in ipairs(opMeta) do
    if (argMeta.dashes == def.dashes) then
      if (argMeta.name == def.name) then
        return argMeta;
      end
    end
  end

  return nil, "unexpected option: " .. argMeta.name;
end

--[[
opConfig structure

index array where index is the dash count
e.g. [1] represents configurations for single dash options, e.g. -a

each value is a table
[1] is for single dashed options
[2] is for double dashed options

[1] = the first index is for singles and is split, all remaining names are not split
e.g. "abc", "def", "ghi" => "a", "b", "c", "def", "ghi"
[2] = array of long option names

anywhere in the chain of names when a '=' or ' ' is listed, the subsequent names are
expected to have values

e.g.
[1] = "abc d"
a, b, and c are enabled options (true|false)
d takes a value, separated by a space, such as -d value
[2] = "foo", "=", "bar"
foo is an option that is enabled
bar takes a value, given after an =, such as -bar=zoopa

= is always allowed to give option values
if ' ' is specified, both are allowed

e.g.
[1] = " d"
-d 1
d is 1
-d=1
d is 1

extra white space is never allowed around an assignment operator
e.g. (do not do this) -a = foobar
That would be a parse error: unexpected =

An assignment operator doesn't have to have a value following it
e.g. -a= foobar
In this case, a="", and foobar is an argument

The default behavior (that is, no opConfig) puts makes all naked options enabled (true|false)
The default behavior is to assign an option a value after =

the option config can be nil or an empty table for default behavior
each index that corresponds to a number of dashes must be nil for default
behavior to be used. That is, [1]={} will not allow any single dash options,
but [1]=nil will implicitly allow all

]]

-- returns arg table, option table, and reason string
function argutil.parse(pack, opConfig)
  -- the config entries can be nil, but opConfig can't
  opConfig = opConfig or {};

  local opMeta, reason = buildOptionMeta(opConfig)
  if (not opMeta) then
    return nil, nil, reason
  end

  local metaPack, reason = buildDataMeta(pack);

  if (not metaPack) then
    return nil, nil, reason;
  end

  local args = {};
  local options = {};
    
  local pending = nil;
    
  for i,meta in ipairs(metaPack) do
    local bOp = meta.dashes > 0;
        
    if (bOp) then
      if (pending) then
        return nil, nil, string.format("%s missing value", pending);
      else
        local currentOpMeta, reason = optionLookup(opMeta, meta);
                
        if (not currentOpMeta) then
          return nil, nil, reason;
        end

        local key = currentOpMeta.name;
                    
        if (options[key]) then
          return nil, nil, string.format("option %s defined more than once", key);
        end
                
        options[key] = {};
        options[key].dashes = meta.dashes;
                
        -- does this option expect a value?
        if (currentOpMeta.assign) then
          if (not meta.value) then
            pending = meta.name
          else
            options[key].value = meta.value;
          end
        else -- enabled
          if (meta.value) then
            return nil, nil, string.format("unexpected = after %s; it does not take a value", key)
          end
          options[key].value = true;
        end
      end
    elseif (pending) then
      if (meta.value) then
        return nil, nil, string.format("unexpected = in value for %s: %s", pending, meta.name .. '=' .. meta.value)
      end
      options[pending].value = meta.name;
      pending = nil;
    else
      args[#args + 1] = meta.name;
    end
  end

  if (pending) then
    return nil, nil, string.format("%s missing value", pending);
  end

  return args, options;
end

return argutil;
