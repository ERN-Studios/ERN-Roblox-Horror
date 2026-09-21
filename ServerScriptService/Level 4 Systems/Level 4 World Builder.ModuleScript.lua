--!strict
-- Level 4 World Builder
--
-- Turns a plan into the standing neighbourhood and returns the manifest the
-- Round Adapter validates. Everything is Parts, WedgeParts and stock materials:
-- Level 4 introduces NO asset ids. Each instance the art pass is expected to
-- replace carries Level4_Placeholder = true, so a search for that attribute is
-- the whole hand-over list.
--
-- Three things this file is responsible for keeping true, because nothing
-- downstream can recover from them being wrong:
--
--   1. THE ARRIVAL GROUND EXISTS FIRST. The service passage, its floor and the
--      compatibility Elevator/ElevatorSpawn/MazeStart are built before anything
--      else, so a streaming client always has real ground under it at the
--      moment GameManager places the party. Level 3 learned this the hard way.
--   2. THE DYNAMIC LIGHTS ARE COUNTED. "A few lights" is not a rule anybody
--      keeps by eye, so every light goes through one helper that counts it and
--      turns its shadow off, and the adapter asserts the total.
--   3. EVERY ROUND OBJECT HANGS OFF ONE MODEL. Cleanup destroys the world and
--      that is the whole teardown; nothing is parented to Workspace directly
--      except the three compatibility markers, which are tagged and swept.

local RunService = game:GetService("RunService")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))

local WorldBuilder = {}

WorldBuilder.Version = 1

local COLORS = Configuration.Colors
local STREETS = Configuration.Streets
local LOTS = Configuration.Lots
local DERIVED = Configuration.Derived

-- ---------------------------------------------------------------------------
-- Primitives
-- ---------------------------------------------------------------------------

local function placeholder(object: Instance): Instance
	object:SetAttribute("Level4_Placeholder", true)
	return object
end

local function part(parent: Instance, name: string, cframe: CFrame, size: Vector3,
	color: Color3, material: Enum.Material?): BasePart
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.Size = size
	object.CFrame = cframe
	object.Color = color
	object.Material = material or Enum.Material.SmoothPlastic
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	-- Nothing decorative in a suburb full of flat surfaces earns a shadow pass.
	object.CastShadow = false
	object.Parent = parent
	placeholder(object)
	return object
end

local function wedge(parent: Instance, name: string, cframe: CFrame, size: Vector3,
	color: Color3, material: Enum.Material?): BasePart
	local object = Instance.new("WedgePart")
	object.Name = name
	object.Anchored = true
	object.Size = size
	object.CFrame = cframe
	object.Color = color
	object.Material = material or Enum.Material.SmoothPlastic
	object.CastShadow = false
	object.Parent = parent
	placeholder(object)
	return object
end

-- Pure dressing: nothing collides with it, nothing touches it, and no ray --
-- including the Neighbour's own line-of-sight tests -- is stopped by it.
local function decorative(object: BasePart): BasePart
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	return object
end

-- Standing geometry that is not an interaction: it collides and it BLOCKS
-- RAYS. Hedges, fences, pavements and furniture are solid, because a hedge a
-- sightline passes straight through is a hedge that lies to the player.
local function solid(object: BasePart): BasePart
	object.CanCollide = true
	object.CanTouch = false
	object.CanQuery = true
	return object
end

-- One text face, drawn with the engine's own fonts. No image, no decal, no id.
local function face(object: BasePart, text: string, faceEnum: Enum.NormalId,
	color: Color3, scale: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Level4Face"
	gui.Face = faceEnum
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = scale or 22
	gui.AlwaysOnTop = false
	gui.Parent = object
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	placeholder(gui)
	return gui
end

-- ---------------------------------------------------------------------------
-- Build session
--
-- One table threaded through every builder, so the light count, the yield
-- cadence and the runtime folder are never module state that could survive a
-- failed build into the next one.
-- ---------------------------------------------------------------------------

local function newSession(plan: any, generation: number)
	return {
		Plan = plan,
		Generation = generation,
		Origin = Configuration.WorldOrigin,
		LightCount = 0,
		LotsBuilt = 0,
	}
end

-- Every light in Level 4 comes through here: counted, shadowless, and short
-- ranged. The adapter asserts the final count against the configured ceiling.
local function light(session: any, parent: BasePart, className: string,
	color: Color3, brightness: number, range: number): Light
	local object = Instance.new(className) :: any
	object.Name = "Level4Light"
	object.Color = color
	object.Brightness = brightness
	object.Range = range
	object.Shadows = false
	object.Parent = parent
	session.LightCount += 1
	placeholder(object)
	return object
end

local function worldPoint(session: any, x: number, y: number, z: number): Vector3
	return session.Origin + Vector3.new(x, y, z)
end

local function at(session: any, x: number, y: number, z: number): CFrame
	return CFrame.new(worldPoint(session, x, y, z))
end

local function yieldIfNeeded(session: any)
	session.LotsBuilt += 1
	if session.LotsBuilt % Configuration.Performance.BuildYieldEveryLots == 0 then
		RunService.Heartbeat:Wait()
	end
end

-- ---------------------------------------------------------------------------
-- Ground, streets and the service passage
-- ---------------------------------------------------------------------------

local function buildGround(session: any, parent: Instance)
	local bounds = session.Plan.Boundary.Bounds
	local width = bounds.MaxX - bounds.MinX + 640
	local depth = bounds.MaxZ - bounds.MinZ + 640
	local centreX = (bounds.MinX + bounds.MaxX) / 2
	local centreZ = (bounds.MinZ + bounds.MaxZ) / 2
	-- Unnaturally uniform green. One slab: the lawn is not supposed to vary.
	local ground = part(parent, "Level4Ground", at(session, centreX, -1, centreZ),
		Vector3.new(width, 2, depth), COLORS.Lawn, Enum.Material.Grass)
	ground:SetAttribute("Level4_Ground", true)
end

local function buildStreet(session: any, parent: Instance, edge: any)
	local plan = session.Plan
	local a, b = plan.JunctionById[edge.A], plan.JunctionById[edge.B]
	local halfWidth = edge.Kind == "Service" and STREETS.ServicePassageHalfWidth or STREETS.HalfWidth
	-- The shortcut is a pedestrian cut, not a carriageway: narrower, but still
	-- wider than the agent needs, because a chase has to be able to use it.
	if edge.Kind == "Shortcut" then halfWidth = math.max(DERIVED.AgentRadius * 3, 9) end

	local centreX, centreZ = (a.X + b.X) / 2, (a.Z + b.Z) / 2
	local spanX, spanZ = math.abs(b.X - a.X), math.abs(b.Z - a.Z)
	local sizeX = spanX > spanZ and spanX or halfWidth * 2
	local sizeZ = spanZ > spanX and spanZ or halfWidth * 2

	local road = part(parent, "Level4Road_" .. edge.Id, at(session, centreX, 0.1, centreZ),
		Vector3.new(sizeX, 0.4, sizeZ), COLORS.Asphalt, Enum.Material.Asphalt)
	road:SetAttribute("Level4_StreetId", edge.Id)

	-- Kerb and pavement on both sides of the carriageways. The shortcut is a
	-- path; it gets neither.
	if edge.Kind == "Shortcut" then return end
	local sidewalk = STREETS.SidewalkWidth
	for _, side in ipairs({-1, 1}) do
		local offsetX = spanX > spanZ and 0 or side * (halfWidth + sidewalk / 2)
		local offsetZ = spanX > spanZ and side * (halfWidth + sidewalk / 2) or 0
		local walkX = spanX > spanZ and sizeX or sidewalk
		local walkZ = spanX > spanZ and sidewalk or sizeZ
		solid(part(parent, "Level4Pavement_" .. edge.Id,
			at(session, centreX + offsetX, STREETS.KerbHeight / 2 + 0.1, centreZ + offsetZ),
			Vector3.new(walkX, STREETS.KerbHeight, walkZ), COLORS.Kerb, Enum.Material.Concrete))
	end
end

-- The compatibility arrival. GameManager's connectElevator() needs a Workspace
-- model called Elevator with DoorL and DoorR, placeSafelyInElevator needs
-- ElevatorSpawn, and ensureWorld waits on MazeStart. Level 4's version of that
-- is a service roller shutter at the west end of the passage -- the door the
-- party comes through out of Level 3.
local function buildArrival(session: any, parent: Instance): (Model, BasePart, BasePart)
	local plan = session.Plan
	local spawn = plan.ArrivalSpawn
	local halfWidth = STREETS.ServicePassageHalfWidth

	-- Solid ground under the arrival, built before anything else in the world,
	-- so a streaming client always has a floor at the advertised position.
	local floor = part(parent, "Level4ServiceFloor",
		at(session, spawn.X - 6, 0.1, 0), Vector3.new(44, 1, halfWidth * 2 + 6),
		COLORS.Concrete, Enum.Material.Concrete)
	floor:SetAttribute("Level4_ArrivalGround", true)

	local model = Instance.new("Model")
	model.Name = "Elevator"
	model:SetAttribute("Level4_CompatibilityMarker", true)
	model.Parent = workspace
	placeholder(model)

	local frameX = spawn.X - 24
	local doorHeight = DERIVED.DoorHeight + 1
	local doorHalf = DERIVED.DoorWidth * 0.6
	part(model, "ServiceHeader", at(session, frameX, doorHeight + 1, 0),
		Vector3.new(2, 2, doorHalf * 2 + 6), COLORS.ZyntraCabinet, Enum.Material.Metal)
	for _, side in ipairs({-1, 1}) do
		part(model, "ServiceJamb", at(session, frameX, doorHeight / 2, side * (doorHalf + 1.5)),
			Vector3.new(2, doorHeight, 3), COLORS.ZyntraCabinet, Enum.Material.Metal)
	end
	local doorL = part(model, "DoorL", at(session, frameX, doorHeight / 2, -doorHalf / 2),
		Vector3.new(1.2, doorHeight, doorHalf), COLORS.ZyntraCabinet, Enum.Material.DiamondPlate)
	local doorR = part(model, "DoorR", at(session, frameX, doorHeight / 2, doorHalf / 2),
		Vector3.new(1.2, doorHeight, doorHalf), COLORS.ZyntraCabinet, Enum.Material.DiamondPlate)
	doorL.Name = "DoorL"
	doorR.Name = "DoorR"
	model.PrimaryPart = doorL

	local spawnPad = part(workspace, "ElevatorSpawn", at(session, spawn.X, 0.7, spawn.Z),
		Vector3.new(12, 0.5, 12), COLORS.Concrete, Enum.Material.Concrete)
	spawnPad:SetAttribute("Level4_CompatibilityMarker", true)
	-- The pad is the surface the entry barrier's downward ray must hit.
	spawnPad.CanCollide = true

	local mazeStart = part(workspace, "MazeStart", spawnPad.CFrame, Vector3.new(2, 0.3, 2),
		COLORS.Zyntra, Enum.Material.Neon)
	decorative(mazeStart)
	mazeStart.Transparency = 1
	mazeStart:SetAttribute("Level4_CompatibilityMarker", true)

	return model, spawnPad, mazeStart
end

-- ---------------------------------------------------------------------------
-- Houses
-- ---------------------------------------------------------------------------

-- A facade window. Four of these is the normal house; the ExtraWindow anomaly
-- adds a fifth, and DrawnCurtains fills one of them on one side only.
local function buildWindow(parent: Instance, name: string, cframe: CFrame): BasePart
	local object = decorative(part(parent, name, cframe, Vector3.new(0.4, 4.2, 5),
		Color3.fromRGB(96, 116, 126), Enum.Material.Glass))
	object.Transparency = 0.35
	object.Reflectance = 0.08
	return object
end

local function buildHouseShell(session: any, parent: Instance, lot: any): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "House_" .. lot.Id
	model.Parent = parent
	placeholder(model)

	local width, depth = LOTS.HouseWidth, LOTS.HouseDepth
	local height = LOTS.StoreyHeight
	local wall = 1
	-- FacingZ is -1 when the house looks towards -z. The front wall is the one
	-- on the facing side.
	local frontZ = lot.Z + lot.FacingZ * depth / 2

	local floorPart = part(model, "HouseFloor", at(session, lot.X, 0.4, lot.Z),
		Vector3.new(width, 0.8, depth), COLORS.InteriorFloor, Enum.Material.WoodPlanks)
	model.PrimaryPart = floorPart

	local body = COLORS[lot.ColorKey] or COLORS.FadedCream

	-- Side and back walls are solid; the front wall is split around the door so
	-- the opening is real geometry, not a decal.
	for _, side in ipairs({-1, 1}) do
		part(model, "HouseWallSide", at(session, lot.X + side * (width / 2 - wall / 2), height / 2, lot.Z),
			Vector3.new(wall, height, depth), body, Enum.Material.Concrete)
	end
	part(model, "HouseWallBack", at(session, lot.X, height / 2, lot.Z - lot.FacingZ * (depth / 2 - wall / 2)),
		Vector3.new(width, height, wall), body, Enum.Material.Concrete)

	local doorWidth, doorHeight = DERIVED.DoorWidth, DERIVED.DoorHeight
	local sidePanel = (width - doorWidth) / 2
	for _, side in ipairs({-1, 1}) do
		part(model, "HouseWallFront",
			at(session, lot.X + side * (doorWidth / 2 + sidePanel / 2), height / 2, frontZ - lot.FacingZ * wall / 2),
			Vector3.new(sidePanel, height, wall), body, Enum.Material.Concrete)
	end
	-- Lintel over the opening, so a 10.5-stud door in a 13-stud wall still has
	-- a wall above it.
	part(model, "HouseDoorLintel",
		at(session, lot.X, doorHeight + (height - doorHeight) / 2, frontZ - lot.FacingZ * wall / 2),
		Vector3.new(doorWidth, height - doorHeight, wall), body, Enum.Material.Concrete)

	-- The door FRAME is the contract the art pass must keep: the AI, the house
	-- state machine and the interior volume all measure from it.
	local doorFrame = part(model, "DoorFrame",
		at(session, lot.X, doorHeight / 2, frontZ - lot.FacingZ * wall / 2),
		Vector3.new(doorWidth, doorHeight, wall), COLORS.Timber, Enum.Material.Wood)
	decorative(doorFrame)
	doorFrame.Transparency = 1
	doorFrame:SetAttribute("Level4_DoorFrame", true)
	doorFrame:SetAttribute("Level4_DoorWidth", doorWidth)
	doorFrame:SetAttribute("Level4_DoorHeight", doorHeight)

	-- Dark roof: two wedges meeting at a ridge that runs along x, over the
	-- middle of the house. A WedgePart is full height at its own -z face and
	-- zero at +z, so the half that sits on -z is turned 180 degrees to put its
	-- tall edge on the ridge rather than on the eaves.
	local roofHeight = LOTS.RoofHeight
	for _, side in ipairs({-1, 1}) do
		local turn = side < 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity
		wedge(model, "HouseRoof",
			at(session, lot.X, height + roofHeight / 2, lot.Z + side * depth / 4) * turn,
			Vector3.new(width + 2, roofHeight, depth / 2), COLORS.DarkRoof, Enum.Material.Slate)
	end

	-- Four windows on the facade, two each side of the door.
	local windowZ = frontZ - lot.FacingZ * (wall / 2 + 0.1)
	for index = 1, 4 do
		local column = index <= 2 and -1 or 1
		local inset = (index % 2 == 1) and 0.28 or 0.72
		buildWindow(model, "HouseWindow",
			at(session, lot.X + column * (doorWidth / 2 + sidePanel * inset), height * 0.58, windowZ)
				* CFrame.Angles(0, math.pi / 2, 0))
	end

	return model, doorFrame
end

-- The three reusable interiors. All share the floor, ceiling and door; the
-- module index decides the partition pattern, and module 3 adds the staircase
-- that proves the derived stair width is walkable.
local function buildInterior(session: any, model: Model, lot: any)
	local width, depth, height = LOTS.HouseWidth, LOTS.HouseDepth, LOTS.StoreyHeight
	local passage = DERIVED.PassageWidth
	local ceiling = DERIVED.InteriorCeiling

	part(model, "HouseCeiling", at(session, lot.X, ceiling, lot.Z),
		Vector3.new(width, 0.6, depth), COLORS.Interior, Enum.Material.Plaster)

	local interiorVolume = part(model, "InteriorVolume", at(session, lot.X, ceiling / 2, lot.Z),
		Vector3.new(width - 3, ceiling - 1, depth - 3), COLORS.Interior, Enum.Material.SmoothPlastic)
	decorative(interiorVolume)
	interiorVolume.Transparency = 1
	interiorVolume:SetAttribute("Level4_InteriorVolume", true)

	local module = lot.Interior
	if module == 1 or module == 3 then
		-- Open plan with a back room. One partition, one opening, no maze.
		local partitionZ = lot.Z - lot.FacingZ * depth * 0.18
		local panel = (width - passage) / 2
		for _, side in ipairs({-1, 1}) do
			part(model, "InteriorPartition",
				at(session, lot.X + side * (passage / 2 + panel / 2), height * 0.45, partitionZ),
				Vector3.new(panel, height * 0.9, 0.8), COLORS.Interior, Enum.Material.Plaster)
		end
	else
		-- Hallway down one side into two rooms. The hallway is exactly a
		-- passage wide, which is exactly a door wide, which is two players.
		local hallX = lot.X - width / 2 + passage / 2 + 0.5
		part(model, "InteriorPartition",
			at(session, hallX + passage / 2 + 0.4, height * 0.45, lot.Z),
			Vector3.new(0.8, height * 0.9, depth * 0.72), COLORS.Interior, Enum.Material.Plaster)
		part(model, "InteriorPartition",
			at(session, lot.X + width * 0.18, height * 0.45, lot.Z + lot.FacingZ * depth * 0.1),
			Vector3.new(width * 0.58, height * 0.9, 0.8), COLORS.Interior, Enum.Material.Plaster)
	end

	if module == 3 then
		-- A short flight to a half-landing. Rise and run come from Derived, so
		-- a taller or wider entity changes the stairs automatically.
		local rise, run = DERIVED.StairRise, DERIVED.StairRun
		local stairX = lot.X + width / 2 - DERIVED.StairWidth / 2 - 1.5
		for step = 1, 8 do
			part(model, "InteriorStair",
				at(session, stairX, rise * step - rise / 2, lot.Z - lot.FacingZ * (depth * 0.3 - run * step)),
				Vector3.new(DERIVED.StairWidth, rise, run), COLORS.Timber, Enum.Material.WoodPlanks)
		end
		part(model, "InteriorLanding",
			at(session, stairX, rise * 8 + 0.2, lot.Z - lot.FacingZ * (depth * 0.3 - run * 11)),
			Vector3.new(DERIVED.StairWidth, 0.5, run * 5), COLORS.Timber, Enum.Material.WoodPlanks)
	end

	-- Ordinary furniture, repeated a little too precisely. No clutter: the
	-- brief is explicit that random mess would hide the gameplay clues.
	solid(part(model, "Sofa", at(session, lot.X - width * 0.24, 1.6, lot.Z + lot.FacingZ * depth * 0.22),
		Vector3.new(9, 3, 3.6), Color3.fromRGB(122, 112, 104), Enum.Material.Fabric))
	solid(part(model, "CoffeeTable", at(session, lot.X - width * 0.24, 1.2, lot.Z + lot.FacingZ * depth * 0.05),
		Vector3.new(5, 0.4, 2.6), COLORS.Timber, Enum.Material.Wood))
	local frame = decorative(part(model, "EmptyPictureFrame",
		at(session, lot.X + width / 2 - 1.2, height * 0.6, lot.Z),
		Vector3.new(0.3, 4, 5.4), COLORS.Timber, Enum.Material.Wood))
	frame:SetAttribute("Level4_EmptyFrame", true)
end

local function buildYard(session: any, model: Instance, lot: any): (BasePart, BasePart)
	local width, depth = LOTS.HouseWidth, LOTS.HouseDepth
	local frontZ = lot.Z + lot.FacingZ * (depth / 2 + LOTS.FrontYardDepth)

	-- Precise hedges: exactly the same length on every lot, on both flanks.
	for _, side in ipairs({-1, 1}) do
		solid(part(model, "Hedge",
			at(session, lot.X + side * (width / 2 + 2), LOTS.HedgeHeight / 2,
				lot.Z + lot.FacingZ * LOTS.FrontYardDepth * 0.4),
			Vector3.new(LOTS.HedgeThickness, LOTS.HedgeHeight, depth + LOTS.FrontYardDepth),
			COLORS.Hedge, Enum.Material.Grass))
	end
	-- A low fence across the front, with a gap on the path.
	local gate = DERIVED.DoorWidth + 2
	for _, side in ipairs({-1, 1}) do
		local panel = (width + 4 - gate) / 2
		solid(part(model, "Fence",
			at(session, lot.X + side * (gate / 2 + panel / 2), LOTS.FenceHeight / 2, frontZ),
			Vector3.new(panel, LOTS.FenceHeight, 0.5), COLORS.Concrete, Enum.Material.WoodPlanks))
	end
	-- Path from the gate to the door.
	decorative(part(model, "Path",
		at(session, lot.X, 0.15, lot.Z + lot.FacingZ * (depth / 2 + LOTS.FrontYardDepth / 2)),
		Vector3.new(DERIVED.DoorWidth, 0.3, LOTS.FrontYardDepth), COLORS.Concrete, Enum.Material.Concrete))

	local mailbox = part(model, "Mailbox",
		at(session, lot.X + width * 0.34, LOTS.MailboxHeight / 2, frontZ - lot.FacingZ * 1.6),
		Vector3.new(1.6, LOTS.MailboxHeight, 1.6), COLORS.Timber, Enum.Material.Wood)
	decorative(mailbox)
	mailbox:SetAttribute("Level4_Mailbox", true)
	-- Mailboxes normally face the street.
	mailbox:SetAttribute("Level4_MailboxFacesStreet", true)

	-- The porch signal: the readable house-state light. One part, one counted
	-- light, and the colour is the whole language.
	local porch = part(model, "PorchSignal",
		at(session, lot.X + DERIVED.DoorWidth / 2 + 2, DERIVED.DoorHeight - 1.5,
			lot.Z + lot.FacingZ * (depth / 2 + 0.6)),
		Vector3.new(1.4, 1.4, 1.4), COLORS.SignalSafe, Enum.Material.Neon)
	decorative(porch)
	porch:SetAttribute("Level4_PorchSignal", true)
	return mailbox, porch
end

local function buildAnomaly(session: any, model: Model, lot: any, mailbox: BasePart)
	if not lot.Anomaly then return end
	local width, depth, height = LOTS.HouseWidth, LOTS.HouseDepth, LOTS.StoreyHeight
	local frontZ = lot.Z + lot.FacingZ * (depth / 2 + 0.6)
	local socket: BasePart

	if lot.Anomaly == "ExtraWindow" then
		socket = buildWindow(model, "AnomalyExtraWindow",
			at(session, lot.X + width * 0.36, height * 0.82, frontZ) * CFrame.Angles(0, math.pi / 2, 0))
	elseif lot.Anomaly == "WrongNumber" then
		socket = decorative(part(model, "AnomalyHouseNumber",
			at(session, lot.X - DERIVED.DoorWidth / 2 - 2, DERIVED.DoorHeight - 2, frontZ),
			Vector3.new(0.3, 2.2, 3.4), COLORS.Concrete, Enum.Material.Metal))
		-- A number that does not belong to this street's run.
		face(socket, "13B", lot.FacingZ < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
			Color3.fromRGB(40, 40, 44), 30)
	elseif lot.Anomaly == "ReversedMailbox" then
		-- The mailbox is turned to face the house instead of the street.
		mailbox.CFrame = mailbox.CFrame * CFrame.Angles(0, math.pi, 0)
		mailbox:SetAttribute("Level4_MailboxFacesStreet", false)
		socket = mailbox
	else -- DrawnCurtains
		socket = decorative(part(model, "AnomalyDrawnCurtains",
			at(session, lot.X - width * 0.3, height * 0.58, frontZ),
			Vector3.new(0.3, 4.6, 5.4), Color3.fromRGB(184, 168, 150), Enum.Material.Fabric))
	end

	-- The reversed-mailbox anomaly IS the mailbox, and the mailbox's own name is
	-- part of the art contract, so only a purpose-built socket gets renamed.
	if socket ~= mailbox then socket.Name = "AnomalySocket" end
	socket:SetAttribute("Level4_AnomalySocket", true)
	socket:SetAttribute("Level4_Anomaly", lot.Anomaly)
	socket:SetAttribute("Level4_LotId", lot.Id)
end

-- ---------------------------------------------------------------------------
-- The three signal fixtures
-- ---------------------------------------------------------------------------

local function newPrompt(parent: BasePart, actionText: string, objectText: string,
	holdSeconds: number, distance: number): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Level4Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdSeconds
	prompt.MaxActivationDistance = distance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent
	return prompt
end

local function buildSignal(session: any, record: any, task: any)
	local lot = record.Lot
	local model = record.Model
	local width, depth, height = LOTS.HouseWidth, LOTS.HouseDepth, LOTS.StoreyHeight
	local objectives = Configuration.Objectives
	local hold = task.Forgiving and objectives.ForgivingHoldSeconds or objectives.StandardHoldSeconds
	local reach = task.Forgiving and objectives.ForgivingPromptDistance or objectives.StandardPromptDistance

	local fixture: BasePart
	local clue: BasePart
	if task.Kind == "FacadeCompare" then
		-- On the porch: a reference board showing what this facade SHOULD look
		-- like. The clue is visible from outside; nothing here needs hearing.
		fixture = part(model, "SignalFixture",
			at(session, lot.X - DERIVED.DoorWidth / 2 - 3.4, 5.2,
				lot.Z + lot.FacingZ * (depth / 2 + 1.4)),
			Vector3.new(0.4, 6, 7), COLORS.ZyntraCabinet, Enum.Material.Metal)
		face(fixture, "ZYNTRA REFERENCE\n4 WINDOWS\nNUMBER IN SEQUENCE\nBOX TO STREET\nCURTAINS OPEN",
			lot.FacingZ < 0 and Enum.NormalId.Front or Enum.NormalId.Back, COLORS.Zyntra, 26)
		clue = fixture
	elseif task.Kind == "Broadcast" then
		-- Inside: a CRT showing the wrong broadcast. The screen is the clue and
		-- it is a colour, not a sound.
		fixture = part(model, "SignalFixture",
			at(session, lot.X + width * 0.2, 3.4, lot.Z + lot.FacingZ * depth * 0.2),
			Vector3.new(6, 5, 5), Color3.fromRGB(58, 56, 54), Enum.Material.Metal)
		clue = part(model, "SignalClueScreen",
			fixture.CFrame * CFrame.new(0, 0.4, -lot.FacingZ * 2.6),
			Vector3.new(4.6, 3.4, 0.3), COLORS.Zyntra, Enum.Material.Neon)
		decorative(clue)
		face(clue, "OFF AIR\nSIGNAL 0" .. task.Index,
			lot.FacingZ < 0 and Enum.NormalId.Back or Enum.NormalId.Front,
			Color3.fromRGB(12, 16, 18), 28)
	else -- Sample
		-- In the front yard: a Zyntra measuring stake reading out of range.
		fixture = part(model, "SignalFixture",
			at(session, lot.X - width * 0.3, 3.6, lot.Z + lot.FacingZ * (depth / 2 + 7)),
			Vector3.new(1, 7, 1), COLORS.ZyntraCabinet, Enum.Material.Metal)
		clue = part(model, "SignalClueReadout",
			at(session, lot.X - width * 0.3, 6.6, lot.Z + lot.FacingZ * (depth / 2 + 7.4)),
			Vector3.new(4.2, 2.4, 0.3), COLORS.Zyntra, Enum.Material.Neon)
		decorative(clue)
		face(clue, "OUT OF RANGE",
			lot.FacingZ < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
			Color3.fromRGB(12, 16, 18), 26)
	end

	fixture.Name = "SignalFixture"
	fixture:SetAttribute("Level4_SignalIndex", task.Index)
	fixture:SetAttribute("Level4_SignalKind", task.Kind)
	clue:SetAttribute("Level4_SignalClue", task.Index)

	local prompt = newPrompt(fixture, "Investigate",
		("SIGNAL %02d  //  ZONE %d"):format(task.Index, task.Zone), hold, reach)
	prompt:SetAttribute("Level4_SignalIndex", task.Index)

	record.Signal = {Index = task.Index, Kind = task.Kind, Forgiving = task.Forgiving,
		Fixture = fixture, Clue = clue, Prompt = prompt, Zone = task.Zone, LotId = lot.Id}
end

-- ---------------------------------------------------------------------------
-- Landmarks: green, tower, bus stop, cabinet, exit, boundary
-- ---------------------------------------------------------------------------

local function buildGreen(session: any, parent: Instance)
	local green = session.Plan.Green
	local model = Instance.new("Model")
	model.Name = "CentralGreen"
	model.Parent = parent
	placeholder(model)
	solid(part(model, "GreenSurface", at(session, green.X, 0.2, green.Z),
		Vector3.new(green.W, 0.4, green.D), COLORS.Lawn, Enum.Material.Grass))
	solid(part(model, "Bench", at(session, green.X - 12, 1.6, green.Z + 8),
		Vector3.new(8, 0.5, 2.4), COLORS.Timber, Enum.Material.WoodPlanks))
	-- A switched-off playground frame and a phone box: landmarks, not props to
	-- interact with.
	for _, offset in ipairs({-4, 0, 4}) do
		solid(part(model, "PlaygroundFrame", at(session, green.X + 14, 4, green.Z + offset),
			Vector3.new(0.8, 8, 0.8), Color3.fromRGB(150, 92, 74), Enum.Material.Metal))
	end
	solid(part(model, "PhoneBox", at(session, green.X - 22, 5, green.Z - 14),
		Vector3.new(4, 10, 4), Color3.fromRGB(78, 96, 112), Enum.Material.Metal))
end

local function buildTower(session: any, parent: Instance): Model
	local tower = session.Plan.Tower
	local model = Instance.new("Model")
	model.Name = "SignalTower"
	model:SetAttribute("Level4_Tower", true)
	model.Parent = parent
	placeholder(model)

	local spread = tower.LegSpread
	for _, x in ipairs({-1, 1}) do
		for _, z in ipairs({-1, 1}) do
			solid(part(model, "TowerLeg",
				at(session, tower.X + x * spread / 2, tower.Height * 0.4, tower.Z + z * spread / 2),
				Vector3.new(2, tower.Height * 0.8, 2), COLORS.ZyntraCabinet, Enum.Material.Metal))
		end
	end
	local tank = decorative(part(model, "TowerTank",
		at(session, tower.X, tower.Height * 0.86, tower.Z),
		Vector3.new(spread * 1.7, tower.Height * 0.2, spread * 1.7),
		COLORS.BlueGrey, Enum.Material.Metal))
	tank.Shape = Enum.PartType.Cylinder
	tank.CFrame = tank.CFrame * CFrame.Angles(0, 0, math.pi / 2)
	local beacon = decorative(part(model, "TowerBeacon",
		at(session, tower.X, tower.Height, tower.Z), Vector3.new(2, 2, 2),
		COLORS.Zyntra, Enum.Material.Neon))
	light(session, beacon, "PointLight", COLORS.Zyntra, 1.4, 40)
	model.PrimaryPart = tank
	return model
end

local function buildFinale(session: any, parent: Instance): any
	local plan = session.Plan
	local model = Instance.new("Model")
	model.Name = "ExtractionBeacon"
	model.Parent = parent
	placeholder(model)

	-- The bus shelter. Empty, ordinary, and the one place on the street where a
	-- Zyntra cabinet does not look like a mistake.
	local stop = plan.BusStop
	solid(part(model, "ShelterRoof", at(session, stop.X, 9.4, stop.Z),
		Vector3.new(6, 0.5, 16), COLORS.BlueGrey, Enum.Material.Metal))
	solid(part(model, "ShelterBack", at(session, stop.X + 2.8, 5, stop.Z),
		Vector3.new(0.4, 9, 16), Color3.fromRGB(150, 164, 172), Enum.Material.Glass))
	solid(part(model, "ShelterBench", at(session, stop.X + 1.2, 2.2, stop.Z),
		Vector3.new(2.4, 0.4, 12), COLORS.Timber, Enum.Material.WoodPlanks))
	local sign = decorative(part(model, "ShelterSign", at(session, stop.X - 3, 8, stop.Z - 9),
		Vector3.new(0.3, 4.4, 6), COLORS.ZyntraCabinet, Enum.Material.Metal))
	face(sign, "ZYNTRA TRANSIT\nSERVICE 04", Enum.NormalId.Left, COLORS.Zyntra, 26)

	-- The cabinet, and the three controls around it. One player walking from
	-- one to the next can do all three; a party can stand at one each.
	local cabinetPosition = plan.Cabinet
	local cabinet = part(model, "SignalCabinet",
		at(session, cabinetPosition.X, 5, cabinetPosition.Z),
		Vector3.new(5, 10, 4), COLORS.ZyntraCabinet, Enum.Material.DiamondPlate)
	cabinet:SetAttribute("Level4_Cabinet", true)
	local status = decorative(part(model, "CabinetStatus",
		at(session, cabinetPosition.X - 2.7, 7.4, cabinetPosition.Z),
		Vector3.new(0.4, 2, 2), COLORS.SignalDangerous, Enum.Material.Neon))
	status:SetAttribute("Level4_CabinetStatus", true)
	light(session, cabinet, "PointLight", COLORS.Zyntra, 1.1, 26)

	local controls = {}
	for index = 1, Configuration.Objectives.CabinetControlCount do
		local angle = math.pi * (index - 2) / 3
		local radius = 7
		local control = part(model, "CabinetControl" .. index,
			at(session, cabinetPosition.X + math.sin(angle) * radius, 4.4,
				cabinetPosition.Z + math.cos(angle) * radius),
			Vector3.new(2, 4.4, 2), COLORS.BlueGrey, Enum.Material.Metal)
		control:SetAttribute("Level4_CabinetControl", index)
		face(control, ("0%d"):format(index), Enum.NormalId.Top, COLORS.Zyntra, 40)
		local prompt = newPrompt(control, "Set", ("BEACON CONTROL %02d"):format(index),
			Configuration.Objectives.CabinetControlHoldSeconds,
			Configuration.Objectives.CabinetControlPromptDistance)
		prompt.Enabled = false
		prompt:SetAttribute("Level4_CabinetControl", index)
		controls[index] = {Index = index, Part = control, Prompt = prompt}
	end

	-- The exit. A transit door beside the shelter: inert, opened only after the
	-- warning, and the ONLY thing that grants Escaped.
	local exit = plan.Exit
	local gate = part(model, "ExitGate", at(session, exit.X, DERIVED.DoorHeight / 2, exit.Z),
		Vector3.new(1.2, DERIVED.DoorHeight, DERIVED.DoorWidth + 2),
		COLORS.ZyntraCabinet, Enum.Material.DiamondPlate)
	gate:SetAttribute("Level4_ExitGate", true)
	local trigger = part(model, "EscapeTrigger",
		at(session, exit.X + 3.5, DERIVED.DoorHeight / 2, exit.Z),
		Vector3.new(5, DERIVED.DoorHeight, DERIVED.DoorWidth + 2), COLORS.Zyntra, Enum.Material.Neon)
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.Transparency = 1
	-- Armed by the Objective Controller when the exit opens. Off until then, so
	-- a body pressed against a closed transit door cannot even raise a touch.
	trigger.CanTouch = false
	trigger:SetAttribute("Level4_EscapeTrigger", true)
	local safeSpawn = part(model, "ExitSafeSpawn",
		at(session, exit.X + 14, 1, exit.Z), Vector3.new(18, 1, 18),
		COLORS.Concrete, Enum.Material.Concrete)
	safeSpawn:SetAttribute("Level4_ExitSafeSpawn", true)
	light(session, gate, "PointLight", COLORS.SignalSafe, 1.2, 22)

	return {
		Model = model, Cabinet = cabinet, Status = status, Controls = controls,
		Gate = gate, Trigger = trigger, SafeSpawn = safeSpawn,
		ExitPosition = worldPoint(session, exit.X, 3, exit.Z),
	}
end

-- Repeated facade rows and hills. This is the whole boundary treatment: the
-- edge has to look like more neighbourhood, and the invisible blockers are what
-- actually hold the player in.
local function buildBoundary(session: any, parent: Instance)
	local boundary = session.Plan.Boundary
	local model = Instance.new("Model")
	model.Name = "Boundary"
	model.Parent = parent
	placeholder(model)

	for _, row in ipairs(boundary.FacadeRows) do
		local alongZ = row.Axis == "Z"
		local count = math.floor(row.Width / (LOTS.HouseWidth + 12))
		for index = 0, count do
			local offset = (index - count / 2) * (LOTS.HouseWidth + 12)
			local x = alongZ and row.X or row.X + offset
			local z = alongZ and row.Z + offset or row.Z
			local body = ({COLORS.FadedCream, COLORS.DustyYellow, COLORS.BlueGrey})[(index % 3) + 1]
			decorative(part(model, "BoundaryFacade",
				at(session, x, LOTS.StoreyHeight / 2, z),
				Vector3.new(alongZ and LOTS.HouseDepth or LOTS.HouseWidth, LOTS.StoreyHeight,
					alongZ and LOTS.HouseWidth or LOTS.HouseDepth),
				body, Enum.Material.Concrete))
			decorative(part(model, "BoundaryRoof",
				at(session, x, LOTS.StoreyHeight + LOTS.RoofHeight / 2, z),
				Vector3.new(alongZ and LOTS.HouseDepth or LOTS.HouseWidth, LOTS.RoofHeight,
					alongZ and LOTS.HouseWidth or LOTS.HouseDepth),
				COLORS.DarkRoof, Enum.Material.Slate))
		end
	end

	for _, hill in ipairs(boundary.Hills) do
		decorative(part(model, "BoundaryHill", at(session, hill.X, hill.H / 2 - 12, hill.Z),
			Vector3.new(hill.W, hill.H, hill.D), COLORS.Hill, Enum.Material.Grass))
	end

	-- Invisible blockers on the play bounds. They are what makes the boundary a
	-- boundary; the facades and hills only make it look like one.
	local bounds = boundary.Bounds
	local centreX, centreZ = (bounds.MinX + bounds.MaxX) / 2, (bounds.MinZ + bounds.MaxZ) / 2
	local spanX, spanZ = bounds.MaxX - bounds.MinX, bounds.MaxZ - bounds.MinZ
	local wallHeight = 120
	local edges = {
		{x = bounds.MinX, z = centreZ, sx = 4, sz = spanZ},
		{x = bounds.MaxX, z = centreZ, sx = 4, sz = spanZ},
		{x = centreX, z = bounds.MinZ, sx = spanX, sz = 4},
		{x = centreX, z = bounds.MaxZ, sx = spanX, sz = 4},
	}
	for _, edge in ipairs(edges) do
		local blocker = part(model, "BoundaryBlocker", at(session, edge.x, wallHeight / 2, edge.z),
			Vector3.new(edge.sx, wallHeight, edge.sz), COLORS.Hill, Enum.Material.SmoothPlastic)
		blocker.Transparency = 1
		-- CanQuery stays TRUE: the Neighbour's own sweeps must see the edge of
		-- the world, or it will try to path through it.
		blocker.CanTouch = false
		blocker:SetAttribute("Level4_Blocker", true)
	end
end

-- Patrol nodes: the street junctions, plus every mailbox and porch. That is
-- exactly the brief's "streets, mailboxes and porches", as data.
local function buildPatrolNodes(session: any, parent: Instance, lotRecords: {any}): {BasePart}
	local folder = Instance.new("Folder")
	folder.Name = "PatrolNodes"
	folder.Parent = parent
	local nodes = {}

	local function node(name: string, position: Vector3, kind: string)
		local marker = part(folder, name, CFrame.new(position), Vector3.new(1, 1, 1),
			COLORS.Zyntra, Enum.Material.Neon)
		decorative(marker)
		marker.Transparency = 1
		marker:SetAttribute("Level4_PatrolKind", kind)
		table.insert(nodes, marker)
	end

	for _, junction in ipairs(session.Plan.Junctions) do
		if junction.Id ~= "Arrival" then
			node("PatrolJunction_" .. junction.Id, worldPoint(session, junction.X, 3, junction.Z), "Street")
		end
	end
	for _, record in ipairs(lotRecords) do
		node("PatrolMailbox_" .. record.Lot.Id, record.Mailbox.Position + Vector3.new(0, 1, 0), "Mailbox")
		node("PatrolPorch_" .. record.Lot.Id,
			record.PorchSignal.Position - Vector3.new(0, DERIVED.DoorHeight - 4, 0), "Porch")
	end
	return nodes
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

function WorldBuilder.Build(plan: any, generation: number): any
	local session = newSession(plan, generation)

	local world = Instance.new("Model")
	world.Name = Configuration.WorldName
	world:SetAttribute("Level4_Generation", generation)
	world:SetAttribute("Level4_PlanHash", plan.PlanHash)
	world:SetAttribute("Level4_Variant", plan.Variant)
	world:SetAttribute("Level4_VariantName", plan.VariantName)

	-- Parented FIRST, deliberately, and the arrival is built immediately after.
	-- Under StreamingEnabled a world staged off Workspace replicates nothing
	-- until the final reparent, which is the worst possible moment for it: the
	-- party is placed right after the build returns. Building in place lets the
	-- arrival region stream while the rest of the neighbourhood is still going
	-- up, and the adapter tears the whole model down on any failure.
	world.Parent = workspace

	buildGround(session, world)
	local elevator, elevatorSpawn, mazeStart = buildArrival(session, world)
	for _, edge in ipairs(plan.Streets) do
		buildStreet(session, world, edge)
	end

	local lotRecords, lotById = {}, {}
	local taskByLot = {}
	for _, task in ipairs(plan.Tasks) do taskByLot[task.LotId] = task end

	for _, lot in ipairs(plan.Lots) do
		local model, doorFrame = buildHouseShell(session, world, lot)
		if lot.Interior > 0 then buildInterior(session, model, lot) end
		local mailbox, porch = buildYard(session, model, lot)
		buildAnomaly(session, model, lot, mailbox)

		local record = {
			Lot = lot, Model = model, DoorFrame = doorFrame, Mailbox = mailbox,
			PorchSignal = porch, Enterable = lot.Interior > 0,
			InteriorVolume = model:FindFirstChild("InteriorVolume"),
		}
		if record.Enterable then
			record.PorchLight = light(session, porch, "PointLight", COLORS.SignalSafe, 1.1, 18)
		end
		local task = taskByLot[lot.Id]
		if task then buildSignal(session, record, task) end
		model:SetAttribute("Level4_LotId", lot.Id)
		model:SetAttribute("Level4_Zone", lot.Zone)
		model:SetAttribute("Level4_HouseState", "SAFE")
		table.insert(lotRecords, record)
		lotById[lot.Id] = record
		yieldIfNeeded(session)
	end

	buildGreen(session, world)
	local tower = buildTower(session, world)
	local finale = buildFinale(session, world)
	buildBoundary(session, world)
	local patrolNodes = buildPatrolNodes(session, world, lotRecords)

	-- The Neighbour's runtime lives in its own folder so the controller can
	-- sweep exactly what it made, and rays can exclude exactly that.
	local runtime = Instance.new("Folder")
	runtime.Name = "NeighbourRuntime"
	runtime.Parent = world

	local signals = {}
	for _, record in ipairs(lotRecords) do
		if record.Signal then signals[record.Signal.Index] = record.Signal end
	end

	world:SetAttribute("Level4_DynamicLightCount", session.LightCount)

	return {
		World = world,
		Plan = plan,
		Generation = generation,
		Elevator = elevator,
		ElevatorSpawn = elevatorSpawn,
		MazeStart = mazeStart,
		Lots = lotRecords,
		LotById = lotById,
		Signals = signals,
		Tower = tower,
		Finale = finale,
		EscapeTrigger = finale.Trigger,
		ExitSafeSpawn = finale.SafeSpawn,
		ExitPosition = finale.ExitPosition,
		PatrolNodes = patrolNodes,
		NeighbourRuntime = runtime,
		NeighbourSpawn = worldPoint(session, plan.JunctionById.NW.X, 3, plan.JunctionById.NW.Z),
		DynamicLightCount = session.LightCount,
	}
end

return WorldBuilder
