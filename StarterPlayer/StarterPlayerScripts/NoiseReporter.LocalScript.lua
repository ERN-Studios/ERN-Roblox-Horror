-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud), Ctrl = crouch (silent), walking = quiet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ReportNoise")
local player = Players.LocalPlayer

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false

local function currentChar()
	local char = player.Character
	return char, char and char:FindFirstChild("Humanoid")
end

local function applySpeed()
	local _, hum = currentChar()
	if not hum then return end

	if crouching then
		state = "crouch"
		hum.WalkSpeed = CROUCH_SPEED
	elseif sprinting then
		state = "sprint"
		hum.WalkSpeed = SPRINT_SPEED
	else
		state = "walk"
		hum.WalkSpeed = WALK_SPEED
	end
end

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = true; applySpeed()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = true; applySpeed()
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		sprinting = false; applySpeed()
	elseif input.KeyCode == Enum.KeyCode.LeftControl then
		crouching = false; applySpeed()
	end
end)

player.CharacterAdded:Connect(function()
	task.wait(0.5)
	sprinting, crouching = false, false
	applySpeed()
end)

-- report at 5Hz, only while actually moving
task.spawn(function()
	while task.wait(0.2) do
		local char, hum = currentChar()
		if not (char and hum and hum.Health > 0) then continue end

		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		-- only make noise if actually in motion
		if root.AssemblyLinearVelocity.Magnitude < 2 then continue end

		local loud = LOUDNESS[state]
		if loud > 0 then
			remote:FireServer(state)
		end
	end
end)
