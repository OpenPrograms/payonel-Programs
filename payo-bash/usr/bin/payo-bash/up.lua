local os = require("os");
local fs = require("filesystem");

os.execute("mpt -yuv");

if (fs.exists("/var/lib/mpt/cache")) then
    os.execute("rm -r /var/lib/mpt/cache");
end

return 0;

