local util = {};

function util.split(txt, delim, keepDelim, keepEmpty)
  delim = delim or "";
  keepDelim = keepDelim or false;
  keepEmpty = keepEmpty or false;

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

  while (true) do
    local next_start, next_end = txt:find(delim, last)

    -- if next == last, then this part is empty
        
    local part = "";
    if (not next_start) then
      part = txt:sub(last, txt:len())
    else
      if (keepDelim) then
        part = txt:sub(last, next_end)
      else
        part = txt:sub(last, next_start - 1);
      end
    end
        
    part = part or "";

    if (part:len() > 0 or keepEmpty) then
      parts[#parts + 1] = part;
      indices[part] = #parts;
    end
        
    if (not next_start) then -- done
      break
    end

    last = next_end + 1;
  end
    
  return parts, indices
    
end

function util.getParentDirectory(filePath)
  if (not filePath) then
    return nil, "expected string"
  end

  -- a/ => a
  -- /// => 
  filePath = util.removeTrailingSlash(filePath);
  if (filePath:len() == 0) then
    return nil, "root directory has no parent"
  end

  local si, ei = filePath:find("/[^/]*$")

  if (not si) then
    return nil, "not enough path given to determine parent"
  end

  return filePath:sub(1, si)
end

function util.removeTrailingSlash(dirName)
  if (not type(dirName) == "string") then
    return "";
  elseif (#dirName == 0) then
    return "";
  end
    
  local fixedPath = dirName:gsub("/+$", "")
  return fixedPath;
end

function util.addTrailingSlash(dirName)
  if (not type(dirName) == "string") then
    return "";
  end
  
  dirName = util.removeTrailingSlash(dirName);
  local lastChar = dirName:sub(#dirName, #dirName);

  local fixedPath = dirName;
  if (lastChar ~= "/") then
    fixedPath = fixedPath .. "/";
  end
    
  return fixedPath;
end

function util.getFileName(path)
  if (type(path) ~= "string") then
    return nil, "path must be a string"
  end

  if (path:len() == 0) then
    return nil, "path must not be empty"
  end

  local indexOfLastForwardSlash = path:find("/[^/]*$")
  if (indexOfLastForwardSlash == nil) then -- no slash, full string is filenaem
    return path
  end

  -- remove up to last /
  path = path:sub(indexOfLastForwardSlash + 1)

  -- if path is now empty, then there is no file name
  if (path:len() == 0) then
    return nil, "path was a directory"
  end

  return path
end

return util;
