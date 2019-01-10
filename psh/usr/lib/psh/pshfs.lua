local fs = require("filesystem")
local text = require("text")
local buffer = require("buffer")
local client = require("psh.client")
local shell = require("shell")
local event = require("event")

local pshfs = {}

local function get_fs(path)
  if type(path) ~= "string" then
    io.stderr:write("pshfs host requires path\n")
    os.exit(1)
  end
  path = shell.resolve(path)
  local proxy, root = fs.get(path)
  if not proxy or not fs.isDirectory(path) then
    io.stderr:write("not a directory: " .. path .. "\n")
    os.exit(1)
  end
  -- we need to return the section of path that follows root, as a prefix for api calls
  if path:find(root, 1, true) == 1 then
    path = path:sub(#root + 1)
  end
  return proxy, path .. "/"
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
  isReadOnly = function(proxy, _)
    return response(proxy.isReadOnly())
  end,
  exit = function()
    os.exit(0)
  end,
  getLabel = function(proxy, _)
    return response(proxy.getLabel())
  end,
  list = function(proxy, path)
    return response(table.concat(proxy.list(path), "\n"))
  end,
  isDirectory = function(proxy, path)
    return response(proxy.isDirectory(path))
  end,
  exists = function(proxy, path)
    return response(proxy.exists(path))
  end,
  size = function(proxy, path)
    return response(proxy.size(path))
  end,
  lastModified = function(proxy, path)
    return response(proxy.lastModified(path))
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
  local proxy, prefix = get_fs(args[1])
  while true do
    local command, arg = read_next()
    if not command then
      break
    end
    local action = commands[command]
    if action then
      log(string.format("action [%s] [%s]..[%s]", command, prefix, arg))
      io.write(action(proxy, prefix .. arg))
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
    log("missing node key", key)
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

  local cache = {}
  function node.isReadOnly()
    if cache.isReadOnly == nil then
      cache.isReadOnly = request(node, "isReadOnly") == "true"
    end
    return cache.isReadOnly
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

  function node.makeDirectory(path)
    return request(node, "makeDirectory", path) == "true"
  end

  return node
end

return pshfs
