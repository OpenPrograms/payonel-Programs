local component = require("component")
local event = require("event")
local process = require("process")
local computer = require("computer")

local thread = require("thread")

local daemon = {}

daemon.thread = nil -- daemon thread

local function modem(addr)
  local modem_addr = addr or component.list("modem")()
  if not modem_addr then
    return
  end
  return component.proxy(modem_addr)
end

local handler = {}
function handler.list(...)
end

local function daemon_thread_proc(port, addr)
  local m = assert(modem(addr), "daemon proc requires modem")
  port = port or 1
  m.open(port)
  while true do
    local modem_pack = table.pack(event.pull("modem_message"))
    if modem_pack[1] then
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
  if not modem(addr) then
    return nil, "no modem"
  end
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
      return true
    end
  end
end

return daemon
