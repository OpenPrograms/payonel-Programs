local util = {};

function util.split(txt, delim, keepDelim, keepEmpty)
  txt = txt or "";
  delim = delim or "";

  if (type(txt) ~= type("") or 
    type(delim) ~= type("") or
    type(keepDelim) ~= type(true) or
    type(keepEmpty) ~= type(true)) then
    return nil, nil, "invalid args"
  end

  local parts = {}
  local indices = {}
    
  -- special case, no delim just return single part of whole string
  local dlen = delim:len();
  if (dlen == 0) then
    parts[1] = txt;
    indices[txt] = 1;
    return parts, indices
  end
    
  local last = 1;

  while (last <= txt:len()) do
        
    local next_start, next_end = txt:find(delim, last)

    -- if next == last, then this part is empty
        
    local part = "";
    if (not next_start) then
      part = txt:sub(last, txt:len())
    else
      if (keepDelim) then
        part = txt:sub(last, next_end)
      else
        part = text:sub(last, next_start - 1);
      end
    end
        
    part = part or "";

    if (part:len() > 0 or keepEmpty) then
      parts[#parts + 1] = part;
      indices[part] = #parts;
    end
        
    if (not next) then -- done
      break
    end

    last = next_end + 1;
  end
    
  return parts, indices
    
end

function util.getParentDirectory(filePath)

  local pwd = os.getenv("PWD")

  if (not filePath) then
    return pwd
  end

  local si, ei = filePath:find("/[^/]+$")
  if (not si) then
    return pwd
  end

  return filePath:sub(1, si - 1)
end

function util.removeTrailingSlash(dirName)
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

function util.addTrailingSlash(dirName)
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

return util;
