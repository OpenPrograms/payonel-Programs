local testutil = require("testutil")
local util = require("uuid")
local shell = require("shell")
local fs = require("filesystem")

-- we can also test mktmp here
local mktmp = loadfile(shell.resolve('mktmp','lua'))
if not mktmp then
  io.stderr:write("could not find mktmp for testing")
else
  local t,o = mktmp('-q')
  if not t then
    io.stderr:write("no tmp file created or returned: " .. tostring(o) .. '\n')
  end
  if not fs.exists(t) then
    io.stderr:write("mktmp did not create the tmp file it returned: " .. tostring(t) .. '\n')
  else
    fs.remove(t)
  end
end
