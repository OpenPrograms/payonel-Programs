local config = require("payo-lib/config");
local fs = require("filesystem");
local component = require("component");
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");

if (not component.isAvailable("internet")) then
  io.stderr:write("popm library requires an internet component\n");
  return nil;
end

local internet = require("internet");

-- component.isAvailable('internet')
--local internet = require("internet");
local wget = loadfile("/bin/wget.lua");

if (not wget) then
  io.stderr:write("popm requires wget\n");
  return nil;
end

if (not mktmp) then
  io.stderr:write("popm library requires mktmp which could not be found\n");
  return nil;
end

local lib = {};

lib.descriptions = {};
lib.descriptions.load = "(path) => table: Loads a file into memory are a value, similar to unserialize and config.load. popm can load local files as well as remote files. Remote files prefixed with http and https are fetch using wget";
lib.descriptions.isUrl = "(url) => boolean: Returns true if path is url prefixed with http or https";
lib.descriptions.save = "(url, destination, bForce) Downloads a file and saves to disk. Returns nil, reason on error";
lib.descriptions.download = "(url) Downloads a file in memory and returns the file contents as a string. Returns nil, reason on error";

function lib.isUrl(path)
  if (type(path) ~= type("")) then
    return false;
  end

  if (path:len() == 0) then
    return false;
  end

  if (path:find("^https?://[^/]") ~= 1) then
    return false;
  end
  
  return true;
end

function lib.download(url)

  local content = "";
  local result, response = internet.request(url);
  if (not result) then
    return nil, "could not establish http request with: " .. tostring(url);
  end

  if (not response) then
    return nil, "result not false but response is from url: " .. tostring(url);
  end

  for chunk in response do
    content = content .. chunk;
  end

  return content;
end

function lib.save(url, destination, bForce)
  if (not lib.isUrl(url)) then
    return nil, "not a valid url";
  end

  if (destination ~= nil) then
    if (type(destination) == type("")) then
      if (fs.exists(destination) and not bForce) then
        return nil, string.format("path exists and save not forced: %s", destination);
      end
    else
      return nil, "destination must be a save path or nil";
    end
  else
    local reason;
    destination, reason = mktmp();
    if (not destination) then
      return nil, "popm failed to create a tmp file for download: " .. tostring(reason);
    end
  end

  -- wget can download to a file
  -- internet can download in memory using internet.request(url), returns an iteration function of strings

  -- -f force (overwrite local file)
  -- -q quiet
  -- -Q quiet quiet (no stderr)

  -- we always force because we've already checked if the file exists, and mktmp may have made it for us
  -- we always go quiet because we return the error message, the caller should check the return for info
  local options = "-fQ";

  local result, reason = wget(url, destination, options)
  if (not result) then
    return nil, reason;
  end

  return destination;
end

function lib.load(url, bInMemory)
  if (type(url) ~= type("")) then
    return nil, "expecting url as string"
  end

  local bTempFile = false;

  if (lib.isUrl(url)) then
    if (bInMemory) then
      url = lib.download(url);
    else
      url, reason = lib.save(url);
      if (not url) then
        return nil, reason
      end
      bTempFile = true;
    end
  elseif (not fs.exists(url)) then  
    return nil, "path given for load does not exist";
  end

  local loaded = nil;
  
  if (bInMemory) then
    local loader = load("local ___t=" .. url .. " return ___t");
    if (loader == nil) then
      return nil, "invalid data. cannot load";
    end
    loaded = loader();
  else
    local reason;
    loaded, reason = config.load(url);
    if (bTempFile) then
      fs.remove(url);
    end
    if (not loaded) then
      return nil, reason;
    end
  end

  return loaded;
end

return lib;
