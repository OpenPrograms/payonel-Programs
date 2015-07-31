local fs = require("filesystem");
local des = require("serialization").unserialize
local ser = require("serialization").serialize
local sutil = require("payo-lib/stringutil");
local config = {};

function config.load(configPath)
  if (type(configPath) ~= type("")) then
    return nil, "file path must be a string";
  end

  if (not fs.exists(configPath)) then
    return nil, string.format("cannot open [%s]. Path does not exist", configPath);
  end

  local handle, reason = io.open(configPath, "rb");
  if (not handle) then
    return nil, reason
  end

  local all = handle:read("*a");
  handle:close();

  return des(all);
end

function config.save(config, configPath)
  if (type(configPath) ~= type("")) then
    return nil, "file path must be a string";
  end

  if (type(config) ~= type({})) then
    return nil, "can only save tables"
  end

  local s, reason = ser(config);
  if (not s) then
    return nil, "Will not be able to save: " .. tostring(reason);
  end

  local pwd = sutil.getParentDirectory(configPath);
  if (not fs.exists(pwd)) then
    local mkdir = loadfile("/bin/mkdir.lua");
    mkdir(pwd);
  end

  local handle, reason = io.open(configPath, "wb");
  if (not handle) then
    return nil, reason
  end

  handle:write(s);
  handle:close();

  return true
end

return config;
