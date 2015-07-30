local config = require("payo-lib/config");
local fs = require("filesystem");
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");

if (not mktmp) then
  io.stderr:write("popm library requires mktmp which could not be found\n");
  return nil;
end

local lib = {};

lib.descriptions = {};
lib.descriptions.load = "(path:string) => table: Loads a file into memory are a value, similar to unserialize and config.load. popm can load local files as well as remote files. Remote files prefixed with http and https are fetch using wget";
lib.descriptions.isUrl = "(url:string) => boolean: Returns true if path is url prefixed with http or https";
lib.descriptions.download = "(url:path[, destination:string]) Downloads a file via wget and saves it at destination if provided, or a temporary file. Returns the path of the saved file or nil with reason";

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

function lib.download(url, destination, bForce)
  if (not lib.isUrl(url)) then
    return nil, "not a valid url";
  end

  if (destination ~= nil and type(destination) ~= type("")) then
    return nil, "destination must be a save path or nil";
  end

  destination = destination or mktmp();
  if (not destination) then
    return nil, "popm failed to create a tmp file for download";
  end

  -- component.isAvailable('internet')
  --local internet = require("internet");
  local wget = loadfile("/bin/wget.lua");

  if (not wget) then
    return nil, "popm download could not load wget";
  end

  -- wget can download to a file
  -- internet can download in memory using internet.request(url), returns an iteration function of strings

  -- -f force (overwrite local file)
  -- -q quiet
  -- -Q quiet quiet (no stderr)
  if (fs.exists(destination) and not bForce) then
    return nil, string.format("path exists and download not forced: %s", destination);
  end

  local options = "";
  if (bForce) then
    options = "-f";
  end

  wget(url, destination, options)
  return destination;
end

function lib.load(url)
  if (type(url) ~= type("")) then
    return nil, "expecting url as string"
  end

  if (lib.isUrl(url)) then
    url, reason = lib.download(url);
    if (not url) then
      return nil, reason
    end
  end

  if (not fs.exists(url)) then  
    return nil, "path given for load does not exist";
  end

  return config.load(url);
end

return lib;
