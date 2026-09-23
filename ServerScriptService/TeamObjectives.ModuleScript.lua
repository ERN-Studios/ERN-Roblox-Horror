-- Shared server-owned team progress. Call only after a validated objective mutation.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local remote = RS:WaitForChild("Remotes"):WaitForChild("RoundStatus")
local TeamObjectives = {}
local serial = 0
function TeamObjectives.Announce(actorName, detail, level)
	if type(actorName) ~= "string" or type(detail) ~= "string" then return end
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
