--!strict
-- LEVEL2_EXIT_TRANSITION_20260828
-- Deterministic coverage for the Level 2 -> Level 3 exit transition.
--
-- The contract under test is that completing Level 2 does not interrupt the
-- ride. A player crosses an invisible sensor at full slide speed, keeps
-- physically sliding down an enclosed continuation for the whole 15-second
-- decision window, and — if they continue — resumes near the back of Level 3's
-- bore with real downhill velocity and slides out into the mall.
--
-- Structural checks (Validate*) run straight after a Build and need no player.
-- Behavioural checks (Probe*) drive a live Studio session and need one.
--
-- Usage from a Play-session Server probe:
--   local Systems = game:GetService("ServerScriptService")["Level 2 Systems"]
--   local Suite = require(Systems["Level 2 Exit Transition Test Suite"])
--   Suite.ValidateExitGeometry(manifest)
--   Suite.ProbeHighSpeedCompletion(manifest, player)
--   Suite.ProbeTransitionRideDuration(manifest, player, nil, true) -- direct Adapter.Build harness
--   Suite.ValidateLevelThreeResume(level3World)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TestSuite = {}

-- The Slide Controller drops a one-way rider into RUNOUT_BRAKING as soon as the
-- floor's downhill component falls below this, which would stop the ride.
local RELEASE_SLOPE = .12
-- The one-way soft speed cap in the Slide Controller.
local EXIT_SOFT_SPEED_CAP = 105
-- GameManager.POST_WIN_SECONDS. Duplicated deliberately: this suite asserts the
-- geometry is long enough for that window, and must fail if either side drifts.
local POST_WIN_SECONDS = 15
-- The shortest ride that can say anything about the recycle. Descending from the
-- completion sensor to the recycle trigger is about 320 studs of drop at the
-- transition grade, roughly fifteen seconds at the speed cap; thirty leaves room
-- for the plunge and for a client that took a moment to pick the ride up.
local MINIMUM_RECYCLE_WINDOW = 30

local function assertStudioProbe(name: string)
	assert(RunService:IsStudio(), name .. " is Studio-only")
end

-- Completion latches once per player per round by design, so a probe that wants
-- to watch a rider cross the sensor has to clear that latch first. Without this
-- only the first probe in a session could ever see a completion.
local function resetCompletion(player: Player): boolean
	local systems = game:GetService("ServerScriptService"):FindFirstChild("Level 2 Systems")
	local module = systems and systems:FindFirstChild("Level 2 Objective Controller")
	if not module then return false end
	local controller = require(module) :: any
	if type(controller.DebugResetCompletion) ~= "function" then return false end
	return (pcall(controller.DebugResetCompletion, player))
end

local function orderedExitFloors(manifest: any): {BasePart}
	local tube
	for _, object in ipairs(manifest.World:GetDescendants()) do
		if object:IsA("Model") and object.Name == "Level 2 Exit Flume" then
			tube = object
			break
		end
	end
	assert(tube, "Level 2 exit flume model is missing from the generated world")
	local floors = {}
	for _, object in ipairs(tube:GetDescendants()) do
		if object:IsA("BasePart") and object.Name:find("Collision Floor") then
			table.insert(floors, object)
		end
	end
	assert(#floors > 2, "Level 2 exit flume has no collision floors")
	-- The builder numbers every segment, so the name IS the ride order. Sorting
	-- by position would be wrong the moment the path doubles back, which the
	-- transition helix does on every turn.
	table.sort(floors, function(a, b)
		return (tonumber(a.Name:match("(%d+)$")) or 0) < (tonumber(b.Name:match("(%d+)$")) or 0)
	end)
	return floors
end

local function sensorIndex(floors: {BasePart}, sensor: BasePart): number
	local best, bestIndex = math.huge, 1
	for index, floor in ipairs(floors) do
		local distance = (floor.Position - sensor.Position).Magnitude
		if distance < best then
			best = distance
			bestIndex = index
		end
	end
	return bestIndex
end

-- ---------------------------------------------------------------------------
-- Structural
-- ---------------------------------------------------------------------------

-- The completion sensors must be invisible forever, unlit, thick enough that a
-- rider at the speed cap cannot tunnel through between physics steps, and armed
-- only by CanTouch.
function TestSuite.ValidateCompletionSensors(manifest: any): {[string]: any}
	assert(type(manifest) == "table" and manifest.Exit, "ValidateCompletionSensors requires a Level 2 manifest")
	local checked = {}
	for _, entry in ipairs({
		{Part = manifest.Exit.Trigger, Label = "Trigger"},
		{Part = manifest.Exit.Backstop, Label = "Backstop"},
	}) do
		local sensor = entry.Part
		assert(sensor and sensor:IsA("BasePart"), "Level 2 exit " .. entry.Label .. " is missing")
		assert(sensor.Transparency == 1, string.format(
			"Level 2 exit %s must be fully invisible (Transparency %.3f)", entry.Label, sensor.Transparency))
		assert(sensor.CastShadow == false,
			"Level 2 exit " .. entry.Label .. " must not cast a shadow")
		assert(sensor.CanCollide == false,
			"Level 2 exit " .. entry.Label .. " must not collide")
		assert(sensor.Material ~= Enum.Material.Neon,
			"Level 2 exit " .. entry.Label .. " must not use Neon")
		-- A TouchTransmitter is expected (Roblox adds one per live .Touched).
		-- Anything emissive is the regression this guards.
		for _, child in ipairs(sensor:GetDescendants()) do
			assert(not child:IsA("Light"), string.format(
				"Level 2 exit %s carries a %s; the sensor must never light up",
				entry.Label, child.ClassName))
			assert(not child:IsA("ParticleEmitter") and not child:IsA("Beam")
				and not child:IsA("Decal") and not child:IsA("Texture")
				and not child:IsA("SurfaceGui") and not child:IsA("BillboardGui"),
				string.format("Level 2 exit %s carries visible decoration (%s)",
					entry.Label, child.ClassName))
		end

		-- Tunneling: a rider at the soft cap covers this much in one 60 Hz step.
		local stepAtCap = EXIT_SOFT_SPEED_CAP / 60
		local thickness = sensor:GetAttribute("Level2_ExitCompletionSensorThickness")
		assert(type(thickness) == "number", "Level 2 exit " .. entry.Label .. " has no declared thickness")
		assert(thickness >= 8, string.format(
			"Level 2 exit %s is %.1f studs thick; 8 is the floor", entry.Label, thickness))
		assert(thickness >= stepAtCap * 4, string.format(
			"Level 2 exit %s (%.1f studs) is under four cap-speed physics steps (%.2f studs)",
			entry.Label, thickness, stepAtCap * 4))
		table.insert(checked, {
			Label = entry.Label,
			Thickness = thickness,
			StepsCovered = thickness / stepAtCap,
			Transparency = sensor.Transparency,
		})
	end
	assert(manifest.Exit.Trigger ~= manifest.Exit.Backstop,
		"Level 2 exit trigger and backstop must be two distinct sensors")
	return {Sensors = checked}
end

-- Every floor from the completion sensor onward must stay steep enough to keep
-- a one-way rider sliding, must overlap its neighbour so there is no hole, and
-- must carry the one-way flag.
function TestSuite.ValidateTransitionGeometry(manifest: any): {[string]: any}
	assert(type(manifest) == "table" and manifest.Exit, "ValidateTransitionGeometry requires a Level 2 manifest")
	local floors = orderedExitFloors(manifest)
	local start = sensorIndex(floors, manifest.Exit.Trigger)

	local length, shallowest, shallowestIndex = 0, math.huge, -1
	local worstOverlap, worstOverlapIndex = -math.huge, -1
	local missingOneWay = {}
	for index = start, #floors do
		local floor = floors[index]
		local direction = floor:GetAttribute("Level2_SlideDirection")
		assert(typeof(direction) == "Vector3",
			"Transition floor " .. floor.Name .. " has no slide direction")
		local grade = -direction.Unit.Y
		if grade < shallowest then
			shallowest = grade
			shallowestIndex = index
		end
		if floor:GetAttribute("Level2_OneWayExit") ~= true then
			table.insert(missingOneWay, floor.Name)
		end
		if index < #floors then
			local step = (floors[index + 1].Position - floor.Position).Magnitude
			length += step
			-- Consecutive floors abut when the centre-to-centre distance is no
			-- more than the mean of their lengths. A positive value is a hole.
			local reach = (floor.Size.Z + floors[index + 1].Size.Z) * .5
			if step - reach > worstOverlap then
				worstOverlap = step - reach
				worstOverlapIndex = index
			end
		end
	end

	assert(#missingOneWay == 0, string.format(
		"%d transition floor(s) are not flagged one-way; first: %s",
		#missingOneWay, tostring(missingOneWay[1])))
	assert(shallowest > RELEASE_SLOPE, string.format(
		"Transition floor %d has grade %.3f, at or under RELEASE_SLOPE %.2f: a one-way rider stops there",
		shallowestIndex, shallowest, RELEASE_SLOPE))
	assert(worstOverlap <= 0, string.format(
		"Transition floors %d and %d leave a %.2f stud hole",
		worstOverlapIndex, worstOverlapIndex + 1, worstOverlap))

	-- Long enough that the rider is still inside the tube when the decision
	-- window closes, even at the speed cap.
	local rideSecondsAtCap = length / EXIT_SOFT_SPEED_CAP
	assert(rideSecondsAtCap > POST_WIN_SECONDS, string.format(
		"Transition is %.0f studs = %.1fs at the %d stud/s cap; the decision window is %ds",
		length, rideSecondsAtCap, EXIT_SOFT_SPEED_CAP, POST_WIN_SECONDS))
	-- Two asserts, not one. A string.format in an assert's message argument is
	-- evaluated EAGERLY, so folding the nil check and the value check together
	-- turns a missing field into "invalid argument #2 to 'format'" instead of
	-- the message that would have explained it.
	local declaredLength = manifest.Exit.TransitionLength
	assert(type(declaredLength) == "number", string.format(
		"Level 2 exit manifest has no numeric TransitionLength (got %s)",
		typeof(declaredLength)))
	assert(math.abs(declaredLength - length) < length * .35, string.format(
		"Declared transition length %.0f disagrees with the measured %.0f",
		declaredLength, length))

	-- Roblox deletes any unanchored part that falls below
	-- workspace.FallenPartsDestroyHeight (default -500). A tube that descends
	-- past it does not merely look wrong: the rider is removed from the game
	-- mid-ride. The margin is asserted rather than assumed because the helix
	-- depth is a product of grade x turns x radius and is easy to change by
	-- accident.
	local destroyHeight = workspace.FallenPartsDestroyHeight
	local lowest = math.huge
	for index = start, #floors do
		lowest = math.min(lowest, floors[index].Position.Y)
	end
	assert(lowest > destroyHeight + 40, string.format(
		"the transition bottoms out at y=%.0f, within 40 studs of FallenPartsDestroyHeight (%.0f): a rider would be deleted mid-ride",
		lowest, destroyHeight))

	-- The final sleeve segment needs a real overlapping collision cap. Merely
	-- placing a wall near the end can leave a character-width gap (the previous
	-- implementation did), which defeats both the claimed infinite route and
	-- the recycle watchdog if a rider reaches the authored bottom.
	local endStop
	local flume = manifest.Exit.FlumeModel
	for _, object in ipairs(flume and flume:GetDescendants() or {}) do
		if object:IsA("BasePart")
			and object:GetAttribute("Level2_ExitTransitionEndStop") == true then
			assert(not endStop, "Level 2 transition has more than one terminal collision cap")
			endStop = object
		end
	end
	assert(endStop and endStop.CanCollide,
		"Level 2 transition is missing its collidable terminal cap")
	local transitionEnd = manifest.Exit.TransitionEnd
	assert(typeof(transitionEnd) == "Vector3",
		"Level 2 exit manifest has no TransitionEnd for cap validation")
	local localEnd = endStop.CFrame:PointToObjectSpace(transitionEnd)
	local half = endStop.Size * .5
	assert(math.abs(localEnd.X) <= half.X + .01
		and math.abs(localEnd.Y) <= half.Y + .01
		and math.abs(localEnd.Z) <= half.Z + .01,
		string.format(
			"terminal cap does not overlap the final path point (local %.2f, %.2f, %.2f; half-size %.2f, %.2f, %.2f)",
			localEnd.X, localEnd.Y, localEnd.Z, half.X, half.Y, half.Z))

	return {
		FloorCount = #floors,
		LowestPointY = lowest,
		FallenPartsDestroyHeight = destroyHeight,
		SensorFloorIndex = start,
		TransitionFloors = #floors - start + 1,
		TransitionLengthStuds = length,
		ShallowestGrade = shallowest,
		GradeMarginOverRelease = shallowest - RELEASE_SLOPE,
		WorstFloorOverlap = worstOverlap,
		RideSecondsAtCap = rideSecondsAtCap,
		DecisionWindowSeconds = POST_WIN_SECONDS,
		TerminalCapOverlap = Vector3.new(
			half.X - math.abs(localEnd.X),
			half.Y - math.abs(localEnd.Y),
			half.Z - math.abs(localEnd.Z)),
	}
end

-- LEVEL2_EXIT_RECYCLE_20260828
-- The decision window is fifteen seconds, but the WAIT before it is unbounded:
-- the first rider out can be circling for minutes while the last teammate is
-- still looking for the third pump. No finite tube covers that, so the last two
-- turns of the helix are recycled -- a rider crossing the trigger is lifted
-- exactly one turn, which on a UNIFORM helix is the same point one turn up.
--
-- This validates that claim numerically rather than trusting the derivation:
-- every authored path point in the recycled span, lifted by DeltaY, has to land
-- on another authored path point. If it does not, the "seamless" lift is a
-- teleport into a wall, and no amount of play-testing at 100 studs/s would show
-- which of the two it was.
function TestSuite.ValidateRecycleGeometry(manifest: any): {[string]: any}
	assert(type(manifest) == "table" and manifest.Exit, "ValidateRecycleGeometry requires a Level 2 manifest")
	local recycle = manifest.Exit.Recycle
	assert(type(recycle) == "table", "Level 2 exit manifest has no Recycle block")
	local points = manifest.Exit.PathPoints
	assert(type(points) == "table" and #points > 32,
		"Level 2 exit manifest has no usable PathPoints")
	local bore = manifest.Exit.BoreRadius
	assert(type(bore) == "number" and bore > 0, "Level 2 exit manifest has no BoreRadius")

	assert(recycle.DeltaY > 0, "recycle DeltaY must descend")
	assert(math.abs((recycle.TriggerY + recycle.DeltaY) - recycle.LandingY) < 1e-6,
		"recycle landing is not exactly one turn above the trigger")
	assert(recycle.LandingY <= recycle.TopY + 1e-6, string.format(
		"recycle landing y=%.2f is above the top of the helix y=%.2f: the lift leaves the tube",
		recycle.LandingY, recycle.TopY))
	assert(recycle.Turns >= 3, string.format(
		"the helix has only %s turns; a recycled rider needs a full turn of bore below the landing",
		tostring(recycle.Turns)))

	-- Deleted mid-ride is the failure mode this number prevents, and the recycle
	-- means a rider is exposed to it for an unbounded time rather than once.
	local destroyHeight = workspace.FallenPartsDestroyHeight
	assert(recycle.BottomY > destroyHeight + 40, string.format(
		"the helix bottoms out at y=%.0f, within 40 studs of FallenPartsDestroyHeight (%.0f)",
		recycle.BottomY, destroyHeight))
	-- The server backstop lifts half a turn below the trigger. It has to leave
	-- real bore beneath it, or a rider whose client did not recycle reaches the
	-- end stop before the server notices.
	local backstopY = recycle.TriggerY - recycle.DeltaY * .5
	assert(backstopY - recycle.BottomY > 40, string.format(
		"the server recycle backstop at y=%.0f leaves only %.0f studs above the drum floor y=%.0f",
		backstopY, backstopY - recycle.BottomY, recycle.BottomY))

	local worst, worstPoint, checked = 0, nil, 0
	for _, point in ipairs(points) do
		if point.Y <= recycle.TriggerY + 1e-3 and point.Y >= recycle.BottomY - 1e-3 then
			local lifted = point + Vector3.new(0, recycle.DeltaY, 0)
			local nearest = math.huge
			for _, candidate in ipairs(points) do
				local distance = (candidate - lifted).Magnitude
				if distance < nearest then nearest = distance end
			end
			checked += 1
			if nearest > worst then
				worst = nearest
				worstPoint = point
			end
		end
	end
	assert(checked > 0, "no authored path points lie inside the recycled span")
	assert(worst < .5, string.format(
		"lifting the path by one turn misses it by %.3f studs near %s: the recycle is not seamless",
		worst, tostring(worstPoint)))

	return {
		TriggerY = recycle.TriggerY,
		LandingY = recycle.LandingY,
		DeltaY = recycle.DeltaY,
		TopY = recycle.TopY,
		BottomY = recycle.BottomY,
		Turns = recycle.Turns,
		ServerBackstopY = backstopY,
		FallenPartsDestroyHeight = destroyHeight,
		PointsChecked = checked,
		WorstSeamStuds = worst,
		BoreRadius = bore,
	}
end

-- The recovery chamber must exist, be sealed, and be nowhere near the ride.
function TestSuite.ValidateRecoveryChamber(manifest: any): {[string]: any}
	local safeSpawn = manifest.Exit.SafeSpawn
	assert(safeSpawn and safeSpawn:IsA("BasePart"), "Level 2 exit recovery spawn is missing")
	assert(safeSpawn:GetAttribute("Level2_ExitRecoverySpawn") == true,
		"Level 2 exit recovery spawn is not tagged as the recovery destination")
	local walls = 0
	for _, object in ipairs(manifest.World:GetDescendants()) do
		if object.Name:find("Recovery Chamber") then walls += 1 end
	end
	assert(walls >= 6, string.format(
		"Recovery chamber has only %d shell parts; it must be fully sealed (floor, ceiling, four walls)", walls))

	-- It must not be the normal visible route: no part of the ride may pass
	-- through it.
	local floors = orderedExitFloors(manifest)
	local nearest = math.huge
	for _, floor in ipairs(floors) do
		nearest = math.min(nearest, (floor.Position - safeSpawn.Position).Magnitude)
	end
	assert(nearest > 40, string.format(
		"The ride passes within %.0f studs of the recovery spawn; recovery must be off the normal route", nearest))
	return {ShellParts = walls, NearestRideDistance = nearest}
end

function TestSuite.ValidateExitGeometry(manifest: any): {[string]: any}
	return {
		Sensors = TestSuite.ValidateCompletionSensors(manifest),
		Transition = TestSuite.ValidateTransitionGeometry(manifest),
		Recycle = TestSuite.ValidateRecycleGeometry(manifest),
		Recovery = TestSuite.ValidateRecoveryChamber(manifest),
	}
end

-- Level 3's continuation must publish a resume frame that is inside its bore,
-- genuinely downhill, carries real speed, and has a physical way out.
function TestSuite.ValidateLevelThreeResume(world: Instance): {[string]: any}
	assert(world and world.Parent == workspace,
		"ValidateLevelThreeResume requires the live Level 3 world")
	local tube
	for _, object in ipairs(world:GetDescendants()) do
		if object:GetAttribute("Level3_Level2ExitTube") == true then
			tube = object
			break
		end
	end
	assert(tube, "Level 3 is missing the Level 2 exit continuation")

	local position = tube:GetAttribute("Level3_SlideResumePosition")
	local tangent = tube:GetAttribute("Level3_SlideResumeTangent")
	local velocity = tube:GetAttribute("Level3_SlideResumeVelocity")
	local mouth = tube:GetAttribute("Level3_SlideMouthPosition")
	local slideLength = tube:GetAttribute("Level3_SlideLength")
	assert(typeof(position) == "Vector3", "Level 3 resume position is missing")
	assert(typeof(tangent) == "Vector3", "Level 3 resume tangent is missing")
	assert(typeof(velocity) == "Vector3", "Level 3 resume velocity is missing")
	assert(typeof(mouth) == "Vector3", "Level 3 slide mouth position is missing")
	assert(type(slideLength) == "number" and slideLength >= 150, string.format(
		"Level 3 continuation is only %s studs; a resume must have room to become a ride",
		tostring(slideLength)))

	-- Downhill and pointing at the mall, not back up the tube.
	assert(-tangent.Unit.Y > .2, string.format(
		"Level 3 resume tangent is not meaningfully downhill (%.3f)", -tangent.Unit.Y))
	local towardMouth = (mouth - position)
	assert(tangent.Unit:Dot(towardMouth.Unit) > .8, string.format(
		"Level 3 resume tangent does not point down the bore toward the mall (dot %.3f)",
		tangent.Unit:Dot(towardMouth.Unit)))
	assert(velocity.Magnitude >= 40, string.format(
		"Level 3 resume speed %.1f is too low to read as a continuing slide", velocity.Magnitude))
	assert(velocity.Unit:Dot(tangent.Unit) > .99,
		"Level 3 resume velocity is not aligned with the resume tangent")

	-- The resume point must sit near the BACK of the bore, not at its mouth.
	local fromMouth = towardMouth.Magnitude
	assert(fromMouth > slideLength * .7, string.format(
		"Level 3 resume is only %.0f studs from the mouth of a %.0f stud bore; it must be at the back",
		fromMouth, slideLength))

	-- There must be solid tube under it, and a physical outlet at the far end.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local below = workspace:Raycast(position, Vector3.new(0, -24, 0), params)
	assert(below ~= nil, "Nothing solid under the Level 3 resume point; a resuming player would fall")
	assert(below.Instance:GetAttribute("Level3_ProgressionSlide") == true, string.format(
		"The surface under the Level 3 resume point is %s, not the progression slide",
		below.Instance.Name))

	local spawn = workspace:FindFirstChild("ElevatorSpawn")
	assert(spawn and spawn:IsA("BasePart"),
		"Level 3 is missing the ElevatorSpawn fallback placement")

	return {
		ResumePosition = position,
		ResumeTangent = tangent,
		ResumeSpeed = velocity.Magnitude,
		DownhillComponent = -tangent.Unit.Y,
		DistanceFromMouth = fromMouth,
		SlideLength = slideLength,
		FloorUnderResume = below.Instance.Name,
		FallbackSpawn = spawn.Position,
	}
end

-- ---------------------------------------------------------------------------
-- Behavioural
-- ---------------------------------------------------------------------------

-- A player's character is normally owned by that player's client, so a server
-- probe cannot impose a velocity on it: the client overwrites it on the next
-- frame and the rider just stands on the slope. These probes take server
-- ownership for their duration, which makes them deterministic, and hand it
-- back afterwards. The physics under test (low-friction slide floors, the
-- one-way grade) is identical either way; only the authority moves.
-- `keepOwnership` decides WHICH system is under test.
--
-- Taking network ownership makes the server the only author of the character's
-- motion, which is what a launch-speed measurement needs: the rider crosses the
-- sensor at exactly the speed the probe asked for. But the ride itself is driven
-- by the client slide controller, and the recycle that makes it endless happens
-- there too, so a probe that measures the RIDE has to leave the character where
-- it lives in a real round -- on the client -- or it measures a rider falling
-- down a tube with nothing driving them.
local function protect(player: Player, keepOwnership: boolean?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	assert(character and humanoid and root and humanoid.Health > 0,
		"the probe player needs a living character")
	local saved = {
		Character = character,
		Humanoid = humanoid,
		Root = root :: BasePart,
		CFrame = character:GetPivot(),
		Escaped = player:GetAttribute("Escaped"),
		Transition = player:GetAttribute("Level2_ExitTransition"),
		ServerRecycles = player:GetAttribute("Level2_ExitServerRecycleCount"),
		Recoveries = player:GetAttribute("Level2_ExitRecoveryCount"),
		PlatformStand = humanoid.PlatformStand,
		AutoRotate = humanoid.AutoRotate,
		TookOwnership = false,
		OwnedAssemblyRoots = {} :: {BasePart},
	}
	if not keepOwnership then
		saved.TookOwnership = pcall(function() (root :: BasePart):SetNetworkOwner(nil) end)
	end
	return saved
end

-- Ragdoll activation splits the character into several independently simulated
-- assemblies. Claim each live assembly root after that split, rather than
-- assuming the HumanoidRootPart claim made before ragdoll still covers every
-- limb. The high-speed probe is only meaningful when the server owns every
-- assembly whose velocity it authors.
local function claimRagdollAssemblies(saved: any): {BasePart}
	local roots = {} :: {BasePart}
	local seen: {[BasePart]: boolean} = {}
	for _, object in ipairs(saved.Character:GetDescendants()) do
		if object:IsA("BasePart") then
			local root = object.AssemblyRootPart or object
			if not seen[root] then
				seen[root] = true
				local canSet, reason = root:CanSetNetworkOwnership()
				assert(canSet, string.format(
					"cannot claim ragdoll assembly %s: %s", root:GetFullName(), tostring(reason)))
				root:SetNetworkOwner(nil)
				table.insert(roots, root)
			end
		end
	end
	assert(#roots > 0, "the active ragdoll exposed no physical assemblies")
	saved.OwnedAssemblyRoots = roots
	return roots
end

-- Place a probe rider at a position with NO residual momentum, and give the
-- physics step time to register it. Repeated because one frame is not always
-- enough to bleed off a large velocity through a PivotTo.
-- Each behavioural probe rides the flume for real, and a full ride leaves the
-- rider 1600+ studs down the helix. Teleporting them back up and riding again
-- inside the SAME generated round fights streaming and replication badly enough
-- to produce spurious failures, so the exit is treated as consumed once ridden.
--
-- This is a genuine constraint of the probes, not of the game: rebuild the round
-- between behavioural probes. Saying so plainly beats a misleading "tunnelled
-- through the sensor" report that describes the harness rather than the code.
local RIDDEN_MARKER = "Level2_ExitTransitionProbeConsumed"

local function claimRide(manifest: any, probeName: string)
	local world = manifest.World
	assert(world and world.Parent, probeName .. " requires the live generated world")
	assert(world:GetAttribute(RIDDEN_MARKER) ~= true, probeName ..
		" cannot run: this generated round's exit has already been ridden by a" ..
		" behavioural probe. Rebuild the round (Adapter.Build) and run one" ..
		" behavioural probe per build.")
	world:SetAttribute(RIDDEN_MARKER, true)
end

local function settleAt(saved: any, position: Vector3)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {saved.Character}
	params.IgnoreWater = true
	params.RespectCanCollide = true

	local grounded = false
	for _ = 1, 8 do
		saved.Root.AssemblyLinearVelocity = Vector3.zero
		saved.Root.AssemblyAngularVelocity = Vector3.zero
		saved.Character:PivotTo(CFrame.new(position))
		task.wait(.2)
		-- The launch only means anything if the rider is actually resting on the
		-- slide floor. Asserting position alone was not enough: straight after a
		-- Build the character can still be mid-relocation, and the probe would
		-- then "launch" someone who was never on the flume and report a
		-- tunnelling failure that never happened.
		local hit = workspace:Raycast(saved.Root.Position, Vector3.new(0, -24, 0), params)
		if hit and hit.Instance:GetAttribute("Level2_SlideFloor") == true then
			grounded = true
			break
		end
	end
	local drift = (saved.Root.Position - position).Magnitude
	assert(drift < 12, string.format(
		"probe rider would not settle at the launch point (%.1f studs away)", drift))
	assert(grounded,
		"probe rider is not resting on a slide floor at the launch point")
end

local function restore(player: Player, saved: any)
	player:SetAttribute("Escaped", saved.Escaped)
	player:SetAttribute("Level2_ExitTransition", saved.Transition)
	player:SetAttribute("Level2_ExitServerRecycleCount", saved.ServerRecycles)
	player:SetAttribute("Level2_ExitRecoveryCount", saved.Recoveries)
	if saved.Character.Parent and saved.Humanoid.Health > 0 then
		saved.Humanoid.PlatformStand = saved.PlatformStand
		saved.Humanoid.AutoRotate = saved.AutoRotate
		-- The high-speed probe drives every ragdoll assembly. Clear every one on
		-- restore as well; clearing only HumanoidRootPart can leave a detached limb
		-- carrying probe momentum into the lobby placement.
		for _, object in ipairs(saved.Character:GetDescendants()) do
			if object:IsA("BasePart") then
				object.AssemblyLinearVelocity = Vector3.zero
				object.AssemblyAngularVelocity = Vector3.zero
			end
		end
		saved.Character:PivotTo(saved.CFrame)
	end
	if saved.TookOwnership then
		local restored: {[BasePart]: boolean} = {}
		for _, root in ipairs(saved.OwnedAssemblyRoots) do
			if root.Parent and not restored[root] then
				restored[root] = true
				pcall(function() root:SetNetworkOwnershipAuto() end)
			end
		end
		if saved.Root.Parent and not restored[saved.Root] then
			pcall(function() saved.Root:SetNetworkOwnershipAuto() end)
		end
	end
end

-- Crossing the sensor at full slide speed must complete the level exactly once,
-- must NOT zero the rider's velocity, and must NOT move them.
function TestSuite.ProbeHighSpeedCompletion(manifest: any, player: Player, speed: number?): {[string]: any}
	assertStudioProbe("ProbeHighSpeedCompletion")
	assert(type(manifest) == "table" and manifest.Exit, "ProbeHighSpeedCompletion requires a Level 2 manifest")
	assert(player and player:IsA("Player") and player.Parent == Players,
		"ProbeHighSpeedCompletion requires a live player")
	local launchSpeed = tonumber(speed) or EXIT_SOFT_SPEED_CAP
	local floors = orderedExitFloors(manifest)
	local start = sensorIndex(floors, manifest.Exit.Trigger)
	local launchGap = 16
	assert(start > launchGap,
		"the completion sensor is too close to the flume mouth to launch a probe above it")
	local PROBE_NAME = "ProbeHighSpeedCompletion"

	claimRide(manifest, PROBE_NAME)
	-- This probe measures the authoritative completion detector, not the client
	-- ride motor (the 75-second probe below covers that separately). Give the
	-- server deterministic ownership and launch every ragdoll assembly at the
	-- same velocity. Writing only HumanoidRootPart on a client-owned ragdoll is a
	-- non-authoritative one-frame suggestion; it was intermittently overwritten
	-- before the rider reached either sensor and misreported that harness stall as
	-- a tunnelling failure.
	local saved = protect(player, false)
	local result
	local ok, failure = pcall(function()
		local launchFloor = floors[start - launchGap]
		local direction = (launchFloor:GetAttribute("Level2_SlideDirection") :: Vector3).Unit
		-- Settle before launching. A previous probe can leave the rider 1500
		-- studs down the helix at 100+ studs/s, and teleporting them back without
		-- killing that momentum carries them out of the bore before they reach
		-- the sensor -- which reads as a tunnelling failure that is really just
		-- test order dependence.
		pcall(function() player:RequestStreamAroundAsync(launchFloor.Position, 10) end)
		settleAt(saved, launchFloor.Position + Vector3.new(0, 3.2, 0))
		-- Clear both completion latches and the sweep endpoint AFTER placement;
		-- the setup teleport is not part of the ride being tested.
		resetCompletion(player)
		player:SetAttribute("Escaped", nil)
		player:SetAttribute("Level2_ExitTransition", nil)
		local ragdollDeadline = os.clock() + 4
		while saved.Character:GetAttribute("Level2_RagdollServerActive") ~= true
			and os.clock() < ragdollDeadline do task.wait(.05) end
		assert(saved.Character:GetAttribute("Level2_RagdollServerActive") == true,
			"the production slide controller did not enter its ragdoll session")
		local ownedAssemblies = claimRagdollAssemblies(saved)
		for _, root in ipairs(ownedAssemblies) do
			root.AssemblyLinearVelocity = direction * launchSpeed
			root.AssemblyAngularVelocity = Vector3.zero
		end
		-- Observe a real physics step under server authority. Merely recording the
		-- value assigned above would let this test pass even if ownership were
		-- immediately reclaimed and the launch overwritten before the sensor.
		RunService.Heartbeat:Wait()
		local observedLaunchSpeed = saved.Root.AssemblyLinearVelocity.Magnitude
		local minimumObservedSpeed = launchSpeed * .75
		assert(observedLaunchSpeed >= minimumObservedSpeed, string.format(
			"high-speed probe never reached its required speed after a physics step" ..
			" (observed %.1f, required %.1f, requested %.1f studs/s)",
			observedLaunchSpeed, minimumObservedSpeed, launchSpeed))

		local deadline = os.clock() + 8
		local completedAt, speedAtCompletion, positionAtCompletion
		local peakSpeed = observedLaunchSpeed
		while os.clock() < deadline do
			task.wait(.05)
			peakSpeed = math.max(peakSpeed, saved.Root.AssemblyLinearVelocity.Magnitude)
			if player:GetAttribute("Escaped") == true then
				completedAt = os.clock()
				speedAtCompletion = saved.Root.AssemblyLinearVelocity.Magnitude
				positionAtCompletion = saved.Root.Position
				break
			end
		end
		assert(completedAt, string.format(
			"a rider launched at %.0f studs/s tunnelled through the completion sensors without completing",
			launchSpeed))
		assert(player:GetAttribute("Level2_ExitTransition") == true,
			"completion did not open the exit transition state")
		-- The old implementation zeroed velocity and teleported here. Both are
		-- the regression this probe exists to catch.
		task.wait(.25)
		local afterSpeed = saved.Root.AssemblyLinearVelocity.Magnitude
		assert(afterSpeed > 5, string.format(
			"the rider was stopped by completion (%.1f studs/s a quarter second later)", afterSpeed))
		local moved = (saved.Root.Position - manifest.Exit.SafeSpawn.Position).Magnitude
		assert(moved > 60, string.format(
			"completion teleported the rider to within %.0f studs of the recovery spawn", moved))
		result = {
			LaunchSpeed = launchSpeed,
			ObservedLaunchSpeed = observedLaunchSpeed,
			MinimumObservedSpeed = minimumObservedSpeed,
			OwnedAssemblies = #ownedAssemblies,
			PeakSpeed = peakSpeed,
			SpeedAtCompletion = speedAtCompletion,
			SpeedAfterCompletion = afterSpeed,
			PositionAtCompletion = positionAtCompletion,
			DistanceFromRecoverySpawn = moved,
		}
	end)
	restore(player, saved)
	if not ok then error(failure, 0) end
	return result
end

-- After completion the rider must still be sliding when the decision window
-- closes, still inside the tube, and still flagged mid-transition.
function TestSuite.ProbeTransitionRideDuration(manifest: any, player: Player, seconds: number?,
	isolatedHarness: boolean?): {[string]: any}
	assertStudioProbe("ProbeTransitionRideDuration")
	local PROBE_NAME = "ProbeTransitionRideDuration"
	-- NOT POST_WIN_SECONDS. The authored tube alone is over 2000 studs, about
	-- twenty seconds at the speed cap, so a fifteen-second ride never even
	-- reaches the recycle trigger: every assertion below would be satisfied by
	-- the static geometry and the probe would prove nothing about the ride being
	-- unbounded. The default is long enough to recycle several times over.
	local window = tonumber(seconds) or MINIMUM_RECYCLE_WINDOW * 2.5
	-- In a normal solo round GameManager causally tears this world down fifteen
	-- seconds after the only player completes. That is a valid production result,
	-- but it cannot prove a 30-75 second recycle. Require either the isolated
	-- adapter session used by this suite or an explicit unescaped teammate who
	-- keeps the round alive, and fail before moving the player if neither exists.
	-- Direct Adapter.Build harnesses must explicitly pass isolatedHarness=true;
	-- that opt-in cannot be inferred because the production controllers require
	-- the same InRound/RoundActive attributes as the real GameManager round.
	assert(player:GetAttribute("InRound") == true
		and workspace:GetAttribute("RoundActive") == true,
		"the ride probe requires InRound=true and RoundActive=true so the production slide and objective controllers are armed")
	if isolatedHarness ~= true then
		local roundKeeper = false
		for _, candidate in ipairs(Players:GetPlayers()) do
			local character = candidate.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if candidate ~= player
				and candidate:GetAttribute("InRound") == true
				and candidate:GetAttribute("Escaped") ~= true
				and humanoid and humanoid.Health > 0 then
				roundKeeper = true
				break
			end
		end
		assert(roundKeeper,
			"the long recycle probe cannot run in a normal solo round: use an isolated Level 2 adapter session or keep one living teammate unescaped")
	end
	local floors = orderedExitFloors(manifest)
	local start = sensorIndex(floors, manifest.Exit.Trigger)
	local launchGap = 16
	assert(start > launchGap,
		"the completion sensor is too close to the flume mouth to launch the ride probe")
	claimRide(manifest, PROBE_NAME)
	-- Client-owned, deliberately: see protect(). This probe measures the ride.
	local saved = protect(player, true)
	local result
	local ok, failure = pcall(function()
		local launchFloor = floors[start - launchGap]
		local direction = (launchFloor:GetAttribute("Level2_SlideDirection") :: Vector3).Unit
		-- Settle before launching. A previous probe can leave the rider 1500
		-- studs down the helix at 100+ studs/s, and teleporting them back without
		-- killing that momentum carries them out of the bore before they reach
		-- the sensor -- which reads as a tunnelling failure that is really just
		-- test order dependence.
		-- Stream the flume in around the launch point first. The probe drops the
		-- rider a long way from wherever they were standing, and a client that
		-- has not got the floor yet simply does not simulate them -- which shows
		-- up as a "stalled" ride that is really an unloaded one.
		pcall(function() player:RequestStreamAroundAsync(launchFloor.Position, 10) end)
		settleAt(saved, launchFloor.Position + Vector3.new(0, 3.2, 0))
		resetCompletion(player)
		player:SetAttribute("Escaped", nil)
		player:SetAttribute("Level2_ExitTransition", nil)
		local ragdollDeadline = os.clock() + 4
		while saved.Character:GetAttribute("Level2_RagdollServerActive") ~= true
			and os.clock() < ragdollDeadline do task.wait(.05) end
		assert(saved.Character:GetAttribute("Level2_RagdollServerActive") == true,
			"the production slide controller did not enter its ragdoll session")
		saved.Root.AssemblyLinearVelocity = direction * EXIT_SOFT_SPEED_CAP

		-- The window is measured from COMPLETION, not from the launch: that is
		-- where the real decision window starts, and it keeps the measurement
		-- clear of however long this particular client took to pick the ride up.
		local armDeadline = os.clock() + 60
		while player:GetAttribute("Escaped") ~= true and os.clock() < armDeadline do
			task.wait(.2)
		end
		assert(player:GetAttribute("Escaped") == true,
			"the rider never crossed the completion sensor during the ride probe")

		local samples = {}
		local started = os.clock()
		local travelled, lastPosition = 0, saved.Root.Position
		local stalledSamples = 0
		local lowestY = saved.Root.Position.Y
		-- Recycles are COUNTED from the outside, by watching for the one-turn
		-- lift itself. The client's own tally is a client-set character
		-- attribute, which never replicates back here, and a probe that trusted
		-- it would silently measure nothing. A sudden climb of most of a turn
		-- inside half a second has no other explanation on a downhill ride.
		local recycleEvents = 0
		local liftThreshold = manifest.Exit.Recycle
			and manifest.Exit.Recycle.DeltaY * .8 or math.huge
		while os.clock() - started < window do
			task.wait(.5)
			local position = saved.Root.Position
			local climb = position.Y - lastPosition.Y
			if climb >= liftThreshold then recycleEvents += 1 end
			travelled += (position - lastPosition).Magnitude
			lastPosition = position
			local speed = saved.Root.AssemblyLinearVelocity.Magnitude
			if speed < 8 then stalledSamples += 1 end
			table.insert(samples, {
				T = os.clock() - started,
				Position = position,
				Speed = speed,
				Escaped = player:GetAttribute("Escaped") == true,
				Transitioning = player:GetAttribute("Level2_ExitTransition") == true,
			})
			lowestY = math.min(lowestY, position.Y)
		end
		assert(player:GetAttribute("Level2_ExitTransition") == true, string.format(
			"the exit transition was cleared before the %.0f second decision window closed", window))
		assert(stalledSamples == 0, string.format(
			"the rider stalled on %d of %d samples during the decision window", stalledSamples, #samples))
		assert(travelled > window * 30, string.format(
			"the rider covered only %.0f studs in %.0f seconds; the ride is not continuing", travelled, window))
		-- The tube is finite; the RIDE is not. Past the point where the authored
		-- tube runs out, still moving can only mean the recycle is working -- so
		-- this is asserted unconditionally, and a caller who asks for a window too
		-- short to reach the trigger is told the probe cannot answer the question
		-- rather than being handed a pass that the static geometry earned.
		local serverRecycles = tonumber(player:GetAttribute("Level2_ExitServerRecycleCount")) or 0
		local recoveries = tonumber(player:GetAttribute("Level2_ExitRecoveryCount")) or 0
		local recycle = manifest.Exit.Recycle
		assert(window >= MINIMUM_RECYCLE_WINDOW, string.format(
			"a %.0f second ride cannot test the recycle: the authored tube is %.0f studs"
			.. " and the rider does not reach the trigger for about %d seconds",
			window, manifest.Exit.TransitionLength, MINIMUM_RECYCLE_WINDOW))
		assert(recycleEvents > 0, string.format(
			"the rider was still moving after %.0f seconds but was never lifted a turn:"
			.. " the tube is only %.0f studs, so this is not the recycle keeping them up",
			window, manifest.Exit.TransitionLength))
		-- A recovery uses the same one-turn landing point as a recycle. Without
		-- this production-owned counter, a broken rider repeatedly rescued by the
		-- watchdog could masquerade as a healthy infinite tube in the lift samples.
		assert(recoveries == 0, string.format(
			"the ride required %d server recoveries; observed lifts do not prove healthy recycling",
			recoveries))
		if recycle then
			assert(lowestY > recycle.BottomY - 2, string.format(
				"the rider sank to y=%.0f, below the drum floor y=%.0f", lowestY, recycle.BottomY))
			assert(lowestY > workspace.FallenPartsDestroyHeight + 40, string.format(
				"the rider reached y=%.0f, within 40 studs of FallenPartsDestroyHeight (%.0f)",
				lowestY, workspace.FallenPartsDestroyHeight))
		end
		result = {
			WindowSeconds = window,
			Samples = #samples,
			TravelledStuds = travelled,
			StalledSamples = stalledSamples,
			StillTransitioning = true,
			ObservedRecycleLifts = recycleEvents,
			ServerFallbackRecycles = serverRecycles,
			ServerRecoveries = recoveries,
			LowestY = lowestY,
			DrumFloorY = recycle and recycle.BottomY or nil,
			FallenPartsDestroyHeight = workspace.FallenPartsDestroyHeight,
			Series = samples,
		}
	end)
	restore(player, saved)
	if not ok then error(failure, 0) end
	return result
end

-- Resuming at Level 3's frame must carry the rider out of the bore under its
-- own physics and leave them standing in the mall, not ragdolled.
function TestSuite.ProbeLevelThreeSlideOut(world: Instance, player: Player): {[string]: any}
	assertStudioProbe("ProbeLevelThreeSlideOut")
	local frame = TestSuite.ValidateLevelThreeResume(world)
	-- Client-owned, like the other behavioural probes: the continuation bore is
	-- driven by the same client slide controller as the Level 2 flume, and a
	-- server-owned character measures a rider coasting with nothing driving them.
	local saved = protect(player, true)
	local result
	local ok, failure = pcall(function()
		local tube
		for _, object in ipairs(world:GetDescendants()) do
			if object:GetAttribute("Level3_Level2ExitTube") == true then tube = object break end
		end
		local position = tube:GetAttribute("Level3_SlideResumePosition") :: Vector3
		local tangent = tube:GetAttribute("Level3_SlideResumeTangent") :: Vector3
		local velocity = tube:GetAttribute("Level3_SlideResumeVelocity") :: Vector3
		local mouth = tube:GetAttribute("Level3_SlideMouthPosition") :: Vector3

		saved.Root.Anchored = true
		saved.Root.AssemblyLinearVelocity = Vector3.zero
		saved.Character:PivotTo(CFrame.lookAt(position, position + tangent))
		task.wait(1.1)
		saved.Root.Anchored = false
		saved.Root.AssemblyLinearVelocity = velocity

		local deadline = os.clock() + 14
		local exitedAt, peakSpeed, sawPlatformStand = nil, 0, false
		local approachSpeed, travelled = 0, 0
		local lastPosition = saved.Root.Position
		local towardMall = (mouth - position).Unit
		while os.clock() < deadline do
			-- 0.1s, not 0.25s. The mall floor takes a rider from 110 studs/s to a
			-- stop inside about a third of a second, so a coarse sample lands
			-- somewhere random on that ramp and measures the floor rather than
			-- the ride.
			task.wait(.1)
			local here = saved.Root.Position
			travelled += (here - lastPosition).Magnitude
			lastPosition = here
			local speed = saved.Root.AssemblyLinearVelocity.Magnitude
			peakSpeed = math.max(peakSpeed, speed)
			if saved.Humanoid.PlatformStand then sawPlatformStand = true end
			local past = (here - mouth):Dot(towardMall)
			if past <= 0 then
				-- The speed they ARRIVE at the mouth with is the honest measure of
				-- whether the bore carried them; where they stop afterwards is a
				-- property of the mall floor.
				approachSpeed = speed
			elseif not exitedAt then
				exitedAt = os.clock()
			end
			if exitedAt and os.clock() - exitedAt > 5 then break end
		end
		assert(sawPlatformStand,
			"the rider never entered the slide state; Level 3's bore is being walked, not ridden")
		assert(exitedAt, "the rider never reached the mouth of Level 3's bore")
		-- What "slides out into the mall" actually means is that the bore CARRIES
		-- them: they cover its length under their own physics and are still moving
		-- when they pass the mouth. Where they finally come to rest is a property
		-- of the mall floor's friction, not of the transition, and measuring that
		-- instead let a rider who was carried the whole way out fail the test.
		assert(travelled > frame.SlideLength * .8, string.format(
			"the rider covered only %.0f studs of a %.0f stud bore", travelled, frame.SlideLength))
		assert(approachSpeed > 40, string.format(
			"the rider reached the mouth at only %.0f studs/s; the resume must carry them out",
			approachSpeed))
		assert(peakSpeed > frame.ResumeSpeed, string.format(
			"the bore never accelerated the rider past its %.0f stud/s resume speed (peak %.0f);"
			.. " the continuation is not downhill under them", frame.ResumeSpeed, peakSpeed))
		local past = (saved.Root.Position - mouth):Dot(towardMall)
		assert(past > 0, string.format(
			"the rider ended %.0f studs short of the mouth; they must leave the bore", past))
		assert(saved.Humanoid.PlatformStand == false,
			"the rider was left in PlatformStand after leaving the bore")
		result = {
			Frame = frame,
			PeakSpeed = peakSpeed,
			ApproachSpeed = approachSpeed,
			TravelledStuds = travelled,
			StudsPastMouth = past,
			EnteredSlideState = sawPlatformStand,
			ReleasedOnExit = true,
		}
	end)
	restore(player, saved)
	if saved.Humanoid.Parent then saved.Humanoid.PlatformStand = false end
	if not ok then error(failure, 0) end
	return result
end

return TestSuite
