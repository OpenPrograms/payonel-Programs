
-- everything piped to this command should be
--sent to a specified modem on a specified port

local shell = require("shell");
local comp = require("component");
local process = require("process");
local ser = require("serialization");
local remote = require("psh/remote");

local m = comp.modem;
if (not m) then
  io.stderr:write("modem required\n");
  return 1;
end

local args, options = shell.parse(...);

local address = args[1];
local port = args[2];

if (type(port) == type("")) then
  port = tonumber(port)
end

if (#args ~= 2 or type(address) ~= type("") or type(port) ~= type(0)) then
  io.stderr:write("Usage: [remote_modem_guid] [port]");
  io.stderr:write(string.format("%i, %s, %s\n", #args, type(address), type(port)))
  return 1;
end

--address = "61960d22-b4a0-4e35-af89-0856dc2a0721"

local inputHandle = io.input();
local stream = inputHandle.stream;
local read_size = 8192;

while true do
  local line = stream:read(read_size);
    
  while (stream.buffer:len() > 0) do
    line = line .. stream:read(read_size);
  end
    
  if (not line) then
    inputHandle:close();
    break;
  end
    
  remote.send_output(line, 1);
end

remote.send_output(nil, 1);
