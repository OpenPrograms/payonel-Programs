local component = require("component")
local thread = require("thread")
local uuid = require("uuid")
local event = require("event")
local process = require("process")

local S = {}

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
    socket:set_status(STATUS.nomodem)
    return nil, why
  end
  socket.cached_modem_proxy = proxy
  if not proxy.isOpen(socket.port) and not proxy.open(socket.port) then
    socket:set_status(STATUS.noport)
    return nil, "could not open port"
  end
  return socket.cached_modem_proxy
end

local function send(socket, ePacketType, ...)
  local m, why = get_modem(socket)
  if not m then
    return nil, why
  end
  return m.send(socket.remote_address, socket.port, socket.id, ePacketType, ...)
end

local function recv(socket)
  local m = assert(get_modem(socket))
  return event.pull("modem_message", m.address, socket.remote_address, socket.port, nil, socket.id)
end

local function new_socket(remote_address, port, id, modem_addr)
  checkArg(1, remote_address, "string")
  checkArg(2, port, "number")
  checkArg(3, id, "string")
  checkArg(4, modem_addr, "string", "nil")
  return {
    remote_address = remote_address,
    port = port,
    local_address = modem_addr,
    queue = {},
    id = id,
    status = STATUS.new,
  }
end

local socket_base = {}

local function socket_proc(socket)
  local ok = pcall(function()
    send(socket, PACKET.connect)
    while socket.status >= STATUS.new do
      local packet = table.pack(select(7, recv(socket)))
      local eType = table.remove(packet, 1)
      packet.n = packet.n - 1
      if eType == PACKET.deny then
        socket:set_status(STATUS.denied)
      elseif eType == PACKET.close then
        socket:set_status(STATUS.closed)
      elseif eType == PACKET.connect then
        send(socket, PACKET.accept)
      elseif eType == PACKET.accept then
        socket:set_status(STATUS.connected)
      elseif eType == PACKET.packet then
        if socket.status >= STATUS.connected then
          table.insert(socket.queue, packet)
        end
      end
    end
  end)
  if not ok then
    socket:set_status(STATUS.aborted)
    send(socket, PACKET.close)
  end
end

function socket_base:set_status(status)
  if self.status ~= status then
    self.status = status
    event.push("socket_status", self.id, self.status)
  end
end

local function open_socket(socket)
  socket = setmetatable(socket, {__index = socket_base})
  process.closeOnExit(socket)
  socket.thread = thread.create(socket_proc, socket):detach()
  return socket
end

function socket_base:close()
  if self.thread then self.thread:kill() end
  self.queue = {}
  send(self, PACKET.close)
  self:set_status(STATUS.closed)
end

function socket_base:read(timeout)
  checkArg(1, timeout, "number", "nil")
  timeout = timeout or math.huge
  while #self.queue == 0 and self.thread:status() == "running" and timeout > 0 do
    event.pull(.05, "modem_message")
    timeout = timeout - .05
  end
  local p = table.remove(self.queue, 1)
  if not p then return end
  return table.unpack(p, 1, p.n)
end

function socket_base:write(...)
  if self.status == STATUS.connected then
    send(self, PACKET.packet, ...)
  end
end

function S.connect(remote_address, port, modem_addr)
  local socket = new_socket(remote_address, port, uuid.next(), modem_addr)
  return open_socket(socket)
end

function S.accept(remote_address, port, id, modem_addr)
  local socket = new_socket(remote_address, port, id, modem_addr)
  open_socket(socket)
  send(socket, PACKET.accept)
  return socket
end

function S.deny(remote_address, port, id, modem_addr)
  local socket = new_socket(remote_address, port, id, modem_addr)
  return send(socket, PACKET.deny)
end

return S
