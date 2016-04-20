
local args = table.pack(...)
local i = 1
while i <= args.n do
  local t = args[i]
  if t == 'r' then
    io.write(io.read('*l') or '[nil]')
  elseif t == 'R' then
    io.write(io.read('*L') or '[nil]\n')
  elseif t == 'w' then
    i = i + 1
    io.write(args[i])
  elseif t == 'W' then
    i = i + 1
    io.write(args[i]..'\n')
  elseif t == 'e' then
    i = i + 1
    io.stderr:write(args[i])
  elseif t == 'E' then
    i = i + 1
    io.stderr:write(args[i]..'\n')
  elseif t == '-' then
    io.read()
  elseif t == 'c' then
    assert(false,'crashed')
  end
  i = i + 1
end
