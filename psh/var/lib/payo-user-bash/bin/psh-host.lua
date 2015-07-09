local component = require("component");
local event = require("event")
local shell = require("shell")
local ser = require("serialization");
local process = require("process");
local hijack = require("hijack");
local remote = require("remote");

-- hijack print (to use io.write)
local function ioprint(a, b)
    io.write(tostring(a))
    if (b) then 
        io.write('\t')
        io.write(tostring(b))
    end

    io.write('\n')
end
local original_print = print;
print = ioprint

--hijack term read (to use io.read -- to use remote reader)
hijack.load("term", "read", function(original, ...)
    -- TODO ... includes history, dobreak, hint, pwchar, and filter
    -- support may come for those later, but it isn't really necessary
    return io.read("*L");
end);

local args, options = shell.parse(...)

-- takes two args, the remote id and the remote port
local local_port = args[1] and tonumber(args[1]) or nil;
local remote_id = args[2]
local remote_port = args[3] and tonumber(args[3]) or nil;
local remote_reader_file_path = shell.resolve(remote.tools.reader, "lua");
    
if (#args ~= 3 or not local_port or not remote_id or not remote_port) then
    io.stderr:write("Usage: remote-shell-host local_port remote_id remote_port")
    return 1;
end

local m = component.modem;

if (not m) then
    io.stderr:write("missing a modem");
    return 1;
end

if (not m.isOpen(local_port)) then
    io.stderr:write("host expects local port to already be open")
    return 1;
end

local function updatePrompt()
    -- true, show prompt
    loadfile(remote_reader_file_path)(remote_id, remote_port, true);
end

local function pipeIt(command)
    return
        string.format(remote.tools.reader .. " %s %i | ", remote_id, remote_port) ..
        command ..
        string.format(" | " .. remote.tools.writer .. " %s %i", remote_id, remote_port);
end

local function getMatchingPrograms(baseName)
  local result = {}
  -- TODO only matching files with .lua extension for now, might want to
  --      extend this to other extensions at some point? env var? file attrs?
  if not baseName or #baseName == 0 then
    baseName = "^(.*)%.lua$"
  else
    baseName = "^(" .. baseName .. ".*)%.lua$"
  end
  for basePath in string.gmatch(os.getenv("PATH"), "[^:]+") do
    for file in fs.list(basePath) do
      local match = file:match(baseName)
      if match then
        table.insert(result, match)
      end
    end
  end
  return result
end

local function getMatchingFiles(baseName)
  local result, basePath = {}
  -- note: we strip the trailing / to make it easier to navigate through
  -- directories using tab completion (since entering the / will then serve
  -- as the intention to go into the currently hinted one).
  -- if we have a directory but no trailing slash there may be alternatives
  -- on the same level, so don't look inside that directory... (cont.)
  if fs.isDirectory(baseName) and baseName:sub(-1) == "/" then
    basePath = baseName
    baseName = "^(.-)/?$"
  else
    basePath = fs.path(baseName) or "/"
    baseName = "^(" .. fs.name(baseName) .. ".-)/?$"
  end
  for file in fs.list(basePath) do
    local match = file:match(baseName)
    if match then
      table.insert(result, fs.concat(basePath, match))
    end
  end
  -- (cont.) but if there's only one match and it's a directory, *then* we
  -- do want to add the trailing slash here.
  if #result == 1 and fs.isDirectory(result[1]) then
    result[1] = result[1] .. "/"
  end
  return result
end

local hinted = nil;
local function commandHint(command)
    -- TODO hints are WIP
    if true then return nil end
    
    local line = unicode.sub(command, 1, cursor - 1)

    if not line or #line < 1 then
        return nil
    end
    
    local result
    local prefix, partial = string.match(line, "^(.+%s)(.+)$")
    local searchInPath = not prefix and not line:find("/")
    if searchInPath then
        -- first part and no path, look for programs in the $PATH
        result = getMatchingPrograms(line)
    else -- just look normal files
        result = getMatchingFiles(shell.resolve(partial or line))
    end
    
    if (#result > 0) then
        if (hinted == line) then
            remote.send_output("multiple results", 1);
        else
            hinted = line
            remote.send_output(nil, 3); -- 3 is beep
        end
    else -- single result
        local result_partial = result[1];
        remote.send_output(result_partial, 0)
    end
end

-- let client know we're ready now
updatePrompt()

local handlers = {};
local token_handlers = {}

function handlers.pwd_changed(oldPath, newPath)
    if (newPath) then
        os.setenv("PWD", newPath)
    end
end

handlers[remote.messages.INPUT_SIGNAL] = function(lastChar, lengthAvailable)
    
    if (lengthAvailable == 0) then
        return;
    end
    
    -- if we get anything but tab, clear the last hint attempt if any
    if (lastChar ~= '\t') then
        hinted = nil
    end
    
    -- we only care about LINEs or tabs
    if (lastChar ~= '\n' and lastChar ~= '\t') then
        return -- ignore this
    end
    
    local command = remote.read(lengthAvailable);
    command = command:sub(1, command:len() - 1);
    
    -- we don't care for the closing new line or tab in the command string
    if (lastChar == '\t') then
        return commandHint(command)
    elseif (command == "exit") then
        io.stderr:write("disconnected: client closed connection\n")
        remote.onDisconnected();
    else
        command = (command and (command:match('^%s*(.*%S)') or '')) or "";
            
        if (command:len() > 0) then
            local pipedToResponder = pipeIt(command);
        
            print("piper: " .. command);
            
            local ok, reason = shell.execute(pipedToResponder);
            
            if (not ok) then
                remote.send_output(reason .. '\n', 2);
            end
            
            -- incase there was a pwd_changed, we should respond to it NOW
            -- flush all pendning events
            remote.flushEvents({pwd_changed = handlers.pwd_changed}, token_handlers);
        end

        updatePrompt()
        print("pipe dispatch completed")
    end
end

-- The main event handler as function to separate eventID from the remaining arguments

remote.onConnected(remote_id, remote_port);

while (remote.connected) do
    remote.handleNextEvent(handlers, token_handlers);
end

-- fix hijacks
print = original_print
hijack.unload("term", "read");
