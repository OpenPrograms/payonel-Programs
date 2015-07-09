
local util = {};

function util.split(txt, delim, dropEmpty)
    
    local parts = {}
    
    -- special case, no delim just return single part of whole string
    txt = txt or "";
    delim = delim or "";
    local dlen = delim:len();
    if (dlen == 0) then
        parts[1] = txt;
        return parts
    end
    
    local last = 1;

    while (true) do
        
        local next = txt:find(delim, last)

        -- if next == last, then this part is empty
        
        local part = "";
        if (not next) then
            part = txt:sub(last, txt:len())
        elseif (next > last) then
            part = txt:sub(last, next - dlen)
        end
        
        part = part or "";

        if (part:len() > 0 or not dropEmpty) then
            parts[#parts + 1] = part;
        end
        
        if (not next) then -- done
            break
        end

        last = next + dlen;
    end
    
    return parts;
    
end


return util;
