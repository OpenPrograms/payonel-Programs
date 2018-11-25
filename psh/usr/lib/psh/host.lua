local ser = require("serialization").serialize
local dsr = require("serialization").unserialize
local shell = require("shell")

local H = {}

local _init_packet_timeout = 5

local packets =
{
  init = {label = "psh.init"},
}

function packets.init.parse(packet_label, packet_body)
  assert(packet_label == packets.init.label)
  return {
    command = packet_body[1] or "/bin/sh",
    timeout = packet_body[2] or _init_packet_timeout,
  }
end

local function next_packet(client, timeout)
  local packet = table.pack(client:pull(timeout))
  assert(packet.n > 0)
  return packet[1], dsr(packet[2])
end

function H.run(client)
  -- local o = io.output()

  local ok, why = pcall(function()
    -- the client connection hasn't proven it is for psh
    -- though it is using psh.sockets
    -- give it time to provide the init packet to establish a psh session
    local init_packet = packets.init.parse(next_packet(client, _init_packet_timeout))
    local context = {socket = client}
    context.command = init_packet.command
    context.timeout = init_packet.timeout

    local host_stream = setmetatable({}, {__metatable = "file"})
    io.input(host_stream)
    io.output(host_stream)
    io.error(host_stream)

    shell.getShell()(nil, context.command)
  end)
  client:close()

  -- o = io.dup(o)
  -- getmetatable(o).__metatable = "file"
  -- io.output(o)
  -- print(ok, why)
end

return H
