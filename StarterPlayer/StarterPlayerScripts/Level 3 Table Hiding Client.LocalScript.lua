--!strict
-- Level 3 Table Hiding Client
-- Mobile/desktop leave control, the shared all-client crouch animation, and a
-- camera point physically inside the table. Entry uses one cross-device prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIDevice = require(ReplicatedStorage:WaitForChild("UIDevice"))
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local requestRemote: RemoteEvent? = nil

local hiding = false

-- Ordinary crouching retains its low gait. Level 3 table hiding uses the
-- separately authored hold below and its uploaded animation. Clients evaluate
-- the procedural fallback for
-- every replicated crouching/hidden player because AnimationConstraint.Transform
-- itself does not replicate. There is deliberately only one pose writer.
local RAD = math.rad
local CROUCH_POSE = {
	Root = CFrame.new(0, -0.92, 0.12) * CFrame.Angles(RAD(-8), 0, 0),
	Waist = CFrame.Angles(RAD(-34), 0, 0),
	Neck = CFrame.Angles(RAD(23), 0, 0),
	LeftHip = CFrame.Angles(RAD(106), RAD(7), RAD(-4)),
	RightHip = CFrame.Angles(RAD(106), RAD(-7), RAD(4)),
	LeftKnee = CFrame.Angles(RAD(-121), 0, 0),
	RightKnee = CFrame.Angles(RAD(-121), 0, 0),
	LeftAnkle = CFrame.Angles(RAD(18), 0, 0),
	RightAnkle = CFrame.Angles(RAD(18), 0, 0),
	LeftShoulder = CFrame.Angles(RAD(31), RAD(-5), RAD(-17)),
	RightShoulder = CFrame.Angles(RAD(31), RAD(5), RAD(17)),
	LeftElbow = CFrame.Angles(RAD(-64), 0, RAD(-5)),
	RightElbow = CFrame.Angles(RAD(-64), 0, RAD(5)),
}
-- Frame 0 of the Blender hold, fitted to the actual hazmat meshes. Kept as a
-- local fallback while the group-owned asset loads or if it is unavailable.
local HIDE_POSE = {
	Root = CFrame.new(0, -0.327591755, 0.471597579, 1, 0, 0, 0, 0.980363428, -0.197199264, 0, 0.197199264, 0.980363428),
	Waist = CFrame.new(0, 0, 0, 1, 0, 0, 0, -0.230934263, 0.972969355, 0, -0.972969355, -0.230934263),
	Neck = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.342020143, -0.939692621, 0, 0.939692621, 0.342020143),
	LeftHip = CFrame.new(0, 0, 0, 0.992546152, 0, 0.121869343, 0.075395165, -0.785662216, -0.61404434, 0.095748138, 0.618655706, -0.779806009),
	LeftKnee = CFrame.new(0, 0, 0, 1, 0, 0, 0, -0.925527725, 0.378679852, 0, -0.378679852, -0.925527725),
	LeftAnkle = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.99394982, -0.109835129, 0, 0.109835129, 0.99394982),
	LeftShoulder = CFrame.new(0, 0, 0, 0.286578739, 0.320678384, 0.90279455, -0.671238927, -0.605165734, 0.428033571, 0.68360144, -0.728656166, 0.041824181),
	LeftElbow = CFrame.new(0, 0, 0, 0.498097349, 0.043577871, 0.866025404, -0.602258954, -0.701149179, 0.381672611, 0.62384548, -0.711681669, -0.322995384),
	LeftWrist = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
	RightHip = CFrame.new(0, 0, 0, 0.992546152, 0, -0.121869343, -0.075395165, -0.785662216, -0.61404434, -0.095748138, 0.618655706, -0.779806009),
	RightKnee = CFrame.new(0, 0, 0, 1, 0, 0, 0, -0.925527725, 0.378679852, 0, -0.378679852, -0.925527725),
	RightAnkle = CFrame.new(0, 0, 0, 1, 0, 0, 0, 0.99394982, -0.109835129, 0, 0.109835129, 0.99394982),
	RightShoulder = CFrame.new(0, 0, 0, 0.286578739, -0.320678384, -0.90279455, 0.671238927, -0.605165734, 0.428033571, -0.68360144, -0.728656166, 0.041824181),
	RightElbow = CFrame.new(0, 0, 0, 0.498097349, -0.043577871, -0.866025404, 0.602258954, -0.701149179, 0.381672611, -0.62384548, -0.711681669, -0.322995384),
	RightWrist = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1),
}
local jointCache = setmetatable({}, {__mode = "k"})
local poseStates = setmetatable({}, {__mode = "k"})

local function jointsFor(character: Model): {Instance}
	local cached = jointCache[character]
	if cached then return cached end
	local joints = {}
	for _, object in ipairs(character:GetDescendants()) do
		if (object:IsA("AnimationConstraint") or object:IsA("Motor6D"))
			and (CROUCH_POSE[object.Name] ~= nil or HIDE_POSE[object.Name] ~= nil) then
			table.insert(joints, object)
		end
	end
	jointCache[character] = joints
	return joints
end

local function writeJointTransform(joint: Instance, transform: CFrame)
	if joint:IsA("AnimationConstraint") then
		joint.Transform = transform
	elseif joint:IsA("Motor6D") then
		joint.Transform = transform
	end
end

local function isCrouching(targetPlayer: Player): boolean
	-- The owner predicts locally for immediate camera/pose response while every
	-- other observer waits for the server-owned attribute. Local truth must also
	-- own EXIT so a stale replicated true cannot hold our body down for one RTT.
	if targetPlayer == player then
		return targetPlayer:GetAttribute("LocalCrouching") == true
	end
	return targetPlayer:GetAttribute("Crouching") == true
end

local function poseAllowed(targetPlayer: Player, character: Model): (boolean, boolean)
	local hidden = workspace:GetAttribute("SelectedLevel") == 3
		and targetPlayer:GetAttribute("Level3_Hiding") == true
	local ordinaryCrouch = targetPlayer:GetAttribute("InRound") == true
		and (workspace:GetAttribute("RoundActive") == true
			or targetPlayer:GetAttribute("Level6PlaygroundPreview") == true)
		and isCrouching(targetPlayer)
	if not hidden and not ordinaryCrouch then return false, false end
	if not hidden and (character:GetAttribute("Level2_ForcedSliding") == true
		or character:GetAttribute("Level2_RagdollServerActive") == true) then
		return false, false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0, hidden
end

local function animatedTransform(jointName: string, hidden: boolean,
	phase: number, gaitWeight: number): CFrame
	if hidden then
		local transform = HIDE_POSE[jointName] or CFrame.identity
		local breath = math.sin(os.clock() * math.pi / 2)
		if jointName == "Waist" then
			transform *= CFrame.Angles(RAD(breath * .20), 0, 0)
		elseif jointName == "Neck" then
			transform *= CFrame.Angles(RAD(-breath * .15), 0, 0)
		end
		return transform
	end
	local transform = CROUCH_POSE[jointName] or CFrame.identity
	local stride = if hidden then 0 else math.sin(phase) * gaitWeight
	local counterStride = if hidden then 0 else math.sin(phase + math.pi) * gaitWeight
	if jointName == "Root" then
		transform *= CFrame.new(0, -math.abs(math.sin(phase * 2)) * .035 * gaitWeight, 0)
	elseif jointName == "Waist" then
		local breath = math.sin(os.clock() * 1.55) * .7
		transform *= CFrame.Angles(RAD(breath), RAD(stride * 1.4), RAD(stride * 1.1))
	elseif jointName == "LeftHip" then
		transform *= CFrame.Angles(RAD(stride * 8), 0, RAD(-stride * 1.5))
	elseif jointName == "RightHip" then
		transform *= CFrame.Angles(RAD(counterStride * 8), 0, RAD(-counterStride * 1.5))
	elseif jointName == "LeftKnee" then
		transform *= CFrame.Angles(RAD(math.max(0, -stride) * -9), 0, 0)
	elseif jointName == "RightKnee" then
		transform *= CFrame.Angles(RAD(math.max(0, -counterStride) * -9), 0, 0)
	elseif jointName == "LeftAnkle" then
		transform *= CFrame.Angles(RAD(stride * -4), 0, 0)
	elseif jointName == "RightAnkle" then
		transform *= CFrame.Angles(RAD(counterStride * -4), 0, 0)
	elseif jointName == "LeftShoulder" then
		transform *= CFrame.Angles(RAD(counterStride * 3.5), 0, RAD(stride * 1.5))
	elseif jointName == "RightShoulder" then
		transform *= CFrame.Angles(RAD(stride * 3.5), 0, RAD(counterStride * 1.5))
	end
	return transform
end

local function hideTrackReady(targetPlayer: Player, character: Model): boolean
	local id = targetPlayer:GetAttribute("Level3_HideAnimationId")
	if type(id) ~= "string" or id == "" then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return false end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Animation and track.Animation.AnimationId == id
			and track.IsPlaying and track.Length > 0 and track.WeightCurrent > .99 then
			return true
		end
	end
	return false
end

-- Animator writes first; PreSimulation owns the final crouch for this frame.
-- Weight and gait are eased for ordinary crouching. Hidden players use the
-- fitted hold immediately because their server root is already under the table.
RunService.PreSimulation:Connect(function(deltaTime)
	local seen = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local character = targetPlayer.Character
		if not character or not character.Parent then continue end
		seen[character] = true
		local active, hidden = poseAllowed(targetPlayer, character)
		if active and hidden and hideTrackReady(targetPlayer, character) then
			-- Animator has already written this frame. Do not overwrite it on the
			-- owner OR other clients. Missing/denied content keeps the old fallback.
			poseStates[character] = nil
			continue
		end
		local poseState = poseStates[character]
		if not poseState and not active then continue end
		if not poseState then
			poseState = {Weight=0, GaitWeight=0, Phase=0}
			poseStates[character] = poseState
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		local flatSpeed = 0
		if active and not hidden and root and root:IsA("BasePart") then
			local velocity = root.AssemblyLinearVelocity
			flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		end
		local gaitTarget = active and not hidden and flatSpeed > .75 and 1 or 0
		local gaitAlpha = math.clamp(deltaTime * 10, 0, 1)
		poseState.GaitWeight += (gaitTarget - poseState.GaitWeight) * gaitAlpha
		if gaitTarget > 0 then
			poseState.Phase += deltaTime * 7.5 * math.clamp(flatSpeed / 8, .5, 1.35)
		end
		if hidden then
			-- The server has already pivoted the rig inside solid furniture. Land on
			-- the proven hide pose immediately; only ordinary crouch uses the blend.
			poseState.Weight = 1
			poseState.GaitWeight = 0
		else
			local poseAlpha = math.clamp(deltaTime * (active and 16 or 12), 0, 1)
			poseState.Weight += ((active and 1 or 0) - poseState.Weight) * poseAlpha
		end

		for _, joint in ipairs(jointsFor(character)) do
			local desired = animatedTransform(joint.Name, hidden,
				poseState.Phase, poseState.GaitWeight)
			writeJointTransform(joint, CFrame.new():Lerp(desired, poseState.Weight))
		end
		if not active and poseState.Weight < .002 then
			for _, joint in ipairs(jointsFor(character)) do
				writeJointTransform(joint, CFrame.new())
			end
			poseStates[character] = nil
		end
	end
	for character in pairs(poseStates) do
		if not seen[character] then
			for _, joint in ipairs(jointsFor(character)) do
				writeJointTransform(joint, CFrame.new())
			end
			poseStates[character] = nil
		end
	end
end)

-- A custom camera point is replicated by the server at the physical hide
-- anchor. Hide only the local head/torso with LocalTransparencyModifier so the
-- near plane stays clean; Transparency is never changed, so everyone else
-- continues to see the player's crouched body.
local localClipOriginal = {}
local CLIP_PARTS = {Head=true, UpperTorso=true, LowerTorso=true}
local function setLocalCameraClipping(active: boolean)
	if not active then
		for object, transparency in pairs(localClipOriginal) do
			if object.Parent then object.LocalTransparencyModifier = transparency end
		end
		table.clear(localClipOriginal)
		return
	end
	local character = player.Character
	if not character then return end
	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart")
			and (CLIP_PARTS[object.Name] == true or object.Parent:IsA("Accessory")) then
			if localClipOriginal[object] == nil then
				localClipOriginal[object] = object.LocalTransparencyModifier
			end
			object.LocalTransparencyModifier = 1
		end
	end
end

RunService:BindToRenderStep("Level3UnderTableCamera",
	Enum.RenderPriority.Camera.Value + 1, function()
		if player:GetAttribute("Level3_Hiding") ~= true then return end
		local camera = workspace.CurrentCamera
		if not camera then return end
		local cameraPosition = player:GetAttribute("Level3_HideCameraPosition")
		if typeof(cameraPosition) ~= "Vector3" then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then return end
			cameraPosition = root.Position + Vector3.new(0, -0.45, 0)
		end
		setLocalCameraClipping(true)
		local rotation = camera.CFrame.Rotation
		camera.CFrame = CFrame.new(cameraPosition) * rotation
		camera.Focus = CFrame.new(cameraPosition + camera.CFrame.LookVector * 12)
	end)

local gui = Instance.new("ScreenGui")
gui.Name = "Level3TableHideUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 92
gui.Enabled = false
gui.Parent = playerGui

local shade = Instance.new("Frame")
shade.Name = "UnderTableShade"
shade.Size = UDim2.fromScale(1, 1)
shade.BackgroundColor3 = Color3.fromRGB(6, 5, 5)
shade.BackgroundTransparency = .76
shade.BorderSizePixel = 0
shade.Active = false
shade.Parent = gui

local topBar = Instance.new("Frame")
topBar.Name = "TableEdgeTop"
topBar.Size = UDim2.new(1, 0, 0, 34)
topBar.BackgroundColor3 = Color3.fromRGB(23, 18, 15)
topBar.BackgroundTransparency = .08
topBar.BorderSizePixel = 0
topBar.Parent = gui

local bottomBar = topBar:Clone()
bottomBar.Name = "TableEdgeBottom"
bottomBar.AnchorPoint = Vector2.new(0, 1)
bottomBar.Position = UDim2.fromScale(0, 1)
bottomBar.Parent = gui

-- B7: the server/camera/pose owners above stay unchanged.
local Hud = require(ReplicatedStorage:WaitForChild("RoundHud"))
local Binder = require(ReplicatedStorage:WaitForChild("ZyntraShopUI"):WaitForChild("ShopBinder"))
local bannerRoot, leaveRoot, checkRoot
local bannerAttention, leaveAttention
local message, leave, secondsLabel, checkFill
local checkFillWidth = 1
local warningDeadline, warningStart = 0, 0
local leaveConnection
local requestExit
local function mountHiding()
	if leaveConnection then leaveConnection:Disconnect() end
	for _, root in ipairs({bannerRoot, leaveRoot, checkRoot}) do if root then root:Destroy() end end
	local touch = UIDevice.Layout().IsTouch
	local suffix = touch and "Touch" or ""
	bannerRoot, bannerAttention = Hud.Mount("HUD_Screens", "HidingBanner" .. suffix, gui,
		{Name = "HiddenStatus", Attention = {Hold = 6, Rest = 0.45}})
	leaveRoot, leaveAttention = Hud.Mount("HUD_Screens", "LeaveHiding" .. suffix, gui,
		{Name = "LeaveHiding", Attention = {Hold = 6, Rest = 0.55}})
	checkRoot = Hud.Mount("HUD_Screens", "TableCheck" .. suffix, gui, {Name = "TableCheck"})
	if not (bannerRoot and leaveRoot and checkRoot) then
		warn("Level 3 hiding: missing imported HUD templates")
		return
	end
	message = Binder.text(Binder.at(bannerRoot, "Banner"))
	leave = Binder.button(leaveRoot, "LeaveHit")
	leaveConnection = leave.Activated:Connect(function() if requestExit then requestExit() end end)
	secondsLabel = Binder.text(Binder.at(checkRoot, "Seconds"))
	checkFill = Binder.at(checkRoot, "Track/Fill")
	checkFillWidth = checkFill.Size.X.Scale
	Hud.Keycap(Binder.at(leaveRoot, "KeyChip"), Enum.KeyCode.E, Enum.KeyCode.ButtonB)
	checkRoot.Visible = false
end
local function applyHidingLayout()
	if not bannerRoot or not leaveRoot or not checkRoot then return end
	local layout = UIDevice.Layout()
	local safe = layout.Safe
	local centre = (safe.Left + safe.Right) / 2
	local top = safe.Top + (layout.IsTouch and 6 or 16)
	if layout.IsTouch then
		local band = layout.TopBand
		if band then centre = (band.Left + band.Right) / 2 end
	end
	for _, root in ipairs({bannerRoot, checkRoot, leaveRoot}) do root.AnchorPoint = Vector2.new(0.5, 0) end
	bannerRoot.Position = UIDevice.LocalPosition(gui, centre, top)
	checkRoot.Position = UIDevice.LocalPosition(gui, centre, top + 30)
	local leaveTop = top + 30 + (checkRoot.Visible and checkRoot.Size.Y.Offset + 6 or 0)
	local leaveCentre = centre
	if layout.IsTouch then
		local width, height = leaveRoot.Size.X.Offset, leaveRoot.Size.Y.Offset
		local zone = layout.Zones.Thumbstick
		if centre - width / 2 < zone.Right and centre + width / 2 > zone.Left
			and leaveTop < zone.Bottom and leaveTop + height > zone.Top then
			-- The short landscape screen's movement region reaches this row.
			-- Keep the authored hit target in the clear column to its right.
			local candidate = zone.Right + 8 + width / 2
			if candidate + width / 2 <= safe.Right
				and UIDevice.OverlapsMovementZone(candidate - width / 2, leaveTop,
					candidate + width / 2, leaveTop + height) == nil then
				leaveCentre = candidate
			end
		end
	end
	leaveRoot.Position = UIDevice.LocalPosition(gui, leaveCentre, leaveTop)
end
mountHiding()
applyHidingLayout()

-- LEVEL3_MANAGER_TABLE_CHECK_20260904
-- The Mall Manager kneels at one hiding table and gives whoever is under it a
-- short window to leave. The server publishes which table (by its
-- Level3_HideTableIndex) and when the window closes, in server-time, so only
-- that table's occupants are warned. This reuses the existing hidden banner
-- rather than adding a second panel over an already tight mobile layout.
local HIDDEN_TEXT = "HIDDEN UNDER TABLE"
local level3State: Instance? = nil

local function tableCheckWarned(): boolean
	local state = level3State
	if not state or not hiding then return false end
	local index = tonumber(state:GetAttribute("Level3_MallManagerTableCheckIndex")) or 0
	if index == 0 or index ~= (tonumber(player:GetAttribute("Level3_HideTableIndex")) or 0) then
		return false
	end
	local endsAt = tonumber(state:GetAttribute("Level3_MallManagerTableCheckEndsAt")) or 0
	return workspace:GetServerTimeNow() < endsAt
end

local function refreshWarning()
	if not bannerRoot or not leaveRoot or not checkRoot then return end
	local warned = tableCheckWarned()
	if not hiding then
		bannerAttention:Hide()
		leaveAttention:Hide()
		checkRoot.Visible = false
		warningDeadline, warningStart = 0, 0
		return
	end
	bannerAttention:Show("HIDDEN", warned)
	leaveAttention:Show("HIDDEN", warned)
	local changed = checkRoot.Visible ~= warned
	checkRoot.Visible = warned
	shade.BackgroundTransparency = warned and .5 or .76
	if warned then
		local deadline = tonumber(level3State:GetAttribute("Level3_MallManagerTableCheckEndsAt")) or 0
		local now = workspace:GetServerTimeNow()
		if deadline ~= warningDeadline then warningDeadline, warningStart = deadline, now end
		local remaining = math.max(0, deadline - now)
		secondsLabel.Text = string.format("%.1f s", remaining)
		checkFill.Size = UDim2.new(checkFillWidth * math.clamp(remaining / math.max(.01, deadline - warningStart), 0, 1), 0, 1, 0)
	end
	if changed then applyHidingLayout() end
end
RunService.Heartbeat:Connect(function() if hiding then refreshWarning() end end)
UIDevice.Changed:Connect(function()
	mountHiding()
	refreshWarning()
	applyHidingLayout()
end)

task.spawn(function()
	level3State = ReplicatedStorage:WaitForChild("Level 3 State")
end)

requestExit = function()
	if not hiding or not requestRemote then return end
	requestRemote:FireServer("EXIT")
end

local function apply()
	local shouldHide = player:GetAttribute("Level3_Hiding") == true
		and player:GetAttribute("InRound") == true
		and workspace:GetAttribute("SelectedLevel") == 3
	if RunService:IsStudio()
		and player:GetAttribute("UIRegressionForceHiding") == true then
		shouldHide = true
	end
	-- Two players share a table, so the anchor's prompt stays Enabled while the
	-- second lane is free. Without this the FIRST occupant sits under the table
	-- looking at a HIDE UNDER TABLE prompt that can only ever answer
	-- ALREADY_HIDDEN -- and the core prompt UI binds its KeyboardKeyCode, which
	-- for this prompt is E, the advertised leave key, so E arrives here already
	-- game-processed and is dropped. A hidden player is anchored at WalkSpeed 0
	-- and cannot use any prompt anyway, so all of them go away for the duration.
	-- ProximityPromptService.Enabled is a client-only property (LocalScript
	-- writes only); it does not replicate, and nothing else in the game sets it.
	ProximityPromptService.Enabled = not shouldHide
	if shouldHide == hiding then
		gui.Enabled = shouldHide
		setLocalCameraClipping(player:GetAttribute("Level3_Hiding") == true)
		refreshWarning()
		return
	end
	hiding = shouldHide
	gui.Enabled = hiding
	setLocalCameraClipping(player:GetAttribute("Level3_Hiding") == true)
	refreshWarning()
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not hiding then return end
	-- UI owns processed input. RoundUI passes B through while hiding, so an
	-- unprocessed B still exits, but closing a menu must not release cover.
	if processed or UserInputService:GetFocusedTextBox() ~= nil then return end
	if input.KeyCode == Enum.KeyCode.E
		or input.KeyCode == Enum.KeyCode.ButtonB
		or input.KeyCode == Enum.KeyCode.ButtonX then
		requestExit()
	end
end)

player:GetAttributeChangedSignal("Level3_Hiding"):Connect(apply)
if RunService:IsStudio() then
	player:GetAttributeChangedSignal("UIRegressionForceHiding"):Connect(apply)
end
player:GetAttributeChangedSignal("InRound"):Connect(apply)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(apply)
player.CharacterAdded:Connect(function()
	setLocalCameraClipping(false)
	hiding = false
	task.defer(apply)
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("Level 3 Remotes")
	local candidate = folder:WaitForChild("Level3HideRequest")
	if candidate:IsA("RemoteEvent") then requestRemote = candidate end
end)

apply()
