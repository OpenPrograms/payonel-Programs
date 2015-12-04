local testutil = require("testutil")
local util = testutil.load("payo-lib/stringutil")
local tableutil = testutil.load("payo-lib/tableutil")

local ser = require("serialization").serialize

local function pwd_test(input, output)
  testutil.bump(true)
  local result, reason = util.getParentDirectory(input)

  if (result ~= output) then
    local msg = string.format(
      "getParentDirectory(%s) ~= %s, but %s, because %s", 
      tostring(input), 
      tostring(output), 
      tostring(result), 
      tostring(reason))

    io.stderr:write(msg .. '\n')
  end
end

pwd_test("", nil)
pwd_test("/", nil)
pwd_test("a/", nil)
pwd_test("a/foo.bar", "a/")
pwd_test(".a/foo.bar", ".a/")
pwd_test(".a.d/foo.bar", ".a.d/")
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
  testutil.bump(true)
  local actual, _, reason = util.split(...)

  local equal = tableutil.equal(actual, output)
  if (equal and reason or not equal and not reason) then
    local msg = string.format("split(%s)~=%s actual: %s because: %s", ser(table.pack(...)), ser(output), ser(actual), tostring(reason))
    io.stderr:write(msg .. '\n')
  end
end

testutil.assert("split", nil, util.split()) -- gives a reason for nil, thus split_test doesn't really work on this nil check
split_test({""}, "") -- no delim
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
  testutil.bump(true)
  local actual, reason = util.removeTrailingSlash(input)

  local equal = actual == output
  if (equal and reason or not equal and not reason) then
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
  testutil.bump(true)
  local actual, reason = util.addTrailingSlash(input)

  local equal = actual == output
  if (equal and reason or not equal and not reason) then
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

local function file_test(input, output)
  testutil.bump(true)
  local result, reason = util.getFileName(input)

  if (result ~= output) then
    local msg = string.format(
      "getFileName(%s) ~= %s, but %s, because %s", 
      tostring(input), 
      tostring(output), 
      tostring(result), 
      tostring(reason))

    io.stderr:write(msg .. '\n')
  end
end

file_test(nil, nil)
file_test("", "")
file_test("/", "")
file_test("a/", "")
file_test("a/.", ".")
file_test("a/.b", ".b")
file_test(".a/.b", ".b")
file_test("./.a/.b", ".b")
file_test("./.a/b", "b")
file_test("a/foo.bar", "foo.bar")
file_test("a/b/foo.bar", "foo.bar")
file_test("/init.lua", "init.lua")
file_test("/boot/", "")
file_test("/boot" , "boot")
file_test("/a", "a")
file_test("/a/", "")
file_test("/a/b", "b")
file_test("/a/b/", "")
file_test("/////", "")
file_test("/a/b/////////", "")
file_test("/a.foo/b", "b")
file_test("/a.foo/b.bar", "b.bar")
file_test("/a.foo", "a.foo")
file_test("/a.foo/", "")
