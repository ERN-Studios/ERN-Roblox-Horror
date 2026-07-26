-- NoiseReporter
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "NoiseReporter"
-- Shift = sprint (loud), Ctrl = crouch (silent), walking = quiet.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local remote = RS:WaitForChild("Remotes"):WaitForChild("ReportNoise")
local player = Players.LocalPlayer

local WALK_SPEED, SPRINT_SPEED, CROUCH_SPEED = 16, 26, 8

-- loudness per movement state, 0..1 (server owns the real values)
local LOUDNESS = { sprint = 1.0, walk = 0.45, crouch = 0.0 }

local state = "walk"
local sprinting, crouching = false, false

-- stamina: sprint is limited, drains while sprinting, recovers otherwise
local STAMINA_MAX      = 100
local SPRINT_DRAIN     = 16   -- ~6s of sprint on a full bar
local STAMINA_RECHARGE = 10   -- recovers while not sprinting
local STAMINA_RECOVER  = 25   -- must reach this after exhaustion before sprinting again
local stamina, exhausted = STAMINA_MAX, false

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
	elseif sprinting and stamina > 0 and not exhausted then
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

-- ── stamina UI + drain/recharge ───────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "StaminaGui"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local staBg = Instance.new("Frame")
staBg.AnchorPoint = Vector2.new(0, 1)
staBg.Position = UDim2.new(0, 16, 1, -40) -- just above the flashlight battery
staBg.Size = UDim2.new(0, 160, 0, 16)
staBg.BackgroundColor3 = Color3.new(0, 0, 0)
staBg.BackgroundTransparency = 0.45
staBg.BorderSizePixel = 0
staBg.Visible = false -- stamina still limits sprint, just no on-screen bar
staBg.Parent = gui
local staFill = Instance.new("Frame")
staFill.Size = UDim2.new(1, 0, 1, 0)
staFill.BorderSizePixel = 0
staFill.BackgroundColor3 = Color3.fromRGB(120, 220, 120)
staFill.Parent = staBg

RunService.Heartbeat:Connect(function(dt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local moving = root
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 2

	if state == "sprint" and moving then
		stamina = stamina - SPRINT_DRAIN * dt
		if stamina <= 0 then
			stamina = 0
			exhausted = true
			applySpeed() -- drop out of sprint
		end
	else
		stamina = math.min(STAMINA_MAX, stamina + STAMINA_RECHARGE * dt)
		if exhausted and stamina >= STAMINA_RECOVER then
			exhausted = false
			applySpeed() -- sprint available again if shift still held
		end
	end

	local frac = stamina / STAMINA_MAX
	-- publish stamina (0–1) so SoundController can drive the winded-breathing sound
	player:SetAttribute("Stamina", frac)
	staFill.Size = UDim2.new(frac, 0, 1, 0)
	staFill.BackgroundColor3 = exhausted
		and Color3.fromRGB(230, 80, 60)
		or Color3.fromRGB(120, 220, 120)
end)
