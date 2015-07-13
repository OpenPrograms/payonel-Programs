local component = require("component")
local fs = require("filesystem")
local shell = require("shell")
local text = require('text')

local dirs, options = shell.parse(...)
if #dirs == 0 then
  table.insert(dirs, ".")
end

local function no_decimal(number)

  local value = number;
  if (type(value) == type(nil)) then
    return "0";
  end

  if (type(value) == type(0)) then
    value = tostring(value)
  end

  if (type(value) ~= type("")) then
    return nil, "no_decimal: could not read number"
  end

  local dec = value:find("\\.")
  if (dec) then
    local cleaned = value:sub(1, dec - 1)
    local d = value:sub(dec + 1, value:len())
    d = d:gsub("0+$", "")
    if (d:len() > 0) then
      cleaned = cleaned .. "." .. d;
    end
    return clenaned;
  else
    return value;
  end
end

local function formatSize(size)
  if not options.h then
    return tostring(size)
  end
  local sizes = {"", "K", "M", "G"}
  local unit = 1
  local power = options.si and 1000 or 1024
  while size > power and unit < #sizes do
    unit = unit + 1
    size = size / power
  end

  local num = math.floor(size * 10) / 10;
  local clean = no_decimal(num);
    
  return clean .. sizes[unit]
end

local function formatOutput()
  return component.isAvailable("gpu") and io.output() == io.stdout
end

local day_names =
{
  "Sunday", -- indices are off-by-one
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
};

local month_names =
{
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
};

local function epoch_to_hdate(epochms)

  local ndate = os.date("*t", epochms / 1000);

  local result = {};

  result.sec = ndate.sec;
  result.min = ndate.min;
  result.hour = ndate.hour;
  result.day_name = day_names[ndate.wday + 1];
  result.day = ndate.day;
  result.month = month_names[ndate.month];
  result.year = ndate.year;

  return result;

end

local function pad_left_zero(txt)
  if (txt:len() == 2) then
    return txt;
  else
    return "0" .. txt
  end
end

local function display(item, fullpath)
  local t; -- d, f, or l
  if (fs.isDirectory(fullpath)) then
    t = 'd';
  elseif (fs.isLink(fullpath)) then
    t = 'l';
  else
    t = 'f';
  end
    
  local r = 'r'; -- openos doesn't support non-readable files. only root user
  local x = 'x'; -- openos doesn't have the concept of exe bit
    
  local w = fs.get(fullpath).isReadOnly() and '-' or 'w';
  local size = formatSize(fs.size(fullpath));

  local hdate = epoch_to_hdate(fs.lastModified(fullpath));
  local modDate = string.format("%s %+2s %+2s:%+2s",
    hdate.month:sub(1, 3),
    no_decimal(hdate.day),
    pad_left_zero(no_decimal(hdate.hour)),
    pad_left_zero(no_decimal(hdate.min)));
        
  local link_target = "";
    
  local bIsLink, linkPath = fs.isLink(fullpath);
  if (bIsLink) then
    link_target = string.format(" -> %s", linkPath);
  end
    
  io.write(string.format("%s-%s %+7s %s %s%s\n",
    t, r .. w,
    size,
    modDate,
    item,
    link_target));
end

io.output():setvbuf("line")
for i = 1, #dirs do
  local path = shell.resolve(dirs[i])
  if #dirs > 1 then
    if i > 1 then
      io.write("\n")
    end
    io.write(path, ":\n")
  end
    
  if (not fs.exists(path)) then
    io.stderr:write("cannot access " .. tostring(path) .. ": No such file or directory\n")
  else
    local list, reason = fs.list(path)
    if not list then
      io.stderr:write(reason .. "\n")
    else
      local function setColor(c)
        if formatOutput() and component.gpu.getForeground() ~= c then
          io.stdout:flush()
          component.gpu.setForeground(c)
        end
      end
      local lsd = {}
      local lsf = {}
      local m = 1
      for f in list do
        m = math.max(m, f:len() + 2)
        if f:sub(-1) == "/" then
          if options.p then
            table.insert(lsd, f)
          else
            table.insert(lsd, f:sub(1, -2))
          end
        else
          table.insert(lsf, f)
        end
      end
      table.sort(lsd)
      table.sort(lsf)
      setColor(0x66CCFF)
        
      local col = 1
      local columns = math.huge
      if formatOutput() then
        columns = math.max(1, math.floor((component.gpu.getResolution() - 1) / m))
      end
        
      for _, d in ipairs(lsd) do
        if options.a or d:sub(1, 1) ~= "." then
          if options.l or not formatOutput() or col % columns == 0 then
            display(d, fs.concat(path, d));
          else
            io.write(text.padRight(d, m))
          end
          col = col + 1
        end
      end
        
      for _, f in ipairs(lsf) do
        if fs.isLink(fs.concat(path, f)) then
          setColor(0xFFAA00)
        elseif f:sub(-4) == ".lua" then
          setColor(0x00FF00)
        else
          setColor(0xFFFFFF)
        end
        if options.a or f:sub(1, 1) ~= "." then
          if not formatOutput() then
            if options.l then
              display(f, fs.concat(path, f));
            else
              io.write(f .. "\n")
            end
          else
            if options.l then
              setColor(0xFFFFFF)
              display(f, fs.concat(path, f));
            else
              io.write(text.padRight(f, m))
              if col % columns == 0 then
                io.write("\n")
              end
            end
          end
          col = col + 1
        end
      end
        
      setColor(0xFFFFFF)
      if options.M then
        io.write("\n" .. tostring(#lsf) .. " File(s)")
        io.write("\n" .. tostring(#lsd) .. " Dir(s)")
      end
      if not options.l then
        io.write("\n")
      end
    end
  end
end

io.output():setvbuf("no")
io.output():flush()

