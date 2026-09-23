-- First Entry Guide
--
-- A brand-new player spawns in the middle of the tunnel with six identical
-- bays around them and no idea which one starts the game. This draws a
-- one-time cyan trail from the player to the nearest Level 1 launch pad, with
-- a marker floating over that pad.
--
-- Client-only. "First login" is decided by the server: ZyntraMonetization's
-- loadProfile publishes ZyntraFirstLogin from whether the DataStore record
-- existed before the load committed it, so this runs on the first successful
-- login and on no other.

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIStyle = require(ReplicatedStorage:WaitForChild("UIStyle"))

local player = Players.LocalPlayer
local roundStatus = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RoundStatus")

-- The lobby's Zyntra accent, and the colour of the beam this marker labels.
-- Deliberately NOT the in-level green: the marker belongs to the lobby.
local ZYNTRA_CYAN = Color3.fromRGB(73, 245, 204)
local RECOMPUTE_INTERVAL = 0.75
local RECOMPUTE_MOVE = 3
local HOVER = Vector3.new(0, 0.35, 0)
-- TunnelLobbyBuilder's built value, used only if a pad lost its attribute.
local DEFAULT_QUEUE_RADIUS = 7.4
local AGENT = {AgentRadius = 2, AgentHeight = 5, AgentCanJump = false}
local ENDING_EVENTS = {
	queuehost = true,
	queueconfigured = true,
	lobbycountdown = true,
	loadinggame = true,
}

local holder, billboard, arrow, path
local attachments, beams = {}, {}
local connections = {}
local chainCount, visible = 0, false
local finished, latched, computing = false, false, false
local lastComputeAt, lastOrigin, lastFailed = -math.huge, nil, true
local bobClock = 0
local finish

local function level1Room()
	local lobby = workspace:FindFirstChild("ServerLobby")
	local rooms = lobby and lobby:FindFirstChild("LevelQueueRooms")
	local room = rooms and rooms:FindFirstChild("Level1QueueRoom")
	if not room or room:GetAttribute("LevelEnabled") ~= true then return nil end
	return room
end

-- Nearest Level 1 pad by horizontal distance, and whether the player already
-- stands on one of them (the "arrived" end condition). Scoped to the Level 1
-- bay: the other bays name their own pads LaunchZone5..LaunchZone24.
local function scanPads(position)
	local room = level1Room()
	if not room then return nil, false end
	local best, bestDistance
	for _, child in ipairs(room:GetChildren()) do
		if string.match(child.Name, "^LaunchZone%d+$") and child:IsA("BasePart") then
			local pad = child.Position
			local offsetX, offsetZ = position.X - pad.X, position.Z - pad.Z
			local distance = math.sqrt(offsetX * offsetX + offsetZ * offsetZ)
			local radius = child:GetAttribute("QueueRadius")
			if type(radius) ~= "number" then radius = DEFAULT_QUEUE_RADIUS end
			if distance <= radius then return nil, true end
			if not bestDistance or distance < bestDistance then
				best, bestDistance = child, distance
			end
		end
	end
	return best, false
end

local function makeBeam()
	local beam = Instance.new("Beam")
	beam.Color = ColorSequence.new(ZYNTRA_CYAN)
	beam.Transparency = NumberSequence.new(0.25)
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Enabled = false
	-- No texture by default: an asset id that turns out to be unusable renders
	-- as a broken stripe, and this is the first thing a new player ever sees.
	-- Set a BeamTexture string attribute on this script to audition one in
	-- Studio; the scroll then runs from the player towards the pad.
	local texture = script:GetAttribute("BeamTexture")
	if type(texture) == "string" and texture ~= "" then
		beam.Texture = texture
		beam.TextureLength = 4
		beam.TextureSpeed = 2
	end
	beam.Parent = holder
	return beam
end

local function setVisible(enabled)
	if enabled == visible then return end
	visible = enabled
	billboard.Enabled = enabled
	for index, beam in ipairs(beams) do
		beam.Enabled = enabled and index < chainCount
	end
end

-- Attachments and beams are pooled: a recompute moves them, it never rebuilds
-- them.
local function setChain(points)
	for index, position in ipairs(points) do
		local attachment = attachments[index]
		if not attachment then
			attachment = Instance.new("Attachment")
			attachment.Parent = holder
			attachments[index] = attachment
		end
		attachment.WorldPosition = position + HOVER
	end
	chainCount = #points
	for index = 1, math.max(#beams, chainCount - 1) do
		local beam = beams[index]
		if not beam and index < chainCount then
			beam = makeBeam()
			beams[index] = beam
		end
		if beam then
			if index < chainCount then
				beam.Attachment0 = attachments[index]
				beam.Attachment1 = attachments[index + 1]
			end
			beam.Enabled = visible and index < chainCount
		end
	end
end

local function recompute(origin, target)
	local points
	local ok = pcall(function()
		path:ComputeAsync(origin, target)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		points = {}
		for _, waypoint in ipairs(path:GetWaypoints()) do
			table.insert(points, waypoint.Position)
		end
	end
	if points and #points >= 2 then
		lastFailed = false
	else
		-- A straight line still points the right way, and lastFailed makes the
		-- next tick retry instead of waiting for the player to move.
		points = {origin, target}
		lastFailed = true
	end
	computing = false
	if finished then return end
	setChain(points)
end

local function update(deltaTime)
	if finished then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		setVisible(false)
		return
	end
	local pad, arrived = scanPads(root.Position)
	if arrived then
		finish()
		return
	end
	if not pad then
		setVisible(false)
		return
	end
	if billboard.Adornee ~= pad then billboard.Adornee = pad end
	setVisible(true)
	bobClock += deltaTime
	arrow.Position = UDim2.new(0, 0, 0.58, math.sin(bobClock * 4) * 6)

	local now = os.clock()
	if computing or now - lastComputeAt < RECOMPUTE_INTERVAL then return end
	if lastOrigin and not lastFailed
		and (root.Position - lastOrigin).Magnitude <= RECOMPUTE_MOVE then return end
	lastComputeAt = now
	lastOrigin = root.Position
	computing = true
	task.spawn(recompute, root.Position, pad.Position)
end

function finish()
	if finished then return end
	finished = true
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(attachments)
	table.clear(beams)
	if holder then
		holder:Destroy()
		holder = nil
	end
	billboard, arrow, path = nil, nil, nil
end

local function start()
	if finished then return end
	holder = Instance.new("Part")
	holder.Name = "FirstEntryGuide"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Parent = workspace

	billboard = Instance.new("BillboardGui")
	billboard.Name = "FirstEntryMarker"
	-- Offset pixels, not studs: the marker keeps a readable size on a phone.
	billboard.Size = UDim2.fromOffset(240, 96)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Enabled = false
	billboard.Parent = holder

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.5)
	title.Text = "LEVEL 1 START HERE"
	title.TextScaled = true
	title.TextStrokeTransparency = 0.5
	title.Parent = billboard
	-- UI_STYLE_20260915 (Trello #98). It was floating text over the lobby; it is
	-- now the same dark card the rest of the game prints on. The pathfinding
	-- beam, the placement and every ending condition are untouched.
	UIStyle.panel(title, {Stroke = ZYNTRA_CYAN, StrokeTransparency = 0.4})
	UIStyle.title(title, {TextColor = ZYNTRA_CYAN})
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingLeft = UDim.new(0, 10)
	titlePad.PaddingRight = UDim.new(0, 10)
	titlePad.PaddingTop = UDim.new(0, 5)
	titlePad.PaddingBottom = UDim.new(0, 5)
	titlePad.Parent = title

	arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 0.4)
	arrow.Position = UDim2.fromScale(0, 0.58)
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "▼"
	arrow.TextColor3 = ZYNTRA_CYAN
	arrow.TextScaled = true
	arrow.TextStrokeTransparency = 0.5
	arrow.Parent = billboard

	path = PathfindingService:CreatePath(AGENT)

	table.insert(connections, RunService.Heartbeat:Connect(update))
	table.insert(connections, player:GetAttributeChangedSignal("InRound"):Connect(function()
		if player:GetAttribute("InRound") == true then finish() end
	end))
	table.insert(connections, roundStatus.OnClientEvent:Connect(function(event)
		if ENDING_EVENTS[event] then finish() end
	end))
end

local profileConnection
local function considerProfile()
	if latched or finished then return end
	if player:GetAttribute("ZyntraProfileLoaded") ~= true then return end
	latched = true
	profileConnection:Disconnect()
	profileConnection = nil
	-- Read exactly once, at load: ZyntraFirstLogin is published immediately
	-- before ZyntraProfileLoaded and then stays true for the whole session, so
	-- re-reading it would say nothing new. The guide's own `finished` latch owns
	-- the end.
	if player:GetAttribute("ZyntraFirstLogin") ~= true
		or workspace:GetAttribute("ReservedRoundServer") == true
		or player:GetAttribute("InRound") == true then
		return
	end
	start()
end

-- No profile, no guide: a load that never completes simply leaves this idle.
profileConnection = player:GetAttributeChangedSignal("ZyntraProfileLoaded"):Connect(considerProfile)
script.Destroying:Connect(function()
	if profileConnection then
		profileConnection:Disconnect()
		profileConnection = nil
	end
	finish()
end)
considerProfile()
