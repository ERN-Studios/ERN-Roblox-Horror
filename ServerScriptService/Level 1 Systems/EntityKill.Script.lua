-- EntityKill: server-authoritative cinematic capture with cancellable ownership.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local PlayerProtection = require(game:GetService("ServerScriptService"):WaitForChild("PlayerProtection"))

local remote = RS:WaitForChild("Remotes"):WaitForChild("Jumpscare")
local entity = workspace:WaitForChild("Entity")
local entityHumanoid = entity:WaitForChild("Humanoid")
local entityRoot = entity:WaitForChild("HumanoidRootPart")
local KILL_DURATION = 5.0
local DEATH_AT = 124 / 30
local CAPTURE_DISTANCE = 3.7
local playerDebounce = {}
local captureEpoch, captureSerial = 0, 0
local captureGeneration = HttpService:GenerateGUID(false)
local activeCapture = nil

local function findPlayer(hit)
	local node = hit
	while node and node ~= workspace do
		if node:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(node)
			if player then return player, node end
		end
		node = node.Parent
	end
	return nil, nil
end

local function eligible(player, char)
	if not (player and player.Parent == Players and player.Character == char and char and char.Parent)
		or player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true
		or workspace:GetAttribute("RoundActive") ~= true or workspace:GetAttribute("SelectedLevel") ~= 1 then return false end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return hum ~= nil and hum.Health > 0 and root ~= nil and not PlayerProtection.IsActive(player, char)
end

local function finishCapture(record, cancelled)
	if activeCapture ~= record then return end
	cancelled = cancelled and not record.Fatal -- completed death keeps its normal client fade
	activeCapture = nil -- invalidate every waiter before cancelling its tween
	for _, connection in ipairs(record.Connections) do connection:Disconnect() end
	for _, tween in ipairs(record.Tweens) do tween:Cancel() end
	local saved = record.Saved
	if saved then
		if entityRoot.Parent then
			entityRoot.CFrame = record.KillBaseCFrame
			entityRoot.Anchored = saved.entityAnchored
			entityHumanoid.WalkSpeed = saved.entityWalkSpeed
			entityRoot.AssemblyLinearVelocity = Vector3.zero
			entityRoot.AssemblyAngularVelocity = Vector3.zero
			pcall(function() entityRoot:SetNetworkOwner(nil) end)
		end
		if record.Player.Character == record.Character and record.Root.Parent and record.Humanoid.Parent
			and (cancelled or record.Humanoid.Health > 0) then
			record.Root.Anchored = saved.playerAnchored
			record.Root.AssemblyLinearVelocity = Vector3.zero
			record.Root.AssemblyAngularVelocity = Vector3.zero
			record.Humanoid.WalkSpeed = saved.walkSpeed
			record.Humanoid.JumpPower = saved.jumpPower
			record.Humanoid.AutoRotate = saved.autoRotate
			record.Humanoid.BreakJointsOnDeath = saved.breakJoints
			record.Humanoid.PlatformStand = saved.platformStand
			-- Restore the pre-grab pose. Merely unrolling the floor-pin pose would
			-- leave an upright HumanoidRootPart partly below the collision floor.
			if cancelled and record.Humanoid.Health > 0 then
				record.Root.CFrame = saved.playerCFrame
			end
		end
	end
	workspace:SetAttribute("EntityKillActive", false)
	workspace:SetAttribute("EntityKillCaptureId", nil)
	if cancelled and record.Started then
		local cancelKill = entity:FindFirstChild("CancelKill")
		if cancelKill and cancelKill:IsA("BindableEvent") then cancelKill:Fire(record.Id) end
		if record.Player.Parent == Players then
			remote:FireClient(record.Player, "cancel", nil, nil, nil, record.Id, record.Character)
		end
	end
end

local function captureStep(record)
	if activeCapture ~= record then return false end
	if record.Epoch ~= captureEpoch or not eligible(record.Player, record.Character)
		or (record.Humanoid and record.Character:FindFirstChildOfClass("Humanoid") ~= record.Humanoid)
		or (record.Root and record.Character:FindFirstChild("HumanoidRootPart") ~= record.Root) then
		finishCapture(record, true)
		return false
	end
	return true
end

local function playTween(record, object, info, goal)
	if not captureStep(record) then return nil end
	local tween = TweenService:Create(object, info, goal)
	table.insert(record.Tweens, tween)
	tween:Play()
	return tween
end

local function runKill(record)
	if not captureStep(record) then return end
	local player, char = record.Player, record.Character
	local hum = char:FindFirstChildOfClass("Humanoid")
	local playerRoot = char:FindFirstChild("HumanoidRootPart")
	record.Humanoid, record.Root = hum, playerRoot
	playerDebounce[player] = os.clock()
	workspace:SetAttribute("EntityKillActive", true)
	workspace:SetAttribute("EntityKillCaptureId", record.Id)
	workspace:SetAttribute("EntityIsLunging", false)
	local saved = {
		entityAnchored = entityRoot.Anchored, entityWalkSpeed = entityHumanoid.WalkSpeed,
		playerAnchored = playerRoot.Anchored, playerCFrame = playerRoot.CFrame,
		walkSpeed = hum.WalkSpeed, jumpPower = hum.JumpPower, autoRotate = hum.AutoRotate,
		breakJoints = hum.BreakJointsOnDeath, platformStand = hum.PlatformStand,
	}
	record.Saved = saved
	entityRoot.AssemblyLinearVelocity, entityRoot.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	entityHumanoid.WalkSpeed, entityRoot.Anchored = 0, true
	local entityPos = entityRoot.Position
	local targetFlat = Vector3.new(playerRoot.Position.X, entityPos.Y, playerRoot.Position.Z)
	if (targetFlat - entityPos).Magnitude > 0.01 then entity:PivotTo(CFrame.lookAt(entity:GetPivot().Position, targetFlat)) end
	local killBaseCFrame = entityRoot.CFrame
	record.KillBaseCFrame = killBaseCFrame
	entityPos = entityRoot.Position
	local capturePos = entityPos + entityRoot.CFrame.LookVector * CAPTURE_DISTANCE
	capturePos = Vector3.new(capturePos.X, playerRoot.Position.Y, capturePos.Z)
	playerRoot.CFrame = CFrame.lookAt(capturePos, Vector3.new(entityPos.X, capturePos.Y, entityPos.Z))
	playerRoot.AssemblyLinearVelocity, playerRoot.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	playerRoot.Anchored, hum.WalkSpeed, hum.JumpPower = true, 0, 0
	hum.AutoRotate, hum.PlatformStand, hum.BreakJointsOnDeath = false, false, false
	record.Started = true
	remote:FireClient(player, "capture", entity, KILL_DURATION, DEATH_AT, record.Id, char)
	local playKill = entity:FindFirstChild("PlayKill")
	if playKill and playKill:IsA("BindableEvent") then playKill:Fire(record.Id) end
	local function cancelInvalid()
		if not record.Fatal and activeCapture == record and not eligible(player, char) then finishCapture(record, true) end
	end
	for _, name in ipairs({"InRound", "Escaped"}) do
		table.insert(record.Connections, player:GetAttributeChangedSignal(name):Connect(cancelInvalid))
	end
	table.insert(record.Connections, player.CharacterRemoving:Connect(function(character)
		if character == char then finishCapture(record, true) end
	end))
	table.insert(record.Connections, hum.Died:Connect(cancelInvalid))

	task.delay(1.05, function()
		if not captureStep(record) then return end
		local crouchCF = killBaseCFrame + killBaseCFrame.LookVector * 0.25 - Vector3.new(0, 1.45, 0)
		playTween(record, entityRoot, TweenInfo.new(0.68, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {CFrame = crouchCF})
	end)
	task.spawn(function()
		task.wait(0.72)
		if not captureStep(record) then return end
		local closePos = entityRoot.Position + entityRoot.CFrame.LookVector * 2.45
		closePos = Vector3.new(closePos.X, playerRoot.Position.Y, closePos.Z)
		local closeCF = CFrame.lookAt(closePos, Vector3.new(entityRoot.Position.X, closePos.Y, entityRoot.Position.Z))
		local pull = playTween(record, playerRoot, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = closeCF})
		if not pull then return end
		pull.Completed:Wait()
		if not captureStep(record) then return end
		task.wait(0.38)
		if not captureStep(record) then return end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local floorFilter = {entity, char}
		for _, name in ipairs({"Decor", "PuzzleItems"}) do
			local instance = workspace:FindFirstChild(name)
			if instance then table.insert(floorFilter, instance) end
		end
		params.FilterDescendantsInstances = floorFilter
		local pinXZ = entityRoot.Position + entityRoot.CFrame.LookVector * 1.35
		local entityFloorHit = workspace:Raycast(entityRoot.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -12, 0), params)
		local fallbackFloorY = entityRoot.Position.Y - math.max(entityHumanoid.HipHeight + entityRoot.Size.Y * 0.5, 2.5)
		local floorY = entityFloorHit and entityFloorHit.Normal.Y > 0.7 and entityFloorHit.Position.Y or fallbackFloorY
		local pinFloorHit = workspace:Raycast(Vector3.new(pinXZ.X, floorY + 2.5, pinXZ.Z), Vector3.new(0, -5, 0), params)
		if pinFloorHit and pinFloorHit.Normal.Y > 0.7 and math.abs(pinFloorHit.Position.Y - floorY) <= 0.75 then floorY = pinFloorHit.Position.Y end
		local groundPos = Vector3.new(pinXZ.X, floorY + playerRoot.Size.Z * 0.5 + 0.1, pinXZ.Z)
		local groundCF = CFrame.lookAt(groundPos, Vector3.new(entityRoot.Position.X, groundPos.Y, entityRoot.Position.Z)) * CFrame.Angles(math.rad(90), 0, 0)
		hum.PlatformStand = true
		playerRoot.AssemblyLinearVelocity, playerRoot.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		playTween(record, playerRoot, TweenInfo.new(0.72, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut), {CFrame = groundCF})
	end)
	task.wait(DEATH_AT)
	if not captureStep(record) then return end
	-- Final private guard precedes both death feedback and the irreversible hit.
	if PlayerProtection.IsActive(player, char) then finishCapture(record, true); return end
	record.Fatal = true
	remote:FireClient(player, "death", nil, nil, nil, record.Id, char)
	hum.Health = 0
	task.wait(math.max(0, KILL_DURATION - DEATH_AT))
	finishCapture(record, false)
end

local function onTouched(hit)
	if activeCapture then return end
	local player, char = findPlayer(hit)
	if not eligible(player, char) then return end
	local last = playerDebounce[player]
	if last and os.clock() - last < KILL_DURATION + 1 then return end
	captureSerial += 1
	local record = {Player = player, Character = char, Epoch = captureEpoch,
		Id = captureGeneration .. ":" .. tostring(captureSerial), Tweens = {}, Connections = {}}
	activeCapture = record -- reserve before task.spawn or another touch callback
	task.spawn(runKill, record)
end

PlayerProtection.Activated:Connect(function(player, character)
	local record = activeCapture
	if record and record.Player == player and record.Character == character
		and PlayerProtection.IsActive(player, character) then finishCapture(record, true) end
end)
local function invalidateRound()
	captureEpoch += 1
	if activeCapture then finishCapture(activeCapture, true) end
end
workspace:GetAttributeChangedSignal("RoundActive"):Connect(invalidateRound)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(invalidateRound)
Players.PlayerRemoving:Connect(function(player)
	if activeCapture and activeCapture.Player == player then finishCapture(activeCapture, true) end
	playerDebounce[player] = nil
end)
local function connectPart(part)
	if part:IsA("BasePart") then part.Touched:Connect(onTouched) end
end
for _, descendant in ipairs(entity:GetDescendants()) do connectPart(descendant) end
entity.DescendantAdded:Connect(connectPart)
print("[EntityKill] Cinematic ground-pin knockout sequence active")
