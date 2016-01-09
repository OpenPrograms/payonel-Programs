
local args = table.pack(...)
local i = 1
while i <= args.n do
  local t = args[i]
  if t == 'r' then
    io.write(io.read('*l'))
  elseif t == 'R' then
    io.write(io.read('*L'))
  elseif t == 'w' then
    i = i + 1
    io.write(args[i])
  elseif t == 'W' then
    i = i + 1
    io.write(args[i]..'\n')
  elseif t == '-' then
    io.read()
  elseif t == 'c' then
    assert(false,'crashed')
  end
  i = i + 1
end
