--!strict
-- Level3Generator
-- Compatibility doorway used by GameManager. All Level 3 behaviour is owned
-- by the explicitly named modules inside ServerScriptService/Level 3 Systems.

local Systems = script.Parent:WaitForChild("Level 3 Systems")
local Adapter = require(Systems:WaitForChild("Level 3 Round Adapter"))

return {
	Build = function()
		return Adapter.Build()
	end,
	Cleanup = function()
		return Adapter.Cleanup()
	end,
}
