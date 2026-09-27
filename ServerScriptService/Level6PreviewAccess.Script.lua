-- Developer-only entry to the static Level 6 cinema preview; Level 6 is not a
-- playable round. Prompts are only UI: every trigger re-checks DevAccess, life,
-- round state and distance here before the avatar is pivoted.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

local DOOR_NAME = "Level6SealedDoor"
local PREVIEW_NAME = "Level 6 Cinema Preview"
local MARKER_NAME = "Camera1_RedConcession"
local ENTER_PROMPT = "Level6DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level6DeveloperPreviewReturnPrompt"
local RETURN_POINT = "Level6DeveloperPreviewReturnPoint"
local STREAM_TIMEOUT = 8
local DOOR_REACH = 12 -- studs from the door's surface; the prompt reaches 10 from its centre
local RETURN_REACH = 12
local SPAWN_LIFT = 4
local COOLDOWN = 2

local hooked = setmetatable({}, {__mode = "k"})
local nextUse = {}
local preview = nil
local buildAttempted = false

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

-- Red carpet by photo 1's eye (floor top Y=24), facing the concession stand.
local ARRIVAL = upright(Vector3.new(23006, 27.5, 36), Vector3.new(78, 0, -44))

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

-- Server-side facts only; nothing a client sends can satisfy these.
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
	if not ok then warn("[Level6PreviewAccess] streaming request failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

-- Reuse a prompt that already has this name; never restyle or replace it.
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
		warn("[Level6PreviewAccess] ServerLobby.LobbySpawn is missing; return refused")
		return
	end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, pad.Position) then return end
		-- Streaming yields: re-read the player, avatar, prompt and live spawn.
		local nowCharacter, nowRoot = ready(player)
		pad = liveSpawn()
		at = promptPosition(prompt)
		if nowCharacter ~= character or not pad or not at or not prompt:IsDescendantOf(workspace)
			or (nowRoot.Position - at).Magnitude > RETURN_REACH then return end
		character:PivotTo(upright(pad.Position + Vector3.new(0, SPAWN_LIFT, 0), pad.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level6PreviewAccess] return failed:", err) end
end

local function validPreview(model)
	return typeof(model) == "Instance" and model:IsA("Model")
		and model:GetAttribute("Level6Preview") == true and model:GetAttribute("PreviewOnly") == true
end

-- The return prompt hangs off an attachment a few studs ahead of photo 1's
-- marker, so it sits in view from the arrival point in first or third person.
local function hookPreview(model)
	if not validPreview(model) then return nil end
	local marker = model:FindFirstChild(MARKER_NAME, true)
	if not (marker and marker:IsA("BasePart")) then return nil end
	local existing = marker:FindFirstChild(RETURN_PROMPT, true)
	local holder = existing and existing.Parent or marker:FindFirstChild(RETURN_POINT)
	if not holder then
		holder = Instance.new("Attachment")
		holder.Name = RETURN_POINT
		holder.CFrame = CFrame.new(0, -1.5, -4)
		holder.Parent = marker
	end
	return ensurePrompt(holder, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 6 DEVELOPER PREVIEW", onReturn)
end

local function getPreview()
	local function expanded(model)
		local module = ServerScriptService:FindFirstChild("Level6Expansion")
		if not (module and module:IsA("ModuleScript")) then
			warn("[Level6PreviewAccess] ServerScriptService.Level6Expansion is missing")
			return nil
		end
		local ok, result, err = pcall(function() return require(module).Append(model) end)
		if not ok or not result then
			warn("[Level6PreviewAccess] preview expansion failed:", if ok then err else result)
			return nil
		end
		return model
	end
	if validPreview(preview) and preview:IsDescendantOf(workspace) then return expanded(preview) end
	local found = workspace:FindFirstChild(PREVIEW_NAME)
	if validPreview(found) then
		preview = found
		return expanded(found)
	end
	if buildAttempted then return nil end
	buildAttempted = true
	local module = ServerScriptService:FindFirstChild("Level6Generator")
	if not (module and module:IsA("ModuleScript")) then
		warn("[Level6PreviewAccess] ServerScriptService.Level6Generator is missing")
		return nil
	end
	local ok, model, err = pcall(function() return require(module).BuildPreview(workspace) end)
	if not ok or not validPreview(model) then
		warn("[Level6PreviewAccess] preview build failed:", if ok then err else model)
		return nil
	end
	preview = model
	return expanded(model)
end

local function hasFloor(model)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model}
	params.RespectCanCollide = true
	return workspace:Raycast(ARRIVAL.Position, Vector3.new(0, -8, 0), params) ~= nil
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = ready(player)
	local door = prompt.Parent
	if not character or not door or door ~= liveDoor() or distanceToPart(door, root.Position) > DOOR_REACH then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		local model = getPreview()
		if not model or not hookPreview(model) or not hasFloor(model) then
			warn("[Level6PreviewAccess] preview unavailable, unreturnable or floorless; entry refused")
			return
		end
		-- An errored request may leave the carpet unstreamed on the client.
		if not stream(player, ARRIVAL.Position) then return end
		-- Streaming yields: re-read the player, avatar and the exact live door.
		local nowCharacter, nowRoot = ready(player)
		if nowCharacter ~= character or prompt.Parent ~= door or door ~= liveDoor()
			or distanceToPart(door, nowRoot.Position) > DOOR_REACH or not model:IsDescendantOf(workspace) then return end
		character:PivotTo(ARRIVAL)
	end)
	release(player)
	if not ok then warn("[Level6PreviewAccess] entry failed:", err) end
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 6 PREVIEW", "DEVELOPER PREVIEW", onEnter) end
end

-- The lobby is rebuilt piecewise and may be parked/restored, so any segment of
-- the door path re-resolves the live door; the preview may appear at any time.
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

-- Keep the distant preview developer-only even if a client moves there without using the door.
local guardedModel, guardedPartCount, guardedFrame, guardedHalf
local function ejectNonDevelopers()
	local model = workspace:FindFirstChild(PREVIEW_NAME)
	if not validPreview(model) then return end
	local partCount = model:GetAttribute("PartCount")
	if guardedModel ~= model or guardedPartCount ~= partCount then
		guardedModel = model
		guardedPartCount = partCount
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
