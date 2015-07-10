
function start(args)
  local s = require("shell");
  local fs = require("filesystem");

  local source_path = s.resolve("source", "lua") or "/usr/bin/payo-bash/source.lua";
  if (not fs.exists(source_path)) then
    io.stderr:write("could not locate source.lua");
    return false;
  end

  os.execute(source_path .. ' /etc/profile');

end
