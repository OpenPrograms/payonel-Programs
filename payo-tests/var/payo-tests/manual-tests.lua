local term = require("term")

print("testing term blink")

term.setCursorBlink(true)
io.write("this should blink for 1 second")
term.pull(1, "adsfasdfA")
print()

io.write("this should not blink for 1 second")
term.setCursorBlink(false)
term.pull(1, "adsfasdfA")
print()

io.write("this should blink for input [ENTER]: ")
term.setCursorBlink(true)
term.read()

io.write("this should not blink for input [ENTER]: ")
term.setCursorBlink(false)
term.read()

print("time to blink the screen")
print("moving with blinkyness on")
term.setCursorBlink(true)
for _=1,100 do
  io.write("x")
  term.pull(0,"adsfasdf")
end
print()

print("moving with blinkyness off")
term.setCursorBlink(false)
for _=1,100 do
  io.write("-")
  term.pull(0,"adsfasdf")
end
print()

print("shell should be blinking after this test finishes")
term.setCursorBlink(true)
