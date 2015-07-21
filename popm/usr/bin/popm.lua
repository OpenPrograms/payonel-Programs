local argutil = require("payo-lib/argutil");
local ser = require("serialization").serialize

package.loaded["popm-lib/popm"] = nil;
local popmlib = require("popm-lib/popm")

print("initial check in and test");

local repos = popmlib.read("https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg");

print("download complete, printing table result");
print(ser(repos));

