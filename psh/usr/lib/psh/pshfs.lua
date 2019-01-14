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

local function to_packet(...)
  local pack = table.pack(...)
  for i=pack.n,0,-1 do
    if pack[i] ~= nil then
      pack.n = i
      break
    end
  end
  local spack = serialization.serialize(pack)
  return string.format("%i:%s\n", #spack, spack)
end

local function from_packet(packet)
  local colon = assert(packet:find(":"), "malformed pshfs packet missing colon")
  local num_part = packet:sub(1, colon - 1)
  local spack = packet:sub(colon + 1)
  local num = assert(tonumber(num_part), "malformed pshfs packet expected packet size")
  if num >= #spack then
    -- or equal to because we need +1 for the tail newline
    return nil, "insuficient pack"
  end
  assert(spack:sub(num + 1, num + 1) == "\n", "malformed pshfs packet missing newline")
  local remainder = spack:sub(num + 2)
  local pack = assert(serialization.unserialize(spack:sub(1, num)), "malformed pshfs")
  return remainder, table.unpack(pack, 1, pack.n)
end

local function request(node, command, ...)
  if not node.pipe then
    return nil, "no pipe"
  end
  node.pipe:write(to_packet(command, ...))

  while true do
    local aggregate = table.concat(node.buffer)
    if #aggregate > 0 then
      local pack = table.pack(from_packet(aggregate))
      node.buffer = {pack[1]}
      if node.buffer[1] then
        return table.unpack(pack, 2, pack.n)
      end
    end
    if event.pull(0.5) == "interrupted" then
      return nil, "interrupted"
    end
  end
end

local commands = {
  isReadOnly = function(ctx, _)
    return ctx.proxy.isReadOnly()
  end,
  exit = function()
    os.exit(0)
  end,
  getLabel = function(ctx, _)
    return ctx.proxy.getLabel()
  end,
  list = function(ctx, suffix)
    return ctx.proxy.list(ctx.prefix .. suffix)
  end,
  isDirectory = function(ctx, suffix)
    return ctx.proxy.isDirectory(ctx.prefix .. suffix)
  end,
  exists = function(ctx, suffix)
    return ctx.proxy.exists(ctx.prefix .. suffix)
  end,
  size = function(ctx, suffix)
    return ctx.proxy.size(ctx.prefix .. suffix)
  end,
  lastModified = function(ctx, suffix)
    return ctx.proxy.lastModified(ctx.prefix .. suffix)
  end,
  open = function(ctx, suffix, mode)
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
    return handle, err
  end,
  close = function(ctx, id)
    local file = ctx.files[id or false]
    if not file then
      return nil, "bad handle"
    end
    ctx.proxy.close(file)
    ctx.files[id] = nil
  end,
  read = function(ctx, id, bytes)
    local file = ctx.files[id or false]
    if not file then
      return nil, "bad handle"
    end
    return ctx.proxy.read(file, bytes)
  end,
  write = function(ctx, id, data)
    local file = ctx.files[id or false]
    if not file then
      return nil, "bad handle"
    end
    return ctx.proxy.write(file, data)
  end
}

local function read_next(remainder)
  while true do
    local input = io.stdin:readLine()
    if not input then
      return
    end
    remainder = remainder .. input
    local pack = table.pack(from_packet(remainder))
    if pack[1] then
      return pack
    end
  end
end

function pshfs.host(args)
  local context = {
    files = {}
  }
  context.proxy, context.prefix = get_fs((args or {})[1])
  local remainder = ""
  while true do
    local pack = read_next(remainder)
    if not pack then
      break
    end
    remainder = table.remove(pack, 1)
    local command = pack[1]
    local action = commands[command]
    if action then
      io.write(to_packet(action(context, table.unpack(pack, 2, pack.n))))
    else
      io.write(to_packet(nil, "io error"))
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
  }, { __index = function(tbl, key)
    if commands[key] then
      return function(...)
        return request(tbl, key, ...)
      end
    end
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

  return node
end

return pshfs
