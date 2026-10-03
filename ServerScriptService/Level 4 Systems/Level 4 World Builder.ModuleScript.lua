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

-- FACADE_POLISH_20260922. A facade window UNIT: an off-white frame standing a
-- little proud of the outer wall face, a frosted pane in front of it and a sill
-- under it. Every house faces along z, so the unit is sized in world axes and
-- never rotated -- the old 0.4-wide part turned by ninety degrees sat 0.1 studs
-- INSIDE the wall, and Codex measured all four panes buried in the render.
-- `outward` is the lot's FacingZ; `centre` is the point ON the outer wall face.
-- Returns the pane (the socket the anomalies key on) and the frame.
local function buildWindow(parent: Instance, name: string, centre: Vector3, outward: number,
	width: number?, height: number?): (BasePart, BasePart)
	local w = width or LOTS.WindowWidth
	local h = height or LOTS.WindowHeight
	local lip = LOTS.WindowFrame
	local proud = LOTS.WindowProud
	local frame = decorative(part(parent, name .. "Frame",
		CFrame.new(centre + Vector3.new(0, 0, outward * proud / 2)),
		Vector3.new(w + lip * 2, h + lip * 2, proud), COLORS.Trim, Enum.Material.SmoothPlastic))
	local pane = decorative(part(parent, name,
		CFrame.new(centre + Vector3.new(0, 0, outward * (proud + 0.1))),
		Vector3.new(w, h, 0.2), COLORS.Pane, Enum.Material.Glass))
	pane.Transparency = 0.25
	pane.Reflectance = 0.12
	decorative(part(parent, name .. "Sill",
		CFrame.new(centre + Vector3.new(0, -(h / 2 + lip + 0.15), outward * (proud / 2 + 0.25))),
		Vector3.new(w + lip * 2 + 0.6, 0.3, proud + 0.5), COLORS.Trim, Enum.Material.SmoothPlastic))
	return pane, frame
end

-- FACADE_POLISH_20260922. Where the four normal windows sit on a facade, as
-- points on the OUTER wall face; buildAnomaly reuses slot 1 for the curtain.
local function facadeWindowCentres(session: any, lot: any): {Vector3}
	local width, depth, height = LOTS.HouseWidth, LOTS.HouseDepth, LOTS.StoreyHeight
	local frontZ = lot.Z + lot.FacingZ * depth / 2
	local sidePanel = (width - DERIVED.DoorWidth) / 2
	local centres = {}
	for index = 1, 4 do
		local column = index <= 2 and -1 or 1
		local inset = (index % 2 == 1) and 0.3 or 0.7
		centres[index] = worldPoint(session,
			lot.X + column * (DERIVED.DoorWidth / 2 + sidePanel * inset), height * 0.58, frontZ)
	end
	return centres
end

-- The bare wall between the door edge and the first window unit.
local function facadeBandWidth(): number
	local sidePanel = (LOTS.HouseWidth - DERIVED.DoorWidth) / 2
	return sidePanel * 0.3 - LOTS.WindowWidth / 2
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

	-- Dark gable roof: two wedges meeting at a ridge that runs along x over the
	-- MIDDLE of the house. A WedgePart is full height at its own +z (Back) face
	-- and zero at -z (Front), so the half on the +z side is the one turned 180
	-- degrees, putting both tall edges on the ridge. (The first build had this
	-- backwards -- a valley down the middle -- and Codex measured it: the roof
	-- was 12.6 studs over the floor at the centre and 18.4 near the eaves.)
	-- Each half also overhangs its eave a little; the footprint itself is
	-- unchanged. FACADE_POLISH_20260922.
	local roofHeight = LOTS.RoofHeight
	local overhang = LOTS.EavesOverhang
	for _, side in ipairs({-1, 1}) do
		local turn = side > 0 and CFrame.Angles(0, math.pi, 0) or CFrame.identity
		local halfDepth = depth / 2 + overhang
		wedge(model, "HouseRoof",
			at(session, lot.X, height + roofHeight / 2, lot.Z + side * halfDepth / 2) * turn,
			Vector3.new(width + overhang * 2, roofHeight, halfDepth), COLORS.DarkRoof, Enum.Material.Slate)
		-- Fascia board along the eave, under the roof edge.
		decorative(part(model, "HouseFascia",
			at(session, lot.X, height - LOTS.FasciaDepth / 2 + 0.05, lot.Z + side * (depth / 2 + overhang - 0.15)),
			Vector3.new(width + overhang * 2, LOTS.FasciaDepth, 0.3), COLORS.Fascia, Enum.Material.SmoothPlastic))
	end
	-- Gable-end boards, so the roof edge reads as a built edge from the side.
	for _, side in ipairs({-1, 1}) do
		decorative(part(model, "HouseFascia",
			at(session, lot.X + side * (width / 2 + overhang - 0.15), height - LOTS.FasciaDepth / 2 + 0.05, lot.Z),
			Vector3.new(0.3, LOTS.FasciaDepth, depth + overhang * 2), COLORS.Fascia, Enum.Material.SmoothPlastic))
	end

	-- Four window units on the facade, two each side of the door, standing on
	-- the OUTER face of the front wall.
	for _, centre in ipairs(facadeWindowCentres(session, lot)) do
		buildWindow(model, "HouseWindow", centre, lot.FacingZ)
	end

	-- Door trim: a frame around the opening, proud of the wall like the windows,
	-- so the entrance reads as a doorway and not a hole. It stands OUTSIDE the
	-- opening on every side and never narrows the 6 x 10.5 contract.
	local trimLip = LOTS.WindowFrame
	local outerFront = frontZ + lot.FacingZ * (LOTS.WindowProud / 2)
	for _, side in ipairs({-1, 1}) do
		decorative(part(model, "DoorTrim",
			CFrame.new(worldPoint(session, lot.X + side * (doorWidth / 2 + trimLip / 2), doorHeight / 2, outerFront)),
			Vector3.new(trimLip, doorHeight, LOTS.WindowProud), COLORS.Trim, Enum.Material.SmoothPlastic))
	end
	decorative(part(model, "DoorTrim",
		CFrame.new(worldPoint(session, lot.X, doorHeight + trimLip / 2, outerFront)),
		Vector3.new(doorWidth + trimLip * 2, trimLip, LOTS.WindowProud), COLORS.Trim, Enum.Material.SmoothPlastic))

	-- House identification in the bare wall band on the street-viewer's RIGHT
	-- of the door (the porch signal takes the left band): the lot id, on the
	-- outward face. The WrongNumber anomaly REPLACES this text (see
	-- buildAnomaly); the lot id stays the technical identity either way.
	local bandX = doorWidth / 2 + (facadeBandWidth() / 2)
	local plate = decorative(part(model, "HouseNumber",
		CFrame.new(worldPoint(session, lot.X + lot.FacingZ * bandX, LOTS.FittingHeight, frontZ + lot.FacingZ * 0.25)),
		Vector3.new(1.6, 1.6, 0.5), COLORS.Graphite, Enum.Material.Metal))
	plate:SetAttribute("Level4_HouseNumber", true)
	face(plate, string.upper(lot.Id), lot.FacingZ < 0 and Enum.NormalId.Front or Enum.NormalId.Back,
		COLORS.Trim, 40)

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
			Vector3.new(panel, LOTS.FenceHeight, 0.5), COLORS.Trim, Enum.Material.WoodPlanks))
	end
	-- Path from the gate to the door.
	decorative(part(model, "Path",
		at(session, lot.X, 0.15, lot.Z + lot.FacingZ * (depth / 2 + LOTS.FrontYardDepth / 2)),
		Vector3.new(DERIVED.DoorWidth, 0.3, LOTS.FrontYardDepth), COLORS.Concrete, Enum.Material.Concrete))

	-- FACADE_POLISH_20260922. A recognisable mailbox: timber post, galvanised
	-- box, a darker door plate on the STREET end and a red flag on one side, so
	-- the ReversedMailbox anomaly (the whole assembly turned 180 degrees to face
	-- the house) reads from the pavement. The `Mailbox` part is still the
	-- contract object; post, door and flag hang off it in a Model.
	local mailboxModel = Instance.new("Model")
	mailboxModel.Name = "MailboxAssembly"
	mailboxModel.Parent = model
	placeholder(mailboxModel)
	local boxCentre = worldPoint(session, lot.X + width * 0.34, LOTS.MailboxHeight - 0.7, frontZ - lot.FacingZ * 1.6)
	local mailbox = part(mailboxModel, "Mailbox", CFrame.new(boxCentre),
		Vector3.new(1.4, 1.3, 2.2), COLORS.MailboxMetal, Enum.Material.Metal)
	decorative(mailbox)
	mailboxModel.PrimaryPart = mailbox
	decorative(part(mailboxModel, "MailboxPost",
		CFrame.new(boxCentre + Vector3.new(0, -(LOTS.MailboxHeight - 0.7) / 2 - 0.65, 0)),
		Vector3.new(0.5, LOTS.MailboxHeight - 1.3, 0.5), COLORS.Timber, Enum.Material.Wood))
	-- The door: on the street-facing end, i.e. towards +FacingZ.
	decorative(part(mailboxModel, "MailboxDoor",
		CFrame.new(boxCentre + Vector3.new(0, -0.05, lot.FacingZ * 1.15)),
		Vector3.new(1.2, 1.1, 0.12), COLORS.Graphite, Enum.Material.Metal))
	decorative(part(mailboxModel, "MailboxFlag",
		CFrame.new(boxCentre + Vector3.new(0.78, 0.55, lot.FacingZ * 0.5)),
		Vector3.new(0.12, 0.7, 0.9), COLORS.MailboxFlag, Enum.Material.SmoothPlastic))
	mailbox:SetAttribute("Level4_Mailbox", true)
	-- Mailboxes normally face the street.
	mailbox:SetAttribute("Level4_MailboxFacesStreet", true)

	-- The porch signal: the readable house-state light. A graphite housing with a
	-- small lit aperture, beside the door at head height. The aperture colour is
	-- the language (SAFE green / WARNED amber / DANGEROUS red-then-dark); the
	-- housing keeps it from lighting the whole lawn. One part carries the state
	-- and the one counted light (FACADE_POLISH_20260922).
	local bandX = DERIVED.DoorWidth / 2 + facadeBandWidth() / 2
	local porchCentre = worldPoint(session, lot.X - lot.FacingZ * bandX, LOTS.FittingHeight,
		lot.Z + lot.FacingZ * (depth / 2 + 0.45))
	decorative(part(model, "PorchSignalHousing", CFrame.new(porchCentre),
		Vector3.new(1.4, 1.4, 0.9), COLORS.Graphite, Enum.Material.Metal))
	local porch = part(model, "PorchSignal",
		CFrame.new(porchCentre + Vector3.new(0, 0, lot.FacingZ * 0.4)),
		Vector3.new(0.8, 0.8, 0.25), COLORS.SignalSafe, Enum.Material.Neon)
	decorative(porch)
	porch:SetAttribute("Level4_PorchSignal", true)
	return mailbox, porch
end

local function buildAnomaly(session: any, model: Model, lot: any, mailbox: BasePart)
	if not lot.Anomaly then return end
	local width, depth, height = LOTS.HouseWidth, LOTS.HouseDepth, LOTS.StoreyHeight
	local frontZ = lot.Z + lot.FacingZ * (depth / 2 + 0.6)
	local socket: BasePart

	-- FACADE_POLISH_20260922: every anomaly is built in the same world axes as
	-- the normal facade fittings, so it is comparable with them from the
	-- pavement instead of being a 0.3-stud sliver seen edge-on.
	local wallFace = lot.Z + lot.FacingZ * depth / 2
	if lot.Anomaly == "ExtraWindow" then
		-- A fifth, shorter window over the door, under the eaves: no other house
		-- has one there, and it is compared against the four normal units.
		socket = buildWindow(model, "AnomalyExtraWindow",
			worldPoint(session, lot.X, DERIVED.DoorHeight + (height - DERIVED.DoorHeight) / 2 + 0.15, wallFace),
			lot.FacingZ, LOTS.WindowWidth, 1.6)
	elseif lot.Anomaly == "WrongNumber" then
		-- The house's OWN plate shows a number that cannot belong to this
		-- street: the zone letter with 0, which no lot ever has.
		local plate = model:FindFirstChild("HouseNumber")
		if plate then
			local gui = plate:FindFirstChildOfClass("SurfaceGui")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			if label then label.Text = string.upper(string.sub(lot.Id, 1, 1)) .. "0" end
			plate:SetAttribute("Level4_WrongNumber", true)
		end
		socket = plate or mailbox
	elseif lot.Anomaly == "ReversedMailbox" then
		-- The whole mailbox assembly is turned to face the house: door and flag
		-- now point at the front wall instead of the street.
		local assembly = mailbox.Parent
		if assembly and assembly:IsA("Model") then
			assembly:PivotTo(mailbox.CFrame * CFrame.Angles(0, math.pi, 0))
		else
			mailbox.CFrame = mailbox.CFrame * CFrame.Angles(0, math.pi, 0)
		end
		mailbox:SetAttribute("Level4_MailboxFacesStreet", false)
		socket = mailbox
	else -- DrawnCurtains
		-- One of the four normal windows is drawn on one side: a curtain panel
		-- immediately in front of the pane of window slot 1, covering ONE half.
		local centre = facadeWindowCentres(session, lot)[1]
		local w, h = LOTS.WindowWidth, LOTS.WindowHeight
		socket = decorative(part(model, "AnomalyDrawnCurtains",
			CFrame.new(centre + Vector3.new(-w / 4, 0, lot.FacingZ * (LOTS.WindowProud + 0.32))),
			Vector3.new(w / 2 - 0.2, h - 0.3, 0.14), COLORS.Curtain, Enum.Material.Fabric))
	end

	-- The reversed-mailbox anomaly IS the mailbox, and the mailbox's own name is
	-- part of the art contract, so only a purpose-built socket gets renamed.
	if socket ~= mailbox and socket.Name ~= "HouseNumber" then socket.Name = "AnomalySocket" end
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
	-- EXIT_POINTER_20260922: the trigger volume starts at the gate's inner face
	-- and runs 6 studs past it, and ExitPosition (what the reader/pointer aims
	-- at) is the volume's own centre -- a point that completes the escape when
	-- reached, not a spot 3.5 studs short of it.
	local trigger = part(model, "EscapeTrigger",
		at(session, exit.X + 0.6 + 3, DERIVED.DoorHeight / 2, exit.Z),
		Vector3.new(6, DERIVED.DoorHeight, DERIVED.DoorWidth + 2), COLORS.Zyntra, Enum.Material.Neon)
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
		ExitPosition = trigger.Position,
	}
end

-- ---------------------------------------------------------------------------
-- Megastructure: the arrival slice of the indoor-suburb direction
-- (ARRIVAL_SLICE_20260923). Two tall facade groups, one bridge and the
-- artificial ceiling, all from Configuration.Megastructure. A block's core is
-- one solid part -- it collides and it blocks rays, like any wall -- and
-- everything on its faces is decorative, so no sightline or Neighbour sweep
-- ever stops on a balcony rail.
-- ---------------------------------------------------------------------------

local MEGA = Configuration.Megastructure

local OUTWARD = {
	["+X"] = Vector3.xAxis, ["-X"] = -Vector3.xAxis,
	["+Z"] = Vector3.zAxis, ["-Z"] = -Vector3.zAxis,
}

local WINDOW_DARK = Color3.fromRGB(64, 70, 72)
local WINDOW_LIT = Color3.fromRGB(255, 214, 142)
local PANEL_LIT = Color3.fromRGB(255, 246, 218)

-- True when a plan-space rectangle overlaps any megastructure block. The
-- boundary uses it to leave out the low facades a tall block now stands in.
local function insideMegastructure(minX: number, maxX: number, minZ: number, maxZ: number): boolean
	for _, group in ipairs(MEGA.Groups) do
		for _, block in ipairs(group.Blocks) do
			if minX < block.MaxX and maxX > block.MinX and minZ < block.MaxZ and maxZ > block.MinZ then
				return true
			end
		end
	end
	return false
end

local function overlapsAny(boxes: {any}, low: Vector3, high: Vector3): boolean
	for _, box in ipairs(boxes) do
		if low.X < box.Max.X and high.X > box.Min.X and low.Y < box.Max.Y and high.Y > box.Min.Y
			and low.Z < box.Max.Z and high.Z > box.Min.Z then
			return true
		end
	end
	return false
end

-- One face of a block, dressed with the residential module repeated along it
-- and up it. Near storeys keep depth (balcony slab, rail, door and windows; a
-- bay with a gable), mid storeys keep the silhouette with fewer parts, and
-- every storey above is one window band per module. Street level is flush
-- openings only, so nothing stands out for a player to walk into. `clear`
-- lists plan-space boxes (the bridge) that no module may grow into.
local function buildFacadeFace(session: any, parent: Instance, block: any, spec: any,
	body: Color3, clear: {any})
	local outward = OUTWARD[spec.Outward]
	assert(outward, "Level 4 megastructure face has no valid Outward: " .. tostring(spec.Outward))
	local along = outward:Cross(Vector3.yAxis)
	local alongX = along.X ~= 0
	local from = spec.From or (alongX and block.MinX or block.MinZ)
	local to = spec.To or (alongX and block.MaxX or block.MaxZ)
	local mid = (from + to) / 2
	local centre = Vector3.new(
		outward.X > 0 and block.MaxX or outward.X < 0 and block.MinX or mid, 0,
		outward.Z > 0 and block.MaxZ or outward.Z < 0 and block.MinZ or mid)
	local faceWidth = to - from
	local moduleWidth = MEGA.ModuleWidth
	local storey = LOTS.StoreyHeight
	local storeys = math.floor(MEGA.CeilingHeight / storey)
	local count = math.floor(faceWidth / moduleWidth)
	local first = -faceWidth / 2 + (faceWidth - count * moduleWidth) / 2
	local frame = CFrame.fromMatrix(Vector3.zero, along, Vector3.yAxis)
	local skip = spec.SkipStoreys or 0

	-- A box `u` along the face, centred `y` up, standing `proud` off it.
	local function box(name: string, u: number, y: number, w: number, h: number, d: number,
		proud: number, color: Color3, material: Enum.Material?): BasePart
		local position = session.Origin + centre + along * u + outward * (proud + d / 2) + Vector3.new(0, y, 0)
		return decorative(part(parent, name, frame + position, Vector3.new(w, h, d), color, material))
	end
	-- Half a gable: tall edge at `u`, slope falling away in `dir`. A WedgePart
	-- is tall at its own +Z; with its X on the outward normal that +Z runs
	-- along the face, so the far half is turned to face inward instead.
	local function gableHalf(u: number, y: number, halfWidth: number, h: number, d: number, dir: number)
		local position = session.Origin + centre + along * (u + dir * halfWidth / 2)
			+ outward * (d / 2) + Vector3.new(0, y, 0)
		decorative(wedge(parent, "Level4FacadeGable",
			CFrame.fromMatrix(position, dir > 0 and -outward or outward, Vector3.yAxis),
			Vector3.new(d, h, halfWidth), COLORS.Trim, Enum.Material.SmoothPlastic))
	end
	local function window(u: number, y: number, w: number, h: number, proud: number, seed: number)
		local lit = seed % MEGA.LitEvery == 0
		box(lit and "Level4FacadeWindowLit" or "Level4FacadeWindow", u, y, w, h, 0.3, proud,
			lit and WINDOW_LIT or WINDOW_DARK, lit and Enum.Material.Neon or Enum.Material.SmoothPlastic)
	end

	for column = 0, count - 1 do
		local u = first + (column + 0.5) * moduleWidth
		local bay = column % MEGA.BayEvery == 1
		for level = skip, storeys - 1 do
			local y0 = level * storey
			local a = centre + along * (u - moduleWidth / 2) + Vector3.new(0, y0, 0)
			local b = centre + along * (u + moduleWidth / 2) + outward * 5 + Vector3.new(0, y0 + storey, 0)
			local n = column * 5 + level * 3
			if overlapsAny(clear, a:Min(b), a:Max(b)) then
				continue
			elseif level == 0 then
				box("Level4FacadeDoor", u - 6, 4.4, 3.8, 8, 0.4, 0, WINDOW_DARK)
				window(u + 1, 6, 3.6, 4.4, 0, n)
				window(u + 7, 6, 3.6, 4.4, 0, n + 1)
			elseif level >= MEGA.MidStoreys then
				window(u, y0 + 6.5, 18, 5, 0, n)
			elseif bay then
				box("Level4FacadeBay", u, y0 + 5.5, 10, 9, 3, 0, body)
				window(u, y0 + 6, 7, 4.4, 3, n)
				gableHalf(u, y0 + 11.75, 5.5, 3.5, 3.4, -1)
				gableHalf(u, y0 + 11.75, 5.5, 3.5, 3.4, 1)
				if level < MEGA.NearStoreys then
					window(u - 8.5, y0 + 6, 3.2, 4.4, 0, n + 1)
					window(u + 8.5, y0 + 6, 3.2, 4.4, 0, n + 2)
				end
			else
				box("Level4FacadeBalcony", u, y0 + 0.4, moduleWidth - 2, 0.8, 4, 0, COLORS.Trim)
				box("Level4FacadeRail", u, y0 + 2.3, moduleWidth - 2, 3, 0.3, 3.7, COLORS.Trim).Transparency = 0.3
				if level < MEGA.NearStoreys then
					box("Level4FacadeDoor", u - 6, y0 + 4.8, 3.6, 8, 0.4, 0, WINDOW_DARK)
					window(u + 1, y0 + 6, 3.6, 4.4, 0, n)
					window(u + 7, y0 + 6, 3.6, 4.4, 0, n + 1)
				else
					window(u + 1.5, y0 + 6, 14, 4.4, 0, n)
				end
			end
		end
	end
	-- The grid: one floor line per storey and a pilaster every bay column,
	-- one part each, from the first storey up.
	for level = math.max(skip, 1), storeys - 1 do
		box("Level4FacadeFloorLine", 0, level * storey, faceWidth, 0.8, 0.8, 0, COLORS.Trim)
	end
	local base = math.max(skip, 1) * storey
	for column = 0, count, MEGA.BayEvery do
		box("Level4FacadePilaster", first + column * moduleWidth, (base + MEGA.CeilingHeight) / 2,
			1.6, MEGA.CeilingHeight - base, 1.2, 0, COLORS.Trim)
	end
end

-- The bridge's own space, which no facade module may grow into.
local function bridgeClearance(): any
	local bridge = MEGA.Bridge
	local deckY = bridge.Storey * LOTS.StoreyHeight
	return {
		Min = Vector3.new(bridge.X - bridge.Width / 2 - 2, deckY - 20, bridge.MinZ - 6),
		Max = Vector3.new(bridge.X + bridge.Width / 2 + 2, deckY + 12, bridge.MaxZ + 6),
	}
end

local function buildMegastructure(session: any, parent: Instance)
	local clear = {bridgeClearance()}
	for _, group in ipairs(MEGA.Groups) do
		local model = Instance.new("Model")
		model.Name = "Level4FacadeGroup_" .. group.Name
		model:SetAttribute("Level4_FacadeGroup", group.Name)
		model.Parent = parent
		placeholder(model)
		for _, block in ipairs(group.Blocks) do
			local body = COLORS[block.ColorKey] or COLORS.FadedCream
			local core = solid(part(model, "Level4FacadeCore_" .. block.Name,
				at(session, (block.MinX + block.MaxX) / 2, MEGA.CeilingHeight / 2, (block.MinZ + block.MaxZ) / 2),
				Vector3.new(block.MaxX - block.MinX, MEGA.CeilingHeight, block.MaxZ - block.MinZ),
				body, Enum.Material.SmoothPlastic))
			core:SetAttribute("Level4_Megastructure", block.Name)
			for _, spec in ipairs(block.Faces) do
				buildFacadeFace(session, model, block, spec, body, clear)
				RunService.Heartbeat:Wait()
			end
		end
	end
end

-- The one bridge: a covered walkway across the canyon, braced back to both
-- walls, with a dark doorway where it enters each block. Out of reach and
-- decorative throughout.
local function buildBridge(session: any, parent: Instance)
	local bridge = MEGA.Bridge
	local model = Instance.new("Model")
	model.Name = "Level4Bridge"
	model.Parent = parent
	placeholder(model)

	local deckY = bridge.Storey * LOTS.StoreyHeight
	local length = bridge.MaxZ - bridge.MinZ
	local midZ = (bridge.MinZ + bridge.MaxZ) / 2
	local halfWidth = bridge.Width / 2
	local function piece(name: string, x: number, y: number, z: number, size: Vector3,
		color: Color3, material: Enum.Material?): BasePart
		return decorative(part(model, name, at(session, x, y, z), size, color, material))
	end

	piece("BridgeDeck", bridge.X, deckY - 0.6, midZ, Vector3.new(bridge.Width, 1.2, length), COLORS.Trim)
	piece("BridgeGirder", bridge.X, deckY - 2.7, midZ, Vector3.new(bridge.Width - 6, 3, length), COLORS.Fascia)
	piece("BridgeRoof", bridge.X, deckY + 9, midZ, Vector3.new(bridge.Width + 1, 0.8, length), COLORS.Trim)
	for _, side in ipairs({-1, 1}) do
		local x = bridge.X + side * (halfWidth - 0.2)
		piece("BridgeRail", x, deckY + 1.5, midZ, Vector3.new(0.3, 3, length), COLORS.Trim).Transparency = 0.3
		for _, offset in ipairs({-length / 4, 0, length / 4}) do
			piece("BridgePost", x, deckY + 4.5, midZ + offset, Vector3.new(0.6, 9, 0.6), COLORS.Trim)
		end
		-- The arch, as two struts from each wall up under the deck.
		for _, endZ in ipairs({bridge.MinZ, bridge.MaxZ}) do
			local braceX = bridge.X + side * (halfWidth - 3)
			local foot = worldPoint(session, braceX, deckY - 16, endZ)
			local head = worldPoint(session, braceX, deckY - 2, endZ + (endZ < midZ and 14 or -14))
			decorative(part(model, "BridgeBrace", CFrame.lookAt((foot + head) / 2, head),
				Vector3.new(1.4, 1.4, (head - foot).Magnitude), COLORS.Fascia, Enum.Material.SmoothPlastic))
		end
	end
	for _, offset in ipairs({-length / 4, length / 4}) do
		piece("BridgeLamp", bridge.X, deckY + 8.4, midZ + offset, Vector3.new(1.6, 0.4, 1.6),
			WINDOW_LIT, Enum.Material.Neon)
	end
	for _, endZ in ipairs({bridge.MinZ, bridge.MaxZ}) do
		piece("BridgeDoorway", bridge.X, deckY + 4.4, endZ + (endZ < midZ and 0.2 or -0.2),
			Vector3.new(8, 8.8, 0.4), WINDOW_DARK)
	end
end

-- The artificial ceiling: one slab as large as a part may be, over the whole
-- neighbourhood, rows of emissive panels under it, and a wall down each of the
-- slab's edges so the horizon is haze instead of sky. The panels are Neon
-- faces, not lights, so none of them spends the dynamic-light budget.
local function buildCeiling(session: any, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Level4Ceiling"
	model.Parent = parent
	placeholder(model)

	local bounds = session.Plan.Boundary.Bounds
	local top = MEGA.CeilingHeight
	local span = 2048
	local centreX, centreZ = (bounds.MinX + bounds.MaxX) / 2, (bounds.MinZ + bounds.MaxZ) / 2
	decorative(part(model, "CeilingSlab", at(session, centreX, top + MEGA.CeilingThickness / 2, centreZ),
		Vector3.new(span, MEGA.CeilingThickness, span), MEGA.CeilingColor, Enum.Material.SmoothPlastic))
	local height = top + 40
	for _, edge in ipairs({{span / 2, 0}, {-span / 2, 0}, {0, span / 2}, {0, -span / 2}}) do
		decorative(part(model, "CeilingFarWall", at(session, centreX + edge[1], top - height / 2, centreZ + edge[2]),
			Vector3.new(edge[1] ~= 0 and 4 or span, height, edge[2] ~= 0 and 4 or span),
			MEGA.FarWallColor, Enum.Material.SmoothPlastic))
	end
	local size = MEGA.PanelSize
	for _, z in ipairs(MEGA.PanelRowsZ) do
		for x = MEGA.PanelFromX, MEGA.PanelToX, MEGA.PanelPitchX do
			decorative(part(model, "CeilingPanel", at(session, x, top - size.Y / 2, z), size,
				PANEL_LIT, Enum.Material.Neon))
		end
	end
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
			local sizeX = alongZ and LOTS.HouseDepth or LOTS.HouseWidth
			local sizeZ = alongZ and LOTS.HouseWidth or LOTS.HouseDepth
			-- A tall megastructure block already stands here.
			if insideMegastructure(x - sizeX / 2, x + sizeX / 2, z - sizeZ / 2, z + sizeZ / 2) then continue end
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

	-- FACADE_POLISH_20260922: rolling ridges, not a flat green wall. Each
	-- boundary hill is three overlapping cylinders lying along the row, sunk
	-- into the ground, so the skyline is rounded and uneven from the street.
	-- Decorative: the blockers below are what hold the player.
	for hillIndex, hill in ipairs(boundary.Hills) do
		local alongX = hill.W >= hill.D
		local length = alongX and hill.W or hill.D
		local lumps = {{0, 1.0}, {-0.34, 0.72}, {0.36, 0.84}}
		for lumpIndex, lump in ipairs(lumps) do
			local diameter = hill.H * 2 * lump[2]
			local shift = lump[1] * length * 0.6
			local centre = alongX and Vector3.new(hill.X + shift, 0, hill.Z + (lumpIndex - 2) * 22)
				or Vector3.new(hill.X + (lumpIndex - 2) * 22, 0, hill.Z + shift)
			local ridge = decorative(part(model, "BoundaryHill",
				at(session, centre.X, -diameter * 0.32, centre.Z)
					* (alongX and CFrame.identity or CFrame.Angles(0, math.pi / 2, 0)),
				Vector3.new(length * (0.55 + 0.15 * lumpIndex), diameter, diameter), COLORS.Hill, Enum.Material.Grass))
			ridge.Shape = Enum.PartType.Cylinder
			ridge:SetAttribute("Level4_HillIndex", hillIndex)
		end
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
	buildMegastructure(session, world)
	buildBridge(session, world)
	buildCeiling(session, world)
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
