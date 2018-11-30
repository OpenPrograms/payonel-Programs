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
  packet = "packet",
  close = "close",
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
local _pending = {}

local function packet_select(p, from, to)
  to = to or from
  local ret = table.pack(table.unpack(p, from, to))
  ret[ret.n + 1] = table.pack(table.unpack(p, to + 1))
  return table.unpack(ret, 1, ret.n + 1)
end

local function set_socket_status(socket, status)
  if socket.status ~= status and socket.status >= STATUS.new then
    socket.status = status
    event.push("socket_status", socket.id, socket.status)
  end
end

local function socket_service_id(socket)
  return socket.remote_address and socket.id or false
end

local _modem_cache = {}
local function get_modem(local_address, port)
  local proxy = false
  if not local_address and next(_modem_cache) then
    proxy = select(2, next(_modem_cache))
  end
  if not proxy then
    local address = assert(local_address or component.list("modem")(), "socket could not find a modem")
    proxy = _modem_cache[address] or component.proxy(address)
    if not proxy then
      return nil, STATUS.nomodem
    end
  end
  if not proxy.isOpen(port) and not proxy.open(port) then
    return nil, STATUS.noport
  end
  _modem_cache[proxy.address] = proxy
  return proxy
end

local function deny(local_address, port, packet)
  local m = get_modem(local_address, port)
  if m then
    m.send(packet.remote_address, port, socket_api, packet.remote_id, false, PACKET.close)
  end
end

local function send(socket, ePacketType, ...)
  local m, status = get_modem(socket.local_address, socket.port)
  if not m then
    set_socket_status(socket, status)
    return nil, status
  end
  return m.send(socket.remote_address, socket.port, socket_api, socket.remote_id, socket_service_id(socket), ePacketType, ...)
end

local function socket_handler(socket, eType, packet)
  --[[
    connect:
      new sockets and keepalives may choose to send connect to either a listener or a linked socket
      sub state change: new unpaired -> new unlinked (unlinked is waiting for accept)
      client: no packet is queued; server: the packet is queued
      response: accept (server delays response)

    accept:
      accept is always and only the response to a connect and indicates a linked socket exists
      state changes: new -> connected
      no packet is queued
      response: none

    packet:
      linked sockets communicate by passing packets
      no state change
      the packet is queue
      response: none

    close:
      a socket may request or notify closure. client must linked or directed from server
      client only: connected|new -> closed
      no packet is queued
      response: none

    states
      new: client, known server, waiting for accept
        -> new: unlinked (known pair, waiting for accept) accept can come first, socket becomes linked but not connected
        -> connected: linked pair [any accept from server is allowed]
          -> closed: closed by server or linked pair
        -> closed: rejected by server
      new: client, known link pair, waiting for accept
        -> connected: linked pair [only allowed from expected known link]
          -> closed: closed by link pair [these run locally to the server, but technically we can allow any close packet from the remote]
        -> closed: rejected by known link pair or remote machine
      new: server, waiting for connect requests
        -> no state change
      new: server, broadcaster waiting for connect requests (ignores accepts)
        -> no state change
  ]]
  local is_good_client = socket.status >= STATUS.new and socket.remote_address
  local is_listening = socket.status == STATUS.new and not socket.remote_address -- server socket, taking new connections

  -- client states
  -- 1. unpaired -- originating socket, making a request to a server, has no remote id as there is none yet
  -- 2. unlinked -- the accepting socket, having accepted the initial connection request, but not yet linked with its known remote id
  -- 3. linked -- connections have been accepted, the sockets are inter-operating
  -- 4. disconnected -- closed or otherwise failed sockets

  if eType == PACKET.connect and is_listening then
    -- queue the packet for async accept
    table.insert(socket.queue, packet)
    event.push("socket_request", socket.port, socket.local_address)
  elseif eType == PACKET.connect and is_good_client then
    -- if client_unpaired -> we made the initial connect request but got a connect back first (this is okay, order not required)
    -- if client_unlinked -> this is a bit odd, we know the remote socket and we've requested an accept, but another connect request?
    -- if linked, but this is just a keep alive
    -- regardless, the remote_id already matches
    socket.remote_id = packet.remote_id
    send(socket, PACKET.accept)
  
  elseif eType == PACKET.accept and is_good_client then
    -- if unpaired -> we got the accept back from our request to open a connection on a remote system
    -- if unlinked -> we got the accept back from the originating linked socket, remote_id already matches
    -- if good client -> remote_id already matches
    socket.remote_id = packet.remote_id
    set_socket_status(socket, STATUS.connected)

  elseif eType == PACKET.packet and is_good_client then
    table.insert(socket.queue, packet)
    
  elseif eType == PACKET.close and is_good_client then
    set_socket_status(socket, STATUS.closed)

  elseif eType == PACKET.close and is_listening then
    -- this is the server handling the client connection closing before it was accepted
    for index, waiting in pairs(socket.queue) do
      if waiting.remote_id == packet.remote_id then
        table.remove(socket.queue, index)
        break
      end
    end

  else
    return false

  end

  return true
end

local _main_thread = thread.create(pcall, function()
  local function all_sockets()
    if not next(_pending) then
      return _sockets
    end
    local ret = _pending
    _pending = {}
    for key, value in pairs(_sockets) do
      ret[key] = value
    end
    return ret
  end

  while true do
    xpcall(function()
      local pack = table.pack(event.pull(.5, "modem_message"))
      -- modem_message, local_address, remote_address, port, distance, ...
      local local_address, remote_address, port, _, api, target_id, remote_id, eType, packet = packet_select(pack, 2, 9)
      if socket_api == api and remote_id then
        -- handle new requests
        packet.remote_address = remote_address
        packet.remote_id = remote_id
        for socket in pairs(all_sockets()) do
          if (not socket.local_address or socket.local_address == local_address) and
             (not socket.remote_address or socket.remote_address == remote_address) and
             socket_service_id(socket) == target_id and socket.port == port then
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

event.listen("shutdown", function()
  for socket in pairs(_sockets) do
    socket:close()
  end
  _sockets = {}
  _main_thread:kill()
  return false
end)

local function socket_close(socket)
  _pending[socket] = nil
  _sockets[socket] = nil
  if socket.status > STATUS.closed then
    if socket.remote_address then
      send(socket, PACKET.close)
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
    id = uuid.next(),
    remote_id = false,
    status = STATUS.new,
    close = socket_close,
  }

  if remote_address then
    socket.pull = socket_pull
    socket.push = socket_push
  end

  return socket
end

local function add_socket(socket, ...)
  if socket then
    _pending[socket] = nil
    _sockets[socket] = socket.id
    process.closeOnExit(socket)
  end
  return socket, ...
end

local function wait(cancel, predicate, socket_ref)
  if type(cancel) ~= "function" then
    local timeout = computer.uptime() + (cancel or math.huge)
    cancel = function()
      return computer.uptime() > timeout
    end
  end
  repeat
    local socket = socket_ref[1]
    if socket then
      _pending[socket] = socket.id
    end
    event.pull(.05, "modem_message")
    --the main socket thread is responsible for clearing pending sockets
    --we have nothing else to do with it
    local result = predicate(socket_ref)
    if result then
      return result
    elseif result == false then
      break
    end
  until cancel()
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

function S.connect(remote_address, port, local_address, cancel)
  checkArg(1, remote_address, "string")
  checkArg(2, port, "number")
  checkArg(3, local_address, "string", "nil")
  checkArg(4, cancel, "number", "function", "nil")
  local socket = new_socket(remote_address, port, local_address)
  send(socket, PACKET.connect)
  return add_socket(wait(cancel, socket_ready_check, {socket}))
end

local function socket_accept(socket, timeout)
  checkArg(1, timeout, "number", "nil")
  local next_request = {
    wait(timeout, function(socket_ref)
      if socket.status <= STATUS.closed then return false end
      if #socket.queue > 0 then
        local packet = table.remove(socket.queue, 1)
        local client = new_socket(packet.remote_address, socket.port, socket.local_address)
        client.remote_id = packet.remote_id
        send(client, PACKET.accept) -- required response to the initial connect request
        send(client, PACKET.connect) -- required to upgrade this socket to a linked state
        socket_ref[1] = client
        return client
      end
    end, {})
  }
  return add_socket(wait(math.max(5, timeout or math.huge), socket_ready_check, next_request))
end

local function get_listener(port, local_address)
  for socket in pairs(_sockets) do
    if not socket.remote_address and socket.port == port then
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
  return add_socket(socket)
end

function S.broadcast(port, local_address)
  checkArg(1, port, "number")
  checkArg(2, local_address, "string", "nil")
  local socket = new_socket(nil, port, local_address)
  socket.accept = socket_accept -- but accept like a server

  local m, why = get_modem(socket.local_address, socket.port)
  if not m then
    return nil, why
  end

  --broadcast invites with servers
  m.broadcast(socket.port, socket_api, false, socket.id, PACKET.connect)
  return add_socket(socket)
end

return S
