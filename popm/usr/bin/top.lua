package.loaded["payo-lib/argutil"] = nil;
local args = require("payo-lib/argutil").parse(table.pack(...));

package.loaded["payo-lib/tableutil"] = nil;
local tutil = require("payo-lib/tableutil");

local wget = loadfile("/bin/wget.lua");

if (not wget) then
  return nil, "this system cannot download without wget installed";
end

local host = "https://raw.githubusercontent.com/OpenPrograms/payonel-Programs/master/";
-- raw.githubusercontent.com/OpenPrograms/payonel-Programs/master/popm/usr/lib/popm-lib/popm.lua

local function download(pkg, file)
  -- wget can download to a file
  -- internet can download in memory using internet.request(url), returns an iteration function of strings

  -- if a pkg name was passed on the command line, only updates those files
  if (next(args) and tutil.indexOf(args, pkg) == nil) then
    return; -- do nothing, pkgs were defined and not this one
  end

  -- -f force (overwrite local file)
  -- -q quiet
  -- -Q quiet quiet (no stderr)
  wget("-f", host .. pkg .. file, file)
end

-- popm
download("popm", "/usr/lib/popm-lib/popm.lua");
download("popm", "/usr/bin/popm.lua");
download("popm", "/usr/bin/top.lua");

-- payo-bash
download("payo-bash", "/etc/rc.d/payo-bash.lua");
download("payo-bash", "/etc/profile");
download("payo-bash", "/usr/bin/load-payo-bash.lua");
download("payo-bash", "/usr/bin/payo-bash/alias.lua");
download("payo-bash", "/usr/bin/payo-bash/cd.lua");
download("payo-bash", "/usr/bin/payo-bash/du.lua");
download("payo-bash", "/usr/bin/payo-bash/echo.lua");
download("payo-bash", "/usr/bin/payo-bash/find.lua");
download("payo-bash", "/usr/bin/payo-bash/grep.lua");
download("payo-bash", "/usr/bin/payo-bash/ls.lua");
download("payo-bash", "/usr/bin/payo-bash/mount.lua");
download("payo-bash", "/usr/bin/payo-bash/mv.lua");
download("payo-bash", "/usr/bin/payo-bash/rm.lua");
download("payo-bash", "/usr/bin/payo-bash/rmdir.lua");
download("payo-bash", "/usr/bin/payo-bash/source.lua");
download("payo-bash", "/usr/bin/payo-bash/touch.lua");

-- payo-lib
download("payo-lib", "/usr/lib/payo-lib/argutil.lua");
download("payo-lib", "/usr/lib/payo-lib/config.lua");
download("payo-lib", "/usr/lib/payo-lib/hijack.lua");
download("payo-lib", "/usr/lib/payo-lib/stringutil.lua");
download("payo-lib", "/usr/lib/payo-lib/tableutil.lua");

-- payo-tests
download("payo-tests", "/var/payo-tests/all-tests.lua");
download("payo-tests", "/var/payo-tests/argutil-test.lua");
download("payo-tests", "/var/payo-tests/config-test.lua");
download("payo-tests", "/var/payo-tests/popm-test.lua");
download("payo-tests", "/var/payo-tests/stringutil-test.lua");
download("payo-tests", "/var/payo-tests/tableutil-test.lua");

-- psh
download("psh", "/etc/psh/psh.cfg");
download("psh", "/etc/rc.d/pshd.lua");
download("psh", "/usr/bin/psh/psh-host.lua");
download("psh", "/usr/bin/psh/psh-reader.lua");
download("psh", "/usr/bin/psh/psh-writer.lua");
download("psh", "/usr/bin/pcp.lua");
download("psh", "/usr/bin/psh.lua");
download("psh", "/usr/bin/pshd.lua");
download("psh", "/usr/lib/psh/remote.lua");
download("psh", "/usr/lib/psh/shell-ex.lua");
