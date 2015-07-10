local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local keyboard = require("keyboard")
local term = require("term")
local unicode = require("unicode")
local computer = require("computer")

require("package").loaded.remote = nil;
local remote = require("remote");

local m = component.modem;
local remote_port;
local local_port;
local remote_prompt = nil

local cursorX, cursorY = 1, 1
local cursorBlink = nil
local handlers = {};
local token_handlers = {};

-- Example key-handler that simply sets running to false if the user hits space
local currentInput = nil;
local currentInputIndex = 0;

local args, options = shell.parse(...);
local address = args[1]
--local address = "5bbd615a-b630-4b7c-afbe-971e28654c72"

if (not m) then
    print("no modem");
    return 1;
end

local function pickLocalPort()
    local lport = remote.DAEMON_PORT + 1;
    m.close(lport);
    return m.open(lport), lport;
end

local function closeLocalPort()
    if (local_port and m.isOpen(local_port)) then
        m.close(local_port)
    end
end

local function pickSingleHost()
    local responders = remote.search(address, options.f, true)
    if (#responders == 0) then
        return nil, "No hosts found";
    end
    
    if (#responders > 1) then
        return nil, "Too many hosts"
    end
    
    return responders[1].remote_id
end

local function prompt()
    return "[" .. remote_id:sub(1, 4) .. "] " .. tostring(remote_prompt)
end

local function term_at_home()
    return cursorX == 1;
end

local function term_at_end()
    return cursorX - 1 == currentInput:len();
end

local function term_delete()
    
    -- can only delete if cursor is ON an input char
    -- same as asking can we move right
    if (term_at_end()) then
        return false
    end
    
    -- new input is sub skipping cursorX
    -- keep copy of separate subs to help write line
    local left = currentInput:sub(1, cursorX - 1)
    local right = currentInput:sub(cursorX + 1, currentInput:len())
    local overwrite = right .. ' '; -- space to clear what WAS there (i.e. last char of right)
    
    local cx, cy = term.getCursor();
    io.write(overwrite);
    term.setCursor(cx, cy);
    currentInput = left .. right;
    
    return true;
end

local function term_move_left()
    
    -- can move left?
    if (term_at_home()) then
        return false;
    end
    
    cursorX = cursorX - 1;
    
    local cx, cy = term.getCursor()
    term.setCursor(cx - 1, cy)

    return true
end

local function term_move_right()
    
    -- at end of current input?
    if (term_at_end()) then
        return false;
    end
    
    cursorX = cursorX + 1;
    local cx, cy = term.getCursor()
    term.setCursor(cx + 1, cy)
    
    return true
end

local function term_move_home()
    
    if (term_at_home()) then
        return false;
    end
    
    local cx, cy = term.getCursor()
    term.setCursor(cx - cursorX + 1, cy)
    cursorX = 1;
    
    return true
end

local function term_move_end()
    
    if (term_at_end()) then
        return false;
    end
    
    local cx, cy = term.getCursor()
    term.setCursor(cx - cursorX + 1 + currentInput:len(), cy)
    cursorX = currentInput:len() + 1;

    return true
end

local function term_move_up()
    return false
end

local function term_move_down()
    return false
end

local function term_complete()
    m.send(remote_id, remote_port, remote.messages.INPUT, currentInput .. '\t');
    return true
end

local function term_blink(toggle)
    return term.setCursorBlink(toggle)
end

local function term_insert(char)
    
    -- cursorX may not be at end
    if (term_at_end()) then
        currentInput = currentInput .. char
        io.write(char)
    else -- we need to INSERT
        local left = currentInput:sub(1, cursorX - 1)
        local right = char .. currentInput:sub(cursorX, currentInput:len())

        local cx, cy = term.getCursor();
        io.write(right);
        term.setCursor(cx + 1, cy);
        currentInput = left .. right;
    end
end

function handlers.key_down(_, byte, code, _)
    
    if (not currentInput) then
        return
    end

    term_blink(false)
    
    if code == keyboard.keys.back then
        if term_move_left() then
            term_delete()
        end
    elseif code == keyboard.keys.delete then
        term_delete()
    elseif code == keyboard.keys.left then
        term_move_left()
    elseif code == keyboard.keys.right then
        term_move_right()
    elseif code == keyboard.keys.home then
        term_move_home()
    elseif code == keyboard.keys["end"] then
        term_move_end()
    elseif code == keyboard.keys.up then
        term_move_up()
    elseif code == keyboard.keys.down then
        term_move_down()
    elseif code == keyboard.keys.tab then
        term_complete()
    elseif code == keyboard.keys.enter then
        term_blink(false)
        local tmpInput = currentInput;
        currentInput = nil; -- means input is ignored for a time
        cursorX = 1;
        m.send(remote_id, remote_port, remote.messages.INPUT, tmpInput .. '\n');
        
        if (tmpInput == "exit") then
            remote.onDisconnected();
        end
        
        io.write('\n');
    elseif not keyboard.isControl(byte) then
        if (remote.client_side_line_buffering) then
            term_insert(unicode.char(byte))
        else
            m.send(remote_id, remote_port, remote.messages.INPUT, unicode.char(byte));
        end
        cursorX = cursorX + 1
    end

    term_blink(true)
    term_blink(true) -- force toggle to caret
end

local function refreshPrompt()
    term_blink(true)
    local cx, cy = term.getCursor()
    --term.setCursor(1, cy)
    --term.clearLine()
    local p = prompt();
    io.write(p)
    --term.setCursor(p:len() + 1, cy)
    term.setCursor(cx + p:len(), cy)
end

token_handlers[remote.messages.PROMPT] = function(meta, newPromptString)
    remote_prompt = newPromptString or remote_prompt;
    refreshPrompt()
end

token_handlers[remote.messages.OUTPUT] = function(meta, textToDisplay, level)
    if (textToDisplay) then
        if (level == 0) then -- 0 is input, insert the text into our current input
            term_insert(textToDisplay);
        elseif (level == 1) then -- stdout only
            io.write(textToDisplay);
        elseif (level == 2) then -- stderr
            io.stderr:write(textToDisplay);
        elseif (level == 3) then -- beep, what to do with text?
            require("computer").beep()
        end
    end
end

token_handlers[remote.messages.ACCEPT] = function(meta, remotePort)
    if (remote_port) then
        io.stderr:write("host tried to specify a port twice")
    else
        remote_port = tonumber(remotePort)
        remote.onConnected(remote_id, remote_port)
    end
end

token_handlers[remote.messages.READ] = function(meta)
    currentInput = ""; -- allow input again
end

local local_port = nil
local function initiateConnection()
    io.write(string.format("connecting to %s\n", remote_id))
    m.send(remote_id, remote.DAEMON_PORT, remote.messages.CONNECT, remote_id, local_port);
end

local reason, ok;
remote_id, reason = pickSingleHost()

if (not remote_id) then
    io.stderr:write(reason .. '\n');
    return 1;
end

ok, local_port = pickLocalPort()
if (not ok) then
    print("Failed to open shell port: " .. tostring(local_port))
    return 1;
end

if (options.l) then -- list only
    os.exit()
end

-- request responder
remote.running = true;
initiateConnection();

-- main event loop which processes all events, or sleeps if there is nothing to do
while (remote.running) do
    
    if (remote_port and not remote.connected) then
        remote.onDisconnected();
        remote.running = false;
    else
        remote.handleNextEvent(handlers, token_handlers);
    end
end

closeLocalPort();

