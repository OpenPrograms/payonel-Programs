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

local function pathname(uri, path, name)
  local gpath = fs.path(uri)
  local gname = fs.name(uri)
  testutil.assert("path " .. uri, gpath, path)
  testutil.assert("name " .. uri, gname, name)
end

pathname("/", "/", nil)
pathname("", "/", nil)
pathname("asdf", "/", "asdf")
pathname("/asdf", "/", "asdf")
pathname("/as/df", "/as/", "df")
pathname("/as/.df", "/as/", ".df")
pathname("/as/.df/../foo", "/as/", "foo")
pathname("/as/.df/../../foo", "/", "foo")
pathname("/as/.df/../../foo/../bar", "/", "bar")
pathname("/as/.df/../../foo/bar", "/foo/", "bar")
pathname("/as/.df/../../foo/bar/baz", "/foo/bar/", "baz")
pathname("/asdf//../oath", "/", "oath")
-- path apparently is relative!
pathname("asdf/foo", "asdf/", "foo")
pathname("asdf//foo", "asdf/", "foo")
pathname("asdf/.../foo", "asdf/.../", "foo")
pathname("asdf//../.../foo", ".../", "foo")

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
-- cause dev to populate
fs.list("/dev/")()
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

-- exists
local function exists(path, setup, result, teardown)
  for _,cmd in ipairs(setup) do
    os.execute(cmd)
  end

  local stat = fs.stat(path)
  local exists = fs.exists(path)

  for _,cmd in ipairs(teardown or {}) do
    os.execute(cmd)
  end

  testutil.assert("exists check: " .. path, result, exists)
  --testutil.assert("exists check from stat: " .. path, stat.exists, exists)
end

exists("/init.lua", {}, true)
exists("/tmp", {}, true)
exists("/", {}, true)
exists("/bin/cfgemu.lua", {}, true)
exists("/tmp/a", {}, false)
exists("/a", {}, false)
exists("/tmp/a", {"touch /tmp/a"}, true, {"rm /tmp/a"})
exists("/tmp/j/init.lua", {"ln / /tmp/j"}, true, {"rm /tmp/j"})
exists("/tmp/j/init.lua", {"cd /tmp;ln ../ j"}, true, {"rm /tmp/j"})
exists("/tmp/q/init.lua", {"cd /tmp;ln ../ j;ln j q;"}, true, {"rm /tmp/j","rm /tmp/q"})
exists("/tmp/here/init.lua", {"mkdir /tmp/dir;cd /tmp/dir;ln ../ up;cd ../;cp -P dir/up here;"},
  true, {"rm -r /tmp/dir","rm /tmp/here"})
exists("/tmp/a", {"cd /tmp;touch a;ln a b;ln b c;rm b;ln c b"}, true, {"rm /tmp/a /tmp/b /tmp/c"})
exists("/tmp/b", {"cd /tmp;touch a;ln a b;ln b c;rm b;ln c b"}, true, {"rm /tmp/a /tmp/b /tmp/c"})
exists("/tmp/c", {"cd /tmp;touch a;ln a b;ln b c;rm b;ln c b"}, true, {"rm /tmp/a /tmp/b /tmp/c"})
exists("/tmp/c/no", {"cd /tmp;touch a;ln a b;ln b c;rm b;ln c b"}, false, {"rm /tmp/a /tmp/b /tmp/c"})
exists("/tmp/b/../a", {"cd /tmp;mkdir c;touch a;ln c b;"}, true, {"rm /tmp/a /tmp/b; rmdir /tmp/c"})

local function link(cmd, file, is_link, link_path)
  local tmp_dir_path = mktmp('-d','-q')
  chdir(tmp_dir_path)
  os.execute(cmd)
  chdir(home)

  local path = tmp_dir_path .."/".. file
  local g_is_link, g_link_path = fs.isLink(path)
  local meta = fs.stat(path)
  os.execute("rm -rf " .. tmp_dir_path)

  testutil.assert("link check `" .. cmd .. '`', is_link, g_is_link)
  testutil.assert("link path check `" .. cmd .. '`', link_path, g_link_path)

  testutil.assert("meta link check `" .. cmd .. '`', is_link, meta.linkpath and true or nil)
  testutil.assert("meta link path check `" .. cmd .. '`', link_path, meta.linkpath)
end

link("ln /mnt a", "a", true, "/mnt")
link("touch a", "a")
link("ln ../ a", "a", true, "../")
link("ln ../../ a", "a", true, "../../")
link("mkdir d;ln d a;rmdir d", "a", true, "d")
link("touch a;ln a b;ln b c;rm b;ln c b", "b", true, "c")
