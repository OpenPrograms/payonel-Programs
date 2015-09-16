local lib = {}

function lib.escapeMagic(text)
  return text:gsub('[%(%)%.%%%+%-%*%?%[%^%$]', '%%%1')
end

function lib.getMatchingPrograms(baseName)
  local result = {}
  -- TODO only matching files with .lua extension for now, might want to
  --      extend this to other extensions at some point? env var? file attrs?
  if not baseName or #baseName == 0 then
    baseName = "^(.*)%.lua$"
  else
    baseName = "^(" .. escapeMagic(baseName) .. ".*)%.lua$"
  end
  for basePath in string.gmatch(os.getenv("PATH"), "[^:]+") do
    for file in fs.list(basePath) do
      local match = file:match(baseName)
      if match then
        table.insert(result, match)
      end
    end
  end
  return result
end

function lib.getMatchingFiles(partialPrefix, name)
  local baseName = shell.resolve(partialPrefix .. name)
  local result, basePath = {}
  -- note: we strip the trailing / to make it easier to navigate through
  -- directories using tab completion (since entering the / will then serve
  -- as the intention to go into the currently hinted one).
  -- if we have a directory but no trailing slash there may be alternatives
  -- on the same level, so don't look inside that directory... (cont.)
  if fs.isDirectory(baseName) and baseName:sub(-1) == "/" then
    basePath = baseName
    baseName = "^(.-)/?$"
  else
    basePath = fs.path(baseName) or "/"
    baseName = "^(" .. escapeMagic(fs.name(baseName)) .. ".-)/?$"
  end
  for file in fs.list(basePath) do
    local match = file:match(baseName)
    if match then
      table.insert(result, partialPrefix ..  match)
    end
  end
  -- (cont.) but if there's only one match and it's a directory, *then* we
  -- do want to add the trailing slash here.
  if #result == 1 and fs.isDirectory(result[1]) then
    result[1] = result[1] .. "/"
  end
  return result
end

function lib.hintHandler(line, cursor)
  local line = unicode.sub(line, 1, cursor - 1)
  if not line or #line < 1 then
    return nil
  end
  local result
  local prefix, partial = string.match(line, "^(.+%s)(.+)$")
  local searchInPath = not prefix and not line:find("/")
  if searchInPath then
    -- first part and no path, look for programs in the $PATH
    result = getMatchingPrograms(line)
  else -- just look normal files
    local partialPrefix = (partial or line)
    local name = fs.name(partialPrefix)
    partialPrefix = partialPrefix:sub(1, -name:len() - 1)
    result = getMatchingFiles(partialPrefix, name)
  end
  local resultSuffix = ""
  if searchInPath then
    resultSuffix  = " "
  elseif #result == 1 and result[1]:sub(-1) ~= '/' then
    resultSuffix = " "
  end
  prefix = prefix or ""
  for i = 1, #result do
    result[i] = prefix .. result[i] .. resultSuffix
  end
  table.sort(result)
  return result
end

return lib