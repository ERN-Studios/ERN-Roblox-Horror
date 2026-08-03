-- SetRunAnimation
-- Roblox swaps the character's Animate script for the platform default at spawn,
-- so editing StarterCharacter's own copy has no effect. Patch the id at runtime
-- and restart Animate so it reloads the track.

local RUN_ID = "rbxassetid://83054249237379"

local player = game:GetService("Players").LocalPlayer
if player:GetAttribute("InRound") ~= true then return end

local char = script.Parent
local animate = char:WaitForChild("Animate")
local runAnim = animate:WaitForChild("run"):WaitForChild("RunAnim")

if runAnim.AnimationId ~= RUN_ID then
	animate.Disabled = true
	runAnim.AnimationId = RUN_ID
	animate.Disabled = false
end
