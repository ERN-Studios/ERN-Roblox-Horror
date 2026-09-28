-- Developer-only E preview entry launches the current playable Level 5 map.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

local DOOR_NAME = "Level5SealedDoor"
local PREVIEW_NAME = "Level 5 Architecture Preview"
local MARKER_NAME = "Level5DeveloperPreviewArrival"
local ENTER_PROMPT = "Level5DeveloperPreviewPrompt"
local PLAY_PROMPT = "Level5DeveloperPlayPrompt"
local RETURN_PROMPT = "Level5DeveloperPreviewReturnPrompt"
local RETURN_POINT = "Level5DeveloperPreviewReturnPoint"
local GALLERY_VERSION = "reference-gallery-2026-09-27-v1"
-- Isolate this draft gallery from playable Level 5 and the old X=31000 static preview.
local ORIGIN = Vector3.new(47000, 24, 0)
local STREAM_TIMEOUT = 8
local DOOR_REACH = 12
local RETURN_REACH = 12
local SPAWN_LIFT = 4
local COOLDOWN = 2
local BUILD_RETRY_SECONDS = 10
local MAX_PREVIEW_DESCENDANTS = 30000

local hooked = setmetatable({}, {__mode = "k"})
local nextUse = {}
local preview = nil
local buildInProgress = false
local nextBuildAt = 0
local galleryCache = nil
local playLaunchPending = false

local function galleryModule()
	if galleryCache then return galleryCache end
	local systems = ServerScriptService:FindFirstChild("Level 5 Systems")
	local module = systems and systems:FindFirstChild("Level 5 Rework Gallery")
	if not (module and module:IsA("ModuleScript")) then
		warn("[Level5PreviewAccess] Level 5 Rework Gallery is missing")
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" or result.ContentVersion ~= GALLERY_VERSION then
		warn("[Level5PreviewAccess] Level 5 Rework Gallery failed or has the wrong version:", result)
		return nil
	end
	galleryCache = result
	return result
end

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

local function liveDoor()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local doorways = lobby and lobby:FindFirstChild("LevelDoorways")
	local door = doorways and doorways:FindFirstChild(DOOR_NAME)
	return door and door:IsA("BasePart") and door or nil
end

local function liveSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local pad = lobby and lobby:FindFirstChild("LobbySpawn")
	return pad and pad:IsA("BasePart") and pad or nil
end

local function levelFiveRoundInProgress()
	return workspace:GetAttribute("SelectedLevel") == 5
		or workspace:FindFirstChild("Level 5 Generated World") ~= nil
end

local function ready(player)
	if player.Parent ~= Players or not DevAccess.IsAllowed(player) then return nil end
	if player:GetAttribute("InRound") == true or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored or humanoid.SeatPart
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
	return character, root
end

local function distanceToPart(part, position)
	local offset = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * 0.5
	return (offset - Vector3.new(
		math.clamp(offset.X, -half.X, half.X),
		math.clamp(offset.Y, -half.Y, half.Y),
		math.clamp(offset.Z, -half.Z, half.Z))).Magnitude
end

local function promptPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then return parent.WorldPosition end
	if parent and parent:IsA("BasePart") then return parent.Position end
	return nil
end

local function stream(player, position)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(position, STREAM_TIMEOUT) end)
	if not ok then warn("[Level5PreviewAccess] streaming request failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

local function hookPrompt(prompt, onTriggered)
	if not (prompt and prompt:IsA("ProximityPrompt")) then return nil end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) onTriggered(player, prompt) end)
	end
	return prompt
end

local function ensurePrompt(parent, name, actionText, objectText, onTriggered, keyboardKey, gamepadKey)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = actionText
		prompt.ObjectText = objectText
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		if keyboardKey then prompt.KeyboardKeyCode = keyboardKey end
		if gamepadKey then prompt.GamepadKeyCode = gamepadKey end
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return nil end
	if (keyboardKey and prompt.KeyboardKeyCode ~= keyboardKey)
		or (gamepadKey and prompt.GamepadKeyCode ~= gamepadKey) then
		warn("[Level5PreviewAccess] prompt input changed; refusing to reuse:", name)
		return nil
	end
	return hookPrompt(prompt, onTriggered)
end

local function returnOwner(prompt)
	local model = prompt:FindFirstAncestor(PREVIEW_NAME)
	if not model or not model:IsA("Model") or model.Parent ~= workspace
		or workspace:FindFirstChild(PREVIEW_NAME) ~= model
		or model:GetAttribute("Level5Preview") ~= true or model:GetAttribute("PreviewOnly") ~= true
		or model:GetAttribute("PreviewReady") ~= true
		or model:GetAttribute("GalleryContentVersion") ~= GALLERY_VERSION
		or #model:GetDescendants() ~= model:GetAttribute("PartCount") then return nil end
	local Gallery = galleryModule()
	if not Gallery then return nil end
	local ok, manifest = pcall(Gallery.ReadManifest, model)
	if not ok or manifest.LobbyPrompt ~= prompt or not prompt.Enabled then return nil end
	return model
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local at = promptPosition(prompt)
	local model = returnOwner(prompt)
	if not character or not model or not at or not prompt:IsDescendantOf(workspace)
		or (root.Position - at).Magnitude > RETURN_REACH then return end
	local pad = liveSpawn()
	if not pad then
		warn("[Level5PreviewAccess] ServerLobby.LobbySpawn is missing; return refused")
		return
	end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, pad.Position) then return end
		local nowCharacter, nowRoot = ready(player)
		pad = liveSpawn()
		at = promptPosition(prompt)
		if nowCharacter ~= character or returnOwner(prompt) ~= model
			or not pad or not at or not prompt:IsDescendantOf(workspace)
			or (nowRoot.Position - at).Magnitude > RETURN_REACH then return end
		character:PivotTo(upright(pad.Position + Vector3.new(0, SPAWN_LIFT, 0), pad.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] return failed:", err) end
end

local function ownedPreview(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model:GetAttribute("Level5Preview") == true and model:GetAttribute("PreviewOnly") == true
end

local function validPreview(model)
	return ownedPreview(model) and model:GetAttribute("PreviewReady") == true
		and model:GetAttribute("GalleryContentVersion") == GALLERY_VERSION
end

local function previewMarker(model)
	local marker = model:FindFirstChild(MARKER_NAME)
	return marker and marker:IsA("BasePart") and marker or nil
end

local onGalleryTravel
local function hookPreview(model)
	if not validPreview(model) then return nil end
	local Gallery = galleryModule()
	if not Gallery then return nil end
	local ok, manifest = pcall(Gallery.ReadManifest, model)
	if not ok or #model:GetDescendants() ~= model:GetAttribute("PartCount") then
		warn("[Level5PreviewAccess] gallery manifest or instance count changed:", manifest)
		return nil
	end
	if previewMarker(model) ~= manifest.HubMarker
		or manifest.LobbyPrompt.Parent ~= manifest.HubMarker:FindFirstChild(RETURN_POINT)
		or manifest.LobbyPrompt.Name ~= RETURN_PROMPT then return nil end
	local returnPrompt = hookPrompt(manifest.LobbyPrompt, onReturn)
	if not returnPrompt then return nil end
	for id, section in ipairs(manifest.Sections) do
		if not hookPrompt(section.SelectPrompt, function(player, prompt)
			onGalleryTravel(player, prompt, model, id, false)
		end) or not hookPrompt(section.ReturnPrompt, function(player, prompt)
			onGalleryTravel(player, prompt, model, id, true)
		end) then return nil end
	end
	returnPrompt.Enabled = true
	for _, section in ipairs(manifest.Sections) do
		section.SelectPrompt.Enabled = true
		section.ReturnPrompt.Enabled = true
	end
	return returnPrompt, manifest
end

local function buildPreview()
	local Gallery = galleryModule()
	if not Gallery then return nil end
	local model
	local ok, result = xpcall(function()
		model = Instance.new("Model")
		model.Name = PREVIEW_NAME
		model:SetAttribute("Level5Preview", true)
		model:SetAttribute("PreviewOnly", true)
		model.Parent = workspace
		local manifest = Gallery.Build(model, ORIGIN)
		assert(type(manifest) == "table" and manifest.HubMarker and manifest.HubPad,
			"Gallery did not return a safe hub")
		local descendants = #model:GetDescendants()
		assert(descendants <= MAX_PREVIEW_DESCENDANTS, "Level 5 gallery exceeds the 30,000-instance budget")
		model:SetAttribute("PartCount", descendants)
		model:SetAttribute("PreviewReady", true)
		assert(workspace:FindFirstChild(PREVIEW_NAME) == model and hookPreview(model),
			"Gallery prompts could not be connected")
		assert(#model:GetDescendants() == descendants, "Gallery changed while prompts were connected")
		return model
	end, debug.traceback)
	if not ok then
		warn("[Level5PreviewAccess] gallery build failed:", result)
		if model then model:Destroy() end
		return nil
	end
	return result
end

local function getPreview()
	if validPreview(preview) and preview:IsDescendantOf(workspace) then return preview end
	local found = workspace:FindFirstChild(PREVIEW_NAME)
	if found then
		if validPreview(found) then preview = found; return found end
		if ownedPreview(found) then
			warn("[Level5PreviewAccess] a stale or incomplete preview occupies this name; entry refused")
			return nil
		end
		warn("[Level5PreviewAccess] preview name is occupied by unowned content")
		return nil
	end
	if buildInProgress or os.clock() < nextBuildAt then return nil end
	buildInProgress = true
	local ok, result = pcall(buildPreview)
	buildInProgress = false
	if not ok then warn("[Level5PreviewAccess] preview build failed:", result) end
	preview = if ok then result else nil
	if not preview then nextBuildAt = os.clock() + BUILD_RETRY_SECONDS end
	return preview
end

local function hasFloor(pad, arrival)
	if not pad or not pad:IsA("BasePart") or not pad.CanCollide or not pad.CanQuery
		or not pad:IsDescendantOf(workspace) then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {pad}
	params.RespectCanCollide = true
	local hit = workspace:Raycast(arrival.Position, Vector3.new(0, -8, 0), params)
	return hit ~= nil and hit.Instance == pad
end

onGalleryTravel = function(player, prompt, model, id, toHub)
	if (not toHub and (playLaunchPending or levelFiveRoundInProgress()))
		or (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local Gallery = galleryModule()
	if not character or not Gallery or not validPreview(model)
		or workspace:FindFirstChild(PREVIEW_NAME) ~= model
		or #model:GetDescendants() ~= model:GetAttribute("PartCount") then return end
	local okManifest, manifest = pcall(Gallery.ReadManifest, model)
	if not okManifest then return end
	local section = manifest.Sections[id]
	local expectedPrompt = toHub and section.ReturnPrompt or section.SelectPrompt
	local destination = toHub and manifest.HubMarker or section.Marker
	local pad = toHub and manifest.HubPad or section.Pad
	local at = promptPosition(prompt)
	local arrival = destination.CFrame
	if prompt ~= expectedPrompt or not prompt.Enabled or not prompt:IsDescendantOf(model)
		or not at or (root.Position - at).Magnitude > RETURN_REACH
		or not hasFloor(pad, arrival) then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, arrival.Position) then return end
		local nowCharacter, nowRoot = ready(player)
		if nowCharacter ~= character or workspace:FindFirstChild(PREVIEW_NAME) ~= model
			or not validPreview(model)
			or #model:GetDescendants() ~= model:GetAttribute("PartCount") then return end
		local stillValid, current = pcall(Gallery.ReadManifest, model)
		if not stillValid then return end
		local currentSection = current.Sections[id]
		at = promptPosition(prompt)
		if (not toHub and (playLaunchPending or levelFiveRoundInProgress()))
			or not at or (nowRoot.Position - at).Magnitude > RETURN_REACH
			or prompt ~= (toHub and currentSection.ReturnPrompt or currentSection.SelectPrompt)
			or not prompt.Enabled or not prompt:IsDescendantOf(model)
			or destination ~= (toHub and current.HubMarker or currentSection.Marker)
			or pad ~= (toHub and current.HubPad or currentSection.Pad)
			or destination.CFrame ~= arrival or not hasFloor(pad, arrival) then return end
		character:PivotTo(arrival)
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] gallery travel failed:", err) end
end

local function onEnter(player, prompt)
	if playLaunchPending or levelFiveRoundInProgress()
		or (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local door = prompt.Parent
	if not character or not door or door ~= liveDoor() or distanceToPart(door, root.Position) > DOOR_REACH then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		local model = getPreview()
		local returnPrompt, manifest
		if model then returnPrompt, manifest = hookPreview(model) end
		local marker = manifest and manifest.HubMarker
		local arrival = marker and marker.CFrame
		if not model or not marker or not returnPrompt or not returnPrompt.Enabled
			or not hasFloor(manifest.HubPad, arrival) then
			warn("[Level5PreviewAccess] preview unavailable, unreturnable or floorless; entry refused")
			return
		end
		if not stream(player, arrival.Position) then return end
		local nowCharacter, nowRoot = ready(player)
		local currentReturn, currentManifest = hookPreview(model)
		if playLaunchPending or levelFiveRoundInProgress()
			or nowCharacter ~= character or prompt.Parent ~= door or door ~= liveDoor()
			or distanceToPart(door, nowRoot.Position) > DOOR_REACH
			or workspace:FindFirstChild(PREVIEW_NAME) ~= model or not validPreview(model)
			or not currentManifest or currentManifest.HubMarker ~= marker
			or currentManifest.HubPad ~= manifest.HubPad
			or currentReturn ~= returnPrompt
			or previewMarker(model) ~= marker or marker.CFrame ~= arrival
			or not returnPrompt:IsDescendantOf(model)
			or returnPrompt.Parent ~= marker:FindFirstChild(RETURN_POINT)
			or not returnPrompt.Enabled or not hasFloor(manifest.HubPad, arrival) then return end
		character:PivotTo(arrival)
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] entry failed:", err) end
end

local function verifiedGallery()
	local model
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == PREVIEW_NAME then
			if model then return nil, "duplicate preview names exist" end
			model = child
		end
	end
	if not model then return nil end
	if model.Parent ~= workspace or not validPreview(model)
		or model:GetAttribute("GalleryOnly") ~= true
		or #model:GetDescendants() ~= model:GetAttribute("PartCount") then
		return nil, "an unverified preview occupies the gallery name"
	end
	local Gallery = galleryModule()
	if not Gallery then return nil, "the gallery module is unavailable" end
	local ok = pcall(Gallery.ReadManifest, model)
	if not ok then return nil, "the gallery manifest changed" end
	return model
end

local function galleryOccupied(model)
	local frame, size = model:GetBoundingBox()
	local half = size * 0.5 + Vector3.new(8, 20, 8)
	for _, visitor in ipairs(Players:GetPlayers()) do
		local character = visitor.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = (humanoid and humanoid.RootPart) or (character and character:FindFirstChild("HumanoidRootPart"))
		local position
		if root and root:IsA("BasePart") and root:IsDescendantOf(workspace) then
			position = root.Position
		elseif character and character:IsA("Model") and character:IsDescendantOf(workspace) then
			position = character:GetPivot().Position
		end
		if position then
			local at = frame:PointToObjectSpace(position)
			if math.abs(at.X) <= half.X and math.abs(at.Y) <= half.Y
				and math.abs(at.Z) <= half.Z then return true end
		end
	end
	return false
end

local function onPlay(player, prompt)
	if playLaunchPending or levelFiveRoundInProgress()
		or (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local door = prompt.Parent
	if not character or not prompt.Enabled or prompt.Name ~= ENTER_PROMPT
		or not door or door ~= liveDoor() or prompt ~= door:FindFirstChild(ENTER_PROMPT)
		or not prompt:IsDescendantOf(workspace) or distanceToPart(door, root.Position) > DOOR_REACH
		or workspace:GetAttribute("Level5DevEnabled") ~= true
		or workspace:GetAttribute("Level5PublicPreviewEnabled") == true then return end
	local model, problem = verifiedGallery()
	if problem or (model and galleryOccupied(model)) then
		warn("[Level5PreviewAccess] playable entry refused:", problem or "someone is in the gallery")
		return
	end
	local start = ServerStorage:FindFirstChild("Level5DevStart")
	if not (start and start:IsA("BindableFunction")) then
		warn("[Level5PreviewAccess] Level5DevStart is unavailable")
		return
	end
	local nowCharacter, nowRoot = ready(player)
	if playLaunchPending or levelFiveRoundInProgress()
		or nowCharacter ~= character or prompt.Parent ~= door or door ~= liveDoor()
		or not prompt.Enabled or distanceToPart(door, nowRoot.Position) > DOOR_REACH
		or workspace:GetAttribute("Level5DevEnabled") ~= true
		or workspace:GetAttribute("Level5PublicPreviewEnabled") == true then return end
	playLaunchPending = true
	nextUse[player] = math.huge
	local ok, accepted, reason = pcall(function() return start:Invoke(player) end)
	if not ok or accepted ~= true then
		playLaunchPending = false
		warn("[Level5PreviewAccess] playable entry refused:", if ok then reason else accepted)
	else
		-- The GameManager accepted the launch. Remove only the exact gallery that
		-- was verified empty above; a newly occupied or changed model is preserved.
		if model then
			local current, currentProblem = verifiedGallery()
			if current == model and not galleryOccupied(model) then
				local removed, removeError = pcall(function() model:Destroy() end)
				if removed then preview = nil
				else warn("[Level5PreviewAccess] gallery cleanup failed:", removeError) end
			else
				warn("[Level5PreviewAccess] retained gallery during playable launch:",
					currentProblem or "gallery changed or became occupied")
			end
		end
		-- GameManager marks the accepted roster InRound asynchronously. Keep
		-- gallery travel closed until that server-owned state has taken effect.
		task.delay(10, function() playLaunchPending = false end)
	end
	release(player)
end

local function hookDoor()
	local door = liveDoor()
	if not door then return end
	-- E uses the same lobby affordance as Level 6, but starts the current
	-- server-authoritative Level 5 world instead of the stale gallery copy.
	local enter = ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 5 PREVIEW", "DEVELOPER PREVIEW", onPlay)
	if enter then
		enter.Enabled = workspace:GetAttribute("Level5DevEnabled") == true
			and workspace:GetAttribute("Level5PublicPreviewEnabled") ~= true
			and not levelFiveRoundInProgress()
	end
	local oldPlay = door:FindFirstChild(PLAY_PROMPT)
	if oldPlay and oldPlay:IsA("ProximityPrompt") then oldPlay.Enabled = false end
end

local function onDescendantAdded(instance)
	local name = instance.Name
	if name == DOOR_NAME or name == "LevelDoorways" or name == "ServerLobby" then
		hookDoor()
	elseif name == PREVIEW_NAME or name == MARKER_NAME then
		local model = if name == PREVIEW_NAME then instance else instance:FindFirstAncestor(PREVIEW_NAME)
		if model and model:IsA("Model") then
			preview = model
			hookPreview(model)
		end
	end
end

-- A teleport exploit cannot turn a private preview into a public map.
local guardedModel, guardedPartCount, guardedFrame, guardedHalf
local function ejectNonDevelopers()
	local model = workspace:FindFirstChild(PREVIEW_NAME)
	if not ownedPreview(model) or model:GetAttribute("PreviewReady") ~= true then return end
	local partCount = model:GetAttribute("PartCount")
	if guardedModel ~= model or guardedPartCount ~= partCount then
		guardedModel, guardedPartCount = model, partCount
		local size
		guardedFrame, size = model:GetBoundingBox()
		guardedHalf = size * 0.5 + Vector3.new(8, 20, 8)
	end
	local spawn = liveSpawn()
	if not spawn then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if not DevAccess.IsAllowed(player) then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = humanoid and humanoid.RootPart
			if root and humanoid.Health > 0 then
				local p = guardedFrame:PointToObjectSpace(root.Position)
				if math.abs(p.X) <= guardedHalf.X and math.abs(p.Y) <= guardedHalf.Y
					and math.abs(p.Z) <= guardedHalf.Z then
					character:PivotTo(upright(spawn.Position + Vector3.new(0, SPAWN_LIFT, 0), spawn.CFrame.LookVector))
				end
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
workspace:GetAttributeChangedSignal("Level5DevEnabled"):Connect(hookDoor)
workspace:GetAttributeChangedSignal("Level5PublicPreviewEnabled"):Connect(hookDoor)
workspace:GetAttributeChangedSignal("SelectedLevel"):Connect(hookDoor)
workspace.DescendantAdded:Connect(onDescendantAdded)
for _, descendant in ipairs(workspace:GetDescendants()) do onDescendantAdded(descendant) end
task.spawn(function()
	while task.wait(0.5) do ejectNonDevelopers() end
end)
