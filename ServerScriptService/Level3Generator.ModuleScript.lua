-- Level3Generator
-- Compatibility doorway used by GameManager, matching the Level2Generator
-- surface. All Level 3 behaviour lives in the explicitly named Level 3 services.
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
