local computer = require("computer")
local args,options = require("shell").parse(...)

if options.help then
  print([[Usage: free [OPTIONS]
  -b, --bytes    show output in bytes (default)
  -k, --kilo     show output in kilobytes
  -m, --mega     show output in megabytes
  -g, --giga     show output in gigabytes
  -h, --human    show human-reqadable output
      --si       use powers of 1000 not 1024
      --count=N  cycle system events N times (default 20)
      --help     dispaly this help and exit
]])
  return
end

local function nod(n)
  return n and (tostring(n):gsub("(%.[0-9]+)0+$","%1")) or "0"
end

local function formatSize(size)
  local factor
  if not options.h then
    factor = options.k and 2 or 1
    factor = options.m and 3 or factor
    factor = options.g and 4 or factor
  end
  local sizes = {"", "K", "M", "G"}
  local unit = 1
  local power = options.si and 1000 or 1024
  while true do
    if factor then if unit >= factor then break end
    elseif size < power or unit > #sizes then break end
    unit = unit + 1
    size = size / power
  end
  return nod(math.floor(size*10)/10)..sizes[unit]
end

local function free()
  local max = 0
  local count = tonumber(options.count) or 20
  for i=1,count do
    max = math.max(max,computer.freeMemory())
    os.sleep(0)
  end
  return max
end

print(string.format("    %8s%8s%8s","total","used","free"))
local total = computer.totalMemory()
local free = computer.freeMemory()
local used = total - free
total = formatSize(total)
free = formatSize(free)
used = formatSize(used)
print(string.format("Mem:%8s%8s%8s", total, used, free))
