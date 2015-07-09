-- instead of using =, this parses --type f as 'f' as a value for 'type'

local ser = require("serialization");

local argutil = {};

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
-- shorts are options that can be enabled with a single char
-- longs are options that can be enabled by long name

function argutil.buildMeta(pack, bLongNamesDefinedForSingles)
    local metaPack = {};
    
    -- how is pack packed?
    if (not pack.n) then
        return nil, "arg pack must be an array"
    end
    
    for i,arg in ipairs(pack) do
        
        local dashes = arg:match("^-+") or "";
        dashes = #dashes;
        local split = {arg:sub(dashes + 1, #arg)};
        
        if (dashes == 1) then
            if (not bLongNamesDefinedForSingles) then
                local singles = split[1];
                split = {};
                for i=1,#singles do
                    split[#split + 1] = singles:sub(i, i);
                end
            end
        end

        for i,entry in ipairs(split) do
            local meta = {}
            meta.dashes = dashes;
            meta.value = entry;
            metaPack[#metaPack + 1] = meta;
        end
    end
    
    return metaPack;
end

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

-- returns key, value, and reason for failure
-- value: nil indicates there is a pending value on the next argument
-- value: not nil indicates the value for the option

local function optionLookup(optionMeta, opConfig)
    if (not optionMeta or optionMeta.dashes < 1) then
        return nil, nil, "invalid option meta";
    end
    
    local optionIndex = optionMeta.dashes;
    local optionConfig = opConfig[optionIndex];
    if (not optionConfig) then -- all are allowed, and no value assigned
        return optionMeta.value, true, nil;
    end
    
    local bFound = false;
    local pending = nil;
    for i,g in ipairs(optionConfig) do
        
        -- g for single names and long names
        if (type(g) ~= "table") then
            return nil, nil, string.format(
                "malformed options configuration, expecting table group for dash length %i", 
                optionMeta.dashes);
        end
        
        pending = nil; -- reset
        
        for j,t in ipairs(g) do
            
            -- t for token, a single
            if (type(t) ~= "string") then
                return nil, nil, string.format(
                    "malformed options configuration, expecting string token in dash length %i", 
                    optionMeta.dashes);
            end
        
            if (t == ' ' or t == '=') then
                pending = t;
            elseif (t == optionMeta.value) then
                bFound = true;
                break;
            end
        end
    end

    if (not bFound) then
        return nil, nil, string.format("invalid option: %s", optionMeta.value);
    end
    
    if (pending == '=') then -- extract value
        local eIndex = optionMeta.value:find("=");
        if (eIndex) then
            local key = optionMeta.value:sub(1, eIndex - 1);
            local value = optionMeta.value:sub(eIndex + 1, #optionMeta.value);
            return key, value, nil;
        end
    elseif (pending == ' ') then -- next arg
        return optionMeta.value, nil, nil;
    end
    
    -- enabled(true/false) type option

    return optionMeta.value, true, nil;
end

--[[

opConfig structure

index array where index is the dash count
e.g. [1] represents configurations for single dash options, e.g. -a

each value is a table
[1] = string or array of single char option names
[2] = array of long option names

shorts or longs separated by a '=' or ' ' entry indicates that the folllowing
names are to be assigned. ' ' means the following argument is its value, '='
means a = is used to give the value

e.g.

[1], "abcd f", {"verbose", " ", "type"}

]]--

-- returns arg table, option table, and reason string
function argutil.parse(pack, opConfig)
    -- the config entries can be nil, but opConfig can't
    opConfig = opConfig or {};

    -- expand any singles strings
    for i,opC in ipairs(opConfig) do
        opConfig[i][1] = splitSingles(opC[1]);
    end

    -- split singles by default
    -- don't split singles when long names are defined for singles
    local bLongNamesDefinedForSingles = opConfig[1] and opConfig[1][2];
    local metaPack, reason = argutil.buildMeta(pack, bLongNamesDefinedForSingles);

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
                local key, value, reason = optionLookup(meta, opConfig);
                
                if (not key) then
                    return nil, nil, reason;
                end
                    
                if (options[key]) then
                    return nil, nil, string.format("option %s defined more than once", key);
                end
                
                options[key] = {};
                options[key].dashes = meta.dashes;
                
                if (not value) then
                    pending = key;
                else
                    options[key].value = value;
                end
            end
        elseif (pending) then
            options[pending].value = meta.value;
            pending = nil;
        else
            args[#args+1] = meta.value;
        end
    end

    if (pending) then
        return nil, nil, string.format("%s missing value", pending);
    end

    return args, options;
end

return argutil;
