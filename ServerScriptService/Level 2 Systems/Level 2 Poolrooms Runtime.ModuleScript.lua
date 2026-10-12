-- Approved six-area Poolrooms presentation and native round zones.
-- The Round Adapter owns map adoption; this module never generates or clears Terrain.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local DeathAdvice = require(ReplicatedStorage:WaitForChild("DeathAdvice"))
-- SHADE_20261010: the shadow entity is its own module and may be absent or broken without costing the level anything.
local Shade
do
	local module = script.Parent:FindFirstChild("Level 2 Shade")
	local ok, result = pcall(function() return module and require(module) end)
	if ok and type(result) == "table" then Shade = result elseif module then warn("[Level 2] Shade did not load: " .. tostring(result)) end
end
local Runtime = {}
local active
local generation = 0
local SLIDE_NAME, SLIDE_FINISH = "Exit Slide", "Exit Slide Finish"
local SLIDE_RADIUS, SLIDE_AXIS = 8, 8.3
local SLIDE_LEAD, SLIDE_RUN, SLIDE_DROP, SLIDE_RUNOUT, SLIDE_FINISH_BEFORE = 8, 120, 32, 60, 26
local ZONE_STEP = 0.1

local function buildExitSlide(model, marker)
	local systems = ServerScriptService:FindFirstChild("Level 2 Systems")
	local module = systems and systems:FindFirstChild("Level 2 World Builder")
	local settings = systems and systems:FindFirstChild("Level 2 Configuration")
	assert(module and module:IsA("ModuleScript") and settings and settings:IsA("ModuleScript"),
		"Level 2 Systems are missing")
	local WorldBuilder = require(module)
	assert(WorldBuilder.MakeEntryTub and WorldBuilder.MakeTubeFromPoints, "World Builder does not export its tub")
	local color = require(settings).Colors.TileCool
	-- the deck: the map's floor collider under the marker
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {model:FindFirstChild("Collision") or model}
	local hit = workspace:Raycast(marker.Position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	local deckTop = if hit then hit.Position.Y else marker.Position.Y - 3
	local mouth = Vector3.new(marker.Position.X, deckTop + SLIDE_AXIS, marker.Position.Z)
	local start = mouth + Vector3.xAxis * SLIDE_LEAD
	local bottom = start + Vector3.new(SLIDE_RUN, -SLIDE_DROP, 0)
	local c1, c2 = start + Vector3.new(24, -2, 0), bottom - Vector3.xAxis * 34 -- level in, level out
	local points = {mouth, start}
	for i = 1, 72 do
		local t = i / 72
		local u = 1 - t
		table.insert(points, start * u ^ 3 + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + bottom * t ^ 3)
	end
	local tail = bottom + Vector3.xAxis * SLIDE_RUNOUT
	table.insert(points, bottom + Vector3.xAxis * (SLIDE_RUNOUT * .5))
	table.insert(points, tail)
	local slide = Instance.new("Model")
	slide.Name = SLIDE_NAME
	slide.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a rider never meets a segment that has not streamed
	WorldBuilder.MakeEntryTub(slide, mouth, start, SLIDE_RADIUS, deckTop, color, "Level 2 Exit Flume", true, false)
	WorldBuilder.MakeTubeFromPoints(slide, points, SLIDE_RADIUS, color, "Level 2 Exit Flume", false, .18, nil, nil, true)
	local function block(name, cframe, size)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CFrame = cframe
		part.Size = size
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Parent = slide
		return part
	end
	-- the runout ends in the dark: a black seal overlapping its last plane, like the live flume's End Stop
	local stop = block("Exit Slide End Stop", CFrame.new(tail + Vector3.xAxis),
		Vector3.new(4, SLIDE_RADIUS * 2 + 2, SLIDE_RADIUS * 2 + 2))
	stop.Color = Color3.new(0, 0, 0)
	stop.Material = Enum.Material.SmoothPlastic
	-- the finish, from 26 studs before the plunge's end to the stop, the bore's full height (only the server reads it)
	local x0, top = bottom.X - SLIDE_FINISH_BEFORE, bottom.Y
	for _, p in ipairs(points) do
		if p.X >= x0 then top = math.max(top, p.Y) end
	end
	local finish = block(SLIDE_FINISH, CFrame.new((x0 + tail.X + 3) * .5, (top + bottom.Y) * .5, mouth.Z),
		Vector3.new(tail.X + 3 - x0, top - bottom.Y + SLIDE_RADIUS * 2, SLIDE_RADIUS * 2))
	finish.Transparency = 1
	finish.CanCollide = false
	-- the exporter's fall barriers across the far wall's round hole would stop the ride: the bore fills that hole
	local collision = model:FindFirstChild("Collision")
	local guards = collision and collision:FindFirstChild("Guards")
	for _, g in ipairs(if guards then guards:GetDescendants() else {}) do
		local d = g:IsA("BasePart") and g.Name == "Barrier" and g.Position - mouth
		if d and d.X > 3 and d.X < 7 and math.abs(d.Y) < 8 and math.abs(d.Z) < 8 then g.CanCollide = false end
	end
	slide.Parent = model
end

-- F8 (owner 2026-10-07): the P2 culvert's stepped cascade is a sloped sheet of Roblox terrain water (the map
-- build writes it). Terrain water does not flow, so the running reads from foam sliding down the sheet, spray
-- at the crest and the toe, and the Level 2 water bed. Built-in particle texture, library sound: no new assets.
-- The cascade plane of passages_a.build_p2 in Studio studs (exporter ORIGIN 70000, 300, 0). Since 2026-10-08
-- the sheet lies 0.45 m over the nosings, the channel's water reaches one voxel under the walkway and behind
-- the east wall (so Roblox draws it on the plane), and the upper pool runs on to nosing 0 (Z 148), where it
-- pours: the foam starts there (Y 182.77) and ends at the toe (Y 167.59, Z 180.17); channel X 70004.14..70014.16.
local WATER_FX = "Water FX"
local CASCADE_CREST, CASCADE_TOE, CASCADE_WIDTH = Vector3.new(70009.15, 182.77, 148), Vector3.new(70009.15, 167.59, 180.17), 9.6
local function buildWaterFx(model)
	local fx = Instance.new("Folder")
	fx.Name = WATER_FX
	local down = (CASCADE_TOE - CASCADE_CREST).Unit
	local function anchor(name, cframe, size)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
		part.Transparency = 1
		part.CFrame, part.Size = cframe, size
		part.Parent = fx
		return part
	end
	local function emitter(part, props)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.LightEmission, e.LightInfluence = 0.15, 1
		e.Color = ColorSequence.new(Color3.fromRGB(225, 240, 238))
		for key, value in pairs(props) do e[key] = value end
		e.Parent = part
	end
	-- foam streaks: six thin emitters across the channel down the sheet, each pushing its foam downhill
	for i = 0, 5 do
		local p = CASCADE_CREST:Lerp(CASCADE_TOE, (i + .5) / 6) + Vector3.new(0, .25, 0)
		local part = anchor("Cascade Foam " .. i, CFrame.lookAt(p, p + down), Vector3.new(CASCADE_WIDTH, .1, .4))
		emitter(part, {EmissionDirection = Enum.NormalId.Front, Rate = 45, Lifetime = NumberRange.new(.5, .9),
			Speed = NumberRange.new(9, 13), Acceleration = down * 8, SpreadAngle = Vector2.new(4, 4),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, .15)}),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1)})})
	end
	-- spray where the upper pool falls onto the sheet, mist where the sheet meets the lower pool
	for _, spot in ipairs({{"Cascade Crest Spray", CASCADE_CREST + Vector3.new(0, .4, .5)},
		{"Cascade Toe Mist", CASCADE_TOE + Vector3.new(0, .3, 1.5)}}) do
		local part = anchor(spot[1], CFrame.new(spot[2]), Vector3.new(CASCADE_WIDTH, .2, 1.5))
		emitter(part, {EmissionDirection = Enum.NormalId.Top, Rate = 18, Lifetime = NumberRange.new(.8, 1.6),
			Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, -2, 0), SpreadAngle = Vector2.new(40, 40),
			Size = NumberSequence.new({NumberSequenceKeypoint.new(0, .8), NumberSequenceKeypoint.new(1, 2.4)}),
			Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, .55), NumberSequenceKeypoint.new(1, 1)})})
	end
	-- the water bed from the Level 2 Sound Library
	local library = ReplicatedStorage:FindFirstChild("Level 2 Sound Library")
	local slot = library and library:FindFirstChild("Level 2 Distant Water")
	local raw = if slot and slot:IsA("StringValue") then (tostring(slot.Value):gsub("%s", "")) else ""
	if raw:match("^%d+$") then raw = "rbxassetid://" .. raw end
	if raw:match("^rbxassetid://%d+$") then
		local part = anchor("Cascade Sound", CFrame.new(CASCADE_CREST:Lerp(CASCADE_TOE, .5)), Vector3.new(1, 1, 1))
		local sound = Instance.new("Sound")
		sound.Name = "Cascade Water"
		sound.SoundId, sound.Looped, sound.Volume = raw, true, .7
		sound.RollOffMode, sound.RollOffMinDistance, sound.RollOffMaxDistance = Enum.RollOffMode.InverseTapered, 8, 90
		sound.Parent = part
		sound.Playing = true
	else
		warn("[Level 2 Poolrooms] no 'Level 2 Distant Water' sound in the Level 2 Sound Library")
	end
	fx.Parent = model
end

-- The A2 skylight (owner 2026-10-08: "a skylight that comes down and hits the gold thing in the middle; only that
-- one place"). The sunlight itself is the developer client's A2 sun (Level2BlenderPreviewButton: the sun stands over
-- the oculus while the character is in the rotunda, so the oculus's own sun patch lands on the island). Roblox has
-- no volumetric light, so seven thin camera-facing additive Beams from the oculus throat down to just over the gold
-- disc (a ribbon through the disc would split it with a seam that turns with the camera) are the shaft, built-in
-- sparkles drift in it, and the exported oculus spot A2_BeamCone (parked 48 studs over the disc at
-- Range 60, where almost nothing arrives) moves to 26 studs over the disc, leaning toward the face the entry sees.
-- Built-in texture only: no new assets. The gold thing is the bronze disc on the island (PROP_bronze_disc_crank_frame).
local SKYLIGHT = "A2 Skylight"
local SHAFT_TOP, SHAFT_BOTTOM = Vector3.new(69742.6, 394, 0), Vector3.new(69742.6, 292.5, 0) -- throat / disc top
local DISC_CENTRE, DISC_FACE = Vector3.new(69742.6, 287.9, 0), Vector3.new(.7071, 0, .7071)
local SPOT_HEIGHT, SPOT_LEAN = 26, 9 -- studs over the disc centre / toward its entry-side face (0 = plumb)
local function buildSkylight(model)
	local reflector = model:FindFirstChild("A2 Reflector", true)
	local centre = (reflector and reflector:GetAttribute("DiscCentre")) or model:GetAttribute("A2ReflectorCentre")
	local hasReflectorCentre = typeof(centre) == "Vector3"
	if not hasReflectorCentre then centre = DISC_CENTRE end
	local shaftTop = if hasReflectorCentre then Vector3.new(centre.X, SHAFT_TOP.Y, centre.Z) else SHAFT_TOP
	local shaftBottom = if hasReflectorCentre then centre + Vector3.new(0, .2, 0) else SHAFT_BOTTOM
	local spotLean = if hasReflectorCentre then 0 else SPOT_LEAN
	local fx = Instance.new("Folder")
	fx.Name = SKYLIGHT
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Anchored, shaft.CanCollide, shaft.CanTouch, shaft.CanQuery, shaft.CastShadow = true, false, false, false, false
	shaft.Transparency = 1
	shaft.Size = Vector3.new(14, shaftTop.Y - shaftBottom.Y, 14)
	shaft.CFrame = CFrame.new((shaftTop + shaftBottom) / 2)
	shaft.Parent = fx
	local top, bottom = Instance.new("Attachment"), Instance.new("Attachment")
	top.Position, bottom.Position = Vector3.new(0, shaft.Size.Y / 2, 0), Vector3.new(0, -shaft.Size.Y / 2, 0)
	top.Parent, bottom.Parent = shaft, shaft
	-- {width in the oculus, width over the disc}: seven thin additive layers, so the column thickens toward its
	-- axis in small steps (a soft edge) instead of three hard bands. Tuned in Play 2026-10-09: 0.90 at the throat
	-- (added onto the sunlit oculus) to 0.86 over the disc (against the dark dome), warm against the cold grade.
	for i, layer in ipairs({{6, 7.5}, {8, 9.5}, {10, 11.8}, {12, 14}, {13.6, 16}, {15, 18}, {16.4, 20}}) do
		local beam = Instance.new("Beam")
		beam.Name = "Shaft " .. i
		beam.Attachment0, beam.Attachment1 = top, bottom
		beam.FaceCamera, beam.Segments = true, 1
		beam.Width0, beam.Width1 = layer[1], layer[2]
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 212, 140))
		beam.LightEmission, beam.LightInfluence = 1, 0
		beam.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, .9), NumberSequenceKeypoint.new(.5, .87),
			NumberSequenceKeypoint.new(.93, .86), NumberSequenceKeypoint.new(1, 1)})
		beam.Parent = shaft
	end
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Shape, dust.ShapeStyle = Enum.ParticleEmitterShape.Box, Enum.ParticleEmitterShapeStyle.Volume
	dust.Rate, dust.Lifetime = 10, NumberRange.new(8, 14)
	dust.Speed, dust.SpreadAngle = NumberRange.new(.2, .6), Vector2.new(180, 180)
	dust.Acceleration, dust.Drag = Vector3.new(0, -.04, 0), .3
	dust.Size = NumberSequence.new(.12)
	dust.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.3, .35),
		NumberSequenceKeypoint.new(.7, .35), NumberSequenceKeypoint.new(1, 1)})
	dust.LightEmission, dust.LightInfluence = 1, 0
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 230, 185))
	dust.Parent = shaft
	local lights = model:FindFirstChild("Lights")
	local holder = lights and lights:FindFirstChild("A2_BeamCone", true)
	local spot = holder and holder:FindFirstChildOfClass("SpotLight")
	if spot then
		holder.CFrame = CFrame.lookAt(centre + Vector3.new(0, SPOT_HEIGHT, 0) + DISC_FACE * spotLean, centre)
		-- the disc is polished brass (Metal): it shows a light only bright and narrow (Play, 2026-10-09)
		spot.Face, spot.Angle, spot.Brightness, spot.Range, spot.Shadows = Enum.NormalId.Front, 24, 8, 60, true
		holder:SetAttribute("BaseBrightness", spot.Brightness) -- what A/B and flicker tools scale from
		holder:SetAttribute("BaseRange", spot.Range)
	else
		warn("[Level 2 Poolrooms] A2_BeamCone not found: the skylight has no light on the disc")
	end
	fx.Parent = model
end

local function inside(part, position)
	local p = part.CFrame:PointToObjectSpace(position)
	local half = part.Size * .5
	if math.abs(p.X) > half.X then return false end
	if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
		return p.Y * p.Y + p.Z * p.Z <= math.min(half.Y, half.Z) ^ 2
	end
	return math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function ensureSafeSpawn(slide, finish)
	local existing = slide:FindFirstChild("Exit Slide Safe Spawn")
	if existing then
		assert(existing:IsA("BasePart"), "exit safe spawn has wrong class")
		return existing
	end
	-- Start INSIDE the bore, over its flat runout, so the ray reaches the floor rather than the roof.
	local at = Vector3.new(finish.Position.X + finish.Size.X * .5 - SLIDE_RUNOUT * .5,
		finish.Position.Y, finish.Position.Z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {slide}
	params.IgnoreWater, params.RespectCanCollide = true, true
	local hit = workspace:Raycast(at, Vector3.new(0, -SLIDE_RADIUS * 4, 0), params)
	assert(hit and hit.Normal.Y > .9, "exit runout has no safe horizontal floor")
	local marker = Instance.new("Part")
	marker.Name = "Exit Slide Safe Spawn"
	marker.Size = Vector3.new(1, 1, 1)
	local point = hit.Position + Vector3.new(0, 3.5, 0)
	marker.CFrame = CFrame.lookAt(point, point + Vector3.xAxis)
	marker.Transparency = 1
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
	marker.Parent = slide
	return marker
end

function Runtime.Prepare(world)
	assert(world and world:IsA("Model") and world:GetAttribute("Level2NewMap") == true,
		"approved Level 2 Poolrooms map is missing")
	local markers = world:FindFirstChild("Markers")
	local collision = world:FindFirstChild("Collision")
	local marker = markers and markers:FindFirstChild("EXIT_SLIDE")
	assert(markers and collision and marker and marker:IsA("BasePart"), "Poolrooms markers/collision are missing")
	local reflector = world:FindFirstChild("A2 Reflector", true)
	local reflection = world:FindFirstChild("A2 Lion Reflection")
	assert(reflector and reflection and reflection:FindFirstChild("Reflected Sunlight", true),
		"approved A2 reflector and lion illumination must be retained")
	assert(typeof(reflector:GetAttribute("DiscCentre")) == "Vector3"
		and typeof(reflector:GetAttribute("DiscNormal")) == "Vector3", "measured reflector attributes are missing")
	if world:GetAttribute("BoundsSize") == nil then
		local box, size = world:GetBoundingBox()
		world:SetAttribute("BoundsCenter", box.Position)
		world:SetAttribute("BoundsSize", size + Vector3.new(16, 40, 16))
	end
	if not world:FindFirstChild(SLIDE_NAME) then buildExitSlide(world, marker) end
	local slide = world:FindFirstChild(SLIDE_NAME)
	local finish = slide and slide:FindFirstChild(SLIDE_FINISH)
	assert(finish and finish:IsA("BasePart"), "Poolrooms exit finish is missing")
	ensureSafeSpawn(slide, finish)
	if not world:FindFirstChild(WATER_FX) then buildWaterFx(world) end
	if not world:FindFirstChild(SKYLIGHT) then buildSkylight(world) end
	return world
end

local function validWorld(handle)
	local world = handle.World
	return active == handle and handle.Stopped ~= true
		and world.Parent == workspace and world.Name == "Level 2 Generated World"
		and workspace:FindFirstChild("Level 2 Generated World") == world
		and world:GetAttribute("Level2NewMap") == true
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("WorldGenerated") == true
end

local function validTransition(handle, player, record)
	return validWorld(handle) and handle.Finishers[player] == record and player.Parent == Players
		and player:GetAttribute("InRound") == true and player:GetAttribute("Escaped") == true
		and player:GetAttribute("Level2_ExitTransition") == true
		and player:GetAttribute("Level2PoolroomsExitGeneration") == handle.Generation
		and (workspace:GetAttribute("RoundActive") == true
			or workspace:GetAttribute("PostWinIntermissionActive") == true)
end

local function recoverFinisher(handle, player, record, character)
	local token = {}
	record.RecoveryToken = token
	task.spawn(function()
		task.wait(.35)
		local deadline = os.clock() + 10
		local humanoid, root
		while validTransition(handle, player, record) and record.RecoveryToken == token
			and player.Character == character and os.clock() < deadline do
			humanoid = character:FindFirstChildOfClass("Humanoid")
			root = humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart")
			if root then break end
			task.wait(.05)
		end
		if not root or not validTransition(handle, player, record) or record.RecoveryToken ~= token
			or player.Character ~= character or not character:IsDescendantOf(workspace) then return end
		local safe = handle.SafeSpawn
		if not safe:IsDescendantOf(handle.World) then return end
		root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
		character:PivotTo(safe.CFrame * root.CFrame:ToObjectSpace(character:GetPivot()))
		root.Anchored = false
		record.RecoveryToken = nil
	end)
end

local function completeFor(handle, player, character)
	if handle.Finishers[player] then return end
	local record = {Character = character}
	handle.Finishers[player] = record
	record.Connection = player.CharacterAdded:Connect(function(body)
		if validTransition(handle, player, record) then recoverFinisher(handle, player, record, body) end
	end)
	player:SetAttribute("Level2PoolroomsExitGeneration", handle.Generation)
	player:SetAttribute("Level2_ExitTransition", true)
	player:SetAttribute("Escaped", true)
end

local function zoneStep(handle)
	if not validWorld(handle) or workspace:GetAttribute("RoundActive") ~= true then return end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then continue end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.Health > 0 and humanoid.RootPart
		if not root or not character:IsDescendantOf(workspace) then continue end
		for _, hazard in ipairs(handle.Hazards) do
			if hazard:IsDescendantOf(handle.World) and inside(hazard, root.Position) then
				DeathAdvice.Mark(player, "L2Hole")
				humanoid.Health = 0
				break
			end
		end
		local finish = handle.Finish
		if humanoid.Health > 0 and finish:IsDescendantOf(handle.World) and inside(finish, root.Position)
			and player.Character == character then
			-- GameManager owns win, rewards and the next-level tube. Our finite runout stays safe during the vote.
			completeFor(handle, player, character)
		end
	end
end

function Runtime.Stop(handle)
	handle = handle or active
	if not handle then return end
	handle.Stopped = true
	if handle.Connection then handle.Connection:Disconnect(); handle.Connection = nil end
	if Shade and handle.Shade then pcall(Shade.Stop, handle.Shade); handle.Shade = nil end
	for player, record in pairs(handle.Finishers) do
		record.RecoveryToken = nil
		if record.Connection then record.Connection:Disconnect() end
		if player:GetAttribute("Level2PoolroomsExitGeneration") == handle.Generation then
			player:SetAttribute("Level2PoolroomsExitGeneration", nil)
			player:SetAttribute("Level2_ExitTransition", nil)
		end
	end
	table.clear(handle.Finishers)
	if handle.World:GetAttribute("Level2PoolroomsExitGeneration") == handle.Generation then
		handle.World:SetAttribute("Level2PoolroomsExitGeneration", nil)
	end
	if active == handle then active = nil end
end

function Runtime.Start(world)
	Runtime.Stop()
	Runtime.Prepare(world)
	assert(world.Parent == workspace and world.Name == "Level 2 Generated World", "Poolrooms must be adopted before Start")
	generation += 1
	local handle = {World = world, Hazards = {}, Finish = world[SLIDE_NAME][SLIDE_FINISH],
		SafeSpawn = world[SLIDE_NAME]["Exit Slide Safe Spawn"], Finishers = {}, Generation = generation, Stopped = false}
	for _, part in ipairs(world.Collision:GetDescendants()) do
		if part.Name == "Hazard" and part:IsA("BasePart") and part:GetAttribute("KillZone") == true then
			table.insert(handle.Hazards, part)
		end
	end
	local markers = world.Markers
	local exit = markers:FindFirstChild("EXIT")
	workspace:SetAttribute("Level2_ExitPosition", if exit and exit:IsA("BasePart") then exit.Position else handle.Finish.Position)
	world:SetAttribute("Level2PoolroomsExitGeneration", handle.Generation)
	active = handle
	local elapsed = 0
	local ok, err = pcall(function()
		handle.Connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < ZONE_STEP then return end
			elapsed %= ZONE_STEP
			zoneStep(handle)
		end)
	end)
	if not ok then Runtime.Stop(handle); error(err) end
	if Shade then
		local started, shade = pcall(Shade.Start, world)
		if started then handle.Shade = shade else warn("[Level 2] Shade did not start: " .. tostring(shade)) end
	end
	return handle
end

return Runtime
