local lib = "payo-lib/guid"
package.loaded[lib] = nil
local util = require(lib)

if (not util) then
  error("failed to load " .. lib)
end

