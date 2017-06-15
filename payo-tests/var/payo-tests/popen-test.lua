local fs = require("filesystem")
local process = require("process")
local text = require("text")
local testutil = require("testutil")
local shell = require("shell")
local sh = require("sh")
local pipes = require("pipes")
local thread = require("thread")
local event = require("event")

local tests={}
tests[1]=false
tests[2]=true
tests[3]=true
tests[4]=true
tests[5]=true

local function handler()
  return require("process").info().data.coroutine_handler
end

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

if tests[1] then
  local p = pipes.popen("./iohelper.lua W first w second | ./iohelper R R", "r")
  testutil.assert("p failed", true, not not p)
  if p then
    testutil.assert('*a','first\nsecond', p:read('*a'))
    testutil.assert('empty read',nil, p:read())
    testutil.assert('empty read',nil, p:read())
    testutil.assert('empty read',nil, p:read())

    p:close()
  end
end

if tests[2] then

local result_buffer = ''
local function add_result(r)
  --print(r)
  result_buffer = result_buffer .. text.trim(r)
end

local pco_thread = pipes.createCoroutineStack(function()
  local p1, p2, p3, p4, p5

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

  while true do
    local root = pco_thread.root or pco_thread.stack[1]
    local resume = pco_thread.root and pco_thread.resume or function(_, ...) return pco_thread.resume_all(...) end
    if pco_thread.top and not pco_thread.top() or pco_thread.root and pco_thread.status(pco_thread.root) == "dead" then
      break
    end
    add_result('main loop')
    resume(root)
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

local p
if tests[3] then
  p = io.popen("./iohelper.lua W first;echo 2|grep 4;./iohelper.lua W second W third W fourth","r")
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
  local function redirect(_, value)
    buffer = (buffer or '') .. value
  end

  p=io.popen("./iohelper.lua R R | ./iohelper.lua R W mid R W done","w")
  process.info(p.stream.pm.threads[2]).data.io[1] = {write = redirect}

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

local grep_tmp_file = mktmp('-q')
local file = io.open(grep_tmp_file, "w")
file:write("hi\n") -- whole word and whole line
file:write("hi world\n")
file:write(" hi \n") -- whole word
file:write("not a match\n")
file:write("high\n") -- not whole word
file:write("hi foo hi bar\n")
file:close()

local function grep(pattern, options, result)
  local label = pattern..':'..options..':'..table.concat(result,'|')
  local g = io.popen("grep "..pattern.." "..grep_tmp_file.." "..options, "r")
  while true do
    local line = g:read("*l")
    if not line then break end
    local next = table.remove(result, 1)
    testutil.assert("grep "..label, line, next)
  end
  g:close()
  testutil.assert("not all grep results found "..label, #result, 0)
end

grep("hi", "", {"hi", "hi world", " hi ", "high", "hi foo hi bar"})
grep("hi", "-w", {"hi", "hi world", " hi ", "hi foo hi bar"})
grep("hi", "-wt", {"hi", "hi world", "hi", "hi foo hi bar"})
grep("hI", "-wti", {"hi", "hi world", "hi", "hi foo hi bar"})
grep("hI", "-wtiv", {"not a match", "high"})
grep("hI", "-wix", {"hi"})
grep("hI", "-wixv", {"hi world", " hi ", "not a match", "high", "hi foo hi bar"})
grep("hI", "-wiv", {"not a match", "high"})
grep("hI", "-ion", {"1:hi", "2:hi", "3:hi", "5:hi", "6:hi", "6:hi"})

fs.remove(grep_tmp_file)

-- read line testing

local function execute(...)
  return sh.execute(nil, ...)
end

local function rtest(cmd, files, ex_out)
  local clean_dir = mktmp('-d','-q')
  execute("cd " .. clean_dir)

  local sub = io.popen(cmd)
  local out = sub:read("*a")
  sub:close()

  local file_data = {}

  for n in pairs(files) do
    local f = io.open(clean_dir .. "/" .. n, "r")
    if not f then
      file_data[n] = false
    else
      file_data[n] = f:read("*a")
      f:close()
      fs.remove(clean_dir .. "/" .. n)
    end
  end

  local junk_files = fs.list(clean_dir)
  while true do
    local junk = junk_files()
    if not junk then break end
    file_data[junk] = false
    fs.remove(clean_dir .. "/" .. junk)
  end

  execute("cd " .. os.getenv("OLDPWD"))
  execute("rmdir " .. clean_dir)

  for k,v in pairs(file_data) do
    local expected_data = files[k]
    if v == false then
      if expected_data then
        testutil.assert("rtest:"..cmd, k, "file missing")
      else
        testutil.assert("rtest:"..cmd, k, "file should not exist")
      end
    else
      testutil.assert("rtest:"..cmd, expected_data, v)
    end
  end

  testutil.assert("rtest:"..cmd.." leak", ex_out or "", out)
end

rtest("echo hi", {}, "hi\n")
rtest("echo hi>a", {a="hi\n"})
rtest("echo hi>>a", {a="hi\n"})
rtest("echo hi>>a;echo hi>>a", {a="hi\nhi\n"})
rtest("echo hi>>a;echo hi>a", {a="hi\n"})
rtest("echo hi>a;echo hi>a", {a="hi\n"})
local ioh = "/var/payo-tests/iohelper.lua "
rtest(ioh.."w a|"..ioh.."r>b", {b="a"})
rtest(ioh.."W a|"..ioh.."R|"..ioh.." r>b", {b="a"})
rtest(ioh.."W a|"..ioh.."R w j|"..ioh.." R r>b", {b="a\nj"})
rtest("echo stuff>a;"..ioh.." R<a>b;echo j>>b", {a="stuff\n",b="stuff\nj\n"})
rtest("echo hello > a|"..ioh.." r", {a="hello\n"}, "[nil]")
rtest(ioh.."w hello > a|"..ioh.." r", {a="hello"}, "[nil]")
rtest(ioh.."w 1 > a|"..ioh.."w 2 > b|"..ioh.."w 3 > c", {a="1",b="2",c="3"}, "")
rtest("echo hello>a|echo goodbye", {a="hello\n"}, "goodbye\n")
rtest("echo hello>a>b|echo goodbye", {a="",b="hello\n"}, "goodbye\n")
rtest(ioh.." W foo E bar E baz 2>&1 >/dev/null | grep baz > result", {result="baz\n"}, "")
rtest(ioh.." W foo E bar E baz 3>result 2>&1 >&3 | grep baz > grep_result", {result="foo\n", grep_result="baz\n"}, "")

-- thread testing
--tty.setCursorBlink(false)
local event_on_error = event.onError
local event_error = ""
event.onError = function(msg)
  event_error = event_error .. msg
end
local buffer = ""
local function print_buffer(txt)
  buffer = buffer .. txt
end
print_buffer("p start")
local reader = thread.create(function()
  print_buffer("reader start")
  os.exit(1)
  print_buffer("reader done")
end)
print_buffer("p end")
reader:join()
testutil.assert("thread abort test", "p startreader startp end", buffer)
testutil.assert("thread sleep message", "", event_error)
event_error = ""

buffer = ""
testutil.assert("thread waitForAny join", true, thread.create(function()
  local cleanup_thread = thread.create(function()
    event.pull("custom_interrupted")
    print_buffer("cleaning up resources")
  end)

  local main_thread = thread.create(function()
    print_buffer("main program")
    print_buffer("input: ")
    event.pull("never")
    print_buffer("X")
  end)

  event.push("custom_interrupted")
  thread.waitForAny({cleanup_thread, main_thread})
  os.exit(1)
end):join(1))
testutil.assert("thread waitForAny test", "main programinput: cleaning up resources", buffer)
testutil.assert("thread sleep message", "", event_error)
event_error = ""

buffer = ""
thread.create(function()
  print_buffer("a")
  local cleanup_thread = thread.create(function()
    print_buffer("b")
    event.pull("never")
    print_buffer("c")
  end)

  print_buffer("d")
  local main_thread = thread.create(function()
    print_buffer("e")
    error("die")
    print_buffer("f")
  end)

  print_buffer("g")
  thread.waitForAny({cleanup_thread, main_thread})
  print_buffer("h")
  os.exit(1)
end):join(1)
testutil.assert("thread abort test", "abdegh", buffer)
testutil.assert("thread abort message", true, not not event_error:find("popen%-test.lua:...: die"), event_error)
event_error = ""

buffer = ""
thread.create(function()
  print_buffer("a")
  local cleanup_thread = thread.create(function()
    print_buffer("b")
    event.pull("never")
    print_buffer("c")
  end)

  print_buffer("d")
  local main_thread = thread.create(function()
    print_buffer("e")
    event.pull("custom_interrupted")
    print_buffer("f")
    error("die")
    print_buffer("g")
  end)

  print_buffer("h")
  event.push("custom_interrupted")
  thread.waitForAny({cleanup_thread, main_thread})
  print_buffer("i")
  os.exit(1)
end):join(1)
testutil.assert("thread pull and abort test", "abdehfi", buffer)
testutil.assert("thread pull and abort message", true, not not event_error:find("popen%-test.lua:...: die"), event_error)
event_error = ""

buffer = ""
thread.create(function()
  print_buffer("a")
  thread.create(function()
    print_buffer("b")
    os.sleep()
    print_buffer("c")
  end)
  print_buffer("d")
end):join(1)
testutil.assert("thread sleep test", "abdc", buffer)
testutil.assert("thread sleep message", "", event_error)
event_error = ""

buffer = ""
thread.create(function()
  print_buffer("a")
  os.sleep()
  print_buffer("b")
  thread.create(function()
    print_buffer("c")
    os.sleep()
    print_buffer("d")
    thread.create(function()
      print_buffer("e")
      os.sleep()
      print_buffer("f")
      thread.create(function()
        print_buffer("g1")
      end)
      print_buffer("h")
      os.sleep()
      thread.create(function()
        print_buffer("g2")
      end)
      print_buffer("i")
    end)
    print_buffer("j")
    os.sleep()
    print_buffer("k")
  end)
  print_buffer("l")
  os.sleep()
  print_buffer("m")
end):join(2)
testutil.assert("thread sleepy sleepy test", "abcldejmfg1hkg2i", buffer)

buffer = ""
thread.create(function()
  print_buffer("a")
  os.sleep()
  print_buffer("b")
  thread.create(function()
    print_buffer("c")
    os.sleep()
    print_buffer("d")
    thread.create(function()
      print_buffer("e")
      os.sleep()
      print_buffer("f")
      thread.create(function()
        print_buffer("g1")
      end)
      print_buffer("h")
      os.sleep()
      thread.create(function()
        print_buffer("g2")
      end)
      print_buffer("i")
    end):join()
    print_buffer("j")
    os.sleep()
    print_buffer("k")
  end)
  print_buffer("l")
  os.sleep()
  print_buffer("m")
end):join(2)
testutil.assert("thread sleepy join sleepy test", "abcldemfg1hg2ijk", buffer)

event.onError = event_on_error
