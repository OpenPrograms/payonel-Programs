local fs = require("filesystem")
local text = require("text")
local buffer = require("buffer")
local client = require("psh.client")
local shell = require("shell")
local event = require("event")

local pshfs = {}

local function get(path)
  local proxy = fs.get(path)
  if not proxy or not fs.isDirectory(path) then
    io.stderr:write("not a directory: " .. path .. "\n")
    os.exit(1)
  end
  return proxy
end

local function response(data)
  return string.pack("s", tostring(data))
end

local function request(node, command, data)
  if not node.pipe then
    return nil, "no pipe"
  end
  local buf = {command}
  if data then
    buf[2] = " "
    buf[3] = data
  end
  buf[#buf + 1] = "\n"
  node.pipe:write(table.concat(buf))

  while true do
    local aggregate = table.concat(node.buffer)
    node.buffer = {}
    if #aggregate > 0 then
      local packet, next_byte = string.unpack("s", aggregate)
      node.buffer[1] = aggregate:sub(next_byte)
      return packet
    end
    if event.pull(0) == "interrupted" then
      break
    end
  end
end

local commands = {
  isReadOnly = function(path)
    local proxy = get(path)
    return response(proxy.isReadOnly())
  end,
  exit = function()
    os.exit(0)
  end,
  getLabel = function(path)
    local proxy = get(path)
    return response(proxy.getLabel())
  end,
  list = function(path, arg)
    local canon_path = fs.canonical(path .. "/" .. arg)
    local ret = {}
    for entry in fs.list(canon_path) do
      ret[#ret + 1] = entry
    end
    return response(table.concat(ret, "\n"))
  end,
  isDirectory = function(path, arg)
    local canon_path = fs.canonical(path .. "/" .. arg)
    return response(fs.isDirectory(canon_path))
  end,
  exists = function(path, arg)
    local canon_path = fs.canonical(path .. "/" .. arg)
    return response(fs.exists(canon_path))
  end,
  size = function(path, arg)
    local canon_path = fs.canonical(path .. "/" .. arg)
    return response(fs.size(canon_path))
  end,
  lastModified = function(path, arg)
    local canon_path = fs.canonical(path .. "/" .. arg)
    return response(fs.lastModified(canon_path))
  end,
}

local function read_next()
  local input = io.read()
  if not input then
    return
  end
  return string.match(input, "^([^%s]*)%s?(.*)")
end

function pshfs.host(args)
  args = args or {}
  local path = shell.resolve(args[1])
  if type(path) ~= "string" then
    io.stderr:write("pshfs host requires path\n")
    os.exit(1)
  end
  while true do
    local command, arg = read_next()
    if not command then
      break
    end
    local action = commands[command]
    if action then
      io.write(action(path, arg))
    else
      io.stderr:write(string.format("io error: [%s] [%s]\n", command, arg))
    end
  end
end

function pshfs.client(socket, remote_path)
  checkArg(1, socket, "table")
  checkArg(2, remote_path, "string")
  local ok, why = pcall(client.run, socket, "pshfs --host " .. remote_path)
  return ok, why
end

function pshfs.new_node(address, remote_path)
  checkArg(1, address, "string")
  checkArg(2, remote_path, "string")
  local node = setmetatable({
    address = string.format("%s:%s", address, remote_path),
    buffer = {},
  }, { __index = function(_, key)
    --log("missing node key", key)
  end})

  node.output = buffer.new("w", {
    handle = true,
    close = function(self) self.handle = false end,
    write = function(_, data)
      table.insert(node.buffer, data)
      return true
    end,
  })
  node.output:setvbuf("no")

  function node.isReadOnly()
    if node.isReadOnly_cache == nil then
      node.isReadOnly_cache = request(node, "isReadOnly") == "true"
    end
    return node.isReadOnly_cache
  end
  
  function node.getLabel()
    return request(node, "getLabel")
  end
  
  function node.list(path)
    return text.split(request(node, "list", path), {"\n"}, true)
  end
  
  function node.isDirectory(path)
    return request(node, "isDirectory", path) == "true"
  end
  
  function node.exists(path)
    return request(node, "exists", path) == "true"
  end
  
  function node.open() -- path, mode)
    return false, "not impl"
  end

  function node.size(path)
    return tonumber(request(node, "size", path)) or 0
  end

  function node.lastModified(path)
    return tonumber(request(node, "lastModified", path)) or 0
  end

  return node
end

return pshfs
