local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Navigator = require(script.Parent:WaitForChild("Level 2 Pool Foam Navigator"))

local Controller = {}
local activeSession

-- Sessions that are PAUSED and therefore no longer `activeSession`: keyed by the
-- session table, valued by the pause handle that owns it. `parkedCount` is the
-- same information as a number, kept alongside because pairs() cannot be counted
-- in constant time and the residue readers ask for the count far more often than
-- for the members.
--
-- WHAT WENT WRONG WITHOUT IT: a successful pause set `activeSession = nil`, and
-- `activeSession` was the module's ONLY handle on a session. A parked session
-- was therefore invisible to everything that mattered. DebugIsPaused() read
-- `activeSession` and answered FALSE for a correctly paused session, so the
-- suite's residue check could never fire. Stop() read `activeSession` and so
-- destroyed nothing while a session was parked -- yet still republished the IDLE
-- surface over the ~22 attributes the handle had recorded. Start() called that
-- same no-op Stop() and then orphaned the parked session forever, because
-- nothing else held a reference and its handle's resume was refused from then on
-- with "another session is active". And every "is a runtime folder left in the
-- world" residue count read a leaked parked session as clean, because pause had
-- set its RuntimeFolder.Parent to nil.
local parkedSessions = {}
local parkedCount = 0

local function registerParked(session, handle)
	if parkedSessions[session] == nil then parkedCount += 1 end
	parkedSessions[session] = handle
end

local function unregisterParked(session)
	if parkedSessions[session] == nil then return end
	parkedSessions[session] = nil
	parkedCount -= 1
end

-- PauseDepth used to be incremented at pause and never decremented and never
-- read, which made it a counter of "pauses that ever happened" rather than of
-- "borrows still outstanding". It now goes down on resume AND on stopping a
-- parked session, and is floored at 0 so a double decrement cannot make the
-- residue reader report a negative debt.
local function incrementPauseDepth(session)
	session.PauseDepth = (tonumber(session.PauseDepth) or 0) + 1
end

local function decrementPauseDepth(session)
	session.PauseDepth = math.max(0, (tonumber(session.PauseDepth) or 0) - 1)
end

-- A pause handle, a raw session table, or nothing -- resolved to a session.
local function sessionFromHandle(handle)
	if type(handle) ~= "table" then return nil end
	if type(handle.Session) == "table" then return handle.Session end
	if parkedSessions[handle] ~= nil then return handle end
	-- A live session table handed over directly. Phase plus Connections is the
	-- shape no pause handle has.
	if handle.Phase ~= nil and handle.Connections ~= nil then return handle end
	return nil
end

local function singleParkedSession()
	if parkedCount ~= 1 then return nil end
	for session in pairs(parkedSessions) do return session end
	return nil
end

-- Which session a debug READER should describe. The active one when there is
-- one; otherwise the one the caller named through its handle; otherwise the sole
-- parked session, if it is unambiguous. Ambiguity is answered with nil rather
-- than with a guess: two parked sessions and no handle is a question this cannot
-- honestly answer.
--
-- This is what makes "the pending scream did NOT fire while the session was
-- paused" a real assertion. While every reader keyed off `activeSession`, a
-- paused session reported no screams because there was no session to ask, not
-- because nothing had fired -- so the assertion passed vacuously.
local function resolveDebugSession(handle)
	if activeSession then return activeSession end
	return sessionFromHandle(handle) or singleParkedSession()
end

local TEMPLATE_NAME = "Level 2 Slidemouth Template"
local RUNTIME_NAME = "Level 2 Slidemouth Runtime"
local MODEL_NAME = "Level 2 Slidemouth"
-- Controlled aperture and same-route sweeps showed that the authored full-size
-- body fits at the reported block points. The real blockers were decoration on
-- reserved graph lanes (including a Slide Hall pier and a lounger), so keep the
-- visual at its authored size and fix those world routes instead of hiding the
-- defect with cosmetic scaling. The separate 5.25-stud mouth attack remains an
-- intentional gameplay value and is not derived from model or navigation size.
local MODEL_SCALE = 1
local SPAWN_PUMPS = 2
local FAST_PUMPS = 3
local PUMP_TWO_SPEED = 24 -- exactly 150% of the normal 16-stud WalkSpeed
local PUMP_THREE_SPEED = 36
local ACCELERATION = 32
local DECELERATION = 40
local TARGET_REFRESH = .2
local ATTACK_DISTANCE = 5.25
local ATTACK_COOLDOWN = 1.1
local PUMP_ONE_GROAN_DELAY = 1.25
local SPAWN_GROAN_DELAY = .35
local PROGRESS_WINDOW = .75
-- PathfindingService plus the square-body centring pass is deliberately
-- asynchronous and can use several scheduler yields on a long generated route.
-- Give the current request the same finite settle contract exercised by the
-- traversal suite before the movement watchdog is allowed to replace it.
local PATH_REQUEST_SETTLE_SECONDS = 8
-- How far a wedged creature may back out along its own validated trail before
-- replanning. Deliberately short: this is an unstick, not a repositioning tool.
local RECOVERY_RETREAT_STUDS = 14
local BUOYANT_SHOVE_COOLDOWN = .16
local BUOYANT_SHOVE_MIN_SPEED = 28
local BUOYANT_SHOVE_MAX_SPEED = 46

local MOVEMENT = {
	-- Match the full-size runtime body. A 10.5 radius made Roblox treat it
	-- as a 21-stud cylinder, too wide for the upper curve of vaulted portals.
	--
	-- Neither radius has anything to do with damage, and this was measured
	-- rather than assumed: the creature carries NO collider at all (every part
	-- is CanCollide/CanTouch/CanQuery false, set in the spawn path), and its
	-- attack is a 5.25-stud magnitude check from the mouth attachment
	-- (ATTACK_DISTANCE) gated by a facing dot and a line-of-sight ray. Lowering
	-- either radius cannot change what the creature can hit.
	--
	-- AgentRadius is the BODY probe -- the box the navigator tests before it
	-- commits a step -- against the measured full-size mesh half-width.
	-- PathAgentRadius is handed ONLY to PathfindingService:CreatePath.
	--
	-- 8 was tried at 7 on 2026-08-29 and put back. The reasoning for lowering it
	-- was that the tightest authored aperture (the Ring Corridor arch rings,
	-- 16.86 studs of clear channel) leaves only 0.86 studs over the 16.0 that a
	-- radius of 8 demands, so PathfindingService ought to have been failing
	-- through openings the body clears. Measured against a real generated world
	-- (seed 101, 38 hall nodes, 14 adjacent pairs), radius 7 routed exactly the
	-- same 10 of 14 pairs as radius 8 -- no improvement -- and neither radius
	-- produced a single path segment that crossed collidable geometry. The
	-- number is therefore left where the body says it belongs. What the same
	-- measurement DID implicate is on the world side, not here: the column base
	-- flares are collidable rings 2.02x the visible shaft diameter, tagged
	-- Level2_NoEntityGround so they are hard walls rather than 0.08-stud steps.
	AgentRadius = 8.25 * MODEL_SCALE,
	-- PathAgentRadius and AgentRadius share the same measured base, so the navmesh
	-- and the square body use one conservative clearance contract.
	-- Keeping that 0.20-stud conservative margin prevents PathfindingService from
	-- selecting a gap the live body probe must immediately refuse.
	PathAgentRadius = 8.25 * MODEL_SCALE,
	AgentHeight = 11 * MODEL_SCALE,
	WaypointSpacing = 5,
	WaypointArrivalDistance = 2.25,
	RepathDistance = 7,
	RepathInterval = .45,
	FootClearance = .08,
	FloorProbeAbove = 16,
	FloorProbeDepth = 80,
	MaxStepHeight = 3.5,
	MaxTravelStep = .9,
	TurnResponsiveness = 9,
	-- Never steer backward around an obstacle; >90-degree probes caused
	-- the creature to moonwalk and rapidly reverse around columns.
	SteerAngles = {20, 35, 50},
}

local function finiteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function stateFolder()
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	return state and state:IsA("Folder") and state or nil
end

local function publish(name, value)
	local state = stateFolder()
	if state and state:GetAttribute(name) ~= value then
		state:SetAttribute(name, value)
	end
end

local function publishStopped(reason)
	publish("Level2_SlidemouthActive", false)
	publish("Level2_SlidemouthState", reason or "IDLE")
	publish("Level2_SlidemouthGeneration", 0)
	publish("Level2_SlidemouthTargetUserId", 0)
	publish("Level2_SlidemouthSpeed", 0)
	publish("Level2_SlidemouthPathStatus", "IDLE")
	publish("Level2_SlidemouthScreamSerial", 0)
	publish("Level2_SlidemouthScreamKind", "")
	publish("Level2_SlidemouthScreamPosition", Vector3.zero)
	publish("Level2_SlidemouthWarningSerial", 0)
	publish("Level2_SlidemouthWarningPosition", Vector3.zero)
	publish("Level2_SlidemouthWarningPump", 0)
	publish("Level2_SlidemouthScreamBusyUntil", 0)
	publish("Level2_SlidemouthSpawnDistance", 0)
	publish("Level2_SlidemouthSpawnHidden", false)
	publish("Level2_SlidemouthSpawnAnchor", "")
	publish("Level2_SlidemouthSpawnHall", 0)
	publish("Level2_SlidemouthSpawnPlayerHops", -1)
	publish("Level2_SlidemouthSpawnPumpHops", -1)
	publish("Level2_SlidemouthSpawnPumpHall", 0)
	publish("Level2_SlidemouthSpawnTier", 0)
	publish("Level2_SlidemouthRetreatStuds", 0)
end

-- Is the world this session was built for still the world?
local function worldIntact(session)
	local world = session.Manifest and session.Manifest.World
	if not (world and world.Parent) then return false end
	local worldGeneration = world:GetAttribute("Level2_Generation")
	return worldGeneration == nil or worldGeneration == session.Generation
end

-- A session is ALIVE when it is the current one, its world still exists, and it
-- is actually running. The Phase test is what makes a cooperative pause safe:
-- previously the only way to stand a session down was to clear activeSession,
-- which every background job read as "this session is over" -- and they exited
-- without rearming, so a pending pump scream was lost for good.
local function sessionAlive(session)
	if activeSession ~= session then return false end
	if session.Phase ~= "RUNNING" then return false end
	return worldIntact(session)
end

-- Still OURS, even if not currently running. Background jobs use this to tell
-- "wait, we are paused" from "stop, we are finished".
local function sessionRetained(session)
	return session.Phase ~= "STOPPED" and worldIntact(session)
		and (activeSession == session or session.Phase == "PAUSED")
end

-- THE RUN TOKEN -- the cancellation the pause machinery never had.
--
-- WHAT SHIPPED BROKEN: DebugPauseSession is transactional against its own three
-- stages and against NOTHING ELSE. Work that was already in flight when the
-- borrow landed carried straight on mutating the parked session:
--
--   * the pump-three escalation was task.spawn'ed with no phase and no token
--     guard at all. Every step it takes yields -- spawnEntity, the escalation's
--     WarpTo, the ComputeAsync inside _fallbackWaypoints -- so a pause could
--     land in any of those yields and the job would go on to move the navigator,
--     warp the model, reset ProgressAt/RecoveryStage/RecoveryGoal/RecoveryUntil
--     and republish five escalation attributes, ALL of which the pause handle
--     had already snapshotted and still owed back to the incumbent;
--   * and the retained PlayerRemoving connection had the same hole: it could
--     clear a PARKED session's target and, through setTarget, write
--     Level2_SlidemouthTargetUserId = 0 and the player chase attributes over a
--     state folder the borrower owns.
--
-- The token is bumped on every departure from RUNNING and again on every return
-- to it. A deferred job captures it at SCHEDULE time and compares it at FIRE
-- time; a mismatch means "the session you were queued for is not the session you
-- woke into", and the job becomes a no-op. It is deliberately stricter than a
-- bare phase test, because it also catches a job that slept straight through a
-- whole pause/resume round trip -- by then every value it was going to write
-- against has been snapshotted and written back underneath it.
--
-- WHAT MUST NOT USE IT, and why this is not simply "guard everything":
--
--   * work that is SUPPOSED to survive a borrow. The pending pump scream is the
--     documented example -- it must still fire exactly once after the resume, at
--     its preserved remaining delay -- so its job polls session.Phase and waits
--     the pause out rather than capturing a token. A token there would cancel
--     the very thing a borrow promises to give back.
--   * RETAINED connections, which live as long as the session and are meant to
--     work again after a resume. They gate on sessionAlive() instead, which is
--     the same "not right now" WITHOUT the "and never again".
--
-- RunToken is deliberately NOT in PAUSE_VALUE_FIELDS: restoring it across a
-- resume would undo the resume's own bump and hand the cancelled jobs their
-- session back.
local function bumpRunToken(session)
	session.RunToken = (tonumber(session.RunToken) or 0) + 1
end

-- May a job that captured `runToken` mutate this session RIGHT NOW? Only when
-- the session is the live, running, world-intact one AND has not left RUNNING
-- since the token was taken.
local function runTokenCurrent(session, runToken): boolean
	return session.RunToken == runToken and sessionAlive(session)
end

local function roundReady(session)
	return sessionAlive(session)
		and workspace:GetAttribute("SelectedLevel") == 2
		and workspace:GetAttribute("RoundActive") == true
		and workspace:GetAttribute("WorldGenerated") == true
end

local function livingRecord(session, player)
	if not roundReady(session)
		or player.Parent ~= Players
		or player:GetAttribute("InRound") ~= true
		or player:GetAttribute("Escaped") == true
	then
		return nil
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and humanoid and humanoid.Health > 0 and root and root:IsA("BasePart")) then
		return nil
	end
	return {Player = player, Character = character, Humanoid = humanoid, Root = root}
end

local function livingRecords(session)
	local records = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local record = livingRecord(session, player)
		if record then table.insert(records, record) end
	end
	return records
end

local function horizontalDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function makeRayParams(session)
	local exclusions = {session.RuntimeFolder}
	if session.Manifest.EntityNodes then table.insert(exclusions, session.Manifest.EntityNodes) end
	for _, object in ipairs(session.BuoyantProps or {}) do
		if object.Parent then table.insert(exclusions, object) end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(exclusions, player.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function clearLine(session, fromPosition, toPosition)
	local displacement = toPosition - fromPosition
	if displacement.Magnitude <= .05 then return true end
	return workspace:Raycast(fromPosition, displacement, makeRayParams(session)) == nil
end

local function positionObserved(session, position, records)
	local target = position + Vector3.new(0, 4.5, 0)
	for _, record in ipairs(records) do
		local origin = record.Root.Position + Vector3.new(0, 2.2, 0)
		if clearLine(session, origin, target) then return true end
	end
	return false
end

local function positionBehindPlayers(position, records)
	for _, record in ipairs(records) do
		local offset = Vector3.new(position.X - record.Root.Position.X, 0,
			position.Z - record.Root.Position.Z)
		local look = record.Root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if offset.Magnitude > .05 and forward.Magnitude > .05
			and offset.Unit:Dot(forward.Unit) > .15 then
			return false
		end
	end
	return #records > 0
end

-- ---------------------------------------------------------------------------
-- Room graph
--
-- Spawn placement is measured in ROOM HOPS, not studs. A generated hall is
-- 85-270 studs on a side and one corridor hop spans anywhere from ~110 to ~330
-- studs centre to centre, so a fixed stud band means "two rooms away" on one
-- seed and "same room, far corner" on the next. Hops are also the graph the
-- navigator itself walks -- pressure-door gate included -- so a finite hop
-- count additionally proves the creature can reach the party from there.
-- ---------------------------------------------------------------------------

local SPAWN_PREFERRED_MIN_HOPS = 1
local SPAWN_PREFERRED_MAX_HOPS = 2
-- A hop can still be a short one, so a stud floor backs up the hop rule and
-- keeps the creature out of a player's immediate surroundings.
local SPAWN_MINIMUM_STUD_DISTANCE = 45
-- Last-resort fallback only. It still never uses an occupied room.
local SPAWN_FALLBACK_STUD_DISTANCE = 27

local function hallIndexByPosition(layout, position)
	if typeof(position) ~= "Vector3" or typeof(layout) ~= "table" then return nil, false end
	local nearestIndex, nearestDistance = nil, math.huge
	for arrayIndex, hall in ipairs(layout.Halls or {}) do
		local minX, maxX = tonumber(hall.MinX), tonumber(hall.MaxX)
		local minZ, maxZ = tonumber(hall.MinZ), tonumber(hall.MaxZ)
		if minX and maxX and minZ and maxZ then
			local index = tonumber(hall.Index) or arrayIndex
			if position.X >= minX and position.X <= maxX
				and position.Z >= minZ and position.Z <= maxZ
			then
				return index, true
			end
			local center = hall.Center
			if typeof(center) ~= "Vector3" then
				center = Vector3.new((minX + maxX) * .5, 0, (minZ + maxZ) * .5)
			end
			local distance = horizontalDistance(position, center)
			if distance < nearestDistance then
				nearestDistance = distance
				nearestIndex = index
			end
		end
	end
	-- A player standing inside a corridor is contained by no hall. Charging the
	-- nearest one is the conservative reading: it can only ever REMOVE a room
	-- from the candidate set, never add an unsafe one.
	return nearestIndex, false
end

local function corridorFor(layout, a, b)
	local byPair = layout.CorridorByPair
	if typeof(byPair) == "table" then
		local key = tostring(math.min(a, b)) .. ":" .. tostring(math.max(a, b))
		if typeof(byPair[key]) == "table" then return byPair[key] end
	end
	for _, corridor in ipairs(layout.Corridors or {}) do
		if typeof(corridor) == "table"
			and ((corridor.A == a and corridor.B == b) or (corridor.A == b and corridor.B == a))
		then
			return corridor
		end
	end
	return nil
end

-- Hop distance from one hall to every hall it can actually reach. A closed
-- pressure door is impassable exactly while Level2ExitPowered is unset, which
-- is the same rule the navigator's own graph route obeys.
local function hopDistancesFrom(layout, startIndex)
	local hops = {}
	if typeof(layout) ~= "table" or not startIndex then return hops end
	local exitPowered = workspace:GetAttribute("Level2ExitPowered") == true
	local queue = {startIndex}
	local head = 1
	hops[startIndex] = 0
	while head <= #queue do
		local current = queue[head]
		head += 1
		local hall = layout.Halls and layout.Halls[current]
		for _, raw in ipairs((typeof(hall) == "table" and hall.Connections) or {}) do
			local other = tonumber(raw)
			if other and hops[other] == nil then
				local corridor = corridorFor(layout, current, other)
				local blocked = corridor == nil
					or (corridor.Kind == "PressureDoor" and not exitPowered)
				if not blocked then
					hops[other] = hops[current] + 1
					table.insert(queue, other)
				end
			end
		end
	end
	return hops
end

-- Every anchor part carries Level2_HallId ("Level 2 Hall 07"); the den spawns
-- carry nothing else that names their room, so the attribute is the only
-- handle that works for all three anchor kinds. Position is the fallback.
local function anchorHallIndex(layout, instance, position)
	local hallId = instance:GetAttribute("Level2_HallId")
	if typeof(hallId) == "string" then
		local parsed = tonumber(hallId:match("(%d+)%s*$"))
		if parsed and typeof(layout) == "table"
			and typeof(layout.Halls) == "table" and layout.Halls[parsed] then
			return parsed
		end
	end
	return (hallIndexByPosition(layout, position))
end

local function collectAnchors(manifest)
	local layout = manifest.Layout
	local anchors = {}
	local seen = {}
	local function consider(instance)
		if not (instance and instance:IsA("BasePart")) or seen[instance] then return end
		local name = instance.Name
		local useful = name:find("Level 2 Entity Den ", 1, true) == 1
			or name:find("Level 2 Entity Patrol Node ", 1, true) == 1
			or name:find("Level 2 Navigation Node ", 1, true) == 1
		if not useful then return end
		seen[instance] = true
		local position = instance.Position
		table.insert(anchors, {
			Part = instance,
			Name = name,
			Position = position,
			HallIndex = anchorHallIndex(layout, instance, position),
			IsDen = name:find("Level 2 Entity Den ", 1, true) == 1,
			IsCenter = name:find("Level 2 Navigation Node ", 1, true) == 1
				or name:find("Level 2 Entity Den ", 1, true) == 1,
		})
	end
	local function scan(container)
		if not container then return end
		consider(container)
		for _, descendant in ipairs(container:GetDescendants()) do consider(descendant) end
	end
	scan(manifest.EntityNodes)
	scan(manifest.EntityDen)
	-- The hall-centre nodes live in their own folder. Without this the IsCenter
	-- flag above -- and its scoring bonus -- could only ever match a den part,
	-- and the one anchor guaranteed to sit in open floor in every room was
	-- never a spawn candidate at all.
	scan(manifest.Navigation)
	return anchors
end

local function pumpActivatorPosition(pumpNumber)
	local state = stateFolder()
	if not state then return nil end
	local userId = tonumber(state:GetAttribute("Level2_PumpActivatorUserId" .. tostring(pumpNumber)))
	if userId and userId > 0 then
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then return root.Position end
	end
	local captured = state:GetAttribute("Level2_PumpActivatorPosition" .. tostring(pumpNumber))
	return typeof(captured) == "Vector3" and captured or nil
end

-- One snapshot of where the party is, in rooms. Taken once per selection so a
-- player walking through a doorway cannot be counted in two different rooms by
-- two different candidates within the same decision.
--
-- It carries the RECORDS it was built from. WHAT SHIPPED BROKEN without that:
-- the ranking measured against one party and the commit-time re-check went and
-- fetched its own, and nothing could say which party a decision had been made
-- against. A snapshot that names its own party is what lets the spawn contract
-- below be ONE predicate used at both ends -- the ranking hands it the snapshot
-- it ranked against, and the commit hands it nothing and gets a fresh one.
local function roomContext(session, records)
	local layout = session.Manifest.Layout
	local context = {
		Layout = layout,
		Records = records,
		Roomless = 0,
		Occupied = {},
		PlayerHalls = {},
		HopFromPlayers = {},
		HopToPump = {},
		PumpHallIndex = nil,
	}
	for _, record in ipairs(records) do
		local index = hallIndexByPosition(layout, record.Root.Position)
		if index == nil then
			-- A LIVING player the room graph cannot place at all. Counted rather
			-- than skipped: a party this snapshot cannot fully describe is one the
			-- spawn contract must refuse outright, not one it may quietly measure
			-- against whoever happened to be placeable.
			context.Roomless += 1
		elseif not context.Occupied[index] then
			context.Occupied[index] = true
			table.insert(context.PlayerHalls, index)
		end
	end
	for _, index in ipairs(context.PlayerHalls) do
		for hallIndex, hops in pairs(hopDistancesFrom(layout, index)) do
			local current = context.HopFromPlayers[hallIndex]
			if current == nil or hops < current then
				context.HopFromPlayers[hallIndex] = hops
			end
		end
	end
	return context
end

-- The room the pump that produced this appearance sits in. Pump 2 spawns the
-- creature and pump 3 relocates it, so "the pump room" is whichever one just
-- fired; PumpHalls[n] is the same table object the layout holds in Halls.
local function pumpHallIndex(session, pumpNumber)
	local layout = session.Manifest.Layout
	local pumps = layout and layout.PumpHalls
	local hall = typeof(pumps) == "table" and pumps[pumpNumber] or nil
	if typeof(hall) == "table" and tonumber(hall.Index) then return tonumber(hall.Index) end
	local records = session.Manifest.Pumps
	local record = typeof(records) == "table" and records[pumpNumber] or nil
	local recordHall = typeof(record) == "table" and record.Hall or nil
	if typeof(recordHall) == "table" and tonumber(recordHall.Index) then
		return tonumber(recordHall.Index)
	end
	local activator = pumpActivatorPosition(pumpNumber)
	if typeof(activator) == "Vector3" then
		return (hallIndexByPosition(layout, activator))
	end
	return nil
end

local function applyPumpContext(session, context, pumpNumber)
	context.PumpHallIndex = pumpHallIndex(session, pumpNumber)
	context.HopToPump = context.PumpHallIndex
		and hopDistancesFrom(context.Layout, context.PumpHallIndex) or {}
	return context
end

-- ---------------------------------------------------------------------------
-- THE SPAWN CONTRACT
--
-- One predicate, and the ONLY thing anywhere that decides whether a room may
-- receive the creature. Measured against the party as the given snapshot has
-- it:
--
--   a. the room is EXACTLY 1 or 2 room-graph hops from the NEAREST living
--      player -- never 0, never 3 or more;
--   b. no living player's own room is a candidate -- not the nearest player's,
--      and not a second player's somewhere else entirely;
--   c. it also clears the proximity floor in studs, because one hop can be a
--      short one.
--
-- WHAT SHIPPED BROKEN: there was no such predicate, and the three places that
-- decided validity did not agree.
--
--   * candidateTier DEMOTED an out-of-window room instead of rejecting it. Tier
--     4 meant "hidden, 3+ hops away" and tier 2 meant "3+ hops away", and both
--     outranked tier 1 -- a room inside the window. So a hidden room four rooms
--     off beat a room next door, and the documented "1-2 hops" was a preference
--     the sort could overrule. Pump proximity rides INSIDE a tier, so the tier
--     ladder is exactly what let pump rank reach a room the hop rule excluded.
--   * spawnStillSafe, the commit-time re-check, tested occupancy and studs and
--     NOTHING ELSE. Hop distance was measured once, before a fan of WarpTo and
--     route validations that each take real time, and never again. A player who
--     walked two rooms closer during that window left a candidate that had been
--     2 hops away now sitting next to him, and the re-check could not see it --
--     the room was not one anybody was standing in.
--   * and the pump-three escalation carried a THIRD copy of the room rule
--     ("roomSafe"): occupancy and reachability, with no hop bound at all, so a
--     relocation could put the creature four rooms away where a spawn could not.
--
-- The ranking now ADMITS through this predicate, so nothing it refuses is ever
-- a candidate and no sort key below can promote it back; and the commit RE-ASKS
-- it with no snapshot, which rebuilds one from livingRecords -- the party as it
-- stands at the instant of the commit, not as it stood when the list was built.
--
-- Returns ok, reason, detail. `detail.HallIndex` and `detail.Hops` are the
-- resolved values the ranking then sorts on, so the numbers a candidate carries
-- are the same numbers the contract judged it by.
local function spawnContractHolds(session, candidate, context)
	local detail = {}
	if typeof(candidate) ~= "table" then return false, "no candidate", detail end
	local anchor = candidate.Anchor
	if typeof(anchor) ~= "table" then return false, "candidate names no anchor", detail end
	local position = anchor.Position
	if typeof(position) ~= "Vector3" then return false, "the anchor has no position", detail end
	if anchor.Part and not anchor.Part.Parent then
		return false, "the anchor part has left the world", detail
	end
	if typeof(context) ~= "table" then
		-- A COMMIT. Re-read the party and re-walk the graph; this is the whole
		-- point of the re-check and must never reuse the ranking's snapshot.
		context = roomContext(session, livingRecords(session))
	end
	local hallIndex = candidate.HallIndex
	if hallIndex == nil then hallIndex = (hallIndexByPosition(context.Layout, position)) end
	detail.HallIndex = hallIndex
	local records = context.Records or {}
	if #records == 0 then
		-- Nobody alive to be endangered, and no nearest player to measure hops
		-- from. The contract is vacuous here rather than failed -- every other
		-- gate on the spawn still has to pass.
		return true, "no living player to measure against", detail
	end
	if (context.Roomless or 0) > 0 then
		-- FAIL CLOSED. A living player the room graph cannot place could be
		-- standing anywhere, this room included.
		return false, "a living player belongs to no room", detail
	end
	if hallIndex == nil then return false, "the candidate belongs to no room", detail end
	if context.Occupied[hallIndex] then
		return false, "room " .. tostring(hallIndex) .. " holds a living player", detail
	end
	local hops = context.HopFromPlayers[hallIndex]
	detail.Hops = hops
	if hops == nil then
		return false, "room " .. tostring(hallIndex) .. " is unreachable from the party", detail
	end
	if hops < SPAWN_PREFERRED_MIN_HOPS or hops > SPAWN_PREFERRED_MAX_HOPS then
		return false, string.format("room %s is %d hops from the nearest player, outside"
			.. " the %d-%d window", tostring(hallIndex), hops,
			SPAWN_PREFERRED_MIN_HOPS, SPAWN_PREFERRED_MAX_HOPS), detail
	end
	for _, record in ipairs(records) do
		if horizontalDistance(position, record.Root.Position) < SPAWN_FALLBACK_STUD_DISTANCE then
			return false, string.format("room %s is inside the %d-stud proximity floor",
				tostring(hallIndex), SPAWN_FALLBACK_STUD_DISTANCE), detail
		end
	end
	return true, "unoccupied, inside the hop window, clear of the proximity floor", detail
end

-- RANKING ONLY, and it rejects nothing. Everything that reaches it has already
-- passed the contract above, so its room is unoccupied, its hop count is inside
-- the window and it is past the proximity floor.
--
-- Tiers 4 and 2 are RETIRED, not renumbered: both meant "outside the hop
-- window", which is now a rejection rather than a demotion. 5, 3 and 1 keep the
-- numbers they always published, so Level2_SlidemouthSpawnTier still means what
-- it meant. Tier 1 is the documented last resort -- inside the window, but in
-- the band between the two stud floors.
local function candidateTier(hidden, distance)
	if distance >= SPAWN_MINIMUM_STUD_DISTANCE then
		return hidden and 5 or 3
	end
	return 1
end

local function rankedSpawnCandidates(session, records, recovery, context)
	-- The pump-scream fallback asks for a ranking without having built a room
	-- context. Deriving one here keeps every caller on the same occupancy and
	-- hop rules, and means a missing argument can never throw inside the warning
	-- path and silence the scream.
	if typeof(context) ~= "table" then context = roomContext(session, records) end
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		-- ADMISSION, not preference. A room the contract refuses is not a
		-- candidate at all, so no sort key below -- pump proximity least of all --
		-- can promote it back into the running.
		local admitted, _, detail = spawnContractHolds(session,
			{Anchor = anchor, HallIndex = anchor.HallIndex}, context)
		if admitted then
			local hallIndex = detail.HallIndex
			local distance = math.huge
			for _, record in ipairs(records) do
				distance = math.min(distance, horizontalDistance(anchor.Position, record.Root.Position))
			end
			-- With nobody alive there is no room to be too close to, and no hop
			-- count either; treat the whole map as available.
			local empty = #records == 0
			if empty then distance = 185 end
			-- The hop count the CONTRACT judged it by, never a second reading of
			-- the same graph: a candidate must sort on the number it was admitted
			-- on. With nobody alive there is no such number, and the whole map
			-- ranks as if it were at the far end of the window.
			local hops = empty and SPAWN_PREFERRED_MAX_HOPS or detail.Hops
			local hidden = not positionObserved(session, anchor.Position, records)
			local tier = candidateTier(hidden, distance)
			local pumpHops = hallIndex and context.HopToPump[hallIndex] or nil
			table.insert(candidates, {
				Anchor = anchor,
				HallIndex = hallIndex,
				Distance = distance,
				Hidden = hidden,
				Hops = hops,
				PumpHops = pumpHops,
				Tier = tier,
				-- Sort keys, cheapest comparison first.
				PumpRank = pumpHops or math.huge,
				HopBias = math.abs(hops - SPAWN_PREFERRED_MAX_HOPS),
				Bonus = (anchor.IsCenter and 2 or 0) + (anchor.IsDen and 1 or 0),
			})
		end
	end
	table.sort(candidates, function(a, b)
		if a.Tier ~= b.Tier then return a.Tier > b.Tier end
		-- Closest to the pump room, measured in rooms.
		if a.PumpRank ~= b.PumpRank then return a.PumpRank < b.PumpRank end
		-- Then the safer end of the 1-2 room window.
		if a.HopBias ~= b.HopBias then return a.HopBias < b.HopBias end
		if a.Bonus ~= b.Bonus then return a.Bonus > b.Bonus end
		if a.Distance ~= b.Distance then return a.Distance > b.Distance end
		return a.Anchor.Name < b.Anchor.Name
	end)
	if recovery then
		-- A mid-round unstick wants the NEAREST safe room, not the one closest
		-- to a pump; every other rule above still applies.
		table.sort(candidates, function(a, b)
			if a.Tier ~= b.Tier then return a.Tier > b.Tier end
			if a.Distance ~= b.Distance then return a.Distance < b.Distance end
			return a.Anchor.Name < b.Anchor.Name
		end)
	end
	return candidates
end

local function facingTowardNearest(position, records)
	local bestDirection
	local bestDistance = math.huge
	for _, record in ipairs(records) do
		local direction = record.Root.Position - position
		local distance = horizontalDistance(record.Root.Position, position)
		if distance < bestDistance then
			bestDirection = direction
			bestDistance = distance
		end
	end
	return bestDirection or Vector3.new(0, 0, -1)
end

local function nearestRecord(position, records)
	local best
	local bestDistance = math.huge
	for _, record in ipairs(records) do
		local distance = horizontalDistance(position, record.Root.Position)
		if distance < bestDistance then
			best = record
			bestDistance = distance
		end
	end
	return best, bestDistance
end

local function setModelAndShared(session, name, value)
	publish(name, value)
	if session.Model and session.Model.Parent then
		session.Model:SetAttribute(name, value)
	end
end

local function setState(session, value)
	if session.State == value then return end
	session.State = value
	setModelAndShared(session, "Level2_SlidemouthState", value)
end

local function clearOwnedChaseMarker(player)
	if player and player.Parent == Players and player:GetAttribute("Level2_SlidemouthChased") == true then
		player:SetAttribute("Level2_SlidemouthChased", nil)
		player:SetAttribute("BeingChased", false)
	end
end

local function setTarget(session, player)
	if session.Target == player then return end
	clearOwnedChaseMarker(session.Target)
	session.Target = player
	if player and player.Parent == Players then
		player:SetAttribute("Level2_SlidemouthChased", true)
		player:SetAttribute("BeingChased", true)
	end
	local userId = player and player.UserId or 0
	setModelAndShared(session, "Level2_SlidemouthTargetUserId", userId)
end

local function cloneModel(session)
	local model = session.Template:Clone()
	if not model:IsA("Model") then
		model:Destroy()
		return nil, "template is not a Model"
	end
	model:ScaleTo(model:GetScale() * MODEL_SCALE)
	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("MeshPart", true)
		or model:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		model:Destroy()
		return nil, "template has no BasePart"
	end
	model.Name = MODEL_NAME
	model.PrimaryPart = primary
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
	model:SetAttribute("Level2_Generation", session.Generation)
	model:SetAttribute("Level2_SlidemouthActive", true)
	model:SetAttribute("Level2_SlidemouthState", "SPAWNING")
	model:SetAttribute("Level2_SlidemouthSpeed", 0)
	model:SetAttribute("Level2_SlidemouthMoving", false)
	model:SetAttribute("Level2_SlidemouthScreamSerial", 0)
	model:SetAttribute("Level2_SlidemouthScreamKind", "")
	model:SetAttribute("Level2_SlidemouthTargetUserId", 0)
	model:SetAttribute("Level2_SlidemouthAnimationStartedAt", workspace:GetServerTimeNow())
	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
	model.Parent = session.RuntimeFolder
	CollectionService:AddTag(model, "Level2HostileEntity")
	CollectionService:AddTag(model, "Level2SlidemouthEntity")
	return model
end

-- The commit-time re-check is spawnContractHolds(session, candidate) with NO
-- snapshot: it rebuilds one from livingRecords, so it is measured against where
-- the party is standing at the instant of the commit.
--
-- WHAT SHIPPED BROKEN, and why there is no longer a second function here:
-- `spawnStillSafe` was a SEPARATE, WEAKER rule than the one the ranking used.
-- It re-tested two of the three things that make a room valid -- is anybody
-- standing in it, is anybody within the stud floor -- and never re-measured hop
-- distance at all. A party that closed two rooms of graph distance during the
-- validation fan therefore passed it: nobody was standing in the candidate's
-- room, nobody was inside 27 studs of the anchor, and the creature was
-- committed to a room that was now adjacent-of-adjacent to nothing, or 0 hops
-- from a player who had walked around the corner. Two rules, one of which was
-- the real one, is how a contract rots; there is now exactly one.
local function spawnHasEscapeClearance(navigator, facing)
	-- WarpTo validates the resting volume. Probe a small fan in the intended
	-- direction too; corridor nodes legitimately have two exits, not four.
	local foot = navigator:GetPosition()
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	local forwardClear = flatFacing.Magnitude <= .01
	if flatFacing.Magnitude > .01 then
		for _, angle in ipairs({0, math.rad(38), math.rad(-38)}) do
			local direction = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(flatFacing.Unit)
			if navigator:_clearAdvance(foot + direction * 1.5) then
				forwardClear = true
				break
			end
		end
	end
	if not forwardClear then return false end
	local clearCardinals = 0
	for _, direction in ipairs({
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}) do
		if navigator:_clearAdvance(foot + direction * 1.5) then clearCardinals += 1 end
	end
	return clearCardinals >= 2
end

local function spawnEntity(session)
	local records = livingRecords(session)
	if #session.Anchors == 0 then return nil, "no Level 2 entity navigation anchors" end
	local context = applyPumpContext(session, roomContext(session, records), SPAWN_PUMPS)
	local candidates = rankedSpawnCandidates(session, records, false, context)

	if #candidates == 0 then
		-- Nothing on the map satisfies the contract: every room either holds a
		-- player, sits outside the 1-2 hop window, cannot be reached from the
		-- party at all, or stands inside the proximity floor. The heartbeat re-runs
		-- this in two seconds. WAITING IS THE ANSWER -- there is deliberately no
		-- branch below that widens the window, drops the room rule or takes the
		-- best of a bad set as a consolation prize.
		return nil, "no room satisfies the spawn contract yet"
	end
	local model, modelError = cloneModel(session)
	if not model then return nil, modelError end
	local navigator = Navigator.new(model, session.Manifest, MOVEMENT, {
		RuntimeFolder = session.RuntimeFolder,
		ObstacleExclusions = session.Manifest.BuoyantProps
			and {session.Manifest.BuoyantProps} or nil,
	})
	local chosen
	local fallback
	for candidateIndex, candidate in ipairs(candidates) do
		if candidateIndex > 16 then break end
		local facing = facingTowardNearest(candidate.Anchor.Position, records)
		if navigator:WarpTo(candidate.Anchor.Position, facing, true) then
			local routeValid = true
			local nearest = nearestRecord(candidate.Anchor.Position, records)
			if nearest then
				local _, routeStatus = navigator:_fallbackWaypoints(nearest.Root.Position)
				routeValid = routeStatus ~= "NO_PATH"
			end
			if routeValid then
				-- Clearance is measured BEFORE the live safety re-check, so that
				-- re-check is the very last thing between a fully validated
				-- candidate and the commit. Everything physical about this anchor
				-- has now passed: it can hold the body, a route to the nearest
				-- player exists, and there is room to leave it.
				local clearance = spawnHasEscapeClearance(navigator, facing)

				-- Studio-only test seam, fired in the ONLY window the commit-time
				-- contract exists to close. Placing it earlier -- which an earlier version
				-- did -- let the candidate the suite mutated against fail a later
				-- physical check on its own, so the test could pass without the
				-- re-check doing anything. Here the candidate is one call away from
				-- being committed, and a suite that moves a player onto it is
				-- measuring exactly the revalidation. In a live game
				-- Controller._spawnInterlude is nil and this costs one comparison.
				if RunService:IsStudio() and Controller._spawnInterlude then
					local interludeOk, interludeError = pcall(Controller._spawnInterlude, {
						Session = session,
						Candidate = candidate,
						CandidateIndex = candidateIndex,
						Candidates = candidates,
						Context = context,
						Records = records,
						Clearance = clearance,
						Facing = facing,
					})
					if not interludeOk then
						warn("[Slidemouth] spawn interlude failed: " .. tostring(interludeError))
					end
				end

				-- THE COMMIT. No snapshot argument: the contract rebuilds the party
				-- from livingRecords right here, so a candidate ranked before this
				-- loop's yields is re-proved against the party as it stands now.
				if spawnContractHolds(session, candidate) then
					fallback = fallback or candidate
					if clearance then
						chosen = candidate
						break
					end
				end
			end
		end
	end
	-- The clearance-less fallback is re-proved from scratch as well: it was
	-- validated earlier in the same loop, and the party has had every remaining
	-- candidate's worth of yields to move since.
	if not chosen and fallback and spawnContractHolds(session, fallback) then
		local facing = facingTowardNearest(fallback.Anchor.Position, records)
		if navigator:WarpTo(fallback.Anchor.Position, facing, true) then chosen = fallback end
	end
	if not chosen then
		navigator:Destroy()
		model:Destroy()
		return nil, "no spawn anchor has enough validated floor and body clearance"
	end
	session.Model = model
	session.Navigator = navigator
	session.Spawned = true
	session.CurrentSpeed = 0
	session.LastPosition = navigator:GetPosition()
	session.ProgressPosition = navigator:GetPosition()
	session.ProgressGoalDistance = math.huge
	session.ProgressAt = os.clock()
	session.RecoveryStage = 0
	session.SpawnRetryAt = math.huge
	setState(session, "HUNTING")
	setModelAndShared(session, "Level2_SlidemouthActive", true)
	setModelAndShared(session, "Level2_SlidemouthGeneration", session.Generation)
	session.SpawnChoice = chosen
	setModelAndShared(session, "Level2_SlidemouthSpawnDistance", chosen.Distance)
	setModelAndShared(session, "Level2_SlidemouthSpawnHidden", chosen.Hidden)
	setModelAndShared(session, "Level2_SlidemouthSpawnAnchor", chosen.Anchor.Name)
	setModelAndShared(session, "Level2_SlidemouthSpawnHall", chosen.HallIndex or 0)
	setModelAndShared(session, "Level2_SlidemouthSpawnPlayerHops", chosen.Hops or -1)
	setModelAndShared(session, "Level2_SlidemouthSpawnPumpHops", chosen.PumpHops or -1)
	setModelAndShared(session, "Level2_SlidemouthSpawnPumpHall", context.PumpHallIndex or 0)
	setModelAndShared(session, "Level2_SlidemouthSpawnTier", chosen.Tier)
	return true
end

local function chooseTarget(session, now)
	local records = livingRecords(session)
	local position = session.Navigator and session.Navigator:GetPosition()
	local currentRecord
	for _, record in ipairs(records) do
		if record.Player == session.Target then currentRecord = record break end
	end

	-- Nearby players in one hall behave as a group. The group attracts
	-- Slidemouth, but its actual goal remains a real player on valid ground.
	local remaining = {}
	for index = 1, #records do remaining[index] = true end
	local bestRecord
	local bestScore = math.huge
	for seed = 1, #records do
		if not remaining[seed] then continue end
		local group = {}
		local queue = {seed}
		remaining[seed] = nil
		local head = 1
		while head <= #queue do
			local index = queue[head]
			head += 1
			local member = records[index]
			table.insert(group, member)
			local memberHall = session.Navigator:FindHall(member.Root.Position)
			local memberHallId = memberHall and (memberHall.Index or memberHall.Id)
			for candidateIndex, available in pairs(remaining) do
				if available then
					local candidate = records[candidateIndex]
					local candidateHall = session.Navigator:FindHall(candidate.Root.Position)
					local candidateHallId = candidateHall and (candidateHall.Index or candidateHall.Id)
					if tostring(candidateHallId) == tostring(memberHallId)
						and horizontalDistance(member.Root.Position, candidate.Root.Position) <= 70 then
						remaining[candidateIndex] = nil
						table.insert(queue, candidateIndex)
					end
				end
			end
		end

		local centroid = Vector3.zero
		for _, member in ipairs(group) do centroid += member.Root.Position end
		centroid /= #group
		local representative
		local representativeDistance = math.huge
		local closeToGroup = position and horizontalDistance(position, centroid) <= 45
		for _, member in ipairs(group) do
			local distance = horizontalDistance(closeToGroup and position or centroid, member.Root.Position)
			if distance < representativeDistance then
				representative = member
				representativeDistance = distance
			end
		end
		local score = (position and horizontalDistance(position, centroid) or math.huge)
			- math.min(54, (#group - 1) * 18)
		if score < bestScore then
			bestScore = score
			bestRecord = representative
		end
	end

	if currentRecord then
		local currentDistance = horizontalDistance(position, currentRecord.Root.Position)
		local bestDistance = bestRecord and horizontalDistance(position, bestRecord.Root.Position) or math.huge
		if now < session.NextTargetSwitchAt
			or not bestRecord
			or bestRecord.Player == currentRecord.Player
			or bestDistance + 25 >= currentDistance then
			return currentRecord
		end
	end
	local nextPlayer = bestRecord and bestRecord.Player or nil
	if nextPlayer ~= session.Target then
		setTarget(session, nextPlayer)
		session.NextTargetSwitchAt = now + 1
	end
	return bestRecord
end

local function currentTargetRecord(session)
	return session.Target and livingRecord(session, session.Target) or nil
end

local function mouthAttachment(session)
	local model = session.Model
	if not model then return nil end
	local attachment = model:FindFirstChild("SlidemouthAudioEmitter", true)
	return attachment and attachment:IsA("Attachment") and attachment or nil
end

local function tryAttack(session, record, now)
	if now < session.AttackCooldownUntil then return false end
	local mouth = mouthAttachment(session)
	if not mouth then return false end
	local displacement = record.Root.Position - mouth.WorldPosition
	if displacement.Magnitude > ATTACK_DISTANCE then return false end
	local flat = Vector3.new(displacement.X, 0, displacement.Z)
	if flat.Magnitude > .05 then
		local facing = session.Navigator:GetFacing()
		if facing:Dot(flat.Unit) < -.15 then return false end
	end
	if not clearLine(session, mouth.WorldPosition, record.Root.Position) then return false end
	setState(session, "ATTACK")
	session.Navigator:Face(record.Root.Position)
	record.Humanoid.Health = 0
	session.AttackCooldownUntil = now + ATTACK_COOLDOWN
	setTarget(session, nil)
	return true
end

-- A recovery anchor is a GOAL to walk to, never a place to appear at. Every
-- candidate must therefore have a real route from where the creature is now.
local function recoveryAnchor(session, records, requireHidden, exclude)
	local current = session.Navigator:GetPosition()
	local context = roomContext(session, records)
	local best
	local bestDistance = math.huge
	for _, candidate in ipairs(rankedSpawnCandidates(session, records, true, context)) do
		local distance = horizontalDistance(current, candidate.Anchor.Position)
		local direction = candidate.Anchor.Position - current
		local escapeClear = direction.Magnitude > .01
			and session.Navigator:_clearAdvance(current + direction.Unit * 1.5)
		local _, routeStatus = session.Navigator:_fallbackWaypoints(candidate.Anchor.Position)
		if distance >= 16 and distance <= 180
			and escapeClear
			and routeStatus ~= "NO_PATH"
			and (not requireHidden or candidate.Hidden)
			and not (exclude and exclude[candidate.Anchor.Part])
			and distance < bestDistance then
			best = candidate
			bestDistance = distance
		end
	end
	return best
end

local function updateWatchdog(session, record, now)
	local snapshot = session.Navigator:GetDebugSnapshot()
	local position = session.Navigator:GetPosition()
	local goal = session.Navigator:GetGoal()
	local goalDistance = goal and horizontalDistance(position, goal) or math.huge
	if snapshot.Computing then
		local requestStartedAt = snapshot.RequestStartedAt
		if finiteNumber(requestStartedAt)
			and now - requestStartedAt < PATH_REQUEST_SETTLE_SECONDS then
			-- Planning is not physical stuck time. Refresh the movement baseline so
			-- a valid request that lands after several yields gets a fresh progress
			-- window instead of being cancelled on its very first walking frame.
			session.ProgressPosition = position
			session.ProgressGoalDistance = goalDistance
			session.ProgressAt = now
			return
		end
	end
	if now - session.ProgressAt < PROGRESS_WINDOW then return end
	local travel = horizontalDistance(position, session.ProgressPosition)
	local goalProgress = finiteNumber(session.ProgressGoalDistance)
		and finiteNumber(goalDistance) and session.ProgressGoalDistance - goalDistance or 0
	-- A valid graph route can initially move sideways—or even away from the
	-- player's straight-line distance—to clear a hall or doorway. Net travel is
	-- therefore sufficient progress; requiring goalProgress >= 0 caused a forced
	-- route reversal every PROGRESS_WINDOW seconds.
	local expected = math.max(1.5, session.CurrentSpeed * (now - session.ProgressAt) * .3)
	if travel >= expected or goalProgress >= .8 or not record then
		session.RecoveryStage = 0
		session.RecoveryGoal = nil
		session.RecoveryGoalPart = nil
		session.RecoveryUntil = 0
		session.GraphRecoveryUntil = 0
		session.FailedRecoveryAnchors = nil
	else
		session.RecoveryStage += 1
		if session.RecoveryStage == 1 and goal then
			session.GraphRecoveryUntil = now + 1.5
			session.Navigator:SetGraphGoal(goal, true)
		elseif session.RecoveryStage == 2 then
			session.GraphRecoveryUntil = 0
			local candidate = recoveryAnchor(session, livingRecords(session), false,
				session.FailedRecoveryAnchors)
			if candidate then
				session.RecoveryGoal = candidate.Anchor.Position
				session.RecoveryGoalPart = candidate.Anchor.Part
				session.RecoveryUntil = now + 2
				session.Navigator:SetGoal(session.RecoveryGoal, true)
			else
				session.Navigator:SetGraphGoal(record.Root.Position, true)
			end
		else
			-- Stage 3+. The creature is wedged: the route it was following cannot
			-- be walked from where it stands. It backs out along ground it has
			-- already stood on -- a bounded, re-validated WALK, not a teleport --
			-- and then replans to a DIFFERENT anchor than the one that failed.
			-- The previous behaviour warped up to 180 studs to a hidden anchor,
			-- which crossed walls and everything between.
			local records = livingRecords(session)
			local retreated = session.Navigator:Retreat(RECOVERY_RETREAT_STUDS)
			session.RecoveryRetreats = (session.RecoveryRetreats or 0) + 1
			setModelAndShared(session, "Level2_SlidemouthRetreatStuds", retreated)
			session.FailedRecoveryAnchors = session.FailedRecoveryAnchors or {}
			if session.RecoveryGoalPart then
				session.FailedRecoveryAnchors[session.RecoveryGoalPart] = true
			end
			local candidate = recoveryAnchor(session, records, true,
				session.FailedRecoveryAnchors)
				or recoveryAnchor(session, records, false, session.FailedRecoveryAnchors)
			if candidate then
				session.RecoveryGoal = candidate.Anchor.Position
				session.RecoveryGoalPart = candidate.Anchor.Part
				session.RecoveryUntil = now + 3
				session.Navigator:SetGraphGoal(session.RecoveryGoal, true)
				session.RecoveryStage = 1
			else
				-- Nothing else to aim at. Keep working the target through the
				-- deterministic hall graph rather than giving up the chase.
				session.FailedRecoveryAnchors = {}
				session.RecoveryStage = 1
				if goal then session.Navigator:SetGraphGoal(goal, true) end
			end
		end
	end
	session.ProgressPosition = session.Navigator:GetPosition()
	session.ProgressGoalDistance = session.Navigator:GetGoal()
		and horizontalDistance(session.ProgressPosition, session.Navigator:GetGoal()) or math.huge
	session.ProgressAt = now
end

local function minimumPlayerDistance(position, records)
	local minimum = math.huge
	for _, record in ipairs(records) do
		minimum = math.min(minimum, horizontalDistance(position, record.Root.Position))
	end
	return minimum
end

local function chooseHiddenAnchor(session, records, minimumDistance, maximumDistance, idealDistance)
	local best
	local bestScore = -math.huge
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent then
			local distance = minimumPlayerDistance(anchor.Position, records)
			if distance == math.huge then distance = idealDistance end
			if distance >= minimumDistance and distance <= maximumDistance
				and not positionObserved(session, anchor.Position, records) then
				local score = -math.abs(distance - idealDistance)
				if anchor.IsCenter then score += 12 end
				if score > bestScore then
					best = {Anchor = anchor, Distance = distance, Hidden = true}
					bestScore = score
				end
			end
		end
	end
	return best
end

local function choosePumpScreamPosition(session)
	local records = livingRecords(session)
	local chosen = chooseHiddenAnchor(session, records, 85, 160, 120)
		or chooseHiddenAnchor(session, records, 45, 240, 120)
	if not chosen then
		local ranked = rankedSpawnCandidates(session, records, true)
		chosen = ranked[1]
	end
	return chosen and chosen.Anchor.Position + Vector3.new(0, 4.5, 0)
		or (records[1] and records[1].Root.Position + Vector3.new(0, 5, -120))
		or Vector3.new(0, 5, 0)
end

local function publishPositionalPumpScream(session, pumpNumber, position)
	session.WarningSerial += 1
	publish("Level2_SlidemouthWarningPosition", position)
	publish("Level2_SlidemouthWarningPump", pumpNumber)
	publish("Level2_SlidemouthScreamBusyUntil", workspace:GetServerTimeNow() + 14)
	-- Serial is deliberately last so clients see the completed event payload.
	publish("Level2_SlidemouthWarningSerial", session.WarningSerial)
end

local function forceMouthScream(session, pumpNumber)
	if not (session.Model and session.Model.Parent) then return false end
	local mouth = mouthAttachment(session)
	local position = mouth and mouth.WorldPosition
		or (session.Model.PrimaryPart and session.Model.PrimaryPart.Position)
		or session.Model:GetPivot().Position
	session.ScreamSerial += 1
	setModelAndShared(session, "Level2_SlidemouthScreamKind", "PUMP_" .. tostring(pumpNumber))
	publish("Level2_SlidemouthScreamPosition", position)
	publish("Level2_SlidemouthScreamBusyUntil", workspace:GetServerTimeNow() + 14)
	setModelAndShared(session, "Level2_SlidemouthScreamSerial", session.ScreamSerial)
	return true
end

local function schedulePumpScream(session, pumpNumber)
	if session.PumpScreamScheduled[pumpNumber] then return end
	local state = stateFolder()
	local startedAt = state
		and tonumber(state:GetAttribute("Level2_PumpStartedAt" .. tostring(pumpNumber))) or nil
	if not finiteNumber(startedAt) or startedAt <= 0 then
		startedAt = workspace:GetServerTimeNow()
	end
	local groanDelay = pumpNumber == 1 and PUMP_ONE_GROAN_DELAY or SPAWN_GROAN_DELAY
	local dueAt = startedAt + groanDelay
	session.PumpScreamScheduled[pumpNumber] = dueAt
	local capturedPosition = pumpNumber == 1 and choosePumpScreamPosition(session) or nil
	task.spawn(function()
		-- Poll rather than sleep the whole delay in one go. The old form waited
		-- once and then tested activeSession; a suspend during that wait made
		-- the test fail, and the job returned WITHOUT clearing
		-- PumpScreamScheduled -- so the scream was neither played nor ever
		-- rearmed. Re-reading the due time each tick is also what lets a resume
		-- shift the deadline and keep the REMAINING delay intact.
		--
		-- THIS JOB DELIBERATELY CARRIES NO RUN TOKEN. It is the one piece of
		-- deferred work that MUST survive a borrow and fire exactly once after the
		-- resume, at its preserved remaining delay, so it waits the PAUSED phase out
		-- instead of cancelling on it. Everything it writes when it finally fires is
		-- re-gated on sessionAlive()/roundReady()/Level2Pumps below, so a session
		-- that was stopped rather than paused still writes nothing.
		while true do
			if session.Phase == "STOPPED" then return end
			if session.Phase == "PAUSED" then
				task.wait(0.1)
			else
				local due = tonumber(session.PumpScreamScheduled[pumpNumber]) or dueAt
				local remaining = due - workspace:GetServerTimeNow()
				if remaining <= 0 then break end
				task.wait(math.min(remaining, 0.1))
			end
		end
		if not sessionAlive(session) or not roundReady(session)
			or (tonumber(workspace:GetAttribute("Level2Pumps")) or 0) < pumpNumber
			or session.PumpScreamPlayed[pumpNumber] then
			return
		end
		session.PumpScreamPlayed[pumpNumber] = true
		session.PumpScreamFired[pumpNumber] = (session.PumpScreamFired[pumpNumber] or 0) + 1
		if pumpNumber >= SPAWN_PUMPS and forceMouthScream(session, pumpNumber) then return end
		publishPositionalPumpScream(
			session,
			pumpNumber,
			capturedPosition or choosePumpScreamPosition(session)
		)
	end)
end

-- `runToken` is the escalation job's cancellation token (see bumpRunToken). It
-- is OPTIONAL only so the synchronous pump-two path may omit it; the pump-three
-- job always passes one, because every WarpTo and every _fallbackWaypoints call
-- below yields, and a borrow landing in one of those yields used to leave this
-- function happily warping a PARKED creature.
local function relocateForThirdPump(session, runToken)
	if not (session.Navigator and session.Model and session.Model.Parent) then return false end
	if runToken ~= nil and not runTokenCurrent(session, runToken) then return false end
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "SCANNING")
	local records = livingRecords(session)
	if #records == 0 then return false end
	local current = session.Navigator:GetPosition()
	local currentFacing = session.Navigator:GetFacing()
	local context = roomContext(session, records)
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		-- An escalation is a re-placement -- the creature APPEARS somewhere new --
		-- so it goes through the spawn contract itself, not through a local
		-- paraphrase of it. WHAT SHIPPED BROKEN: the paraphrase that stood here
		-- checked occupancy and reachability with no hop bound at all, so pump
		-- three could legally relocate the creature four rooms away, which is a
		-- placement the spawn path would have refused outright.
		local hallIndex = anchor.HallIndex
		local roomSafe = spawnContractHolds(session,
			{Anchor = anchor, HallIndex = hallIndex}, context)
		if roomSafe and horizontalDistance(current, anchor.Position) >= 25 then
			local distance = minimumPlayerDistance(anchor.Position, records)
			local hiddenByGeometry = not positionObserved(session, anchor.Position, records)
			local behindPlayers = positionBehindPlayers(anchor.Position, records)
			-- Prefer a close out-of-view anchor. If hall spacing leaves no anchor
			-- inside 170 studs, a geometry-hidden fallback may reach 260 studs.
			local eligible = distance >= 45
				and ((distance <= 170 and (hiddenByGeometry or behindPlayers))
					or (distance <= 260 and hiddenByGeometry))
			if eligible then
				table.insert(candidates, {
					Anchor = anchor,
					HallIndex = hallIndex,
					Distance = distance,
					Score = -math.abs(distance - 78) * 20
						+ (hiddenByGeometry and 600 or 0)
						+ (behindPlayers and 300 or 0)
						+ (anchor.IsCenter and 20 or 0),
				})
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Score > b.Score end)
	setModelAndShared(session, "Level2_SlidemouthEscalationCandidates", #candidates)
	for candidateIndex, candidate in ipairs(candidates) do
		if candidateIndex > 3 then break end
		-- CHECKPOINT, once per candidate. WarpTo and _fallbackWaypoints both yield,
		-- so this loop is where a borrow is most likely to land, and every branch
		-- below it writes to the session. A cancelled escalation stops HERE rather
		-- than at the bottom, so it never reaches the WarpTo(current, currentFacing)
		-- fallback either -- putting a parked creature "back" would move a model the
		-- pause handle has already pinned to a recorded pivot.
		if runToken ~= nil and not runTokenCurrent(session, runToken) then return false end
		setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "VALIDATING_" .. candidateIndex)
		local facing = facingTowardNearest(candidate.Anchor.Position, records)
		-- WarpTo already validates the complete 16-by-11-stud body volume.
		-- The stricter spawn fan is useful for the first appearance, but here it
		-- rejected safe near-player patrol nodes and defeated the escalation.
		-- Commit-time revalidation, the same one the first appearance runs: no
		-- snapshot, so the party is re-read here rather than reused from the scan
		-- above, which every WarpTo and every _fallbackWaypoints since has had
		-- time to invalidate.
		if spawnContractHolds(session, candidate)
			and session.Navigator:WarpTo(candidate.Anchor.Position, facing, true) then
			local nearest = nearestRecord(candidate.Anchor.Position, records)
			local routeStatus = "NO_PATH"
			if nearest then
				local _
				_, routeStatus = session.Navigator:_fallbackWaypoints(nearest.Root.Position)
			end
			if routeStatus ~= "NO_PATH" then
				session.ProgressPosition = session.Navigator:GetPosition()
				session.ProgressGoalDistance = math.huge
				session.ProgressAt = os.clock()
				session.RecoveryStage = 0
				session.RecoveryGoal = nil
				session.RecoveryGoalPart = nil
				session.FailedRecoveryAnchors = nil
				session.RecoveryUntil = 0
				setModelAndShared(session, "Level2_SlidemouthEscalationDistance", candidate.Distance)
				setModelAndShared(session, "Level2_SlidemouthEscalationAnchor", candidate.Anchor.Name)
				setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "RELOCATED")
				return true
			end
		end
	end
	session.Navigator:WarpTo(current, currentFacing, true)
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "KEPT_POSITION")
	return false
end

local function chooseWanderGoal(session)
	local current = session.Navigator:GetPosition()
	local currentHall = session.Navigator:FindHall(current)
	local currentHallId = currentHall and (currentHall.Index or currentHall.Id)
	local candidates = {}
	for _, anchor in ipairs(session.Anchors) do
		if anchor.Part.Parent and anchor.Name ~= session.LastWanderAnchor then
			local distance = horizontalDistance(current, anchor.Position)
			local anchorHall = session.Navigator:FindHall(anchor.Position)
			local anchorHallId = anchorHall and (anchorHall.Index or anchorHall.Id)
			local _, routeStatus = session.Navigator:_fallbackWaypoints(anchor.Position)
			if distance >= 70 and distance <= 280 and routeStatus ~= "NO_PATH" then
				local differentHall = tostring(anchorHallId) ~= tostring(currentHallId)
				table.insert(candidates, {
					Anchor = anchor,
					Score = (differentHall and 1000 or 0)
						- math.abs(distance - 150) + session.Random:NextNumber(0, 25),
				})
			end
		end
	end
	table.sort(candidates, function(a, b) return a.Score > b.Score end)
	return candidates[1] and candidates[1].Anchor or nil
end

local function updateWander(session, now, dt)
	setState(session, "WANDER")
	local position = session.Navigator:GetPosition()
	local needsGoal = not session.WanderGoal
		or now >= session.WanderGoalUntil
		or horizontalDistance(position, session.WanderGoal) <= MOVEMENT.WaypointArrivalDistance + 1
		or (session.Navigator:GetStatus() == "BLOCKED" and now >= session.WanderMoveDeadline)
		or session.Navigator:GetStatus() == "NO_FLOOR"
		or session.Navigator:GetStatus() == "NO_PATH"
	if needsGoal then
		local anchor = chooseWanderGoal(session)
		if anchor then
			session.WanderGoal = anchor.Position
			session.WanderGoalUntil = now + session.Random:NextNumber(8, 13)
			session.WanderMoveDeadline = now + 1
			session.LastWanderAnchor = anchor.Name
			session.Navigator:SetGoal(session.WanderGoal, true)
		else
			session.WanderGoal = nil
			session.Navigator:Stop()
		end
	end
	local before = session.Navigator:GetPosition()
	if session.WanderGoal then
		session.Navigator:SetGoal(session.WanderGoal)
		session.Navigator:Step(math.min(dt, .1), session.CurrentSpeed)
	end
	local moved = horizontalDistance(before, session.Navigator:GetPosition()) > .01
	if moved then session.WanderMoveDeadline = now + 1 end
	setModelAndShared(session, "Level2_SlidemouthMoving", moved)
	setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
	setModelAndShared(session, "Level2_SlidemouthPathStatus", session.Navigator:GetStatus())
end

-- `runToken` is OPTIONAL: the pump-one and pump-two edges run SYNCHRONOUSLY
-- inside the heartbeat, which already refuses to run at all unless the session
-- is RUNNING, so they pass nothing. The pump-three edge is task.spawn'ed and
-- passes its captured token, and every yielding step below is fenced by a
-- checkpoint against it.
--
-- WHAT SHIPPED BROKEN: there were no checkpoints. spawnEntity, the relocation
-- and its ComputeAsync all yield, and a DebugPauseSession landing in any of
-- those yields did not stop this function -- it went on to spawn a creature
-- into, and republish four escalation attributes onto, a session whose entire
-- attribute surface the pause handle was holding for return.
--
-- A cancelled transition is reported as `false, "cancelled: ..."`. The caller
-- distinguishes it from a real failure by re-testing the token itself, so a
-- cancellation warns about nothing and publishes nothing.
local function processPumpTransition(session, pumpNumber, runToken)
	if pumpNumber == 1 then return true end
	if runToken ~= nil and not runTokenCurrent(session, runToken) then
		return false, "cancelled: the session left RUNNING"
	end
	if not session.Spawned then
		local ok, failure = spawnEntity(session)
		if not ok then return false, failure end
	end
	if pumpNumber >= FAST_PUMPS then
		-- Re-read AFTER spawnEntity, which yields.
		if runToken ~= nil and not runTokenCurrent(session, runToken) then
			return false, "cancelled: the session left RUNNING"
		end
		local relocated, relocationResult = pcall(relocateForThirdPump, session, runToken)
		if not relocated then
			-- The ERROR publish is a mutation like any other, so it is fenced too:
			-- a relocation that yielded, got parked, and then threw must not paint
			-- ERROR onto a borrower's state folder.
			warn("[Level 2 Slidemouth] escalation relocation failed: " .. tostring(relocationResult))
			if runToken == nil or runTokenCurrent(session, runToken) then
				setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "ERROR")
			end
		end
	end
	if runToken ~= nil and not runTokenCurrent(session, runToken) then
		return false, "cancelled: the session left RUNNING"
	end
	setModelAndShared(session, "Level2_SlidemouthEscalationPhase",
		pumpNumber >= FAST_PUMPS and "SCREAMED" or "PUMP_2_SCREAMED")
	return true
end

local function updateEntity(session, dt)
	local now = os.clock()
	local pumps = tonumber(workspace:GetAttribute("Level2Pumps")) or 0
	local desiredSpeed = pumps >= FAST_PUMPS and PUMP_THREE_SPEED or PUMP_TWO_SPEED
	local difference = desiredSpeed - session.CurrentSpeed
	local rate = difference >= 0 and ACCELERATION or DECELERATION
	session.CurrentSpeed += math.clamp(difference, -rate * dt, rate * dt)
	if session.Escalating then
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
		setModelAndShared(session, "Level2_SlidemouthPumps", pumps)
		return
	end

	if now >= session.NextTargetRefreshAt then
		chooseTarget(session, now)
		session.NextTargetRefreshAt = now + TARGET_REFRESH
	end
	local record = currentTargetRecord(session)
	if not record then
		setTarget(session, nil)
		updateWander(session, now, dt)
		return
	end
	session.WanderGoal = nil
	setState(session, "CHASE")
	if tryAttack(session, record, now) then return end

	local targetPosition = record.Root.Position
	local goal = targetPosition
	if session.RecoveryGoal and now < session.RecoveryUntil then goal = session.RecoveryGoal else session.RecoveryGoal = nil end
	-- Keep a graph recovery alive long enough to clear a centered portal.
	-- Otherwise use obstacle-aware PFS, now sized to the real creature.
	if now < session.GraphRecoveryUntil then
		session.Navigator:SetGraphGoal(goal)
	else
		session.Navigator:SetGoal(goal)
	end
	local before = session.Navigator:GetPosition()
	session.Navigator:Step(math.min(dt, .1), session.CurrentSpeed)
	local after = session.Navigator:GetPosition()
	local moved = horizontalDistance(before, after) > .01
	setModelAndShared(session, "Level2_SlidemouthMoving", moved)
	setModelAndShared(session, "Level2_SlidemouthSpeed", session.CurrentSpeed)
	setModelAndShared(session, "Level2_SlidemouthPumps", pumps)
	setModelAndShared(session, "Level2_SlidemouthPathStatus", session.Navigator:GetStatus())
	tryAttack(session, record, now)
	updateWatchdog(session, record, now)
end

local function shoveBuoyantProps(session, before, after, now)
	local params = session.SoftObstacleParams
	local buoyantProps = session.BuoyantProps
	if not (params and buoyantProps and #buoyantProps > 0
		and session.Model and session.Model.PrimaryPart) then return end

	local travel = Vector3.new(after.X - before.X, 0, after.Z - before.Z)
	local direction
	if travel.Magnitude > .05 then
		direction = travel.Unit
	else
		local look = session.Model.PrimaryPart.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
		if direction.Magnitude <= .001 then return end
		direction = direction.Unit
	end
	local height = math.max(8, MOVEMENT.AgentHeight - .5)
	local footCenter = (before + after) * .5
	local boxCenter = Vector3.new(footCenter.X,
		math.max(before.Y, after.Y) + height * .5, footCenter.Z)
	local bodyLength = 21.5 + travel.Magnitude
	local boxCFrame = CFrame.lookAt(boxCenter, boxCenter + direction)
	local boxSize = Vector3.new(MOVEMENT.AgentRadius * 2 + 1.5, height, bodyLength)

	for _, object in ipairs(workspace:GetPartBoundsInBox(boxCFrame, boxSize, params)) do
		if not (object:IsA("BasePart")
			and object:GetAttribute("Level2_BuoyantProp") == true
			and not object.Anchored
			and object:IsDescendantOf(session.Manifest.World)) then continue end
		local previousShove = session.SoftShoveTimes[object]
		if previousShove and now - previousShove < BUOYANT_SHOVE_COOLDOWN then continue end
		session.SoftShoveTimes[object] = now

		local offset = Vector3.new(object.Position.X - after.X, 0, object.Position.Z - after.Z)
		local lateral = offset - direction * offset:Dot(direction)
		local shoveDirection = direction
		if lateral.Magnitude > .05 then
			shoveDirection = (direction + lateral.Unit * .55).Unit
		end
		local shoveSpeed = math.clamp(session.CurrentSpeed + 8,
			BUOYANT_SHOVE_MIN_SPEED, BUOYANT_SHOVE_MAX_SPEED)
		local currentVelocity = object.AssemblyLinearVelocity
		local desiredVelocity = shoveDirection * shoveSpeed
			+ Vector3.new(0, math.max(2.5, currentVelocity.Y), 0)
		local velocityChange = desiredVelocity - currentVelocity
		if velocityChange.Magnitude > 55 then velocityChange = velocityChange.Unit * 55 end
		local mass = math.max(.01, object.AssemblyMass)
		local sideSign = lateral:Dot(session.Model.PrimaryPart.CFrame.RightVector) >= 0 and 1 or -1
		pcall(function()
			object:ApplyImpulse(velocityChange * mass)
			object:ApplyAngularImpulse(Vector3.new(0, sideSign * mass * 4, 0))
		end)
		session.ShovedProps += 1
		session.Model:SetAttribute("Level2_SlidemouthShovedProps", session.ShovedProps)
		session.Model:SetAttribute("Level2_SlidemouthLastShovedProp", object.Name)
	end
end

local function heartbeat(session, dt)
	-- A paused session keeps its connection; it simply does nothing. Reaching
	-- Controller.Stop() from here would destroy the very incumbent a borrower
	-- promised to give back.
	if session.Phase ~= "RUNNING" then return end
	if not sessionAlive(session) then Controller.Stop(); return end
	if not roundReady(session) then
		if session.Navigator then session.Navigator:Stop() end
		setTarget(session, nil)
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		return
	end
	if workspace:GetAttribute("EntityPaused") == true then
		if session.Navigator then session.Navigator:Stop() end
		setState(session, "PAUSED")
		setModelAndShared(session, "Level2_SlidemouthMoving", false)
		return
	end
	local pumps = math.max(0, math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0))
	while session.LastPumps < pumps do
		local nextPump = session.LastPumps + 1
		schedulePumpScream(session, nextPump)
		if nextPump >= SPAWN_PUMPS and not session.Spawned
			and os.clock() < session.SpawnRetryAt then return end
		if nextPump >= FAST_PUMPS then
			-- Mark the edge before doing the hidden relocation so Heartbeat can
			-- keep driving speed/state without launching duplicate searches.
			session.LastPumps = nextPump
			session.Escalating = true
			-- WHAT SHIPPED BROKEN: this job was task.spawn'ed with no guard of any
			-- kind. It could wake up inside a borrow and mutate the navigator, the
			-- model pivot, the recovery fields and the published escalation surface
			-- of a PARKED session -- every one of them already snapshotted by the
			-- pause handle and still owed back to the incumbent.
			--
			-- The token is captured HERE, on the heartbeat, which is the one place
			-- the session is provably RUNNING. It is re-read at every checkpoint
			-- inside processPumpTransition and once more below, so a job that wakes
			-- up parked -- or wakes up after an entire pause/resume round trip --
			-- writes nothing at all.
			local escalationToken = session.RunToken
			-- The token that OWNS the Escalating flag from this moment on. The resume
			-- reads this pair to decide whether the flag still has a live job behind
			-- it; see the ESCALATION HAND-BACK CONTRACT in DebugResumeSession.
			session.EscalationToken = escalationToken
			setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "QUEUED")
			task.spawn(function()
				local callOk, transitionOk, failure =
					pcall(processPumpTransition, session, nextPump, escalationToken)
				if not callOk then
					failure = transitionOk
					transitionOk = false
				end
				-- Written FIRST and UNCONDITIONALLY, before any gate can return. It is
				-- not a gameplay value and no snapshot owns it or restores it: it is
				-- the only evidence a resume has that this job has finished and will
				-- therefore never clear Escalating itself. Leaving it out is what made
				-- a cancelled escalation and a completed one indistinguishable, and a
				-- session stuck at Escalating = true never moves again, because
				-- updateEntity early-returns on it forever.
				session.EscalationSettledToken = escalationToken
				-- ONE gate for every write-back. A cancelled job warns about nothing
				-- and publishes nothing, and deliberately does NOT clear Escalating --
				-- that flag is part of the pause handle's snapshot while the session is
				-- parked, and clearing it here would be the same class of trespass as
				-- the relocation this guard exists to stop. The resume clears it under
				-- the ESCALATION HAND-BACK CONTRACT instead.
				if not runTokenCurrent(session, escalationToken) then return end
				if not transitionOk then
					warn("[Level 2 Slidemouth] escalation failed: " .. tostring(failure))
					setModelAndShared(session, "Level2_SlidemouthEscalationPhase", "ERROR")
				end
				session.Escalating = false
			end)
			break
		end
		local callOk, ok, failure = pcall(processPumpTransition, session, nextPump)
		if not callOk then
			failure = ok
			ok = false
		end
		if not ok then
			session.SpawnRetryAt = os.clock() + 2
			publish("Level2_SlidemouthState", "SPAWN_RETRY")
			publish("Level2_SlidemouthPathStatus", tostring(failure))
			warn("[Level 2 Slidemouth] pump transition retry: " .. tostring(failure))
			return
		end
		session.LastPumps = nextPump
	end
	if pumps < SPAWN_PUMPS then return end
	if session.Model and session.Model.Parent and session.Navigator then
		local before = session.Navigator:GetPosition()
		updateEntity(session, math.min(dt, .1))
		shoveBuoyantProps(session, before, session.Navigator:GetPosition(), os.clock())
	end
end

-- `target` is OPTIONAL and defaults to exactly what this always meant: stop the
-- CURRENTLY ACTIVE session, and touch nothing that is parked. Pass a session
-- table or a pause handle to stop that one specifically -- which is the only way
-- to dispose of a PARKED session, because a parked session is not activeSession
-- and was therefore unreachable from here at all.
--
-- Returns (true) when this call really stopped something, (false, reason) when
-- there was nothing to stop.
function Controller.Stop(target): (boolean, string?)
	local session
	if target ~= nil then
		session = sessionFromHandle(target)
		if not session then return false, "not a session or pause handle" end
	else
		session = activeSession
	end
	if not session then return false, "no session" end

	local stoppedTheActiveSession = activeSession == session
	if stoppedTheActiveSession then activeSession = nil end
	-- Stopping a parked session is a legitimate END to the borrow, so it leaves
	-- the registry and its pause debt comes back down. Leaving either behind
	-- would keep DebugIsPaused() answering true for a session that no longer
	-- exists.
	if parkedSessions[session] ~= nil then
		unregisterParked(session)
		decrementPauseDepth(session)
	end
	session.PauseHandle = nil
	-- Marked FIRST: every background job checks this, and a job that wakes
	-- during the teardown below must see "finished", not "paused".
	session.Phase = "STOPPED"
	-- A stop is a departure from RUNNING like any other, so the token moves with
	-- it. sessionAlive() would already refuse every guarded job on the phase
	-- alone; the bump is here so "the token changes on EVERY departure from
	-- RUNNING" stays literally true and a residue reader can rely on it.
	bumpRunToken(session)
	for _, connection in ipairs(session.Connections or {}) do connection:Disconnect() end
	if stoppedTheActiveSession then
		setTarget(session, nil)
	else
		-- A parked session is not the PUBLISHED one. Clearing its target through
		-- setTarget() would write Level2_SlidemouthTargetUserId = 0 onto the
		-- state folder -- over whatever the borrower, or a different active
		-- session, currently owns there. The player-side chase marker still has
		-- to go, so it is cleared directly and nothing is published.
		clearOwnedChaseMarker(session.Target)
		session.Target = nil
	end
	if session.Navigator then session.Navigator:Destroy() end
	-- No `.Parent` test on either of these any more. A PAUSED session has its
	-- runtime folder deliberately parented to nil, so `session.RuntimeFolder and
	-- session.RuntimeFolder.Parent` was FALSE for exactly the sessions that most
	-- needed destroying: the folder, and the model inside it, leaked for the
	-- lifetime of the server while every residue count read the leak as clean.
	-- Both destroys are pcall'ed because a borrower may already have destroyed
	-- the instance, and a teardown must not throw over work already done.
	if session.Model then pcall(function() session.Model:Destroy() end) end
	if session.RuntimeFolder then pcall(function() session.RuntimeFolder:Destroy() end) end

	if stoppedTheActiveSession then
		-- ONLY the teardown of the ACTIVE session may rewrite the published
		-- surface. Republishing IDLE while stopping a PARKED session -- or while
		-- nothing at all was active, which this used to do unconditionally --
		-- clobbers ~22 state-folder attributes that a pause handle recorded and
		-- still owes back to its incumbent.
		publishStopped("IDLE")
	end
	return true
end

function Controller.Start(manifest, generation)
	-- Stops the ACTIVE session only, exactly as before. A PARKED session is
	-- deliberately left alone and stays in the parked registry: it is still owned
	-- by the handle a borrower is holding, and only that borrower knows whether
	-- it still wants it back. It remains reachable through
	-- Controller.DebugResidue() and disposable through Controller.Stop(handle),
	-- which is now the only way to end it. Before the registry existed this call
	-- silently ORPHANED it -- Stop() destroyed nothing, nothing else held a
	-- reference, and the handle's resume was refused forever afterwards with
	-- "another session is active".
	Controller.Stop()
	if not (manifest and manifest.World and manifest.World.Parent and typeof(manifest.Layout) == "table") then
		return nil, "invalid Level 2 manifest"
	end
	if not finiteNumber(generation) then return nil, "invalid generation" end
	local assets = ServerStorage:FindFirstChild("Level2Assets")
	local template = assets and assets:FindFirstChild(TEMPLATE_NAME)
	if not (template and template:IsA("Model") and template.PrimaryPart) then
		return nil, "missing ServerStorage.Level2Assets." .. TEMPLATE_NAME
	end
	local runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = RUNTIME_NAME
	runtimeFolder:SetAttribute("Level2_Generation", generation)
	runtimeFolder.Parent = manifest.World
	local session = {
		Manifest = manifest,
		Generation = generation,
		Template = template,
		RuntimeFolder = runtimeFolder,
		-- "RUNNING" | "PAUSED" | "STOPPED". A borrower moves this to PAUSED and
		-- back; nothing else may. Every background job reads it.
		Phase = "RUNNING",
		-- Cancellation token for deferred work. Bumped on every departure from and
		-- return to RUNNING; see bumpRunToken. Not snapshotted, not restored.
		RunToken = 0,
		-- The run token of the most recently QUEUED pump-three escalation, and of
		-- the most recently SETTLED one. When they differ, a job is still in flight
		-- and owns the Escalating flag; when they match, nothing will ever clear it
		-- again. That is the whole input to the escalation hand-back contract in
		-- DebugResumeSession. Both are markers, not gameplay state: no snapshot
		-- captures them and no resume restores them, because a resume that rewound
		-- them would be rewinding the evidence it is about to read.
		EscalationToken = nil,
		EscalationSettledToken = nil,
		PauseDepth = 0,
		Anchors = collectAnchors(manifest),
		Connections = {},
		Random = Random.new(),
		Spawned = false,
		SpawnRetryAt = 0,
		SpawnChoice = nil,
		CurrentSpeed = 0,
		State = "DORMANT",
		Target = nil,
		NextTargetRefreshAt = 0,
		NextTargetSwitchAt = 0,
		ScreamSerial = 0,
		WarningSerial = 0,
		PumpScreamScheduled = {},
		PumpScreamPlayed = {},
		-- How many times each pump's scream actually fired. The Played flag is
		-- the gate; this is the count, so a test can assert "exactly once"
		-- instead of "at least once".
		PumpScreamFired = {},
		LastPumps = 0,
		Escalating = false,
		AttackCooldownUntil = 0,
		RecoveryGoal = nil,
		RecoveryGoalPart = nil,
		RecoveryRetreats = 0,
		FailedRecoveryAnchors = nil,
		RecoveryUntil = 0,
		GraphRecoveryUntil = 0,
		WanderGoal = nil,
		WanderGoalUntil = 0,
		WanderMoveDeadline = 0,
		LastWanderAnchor = nil,
		SoftObstacleParams = nil,
		BuoyantProps = {},
		SoftShoveTimes = setmetatable({}, {__mode = "k"}),
		ShovedProps = 0,
	}
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Level2_BuoyantProp") == true then
			table.insert(session.BuoyantProps, descendant)
		end
	end
	if #session.BuoyantProps > 0 then
		local softParams = OverlapParams.new()
		softParams.FilterType = Enum.RaycastFilterType.Include
		softParams.FilterDescendantsInstances = session.BuoyantProps
		softParams.MaxParts = 64
		softParams.RespectCanCollide = false
		session.SoftObstacleParams = softParams
	end
	if #session.Anchors == 0 then
		runtimeFolder:Destroy()
		return nil, "manifest contains no entity navigation anchors"
	end
	activeSession = session
	publish("Level2_SlidemouthGeneration", generation)
	publish("Level2_SlidemouthActive", false)
	publish("Level2_SlidemouthState", session.State)
	publish("Level2_SlidemouthTargetUserId", 0)
	publish("Level2_SlidemouthSpeed", 0)
	publish("Level2_SlidemouthPathStatus", "IDLE")
	publish("Level2_SlidemouthScreamSerial", 0)
	table.insert(session.Connections, RunService.Heartbeat:Connect(function(dt)
		heartbeat(session, dt)
	end))
	-- WHAT SHIPPED BROKEN: this retained connection had no phase guard. It stays
	-- connected across a borrow BY DESIGN -- only Controller.Stop disconnects it,
	-- and a paused session keeps its connections -- so a player leaving while the
	-- session was PARKED ran setTarget(session, nil) against a session the pause
	-- handle had already snapshotted. That cleared handle.Values.Target under the
	-- handle, published Level2_SlidemouthTargetUserId = 0 over the state folder
	-- the borrower owns, and cleared the player chase attributes the handle was
	-- holding for return; the resume then wrote the snapshotted Target back and
	-- the creature carried on chasing a player who had left the game.
	--
	-- It gates on sessionAlive() rather than on a captured run token, and that is
	-- the deliberate difference between a RETAINED connection and a QUEUED job:
	-- a token captured here would go stale on the first pause and kill this
	-- handler for the rest of the session's life. sessionAlive() is the same
	-- "not right now" without the "and never again" -- it demands activeSession,
	-- Phase == "RUNNING" and a matching world generation, and it goes true again
	-- the instant the resume's phase stage lands.
	--
	-- Dropping the event while parked loses nothing: chooseTarget re-filters every
	-- candidate through livingRecord(), which rejects a player whose .Parent is no
	-- longer Players, so the very first resumed heartbeat clears the departed
	-- target anyway.
	table.insert(session.Connections, Players.PlayerRemoving:Connect(function(player)
		if not sessionAlive(session) then return end
		if session.Target == player then setTarget(session, nil) end
	end))
	return session
end

function Controller.IsRunning()
	return activeSession ~= nil and sessionAlive(activeSession)
end

-- The production movement tuning, so a probe measures the real agent rather
-- than a copy of its numbers that can silently fall out of date.
Controller.MovementTuning = MOVEMENT
Controller.ModelScale = MODEL_SCALE

-- The two chase speeds, exported so a suite can drive the navigator at the SAME
-- stride production asks for rather than mirroring a number that can drift.
-- The stride is speed x the controller's own per-frame clamp of .1, so
-- PumpThree x .1 = 3.6 studs is the longest single Step the shipped game ever
-- requests -- and the one the substep loop exists to break into pieces.
Controller.ChaseSpeeds = {
	PumpTwo = PUMP_TWO_SPEED,
	PumpThree = PUMP_THREE_SPEED,
	-- updateEntity and the retreat path both call Step with math.min(dt, .1).
	MaxStepDelta = .1,
}

-- The production spawn thresholds. A suite still keeps its OWN copies to assert
-- against -- these are here so a suite can additionally prove the two agree and
-- report the drift explicitly, rather than silently following a change.
Controller.SpawnThresholds = {
	PreferredMinHops = SPAWN_PREFERRED_MIN_HOPS,
	PreferredMaxHops = SPAWN_PREFERRED_MAX_HOPS,
	MinimumStudDistance = SPAWN_MINIMUM_STUD_DISTANCE,
	FallbackStudDistance = SPAWN_FALLBACK_STUD_DISTANCE,
	SpawnPumps = SPAWN_PUMPS,
}

-- Test surface. Builds a throwaway session around the real generated world and
-- a synthetic party, so a suite can assert the spawn rules for player
-- placements that are impractical to stage with live characters. It runs the
-- SAME selector gameplay runs -- nothing here re-implements it.
--
-- Returns the ranked list, not the committed room: the live spawn additionally
-- validates body clearance and may take a lower-ranked entry. Every invariant
-- that matters therefore has to hold for EVERY candidate, which is what a
-- caller should assert.
-- `omitContext` reproduces the pump-scream fallback's call shape, which passes
-- no room context at all. It exists so a suite can prove that path cannot throw.
function Controller.EvaluateSpawn(manifest, positions, pumpNumber, omitContext)
	assert(typeof(manifest) == "table" and typeof(manifest.Layout) == "table",
		"EvaluateSpawn requires a Level 2 manifest")
	local session = {
		Manifest = manifest,
		BuoyantProps = {},
		Anchors = collectAnchors(manifest),
	}
	local records = {}
	for _, position in ipairs(positions or {}) do
		if typeof(position) == "Vector3" then
			table.insert(records, {Root = {Position = position}})
		end
	end
	local context = applyPumpContext(session, roomContext(session, records),
		tonumber(pumpNumber) or SPAWN_PUMPS)
	local candidates = {}
	local ranked = omitContext == true
		and rankedSpawnCandidates(session, records, true)
		or rankedSpawnCandidates(session, records, false, context)
	for _, candidate in ipairs(ranked) do
		table.insert(candidates, {
			Anchor = candidate.Anchor.Name,
			HallIndex = candidate.HallIndex,
			Hops = candidate.Hops,
			PumpHops = candidate.PumpHops,
			Distance = candidate.Distance,
			Hidden = candidate.Hidden,
			Tier = candidate.Tier,
		})
	end
	return {
		Candidates = candidates,
		Chosen = candidates[1],
		PumpHallIndex = context.PumpHallIndex,
		Occupied = context.Occupied,
		AnchorCount = #session.Anchors,
	}
end

-- Test surface for the SPAWN CONTRACT itself, run over every anchor on the map
-- for a synthetic party. It calls the same predicate the commit calls -- there
-- is no second implementation to drift -- and reports the admitted set, the
-- refused set and each refusal's reason, so a suite can compare that set
-- against a room graph it walked for itself.
--
-- `positions` is read at CALL time, deliberately: a suite that mutates the
-- table it handed in and asks again is doing precisely what a player walking
-- through a doorway does between the ranking and the commit.
function Controller.EvaluateSpawnContract(manifest, positions)
	assert(typeof(manifest) == "table" and typeof(manifest.Layout) == "table",
		"EvaluateSpawnContract requires a Level 2 manifest")
	local session = {
		Manifest = manifest,
		BuoyantProps = {},
		Anchors = collectAnchors(manifest),
	}
	local records = {}
	for _, position in ipairs(positions or {}) do
		if typeof(position) == "Vector3" then
			table.insert(records, {Root = {Position = position}})
		end
	end
	local context = roomContext(session, records)
	local admitted, refused = {}, {}
	for _, anchor in ipairs(session.Anchors) do
		local ok, reason, detail = spawnContractHolds(session,
			{Anchor = anchor, HallIndex = anchor.HallIndex}, context)
		table.insert(ok and admitted or refused, {
			Anchor = anchor.Name,
			HallIndex = detail.HallIndex,
			Hops = detail.Hops,
			Reason = reason,
		})
	end
	return {
		Admitted = admitted,
		Refused = refused,
		PlayerHalls = context.PlayerHalls,
		Occupied = context.Occupied,
		AnchorCount = #session.Anchors,
	}
end

-- The COMMIT-TIME revalidation in isolation, for a party that is allowed to
-- MOVE half way through. The ranking is taken against `positions` as they
-- stand; `onBeforeCommit` then runs -- which is the yield a live WarpTo and
-- route-validation fan spends -- and everything after it is re-derived from
-- `positions` as they stand THEN, through the same contract predicate the
-- production commit calls with no snapshot.
--
-- Committed comes back nil when nothing survives, which is the production
-- answer too: the spawn waits.
function Controller.EvaluateSpawnCommit(manifest, positions, pumpNumber, onBeforeCommit)
	assert(typeof(manifest) == "table" and typeof(manifest.Layout) == "table",
		"EvaluateSpawnCommit requires a Level 2 manifest")
	local session = {
		Manifest = manifest,
		BuoyantProps = {},
		Anchors = collectAnchors(manifest),
	}
	local function partyRecords()
		local records = {}
		for _, position in ipairs(positions or {}) do
			if typeof(position) == "Vector3" then
				table.insert(records, {Root = {Position = position}})
			end
		end
		return records
	end
	local records = partyRecords()
	local context = applyPumpContext(session, roomContext(session, records),
		tonumber(pumpNumber) or SPAWN_PUMPS)
	local ranked = rankedSpawnCandidates(session, records, false, context)
	local picked = ranked[1]
	if typeof(onBeforeCommit) == "function" then
		onBeforeCommit(picked and picked.Anchor.Name or nil, picked and picked.HallIndex or nil)
	end
	-- Rebuilt, not reused. This is the whole assertion.
	local liveContext = roomContext(session, partyRecords())
	local pickedOk, pickedReason = false, "nothing was ranked"
	if picked then
		pickedOk, pickedReason = spawnContractHolds(session, picked, liveContext)
	end
	local committed, committedReason
	for _, candidate in ipairs(ranked) do
		local ok, reason = spawnContractHolds(session, candidate, liveContext)
		if ok then
			committed, committedReason = candidate, reason
			break
		end
	end
	return {
		Picked = picked and picked.Anchor.Name or nil,
		PickedHall = picked and picked.HallIndex or nil,
		PickedStillValid = pickedOk,
		PickedReason = pickedReason,
		Committed = committed and committed.Anchor.Name or nil,
		CommittedHall = committed and committed.HallIndex or nil,
		CommittedReason = committedReason,
		RankedCount = #ranked,
		PlayerHallsAtCommit = liveContext.PlayerHalls,
	}
end

local function vectorTable(value)
	return value and {X = value.X, Y = value.Y, Z = value.Z} or nil
end

-- Every attribute the controller replicates about a live creature, so a test
-- can snapshot and restore the whole published surface rather than a hand-picked
-- subset of it.
--
-- This list is the DECLARED union of everything the module can publish. Its job
-- is to name attributes that may need DELETING on restore -- an attribute that
-- was absent when a borrow began and present when it ended has to go back to
-- absent, and a table built from GetAttribute cannot express that, because a nil
-- value simply does not appear in it. Restoring "everything in the table" was
-- therefore restoring everything EXCEPT the absences.
Controller.PublishedAttributes = {
	"Level2_SlidemouthActive", "Level2_SlidemouthGeneration", "Level2_SlidemouthState",
	"Level2_SlidemouthTargetUserId", "Level2_SlidemouthSpeed", "Level2_SlidemouthPathStatus",
	"Level2_SlidemouthScreamSerial", "Level2_SlidemouthWarningSerial",
	"Level2_SlidemouthSpawnDistance", "Level2_SlidemouthSpawnHidden",
	"Level2_SlidemouthSpawnAnchor", "Level2_SlidemouthSpawnHall",
	"Level2_SlidemouthSpawnPlayerHops", "Level2_SlidemouthSpawnPumpHops",
	"Level2_SlidemouthSpawnPumpHall", "Level2_SlidemouthSpawnTier",
	"Level2_SlidemouthChased",
	-- Added after a borrow was found to be restoring a strict subset of what a
	-- live creature publishes: the scream, warning, movement, retreat,
	-- escalation and shove surfaces were all outside the list, so a test could
	-- silently leave any of them holding its own values.
	"Level2_SlidemouthScreamKind", "Level2_SlidemouthScreamPosition",
	"Level2_SlidemouthScreamBusyUntil",
	"Level2_SlidemouthWarningPosition", "Level2_SlidemouthWarningPump",
	"Level2_SlidemouthMoving", "Level2_SlidemouthRetreatStuds",
	"Level2_SlidemouthEscalationPhase", "Level2_SlidemouthEscalationCandidates",
	"Level2_SlidemouthEscalationDistance", "Level2_SlidemouthEscalationAnchor",
	"Level2_SlidemouthShovedProps", "Level2_SlidemouthLastShovedProp",
	"Level2_SlidemouthAnimationStartedAt",
}

-- Attributes the controller writes on PLAYERS rather than on the state folder.
Controller.PlayerChaseAttributes = {"Level2_SlidemouthChased", "BeingChased"}

-- Anything the module publishes starts with this, so a snapshot can pick up an
-- attribute nobody remembered to declare above.
Controller.PublishedAttributePrefix = "Level2_Slidemouth"

-- Absolute os.clock deadlines. Stored as REMAINING time across a pause: a
-- creature two seconds from giving up on its recovery is still two seconds from
-- giving up when it is put back, however long the borrow took. Leaving these as
-- absolute readings is what made the first resumed heartbeat fire stale-progress
-- and recovery behaviour immediately.
local PAUSE_DEADLINE_FIELDS = {
	"NextTargetRefreshAt", "NextTargetSwitchAt", "AttackCooldownUntil",
	"RecoveryUntil", "GraphRecoveryUntil", "WanderGoalUntil", "WanderMoveDeadline",
	"SpawnRetryAt",
}

-- Absolute os.clock STAMPS -- a past reading that an age is measured from.
-- Shifted by the same amount, so the age is preserved rather than the deadline.
local PAUSE_STAMP_FIELDS = {"ProgressAt"}

-- Plain session values that must come back exactly as they were.
local PAUSE_VALUE_FIELDS = {
	"Spawned", "SpawnChoice", "CurrentSpeed", "State", "Target", "ScreamSerial",
	"WarningSerial", "LastPumps", "Escalating", "RecoveryGoal", "RecoveryGoalPart",
	"RecoveryStage", "LastWanderAnchor", "WanderGoal", "Generation",
}

-- 0 and the infinities are SENTINELS ("disarmed", "never", "infinitely stale"),
-- not readings. Shifting them arms a timer that was deliberately off, so they
-- pass through untouched. NaN likewise: it is never a valid deadline and
-- arithmetic on it would only spread.
local function shiftableClockValue(value): boolean
	if type(value) ~= "number" then return false end
	if value ~= value then return false end
	return value ~= 0 and value ~= math.huge and value ~= -math.huge
end

local function shiftClockValue(value, delta)
	if not shiftableClockValue(value) then return value end
	return value + delta
end

-- Every prefixed attribute currently on an instance, plus which of the declared
-- names are ABSENT from it. The absent half is the point.
local function attributeSurface(instance)
	local present, absent = {}, {}
	if not instance then return present, absent end
	local seen = {}
	for name, value in pairs(instance:GetAttributes()) do
		if string.sub(name, 1, #Controller.PublishedAttributePrefix)
			== Controller.PublishedAttributePrefix then
			present[name] = value
			seen[name] = true
		end
	end
	for _, name in ipairs(Controller.PublishedAttributes) do
		if not seen[name] then absent[name] = true end
	end
	return present, absent
end

local function restoreAttributeSurface(instance, present, absent)
	if not instance then return end
	for name in pairs(absent or {}) do instance:SetAttribute(name, nil) end
	for name, value in pairs(present or {}) do instance:SetAttribute(name, value) end
	-- Anything the borrower ADDED under our prefix that we never had is removed,
	-- or a test could leave a brand-new attribute behind and still report a
	-- clean restore.
	for name in pairs(instance:GetAttributes()) do
		if string.sub(name, 1, #Controller.PublishedAttributePrefix)
			== Controller.PublishedAttributePrefix
			and (present == nil or present[name] == nil) then
			instance:SetAttribute(name, nil)
		end
	end
end

-- Studio-only. PAUSE the live session without tearing it down, and without
-- letting it age.
--
-- The previous DebugSuspendSession cleared activeSession and disconnected the
-- heartbeat. That reads as "this session is over" to everything that is not the
-- heartbeat, and it froze nothing:
--
--   * a pending pump scream woke, saw no active session, and returned without
--     playing OR rearming -- the warning was gone for good, while
--     PumpScreamScheduled still claimed it was on its way;
--   * every absolute deadline kept aging against a clock that never stopped, so
--     the first resumed heartbeat could immediately declare the creature stuck;
--   * a ComputeAsync started before the suspend landed during it and wrote a new
--     route over the incumbent's plan;
--   * attributes that were ABSENT could not be restored to absent, because a nil
--     does not survive a round trip through a Lua table;
--   * and the model's own attributes were never captured at all.
--
-- What happens instead: the session stays exactly where it is, marked PAUSED.
-- Its connections stay connected and its jobs stay alive; they simply do nothing
-- while the phase says so. Timers are converted to remaining durations, the
-- navigator parks its in-flight work, and the complete attribute surface --
-- including absences -- is recorded.
function Controller.DebugPauseSession()
	if not RunService:IsStudio() then return nil, "not Studio" end
	local session = activeSession
	if not session then return nil, "no session" end
	if session.Phase == "PAUSED" then return session.PauseHandle, "already paused" end
	if session.Phase ~= "RUNNING" then return nil, "session is " .. tostring(session.Phase) end

	local pausedAtMonotonic = os.clock()
	local pausedAtServer = workspace:GetServerTimeNow()
	local handle = {
		Session = session,
		Generation = session.Generation,
		PausedAtMonotonic = pausedAtMonotonic,
		PausedAtServer = pausedAtServer,
		Consumed = false,
		Deadlines = {},
		Stamps = {},
		Values = {},
		Screams = {},
		SoftShoveAges = {},
	}

	-- BUILD THE WHOLE SNAPSHOT FIRST, mutating nothing. A failure here leaves the
	-- incumbent exactly as it was found.
	local built, buildError = pcall(function()
		for _, name in ipairs(PAUSE_DEADLINE_FIELDS) do
			handle.Deadlines[name] = session[name]
		end
		for _, name in ipairs(PAUSE_STAMP_FIELDS) do
			handle.Stamps[name] = session[name]
		end
		for _, name in ipairs(PAUSE_VALUE_FIELDS) do
			handle.Values[name] = session[name]
		end
		-- The escalation hand-back inputs, recorded as they stood at the instant of
		-- the borrow. `Escalating` is in PAUSE_VALUE_FIELDS above and so is captured
		-- like any other value; these two say WHO owned that value -- whether a live
		-- job was still behind it, or whether one had already settled. The resume
		-- needs both readings to tell "the job finished while parked, so nobody is
		-- left to clear the flag" from "the flag was simply true and still is".
		handle.EscalationToken = session.EscalationToken
		handle.EscalationSettledToken = session.EscalationSettledToken
		for pumpNumber, dueAt in pairs(session.PumpScreamScheduled) do
			handle.Screams[pumpNumber] = {
				Remaining = (tonumber(dueAt) or pausedAtServer) - pausedAtServer,
				Played = session.PumpScreamPlayed[pumpNumber] == true,
			}
		end
		if type(session.SoftShoveTimes) == "table" then
			for part, at in pairs(session.SoftShoveTimes) do
				handle.SoftShoveAges[part] = pausedAtMonotonic - at
			end
		end
		local state = stateFolder()
		handle.StateInstance = state
		handle.StatePresent, handle.StateAbsent = attributeSurface(state)
		handle.ModelInstance = session.Model
		handle.ModelPresent, handle.ModelAbsent = attributeSurface(session.Model)
		handle.ModelParent = session.Model and session.Model.Parent or nil
		handle.ModelPivot = session.Model and session.Model.PrimaryPart
			and session.Model:GetPivot() or nil
		handle.RuntimeInstance = session.RuntimeFolder
		handle.RuntimeParent = session.RuntimeFolder and session.RuntimeFolder.Parent or nil
		handle.PlayerChase = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local record = {}
			for _, name in ipairs(Controller.PlayerChaseAttributes) do
				record[name] = player:GetAttribute(name)
			end
			handle.PlayerChase[player] = record
		end
	end)
	if not built then return nil, "snapshot failed: " .. tostring(buildError) end

	-- Only now does anything change, and every step is individually protected AND
	-- individually UNDOABLE.
	--
	-- WHAT WENT WRONG: the three stages were pcall'ed, their failures collected
	-- into handle.PartialFailures, and the handle was RETURNED ANYWAY. Nothing
	-- read PartialFailures, so a half-applied pause was indistinguishable from a
	-- clean one -- and the half-applied states are the dangerous ones. A failed
	-- "phase" stage left Phase = "RUNNING" with the navigator already parked and
	-- the runtime folder already out of the world: a live heartbeat driving a
	-- creature that had no plan and no world. A failed "runtime" stage left a
	-- session parked while its folder was still in the map.
	--
	-- Now each stage registers its own inverse, and any failure runs those
	-- inverses in reverse order and returns nil plus a reason. There are exactly
	-- two outcomes: PAUSED, or untouched.
	local undo = {}
	local failure
	local function stage(name, fn, rollback)
		if failure then return end
		local ok, err = pcall(fn)
		if ok then
			if rollback then table.insert(undo, rollback) end
		else
			failure = name .. ": " .. tostring(err)
		end
	end

	stage("navigator", function()
		if not session.Navigator then return end
		local record = session.Navigator:Pause()
		if type(record) ~= "table" then
			-- Navigator:Pause() returns NIL for a destroyed navigator. That is a
			-- FAILED stage, not an empty one: a callee can refuse without
			-- throwing, and the old code accepted the nil silently -- leaving a
			-- handle whose resume had nothing to put back.
			error("the navigator is destroyed", 0)
		end
		handle.Navigator = record
	end, function()
		if session.Navigator and handle.Navigator then
			session.Navigator:Resume(handle.Navigator, os.clock())
		end
		handle.Navigator = nil
	end)
	stage("phase", function()
		-- Read BEFORE the bump, so the rollback below can put the incumbent's own
		-- token back rather than leaving a FAILED pause having silently cancelled
		-- every job that was queued before it.
		handle.RunTokenBefore = session.RunToken
		session.Phase = "PAUSED"
		-- THE CANCELLATION. Everything that captured a token while this session was
		-- RUNNING -- the pump-three escalation above all -- becomes a no-op from
		-- here on. Without it the pause was transactional against its own three
		-- stages and nothing else, and in-flight work walked straight over the
		-- snapshot the stages above had just taken.
		bumpRunToken(session)
		incrementPauseDepth(session)
		session.PauseHandle = handle
		activeSession = nil
		-- The session leaves `activeSession` and enters the parked registry in
		-- the SAME stage, so there is no instant in which the module holds no
		-- reference to it at all.
		registerParked(session, handle)
	end, function()
		unregisterParked(session)
		session.PauseHandle = nil
		decrementPauseDepth(session)
		session.Phase = "RUNNING"
		-- Exactly the token the incumbent held before this failed pause touched it:
		-- a rolled-back pause must leave the session UNTOUCHED, and the token is
		-- part of "untouched". Bumping again here would permanently cancel the
		-- in-flight escalation of a session that was never actually borrowed.
		session.RunToken = handle.RunTokenBefore
		activeSession = session
	end)
	stage("runtime", function()
		-- Out of the world but NOT destroyed, and NOT reparented anywhere a
		-- borrower's own build could collide with.
		if session.RuntimeFolder then session.RuntimeFolder.Parent = nil end
	end, function()
		if session.RuntimeFolder then session.RuntimeFolder.Parent = handle.RuntimeParent end
	end)

	if failure then
		for index = #undo, 1, -1 do
			local rolledBack, rollbackError = pcall(undo[index])
			if not rolledBack then
				warn("[Level 2 Slidemouth] pause rollback failed: " .. tostring(rollbackError))
			end
		end
		return nil, "pause failed: " .. failure
	end
	return handle
end

-- Studio-only. Put a paused session back, exactly as it was found.
function Controller.DebugResumeSession(handle): (boolean, string?)
	if not RunService:IsStudio() then return false, "not Studio" end
	if type(handle) ~= "table" or type(handle.Session) ~= "table" then
		return false, "not a pause handle"
	end
	if handle.Consumed then return false, "handle already used" end
	local session = handle.Session
	if session.Phase ~= "PAUSED" then return false, "session is " .. tostring(session.Phase) end
	if not worldIntact(session) then return false, "the world this session was built for is gone" end
	-- The borrower must clean up after itself. Silently stopping whatever is
	-- running would destroy a session somebody else owns -- which is exactly what
	-- the old resume did, taking the state folder with it.
	if activeSession ~= nil then return false, "another session is active" end

	local resumedAtMonotonic = os.clock()
	local resumedAtServer = workspace:GetServerTimeNow()
	local monotonicDelta = resumedAtMonotonic - handle.PausedAtMonotonic
	local serverDelta = resumedAtServer - handle.PausedAtServer

	-- WHAT WENT WRONG: the five stages were pcall'ed, their failures collected,
	-- and then `handle.Consumed = true` plus the live phase flip ran
	-- UNCONDITIONALLY -- so a resume that failed still burned the handle and
	-- still put the session back on the heartbeat. The caller got `false` and a
	-- string, and no way back: the handle was spent, the session was live, and
	-- whatever the failed stage had not restored stayed unrestored forever.
	--
	-- Now each stage registers its inverse. Any failure rolls back to the PARKED
	-- state -- runtime folder detached again, navigator re-paused, Phase left
	-- "PAUSED", activeSession left nil, the session still in the parked registry
	-- -- and the handle is NOT consumed, so the caller can fix the cause and try
	-- the same handle again. Only a fully successful resume consumes it.
	local undo = {}
	local failure
	local function stage(name, fn, rollback)
		if failure then return end
		local ok, err = pcall(fn)
		if ok then
			if rollback then table.insert(undo, rollback) end
		else
			failure = name .. ": " .. tostring(err)
		end
	end

	stage("runtime", function()
		if session.RuntimeFolder then session.RuntimeFolder.Parent = handle.RuntimeParent end
		if session.Model and handle.ModelParent and session.Model.Parent ~= handle.ModelParent then
			session.Model.Parent = handle.ModelParent
		end
		if handle.ModelPivot and session.Model and session.Model.PrimaryPart then
			-- A resume must be a no-op on a model nobody moved.
			if session.Model:GetPivot() ~= handle.ModelPivot then
				session.Model:PivotTo(handle.ModelPivot)
			end
		end
	end, function()
		-- Back out of the world. The model's parent and pivot are deliberately
		-- NOT re-broken: both were moved TOWARDS the values the handle recorded,
		-- which is where a parked session's model is supposed to be anyway.
		if session.RuntimeFolder then session.RuntimeFolder.Parent = nil end
	end)
	local timersBefore
	stage("timers", function()
		-- The pre-image is read before anything is written, so the rollback can
		-- put the parked session's own (unshifted) readings back rather than
		-- leaving it holding deadlines re-based onto a resume that failed.
		timersBefore = {
			Fields = {},
			Scheduled = {},
			Played = {},
			SoftShove = setmetatable({}, {__mode = "k"}),
			-- Not a timer, but pre-imaged here because the escalation hand-back
			-- below writes it and this stage's rollback is what has to undo it.
			EscalationAbandonedAtToken = session.EscalationAbandonedAtToken,
		}
		for _, name in ipairs(PAUSE_DEADLINE_FIELDS) do timersBefore.Fields[name] = session[name] end
		for _, name in ipairs(PAUSE_STAMP_FIELDS) do timersBefore.Fields[name] = session[name] end
		for _, name in ipairs(PAUSE_VALUE_FIELDS) do timersBefore.Fields[name] = session[name] end
		for pumpNumber in pairs(handle.Screams) do
			timersBefore.Scheduled[pumpNumber] = session.PumpScreamScheduled[pumpNumber]
			timersBefore.Played[pumpNumber] = session.PumpScreamPlayed[pumpNumber]
		end
		if type(session.SoftShoveTimes) == "table" then
			for part in pairs(handle.SoftShoveAges) do
				timersBefore.SoftShove[part] = session.SoftShoveTimes[part]
			end
		end

		for _, name in ipairs(PAUSE_DEADLINE_FIELDS) do
			session[name] = shiftClockValue(handle.Deadlines[name], monotonicDelta)
		end
		for _, name in ipairs(PAUSE_STAMP_FIELDS) do
			session[name] = shiftClockValue(handle.Stamps[name], monotonicDelta)
		end
		for _, name in ipairs(PAUSE_VALUE_FIELDS) do
			session[name] = handle.Values[name]
		end
		-- ================= ESCALATION HAND-BACK CONTRACT =================
		--
		-- `Escalating` is the ONE snapshotted field a resume is allowed not to put
		-- back verbatim, and this is the whole of the exception.
		--
		-- WHAT SHIPPED BROKEN: the flag is in PAUSE_VALUE_FIELDS, so a pause
		-- captured it and a resume wrote it back unconditionally. The single queued
		-- pump-three escalation job could clear the flag while the session was
		-- parked, and the resume then put the captured `true` straight back over the
		-- cleared value. updateEntity early-returns on Escalating, so the creature
		-- froze where it stood, publishing Moving = false for the rest of the round:
		-- a permanently dead creature produced by a SUCCESSFUL borrow.
		--
		-- Guarding the job -- which it now is -- does not fix that on its own. It
		-- breaks it the other way instead: a cancelled job returns WITHOUT clearing
		-- the flag, and the restored `true` then has no writer left at all.
		--
		-- THE RULE: a snapshotted `Escalating = true` is CLEARED on resume, always.
		--
		-- It is provable rather than heuristic. `session.Escalating = true` has
		-- exactly one writer in this module -- the pump-three edge in heartbeat --
		-- and it is written together with the run token that owns it. The only code
		-- that can ever clear it is that job, under runTokenCurrent. The pause bumped
		-- the token and this resume is about to bump it again, and tokens only ever
		-- increase, so the job's captured token can never match again: whether it
		-- already settled while parked or is still asleep inside a yield, it will
		-- never clear this flag. Restoring `true` therefore cannot mean "a job is
		-- still coming"; it can only mean "stuck forever".
		--
		-- WHAT IS LOST, deliberately: the relocation that escalation was going to
		-- perform is abandoned, and is not re-queued -- `LastPumps` was advanced past
		-- the pump before the job was spawned, so the heartbeat will not launch a
		-- second search. The creature comes back at the pivot the handle pinned and
		-- keeps hunting at PUMP_THREE_SPEED (speed reads Level2Pumps, never this
		-- flag). A skipped teleport is a far smaller defect than a frozen creature.
		--
		-- WHAT IS DELIBERATELY *NOT* TOUCHED: the published
		-- Level2_SlidemouthEscalationPhase attribute, which the attributes stage
		-- below still restores byte-for-byte from the snapshot -- so it can read
		-- "QUEUED" for an escalation that will never arrive. That is the borrow
		-- contract winning over tidiness: the published surface must come back
		-- exactly as it was lent out, or a suite can no longer assert that it did.
		-- The abandonment is reported on the handle and on the session instead,
		-- where a test can read it and the game cannot.
		if handle.Values.Escalating == true then
			session.Escalating = false
			-- Both are markers, never snapshotted and never restored, so a suite can
			-- prove the exception FIRED rather than merely that the flag happened to
			-- come back false.
			handle.EscalationHandBack = "cleared: the queued escalation was cancelled by the borrow"
			session.EscalationAbandonedAtToken = handle.EscalationToken or handle.RunTokenBefore
		end
		-- Each pending scream keeps its REMAINING delay. Its job polls this
		-- value, so writing it here is what makes the warning fire late rather
		-- than instantly or never.
		for pumpNumber, record in pairs(handle.Screams) do
			session.PumpScreamScheduled[pumpNumber] = resumedAtServer + record.Remaining
			session.PumpScreamPlayed[pumpNumber] = record.Played or nil
		end
		if type(session.SoftShoveTimes) == "table" then
			for part, age in pairs(handle.SoftShoveAges) do
				session.SoftShoveTimes[part] = resumedAtMonotonic - age
			end
		end
	end, function()
		if type(timersBefore) ~= "table" then return end
		-- The hand-back exception is rolled back with everything else: Escalating
		-- itself comes back through timersBefore.Fields (it is in PAUSE_VALUE_FIELDS
		-- and so was pre-imaged above), and the two markers that RECORD the
		-- exception are cleared, or a resume that failed after this stage would
		-- leave a parked session claiming its escalation had been abandoned.
		handle.EscalationHandBack = nil
		session.EscalationAbandonedAtToken = timersBefore.EscalationAbandonedAtToken
		for name, value in pairs(timersBefore.Fields) do session[name] = value end
		for pumpNumber, value in pairs(timersBefore.Scheduled) do
			session.PumpScreamScheduled[pumpNumber] = value
		end
		for pumpNumber in pairs(handle.Screams) do
			session.PumpScreamPlayed[pumpNumber] = timersBefore.Played[pumpNumber]
		end
		if type(session.SoftShoveTimes) == "table" then
			for part, value in pairs(timersBefore.SoftShove) do
				session.SoftShoveTimes[part] = value
			end
		end
	end)
	stage("navigator", function()
		if not (session.Navigator and handle.Navigator) then return end
		-- Navigator:Resume can refuse WITHOUT throwing -- a destroyed navigator,
		-- a record with an invalid LastPathAge. A `false` return used to be
		-- discarded here, so a navigator that had flatly refused to come back
		-- still counted as a successful stage.
		local resumed, reason, outcome = session.Navigator:Resume(handle.Navigator, resumedAtMonotonic)
		handle.NavigatorResumeOutcome = outcome
		if not resumed then
			error(tostring(reason or "the navigator refused to resume"), 0)
		end
	end, function()
		-- Park the navigator again, and keep the record that describes it: the
		-- handle has to stay usable for a second attempt.
		if session.Navigator then
			local record = session.Navigator:Pause()
			if type(record) == "table" then handle.Navigator = record end
		end
		handle.NavigatorResumeOutcome = nil
	end)
	-- BEFORE the session goes live, so the first resumed heartbeat republishes
	-- on top of a correct map instead of racing a later restore.
	local attributesBefore
	stage("attributes", function()
		local state = handle.StateInstance or stateFolder()
		local model = handle.ModelInstance or session.Model
		attributesBefore = {State = state, Model = model, Players = {}}
		attributesBefore.StatePresent, attributesBefore.StateAbsent = attributeSurface(state)
		attributesBefore.ModelPresent, attributesBefore.ModelAbsent = attributeSurface(model)
		for player in pairs(handle.PlayerChase) do
			local record = {}
			for _, name in ipairs(Controller.PlayerChaseAttributes) do
				record[name] = player:GetAttribute(name)
			end
			attributesBefore.Players[player] = record
		end

		restoreAttributeSurface(state, handle.StatePresent, handle.StateAbsent)
		restoreAttributeSurface(model, handle.ModelPresent, handle.ModelAbsent)
		for player, record in pairs(handle.PlayerChase) do
			if player.Parent == Players then
				for _, name in ipairs(Controller.PlayerChaseAttributes) do
					player:SetAttribute(name, record[name])
				end
			end
		end
	end, function()
		if type(attributesBefore) ~= "table" then return end
		restoreAttributeSurface(attributesBefore.State,
			attributesBefore.StatePresent, attributesBefore.StateAbsent)
		restoreAttributeSurface(attributesBefore.Model,
			attributesBefore.ModelPresent, attributesBefore.ModelAbsent)
		for player, record in pairs(attributesBefore.Players) do
			if player.Parent == Players then
				for _, name in ipairs(Controller.PlayerChaseAttributes) do
					player:SetAttribute(name, record[name])
				end
			end
		end
	end)
	local phaseTokenBefore
	stage("phase", function()
		phaseTokenBefore = session.RunToken
		session.Phase = "RUNNING"
		-- A resume is a SECOND token change, not a return to the pre-pause value.
		-- A job that slept straight through the whole borrow must still be
		-- cancelled: every field and every attribute it was going to write against
		-- has been snapshotted and written back underneath it, so letting it wake
		-- into a matching token would hand it a session that is no longer the one it
		-- was queued for. Monotone, never rewound -- that is what makes "the job's
		-- token can never match again" in the hand-back contract above a proof
		-- rather than a hope.
		bumpRunToken(session)
		session.PauseHandle = nil
		unregisterParked(session)
		decrementPauseDepth(session)
		activeSession = session
	end, function()
		activeSession = nil
		incrementPauseDepth(session)
		registerParked(session, handle)
		session.PauseHandle = handle
		session.Phase = "PAUSED"
		-- Back to the token the PARKED session was holding. A rolled-back resume
		-- has to be indistinguishable from a resume that was never attempted, and
		-- the handle stays usable for a second attempt.
		if phaseTokenBefore ~= nil then session.RunToken = phaseTokenBefore end
	end)

	if failure then
		for index = #undo, 1, -1 do
			local rolledBack, rollbackError = pcall(undo[index])
			if not rolledBack then
				warn("[Level 2 Slidemouth] resume rollback failed: " .. tostring(rollbackError))
			end
		end
		return false, "resume failed: " .. failure
	end
	handle.ResumedAtMonotonic = resumedAtMonotonic
	handle.ResumedAtServer = resumedAtServer
	handle.Consumed = true
	return true
end

-- TRUE when ANY session is parked, not merely when the active one somehow says
-- PAUSED. A successful pause sets activeSession = nil, so the old reading --
-- `activeSession` first, then its Phase -- answered FALSE for exactly the state
-- it was written to detect. A suite residue check written as
-- `if Controller.DebugIsPaused() then ...` could therefore never fire.
function Controller.DebugIsPaused(): boolean
	if parkedCount > 0 then return true end
	local session = activeSession
	return session ~= nil and session.Phase == "PAUSED"
end

-- How many sessions are parked right now. A clean suite ends on 0.
function Controller.DebugParkedCount(): number
	return parkedCount
end

-- The outstanding borrow debt of one session -- the one a handle names, or the
-- one resolveDebugSession would pick. Zero means nothing is holding it.
function Controller.DebugPauseDepth(handle): number
	local session = sessionFromHandle(handle) or resolveDebugSession(nil)
	if not session then return 0 end
	return tonumber(session.PauseDepth) or 0
end

-- Everything a residue check needs in one read, including the leak that used to
-- be uncountable: a PARKED session's runtime folder has Parent = nil by design,
-- so "count the runtime folders left in the world" scored a leaked parked
-- session as clean. OrphanRuntimeFolders counts them from the registry side
-- instead, where being detached is the evidence rather than the hiding place.
function Controller.DebugResidue()
	local depth = 0
	local orphanRuntimeFolders = 0
	for session in pairs(parkedSessions) do
		depth += tonumber(session.PauseDepth) or 0
		if session.RuntimeFolder ~= nil and session.RuntimeFolder.Parent == nil then
			orphanRuntimeFolders += 1
		end
	end
	if activeSession then depth += tonumber(activeSession.PauseDepth) or 0 end
	return {
		Parked = parkedCount,
		Active = activeSession ~= nil,
		PauseDepth = depth,
		OrphanRuntimeFolders = orphanRuntimeFolders,
	}
end

-- Studio-only. The RAW references, resolved the same way every other reader
-- resolves one. GetFullDebugSnapshot reports instances as GetFullName() strings,
-- which two different Instances at the same path share -- so a test that has to
-- prove "this is the SAME model, not a look-alike rebuilt at the same place"
-- cannot use them. Identity comparison needs the objects themselves.
function Controller.DebugSessionRefs(handle)
	if not RunService:IsStudio() then return nil end
	local session = resolveDebugSession(handle)
	if not session then return nil end
	return {
		Session = session,
		Model = session.Model,
		RuntimeFolder = session.RuntimeFolder,
		Navigator = session.Navigator,
		Phase = session.Phase,
	}
end

function Controller.DebugPauseHandleValid(handle): (boolean, string?)
	if type(handle) ~= "table" or type(handle.Session) ~= "table" then
		return false, "not a pause handle"
	end
	if handle.Consumed then return false, "already used" end
	if handle.Session.Phase ~= "PAUSED" then return false, "session is " .. tostring(handle.Session.Phase) end
	return true
end

-- The phase of the session a handle refers to, for a test that has to prove the
-- incumbent survived a borrow that threw.
function Controller.DebugSessionPhase(handle): string?
	-- Falls through to the same resolution every other reader uses, so a PARKED
	-- session asked about without a handle reports "PAUSED" rather than nil --
	-- nil used to be the answer for both "no session" and "a session nobody can
	-- see from here", which are not the same fact.
	local session = sessionFromHandle(handle) or resolveDebugSession(nil)
	return session and session.Phase or nil
end

-- Studio-only. Who the LIVE session currently counts, read through the same
-- livingRecord() gate the spawn uses -- round state, InRound, Escaped, a living
-- humanoid and a root part. A suite that wants to prove a dropped-out player
-- stops constraining the map has to read this; handing EvaluateSpawn an empty
-- synthetic party proves only that an empty list is empty.
function Controller.DebugEligibleRecords()
	if not RunService:IsStudio() then return nil end
	local session = activeSession
	if not session then return nil end
	local out = {}
	for _, record in ipairs(livingRecords(session)) do
		table.insert(out, {
			UserId = record.Player.UserId,
			Name = record.Player.Name,
			Position = vectorTable(record.Root.Position),
		})
	end
	return out
end

-- Studio-only. The ranking the LIVE session would commit right now, built from
-- its real eligibility rather than from positions a test made up.
function Controller.DebugRankLiveCandidates(recovery)
	if not RunService:IsStudio() then return nil end
	local session = activeSession
	if not session then return nil end
	local records = livingRecords(session)
	local context = applyPumpContext(session, roomContext(session, records), SPAWN_PUMPS)
	local ranked = rankedSpawnCandidates(session, records, recovery == true, context)
	local candidates = {}
	for _, candidate in ipairs(ranked) do
		table.insert(candidates, {
			Anchor = candidate.Anchor.Name,
			HallIndex = candidate.HallIndex,
			Hops = candidate.Hops,
			PumpHops = candidate.PumpHops,
			Distance = candidate.Distance,
			Hidden = candidate.Hidden,
			Tier = candidate.Tier,
		})
	end
	return {
		RecordCount = #records,
		Candidates = candidates,
		Chosen = candidates[1],
		Occupied = context.Occupied,
		PumpHallIndex = context.PumpHallIndex,
	}
end

-- The COMPLETE comparable surface of a live session, for a test that has to
-- prove an incumbent came back exactly as it was lent out.
--
-- GetDebugSnapshot below reports the interesting few, and reports the navigator
-- as counts -- which cannot tell a restored trail from a different trail of the
-- same length, or a restored waypoint list from a fresh one. A borrow that
-- corrupts the incumbent inside those blind spots looks identical.
--
-- Timers are reported as REMAINING durations rather than absolute readings,
-- because comparing two absolute os.clock values across a pause would fail even
-- on a perfect restore -- and rounding them to a whole second is what lets
-- "these timers did not age" be a real assertion rather than a coin toss.
-- Studio-only. Put the live session into the state a pause has to survive.
--
-- Every way the old suspend corrupted an incumbent needed a creature in the
-- MIDDLE of something, and a session that has just been started is in the middle
-- of nothing -- which is exactly why a suite that only ever borrowed a fresh one
-- reported that everything had been restored.
--
-- WHAT WENT WRONG: arming mutated at least the Level2Pumps world attribute, the
-- session's scream bookkeeping for one pump, LastPumps, SEVEN deadline fields,
-- ProgressAt, the navigator's goal, and two state-folder attributes -- and
-- recorded NONE of it. DebugDisarmPauseTest was two lines that cleared a
-- pointer. Every mutation therefore survived the "cleanup" and leaked into
-- whatever ran next, and an arm that failed half way left the world in that
-- half-armed state with nothing to unwind it.
--
-- WHAT ALSO SHIPPED BROKEN, and is the reason this function can now REFUSE:
-- arming raised Level2Pumps on a PRE-EXISTING production session until the
-- incumbent grew a creature, and the code admitted in its own comment that this
-- could not be undone. A test harness was permanently advancing a live round --
-- the creature spawned early, its spawn attributes were published, and disarm
-- put the pump COUNT back while leaving every consequence of it in the world.
--
-- The rule now, field by field, is (a) reversible or (b) refuse:
--
--   (a) REVERSIBLE, and restored provably from restore.* below, every reading
--       taken before the first mutation: Level2Pumps, LastPumps, ProgressAt, all
--       EIGHT PAUSE_DEADLINE_FIELDS, the three pump-scream tables, the navigator
--       (through Navigator:Snapshot/Restore) and the two probe state attributes.
--       DebugPauseProbeResidue() re-reads every one of them afterwards and
--       reports any that is still holding the value the ARM wrote.
--
--   (b) REFUSED, because spawning is irreversible: when there is no creature yet
--       AND Level2Pumps is below SPAWN_PUMPS, arming would have to RAISE the
--       pump count on a session it did not create, and a creature grown that way
--       cannot be un-spawned. That returns `nil, "<reason>"` and the caller takes
--       a declared branch -- pump the round itself, or start its own session --
--       rather than having a production session advanced underneath it.
--       `options.AllowIrreversibleSpawn = true` is the explicit opt-in for a
--       caller that owns the session and accepts the cost; the cost is then
--       listed in armed.Irreversible and reported by the residue reader.
--
--       The refusal is scoped to the MUTATION, not to the situation: if the round
--       has already pumped to SPAWN_PUMPS and the incumbent is merely still
--       spawning, arming waits for it and refuses nothing, because waiting
--       changes no state. It re-reads its whole pre-image after that wait, so
--       everything the incumbent advanced during it belongs to the round and not
--       to the disarm.
--
-- One reversible-looking mutation is honestly only PARTLY reversible, and is
-- listed in armed.Irreversible whenever it applies:
--
--   * schedulePumpScream spawns a live job. A spawned thread cannot be
--     unspawned. Disarm instead restores the entries the job's OWN gate reads --
--     PumpScreamScheduled/Played/Fired for the probe pump, and the Level2Pumps
--     count. With Level2Pumps back BELOW the probe pump the job's
--     `workspace.Level2Pumps >= pumpNumber` test fails and it returns without
--     touching anything, which is what makes it inert rather than merely late.
--
-- `options.NavigatorMode` selects what the navigator is left holding:
--   "computing" (default) -- a path request in flight, armed.NavigatorRequesting
--   "blocked"             -- a settled route WITH a live Path.Blocked binding,
--                            which is the only state that exercises the
--                            HadBlockedConnection half of a navigator resume.
function Controller.DebugArmForPauseTest(options)
	if not RunService:IsStudio() then return nil, "not Studio" end
	local session = activeSession
	if not session or session.Phase ~= "RUNNING" then return nil, "no running session" end
	local state = stateFolder()
	if not state then return nil, "no state folder" end
	options = type(options) == "table" and options or {}

	local screamIn = tonumber(options.ScreamInSeconds) or 6
	local deadlineIn = tonumber(options.DeadlineInSeconds) or 0.75
	local presentName = options.PresentAttribute or "Level2_SlidemouthPauseProbePresent"
	local absentName = options.AbsentAttribute or "Level2_SlidemouthPauseProbeAbsent"
	local presentValue = 4242
	local requestedMode = options.NavigatorMode == "blocked" and "blocked" or "computing"

	-- A failed pause probe may deliberately leave the active throwaway session
	-- holding a destroyed Navigator.  A destroyed Navigator can still accept a
	-- Lua-side Path.Blocked connection, but that connection is not live: every
	-- callback immediately exits on `self.Destroyed`.  Treating that synthetic
	-- connection as a successful blocked arm also publishes a second pause probe
	-- over the incumbent's existing undo list.  Refuse before the first mutation
	-- so the caller gets the honest no-binding branch and the earlier probe stays
	-- responsible for its own restore.
	if session.Navigator and session.Navigator.Destroyed == true then
		if requestedMode == "blocked" then
			return nil, "could not arm a live Blocked binding"
		end
		return nil, "navigator is destroyed"
	end

	-- THE COMPLETE RESTORE SET. The scream tables are cloned WHOLE rather than by
	-- pump number, because the probe pump is derived from a count this function may
	-- change -- capturing the whole table is the only way to record it before the
	-- first mutation.
	local restore = {StateAttributeNames = {presentName, absentName}}
	-- What the arm WROTE, filled in as each stage applies. The residue reader
	-- compares against THIS, not against restore: a field is "still armed" when it
	-- currently holds the arm's own value AND that value differs from the
	-- pre-image. Comparing against restore alone would report every legitimate
	-- advance the live incumbent makes after a clean disarm as residue.
	local applied = {Deadlines = {}, StateAttributes = {}}
	-- Everything the arm could not put back, in the caller's own words. Empty is
	-- the normal, refusing-rather-than-mutating outcome.
	local irreversible = {}

	-- The pre-image, as ONE function, because it is taken more than once. The
	-- second reading is what makes "read BEFORE the first mutation" true on the
	-- path that has to WAIT for the incumbent to finish spawning: the incumbent
	-- keeps running through that wait and legitimately advances its own deadlines,
	-- its scream tables and even the pump count, and a pre-image taken before the
	-- wait would make disarm rewind the round's own progress rather than the arm's.
	--
	-- `skipPumps` is the one exception, and it exists for exactly one caller: the
	-- opted-in path that RAISED Level2Pumps itself. That raise is the arm's own
	-- mutation and must still be undone, so its pre-image is deliberately kept from
	-- the very first reading and not overwritten by the second.
	local function readPreImage(skipPumps)
		if not skipPumps then restore.Level2Pumps = workspace:GetAttribute("Level2Pumps") end
		restore.LastPumps = session.LastPumps
		restore.ProgressAt = session.ProgressAt
		restore.Deadlines = {}
		for _, name in ipairs(PAUSE_DEADLINE_FIELDS) do
			restore.Deadlines[name] = session[name]
		end
		restore.PumpScreamScheduled = table.clone(session.PumpScreamScheduled)
		restore.PumpScreamPlayed = table.clone(session.PumpScreamPlayed)
		restore.PumpScreamFired = table.clone(session.PumpScreamFired)
		-- A nil here is the POINT: an attribute that was absent has to go back to
		-- absent, and SetAttribute(name, nil) is how. StateAttributeNames carries the
		-- names so the absences survive the round trip through this table.
		restore.StateAttributes = {}
		for _, name in ipairs(restore.StateAttributeNames) do
			restore.StateAttributes[name] = state:GetAttribute(name)
		end
		-- Read but NOT written by any stage below. They are here because "Restore
		-- captures every field arm touches" is only checkable if a caller can also
		-- see the fields arm promises NOT to touch: a residue check that finds
		-- Spawned, Escalating, the phase or the run token moved has caught the arm
		-- reaching further than it declares. The serials additionally bound the one
		-- partly-irreversible mutation -- a scream the armed job manages to fire
		-- shows up here as a serial that advanced, and a replicated scream cannot be
		-- un-replicated.
		restore.Phase = session.Phase
		restore.RunToken = session.RunToken
		restore.Spawned = session.Spawned
		restore.Escalating = session.Escalating
		restore.WarningSerial = session.WarningSerial
		restore.ScreamSerial = session.ScreamSerial
		restore.State = session.State
		if session.Navigator then
			restore.Navigator = session.Navigator:Snapshot()
			restore.NavigatorCaptured = true
		else
			restore.Navigator = nil
			restore.NavigatorCaptured = false
		end
	end
	readPreImage(false)
	-- Stays TRUE unless a stage below writes something before the LAST pre-image
	-- reading. Only the opted-in pump raise can do that, and it clears this flag,
	-- so a caller can tell a pre-image it may trust completely from one taken
	-- across a mutation this function had already made.
	restore.CapturedBeforeAnyMutation = true

	local undo = {}
	local failure
	local function apply(name, fn, rollback)
		if failure then return end
		local ok, err = pcall(fn)
		if ok then
			if rollback then table.insert(undo, rollback) end
		else
			failure = name .. ": " .. tostring(err)
		end
	end
	-- Deliberately does NOT touch Controller._pauseProbe. A failing arm never
	-- published itself there, so clearing it would throw away a DIFFERENT arm's
	-- undo list -- the one thing standing between an earlier probe and a
	-- permanently mutated world.
	local function unwind(reason)
		for index = #undo, 1, -1 do
			local ok, err = pcall(undo[index])
			if not ok then
				warn("[Level 2 Slidemouth] arm rollback failed: " .. tostring(err))
			end
		end
		return nil, reason
	end

	-- There must be a CREATURE to borrow: a navigator, a model, a plan. The
	-- Slidemouth only exists from the spawn pump onward, and a session that has
	-- not spawned has none of the state a pause has to preserve -- which is
	-- exactly the emptiness that made a borrow look harmless.
	--
	-- THE REFUSAL. This function used to raise Level2Pumps on whatever production
	-- session happened to be running and wait for it to grow a creature. That is a
	-- test harness permanently advancing a live round, and its own comment said so.
	-- Nothing below has mutated anything yet, so refusing here is free: the world
	-- is exactly as it was found, `undo` is empty, and no probe is published.
	local pumps = math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0)
	if not (session.Spawned and session.Navigator) then
		-- The refusal is scoped to the mutation, not to the situation. Waiting for a
		-- spawn the ROUND has already ordered (Level2Pumps is at or above the spawn
		-- pump and the incumbent simply has not finished) changes nothing and is
		-- allowed. RAISING the count to force one is the irreversible act, and that
		-- is what refuses.
		local mustRaise = pumps < SPAWN_PUMPS
		if mustRaise and options.AllowIrreversibleSpawn ~= true then
			return nil, "the incumbent has not spawned a creature: arming one would have to raise "
				.. "Level2Pumps from " .. tostring(pumps) .. " to " .. tostring(SPAWN_PUMPS)
				.. " on a session this call did not create, and a spawned creature cannot be "
				.. "un-spawned. Pump the round to " .. tostring(SPAWN_PUMPS)
				.. " yourself, or pass options.AllowIrreversibleSpawn = true"
		end
		if mustRaise then
			-- The declared opt-in. Everything it costs is recorded HERE rather than in
			-- a comment, so DebugDisarmPauseTest and DebugPauseProbeResidue report it
			-- instead of quietly implying a clean restore.
			table.insert(irreversible,
				"Level2Pumps raised from " .. tostring(restore.Level2Pumps) .. " to "
				.. tostring(SPAWN_PUMPS) .. " to force a spawn; the count is restored on disarm "
				.. "but the creature, its runtime model and its published spawn attributes are not")
			apply("pumps", function()
				workspace:SetAttribute("Level2Pumps", SPAWN_PUMPS)
				applied.Level2Pumps = SPAWN_PUMPS
				pumps = SPAWN_PUMPS
			end, function()
				workspace:SetAttribute("Level2Pumps", restore.Level2Pumps)
			end)
			if failure then return unwind(failure) end
		end

		local spawnDeadline = os.clock() + 15
		while os.clock() < spawnDeadline and not (session.Spawned and session.Navigator) do
			task.wait(0.2)
		end
		if not (session.Spawned and session.Navigator) then
			return unwind("the incumbent never spawned a creature to borrow")
		end
		-- RE-READ the pre-image now the wait is over. The incumbent ran for up to
		-- fifteen seconds in there and moved its own deadlines, its scream tables and
		-- its navigator; restoring the readings from BEFORE the wait would make
		-- disarm rewind the round's own progress instead of the arm's. Level2Pumps is
		-- the deliberate exception on the raising path -- that raise is ours to undo.
		readPreImage(mustRaise)
		pumps = math.floor(tonumber(workspace:GetAttribute("Level2Pumps")) or 0)
		if mustRaise then restore.CapturedBeforeAnyMutation = false end
	end
	if not restore.NavigatorCaptured then
		restore.Navigator = session.Navigator:Snapshot()
		restore.NavigatorCaptured = true
	end

	-- A pending, unplayed scream, due DURING the borrow. It is armed on a pump
	-- the heartbeat has NOT reached, and LastPumps is advanced past it first, so
	-- arming cannot itself trigger the pump-transition escalation.
	local pump = math.max(math.floor(tonumber(options.ScreamPump) or 0),
		pumps + 1, FAST_PUMPS + 1)
	-- The spawned scream job is the one mutation this stage cannot fully take
	-- back, so it is declared rather than implied.
	table.insert(irreversible,
		"schedulePumpScream spawned a job for pump " .. tostring(pump)
		.. "; the thread cannot be unspawned, and disarm makes it INERT instead by "
		.. "restoring Level2Pumps below that pump, which is the gate the job reads")
	apply("scream", function()
		session.PumpScreamPlayed[pump] = nil
		session.PumpScreamScheduled[pump] = nil
		schedulePumpScream(session, pump)
		session.PumpScreamScheduled[pump] = workspace:GetServerTimeNow() + screamIn
		session.LastPumps = math.max(session.LastPumps, pump)
		workspace:SetAttribute("Level2Pumps", pump)
		applied.ScreamPump = pump
		applied.LastPumps = session.LastPumps
		applied.PumpScreamScheduled = session.PumpScreamScheduled[pump]
		applied.Level2Pumps = pump
	end, function()
		-- Level2Pumps goes back FIRST, ahead of LastPumps, and the order is
		-- load-bearing in a way the old comment had exactly backwards. The scream
		-- job reads Level2Pumps at its own FIRE time, long after this whole undo has
		-- run, so no ordering here can change what it sees. What ordering CAN change
		-- is the window in between: with LastPumps lowered first there is an instant
		-- where LastPumps < FAST_PUMPS <= Level2Pumps, which is precisely the edge
		-- the heartbeat reads as "escalate now" -- a disarm that launched a
		-- pump-three escalation would be the loudest possible residue. Lowering the
		-- pump count first means that edge never exists.
		workspace:SetAttribute("Level2Pumps", restore.Level2Pumps)
		session.LastPumps = restore.LastPumps
		session.PumpScreamScheduled[pump] = restore.PumpScreamScheduled[pump]
		session.PumpScreamPlayed[pump] = restore.PumpScreamPlayed[pump]
		session.PumpScreamFired[pump] = restore.PumpScreamFired[pump]
	end)

	-- Deadlines about to expire. Under the old suspend these kept counting, so
	-- the first resumed heartbeat fired every one of them at once.
	local now = os.clock()
	apply("deadlines", function()
		for _, name in ipairs({"NextTargetRefreshAt", "NextTargetSwitchAt", "AttackCooldownUntil",
			"RecoveryUntil", "GraphRecoveryUntil", "WanderGoalUntil", "WanderMoveDeadline"}) do
			session[name] = now + deadlineIn
			applied.Deadlines[name] = session[name]
		end
		-- A stamp an AGE is measured from, already most of the way to its window.
		session.ProgressAt = now - deadlineIn
		applied.ProgressAt = session.ProgressAt
	end, function()
		-- All EIGHT go back, not the seven that were written: restoring
		-- SpawnRetryAt to its own value is free, and a list that matches
		-- PAUSE_DEADLINE_FIELDS exactly cannot fall behind it.
		for _, name in ipairs(PAUSE_DEADLINE_FIELDS) do
			session[name] = restore.Deadlines[name]
		end
		session.ProgressAt = restore.ProgressAt
	end)

	-- The navigator. Two studs, not eight: the goal has to stay inside the hall
	-- the creature is actually in, or SetGoal refuses it and nothing is in flight
	-- to preserve.
	local requesting = false
	local blocked = false
	local achievedMode = "none"
	if not failure then
		local navigator = session.Navigator
		local position = navigator and navigator:GetPosition()
		if not position then
			failure = "navigator: the navigator has no position"
		else
			local goalSet, goalError = pcall(function()
				navigator:SetGoal(position + Vector3.new(2, 0, 2), true)
			end)
			if not goalSet then
				failure = "navigator: " .. tostring(goalError)
			else
				applied.NavigatorGoal = true
				table.insert(undo, function()
					if session.Navigator and restore.Navigator then
						session.Navigator:Restore(restore.Navigator)
					end
				end)
				-- Navigator:Restore is deliberately side-effect free, so a request the
				-- arm left in flight can still land afterwards and overwrite the
				-- restored route. Declared, not hidden.
				table.insert(irreversible,
					"a navigator path request was started by the arm; Navigator:Restore puts the "
					.. "route back but cannot cancel an in-flight ComputeAsync, which may land "
					.. "after the disarm and overwrite it")
				if requestedMode == "blocked" then
					-- A Blocked binding only exists once PathfindingService has
					-- returned a usable route, so this waits for the request to
					-- SETTLE rather than assuming it did. Bounded at ~6 seconds
					-- because a hall with no computable route would otherwise
					-- hang the suite instead of failing it.
					local bindDeadline = os.clock() + 6
					while os.clock() < bindDeadline do
						if navigator:HasBlockedConnection() and navigator.Computing ~= true then
							break
						end
						task.wait(0.1)
					end
					if not (navigator:HasBlockedConnection()
						and navigator.Computing ~= true) then
						-- A nearby valid goal can settle as ARRIVED without retaining a Path,
						-- so there is then no Blocked signal for the controller-level borrow
						-- to carry. This Studio-only seam installs a real Path.Blocked
						-- connection on the incumbent's real Navigator deterministically. The
						-- RequestId bump fences out the superseded ComputeAsync, and the arm's
						-- existing Snapshot/Restore undo owns every field changed here.
						navigator.RequestId += 1
						navigator.Computing = false
						navigator:_clearBlocked()
						navigator:_bindBlocked(game:GetService("PathfindingService"):CreatePath())
					end
					if navigator:HasBlockedConnection() and navigator.Computing ~= true then
						blocked = true
						achievedMode = "blocked"
					else
						return unwind("could not arm a live Blocked binding")
					end
				else
					requesting = navigator.Computing == true
					achievedMode = "computing"
				end
			end
		end
	end

	-- One attribute PRESENT and one deliberately ABSENT, so the restore has to
	-- carry a nil as well as a value.
	apply("attributes", function()
		state:SetAttribute(presentName, presentValue)
		state:SetAttribute(absentName, nil)
		applied.StateAttributes[presentName] = presentValue
		-- The absent one is recorded as an EXPLICIT nil marker rather than by
		-- omission: a Lua table cannot hold a nil, and "arm wrote nothing here" and
		-- "arm wrote an absence here" are different claims for a residue check to
		-- make. The reader tests applied.AbsentAttribute by name instead.
		applied.AbsentAttribute = absentName
	end, function()
		for _, name in ipairs(restore.StateAttributeNames) do
			state:SetAttribute(name, restore.StateAttributes[name])
		end
	end)

	if failure then return unwind(failure) end

	local armed = {
		Session = session,
		StateInstance = state,
		ScreamPump = pump,
		ScreamDueIn = screamIn,
		NavigatorRequesting = requesting,
		NavigatorBlocked = blocked,
		NavigatorMode = achievedMode,
		PresentAttribute = presentName,
		PresentValue = presentValue,
		AbsentAttribute = absentName,
		WarningSerialBefore = session.WarningSerial,
		ScreamSerialBefore = session.ScreamSerial,
		-- Everything read before the first mutation, for a caller that wants to
		-- assert against the pre-arm world itself.
		Restore = restore,
		-- Everything the arm WROTE. Restore says what the world was; this says what
		-- the arm made of it, and the pair is what lets DebugPauseProbeResidue tell
		-- "the arm's value is still sitting there" from "the live incumbent has
		-- moved on since the disarm", which are indistinguishable from Restore alone.
		Applied = applied,
		-- What the arm could not put back, in plain words. On the default path this
		-- is the spawned scream job and, if a path request was started, the
		-- in-flight ComputeAsync. It gains the forced spawn ONLY when the caller
		-- passed AllowIrreversibleSpawn.
		Irreversible = irreversible,
		AllowedIrreversibleSpawn = options.AllowIrreversibleSpawn == true,
		-- The inverse of every mutation that was actually APPLIED, newest last.
		-- Disarm walks it backwards; it is the restore, not a description of one.
		Undo = undo,
		Disarmed = false,
		DisarmProblems = nil,
	}
	Controller._pauseProbe = armed
	-- Kept after a disarm clears the live pointer, so DebugPauseProbeResidue can
	-- still answer "did everything the arm applied actually go back". A residue
	-- reader that forgets the probe the moment it is disarmed can only ever report
	-- on probes that were never cleaned up.
	Controller._lastPauseProbe = armed
	return armed
end

-- Which of the arm's own mutations are STILL APPLIED right now, by name.
--
-- A residue reader cannot work by comparing against the pre-image: the incumbent
-- goes on running through the arm and the disarm, and legitimately re-advances
-- NextTargetRefreshAt, Level2Pumps and the rest within a frame of getting them
-- back. Comparing "current vs. what the arm WROTE" instead makes a false
-- positive require the live session to land on the arm's exact value by
-- coincidence -- an os.clock deadline pinned to a specific past instant, or a
-- probe attribute holding 4242.
--
-- `handleOrNil` is optional; without it the CURRENT probe is read, and after a
-- disarm has cleared that pointer, the LAST one. Reporting only on probes that
-- were never cleaned up would make the reader useless for the one question that
-- matters: did the disarm actually work.
function Controller.DebugPauseProbeResidue(handleOrNil)
	local armed = handleOrNil
	if type(armed) ~= "table" then
		armed = Controller._pauseProbe or Controller._lastPauseProbe
	end
	if type(armed) ~= "table" then
		return {Probe = false, Armed = false, Disarmed = true, Applied = {}, AppliedCount = 0,
			Irreversible = {}, Clean = true}
	end
	local restore = type(armed.Restore) == "table" and armed.Restore or {}
	local applied = type(armed.Applied) == "table" and armed.Applied or {}
	local session = armed.Session
	local still = {}
	-- A field counts as residue only when it currently holds the ARM's value AND
	-- that value actually differed from the pre-image. Without the second half, an
	-- arm that happened to write back the value it found would be reported as
	-- permanent residue that no disarm could ever clear.
	local function check(name, current, appliedValue, restoredValue)
		if appliedValue == nil then return end
		if appliedValue == restoredValue then return end
		if current == appliedValue then table.insert(still, name) end
	end

	check("Level2Pumps", workspace:GetAttribute("Level2Pumps"),
		applied.Level2Pumps, restore.Level2Pumps)
	if type(session) == "table" then
		check("LastPumps", session.LastPumps, applied.LastPumps, restore.LastPumps)
		check("ProgressAt", session.ProgressAt, applied.ProgressAt, restore.ProgressAt)
		for name, value in pairs(applied.Deadlines or {}) do
			check(name, session[name], value, (restore.Deadlines or {})[name])
		end
		if applied.ScreamPump ~= nil then
			check("PumpScreamScheduled[" .. tostring(applied.ScreamPump) .. "]",
				session.PumpScreamScheduled[applied.ScreamPump],
				applied.PumpScreamScheduled,
				(restore.PumpScreamScheduled or {})[applied.ScreamPump])
		end
		-- Fields the ARM promises not to touch at all. A mismatch is the arm having
		-- reached further than it declares -- the fault B9 was written about -- so it
		-- is reported under its own prefix rather than folded in above.
		--
		-- The run token is deliberately NOT one of them, and this is the difference
		-- between residue and history. The whole point of a pause probe is to be
		-- borrowed, and a borrow bumps the token twice; treating that as residue
		-- would make every correct arm-pause-resume-disarm cycle fail its own
		-- cleanup check. It is reported below as a reading instead, where a suite can
		-- assert the opposite -- that the token DID move, and that the borrow
		-- therefore really did cancel the in-flight work.
		if restore.Spawned ~= nil and session.Spawned ~= restore.Spawned then
			table.insert(still, "UNDECLARED:Spawned")
		end
		if session.Phase ~= restore.Phase then table.insert(still, "UNDECLARED:Phase") end
	end
	local state = armed.StateInstance
	if state and state.Parent then
		for name, value in pairs(applied.StateAttributes or {}) do
			check(name, state:GetAttribute(name), value, (restore.StateAttributes or {})[name])
		end
		-- The ABSENCE the arm wrote. Residue here is the attribute still being gone
		-- when the pre-image had a value: an absence cannot be compared by equality
		-- through a Lua table, which is why it travels by name instead.
		local absentName = applied.AbsentAttribute
		if absentName ~= nil and (restore.StateAttributes or {})[absentName] ~= nil
			and state:GetAttribute(absentName) == nil then
			table.insert(still, absentName)
		end
	end

	return {
		Probe = true,
		-- TRUE only while this probe is the LIVE one. After a disarm it is false and
		-- the reader is answering about a probe that has already been cleaned up.
		Armed = Controller._pauseProbe == armed,
		Disarmed = armed.Disarmed == true,
		Applied = still,
		AppliedCount = #still,
		-- Copied, not handed out: a caller must not be able to edit the record of
		-- what could not be undone.
		Irreversible = table.clone(armed.Irreversible or {}),
		AllowedIrreversibleSpawn = armed.AllowedIrreversibleSpawn == true,
		CapturedBeforeAnyMutation = restore.CapturedBeforeAnyMutation == true,
		-- History, not residue. Equal means nothing borrowed this session between
		-- the arm and now; a difference of two is one clean pause/resume round trip.
		RunTokenAtArm = restore.RunToken,
		RunTokenNow = type(session) == "table" and session.RunToken or nil,
		DisarmProblems = armed.DisarmProblems,
		Clean = #still == 0,
	}
end

-- Undo everything the arm did, in reverse order. Returns (true) or
-- (false, reason).
--
-- Safe to call twice: the probe pointer is cleared first, so a second call finds
-- nothing and reports success. Safe to call when arming FAILED: a failed arm
-- unwinds itself and never publishes a probe, so there is nothing here to undo.
--
-- It does NOT stop, pause or resume anything. The incumbent keeps running
-- throughout; only the values the arm changed go back. Note that the navigator
-- half goes back through Navigator:Restore(), which is deliberately free of side
-- effects -- a path request the arm left in flight is still in flight and can
-- land afterwards and overwrite the restored route. A caller that needs the
-- navigator quiescent as well has to borrow it properly.
--
-- WHAT SHIPPED BROKEN: this reported success as long as no undo THREW. It never
-- asked whether the undos had actually put anything back, so an undo list that
-- was simply MISSING a mutation -- which is exactly what B9 found -- returned
-- true while the arm's values were still sitting in the world. It now re-reads
-- every mutation it applied through DebugPauseProbeResidue and fails honestly
-- when one is still there. What it does NOT call a failure is an opted-in
-- irreversible spawn: the caller asked for that in writing, so it is reported
-- through Irreversible rather than through the return value.
--
-- It DOES fail on being called while a borrow is still outstanding: the session
-- reads PAUSED where the arm found RUNNING, and the residue check reports
-- UNDECLARED:Phase. That is deliberate. Disarming underneath a live pause handle
-- restores values the handle is holding a snapshot of and is about to write back
-- over, so it cannot honestly report success. Resume first, then disarm.
function Controller.DebugDisarmPauseTest(): (boolean, string?)
	local armed = Controller._pauseProbe
	Controller._pauseProbe = nil
	if type(armed) ~= "table" then return true end
	if armed.Disarmed == true then return true end
	armed.Disarmed = true

	local problems = {}
	local undo = armed.Undo
	if type(undo) == "table" then
		for index = #undo, 1, -1 do
			local ok, err = pcall(undo[index])
			if not ok then table.insert(problems, tostring(err)) end
		end
	end
	-- The verification half. Reading the world back is the only thing that can
	-- tell "every undo ran" from "everything actually went back".
	local checked, residue = pcall(Controller.DebugPauseProbeResidue, armed)
	if not checked then
		table.insert(problems, "residue check failed: " .. tostring(residue))
	elseif type(residue) == "table" and residue.AppliedCount > 0 then
		table.insert(problems,
			"still applied after undo: " .. table.concat(residue.Applied, ", "))
	end
	if #problems > 0 then
		armed.DisarmProblems = problems
		return false, table.concat(problems, "; ")
	end
	return true
end

-- `handle` is OPTIONAL and only consulted when there is no ACTIVE session, which
-- is precisely the situation a pause creates. Reading `activeSession` alone
-- meant a paused session answered "no scream has played" because there was
-- nothing to ask -- not because nothing had played. The suite's central
-- assertion, "the pending scream did NOT fire while the session was paused", was
-- therefore true of every possible implementation.
function Controller.DebugScreamPlayed(pump, handle): boolean
	local session = resolveDebugSession(handle)
	return session ~= nil and session.PumpScreamPlayed[pump] == true
end

-- How many scream events this pump has produced since the arm. Counted off the
-- SERIALS, which are what clients actually react to, so "exactly once" is an
-- assertion about the replicated event and not merely about a boolean flag.
-- -1 still means "there was no session to ask", which is not the same as 0.
function Controller.DebugScreamCount(pump, handle): number
	local session = resolveDebugSession(handle)
	if not session then return -1 end
	return session.PumpScreamFired[pump] or 0
end

function Controller.DebugWaitForScream(pump, timeoutSeconds, handle): boolean
	local deadline = os.clock() + (tonumber(timeoutSeconds) or 10)
	while os.clock() < deadline do
		if Controller.DebugScreamPlayed(pump, handle) then return true end
		task.wait(0.1)
	end
	return Controller.DebugScreamPlayed(pump, handle)
end

-- `handle` is OPTIONAL and resolved exactly as the scream readers resolve one:
-- the active session, else the session a handle names, else the sole parked one.
-- Without it a PARKED session was undescribable -- the snapshot returned
-- `{Running = false}` and nothing else, so "the incumbent survived the borrow"
-- could not be checked while the borrow was still happening.
--
-- `Running` stays honest: a parked session is not running, and this must not
-- start claiming it is. `Parked` is the field that says which of the two kinds
-- of not-running this is.
function Controller.GetFullDebugSnapshot(handle)
	local session = resolveDebugSession(handle)
	if not session then return {Running = false} end
	local now = os.clock()
	local pivot = session.Model and session.Model.PrimaryPart
		and session.Model:GetPivot() or nil
	local snapshot = {
		Running = sessionAlive(session),
		Parked = parkedSessions[session] ~= nil,
		Phase = session.Phase,
		Generation = session.Generation,
		SessionIdentity = tostring(session),
		ModelIdentity = session.Model and session.Model:GetFullName() or nil,
		RuntimeIdentity = session.RuntimeFolder and session.RuntimeFolder:GetFullName() or nil,
		ModelPivot = pivot and vectorTable(pivot.Position) or nil,
		-- POSITION ALONE cannot see an orientation-only corruption: a borrow that
		-- rotated the creature 90 degrees and put it down on the same spot
		-- produced an identical ModelPivot. All twelve components make the whole
		-- CFrame comparable.
		ModelPivotComponents = pivot and {pivot:GetComponents()} or nil,
		Timers = {},
		Values = {},
		Screams = {},
		StateAttributes = {},
		ModelAttributes = {},
	}
	for _, name in ipairs({"NextTargetRefreshAt", "NextTargetSwitchAt", "AttackCooldownUntil",
		"RecoveryUntil", "GraphRecoveryUntil", "WanderGoalUntil", "WanderMoveDeadline",
		"SpawnRetryAt", "ProgressAt"}) do
		local value = session[name]
		if type(value) == "number" and value == value
			and value ~= 0 and value ~= math.huge and value ~= -math.huge then
			-- Whole seconds: the point is "did this age across the borrow", not
			-- "did it survive to the microsecond".
			snapshot.Timers[name] = math.floor(value - now)
		else
			snapshot.Timers[name] = value
		end
	end
	-- RunToken and the three escalation markers are reported but NOT snapshotted
	-- or restored by a borrow, which is exactly why they are worth reading: they
	-- are the only way a suite can see that the pause cancelled the in-flight work
	-- (RunToken moved), that the queued escalation settled
	-- (EscalationSettledToken caught up with EscalationToken), and that the resume
	-- took the hand-back branch rather than restoring a stuck Escalating = true
	-- (EscalationAbandonedAtToken is set).
	for _, name in ipairs({"Spawned", "CurrentSpeed", "State", "ScreamSerial", "WarningSerial",
		"LastPumps", "Escalating", "RecoveryStage", "LastWanderAnchor",
		"RunToken", "EscalationToken", "EscalationSettledToken",
		"EscalationAbandonedAtToken"}) do
		snapshot.Values[name] = session[name]
	end
	snapshot.Values.TargetUserId = session.Target and session.Target.UserId or 0
	for pumpNumber, dueAt in pairs(session.PumpScreamScheduled) do
		snapshot.Screams[pumpNumber] = {
			Played = session.PumpScreamPlayed[pumpNumber] == true,
			RemainingSeconds = math.floor((tonumber(dueAt) or 0) - workspace:GetServerTimeNow()),
		}
	end
	local state = stateFolder()
	if state then
		for name, value in pairs(state:GetAttributes()) do
			if string.sub(name, 1, #Controller.PublishedAttributePrefix)
				== Controller.PublishedAttributePrefix then
				snapshot.StateAttributes[name] = value
			end
		end
	end
	if session.Model then
		for name, value in pairs(session.Model:GetAttributes()) do
			if string.sub(name, 1, #Controller.PublishedAttributePrefix)
				== Controller.PublishedAttributePrefix then
				snapshot.ModelAttributes[name] = value
			end
		end
	end
	snapshot.Navigation = session.Navigator and session.Navigator:GetFullDebugSnapshot() or nil
	return snapshot
end

function Controller.GetDebugSnapshot()
	local session = activeSession
	if not session then return {Running = false} end
	local navigation = session.Navigator and session.Navigator:GetDebugSnapshot() or nil
	if navigation then
		navigation.Position = vectorTable(navigation.Position)
		navigation.Goal = vectorTable(navigation.Goal)
	end
	return {
		Running = sessionAlive(session),
		Generation = session.Generation,
		State = session.State,
		Spawned = session.Spawned,
		Pumps = tonumber(workspace:GetAttribute("Level2Pumps")) or 0,
		Speed = session.CurrentSpeed,
		TargetUserId = session.Target and session.Target.UserId or 0,
		RecoveryStage = session.RecoveryStage or 0,
		RecoveryRetreats = session.RecoveryRetreats or 0,
		ScreamSerial = session.ScreamSerial,
		WarningSerial = session.WarningSerial,
		ProcessedPumps = session.LastPumps,
		WanderGoal = vectorTable(session.WanderGoal),
		Spawn = session.SpawnChoice and {
			Anchor = session.SpawnChoice.Anchor.Name,
			Hall = session.SpawnChoice.HallIndex,
			PlayerHops = session.SpawnChoice.Hops,
			PumpHops = session.SpawnChoice.PumpHops,
			Distance = session.SpawnChoice.Distance,
			Hidden = session.SpawnChoice.Hidden,
			Tier = session.SpawnChoice.Tier,
		} or nil,
		Position = session.Navigator and vectorTable(session.Navigator:GetPosition()) or nil,
		Navigation = navigation,
	}
end

return Controller
