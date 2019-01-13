local fs = require("filesystem")
local text = require("text")
local buffer = require("buffer")
local client = require("psh.client")
local shell = require("shell")
local event = require("event")
local serialization = require("serialization")

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

local function response(...)
  local pack = table.pack(...)
  for i=pack.n,0,-1 do
    if pack[i] ~= nil then
      pack.n = i
      break
    end
  end
  local spack = serialization.serialize(pack)
  return string.pack("s", spack)
end

local function request(node, command, data)
  if not node.pipe then
    return nil, "no pipe"
  end
  node.pipe:write(table.concat({command,data}," ") .. "\n")

  while true do
    local aggregate = table.concat(node.buffer)
    node.buffer = {}
    if #aggregate > 0 then
      local ok, packet, next_byte = pcall(string.unpack, "s", aggregate)
      if not ok then
        return nil, packet
      end
      node.buffer[1] = aggregate:sub(next_byte)
      log(command, data, packet)
      local pack = serialization.unserialize(packet) or {[2]="unserialize failed",n=2}
      return table.unpack(pack, 1, pack.n)
    end
    if event.pull(0) == "interrupted" then
      return nil, "interrupted"
    end
  end
end

local commands = {
  isReadOnly = function(ctx, _)
    return response(ctx.proxy.isReadOnly())
  end,
  exit = function()
    os.exit(0)
  end,
  getLabel = function(ctx, _)
    return response(ctx.proxy.getLabel())
  end,
  list = function(ctx, suffix)
    return response(table.concat(ctx.proxy.list(ctx.prefix .. suffix), "\n"))
  end,
  isDirectory = function(ctx, suffix)
    return response(ctx.proxy.isDirectory(ctx.prefix .. suffix))
  end,
  exists = function(ctx, suffix)
    return response(ctx.proxy.exists(ctx.prefix .. suffix))
  end,
  size = function(ctx, suffix)
    return response(ctx.proxy.size(ctx.prefix .. suffix))
  end,
  lastModified = function(ctx, suffix)
    return response(ctx.proxy.lastModified(ctx.prefix .. suffix))
  end,
  open = function(ctx, mode_suffix)
    local mode, suffix = mode_suffix:match("([^:]*):(.*)")
    if not mode or mode == "" then
      mode = "r"
    end
    local path = ctx.prefix .. suffix
    local handle, err = ctx.proxy.open(path, mode)
    if handle then
      local id = tostring(handle)
      ctx.files[id] = handle
      handle = id
    end
    return response(handle, err)
  end,
  close = function(ctx, id)
    local file = ctx.files[id or false]
    if not file then
      return response(nil, "bad handle")
    end
    ctx.proxy.close(file)
    ctx.files[id] = nil
    return response()
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
  local context = {
    files = {}
  }
  context.proxy, context.prefix = get_fs((args or {})[1])
  while true do
    local command, arg = read_next()
    if not command then
      break
    end
    local action = commands[command]
    if action then
      log(string.format("action [%s] [%s]..[%s]", command, context.prefix, arg))
      io.write(action(context, arg))
    else
      io.stderr:write(string.format("io error: [%s] [%s]\n", command, arg))
      io.write("\n")
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
      cache.isReadOnly = request(node, "isReadOnly")
    end
    return cache.isReadOnly
  end
  
  function node.getLabel()
    return request(node, "getLabel")
  end
  
  function node.list(path)
    local set, err = request(node, "list", path)
    if type(set) == "string" then
      return text.split(set, {"\n"}, true)
    end
    return set, err
  end
  
  function node.isDirectory(path)
    return request(node, "isDirectory", path)
  end
  
  function node.exists(path)
    return request(node, "exists", path)
  end
  
  function node.size(path)
    return request(node, "size", path)
  end

  function node.lastModified(path)
    return request(node, "lastModified", path)
  end

  function node.makeDirectory(path)
    return request(node, "makeDirectory", path)
  end 

  function node.open(path, mode)
    -- sanatize mode
    mode = (mode or ""):gsub("[^awrbt]", "")
    return request(node, "open", mode, path)
  end

  function node.close(handle)
    return request(node, "close", handle)
  end

  -- function node.read(handle, bytes)
  --   return request(node, "read", table.concat({handle, bytes}))
  -- end

  return node
end

return pshfs
