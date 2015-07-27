local config = require("payo-lib/config");

local lib = {};

lib.descriptions = {};
lib.descriptions.load = "Loads a file into memory are a value, similar to unserialize and config.load. popm can load local files as well as remote files. Remote files prefixed with http and https are fetch using wget";
lib.descriptions.isUrl = "Returns true if path is url prefixed with http or https";

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

function lib.load(url)
  if (type(url) ~= type("")) then
    return nil, "expecting url as string"
  end

  -- component.isAvailable('internet')
  local internet = require("internet");
  local wget = loadfile("/bin/wget.lua");

  -- wget can download to a file
  -- internet can download in memory using internet.request(url), returns an iteration function of strings

  -- -f force (overwrite local file)
  -- -q quiet
  -- -Q quiet quiet (no stderr)

  local tmp = "/tmp/popm-buffer"
  wget("", url, tmp)

  return config.load(tmp);
end

return lib;
