-- RouteMarkerService
-- Server authority for the Route Marker Pack (Trello #85). A player buys three
-- markers for two tokens and drops them to point their team through a maze.
--
-- The client may only ASK. Every number that decides where a marker lands is
-- read from this server's own copy of the character, so the remote deliberately
-- carries nothing but the string "place": there is no CFrame, no parent and no
-- count a client could supply, and therefore none to forge. The marker is
-- purely informational -- it has no collision, no query hit and no effect on
-- any hazard -- so the worst a broken client can achieve is litter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ACCENT = Color3.fromRGB(68, 221, 196)    -- the Zyntra store accent
local PLATE_COLOUR = Color3.fromRGB(8, 14, 12) -- dark backing, so the neon reads on a pale floor
local NAME_COLOUR = Color3.fromRGB(150, 172, 165)
local PLACE_COOLDOWN = 1.5      -- seconds between accepted attempts, per player
local FORWARD_OFFSET = 2.5      -- studs in front of the placer
local FLOOR_PROBE = 12          -- downward raycast length
local FLOOR_FALLBACK = 2.6      -- root -> feet when the probe hits nothing
local FLOOR_CLEARANCE = 0.15    -- studs above the floor, so it never z-fights
local CHEVRON_ANGLE = math.rad(38)
local CHEVRON_LENGTH = 1.5
local MAX_ACTIVE_FALLBACK = 3   -- used only if ZyntraConfig has no Items entry

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotes:FindFirstChild("RouteMarker")
if remote and not remote:IsA("RemoteEvent") then
	remote:Destroy()
	remote = nil
end
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RouteMarker"
	remote.Parent = remotes
end

-- ZyntraConfig is A-SERVER's file and may not carry Items yet on an older
-- place; a missing entry falls back rather than breaking placement.
local Config
do
	local module = ReplicatedStorage:FindFirstChild("ZyntraConfig")
	local ok, value = pcall(function()
		return module and require(module) or nil
	end)
	Config = (ok and type(value) == "table") and value or nil
end

local function maxActive(): number
	local entry = Config and Config.Items and Config.Items.RouteMarker
	local value = entry and tonumber(entry.MaxActive)
	if not value or value ~= value or value < 1 then return MAX_ACTIVE_FALLBACK end
	return math.floor(value)
end

-- [Player] = { Model }, oldest first. Rebuilt lazily, never trusted blindly:
-- anything else that destroys a marker (a world teardown, for example) has to
-- be survivable without leaving a phantom against the player's three.
local placed = {}
local lastPlaceAt = {}
local serial = 0

local function markerFolder(): Folder
	local folder = workspace:FindFirstChild("RouteMarkers")
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RouteMarkers"
		folder.Parent = workspace
	end
	return folder
end

local function activeList(player: Player)
	local list = placed[player]
	if not list then
		list = {}
		placed[player] = list
	end
	for index = #list, 1, -1 do
		if list[index].Parent == nil then table.remove(list, index) end
	end
	return list
end

local function publishCount(player: Player, count: number)
	if player.Parent == Players then
		player:SetAttribute("RouteMarkersActive", count)
	end
end

-- Yaw-only rotation. Every part of a marker is flat on the floor, so this is
-- the whole of the geometry it needs, and a sign error would only mirror the
-- two chevron arms into each other.
local function rotateY(vector: Vector3, angle: number): Vector3
	local cosine, sine = math.cos(angle), math.sin(angle)
	return Vector3.new(vector.X * cosine + vector.Z * sine, 0,
		-vector.X * sine + vector.Z * cosine)
end

local function floorHeight(origin: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Players and the markers themselves are not ground. Two players standing
	-- on each other's heads must not stack markers in the air, and a second
	-- marker dropped on the first must land on the same floor as the first.
	local ignore = {markerFolder()}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then table.insert(ignore, other.Character) end
	end
	params.FilterDescendantsInstances = ignore
	-- Level 2 is a flooded level: the marker belongs on the tiles, not on the
	-- water surface, and decoration that nothing can walk on is not floor.
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local hit = workspace:Raycast(origin, Vector3.new(0, -FLOOR_PROBE, 0), params)
	return hit and hit.Position.Y or (origin.Y - FLOOR_FALLBACK)
end

local function spawnMarker(player: Player, origin: Vector3, forward: Vector3): Model
	serial += 1
	local model = Instance.new("Model")
	model.Name = "RouteMarker"
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("PlacedAt", workspace:GetServerTimeNow())
	model:SetAttribute("Serial", serial)

	local function part(name: string, size: Vector3, centre: Vector3, direction: Vector3,
		colour: Color3, material: Enum.Material): BasePart
		local instance = Instance.new("Part")
		instance.Name = name
		instance.Size = size
		instance.CFrame = CFrame.new(centre, centre + direction)
		instance.Anchored = true
		instance.CanCollide = false
		-- CanQuery false keeps the marker out of every OTHER system's raycasts
		-- and overlap checks -- entity line of sight, the queue barrier push-out
		-- and this script's own floor probe included.
		instance.CanQuery = false
		instance.CanTouch = false
		instance.CastShadow = false
		instance.Material = material
		instance.Color = colour
		instance.TopSurface = Enum.SurfaceType.Smooth
		instance.BottomSurface = Enum.SurfaceType.Smooth
		instance.Parent = model
		return instance
	end

	-- A dark plate for the tail and two neon arms for the head. Not a wedge:
	-- a WedgePart's triangle stands in the VERTICAL plane, so from a player's
	-- eye height it reads as a ramp rather than an arrow. A chevron reads as a
	-- direction from any angle, and is yaw-only in every part.
	local plate = part("Base", Vector3.new(2.6, 0.08, 3.6), origin, forward,
		PLATE_COLOUR, Enum.Material.SmoothPlastic)
	plate.Transparency = 0.15
	local tip = origin + forward * 1.45 + Vector3.new(0, 0.07, 0)
	for _, side in ipairs({1, -1}) do
		local direction = rotateY(forward, side * CHEVRON_ANGLE)
		part(side > 0 and "HeadLeft" or "HeadRight",
			Vector3.new(0.34, 0.12, CHEVRON_LENGTH),
			tip - direction * (CHEVRON_LENGTH * 0.5), direction, ACCENT, Enum.Material.Neon)
	end

	-- Who dropped it. A marker is a claim about the route, and a team can only
	-- weigh it if they know whose claim it is.
	local tag = Instance.new("BillboardGui")
	tag.Name = "Placer"
	tag.Adornee = plate
	tag.Size = UDim2.fromOffset(150, 20)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0)
	tag.MaxDistance = 60
	tag.AlwaysOnTop = false
	tag.Parent = plate
	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 13
	label.TextColor3 = NAME_COLOUR
	label.TextStrokeTransparency = 0.6
	label.Text = player.Name
	label.Parent = tag

	model.PrimaryPart = plate
	model.Parent = markerFolder()
	return model
end

-- The one gate. Returns a refusal reason, or nil when the placement may go
-- ahead. Every branch is also checked by the HUD, but only this one decides.
local function refusalFor(player: Player): string?
	if player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true
		or workspace:GetAttribute("RoundActive") ~= true
		or workspace:GetAttribute("RoundLoadingState") ~= "ready" then
		return "NotInRound"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not root then
		return "NoCharacter"
	end
	-- One reason for all three movement locks. The player is tucked under a
	-- Level 3 table or riding the Level 2 slide: in every case the body the
	-- marker would be aimed from is not theirs to point right now.
	if player:GetAttribute("Level3_Hiding") == true
		or character:GetAttribute("Level2_ForcedSliding") == true
		or character:GetAttribute("Level2_RagdollServerActive") == true then
		return "Hiding"
	end
	return nil
end

local function place(player: Player): (string?, number?)
	local refusal = refusalFor(player)
	if refusal then return refusal end

	local now = os.clock()
	if now - (lastPlaceAt[player] or -math.huge) < PLACE_COOLDOWN then
		return "RateLimited"
	end
	-- Stamped before the durable call, and kept even when that call refuses:
	-- the throttle exists to stop a spamming client hammering the profile
	-- transaction, and an empty pack is exactly the case that would retry.
	lastPlaceAt[player] = now

	-- Read the geometry BEFORE consuming. Invoke yields, and a player who dies
	-- in that window has still paid for the marker; placing it where they asked
	-- from is both honest and impossible for a client to influence.
	local root = player.Character.HumanoidRootPart
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local forward = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
	local ahead = root.Position + forward * FORWARD_OFFSET
	local origin = Vector3.new(ahead.X, floorHeight(ahead) + FLOOR_CLEARANCE, ahead.Z)

	-- ZyntraInventory owns the durable side. On ANY doubt -- module missing, the
	-- invoke erroring, a false answer -- nothing is placed, because the marker
	-- would otherwise be free.
	local ok, consumed = pcall(function()
		return ServerStorage:WaitForChild("ZyntraInventory", 5):Invoke("Consume", player, "RouteMarker", 1)
	end)
	if not ok then return "Unavailable" end
	if consumed ~= true then return "NoMarkers" end

	local list = activeList(player)
	-- The pack is spent either way, so the cap retires the OLDEST marker rather
	-- than refusing: a player walking a long corridor keeps a moving trail.
	local limit = maxActive()
	while #list >= limit do
		local oldest = table.remove(list, 1)
		if oldest then oldest:Destroy() end
	end
	table.insert(list, spawnMarker(player, origin, forward))
	publishCount(player, #list)
	return nil, #list
end

remote.OnServerEvent:Connect(function(player, message)
	-- "place" is the entire client vocabulary. Anything else -- including a
	-- second argument carrying a position or a CFrame -- is never read.
	if message ~= "place" then return end
	local refusal, count = place(player)
	if player.Parent ~= Players then return end
	if refusal then
		remote:FireClient(player, "refused", refusal)
	else
		remote:FireClient(player, "placed", count)
	end
end)

-- Markers live exactly as long as the round does. They are NOT removed when
-- their placer dies or leaves: the arrow is information the rest of the team
-- is still walking on, and deleting it would punish the party for the death
-- that made the route worth marking. A leaver's count is dropped instead, so
-- a rejoin starts from zero and the corpse's markers are nobody's to retire.
local function clearAll()
	markerFolder():ClearAllChildren()
	table.clear(placed)
	table.clear(lastPlaceAt)
	for _, player in ipairs(Players:GetPlayers()) do
		publishCount(player, 0)
	end
end

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") ~= true then clearAll() end
end)

Players.PlayerRemoving:Connect(function(player)
	placed[player] = nil
	lastPlaceAt[player] = nil
end)

local function onPlayer(player: Player)
	publishCount(player, 0)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do onPlayer(player) end
