-- Developer-only entry to the static Level 5 architecture preview.
-- The playable Level 5 round and its queue stay closed while the map is rebuilt.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

local DOOR_NAME = "Level5SealedDoor"
local PREVIEW_NAME = "Level 5 Architecture Preview"
local MARKER_NAME = "Level5DeveloperPreviewArrival"
local ENTER_PROMPT = "Level5DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level5DeveloperPreviewReturnPrompt"
local RETURN_POINT = "Level5DeveloperPreviewReturnPoint"
-- Keep this static copy clear of the playable Level 5 world at X=17000.
local ORIGIN = Vector3.new(31000, 24, 0)
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

local function ensurePrompt(parent, name, actionText, objectText, onTriggered)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = actionText
		prompt.ObjectText = objectText
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return nil end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) onTriggered(player, prompt) end)
	end
	return prompt
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local at = promptPosition(prompt)
	if not character or not at or not prompt:IsDescendantOf(workspace)
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
		if nowCharacter ~= character or not pad or not at or not prompt:IsDescendantOf(workspace)
			or (nowRoot.Position - at).Magnitude > RETURN_REACH then return end
		character:PivotTo(upright(pad.Position + Vector3.new(0, SPAWN_LIFT, 0), pad.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] return failed:", err) end
end

local function validPreview(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model:GetAttribute("Level5Preview") == true and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("PreviewReady") == true
end

local function previewMarker(model)
	local marker = model:FindFirstChild(MARKER_NAME)
	return marker and marker:IsA("BasePart") and marker or nil
end

local function hookPreview(model)
	if not validPreview(model) then return nil end
	local marker = previewMarker(model)
	if not marker then return nil end
	local holder = marker:FindFirstChild(RETURN_POINT)
	if not holder then
		holder = Instance.new("Attachment")
		holder.Name = RETURN_POINT
		holder.CFrame = CFrame.new(0, -1, -4)
		holder.Parent = marker
	end
	if not holder:IsA("Attachment") then return nil end
	return ensurePrompt(holder, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 5 DEVELOPER PREVIEW", onReturn)
end

local function buildPreview()
	local systems = ServerScriptService:FindFirstChild("Level 5 Systems")
	local module = systems and systems:FindFirstChild("Level 5 Architecture")
	if not (module and module:IsA("ModuleScript")) then
		warn("[Level5PreviewAccess] Level 5 Architecture is missing")
		return nil
	end
	local model
	local ok, result = xpcall(function()
		model = Instance.new("Model")
		model.Name = PREVIEW_NAME
		model:SetAttribute("Level5Preview", true)
		model:SetAttribute("PreviewOnly", true)
		model.Parent = workspace
		local manifest = require(module).Build(model, ORIGIN, {MapOnly = true})
		assert(type(manifest) == "table" and typeof(manifest.SpawnCFrame) == "CFrame",
			"Architecture did not return an arrival CFrame")
		-- The playable adapter supplies this floor separately. Preview entry needs
		-- the same safe landing without changing the adapter or the round state.
		local floor = Instance.new("Part")
		floor.Name = "Level5PreviewArrivalFloor"
		floor.CFrame = manifest.SpawnCFrame * CFrame.new(0, -3, 0)
		floor.Size = Vector3.new(16, 0.5, 16)
		floor.Anchored = true
		floor.Transparency = 1
		floor.CanCollide = true
		floor.CanTouch = false
		floor.Parent = model
		local marker = Instance.new("Part")
		marker.Name = MARKER_NAME
		marker.CFrame = manifest.SpawnCFrame
		marker.Size = Vector3.new(0.25, 0.25, 0.25)
		marker.Anchored = true
		marker.Transparency = 1
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Parent = model
		local descendants = #model:GetDescendants()
		-- Reserve two descendants for the return attachment and prompt added on entry.
		assert(descendants + 2 <= MAX_PREVIEW_DESCENDANTS, "Level 5 preview exceeds the 30,000-instance budget")
		model:SetAttribute("PartCount", descendants)
		model:SetAttribute("PreviewReady", true)
		return model
	end, debug.traceback)
	if not ok then
		warn("[Level5PreviewAccess] architecture build failed:", result)
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
		if found:GetAttribute("Level5Preview") == true and found:GetAttribute("PreviewOnly") == true then return nil end
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

local function hasFloor(model, arrival)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	return workspace:Raycast(arrival.Position, Vector3.new(0, -8, 0), params) ~= nil
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local door = prompt.Parent
	if not character or not door or door ~= liveDoor() or distanceToPart(door, root.Position) > DOOR_REACH then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		local model = getPreview()
		local marker = model and previewMarker(model)
		local arrival = marker and marker.CFrame
		local returnPrompt = model and hookPreview(model)
		if not model or not marker or not returnPrompt or not returnPrompt.Enabled
			or not hasFloor(model, arrival) then
			warn("[Level5PreviewAccess] preview unavailable, unreturnable or floorless; entry refused")
			return
		end
		if not stream(player, arrival.Position) then return end
		local nowCharacter, nowRoot = ready(player)
		if nowCharacter ~= character or prompt.Parent ~= door or door ~= liveDoor()
			or distanceToPart(door, nowRoot.Position) > DOOR_REACH
			or workspace:FindFirstChild(PREVIEW_NAME) ~= model or not validPreview(model)
			or previewMarker(model) ~= marker or marker.CFrame ~= arrival
			or not returnPrompt:IsDescendantOf(model)
			or returnPrompt.Parent ~= marker:FindFirstChild(RETURN_POINT)
			or not returnPrompt.Enabled or not hasFloor(model, arrival) then return end
		character:PivotTo(arrival)
	end)
	release(player)
	if not ok then warn("[Level5PreviewAccess] entry failed:", err) end
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 5 PREVIEW", "DEVELOPER PREVIEW", onEnter) end
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
	if not validPreview(model) then return end
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
workspace.DescendantAdded:Connect(onDescendantAdded)
for _, descendant in ipairs(workspace:GetDescendants()) do onDescendantAdded(descendant) end
task.spawn(function()
	while task.wait(0.5) do ejectNonDevelopers() end
end)
