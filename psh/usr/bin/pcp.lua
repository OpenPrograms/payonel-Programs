local shell = require("shell")

local args, options = shell.parse(...)

options.l = options.l or options.list
options.r = options.r or options.recursive
options.f = not options.l and (options.f or options.first)
options.v = options.v or options.verbose
options.h = options.h or options.help

-- local remote_address, remote_path = (remote_arg or ""):match("^([^:]*):.*$")

local ec = 1

local function parse_paths(paths)
  local ret = {}
  local longest_host = ""
  for _, path in ipairs(paths) do
    local host = path:match("^([^:]*):")
    local name = host and path:match(":(.*)$") or path
    if host then
      if options.f then
        if host:find(longest_host, 1, true) ~= 1 then
          io.stderr:write("Hosts must refer a singular address when using --first: ", host)
          return false
        end
      end
      longest_host = #longest_host > #host and longest_host or host
      if name == "" then
        name = "."
      end
    end
    table.insert(ret, {host = host, name = name})
  end
  return ret
end

local paths = parse_paths(args)

if ec > 0 or options.h or not paths then
  print([[Usage: pcp [OPTIONS] [HOST:]PATH ...
  OPTIONS
  -l  --list        no files are copied, available hosts are listed
  -f  --first       use first available and matching host
  -r  --recursive   copy directory recursively
  -v  --verbose     be verbose during the operations
  -h  --help        print this help
      --port=N      Use a specified port instead of the default
  PATH              file or directory path. final path is destination
                    Path is local if HOST: prefix is omitted. Path can be empty
                    following the : which indicates the home directory of the
                    specified host. Paths can be absolute starting with /
  HOST              Modem address followed by a colon. --first reads all HOST
                    paths as a prefix, even empty HOST paths (e.g. :PATH)
  Example:
    pcp local_file 2553a215-59c3-629a-939c-f4efd0050984:remote_file
    pcp -r my_dir 5bbd:
    pcp -r 5bbd:remote_dir .]])
  os.exit(ec)
end

-- now the crazy part
-- create a virtual mount point in /tmp
-- copy the local_path using the options.r given
-- handle all files writes in the virtual mount point by sending command to remote to create those files
-- when cp is done, unmount virtual mount point
-- just in case something crazy happens during the pcp execution, do it all in a pcall

  for _,entry in ipairs(paths) do
    print(entry.name, entry.host)
  end
  
  