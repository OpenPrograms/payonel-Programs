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
lib.descriptions.load = "(path) Loads a file or remote url into memory";
lib.descriptions.isUrl = "(url) Returns true if path is url prefixed with http or https";
lib.descriptions.save = "(url, destination, bForce) Downloads a file and saves to disk";
lib.descriptions.download = "(url) Downloads a file in memory and returns the file contents as a string";
lib.descriptions.migrate = "() Reads existing oppm database and creates initial popm database";
lib.descriptions.deptree = "() Creates a linked list of dependencies of installed packages";
lib.descriptions.world = "(bIncludeDeps) Returns list of installed packages";
lib.descriptions.createTasks = "(bUpdate, {pkgs}) Returns list of tasks needed to update or install a list of packages";
lib.descriptions.databasePath = "() Returns path to popm databsae";
lib.descriptions.configPath = "() Returns path to popm configuration";

function lib.isUrl(path)
  if (type(path) ~= type("")) then
    return nil, "path must be a string"
  end

  if (path:len() == 0) then
    return false;
  end

  if (path:find("^https?://[^/]") ~= 1) then
    return false;
  end
  
  return true;
end

local function ne() return nil, "not implemented"; end

local function default_configuration()
  return
  {
    databasePath = "/etc/popm/popm.svd",
  }
end

function lib.configPath()
  return "/etc/popm/popm.cfg";
end

function lib.databasePath()
  local cfg_path = lib.configPath();
  local cfg = config.load(cfg_path) or {};
  local updated = false;
  local defaults = default_configuration();
  for k,v in pairs(defaults) do
    if (cfg[k] == nil) then
      cfg[k] = v;
      updated = true;
    end
  end

  if (updated) then
    local ok, reason = config.save(cfg, cfg_path);
    if (not ok) then
      return nil, string.format("failed to load popm databsae, needing to save updated config: %s", reason);
    end
  end

  return cfg.databasePath;
end

function lib.createTasks(bUpdate, pkgs)
  return ne();
end

function lib.world(bIncludeDeps)
  return ne();
end

function lib.migrate()
  return ne();
end

function lib.deptree()
  return ne();
end

function lib.download(url)
  local content_chain = {};

  -- the code here is taken from wget from OC
  local result, response = pcall(internet.request, url);
  if (result) then
    local result, reason = pcall(function()
      for chunk in response do
        content_chain[#content_chain + 1] = chunk;
      end
    end);
    if (not result) then
      return nil, reason;
    end
  else
    return nil, response;
  end

  return table.concat(content_chain);
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
  local reason = nil;

  if (lib.isUrl(url)) then
    if (bInMemory) then
      url, reason = lib.download(url);
    else
      url, reason = lib.save(url);
      bTempFile = true;
    end
    if (not url) then
      return nil, reason;
    end
  elseif (not fs.exists(url)) then  
    return nil, "path given for load does not exist";
  end

  local loaded = nil;
  
  if (bInMemory) then
    local loader = load("local ___t=" .. url .. " return ___t");
    if (loader == nil) then
      return nil, "invalid data. cannot load: " .. tostring(url);
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
