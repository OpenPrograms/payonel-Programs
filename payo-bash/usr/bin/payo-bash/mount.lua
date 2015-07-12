local fs = require("filesystem")
local argutil = require("payo-lib/argutil")
local ser = require("serialization")

local args = argutil.parse(table.pack(...), {{},{}});
    
if (#args == 0) then 
    
  -- for each mount
  local mounts = {};
    
  for proxy,path in fs.mounts() do
    local device = {};

    device.dev_path = proxy.address;
    device.mount_path = path;
    device.rw_ro = proxy.isReadOnly() and "ro" or "rw";
    device.fs_label = proxy.getLabel() or proxy.address;

    mounts[device.dev_path] = mounts[device.dev_path] or {};
    local dev_mounts = mounts[device.dev_path];
    dev_mounts[#dev_mounts + 1] = device;
  end
    
  table.sort(mounts);
    
  for dev_path, dev_mounts in pairs(mounts) do
        
    for index=1,#dev_mounts do
      local device = dev_mounts[index];
            
      local rw_ro = "(" .. device.rw_ro .. ")";
      local fs_label = "\"" .. device.fs_label .. "\"";
            
      io.write(string.format("%s on %-10s %s %s\n",
        dev_path,
        device.mount_path,
        rw_ro,
        fs_label));
    end
  end

else -- have old mount do the job
  return loadfile("/bin/mount.lua")(...);
end

