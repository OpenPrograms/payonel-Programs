require("package").loaded.remote = nil

local remote = require("psh/remote")
local shell = require("shell")
local fs = require("filesystem")

local args, options = shell.parse(...)

-- there must be exactly one available host
-- and it must be specified by at least a 4-length address prefix

local function usage()
  io.stderr:write("usage: [-r] [local path] [min 4-length address prefix]:[remote path]")
  os.exit();
end

if (#args ~= 2) then
  usage();
end

local function getPaths(p1, p2)
  local recursive = options.r;
  local local_path = args[1];
  local remote_arg = args[2];
    
  if (not local_path or not remote_arg) then
    return nil, "missing local path or remote argument"
  end
    
  local_path = shell.resolve(local_path)
    
  if (not fs.exists(local_path)) then
    return nil, "file or directory does not exist: " .. local_path
  end
    
  if (fs.isDirectory(local_path)) then
    if (not options.r) then
      return nil, local_path .. " is a directory, use -r for a recursive copy for directories"
    end
  elseif (options.r) then
    -- ignore r on files
    options.r = nil
  end
    
  local addr_path_index = remote_arg:find(":");
  if (not addr_path_index) then
    return nil, "remote address must have :"
  end
    
  local remote_id_prefix = remote_arg:sub(1, addr_path_index - 1)
  local remote_path = remote_arg:sub(addr_path_index + 1)
    
  if (remote_id_prefix:len() < 4) then
    return nil, "remote address must be at least 4 chars long"
  end
    
  return true, nil, local_path, remote_id_prefix, remote_path
end

local ok, reason, local_path, remote_id_prefix, remote_path = getPaths(args[1], args[2])
    
if (not ok) then
  if (reason) then
    io.stderr:write(reason .. '\n')
  end
  usage()
end

local files = {}

-- now option.r should indicate dir or file for us
if (options.r) then
  files[1] = {'d', local_path}
  for p in fs.list(local_path) do
    local full = local_path .. '/' .. p
    local t = fs.isDirectory(full) and 'd' or 
              fs.isLink(full) and 'l' or 'f';
                  
    files[#files + 1] = {t, p}
  end
else
  files[1] = {'f', local_path}
end

local available_hosts = remote.search(remote_id_prefix, true, false)
if (#available_hosts > 1) then
  io.write("Too many hosts\n")
  for i,host in ipairs(available_hosts) do
    io.write(host .. '\n')
  end
  os.exit()
elseif (#available_hosts == 0) then
  io.write("host by prefix not found: " .. remote_id_prefix)
  os.exit()
end
   
local remote_id = available_hosts[1].remote_id
print(local_path, remote_id, remote_path)

for i,file in ipairs(files) do
  print("pcp " .. file[1] .. " " .. file[2] .. " => " .. remote_id .. ":" .. remote_path)
end

