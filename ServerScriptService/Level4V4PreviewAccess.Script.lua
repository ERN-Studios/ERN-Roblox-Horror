-- Developer-only entry to the already-built V4 cinema preview.
-- The prompts are UI; every teleport is authorized again on the server.
local Players = game:GetService("Players")
local DevAccess = require(game:GetService("ReplicatedStorage"):WaitForChild("DevAccess"))

-- 2026-09-30: the Blender-built cinema; the original "Level 4 Cinema Preview" model is kept untouched.
local MODEL_NAME = "Level 4 Cinema Blender"
local EXIT_NAME = "Level4V4Exit"
local ENTER_PROMPT = "Level4DeveloperPreviewPrompt"
local RETURN_PROMPT = "Level4DeveloperPreviewReturnPrompt"
local COOLDOWN = 2
local nextUse = {}
local hooked = setmetatable({}, { __mode = "k" })

local function liveDoor()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local doorways = lobby and lobby:FindFirstChild("LevelDoorways")
	local door = doorways and doorways:FindFirstChild("Level4SealedDoor")
	return door and door:IsA("BasePart") and door or nil
end

local function liveSpawn()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
	return spawn and spawn:IsA("BasePart") and spawn or nil
end

local function readyPreview()
	local model = workspace:FindFirstChild(MODEL_NAME)
	if not (model and model:IsA("Model") and model:GetAttribute("Level4Preview") == true
		and model:GetAttribute("PreviewOnly") == true
		and model:GetAttribute("Level4LayoutVersion") == 4
		and model:GetAttribute("Level4PreviewReady") == true) then return nil end
	local exit = model:FindFirstChild(EXIT_NAME, true)
	if not (exit and exit:IsA("BasePart") and exit:IsDescendantOf(model)) then return nil end
	return model, exit
end

local function readyPlayer(player)
	if player.Parent ~= Players or not DevAccess.IsAllowed(player)
		or player:GetAttribute("InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored or humanoid.SeatPart
		or humanoid.Health <= 0 or humanoid:GetState() == Enum.HumanoidStateType.Dead then return nil end
	return character, root
end

local function upright(position, look)
	local flat = Vector3.new(look.X, 0, look.Z)
	return CFrame.lookAt(position, position + (if flat.Magnitude > 0.01 then flat else Vector3.zAxis))
end

local function stream(player, position)
	local ok, err = pcall(function() player:RequestStreamAroundAsync(position, 8) end)
	if not ok then warn("[Level4V4PreviewAccess] streaming failed:", err) end
	return ok
end

local function release(player)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
end

local function hasFloor(model, exit)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	params.RespectCanCollide = true
	local hit = workspace:Raycast(exit.Position, Vector3.new(0, -8, 0), params)
	return hit ~= nil and hit.Normal.Y > 0.7
end

local function onReturn(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local model, exit = readyPreview()
	if not character or not model or not exit or prompt.Parent ~= exit
		or (root.Position - exit.Position).Magnitude > 12 then return end
	local spawn = liveSpawn()
	if not spawn then return end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, spawn.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		spawn = liveSpawn()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit or not spawn
			or prompt.Parent ~= exit or (nowRoot.Position - exit.Position).Magnitude > 12 then return end
		character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level4V4PreviewAccess] return failed:", err) end
end

local function onEnter(player, prompt)
	if (nextUse[player] or 0) > os.clock() then return end
	local character, root = readyPlayer(player)
	local door = liveDoor()
	if not character or not door or prompt.Parent ~= door or (root.Position - door.Position).Magnitude > 14 then return end
	local model, exit = readyPreview()
	local returnPrompt = exit and exit:FindFirstChild(RETURN_PROMPT)
	if not model or not returnPrompt or not returnPrompt:IsA("ProximityPrompt")
		or not returnPrompt.Enabled or not hasFloor(model, exit) then
		warn("[Level4V4PreviewAccess] ready V4 preview, return prompt or landing floor is missing")
		return
	end
	nextUse[player] = math.huge
	local ok, err = pcall(function()
		if not stream(player, exit.Position) then return end
		local nowCharacter, nowRoot = readyPlayer(player)
		local nowModel, nowExit = readyPreview()
		if nowCharacter ~= character or nowModel ~= model or nowExit ~= exit
			or prompt.Parent ~= door or liveDoor() ~= door
			or (nowRoot.Position - door.Position).Magnitude > 14
			or returnPrompt.Parent ~= exit or not returnPrompt.Enabled
			or not hasFloor(model, exit) then return end
		character:PivotTo(upright(exit.Position, exit.CFrame.LookVector))
	end)
	release(player)
	if not ok then warn("[Level4V4PreviewAccess] entry failed:", err) end
end

local function ensurePrompt(parent, name, action, object, callback)
	local prompt = parent:FindFirstChild(name)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parent
	end
	if not prompt:IsA("ProximityPrompt") then return end
	if not hooked[prompt] then
		hooked[prompt] = true
		prompt.Triggered:Connect(function(player) callback(player, prompt) end)
	end
end

local function hookDoor()
	local door = liveDoor()
	if door then ensurePrompt(door, ENTER_PROMPT, "ENTER LEVEL 4 PREVIEW", "DEVELOPER PREVIEW", onEnter) end
end

local function hookExit()
	local _, exit = readyPreview()
	if exit then ensurePrompt(exit, RETURN_PROMPT, "RETURN TO LOBBY", "LEVEL 4 DEVELOPER PREVIEW", onReturn) end
end

local watchedModel, readyConnection
local function watchPreview(model)
	if watchedModel ~= model then
		if readyConnection then readyConnection:Disconnect() end
		watchedModel = model
		readyConnection = model and model:GetAttributeChangedSignal("Level4PreviewReady"):Connect(hookExit) or nil
	end
	hookExit()
end

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
workspace.DescendantAdded:Connect(function(instance)
	local name = instance.Name
	if name == "ServerLobby" or name == "LevelDoorways" or name == "Level4SealedDoor" then
		hookDoor()
	elseif name == MODEL_NAME and instance.Parent == workspace and instance:IsA("Model") then
		watchPreview(instance)
	elseif name == EXIT_NAME then
		hookExit()
	end
end)
hookDoor()
watchPreview(workspace:FindFirstChild(MODEL_NAME))

-- Preserve the existing preview's developer-only physical boundary during the V4 swap.
task.spawn(function()
	local boundedModel, bounds, half
	while task.wait(0.5) do
		local model = readyPreview()
		local spawn = liveSpawn()
		if model and spawn then
			if boundedModel ~= model then
				local size
				bounds, size = model:GetBoundingBox()
				half = size * 0.5 + Vector3.new(8, 20, 8)
				boundedModel = model
			end
			for _, player in ipairs(Players:GetPlayers()) do
				if not DevAccess.IsAllowed(player) then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local root = humanoid and humanoid.RootPart
					if root and humanoid.Health > 0 then
						local p = bounds:PointToObjectSpace(root.Position)
						if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
							character:PivotTo(upright(spawn.Position + Vector3.new(0, 4, 0), spawn.CFrame.LookVector))
						end
					end
				end
			end
		end
	end
end)
