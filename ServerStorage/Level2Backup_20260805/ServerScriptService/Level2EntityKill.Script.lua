-- Combat is implemented inside Level2EntityController so movement, windup,
-- cone/line-of-sight checks and hit revalidation share one per-entity state.
local ServerScriptService = game:GetService("ServerScriptService")
local Controller = require(ServerScriptService:WaitForChild("Level2EntityController"))
Controller.SetCombatEnabled(true)
