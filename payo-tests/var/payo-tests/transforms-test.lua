local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")

local function insert_all(dst, src, ex)
  --testutil.assert("insert_all:"..ser(dst)..'+'..ser(src), ex, text.insert_all(dst, src))
end

insert_all({},{},{})
insert_all({},{'a'},{'a'})
insert_all({},{'a','b'},{'a','b'})
insert_all({'a'},{'b','c'},{'a','b','c'})
insert_all({'a','b'},{'c','d'},{'a','b','c','d'})
insert_all({'a','b'},{'c'},{'a','b','c'})
insert_all({'a','b'},{},{'a','b'})

local function sub(p1,p2,p3,e1)
--  testutil.assert(
--    "sub("..type(p1).."):"..ser(p1)..'['..ser(p2)..','..ser(p3)..']',
--    e1, text.sub(p1, p2, p3))
end

sub({'a','b','c'}, 0,  1,{'a'        })
sub({'a','b','c'}, 1,  1,{'a'        })
sub({'a','b','c'}, 1,  2,{'a','b'    })
sub({'a','b','c'}, 1,  3,{'a','b','c'})
sub({'a','b','c'}, 1,  4,{'a','b','c'})
sub({'a','b','c'}, 2,  2,{    'b'    })
sub({'a','b','c'}, 2,  3,{    'b','c'})
sub({'a','b','c'}, 2,  4,{    'b','c'})
sub({'a','b','c'}, 3,  3,{        'c'})
sub({'a','b','c'}, 3,  4,{        'c'})
sub({'a','b','c'}, 4,  4,{           })
sub({'a','b','c'}, 1,nil,{'a','b','c'})
sub({'a','b','c'}, 2,nil,{    'b','c'})
sub({'a','b','c'}, 3,nil,{        'c'})
sub({'a','b','c'}, 4,nil,{           })
sub({'a','b','c'},-1,nil,{        'c'})
sub({'a','b','c'},-2,nil,{    'b','c'})
sub({'a','b','c'},-3,nil,{'a','b','c'})
sub({'a','b','c'},-4,nil,{'a','b','c'})
sub({'a','b','c'},-1, -2,{           })
sub({'a','b','c'},-1, -1,{        'c'})
sub({'a','b','c'},-1,  0,{           })
sub({'a','b','c'},-2, -3,{           })
sub({'a','b','c'},-2, -2,{    'b'    })
sub({'a','b','c'},-2, -1,{    'b','c'})
sub({'a','b','c'},-2,  0,{           })
sub({'a','b','c'},-3, -4,{           })
sub({'a','b','c'},-3, -3,{'a'        })
sub({'a','b','c'},-3, -2,{'a','b'    })
sub({'a','b','c'},-3, -1,{'a','b','c'})
sub({'a','b','c'},-3, -0,{           })
sub({'a','b','c'},-4, -4,{           })
sub({'a','b','c'},-4, -3,{'a'        })
sub({'a','b','c'},-4, -2,{'a','b'    })
sub({'a','b','c'},-4, -1,{'a','b','c'})
sub({'a','b','c'},-4, -0,{           })
sub({           }, 1,  2,{           })

local function find(p1,p2,p3,e1,e2)
--  testutil.assert(
--    "find("..type(p1).."):"..ser(p1)..'['..ser(p2)..','..ser(p3)..']',
--    {e1,e2}, {text.find(p1, p2, p3)})
end

find({'a','b','c'},{'a'        },nil,  1, 1)
find({'a','b','c'},{    'b'    },nil,  2, 2)
find({'a','b','c'},{        'c'},nil,  3, 3)
find({'a','b','c'},{'a','b'    },nil,  1, 2)
find({'a','b','c'},{    'b','c'},nil,  2, 3)
find({'a','b','c'},{'a','b','c'},nil,  1, 3)
find({'a','b','c'},{'a'        },  1,  1, 1)
find({'a','b','c'},{    'b'    },  2,  2, 2)
find({'a','b','c'},{        'c'},  3,  3, 3)
find({'a','b','c'},{'a','b'    },  1,  1, 2)
find({'a','b','c'},{    'b','c'},  2,  2, 3)
find({'a','b','c'},{'a','b','c'},  1,  1, 3)
find({'a','b','c'},{'a'        },  2,nil)
find({'a','b','c'},{    'b'    },  3,nil)
find({'a','b','c'},{        'c'},  4,nil)
find({'a','b','c'},{        'd'},  1,nil)
find({'a','b','c'},{'a'        }, -3,  1, 1)
find({'a','b','c'},{'a'        },  0,  1, 1)
find({'a','b','c'},{    'b'    }, -2,  2, 2)
find({'a','b','c'},{        'c'}, -1,  3, 3)
find({'a','b','c'},{'a','b'    }, -3,  1, 2)
find({'a','b','c'},{    'b','c'}, -2,  2, 3)
find({'a','b','c'},{'a','b','c'}, -3,  1, 3)
find({'a','b','c'},{'a'        }, -2,nil)
find({'a','b','c'},{    'b'    }, -1,nil)
find({'a','b','c'},{        'd'}, -4,nil)
find({           },{'a'        },nil,nil)

find({'a','b','c'},{'a','b','c'},  1,  1, 3)
find({'a','b','c'},{'a','b','c'},  2,nil)
find({'a','b','c'},{'a','b','c','d'})
find({'a','b','c'},{'a','b','c','d'},-1)
find({'a','b','c'},{    'b','c'},  2,  2, 3)
find({'a','b','c'},{    'b','c'},  3,nil)
find({'a','b','c'},{           },  1,1,0)
find({'a','bc','d'},{'abc'},nil,nil,nil)
find({'a','bc','d'},{'ab','c'},nil,nil,nil)
find({'a','bc','d'},{'b','c'},nil,nil,nil)
find({'aa'},{'a'},nil,nil,nil)
find({'a'},{'aa'},nil,nil,nil)
find({'a','a'},{'aa'},nil,nil,nil)
find({'ab','ab','c'},{'ab','c'},nil,2,3)

local function splitBy(input, delims, ex, dropDelims)
--  local special = dropDelims and '(drop)' or ''
--  testutil.assert("split"..special..":"..ser(input)..'-'..ser(delims), ex, 
--    text.splitBy(input,
--      function(c, pi)
--        return delims[pi][1] == c
--      end, dropDelims, #delims))
end

splitBy({'a','b','c'}, {{'a'}}, {{'a'},{'b','c'}})
splitBy({'a','b','c'}, {{'b'}}, {{'a'},{'b'},{'c'}})
splitBy({'a','b','c'}, {{'c'}}, {{'a','b'},{'c'}})
splitBy({'a','b','c'}, {{'d'}}, {{'a','b','c'}})
splitBy({'a','b','c'}, {{'a'},{'b'},{'c'}}, {{'a'},{'b'},{'c'}})
splitBy({'a','b','c'}, {{'b'},{'a'},{'c'}}, {{'a'},{'b'},{'c'}})
splitBy({'a','b','c'}, {{'c'},{'b'},{'a'}}, {{'a'},{'b'},{'c'}})
splitBy({'a','bb','c'}, {{'b'},{'bb'}}, {{'a'},{'bb'},{'c'}})
splitBy({'a','bb','c'}, {{'bb'},{'b'}}, {{'a'},{'bb'},{'c'}})
splitBy({'a','bb','c','b','d'}, {{'bb'},{'b'}}, {{'a'},{'bb'},{'c'},{'b'},{'d'}})
splitBy({'b','a','bb','c','d','bb'}, {{'bb'},{'b'}}, {{'b'},{'a'},{'bb'},{'c','d'},{'bb'}})
splitBy({'a','b','c'}, {{'b'}}, {{'a'},{'c'}}, true)

splitBy({'a','b','c'}, {}, {{'a','b','c'}}, true)
splitBy({'a','b','c'}, {{'b','c'},{'b'}}, {{'a'}}, true)
splitBy({'a','b','c'}, {{'b'},{'b','c'}}, {{'a'},{'c'}}, true)

splitBy('', {';'}, {}, true)
splitBy(';', {';'}, {}, true)
splitBy(';;;;;;;', {';'}, {}, true)

local function foreach(input, fn, output)
--  testutil.assert('foreach:'..ser(input),output,text.foreach(input, fn))
end

foreach({'a','aaa','aa'}, function(s) return s:len() end, {1,3,2})
foreach({'a','aa','aaa'}, function(s) return s..'!' end, {'a!','aa!','aaa!'})
foreach({'a','','c'}, function(s) if s:len() > 0 then return s end end, {'a','c'})
foreach({}, function(s) assert(false) end, {})
