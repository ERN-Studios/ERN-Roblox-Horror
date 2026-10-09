-- Level2Generator
-- Compatibility doorway used by GameManager, matching the Level2Generator
-- surface. All Level 2 behaviour lives in the explicitly named Level 2 services.
local Systems = script.Parent:WaitForChild("Level 2 Systems")
local Adapter = require(Systems:WaitForChild("Level 2 Round Adapter"))

return {
	Build = function()
		return Adapter.Build()
	end,
	Cleanup = function()
		return Adapter.Cleanup()
	end,
}
