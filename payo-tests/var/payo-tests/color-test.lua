local gpu = require("component").gpu
local bit32 = require("bit32")

local depth = tonumber((...)) or 8
if gpu.getDepth() ~= depth then
  local old = gpu.getDepth()
  gpu.setDepth(depth)
  depth = old
end

-- rgb
local reds = {0,0x33,0x66,0x99,0xCC,0xFF}
local greens = {0,0x24,0x49,0x6D,0x92,0xB6,0xDB,0xFF}
local blues = {0,0x40,0x80,0xC0,0xFF}

for _,red in ipairs(reds) do
  for _,green in ipairs(greens) do
    for _,blue in ipairs(blues) do
      local c = bit32.bor(bit32.lshift(red, 16), bit32.lshift(green, 8), blue)
      gpu.setBackground(c)
      io.write(' ')
    end
  end
  io.write("\27[m\n")
end

-- grays
for _,gray in ipairs({0x0F,0x1E,0x2D,0x3C,0x4B,0x5A,0x69,0x78,0x87,0x96,0xA5,0xB4,0xC3,0xD2,0xE1,0xF0}) do
  local c = bit32.bor(bit32.lshift(gray, 16), bit32.lshift(gray, 8), gray)
  gpu.setBackground(c)
  io.write(" ")
end
io.write("\27[m\n")

for fg=30,37 do
  for bg=40,47 do
    io.write(string.format("%s[%d;%dmX", string.char(0x1b), fg, bg))
  end
  io.write("\27[m\n")
end

for pfg=0,15 do
  for pbg=0,15 do
    gpu.setForeground(pfg, true)
    gpu.setBackground(pbg, true)
    io.write("P")
  end
  io.write("\27[m\n")
end
io.write("\27[m\n")

if gpu.getDepth() ~= depth then
  gpu.setDepth(depth)
end

