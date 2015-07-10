local component = require("component");
local event = require("event");
require("package").loaded.remote = nil;
local remote = require("remote");

local m = component.modem;
local token_handlers = {}

remote.running = true;

if (not m) then
  print ("missing a modem");
  return 1;
end

m.open(remote.DAEMON_PORT);
if (not m.isOpen(remote.DAEMON_PORT)) then
  print("Failed to open daemon port")
  return 1;
end

local function pickLocalPort()
  for i=remote.DAEMON_PORT+1,64000 do
    if (not m.isOpen(i)) then
      return m.open(i), i
    end
  end
end

local function readyMessage()
  if (remote.running) then
    print("\nReady for remote connection")
  end
end

token_handlers[remote.messages.SEARCH] = function (meta, p1, p2)
  local remote_port = p2 and tonumber(p2) or nil;

  if (remote_port) then
        
    local wants_us = true;
    p1 = (p1 and p1:len() > 0 and p1) or nil;
    if (p1) then
      local id = meta.local_id:find(p1);
      wants_us = id == 1
    end

    if (wants_us) then
      print("available, responding to " .. meta.remote_id .. " on " .. tostring(remote_port))
      m.send(meta.remote_id, remote_port, remote.messages.AVAILABLE)
    else
      print("ignoring: does not want us")
    end
  end
end

token_handlers[remote.messages.CONNECT] = function (meta, p1, p2)
  local remote_port = p2 and tonumber(p2) or nil;
  local local_port;
    
  if (remote_port) then
        
    local wants_us = meta.local_id == p1;

    if (wants_us) then
            
      local ok;
      ok, local_port = pickLocalPort();
            
      if (not ok) then
        io.stderr:write("abort: failed to open shell port for remote connect request\n")
        return 1
      end
            
      print("sending accept: " .. tostring(meta.remote_id) 
        ..",".. tostring(remote_port) ..",".. remote.messages.ACCEPT ..",".. tostring(local_port));
                
      m.send(meta.remote_id, remote_port, remote.messages.ACCEPT, local_port);
            
      local invoke = string.format(remote.tools.host .. " %s %s %s", 
        tostring(local_port),
        tostring(meta.remote_id), 
        tostring(remote_port));
                
      print("request wants us: ", invoke)
            
      local ok, reason = os.execute(invoke);
            
      if (not ok) then
        io.stderr:write("failed to invoke: " .. reason .. "\n")
      else
        print("connection closed with: ", meta.remote_id);
      end

      m.close(local_port)
      readyMessage()
    else
        print("ignoring: does not want us")
    end
  end
end

readyMessage()

while (remote.running) do
  remote.handleNextEvent(nil, token_handlers)
end

m.close(remote.DAEMON_PORT)

