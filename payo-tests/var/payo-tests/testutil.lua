local util = {};
local ser = require("serialization").serialize
local tutil = require("payo-lib/tableutil");
local shell = require("shell")
local fs = require("filesystem")
local process = require("process")
local unicode = require("unicode")
local sh = require("sh")

local mktmp = loadfile(shell.resolve('mktmp','lua'))
if (not mktmp) then
  io.stderr:write("testutils requires mktmp which could not be found\n")
  return false
end

util.asserts = 0
util.assert_max = 1
util.total_tests_run = 0
util.last_time = 0
util.timeout = 1

function util.bump(ok)
  local next_time = os.time()
  if next_time - util.last_time > util.timeout then
    util.last_time = next_time
    os.sleep(0)
    io.write('.')
  end

  util.total_tests_run = util.total_tests_run + 1
  if ok == true then return true end

  util.asserts = util.asserts + 1
  if util.asserts >= util.assert_max then
    io.stderr:write("Too many asserts\n",debug.traceback())
    os.exit(1)
  end
  return false
end

function util.load(lib)
  package.loaded[lib] = nil;
  local result = require(lib);

  if (not result) then
    error("failed to load library: " .. result);
    return nil; -- shouldn't happen after an error
  end
  return result;
end

util.broken_handler = {}
util.broken_handler.__index = function(table_, key_)
  return function(...) end
end

util.broken = {}
setmetatable(util.broken, util.broken_handler)

function util.assert(msg, expected, actual, detail)
  local etype = type(expected);
  local atype = type(actual);
  local detail_msg = detail and string.format(". detail: %s", ser(detail)) or ""

  if (etype ~= atype) then
    io.stderr:write(string.format("%s: mismatch type, %s vs %s. expected value: |%s|. %s\n", msg, etype, atype, ser(expected), detail_msg));
    return util.bump()
  end
  
  -- both same type

  if (etype == nil) then -- both nil
    return true;
  end

  local matching = true;
  if (etype == type({})) then
    if (not tutil.equal(expected, actual)) then
      matching = false;
    end
  elseif (expected ~= actual) then
    matching = false;
  end

  if (not matching) then
    io.stderr:write(string.format("%s: %s ~= %s. %s\n", msg, ser(actual), ser(expected), detail_msg));
  end

  return util.bump(matching)
end

function util.assert_files(file_a, file_b)
  util.bump(true)
  local path_a = shell.resolve(file_a)
  local path_b = shell.resolve(file_b)

  local a_data = io.lines(path_a, "*a")()
  local b_data = io.lines(path_b, "*a")()

  util.assert("path a missing", fs.exists(path_a), true)
  util.assert("path b missing", fs.exists(path_b), true)
  util.assert("path a is dir", fs.isDirectory(path_a), false, path_a)
  util.assert("path b is dir", fs.isDirectory(path_b), false, path_b)
  util.assert("content mismatch", a_data, b_data)
end

function util.run_cmd(cmds, files, meta)
  local chdir = shell.setWorkingDirectory
  local function execute(...)
    return require("sh").execute(nil, ...)
  end

  meta = meta or {}
  local exit_code = meta.exit_code
  local tmp_dir_path = mktmp('-d','-q')
  local home = shell.getWorkingDirectory()
  chdir(tmp_dir_path)

  local stdouts = {}
  local stderrs = {}

  local stdout = setmetatable({tty=false, write = function(self, ...)
    for _,v in ipairs({...}) do
      if #v > 0 then table.insert(stdouts,v) end
    end
  end}, {__index = io.stdout})

  local stderr = setmetatable({tty=false, write = function(self, ...)
    for _,v in ipairs({...}) do
      if #v > 0 then table.insert(stderrs,v) end
    end
  end}, {__index = io.stderr})

  for _,c in ipairs(cmds) do
    if type(c) == "string" then
      local fp = function()execute(c)end
      local proc = process.load(fp,nil,nil,"cmd_test:"..c)
      process.info(proc).data.io[1] = stdout
      process.info(proc).data.io[2] = stderr
      while coroutine.status(proc) ~= "dead" do
        coroutine.resume(proc)
      end
    else
      c()
    end
  end

  local actual = {}
  local scan = nil
  scan = function(d)
    for it in fs.list(d) do
      local path = (d .. '/' .. it):gsub("/+", "/")
      local key = path:sub(unicode.len(tmp_dir_path)+1):gsub("/*$",""):gsub("^/*", "")
      path = shell.resolve(path)
      local isLink, linkPath = fs.isLink(path)
      path = fs.realPath(path)
      if isLink then
        actual[key] = {linkPath}
      elseif fs.isDirectory(path) then
        actual[key] = true
        scan(path)
      else
        local fh = io.open(path)
        actual[key] = fh:read("*a")
        fh:close()
      end
    end
  end
  
  chdir(tmp_dir_path)
  scan(tmp_dir_path)
  chdir(home)
  fs.remove(tmp_dir_path)

  local details = ' cmds:' .. ser(cmds,true) .. '\n' .. ser(meta,true) .. '\n'
  
  for name,contents in pairs(actual) do
    if not files[name] then
      io.stderr:write("missing file: [", name, "]\ndetails:", details)
      util.bump()
    else
      util.assert("files did not match: " .. name, files[name], contents, ser(contents) .. details)
    end
    files[name]=nil
  end

  util.assert("missing files", {}, files, ser(actual) .. details)
  util.assert("exit code", sh.getLastExitCode(), sh.internal.command_result_as_code(exit_code), details)

  local function output_check(captures, pattern)
    if type(pattern) == "string" then
      pattern = {pattern}
      captures = {table.concat(captures)}
    end
    for _,c in ipairs(captures) do
      if pattern and pattern[_] then
        util.assert("output capture mismatch pos["..tostring(_).."]", not not c:match(pattern[_]), true,
        string.format("[%d][%s]: captured output:[%s]", _, details, c)) 
      else
        util.assert("unexpected output", nil, c, details .. c)
      end
    end
  end

  output_check(stdouts, meta[1])
  output_check(stderrs, meta[2])
end

function util.assert_process_output(cmd, expected_output)
  util.bump(true)
  local piped_file = mktmp('-q')
  local full_cmd = cmd .. " > " .. piped_file
  os.execute(full_cmd)
  assert(fs.exists(piped_file))
  local piped_handle = io.open(piped_file)
  local piped_data = piped_handle:read("*a")
  piped_handle:close()
  fs.remove(piped_file)

  if (piped_data ~= expected_output) then
    io.stderr:write("failed command: ",full_cmd,"\n")
    io.stderr:write(string.format("lengths: %i, %i:", piped_data:len(), 
      expected_output:len()))
    io.stderr:write(string.format("%s", piped_data:gsub("\n", "\\n")))
    io.stderr:write("[does not equal]")
    io.stderr:write(string.format("%s\n", expected_output:gsub("\n", "\\n")))
    util.bump()
  end
end

return util;