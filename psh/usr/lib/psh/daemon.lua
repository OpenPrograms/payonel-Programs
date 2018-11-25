local event = require("event")
local thread = require("thread")
local sockets = require("psh.socket")

local daemon = {
  service = false,
  thread = false,
}

local function handle_new_client(client)
  print(client:pull())
  client:close()
end

function daemon.close()
  if daemon.service then
    daemon.service:close()
    daemon.service = false
  end
end

local function daemon_thread_proc(port, addr)
  event.push("pshd.daemon.start")
  event.pull(0) -- immediately yield to get new parent process (detached)
  daemon.close()
  daemon.service = assert(sockets.listen(port, addr))
  while true do
    local ok, why = pcall(thread.create, handle_new_client, daemon.service:accept())
    if not ok then
      event.onError("pshd caught an exception: " .. tostring(why))
    end
  end
end

function daemon.status()
  if daemon.thread then
    return daemon.thread:status()
  else
    return "stopped"
  end
end

function daemon.start(port, addr)
  if daemon.thread then
    local status = daemon.thread:status()
    if status == "running" then
      return -- already running
    elseif status == "suspended" then
      daemon.thread:resume()
    elseif status == "dead" then
      daemon.thread = nil
      return daemon.start()
    end
  else
    daemon.thread = thread.create(daemon_thread_proc, port, addr):detach()
  end
  return daemon.thread:status() == "running"
end

function daemon.stop()
  if daemon.thread then
    if daemon.thread:status() ~= "dead" then
      daemon.thread:kill()
      daemon.thread:join()
      -- this is a hack because killed threads don't close their handles
      daemon.close()
      return true
    end
  end
end

return daemon
