--!strict
-- Level 2 Pool Foam Client
--
-- Sends camera telemetry only. The server decides whether a Pool Foam entity is
-- seen, where it may move, and when it can hurt a player. ClientEvent is only
-- local presentation: it cannot change gameplay, camera ownership, or assets.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PROTOCOL = 1
local REPORT_INTERVAL = 1 / 8
local REMOTE_FOLDER_NAME = "Level 2 Pool Foam Remotes"
local CLIENT_REPORT_NAME = "ClientReport"
local CLIENT_EVENT_NAME = "ClientEvent"
local AUDIO_LIBRARY_NAME = "Level 2 Pool Foam Audio"
-- Runtime entities carry this tag. PoolFoamSlot distinguishes Primary from
-- Secondary without making the client a gameplay authority.
local ENTITY_TAG = "Level2PoolFoamEntity"
local RENDER_STEP_NAME = "Level2PoolFoamLocalPresentation"

-- Deliberately blank. Add only reviewed, licensed Roblox audio IDs here. A
-- network event is never allowed to supply an arbitrary SoundId.
local SOUND_IDS: {[string]: string} = table.freeze({
	Cue = "",
	Reveal = "",
	Attack = "",
	Phase = "",
	Decoy = "",
})
local AUDIO_STATES: {[string]: boolean} = table.freeze({
	Idle = true,
	Walk = true,
	Caught = true,
	Hunt = true,
	Attack = true,
	Collapse = true,
})

-- Atmospheric whisper captions removed on request ("[the water grows
-- unnaturally still]" and friends): no bracketed status lines anywhere in
-- Level 2. The caption pipeline stays for explicitly authored server
-- captions, but none are sent today and no defaults exist.
local DEFAULT_CAPTIONS: {[string]: string} = table.freeze({})

local remoteFolder: Folder? = nil
local reportRemote: RemoteEvent? = nil
local eventRemote: RemoteEvent? = nil
local eventConnection: RBXScriptConnection? = nil
local connections: {RBXScriptConnection} = {}
local taggedEntities: {[Instance]: boolean} = {}
local reportSequence = 0
local reportClock = 0
local captionSerial = 0
local activeAttackId: string? = nil
local revealGeneration: number? = nil

local oldGui = playerGui:FindFirstChild("Level2PoolFoamGui")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "Level2PoolFoamGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 72
gui.Parent = playerGui

local caption = Instance.new("TextLabel")
caption.Name = "Caption"
caption.AnchorPoint = Vector2.new(0.5, 1)
caption.Position = UDim2.fromScale(0.5, 0.91)
caption.Size = UDim2.new(0.72, 0, 0, 50)
caption.BackgroundColor3 = Color3.fromRGB(5, 13, 16)
caption.BackgroundTransparency = 0.3
caption.BorderSizePixel = 0
caption.Font = Enum.Font.GothamMedium
caption.TextColor3 = Color3.fromRGB(232, 246, 240)
caption.TextStrokeColor3 = Color3.new(0, 0, 0)
caption.TextStrokeTransparency = 0.55
caption.TextSize = 19
caption.TextWrapped = true
caption.Visible = false
caption.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 7)
corner.Parent = caption

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.Parent = caption

local grade = Lighting:FindFirstChild("Level 2 Pool Foam Local Grade")
local gradeCreated = false
if not (grade and grade:IsA("ColorCorrectionEffect")) then
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "Level 2 Pool Foam Local Grade"
	grade.Parent = Lighting
	gradeCreated = true
end
local colorGrade = grade :: ColorCorrectionEffect
local initialGrade = {
	Enabled = colorGrade.Enabled,
	Brightness = colorGrade.Brightness,
	Contrast = colorGrade.Contrast,
	Saturation = colorGrade.Saturation,
	TintColor = colorGrade.TintColor,
}

type Effect = {
	StartedAt: number,
	Duration: number,
	Fov: number,
	Contrast: number,
	Saturation: number,
	Tint: Color3,
	Shake: number,
}
local activeEffect: Effect? = nil
local ownFovOffset = 0
local lastAppliedFov: number? = nil

local function numberAttribute(instance: Instance?, name: string): number?
	if not instance then return nil end
	local value = instance:GetAttribute(name)
	return typeof(value) == "number" and value or nil
end

local function currentGeneration(): number?
	return numberAttribute(remoteFolder, "Generation")
end

local function activeCharacter(): (Model?, Humanoid?, BasePart?, Camera?)
	if workspace:GetAttribute("SelectedLevel") ~= 2
		or workspace:GetAttribute("RoundActive") ~= true
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Spectating") == true
		or player:GetAttribute("IsSpectating") == true
	then
		return nil, nil, nil, nil
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not character or not humanoid or humanoid.Health <= 0 or not (root and root:IsA("BasePart")) or not camera then
		return nil, nil, nil, nil
	end

	-- Do not report a spectator camera as the local player's camera.
	local subject = camera.CameraSubject
	if subject and subject:IsA("Humanoid") and subject ~= humanoid then
		return nil, nil, nil, nil
	end
	if subject and subject:IsA("BasePart") and not subject:IsDescendantOf(character) then
		return nil, nil, nil, nil
	end
	return character, humanoid, root, camera
end

local function liveLevel2(): boolean
	return activeCharacter() ~= nil
end

local function captionsAllowed(): boolean
	return player:GetAttribute("DisableCaptions") ~= true and player:GetAttribute("CaptionsEnabled") ~= false
end

local function showCaption(text: unknown, duration: unknown)
	if not captionsAllowed() or typeof(text) ~= "string" then return end
	text = text:sub(1, 160)
	if text == "" then return end
	captionSerial += 1
	local serial = captionSerial
	caption.Text = text
	caption.Visible = true
	task.delay(math.clamp(typeof(duration) == "number" and duration or 1.6, 0.5, 4), function()
		if captionSerial == serial then caption.Visible = false end
	end)
end

local function resetPresentation()
	captionSerial += 1
	caption.Visible = false
	activeEffect = nil
	activeAttackId = nil
	colorGrade.Enabled = initialGrade.Enabled
	colorGrade.Brightness = initialGrade.Brightness
	colorGrade.Contrast = initialGrade.Contrast
	colorGrade.Saturation = initialGrade.Saturation
	colorGrade.TintColor = initialGrade.TintColor

	local camera = workspace.CurrentCamera
	if camera and lastAppliedFov and math.abs(camera.FieldOfView - lastAppliedFov) < 0.05 then
		camera.FieldOfView = math.clamp(camera.FieldOfView - ownFovOffset, 20, 100)
	end
	lastAppliedFov = nil
	ownFovOffset = 0
end

local function normalizedSoundId(value: string): string?
	if value:match("^%d+$") then return "rbxassetid://" .. value end
	if value:match("^rbxassetid://%d+$") then return value end
	return nil
end

local function playSound(kind: string, payload: {[any]: any})
	local rawId = SOUND_IDS[kind] or ""
	local slot = payload.Slot or payload.EntityId
	local audioState = payload.AudioState
	if (slot == "Primary" or slot == "Secondary")
		and typeof(audioState) == "string"
		and AUDIO_STATES[audioState]
	then
		local library = ReplicatedStorage:FindFirstChild(AUDIO_LIBRARY_NAME)
		local value = library and library:FindFirstChild(slot .. " " .. audioState)
		if value and value:IsA("StringValue") then rawId = value.Value end
	end
	local assetId = normalizedSoundId(rawId)
	if not assetId then return end
	local sound = Instance.new("Sound")
	sound.Name = "Level2PoolFoam" .. kind
	sound.SoundId = assetId
	sound.Volume = math.clamp(typeof(payload.Volume) == "number" and payload.Volume or 0.19, 0, 0.35)
	sound.PlaybackSpeed = math.clamp(typeof(payload.PlaybackSpeed) == "number" and payload.PlaybackSpeed or 1, 0.75, 1.25)
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, 8)
end

local function beginEffect(duration: number, intensity: number, fov: number, contrast: number, saturation: number, shake: number)
	activeEffect = {
		StartedAt = os.clock(),
		Duration = math.clamp(duration, 0.12, 1.1),
		Fov = fov * intensity,
		Contrast = contrast * intensity,
		Saturation = saturation * intensity,
		Tint = Color3.fromRGB(215, 242, 232),
		Shake = shake * intensity,
	}
end

local function captionFor(kind: string, payload: {[any]: any}): string?
	if payload.Caption == false then return nil end
	if typeof(payload.Caption) == "string" then return payload.Caption end
	return DEFAULT_CAPTIONS[kind]
end

local function matchesAttack(payload: {[any]: any}): boolean
	if activeAttackId == nil or payload.AttackId == nil then return true end
	return activeAttackId == tostring(payload.AttackId)
end

local function handleClientEvent(payload: unknown)
	if typeof(payload) ~= "table" or not liveLevel2() then return end
	local event = payload :: {[any]: any}
	if event.Protocol ~= nil and event.Protocol ~= PROTOCOL then return end
	local rawKind = event.Type or event.Kind
	if typeof(rawKind) ~= "string" then return end

	-- Compatibility aliases keep older server presentation calls harmless while
	-- the supported public contract remains Cue/Reveal/Attack/Phase/Decoy.
	local kind = rawKind
	if kind == "FirstReveal" then kind = "Reveal" end
	if kind == "AttackStart" or kind == "AttackHit" or kind == "AttackCancelled" then kind = "Attack" end
	if kind ~= "Cue" and kind ~= "Reveal" and kind ~= "Attack" and kind ~= "Phase" and kind ~= "Decoy" then return end

	local intensity = math.clamp(typeof(event.Intensity) == "number" and event.Intensity or 1, 0, 1)
	if kind == "Reveal" then
		local generation = currentGeneration()
		if generation and revealGeneration == generation then return end
		revealGeneration = generation
	elseif rawKind == "AttackCancelled" then
		if not matchesAttack(event) then return end
		resetPresentation()
		return
	elseif kind == "Attack" then
		if rawKind == "AttackHit" and not matchesAttack(event) then return end
		if rawKind ~= "AttackHit" then activeAttackId = event.AttackId ~= nil and tostring(event.AttackId) or nil end
	end

	playSound(kind, event)
	showCaption(captionFor(kind, event), event.CaptionDuration)
	if kind == "Cue" then
		if event.Emphasis == true then beginEffect(0.23, intensity, -0.45, 0.012, -0.02, 0.007) end
	elseif kind == "Reveal" then
		beginEffect(0.72, intensity, -1.35, 0.04, -0.07, 0.018)
	elseif kind == "Attack" then
		beginEffect(rawKind == "AttackHit" and 0.55 or 0.44, intensity, rawKind == "AttackHit" and 1.8 or -1.1, 0.06, -0.1, 0.045)
		if rawKind == "AttackHit" then activeAttackId = nil end
	elseif kind == "Phase" then
		beginEffect(0.5, intensity, -0.7, 0.018, -0.04, 0.01)
	elseif kind == "Decoy" then
		beginEffect(0.3, intensity, -0.35, 0.01, -0.02, 0.006)
	end
end

local function resolveRemotes()
	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	local nextFolder = folder and folder:IsA("Folder") and folder or nil
	local nextReport = nextFolder and nextFolder:FindFirstChild(CLIENT_REPORT_NAME)
	local nextEvent = nextFolder and nextFolder:FindFirstChild(CLIENT_EVENT_NAME)
	if nextReport and not nextReport:IsA("RemoteEvent") then nextReport = nil end
	if nextEvent and not nextEvent:IsA("RemoteEvent") then nextEvent = nil end

	remoteFolder = nextFolder
	reportRemote = nextReport :: RemoteEvent?
	if eventRemote ~= nextEvent then
		if eventConnection then eventConnection:Disconnect() end
		eventConnection = nil
		eventRemote = nextEvent :: RemoteEvent?
		if eventRemote then eventConnection = eventRemote.OnClientEvent:Connect(handleClientEvent) end
	end
end

local function refreshTaggedEntities()
	table.clear(taggedEntities)
	local world = workspace:FindFirstChild("Level 2 Generated World")
	for _, entity in ipairs(CollectionService:GetTagged(ENTITY_TAG)) do
		if not world or entity:IsDescendantOf(world) then taggedEntities[entity] = true end
	end
end

local function sendReport()
	local _, _, _, camera = activeCharacter()
	local generation = currentGeneration()
	if not camera or not reportRemote or not remoteFolder or not generation then return end
	-- This LocalScript never creates remotes. Therefore this call can only use a
	-- replicated RemoteEvent supplied by the server, never a client fallback.
	reportSequence += 1
	reportRemote:FireServer({
		Protocol = PROTOCOL,
		Generation = generation,
		Sequence = reportSequence,
		CameraCFrame = camera.CFrame,
		FieldOfView = camera.FieldOfView,
		ViewportSize = camera.ViewportSize,
	})
end

table.insert(connections, ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == REMOTE_FOLDER_NAME then task.defer(resolveRemotes) end
end))
table.insert(connections, ReplicatedStorage.ChildRemoved:Connect(function(child)
	if child == remoteFolder then task.defer(resolveRemotes) end
end))
table.insert(connections, ReplicatedStorage.DescendantAdded:Connect(function(instance)
	if instance.Name == CLIENT_REPORT_NAME or instance.Name == CLIENT_EVENT_NAME then task.defer(resolveRemotes) end
end))
table.insert(connections, CollectionService:GetInstanceAddedSignal(ENTITY_TAG):Connect(refreshTaggedEntities))
table.insert(connections, CollectionService:GetInstanceRemovedSignal(ENTITY_TAG):Connect(refreshTaggedEntities))
table.insert(connections, workspace.ChildAdded:Connect(function(child)
	if child.Name == "Level 2 Generated World" then refreshTaggedEntities() end
end))
table.insert(connections, workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Level 2 Generated World" then
		table.clear(taggedEntities)
		resetPresentation()
	end
end))
table.insert(connections, player.CharacterAdded:Connect(function()
	resetPresentation()
	task.defer(refreshTaggedEntities)
end))
for _, attribute in ipairs({"InRound", "Escaped", "Spectating", "IsSpectating"}) do
	table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(function()
		if not liveLevel2() then resetPresentation() end
	end))
end
table.insert(connections, workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(function()
	if not liveLevel2() then resetPresentation() end
end))
table.insert(connections, workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if not liveLevel2() then resetPresentation() end
end))

RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local baseFov = camera.FieldOfView
	if lastAppliedFov and math.abs(baseFov - lastAppliedFov) < 0.05 then baseFov -= ownFovOffset end
	lastAppliedFov = nil
	ownFovOffset = 0
	if not liveLevel2() or not activeEffect then
		colorGrade.Enabled = initialGrade.Enabled
		return
	end

	local effect = activeEffect
	local progress = math.clamp((os.clock() - effect.StartedAt) / effect.Duration, 0, 1)
	if progress >= 1 then
		activeEffect = nil
		colorGrade.Enabled = initialGrade.Enabled
		camera.FieldOfView = math.clamp(baseFov, 20, 100)
		return
	end
	local fade = (1 - progress) ^ 2
	local visualFade = player:GetAttribute("ReduceFlashing") == true and fade * 0.3 or fade
	colorGrade.Enabled = true
	colorGrade.Brightness = initialGrade.Brightness
	colorGrade.Contrast = initialGrade.Contrast + effect.Contrast * visualFade
	colorGrade.Saturation = initialGrade.Saturation + effect.Saturation * visualFade
	colorGrade.TintColor = initialGrade.TintColor:Lerp(effect.Tint, visualFade)
	local appliedFov = math.clamp(baseFov + effect.Fov * fade, 20, 100)
	camera.FieldOfView = appliedFov
	ownFovOffset = appliedFov - baseFov
	lastAppliedFov = appliedFov
	if player:GetAttribute("ReduceCameraShake") ~= true then
		local n = os.clock()
		local shake = effect.Shake * fade
		-- Rotation is a one-frame additive nudge after Roblox's camera update;
		-- CameraType, CameraSubject, and player movement remain untouched.
		camera.CFrame *= CFrame.Angles(math.rad(math.noise(n * 17) * shake), math.rad(math.noise(n * 23, 4) * shake), 0)
	end
end)

table.insert(connections, RunService.Heartbeat:Connect(function(deltaTime)
	if not liveLevel2() then reportClock = 0 return end
	reportClock += math.min(deltaTime, REPORT_INTERVAL * 2)
	if reportClock >= REPORT_INTERVAL then
		reportClock %= REPORT_INTERVAL
		sendReport()
	end
end))

script.Destroying:Connect(function()
	if eventConnection then eventConnection:Disconnect() end
	for _, connection in ipairs(connections) do connection:Disconnect() end
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	resetPresentation()
	gui:Destroy()
	if gradeCreated then colorGrade:Destroy() end
end)

resolveRemotes()
refreshTaggedEntities()
