local testutil = require("testutil");
local util = testutil.load("payo-lib/argutil");
local tutil = testutil.load("payo-lib/tableutil");
local ser = require("serialization").serialize
local fs = require("filesystem")
local shell = dofile("/lib/shell.lua")
local text = dofile("/lib/text.lua")
local tx = dofile("/lib/transforms.lua")

local function cut(input, offset, last)
  local c = tx.internal.table_view(input, offset, last)

  testutil.assert('cut len', #input, #c)
  for i=1,#input do
    local ex
    if i >= offset and i <= last then
      ex = input[i]
    end
      
    testutil.assert('cut i++', ex, c[i])
  end
  local ipairs_count = 0
  for i,e in ipairs(c) do
    ipairs_count = ipairs_count + 1
    testutil.assert('cut ipairs', input[i], c[i])
  end
  testutil.assert('ipairs count', ipairs_count, last - offset + 1)
  testutil.assert('cut keys check', input.foo, c.foo)
  local pairs_count = 0
  for k,v in pairs(c) do
    pairs_count = pairs_count + 1
    local ex
    if type(k) ~= 'number' or (k >= offset and k <= last) then
      ex = input[k]
    end
    testutil.assert('cut pairs', ex, v)
  end
  testutil.assert('pairs count', pairs_count, last - offset + 1 + 1)
end

cut({1,2,3,4,5,['foo']='bar'}, 2, 4)

local function insert_all(dst, src, ex)
  testutil.assert("insert_all:"..ser(dst)..'+'..ser(src), ex, tx.concat(dst, src))
end

insert_all({},{},{})
insert_all({},{'a'},{'a'})
insert_all({},{'a','b'},{'a','b'})
insert_all({'a'},{'b','c'},{'a','b','c'})
insert_all({'a','b'},{'c','d'},{'a','b','c','d'})
insert_all({'a','b'},{'c'},{'a','b','c'})
insert_all({'a','b'},{},{'a','b'})
insert_all({'a','b'},table.pack('c'),{'a','b','c',n=3})
insert_all({'a','b'},{[2]='c',n=2},{'a','b',[4]='c',n=4})
insert_all({n=1},{'a'},{[2]='a',n=2})

local function sub(p1,p2,p3,e1)
  testutil.assert(
    "sub("..type(p1).."):"..ser(p1)..'['..ser(p2)..','..ser(p3)..']',
    e1, tx.sub(p1, p2, p3))
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

local function find(p1,p2,p3,p4,e1,e2)
  testutil.assert(
    "find("..type(p1).."):"..ser(p1)..'['..ser(p2)..','..ser(p3)..','..ser(p4)..']',
    {e1,e2}, {tx.find(p1, p2, p3, p4)})
end

find({'a','b','c'},{'a'        },nil,nil,  1, 1)
find({'a','b','c'},{    'b'    },nil,nil,  2, 2)
find({'a','b','c'},{        'c'},nil,nil,  3, 3)
find({'a','b','c'},{'a','b'    },nil,nil,  1, 2)
find({'a','b','c'},{    'b','c'},nil,nil,  2, 3)
find({'a','b','c'},{'a','b','c'},nil,nil,  1, 3)
find({'a','b','c'},{'a'        },  1,nil,  1, 1)
find({'a','b','c'},{    'b'    },  2,nil,  2, 2)
find({'a','b','c'},{        'c'},  3,nil,  3, 3)
find({'a','b','c'},{'a','b'    },  1,nil,  1, 2)
find({'a','b','c'},{    'b','c'},  2,nil,  2, 3)
find({'a','b','c'},{'a','b','c'},  1,nil,  1, 3)
find({'a','b','c'},{'a'        },  2,nil,nil)
find({'a','b','c'},{    'b'    },  3,nil,nil)
find({'a','b','c'},{        'c'},  4,nil,nil)
find({'a','b','c'},{        'd'},  1,nil,nil)
find({'a','b','c'},{'a'        }, -3,nil,  1, 1)
find({'a','b','c'},{'a'        },  0,nil,  1, 1)
find({'a','b','c'},{    'b'    }, -2,nil,  2, 2)
find({'a','b','c'},{        'c'}, -1,nil,  3, 3)
find({'a','b','c'},{'a','b'    }, -3,nil,  1, 2)
find({'a','b','c'},{    'b','c'}, -2,nil,  2, 3)
find({'a','b','c'},{'a','b','c'}, -3,nil,  1, 3)
find({'a','b','c'},{'a'        }, -2,nil,nil)
find({'a','b','c'},{    'b'    }, -1,nil,nil)
find({'a','b','c'},{        'd'}, -4,nil,nil)
find({           },{'a'        },nil,nil,nil)
find({'a','b','c'}  ,{'a','b','c'}    ,  1,nil,  1, 3)
find({'a','b','c'}  ,{'a','b','c'}    ,  2,nil,nil)
find({'a','b','c'}  ,{'a','b','c','d'})
find({'a','b','c'}  ,{'a','b','c','d'},-1)
find({'a','b','c'}  ,{    'b','c'}    ,  2,nil,  2,  3)
find({'a','b','c'}  ,{    'b','c'}    ,  3,nil,nil)
find({'a','b','c'}  ,{           }    ,  1,nil,  1,  0)
find({'a','bc','d'} ,{'abc'}          ,nil,nil,nil,nil)
find({'a','bc','d'} ,{'ab','c'}       ,nil,nil,nil,nil)
find({'a','bc','d'} ,{'b','c'}        ,nil,nil,nil,nil)
find({'aa'}         ,{'a'}            ,nil,nil,nil,nil)
find({'a'}          ,{'aa'}           ,nil,nil,nil,nil)
find({'a','a'}      ,{'aa'}           ,nil,nil,nil,nil)
find({'ab','ab','c'},{'ab','c'}       ,nil,nil,  2,  3)

find({'a','b','c'},{'a'        },  1, -3,  1, 1)
find({'a','b','c'},{    'b'    },  2, -2,  2, 2)
find({'a','b','c'},{    'b'    },  1,  1,  nil)
find({'a','b','c'},{        'c'},  1,  2,  nil)
find({'a','b','c'},{'a','b'    },  1,  2,  1, 2)
find({'a','b','c'},{'a','b'    },  1,  3,  1, 2)
find({'a','b','c'},{'a','b'    },  1,  1,  nil)
find({'a','b','c'},{    'b','c'},  1,  3,  2, 3)
find({'a','b','c'},{    'b','c'},  1,  2,  nil)

local function begins(input, set, offset, last, ex)
  testutil.assert('begins:'..ser(input)..ser(set)..ser(offset)..','..ser(last),ex,tx.begins(input, set, offset, last))
end

begins({}, {}, nil, nil,true)
begins({}, {'a'}, nil, nil,false)
begins({}, {}, 1, nil,true)
begins({'a','b'},{'a'},nil,nil,true)
begins({'a','b'},{'a'},0,nil,false) --sub(offset, offset+#value-1)=>sub(0,0)=>{}
begins({'a','b'},{'a'},1,nil,true)
begins({'a','b'},{'a'},2,nil,false)
begins({'a','b'},{'b'},2,nil,true)
begins({'a','b'},{'b'},1,nil,false)
begins({'a','b'},{'a','b'},1,nil,true)
begins({'a','b'},{'a','b'},nil,nil,true)
begins({'a','b','c','d'},{'a','b'},nil,nil,true)
begins({'a','b','c','d'},{'b','c'},1,nil,false)
begins({'a','b','c','d'},{'b','c'},2,nil,true)
begins({'a','b','c','d'},{'b','c'},3,nil,false)

begins({}, {}, 1, 0, true)
begins({'a','b'},{'a'},1,1,true)
begins({'a','b'},{'a'},1,0,false)
begins({'a','b'},{'a','b'},1,1,false)
begins({'a','b'},{'a','b'},1,-1,true)
begins({'a','b'},{'a','b'},1,2,true)
begins({'a','b'},{'a','b'},1,3,true)
begins({'a','b','c','d'},{'b','c'},1,4,false)
begins({'a','b','c','d'},{'b','c'},1,3,false)
begins({'a','b','c','d'},{'b','c'},1,2,false)
begins({'a','b','c','d'},{'b','c'},1,1,false)
begins({'a','b','c','d'},{'b','c'},2,4,true)
begins({'a','b','c','d'},{'b','c'},2,3,true)
begins({'a','b','c','d'},{'b','c'},2,2,false)
begins({'a','b','c','d'},{'b','c'},2,1,false)
begins({'a','b','c','d'},{'b','c'},3,4,false)
begins({'a','b','c','d'},{'b','c'},3,3,false)
begins({'a','b','c','d'},{'b','c'},3,2,false)
begins({'a','b','c','d'},{'b','c'},3,1,false)

local function any(input, where, ex)
  testutil.assert('any:'..ser(input),ex,tx.first(input, where))
end

any({}, {}, nil)
any({'a','b'}, {{'b'}}, 2)
any({'a'}, {{'b'},{'a'}}, 1)
any({'a'}, {{'a'},{'b'}}, 1)
any({'a','b'}, {{'a'},{'b'}}, 1)
any({'a','b'}, {{'b'},{'a'}}, 1)
any({'a','b'}, {{'a','b'}}, 1)
any({'a','b'}, {{'b','a'}}, nil)
any({{},{{}}}, function(e) return #e > 0 end, 2)
any({}, {}, nil)

local function part(input, delims, ex, dropDelims, offset, last)
  local special = dropDelims and '(drop)' or ''
  testutil.assert("part"..special..":"..ser(input)..'-'..ser(delims), ex, 
    tx.partition(input, delims, dropDelims, offset, last))
end

part({'a','b','c'},{{'a'}},{{'a'},{'b','c'}})
part({'a','b','c'},{{'b'}},{{'a','b'},{'c'}})
part({'a','b','c'},{{'c'}},{{'a','b','c'}})
part({'a','b','c'},{{'d'}},{{'a','b','c'}})
part({'a','b','c'},{{'a'},{'b'},{'c'}},{{'a'},{'b'},{'c'}})
part({'a','b','c'},{{'b'},{'a'},{'c'}},{{'a'},{'b'},{'c'}})
part({'a','b','c'},{{'c'},{'b'},{'a'}},{{'a'},{'b'},{'c'}})
part({'a','bb','c'},{{'b'},{'bb'}},{{'a','bb'},{'c'}})
part({'a','bb','c'},{{'bb'},{'b'}},{{'a','bb'},{'c'}})
part({'a','bb','c','b','d'},{{'bb'},{'b'}},{{'a','bb'},{'c','b'},{'d'}})
part({'b','a','bb','c','d','bb'},{{'bb'},{'b'}},{{'b'},{'a','bb'},{'c','d','bb'}})
part({'a','b','c'},{{'b'}},{{'a'},{'c'}}, true)
part({'a','b','c'},{}, {{'a','b','c'}}, true)
part({'a','b','c'},{{'b','c'},{'b'}},{{'a'}},true)
part({'a','b','c'},{{'b'},{'b','c'}},{{'a'},{'c'}},true)
part({''},{{';'}},{{''}},true)
part({';'},{{';'}},{},true)
part({';;;;;;;'},{{';'}},{{';;;;;;;'}},true)
part({'a','b','c',';',';'},{{';'}},{{'a','b','c',';'},{';'}},false)
part({'a','b','c',';',';'},{{';'}},{{'a','b','c'}},true)
part({'a','b','c',';'},{{';'}},{{'a','b','c',';'}},false)
part({'a','b','c',';'},{{';'}},{{'a','b','c'}},true)
part({'a','b',';','c'},{{';'}},{{'a','b',';'},{'c'}},false)
part({'a','b',';','c'},{{';'}},{{'a','b'},{'c'}},true)
part({'a','b',';',';','c'},{{';'}},{{'a','b',';'},{';'},{'c'}},false)
part({'a','b',';',';','c'},{{';'}},{{'a','b'},{'c'}},true)
part({';',';','a','b',';',';','c'},{{';'}},{{';'},{';'},{'a','b',';'},{';'},{'c'}},false)
part({';',';','a','b',';',';','c'},{{';'}},{{'a','b'},{'c'}},true)
part({';','a',';','b',';','c',';'},{{';','c'}},{{';','b'}},true,3,-2)
part({'a','b','c'},{{'b'},{'a'}},{{'c'}},true)
part({'a','b','c'},{{'a'},{'b'}},{{'c'}},true)
part({'b','b','c'},{{'b','b'},{'b'}},{{'c'}},true)
part({'b','b','c'},{{'b','b'},{'b'}},{{'b','b'},{'c'}},false)
part({'b','b','c'},{{'b'},{'b','b'}},{{'b'},{'b'},{'c'}},false)
part({'b','b','c'},{},{{'b','b','c'}},false)
part({'b','b','c'},{},{{'b','b','c'}},true)
part({'b','b','c'},{{}},{{'b','b','c'}},false)
part({'b','b','c'},{{}},{{'b','b','c'}},true)
part({'a','b','a','b','c'},{{'a'}},{{'a'},{'b','a'},{'b','c'}})
part({'a','b','a','b','c'},{{'a'}},{{'b'},{'b','c'}},true)

local function part_fn(input, fn, ex, dropDelims, offset, last)
  local special = dropDelims and '(drop)' or ''
  testutil.assert("part_fn"..special..":"..ser(input), ex, 
    tx.partition(input, fn, dropDelims, offset, last))
end

part_fn({'a','b','c'}, function()end, {{'a','b','c'}}, false)
part_fn({'a','b','c'}, function()end, {{'a','b','c'}}, true)
part_fn({'a','b','c','d','e','f','g'}, function(e,i)if i<2 then return 4 end end, 
  {{'a','b','c','d','e','f','g'}}, false)
part_fn({'a','b','c','d','e','f','g'}, function(e,i)if i<2 then return 4 end end, 
  {{'a','b','c'}}, true)
part_fn({'a','b','c','d','e','f','g'}, function(e,i) return 4 end, 
  {{'a','b','c','d','e','f','g'}}, false)
part_fn({'a','b','c','d','e','f','g'}, function(e,i) return 4 end, 
  {{'a','b','c'}}, true)
part_fn({'a','b','a','b','c'},function(e)return e=='a'end,{{'a'},{'b'},{'a'},{'b','c'}})
part_fn({'a','b','a','b','c'},function(e)return e=='a'end,{{'b'},{'b','c'}},true)

local function foreach(input, fn, output)
  testutil.assert('foreach:'..ser(input),output,tx.foreach(input, fn))
end

foreach({'a','aaa','aa'}, function(s) return s:len() end, {1,3,2})
foreach({'a','aa','aaa'}, function(s) return s..'!' end, {'a!','aa!','aaa!'})
foreach({'a','','c'}, function(s) if s:len() > 0 then return s end end, {'a','c'})
foreach({}, function(s) assert(false) end, {})
foreach({'a','aaa','aa'}, function(s) return s,s:len() end, {'a','aa','aaa'})

testutil.assert('foreach range test',{102,103},tx.foreach({1,2,3,4}, 
  function(e,i,t) return e+100 end, 2, -2))

testutil.assert('foreach range test',{1,0},tx.foreach({1,2,3,4}, 
  function(e,i,t) return t[i+1] and 1 or 0 end, 2, -2))

local function where(input, fn, offset, last, ex)
  testutil.assert('where:'..ser(input)..ser(offset),ex,tx.where(input,fn,offset,last))
end

where({1,2,3,4,5},function(i)return i%2==0 end,nil,nil,{2,4})
where({1,2,3,4,5},function(i)return i%2==1 end,nil,nil,{1,3,5})
where({1,2,3,4,5},function(i)return i%2==1 end,3,nil,{3,5})
where({1,2,3,4,5},function(i)return i%2==0 end,-2,nil,{4})
where({1,2,3,4,5},function(i)return i%2==1 end,1,3,{1,3})
where({1,2,3,4,5},function(i)return i%2==0 end,1,3,{2})

local function concat(ex, ...)
  testutil.assert('concat',ex,tx.concat(...))
end

concat({})
concat({1,2,3,4},{1},{2,3},{4})
concat({1,2,3,4,5,6,7},{},{1,2,3,4,5},{6,7})
concat({1,2,3,4,5,6,7},{},{1,2,3,4,5},{},{},{6,7})
concat({1,2,3,4,5,6,7,{}},{},{1,2,3,4,5},{6,7},{{}})

local function reverse(input, offset, last, ex)
  testutil.assert('rev:'..ser(input)..ser(offset)..','..ser(last),ex,
    tx.reverse(input,offset,last))
end

reverse({1,2,3},nil,nil,{3,2,1})
reverse({1,2,3},0,nil,{3,2,1})
reverse({1,2,3},1,nil,{3,2,1})
reverse({1,2,3},2,nil,{1,3,2})
reverse({1,2,3},3,nil,{1,2,3})
reverse({1,2,3},4,nil,{1,2,3})
reverse({},nil,nil,{})
reverse({},5,10,{})
reverse({},1,-1,{})
reverse({1,2,3},1,-1,{3,2,1})
reverse({1,2,3},1,-2,{2,1,3})
reverse({1,2,3},1,2,{2,1,3})
reverse({1,2,3},2,-2,{1,2,3})
reverse({1,2,3},-2,nil,{1,3,2})
reverse({1,2,3},4,-3,{1,2,3})

