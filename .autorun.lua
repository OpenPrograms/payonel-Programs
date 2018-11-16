local fs = require("filesystem")

local mount_point = fs.path(os.getenv("_"))
fs.link(mount_point .. "payo-tests/var", "/var")
fs.link(mount_point .. "payo-lib/usr/lib", "/usr/lib")
