local util = require("payo-lib/argutil")

local args, options, reason = util.parse(table.pack(...), {{'n'},{}});

for i = 1, #args do
  if i > 1 then
    io.write(" ")
  end
  io.write(args[i])
end

if (not options.n) then
  io.write('\n')
end

