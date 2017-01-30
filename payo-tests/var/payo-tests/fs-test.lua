local testutil = require("testutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = require("shell")

local home = shell.getWorkingDirectory()
local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end
local chdir = shell.setWorkingDirectory

local rootfs
local mounts = {}
for proxy,path in fs.mounts() do
  mounts[proxy] = mounts[proxy] or {}
  table.insert(mounts[proxy], path)

  if path == "/" then
    rootfs = proxy
  end
end

testutil.assert("rootfs missing", true, fs.get("/") == rootfs)

for proxy,paths in pairs(mounts) do
  for _,path in ipairs(paths) do
    local given_fs, given_path = fs.get(path)
    testutil.assert("get wrong fs proxy", true, proxy == given_fs, given_fs.address)
    testutil.assert("get wrong fs path", path, given_path, path)

    local test_path = path .. "/afs/dfas/dfasdfasdf/asdf"
    local given_fs, given_path = fs.get(test_path)
    testutil.assert("get wrong fs proxy in test path", true, proxy == given_fs, given_fs.address)
    testutil.assert("get wrong fs path in test path", path, given_path, test_path)

    local test_path = path .. "/../../../../../"
    local given_fs, given_path = fs.get(test_path)
    testutil.assert("get wrong fs proxy in upped path", true, rootfs == given_fs, given_fs.address)
    testutil.assert("get wrong fs path in upped path", "/", given_path, test_path)
  end
end

-- real path

local function real(path, exp, cmds)
  local tmp_dir_path
  if cmds then
    tmp_dir_path = mktmp('-d','-q')
    chdir(tmp_dir_path)
    if exp then -- could be nil
      exp = tmp_dir_path .. "/" .. exp
    end
    path = tmp_dir_path .. "/" .. path

    for _,cmd in ipairs(cmds) do
      os.execute(cmd)
    end

    chdir(home)
  end

  local result, err = fs.realPath(path)
  testutil.assert("realPath("..tostring(path)..")", exp, result, tostring(err))

  if tmp_dir_path then
    fs.remove(tmp_dir_path)
  end
end

real("asdf", "/asdf")
real("/bin/cfgemu.lua", "/mnt/d76/bin/cfgemu.lua")
local eeprom = require("component").eeprom
local eeaddr = eeprom.address
real("/dev/eeprom", 
  "/dev/components/by-address/"..eeaddr.."/contents")
real("/init.lua", "/init.lua")
local rootaddr = rootfs.address:sub(1, 3)
local mount_path = "/mnt/" .. rootaddr
real(mount_path .. "/init.lua", mount_path .. "/init.lua")

-- link
real("a","b",{"touch b", "ln b a"})
real("pf","d/f",{"mkdir d", "touch d/f", "ln d pd", "ln pd/f pf"})
-- link to link
real("a","c",{"touch c", "ln c b", "ln b a"})
-- cycle
real("a",nil,{"touch c", "ln c b", "ln b a", "rm b", "ln a b"})

