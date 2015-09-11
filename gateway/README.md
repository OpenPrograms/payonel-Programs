Sample code
```
local components = require("component")
local internet = components.internet

if not internet then
	local gateway = require("gateway")
	local availableGateways = gateway.search()
	if #availableGateways > 0 then
		internet = availableGateways[1].connect()
	end
end

assert(internet)
```
