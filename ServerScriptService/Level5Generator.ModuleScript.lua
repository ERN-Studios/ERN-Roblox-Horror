--!strict
-- GameManager's independent Level 5 doorway. Map preview only: no Level 4
-- controller, entity, objective, completion or reward code is loaded here.
local systems = script.Parent:WaitForChild("Level 5 Systems")
local adapter = require(systems:WaitForChild("Level 5 Round Adapter"))

return {
	Build = function() return adapter.Build() end,
	Cleanup = function() return adapter.Cleanup() end,
}
