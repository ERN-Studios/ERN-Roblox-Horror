-- DevCheats (whitelisted developers only)
--
--   B = toggle ESP + 3-second lobby queue
--   V = toggle noclip fly (WASD + mouse, Space up, Ctrl down)
--   P = pause / resume hostile entities
--   I = toggle immunity to the Entity's yell push-back
--   U = toggle unlimited battery + stamina
--   C = toggle third-person gameplay camera
--
-- The Zyntra phone fires the same toggle functions through DevCheatCommand, so
-- keyboard and phone state can never drift apart. Server-affecting commands are
-- validated again by GameManager through the shared DevAccess whitelist.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local DevAccess = require(RS:WaitForChild("DevAccess"))
if not DevAccess.IsAllowed(player) then return end

local playerScripts = player:WaitForChild("PlayerScripts")
local commandEvent = playerScripts:FindFirstChild("DevCheatCommand")
if not commandEvent then
	commandEvent = Instance.new("BindableEvent")
	commandEvent.Name = "DevCheatCommand"
	commandEvent.Parent = playerScripts
end
if not commandEvent:IsA("BindableEvent") then
	warn("[DevCheats] PlayerScripts.DevCheatCommand must be a BindableEvent")
	return
end

local remotes = RS:WaitForChild("Remotes")
local devControl = remotes:FindFirstChild("DevControl")
local function fireDev(command, value)
	if not devControl then devControl = remotes:FindFirstChild("DevControl") end
	if devControl then
		devControl:FireServer(command, value)
		return true
	end
	warn("[DevCheats] DevControl is missing; server-backed developer cheats are unavailable")
	return false
end

local function requestedState(current, requested)
	if typeof(requested) == "boolean" then return requested end
	return not current
end

local entityPaused = workspace:GetAttribute("EntityPaused") == true
local pushImmune = player:GetAttribute("DevPushImmune") == true
local unlimitedOn = false
local fastQueueOn = player:GetAttribute("DevFastQueue") == true
local thirdPersonOn = false

-- ESP (highlight through walls)
local COLORS = {
	Fuse = Color3.fromRGB(255, 220, 60),
	FuseRelay = Color3.fromRGB(255, 190, 55),
	FuseBox = Color3.fromRGB(80, 160, 255),
	Lever = Color3.fromRGB(180, 90, 255),
	Exit = Color3.fromRGB(60, 255, 130),
	Entity = Color3.fromRGB(255, 45, 45),
	Level2Entity = Color3.fromRGB(255, 70, 45),
}

-- Preserve the old developer behavior: ESP starts enabled, while every other
-- cheat starts disabled. B now deliberately synchronizes ESP and fast queue.
local espOn = true

local function publishState(attribute, enabled)
	player:SetAttribute(attribute, enabled)
end

publishState("DevCheatEsp", espOn)
publishState("DevCheatFastQueue", fastQueueOn)
publishState("DevCheatNoclip", false)
publishState("DevCheatEntityPaused", entityPaused)
publishState("DevCheatPushImmune", pushImmune)
publishState("DevCheatUnlimited", unlimitedOn)
publishState("DevCheatThirdPerson", thirdPersonOn)
player:SetAttribute("DevEspEnabled", espOn)
player:SetAttribute("DevUnlimited", nil)

local function tag(instance, color)
	if instance:FindFirstChild("DevESP") then return end
	local highlight = Instance.new("Highlight")
	highlight.Name = "DevESP"
	highlight.FillColor = color
	highlight.FillTransparency = 0.55
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = espOn
	highlight.Adornee = instance
	highlight.Parent = instance
end

local function setEsp(requested)
	local enabled = requestedState(espOn, requested)
	espOn = enabled
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == "DevESP" and descendant:IsA("Highlight") then
			descendant.Enabled = enabled
		end
	end
	player:SetAttribute("DevEspEnabled", enabled)
	publishState("DevCheatEsp", enabled)
	print("[DevCheats] ESP " .. (enabled and "ON" or "OFF"))
end

task.spawn(function()
	while true do
		local items = workspace:FindFirstChild("PuzzleItems")
		if items then
			for _, child in ipairs(items:GetChildren()) do
				if COLORS[child.Name] then tag(child, COLORS[child.Name]) end
			end
		end
		local entity = workspace:FindFirstChild("Entity")
		if entity then tag(entity, COLORS.Entity) end
		for _, levelTwoEntity in ipairs(CollectionService:GetTagged("Level2HostileEntity")) do
			if levelTwoEntity:IsA("Model") and levelTwoEntity:IsDescendantOf(workspace) then
				tag(levelTwoEntity, COLORS.Level2Entity)
			end
		end
		-- Compatibility fallback while a newly generated Level 2 entity is tagged.
		local levelTwoWorld = workspace:FindFirstChild("PoolroomsLevel2")
		if levelTwoWorld then
			for _, candidate in ipairs(levelTwoWorld:GetDescendants()) do
				if candidate:IsA("Model") and candidate:GetAttribute("Level2Hostile") == true then
					tag(candidate, COLORS.Level2Entity)
				end
			end
		end
		task.wait(0.5)
	end
end)

local function setFastQueue(requested)
	local enabled = requestedState(fastQueueOn, requested)
	if enabled == fastQueueOn then return end
	fastQueueOn = enabled
	publishState("DevCheatFastQueue", enabled)
	fireDev("fastQueue", enabled)
	print("[DevCheats] 3-second lobby queue " .. (enabled and "ON" or "OFF"))
end

local function setEntityPaused(requested)
	local enabled = requestedState(entityPaused, requested)
	if enabled == entityPaused then return end
	entityPaused = enabled
	publishState("DevCheatEntityPaused", enabled)
	fireDev("pauseEntity", enabled)
	print("[DevCheats] Entities " .. (enabled and "PAUSED" or "resumed"))
end

local function setPushImmune(requested)
	local enabled = requestedState(pushImmune, requested)
	if enabled == pushImmune then return end
	pushImmune = enabled
	publishState("DevCheatPushImmune", enabled)
	fireDev("immunePush", enabled)
	print("[DevCheats] Yell push-back immunity " .. (enabled and "ON" or "OFF"))
end

local function setUnlimited(requested)
	local enabled = requestedState(unlimitedOn, requested)
	if enabled == unlimitedOn then return end
	unlimitedOn = enabled
	player:SetAttribute("DevUnlimited", enabled or nil)
	publishState("DevCheatUnlimited", enabled)
	print("[DevCheats] Unlimited battery + stamina " .. (enabled and "ON" or "OFF"))
end

-- Noclip fly
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

local function applyLocalNoclip(character)
	for _, part in ipairs(character:GetDescendants()) do disablePart(part) end
end

local function startFlying()
	if flying then return true end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then return false end

	flying = true
	collisionOriginal = {}
	humanoidOriginal = {
		autoRotate = humanoid.AutoRotate,
		fallingDown = humanoid:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
		ragdoll = humanoid:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
	}
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Flying)
	applyLocalNoclip(character)
	noclipAdded = character.DescendantAdded:Connect(disablePart)
	fireDev("noclip", true)
	publishState("DevCheatNoclip", true)
	print("[DevCheats] Noclip fly ON")
	return true
end

local function stopFlying()
	if not flying then
		publishState("DevCheatNoclip", false)
		return
	end
	flying = false
	fireDev("noclip", false)
	if noclipAdded then noclipAdded:Disconnect(); noclipAdded = nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	for part, original in pairs(collisionOriginal) do
		if part.Parent then part.CanCollide = original end
	end
	collisionOriginal = {}
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = humanoidOriginal and humanoidOriginal.autoRotate ~= false
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.FallingDown,
			not humanoidOriginal or humanoidOriginal.fallingDown
		)
		humanoid:SetStateEnabled(
			Enum.HumanoidStateType.Ragdoll,
			not humanoidOriginal or humanoidOriginal.ragdoll
		)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	humanoidOriginal = nil
	publishState("DevCheatNoclip", false)
	print("[DevCheats] Noclip fly OFF")
end

local function setFlying(requested)
	local enabled = requestedState(flying, requested)
	if enabled then startFlying() else stopFlying() end
end

RunService.PreSimulation:Connect(function(deltaTime)
	if not flying then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then return end

	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	applyLocalNoclip(character)

	local camera = workspace.CurrentCamera
	if not camera then return end
	local move = Vector3.zero
	if UIS:IsKeyDown(Enum.KeyCode.W) then move += camera.CFrame.LookVector end
	if UIS:IsKeyDown(Enum.KeyCode.S) then move -= camera.CFrame.LookVector end
	if UIS:IsKeyDown(Enum.KeyCode.D) then move += camera.CFrame.RightVector end
	if UIS:IsKeyDown(Enum.KeyCode.A) then move -= camera.CFrame.RightVector end
	if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
	if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
	if move.Magnitude > 0 then move = move.Unit end

	root.AssemblyAngularVelocity = Vector3.zero
	root.AssemblyLinearVelocity = Vector3.zero
	if move.Magnitude > 0 then
		character:PivotTo(character:GetPivot() + move * FLY_SPEED * math.min(deltaTime, 1 / 20))
	end
end)

-- Third-person only changes Roblox's player camera constraints. It deliberately
-- leaves CameraType/CameraSubject alone so kill and spectate cameras keep control.
local function applyPerspective()
	local inRound = player:GetAttribute("InRound") == true
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if inRound and humanoid and humanoid.Health <= 0 then return end

	if inRound then
		if thirdPersonOn then
			player.CameraMode = Enum.CameraMode.Classic
			-- Force the camera out immediately. A 0.5 minimum leaves it at the
			-- first-person zoom until the player manually scrolls backwards.
			player.CameraMaxZoomDistance = 14
			player.CameraMinZoomDistance = 6
		else
			player.CameraMode = Enum.CameraMode.LockFirstPerson
			player.CameraMinZoomDistance = 0.5
			player.CameraMaxZoomDistance = 0.5
		end
	else
		-- Lobby players always keep their normal third-person avatar camera.
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = 18
		player.CameraMinZoomDistance = 8
	end
end

local function reapplyPerspectiveSoon()
	task.defer(applyPerspective)
	task.delay(0.25, applyPerspective)
end

local function setThirdPerson(requested)
	local enabled = requestedState(thirdPersonOn, requested)
	thirdPersonOn = enabled
	publishState("DevCheatThirdPerson", enabled)
	applyPerspective()
	print("[DevCheats] Third-person camera " .. (enabled and "ON" or "OFF"))
end

player.CharacterAdded:Connect(function()
	if flying then stopFlying() end
	reapplyPerspectiveSoon()
end)
player:GetAttributeChangedSignal("InRound"):Connect(reapplyPerspectiveSoon)

-- Server-backed state can also change during round cleanup or when another
-- whitelisted developer uses the global pause toggle. Mirror those acknowledgements
-- so the phone always describes what the server is actually doing.
workspace:GetAttributeChangedSignal("EntityPaused"):Connect(function()
	entityPaused = workspace:GetAttribute("EntityPaused") == true
	publishState("DevCheatEntityPaused", entityPaused)
end)
player:GetAttributeChangedSignal("DevFastQueue"):Connect(function()
	fastQueueOn = player:GetAttribute("DevFastQueue") == true
	publishState("DevCheatFastQueue", fastQueueOn)
end)
player:GetAttributeChangedSignal("DevPushImmune"):Connect(function()
	pushImmune = player:GetAttribute("DevPushImmune") == true
	publishState("DevCheatPushImmune", pushImmune)
end)

local function dispatchCommand(command, requested)
	if command == "esp" then
		setEsp(requested)
	elseif command == "fastQueue" then
		setFastQueue(requested)
	elseif command == "noclip" then
		setFlying(requested)
	elseif command == "pauseEntity" then
		setEntityPaused(requested)
	elseif command == "immunePush" then
		setPushImmune(requested)
	elseif command == "unlimited" then
		setUnlimited(requested)
	elseif command == "thirdPerson" then
		setThirdPerson(requested)
	else
		warn("[DevCheats] Unknown command: " .. tostring(command))
	end
end

commandEvent.Event:Connect(dispatchCommand)

UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		local enabled = not (espOn and fastQueueOn)
		setEsp(enabled)
		setFastQueue(enabled)
	elseif input.KeyCode == Enum.KeyCode.V then
		setFlying()
	elseif input.KeyCode == Enum.KeyCode.P then
		setEntityPaused()
	elseif input.KeyCode == Enum.KeyCode.I then
		setPushImmune()
	elseif input.KeyCode == Enum.KeyCode.U then
		setUnlimited()
	elseif input.KeyCode == Enum.KeyCode.C then
		setThirdPerson()
	end
end)

reapplyPerspectiveSoon()
