local ser = require("serialization").serialize
local dsr = require("serialization").unserialize

local init =
{
  api =
  {
    init = "psh.init",
    io = "psh.io",
    throw = "psh.throw",
    hint = "psh.hint",
  },
  pull = function(socket, timeout)
    local packet = table.pack(socket:pull(timeout))
    if packet.n == 0 then return end
    return packet[1], dsr(packet[2])
  end,
  push = function(socket, eType, packet)
    return socket:push(eType, ser(packet))
  end,
  port = 22
}

return init
