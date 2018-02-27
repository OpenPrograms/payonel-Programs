local testutil = require("testutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = require("shell")
local sh = require("sh")
local event = require("event")
local thread = require("thread")
local computer = require("computer")

testutil.assert_files(os.getenv("_"), os.getenv("_"))
testutil.assert_process_output("echo hi", "hi\n")
testutil.no_sleep = true

local touch = loadfile(shell.resolve("touch", "lua"))
if not touch then
  io.stderr:write("bash-test requires touch which could not be found\n")
  return
end

local function execute(...)
  return sh.execute(nil, ...)
end

local mktmp = loadfile(shell.resolve("mktmp", "lua"))
if not mktmp then
  io.stderr:write("bash-test requires mktmp which could not be found\n")
  return
end

local function hint(line, ex, cursor)
  local results = sh.hintHandler(line, cursor or (line:len() + 1))
  local detail = '`'..line..'`'.."=>"..ser(results)..'<and not>'..ser(ex)
  
  if testutil.assert("result type", "table", type(results), detail) and
     testutil.assert("result size", #ex, #results, detail) then

    for _,v in ipairs(results) do
      for j,w in ipairs(ex) do
        if v == string.format("%s%s", line, w) then
          table.remove(ex, j)
          break
        end
      end
    end

    testutil.assert("wrong results", true, not next(ex), detail)
  end
end

hint("", {})
hint("a", {"ddress ", "lias ", "ll-tests ", "rgutil-test "})
hint("d", {"ate ", "f ", "mesg ", "u "})
hint("cd", {" "})

hint("/b", {"in", "oot"})

-- test files can come after redirects and equal sign
hint("foo asdf --file=s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf >s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf >>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 1>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 1>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 2>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf 2>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("foo asdf <s", {"h-test.lua", "hell-test.lua", "low-test.lua"})

-- now retest that program are listed after statement separators
hint("foo asdf;d", {"ate ", "f ", "mesg ", "u "})
hint("foo asdf|d", {"ate ", "f ", "mesg ", "u "})
hint("foo asdf||d", {"ate ", "f ", "mesg ", "u "})
hint("foo asdf&&d", {"ate ", "f ", "mesg ", "u "})

-- confirm quotes are checked
hint("foo asdf';'c", {})
hint("foo asdf\"|\"c", {})
hint("foo asdf'||'c", {})
hint("foo asdf'&&'c", {})

-- and retest that files are searched
hint("echo hello&&foo asdf --file=s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf >s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf >>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 1>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 1>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 2>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf 2>>s", {"h-test.lua", "hell-test.lua", "low-test.lua"})
hint("echo hello&&foo asdf <s", {"h-test.lua", "hell-test.lua", "low-test.lua"})

local tmp_path = mktmp('-d','-q')

local test_depth = 10
hint("cd " .. tmp_path:sub(1, test_depth), {tmp_path:sub(test_depth+1) .. '/'})

execute("mkdir " .. tmp_path .. '/' .. 'a')

hint("cd " .. tmp_path .. '/', {"a/"})
local test_dir = os.getenv("PWD")
execute("cd " .. tmp_path .. '/a')
hint("cd ../", {"a/"})
execute("cd ..")
hint(tmp_path, {"/"})
execute("mkdir " .. tmp_path .. '/' .. 'a2')
hint("cd a", {"", "2"})

hint("cd ../.." .. tmp_path .. '/', {"a", "a2"})

execute("cd a")
hint("cd ", {})

hint("mo", {"re ", "unt "})
hint("/bin/mo", {"re.lua", "unt.lua"})
hint("mo ", {})
hint("/bin/mo ", {})
execute("cd ..")
hint("cd a/", {})
hint("cd ../ ", {"a", "a2"})
hint(tmp_path, {"/"})
hint(tmp_path..'/a/', {})
execute("touch .c")
hint('cat '..tmp_path..'/.',{"c "})
hint('./.',{'c '})
execute("mkdir .d")
hint('cd .', {'c', 'd'})
fs.remove(tmp_path..'/.c')
hint('cd .', {'d/'}) -- with / because it is the only one

execute("cd .d")
hint(' ', {})
hint(';', {})
hint('; ', {})
execute("touch foo.lua")
hint(' ca ', {'foo.lua '})
hint('  ca ', {'foo.lua '})
execute("touch bar\\ baz.lua")
hint(' ', {})
hint(';', {})
hint('; ', {})
hint('cat bar', {'\\ baz.lua '})
hint('cat f', {'oo.lua '})
hint('cat bar\\ ', {'baz.lua '})
hint('cat bar ', {'bar\\ baz.lua', 'foo.lua'})
hint('cat bar\\', {})

execute("cd " .. test_dir)
fs.remove(tmp_path..'/.d')

fs.remove(tmp_path..'/a')
fs.remove(tmp_path)

local function hint2(line, ex, cursor)
  local results = sh.hintHandler(line, cursor or (line:len() + 1))
  local detail = line.."=>"..ser(results)..'<and not>'..ser(ex)
  
  if testutil.assert("result type", "table", type(results), detail) then

     for _,v in ipairs(results) do
      local removed = false
      for j,w in ipairs(ex) do
        if v == string.format("%s%s", line, w) then
          table.remove(ex, j)
          removed = true
          break
        end
      end
      if not removed then
        ex[#ex + 1] = v
      end
    end

    testutil.assert("wrong results", true, not next(ex), detail)

  end
end

local tilde_support = false

execute("cd") -- home
hint2("cat .", {"shrc "})
hint2("cat ./.", {"shrc "})
if tilde_support then hint2("cat ~/.", {"shrc "}) end
hint2("cat /home/.", {"shrc "})
execute("cd " .. test_dir)

execute("cd /")
hint2("cat ./home/.", {"shrc "})
if tilde_support then hint2("cat ~/.", {"shrc "}) end
hint2("cat /home/.", {"shrc "})
execute("cd " .. test_dir)

execute("cd") -- home
hint2("cat < .", {"shrc "})
hint2("cat < ./.", {"shrc "})
if tilde_support then hint2("cat < ~/.", {"shrc "}) end
hint2("cat < /home/.", {"shrc "})
execute("cd " .. test_dir)

execute("cd /")
hint2("cat < ./home/.", {"shrc "})
hint2("cat < /home/.", {"shrc "})
if tilde_support then hint2("cat < ~/.", {"shrc "}) end
hint2("cat < /home/.", {"shrc "})
execute("cd " .. test_dir)

local function create_event_watch(event_name, event_ret, exp_calls)
  local watch =
  {
    called = 0,
    name = event_name,
  }
  watch.callback = function (ename)
    testutil.assert("event watch called too many times", exp_calls > watch.called, true, string.format("%d > %d", exp_calls, watch.called))
    watch.called = watch.called + 1
    if event_name then
      testutil.assert("event watch called with wrong event", event_name, ename)
    end
    return event_ret
  end

  watch.id = event.listen(watch.name, watch.callback)

  return watch
end

-- listen tests


local watch = create_event_watch("test_event", false, 1)
testutil.assert("listen", not not watch.id, true)
testutil.assert("cannot subscribe twice", event.listen(watch.name, watch.callback), false)
event.push(watch.name)
event.pull(watch.name)
testutil.assert("watch called after 1st push", 1, watch.called)
event.push(watch.name)
event.pull(watch.name)
testutil.assert("watch called after 2nd push", 1, watch.called)
testutil.assert("ignore should be false because watch self unsubd", event.ignore(watch.name, watch.callback), false)

watch = create_event_watch("test_event", true, 2)
testutil.assert("listen", not not watch.id, true)
event.push(watch.name)
event.pull(watch.name)
testutil.assert("watch called after 1st push", 1, watch.called)
event.push(watch.name)
event.pull(watch.name)
testutil.assert("watch called after 1st push", 2, watch.called)
testutil.assert("ignore should be true because watch rets true", event.ignore(watch.name, watch.callback), true)
event.push(watch.name)
event.pull(watch.name)
testutil.assert("watch called after 3rd push", 2, watch.called)
testutil.assert("ignore should be false because watch removed already", event.ignore(watch.name, watch.callback), false)

--timer tests
-- interval: number
-- callback: function
-- times: number, nil [nil is forever]
local function create_event_timer(interval, times, ret)
  local timer =
  {
    called = 0,
  }
  timer.callback = function()
    timer.called = timer.called + 1
    return ret
  end
  timer.id = event.timer(interval, timer.callback, times)
  return timer
end

local timer = create_event_timer(0, nil, true)
testutil.assert("a. timer remove", event.cancel(timer.id), true)

timer = create_event_timer(0, 1, true)
testutil.assert("a. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("a. timer count", 1, timer.called)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("a. timer count should not exceed 1", 1, timer.called)
testutil.assert("a. timer remove", event.cancel(timer.id), false)

timer = create_event_timer(0, 2, true)
testutil.assert("b. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("b. timer count", 2, timer.called)
testutil.assert("b. timer remove", event.cancel(timer.id), false)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("b. timer count should not exceed 2", 2, timer.called)

timer = create_event_timer(0, 2, true)
testutil.assert("c. timer created", not not timer.id, true)
testutil.assert("c. timer remove", event.cancel(timer.id), true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("c. timer count", 0, timer.called)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("c. timer count should not exceed 0", 0, timer.called)
-----------------------------------------------------------------------------------
timer = create_event_timer(0, nil, true)
testutil.assert("d. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("d. timer count", 1, timer.called)
testutil.assert("d. timer remove", event.cancel(timer.id), false)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("d. timer count should not exceed count", 1, timer.called)

timer = create_event_timer(0, nil, false)
testutil.assert("e. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("e. timer count", 1, timer.called)
testutil.assert("e. timer remove", event.cancel(timer.id), false)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("e. timer count should not exceed 1", 1, timer.called)

timer = create_event_timer(1000, nil, true)
testutil.assert("f. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("f. timer count", 0, timer.called)
testutil.assert("f. timer remove", event.cancel(timer.id), true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("f. timer count should not exceed 0", 0, timer.called)

timer = create_event_timer(.5, nil, true)
testutil.assert("g. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar")
testutil.assert("g. [this might fail, it depends on actual test runtime] timer count", 0, timer.called)
local start_time = computer.uptime()
while computer.uptime() - start_time < 1 and timer.called == 0 do
  os.sleep()
end
testutil.assert("g. [this might fail, it depends on actual test runtime] timer count", 1, timer.called)
testutil.assert("g. timer remove", event.cancel(timer.id), false)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("g. [runtime dependant] timer count should not exceed 0", 1, timer.called)

timer = create_event_timer(.1, nil, true)
testutil.assert("h. timer created", not not timer.id, true)
start_time = computer.uptime()
while computer.uptime() - start_time < 1 and timer.called == 0 do
  os.sleep()
end
testutil.assert("h. [this might fail, it depends on actual test runtime] timer count", 1, timer.called)
testutil.assert("h. timer remove", event.cancel(timer.id), false)
os.sleep(0)
testutil.assert("h. [runtime dependant] timer count should not exceed count", 1, timer.called)

-----------------------------------------------------------------------------------

timer = create_event_timer(0, math.huge, true)
testutil.assert("g2. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("g2. timer count", 2, timer.called)
testutil.assert("g2. timer remove", event.cancel(timer.id), true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("g2. timer count should not exceed count", 2, timer.called)

timer = create_event_timer(0, math.huge, false)
testutil.assert("h2. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("h2. timer count", 1, timer.called)
testutil.assert("h2. timer remove", event.cancel(timer.id), false)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("h2. timer count should not exceed 1", 1, timer.called)

timer = create_event_timer(1000, math.huge, true)
testutil.assert("i. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("i. timer count", 0, timer.called)
testutil.assert("i. timer remove", event.cancel(timer.id), true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("i. timer count should not exceed 0", 0, timer.called)

timer = create_event_timer(.5, math.huge, true)
testutil.assert("j. timer created", not not timer.id, true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("j. [this might fail, it depends on actual test runtime] timer count", 0, timer.called)
os.sleep(0)
testutil.assert("j. [this might fail, it depends on actual test runtime] timer count", 0, timer.called)
testutil.assert("j. timer remove", event.cancel(timer.id), true)
event.push("foobar")
event.pull("foobar") -- force the timer to fire
testutil.assert("j. [runtime dependant] timer count should not exceed 0", 0, timer.called)

timer = create_event_timer(.1, math.huge, true)
testutil.assert("k. timer created", not not timer.id, true)
start_time = computer.uptime()
while computer.uptime() - start_time < 1 and timer.called <= 5 do
  os.sleep()
end
local count = timer.called
local cancel_ret = event.cancel(timer.id)
testutil.assert("k. [this might fail, it depends on actual test runtime] timer count", count >= 5, true, count)
testutil.assert("k. timer remove", cancel_ret, true)
os.sleep(0)
testutil.assert("k. timer count should not exceed count", count, timer.called)

timer = create_event_timer(.1, math.huge, false)
testutil.assert("L. timer created", not not timer.id, true)
start_time = computer.uptime()
while computer.uptime() - start_time < 1 and timer.called == 0 do
  os.sleep()
end
cancel_ret = event.cancel(timer.id)
testutil.assert("L. [this might fail, it depends on actual test runtime] timer count", 1 <= timer.called, true, timer.called)
testutil.assert("L. timer remove", cancel_ret, false)
local before_sleep_L_count = timer.called
os.sleep(0)
testutil.assert("L. [runtime dependant] timer count should not exceed count", before_sleep_L_count, timer.called)

-------------------
--a thread that event pulls on an event should not block other coroutines
local event_received
local t_a = thread.create(function()
  event_received = event.pull(.1, "custom_a")
  event.push("custom_b")
end)
event.push("custom_a")
local event_pushed = event.pull(.1,"custom_b")
testutil.assert("coroutine status", t_a:status(), "dead")
testutil.assert("threaded event stack", "custom_a", event_received)
testutil.assert("main event stack", "custom_b", event_pushed)

testutil.no_sleep = nil
