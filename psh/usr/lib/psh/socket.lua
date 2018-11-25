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

local _modem_cache = {}
local function get_modem(local_address, port)
  if not local_address and next(_modem_cache) then
    return select(2, next(_modem_cache))
  end
  local address = local_address or component.list("modem")()
  if _modem_cache[address] then
    return _modem_cache[address]
  end
  local proxy = component.proxy(address)
  if not proxy then
    return nil, STATUS.nomodem
  end
  if not proxy.isOpen(port) and not proxy.open(port) then
    return nil, STATUS.noport
  end
  _modem_cache[address] = proxy
  return proxy
end

local function deny(local_address, port, packet)
  local m = get_modem(local_address, port)
  if m then
    m.send(packet.remote_address, port, socket_api, packet.remote_id, false, PACKET.deny)
  end
end

local function send(socket, ePacketType, ...)
  local m, status = get_modem(socket.local_address, socket.port)
  if not m then
    set_socket_status(socket, status)
    return nil, status
  end
  return m.send(socket.remote_address, socket.port, socket_api, socket.remote_id, socket.id, ePacketType, ...)
end

local function socket_handler(socket, eType, packet)
  local is_p2p_socket = socket.id
  local linked = socket.remote_id == packet.remote_id and is_p2p_socket
  local new = socket.status == STATUS.new
  local requestor_waiting_for_accept = is_p2p_socket and not socket.remote_id and new
  local acceptor_waiting_for_accept = linked and new
  local can_be_denied = linked or requestor_waiting_for_accept

  if     eType == PACKET.connect and not is_p2p_socket then
    table.insert(socket.queue, packet)
    event.push("socket_request", socket.port, socket.local_address)
  elseif eType == PACKET.connect and linked then
    -- keep alive ping
    send(socket, PACKET.accept)

  elseif eType == PACKET.accept and requestor_waiting_for_accept then
    socket.remote_id = packet.remote_id
    set_socket_status(socket, STATUS.connected)
    send(socket, PACKET.accept) -- put acceptor in connected state
  elseif eType == PACKET.accept and acceptor_waiting_for_accept  then
    set_socket_status(socket, STATUS.connected) -- connection complete

  elseif eType == PACKET.deny and can_be_denied then
    set_socket_status(socket, STATUS.denied)
    socket:close()

  elseif eType == PACKET.close and linked then
    socket:close()

  elseif eType == PACKET.close and not is_p2p_socket then
    -- this is the server handling the client connection closing before it was accepted
    for index, waiting in pairs(socket.queue) do
      if waiting.remote_id == packet.remote_id then
        table.remove(socket.queue, index)
        break
      end
    end

  elseif eType == PACKET.packet and linked then
    table.insert(socket.queue, packet)

  else
    return false

  end

  return true
end

thread.create(pcall, function()
  while true do
    xpcall(function()
      local pack = table.pack(event.pull(.5, "modem_message"))
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
              return
            end
          end
        end
        deny(local_address, port, packet)
      end
    end, function(msg)
      event.onError(string.format("socket service thread caught an exception [%s] at:\n%s", tostring(msg), debug.traceback()))
    end)
  end
end):detach()

local function close_children(parent_id)
  local children = {}
  for child in pairs(_sockets) do
    if child.parent_id == parent_id then
      children[#children + 1] = child
    end
  end
  for _, child in ipairs(children) do
    child:close()
  end
end

local function socket_close(socket)
  local id = _sockets[socket]
  _sockets[socket] = nil
  socket.queue = {}
  if socket.status > STATUS.closed then
    if socket.remote_address then
      send(socket, PACKET.close)
    elseif not socket.id then
      -- service socket, close all children
      close_children(id)
    end
    set_socket_status(socket, STATUS.closed)
  end
end

local function socket_pull(socket, timeout)
  checkArg(1, timeout, "number", "nil")
  timeout = computer.uptime() + (timeout or math.huge)
  while #socket.queue == 0 and socket.status >= STATUS.new and computer.uptime() < timeout do
    event.pull(.05, "modem_message")
  end
  local p = table.remove(socket.queue, 1)
  if not p then return end
  return table.unpack(p, 1, p.n)
end

local function socket_push(socket, ...)
  if socket.status == STATUS.connected then
    send(socket, PACKET.packet, ...)
    return true
  end
  return nil, "not connected"
end

local function new_socket(remote_address, port, local_address)
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
    socket.pull = socket_pull
    socket.push = socket_push
    socket.id = uuid.next()
  end

  _sockets[socket] = socket.id

  process.closeOnExit(socket)
  return socket
end

local function wait(timeout, predicate, socket_ref)
  timeout = computer.uptime() + (timeout or math.huge)
  repeat
    event.pull(.05, "modem_message")
    local result = predicate(socket_ref)
    if result then
      return result
    elseif result == false then
      break
    end
  until computer.uptime() > timeout
  if socket_ref[1] then
    socket_ref[1]:close()
  end
  return nil, "timed out"
end

local function socket_ready_check(socket_ref)
  local socket = socket_ref[1]
  if not socket then
    return false
  elseif socket.status == STATUS.connected then
    return socket
  elseif socket.status == STATUS.new then
    return
  else
    return false
  end
end

function S.connect(remote_address, port, timeout, local_address)
  checkArg(1, remote_address, "string")
  checkArg(2, port, "number")
  checkArg(3, timeout, "number", "nil")
  checkArg(4, local_address, "string", "nil")
  local socket = new_socket(remote_address, port, local_address)
  send(socket, PACKET.connect)
  return wait(timeout, socket_ready_check, {socket})
end

local function socket_accept(socket, timeout)
  checkArg(1, timeout, "number", "nil")
  local next_request = {
    wait(timeout, function(socket_ref)
      if #socket.queue > 0 then
        local packet = table.remove(socket.queue, 1)
        local client = new_socket(packet.remote_address, socket.port, socket.local_address)
        client.remote_id = packet.remote_id
        client.parent_id = _sockets[socket]
        send(client, PACKET.accept)
        socket_ref[1] = client
        return client
      end
    end, {})
  }
  return wait(math.max(5, timeout or math.huge), socket_ready_check, next_request)
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
  -- cache the modem, which also opens the port
  if not get_modem(local_address, port) then
    return nil, "modem failed"
  end
  local socket = new_socket(nil, port, local_address)
  socket.accept = socket_accept
  return socket
end

return S
