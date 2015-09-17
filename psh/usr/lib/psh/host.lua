local component = require("component")
local event = require("event")
local shell = require("shell")
local ser = require("serialization")
local process = require("process")
local hijack = require("payo-lib/hijack")
local hintpath = require("payo-lib/hintpath")

local m = component.modem
assert(m)


local lib = {}
function lib.resume(host)
  lib.active_host = host

  -- hijack print (to use io.write)
  local function ioprint(a, b)
    io.write(tostring(a))
    if b then
      io.write('\t')
      io.write(tostring(b))
    end

    io.write('\n')
  end

  local original_print = print
  print = ioprint

  --hijack term read (to use io.read -- to use remote reader)
  hijack.load("term", "read", function(original, ...)
    -- TODO ... parameteres include history, dobreak, hint, pwchar, and filter
    -- support may come for those later, but it isn't really necessary
    return io.read("*L")
  end);

  --event.listen("pwd_changed", lib.pwd_changed)
  lib.pwd_changed(host.pwd)
end

function lib.yield()
  lib.active_host = nil
  print = original_print
  hijack.unload("term", "read")
  --event.ignore("pwd_changed", lib.pwd_changed)
end

function lib.pwd_changed(newPath)
  if newPath then
    os.setenv("PWD", newPath)
  end
end

function lib.updatePrompt(host)
  -- true, show prompt
  host.pshlib.log.debug("/usr/bin/psh/psh-reader.lua", host.remote_id, host.remote_port, true)
  loadfile("/usr/bin/psh/psh-reader.lua")(host.remote_id, host.remote_port, true)
end

function lib.pipeIt(host, command)
  return
    string.format("/usr/bin/psh/psh-reader.lua" .. " %s %i | ", host.remote_id, host.remote_port) ..
    command ..
    string.format(" | " .. "/usr/bin/psh/psh-writer.lua" .. " %s %i", host.remote_id, host.remote_port)
end

function lib.commandHint(host, command)
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
    result = hintpath.getMatchingPrograms(line)
  else -- just look normal files
    result = hintpath.getMatchingFiles(shell.resolve(partial or line))
  end
    
  if (#result > 0) then
    if (host.hinted == line) then
      remote.send_output("multiple results", 1);
    else
      host.hinted = line
      host.output(nil, 3); -- 3 is beep
    end
  else -- single result
    local result_partial = result[1];
    host.output(result_partial, 0);
  end
end

function lib.init(pshlib, host, hostArgs)
  -- at this point, we've already sent the ACCEPT back to the user

  host.pshlib = pshlib
  host.port = hostArgs.port
  host.remote_id = hostArgs.remote_id
  host.remote_port = hostArgs.remote_port
  host.send = function(...) return m.send(host.remote_id, host.remote_port, ...) end
  host.output = function(...) return host.send(pshlib.api.OUTPUT, ...) end
  host.pwd = os.getenv('HOME')
  host.hinted = nil
  host.buffer = ""

  -- tell user to update prompt
  lib.updatePrompt(host)

  host.tokens[pshlib.api.INPUT] = function(meta, input)
    if meta.remote_id ~= host.remote_id then
      host.pshlib.log.debug('ignoring input, wrong id')
      return false
    elseif meta.port ~= host.port then
      host.pshlib.log.debug('ignoring input, wrong local port')
      return false
    end

    host.buffer = host.buffer .. input
    local lengthAvailable = host.buffer:len()

    if (lengthAvailable == 0) then
      return true
    end

    local lastChar = host.buffer:sub(-1)
    
    -- if we get anything but tab, clear the last hint attempt if any
    if (lastChar ~= '\t') then
      host.hinted = nil
    end
    
    -- we only care about LINEs or tabs
    if (lastChar ~= '\n' and lastChar ~= '\t') then
      return true
    end
    
    local command = host.buffer:sub(1, lengthAvailable)
    host.buffer = ""
    command = command:sub(1, command:len() - 1) -- drop new line from buffer
    
    -- we don't care for the closing new line or tab in the command string
    if (lastChar == '\t') then
      lib.commandHint(host, command)
    elseif command == "exit" then
      pshlib.log.debug("disconnected: client closed connection\n")
      host.shutdown();
    else
      command = (command and (command:match('^%s*(.*%S)') or '')) or "";
            
      if (command:len() > 0) then
        local pipedToResponder = lib.pipeIt(host, command);
        
        pshlib.log.debug("piper: " .. command);
            
        local ok, reason = shell.execute(pipedToResponder);
            
        if not ok then
          host.output(reason .. '\n', 2)
        end
      end

      lib.updatePrompt(host)
      pshlib.log.debug("pipe dispatch completed")
    end

    return true
  end

  return true
end

return lib
