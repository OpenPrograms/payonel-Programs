local config = require("payo-lib/config");
local fs = require("filesystem");
local component = require("component");
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
local sutil = require("payo-lib/stringutil");

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
lib.descriptions.database = "(bIncludeDeps) Returns list of installed packages";
lib.descriptions.createTasks = "(bUpdate, {pkgs}) Returns list of tasks needed to update or install a list of packages";
lib.descriptions.databasePath = "() Returns path to popm databsae";
lib.descriptions.configPath = "() Returns path to popm configuration";
lib.descriptions.config = "() Return popm config";
lib.descriptions.sync = "(repo_url) Syncronize world database with package definitions";

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

function lib.config()
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
      return nil, string.format("failed to load popm config, needing to save updated config: %s", reason);
    end
  end

  return cfg;
end

function lib.databasePath()
  local cfg, reason = lib.config();
  if (not cfg) then
    return nil, string.format("failed to aquire database path: %s", reason);
  end
  return cfg.databasePath;
end

function lib.createTasks(bUpdate, pkgs)
  return ne();
end

function lib.database()
  local dbPath = lib.databasePath();
  return config.load(dbPath);
end

function lib.migrate()
  local db, reason = lib.database();
  if (db) then
    return true; -- already migrated
  end

  -- create world data from existing installed pkgs
  -- assume all files from opdata.svd are target packages, unfortunately

  local oppm_cfg = config.load("/etc/opdata.svd");
  if (not oppm_cfg) then
    return nil, "oppm database not found";
  end

  db = {};
  db.world = {};

  for pkg,file_table in pairs(oppm_cfg) do
    local pkg_data = {};
    db.world[pkg] = pkg_data
    pkg_data.dep = false; -- meaning, it was a target pkg

    local files = {};
    pkg_data.installed_files = files;

    for _,file in pairs(file_table) do
      files[#files + 1] = file;
    end
  end

  -- update database
  return config.save(db, lib.databasePath());
end

function lib.sync(repo_base, repo_url)
  repo_base = repo_base or "https://raw.githubusercontent.com/OpenPrograms/";
  repo_base = sutil.addTrailingSlash(repo_base);

  repo_url = repo_url or (repo_base .. "openprograms.github.io/master/repos.cfg");

  local repos, reason = lib.load(repo_base .. repo_url);
  if (not repos) then
    return nil, string.format("failed to synchronize with repo definition: %s", reason);
  end

  local db = lib.database();

  -- for each pkg in the world
  -- update the sync rules

  for author, entry in pairs(repos) do
    local repo = entry.repo;
    if (repo) then
      local programs_url = repo_base .. repo;
      local programs, reason = lib.load(programs_url);

      if (not programs) then
        io.stderr:write(string.format("failed to load programs data about: %s. reason: %s\n", 
          tostring(programs), 
          tostring(reason)));
      else
        for pkg_name, rules in pairs(programs) do
          print(pkg_name);
        end
      end
    end

    -- for each package provided by repo

  end

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
