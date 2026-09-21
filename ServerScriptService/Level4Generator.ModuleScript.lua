--!strict
-- Level4Generator
-- Compatibility doorway used by GameManager, identical in shape to
-- Level3Generator. All Level 4 behaviour is owned by the explicitly named
-- modules inside ServerScriptService/Level 4 Systems.
--
-- LEVEL 4 IS DEV-ONLY: the adapter refuses to build unless
-- workspace.Level4DevEnabled is true. See docs/LEVEL4_CONTRACTS_2026-09-21.md.

local Systems = script.Parent:WaitForChild("Level 4 Systems")
local Adapter = require(Systems:WaitForChild("Level 4 Round Adapter"))

return {
	Build = function()
		return Adapter.Build()
	end,
	Cleanup = function()
		return Adapter.Cleanup()
	end,
}
