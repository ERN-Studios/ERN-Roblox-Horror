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

-- This is the game's canonical runtime-authored R15 crouch animation. Its base
-- pose is the exact under-table silhouette; ordinary crouching layers a small,
-- low gait over that same pose while moving. Every client evaluates it for
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
local jointCache = setmetatable({}, {__mode = "k"})
local poseStates = setmetatable({}, {__mode = "k"})

local function jointsFor(character: Model): {Instance}
	local cached = jointCache[character]
	if cached then return cached end
	local joints = {}
	for _, object in ipairs(character:GetDescendants()) do
		if (object:IsA("AnimationConstraint") or object:IsA("Motor6D"))
			and CROUCH_POSE[object.Name] ~= nil then
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
		and workspace:GetAttribute("RoundActive") == true
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
	local transform = CROUCH_POSE[jointName]
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

-- Animator writes first; PreSimulation owns the final crouch for this frame.
-- Weight and gait are eased, so entering/exiting never snaps and a stationary
-- crouch settles back to the exact Level 3 hiding pose instead of skating.
RunService.PreSimulation:Connect(function(deltaTime)
	local seen = {}
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		local character = targetPlayer.Character
		if not character or not character.Parent then continue end
		seen[character] = true
		local active, hidden = poseAllowed(targetPlayer, character)
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

local message = Instance.new("TextLabel")
message.Name = "HiddenStatus"
message.AnchorPoint = Vector2.new(.5, 0)
message.Position = UDim2.new(.5, 0, 0, 45)
message.Size = UDim2.new(0, 360, 0, 42)
message.BackgroundColor3 = Color3.fromRGB(8, 10, 11)
message.BackgroundTransparency = .24
message.BorderSizePixel = 0
message.Font = Enum.Font.GothamBold
message.Text = "HIDDEN UNDER TABLE"
message.TextColor3 = Color3.fromRGB(186, 245, 225)
message.TextScaled = true
message.Parent = gui
local messageCorner = Instance.new("UICorner")
messageCorner.CornerRadius = UDim.new(0, 8)
messageCorner.Parent = message
local messageStroke = Instance.new("UIStroke")
messageStroke.Color = Color3.fromRGB(79, 183, 157)
messageStroke.Transparency = .2
messageStroke.Thickness = 1.5
messageStroke.Parent = message

local leave = Instance.new("TextButton")
leave.Name = "LeaveHiding"
leave.AnchorPoint = Vector2.new(.5, 1)
leave.Position = UDim2.new(.5, 0, 1, -54)
leave.Size = UDim2.new(0, 330, 0, 58)
leave.BackgroundColor3 = Color3.fromRGB(17, 22, 23)
leave.BackgroundTransparency = .08
leave.BorderSizePixel = 0
leave.AutoButtonColor = true
leave.Font = Enum.Font.GothamBold
leave.TextColor3 = Color3.fromRGB(236, 248, 243)
leave.TextScaled = true
-- Captioned once at load in the old build, so a tablet that gained a keyboard
-- kept reading "TAP" forever. It is now rebuilt on every UIDevice.Changed.
leave.Text = "LEAVE HIDING"
leave.Parent = gui
local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = UDim.new(0, 10)
leaveCorner.Parent = leave
local leaveStroke = Instance.new("UIStroke")
leaveStroke.Color = Color3.fromRGB(101, 224, 187)
leaveStroke.Transparency = .05
leaveStroke.Thickness = 2
leaveStroke.Parent = leave

-- Both panels were fixed-size (360 and 330 wide). At 375x667 the leave button
-- ran under the JUMP control and the message ran to within 7px of both edges.
-- They now size to the safe width and sit inside the safe content band.
local function applyHidingLayout()
	local layout = UIDevice.Layout()
	if layout.IsTouch then
		local band = layout.TopBand
		local centre = (band.Left + band.Right) * .5
		local landscape = not layout.Portrait
		local leaveHeight = landscape and 44 or 52
		local gap = 6
		local messageHeight = landscape and 30 or 42
		if messageHeight + gap + leaveHeight > band.Height then
			messageHeight = math.max(22, band.Height - gap - leaveHeight)
		end
		-- Absolute -> gui offsets, both axes.
		message.AnchorPoint = Vector2.new(.5, 0)
		message.Position = UIDevice.LocalPosition(gui, centre, band.Top)
		message.Size = UDim2.fromOffset(math.min(360, band.Width), messageHeight)
		leave.AnchorPoint = Vector2.new(.5, 0)
		leave.Position = UIDevice.LocalPosition(gui, centre, band.Top + messageHeight + gap)
		leave.Size = UDim2.fromOffset(math.min(330, band.Width), leaveHeight)
	else
		local available = layout.SafeRight - layout.SafeLeft
		message.AnchorPoint = Vector2.new(.5, 0)
		message.Size = UDim2.new(0, math.min(360, available), 0, 42)
		message.Position = UDim2.new(.5, 0, 0, 45)
		leave.AnchorPoint = Vector2.new(.5, 1)
		leave.Size = UDim2.new(0, math.min(330, available), 0, 58)
		leave.Position = UDim2.new(.5, 0, 1, -54)
	end
	leave.Text = UIDevice.Caption("LEAVE HIDING", "//  E", "//  B")
end
applyHidingLayout()
UIDevice.Changed:Connect(applyHidingLayout)

-- LEVEL3_MANAGER_TABLE_CHECK_20260904
-- The Mall Manager kneels at one hiding table and gives whoever is under it a
-- short window to leave. The server publishes which table (by its
-- Level3_HideTableIndex) and when the window closes, in server-time, so only
-- that table's occupants are warned. This reuses the existing hidden banner
-- rather than adding a second panel over an already tight mobile layout.
local HIDDEN_TEXT = "HIDDEN UNDER TABLE"
local HIDDEN_COLOR = Color3.fromRGB(186, 245, 225)
local HIDDEN_STROKE = Color3.fromRGB(79, 183, 157)
local WARNING_TEXT = "SOMETHING IS LOOKING UNDER THE TABLE"
local WARNING_COLOR = Color3.fromRGB(255, 226, 226)
local WARNING_STROKE = Color3.fromRGB(226, 74, 74)
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
	local warned = tableCheckWarned()
	message.Text = if warned then WARNING_TEXT else HIDDEN_TEXT
	message.TextColor3 = if warned then WARNING_COLOR else HIDDEN_COLOR
	messageStroke.Color = if warned then WARNING_STROKE else HIDDEN_STROKE
	shade.BackgroundTransparency = if warned then .5 else .76
end

-- The window closes on a timestamp, not an attribute edge, so this has to tick.
-- It costs two attribute reads a frame while hidden and returns immediately the
-- rest of the time.
RunService.Heartbeat:Connect(function()
	if not hiding and message.Text == HIDDEN_TEXT then return end
	refreshWarning()
end)

task.spawn(function()
	level3State = ReplicatedStorage:WaitForChild("Level 3 State")
end)

local function requestExit()
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

leave.Activated:Connect(requestExit)
UserInputService.InputBegan:Connect(function(input, processed)
	if not hiding then return end
	-- RoundUI can consume B to dismiss a transmission. While hidden, B is also
	-- the advertised leave control, so it must still release the table in that
	-- same frame instead of making the player press it twice.
	if processed and input.KeyCode ~= Enum.KeyCode.ButtonB then return end
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
