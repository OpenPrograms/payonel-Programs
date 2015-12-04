local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile('/lib/text.lua')

testutil.broken.all_pipes_tests()
if true then return 0 end

local pipes = dofile("/lib/pipes.lua")

local function pc(cmd, out)
  testutil.assert('pc:'..cmd, out, pipes.parseCommands(cmd))
end

pc("", true)
pc("echo", {{{"echo"}}})
pc("echo hi", {{{"echo", "hi"}}})
pc("echo 'hi'", {{{"echo", "\'hi\'"}}})
pc('echo hi "world"', {{{"echo", "hi", "\"world\""}}})
pc('echo test;echo hello|grep world>>result',
  {
    {{'echo','test'}},
    {{'echo','hello'},{'grep','world','>>','result'}},
  })
pc('echo test; echo hello |grep world >>result',
  {
    {{'echo','test'}},
    {{'echo','hello'},{'grep','world','>>','result'}},
  })

pc('|echo', false)
pc('|echo|', false)
pc('echo|', false)
pc('echo||echo', false)
pc(';', true)
pc(';;;;;;;', true)
pc(';echo ignore;echo hello|grep hello>>result',
  {
    {{'echo','ignore'}},
    {{'echo','hello'},{'grep','hello','>>','result'}}
  })

pc([[echo 'hi']],{{{'echo',[['hi']]}}})

local function pack(program, args, input, output, mode)
  return table.pack(program, args, input, output, mode)
end

local function resolve(cmd, out)
  testutil.assert('resolve:'..tostring(cmd), out, pipes.resolveCommands(cmd))
end

resolve('', true)
resolve(';;', true)
resolve('echo hi',{{pack('/bin/echo.lua',{'hi'},nil,nil,'write')}})
resolve(';;echo hi',{{pack('/bin/echo.lua',{'hi'},nil,nil,'write')}})
resolve(';echo hi|grep world>data;echo done',
  {
    {
      pack('/bin/echo.lua',{'hi'},nil,nil,'write'),
      pack(shell.resolve('grep', 'lua'), {'world'}, nil, 'data', 'write')
    },
    {
      pack('/bin/echo.lua',{'done'},nil,nil,'write')
    }
  })

