local lib = "payo-lib/stringutil"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

local tableutil = require("payo-lib/tableutil")
local ser = require("serialization").serialize

local function pwd_test(input, output)

  local result, reason = util.getParentDirectory(input)

  if (result ~= output) then
    local msg = string.format(
      "getParentDirectory(%s) ~= %s, but %s, because %s", 
      tostring(input), 
      tostring(output), 
      tostring(result), 
      tostring(reason));

    io.stderr:write(msg .. '\n')
  end
end

pwd_test("", nil)
pwd_test("/", nil)
pwd_test("a/", nil)
pwd_test("a/foo.bar", "a/")
pwd_test("a/b/foo.bar", "a/b/")
pwd_test("/init.lua", "/")
pwd_test("/boot/", "/")
pwd_test("/boot" , "/")
pwd_test("/a", "/")
pwd_test("/a/", "/")
pwd_test("/a/b", "/a/")
pwd_test("/a/b/", "/a/")
pwd_test("/////", nil)
pwd_test("/a/b/////////", "/a/")
pwd_test("/a.foo/b", "/a.foo/")
pwd_test("/a.foo/b.bar", "/a.foo/")
pwd_test("/a.foo", "/")
pwd_test("/a.foo/", "/")

local function split_test(output, ...)
  local actual, _, reason = util.split(...)

  local equal = tableutil.equal(actual, output);
  if (equal and not reason or not equal and reason) then
    local msg = string.format("split(%s)~=%s actual: %s because: %s", ser(table.pack(...)), ser(output), ser(actual), tostring(reason))
    io.stderr:write(msg .. '\n')
  end
end

split_test({})
split_test({}, "") -- no delim
split_test({"abc"}, "abc") -- no delim
split_test({}, "abc", ".") -- delim on . but do not keep it
split_test({'a','b','c'}, "abc", ".", true) -- delim on . and keep it
split_test({'a','c'}, 'abc', 'b') -- delim on b and do not keep it
split_test({'ab','c'}, 'abc', 'b', true) -- delim on b and keep it
split_test({'abc','def', ''}, 'abc;def;', ';', false, true) -- keep empty
split_test({'abc;','def;', ''}, 'abc;def;', ';', true, true)
split_test({';', 'abc;','def;', ''}, ';abc;def;', ';', true, true)
split_test({'abc','def'}, ';abc;def;', ';', false, false)
split_test({'abc','def'}, ';abc;def;', ';')

split_test({'ab','cd'}, "abcd", "..", true)

split_test({'ab', 'cd'}, "ab;;;;cd", ";", false, false)

split_test({'ab;', ';', ';', ';', 'cd'}, "ab;;;;cd", ";", true)
split_test({'ab;;;;', 'cd'}, "ab;;;;cd", ";+", true)

local function remove_trail_test(input, output)
  local actual, reason = util.removeTrailingSlash(input)

  local equal = actual == output
  if (equal and not reason or not equal and reason) then
    io.stderr:write("[remove trail] input:" .. ser(input) ..
      " expected:" .. ser(output) ..
      " actual:" .. ser(actual) ..
      " because:" .. tostring(reason) .. '\n')
  end
end

remove_trail_test("////", "")
remove_trail_test("/", "")
remove_trail_test("", "")
remove_trail_test("asdfasdf", "asdfasdf")
remove_trail_test("a/af/s", "a/af/s")
remove_trail_test("a/af/s/", "a/af/s")
remove_trail_test("a/af/s/a.out", "a/af/s/a.out")
remove_trail_test("a/af/s/a.out/////", "a/af/s/a.out")
remove_trail_test("/a/af/s/a.out/////", "/a/af/s/a.out")
remove_trail_test("/a/af/s/a.out", "/a/af/s/a.out")

local function add_trail_test(input, output)
  local actual, reason = util.addTrailingSlash(input)

  local equal = actual == output
  if (equal and not reason or not equal and reason) then
    io.stderr:write("[add trail] input:" .. ser(input) ..
      " expected:" .. ser(output) ..
      " actual:" .. ser(actual) ..
      " because:" .. tostring(reason) .. '\n')
  end
end

add_trail_test("////", "/")
add_trail_test("/", "/")
add_trail_test("", "/")
add_trail_test("asdfasdf", "asdfasdf/")
add_trail_test("a/af/s", "a/af/s/")
add_trail_test("a/af/s/", "a/af/s/")
add_trail_test("a/af/s/a.out", "a/af/s/a.out/")
add_trail_test("a/af/s/a.out/////", "a/af/s/a.out/")
add_trail_test("/a/af/s/a.out/////", "/a/af/s/a.out/")
add_trail_test("/a/af/s/a.out", "/a/af/s/a.out/")
