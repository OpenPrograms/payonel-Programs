local fs = require("filesystem")
local thread = require("thread")
local text = require("text")
local buffer = require("buffer")
local client = require("psh.client")

local pshfs = {}

local function get(path)
  local proxy = fs.get(path)
  if not proxy or not fs.isDirectory(path) then
    io.stderr:write("not a directory: ", path, "\n")
    os.exit(1)
  end
  return proxy
end

local commands = {
  isReadOnly = function(proxy)
    return tostring(proxy.isReadOnly()) .. "\n"
  end,
  exit = function()
    os.exit(0)
  end,
  getLabel = function(proxy)
    return proxy.getLabel() .. "\n"
  end,
  list = function(proxy, path)
    local ret = {}
    for _, entry in ipairs(proxy.list(path)) do
      ret[#ret + 1] = entry
    end
    return table.concat(ret, "\n") .. "\n"
  end,
  isDirectory = function(proxy, path)
    return tostring(proxy.isDirectory(path)) .. "\n"
  end,
  exists = function(proxy, path)
    return tostring(proxy.exists(path)) .. "\n"
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
  local path = args[1]
  if type(path) ~= "string" then
    io.stderr:write("pshfs host requires path\n")
    os.exit(1)
  end
  while true do
    local command, arg = read_next()
    if not command then
      break
    end
    local proxy = get(path)
    local action = commands[command]
    if action then
      io.write(action(proxy, arg))
    else
      io.stderr:write(string.format("io error: [%s] [%s]\n", command, arg))
    end
  end
end

local function new_stream(mode)
  local raw = setmetatable({
    handle = true,
    close = function(self) self.handle = false end,
    read = function(self, size)
      log("fs io read", size)
      return nil
    end,
    size = function(self)
      return 0
    end,
    write = function(self, data)
      log(string.format("fs io write [%s]", data))
    end,
  }, {__index = function(_, key)
    log("raw access", key)
  end})
  local stream = buffer.new(mode, raw)
  stream:setvbuf("no")
  return stream
end

local function worker_func(node)
  node.input = new_stream("r")
  node.output = new_stream("w")

  io.stream(0, node.input)
  io.stream(1, node.output)

  local ok, why = pcall(client.run, node.socket, "pshfs --host " .. node.path)
  if not ok then
    node.why = why
  end
  node.socket:close()
  fs.umount(node)
end

local function request(node, command, data)
  log("request", command, data, node.socket:wait())
  node.output:write(command, " ", data, "\n")
  return node.input:read()
end

function pshfs.client(socket, remote_path)
  local address = socket:remote_address()
  local node = {
    socket = socket,
    path = remote_path,
    address = string.format("%s:%s", address, remote_path),
  }

  node.worker = thread.create(worker_func, node):detach()

  function node.isReadOnly()
    return request(node, "isReadOnly") == "true"
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

  setmetatable(node, { __index = function(a, b)
    log(tostring(a), tostring(b))
  end})
  
  return node
  -- socket:close()
end

return pshfs
