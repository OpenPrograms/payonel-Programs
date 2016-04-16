local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")
local term = require("term")

print("testing term blink")

io.write("this should blink for 1 second")
term.pull(1, "adsfasdfA")
print()

io.write("this should not blink for 1 second")
term.setCursorBlink(false)
term.pull(1, "adsfasdfA")
print()

io.write("this should blink for input [ENTER]: ")
term.read({blink=true})

io.write("this should not blink for input [ENTER]: ")
term.read()

term.setCursorBlink(true)
io.write("this should blink for input [ENTER]: ")
term.read()

io.write("this should not blink for input [ENTER]: ")
term.read({blink=false})

io.write("this should blink for .5 seconds")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
print()

term.setCursorBlink(false)
io.write("this should not blink for .5 seconds")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
term.pull(.1,"asdfasdfasdf")
print()

print("time to blink the screen")
print("moving with blinkyness on")
term.setCursorBlink(true)
for i=1,200 do
  io.write("x")
  term.pull(.01,"adsfasdf")
end
print()

print("moving with blinkyness off")
term.setCursorBlink(false)
for i=1,200 do
  io.write("-")
  term.pull(.01,"adsfasdf")
end
print()

print("shell should be blinking after this test finishes")
term.setCursorBlink(false)
