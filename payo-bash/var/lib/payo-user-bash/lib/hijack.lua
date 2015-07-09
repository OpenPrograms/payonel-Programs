local hijack = {}

function hijack.load(libName, methodName, override)
   
   if (not hijack) then
       return nil, "no hijack"
   end
   
    if (not hijack[libName]) then
        local lib, reason = require(libName);
        if (not lib) then
            return nil, reason
        end
    
        hijack[libName] = {}
        hijack[libName].lib = lib
        hijack[libName].originals = {};
    end

    -- safeguard original if not yet set
    if (not hijack[libName].originals[methodName]) then
        -- if the lib doesn't know about this method, error out now
        if (not hijack[libName].lib[methodName] or type(hijack[libName].lib[methodName]) ~= "function") then
            return nil, libName .. "." .. methodName .. " does not exist or is not a function";
        end
           
        hijack[libName].originals[methodName] = hijack[libName].lib[methodName];
    end
   
    local original = hijack[libName].originals[methodName];
    local redirect = function(...)
        return override(original, ...)
    end
   
    hijack[libName].lib[methodName] = redirect;
    return hijack[libName].lib;
end

function hijack.unload(libName, methodName)
    
    if (not hijack or not hijack[libName] or not hijack[libName].lib or not hijack[libName].originals[methodName]) then
        return false, libName .. "." .. methodName .. " was not hijacked"
    end
    
    hijack[libName].lib[methodName] = hijack[libName].originals[methodName];
    hijack[libName].originals[methodName] = nil; -- allow for override again
end

return hijack
