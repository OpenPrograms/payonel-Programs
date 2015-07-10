function ex_link(original, target, linkpath, bSilent)
    
  local ok, reason = original(target, linkpath);
  if (not ok) then
      return reason;
  end
  
  if (not bSilent) then
    --print("local psym = require('persisted_symlinks');");
    --print("psym.storeLink(target, linkpath);");
  end

  return ok, reason;
end

function ex_remove(original, path)
    
    local ok, reason = original(path);
    if (not ok) then
        return reason;
    end
    
    if (bLink) then
        --print("local psym = require('persisted_symlinks');");
        --print("psym.removeLink(path);");
    end
    
    return ok, reason;
end

local hijack = require("hijack")
hijack.load("filesystem", "link", ex_link);
return hijack.load("filesystem", "remove", ex_remove);
