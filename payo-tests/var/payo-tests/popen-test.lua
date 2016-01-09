local fs = require("filesystem")
local pipes = require("pipes")
local term = require("term")
local process = require("process")
local tx = require("transforms")
local text = require("text")
local testutil = require("testutil")

local tests={}
tests[1]=true
tests[2]=true
tests[3]=true
tests[4]=true
tests[5]=true

local function handler()
  return require("process").info().data.coroutine_handler
end

local function d(s)
  --term.debug(type(s),s)
end

if tests[1] then
  local p, reason = pipes.popen("./iohelper.lua W first w second | ./iohelper R R", "r")
  if not p then print(reason) return end
  
  testutil.assert('*a','first\nsecond', p:read('*a'))
  testutil.assert('empty read',nil, p:read())
  testutil.assert('empty read',nil, p:read())
  testutil.assert('empty read',nil, p:read())
  
  p:close()
end

if tests[2] then

local result_buffer = ''
local function add_result(r)
  --print(r)
  result_buffer = result_buffer .. text.trim(r)
end

local pco = pipes.internal.create(function()
  local p1, p2, p3, p4

  local function stats()
    return '' or string.format(("%10s"):rep(5).." %d",
      coroutine.status(handler().stack[1]),
      coroutine.status(p1),
      coroutine.status(p2),
      coroutine.status(p3),
      coroutine.status(p4),
      #handler().stack)
  end

  p1 = coroutine.create(function()
    add_result("   p1 start ".. stats())
    coroutine.resume(p2)
    add_result("     p1 mid ".. stats())
    coroutine.resume(p2)
    add_result("     p1 end ".. stats())
    add_result(select(2,coroutine.resume(p2)))
  end)

  p2 = coroutine.create(function()
    coroutine.resume(p1)
    add_result("   p2 start ".. stats())
    coroutine.resume(p3)
    add_result("   p2 yield ".. stats())
    coroutine.yield()
    add_result("     p2 mid ".. stats())
    coroutine.resume(p3)
    add_result("     p2 end ".. stats())
  end)

  p3 = coroutine.create(function()
    add_result("   p3 start ".. stats())
    coroutine.resume(p4)
    add_result(" p3 resumed ".. stats())
    coroutine.resume(p5)
    add_result("+p3 resumed ".. stats())
    handler().yield_all()
    add_result("     p3 mid ".. stats())
    coroutine.resume(p4)
    add_result("     p3 end ".. stats())
  end)

  p4 = coroutine.create(function()
    add_result("   p4 start ".. stats())
    add_result("super yield ".. stats())
    handler().yield_all("a","b","c")
    add_result(" post super ".. stats())
    coroutine.yield()
    add_result("     p4 end ".. stats())
  end)

  p5 = coroutine.create(function()
    add_result("   p5 start ".. stats())
    coroutine.yield()
    add_result("   p5   end ".. stats())
  end)

  add_result('pco start')
  coroutine.resume(p1)
  add_result('pco mid')
  coroutine.resume(p4)
  add_result('pco end')
end)
  
  while #pco.stack > 0 do
    add_result('main loop')
    pco.resume_all()
  end

  testutil.assert('pco',
  'main loop' ..
  'pco start' ..
  'p1 start' ..
  'p2 start' ..
  'p3 start' ..
  'p4 start' ..
  'super yield' ..
  'main loop' ..
  'post super' ..
  'p3 resumed' ..
  'p5 start' ..
  '+p3 resumed' ..
  'main loop' ..
  'p3 mid' ..
  'p4 end' ..
  'p3 end' ..
  'p2 yield' ..
  'p1 mid' ..
  'p2 mid' ..
  'p2 end' ..
  'p1 end' ..
  'cannot resume dead coroutine' ..
  'pco mid' ..
  'pco end'
  ,result_buffer)

end

if tests[3] then
  p,r=io.popen("./iohelper.lua W first;echo 2|grep 4;./iohelper.lua W second W third W fourth","r")
  if not p then
    testutil.assert('popen',p,"failed to create p")
  else

    testutil.assert('1st *l','first',p:read("*l")) --3
    testutil.assert('2nd *l','second',p:read("*l")) --3
    testutil.assert('last *L','third\n',p:read("*L")) --2\n
    p:close()
    testutil.assert('after close 1',nil,p:read()) --nil
    testutil.assert('after close 2',nil,p:read()) --nil
  end
end

if tests[4] then

  local buffer = nil
  local function get_buffer()
    local result = buffer
    buffer = nil
    return result
  end
  local function redirect()
  end

  p=io.popen("./iohelper.lua R R | ./iohelper.lua R W mid R W done","w")
  process.info(p.stream.pm.threads[2]).data.io[1] = 
  {
    write = function(this, value)
      buffer = (buffer or '') .. value
    end
  }

  testutil.assert('test 4 1',nil,get_buffer())
  p:write("write 1\n")
  testutil.assert('test 4 2','write 1\nmid\n',get_buffer())
  testutil.assert('test 4 3',nil,get_buffer())
  p:write("write 2")
  testutil.assert('test 4 4',nil,get_buffer())
  testutil.assert('test 4 5',nil,get_buffer())
  p:close() -- on close, flush buffer (was waiting for new line)
  testutil.assert('test 4 6','write 2done\n',get_buffer())
end

if tests[5] then
  testutil.assert('crash not caught',true,pcall(function()
    local c = io.popen("./iohelper.lua c") -- testing scripts that crash
    c:close()
  end))
end
