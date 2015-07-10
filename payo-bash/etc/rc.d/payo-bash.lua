
function start(msg)
    local payo = require("payo-user-bash");
    
    if (payo) then
        payo.hijackPath();
        payo.hijackPackages();
        return true;
    end
    
    return false;
end
