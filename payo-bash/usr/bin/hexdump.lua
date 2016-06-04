local shell = require("shell")
local fs = require("filesystem")
local process = require("process")

-- custom stdout to listen for piped processes that try to close our stdout fh
local stdout = process.info().data.io[1]

local cmd_name = "hexdump"
local args, options = shell.parse(...)

local function print_usage()
  print(
[[Usage: hexdump [options] <file>...
Display file(s) contents in hexadecimal.
With no file read stdin.
 -C, --canonical           canonical hex+ASCII display
     --length=<length>     interpret only length bytes of input
     --skip=<offset>       skip offset bytes from the beginning
     --help                display this help and exit
 Files are concatenated in output if multiple given]])
end

if options.help then
  print_usage()
  return
end

local flush_offset = 0
local buffer_max = 16
local buffer = ""

local length = options.length and tonumber(options.length) or math.huge
local skip = options.skip and tonumber(options.skip) or 0
options.C = options.C or options.canonical

local function file_open(path)
  if path == '-' then
    return io.stdin
  end
  return io.open(path, 'r')
end

local function tohex(c)
  return string.format("%02x%02x ", 
    c:len() > 1 and string.byte(c, 2) or 0,
    string.byte(c, 1))
end

local function flush()
  local line = string.format("%08x", flush_offset)

  for i=1,buffer:len(),2 do
    line = string.format("%s %02x%02x", line, 
      string.byte(buffer, i + 1) or 0,
      string.byte(buffer, i))
  end

  if options.C and buffer:len() > 0 then
    line = string.format("%s |%s|", line, buffer:gsub('[\n\r\t]', '.'))
  end

  print(line)
  flush_offset = flush_offset + buffer:len()
  buffer = ""
end

local function store(data)
  while data:len() > 0 do
    local space_remaining = buffer_max - buffer:len()
    local sub = string.sub(data, 1, space_remaining)
    data = string.sub(data, 1 + sub:len())
    buffer = buffer .. sub

    if buffer:len() >= buffer_max then
      flush()
    end

  end
end

local total_bytes_stored = 0
local skipping = skip > 0

local function dump(path)
  local f = file_open(path, 'r')

  while not stdout.closed and f:read(0) and length > total_bytes_stored do
    local b = f:read("*L")

    -- stdin can fail to read more than 0 when closed
    if b == nil then
      break
    end

    --special case -- f is stdin and b is \n only, we need to display it
    if b == '\n' and f == io.stdin then
      print()
    end

    if skipping then
      if skip <= b:len() then
        skipping = false
        b = string.sub(b, skip + 1)
      else
        skip = skip - b:len()
      end
    end
    -- not else - skip may just have been fulfilled
    if not skipping then
      local store_remaining = length - total_bytes_stored
      b = string.sub(b, 1, math.min(b:len(), store_remaining))
      total_bytes_stored = total_bytes_stored + b:len()

      store(b)
    end
  end

  f:close()
end

local files = {}
local ec = 0

for _,arg in ipairs(args) do
  local file = args[1]
  local full_path = shell.resolve(file)
  local exists = fs.exists(full_path)

  if not exists then
    io.stderr:write(string.format("%s: %s: No such file\n", cmd_name, file))
    ec = 1
  elseif not exists or fs.isDirectory(file) then
    io.stderr:write(string.format("%s: %s: Is a directory\n", cmd_name, file))
    ec = 1
  else
    files[#files + 1] = full_path
  end
end

if #args == 0 then
  files = {"-"}
end

if #files == 0 then
  io.stderr:write(string.format("%s: all input file arguments failed\n", cmd_name))
  return 1
end

for _,file in ipairs(files) do
  dump(file)
end

if buffer:len() > 0 then
  flush()
end

flush()

return ec
