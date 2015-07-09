local fs = require("filesystem");
local ser = require("serialization");

local payo = {};

local function split(text, delim)
    if (not text or not delim) then
        return nil, "cannot split a nil string nor on a nil delim";
    end
    
    if (type(text) ~= "string" or type(delim) ~= "string") then
        return nil, "cannot split non text on non text";
    end
    
    if (#text == 0) then
        return {};
    end
    
    if (#delim > 1) then
        return nil, "current delimeters longer that 1 character are not supported";
    end
    
    local iterator = text:gmatch("[^" .. delim .. "]+");
    local t = {};
    local indices = {};
    
    for i in iterator do
        t[#t + 1] = i;  --preserve order
        indices[i] = #t;
    end
    
    return t, indices;
end

function payo.hijackPath()
    local DELIM = ":";
    local PREF = "/var/lib/payo-user-bash/bin";
    
    local pathText = os.getenv("PATH");
    if (not pathText) then
        io.stderr:write("unexpected failure. PATH has not been set\n");
        return 1;
    end

    local paths, indices = split(pathText, DELIM);

    -- now let's rebuild the path as we want it
    local path = PREF;
    table.remove(paths, indices[PREF]);
    indices[PREF] = nil;

    for i,p in ipairs(paths) do
        path = path .. DELIM .. p;
    end
    
    os.setenv("PATH", path);
end

local CONFIG = "/etc/payo-user-bash.cfg";

local function saveConfig(cfg)
    local root = fs.get("/");
    if (root and not root.isReadOnly()) then
        fs.makeDirectory("/etc");
        local cfgHandle, reason = io.open(CONFIG, "w");
        if (cfgHandle) then
            cfgHandle:write(ser.serialize(cfg)..'\n');
            cfgHandle:close()
        else
            return reason;
        end
    else
        return "could not save config because filesystem is read only";
    end

    return nil; -- no error
end

local function loadConfig()
    local cfg = {};
    local result, reason = loadfile(CONFIG, "t", cfg);
    if (result) then
        result, reason = xpcall(result, debug.traceback);
        if (not result) then
            return nil, "failed to load symlink configuration";
        end
    end

    if (not cfg or not cfg.path or not cfg.overrides) then
        cfg = cfg or {};
        cfg.path = cfg.path or "";
        cfg.overrides = cfg.overrides or {};
        saveConfig(cfg);
    end

    return cfg;
end

function payo.hijackPackages()
    local cfg = loadConfig();
    local DELIM = ";";
    
    if (not cfg or not cfg.path) then
        return "failed to load config";
    end
    
    local pathTable, indexList = split(package.path, DELIM);

    if (indexList[cfg.path]) then -- our path is defined
        if (indexList[cfg.path] ~= 1) then -- but we're not first
            table.remove(paths, indices[PREF]);
            indices[PREF] = nil; -- remove us from the list now
        end
    end

    local fixed = cfg.path;
    for i,p in ipairs(pathTable) do
        fixed = fixed .. DELIM .. p;
    end
    
    package.path = fixed;
    
    -- now unload any packages specified in overrides
    for k,p in pairs(cfg.overrides) do
        local p_ex = require(p .. "-ex");
        package.loaded[p] = p_ex;
    end
end

return payo;
