local component = require("component")
local thread = require("thread")
local uuid = require("uuid")
local event = require("event")
local process = require("process")
local computer = require("computer")

local S = {}

--[[
  events:

  "socket_status", socket id, socket status
    -> socket status change events

  "socket_request", port, address
    -> a listener detected a request for a socket connection
]]--

local socket_api = "payo:socketapi:0"

local PACKET =
{
  connect = "connect",
  accept = "accept",
  deny = "deny",
  close = "close",
  packet = "packet",
}

local STATUS =
{
  aborted = -4,
  noport = -3,
  nomodem = -2,
  denied = -1,
  closed = 0,
  new = 1,
  connected = 2,
}

local _sockets = {}

local function packet_select(p, from, to)
  to = to or from
  local ret = table.pack(table.unpack(p, from, to))
  ret[ret.n + 1] = table.pack(table.unpack(p, to + 1))
  return table.unpack(ret, 1, ret.n + 1)
end

local function set_socket_status(socket, status)
  if socket.status ~= status then
    socket.status = status
    event.push("socket_status", socket.id, socket.status)
  end
end

local function get_modem(socket)
  if socket.cached_modem_proxy then
    if not socket.local_address or socket.cached_modem_proxy.address == socket.local_address then
      return socket.cached_modem_proxy
    end
    socket.cached_modem_proxy = nil
  end
  local addr = socket.local_address or component.list("modem")()
  local proxy, why = component.proxy(addr)
  if not proxy then
    set_socket_status(socket, STATUS.nomodem)
    return nil, why
  end
  socket.cached_modem_proxy = proxy
  if not proxy.isOpen(socket.port) and not proxy.open(socket.port) then
    set_socket_status(socket, STATUS.noport)
    return nil, "could not open port"
  end
  return socket.cached_modem_proxy
end

local function send(socket, ePacketType, ...)
  local m, why = get_modem(socket)
  if not m then
    return nil, why
  end
  return m.send(socket.remote_address, socket.port, socket_api, socket.remote_id, socket.id, ePacketType, ...)
end

local function socket_handler(socket, eType, packet)
  if eType == PACKET.connect and not socket.id then
    table.insert(socket.queue, packet)
    event.push("socket_request", socket.port, socket.local_address)
  elseif eType == PACKET.accept and not socket.remote_id then
    socket.remote_id = packet.remote_id
    set_socket_status(socket, STATUS.connected)
  elseif socket.remote_id == packet.remote_id and socket.id then
    if eType == PACKET.close then
      socket:close()
    elseif eType == PACKET.packet and socket.status >= STATUS.connected then
      table.insert(socket.queue, packet)
    else
      return false
    end
  else
    return false
  end
  return true
end

thread.create(pcall, function()
  while true do
    xpcall(function()
      local pack = table.pack(event.pull("modem_message"))
      -- modem_message, local_address, remote_address, port, distance, ...
      local local_address, remote_address, port, _, api, target_id, remote_id, eType, packet = packet_select(pack, 2, 9)
      if socket_api == api and remote_id then
        -- handle new requests
        packet.remote_address = remote_address
        packet.remote_id = remote_id
        for socket in pairs(_sockets) do
          if (not socket.local_address or socket.local_address == local_address) and
             (not socket.remote_address or socket.remote_address == remote_address) and
             socket.id == target_id and socket.port == port then
            if socket_handler(socket, eType, packet) then
              break
            end
          end
        end
      end
    end, function(msg)
      event.onError(string.format("socket service thread caught an exception [%s] at:\n%s", tostring(msg), debug.traceback()))
    end)
  end
end):detach()

local function socket_close(socket)
  _sockets[socket] = nil
  socket.queue = {}
  if socket.remote_address then
    send(socket, PACKET.close)
  end
  if socket.id then
    set_socket_status(socket, STATUS.closed)
  end
end

local function socket_read(socket, timeout)
  checkArg(1, timeout, "number", "nil")
  timeout = computer.uptime() + (timeout or math.huge)
  while #socket.queue == 0 and socket.status >= STATUS.new and computer.uptime() < timeout do
    event.pull(.05, "modem_message")
  end
  local p = table.remove(socket.queue, 1)
  if not p then return end
  return table.unpack(p, 1, p.n)
end

local function socket_write(socket, ...)
  while socket.status == STATUS.new do
    event.pull(.05, "modem_message")
  end
  if socket.status == STATUS.connected then
    send(socket, PACKET.packet, ...)
    return true
  end
  return nil, "not connected"
end

local function new_socket(remote_address, port, local_address)
  checkArg(1, remote_address, "string", "nil")
  checkArg(2, port, "number")
  checkArg(3, local_address, "string", "nil")
  local socket = {
    local_address = local_address,
    remote_address = remote_address,
    port = port,
    queue = {},
    id = false,
    remote_id = false,
    status = STATUS.new,
    close = socket_close,
  }
  if remote_address then
    socket.read = socket_read
    socket.write = socket_write
    socket.id = uuid.next()
  end
  _sockets[socket] = socket.id
  process.closeOnExit(socket)
  return socket
end

function S.connect(remote_address, port, local_address)
  checkArg(1, remote_address, "string")
  local socket = new_socket(remote_address, port, local_address)
  send(socket, PACKET.connect)
  return socket
end

local function socket_accept(socket, timeout)
  checkArg(1, timeout, "number", "nil")
  timeout = computer.uptime() + (timeout or math.huge)
  repeat
    local p = table.remove(socket.queue, 1)
    if p then
      local client = new_socket(p.remote_address, socket.port, socket.local_address)
      socket_handler(client, PACKET.accept, p)
      send(client, PACKET.accept)
      return client
    end
    event.pull(.05, "modem_message")
  until computer.uptime() > timeout
  return nil, "timed out"
end

local function get_listener(port, local_address)
  for socket in pairs(_sockets) do
    if not socket.id and socket.port == port then
      if not local_address or not socket.local_address or socket.local_address == local_address then
        return socket
      end
    end
  end
end

function S.listen(port, local_address)
  checkArg(1, port, "number")
  checkArg(2, local_address, "string", "nil")
  if get_listener(port, local_address) then
    return nil, "socket already exists"
  end
  local socket = new_socket(nil, port, local_address)
  socket.accept = socket_accept
  return socket
end

return S
