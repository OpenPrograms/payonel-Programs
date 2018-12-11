local component = require("component")
local thread = require("thread")
local uuid = require("uuid")
local event = require("event")
local computer = require("computer")
local process = require("process")

local S = {}

--[[
  return patterns:
      nil: always indicates an error or invalid state (e.g. trying to use a closed socket)
      false: always indicates an incomplete attempt on a valid state. specifically, timeouts and interrupts

  events:

  "socket_status", socket id, socket status
    -> socket status change events

  "socket_request", port, address
    -> a listener detected a request for a socket connection

  "socket_available", id, port, remote_address
    -> broadcast response

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

local function pause(timeout)
  return event.pull(timeout or .05) ~= "interrupted"
end

local function set_status(socket, status)
  if not socket or not status or socket.status == status or socket.status < STATUS.new then return end
  socket.status = status
  event.push("socket_status", socket.id, socket.status)
end

local _sockets = setmetatable({}, {__mode = "k"}) -- handle -> socket

local function packet_select(p, from, to)
  to = to or from
  local ret = table.pack(table.unpack(p, from, to))
  ret[ret.n + 1] = table.pack(table.unpack(p, to + 1))
  return table.unpack(ret, 1, ret.n + 1)
end

local function copy_table(t, base)
  for k,v in pairs(base) do
    t[k] = v
  end
  return t
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

local function send(socket, ePacketType, ...)
  local m, status = get_modem(socket.local_address, socket.port)
  if not m then
    set_status(socket, status)
    return nil, status
  end
  return m.send(socket.remote_address, socket.port, socket_api, socket.remote_id, socket.id, ePacketType, ...)
end

local _main_thread = thread.create(pcall, function()
  process.info().data.signal = function(message, level)
    if message ~= "interrupted" then
      error(message, level)
    end
  end
  while true do
    xpcall(function()
      local pack = table.pack(event.pull(.5, "modem_message",
        nil, -- any local address
        nil, -- any remote address
        nil, -- any port
        nil, -- any distance
        socket_api -- socket api only
      ))
      -- modem_message, local_address, remote_address, port, distance, ...
      if pack.n > 0 and next(_sockets) then
        local local_address, remote_address, port, _, _, target_id, remote_id, eType, packet = packet_select(pack, 2, 9)
        if eType and PACKET[eType] then
          -- handle new requests
          packet.remote_address = remote_address
          packet.remote_id = remote_id
          for _, socket in pairs(_sockets) do
            if socket.status >= STATUS.new then
              local handler = socket[PACKET[eType]]
              if handler then
                if not socket.local_address or socket.local_address == local_address then
                  if socket.port == port then
                    if (target_id == socket.id) or (socket.service and target_id == false) then
                      if not socket.remote_address or socket.remote_address == remote_address then
                        if handler(socket, packet) ~= false then
                          return
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end, function(msg)
      event.onError(string.format("socket service thread caught an exception [%s] at:\n%s", tostring(msg), debug.traceback()))
    end)
  end
end):detach()

event.listen("shutdown", function()
  repeat
    local handle, _ = next(_sockets)
    if handle then
      handle:close()
      _sockets[handle] = nil
    end
  until not handle
  _main_thread:kill()
  return false
end)

local handle_base = {
  close = function(self)
    local socket = _sockets[self or false]
    if not socket then return nil, "bad handle" end
    socket:close()
    _sockets[self] = nil
  end,
  status = function(self)
    local socket = _sockets[self or false]
    if not socket then return nil, "bad handle" end
    return socket.status
  end,
  id = function(self)
    local socket = _sockets[self or false]
    if not socket then return nil, "bad handle" end
    return socket.id
  end,
  remote_address = function(self)
    local socket = _sockets[self or false]
    if not socket then return nil, "bad handle" end
    return socket.remote_address
  end,
  wait = function(self, timeout)
    -- true: socket is ready and connected
    -- nil: socket failed or is closed, will never be usable
    -- false: timed out, please wait again
    checkArg(1, timeout, "number", "nil")
    timeout = computer.uptime() + (timeout or math.huge)
    repeat
      local status, reason = self:status()
      if not status then
        return nil, reason
      elseif status < STATUS.new then
        return nil, "socked closed"
      elseif status > STATUS.new then
        return true
      elseif computer.uptime() >= timeout then
        return false, "timed out"
      end
    until not pause()
    return false, "interrupted"
  end
}

local handle_client_base = {
  pull = function(self, timeout)
    checkArg(1, timeout, "number", "nil")

    local socket = _sockets[self or false]
    if not socket then return end

    timeout = computer.uptime() + (timeout or math.huge)
    while #socket.queue == 0 and socket.status >= STATUS.new and computer.uptime() < timeout do
      if not pause() then
        return
      end
    end

    local p = table.remove(socket.queue, 1) or {}
    return table.unpack(p, 1, p.n or #p)
  end,
  push = function(self, ...)
    local socket = _sockets[self or false]
    if not socket then return nil, "bad handle" end

    if socket.status >= STATUS.new and socket.remote_address and socket.remote_id then
      send(socket, PACKET.packet, ...)
      return true
    end
    return nil, "not connected"
  end
}

local socket_client_base = {
  connect = function(self, packet)
    -- if client_unpaired -> we made the initial connect request but got a connect back first (this is okay, order not required)
    -- if client_unlinked -> this is a bit odd, we know the remote socket and we've requested an accept, but another connect request?
    -- if linked, but this is just a keep alive
    -- regardless, the remote_id already matches
    self.remote_id = packet.remote_id
    send(self, PACKET.accept)
  end,
  accept = function(self, packet)
    -- if unpaired -> we got the accept back from our request to open a connection on a remote system
    -- if unlinked -> we got the accept back from the originating linked socket, remote_id already matches
    -- if good client -> remote_id already matches
    self.remote_id = packet.remote_id
    set_status(self, STATUS.connected)
  end,
  packet = function(self, packet)
    table.insert(self.queue, packet)
  end,
  close = function(self, _)
    if self.status > STATUS.closed then
      if self.remote_address then
        send(self, PACKET.close)
      end
      set_status(self, STATUS.closed)
    end
  end
}

local function new_socket(local_address, port, remote_address)
  local handle = copy_table({}, handle_base)
  local socket = {
    id = uuid.next(),
    local_address = local_address or false,
    port = port,
    remote_address = remote_address or false,
    remote_id = false,
    queue = {},
    status = STATUS.new,
    handle = handle,
  }

  _sockets[handle] = socket
  return handle, socket
end

local function prepare_client_socket(local_address, port, remote_address)
  local handle, socket = new_socket(local_address, port, remote_address)
  copy_table(handle, handle_client_base)
  setmetatable(socket, {__index = socket_client_base})

  return handle, socket
end

local handle_server_base = {
  accept = function(self, timeout)
    checkArg(1, timeout, "number", "nil")
    timeout = computer.uptime() + (timeout or math.huge)

    while true do
      local server = _sockets[self or false]
      if not server or server.status <= STATUS.closed then
        return nil, "bad handle"
      end

      if #server.queue > 0 then
        local packet = table.remove(server.queue, 1)
        local client, socket = prepare_client_socket(server.local_address, server.port, packet.remote_address)
        socket.remote_id = packet.remote_id

        send(socket, PACKET.accept) -- required response to the initial connect request
        send(socket, PACKET.connect) -- required to upgrade this socket to a linked state

        return client
      end

      if computer.uptime() >= timeout then
        return false, "timed out"
      end
      if not pause() then
        return false, "interrupted"
      end
    end
  end
}

local socket_server_base = {
  service = true,
  connect = function(self, packet)
    -- queue the packet for async accept
    table.insert(self.queue, packet)
    event.push("socket_request", self.id, self.port, packet.remote_address, packet.remote_id)
  end,
  close = function(self, packet)
    -- this is the server handling the client connection closing before it was accepted
    for index, waiting in pairs(self.queue) do
      if waiting.remote_id == packet.remote_id then
        table.remove(self.queue, index)
        break
      end
    end
  end
}

function S.connect(remote_address, port, local_address)
  checkArg(1, remote_address, "string")
  checkArg(2, port, "number")
  checkArg(3, local_address, "string", "nil")

  local handle, socket = prepare_client_socket(local_address, port, remote_address)
  send(socket, PACKET.connect)

  return handle
end

function S.listen(port, local_address)
  checkArg(1, port, "number")
  checkArg(2, local_address, "string", "nil")

  -- cache the modem, which also opens the port
  if not get_modem(local_address, port) then
    return nil, "modem failed"
  end

  for _, socket in pairs(_sockets) do
    if socket.service and socket.port == port then
      if not local_address or not socket.local_address or socket.local_address == local_address then
        return nil, "socket already exists"
      end
    end
  end

  local handle, socket = new_socket(local_address, port)
  copy_table(handle, handle_server_base)
  setmetatable(socket, {__index = socket_server_base})

  set_status(socket, STATUS.connect) -- service sockets are immediately ready

  return handle
end

function S.broadcast(port, local_address)
  checkArg(1, port, "number")
  checkArg(2, local_address, "string", "nil")

  local m, why = get_modem(local_address, port)
  if not m then
    return nil, why
  end

  local handle, socket = new_socket(local_address, port)
  copy_table(handle, handle_server_base)
  setmetatable(socket, {__index = socket_server_base})

  function socket:connect(packet)
    -- ignore self requests
    if packet.remote_id == self.id then
      return false
    end
    local client, client_socket = prepare_client_socket(socket.local_address, socket.port, packet.remote_address)
    client_socket.remote_id = packet.remote_id
    client:close()

    local partial = {remote_address = packet.remote_address, remote_id = false}
    -- queue the packet for async accept
    table.insert(self.queue, partial)
    event.push("socket_available", self.id, self.port, packet.remote_address)
  end

  function socket.accept(_)
    return false
  end

  --broadcast invites with servers
  m.broadcast(socket.port, socket_api, false, socket.id, PACKET.connect)
  return handle
end

return S
