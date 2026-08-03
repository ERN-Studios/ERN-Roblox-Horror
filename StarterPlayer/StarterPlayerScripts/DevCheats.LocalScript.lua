-- DevCheats  (TESTING ONLY — delete or restrict before publishing!)
-- PASTE INTO: StarterPlayer → StarterPlayerScripts → Insert Object → LocalScript → rename to "DevCheats"
--
--   B = toggle ESP + 3-second lobby queue (existing ESP behavior is preserved)
--   V = toggle noclip fly (WASD + mouse to move, Space up, Ctrl down)
--   P = pause / unpause the Entity (freezes it in place)
--   I = toggle immunity to the Entity's yell push-back
--   U = toggle UNLIMITED battery + stamina (whitelisted names only)
--
-- ALLOWED_NAMES empty = everyone can cheat (fine while testing). Add your
-- Roblox usernames to restrict it to just you two, or delete this script.
-- The B/P/I server cheats need a RemoteEvent "DevControl" in ReplicatedStorage/Remotes.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local ALLOWED_NAMES = { "mikkelczar","LaverSneglen" } -- e.g. { "Krillemand" } — empty = everyone
local function allowed()
	if #ALLOWED_NAMES == 0 then return true end
	for _, n in ipairs(ALLOWED_NAMES) do
		if n == player.Name then return true end
	end
	return false
end
if not allowed() then return end

-- RemoteEvent used for the B fast queue plus Entity controls (P pause, I push-immunity).
-- Fetched lazily so it still works if you create DevControl after pressing play,
-- and so a missing one never blocks ESP / noclip below.
local remotes = RS:WaitForChild("Remotes")
local devControl = remotes:FindFirstChild("DevControl")
local function fireDev(cmd, arg)
	if not devControl then devControl = remotes:FindFirstChild("DevControl") end
	if devControl then
		devControl:FireServer(cmd, arg)
		return true
	end
	warn("[DevCheats] DevControl RemoteEvent missing in ReplicatedStorage/Remotes — B/P/I server cheats won't work")
	return false
end
local entityPaused = false
local pushImmune = false

local unlimitedOn = false
local fastQueueOn = false

-- ── ESP (highlight through walls) ─────────────────────────
local COLORS = {
	Fuse    = Color3.fromRGB(255, 220, 60),
	FuseBox = Color3.fromRGB(80, 160, 255),
	Lever   = Color3.fromRGB(180, 90, 255),
	Exit    = Color3.fromRGB(60, 255, 130),
	Entity  = Color3.fromRGB(255, 45, 45),
}
local espOn = true

local function tag(inst, color)
	if inst:FindFirstChild("ESP") then return end
	local h = Instance.new("Highlight")
	h.Name = "ESP"
	h.FillColor = color
	h.FillTransparency = 0.55
	h.OutlineColor = color
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Enabled = espOn
	h.Adornee = inst
	h.Parent = inst
end

task.spawn(function()
	while true do
		local items = workspace:FindFirstChild("PuzzleItems")
		if items then
			for _, c in ipairs(items:GetChildren()) do
				if COLORS[c.Name] then tag(c, COLORS[c.Name]) end
			end
		end
		local e = workspace:FindFirstChild("Entity")
		if e then tag(e, COLORS.Entity) end
		task.wait(0.5)
	end
end)

-- ── noclip fly ────────────────────────────────────────────
local flying = false
local FLY_SPEED = 90
local collisionOriginal = {}
local noclipAdded = nil
local humanoidOriginal = nil

local function disablePart(part)
	if not part:IsA("BasePart") then return end
	if collisionOriginal[part] == nil then
		collisionOriginal[part] = part.CanCollide
	end
	part.CanCollide = false
end

local function applyLocalNoclip(char)
	for _, part in ipairs(char:GetDescendants()) do disablePart(part) end
end

local function startFlying()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (char and hum) then return end
	flying = true
	collisionOriginal = {}
	humanoidOriginal = {
		autoRotate = hum.AutoRotate,
		fallingDown = hum:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
		ragdoll = hum:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
	}
	hum.PlatformStand = false
	hum.AutoRotate = false
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	hum:ChangeState(Enum.HumanoidStateType.Flying)
	applyLocalNoclip(char)
	noclipAdded = char.DescendantAdded:Connect(disablePart)
	fireDev("noclip", true) -- server authority makes live-server collision reliable
end

RunService.PreSimulation:Connect(function()
	if not flying then return end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return end

	hum.PlatformStand = false
	hum.AutoRotate = false
	applyLocalNoclip(char)

	local cam = workspace.CurrentCamera
	local move = Vector3.zero
	if UIS:IsKeyDown(Enum.KeyCode.W) then move += cam.CFrame.LookVector end
	if UIS:IsKeyDown(Enum.KeyCode.S) then move -= cam.CFrame.LookVector end
	if UIS:IsKeyDown(Enum.KeyCode.D) then move += cam.CFrame.RightVector end
	if UIS:IsKeyDown(Enum.KeyCode.A) then move -= cam.CFrame.RightVector end
	if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
	if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
	if move.Magnitude > 0 then move = move.Unit end

	root.AssemblyAngularVelocity = Vector3.zero
	root.AssemblyLinearVelocity = move * FLY_SPEED
end)

local function stopFlying()
	if not flying then return end
	flying = false
	fireDev("noclip", false)
	if noclipAdded then noclipAdded:Disconnect(); noclipAdded = nil end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	for part, original in pairs(collisionOriginal) do
		if part.Parent then part.CanCollide = original end
	end
	collisionOriginal = {}
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if hum then
		hum.PlatformStand = false
		hum.AutoRotate = humanoidOriginal and humanoidOriginal.autoRotate ~= false
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,
			not humanoidOriginal or humanoidOriginal.fallingDown)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll,
			not humanoidOriginal or humanoidOriginal.ragdoll)
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	humanoidOriginal = nil
end

player.CharacterAdded:Connect(function()
	if flying then stopFlying() end
end)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		espOn = not espOn
		for _, d in ipairs(workspace:GetDescendants()) do
			if d.Name == "ESP" and d:IsA("Highlight") then d.Enabled = espOn end
		end
		fastQueueOn = not fastQueueOn
		fireDev("fastQueue", fastQueueOn)
		print("[DevCheats] 3-second lobby queue " .. (fastQueueOn and "ON" or "OFF"))
	elseif input.KeyCode == Enum.KeyCode.V then
		if flying then stopFlying() else startFlying() end
	elseif input.KeyCode == Enum.KeyCode.P then
		entityPaused = not entityPaused
		fireDev("pauseEntity", entityPaused)
		print("[DevCheats] Entity " .. (entityPaused and "PAUSED" or "resumed"))
	elseif input.KeyCode == Enum.KeyCode.I then
		pushImmune = not pushImmune
		fireDev("immunePush", pushImmune)
		print("[DevCheats] Yell push-back immunity " .. (pushImmune and "ON" or "OFF"))
	elseif input.KeyCode == Enum.KeyCode.U then
		unlimitedOn = not unlimitedOn
		-- local attribute: FlashlightController (battery) and NoiseReporter
		-- (stamina) both read it on this same client
		player:SetAttribute("DevUnlimited", unlimitedOn or nil)
		print("[DevCheats] Unlimited battery + stamina " .. (unlimitedOn and "ON" or "OFF"))
	end
end)
