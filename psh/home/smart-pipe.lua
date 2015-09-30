local shell = require("shell")
local fs = require("filesystem")
local tutil = require("payo-lib/tableutil")
local ser = require("serialization")
local process = require("process")

local sh_path = shell.resolve("sh", "lua")
assert(sh_path and fs.exists(sh_path), 'failed to locate sh path')
local sh = loadfile(sh_path)
local s = ser.serialize

local args = "/home/piper | /home/piper"
local command = sh_path
local env = _G
--io.write = function(...) io.stderr:write("|"..s(table.pack(...)).."|") end
--io.write(pipe)
--io.read(pipe)
--local pipe = require("buffer").new("rw", memoryStream.new())
--pipe:setvbuf("no")

local pipe = require("buffer").new("rw",
{
  read = function(self, format)
    print('\nmy chlid process is asking for input('..format..'): ')
    local continuation = table.pack(coroutine.yield())
    --print(s(table.pack(coroutine.yield())))
    local line = s(continuation)
    print('\nthank you, sending back ['..line..'] to child process')
    return line..'\n'
  end,

  write = function(...)
    error("write")
  end,

  close = function(...)
  end,
})
pipe:setvbuf("no")

local function init()
  print("init")

  local bad = function()
    return io.input(pipe)
  end

  local result, why = xpcall(bad, function(err) return debug.traceback(err) end)
  if not result then
    io.stderr:write(tostring(why):gsub('%\n', '\n') .. '\n')
  end

  print("init complete")
end

local name = "smart-pipe-wrapper"

local cor = process.load(command, nil, init, name)

local result = table.pack(coroutine.resume(cor, nil, args))
print(s(result))

pipe:close()

--local token_run = true
--while token_run and coroutine.status(cor) ~= "dead" do
--  result = table.pack(coroutine.resume(cor, "hi"))
--  if coroutine.status(threads[i]) ~= "dead" then
--    args = table.pack(pcall(event.pull, table.unpack(result, 2, result.n)))
--  end
--end
--if pipes[i] then
--  pcall(pipes[i].close, pipes[i])
--end

--sh(env, "echo hi")

--io.write = env.io.write
