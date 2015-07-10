local computer = require("computer");

-- overwrite some methods

function ex_setWorkingDirectory(original, newPath)
    
    local oldPath = os.getenv("PWD")
    
    local ok, reason = original(newPath);
    
    if (ok and oldPath) then
        computer.pushSignal("pwd_changed", oldPath, newPath)
    end

    return ok, reason;
end

local hijack = require("hijack")
return hijack.load("shell", "setWorkingDirectory", ex_setWorkingDirectory);
