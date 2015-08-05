local config = require("payo-lib/config");
local fs = require("filesystem");
local component = require("component");
local mktmp = loadfile("/usr/bin/payo-bash/mktmp.lua");
local sutil = require("payo-lib/stringutil");
local tutil = require("payo-lib/tableutil");

local function ne() return nil, "not implemented"; end

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
lib.descriptions.dropCache = "() Discards any previous cached meta data about repos and program configurations. Does not discard meta data of currently installed packages.";
lib.descriptions.updateCache = "(content_path, repo_url, programs_cfg_path) Cache repos and program defintions locally for subsequent updates. Any entries cached overwrite previous entries. " ..
                        "Defaults for parameters are, " ..
                        "content_path: \"https://raw.githubusercontent.com/\", " ..
                        "repo_url: content_path .. \"OpenPrograms/openprograms.github.io/master/repos.cfg\", " ..
                        "programs_cfg_path: \"/master/programs.cfg\"";
lib.descriptions.sync = "(sync_rules) Executes dropCache followed by cache for each sync rule defined in the popm configuration file. " .. 
                        "Optionally, the sync rules can be passed as a table in which case the configuration file is not used. An empty ruleset drops the cache only.";

--[[

database layout
{
  world = 
  {
    [package_name] =
    {
      author = [author]
      definition = [programs.cfg path]
      dep = [boolean: true, user installed; false, dep installed]
      files =
      {
        [src_file_path] =
        {
          sha = [sha: version installed, nil - missing],
          sha_available = [sha: version available, nil - marked for removal],
          path = [path to installed file]
        },
      },
    },
  },
  cache =
  {
    packages =
    {
      [package_name] =
      {
        repo_key = [repo_key],
        parent_repo = [parent_repo url],
        deps = [array of pkg deps],
        files =
        {
          [src_file_path] = 
          {
            sha = [sha: version available]
            path = [path to install file]
          },
        },
      },
    },
  },
}

]]--

function lib.world()
  local db = lib.database();
  if (not db) then
    return nil, "could not load database";
  end

  local w = db.world;
  return w, "could not find world object in database";
end

function lib.package(pkg)
  local w, reason = lib.world();
  if (not w) then
    return nil, reaosn
  end

  local pkg, reason = w[pkg];
  return pkg, tostring(pkg) .. " not defined in database";
end

function lib.cache()
  local db, reason = lib.database();
  if (not db) then
    return nil, reason
  end
  return db.cache, "no cache loaded";
end

function lib.cachedPackage(pkg)
  local c, reason = lib.cache();
  if (not c) then
    return c, reason;
  end
  if (not c.packages) then
    return nil, "no packages have been cached";
  end
  return c.packages[pkg], "package was not defined in cache";
end

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

local function default_configuration()
  return
  {
    databasePath = "/etc/popm/popm.svd",
    sync_rules =
    {
      -- define as array, order matters as later rules overwrite previous
      {
        host_root_path = "https://raw.githubusercontent.com/",
        repos_cfg_url = "OpenPrograms/openprograms.github.io/master/repos.cfg",
        programs_configuration_lookup = "%s/master/programs.cfg",
      },
    },
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
    pkg_data.files = files;

    for src,file in pairs(file_table) do
      local file_def = {};
      file_def.path = file;
      file_def.sha = nil; -- unknown version
      file_def.sha_available = nil; -- normally would mean file is marked for removal
      files[src] = file_def;
    end
  end

  -- update database
  return lib.saveDatabase(db);
end

function lib.dropCache()
  local db, reason = lib.database();
  if (not db) then return nil, reason end;
  db.cache = nil;

  return lib.saveDatabase(db);
end

function lib.saveDatabase(db)
  return config.save(db, lib.databasePath());
end

function lib.updateCache(sync_rule)
  -- clean up parameters a little
  if (type(sync_rule) ~= type({})) then
    return nil, "sync rules must be a table";
  end

  if (type(sync_rule.host_root_path) ~= type("")) then
    return nil, "sync rule missing host_root_path";
  end

  if (type(sync_rule.repos_cfg_url) ~= type("")) then
    return nil, "sync rule missing repos_cfg_url";
  end

  if (type(sync_rule.programs_configuration_lookup) ~= type("")) then
    return nil, "sync rule missing programs_configuration_lookup";
  end

  local inMemory = true;
  local repos, reason = lib.load(sync_rule.host_root_path .. sync_rule.repos_cfg_url, inMemory);
  if (not repos) then
    return nil, string.format("failed to synchronize with repo definition: %s", reason);
  end

  local db = lib.database();
  if (not db.cache) then
    db.cache = {}
    db.cache.packages = {}
  end

  local cache = db.cache;

  -- for each pkg in the world
  for author, entry in pairs(repos) do
    local repo = entry.repo;
    if (repo) then
      local programs_url = string.format(sync_rule.programs_configuration_lookup, repo);
      local programs, reason = lib.load(programs_url, inMemory);

      -- ignore repos without a programs.cfg
      if (programs) then
        for pkg_name, rules in pairs(programs) do
          -- if we have this pkg installed, update the meta data (sha_available)
          local dbpkg = db.world[pkg_name];
          if (dbpkg) then
            print("we know about: " .. pkg_name);

            local pkg = tutil.deepCopy(rules);

            pkg.repo_key = author;
            pkg.parent_repo = repo;

            -- change structure of files            
            pkg.files = {};

            -- expand files to include sha meta
            for s,d in pairs(rules.files) do
              local fdef = {}
              
              fdef.path = d;
              fdef.sha = nil; -- use github api? what about local in memory rules?

              pkg.files[s] = fdef;
            end

            cache.packages[pkg_name] = pkg;
          end
        end
      end
    end
    -- for each package provided by repo
  end

  return lib.saveDatabase(db);
end

function lib.sync(sync_rules)
  lib.dropCache();

  -- for each sync rule
  -- if sync is nil, use configuration rules
  if (not sync_rules) then
    local config = lib.config();
    if (not config) then
      return nil, "failed to load config and thus cannot populate default sync rules";
    end
    sync_rules = config.sync_rules;
    if (not sync_rules) then
      return nil, "popm config missing sync rules and cannot run sync"
    end
  end

  for i,sync_rule in ipairs(sync_rules) do
    local ok, reason = lib.updateCache(sync_rule);
    if (not ok) then
      return nil, reason
    end
  end

  return true;
end

function lib.deptree()
  return ne();
end

function lib.download(url)
  local content_chain = {};
  local request_error = nil;

  -- the code here is taken from wget from OC
  local result, response = pcall(internet.request, url);
  if (result) then
    local result, reason = pcall(function()
      while (true) do
        local response_result, chunk = pcall(response);
        if (not response_result) then
          if (#content_chain == 0) then
            request_error = chunk;
          end
          break;
        end
        content_chain[#content_chain + 1] = chunk;
      end
    end);
    if (not result) then
      return nil, reason;
    end
  else
    return nil, response;
  end

  -- the request will fail on the FIRST chunk if the request was bad
  if (request_error) then
    return nil, request_error;
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

  -- bInMemory means to never store the result in a file, load directly to table

  local bTempFileCreated = false;
  local reason = nil;
  local data = nil;

  if (lib.isUrl(url)) then
    if (bInMemory) then
      data, reason = lib.download(url);
    else
      url, reason = lib.save(url);
      bTempFileCreated = true;
    end
    if (not url) then
      return nil, reason;
    end
  elseif (not fs.exists(url)) then  
    return nil, "path given for load does not exist";
  end

  local loaded = nil;
  
  if (data) then
    local loader = load("local ___t=" .. data .. " return ___t");
    if (loader == nil) then
      return nil, "invalid data. cannot load: " .. tostring(url);
    end
    loaded = loader();
  else -- data in file
    local reason;
    loaded, reason = config.load(url);
    if (bTempFileCreated) then
      fs.remove(url);
    end
    if (not loaded) then
      return nil, reason;
    end
  end

  return loaded;
end

return lib;
