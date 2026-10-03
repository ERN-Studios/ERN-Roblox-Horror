-- Developer-only Level 2 Poolrooms preview button. GameManager owns the actual round.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))
local HOST_NAME = "Level2BlenderPreviewEntry"
local OWNER = "Level2BlenderPreviewHost"
local RANGE, COOLDOWN = 12, 2
-- Best estimates: measure both offsets in a Play Server datamodel; the lobby
-- is rebuilt at play start. Old room target: (83, 34, -848).
local SERVER_LOBBY_HOST_OFFSET = Vector3.new(20, 4.42, -8)
-- X is outward from PreviewCenter, so the east-side Level 2 bay avoids its doorway.
local REIMAGINED_BAY_OUTWARD_HOST_OFFSET = Vector3.new(20, 4.42, 0)
-- Instance userdata can be collected from weak tables while its engine Part
-- remains parented. Keep ownership until the host is explicitly destroyed.
local hosts = {}
local nextUse = {}

-- Reserved round servers never expose lobby entry controls.
if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end
local request = ReplicatedStorage:FindFirstChild("Level2BlenderPreviewRequest")
if not request then
	request = Instance.new("RemoteEvent")
	request.Name = "Level2BlenderPreviewRequest"
	request.Parent = ReplicatedStorage
end
assert(request:IsA("RemoteEvent"), "Level2BlenderPreviewRequest has wrong class")

local function activeRoom(room)
	if typeof(room) ~= "Instance" or not room:IsA("Model") then return false end
	local lobby = workspace:FindFirstChild("ServerLobby")
	local rooms = lobby and lobby:FindFirstChild("LevelQueueRooms")
	if room == (rooms and rooms:FindFirstChild("Level2QueueRoom")) then
		return room:IsA("Model") and room:GetAttribute("LevelNumber") == 2
	end
	local preview = workspace:FindFirstChild("LobbyReimaginedPreview")
	local pads = preview and preview:FindFirstChild("PreviewQueuePads")
	return room ~= nil and room == (pads and pads:FindFirstChild("QueueBay_Level2"))
		and room:IsA("Model") and preview:IsA("Model")
		and preview:GetAttribute("LobbyReimaginedOwned") == true
		and preview:GetAttribute("R3QueueRevision") == 3
		and preview:GetAttribute("Ready") == true
end

local function ensureHost(room)
	if not activeRoom(room) then return end
	local floor = room:FindFirstChild("ChamberFloor")
	if not floor or not floor:IsA("BasePart") or not floor.CanCollide then return end
	local host = room:FindFirstChild(HOST_NAME)
	if host then
		if not hosts[host] then warn("[Level2BlenderPreview] conflicting entry host; inspect before replacement") end
		return
	end
	local position = floor.Position + SERVER_LOBBY_HOST_OFFSET
	if room.Name == "QueueBay_Level2" then
		local preview = workspace:FindFirstChild("LobbyReimaginedPreview")
		local center = preview:GetAttribute("PreviewCenter")
		if typeof(center) ~= "Vector3" then return end
		local side = math.sign(floor.Position.X - center.X)
		if side == 0 then return end
		position = floor.Position + Vector3.new(
			REIMAGINED_BAY_OUTWARD_HOST_OFFSET.X * side,
			REIMAGINED_BAY_OUTWARD_HOST_OFFSET.Y, REIMAGINED_BAY_OUTWARD_HOST_OFFSET.Z)
	end
	host = Instance.new("Part")
	host.Name = HOST_NAME
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(position)
	host.Anchored = true
	host.Transparency = 1
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.CastShadow = false
	host:SetAttribute(OWNER, true)
	hosts[host] = {room = room, floor = floor}
	host.Destroying:Once(function() hosts[host] = nil end)
	host.Parent = room
end

local function hookRooms()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local rooms = lobby and lobby:FindFirstChild("LevelQueueRooms")
	ensureHost(rooms and rooms:FindFirstChild("Level2QueueRoom"))
	local preview = workspace:FindFirstChild("LobbyReimaginedPreview")
	local pads = preview and preview:FindFirstChild("PreviewQueuePads")
	ensureHost(pads and pads:FindFirstChild("QueueBay_Level2"))
end

local function readyPlayer(player, host)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
		or not DevAccess.IsAllowed(player) or player:GetAttribute("InRound") == true
		or player:GetAttribute("Level6InRound") == true
		or workspace:GetAttribute("ReservedRoundServer") == true then return nil end
	local record = hosts[host]
	if not record or not activeRoom(record.room) or host.Parent ~= record.room
		or host:GetAttribute(OWNER) ~= true or not host.Anchored or host.Transparency ~= 1
		or host.CanCollide or host.CanTouch or host.CanQuery
		or record.floor ~= record.room:FindFirstChild("ChamberFloor")
		or not record.floor.CanCollide then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or not character:IsDescendantOf(workspace) or root.Anchored
		or humanoid.Health <= 0 or humanoid.SeatPart
		or humanoid:GetState() == Enum.HumanoidStateType.Dead
		or (root.Position - host.Position).Magnitude > RANGE then return nil end
	return character
end

request.OnServerEvent:Connect(function(player, host)
	if typeof(host) ~= "Instance" or not host:IsA("BasePart")
		or (nextUse[player] or 0) > os.clock() then return end
	local character = readyPlayer(player, host)
	if not character then return end
	-- Lock before invoking: GameManager loading/teleport may yield.
	nextUse[player] = math.huge
	local launch = ServerStorage:FindFirstChild("Level2BlenderPreviewLaunch")
	local ok, accepted, reason = pcall(function()
		if not launch or not launch:IsA("BindableFunction") then return false, "PREVIEW_NOT_READY" end
		if readyPlayer(player, host) ~= character then return false, "ENTRY_CHANGED" end
		return launch:Invoke(player)
	end)
	nextUse[player] = if player.Parent == Players then os.clock() + COOLDOWN else nil
	if player.Parent == Players then
		request:FireClient(player, accepted == true and ok, if ok then reason else "PREVIEW_FAILED")
	end
	if not ok then warn("[Level2BlenderPreview] launch failed: " .. tostring(accepted)) end
end)

Players.PlayerRemoving:Connect(function(player) nextUse[player] = nil end)
local watched = {}
local function observe(instance)
	if instance.Name == "LobbyReimaginedPreview" and instance:IsA("Model") and not watched[instance] then
		watched[instance] = true
		local connection = instance:GetAttributeChangedSignal("Ready"):Connect(hookRooms)
		instance.Destroying:Once(function()
			connection:Disconnect()
			watched[instance] = nil
		end)
	end
	if instance.Name == "ServerLobby" or instance.Name == "LevelQueueRooms"
		or instance.Name == "Level2QueueRoom" or instance.Name == "PreviewQueuePads"
		or instance.Name == "QueueBay_Level2" or instance.Name == "ChamberFloor"
		or instance.Name == "LobbyReimaginedPreview" then task.defer(hookRooms) end
end
workspace.DescendantAdded:Connect(observe)
observe(workspace:FindFirstChild("LobbyReimaginedPreview") or workspace)
hookRooms()
