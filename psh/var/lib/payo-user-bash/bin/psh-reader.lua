local io = require("io");
local shell = require("shell");
local m = require("component").modem;
local remote = require("remote");
local sr = require("serialization").serialize;

if (not m) then
    io.stderr:write(os.getenv()._ .. " requires a modem\n")
    return
end

local args, options = shell.parse(...)

-- requires 2 args, 3rd optional
local remote_id = args[1]
local remote_port = args[2] and tonumber(args[2]) or nil
local bPrompt = not not args[3]

if (not remote_id or not remote_port) then
    io.stderr:write(os.getenv()._ .. " Usage: remote_id remote_port [bPrompt]\n");
    return
end

-- taken from openos sh.lua
local function expand(value)
  local result = value:gsub("%$(%w+)", os.getenv):gsub("%$%b{}",
    function(match) return os.getenv(expand(match:sub(3, -2))) or match end)
  return result
end

local function requestRead()
    m.send(remote_id, remote_port, remote.messages.READ);
end

-- this tool can also be used to ONLY put client back in prompt mode
if (bPrompt) then
    local p = expand(os.getenv("PS1") or "$ ");
    m.send(remote_id, remote_port, remote.messages.PROMPT, p)
    
    requestRead()
    return -- leave this script
end

-- this script will be resumed when the next command in the pipeline goes dead or requests a read

local out = io.output();
local stream = out and out.stream or nil;
local next = stream and stream.next or nil;

if (not next) then
    io.stderr:write("this tool must not be the last command in the pipe unless requesting prompt");
    return
end

local handlers = {};
local token_handlers = {};

local next_input = nil;

handlers[remote.messages.INPUT_SIGNAL] = function(lastChar, lengthAvailable)
    
    if (lengthAvailable == 0) then
        return;
    end
    
    -- we only care about LINEs
    if (lastChar ~= '\n') then
        return -- ignore this
    end
    
    next_input = remote.read(lengthAvailable);
end

while (true) do
    if (coroutine.status(next) == "dead") then
        -- next is dead, there is no point in getting more data
        break;
    end
    
    -- go into event loop to get next input line for user
    -- next is suspended, let's talk to it

    next_input = nil;
    requestRead();
    
    if (remote.running and remote.connected) then
        while (not next_input and remote.running and remote.connected) do
            remote.handleNextEvent(handlers, token_handlers)
        end
    else
        next_input = io.read("*L");
    end
    
    io.write(next_input)
end


