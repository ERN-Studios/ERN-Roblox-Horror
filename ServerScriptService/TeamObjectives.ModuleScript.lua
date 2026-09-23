-- Shared server-owned team progress. Call only after a validated objective mutation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local remote = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
-- ANALYTICS_20260921. This is the single server-validated choke point every
-- level's objective progress passes through, which is why it is the hook.
local Analytics = require(script.Parent:WaitForChild("ZyntraAnalytics"))
local TeamObjectives = {}
local serial = 0
function TeamObjectives.Announce(actorName, detail, level)
	if type(actorName) ~= "string" or type(detail) ~= "string" then return end
	-- Attributed to the ACTOR only, never the party: every caller passes a
	-- player's own name and names are unique within a server. Measurement only.
	Analytics.Objective(Players:FindFirstChild(actorName), level)
	serial += 1
	local payload = {Actor = actorName, Detail = detail, Level = level, Serial = serial}
	for _, recipient in ipairs(Players:GetPlayers()) do
		-- Dead/escaped teammates retain InRound until their round closes.
		if recipient:GetAttribute("InRound") == true then
			remote:FireClient(recipient, "objective", payload)
		end
	end
end
return TeamObjectives
