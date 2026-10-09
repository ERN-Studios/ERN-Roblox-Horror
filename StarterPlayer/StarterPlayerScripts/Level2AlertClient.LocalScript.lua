-- Level 2 announcements share the B5 top-centre feed; gameplay owns every event.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local Hud = require(RS:WaitForChild("RoundHud"))
local event = RS:WaitForChild("Level 2 Remotes"):WaitForChild("Level 2 Alert Event")

local function announcementAllowed()
	return workspace:GetAttribute("SelectedLevel") == 2
		and player:GetAttribute("InRound") == true
		and player:GetAttribute("ZyntraDispatchClientActive") ~= true
end
local function presentAlert(line1, line2, finalLine)
	local title = tostring(line1 or "")
	local instruction = tostring(finalLine or "")
	-- Validated pump progress already uses TeamObjectives. Retain a separate
	-- urgent water cue and the final exit announcement, without repeating pumps.
	if string.find(title, "PUMP STATION", 1, true) then
		if string.find(instruction, "NO LONGER SAFE", 1, true) then
			Hud.Feed({Kind = "LEVEL", Detail = "The water is no longer safe", Key = "level2:water"})
		end
		return
	end
	local copy = title
	if instruction ~= "" then copy ..= " \u{B7} " .. instruction end
	if copy ~= "" then Hud.Feed({Kind = "LEVEL", Detail = copy, Key = "level2:alert"}) end
end
local function onAlertEvent(line1, line2, finalLine, holdSeconds)
	if announcementAllowed() then presentAlert(line1, line2, finalLine) end
end
local alertWiring = {Handler = onAlertEvent, Connection = event.OnClientEvent:Connect(onAlertEvent)}
-- The retired band owner must never stand down the shared objective card.
player:SetAttribute("Level2AlertOwnsBand", nil)
if RunService:IsStudio() then
	local probe = Instance.new("BindableFunction")
	probe.Name = "UIRegressionLevel2AlertProbe"
	probe.OnInvoke = function(action, line1, line2, finalLine, holdSeconds)
		if action == "show" then presentAlert(line1, line2, finalLine) end
		if action == "restore" then Hud.Clear() end
		if action == "wiring" then
			return "remote=" .. tostring(alertWiring.Connection.Connected) .. "/" .. tostring(alertWiring.Handler == onAlertEvent)
		end
		return {Gate = announcementAllowed(), OwnsBand = false}
	end
	probe.Parent = Hud.Gui()
end
