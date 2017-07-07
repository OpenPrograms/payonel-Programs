local term = require("term")
local process = require("process")

io.write("\27","7") -- save cursor position and color

local width, height = term.getViewport()
-- fill screen with X
term.write(("X"):rep(width * height))

for yindex=1,height do
  term.gpu().set(1, yindex, ("="):rep(width))
end

local function set_window(window)
  term.bind(term.gpu(), window)
  process.info().data.window = window
end

-- open input line window
local input_window = term.internal.open(2, height - 4, width - 4, 1)
-- open output window
local output_window = term.internal.open(3, 3, width - 6, 10)

-- fill output window with O
set_window(output_window)
term.write(("O"):rep(width * height))

-- clear input line
set_window(input_window)
-- term.clearLine()
term.write((" "):rep(width - 6))
term.setCursor(1, 1)

-- loop
while true do
  set_window(input_window)
  local data = term.read({nowrap=true})
  if not data or data == "quit\n" then
    break
  end
  set_window(output_window)
  term.write(data)
end

set_window(nil)
io.write("\27","8") -- restore cursor position
