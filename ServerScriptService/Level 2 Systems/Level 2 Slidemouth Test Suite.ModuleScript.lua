-- Level 2 Slidemouth Test Suite
--
-- Four suites, all run against a REAL generated Level 2:
--
--   Spawn()     -- room-graph assertions driven by a synthetic party. Every
--                  property of every candidate (its room, its hop distance to
--                  the nearest player and to the pump room, whether that room is
--                  occupied, line of sight, proximity, AND its tier) is
--                  recomputed HERE and compared against the controller's own
--                  metadata. The controller's numbers are never used as the
--                  expected value for themselves -- including its Tier, which
--                  this suite derives from its own copies of the thresholds.
--   LiveSpawn() -- the production path: a real round state, a real pump
--                  transition, the real spawnEntity with its clearance
--                  validation and its live re-check. The movement race is
--                  injected DETERMINISTICALLY, between the ranking snapshot and
--                  the commit, through a Studio-only seam in the controller --
--                  which is the only window spawnStillSafe exists to close.
--                  Eligibility is read through the controller's real
--                  livingRecord() gate, never handed in as a synthetic list.
--   Ledges()    -- locomotion. Controlled ledges at known rises plus authored
--                  edges from the generated world. A refusal only counts when
--                  this suite independently confirms something is really in the
--                  way or that there is really no floor, and EVERY attempted
--                  probe must end up either crossed or verifiably refused --
--                  "never reached the edge" is a probe defect, not a pass.
--   SpawnParties() -- the same room rule reverified with SEVERAL players and
--                  with deliberate TIES, including the named case: a friend in
--                  the pump room AND another player in the room next door.
--                  Every expected answer is derived here from the room graph.
--   Traversal() -- PRODUCTION navigation, walked end to end. The navigator the
--                  controller builds, driven over node pairs and the tightest
--                  corridors on the map: a route must exist where the room
--                  graph supplies one, no segment may cross collidable
--                  geometry, no step may exceed the navigator's own travel
--                  bound, and running out of the iteration cap is a failure.
--                  It also measures the REAL creature asset against the
--                  clearance the navigator assumes.
--   Adversarial()  the repaired failure modes themselves.
--
-- Nothing here mocks the code under test, and every probe restores what it
-- touched -- player CFrame, round attributes, controller state, test folders --
-- on every exit path including an error. Run from a Play session:
--
--   local Adapter = require(game.ServerScriptService["Level 2 Systems"]
--       ["Level 2 Round Adapter"])
--   local Suite = require(game.ServerScriptService["Level 2 Systems"]
--       ["Level 2 Slidemouth Test Suite"])
--   print((Suite.RunAll(Adapter.GetManifest())))

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Systems = script.Parent
local Controller = require(Systems:WaitForChild("Level 2 Slidemouth Controller"))
local Navigator = require(Systems:WaitForChild("Level 2 Pool Foam Navigator"))

local Suite = {}

local LEDGE_SAMPLE = 24
-- WHAT SHIPPED BROKEN in the ledge scan, and what these bound:
--
--   * a skipped candidate carried no cost at all, so a map on which almost
--     nothing was occupiable "passed" on whatever handful remained;
--   * a REFUSAL counted towards the same accounting identity a crossing did, so
--     a rig that refused twenty-one of twenty-four edges passed as long as each
--     refusal had an explanation;
--   * three successful crossings, in total, across every family of authored
--     edge on the map, was the entire success bar -- one family could supply
--     all three and every other family go entirely unproven;
--   * and the expected outcome came from the SAME production tags the code
--     under test reads (Level2_EntityGround / Level2_NoEntityGround), so a
--     wrongly tagged part made the navigator refuse a crossable edge AND made
--     this suite call that refusal correct. Nothing could see it.
--
-- Skips and refusals are now ratios with a cap, every family that contains a
-- geometrically-must-cross edge has to actually cross one, and the expected
-- outcome is derived from MEASURED geometry with no tag in the decision.
local LEDGE_MAX_SKIP_RATIO = .6
local LEDGE_MAX_REFUSAL_RATIO = .6
local LEDGE_FAMILY_MIN_CROSSINGS = 1
local LEDGE_MIN_FAMILIES = 3
-- Dead band around MaxStepHeight, and around the body probe's width, inside
-- which the oracle declines to predict. A measurement is not a certificate: an
-- edge within a quarter-stud of the step limit may legitimately go either way,
-- and asserting on it would be asserting on raycast noise.
local LEDGE_ORACLE_MARGIN = .25
local STEP_FRAMES = 280
-- A probe that is still walking freely when its frame budget runs out has
-- proved nothing about the edge in front of it. Rather than record that as an
-- unresolved result, give it more frames -- but a bounded number, so a rig
-- circling forever still fails.
local STEP_EXTENSIONS = 3
local PROBE_SPEED = 16
local PROBE_DELTA = 1 / 60
-- Mirrors of the controller's spawn thresholds, held separately on purpose: if
-- the controller's constants drift, these assertions should start failing
-- rather than silently following along. Suite.Spawn also asserts the two agree,
-- so a drift is reported as a drift instead of as a wall of failures.
local EXPECTED_MIN_HOPS = 1
local EXPECTED_MAX_HOPS = 2
local EXPECTED_MIN_STUDS = 45
local EXPECTED_FALLBACK_STUDS = 27

-- Mirrors of the controller's PAUSE_DEADLINE_FIELDS and of
-- the navigator's NAVIGATOR_PAUSE_FIELDS, held separately for exactly the reason
-- the spawn thresholds above are: if a module's list changes, these assertions
-- should start FAILING rather than silently following along. A pause that
-- restores seven of eight deadlines is the bug; a suite that reads the list off
-- the thing under test cannot see it.
local EXPECTED_DEADLINE_FIELDS = {
	"NextTargetRefreshAt", "NextTargetSwitchAt", "AttackCooldownUntil",
	"RecoveryUntil", "GraphRecoveryUntil", "WanderGoalUntil", "WanderMoveDeadline",
	"SpawnRetryAt",
}
local EXPECTED_NAVIGATOR_PAUSE_FIELDS = {
	"Waypoints", "WaypointIndex", "Goal", "LastRequestedGoal", "Status",
	"LastFailure", "LastBlockedBy", "Facing", "FootPosition", "HasGrounded",
	"LastSafeFoot", "LastSafeFacing", "TrailFrozen", "PivotAboveFoot", "Trail",
}

-- Fields GetFullDebugSnapshot reports for OBSERVATION and that a borrow
-- deliberately never restores. The controller says so at its own snapshot
-- builder, field by field: RunToken is the CANCELLATION token -- restoring it
-- would hand the jobs a pause cancelled their session back -- and the three
-- escalation markers are the only evidence a resume has that a queued
-- escalation settled (EscalationSettledToken caught up with EscalationToken) or
-- was abandoned (EscalationAbandonedAtToken), so a resume that rewound them
-- would be rewinding the very reading it is about to make.
--
-- WHAT SHIPPED BROKEN: comparableSnapshot masked Navigation.RequestId and
-- Navigation.Computing for exactly this reason and then stopped. The
-- whole-surface comparison therefore demanded that Values.RunToken come back
-- unchanged, which is the one thing a correct borrow must never do -- and on a
-- real generated world it duly failed with "Values.RunToken (0 vs 2)": one bump
-- leaving RUNNING, one bump returning to it, a textbook clean borrow reported
-- as corruption. That failure was in the SUITE.
--
-- These four are masked BECAUSE they are documented as unrestored, and nothing
-- else is masked with them. The run token is then asserted POSITIVELY in
-- PauseIsolation -- it has to have MOVED, or the pause cancelled nothing -- so
-- the fact is checked deliberately rather than merely stopped from failing.
local UNRESTORED_SESSION_VALUES = {
	"RunToken", "EscalationToken", "EscalationSettledToken", "EscalationAbandonedAtToken",
}

-- Mirror of the controller's SPAWN_PUMPS, held separately for the reason every
-- other mirror in this file is: the arm's forced-spawn path is described in
-- terms of it, and a suite that read the number off the thing under test could
-- not see it move. Controller.SpawnThresholds.SpawnPumps is asserted against
-- this in Suite.Spawn.
local EXPECTED_SPAWN_PUMPS = 2

-- Mirrors of the controller's asset names and of the navigator's own travel
-- cap, held here for the same reason every other mirror is: a rename or a
-- retune should FAIL this suite rather than be silently followed.
local EXPECTED_TEMPLATE_NAME = "Level 2 Slidemouth Template"
local EXPECTED_ASSET_FOLDER = "Level2Assets"
-- Navigator.MAX_TRAVEL_SUBSTEPS. Not exported, so it is mirrored: the teleport
-- bound below is derived from it and from MaxTravelStep together.
local EXPECTED_MAX_TRAVEL_SUBSTEPS = 12

-- Traversal probe. The delta is the controller's OWN per-frame clamp
-- (updateEntity calls Step with math.min(dt, .1)) and the speed is
-- PUMP_TWO_SPEED, so one iteration here asks the navigator for exactly the
-- stride a live pump-two chase asks for -- 2.4 studs, which the substep rewrite
-- splits into three validated placements. Anything smaller would never exercise
-- the substep loop at all.
local TRAVERSAL_DELTA = .1
local TRAVERSAL_SPEED = 24
local TRAVERSAL_PAIR_BUDGET = 10
-- How many of those the tightest corridors may claim before the multi-hop
-- routes get their turn.
local TRAVERSAL_TIGHT_BUDGET = 6
-- Bounded completion. The per-pair cap is derived from the route the navigator
-- actually produced -- four times the iterations a straight walk of it needs --
-- and then hard-capped, so neither a long route nor a broken one can spin. A
-- rig that is STILL MOVING when its cap runs out is a FAILURE, never a pass.
-- RAISED 900 -> 2600. WHAT SHIPPED BROKEN: the ceiling was below the number of
-- frames a STRAIGHT walk of the longest sampled route needs. At the probe's
-- 2.4 studs per frame a 2425-stud route needs 1010 frames just to cover the
-- ground, so 900 made arrival arithmetically impossible and the pair was
-- reported as "ran out of its iteration cap still moving" -- a harness budget
-- failure wearing the costume of a navigation failure. 2600 leaves the longest
-- route on this map about 2.5x the frames a straight walk needs.
--
-- The ceiling is NOT the safety property here and never was: the loop is
-- bounded by `cap` whatever this number is. To stop the same mistake being
-- made silently again, the cap a pair is granted is now ASSERTED to be able to
-- admit that pair's own route -- see "every walked pair was given a budget".
local TRAVERSAL_ITERATION_CEILING = 2600
local TRAVERSAL_ITERATION_SLACK = 4
local TRAVERSAL_ITERATION_FLOOR = 120
-- A rig that has stopped moving has reached a terminal, bounded outcome and is
-- recorded as blocked; that is a different fact from running out of budget.
local TRAVERSAL_STALL_FRAMES = 45
local TRAVERSAL_STALL_STUDS = .02
-- How long a path request may take to settle before the pair is abandoned.
local TRAVERSAL_SETTLE_SECONDS = 8
-- There is deliberately no minimum-arrivals constant any more. It used to be 3,
-- and "3 of 10 arrived" was a PASS; the owner has ruled that out. Every pair
-- joined by an open corridor must arrive, and a blocked pair is named.
local TRAVERSAL_MAX_SKIP_RATIO = .5

-- ---------------------------------------------------------------------------
-- reporting
-- ---------------------------------------------------------------------------

-- Every suite declares, per branch it can take, exactly how many checks that
-- branch performs. RunAll asserts the declaration. A suite that quietly stops
-- running half its assertions then fails, instead of reporting a smaller total
-- nobody was watching -- which is why no number here is approximate.
-- A branch that returns from INSIDE protect() runs protect's own counted check
-- as well -- "every change this suite made was restored" -- so every number
-- below for such a branch is one higher than the checks its own code ran.
-- WHAT SHIPPED BROKEN: every one of these was written as if that check did not
-- exist, so five of PauseIsolation's branches and four of LiveSpawn's declared
-- a count no run could ever produce. A branch whose declared count is wrong is
-- a branch nobody has ever verified: it fails the moment it is taken, which is
-- indistinguishable from the code under test failing.
local EXPECTED_CHECKS = {
	["Slidemouth spawn (independently verified)"] = {
		["fallback-reached"] = 78,
		["fallback-not-reached"] = 81,
		["no-pump-hall"] = 1,
		["no-neighbour"] = 15,
	},
	-- No protect: this suite only reads the ranking through EvaluateSpawn, which
	-- builds a throwaway session and mutates nothing, so there is no restore
	-- check on any of its branches.
	["Slidemouth spawn with a crowded party"] = {
		full = 11,
		["no-pump-hall"] = 1,
		["no-neighbour"] = 1,
	},
	-- Reads the contract through Controller.EvaluateSpawnContract and
	-- EvaluateSpawnCommit, both of which build a throwaway session and mutate
	-- nothing live, so there is no protect and no restore check on any branch.
	["Slidemouth spawn contract (enforced at commit)"] = {
		full = 19,
		["no-pump-hall"] = 1,
		["no-neighbour"] = 1,
		-- A FIFTH branch nobody had declared. It is taken on a map with no room
		-- two hops from one player and one hop from another, and on such a map
		-- RunAll would have failed with "no expected check count declared" --
		-- which is exactly the class of fault the note at the head of this table
		-- was written about, sitting inside the table itself.
		["no-tie"] = 11,
	},
	-- The tuning and speed reads happen BEFORE protect, so they are counted on
	-- every branch; everything from the geometry sanity check down additionally
	-- carries protect's own restore check.
	-- The tuning read happens BEFORE protect, so it is counted on every branch;
	-- everything from the corridor search down additionally carries protect's
	-- own restore check.
	["Slidemouth route centring (clearance-aware)"] = {
		full = 13,
		["no-tuning"] = 1,
		["no-corridor"] = 3,
	},
	["Slidemouth substep floor resolve (production stride)"] = {
		full = 15,
		["no-tuning"] = 1,
		["no-speeds"] = 2,
		["no-lane"] = 5,
	},
	["Slidemouth pause isolation (a loaded incumbent)"] = {
		full = 121,
		-- Returns BEFORE protect, so no restore check.
		["no-world"] = 0,
		["no-state"] = 1,
		-- Everything below returns from inside protect.
		["no-session"] = 14,
		["no-player"] = 15,
		-- +1 on the pre-B9 count: a refused arm now also has to say WHY it was
		-- entitled to be refused -- that this suite declined to claim the world.
		["no-arm"] = 19,
		-- +1 each on the pre-B9 counts: the opt-in the controller recorded is
		-- asserted immediately after a successful arm, so every branch below the
		-- arm carries it.
		["pause-failed"] = 28,
		["resume-failed"] = 68,
		-- A map on which PathfindingService cannot settle a route has no live
		-- Blocked binding to arm, and the blocked half of a navigator resume is
		-- then honestly unexercised rather than quietly skipped. +3: the opt-in
		-- check, the run-token check after the resume, and the disarm residue
		-- check, all of which run before this branch is taken.
		["no-blocked-arm"] = 108,
	},
	["Slidemouth live spawn (production path)"] = {
		full = 36,
		["no-player"] = 1,
		["no-character"] = 2,
		["no-pause"] = 8,
		["no-state"] = 9,
		["no-stage"] = 10,
		["no-spawn"] = 11,
		["no-position"] = 12,
	},
	-- full assumes the controlled-ledge lane was found AND all five controlled
	-- walks returned a result: the "stops ON the ledge" half of each rise runs
	-- only when its walk produced one, which is the same contract this number
	-- has always carried. 22 before B3; +6 for the per-family minimum, the
	-- family span, the two ratio caps and the two independent-oracle checks.
	["Slidemouth ledge crossing"] = {full = 28, ["no-tuning"] = 1},
	-- The tuning check runs BEFORE protect, so it is counted on every branch
	-- including no-tuning, and every branch below it additionally carries
	-- protect's own restore check.
	-- 15 -> 17: the two hardest assertions in this suite were added without
	-- their number being moved with them (connectedUnarrived and staleYield), so
	-- the branch failed its own count on every run and the two REAL failures
	-- underneath were reported alongside a bookkeeping one.
	["Slidemouth production navigation"] = {
		full = 23,
		["no-tuning"] = 1,
		["no-nodes"] = 3,
		["no-template"] = 4,
		["no-pairs"] = 11,
	},
	["Slidemouth repaired failure modes"] = {full = 16, ["no-lane"] = 5},
}

local function newReport(title, branch)
	return {Lines = {"=== " .. title .. " ==="}, Failures = 0, Checks = 0,
		Title = title, Branch = branch or "full"}
end

local function setBranch(report, branch)
	report.Branch = branch
	return report
end

local function check(report, ok, description, detail)
	report.Checks += 1
	if ok then
		table.insert(report.Lines, "  ok   " .. description)
	else
		report.Failures += 1
		table.insert(report.Lines, "  FAIL " .. description
			.. (detail and ("  (" .. tostring(detail) .. ")") or ""))
	end
	return ok
end

local function note(report, text)
	table.insert(report.Lines, "       " .. text)
end

-- Every probe below mutates something live -- a player's position, a round
-- attribute, a controller session, a folder in the world. `protect` runs the
-- body and restores, in reverse order, on EVERY exit path: normal return, early
-- return, and error.
--
-- A restoration that fails is a FAILED ASSERTION, not a warning. A suite that
-- leaves the place changed has not passed, however green its own checks were,
-- and a warning in the output is not something anybody counts.
local function protect(report, body)
	local undo = {}
	local function onCleanup(label, fn) table.insert(undo, {Label = label, Run = fn}) end
	local ok, result = pcall(body, onCleanup)
	local failed = {}
	for index = #undo, 1, -1 do
		local step = undo[index]
		local cleaned, cleanupError = pcall(step.Run)
		if not cleaned then
			table.insert(failed, step.Label .. " -- " .. tostring(cleanupError))
		end
	end
	check(report, #failed == 0, "every change this suite made was restored",
		table.concat(failed, " | "))
	if not ok then
		check(report, false, "the probe body ran to completion", tostring(result))
	end
	return report
end

-- ---------------------------------------------------------------------------
-- the suite's own view of the map
-- ---------------------------------------------------------------------------

local function hallContaining(layout, position)
	for arrayIndex, hall in ipairs(layout.Halls or {}) do
		local minX, maxX = tonumber(hall.MinX), tonumber(hall.MaxX)
		local minZ, maxZ = tonumber(hall.MinZ), tonumber(hall.MaxZ)
		if minX and maxX and minZ and maxZ
			and position.X >= minX and position.X <= maxX
			and position.Z >= minZ and position.Z <= maxZ
		then
			return tonumber(hall.Index) or arrayIndex
		end
	end
	return nil
end

local function hallCenter(hall)
	if typeof(hall.Center) == "Vector3" then return hall.Center end
	return Vector3.new((hall.MinX + hall.MaxX) * .5, 0, (hall.MinZ + hall.MaxZ) * .5)
end

local function nearestHall(layout, position)
	local best, bestDistance
	for arrayIndex, hall in ipairs(layout.Halls or {}) do
		local centre = hallCenter(hall)
		local distance = (Vector3.new(position.X, 0, position.Z)
			- Vector3.new(centre.X, 0, centre.Z)).Magnitude
		if not bestDistance or distance < bestDistance then
			best, bestDistance = tonumber(hall.Index) or arrayIndex, distance
		end
	end
	return best
end

-- The room a POSITION belongs to, by the same conservative rule the controller
-- uses: containment where there is one, otherwise the nearest room's centre.
local function roomOf(layout, position)
	return hallContaining(layout, position) or nearestHall(layout, position)
end

-- An independent BFS, deliberately not the controller's, so a fault in the
-- controller's traversal shows up as a disagreement rather than cancelling out.
local function hops(layout, startIndex)
	local distance = {}
	if not startIndex then return distance end
	distance[startIndex] = 0
	local queue, head = {startIndex}, 1
	local exitPowered = workspace:GetAttribute("Level2ExitPowered") == true
	while head <= #queue do
		local current = queue[head]
		head += 1
		local hall = layout.Halls[current]
		for _, raw in ipairs((hall and hall.Connections) or {}) do
			local other = tonumber(raw)
			if other and distance[other] == nil then
				local key = tostring(math.min(current, other)) .. ":" .. tostring(math.max(current, other))
				local corridor = layout.CorridorByPair and layout.CorridorByPair[key]
				if corridor and not (corridor.Kind == "PressureDoor" and not exitPowered) then
					distance[other] = distance[current] + 1
					table.insert(queue, other)
				end
			end
		end
	end
	return distance
end

local function horizontal(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- The suite's OWN tier rule, written from the documented thresholds rather than
-- read off the controller. Comparing this against candidate.Tier is what makes
-- the ranking assertions independent instead of self-confirming.
--
-- WHAT SHIPPED BROKEN, and what the shape below now mirrors: tiers 4 and 2 meant
-- "outside the 1-2 hop window" -- 4 hidden, 2 not -- and BOTH outranked tier 1,
-- which is inside it. A hop count the module documents as a hard window was in
-- fact a preference the sort could overrule, so a hidden room four rooms away
-- beat a room next door. Out-of-window is now a REJECTION (nil) rather than a
-- demotion, in the controller and here; 5, 3 and 1 keep their published
-- meanings, and nil is asserted against a candidate list that must not contain
-- the room at all.
local function independentTier(hopCount, hidden, distance)
	if hopCount == nil
		or hopCount < EXPECTED_MIN_HOPS or hopCount > EXPECTED_MAX_HOPS then return nil end
	if distance >= EXPECTED_MIN_STUDS then
		if hidden then return 5 end
		return 3
	end
	if distance >= EXPECTED_FALLBACK_STUDS then return 1 end
	return nil
end

-- The controller's scoring bonus, derived from the anchor NAME the ranking
-- reports -- the same rule collectAnchors applies, restated here so the suite
-- can predict the ordering without reading the controller's private table.
local function independentBonus(anchorName)
	local isDen = anchorName:find("Level 2 Entity Den ", 1, true) == 1
	local isCenter = isDen or anchorName:find("Level 2 Navigation Node ", 1, true) == 1
	return (isCenter and 2 or 0) + (isDen and 1 or 0)
end

-- Line of sight computed here rather than read off the controller. Same
-- geometry the controller uses -- eye 2.2 above a player, target 4.5 above the
-- anchor, world collision only -- and the same declared filter: the entity node
-- markers and the player characters are excluded on both sides, so any
-- disagreement is a real disagreement about the world.
local function observedFrom(anchorPosition, playerPositions, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local target = anchorPosition + Vector3.new(0, 4.5, 0)
	for _, position in ipairs(playerPositions) do
		local origin = position + Vector3.new(0, 2.2, 0)
		local displacement = target - origin
		if displacement.Magnitude > .05
			and workspace:Raycast(origin, displacement, params) == nil then
			return true
		end
	end
	return false
end

-- The exclusion set the controller's own ray filter declares, rebuilt here.
local function sightExclusions(manifest, extra)
	local ignore = {}
	if manifest.EntityNodes then table.insert(ignore, manifest.EntityNodes) end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(ignore, player.Character) end
	end
	for _, instance in ipairs(extra or {}) do table.insert(ignore, instance) end
	return ignore
end

-- Everything the assertions need about an anchor, derived from its world
-- position and the party's world positions. No controller metadata involved.
local function describeIndependently(manifest, anchorPosition, playerPositions, pumpIndex, ignore)
	local layout = manifest.Layout
	local occupied, playerRooms = {}, {}
	for _, position in ipairs(playerPositions) do
		local room = roomOf(layout, position)
		if room and not occupied[room] then
			occupied[room] = true
			table.insert(playerRooms, room)
		end
	end
	local fromPlayers = {}
	for _, room in ipairs(playerRooms) do
		for index, distance in pairs(hops(layout, room)) do
			if fromPlayers[index] == nil or distance < fromPlayers[index] then
				fromPlayers[index] = distance
			end
		end
	end
	local room = roomOf(layout, anchorPosition)
	local minStuds = math.huge
	for _, position in ipairs(playerPositions) do
		minStuds = math.min(minStuds, horizontal(anchorPosition, position))
	end
	local toPump = pumpIndex and hops(layout, pumpIndex) or {}
	local hopCount = room and fromPlayers[room] or nil
	local observed = observedFrom(anchorPosition, playerPositions, ignore)
	return {
		Room = room,
		Occupied = room ~= nil and occupied[room] == true,
		Hops = hopCount,
		PumpHops = room and toPump[room] or nil,
		MinStuds = minStuds,
		Observed = observed,
		Tier = independentTier(hopCount, not observed, minStuds),
	}
end

local function anchorLookup(manifest)
	local byName = {}
	local function consider(instance)
		if instance and instance:IsA("BasePart") then byName[instance.Name] = instance.Position end
	end
	local function scan(container)
		if not container then return end
		consider(container)
		for _, d in ipairs(container:GetDescendants()) do consider(d) end
	end
	scan(manifest.EntityNodes)
	scan(manifest.EntityDen)
	scan(manifest.Navigation)
	return byName
end

local function groundParamsFor(manifest)
	local ground = {}
	for _, d in ipairs(manifest.World:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide
			and d:GetAttribute("Level2_EntityGround") == true then
			table.insert(ground, d)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = ground
	params.IgnoreWater = true
	return params, ground
end

-- ---------------------------------------------------------------------------
-- Spawn
-- ---------------------------------------------------------------------------

-- `options.IsolatedPumpRoom` says the caller handed in a CONSTRUCTED map whose
-- pump room has been cut out of the room graph. On such a map "a room is
-- chosen" and "there is a reachable neighbour" are supposed to be false -- that
-- is the condition the no-neighbour branch exists for -- so they are asserted
-- the other way round rather than reported as failures.
function Suite.Spawn(manifest, options)
	local isolated = options ~= nil and options.IsolatedPumpRoom == true
	local report = newReport("Slidemouth spawn (independently verified)")
	local layout = manifest.Layout
	local pumpHall = layout.PumpHalls and layout.PumpHalls[2]
	if not (pumpHall and layout.Halls) then
		check(report, false, "layout exposes a pump 2 hall")
		return setBranch(report, "no-pump-hall")
	end
	local pumpIndex = tonumber(pumpHall.Index)
	local anchors = anchorLookup(manifest)
	local anchorCount = 0
	for _ in pairs(anchors) do anchorCount += 1 end
	note(report, string.format("map: %d halls, %d corridors, pump 2 in room %d, %d anchor parts",
		#layout.Halls, #(layout.Corridors or {}), pumpIndex, anchorCount))

	-- Report a threshold drift as a drift, once, instead of as a wall of
	-- ranking failures nobody can read.
	local live = Controller.SpawnThresholds
	check(report, typeof(live) == "table"
		and live.PreferredMinHops == EXPECTED_MIN_HOPS
		and live.PreferredMaxHops == EXPECTED_MAX_HOPS
		and live.MinimumStudDistance == EXPECTED_MIN_STUDS
		and live.FallbackStudDistance == EXPECTED_FALLBACK_STUDS
		-- The spawn pump belongs in the same drift report: PauseIsolation's
		-- forced-spawn opt-in is described entirely in terms of it, and a suite
		-- that read the number off the controller could not see it move.
		and live.SpawnPumps == EXPECTED_SPAWN_PUMPS,
		"the suite's spawn thresholds still match the controller's",
		typeof(live) == "table" and string.format("controller %s-%s hops, %s/%s studs, spawn pump %s",
			tostring(live.PreferredMinHops), tostring(live.PreferredMaxHops),
			tostring(live.MinimumStudDistance), tostring(live.FallbackStudDistance),
			tostring(live.SpawnPumps))
			or "controller exposes no thresholds")

	local ignore = sightExclusions(manifest)

	local function evaluate(positions)
		return Controller.EvaluateSpawn(manifest, positions, 2)
	end

	-- Every property of every candidate, recomputed and compared. The tier is
	-- derived from the suite's own thresholds, so a controller that mis-tiers a
	-- room disagrees here rather than defining the expected answer.
	local function assertRanking(label, result, positions)
		local mismatched = {Room = 0, Hops = 0, PumpHops = 0, Distance = 0, Hidden = 0, Tier = 0}
		local occupiedHit, zeroHop, tooClose, unreachable, missing = 0, 0, 0, 0, 0
		local outOfOrder = 0
		local previousTier = nil
		for _, candidate in ipairs(result.Candidates) do
			local position = anchors[candidate.Anchor]
			if not position then
				missing += 1
			else
				local truth = describeIndependently(manifest, position, positions, pumpIndex, ignore)
				if truth.Occupied then occupiedHit += 1 end
				if truth.Hops == 0 then zeroHop += 1 end
				if truth.Hops == nil and #positions > 0 then unreachable += 1 end
				if truth.MinStuds < EXPECTED_FALLBACK_STUDS then tooClose += 1 end
				if candidate.HallIndex ~= truth.Room then mismatched.Room += 1 end
				if candidate.Hops ~= truth.Hops then mismatched.Hops += 1 end
				if candidate.PumpHops ~= truth.PumpHops then mismatched.PumpHops += 1 end
				if math.abs((candidate.Distance or -1) - truth.MinStuds) > .01 then
					mismatched.Distance += 1
				end
				if candidate.Hidden ~= (not truth.Observed) then mismatched.Hidden += 1 end
				if candidate.Tier ~= truth.Tier then mismatched.Tier += 1 end
				if previousTier and truth.Tier and truth.Tier > previousTier then
					outOfOrder += 1
				end
				previousTier = truth.Tier or previousTier
			end
		end
		check(report, missing == 0,
			label .. ": every candidate names a real anchor part", missing .. " did not")
		check(report, mismatched.Room == 0,
			label .. ": every candidate's reported room matches the map",
			mismatched.Room .. " disagreed")
		check(report, mismatched.Hops == 0,
			label .. ": every reported hop count matches the independent BFS",
			mismatched.Hops .. " disagreed")
		check(report, mismatched.PumpHops == 0,
			label .. ": every reported pump-hop count matches the independent BFS",
			mismatched.PumpHops .. " disagreed")
		check(report, mismatched.Distance == 0,
			label .. ": every reported distance matches the measured distance",
			mismatched.Distance .. " disagreed")
		check(report, mismatched.Hidden == 0,
			label .. ": every reported sight flag matches an independent raycast",
			mismatched.Hidden .. " disagreed")
		check(report, mismatched.Tier == 0,
			label .. ": every reported tier matches the tier derived here",
			mismatched.Tier .. " disagreed")
		check(report, outOfOrder == 0,
			label .. ": the list is ordered by descending independently-derived tier",
			outOfOrder .. " entries rose above the previous tier")
		check(report, occupiedHit == 0,
			label .. ": no candidate room holds a player (independently checked)",
			occupiedHit .. " did")
		check(report, zeroHop == 0,
			label .. ": no candidate is 0 hops from a player (independent BFS)",
			zeroHop .. " were")
		check(report, unreachable == 0,
			label .. ": every candidate is reachable from the party",
			unreachable .. " were not")
		check(report, tooClose == 0,
			label .. ": no candidate is inside the proximity floor",
			tooClose .. " were")
	end

	-- The ordering the controller documents, predicted here from independently
	-- derived numbers only: highest tier, then fewest room-hops to the pump,
	-- then closest to the top of the 1-2 room window, then the anchor-kind
	-- bonus, then furthest from the party, then name.
	local function bestByDocumentedOrder(result, positions)
		-- Every element of the key is "higher is better", so one lexicographic
		-- comparison covers the whole documented ordering; the anchor name is
		-- the final tie-break, exactly as the controller documents.
		local function keyFor(candidate)
			local position = anchors[candidate.Anchor]
			local truth = position
				and describeIndependently(manifest, position, positions, pumpIndex, ignore)
			if not (truth and truth.Tier) then return nil end
			return {
				truth.Tier,
				-(truth.PumpHops or math.huge),
				-math.abs((truth.Hops or 0) - EXPECTED_MAX_HOPS),
				independentBonus(candidate.Anchor),
				truth.MinStuds,
			}
		end
		local best, bestKey
		for _, candidate in ipairs(result.Candidates) do
			local key = keyFor(candidate)
			if key then
				local better = bestKey == nil
				local decided = better
				if not decided then
					for index = 1, #key do
						if key[index] ~= bestKey[index] then
							better = key[index] > bestKey[index]
							decided = true
							break
						end
					end
				end
				if not decided then better = candidate.Anchor < best.Anchor end
				if better then best, bestKey = candidate, key end
			end
		end
		return best
	end

	local function assertChosen(label, result, positions, requirePreferred)
		local chosen = result.Chosen
		if not check(report, chosen ~= nil, label .. ": a room is chosen") then return nil end
		local position = anchors[chosen.Anchor]
		if not check(report, position ~= nil,
			label .. ": the chosen anchor exists in the world", chosen.Anchor) then return nil end
		local truth = describeIndependently(manifest, position, positions, pumpIndex, ignore)
		note(report, string.format(
			"%s -> room %s via %s | tier %s | %s hop(s) from nearest player | %s from pump %d | %.0f studs | %s",
			label, tostring(truth.Room), chosen.Anchor, tostring(truth.Tier), tostring(truth.Hops),
			tostring(truth.PumpHops), pumpIndex, truth.MinStuds,
			truth.Observed and "IN SIGHT" or "out of sight"))
		check(report, not truth.Occupied, label .. ": room is not occupied")
		check(report, truth.Hops ~= nil and truth.Hops >= EXPECTED_MIN_HOPS,
			label .. ": at least one room away", tostring(truth.Hops))
		-- The best tier ANY candidate reaches, derived here.
		local bestTier = nil
		for _, candidate in ipairs(result.Candidates) do
			local candidatePosition = anchors[candidate.Anchor]
			local candidateTruth = candidatePosition
				and describeIndependently(manifest, candidatePosition, positions, pumpIndex, ignore)
			if candidateTruth and candidateTruth.Tier
				and (bestTier == nil or candidateTruth.Tier > bestTier) then
				bestTier = candidateTruth.Tier
			end
		end
		check(report, truth.Tier ~= nil and truth.Tier == bestTier,
			label .. ": the choice sits in the best tier available (derived here)",
			string.format("chose tier %s, best available %s",
				tostring(truth.Tier), tostring(bestTier)))
		local predicted = bestByDocumentedOrder(result, positions)
		check(report, predicted ~= nil and predicted.Anchor == chosen.Anchor,
			label .. ": the choice is the one the documented ordering predicts",
			string.format("chose %s, predicted %s", chosen.Anchor,
				predicted and predicted.Anchor or "nothing"))
		if requirePreferred then
			check(report, truth.Hops ~= nil and truth.Hops <= EXPECTED_MAX_HOPS,
				label .. ": within the 1-2 room window", tostring(truth.Hops))
			check(report, not truth.Observed, label .. ": out of line of sight")
			check(report, truth.MinStuds >= EXPECTED_MIN_STUDS,
				label .. ": past the proximity floor",
				string.format("%.0f studs", truth.MinStuds))
		end
		return truth, bestTier
	end

	-- (1) Single player, standing in the pump room itself.
	local soloPosition = hallCenter(pumpHall)
	local solo = evaluate({soloPosition})
	local soloTruth, soloBestTier
	if isolated then
		check(report, #solo.Candidates == 0,
			"constructed isolated pump room: nothing is reachable, so nothing is offered",
			#solo.Candidates .. " offered")
	else
		soloTruth, soloBestTier = assertChosen("single player", solo, {soloPosition}, true)
		if soloTruth then
			check(report, soloTruth.Room ~= pumpIndex,
				"single player: not the room the player is standing in")
		end
	end
	assertRanking("single player", solo, {soloPosition})

	-- (2) The required multiplayer case: A in the pump room, B next door.
	local pumpDistance = hops(layout, pumpIndex)
	local neighbourIndex
	for _, raw in ipairs(pumpHall.Connections or {}) do
		local other = tonumber(raw)
		if other and layout.Halls[other] and pumpDistance[other] == 1 then
			neighbourIndex = other
			break
		end
	end
	if isolated then
		check(report, neighbourIndex == nil,
			"constructed isolated pump room: it has no reachable neighbour, which is"
			.. " exactly the condition this branch exists for",
			tostring(neighbourIndex))
		return setBranch(report, "no-neighbour")
	end
	if not check(report, neighbourIndex ~= nil,
		"pump room has a reachable adjacent room to stage B in") then
		return setBranch(report, "no-neighbour")
	end
	local partyPositions = {soloPosition, hallCenter(layout.Halls[neighbourIndex])}
	local party = evaluate(partyPositions)
	note(report, string.format("A in room %d (pump 2), B in room %d (adjacent)",
		pumpIndex, neighbourIndex))
	local partyTruth = assertChosen("two players", party, partyPositions, true)
	if partyTruth then
		check(report, partyTruth.Room ~= pumpIndex, "two players: not A's room",
			tostring(partyTruth.Room))
		check(report, partyTruth.Room ~= neighbourIndex, "two players: not B's room",
			tostring(partyTruth.Room))
		-- Pump priority, grouped by the tier THIS suite derived. Grouping by the
		-- controller's own Tier would have let a mis-tiered candidate define the
		-- set it was then compared against.
		local best = math.huge
		local inTier = 0
		for _, candidate in ipairs(party.Candidates) do
			local position = anchors[candidate.Anchor]
			local truth = position
				and describeIndependently(manifest, position, partyPositions, pumpIndex, ignore)
			if truth and truth.Tier == partyTruth.Tier then
				inTier += 1
				if truth.PumpHops then best = math.min(best, truth.PumpHops) end
			end
		end
		check(report, inTier > 0,
			"two players: the chosen tier is a tier the suite also derived",
			inTier .. " candidates in it")
		check(report, partyTruth.PumpHops == best,
			"two players: closest to the pump room by room hops",
			string.format("chose %s, best in independently derived tier %s",
				tostring(partyTruth.PumpHops), tostring(best)))
	end
	assertRanking("two players", party, partyPositions)

	-- (3) Determinism.
	local repeated = evaluate(partyPositions)
	check(report,
		(party.Chosen and party.Chosen.Anchor) == (repeated.Chosen and repeated.Chosen.Anchor),
		"the same party produces the same choice twice")

	-- (4) Nowhere safe: a player in EVERY room must yield no candidate at all.
	local everywhere = {}
	for _, hall in ipairs(layout.Halls) do table.insert(everywhere, hallCenter(hall)) end
	local crowded = evaluate(everywhere)
	check(report, #crowded.Candidates == 0,
		"a player in every room leaves no candidate (the spawn waits)",
		#crowded.Candidates .. " offered")

	-- (5) The fallback tiers must obey exactly the rules tier 5 obeys.
	--
	-- What this can and cannot claim is bounded by what it actually samples.
	-- The sweep below builds a specific, counted set of parties out of room
	-- occupancy -- crowding one room at a time, and each single free room in
	-- turn -- and looks for one where the CHOSEN tier is below the uncrowded
	-- best. That is a sample, not a proof about every possible party, and it is
	-- reported as a sample. Occupancy sets are the map's power set; nothing here
	-- enumerates them and nothing here says otherwise.
	--
	-- Every tier this branch asserts on is derived HERE, from the suite's own
	-- thresholds. The controller's Tier field is never the expected value for
	-- itself, in the sweep or in the assertions.
	local fallbackPositions, fallbackResult, fallbackTier
	local sweptConfigurations, configurationsWithCandidates = 0, 0
	local topTierSamples, topTierPresent = 0, 0
	local crowdedPositions, crowdedResult
	do
		-- Is a TOP-tier anchor available to this party? Derived independently:
		-- occupancy from the party's own rooms, hop counts from the suite's BFS,
		-- distance measured here, and only then a raycast for concealment --
		-- which is why this is cheap enough to run on every sampled party.
		local function topTierAvailable(party)
			local occupied, playerRooms = {}, {}
			for _, position in ipairs(party) do
				local room = roomOf(layout, position)
				if room and not occupied[room] then
					occupied[room] = true
					table.insert(playerRooms, room)
				end
			end
			local fromPlayers = {}
			for _, room in ipairs(playerRooms) do
				for index, distance in pairs(hops(layout, room)) do
					if fromPlayers[index] == nil or distance < fromPlayers[index] then
						fromPlayers[index] = distance
					end
				end
			end
			for anchorName, anchorPosition in pairs(anchors) do
				local room = roomOf(layout, anchorPosition)
				if room and not occupied[room] then
					local hopCount = fromPlayers[room]
					if hopCount and hopCount >= EXPECTED_MIN_HOPS
						and hopCount <= EXPECTED_MAX_HOPS then
						local minStuds = math.huge
						for _, position in ipairs(party) do
							minStuds = math.min(minStuds, horizontal(anchorPosition, position))
						end
						if minStuds >= EXPECTED_MIN_STUDS
							and not observedFrom(anchorPosition, party, ignore) then
							return true, anchorName
						end
					end
				end
			end
			return false, nil
		end

		local function considerParty(party)
			local attempt = evaluate(party)
			sweptConfigurations += 1
			if #attempt.Candidates == 0 then return attempt end
			configurationsWithCandidates += 1
			topTierSamples += 1
			if topTierAvailable(party) then topTierPresent += 1 end
			if attempt.Chosen and not fallbackResult then
				-- Cheap pre-filter only. Whether this really is a lower tier is
				-- decided below by the suite's own derivation.
				local position = anchors[attempt.Chosen.Anchor]
				local truth = position
					and describeIndependently(manifest, position, party, pumpIndex, ignore)
				if truth and truth.Tier and soloBestTier and truth.Tier < soloBestTier then
					fallbackPositions = table.clone(party)
					fallbackResult = attempt
				end
			end
			return attempt
		end

		-- (a) crowd one room at a time. Occupancy only ever removes candidates,
		-- so once the map is full there is nothing further to find.
		local crowd = {}
		for _, hall in ipairs(layout.Halls) do
			table.insert(crowd, hallCenter(hall))
			local attempt = considerParty(crowd)
			if #attempt.Candidates == 0 then break end
			crowdedPositions, crowdedResult = table.clone(crowd), attempt
		end

		-- (b) each single free room in turn -- the tightest party that can still
		-- leave a spawn anywhere.
		for skip = 1, #layout.Halls do
			local party = {}
			for index, hall in ipairs(layout.Halls) do
				if index ~= skip then table.insert(party, hallCenter(hall)) end
			end
			considerParty(party)
		end

		if fallbackResult then
			for _, candidate in ipairs(fallbackResult.Candidates) do
				local position = anchors[candidate.Anchor]
				local truth = position and describeIndependently(
					manifest, position, fallbackPositions, pumpIndex, ignore)
				if truth and truth.Tier and (fallbackTier == nil or truth.Tier > fallbackTier) then
					fallbackTier = truth.Tier
				end
			end
			if not (fallbackTier and soloBestTier and fallbackTier < soloBestTier) then
				fallbackResult = nil
			end
		end
	end
	note(report, string.format("fallback sweep: %d parties sampled, %d still had a spawn",
		sweptConfigurations, configurationsWithCandidates))

	if fallbackResult then
		setBranch(report, "fallback-reached")
		note(report, string.format("fallback reached: %d rooms occupied, best tier %d (was %s), %d candidates",
			#fallbackPositions, fallbackTier, tostring(soloBestTier), #fallbackResult.Candidates))
		check(report, #fallbackResult.Candidates > 0,
			"the fallback still offers at least one candidate",
			#fallbackResult.Candidates .. " candidates")
		check(report, fallbackTier < (soloBestTier or 6),
			"the intended LOWER fallback tier was the one exercised",
			string.format("%d < %s", fallbackTier, tostring(soloBestTier)))
		assertRanking("fallback tier", fallbackResult, fallbackPositions)
		assertChosen("fallback tier", fallbackResult, fallbackPositions, false)
	else
		setBranch(report, "fallback-not-reached")
		-- Nothing in the SAMPLE forced a lower choice. The claim is exactly
		-- that, and the reason is derived here rather than taken from the
		-- controller: every sampled party that still had a spawn also had a
		-- top-tier anchor available to it, so a lower tier could not win.
		check(report, topTierSamples > 0 and topTierPresent == topTierSamples,
			string.format("in all %d sampled parties that still had a spawn, an"
				.. " independently derived top-tier anchor was available", topTierSamples),
			string.format("%d of %d", topTierPresent, topTierSamples))
		note(report, "so no party IN THIS SAMPLE can force a lower chosen tier. This is a")
		note(report, "statement about the sampled occupancy configurations only -- the")
		note(report, "power set of occupancies is not enumerated and no claim is made")
		note(report, "about parties outside the sample. The fallback tiers are therefore")
		note(report, "asserted as CANDIDATES below, and the tightest sampled party in full.")

		local fallbackCandidates, occupiedHit, unreachable, tooClose, misTiered = 0, 0, 0, 0, 0
		for _, candidate in ipairs(solo.Candidates) do
			local position = anchors[candidate.Anchor]
			local truth = position
				and describeIndependently(manifest, position, {soloPosition}, pumpIndex, ignore)
			if truth and truth.Tier and soloBestTier and truth.Tier < soloBestTier then
				fallbackCandidates += 1
				if truth.Occupied then occupiedHit += 1 end
				if truth.Hops == nil then unreachable += 1 end
				if truth.MinStuds < EXPECTED_FALLBACK_STUDS then tooClose += 1 end
				if candidate.Tier ~= truth.Tier then misTiered += 1 end
			end
		end
		note(report, string.format("%d of %d ranked candidates sit in a fallback tier",
			fallbackCandidates, #solo.Candidates))
		check(report, fallbackCandidates > 0,
			"the ranking really does contain fallback-tier candidates",
			fallbackCandidates .. " found")
		check(report, occupiedHit == 0 and unreachable == 0 and tooClose == 0 and misTiered == 0,
			"every fallback-tier candidate obeys the same room, reach, proximity and tier rules",
			string.format("%d occupied, %d unreachable, %d too close, %d mis-tiered",
				occupiedHit, unreachable, tooClose, misTiered))

		if check(report, crowdedResult ~= nil,
			"the tightest sampled party that still has a spawn was found") then
			note(report, string.format("tightest sampled party: %d rooms occupied, %d candidates",
				#crowdedPositions, #crowdedResult.Candidates))
			check(report, #crowdedResult.Candidates > 0,
				"and it still offers at least one candidate",
				#crowdedResult.Candidates .. " candidates")
			assertRanking("tightest party", crowdedResult, crowdedPositions)
			assertChosen("tightest party", crowdedResult, crowdedPositions, false)
		end
	end

	-- (6) The occupancy rule holds anywhere in a room, not only at its centre.
	for cornerIndex, corner in ipairs({
		Vector3.new(pumpHall.MinX + 2, soloPosition.Y, pumpHall.MinZ + 2),
		Vector3.new(pumpHall.MaxX - 2, soloPosition.Y, pumpHall.MaxZ - 2),
	}) do
		local result = evaluate({corner})
		check(report, hallContaining(layout, corner) == pumpIndex,
			string.format("corner %d is inside the pump room", cornerIndex))
		local position = result.Chosen and anchors[result.Chosen.Anchor]
		local room = position and roomOf(layout, position)
		check(report, room == nil or room ~= pumpIndex,
			string.format("corner %d: still never the occupied room", cornerIndex),
			tostring(room))
	end

	-- (7) With nobody eligible the whole map opens up again. The controller
	-- documents an empty party as "no room to be too close to and no hop count",
	-- so this asserts that documented shape rather than re-deriving distances
	-- there is nobody to measure from.
	local none = evaluate({})
	check(report, #none.Candidates > 0,
		"with nobody eligible the whole map is available again",
		#none.Candidates .. " candidates")
	local emptyBadTier, emptyBadRoom = 0, 0
	for _, candidate in ipairs(none.Candidates) do
		if candidate.Tier ~= independentTier(EXPECTED_MAX_HOPS, candidate.Hidden, 185) then
			emptyBadTier += 1
		end
		if candidate.HallIndex == nil then emptyBadRoom += 1 end
	end
	check(report, emptyBadTier == 0,
		"an empty party tiers every anchor by the documented empty-map rule",
		emptyBadTier .. " disagreed")
	check(report, emptyBadRoom == 0,
		"and every one of them still names a room", emptyBadRoom .. " did not")

	return report
end

-- A manifest whose pump-2 room has no reachable neighbour, built by cutting
-- that room's connections out of a COPY of the layout. Nothing in the live
-- world changes.
--
-- Suite.Spawn has a branch for "this map gave me nowhere to stage the second
-- player", and on every generated map that branch is unreachable -- so its
-- declared check count was never once verified against anything. Running the
-- suite against a constructed map is what makes that contract real.
local function noNeighbourManifest(manifest)
	local layout = manifest.Layout
	local pumpHall = layout.PumpHalls and layout.PumpHalls[2]
	if not pumpHall then return nil end
	local pumpIndex = tonumber(pumpHall.Index)
	local halls = {}
	for index, hall in ipairs(layout.Halls) do
		if index == pumpIndex or tonumber(hall.Index) == pumpIndex then
			local isolated = table.clone(hall)
			isolated.Connections = {}
			halls[index] = isolated
		else
			halls[index] = hall
		end
	end
	local copiedLayout = table.clone(layout)
	copiedLayout.Halls = halls
	copiedLayout.PumpHalls = table.clone(layout.PumpHalls)
	copiedLayout.PumpHalls[2] = halls[pumpIndex] or pumpHall
	local copied = table.clone(manifest)
	copied.Layout = copiedLayout
	return copied
end

function Suite.SpawnNoNeighbour(manifest)
	local constructed = noNeighbourManifest(manifest)
	if not constructed then
		local report = newReport("Slidemouth spawn (independently verified)", "no-pump-hall")
		check(report, false, "layout exposes a pump 2 hall")
		return report
	end
	return Suite.Spawn(constructed, {IsolatedPumpRoom = true})
end

-- ---------------------------------------------------------------------------
-- SpawnParties -- the room rule reverified with SEVERAL players, and with ties
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN: the multiplayer case was one party. Suite.Spawn stages A
-- in the pump room and B next door, asserts that, and moves on to a sweep whose
-- parties are built by crowding rooms one at a time -- which never produces a
-- TIE, because each step adds exactly one room and the ordering never has to
-- break one. So "prefers as close to the pump room as legally possible" was
-- only ever exercised where a single candidate won outright, and the specific
-- case the design document names -- a friend in the pump room AND another
-- player in the room next door -- was verified once, from one party, by the
-- suite that also derived the expectation from it.
--
-- This stages several deliberately AMBIGUOUS parties: the pump room and every
-- one of its neighbours at once, two players at equal hop distance, two players
-- standing in the SAME room, and a three-player spread. The ranking is read
-- through the controller's own EvaluateSpawn -- nothing here re-implements the
-- rule -- but every EXPECTED answer is computed from this suite's own BFS over
-- the room graph, its own tier thresholds and its own raycasts.

function Suite.SpawnParties(manifest)
	local report = newReport("Slidemouth spawn with a crowded party")
	local layout = manifest.Layout
	local pumpHall = layout.PumpHalls and layout.PumpHalls[2]
	if not (pumpHall and layout.Halls) then
		check(report, false, "layout exposes a pump 2 hall")
		return setBranch(report, "no-pump-hall")
	end
	local pumpIndex = tonumber(pumpHall.Index)
	-- anchorLookup takes EVERY BasePart in the three anchor folders; the
	-- controller's collectAnchors takes only the three authored name prefixes.
	-- Weighing a part the controller can never offer would let this suite derive
	-- a "best tier" nothing could reach and fail the controller for it, so the
	-- prefixes are mirrored here -- deliberately by hand, so a rename fails these
	-- assertions instead of being followed silently.
	local ANCHOR_PREFIXES = {
		"Level 2 Entity Den ", "Level 2 Entity Patrol Node ", "Level 2 Navigation Node ",
	}
	local anchors = {}
	for name, position in pairs(anchorLookup(manifest)) do
		for _, prefix in ipairs(ANCHOR_PREFIXES) do
			if name:find(prefix, 1, true) == 1 then
				anchors[name] = position
				break
			end
		end
	end
	local ignore = sightExclusions(manifest)
	-- Undirected graph, so "hops from the pump room" is also "hops to it".
	local pumpDistance = hops(layout, pumpIndex)

	local neighbours = {}
	for _, raw in ipairs(pumpHall.Connections or {}) do
		local other = tonumber(raw)
		if other and layout.Halls[other] and pumpDistance[other] == 1 then
			table.insert(neighbours, other)
		end
	end
	table.sort(neighbours)
	if not check(report, #neighbours >= 1,
		"the pump room has a reachable neighbour to stage the friend next door in",
		#neighbours .. " found") then
		return setBranch(report, "no-neighbour")
	end
	local secondHop = {}
	for index, distance in pairs(pumpDistance) do
		if distance == 2 and layout.Halls[index] then table.insert(secondHop, index) end
	end
	table.sort(secondHop)

	local function centreOf(index) return hallCenter(layout.Halls[index]) end

	-- Everything the assertions need, derived HERE. The controller's own numbers
	-- are never the expected value for themselves.
	local function expectation(positions)
		local occupied, playerRooms = {}, {}
		for _, position in ipairs(positions) do
			local room = roomOf(layout, position)
			if room and not occupied[room] then
				occupied[room] = true
				table.insert(playerRooms, room)
			end
		end
		local fromPlayers = {}
		for _, room in ipairs(playerRooms) do
			for index, distance in pairs(hops(layout, room)) do
				if fromPlayers[index] == nil or distance < fromPlayers[index] then
					fromPlayers[index] = distance
				end
			end
		end
		local bestTier, bestPumpHops, eligible, preferred = nil, math.huge, 0, false
		for _, position in pairs(anchors) do
			local room = roomOf(layout, position)
			if room and not occupied[room] then
				local hopCount = fromPlayers[room]
				local minStuds = math.huge
				for _, playerPosition in ipairs(positions) do
					minStuds = math.min(minStuds, horizontal(position, playerPosition))
				end
				local tier = independentTier(hopCount,
					not observedFrom(position, positions, ignore), minStuds)
				if tier then
					eligible += 1
					if tier == 5 then preferred = true end
					if bestTier == nil or tier > bestTier then
						bestTier, bestPumpHops = tier, math.huge
					end
					if tier == bestTier then
						local toPump = pumpDistance[room]
						if toPump and toPump < bestPumpHops then bestPumpHops = toPump end
					end
				end
			end
		end
		return {
			Occupied = occupied, FromPlayers = fromPlayers, Rooms = playerRooms,
			BestTier = bestTier, BestPumpHops = bestPumpHops,
			Eligible = eligible, HasPreferred = preferred,
		}
	end

	-- The parties. Every one of them is an occupancy this map really has, and
	-- each is named for the ambiguity it stages.
	local parties = {}
	local function addParty(label, rooms, tie)
		local positions = {}
		for _, index in ipairs(rooms) do
			if layout.Halls[index] then table.insert(positions, centreOf(index)) end
		end
		if #positions == 0 then return end
		table.insert(parties, {Label = label, Rooms = rooms, Positions = positions, Tie = tie == true})
	end
	addParty("a friend in the pump room, another next door",
		{pumpIndex, neighbours[1]}, false)
	local everyNeighbour = {pumpIndex}
	for _, index in ipairs(neighbours) do table.insert(everyNeighbour, index) end
	addParty("the pump room and EVERY one of its neighbours", everyNeighbour, #neighbours >= 2)
	if #neighbours >= 2 then
		addParty("two players at equal hop distance from the pump room",
			{neighbours[1], neighbours[2]}, true)
	elseif #secondHop >= 2 then
		addParty("two players at equal hop distance from the pump room",
			{secondHop[1], secondHop[2]}, true)
	end
	if #secondHop >= 1 then
		addParty("three players spread one, two and zero hops from the pump",
			{pumpIndex, neighbours[1], secondHop[1]}, false)
	end
	-- Read off the pump hall record itself rather than through the Halls array:
	-- every other use of centreOf is guarded by a Halls lookup, and this one has
	-- nowhere to fall back to.
	local duplicatePosition = hallCenter(pumpHall)
	table.insert(parties, {
		Label = "two players standing in the SAME room",
		Rooms = {pumpIndex, pumpIndex},
		Positions = {duplicatePosition, duplicatePosition},
		Tie = true,
	})

	local tieParties = 0
	for _, party in ipairs(parties) do
		if party.Tie then tieParties += 1 end
	end
	note(report, string.format("pump 2 in room %d, %d reachable neighbours, %d second-hop"
		.. " rooms; %d parties staged (%d of them deliberate ties)",
		pumpIndex, #neighbours, #secondHop, #parties, tieParties))
	check(report, #parties >= 3,
		"the sweep built enough distinct occupancies of this map to mean something",
		#parties .. " parties")

	local candidateInOccupied, zeroHop = 0, 0
	local chosenInOccupied, tierWrong, pumpWrong, windowWrong = 0, 0, 0, 0
	local nondeterministic, choicelessWithCandidates = 0, 0
	for _, party in ipairs(parties) do
		local truth = expectation(party.Positions)
		local result = Controller.EvaluateSpawn(manifest, party.Positions, 2)
		local repeated = Controller.EvaluateSpawn(manifest, party.Positions, 2)
		party.Expected = truth
		party.Result = result
		if (result.Chosen and result.Chosen.Anchor)
			~= (repeated.Chosen and repeated.Chosen.Anchor) then
			nondeterministic += 1
		end
		for _, candidate in ipairs(result.Candidates) do
			local position = anchors[candidate.Anchor]
			local room = position and roomOf(layout, position)
			if room and truth.Occupied[room] then candidateInOccupied += 1 end
			if room and truth.FromPlayers[room] == 0 then zeroHop += 1 end
		end
		if result.Chosen == nil then
			-- Offering candidates and choosing none is a fault; so is choosing
			-- none when this suite independently derived an eligible tier.
			if #result.Candidates > 0 or truth.BestTier ~= nil then
				choicelessWithCandidates += 1
			end
		else
			local position = anchors[result.Chosen.Anchor]
			local room = position and roomOf(layout, position)
			local chosenTruth = position and describeIndependently(
				manifest, position, party.Positions, pumpIndex, ignore) or nil
			if room and truth.Occupied[room] then chosenInOccupied += 1 end
			if chosenTruth == nil or chosenTruth.Tier ~= truth.BestTier then tierWrong += 1 end
			if chosenTruth == nil or chosenTruth.PumpHops ~= truth.BestPumpHops then
				pumpWrong += 1
			end
			if truth.HasPreferred and (chosenTruth == nil or chosenTruth.Hops == nil
				or chosenTruth.Hops < EXPECTED_MIN_HOPS
				or chosenTruth.Hops > EXPECTED_MAX_HOPS) then
				windowWrong += 1
			end
			note(report, string.format("%s -> room %s via %s | tier %s (best %s) | %s hop(s)"
				.. " from nearest player | %s from pump (best %s in tier)",
				party.Label, tostring(room), result.Chosen.Anchor,
				tostring(chosenTruth and chosenTruth.Tier), tostring(truth.BestTier),
				tostring(chosenTruth and chosenTruth.Hops),
				tostring(chosenTruth and chosenTruth.PumpHops), tostring(truth.BestPumpHops)))
		end
	end

	check(report, candidateInOccupied == 0,
		"no candidate is offered in any room a player is standing in, in ANY party",
		candidateInOccupied .. " were")
	check(report, zeroHop == 0,
		"and none is 0 hops from a player by this suite's own BFS",
		zeroHop .. " were")
	check(report, chosenInOccupied == 0 and choicelessWithCandidates == 0,
		"the chosen room is never an occupied one -- including the named case, a friend"
		.. " in the pump room and another player in the room next door",
		string.format("%d chose an occupied room, %d had somewhere to go and chose nothing",
			chosenInOccupied, choicelessWithCandidates))
	check(report, tierWrong == 0,
		"every choice sits in the best tier this suite derived for its own party",
		tierWrong .. " did not")
	check(report, pumpWrong == 0,
		"and within that tier it is as close to the pump room as the room graph allows,"
		.. " even where several rooms tie for it",
		pumpWrong .. " were not")
	check(report, windowWrong == 0,
		"wherever a preferred-tier anchor existed, the choice is 1-2 rooms from the"
		.. " nearest player", windowWrong .. " were outside the window")
	-- Two players on the SAME spot are one occupancy, one hop field and one set of
	-- distances, so the ranking has no freedom at all: it must land where a single
	-- player there lands. A ranking that counted a room twice, or that let a
	-- duplicated position perturb a distance, disagrees here.
	local soloResult = Controller.EvaluateSpawn(manifest, {duplicatePosition}, 2)
	local duplicateResult = Controller.EvaluateSpawn(manifest,
		{duplicatePosition, duplicatePosition}, 2)
	check(report, (soloResult.Chosen and soloResult.Chosen.Anchor)
		== (duplicateResult.Chosen and duplicateResult.Chosen.Anchor)
		and #soloResult.Candidates == #duplicateResult.Candidates,
		"two players standing in the SAME room rank exactly as one player there does",
		string.format("%s (%d candidates) vs %s (%d candidates)",
			tostring(soloResult.Chosen and soloResult.Chosen.Anchor), #soloResult.Candidates,
			tostring(duplicateResult.Chosen and duplicateResult.Chosen.Anchor),
			#duplicateResult.Candidates))
	check(report, nondeterministic == 0,
		"and every party produces the same choice when the ranking is asked twice --"
		.. " a tie is broken by a rule, not by table order",
		nondeterministic .. " parties answered differently")
	check(report, tieParties > 0,
		"the sweep really did stage the deliberate ties it exists for",
		tieParties .. " tie parties")

	return report
end

-- ---------------------------------------------------------------------------
-- SpawnContract -- the room rule as an INVARIANT, enforced at the commit
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN: "1 to 2 rooms from the nearest player" was three
-- different rules in three places, and none of them was a hard one.
--
--   * the ranking DEMOTED an out-of-window room (tier 4 / tier 2) instead of
--     refusing it, and both of those outranked tier 1 -- a room INSIDE the
--     window. Pump proximity is compared inside a tier, so the tier ladder is
--     exactly how pump rank reached a room the hop rule was meant to exclude;
--   * the commit-time re-check (spawnStillSafe) re-tested occupancy and studs
--     and never re-measured hops at all, so a party that closed two rooms of
--     graph distance during the validation fan passed it;
--   * and the pump-three escalation carried a third paraphrase of the room rule
--     with no hop bound whatsoever.
--
-- There is now ONE predicate, and Controller.EvaluateSpawnContract runs the
-- very function the commit calls. Every expected answer below is derived from
-- the room graph THIS FILE walks, never from the metadata the controller
-- reports about itself.
function Suite.SpawnContract(manifest)
	local report = newReport("Slidemouth spawn contract (enforced at commit)")
	local layout = manifest.Layout
	local pumpHall = layout.PumpHalls and layout.PumpHalls[2]
	if not (pumpHall and layout.Halls) then
		check(report, false, "layout exposes a pump 2 hall")
		return setBranch(report, "no-pump-hall")
	end
	local pumpIndex = tonumber(pumpHall.Index)
	-- The three authored prefixes collectAnchors takes, mirrored by hand so a
	-- rename fails these assertions instead of being followed silently.
	local ANCHOR_PREFIXES = {
		"Level 2 Entity Den ", "Level 2 Entity Patrol Node ", "Level 2 Navigation Node ",
	}
	local anchors = {}
	for name, position in pairs(anchorLookup(manifest)) do
		for _, prefix in ipairs(ANCHOR_PREFIXES) do
			if name:find(prefix, 1, true) == 1 then
				anchors[name] = position
				break
			end
		end
	end
	local pumpDistance = hops(layout, pumpIndex)
	local neighbourIndex
	for _, raw in ipairs(pumpHall.Connections or {}) do
		local other = tonumber(raw)
		if other and layout.Halls[other] and pumpDistance[other] == 1 then
			neighbourIndex = other
			break
		end
	end
	if not check(report, neighbourIndex ~= nil,
		"the pump room has a reachable room next door to stage the friend in") then
		return setBranch(report, "no-neighbour")
	end

	-- The contract restated from the room graph alone: a room is admissible
	-- exactly when it is a room, nobody is standing in it, it is 1 or 2 hops from
	-- the NEAREST living player, and it clears the proximity floor. Pump distance
	-- is deliberately not in it -- that is the whole point.
	local function expectedAdmission(positions)
		local occupied, playerRooms = {}, {}
		for _, position in ipairs(positions) do
			local room = roomOf(layout, position)
			if room and not occupied[room] then
				occupied[room] = true
				table.insert(playerRooms, room)
			end
		end
		local fromPlayers = {}
		for _, room in ipairs(playerRooms) do
			for index, distance in pairs(hops(layout, room)) do
				if fromPlayers[index] == nil or distance < fromPlayers[index] then
					fromPlayers[index] = distance
				end
			end
		end
		local admitted, detail, admittedCount = {}, {}, 0
		for name, position in pairs(anchors) do
			local room = roomOf(layout, position)
			local minStuds = math.huge
			for _, playerPosition in ipairs(positions) do
				minStuds = math.min(minStuds, horizontal(position, playerPosition))
			end
			local hopCount = room and fromPlayers[room] or nil
			local ok = room ~= nil and occupied[room] ~= true
				and hopCount ~= nil
				and hopCount >= EXPECTED_MIN_HOPS and hopCount <= EXPECTED_MAX_HOPS
				and minStuds >= EXPECTED_FALLBACK_STUDS
			detail[name] = {Room = room, Hops = hopCount, Studs = minStuds, Ok = ok}
			if ok then
				admitted[name] = true
				admittedCount += 1
			end
		end
		return {Admitted = admitted, Detail = detail, Occupied = occupied,
			Rooms = playerRooms, FromPlayers = fromPlayers, Count = admittedCount}
	end

	local function admittedSet(result)
		local set, count = {}, 0
		for _, entry in ipairs(result.Admitted) do
			if set[entry.Anchor] == nil then count += 1 end
			set[entry.Anchor] = entry
		end
		return set, count
	end

	local function firstFew(list)
		local out = {}
		for _, text in ipairs(list) do
			if #out >= 4 then break end
			table.insert(out, text)
		end
		return #out > 0 and table.concat(out, "; ") or "none"
	end

	-- (1) The named case: A in the pump room, B in the room next door.
	local partyPositions = {hallCenter(pumpHall), hallCenter(layout.Halls[neighbourIndex])}
	local truth = expectedAdmission(partyPositions)
	local live = Controller.EvaluateSpawnContract(manifest, partyPositions)
	local liveSet, liveCount = admittedSet(live)
	note(report, string.format("A in room %d (pump 2), B in room %d (next door);"
		.. " %d anchors, %d admitted by the contract, %d admissible on the room graph",
		pumpIndex, neighbourIndex, live.AnchorCount, liveCount, truth.Count))

	check(report,
		truth.Occupied[pumpIndex] == true and truth.Occupied[neighbourIndex] == true
			and #truth.Rooms == 2
			and live.Occupied[pumpIndex] == true and live.Occupied[neighbourIndex] == true
			and #live.PlayerHalls == 2,
		"the staged party occupies exactly the pump room and the room next door, by"
		.. " the production reader and by the room graph alike",
		string.format("graph %d rooms, contract %d rooms", #truth.Rooms, #live.PlayerHalls))

	local overAdmitted, underAdmitted = {}, {}
	for name in pairs(liveSet) do
		if not truth.Admitted[name] then
			local entry = truth.Detail[name]
			table.insert(overAdmitted, string.format("%s (room %s, %s hops, %.0f studs)",
				name, tostring(entry and entry.Room), tostring(entry and entry.Hops),
				entry and entry.Studs or -1))
		end
	end
	for name in pairs(truth.Admitted) do
		if not liveSet[name] then table.insert(underAdmitted, name) end
	end
	check(report, #overAdmitted == 0,
		"every anchor the contract admits is one the room graph admits too",
		string.format("%d were not: %s", #overAdmitted, firstFew(overAdmitted)))
	check(report, #underAdmitted == 0,
		"and every anchor the room graph admits is offered by the contract",
		string.format("%d were missing: %s", #underAdmitted, firstFew(underAdmitted)))

	local inPumpRoom, inNeighbourRoom, outsideWindow = 0, 0, 0
	for name in pairs(liveSet) do
		local entry = truth.Detail[name]
		if entry and entry.Room == pumpIndex then inPumpRoom += 1 end
		if entry and entry.Room == neighbourIndex then inNeighbourRoom += 1 end
		if not (entry and entry.Hops and entry.Hops >= EXPECTED_MIN_HOPS
			and entry.Hops <= EXPECTED_MAX_HOPS) then
			outsideWindow += 1
		end
	end
	check(report, inPumpRoom == 0,
		"no admitted anchor stands in the pump room -- the room A is standing in",
		inPumpRoom .. " did")
	check(report, inNeighbourRoom == 0,
		"and none stands in the room B is standing in, though B is not the nearest"
		.. " player to most of the map",
		inNeighbourRoom .. " did")
	check(report, outsideWindow == 0,
		"every admitted anchor is 1 or 2 hops from the NEAREST of the two players"
		.. " (independent BFS)", outsideWindow .. " were not")

	-- (2) Pump proximity may never reach outside the admitted set.
	local bestAdmittedPumpHops = math.huge
	for name in pairs(truth.Admitted) do
		local entry = truth.Detail[name]
		local toPump = entry and entry.Room and pumpDistance[entry.Room] or nil
		if toPump and toPump < bestAdmittedPumpHops then bestAdmittedPumpHops = toPump end
	end
	local promoted, closerToPump = {}, 0
	for name, position in pairs(anchors) do
		local room = roomOf(layout, position)
		local toPump = room and pumpDistance[room] or nil
		if toPump and toPump < bestAdmittedPumpHops then
			closerToPump += 1
			if liveSet[name] then
				table.insert(promoted, string.format("%s (room %s, %d hops to the pump)",
					name, tostring(room), toPump))
			end
		end
	end
	note(report, string.format("%d anchors sit closer to the pump room than the best"
		.. " admitted one (%s hops), and the ranking may not reach any of them",
		closerToPump, bestAdmittedPumpHops < math.huge
			and tostring(bestAdmittedPumpHops) or "no"))
	check(report, #promoted == 0,
		"an anchor closer to the pump room than anything admitted is still refused --"
		.. " pump proximity ranks INSIDE the valid set and never promotes into it",
		string.format("%d were promoted: %s", #promoted, firstFew(promoted)))

	-- (3) The choice the production ranking makes, judged by the same graph.
	local ranked = Controller.EvaluateSpawn(manifest, partyPositions, 2)
	local chosenName = ranked.Chosen and ranked.Chosen.Anchor or nil
	local chosenTruth = chosenName and truth.Detail[chosenName] or nil
	check(report, chosenName ~= nil and liveSet[chosenName] ~= nil,
		"the choice the ranking makes is an anchor the contract admits",
		string.format("chose %s", tostring(chosenName)))
	check(report, chosenTruth ~= nil and chosenTruth.Room ~= pumpIndex
		and chosenTruth.Room ~= neighbourIndex
		and chosenTruth.Hops ~= nil
		and chosenTruth.Hops >= EXPECTED_MIN_HOPS and chosenTruth.Hops <= EXPECTED_MAX_HOPS,
		"and it lands in NEITHER staged room, 1 or 2 hops from the nearest of them",
		chosenTruth and string.format("room %s, %s hops", tostring(chosenTruth.Room),
			tostring(chosenTruth.Hops)) or "no choice was made")

	-- (4) A deliberate TIE: two players whose rooms are two hops apart, so the
	-- room between them is exactly one hop from each and neither player is the
	-- nearer by any margin at all.
	local tieA, tieB, tieMiddle
	for arrayIndex, hall in ipairs(layout.Halls) do
		local a = tonumber(hall.Index) or arrayIndex
		local fromA = hops(layout, a)
		for otherIndex, distance in pairs(fromA) do
			if distance == 2 and layout.Halls[otherIndex] then
				local fromB = hops(layout, otherIndex)
				for middle, first in pairs(fromA) do
					if first == 1 and fromB[middle] == 1 and layout.Halls[middle] then
						tieA, tieB, tieMiddle = a, otherIndex, middle
						break
					end
				end
			end
			if tieMiddle then break end
		end
		if tieMiddle then break end
	end
	if not check(report, tieMiddle ~= nil,
		"the map supplies a deliberate tie: two rooms two hops apart with a room"
		.. " between them that is one hop from each") then
		return setBranch(report, "no-tie")
	end
	local tiePositions = {hallCenter(layout.Halls[tieA]), hallCenter(layout.Halls[tieB])}
	local tieTruth = expectedAdmission(tiePositions)
	local tieLive = Controller.EvaluateSpawnContract(manifest, tiePositions)
	local tieSet, tieCount = admittedSet(tieLive)
	note(report, string.format("tie: players in rooms %d and %d, room %d one hop from"
		.. " both of them, %d anchors admitted", tieA, tieB, tieMiddle, tieCount))
	local tieDisagreements = {}
	for name in pairs(tieSet) do
		if not tieTruth.Admitted[name] then
			table.insert(tieDisagreements, name .. " admitted but not admissible")
		end
	end
	for name in pairs(tieTruth.Admitted) do
		if not tieSet[name] then
			table.insert(tieDisagreements, name .. " admissible but not offered")
		end
	end
	check(report, #tieDisagreements == 0,
		"with the hop distance TIED between two players the admitted set is still"
		.. " exactly the answer the room graph gives",
		string.format("%d disagreements: %s", #tieDisagreements, firstFew(tieDisagreements)))
	local middleAnchors, middleWrong = 0, 0
	for name, position in pairs(anchors) do
		if roomOf(layout, position) == tieMiddle then
			middleAnchors += 1
			if (tieSet[name] ~= nil) ~= (tieTruth.Admitted[name] == true) then
				middleWrong += 1
			end
		end
	end
	check(report, middleAnchors > 0 and middleWrong == 0,
		"and the room that ties -- one hop from BOTH players -- is judged on the tie"
		.. " rather than on either player alone",
		string.format("%d anchors in room %d, %d judged differently",
			middleAnchors, tieMiddle, middleWrong))

	-- (5) A saturated map: a player in every room. There is nowhere legal to
	-- appear, and the answer is to WAIT.
	local everywhere = {}
	for _, hall in ipairs(layout.Halls) do table.insert(everywhere, hallCenter(hall)) end
	local saturatedTruth = expectedAdmission(everywhere)
	local saturated = Controller.EvaluateSpawnContract(manifest, everywhere)
	local _, saturatedCount = admittedSet(saturated)
	check(report, saturatedCount == 0 and saturatedTruth.Count == 0,
		"a player in every room admits no anchor at all",
		string.format("the contract admitted %d, the room graph admitted %d",
			saturatedCount, saturatedTruth.Count))
	local saturatedCommit = Controller.EvaluateSpawnCommit(manifest, everywhere, 2)
	check(report, saturatedCommit.Committed == nil and saturatedCommit.RankedCount == 0,
		"and the commit takes nothing -- the spawn WAITS, it never falls back to a"
		.. " room further away and never spawns anyway",
		string.format("committed %s out of %d ranked",
			tostring(saturatedCommit.Committed), saturatedCommit.RankedCount))

	-- (6) A player MOVING DURING SELECTION. The ranking is taken, B then walks
	-- into the very room it picked, and only then does the commit run. This is
	-- the window spawnStillSafe existed to close and half closed.
	local movingPositions = {hallCenter(pumpHall), hallCenter(layout.Halls[neighbourIndex])}
	local pickedName, pickedHall
	local moved = false
	local movingResult = Controller.EvaluateSpawnCommit(manifest, movingPositions, 2,
		function(name, hallIndex)
			pickedName, pickedHall = name, hallIndex
			if hallIndex and layout.Halls[hallIndex] then
				movingPositions[2] = hallCenter(layout.Halls[hallIndex])
				moved = true
			end
		end)
	local movedTruth = expectedAdmission(movingPositions)
	note(report, string.format("the ranking picked %s in room %s, B then walked into"
		.. " room %s, and the commit answered %s (%s)",
		tostring(pickedName), tostring(pickedHall), tostring(pickedHall),
		tostring(movingResult.Committed), tostring(movingResult.PickedReason)))
	check(report, moved and pickedName ~= nil and truth.Admitted[pickedName] == true,
		"the ranking picked a room that was admissible at the moment it was picked,"
		.. " and the probe really did move a player into it",
		string.format("picked %s, moved %s", tostring(pickedName), tostring(moved)))
	check(report, movingResult.PickedStillValid == false
		and typeof(movingResult.PickedReason) == "string"
		and movingResult.PickedReason:find("holds a living player", 1, true) ~= nil,
		"and the commit -- recomputing from the party as it stands NOW -- refuses it,"
		.. " naming the room as occupied",
		string.format("still valid: %s (%s)", tostring(movingResult.PickedStillValid),
			tostring(movingResult.PickedReason)))
	check(report, movingResult.Committed ~= pickedName,
		"the commit never takes the candidate the move invalidated",
		string.format("committed %s, picked %s", tostring(movingResult.Committed),
			tostring(pickedName)))
	check(report, movingResult.Committed == nil
		or movedTruth.Admitted[movingResult.Committed] == true,
		"and whatever it takes instead is admissible against the party AS MOVED --"
		.. " taking nothing is a valid answer, taking an invalid room is not",
		string.format("committed %s", tostring(movingResult.Committed)))

	return report
end

-- ---------------------------------------------------------------------------
-- LiveSpawn -- the production path, including its live re-check
-- ---------------------------------------------------------------------------

local function level2State()
	local state = ReplicatedStorage:FindFirstChild("Level 2 State")
	return state and state:IsA("Folder") and state or nil
end

local function standOn(params, position)
	local hit = workspace:Raycast(Vector3.new(position.X, 30, position.Z),
		Vector3.new(0, -180, 0), params)
	return hit and Vector3.new(position.X, hit.Position.Y + 3.5, position.Z) or nil
end

local ROUND_ATTRIBUTES = {
	"SelectedLevel", "WorldGenerated", "RoundActive", "EntityPaused", "Level2Pumps",
}

local function armRound()
	workspace:SetAttribute("SelectedLevel", 2)
	workspace:SetAttribute("WorldGenerated", true)
	workspace:SetAttribute("RoundActive", true)
	workspace:SetAttribute("EntityPaused", nil)
end

local function waitForSpawn(timeout)
	local state = level2State()
	local deadline = os.clock() + (timeout or 25)
	while os.clock() < deadline do
		if state and state:GetAttribute("Level2_SlidemouthActive") == true then return true end
		task.wait(.2)
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Complete, reversible isolation
-- ---------------------------------------------------------------------------
--
-- Everything below snapshots WHOLE attribute maps rather than a hand-picked
-- list. A named list is only ever right until something publishes a new
-- attribute -- Level2_SlidemouthChased and the player-side BeingChased were
-- both missing from the last one -- and the residue scan then reports clean
-- because it was looking at the same short list.

local function attributeSnapshot(instance)
	if not instance then return nil end
	return instance:GetAttributes()
end

-- Put every attribute back: values this suite changed, values it deleted, and
-- attributes it created that were never there. Raises on anything it cannot
-- restore, which `protect` turns into a failed assertion.
local function restoreAttributes(instance, snapshot, label)
	if not (instance and snapshot) then return end
	for name in pairs(instance:GetAttributes()) do
		if snapshot[name] == nil then instance:SetAttribute(name, nil) end
	end
	for name, value in pairs(snapshot) do
		instance:SetAttribute(name, value)
	end
	local problems = {}
	local after = instance:GetAttributes()
	for name, value in pairs(snapshot) do
		if after[name] ~= value then
			table.insert(problems, string.format("%s.%s (%s, wanted %s)",
				label, name, tostring(after[name]), tostring(value)))
		end
	end
	for name in pairs(after) do
		if snapshot[name] == nil then
			table.insert(problems, string.format("%s.%s (created by the test)", label, name))
		end
	end
	assert(#problems == 0, table.concat(problems, ", "))
end

-- Every field of the controller's debug state, compared field by field. A
-- session restored by Generation alone loses its spawn choice, its target, its
-- processed pump count, its recovery stage and where the creature was standing;
-- comparing the whole structure is what makes that visible.
local function snapshotDrift(before, after, path, out)
	out = out or {}
	path = path or ""
	if type(before) ~= type(after) then
		table.insert(out, string.format("%s (%s vs %s)", path ~= "" and path or "root",
			typeof(before), typeof(after)))
		return out
	end
	if type(before) ~= "table" then
		local same = before == after
		if type(before) == "number" and type(after) == "number" then
			-- Exact first: math.abs(inf - inf) is NaN, and NaN fails every
			-- comparison, so a tolerance test alone reported two identical
			-- infinities -- a disarmed SpawnRetryAt, for one -- as drift.
			same = before == after or math.abs(before - after) <= 1e-3
		end
		if not same then
			table.insert(out, string.format("%s (%s vs %s)", path,
				tostring(before), tostring(after)))
		end
		return out
	end
	local keys = {}
	for key in pairs(before) do keys[key] = true end
	for key in pairs(after) do keys[key] = true end
	for key in pairs(keys) do
		snapshotDrift(before[key], after[key],
			path == "" and tostring(key) or (path .. "." .. tostring(key)), out)
	end
	return out
end

-- Was this instance DESTROYED?
--
-- NOT `pcall(function() inst.Parent = inst.Parent end)`, which is what these
-- checks used to ask. Assigning a Parent its own current value is a no-op and
-- Roblox raises nothing for it -- measured here, in this place, on a live
-- instance AND on a destroyed one: both return true. So that form can never be
-- false, and the two "Stop(handle) on a parked session really destroys it"
-- checks passed for every possible behaviour of Stop, including doing nothing
-- at all. A false green in a suite written to catch false greens.
--
-- A destroyed instance refuses a reparent to a REAL parent ("The Parent
-- property of X is locked"). The probe parent is a Folder this module never
-- parents to anything, so a LIVE instance is moved nowhere the world can see
-- and is put straight back where it was.
local DESTRUCTION_PROBE = Instance.new("Folder")
DESTRUCTION_PROBE.Name = "SlidemouthSuiteDestructionProbe"

local function wasDestroyed(instance)
	if instance == nil then return false end
	local previous = instance.Parent
	local ok = pcall(function() instance.Parent = DESTRUCTION_PROBE end)
	if not ok then return true end
	instance.Parent = previous
	return false
end

local function runtimeFolders(manifest)
	local found = {}
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:IsA("Folder") and descendant.Name == "Level 2 Slidemouth Runtime" then
			table.insert(found, descendant)
		end
	end
	return found
end

-- GetFullDebugSnapshot reports a clock reading as WHOLE REMAINING SECONDS, and
-- passes the sentinels -- 0, the infinities, NaN, anything that is not a number
-- -- straight through. A test holding an ABSOLUTE pre-arm deadline, which is
-- what armed.Restore.Deadlines carries, has to convert it the same way before
-- the two can be compared at all.
local function expectedTimerReading(value, now)
	if type(value) == "number" and value == value
		and value ~= 0 and value ~= math.huge and value ~= -math.huge then
		return math.floor(value - now)
	end
	return value
end

-- Two whole-second readings of the SAME absolute deadline, taken a moment apart,
-- may floor either side of a second boundary. Exact first, for the same reason
-- snapshotDrift tests exact first: math.abs(inf - inf) is NaN and NaN fails
-- every comparison, so a tolerance test alone reports a disarmed SpawnRetryAt
-- (math.huge, on both sides) as drift.
local function timerAgrees(actual, expected)
	if actual == expected then return true end
	if type(actual) == "number" and type(expected) == "number"
		and actual == actual and expected == expected
		and actual ~= math.huge and actual ~= -math.huge
		and expected ~= math.huge and expected ~= -math.huge then
		return math.abs(actual - expected) <= 1
	end
	return false
end

-- RequestId and Computing are the two fields a correct pause is REQUIRED to
-- change: the id is bumped to kill the in-flight compute and is deliberately
-- never restored, and Computing is decided by the resume's restart-or-settle
-- rule rather than copied back. A whole-surface comparison that expected them
-- unchanged would be demanding the very corruption a borrow exists to prevent.
--
-- RemainingSeconds is a float floored to a whole second. A borrow that preserves
-- it perfectly can still straddle a second boundary and read one lower
-- afterwards, so exact equality here would be a coin toss; the dedicated checks
-- assert it with the tolerance the quantisation warrants. Played stays in.
local function comparableSnapshot(snapshot)
	local copy = table.clone(snapshot)
	if copy.Navigation then
		copy.Navigation = table.clone(copy.Navigation)
		copy.Navigation.RequestId = nil
		copy.Navigation.Computing = nil
	end
	-- The session-level twins of those two, and the same argument: see
	-- UNRESTORED_SESSION_VALUES. A borrow bumps the run token twice by design and
	-- may leave an escalation marker behind it, and a comparison that demanded
	-- either back would be demanding that the pause hand its cancelled jobs their
	-- session again.
	if copy.Values then
		copy.Values = table.clone(copy.Values)
		for _, name in ipairs(UNRESTORED_SESSION_VALUES) do
			copy.Values[name] = nil
		end
	end
	if copy.Screams then
		local screams = {}
		for pumpNumber, record in pairs(copy.Screams) do
			screams[pumpNumber] = {Played = record.Played}
		end
		copy.Screams = screams
	end
	return copy
end

-- Every Level2_Slidemouth* attribute on an instance, as one comparable table.
-- "Byte-identical" is the assertion a Stop() that must not republish needs, and
-- a hand-picked list of names is only ever right until something publishes a new
-- attribute -- which is how the ~22 attributes a pause handle owes back went
-- unwatched in the first place.
local function slidemouthSurface(instance)
	local surface = {}
	if not instance then return surface end
	for name, value in pairs(instance:GetAttributes()) do
		if string.sub(name, 1, #Controller.PublishedAttributePrefix)
			== Controller.PublishedAttributePrefix then
			surface[name] = value
		end
	end
	return surface
end

local function surfaceDifferences(before, after)
	local problems = {}
	for name, value in pairs(before) do
		if after[name] ~= value then
			table.insert(problems, string.format("%s %s -> %s", name,
				tostring(value), tostring(after[name])))
		end
	end
	for name, value in pairs(after) do
		if before[name] == nil then
			table.insert(problems, string.format("%s absent -> %s", name, tostring(value)))
		end
	end
	return problems
end

function Suite.LiveSpawn(manifest)
	local report = newReport("Slidemouth live spawn (production path)")
	local player = Players:GetPlayers()[1]
	if not check(report, player ~= nil, "a player is present to stage the round with") then
		return setBranch(report, "no-player")
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not check(report, root ~= nil, "the player has a character to place") then
		return setBranch(report, "no-character")
	end

	return protect(report, function(onCleanup)
		-- ---------------------------------------------------------------
		-- Snapshot everything, then register the cleanups.
		-- ---------------------------------------------------------------
		local worldBefore = attributeSnapshot(workspace)
		local stateBefore = attributeSnapshot(level2State())
		local playersBefore = {}
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			playersBefore[other] = {
				Attributes = attributeSnapshot(other),
				CFrame = otherRoot and otherRoot.CFrame or nil,
			}
		end
		local runtimeBefore = #runtimeFolders(manifest)

		-- A session that was already running must survive this suite EXACTLY.
		-- If there is none, the suite starts one, so the pause/resume path is
		-- exercised on every run rather than only when the place happens to be
		-- mid-round -- and stops that one again at the end, leaving the true
		-- original state behind.
		--
		-- EVERY cleanup is registered BEFORE the first mutation. The previous
		-- order started and paused the incumbent and only then registered the
		-- handler that could give it back, so anything that threw in between --
		-- including inside Start or the pause itself -- left a live creature
		-- paused, parented to nil, with nobody holding its handle.
		local hadSession = Controller.IsRunning()
		local synthetic = false
		local incumbentBefore, parked, resumeError
		-- The session THIS suite started, held by reference. Everything this
		-- cleanup stops, it stops by naming it: a no-argument Stop() stops
		-- whatever is ACTIVE, and after the resume below that is the borrowed
		-- incumbent itself.
		local suiteSession
		-- How many runtime folders the world holds once the incumbent is PARKED:
		-- a parked session's folder is deliberately detached, so this is one lower
		-- than runtimeBefore whenever there was an incumbent to park.
		local runtimeAfterPause

		-- Registered in reverse of the order they run: players, then Workspace,
		-- then the controller, then the replicated state -- so the controller
		-- compares itself against a Workspace that is already restored, and the
		-- session's own republishing happens before the state map is put back.
		onCleanup("replicated Level 2 state", function()
			restoreAttributes(level2State(), stateBefore, "Level 2 State")
		end)
		onCleanup("controller session", function()
			Controller._spawnInterlude = nil
			-- WHAT SHIPPED BROKEN: this was an unconditional Controller.Stop(). On
			-- the success path the resume below has already made the borrowed
			-- incumbent the active session, so that Stop destroyed the very session
			-- it had just given back -- and the residue assertion used `<=`, which
			-- reads a deletion as clean. Only the suite's own session is stopped
			-- now, and only by naming it.
			if suiteSession then
				Controller.Stop(suiteSession)
				suiteSession = nil
			end
			if parked then
				local resumed, err = Controller.DebugResumeSession(parked)
				resumeError = err
				assert(resumed, "the paused session could not be resumed: " .. tostring(err))
				-- comparableSnapshot, not the raw snapshot: a resumed navigator
				-- carries a bumped RequestId and a restarted request BY DESIGN, so a
				-- raw comparison fails the moment a real incumbent with a navigator
				-- is borrowed -- which is every incumbent that has spawned.
				local drift = snapshotDrift(comparableSnapshot(incumbentBefore),
					comparableSnapshot(Controller.GetFullDebugSnapshot()))
				assert(#drift == 0,
					"the resumed session is not the one that was paused: "
					.. table.concat(drift, ", "))
				if synthetic then
					-- Targeted, so a REAL incumbent standing behind it could never be
					-- caught by this.
					Controller.Stop(parked)
					assert(not Controller.IsRunning(),
						"the suite's own pre-test session was not stopped")
				end
			end
			assert(Controller.IsRunning() == hadSession,
				"the controller's running state was not restored")
			assert(Controller.DebugParkedCount() == 0,
				"a session was left parked: " .. tostring(Controller.DebugParkedCount()))
			-- EXACT. `<=` accepted the deletion of the incumbent's own folder as a
			-- clean result, which is precisely what the unconditional Stop above did.
			assert(#runtimeFolders(manifest) == runtimeBefore,
				string.format("runtime folders: %d, %d before",
					#runtimeFolders(manifest), runtimeBefore))
		end)
		onCleanup("workspace attributes", function()
			restoreAttributes(workspace, worldBefore, "Workspace")
		end)
		onCleanup("player state", function()
			for other, saved in pairs(playersBefore) do
				if other.Parent == Players then
					restoreAttributes(other, saved.Attributes, other.Name)
					local otherRoot = other.Character
						and other.Character:FindFirstChild("HumanoidRootPart")
					if otherRoot and saved.CFrame then otherRoot.CFrame = saved.CFrame end
				end
			end
		end)

		-- ---------------------------------------------------------------
		-- Only now is anything touched.
		-- ---------------------------------------------------------------
		if not hadSession then
			suiteSession = Controller.Start(manifest, manifest.Generation or 1)
			synthetic = Controller.IsRunning()
		end
		check(report, Controller.IsRunning(),
			"there is a live session to borrow the world from",
			hadSession and "pre-existing" or "started by the suite")
		incumbentBefore = Controller.GetFullDebugSnapshot()
		local pauseError
		parked, pauseError = Controller.DebugPauseSession()

		check(report, parked ~= nil,
			"the incumbent controller session was PAUSED, not destroyed", pauseError)
		check(report, parked == nil or parked.PartialFailures == nil,
			"and every stage of the pause succeeded",
			parked and parked.PartialFailures and table.concat(parked.PartialFailures, "; ") or nil)
		check(report, parked == nil or Controller.DebugSessionPhase(parked) == "PAUSED",
			"the incumbent session is PAUSED rather than STOPPED",
			parked and Controller.DebugSessionPhase(parked) or nil)
		check(report, not Controller.IsRunning(),
			"and the suite starts from a clean controller")
		-- Without this the next Controller.Start() below would stop a still-active
		-- incumbent outright, and the suite that exists to prove the incumbent
		-- survives a borrow would be the thing that destroyed it.
		if not parked then return setBranch(report, "no-pause") end
		runtimeAfterPause = #runtimeFolders(manifest)

		local layout = manifest.Layout
		local pumpHall = layout.PumpHalls[2]
		local pumpIndex = tonumber(pumpHall.Index)
		local params = groundParamsFor(manifest)
		local anchors = anchorLookup(manifest)
		local state = level2State()
		if not check(report, state ~= nil, "the Level 2 state folder exists") then
			return setBranch(report, "no-state")
		end
		local runtime = manifest.World:FindFirstChild("Level 2 Slidemouth Runtime", true)

		-- Stage the player on a patrol node: by construction a spot the creature
		-- itself can occupy, so the room is genuinely reachable.
		local stagePosition
		for _, d in ipairs(manifest.EntityNodes:GetDescendants()) do
			if d:IsA("BasePart")
				and d.Name:find("Level 2 Entity Patrol Node " .. tostring(pumpIndex) .. ".", 1, true) then
				stagePosition = d.Position + Vector3.new(0, 3, 0)
				break
			end
		end
		stagePosition = stagePosition or standOn(params, hallCenter(pumpHall))
		if not check(report, stagePosition ~= nil, "found a place to stage the player") then
			return setBranch(report, "no-stage")
		end

		suiteSession = Controller.Start(manifest, manifest.Generation or 1)
		root.CFrame = CFrame.new(stagePosition)
		player:SetAttribute("InRound", true)
		player:SetAttribute("Escaped", nil)
		armRound()
		task.wait(.4)
		workspace:SetAttribute("Level2Pumps", 1)
		task.wait(.5)
		workspace:SetAttribute("Level2Pumps", 2)
		local spawned = waitForSpawn(25)
		check(report, spawned, "the creature spawns through the real pump transition")
		if not spawned then return setBranch(report, "no-spawn") end

		local snapshot = Controller.GetDebugSnapshot()
		local raw = snapshot.Position
		local position = raw and Vector3.new(raw.X, raw.Y, raw.Z)
		if not check(report, position ~= nil, "the creature reports a position") then
			return setBranch(report, "no-position")
		end

		local ignore = sightExclusions(manifest, runtime and {runtime} or nil)
		local truth = describeIndependently(manifest, position, {root.Position}, pumpIndex, ignore)
		note(report, string.format(
			"live: creature in room %s, %s hop(s) from the player, %s from pump %d, %.0f studs, %s",
			tostring(truth.Room), tostring(truth.Hops), tostring(truth.PumpHops), pumpIndex,
			truth.MinStuds, truth.Observed and "IN SIGHT" or "out of sight"))
		check(report, truth.Room ~= nil, "the creature stands inside a known room")
		check(report, not truth.Occupied, "the creature is not in the player's room")
		check(report, truth.Hops ~= nil and truth.Hops >= EXPECTED_MIN_HOPS,
			"the creature is at least one room from the player", tostring(truth.Hops))
		check(report, truth.MinStuds >= EXPECTED_FALLBACK_STUDS,
			"the creature is outside the proximity floor",
			string.format("%.0f studs", truth.MinStuds))
		check(report, state:GetAttribute("Level2_SlidemouthSpawnHall") == truth.Room,
			"published spawn room matches the creature's real room",
			string.format("published %s, actual %s",
				tostring(state:GetAttribute("Level2_SlidemouthSpawnHall")), tostring(truth.Room)))
		check(report, state:GetAttribute("Level2_SlidemouthSpawnPlayerHops") == truth.Hops,
			"published hop count matches the independent BFS",
			string.format("published %s, actual %s",
				tostring(state:GetAttribute("Level2_SlidemouthSpawnPlayerHops")), tostring(truth.Hops)))

		-- ------------------------------------------------------------------
		-- The real race, injected deterministically at the commit point.
		-- ------------------------------------------------------------------
		-- The seam fires inside spawnEntity AFTER a candidate has passed
		-- placement, route and escape-clearance validation, with one call left
		-- before it is committed: the live safety re-check. Mutating there means
		-- the candidate the player is moved onto WOULD have been taken.
		do
			Controller.Stop()
			workspace:SetAttribute("Level2Pumps", 0)
			root.CFrame = CFrame.new(stagePosition)
			task.wait(.4)

			local fired = 0
			local targeted, targetedRoom, targetedClearance, movedInto
			Controller._spawnInterlude = function(info)
				if fired > 0 or not info.Clearance then return end
				fired += 1
				targeted = info.Candidate.Anchor.Name
				targetedRoom = info.Candidate.HallIndex
				targetedClearance = info.Clearance
				local at = standOn(params, info.Candidate.Anchor.Position)
					or (info.Candidate.Anchor.Position + Vector3.new(0, 3, 0))
				root.CFrame = CFrame.new(at)
				movedInto = roomOf(manifest.Layout, root.Position)
			end

			local session = Controller.Start(manifest, manifest.Generation or 1)
			suiteSession = session
			check(report, session ~= nil, "the controller restarts for the race test")
			armRound()
			task.wait(.3)
			workspace:SetAttribute("Level2Pumps", 1)
			task.wait(.4)
			workspace:SetAttribute("Level2Pumps", 2)
			local raced = waitForSpawn(25)
			Controller._spawnInterlude = nil
			check(report, fired == 1,
				"the seam fired once, on a candidate that had passed every"
				.. " placement, route and clearance check",
				fired .. " times")
			check(report, targetedClearance == true,
				"and that candidate was one call from being committed",
				tostring(targetedClearance))
			check(report, targeted ~= nil,
				"the race had a validated candidate to move onto", tostring(targeted))
			if check(report, raced, "the creature still spawns despite the race") then
				local after = Controller.GetDebugSnapshot()
				local afterPosition = after.Position
					and Vector3.new(after.Position.X, after.Position.Y, after.Position.Z)
				local afterRoom = afterPosition and roomOf(layout, afterPosition)
				local playerRoom = roomOf(layout, root.Position)
				note(report, string.format(
					"race: validated candidate '%s' in room %s; player moved into room %s;"
					.. " creature committed to '%s' in room %s",
					tostring(targeted), tostring(targetedRoom), tostring(movedInto),
					tostring(after.Spawn and after.Spawn.Anchor), tostring(afterRoom)))
				check(report, afterRoom ~= playerRoom,
					"the live re-check refuses the room the player moved into",
					string.format("both in %s", tostring(afterRoom)))
				check(report, after.Spawn ~= nil and after.Spawn.Anchor ~= targeted,
					"and reselects away from the candidate it had already validated",
					string.format("validated %s, committed %s", tostring(targeted),
						tostring(after.Spawn and after.Spawn.Anchor)))
				check(report, afterPosition ~= nil
					and horizontal(afterPosition, root.Position) >= EXPECTED_FALLBACK_STUDS,
					"the committed spawn is still outside the proximity floor",
					afterPosition and string.format("%.0f studs",
						horizontal(afterPosition, root.Position)) or "no position")
			else
				check(report, false, "the live re-check refuses the room the player moved into",
					"no spawn to check")
				check(report, false, "and reselects away from the candidate it had already validated",
					"no spawn to check")
				check(report, false, "the committed spawn is still outside the proximity floor",
					"no spawn to check")
			end
		end

		-- ------------------------------------------------------------------
		-- Eligibility, read through the controller's real gate.
		-- ------------------------------------------------------------------
		do
			local before = Controller.DebugRankLiveCandidates()
			if check(report, before ~= nil,
				"the live session exposes its real eligibility and ranking") then
				check(report, before.RecordCount == 1,
					"the staged player is counted by the controller's own gate",
					tostring(before.RecordCount))
				local playerRoom = roomOf(layout, root.Position)
				local inPlayerRoom = 0
				for _, candidate in ipairs(before.Candidates) do
					if candidate.HallIndex == playerRoom then inPlayerRoom += 1 end
				end
				check(report, inPlayerRoom == 0,
					"while they are in round, their room is offered to nobody",
					inPlayerRoom .. " candidates were in it")

				player:SetAttribute("InRound", nil)
				task.wait(.3)
				local after = Controller.DebugRankLiveCandidates()
				local records = Controller.DebugEligibleRecords()
				check(report, records ~= nil and #records == 0,
					"dropping out of the round removes the player from the real gate",
					records and tostring(#records) or "nil")
				check(report, after ~= nil and after.RecordCount == 0,
					"and from the ranking's record count",
					after and tostring(after.RecordCount) or "nil")
				check(report, after ~= nil and #after.Candidates > #before.Candidates,
					"a dropped-out player no longer constrains the map",
					after and string.format("%d before, %d after",
						#before.Candidates, #after.Candidates) or "nil")
				local reopened = 0
				for _, candidate in ipairs(after and after.Candidates or {}) do
					if candidate.HallIndex == playerRoom then reopened += 1 end
				end
				check(report, reopened > 0,
					"and the room they were standing in is offered again",
					reopened .. " candidates in it")
			else
				for _ = 1, 6 do
					check(report, false, "eligibility check skipped: no live session")
				end
			end
		end

		-- ------------------------------------------------------------------
		-- Nothing of this test may outlive it.
		-- ------------------------------------------------------------------
		Controller._spawnInterlude = nil
		if suiteSession then
			Controller.Stop(suiteSession)
			suiteSession = nil
		end
		task.wait(.2)
		-- `not IsRunning()` alone passes for a LEAKED PARKED session: a parked one
		-- is not activeSession and answers false here however badly it was left.
		-- The borrowed incumbent must be parked exactly once, and nothing else.
		check(report, not Controller.IsRunning()
			and Controller.DebugParkedCount() == 1
			and Controller.DebugResidue().Active == false,
			"the test's own controller session is stopped, and only the borrowed"
			.. " incumbent is still parked",
			string.format("%d parked", Controller.DebugParkedCount()))
		-- EXACT, against the count taken once the incumbent was parked. `<=` reads
		-- a destroyed incumbent as a clean result.
		check(report, #runtimeFolders(manifest) == runtimeAfterPause,
			"and left no runtime folder or creature model behind",
			string.format("%d runtime folders, %d once the incumbent was parked",
				#runtimeFolders(manifest), runtimeAfterPause))
		-- The `level2State() == nil or` escape passed whenever the state folder had
		-- gone missing, which is a worse outcome than the one being tested for.
		local liveState = level2State()
		check(report, liveState ~= nil
			and liveState:GetAttribute("Level2_SlidemouthActive") ~= true,
			"no creature is left marked active",
			liveState == nil and "the Level 2 state folder is gone" or nil)

		return report
	end)
end

-- ---------------------------------------------------------------------------
-- Ledges
-- ---------------------------------------------------------------------------

local function aabbHalf(part)
	local cframe, size = part.CFrame, part.Size
	return Vector3.new(
		(math.abs(cframe.RightVector.X) * size.X
			+ math.abs(cframe.UpVector.X) * size.Y
			+ math.abs(cframe.LookVector.X) * size.Z) * .5,
		0,
		(math.abs(cframe.RightVector.Z) * size.X
			+ math.abs(cframe.UpVector.Z) * size.Y
			+ math.abs(cframe.LookVector.Z) * size.Z) * .5)
end

local function partTopY(part)
	local cframe, size = part.CFrame, part.Size
	return cframe.Position.Y
		+ math.abs(cframe.RightVector.Y) * size.X * .5
		+ math.abs(cframe.UpVector.Y) * size.Y * .5
		+ math.abs(cframe.LookVector.Y) * size.Z * .5
end

local function makeProbeModel(parent, tuning)
	local model = Instance.new("Model")
	model.Name = "Level 2 Slidemouth Ledge Probe"
	local root = Instance.new("Part")
	root.Name = "Body"
	root.Size = Vector3.new(tuning.AgentRadius * 2, tuning.AgentHeight, tuning.AgentRadius * 2)
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("PoolFoamGroundOffset", tuning.AgentHeight * .5)
	model.Parent = parent
	return model
end

-- A body 16.5 studs across cannot use a 16-stud stair flight with handrails on
-- both sides, and it should not: those are player routes. What it MUST cross is
-- the small authored floor edge on its own routes. So the probe tests
-- controlled ledges at known rises, and authored edges the body can occupy at
-- both ends -- and every refusal has to be explained by real geometry or by a
-- genuinely missing floor, each confirmed here rather than assumed.
function Suite.Ledges(manifest)
	local report = newReport("Slidemouth ledge crossing")
	local tuning = Controller.MovementTuning
	if not check(report, typeof(tuning) == "table",
		"the controller exposes its production movement tuning") then
		return setBranch(report, "no-tuning")
	end

	return protect(report, function(onCleanup)
	local groundParams, groundParts = groundParamsFor(manifest)
	local function groundY(position)
		local hit = workspace:Raycast(position + Vector3.new(0, 40, 0),
			Vector3.new(0, -260, 0), groundParams)
		return hit and hit.Position.Y or nil
	end

	-- Two folders on purpose. The rig models go in the RuntimeFolder, which the
	-- navigator excludes from its own casts. Test GEOMETRY must not: a ledge
	-- parented there is invisible to _clearAdvance, so a "climbs it" result
	-- would prove only that _surfaceAt found the top, never that the body test
	-- tolerated the riser.
	--
	-- Both are registered for cleanup BEFORE anything can throw: a failed suite
	-- must never leave scaffolding in the live world.
	local folder = Instance.new("Folder")
	folder.Name = "Level 2 Slidemouth Probe Rigs"
	folder.Parent = manifest.World
	onCleanup("probe rig folder", function()
		if folder.Parent then folder:Destroy() end
		assert(folder.Parent == nil, "probe rig folder is still in the world")
	end)
	local geometry = Instance.new("Folder")
	geometry.Name = "Level 2 Slidemouth Probe Geometry"
	geometry.Parent = manifest.World
	onCleanup("probe geometry folder", function()
		if geometry.Parent then geometry:Destroy() end
		assert(geometry.Parent == nil, "probe geometry folder is still in the world")
	end)

	local maxRisePerFrame = 0

	local function walk(origin, direction, distance, expectedTopY)
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		if not navigator:WarpTo(origin, direction, true) then
			navigator:Destroy()
			model:Destroy()
			return nil
		end
		local startY = navigator:GetPosition().Y
		local goal = origin + direction * distance
		navigator.Waypoints = {Vector3.new(goal.X, expectedTopY or startY, goal.Z)}
		navigator.WaypointIndex = 1
		navigator.Goal = navigator.Waypoints[1]
		local previousY = startY
		local travelled = 0
		-- The HIGHEST the body ever stood, not just where it happened to end.
		-- A 1.2-stud kerb is crossed and stepped off again inside a single walk,
		-- so a final-height test scores a successful crossing as a failure --
		-- which is exactly why an earlier version of this scan reported three
		-- crossings out of twenty-four on a map the body traverses fine.
		local peakY = startY
		for _ = 1, STEP_FRAMES do
			local before = navigator:GetPosition()
			navigator:Step(PROBE_DELTA, PROBE_SPEED)
			local now = navigator:GetPosition()
			maxRisePerFrame = math.max(maxRisePerFrame, now.Y - previousY)
			peakY = math.max(peakY, now.Y)
			previousY = now.Y
			travelled += horizontal(now, before)
		end
		local result = {
			StartY = startY,
			PeakY = peakY,
			FinalY = navigator:GetPosition().Y,
			Final = navigator:GetPosition(),
			Travelled = travelled,
			Status = navigator:GetStatus(),
			BlockedBy = navigator:GetDebugSnapshot().LastBlockedBy,
		}
		navigator:Destroy()
		model:Destroy()
		return result
	end

	-- ------------------------------------------------------------------
	-- A. controlled ledges
	-- ------------------------------------------------------------------
	local openHall, openFloor, openCenter
	local halls = table.clone(manifest.Layout.Halls)
	table.sort(halls, function(a, b) return (a.Area or 0) > (b.Area or 0) end)
	for _, hall in ipairs(halls) do
		local center = hallCenter(hall)
		local floor = groundY(center)
		if floor and (hall.Width or 0) >= 120 and (hall.Depth or 0) >= 120 then
			local flat = true
			for offset = -40, 40, 8 do
				local sample = groundY(center + Vector3.new(offset, 0, 0))
				if not sample or math.abs(sample - floor) > .12 then flat = false break end
			end
			if flat then
				local clear = walk(Vector3.new(center.X - 40, floor, center.Z),
					Vector3.xAxis, 70, floor)
				if clear and clear.Travelled >= 45 then
					openHall, openFloor, openCenter = hall, floor, center
					break
				end
			end
		end
	end

	if check(report, openHall ~= nil,
		"found an open hall with a clear lane to build controlled ledges in") then
		note(report, string.format("controlled lane: room %d, floor y=%.2f",
			openHall.Index, openFloor))
		local function buildLedge(rise)
			local thickness = rise * 2 + 10
			local ledge = Instance.new("Part")
			ledge.Name = string.format("Probe Ledge %.2f", rise)
			ledge.Anchored = true
			ledge.CanCollide = true
			ledge.Transparency = 1
			ledge.Size = Vector3.new(46, thickness, 46)
			ledge.CFrame = CFrame.new(openCenter.X + 24, openFloor + rise - thickness * .5,
				openCenter.Z)
			ledge:SetAttribute("Level2_EntityGround", true)
			ledge.Parent = geometry
			return ledge
		end
		local start = Vector3.new(openCenter.X - 26, openFloor, openCenter.Z)
		for _, rise in ipairs({0.5, 0.78, 1.6, 2.4, 3.4}) do
			local ledge = buildLedge(rise)
			local result = walk(start, Vector3.xAxis, 60, openFloor + rise)
			ledge:Destroy()
			local gained = result and (result.FinalY - result.StartY) or -1
			check(report, result ~= nil and gained >= rise - .2,
				string.format("climbs a %.2f-stud ledge", rise),
				result and string.format("gained %.2f, %s, blocked by %s", gained,
					result.Status, tostring(result.BlockedBy)) or "could not stand at the start")
			if result then
				check(report, gained <= rise + .3,
					string.format("stops ON the %.2f-stud ledge, does not rise past it", rise),
					string.format("gained %.2f", gained))
			end
		end
		local tooTall = tuning.MaxStepHeight + 1.6
		local ledge = buildLedge(tooTall)
		local result = walk(start, Vector3.xAxis, 60, openFloor + tooTall)
		ledge:Destroy()
		local gained = result and (result.FinalY - result.StartY) or -1
		check(report, result ~= nil and gained < 1,
			string.format("refuses a %.2f-stud wall (above the %.2f step limit)",
				tooTall, tuning.MaxStepHeight),
			result and string.format("gained %.2f", gained) or "no result")
	end

	-- ------------------------------------------------------------------
	-- B. authored edges
	-- ------------------------------------------------------------------
	-- Scan EVERY authored ground part, and try every approach face rather than
	-- stopping at the first that qualifies. An earlier version capped the
	-- candidate list and so only ever saw whichever family of edges happened to
	-- come first in the descendant order -- on some seeds that was one kind of
	-- hall-edge walkway, nearly all of it vault-blocked, which made the sample
	-- look far worse than the map is.
	local found, counts = {}, {}
	local byFamily, families = {}, {}
	for _, part in ipairs(groundParts) do
		local top = partTopY(part)
		local half = aabbHalf(part)
		local onTop = groundY(part.Position)
		if onTop and math.abs(onTop - top) <= .6 then
			for _, direction in ipairs({
				Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis,
			}) do
				local halfAlong = direction.X ~= 0 and half.X or half.Z
				local standOff = tuning.AgentRadius + 3
				local outside = part.Position + direction * (halfAlong + standOff)
				local low = groundY(outside)
				if low and (top - low) >= .4 and (top - low) <= tuning.MaxStepHeight then
					local family = part.Name:gsub("%s*[%d%.]+$", "")
					if not byFamily[family] then
						byFamily[family] = {}
						table.insert(families, family)
					end
					table.insert(byFamily[family], {
						Part = part,
						Family = family,
						Top = top,
						Rise = top - low,
						Start = Vector3.new(outside.X, low, outside.Z),
						Direction = -direction,
						Distance = standOff + math.min(halfAlong, tuning.AgentRadius + 4)
							+ tuning.AgentRadius,
						-- How far along the approach the body has to get before
						-- the authored edge is behind it: past the near face, and
						-- either across the whole part or a body-radius onto it.
						RequiredProgress = standOff
							+ math.min(halfAlong * 2, tuning.AgentRadius),
					})
				end
			end
		end
	end
	-- Round-robin across families so no single kind of edge can dominate.
	table.sort(families)
	local probes = {}
	local cursor, exhausted = 1, false
	while not exhausted do
		exhausted = true
		for _, family in ipairs(families) do
			local entry = byFamily[family][cursor]
			if entry then
				table.insert(probes, entry)
				exhausted = false
			end
		end
		cursor += 1
	end
	local skipped = 0

	local function genuinelyObstructed(foot)
		local height = tuning.AgentHeight - .3
		local size = Vector3.new(tuning.AgentRadius * 2 - .2, height, tuning.AgentRadius * 2 - .2)
		local box = Instance.new("Part")
		box.Size = size
		box.CFrame = CFrame.new(foot + Vector3.new(0, height * .5 + .18, 0))
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.Transparency = 1
		box.Parent = folder
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {folder}
		params.RespectCanCollide = true
		params.MaxParts = 64
		local touching = workspace:GetPartsInPart(box, params)
		box:Destroy()
		for _, part in ipairs(touching) do
			if part.CanCollide then
				local steppable = part:GetAttribute("Level2_EntityGround") == true
					and part:GetAttribute("Level2_NoEntityGround") ~= true
					and partTopY(part) <= foot.Y + tuning.MaxStepHeight + .05
				if not steppable then return true, part.Name end
			end
		end
		return false, nil
	end

	-- A NO_FLOOR refusal is only correct if this suite cannot find reachable
	-- ground there either. Believing the navigator would make the whole probe
	-- self-confirming.
	local function genuinelyNoFloor(fromFoot, direction)
		for _, ahead in ipairs({.6, 1.2, 2.0}) do
			local sample = fromFoot + direction * ahead
			local surface = groundY(sample)
			if surface and math.abs(surface - fromFoot.Y) <= tuning.MaxStepHeight + .1 then
				return false, string.format("ground at y=%.2f, %.1f studs ahead", surface, ahead)
			end
		end
		return true, nil
	end

	-- ------------------------------------------------------------------
	-- The INDEPENDENT oracle.
	-- ------------------------------------------------------------------
	-- genuinelyObstructed and genuinelyNoFloor above both decide steppability
	-- the way the navigator's own _isSteppable does -- Level2_EntityGround set,
	-- Level2_NoEntityGround clear, top within MaxStepHeight. That makes them
	-- excellent at explaining a refusal and useless at catching a WRONG TAG: the
	-- production code and the expectation move together, and a curb tagged
	-- NoEntityGround is refused by the navigator and pronounced correct here.
	--
	-- This predicts the outcome from MEASURED GEOMETRY instead. No attribute is
	-- read for the decision: the floor is found with a plain collidable ray, the
	-- rise is the difference between two such rays, and an obstruction is
	-- anything whose measured TOP stands more than a step above the landing.
	-- Height, not tags. A disagreement between this and what the rig did is
	-- therefore a real disagreement about the world.
	-- A floor reading with NO tag in it, and deliberately SHORT.
	--
	-- The tagged groundY above starts 40 studs up and casts 260 down, which is
	-- safe only because its Include filter can hit nothing but ground. An
	-- untagged ray cast from up there would hit the HALL CEILING and report it as
	-- the floor, poisoning every measurement this oracle makes. So the caller
	-- supplies an origin just above the surface it expects and a depth that
	-- reaches just below the one it is measuring from -- never far enough to
	-- reach a ceiling above or a foundation below.
	local function rawGroundY(origin, depth)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {folder, geometry}
		params.IgnoreWater = true
		params.RespectCanCollide = true
		local hit = workspace:Raycast(origin, Vector3.new(0, -math.max(1, depth or 8), 0), params)
		return hit and hit.Position.Y or nil
	end

	-- The tallest thing standing inside a body-sized volume at `foot`, as a
	-- height ABOVE that foot. Nothing here reads an attribute: a part is judged
	-- by where its top is, which is the whole point.
	local function overheadAt(foot)
		local height = math.max(2, tuning.AgentHeight - .3)
		local width = math.max(1, tuning.AgentRadius * 2 - .2)
		local box = Instance.new("Part")
		box.Size = Vector3.new(width, height, width)
		box.CFrame = CFrame.new(foot + Vector3.new(0, height * .5 + .18, 0))
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.Transparency = 1
		box.Parent = folder
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {folder, geometry}
		params.RespectCanCollide = true
		params.MaxParts = 64
		local touching = workspace:GetPartsInPart(box, params)
		box:Destroy()
		local tallest, culprit = -math.huge, nil
		for _, part in ipairs(touching) do
			if part.CanCollide then
				local top = partTopY(part)
				if top > tallest then tallest, culprit = top, part.Name end
			end
		end
		return tallest - foot.Y, culprit, width
	end

	-- "must", "must not", or "either" -- plus the measurement that decided it.
	--
	-- The approach is sampled at more than its far end. A landing that is clear
	-- says nothing about the near face of the ledge the body has to get over
	-- first, and predicting "must cross" from the landing alone would blame the
	-- navigator for geometry standing halfway along.
	local function oracleVerdict(probe)
		-- probe.Start already sits ON the low ground, so 1.5 up and 6 down brackets
		-- it without room to reach anything else.
		local lowY = rawGroundY(probe.Start + Vector3.new(0, 1.5, 0), 6)
		if not lowY then return "either", "no measurable floor to start from" end
		-- From 1.5 above the edge's own top down to 4 below the low floor: the
		-- whole band the crossing can possibly land in, and nothing outside it.
		local sampleTop = probe.Top + 1.5
		local sampleDepth = math.max(6, sampleTop - (lowY - 4))
		local worstOverhead, worstCulprit, bodyWidth = -math.huge, nil, 0
		local rise
		for _, fraction in ipairs({.6, 1}) do
			local flat = probe.Start + probe.Direction * (probe.RequiredProgress * fraction)
			local surfaceY = rawGroundY(Vector3.new(flat.X, sampleTop, flat.Z), sampleDepth)
			if not surfaceY then
				return "must not", string.format(
					"no measurable floor %.0f%% of the way across the edge", fraction * 100)
			end
			local step = surfaceY - lowY
			if fraction == 1 then rise = step end
			if step > tuning.MaxStepHeight + LEDGE_ORACLE_MARGIN then
				return "must not", string.format(
					"measured rise %.2f at %.0f%% is above the %.2f step limit",
					step, fraction * 100, tuning.MaxStepHeight)
			end
			local overhead, culprit, width = overheadAt(Vector3.new(flat.X, surfaceY, flat.Z))
			bodyWidth = width
			if overhead > worstOverhead then worstOverhead, worstCulprit = overhead, culprit end
		end
		if worstOverhead > tuning.MaxStepHeight + LEDGE_ORACLE_MARGIN then
			-- A centre-line body box proves that this exact line is blocked, not
			-- that the whole authored edge is. Production locomotion is allowed to
			-- steer laterally by one AgentRadius, and the crossing assertion accepts
			-- the same bounded sidestep. Calling this MUST-NOT made two legitimate
			-- routes around a vault strip disagree with an oracle that never checked
			-- the available lateral lane.
			return "either", string.format(
				"centre line touches '%s' %.2f above the approach; a bounded lateral"
				.. " route may still pass",
				tostring(worstCulprit), worstOverhead)
		end
		if rise ~= nil and rise <= tuning.MaxStepHeight - LEDGE_ORACLE_MARGIN
			and worstOverhead <= tuning.MaxStepHeight - LEDGE_ORACLE_MARGIN then
			return "must", string.format(
				"measured rise %.2f, nothing above %.2f anywhere in a %.1f-wide body"
				.. " volume along the approach", rise, math.max(worstOverhead, 0), bodyWidth)
		end
		return "either", string.format("rise %s, tallest %.2f -- inside the %.2f dead band",
			tostring(rise and string.format("%.2f", rise) or "?"), worstOverhead,
			LEDGE_ORACLE_MARGIN)
	end

	local function stepAgainFrom(position, direction)
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		local outcome = {Placed = false}
		if navigator:WarpTo(position, direction, true) then
			outcome.Placed = true
			outcome.From = navigator:GetPosition()
			local target = navigator:GetPosition() + direction * .6
			outcome.Advanced = navigator:_placeFoot(target, direction)
			outcome.BlockedBy = navigator.LastBlockedBy
			outcome.Status = navigator:GetStatus()
			local surface = navigator:_surfaceAt(target, false)
			outcome.Foot = surface and Vector3.new(target.X, surface + .08, target.Z) or nil
		end
		navigator:Destroy()
		model:Destroy()
		return outcome
	end

	-- Did the body get past the authored edge? Measured as progress ALONG the
	-- approach, with the sideways drift bounded so walking around the edge
	-- cannot be mistaken for crossing it, plus the requirement that the body
	-- really did stand at the edge's height at some point on the way.
	local function crossedEdge(probe, result)
		if not result then return false, 0, 0 end
		local delta = result.Final - probe.Start
		local flat = Vector3.new(delta.X, 0, delta.Z)
		local progress = flat:Dot(probe.Direction)
		local lateral = (flat - probe.Direction * progress).Magnitude
		local gained = result.PeakY - result.StartY
		return progress >= probe.RequiredProgress
			and lateral <= tuning.AgentRadius
			and gained >= probe.Rise - .35, progress, lateral
	end

	-- Walk the probe, and if it has not cleared the edge but is STILL moving
	-- freely when the frame budget runs out, give it another budget from where
	-- it stopped. A rig that ran out of frames has measured nothing about the
	-- edge, and counting that as an unresolved result is what let a scan of 24
	-- probes pass on three crossings.
	local function walkToTheEdge(probe)
		local result = walk(probe.Start, probe.Direction, probe.Distance, probe.Top)
		local extensions = 0
		while result and extensions < STEP_EXTENSIONS do
			if crossedEdge(probe, result) then break end
			local again = stepAgainFrom(result.Final, probe.Direction)
			if not again.Advanced then break end
			local covered = horizontal(result.Final, probe.Start)
			local remaining = math.max(4, probe.Distance - covered)
			local extended = walk(result.Final, probe.Direction, remaining, probe.Top)
			if not extended then break end
			-- Height and progress are always measured from the ORIGINAL foot.
			extended.StartY = result.StartY
			extended.PeakY = math.max(extended.PeakY, result.PeakY)
			extended.Travelled += result.Travelled
			result = extended
			extensions += 1
		end
		return result, extensions
	end

	local crossed, blocked, refused, unexplained, notReached, oldWouldBlock = 0, 0, 0, 0, 0, 0
	local extendedProbes = 0
	local failures = {}
	local attempted = 0
	local standableUnprobed = 0
	local geometryRejected = 0
	-- Per authored family: how many were walked, how many the oracle says MUST be
	-- crossed, and how many actually were. A family that contains a
	-- geometrically-must-cross edge and crossed none of them is a failure named
	-- by family, not a number folded into a total.
	local familyAttempts, familyMustCross, familyCrossed = {}, {}, {}
	local familySeen = {}
	local oracleMust, oracleMustNot, oracleEither = 0, 0, 0
	local oracleCrossWrong, oracleRefuseWrong = 0, 0
	for index = 1, #probes do
		local probe = probes[index]
		local target = probe.Start + probe.Direction * probe.Distance
		-- A low edge is only a candidate for the *navigator* occupancy ratio when
		-- an independent collidable body-volume measurement says the rig can stand
		-- at both ends.  The raw authored-edge scan intentionally sees wall backs,
		-- vault faces and decorative slivers too; charging those known-solid volumes
		-- as navigator "skips" made the ratio describe the breadth of the scan, not
		-- whether WarpTo refused usable geometry.  We still scan every face, report
		-- every measured rejection, and keep the ratio strict for the surfaces that
		-- geometry says are actually occupiable.
		local startOverhead = select(1, overheadAt(probe.Start))
		local targetOverhead = select(1, overheadAt(
			Vector3.new(target.X, probe.Top, target.Z)))
		local geometryStandable = startOverhead <= tuning.MaxStepHeight + LEDGE_ORACLE_MARGIN
			and targetOverhead <= tuning.MaxStepHeight + LEDGE_ORACLE_MARGIN
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		local standable = navigator:WarpTo(probe.Start, probe.Direction, true)
		if standable then
			standable = navigator:WarpTo(
				Vector3.new(target.X, probe.Top, target.Z), probe.Direction, true)
		end
		navigator:Destroy()
		model:Destroy()
		if not geometryStandable then
			geometryRejected += 1
		elseif not standable then
			skipped += 1
		elseif attempted >= LEDGE_SAMPLE then
			-- Keep scanning the full candidate pool even after the walking sample is
			-- full. Stopping on the 24th occupiable edge made the skip ratio depend on
			-- round-robin order and ignored every later standable candidate.
			standableUnprobed += 1
		else
			attempted += 1
			local label = probe.Part.Name:gsub("%s*[%d%.]+$", "")
			counts[label] = (counts[label] or 0) + 1
			local family = probe.Family or label
			if not familySeen[family] then
				familySeen[family] = true
				familyAttempts[family] = 0
				familyMustCross[family] = 0
				familyCrossed[family] = 0
			end
			familyAttempts[family] += 1
			if probe.Part.Position.Y > probe.Start.Y then oldWouldBlock += 1 end
			local verdict, evidence = oracleVerdict(probe)
			if verdict == "must" then
				oracleMust += 1
				familyMustCross[family] += 1
			elseif verdict == "must not" then
				oracleMustNot += 1
			else
				oracleEither += 1
			end
			local result, extensions = walkToTheEdge(probe)
			if extensions > 0 then extendedProbes += 1 end
			local cleared, progress, lateral = crossedEdge(probe, result)
			local gained = result and (result.PeakY - result.StartY) or -1
			-- The independent comparison. Neither side of it consulted a tag.
			if verdict == "must" and not cleared then
				oracleCrossWrong += 1
				if #failures < 10 then
					table.insert(failures, string.format(
						"ORACLE '%s': geometry says it MUST be crossable (%s) and the rig did not",
						probe.Part.Name, evidence))
				end
			elseif verdict == "must not" and cleared then
				oracleRefuseWrong += 1
				if #failures < 10 then
					table.insert(failures, string.format(
						"ORACLE '%s': geometry says it must NOT be crossable (%s) and the rig crossed it",
						probe.Part.Name, evidence))
				end
			end
			if cleared then
				crossed += 1
				familyCrossed[family] += 1
			elseif result then
				blocked += 1
				local again = stepAgainFrom(result.Final, probe.Direction)
				if again.Advanced then
					notReached += 1
					if #failures < 10 then
						table.insert(failures, string.format(
							"NOT REACHED '%s' (rise %.2f): %.1f/%.1f studs of progress,"
							.. " %.1f sideways, peak gain %.2f, still moving after %d extra budgets",
							probe.Part.Name, probe.Rise, progress, probe.RequiredProgress,
							lateral, gained, extensions))
					end
				elseif again.Foot then
					local obstructed, culprit = genuinelyObstructed(again.Foot)
					if obstructed then
						refused += 1
						if #failures < 10 then
							table.insert(failures, string.format(
								"correctly refused '%s' (rise %.2f): '%s' occupies the body",
								probe.Part.Name, probe.Rise, tostring(culprit)))
						end
					else
						unexplained += 1
						if #failures < 10 then
							table.insert(failures, string.format(
								"UNEXPLAINED '%s' rise %.2f -> gained %.2f, %s, blocked by %s",
								probe.Part.Name, probe.Rise, gained, again.Status,
								tostring(again.BlockedBy)))
						end
					end
				else
					local reallyNone, evidence = genuinelyNoFloor(
						again.From or result.Final, probe.Direction)
					if reallyNone then
						refused += 1
						if #failures < 10 then
							table.insert(failures, string.format(
								"correctly refused '%s' (rise %.2f): no floor ahead, confirmed",
								probe.Part.Name, probe.Rise))
						end
					else
						unexplained += 1
						if #failures < 10 then
							table.insert(failures, string.format(
								"UNEXPLAINED NO_FLOOR '%s' rise %.2f -- %s",
								probe.Part.Name, probe.Rise, tostring(evidence)))
						end
					end
				end
			else
				blocked += 1
				notReached += 1
				if #failures < 10 then
					table.insert(failures, string.format(
						"NOT REACHED '%s' (rise %.2f): the rig could not stand to walk at all",
						probe.Part.Name, probe.Rise))
				end
			end
		end
	end

	local labels = {}
	for label, count in pairs(counts) do
		table.insert(labels, string.format("%s x%d", label, count))
	end
	table.sort(labels)
	note(report, string.format("authored edges: %d found, %d independently rejected by"
		.. " collidable body geometry, %d navigator skips, %d probed, %d more"
		.. " confirmed standable",
		#probes, geometryRejected, skipped, attempted, standableUnprobed))
	if #labels > 0 then note(report, "  " .. table.concat(labels, ", ")) end
	note(report, string.format(
		"crossed %d; verified refusals %d; never reached %d; unexplained %d; of %d attempted (%d needed extra frames)",
		crossed, refused, notReached, unexplained, attempted, extendedProbes))
	note(report, string.format("%d of the %d probed sit on a part whose centre is above the"
		.. " approach foot -- the edges the previous obstruction test rejected outright",
		oldWouldBlock, attempted))
	note(report, string.format("largest single-frame rise %.3f studs (step limit %.2f)",
		maxRisePerFrame, tuning.MaxStepHeight))
	for _, line in ipairs(failures) do note(report, line) end

	check(report, attempted >= 6, "enough authored edges were occupiable to be worth probing",
		attempted .. " probed")
	-- The accounting identity. Every attempted probe has exactly one outcome, so
	-- a scan that "passes" while most of its probes never resolved is now a
	-- failure rather than a footnote.
	check(report, crossed + refused + notReached + unexplained == attempted,
		"every attempted probe is accounted for exactly once",
		string.format("%d + %d + %d + %d ~= %d", crossed, refused, notReached,
			unexplained, attempted))
	check(report, crossed + refused == attempted,
		"every attempted authored edge is either crossed or refused for confirmed geometry",
		string.format("%d crossed + %d verified refusals = %d of %d attempted"
			.. " (%d never reached, %d unexplained)",
			crossed, refused, crossed + refused, attempted, notReached, unexplained))
	check(report, unexplained == 0,
		"no refusal is left unexplained",
		string.format("%d unexplained", unexplained))
	check(report, notReached == 0,
		"no probe ran out of frames before reaching its edge",
		string.format("%d never reached", notReached))
	-- Without this the suite would pass just as happily if the rig crossed
	-- nothing at all and every failure were explained away.
	check(report, crossed >= 3,
		"a meaningful number of authored edges were actually crossed",
		string.format("%d crossed of %d probed", crossed, attempted))
	check(report, oldWouldBlock > 0,
		"the probe includes edges the previous obstruction test rejected outright",
		"none found -- the probe would be vacuous")
	check(report, maxRisePerFrame <= tuning.MaxStepHeight + .2,
		"no single frame exceeded the step height",
		string.format("%.3f", maxRisePerFrame))

	-- ------------------------------------------------------------------
	-- Per family, ratios, and the independent oracle.
	-- ------------------------------------------------------------------
	-- Three crossings across the whole map was the entire success bar, and one
	-- family could supply all three. These require a crossing FROM EACH FAMILY
	-- that contains an edge the measured geometry says must be crossable -- a
	-- family whose every candidate really is a wall is exempt, correctly, and by
	-- measurement rather than by being quietly skipped.
	local familyLines, familyStarved, familyCount = {}, {}, 0
	for family in pairs(familySeen) do
		familyCount += 1
		table.insert(familyLines, string.format("%s %d/%d crossed, %d must",
			family, familyCrossed[family], familyAttempts[family], familyMustCross[family]))
		if familyMustCross[family] > 0
			and familyCrossed[family] < LEDGE_FAMILY_MIN_CROSSINGS then
			table.insert(familyStarved, string.format("%s (%d must-cross, %d crossed)",
				family, familyMustCross[family], familyCrossed[family]))
		end
	end
	table.sort(familyLines)
	note(report, "per family: " .. table.concat(familyLines, "; "))
	note(report, string.format("independent oracle: %d must cross, %d must not, %d inside"
		.. " the %.2f-stud dead band; %d disagreements crossing, %d refusing",
		oracleMust, oracleMustNot, oracleEither, LEDGE_ORACLE_MARGIN,
		oracleCrossWrong, oracleRefuseWrong))

	check(report, #familyStarved == 0,
		string.format("every authored family holding an edge the measured geometry says"
			.. " MUST be crossable crossed at least %d of them", LEDGE_FAMILY_MIN_CROSSINGS),
		table.concat(familyStarved, ", "))
	check(report, familyCount >= LEDGE_MIN_FAMILIES,
		string.format("the sample spans at least %d distinct authored families, so no single"
			.. " kind of edge can carry the whole result", LEDGE_MIN_FAMILIES),
		string.format("%d families", familyCount))
	-- Only independently body-clear candidates belong in this ratio. A navigator
	-- skip still carries its full cost; geometry that a separate collidable-volume
	-- probe already proved solid is evidence, not a silent/non-costed skip.
	local examined = attempted + skipped + standableUnprobed
	check(report, skipped <= math.floor(examined * LEDGE_MAX_SKIP_RATIO),
		"skipped candidates stayed under their ratio cap -- a scan that could not stand"
		.. " up on most of what it found has measured nothing",
		string.format("%d skipped of %d examined, cap %d", skipped, examined,
			math.floor(examined * LEDGE_MAX_SKIP_RATIO)))
	check(report, refused <= math.floor(attempted * LEDGE_MAX_REFUSAL_RATIO),
		"and refusals stayed under theirs -- an explained refusal is still a refusal,"
		.. " and a rig that refuses nearly everything has not been shown to walk",
		string.format("%d refused of %d attempted, cap %d", refused, attempted,
			math.floor(attempted * LEDGE_MAX_REFUSAL_RATIO)))
	check(report, oracleCrossWrong == 0 and oracleRefuseWrong == 0,
		"the independently measured geometry and the rig agree on every edge the oracle"
		.. " will commit to -- no tag decided both sides of this",
		string.format("%d it should have crossed and did not, %d it should have refused"
			.. " and crossed", oracleCrossWrong, oracleRefuseWrong))
	check(report, oracleMust > 0 and oracleMustNot + oracleMust >= 2,
		"and the oracle committed to enough edges to be worth comparing against",
		string.format("%d must, %d must not, %d undecided", oracleMust, oracleMustNot,
			oracleEither))

	return report
	end)
end


-- ---------------------------------------------------------------------------
-- Substep -- the mid-stride floor resolve, at the FASTEST production stride
-- ---------------------------------------------------------------------------
--
-- Traversal above walks the real map at PUMP_TWO_SPEED. This walks two
-- CONSTRUCTED lanes at PUMP_THREE_SPEED -- 36 studs/s against the controller's
-- own math.min(dt, .1) clamp, so the stride under test is 3.6 studs, the
-- longest single Step the shipped game ever asks for.
--
-- WHAT SHIPPED BROKEN: Step advanced the whole stride in ONE _placeFoot and
-- validated only where it landed. Everything crossed on the way was assumed.
-- _clearAdvance's horizontal Blockcast is not a substitute -- its box bottom
-- sits at max(startY, endY) + .18 and it deliberately casts PAST step-height
-- entity ground -- so it is blind to exactly the two things a floor can do
-- mid-stride: rise, and stop existing.
--
-- Both lanes are built so that a 3.6-stud stride STRADDLES the feature (its
-- endpoints land 0.8 studs clear on either side) while the .9-stud substeps
-- cannot: any interval 2.0 studs wide contains a multiple of .9. The feature is
-- therefore invisible to one unvalidated leap and unmissable to the loop, which
-- is the entire difference between the two.
--
--   A. RISE -- a 2.0-stud-wide strip of entity ground standing 1.2 studs proud
--      of a flat floor. Production must STAND on it. A single-stride walk sails
--      over it at floor height, never having sampled it: the "glided over edges
--      it should have had to climb" report.
--
--   B. NO FLOOR -- two raised slabs with a 2.0-stud trench between them, six
--      studs above the authored floor so the gap resolves to a drop far beyond
--      MaxStepHeight. Production must REFUSE to cross. A single-stride walk
--      crosses it -- walking on air.
--
-- The mutant is not a paraphrase of the navigator: it calls the very same
-- _placeFoot, off the very same navigator, with the very same stride. The ONLY
-- thing removed is the loop. If the loop is ever deleted from the shipped
-- module, production and mutant converge and four checks here go red.
--
-- Nothing here uses PathfindingService: Goal is left nil and the waypoint list
-- is written directly, so the lane is hermetic and the result cannot turn on
-- whether a navmesh happened to bake.
local SUBSTEP_FEATURE_WIDTH = 2.0
local SUBSTEP_LANE_LENGTH = 24
local SUBSTEP_TRENCH_LIFT = 6
local SUBSTEP_RISE = 1.2
local SUBSTEP_FRAMES = 20

function Suite.Substep(manifest)
	local report = newReport("Slidemouth substep floor resolve (production stride)")
	local tuning = Controller.MovementTuning
	if not check(report, typeof(tuning) == "table",
		"the controller exposes its production movement tuning") then
		return setBranch(report, "no-tuning")
	end
	local speeds = Controller.ChaseSpeeds
	if not check(report, typeof(speeds) == "table"
		and typeof(speeds.PumpThree) == "number"
		and typeof(speeds.MaxStepDelta) == "number",
		"and the chase speeds it drives the navigator with, so this suite walks the"
		.. " production stride instead of a number copied out of it") then
		return setBranch(report, "no-speeds")
	end

	return protect(report, function(onCleanup)
	local speed = speeds.PumpThree
	local delta = speeds.MaxStepDelta
	local stride = speed * delta
	local pieces = math.ceil(stride / tuning.MaxTravelStep)

	-- The lane geometry only means anything if these numbers hold. A retuning
	-- that breaks the straddle makes this suite prove nothing, so it fails HERE
	-- rather than quietly measuring an easier case.
	check(report,
		SUBSTEP_FEATURE_WIDTH > tuning.MaxTravelStep
			and SUBSTEP_FEATURE_WIDTH < stride - 1
			and pieces > 1 and pieces <= EXPECTED_MAX_TRAVEL_SUBSTEPS,
		string.format("the %.1f-stud feature is wider than one %.2f-stud substep and"
			.. " narrower than the %.1f-stud production stride, so only the loop can"
			.. " see it", SUBSTEP_FEATURE_WIDTH, tuning.MaxTravelStep, stride),
		string.format("stride %.2f = %d pieces of %.2f", stride, pieces,
			tuning.MaxTravelStep))

	local groundParams = groundParamsFor(manifest)
	local function groundY(position)
		local hit = workspace:Raycast(position + Vector3.new(0, 40, 0),
			Vector3.new(0, -260, 0), groundParams)
		return hit and hit.Position.Y or nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "Level 2 Slidemouth Substep Rigs"
	folder.Parent = manifest.World
	onCleanup("substep rig folder", function()
		if folder.Parent then folder:Destroy() end
		assert(folder.Parent == nil, "substep rig folder is still in the world")
	end)
	local geometry = Instance.new("Folder")
	geometry.Name = "Level 2 Slidemouth Substep Geometry"
	geometry.Parent = manifest.World
	onCleanup("substep geometry folder", function()
		if geometry.Parent then geometry:Destroy() end
		assert(geometry.Parent == nil, "substep geometry folder is still in the world")
	end)

	-- A flat, open, unobstructed lane. Flatness is sampled along the whole run,
	-- and the headroom test reaches above the raised slabs so lane B cannot be
	-- built inside a vault or a light fitting.
	local lane, laneFloor
	local halls = table.clone(manifest.Layout.Halls)
	table.sort(halls, function(a, b) return (a.Area or 0) > (b.Area or 0) end)
	local clearParams = RaycastParams.new()
	clearParams.FilterType = Enum.RaycastFilterType.Exclude
	clearParams.FilterDescendantsInstances = {folder, geometry}
	clearParams.IgnoreWater = true
	clearParams.RespectCanCollide = true
	for _, hall in ipairs(halls) do
		local center = hallCenter(hall)
		local floor = groundY(center)
		if floor and (hall.Width or 0) >= 120 and (hall.Depth or 0) >= 120 then
			local ok = true
			for offset = -14, SUBSTEP_LANE_LENGTH + 14, 3 do
				local x = center.X - SUBSTEP_LANE_LENGTH * .5 + offset
				local sample = groundY(Vector3.new(x, floor, center.Z))
				if not sample or math.abs(sample - floor) > .12 then ok = false break end
				-- Headroom from just above the floor to well past the raised
				-- slabs, across the body's width, so nothing overhangs the lane.
				for _, sideways in ipairs({-tuning.AgentRadius, 0, tuning.AgentRadius}) do
					local origin = Vector3.new(x, floor + .4, center.Z + sideways)
					if workspace:Raycast(origin,
						Vector3.new(0, SUBSTEP_TRENCH_LIFT + tuning.AgentHeight + 4, 0),
						clearParams) then ok = false break end
				end
				if not ok then break end
			end
			if ok then lane, laneFloor = center, floor break end
		end
	end

	if not check(report, lane ~= nil,
		"found a flat open lane with clear headroom to build the two probe lanes in") then
		return setBranch(report, "no-lane")
	end
	note(report, string.format("lane at (%.0f, %.2f, %.0f); stride %.2f studs ="
		.. " %d x %.2f", lane.X, laneFloor, lane.Z, stride, pieces, tuning.MaxTravelStep))

	local startX = lane.X - SUBSTEP_LANE_LENGTH * .5
	-- Dead centre of the third stride, so the straddling endpoints -- two and
	-- three strides from the start -- sit clear of both faces.
	local featureCenterX = startX + stride * 2.5

	local function newRig()
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		return model, navigator
	end

	-- One Step of the PRE-REWRITE navigator: the waypoint bookkeeping and the
	-- travel arithmetic verbatim from Navigator:Step, then ONE _placeFoot for the
	-- whole stride. Same navigator, same tuning, same floor and body validation.
	-- The loop is the only thing missing.
	local function singleStrideStep(navigator, deltaTime, speedValue)
		local waypoint = navigator.Waypoints[navigator.WaypointIndex]
		while waypoint do
			local difference = Vector3.new(waypoint.X - navigator.FootPosition.X, 0,
				waypoint.Z - navigator.FootPosition.Z)
			if difference.Magnitude > navigator.Tuning.WaypointArrivalDistance then break end
			navigator.WaypointIndex += 1
			waypoint = navigator.Waypoints[navigator.WaypointIndex]
		end
		if not waypoint then return end
		local current = navigator.FootPosition
		local difference = Vector3.new(waypoint.X - current.X, 0, waypoint.Z - current.Z)
		local distance = difference.Magnitude
		if distance <= 0 then return end
		local direction = difference.Unit
		local travel = math.min(distance, speedValue * deltaTime)
		navigator:_placeFoot(current + direction * travel, direction)
	end

	-- Walks a rig from `origin` along +X, either through the shipped Step or
	-- through the mutant, and reports what the foot actually did. `Goal` is
	-- deliberately left nil: with no goal there is no repath, so nothing here can
	-- reach PathfindingService.
	local function walk(origin, mutant)
		local model, navigator = newRig()
		if not navigator:WarpTo(origin, Vector3.xAxis, true) then
			navigator:Destroy()
			model:Destroy()
			return nil
		end
		local start = navigator:GetPosition()
		navigator.Waypoints = {Vector3.new(origin.X + SUBSTEP_LANE_LENGTH, start.Y, origin.Z)}
		navigator.WaypointIndex = 1
		navigator.Goal = nil
		local worstStep, clamped = 0, false
		for _ = 1, SUBSTEP_FRAMES do
			local before = navigator:GetPosition()
			if mutant then
				singleStrideStep(navigator, delta, speed)
			else
				navigator:Step(delta, speed)
			end
			local now = navigator:GetPosition()
			worstStep = math.max(worstStep, horizontal(now, before))
			if navigator.TravelClamped == true then clamped = true end
		end
		-- The height is read off the navigator's own TRAIL, not off a sample
		-- taken between Steps.
		--
		-- WHAT THIS SUITE GOT WRONG FIRST: a 2.0-stud rise is climbed and
		-- stepped off again INSIDE one 3.6-stud stride -- up at +8.1, +9.0,
		-- +9.9 and back down at +10.8 -- so a reading taken after each Step sees
		-- floor height throughout and scores the climb as a miss. It reported
		-- the shipped navigator broken for a fault that was in the measurement.
		--
		-- _recordTrail is called by _placeFoot on every SUCCESSFUL placement and
		-- keeps anything more than .6 studs from the last one, so at .9-stud
		-- substeps it holds every validated position -- which is exactly the
		-- record of what the rig actually stood on. The spacing between
		-- consecutive entries is therefore a DIRECT reading of the substep
		-- granularity: .9 with the loop, a full stride without it.
		local peakY, trailGap, previous = start.Y, 0, nil
		for _, foot in ipairs(navigator.Trail) do
			peakY = math.max(peakY, foot.Y)
			if previous then trailGap = math.max(trailGap, horizontal(foot, previous)) end
			previous = foot
		end
		local final = navigator:GetPosition()
		local result = {
			StartX = start.X,
			StartY = start.Y,
			FinalX = final.X,
			PeakY = peakY,
			TrailGap = trailGap,
			TrailCount = #navigator.Trail,
			Advanced = final.X - start.X,
			WorstStep = worstStep,
			Clamped = clamped,
			Status = navigator:GetStatus(),
			BlockedBy = navigator:GetDebugSnapshot().LastBlockedBy,
		}
		navigator:Destroy()
		model:Destroy()
		return result
	end

	-- ------------------------------------------------------------------
	-- A. a 1.2-stud rise, 2.0 studs wide
	-- ------------------------------------------------------------------
	local riseThickness = SUBSTEP_RISE * 2 + 10
	local strip = Instance.new("Part")
	strip.Name = "Substep Probe Rise"
	strip.Anchored = true
	strip.CanCollide = true
	strip.Transparency = 1
	strip.Size = Vector3.new(SUBSTEP_FEATURE_WIDTH, riseThickness, 52)
	strip.CFrame = CFrame.new(featureCenterX,
		laneFloor + SUBSTEP_RISE - riseThickness * .5, lane.Z)
	strip:SetAttribute("Level2_EntityGround", true)
	strip.Parent = geometry

	local riseOrigin = Vector3.new(startX, laneFloor, lane.Z)
	local riseLive = walk(riseOrigin, false)
	local riseMutant = walk(riseOrigin, true)
	strip:Destroy()

	if check(report, riseLive ~= nil and riseMutant ~= nil,
		"both rigs could stand at the start of the rise lane",
		string.format("production %s, mutant %s", tostring(riseLive ~= nil),
			tostring(riseMutant ~= nil))) then
		local liveGain = riseLive.PeakY - riseLive.StartY
		local mutantGain = riseMutant.PeakY - riseMutant.StartY
		note(report, string.format("rise lane: production peaked +%.2f over %d"
			.. " validated placements at most %.2f studs apart, advancing %.2f (worst"
			.. " Step %.2f); single-stride mutant peaked +%.2f over %d placements up to"
			.. " %.2f apart, advancing %.2f", liveGain, riseLive.TrailCount,
			riseLive.TrailGap, riseLive.Advanced, riseLive.WorstStep, mutantGain,
			riseMutant.TrailCount, riseMutant.TrailGap, riseMutant.Advanced))
		check(report, riseLive.TrailGap <= tuning.MaxTravelStep + .05
			and riseMutant.TrailGap >= stride - .05,
			string.format("the shipped Step validated the floor every %.2f studs across"
				.. " a %.1f-stud stride, where the mutant validated it once per stride",
				tuning.MaxTravelStep, stride),
			string.format("production worst gap %.3f (bound %.2f), mutant worst gap %.3f",
				riseLive.TrailGap, tuning.MaxTravelStep, riseMutant.TrailGap))
		check(report, liveGain >= SUBSTEP_RISE - .2,
			string.format("production STOOD on the %.1f-stud rise -- the loop resolved"
				.. " the floor in the middle of a %.1f-stud stride", SUBSTEP_RISE, stride),
			string.format("gained %.2f, %s", liveGain, riseLive.Status))
		check(report,
			riseLive.Advanced >= SUBSTEP_LANE_LENGTH - tuning.WaypointArrivalDistance - 1,
			"and still walked the lane end to end -- climbing it is not the same as"
			.. " being stopped by it",
			string.format("advanced %.2f of %.1f", riseLive.Advanced, SUBSTEP_LANE_LENGTH))
		check(report, mutantGain < SUBSTEP_RISE * .5
			and riseMutant.Advanced >= SUBSTEP_LANE_LENGTH - tuning.WaypointArrivalDistance - 1,
			"MUTATION CAUGHT: with the loop removed the same navigator sails the same"
			.. " lane at floor height, never having sampled the rise at all",
			string.format("mutant gained %.2f and advanced %.2f", mutantGain,
				riseMutant.Advanced))
		check(report, riseLive.WorstStep <= stride + .05 and not riseLive.Clamped,
			"and no single production Step moved further than the stride it was asked"
			.. " for, with the substep cap never binding",
			string.format("worst %.3f of %.3f, clamped %s", riseLive.WorstStep, stride,
				tostring(riseLive.Clamped)))
	end

	-- ------------------------------------------------------------------
	-- B. a 2.0-stud trench, six studs above the floor
	-- ------------------------------------------------------------------
	local slabTop = laneFloor + SUBSTEP_TRENCH_LIFT
	local trenchNearX = featureCenterX - SUBSTEP_FEATURE_WIDTH * .5
	local function buildSlab(name, minX, maxX)
		local slab = Instance.new("Part")
		slab.Name = name
		slab.Anchored = true
		slab.CanCollide = true
		slab.Transparency = 1
		slab.Size = Vector3.new(maxX - minX, 4, 52)
		slab.CFrame = CFrame.new((minX + maxX) * .5, slabTop - 2, lane.Z)
		slab:SetAttribute("Level2_EntityGround", true)
		slab.Parent = geometry
		return slab
	end
	local near = buildSlab("Substep Probe Slab Near", startX - 14, trenchNearX)
	local far = buildSlab("Substep Probe Slab Far",
		trenchNearX + SUBSTEP_FEATURE_WIDTH, startX + SUBSTEP_LANE_LENGTH + 14)

	local trenchOrigin = Vector3.new(startX, slabTop, lane.Z)
	local trenchLive = walk(trenchOrigin, false)
	local trenchMutant = walk(trenchOrigin, true)
	near:Destroy()
	far:Destroy()

	if check(report, trenchLive ~= nil and trenchMutant ~= nil,
		"both rigs could stand on the near slab of the trench lane",
		string.format("production %s, mutant %s", tostring(trenchLive ~= nil),
			tostring(trenchMutant ~= nil))) then
		local liveReach = trenchLive.FinalX - trenchLive.StartX
		local mutantReach = trenchMutant.FinalX - trenchMutant.StartX
		local nearLip = trenchNearX - trenchLive.StartX
		note(report, string.format("trench lane: near lip at +%.2f; production reached"
			.. " +%.2f (%s, blocked by %s), single-stride mutant reached +%.2f",
			nearLip, liveReach, trenchLive.Status, tostring(trenchLive.BlockedBy),
			mutantReach))
		check(report, liveReach <= nearLip,
			string.format("production STOPPED at the near lip of the %.1f-stud trench --"
				.. " it never stood where there was no floor", SUBSTEP_FEATURE_WIDTH),
			string.format("reached +%.2f, lip at +%.2f", liveReach, nearLip))
		check(report, liveReach >= nearLip - tuning.MaxTravelStep - .1,
			"and walked all the way UP to it, so the refusal is the trench and not"
			.. " something earlier in the lane",
			string.format("reached +%.2f, lip at +%.2f", liveReach, nearLip))
		check(report, mutantReach > nearLip + SUBSTEP_FEATURE_WIDTH,
			"MUTATION CAUGHT: with the loop removed the same navigator steps clean"
			.. " over the trench -- both endpoints have floor, so one placement sees"
			.. " nothing wrong with walking on air",
			string.format("mutant reached +%.2f, past the far lip at +%.2f",
				mutantReach, nearLip + SUBSTEP_FEATURE_WIDTH))
	end

	return report
	end)
end


-- ---------------------------------------------------------------------------
-- Centring -- the route the body can actually walk
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN: the route and the body disagreed about what fits, and
-- nothing measured the disagreement.
--
-- PathfindingService plans for a CYLINDER of PathAgentRadius = 8.25. The body
-- the navigator walks is a 16.30-stud axis-aligned SQUARE box whose corners
-- reach 11.53 from centre. So PFS could legally route within 8.25 studs of an
-- arch rib and the box then did not fit. Measured on seed 101 over the four
-- routes that were failing: 180 of the planned points put the body inside
-- collidable geometry -- and every single one of them had a clear standing
-- position nearby (166 by a sidestep, 143 of those within 5 studs; the rest by
-- a short 2D search; NONE unrescuable). The creature was not too big for the
-- level. It was being routed down the edge of it.
--
-- The authored geometry says how tight this is, and the number is the reason
-- this suite exists. Both the barrel vault and the arch ribs are struck about
-- an arc centre ONE STUD above the corridor floor, so the clear half-width at
-- a height y is sqrt(R^2 - (y - 1)^2). With the body box 10.70 tall on a
-- -1.5 floor its top is at y = 9.46, and:
--
--     vault     R = 13.30  ->  half-width 10.26  ->  body clears to |u| = 2.11
--     arch rib  R = 12.10  ->  half-width  8.65  ->  body clears to |u| = 0.50
--
-- The ribs repeat closely enough that a 16.30-long box nearly always overlaps
-- one. So a 34-stud-wide corridor has a walkable channel about HALF A STUD
-- either side of its centre line, and a route that is merely "on clear ground"
-- is not good enough -- it has to be ON the centre line.
--
-- Every expected value below is derived from those authored radii, by this
-- file, and then checked against what the live world actually does. Nothing is
-- taken from the navigator's own report of itself.
local CENTRING_VAULT_INNER_RADIUS = 13.30
local CENTRING_RIB_INNER_RADIUS = 12.10
local CENTRING_ARC_CENTRE_Y = 1
-- Half a stud of slack on the analytic band, for the polygonal approximation
-- of the arc and the seam overlaps between courses.
local CENTRING_BAND_TOLERANCE = .6

-- The lateral offsets the four originally-failing routes were jamming at, and
-- the parts that stopped them. Named so this suite fails loudly if a future
-- change makes any of them regress, rather than only reporting an aggregate.
local CENTRING_NAMED_ROUTES = {
	{From = 1, To = 32, Blocker = "Level 2 Vault Strip 1"},
	{From = 1, To = 38, Blocker = "Level 2 Vault Strip 1"},
	{From = 1, To = 30, Blocker = "Level 2 Vault Strip 1"},
	{From = 1, To = 31, Blocker = "Level 2 Vault Strip 1"},
	{From = 12, To = 13, Blocker = "Level 2 Arch Rib 21.1"},
	{From = 13, To = 15, Blocker = "Level 2 Arch Rib 21.3"},
}

function Suite.Centring(manifest)
	local report = newReport("Slidemouth route centring (clearance-aware)")
	local tuning = Controller.MovementTuning
	if not check(report, typeof(tuning) == "table",
		"the controller exposes its production movement tuning") then
		return setBranch(report, "no-tuning")
	end

	return protect(report, function(onCleanup)
	local layout = manifest.Layout
	local folder = Instance.new("Folder")
	folder.Name = "Level 2 Slidemouth Centring Rigs"
	folder.Parent = manifest.World
	onCleanup("centring rig folder", function()
		if folder.Parent then folder:Destroy() end
		assert(folder.Parent == nil, "centring rig folder is still in the world")
	end)

	local model = makeProbeModel(folder, tuning)
	local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
	onCleanup("centring navigator", function()
		navigator:Destroy()
		if model.Parent then model:Destroy() end
	end)

	-- The body test, asked of the navigator itself so this cannot drift from
	-- what the walk does.
	local function bodyFits(position)
		navigator.HasGrounded = false
		local surfaceY = navigator:_surfaceAt(position, true)
		if surfaceY == nil then return false, nil end
		local foot = Vector3.new(position.X, surfaceY + tuning.FootClearance, position.Z)
		return navigator:_bodyBoxClear(foot), foot
	end

	local function lateralOf(corridor, position)
		local cross = tonumber(corridor.Cross)
		return corridor.Axis == "X" and (position.Z - cross) or (position.X - cross)
	end
	local function pointOnCorridor(corridor, alongValue, lateralOffset)
		local cross = tonumber(corridor.Cross)
		if corridor.Axis == "X" then
			return Vector3.new(alongValue, 0, cross + lateralOffset)
		end
		return Vector3.new(cross + lateralOffset, 0, alongValue)
	end
	local function corridorOf(position)
		for _, corridor in ipairs(layout.Corridors or {}) do
			local cross, from, to = tonumber(corridor.Cross), tonumber(corridor.From),
				tonumber(corridor.To)
			local width = tonumber(corridor.Width) or 34
			if cross and from and to then
				local lo, hi = math.min(from, to), math.max(from, to)
				local along = corridor.Axis == "X" and position.X or position.Z
				local lateral = corridor.Axis == "X" and position.Z or position.X
				if along >= lo - 2 and along <= hi + 2
					and math.abs(lateral - cross) <= width * .5 + 2 then
					return corridor
				end
			end
		end
		return nil
	end

	-- ------------------------------------------------------------------
	-- A. the analytic channel, checked against the live world
	-- ------------------------------------------------------------------
	local lane, laneFloor
	for _, corridor in ipairs(layout.Corridors or {}) do
		local from, to = tonumber(corridor.From), tonumber(corridor.To)
		if corridor.Kind == "Open" and from and to and math.abs(to - from) >= 40 then
			local middle = pointOnCorridor(corridor, (from + to) * .5, 0)
			local fits, foot = bodyFits(middle)
			if fits and foot then lane, laneFloor = corridor, foot.Y break end
		end
	end
	if not check(report, lane ~= nil,
		"the map has an open corridor whose centre line the body can stand on,"
		.. " to measure the channel in") then
		return setBranch(report, "no-corridor")
	end
	local bodyTop = laneFloor + (math.max(2, tuning.AgentHeight - .3)) + .18
	local halfWidthAt = function(radius)
		local rise = bodyTop - CENTRING_ARC_CENTRE_Y
		local inside = radius * radius - rise * rise
		return inside > 0 and math.sqrt(inside) or 0
	end
	local bodyHalf = math.max(1, tuning.AgentRadius * 2 - .2) * .5
	local ribBand = halfWidthAt(CENTRING_RIB_INNER_RADIUS) - bodyHalf
	local vaultBand = halfWidthAt(CENTRING_VAULT_INNER_RADIUS) - bodyHalf
	note(report, string.format("corridor %s: floor %.2f, body top %.2f; authored channel"
		.. " is |u| <= %.2f at an arch rib and |u| <= %.2f between ribs",
		tostring(lane.Index), laneFloor, bodyTop, ribBand, vaultBand))

	check(report, ribBand > 0 and ribBand < tuning.AgentRadius * .5,
		"the authored arch ribs leave this body less than half a body radius of"
		.. " lateral freedom either side of the corridor centre line -- which is why"
		.. " a route that merely stands on clear ground is not good enough",
		string.format("%.2f studs", ribBand))

	-- The world has to agree with the arithmetic: centred fits, and somewhere
	-- inside the vault band but outside the rib band does not.
	local alongMid = (tonumber(lane.From) + tonumber(lane.To)) * .5
	local centreFits = bodyFits(pointOnCorridor(lane, alongMid, 0))
	local outsideOffset = math.max(vaultBand + 2, 4)
	local outsideFits = bodyFits(pointOnCorridor(lane, alongMid, outsideOffset))
	local outsideFitsOther = bodyFits(pointOnCorridor(lane, alongMid, -outsideOffset))
	check(report, centreFits and not outsideFits and not outsideFitsOther,
		"and the live world agrees with that arithmetic: the body fits on the centre"
		.. " line and does not fit at the offset the authored vault says it should"
		.. " not",
		string.format("centre %s, +%.1f %s, -%.1f %s", tostring(centreFits),
			outsideOffset, tostring(outsideFits), outsideOffset, tostring(outsideFitsOther)))

	-- ------------------------------------------------------------------
	-- B. the pass itself, on a route built to be wrong
	-- ------------------------------------------------------------------
	-- A deliberately off-centre line down the corridor: exactly the shape
	-- PathfindingService produces when it hugs one side, and exactly what the
	-- body cannot walk.
	local crooked = {}
	local from, to = tonumber(lane.From), tonumber(lane.To)
	local span = to - from
	for step = 0, 8 do
		local t = step / 8
		local offset = (step % 2 == 0) and outsideOffset or -outsideOffset
		table.insert(crooked, pointOnCorridor(lane, from + span * t, offset))
	end
	local crookedBlocked = 0
	for _, point in ipairs(crooked) do
		if not bodyFits(point) then crookedBlocked += 1 end
	end
	check(report, crookedBlocked >= #crooked - 1,
		"the deliberately off-centre route this suite builds really is unwalkable --"
		.. " otherwise everything below would pass without proving anything",
		string.format("%d of %d points blocked", crookedBlocked, #crooked))

	navigator:WarpTo(pointOnCorridor(lane, from, 0), Vector3.xAxis, true)
	local centred, stats = navigator:DebugCentreRoute(crooked)
	local afterBlocked, afterOffCentre, worstOffset = 0, 0, 0
	for index, point in ipairs(centred) do
		-- The GOAL is excluded on purpose. It is never moved -- see the
		-- assertion below -- so when the goal itself is somewhere the body
		-- cannot stand, that is a fact about the target, not a failure of the
		-- pass. What the pass owes there is a clear APPROACH point in front of
		-- it, which is asserted separately.
		if index < #centred and not bodyFits(point) then afterBlocked += 1 end
		local corridor = corridorOf(point)
		-- The last point is the goal and is deliberately never moved.
		if corridor and index < #centred then
			local offset = math.abs(lateralOf(corridor, point))
			worstOffset = math.max(worstOffset, offset)
			if offset > ribBand + CENTRING_BAND_TOLERANCE then afterOffCentre += 1 end
		end
	end
	note(report, string.format("centring: %d points -> %d, %d moved, %d inserted,"
		.. " %d unresolved, %d queries, worst residual offset %.2f",
		stats.Points, #centred, stats.Moved, stats.Inserted, stats.Unresolved,
		stats.Queries, worstOffset))

	check(report, stats.Unresolved == 0,
		"the centring pass found a body-clear position for every point of it",
		string.format("%d unresolved", stats.Unresolved))
	check(report, afterBlocked == 0,
		"and every INTERMEDIATE point of the centred route is one the body can stand on",
		string.format("%d still blocked of %d", afterBlocked, #centred - 1))
	-- This crooked route deliberately ends off-centre, so its goal is one the
	-- body cannot occupy. The pass must therefore have put a standable approach
	-- point immediately before it rather than leaving the rig nothing to aim at.
	local goalStandable = bodyFits(crooked[#crooked])
	local approach = centred[#centred - 1]
	check(report, goalStandable or (approach ~= nil and bodyFits(approach)),
		"and when the goal itself is somewhere the body cannot stand, the point"
		.. " immediately before it is somewhere it can -- the rig always has a"
		.. " reachable place to make its final approach from",
		string.format("goal standable %s, approach standable %s", tostring(goalStandable),
			tostring(approach ~= nil and bodyFits(approach))))
	check(report, afterOffCentre == 0,
		"and every corridor point of it sits inside the authored arch-rib channel,"
		.. " not merely somewhere that happens to be clear",
		string.format("%d outside |u| <= %.2f, worst %.2f", afterOffCentre,
			ribBand + CENTRING_BAND_TOLERANCE, worstOffset))
	check(report, centred[#centred] == crooked[#crooked],
		"the GOAL is never moved -- arriving somewhere near the target is not"
		.. " arriving at it",
		string.format("last point %s", tostring(centred[#centred] == crooked[#crooked])))

	-- ------------------------------------------------------------------
	-- C. the routes that were actually failing, by name
	-- ------------------------------------------------------------------
	local nodes = {}
	for _, child in ipairs(manifest.Navigation:GetChildren()) do
		if child:IsA("BasePart") then
			local index = tonumber(child.Name:match("(%d+)$"))
			if index and not nodes[index] then nodes[index] = child.Position end
		end
	end
	local tested, cleanRoutes = 0, 0
	local offenders = {}
	for _, route in ipairs(CENTRING_NAMED_ROUTES) do
		local a, b = nodes[route.From], nodes[route.To]
		if a and b then
			tested += 1
			navigator:WarpTo(a, (b - a).Unit, true)
			navigator:SetGoal(b, true)
			local deadline = os.clock() + 12
			while navigator.Computing and os.clock() < deadline do
				RunService.Heartbeat:Wait()
			end
			local blocked = 0
			for index, point in ipairs(navigator.Waypoints) do
				if index < #navigator.Waypoints and not bodyFits(point) then
					blocked += 1
				end
			end
			if blocked == 0 then
				cleanRoutes += 1
			elseif #offenders < 4 then
				table.insert(offenders, string.format("%d->%d: %d of %d blocked",
					route.From, route.To, blocked, #navigator.Waypoints))
			end
		end
	end
	note(report, string.format("named routes: %d of %d present on this map, %d produced"
		.. " a fully body-clear route", tested, #CENTRING_NAMED_ROUTES, cleanRoutes))
	check(report, tested >= 2,
		"enough of the originally-failing routes exist on this map to be worth"
		.. " re-testing",
		string.format("%d of %d", tested, #CENTRING_NAMED_ROUTES))
	check(report, cleanRoutes == tested,
		"and every one of them now plans a route whose every intermediate point the"
		.. " body can stand on -- these are the exact routes that were jamming on"
		.. " Vault Strip 1 and the arch ribs",
		string.format("%d of %d clean%s", cleanRoutes, tested,
			#offenders > 0 and ("  [" .. table.concat(offenders, "; ") .. "]") or ""))

	return report
	end)
end


-- ---------------------------------------------------------------------------
-- Traversal -- PRODUCTION navigation, walked end to end
-- ---------------------------------------------------------------------------
--
-- WHAT SHIPPED BROKEN: there was no such suite. The one-off probe that measured
-- this was run by hand, once, and never encoded, so nothing in the shipped
-- suite ever walked a production route. Ledges builds its own lanes and its own
-- ledges; Adversarial drives _placeFoot and _clearAdvance directly. Neither
-- ever asked the navigator for a ROUTE. So SetGoal, the PathfindingService
-- request, the graph fallback it falls back to, and -- since the substep
-- rewrite -- every validated placement in between were covered only by a live
-- creature nobody was measuring. A route that cut through a wall, a stride that
-- straddled a riser, or a rig that circled forever would all have shipped
-- green.
--
-- Everything here drives the REAL navigator the controller builds: the same
-- Navigator.new, the same Controller.MovementTuning, the same RuntimeFolder
-- exclusion. Nothing is re-implemented. AgentRadius and PathAgentRadius are
-- READ and never written.
--
-- The four claims, each with an independent oracle:
--
--   route exists   -- for two halls joined by an unblocked corridor, NO_PATH is
--                     impossible: _fallbackWaypoints walks the same room graph
--                     this suite's own hops() walks, so a corridor open to one
--                     is open to the other. Adjacency is decided HERE.
--   no wall cross  -- a raycast between CONSECUTIVE recorded foot positions, at
--                     body-mid height, against collidable geometry that is not
--                     Level2_EntityGround. Ground is skipped past rather than
--                     excluded up front, so a slab cannot hide a wall behind it.
--   no teleport    -- per-Step horizontal displacement against the navigator's
--                     own contract: travel = min(distance, speed * dt), split
--                     into pieces no longer than MaxTravelStep, at most
--                     MAX_TRAVEL_SUBSTEPS of them.
--   bounded        -- a hard iteration cap per pair, derived from the route the
--                     navigator itself produced. Hitting it while still moving
--                     is a FAILURE.

local function traversalNodes(manifest)
	local byHall = {}
	local count = 0
	if not manifest.Navigation then return byHall, count end
	for _, child in ipairs(manifest.Navigation:GetChildren()) do
		if child:IsA("BasePart") then
			local index = tonumber(child.Name:match("(%d+)$"))
			if index and not byHall[index] then
				byHall[index] = child.Position
				count += 1
			end
		end
	end
	return byHall, count
end

function Suite.Traversal(manifest)
	local report = newReport("Slidemouth production navigation")
	local tuning = Controller.MovementTuning
	if not check(report, typeof(tuning) == "table",
		"the controller exposes its production movement tuning") then
		return setBranch(report, "no-tuning")
	end

	return protect(report, function(onCleanup)
	local layout = manifest.Layout
	local folder = Instance.new("Folder")
	folder.Name = "Level 2 Slidemouth Traversal Rigs"
	folder.Parent = manifest.World
	onCleanup("traversal rig folder", function()
		if folder.Parent then folder:Destroy() end
		assert(folder.Parent == nil, "the traversal rig folder is still in the world")
	end)

	local nodes, nodeCount = traversalNodes(manifest)
	local corridorRecords = manifest.Corridors
	if not check(report, nodeCount >= 2 and type(corridorRecords) == "table"
		and type(layout.Corridors) == "table" and #layout.Corridors > 0,
		"the manifest exposes per-hall navigation nodes and the corridor records"
		.. " to route between them",
		string.format("%d nodes, %s corridor records", nodeCount,
			type(corridorRecords) == "table" and "a table of" or "no")) then
		return setBranch(report, "no-nodes")
	end

	-- ------------------------------------------------------------------
	-- The REAL asset, measured against the clearance the navigator assumes.
	-- ------------------------------------------------------------------
	-- Nothing else in this file has ever looked at the creature the controller
	-- actually clones. AgentRadius is the half-width of the box _clearAdvance
	-- tests before it commits a step and AgentHeight is that box's height, so an
	-- asset swap that outgrows either of them makes every clearance decision in
	-- the navigator a lie -- silently, because the navigator measures the BOX and
	-- never the model. The numbers are reported either way, so a marginal result
	-- is diagnosable rather than merely red.
	local assets = ServerStorage:FindFirstChild(EXPECTED_ASSET_FOLDER)
	local template = assets and assets:FindFirstChild(EXPECTED_TEMPLATE_NAME)
	local runtimeScale = tonumber(Controller.ModelScale) or 1
	if not check(report, template ~= nil and template:IsA("Model")
		and template.PrimaryPart ~= nil and runtimeScale > 0,
		"the shipped Slidemouth template is readable from ServerStorage."
		.. EXPECTED_ASSET_FOLDER,
		template == nil and ("no " .. EXPECTED_TEMPLATE_NAME) or "not a Model with a PrimaryPart") then
		return setBranch(report, "no-template")
	end
	local _, authoredTemplateSize = template:GetBoundingBox()
	-- cloneModel applies this exact uniform scale before the runtime navigator is
	-- constructed, so measure the asset players actually see rather than the
	-- unscaled ServerStorage source.
	local templateSize = authoredTemplateSize * runtimeScale
	-- GetBoundingBox is expressed in the model pivot's axes.  X is lateral;
	-- Z is the creature's nose-to-tail length.  Treating max(X, Z) as a
	-- circular radius made the 19.455-stud LONG model fail an 8.25-stud
	-- LATERAL clearance assertion even though its 15.924-stud width fits and
	-- the live asset has no collidable parts.  That false result was the reason
	-- the original seed-101-only scale sweep looked inconclusive. A later
	-- seed-303 aperture proof is why the shipped runtime now deliberately uses
	-- the exported scale measured here.
	local templateLateralHalfWidth = templateSize.X * .5
	local templateLongitudinalHalf = templateSize.Z * .5
	local collidableTemplateParts = 0
	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.CanCollide then
			collidableTemplateParts += 1
		end
	end
	local probeHalfWidth = math.max(1, tuning.AgentRadius * 2 - .2) * .5
	local probeHeight = math.max(2, tuning.AgentHeight - .3)
	note(report, string.format(
		"runtime template at %.2fx: extents %.3f x %.3f x %.3f -> lateral half-width %.3f,"
		.. " nose-to-tail half-length %.3f, height %.3f, %d collidable parts;"
		.. " body probe %.3f half-width, %.3f high (AgentRadius %.2f, AgentHeight %.2f)",
		runtimeScale, templateSize.X, templateSize.Y, templateSize.Z, templateLateralHalfWidth,
		templateLongitudinalHalf, templateSize.Y, collidableTemplateParts,
		probeHalfWidth, probeHeight, tuning.AgentRadius, tuning.AgentHeight))
	check(report, templateLateralHalfWidth <= tuning.AgentRadius
		and collidableTemplateParts == 0,
		"the shipped creature's lateral render width fits inside the navigation"
		.. " radius and it has no separate collidable hull",
		string.format("%.3f lateral vs %.2f radius; %d collidable parts",
			templateLateralHalfWidth, tuning.AgentRadius, collidableTemplateParts))
	check(report, templateSize.Y <= tuning.AgentHeight,
		"and its measured height fits inside the navigator's AgentHeight",
		string.format("%.3f measured, %.2f allowed", templateSize.Y, tuning.AgentHeight))

	-- Spiral Stair Wells used to be authored directly on hall.Center, which is
	-- also the generated graph fallback's waypoint. The route could plan and get
	-- most of the way there, then stop on an outer guard rail. Verify every
	-- RETAINED spiral against the full fixed-size, wall, centre-lane and door-
	-- route contracts. Unsuitable procedural rolls are re-dressed before build,
	-- not scaled down and not allowed to make generation fail.
	local spiralCount = 0
	local wrongSize, outsideWall, centreLaneUnsafe, doorLaneUnsafe = {}, {}, {}, {}
	local bodyHalfDiagonal = math.max(1, tuning.AgentRadius * 2 - .2) * .5 * math.sqrt(2)
	local inflatedClearance = 13 * 1.75 + bodyHalfDiagonal + 1
	local doorsByHall = {}
	for _, hall in ipairs(layout.Halls or {}) do
		doorsByHall[hall.Index] = {East = {}, West = {}, North = {}, South = {}}
	end
	for _, corridor in ipairs(layout.Corridors or {}) do
		local a, b = layout.Halls[corridor.A], layout.Halls[corridor.B]
		if a and b and corridor.Axis == "X" then
			local left = a.MaxX <= b.MinX and a or b
			local right = left == a and b or a
			table.insert(doorsByHall[left.Index].East, corridor.Cross)
			table.insert(doorsByHall[right.Index].West, corridor.Cross)
		elseif a and b then
			local north = a.MaxZ <= b.MinZ and a or b
			local south = north == a and b or a
			table.insert(doorsByHall[north.Index].South, corridor.Cross)
			table.insert(doorsByHall[south.Index].North, corridor.Cross)
		end
	end
	local function distanceToSegment(point, a, b)
		local span = b - a
		local denominator = span.X * span.X + span.Z * span.Z
		local projection = denominator > 0 and math.clamp(
			((point.X - a.X) * span.X + (point.Z - a.Z) * span.Z) / denominator,
			0, 1) or 0
		local closest = a + span * projection
		return horizontal(point, closest)
	end
	for _, hall in ipairs(layout.Halls or {}) do
		if hall.Archetype == "Spiral Stair Well" then
			spiralCount += 1
			local center = hall.SpiralCenter
			local radius = tonumber(hall.SpiralRadius)
			local structureRadius = tonumber(hall.SpiralStructureRadius)
			if radius ~= 13 or structureRadius ~= 13 * 1.75 then
				table.insert(wrongSize, tostring(hall.Index))
			end
			if typeof(center) ~= "Vector3" or not structureRadius
				or center.X - structureRadius < hall.MinX + 3 - .01
				or center.X + structureRadius > hall.MaxX - 3 + .01
				or center.Z - structureRadius < hall.MinZ + 3 - .01
				or center.Z + structureRadius > hall.MaxZ - 3 + .01 then
				table.insert(outsideWall, tostring(hall.Index))
			end
			if typeof(center) ~= "Vector3"
				or math.abs(center.X - hall.Center.X) < inflatedClearance - .01
				or math.abs(center.Z - hall.Center.Z) < inflatedClearance - .01 then
				table.insert(centreLaneUnsafe, tostring(hall.Index))
			end
			if typeof(center) == "Vector3" then
				local doors = doorsByHall[hall.Index]
				local safe = true
				local function scan(values, aFor, bFor)
					for _, cross in ipairs(values or {}) do
						if distanceToSegment(center, aFor(cross), bFor(cross))
							< inflatedClearance - .01 then
							safe = false
							return
						end
					end
				end
				scan(doors and doors.North,
					function(cross) return Vector3.new(cross, 0, hall.MinZ) end,
					function(cross) return Vector3.new(cross, 0, hall.Center.Z) end)
				scan(doors and doors.South,
					function(cross) return Vector3.new(cross, 0, hall.MaxZ) end,
					function(cross) return Vector3.new(cross, 0, hall.Center.Z) end)
				scan(doors and doors.West,
					function(cross) return Vector3.new(hall.MinX, 0, cross) end,
					function(cross) return Vector3.new(hall.Center.X, 0, cross) end)
				scan(doors and doors.East,
					function(cross) return Vector3.new(hall.MaxX, 0, cross) end,
					function(cross) return Vector3.new(hall.Center.X, 0, cross) end)
				if not safe then table.insert(doorLaneUnsafe, tostring(hall.Index)) end
			else
				table.insert(doorLaneUnsafe, tostring(hall.Index))
			end
		end
	end
	local rolls = tonumber(manifest.World:GetAttribute("Level2_SpiralRolls")) or 0
	local built = tonumber(manifest.World:GetAttribute("Level2_SpiralsBuilt")) or 0
	local rerouted = tonumber(manifest.World:GetAttribute("Level2_SpiralsRerouted")) or 0
	check(report, #wrongSize == 0 and built == spiralCount and rolls == built + rerouted,
		"every retained Spiral Stair Well keeps the full fixed 13-stud structure",
		string.format("%d retained, %d rerouted; wrong size: %s", spiralCount, rerouted,
			#wrongSize == 0 and "none" or table.concat(wrongSize, ", ")))
	check(report, #outsideWall == 0,
		"every retained Spiral Stair Well keeps its complete footprint inside the hall walls",
		#outsideWall == 0 and nil or table.concat(outsideWall, ", "))
	check(report, #centreLaneUnsafe == 0,
		"every retained Spiral Stair Well preserves both square-body graph lanes through hall centre",
		#centreLaneUnsafe == 0 and nil or table.concat(centreLaneUnsafe, ", "))
	check(report, #doorLaneUnsafe == 0,
		"every retained Spiral Stair Well preserves the body-inflated route from every door to centre",
		#doorLaneUnsafe == 0 and nil or table.concat(doorLaneUnsafe, ", "))

	-- ------------------------------------------------------------------
	-- Pair selection. Corridor width is measured from the layout, so the
	-- TIGHTEST doorways on this map are the ones sampled, not whichever came
	-- first in build order.
	-- ------------------------------------------------------------------
	local exitPowered = workspace:GetAttribute("Level2ExitPowered") == true
	local adjacency = {}
	for _, corridor in ipairs(layout.Corridors) do
		local a, b = tonumber(corridor.A), tonumber(corridor.B)
		local from, to = tonumber(corridor.From), tonumber(corridor.To)
		local open = not (corridor.Kind == "PressureDoor" and not exitPowered)
		if a and b and nodes[a] and nodes[b] and open then
			table.insert(adjacency, {
				A = a, B = b,
				Width = (from and to) and math.abs(to - from) or math.huge,
				Kind = tostring(corridor.Kind),
				Record = corridorRecords[corridor.Index],
			})
		end
	end
	table.sort(adjacency, function(x, y)
		if x.Width ~= y.Width then return x.Width < y.Width end
		return x.A < y.A
	end)

	local groundParams = groundParamsFor(manifest)
	local function groundY(position)
		local hit = workspace:Raycast(position + Vector3.new(0, 40, 0),
			Vector3.new(0, -260, 0), groundParams)
		return hit and hit.Position.Y or nil
	end

	-- The tightest corridors first, then a spread of longer routes taken from
	-- the suite's own BFS, so the sample is not all one hop.
	--
	-- The budget is SPLIT, not first-come. A generated map has more corridors
	-- than the whole budget, so filling it in sorted order would leave every
	-- multi-hop route unsampled -- and a suite that only ever walks one hop has
	-- not exercised the repath the navigator does on the way to a far goal.
	local wanted = {}
	local seenPair = {}
	local function addPair(a, b, kind, width, limit)
		if a == b then return end
		local key = math.min(a, b) .. ":" .. math.max(a, b) .. ":" .. kind
		if seenPair[key] or #wanted >= math.min(limit, TRAVERSAL_PAIR_BUDGET) then return end
		seenPair[key] = true
		table.insert(wanted, {A = a, B = b, Kind = kind, Width = width, Adjacent = kind == "corridor"})
	end
	for _, entry in ipairs(adjacency) do
		addPair(entry.A, entry.B, "corridor", entry.Width, TRAVERSAL_TIGHT_BUDGET)
	end
	local firstIndex
	for index in pairs(nodes) do
		if firstIndex == nil or index < firstIndex then firstIndex = index end
	end
	local spread = hops(layout, firstIndex)
	local far = {}
	for index, distance in pairs(spread) do
		if distance >= 2 and nodes[index] then
			table.insert(far, {Index = index, Distance = distance})
		end
	end
	table.sort(far, function(x, y)
		if x.Distance ~= y.Distance then return x.Distance > y.Distance end
		return x.Index < y.Index
	end)
	for _, entry in ipairs(far) do
		addPair(firstIndex, entry.Index, "long", math.huge, TRAVERSAL_PAIR_BUDGET)
	end
	-- If the map had fewer long routes than the reserved slots, give the rest
	-- back to the corridors rather than walking a smaller sample than the budget.
	for _, entry in ipairs(adjacency) do
		addPair(entry.A, entry.B, "corridor", entry.Width, TRAVERSAL_PAIR_BUDGET)
	end

	-- ------------------------------------------------------------------
	-- Walk them, through production navigation.
	-- ------------------------------------------------------------------
	local strideBound = TRAVERSAL_SPEED * TRAVERSAL_DELTA
	-- The navigator's own contract, restated: the stride is split into pieces of
	-- at most MaxTravelStep and there are at most MAX_TRAVEL_SUBSTEPS of them,
	-- and each piece runs the full _placeFoot -- floor resolve with the
	-- MaxStepHeight ceiling, plus the body-volume test. So the horizontal reach
	-- of ONE Step is bounded by the stride, and the height it may gain is bounded
	-- by one MaxStepHeight per piece.
	local pieceCount = math.min(EXPECTED_MAX_TRAVEL_SUBSTEPS,
		math.max(1, math.ceil(strideBound / tuning.MaxTravelStep)))
	local riseBound = pieceCount * tuning.MaxStepHeight

	-- Built ONCE. The rig's own folder, the neon marker folders, the buoyant
	-- props the controller itself excludes, and the player characters -- a player
	-- standing in a corridor is not a wall.
	local rayExclusions = {folder}
	if manifest.EntityNodes then table.insert(rayExclusions, manifest.EntityNodes) end
	if manifest.Navigation then table.insert(rayExclusions, manifest.Navigation) end
	if manifest.BuoyantProps then table.insert(rayExclusions, manifest.BuoyantProps) end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(rayExclusions, player.Character) end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	rayParams.RespectCanCollide = true

	local function crossedBlockingGeometry(fromFoot, toFoot)
		local lift = Vector3.new(0, tuning.AgentHeight * .5, 0)
		local origin = fromFoot + lift
		local displacement = (toFoot + lift) - origin
		if displacement.Magnitude < 1e-3 then return nil end
		rayParams.FilterDescendantsInstances = rayExclusions
		local hit = workspace:Raycast(origin, displacement, rayParams)
		if not hit then return nil end
		local part = hit.Instance
		local isGround = part:GetAttribute("Level2_EntityGround") == true
			and part:GetAttribute("Level2_NoEntityGround") ~= true
		if not isGround then return part end
		-- Ground is stepped PAST rather than filtered out up front, so a slab
		-- cannot hide a wall standing behind it. The extra exclusions live on a
		-- COPY, so the shared list above is never grown by a probe.
		local extended = table.clone(rayExclusions)
		table.insert(extended, part)
		local deepParams = RaycastParams.new()
		deepParams.FilterType = Enum.RaycastFilterType.Exclude
		deepParams.IgnoreWater = true
		deepParams.RespectCanCollide = true
		for _ = 1, 7 do
			deepParams.FilterDescendantsInstances = extended
			local deeper = workspace:Raycast(origin, displacement, deepParams)
			if not deeper then return nil end
			local deepPart = deeper.Instance
			if not (deepPart:GetAttribute("Level2_EntityGround") == true
				and deepPart:GetAttribute("Level2_NoEntityGround") ~= true) then
				return deepPart
			end
			table.insert(extended, deepPart)
		end
		-- The budget ran out with only ground behind ground. Nothing has been
		-- shown to be a wall, so nothing is reported as one.
		return nil
	end

	local attempted, skipped = 0, 0
	local arrived, blockedOut, capHit = 0, 0, 0
	local routeless, mustRouteMissing = 0, 0
	-- One list per counter. They used to share one, capped at six entries, so a
	-- blocked pair consumed TWO slots and only three distinct failing pairs were
	-- ever named out of the ten that can be walked -- and each of the three
	-- assertions below quoted the other two's evidence.
	local blockedNames, staleNames, capNames = {}, {}, {}
	local starvedBudgets, budgetNames = 0, {}
	-- WHAT SHIPPED BROKEN IN THIS SUITE'S SUCCESS BAR: the walk ended on
	-- "arrived >= 3 of however many were walked". Five pairs could end jammed
	-- against a prop, or spinning on an empty waypoint list, and the suite went
	-- green -- the exact failure the owner reports in play, reported as a pass.
	-- A blocked route is a FAILURE. These two count the pairs that must arrive
	-- and did not, and the stale-yield regression by name.
	local connectedUnarrived, staleYield = 0, 0
	local wallCrossings, longSteps, tallSteps = 0, 0, 0
	local worstStride, worstRise = 0, 0
	local tightPairs, elevationPairs = 0, 0
	local climbedAtAll = 0
	local graphRecoveryPlanned = 0
	local lines = {}

	for _, pair in ipairs(wanted) do
		local start = nodes[pair.A]
		local goal = nodes[pair.B]
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		local facing = Vector3.new(goal.X - start.X, 0, goal.Z - start.Z)
		facing = facing.Magnitude > .01 and facing.Unit or Vector3.new(0, 0, -1)
		if not navigator:WarpTo(start, facing, true) then
			skipped += 1
			navigator:Destroy()
			model:Destroy()
		else
			attempted += 1
			if pair.Kind == "corridor" and pair.Width < math.huge then tightPairs += 1 end
			local startFloor = groundY(start)
			local goalFloor = groundY(goal)
			if startFloor and goalFloor and math.abs(startFloor - goalFloor) > .4 then
				elevationPairs += 1
			end

			-- Exercise the watchdog's forced graph recovery on the first live pair.
			-- It must use the same clearance-aware installer as an ordinary path;
			-- raw room-centre waypoints were a separate production-only bypass.
			local graphRecovery = attempted == 1
			if graphRecovery then
				navigator:SetGraphGoal(goal, true)
			else
				navigator:SetGoal(goal, true)
			end
			local settleDeadline = os.clock() + TRAVERSAL_SETTLE_SECONDS
			while navigator.Computing == true and os.clock() < settleDeadline do
				task.wait(.05)
			end
			if graphRecovery and navigator.LastCentring ~= nil then
				graphRecoveryPlanned += 1
			end
			local status = navigator:GetStatus()
			-- THE STALE-YIELD REGRESSION, named where it can be seen: a request that
			-- never got scheduled leaves Computing true and the waypoint list EMPTY,
			-- and the rig then walks blind at the raw goal for the rest of the run.
			-- It is a distinct fact from "this map has no route here", and it is
			-- counted as its own failure rather than folded into routeless.
			local function stalledOnAnEmptyList()
				return navigator.Computing == true and #navigator.Waypoints == 0
			end
			local stale = stalledOnAnEmptyList()
			local routeLength = 0
			local cursor = navigator:GetPosition()
			for _, point in ipairs(navigator.Waypoints) do
				routeLength += horizontal(cursor, point)
				cursor = point
			end
			if status == "NO_PATH" or #navigator.Waypoints == 0 then
				routeless += 1
				if stale then
					staleYield += 1
					if #staleNames < 6 then
						table.insert(staleNames, string.format(
							"%d -> %d still Computing on an empty waypoint list after %ds",
							pair.A, pair.B, TRAVERSAL_SETTLE_SECONDS))
					end
				end
				if pair.Adjacent then connectedUnarrived += 1 end
				-- The claim that has an independent oracle: two halls joined by an
				-- unblocked corridor are joined in the room graph, and the graph
				-- fallback walks that same graph. NO_PATH there is impossible.
				if pair.Adjacent then
					mustRouteMissing += 1
					if #lines < 8 then
						table.insert(lines, string.format(
							"NO ROUTE across an OPEN corridor %d -> %d (width %.1f): status %s",
							pair.A, pair.B, pair.Width, tostring(status)))
					end
				end
			else
				local straightFrames = math.ceil(routeLength / strideBound)
				local cap = math.clamp(
					straightFrames * TRAVERSAL_ITERATION_SLACK
						+ TRAVERSAL_ITERATION_FLOOR,
					TRAVERSAL_ITERATION_FLOOR, TRAVERSAL_ITERATION_CEILING)
				-- A budget smaller than the route it is meant to cover cannot
				-- distinguish "the creature could not get there" from "we did
				-- not let it". Recorded per pair and asserted after the loop.
				if cap < straightFrames then
					starvedBudgets += 1
					if #budgetNames < 6 then
						table.insert(budgetNames, string.format(
							"%d -> %d: %d frames granted for a route needing %d",
							pair.A, pair.B, cap, straightFrames))
					end
				end
				local iterations, stalled = 0, 0
				local reached = false
				local previous = navigator:GetPosition()
				local climbed = 0
				local function currentPlanIsWithinDeadline()
					local snapshot = navigator:GetDebugSnapshot()
					local started = snapshot.RequestStartedAt
					return snapshot.Computing == true
						and snapshot.WaypointCount == 0
						and type(started) == "number"
						and started == started
						and os.clock() - started < TRAVERSAL_SETTLE_SECONDS
				end
				while iterations < cap do
					iterations += 1
					-- YIELD, exactly as the production Heartbeat driver does.
					--
					-- WHAT SHIPPED BROKEN IN THIS TEST: the walk loop called Step
					-- hundreds of times without ever yielding. Navigator:_requestPath
					-- does its PathfindingService work in a task.spawn'd thread that
					-- YIELDS on ComputeAsync, so in a non-yielding loop that thread
					-- is never scheduled: the very first repath leaves Computing
					-- true and the waypoint list EMPTY for the rest of the walk, and
					-- every remaining step reports BLOCKED while the rig walks blind
					-- at the raw goal. Traced on seed 101 -- clean progress for 47
					-- steps, then `wpCount=0 computing=true` frozen for 250 more.
					--
					-- The result was a suite that reported "0 arrived of 8 walked"
					-- on every world and blamed whatever prop the blinded rig
					-- happened to touch. That is a false failure, and it would have
					-- kept this suite permanently red for a defect that is not in
					-- the game.
					RunService.Heartbeat:Wait()
					local before = navigator:GetPosition()
					if navigator:Step(TRAVERSAL_DELTA, TRAVERSAL_SPEED) then
						reached = true
						break
					end
					local now = navigator:GetPosition()
					local stride = horizontal(now, before)
					local rise = now.Y - before.Y
					if stride > worstStride then worstStride = stride end
					if rise > worstRise then worstRise = rise end
					if stride > strideBound + 1e-3 then longSteps += 1 end
					if rise > riseBound + 1e-3 then tallSteps += 1 end
					if rise > .05 then climbed += 1 end
					local culprit = crossedBlockingGeometry(before, now)
					if culprit then
						wallCrossings += 1
						if #lines < 8 then
							table.insert(lines, string.format(
								"WALL CROSSED %d -> %d between (%.1f, %.1f) and (%.1f, %.1f): '%s'",
								pair.A, pair.B, before.X, before.Z, now.X, now.Z, culprit.Name))
						end
					end
					if stride < TRAVERSAL_STALL_STUDS then
						-- A yielded ComputeAsync request is bounded by the same eight-second
						-- contract used before the walk. Forty-five render frames can be
						-- substantially less than that, so do not call a legitimate in-flight
						-- request a geometry stall. The deadline belongs to this exact request:
						-- a stream of fresh replans can still exhaust the unchanged iteration
						-- cap, and a request older than the deadline resumes the stall counter.
						if currentPlanIsWithinDeadline() then
							stalled = 0
						else
							stalled += 1
						end
					else
						stalled = 0
					end
					previous = now
					if stalled >= TRAVERSAL_STALL_FRAMES then break end
					-- Yield periodically so a repath the navigator asks for on the
					-- way can actually land. Without it the rig walks a route that
					-- can never be refreshed, which is not what production does.
					if iterations % 4 == 0 then task.wait() end
				end
				if climbed > 0 then climbedAtAll += 1 end
				-- Re-read at the END of the walk as well: a repath asked for on the
				-- way can land in the same hole the first request did, and a rig that
				-- finishes the walk on an empty list with a request still outstanding
				-- has been walking blind, whatever else it did.
				-- ATTRIBUTE THE END STATE TO THE REQUEST'S OWN DEADLINE. LastBlockedBy
				-- is only a live observation and can be cleared by a later accepted
				-- probe, so it cannot prove why an asynchronous request is pending.
				-- A current request gets its full bounded settle window; only the same
				-- request still Computing with no waypoints after that deadline is the
				-- stale-yield regression. Geometry stalls and cap exhaustion retain
				-- their separate assertions below.
				local endSnapshot = navigator:GetDebugSnapshot()
				local endBlocker = endSnapshot.LastBlockedBy
				local requestStarted = endSnapshot.RequestStartedAt
				local requestTimedOut = endSnapshot.Computing == true
					and endSnapshot.WaypointCount == 0
					and (type(requestStarted) ~= "number" or requestStarted ~= requestStarted
						or os.clock() - requestStarted >= TRAVERSAL_SETTLE_SECONDS)
				if not reached and requestTimedOut then
					staleYield += 1
					if #staleNames < 6 then
						table.insert(staleNames, string.format(
							"%d -> %d exceeded the %ds request deadline while Computing"
							.. " on an empty waypoint list",
							pair.A, pair.B, TRAVERSAL_SETTLE_SECONDS))
					end
				end
				if reached then
					arrived += 1
				elseif stalled >= TRAVERSAL_STALL_FRAMES then
					blockedOut += 1
					if pair.Adjacent then connectedUnarrived += 1 end
					if #blockedNames < 6 then
						table.insert(blockedNames, string.format("%d -> %d blocked by %s (%s)",
							pair.A, pair.B, tostring(endBlocker), navigator:GetStatus()))
					end
					if #lines < 8 then
						table.insert(lines, string.format(
							"STOPPED %d -> %d after %d frames, %.0f of %.0f studs: %s, blocked by %s",
							pair.A, pair.B, iterations,
							horizontal(previous, start), routeLength,
							navigator:GetStatus(),
							tostring(navigator:GetDebugSnapshot().LastBlockedBy)))
					end
				else
					capHit += 1
					if pair.Adjacent then connectedUnarrived += 1 end
					if #capNames < 6 then
						table.insert(capNames, string.format(
							"%d -> %d ran out its iteration cap still moving", pair.A, pair.B))
					end
					if #lines < 8 then
						table.insert(lines, string.format(
							"ITERATION CAP %d -> %d: still moving after %d frames of a %.0f-stud route",
							pair.A, pair.B, iterations, routeLength))
					end
				end
			end
			navigator:Destroy()
			model:Destroy()
		end
	end

	note(report, string.format("pairs: %d selected, %d skipped as unstandable, %d walked"
		.. " (%d tight corridors, %d with a real floor-height change)",
		#wanted, skipped, attempted, tightPairs, elevationPairs))
	note(report, string.format("outcomes: %d arrived, %d stopped on geometry, %d hit the"
		.. " iteration cap, %d had no route at all (%d of those across an OPEN corridor)",
		arrived, blockedOut, capHit, routeless, mustRouteMissing))
	note(report, string.format("worst single Step: %.3f studs of travel (bound %.3f),"
		.. " %.3f studs of rise (bound %.3f = %d pieces x %.2f); %d routes climbed something",
		worstStride, strideBound, worstRise, riseBound, pieceCount, tuning.MaxStepHeight,
		climbedAtAll))
	for _, line in ipairs(lines) do note(report, line) end

	if not check(report, attempted >= 3,
		"enough node pairs are standable at both ends to be worth walking",
		string.format("%d of %d attempted, %d skipped", attempted, #wanted, skipped)) then
		return setBranch(report, "no-pairs")
	end
	check(report, tightPairs > 0 and elevationPairs > 0,
		"the sample covers the geometry it is meant to: the narrowest corridors on"
		.. " this map, and a route whose two ends stand at different floor heights",
		string.format("%d tight corridors, %d elevation changes", tightPairs, elevationPairs))
	check(report, graphRecoveryPlanned == 1,
		"the watchdog's forced graph route went through the same body-clearance"
		.. " centring installer as ordinary routes",
		string.format("%d graph recovery routes reported centring", graphRecoveryPlanned))
	check(report, mustRouteMissing == 0,
		"every pair whose rooms are joined by an OPEN corridor produced a route --"
		.. " NO_PATH is impossible there, because the graph fallback walks the same"
		.. " room graph this suite's own BFS walks",
		string.format("%d adjacent pairs had none", mustRouteMissing))
	check(report, starvedBudgets == 0,
		"every walked pair was given an iteration budget big enough to cover its own"
		.. " route -- a cap below the straight-walk frame count measures the harness,"
		.. " not the creature",
		string.format("%d starved: %s", starvedBudgets,
			#budgetNames > 0 and table.concat(budgetNames, "; ") or "none"))
	check(report, capHit == 0,
		"no traversal ran out of its iteration cap while it was still moving",
		string.format("%d did: %s", capHit,
			#capNames > 0 and table.concat(capNames, "; ") or "none recorded"))
	check(report, wallCrossings == 0,
		"no path segment crossed collidable geometry that is not entity ground",
		string.format("%d segments did", wallCrossings))
	check(report, longSteps == 0,
		"no single Step moved further than the navigator's own travel bound",
		string.format("%d exceeded %.3f studs, worst %.3f", longSteps, strideBound, worstStride))
	check(report, tallSteps == 0,
		"and none gained more height than its substep contract permits",
		string.format("%d exceeded %.3f studs, worst %.3f", tallSteps, riseBound, worstRise))
	check(report, skipped <= math.floor(#wanted * TRAVERSAL_MAX_SKIP_RATIO),
		"skipped pairs stayed under their ratio cap -- a sample that mostly could not"
		.. " stand up has measured nothing",
		string.format("%d of %d skipped, cap %d", skipped, #wanted,
			math.floor(#wanted * TRAVERSAL_MAX_SKIP_RATIO)))
	-- WHAT SHIPPED BROKEN: the bar here was "arrived >= 3", of however many were
	-- walked. Seven of ten pairs could end jammed against a prop and this suite
	-- still reported a pass -- the very failure the owner sees in play, scored as
	-- success. There is no number to clear now. Two rooms joined by an open
	-- corridor are two rooms the creature has to be able to walk between; if it
	-- cannot, that is the result, and it is named.
	check(report, connectedUnarrived == 0,
		"every pair whose rooms are joined by an OPEN corridor was walked all the way"
		.. " to its goal",
		string.format("%d of %d did not arrive: %s", connectedUnarrived, attempted,
			(#blockedNames + #capNames) > 0
				and table.concat({table.concat(blockedNames, "; "),
					table.concat(capNames, "; ")}, " | ")
				or "no blocker recorded"))
	check(report, blockedOut == 0,
		"no pair ended stopped on geometry -- a route the rig cannot finish is a"
		.. " failure, not a sample",
		string.format("%d stopped: %s", blockedOut,
			#blockedNames > 0 and table.concat(blockedNames, "; ") or "none recorded"))
	check(report, staleYield == 0,
		"and none ended with the navigator still Computing on an empty waypoint list"
		.. " (the stale-yield regression)",
		string.format("%d did: %s", staleYield,
			#staleNames > 0 and table.concat(staleNames, "; ") or "none recorded"))

	return report
	end)
end

-- ---------------------------------------------------------------------------
-- Adversarial -- the repaired failure modes themselves
-- ---------------------------------------------------------------------------

function Suite.Adversarial(manifest)
	local report = newReport("Slidemouth repaired failure modes")
	local tuning = Controller.MovementTuning
	local layout = manifest.Layout

	-- (1) The pump-scream fallback ranks candidates WITHOUT a room context.
	-- That call used to index a nil table and throw inside the warning path,
	-- which would have swallowed the scream entirely.
	local pumpHall = layout.PumpHalls and layout.PumpHalls[2]
	local positions = pumpHall and {hallCenter(pumpHall)} or {}
	local ok, result = pcall(Controller.EvaluateSpawn, manifest, positions, 2, true)
	check(report, ok, "ranking without a room context does not throw",
		not ok and tostring(result) or nil)
	if ok then
		check(report, type(result) == "table" and #result.Candidates > 0,
			"ranking without a room context still returns usable candidates",
			ok and tostring(#result.Candidates) or nil)
		-- And it still obeys the room rule it derived for itself.
		local occupied = 0
		for _, candidate in ipairs(result.Candidates) do
			if candidate.HallIndex and pumpHall
				and candidate.HallIndex == tonumber(pumpHall.Index) then
				occupied += 1
			end
		end
		check(report, occupied == 0,
			"the context-free ranking still excludes the occupied room",
			occupied .. " candidates were in it")
	end

	return protect(report, function(onCleanup)
	local groundParams = groundParamsFor(manifest)
	local function groundY(position)
		local hit = workspace:Raycast(position + Vector3.new(0, 40, 0),
			Vector3.new(0, -260, 0), groundParams)
		return hit and hit.Position.Y or nil
	end

	local folder = Instance.new("Folder")
	folder.Name = "Level 2 Slidemouth Adversarial Rigs"
	folder.Parent = manifest.World
	onCleanup("adversarial rig folder", function()
		if folder.Parent then folder:Destroy() end
		assert(folder.Parent == nil, "adversarial rig folder is still in the world")
	end)
	local geometry = Instance.new("Folder")
	geometry.Name = "Level 2 Slidemouth Adversarial Geometry"
	geometry.Parent = manifest.World
	onCleanup("adversarial geometry folder", function()
		if geometry.Parent then geometry:Destroy() end
		assert(geometry.Parent == nil, "adversarial geometry folder is still in the world")
	end)

	local function newRig(at, facing)
		local model = makeProbeModel(folder, tuning)
		local navigator = Navigator.new(model, manifest, tuning, {RuntimeFolder = folder})
		local placed = navigator:WarpTo(at, facing, true)
		return navigator, model, placed
	end

	-- Find a flat open lane to run the geometry probes in.
	--
	-- Flat ground is NOT enough, and assuming it was is what made this suite
	-- fail on some seeds for reasons that had nothing to do with the code under
	-- test: the biggest hall's centre line can run straight through a pool
	-- island, so the retreat rig had 12 studs to walk instead of 60 and the
	-- sweep rig's "clear once the slabs are gone" control was blocked by real
	-- geometry. The lane is now WALKED before it is accepted.
	local LANE_HALF = 30
	local LANE_REQUIRED_RUN = 55
	local function laneIsWalkable(start)
		local navigator, model, placed = newRig(start, Vector3.xAxis)
		local travelled = 0
		if placed then
			for _ = 1, 130 do
				local before = navigator:GetPosition()
				if not navigator:_placeFoot(before + Vector3.xAxis * .5, Vector3.xAxis) then break end
				travelled += horizontal(navigator:GetPosition(), before)
			end
		end
		navigator:Destroy()
		model:Destroy()
		return placed and travelled >= LANE_REQUIRED_RUN, travelled
	end

	local lane, floor
	local laneRun, rejected = 0, 0
	local halls = table.clone(layout.Halls)
	table.sort(halls, function(a, b) return (a.Area or 0) > (b.Area or 0) end)
	for _, hall in ipairs(halls) do
		local centre = hallCenter(hall)
		local surface = groundY(centre)
		if surface and (hall.Width or 0) >= 120 and (hall.Depth or 0) >= 120 then
			local flat = true
			for offset = -40, 40, 8 do
				local sample = groundY(centre + Vector3.new(offset, 0, 0))
				if not sample or math.abs(sample - surface) > .12 then flat = false break end
			end
			if flat then
				local walkable, travelled = laneIsWalkable(
					Vector3.new(centre.X - LANE_HALF, surface, centre.Z))
				if walkable then
					lane, floor, laneRun = centre, surface, travelled
					break
				end
				rejected += 1
			end
		end
	end
	if not check(report, lane ~= nil,
		string.format("found a flat lane the rig can actually walk %d studs of",
			LANE_REQUIRED_RUN),
		rejected .. " flat halls rejected as obstructed") then
		return setBranch(report, "no-lane")
	end
	note(report, string.format("probe lane: room centre (%.0f, %.0f), floor y=%.2f,"
		.. " %.1f studs of clear run (%d flat halls rejected as obstructed)",
		lane.X, lane.Z, floor, laneRun, rejected))

	-- (2) The retreat recovery walks BACK over ground it already stood on. It
	-- replaced a warp of up to 180 studs to a hidden anchor, which crossed
	-- walls and everything in between.
	do
		local start = Vector3.new(lane.X - LANE_HALF, floor, lane.Z)
		local navigator, model, placed = newRig(start, Vector3.xAxis)
		onCleanup("retreat rig model", function()
			if model.Parent then model:Destroy() end
		end)
		if check(report, placed, "the retreat rig can stand in the lane") then
			local visited = {navigator:GetPosition()}
			for _ = 1, 120 do
				local before = navigator:GetPosition()
				if not navigator:_placeFoot(before + Vector3.xAxis * .5, Vector3.xAxis) then break end
				table.insert(visited, navigator:GetPosition())
			end
			local advanced = navigator:GetPosition()
			local forward = horizontal(advanced, start)
			check(report, forward > 20, "the rig walked far enough to build a trail",
				string.format("%.1f studs", forward))
			check(report, navigator:GetTrailLength() > 0, "the trail recorded positions",
				tostring(navigator:GetTrailLength()))

			local retreated = navigator:Retreat(14)
			local after = navigator:GetPosition()
			check(report, retreated > 0, "the retreat actually moves the rig",
				string.format("%.2f studs", retreated))
			check(report, retreated <= 14 + .01,
				"the retreat never exceeds its bound",
				string.format("%.2f studs", retreated))
			check(report, horizontal(after, advanced) <= 14 + .5,
				"the rig ends within the bound of where it started backing out",
				string.format("%.2f studs", horizontal(after, advanced)))
			-- Backtracking, not relocation: the end point is somewhere it stood.
			local nearest = math.huge
			for _, position in ipairs(visited) do
				nearest = math.min(nearest, horizontal(after, position))
			end
			check(report, nearest <= 1,
				"the rig ends on ground it had already occupied (not a teleport)",
				string.format("%.2f studs from the nearest visited point", nearest))
			check(report, math.abs(after.Y - advanced.Y) <= tuning.MaxStepHeight,
				"the retreat gains no height it did not climb",
				string.format("%.2f studs", math.abs(after.Y - advanced.Y)))
		end
		navigator:Destroy()
		model:Destroy()
	end

	-- (3) The horizontal sweep may cast past a bounded number of step-height
	-- ledges. Exhausting that budget used to fall through to "clear", proving
	-- nothing about whatever was still in front of the rig.
	do
		local start = Vector3.new(lane.X - LANE_HALF, floor, lane.Z)
		local navigator, model, placed = newRig(start, Vector3.xAxis)
		onCleanup("sweep rig model", function()
			if model.Parent then model:Destroy() end
		end)
		if check(report, placed, "the sweep rig can stand in the lane") then
			local slabs = {}
			-- Eight thin, ground-tagged, step-height slabs in a row: each one is
			-- individually steppable, so each consumes one exclusion. They start
			-- BEYOND the rig's own body box -- a shapecast ignores whatever it is
			-- already inside, so slabs placed under the rig would never be swept
			-- at all and the budget would never be reached.
			local firstSlab = start.X + tuning.AgentRadius + 3
			for index = 1, 8 do
				local slab = Instance.new("Part")
				slab.Name = "Probe Sweep Slab " .. index
				slab.Anchored = true
				slab.CanCollide = true
				slab.Transparency = 1
				slab.Size = Vector3.new(.5, 2, 60)
				slab.CFrame = CFrame.new(firstSlab + (index - 1) * 1.5, floor + 1, lane.Z)
				slab:SetAttribute("Level2_EntityGround", true)
				slab.Parent = geometry
				table.insert(slabs, slab)
			end
			local target = Vector3.new(firstSlab + 8 * 1.5 + tuning.AgentRadius, floor, lane.Z)
			local clear = navigator:_clearAdvance(target)
			check(report, clear == false,
				"a sweep that runs out of exclusions fails closed",
				"returned " .. tostring(clear) .. ", blocked by "
					.. tostring(navigator.LastBlockedBy))
			for _, slab in ipairs(slabs) do slab:Destroy() end
			-- Sanity: with the slabs gone the same advance is allowed again, so
			-- the check above is measuring the budget and not a broken rig.
			check(report, navigator:_clearAdvance(target) == true,
				"the same advance is clear once the slabs are removed",
				tostring(navigator.LastBlockedBy))
		end
		navigator:Destroy()
		model:Destroy()
	end

	return report
	end)
end

-- ---------------------------------------------------------------------------
-- PauseIsolation -- borrowing a DELIBERATELY LOADED incumbent
-- ---------------------------------------------------------------------------
--
-- LiveSpawn proves the pause works on whatever session happens to exist. That is
-- not enough: the ways the old suspend corrupted an incumbent were all invisible
-- on a session that had nothing pending. Every one of them needed a creature
-- that was in the MIDDLE of something.
--
-- So this suite arms the incumbent first -- a pump scream due during the borrow,
-- deadlines about to expire, a navigator mid-request, and both a present and an
-- absent replicated attribute -- then borrows it, throws inside the borrow,
-- moves the creature and the player, breaks the resume on purpose, and proves
-- every one of those survived.
--
-- WHAT SHIPPED BROKEN IN THIS SUITE, and what the new shape catches:
--
--   * the cleanup stopped whatever was ACTIVE. On the success path the resume
--     had already made the borrowed incumbent active again, so the cleanup
--     destroyed the very session it had just given back -- and the only residue
--     assertion used `<=`, which reads a deletion as clean. Ownership is now
--     explicit: this suite stops ONLY sessions it started, by handle, and an
--     audit registered FIRST (and therefore run LAST) proves the pre-existing
--     incumbent is still the same session, model, folder and navigator.
--   * the "everything was restored" baseline was read AFTER the arm, so it
--     compared the armed state against itself. There are now two baselines: the
--     armed one for the pause/resume, and a TRUE pre-arm one for the disarm.
--   * "the old Blocked binding was disconnected" was vacuous -- _requestPath
--     disconnects at its head and the arm leaves a request in flight, so the
--     binding was already gone before the pause. The blocked half of a resume is
--     now exercised for real, in blocked MODE and on a rig navigator.
--   * "the pending scream did NOT fire while paused" was vacuous -- the reader
--     took activeSession, which a pause nils, so it answered "nothing fired"
--     because there was nothing to ask. The handle is passed now, and the count
--     is asserted as 0 rather than -1.
--   * nothing measured elapsed time around the scream, so restoring the
--     ABSOLUTE deadline instead of the remaining delay passed.
function Suite.PauseIsolation(manifest)
	local report = newReport("Slidemouth pause isolation (a loaded incumbent)")
	if not (manifest and manifest.World and manifest.World.Parent) then
		return setBranch(report, "no-world")
	end

	local hadSession = Controller.IsRunning()
	local state = level2State()
	if not check(report, state ~= nil, "the replicated Level 2 state folder exists") then
		return setBranch(report, "no-state")
	end

	return protect(report, function(onCleanup)
		local stateBefore = attributeSnapshot(state)
		local worldBefore = attributeSnapshot(workspace)
		local playersBefore = {}
		for _, other in ipairs(Players:GetPlayers()) do
			local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			playersBefore[other] = {
				Attributes = attributeSnapshot(other),
				-- The controller gives the chase ATTRIBUTES back; where the player is
				-- standing is this suite's own to restore, exactly as LiveSpawn does.
				-- No pause handle carries a CFrame.
				CFrame = otherRoot and otherRoot.CFrame or nil,
			}
		end
		local runtimeBefore = #runtimeFolders(manifest)
		local runtimeWithIncumbent = runtimeBefore
		local syntheticSession, borrowSession
		local handle, blockedHandle, armed
		local refs, refsPreArm
		local rigFolder, rig

		-- CLEANUP ORDER. They run LIFO, so this list is the REVERSE of the order
		-- they run in: players, then Workspace, then the controller, then the
		-- replicated state -- the order LiveSpawn documents, because the controller
		-- has to compare itself against a Workspace that is already restored, and
		-- the resumed session's own republishing has to happen before the state map
		-- is put back over it. Workspace used to be restored AFTER the controller
		-- cleanup here, so a resumed incumbent's first heartbeat ran against this
		-- test's Level2Pumps instead of the round's.
		--
		-- The ownership audit is registered FIRST and therefore runs LAST. It is
		-- the only place "the incumbent survived the WHOLE protected cleanup" can
		-- be asserted from: protect runs every cleanup before it returns, so
		-- nothing in the body can observe the world after the controller cleanup.
		onCleanup("incumbent ownership audit", function()
			local after = Controller.DebugSessionRefs()
			if hadSession then
				assert(Controller.IsRunning(),
					"the pre-existing incumbent is not running after the cleanup")
				assert(after ~= nil, "the pre-existing incumbent is unreachable after the cleanup")
				assert(refs == nil or after.Session == refs.Session,
					"the incumbent is a different session table than the one borrowed")
				assert(refs == nil or after.Model == refs.Model,
					"the incumbent is holding a different Model instance")
				assert(refs == nil or after.RuntimeFolder == refs.RuntimeFolder,
					"the incumbent is holding a different runtime folder")
				assert(refs == nil or after.Navigator == refs.Navigator,
					"the incumbent is holding a different navigator")
				assert(after.Model == nil or after.Model.Parent ~= nil,
					"the incumbent's creature was left out of the world")
			else
				assert(not Controller.IsRunning(),
					"a session this suite started outlived the suite")
				assert(after == nil, "a session this suite started is still reachable")
			end
			assert(Controller.DebugParkedCount() == 0,
				"a session was left parked: " .. tostring(Controller.DebugParkedCount()))
			local residual = Controller.DebugResidue()
			assert(residual.PauseDepth == 0 and residual.OrphanRuntimeFolders == 0,
				string.format("borrow debt left behind: depth %d, %d orphan runtime folders",
					residual.PauseDepth, residual.OrphanRuntimeFolders))
			assert(#runtimeFolders(manifest) == runtimeBefore,
				string.format("%d runtime folders, %d before",
					#runtimeFolders(manifest), runtimeBefore))
		end)
		onCleanup("pause probe rigs", function()
			if rig then rig:Destroy() end
			if rigFolder and rigFolder.Parent then rigFolder:Destroy() end
			assert(rigFolder == nil or rigFolder.Parent == nil,
				"the pause probe rig folder is still in the world")
		end)
		onCleanup("replicated Level 2 state", function()
			restoreAttributes(state, stateBefore, "Level 2 State")
		end)
		onCleanup("controller session", function()
			Controller.DebugDisarmPauseTest()
			-- ONLY sessions this suite started, and by reference. The unconditional
			-- Stop() this used to run killed whatever was ACTIVE -- which after a
			-- successful resume is the incumbent itself.
			if borrowSession then
				Controller.Stop(borrowSession)
				borrowSession = nil
			end
			if blockedHandle and not blockedHandle.Consumed then
				local resumed, err = Controller.DebugResumeSession(blockedHandle)
				assert(resumed, "the blocked-mode borrow could not be given back: " .. tostring(err))
			end
			if handle and not handle.Consumed then
				local resumed, err = Controller.DebugResumeSession(handle)
				assert(resumed, "the paused incumbent could not be given back: " .. tostring(err))
			end
			if syntheticSession then
				Controller.Stop(syntheticSession)
				syntheticSession = nil
			end
			assert(Controller.IsRunning() == hadSession,
				"the controller's running state was not restored")
			assert(#runtimeFolders(manifest) == runtimeBefore,
				string.format("a Slidemouth runtime folder was left in the world (%d, %d before)",
					#runtimeFolders(manifest), runtimeBefore))
		end)
		onCleanup("workspace attributes", function()
			restoreAttributes(workspace, worldBefore, "Workspace")
		end)
		onCleanup("player state", function()
			for other, saved in pairs(playersBefore) do
				if other.Parent == Players then
					restoreAttributes(other, saved.Attributes, other.Name)
					local otherRoot = other.Character
						and other.Character:FindFirstChild("HumanoidRootPart")
					if otherRoot and saved.CFrame then otherRoot.CFrame = saved.CFrame end
				end
			end
		end)

		-- ---------------------------------------------------------------
		-- (0) The navigator's pause/resume CONTRACT, on a rig of our own.
		-- ---------------------------------------------------------------
		-- These are the assertions a live borrow cannot make honestly. A real
		-- incumbent repaths every RepathInterval, so "the binding the pause
		-- recorded is the one the resume put back" is a race against its own
		-- heartbeat, and "a request with no goal settles" cannot be staged at all
		-- because the arm always leaves a goal behind. A rig navigator holds
		-- still, and a Path from PathfindingService carries a real Blocked signal
		-- without ever having to compute a route -- which is everything
		-- _bindBlocked needs.
		rigFolder = Instance.new("Folder")
		rigFolder.Name = "Level 2 Slidemouth Pause Probe Rigs"
		rigFolder.Parent = manifest.World
		local rigModel = makeProbeModel(rigFolder, Controller.MovementTuning)
		local rigBuilt, rigOrError = pcall(Navigator.new, rigModel, manifest,
			Controller.MovementTuning, {RuntimeFolder = rigFolder})
		rig = rigBuilt and rigOrError or nil
		check(report, rig ~= nil,
			"a rig navigator stands in for the incumbent's, so the pause/resume"
			.. " contract can be asserted without racing a live heartbeat",
			not rigBuilt and tostring(rigOrError) or nil)

		-- A distinct value per field, and a DIFFERENT distinct value to scribble
		-- over it with, so a Restore that walks a shortened list leaves the
		-- scribble behind and is named.
		local rigProbeValues = {
			Waypoints = {Vector3.new(11, 12, 13)},
			WaypointIndex = 4,
			Goal = Vector3.new(21, 22, 23),
			LastRequestedGoal = Vector3.new(31, 32, 33),
			Status = "PROBE_STATUS",
			LastFailure = "probe failure",
			LastBlockedBy = "probe blocker",
			Facing = Vector3.new(0, 0, -1),
			FootPosition = Vector3.new(41, 42, 43),
			HasGrounded = true,
			LastSafeFoot = Vector3.new(51, 52, 53),
			LastSafeFacing = Vector3.new(1, 0, 0),
			TrailFrozen = true,
			PivotAboveFoot = 5.5,
			Trail = {Vector3.new(61, 62, 63)},
		}
		local rigScribbleValues = {
			Waypoints = {},
			WaypointIndex = 99,
			Goal = Vector3.new(-1, -1, -1),
			LastRequestedGoal = Vector3.new(-2, -2, -2),
			Status = "SCRIBBLED",
			LastFailure = "scribbled",
			LastBlockedBy = "scribbled",
			Facing = Vector3.new(0, 0, 1),
			FootPosition = Vector3.new(-3, -3, -3),
			HasGrounded = false,
			LastSafeFoot = Vector3.new(-4, -4, -4),
			LastSafeFacing = Vector3.new(-1, 0, 0),
			TrailFrozen = false,
			PivotAboveFoot = -9,
			Trail = {},
		}
		local function sameFieldValue(want, got)
			if type(want) == "table" then
				if type(got) ~= "table" or #got ~= #want then return false end
				for index = 1, #want do
					if got[index] ~= want[index] then return false end
				end
				return true
			end
			return got == want
		end
		local function applyRigFields(values)
			if not rig then return end
			for _, name in ipairs(EXPECTED_NAVIGATOR_PAUSE_FIELDS) do
				local value = values[name]
				rig[name] = type(value) == "table" and table.clone(value) or value
			end
		end
		local function rigFieldsWrong(expected)
			local wrong = {}
			if not rig then return {"no rig navigator"} end
			for _, name in ipairs(EXPECTED_NAVIGATOR_PAUSE_FIELDS) do
				if not sameFieldValue(expected[name], rig[name]) then table.insert(wrong, name) end
			end
			return wrong
		end

		applyRigFields(rigProbeValues)
		if rig then
			rig.LastPathAt = 12345.5
			rig.Computing = true
		end
		local rigSnapshot = rig and rig:Snapshot() or nil
		applyRigFields(rigScribbleValues)
		if rig then
			rig.LastPathAt = -1
			rig.Computing = false
		end
		local rigRestored = rig ~= nil and rigSnapshot ~= nil and rig:Restore(rigSnapshot) == true
		local roundTripWrong = rigFieldsWrong(rigProbeValues)
		check(report, rigRestored and #roundTripWrong == 0
			and rig.LastPathAt == 12345.5 and rig.Computing == true,
			"Navigator:Restore(Snapshot()) round-trips every declared pause field,"
			.. " plus LastPathAt and Computing",
			#roundTripWrong > 0 and table.concat(roundTripWrong, ", ") or nil)
		note(report, "row 27: a hard-coded shorter field list in either loop (B:881 / B:911)"
			.. " leaves the scribble behind on the fields it dropped")

		local rigPath = PathfindingService:CreatePath()
		if rig then
			rig.Computing = true
			rig.RequestId = 77
			rig:_bindBlocked(rigPath)
		end
		local rigIdBefore = rig and rig.RequestId or nil
		local rigBoundBefore = rig ~= nil and rig:HasBlockedConnection()
		local rigUndisturbed = rig and rig:Snapshot() or nil
		check(report, rigUndisturbed ~= nil and rigBoundBefore == true
			and rig.Computing == true and rig.RequestId == rigIdBefore
			and rig:HasBlockedConnection() == true,
			"Snapshot() leaves a live request undisturbed -- no id bump, no disconnect",
			rig and string.format("id %s -> %s", tostring(rigIdBefore), tostring(rig.RequestId)) or nil)
		note(report, "row 26: a Snapshot that bumped RequestId or called _clearBlocked (B:879)"
			.. " would invalidate the very request the arm is arming")

		-- Computing goes back to false first, so this pause exercises the BINDING
		-- half on its own: a WasComputing record restarts the request, and the
		-- restart legitimately replaces the binding it just restored.
		if rig then rig.Computing = false end
		local rigPreRecord = rig and rig:Snapshot() or nil
		local rigRecord = rig and rig:Pause() or nil
		local recordWrong = {}
		if rigPreRecord and rigRecord then
			for _, name in ipairs(EXPECTED_NAVIGATOR_PAUSE_FIELDS) do
				if not sameFieldValue(rigPreRecord.Fields[name], rigRecord.Fields[name]) then
					table.insert(recordWrong, name)
				end
			end
		end
		check(report, rigRecord ~= nil and #recordWrong == 0
			and rigRecord.LastPathAt == rigPreRecord.LastPathAt
			and rigRecord.Computing == rigPreRecord.Computing,
			"Pause()'s field record is exactly Snapshot()'s",
			#recordWrong > 0 and table.concat(recordWrong, ", ") or nil)
		note(report, "row 28: an inline loop over a subset inside Pause (B:922) drifts from"
			.. " Snapshot the moment a field is added to one of them")

		check(report, rigRecord ~= nil and rigRecord.HadBlockedConnection == true
			and rigRecord.BlockedPath == rigPath,
			"Pause() records the live Blocked PATH, not merely the fact of one",
			rigRecord and tostring(rigRecord.BlockedPath) or nil)
		note(report, "row 23: recording only the boolean is why HadBlockedConnection sat"
			.. " unread for its whole life -- there was nothing to rebind to")
		check(report, rig ~= nil and rig:HasBlockedConnection() == false and rig.BlockedPath == nil,
			"and Pause() then drops the binding AND the Path together",
			rig and tostring(rig.BlockedPath) or nil)
		note(report, "row 23: dropping `self.BlockedPath = nil` from _clearBlocked (B:594)"
			.. " leaves a stale Path that a later resume would happily rebind to")

		local rigResumed, rigResumeWhy, rigOutcome
		if rig and rigRecord then
			rigResumed, rigResumeWhy, rigOutcome = rig:Resume(rigRecord, os.clock())
		end
		check(report, rigResumed == true and rigOutcome ~= nil
			and rigOutcome.BlockedRestored == true
			and rigOutcome.RequestRestarted == false and rigOutcome.RequestSettled == false
			and rig:HasBlockedConnection() == true
			and rig:GetFullDebugSnapshot().HasBlockedConnection == true,
			"Resume() rebuilds the recorded binding, and with nothing to restart it"
			.. " stays live -- and the snapshot agrees that it is",
			tostring(rigResumeWhy))
		note(report, "rows 22 and 24: deleting the rebind block (B:986) or letting the"
			.. " snapshot and HasBlockedConnection() read different fields breaks this")

		-- An invalid record must be refused BEFORE a single field is written.
		local rigGuardRecord = rig and rig:Snapshot() or nil
		applyRigFields(rigScribbleValues)
		local rigRefused, rigRefusedWhy
		if rig and rigGuardRecord then rigRefused, rigRefusedWhy = rig:Resume(rigGuardRecord) end
		local guardWrong = rigFieldsWrong(rigScribbleValues)
		check(report, rigRefused == false
			and rigRefusedWhy == "pause record has an invalid LastPathAge"
			and #guardWrong == 0,
			"Resume() refuses a record with an invalid LastPathAge and writes nothing",
			string.format("%s / %s", tostring(rigRefusedWhy),
				#guardWrong > 0 and table.concat(guardWrong, ", ") or "no fields touched"))
		note(report, "row 25: without the validation (B:975) the arithmetic throws with"
			.. " every field already restored -- a half-resumed navigator plus an error")

		if rig then
			rig.Computing = true
			rig.LastRequestedGoal = nil
			rig.LastPathAt = os.clock()
		end
		local rigSettleRecord = rig and rig:Pause() or nil
		local rigSettleOk, rigSettleOutcome
		if rig and rigSettleRecord then
			local _
			rigSettleOk, _, rigSettleOutcome = rig:Resume(rigSettleRecord, os.clock())
		end
		check(report, rigSettleOk == true and rigSettleOutcome ~= nil
			and rigSettleOutcome.RequestSettled == true
			and rigSettleOutcome.RequestRestarted == false
			and rig.Computing == false
			and rig.LastFailure == "the in-flight path request was invalidated by a pause"
			and rig.LastPathAt == -math.huge,
			"a WasComputing record with no goal SETTLES the request explicitly",
			rig and tostring(rig.LastFailure) or nil)
		note(report, "row 21: deleting the settle branch (B:1004-1007) leaves Computing false"
			.. " with no reason and a RepathInterval measured from a dead request")

		if rig then
			rig.Computing = true
			rig.LastRequestedGoal = Vector3.new(31, 32, 33)
			rig.LastPathAt = os.clock()
			rig:_bindBlocked(rigPath)
		end
		local rigRestartRecord = rig and rig:Pause() or nil
		local rigRestartOk, rigRestartOutcome
		if rig and rigRestartRecord then
			local _
			rigRestartOk, _, rigRestartOutcome = rig:Resume(rigRestartRecord, os.clock())
		end
		check(report, rigRestartOk == true and rigRestartOutcome ~= nil
			and rigRestartOutcome.RequestRestarted == true
			and rigRestartOutcome.RequestSettled == false
			and rigRestartOutcome.BlockedRestored == true
			and rig.Computing == true
			and rig:HasBlockedConnection() == false,
			"a WasComputing record with a goal RESTARTS it, and the restart supersedes"
			.. " the binding the same call had just rebound")
		note(report, "row 20: deleting the restart (B:1001) leaves a navigator that believes"
			.. " in a request the pause already killed. BlockedRestored reports what THIS")
		note(report, "call restored, not what survived the restart -- which is why the")
		note(report, "'blocked' half is asserted in blocked MODE below and never here.")

		if rig then rig:Stop() end
		local rigCleared = rig and rig:Pause() or nil
		check(report, rig ~= nil and rig:HasBlockedConnection() == false
			and rig:GetFullDebugSnapshot().HasBlockedConnection == false
			and rigCleared ~= nil and rigCleared.HadBlockedConnection == false
			and rigCleared.BlockedPath == nil,
			"a cleared binding leaves no stale Path for a later resume to rebind,"
			.. " and the snapshot agrees it is gone")

		-- ---------------------------------------------------------------
		-- (1) A live, loaded incumbent.
		-- ---------------------------------------------------------------
		armRound()
		local player = Players:GetPlayers()[1]
		if player then player:SetAttribute("InRound", true) end

		if not hadSession then
			syntheticSession = Controller.Start(manifest, manifest.Generation or 1)
		end
		if not check(report, Controller.IsRunning(), "an incumbent session is running") then
			return setBranch(report, "no-session")
		end
		if not check(report, player ~= nil, "a player is present for the creature to hunt") then
			return setBranch(report, "no-player")
		end
		runtimeWithIncumbent = #runtimeFolders(manifest)

		-- ---------------------------------------------------------------
		-- (2) The TRUE pre-arm world, read before the arm mutates anything.
		-- ---------------------------------------------------------------
		local presentName = "Level2_SlidemouthPauseProbePresent"
		local absentName = "Level2_SlidemouthPauseProbeAbsent"
		local preArmClock = os.clock()
		local preArm = Controller.GetFullDebugSnapshot()
		local preArmPumps = workspace:GetAttribute("Level2Pumps")
		local preArmPresent = state:GetAttribute(presentName)
		local preArmAbsent = state:GetAttribute(absentName)
		refsPreArm = Controller.DebugSessionRefs()
		check(report, refsPreArm ~= nil and type(refsPreArm.Session) == "table",
			"the controller hands out the RAW session references identity needs",
			refsPreArm == nil and "DebugSessionRefs returned nil" or nil)
		local preResidue = Controller.DebugResidue()
		check(report, Controller.DebugParkedCount() == 0 and Controller.DebugIsPaused() == false
			and preResidue.Parked == 0 and preResidue.PauseDepth == 0
			and preResidue.OrphanRuntimeFolders == 0,
			"nothing is parked, and nothing owes a borrow, before this suite borrows",
			string.format("%d parked, depth %d, %d orphan folders",
				preResidue.Parked, preResidue.PauseDepth, preResidue.OrphanRuntimeFolders))

		-- ---------------------------------------------------------------
		-- (3) ARM the incumbent, through the controller's own debug seam.
		-- ---------------------------------------------------------------
		--
		-- OWNERSHIP, and why this call site may pass the sanctioned escape.
		--
		-- WHAT SHIPPED BROKEN, and what this replaces: DebugArmForPauseTest used
		-- to raise Level2Pumps to the spawn pump on whatever production session
		-- happened to be running and wait for a creature to grow -- a harness
		-- permanently advancing somebody's live round, because a creature cannot
		-- be un-spawned. The controller now REFUSES that mutation unless the
		-- caller passes options.AllowIrreversibleSpawn = true, and on a freshly
		-- built world (Level2Pumps = 0, nothing spawned) that refusal is what this
		-- suite met: the whole run took the no-arm branch and the total fell from
		-- 296 checks to 196. The refusal is the controller working.
		--
		-- The honest resolution is not to pass the flag, and not to pass it
		-- blindly either. RunAll is a Studio-only harness driven against a world
		-- the operator BUILT for the test and tears down afterwards, so it
		-- legitimately owns that world -- but only when it can SHOW it does. The
		-- evidence, read from snapshots taken before this suite mutated anything:
		--
		--   * no round was already in progress (workspace.RoundActive was not
		--     true when this probe started), and
		--   * no player was already marked InRound.
		--
		-- Both come from worldBefore/playersBefore, captured at the top of this
		-- body ahead of armRound() and ahead of the InRound write in section (1),
		-- so the suite cannot manufacture its own permission. Neither reading is
		-- about the CONTROLLER: Adapter.Build() starts a session of its own, so
		-- "no incumbent" would be evidence of nothing. Both are about whether a
		-- human is playing this world right now.
		--
		-- With the evidence absent the flag is withheld, the arm refuses, and the
		-- no-arm branch below reports exactly that instead of passing silently.
		-- With it present the flag is passed, the cost is DECLARED in
		-- armed.Irreversible, the pump count the arm raises is restored by the
		-- disarm, and section (9) asserts that restoration through the
		-- controller's own residue reader.
		local ownershipMissing = {}
		if worldBefore.RoundActive == true then
			table.insert(ownershipMissing, "workspace.RoundActive was already true")
		end
		local inRoundBefore = 0
		for _, saved in pairs(playersBefore) do
			if saved.Attributes and saved.Attributes.InRound == true then
				inRoundBefore += 1
			end
		end
		if inRoundBefore > 0 then
			table.insert(ownershipMissing,
				inRoundBefore .. " player(s) were already marked InRound")
		end
		local suiteOwnsWorld = #ownershipMissing == 0
		note(report, suiteOwnsWorld
			and ("world ownership: no round was in progress and nobody was InRound before"
				.. " this probe, so the forced-spawn opt-in is passed explicitly")
			or ("world ownership NOT established (" .. table.concat(ownershipMissing, "; ")
				.. "); the forced-spawn opt-in is WITHHELD"))

		local armError
		armed, armError = Controller.DebugArmForPauseTest({
			ScreamPump = 1,
			ScreamInSeconds = 6,
			DeadlineInSeconds = 0.75,
			PresentAttribute = presentName,
			AbsentAttribute = absentName,
			NavigatorMode = "computing",
			-- Passed on the evidence above and never otherwise. It is inert
			-- whenever the round has already reached the spawn pump: the
			-- controller's refusal is scoped to the MUTATION, so an incumbent that
			-- has already spawned is armed without this ever being consulted.
			AllowIrreversibleSpawn = suiteOwnsWorld,
		})
		if not check(report, armed ~= nil, "the incumbent can be armed for this test", armError) then
			-- Not a silent pass. The only refusal that can reach here is B9's, and
			-- it is CORRECT exactly when this suite declined to claim the world. If
			-- the suite DID claim it and was still refused, that is a fault in the
			-- arm or in the evidence, and it fails here.
			check(report, suiteOwnsWorld == false,
				"and the refusal is the one an unowned world is supposed to produce:"
				.. " the suite would not force an irreversible spawn on somebody's round",
				suiteOwnsWorld
					and ("the suite DID establish ownership and passed"
						.. " AllowIrreversibleSpawn, so this refusal is a real fault: "
						.. tostring(armError))
					or table.concat(ownershipMissing, "; "))
			return setBranch(report, "no-arm")
		end
		check(report, armed.NavigatorMode == "computing",
			"and armed in the mode it was asked for", tostring(armed.NavigatorMode))
		local armResidue = Controller.DebugPauseProbeResidue(armed)
		check(report, armResidue.Probe == true
			and armResidue.AllowedIrreversibleSpawn == suiteOwnsWorld
			-- A pre-image taken ACROSS a mutation is legal on exactly one path --
			-- the opted-in forced spawn, where the arm deliberately re-reads
			-- everything but Level2Pumps AFTER the spawn wait so a disarm rewinds
			-- the arm and not the round. Anywhere else it would mean the arm wrote
			-- something before recording what it wrote over.
			and (suiteOwnsWorld or armResidue.CapturedBeforeAnyMutation == true),
			"the opt-in the controller recorded is exactly the one the suite passed,"
			.. " and a pre-image taken across a mutation happens only on the path"
			.. " that is allowed to take one",
			string.format("owned %s (%s), opt-in recorded %s, pre-image clean %s",
				tostring(suiteOwnsWorld),
				#ownershipMissing > 0 and table.concat(ownershipMissing, "; ")
					or "no round in progress, nobody InRound",
				tostring(armResidue.AllowedIrreversibleSpawn),
				tostring(armResidue.CapturedBeforeAnyMutation)))
		note(report, "B9: passing AllowIrreversibleSpawn unconditionally here would make this"
			.. " suite the thing that advances a live round -- the exact fault the"
			.. " controller's refusal was written to stop")
		check(report, armed.ScreamDueIn ~= nil and armed.ScreamDueIn > 0,
			"a pump scream is pending and due during the borrow",
			armed.ScreamDueIn and string.format("%.1fs", armed.ScreamDueIn) or "none")
		check(report, armed.NavigatorRequesting == true,
			"the navigator has a request in flight", tostring(armed.NavigatorRequesting))
		check(report, state:GetAttribute(armed.PresentAttribute) ~= nil,
			"a replicated attribute is PRESENT before the borrow")
		check(report, state:GetAttribute(armed.AbsentAttribute) == nil,
			"and another is deliberately ABSENT before the borrow")

		-- The arm's own restore set has to be the world as it was BEFORE the arm,
		-- not a copy of the arm's own mutations. Everything the disarm is later
		-- asserted against hangs off this: armed.Restore is compared to readings
		-- taken above, and the post-disarm world is compared to armed.Restore.
		--
		-- WHICH comparison is the honest one depends on the path the arm took, and
		-- the arm SAYS which: Restore.CapturedBeforeAnyMutation is true only when
		-- the WHOLE pre-image was read before the arm wrote anything. On the
		-- opted-in forced-spawn path it is deliberately false, because the arm
		-- re-reads everything except Level2Pumps AFTER waiting up to fifteen
		-- seconds for the creature -- fifteen seconds in which the incumbent
		-- legitimately advances its own deadlines, scream tables and pump
		-- bookkeeping. Demanding that re-read match a pre-wait snapshot would be
		-- demanding the exact bug the second readPreImage exists to prevent: a
		-- disarm that rewinds the ROUND's progress instead of the ARM's.
		--
		-- Level2Pumps and both probe attributes are compared the same way on BOTH
		-- paths, because both are read before any mutation either way -- the
		-- raising path keeps the pump reading from the very first pass on purpose,
		-- since that raise is the arm's own to undo.
		local recordedWrong = {}
		local preImageIsPreArm = armed.Restore.CapturedBeforeAnyMutation == true
		if armed.Restore.Level2Pumps ~= preArmPumps then
			table.insert(recordedWrong, string.format("Level2Pumps %s vs %s",
				tostring(armed.Restore.Level2Pumps), tostring(preArmPumps)))
		end
		if armed.Restore.StateAttributes[presentName] ~= preArmPresent
			or armed.Restore.StateAttributes[absentName] ~= preArmAbsent then
			table.insert(recordedWrong, "probe attributes")
		end
		if preImageIsPreArm then
			if armed.Restore.LastPumps ~= preArm.Values.LastPumps then
				table.insert(recordedWrong, string.format("LastPumps %s vs %s",
					tostring(armed.Restore.LastPumps), tostring(preArm.Values.LastPumps)))
			end
			for _, name in ipairs(EXPECTED_DEADLINE_FIELDS) do
				if not timerAgrees(expectedTimerReading(armed.Restore.Deadlines[name], preArmClock),
					preArm.Timers[name]) then
					table.insert(recordedWrong, name)
				end
			end
			if not timerAgrees(expectedTimerReading(armed.Restore.ProgressAt, preArmClock),
				preArm.Timers.ProgressAt) then
				table.insert(recordedWrong, "ProgressAt")
			end
		else
			-- The re-read path. Two things still have to be true, and together they
			-- are as strong a claim as the pre-arm comparison above.
			--
			-- (a) the pre-image is the world AFTER the forced spawn, not the stale
			--     one from before it. A spawn advances LastPumps to the spawn pump,
			--     so a restore set still carrying the pre-wait value is a restore
			--     set that would rewind the round -- which is exactly what deleting
			--     the second readPreImage produces.
			-- (b) it is not a copy of what the arm went on to WRITE. Every field
			--     the arm applies is compared against the arm's own applied value
			--     and must differ, which is the property the pre-arm comparison
			--     was buying on the other path.
			local applied = armed.Applied or {}
			if type(armed.Restore.LastPumps) ~= "number"
				or armed.Restore.LastPumps < EXPECTED_SPAWN_PUMPS then
				table.insert(recordedWrong, string.format(
					"LastPumps %s never reached the spawn pump, so the pre-image predates"
					.. " the forced spawn", tostring(armed.Restore.LastPumps)))
			end
			if applied.LastPumps ~= nil and armed.Restore.LastPumps == applied.LastPumps then
				table.insert(recordedWrong, "LastPumps is a copy of the arm's own write")
			end
			for _, name in ipairs(EXPECTED_DEADLINE_FIELDS) do
				local appliedValue = (applied.Deadlines or {})[name]
				if appliedValue ~= nil and armed.Restore.Deadlines[name] == appliedValue then
					table.insert(recordedWrong, name .. " is a copy of the arm's own write")
				end
			end
			if applied.ProgressAt ~= nil and armed.Restore.ProgressAt == applied.ProgressAt then
				table.insert(recordedWrong, "ProgressAt is a copy of the arm's own write")
			end
		end
		check(report, #recordedWrong == 0,
			"the arm recorded a pre-image the disarm can honestly restore from, under"
			.. " the contract the arm's own CapturedBeforeAnyMutation declares",
			string.format("%s pre-image: %s",
				preImageIsPreArm and "whole-world" or "re-read-after-forced-spawn",
				#recordedWrong > 0 and table.concat(recordedWrong, ", ") or "clean"))
		note(report, "row 29: this is the half that makes the post-disarm comparison mean"
			.. " something -- without it the restore set could be a copy of the arm itself")
		note(report, "B9 proof: remove the second readPreImage and the re-read branch above"
			.. " sees LastPumps still below the spawn pump -- a disarm about to rewind"
			.. " the round rather than the arm")

		refs = Controller.DebugSessionRefs()
		check(report, refs ~= nil and refs.Model ~= nil and refs.Navigator ~= nil
			and refs.RuntimeFolder ~= nil and refs.Model.Parent ~= nil,
			"the arm left a real creature to borrow -- model, navigator and folder",
			refs == nil and "no references" or nil)
		check(report, refs ~= nil and refsPreArm ~= nil
			and refs.Session == refsPreArm.Session
			and refs.RuntimeFolder == refsPreArm.RuntimeFolder,
			"and it is the same session and runtime folder that was there before the arm")
		note(report, "the MODEL is deliberately not compared across the arm: raising the pump"
			.. " count is what makes the creature exist, and a creature cannot be unspawned")

		local modelStateBefore = refs.Model:GetAttribute("Level2_SlidemouthState")
		local before = Controller.GetFullDebugSnapshot()
		local navBefore = before.Navigation

		-- ---------------------------------------------------------------
		-- (4) BORROW.
		-- ---------------------------------------------------------------
		local pauseError
		handle, pauseError = Controller.DebugPauseSession()
		if not check(report, handle ~= nil, "the loaded incumbent pauses", pauseError) then
			return setBranch(report, "pause-failed")
		end
		check(report, handle.PartialFailures == nil,
			"and no stage half-succeeded: a returned handle is a CLEAN pause",
			handle.PartialFailures and table.concat(handle.PartialFailures, "; ") or nil)
		note(report, "row 16: re-adding handle.PartialFailures (A:1959) means a half-applied"
			.. " pause is handed back as if it were a clean one")
		check(report, Controller.DebugSessionPhase(handle) == "PAUSED",
			"and is PAUSED, not stopped", Controller.DebugSessionPhase(handle))
		check(report, not Controller.IsRunning(),
			"so the borrower starts from a clean controller")
		check(report, Controller.DebugIsPaused() == true
			and Controller.DebugParkedCount() == 1
			and Controller.DebugPauseDepth(handle) == 1,
			"the parked registry knows about it: paused, counted once, one borrow deep",
			string.format("paused %s, %d parked, depth %d",
				tostring(Controller.DebugIsPaused()), Controller.DebugParkedCount(),
				Controller.DebugPauseDepth(handle)))
		note(report, "rows 1, 2 and 7: without the registry (A:2234 / A:1990 / A:2203) a"
			.. " correctly paused session is invisible and its debt is never repaid")
		local parkedResidue = Controller.DebugResidue()
		check(report, parkedResidue.Parked == 1 and parkedResidue.Active == false
			and parkedResidue.PauseDepth == 1 and parkedResidue.OrphanRuntimeFolders == 1,
			"and its detached runtime folder is counted as residue while it is parked",
			string.format("%d parked, active %s, depth %d, %d orphan folders",
				parkedResidue.Parked, tostring(parkedResidue.Active), parkedResidue.PauseDepth,
				parkedResidue.OrphanRuntimeFolders))
		note(report, "row 8: a parked session's folder has Parent = nil BY DESIGN, so counting"
			.. " folders in the world scores the leak as clean (A:2262)")
		local parkedSnapshot = Controller.GetFullDebugSnapshot(handle)
		check(report, parkedSnapshot.Running == false and parkedSnapshot.Parked == true
			and parkedSnapshot.Phase == "PAUSED"
			and parkedSnapshot.Values ~= nil and parkedSnapshot.Values.LastPumps ~= nil
			and parkedSnapshot.Timers ~= nil and parkedSnapshot.Screams ~= nil,
			"a parked session still describes itself in full, and still says it is not running",
			string.format("running %s, parked %s, phase %s", tostring(parkedSnapshot.Running),
				tostring(parkedSnapshot.Parked), tostring(parkedSnapshot.Phase)))
		note(report, "row 12: reading activeSession alone (A:2712) answers {Running = false}"
			.. " and nothing else, so the incumbent is undescribable while it is lent out")
		check(report, Controller.DebugSessionPhase() == "PAUSED",
			"and the readers find the sole parked session without being handed the handle",
			tostring(Controller.DebugSessionPhase()))
		note(report, "row 34: nil used to answer both 'no session' and 'a session nobody can"
			.. " see from here', which are not the same fact (A:2309)")

		local surfaceBeforeStop = slidemouthSurface(state)
		local stopped, stopReason = Controller.Stop()
		local surfaceAfterStop = slidemouthSurface(state)
		check(report, stopped == false and stopReason == "no session"
			and Controller.DebugParkedCount() == 1,
			"Stop() with no argument refuses to touch a parked session",
			string.format("%s/%s, %d parked", tostring(stopped), tostring(stopReason),
				Controller.DebugParkedCount()))
		local surfaceProblems = surfaceDifferences(surfaceBeforeStop, surfaceAfterStop)
		check(report, #surfaceProblems == 0,
			"and left the replicated Slidemouth surface byte-identical",
			table.concat(surfaceProblems, ", "))
		note(report, "rows 3 and 6: an unconditional publishStopped('IDLE') (A:1548) clobbers"
			.. " ~22 attributes the handle recorded and still owes back")
		check(report, Controller.DebugScreamPlayed(armed.ScreamPump, handle) == false
			and Controller.DebugScreamCount(armed.ScreamPump, handle) == 0,
			"and the scream readers answer FOR the parked session -- 0 fired, not -1",
			tostring(Controller.DebugScreamCount(armed.ScreamPump, handle)))
		note(report, "rows 10 and 11: reading activeSession (A:2680 / A:2689) makes 'nothing"
			.. " has fired' true of every possible implementation")

		-- ---------------------------------------------------------------
		-- (5) A REAL borrower writes over everything it is holding.
		-- ---------------------------------------------------------------
		state:SetAttribute(armed.PresentAttribute, -1)
		state:SetAttribute(armed.AbsentAttribute, "written by the borrower")
		check(report, state:GetAttribute(armed.AbsentAttribute) ~= nil
			and state:GetAttribute(armed.PresentAttribute) == -1,
			"the borrower writes over the replicated surface, as a real one would")
		refs.Model:SetAttribute("Level2_SlidemouthState", "BORROWED")
		refs.Model:SetAttribute(armed.AbsentAttribute, "borrower model value")
		check(report, refs.Model:GetAttribute("Level2_SlidemouthState") == "BORROWED"
			and refs.Model:GetAttribute(armed.AbsentAttribute) ~= nil,
			"and over the model's own attributes, the present one and an absent one alike")
		local chaseWritten = true
		for _, name in ipairs(Controller.PlayerChaseAttributes) do
			player:SetAttribute(name, "borrowed")
			if player:GetAttribute(name) ~= "borrowed" then chaseWritten = false end
		end
		check(report, chaseWritten and #Controller.PlayerChaseAttributes > 0,
			"and over EVERY player chase attribute the controller declares",
			table.concat(Controller.PlayerChaseAttributes, ", "))
		note(report, "without this the production PlayerChase restore loop (A:2178) is never"
			.. " exercised: it can only put back values nobody changed")
		local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if playerRoot then playerRoot.CFrame = playerRoot.CFrame + Vector3.new(0, 12, 0) end
		check(report, playerRoot ~= nil,
			"and moves the player it was hunting -- this suite, not the handle, gives that back")

		local borrowThrew = not pcall(function()
			error("deliberate borrower failure, immediately after the pause")
		end)
		check(report, borrowThrew, "the borrow throws, as this test intends it to")
		check(report, Controller.DebugSessionPhase(handle) == "PAUSED",
			"the incumbent is still PAUSED after the borrower threw",
			Controller.DebugSessionPhase(handle))

		-- The borrow has to OUTLAST the pending scream, or this assertion is about
		-- a scream that was not due yet: the old wait was a flat 3 seconds against a
		-- 6-second delay, so it passed with the pause deleted entirely. Waiting past
		-- the due time means a session that is not really frozen fires here.
		task.wait(math.min(12, math.max(3, (armed.ScreamDueIn or 6) + 1)))
		check(report, Controller.DebugScreamPlayed(armed.ScreamPump, handle) == false
			and Controller.DebugScreamCount(armed.ScreamPump, handle) == 0,
			"the pending scream did NOT fire while the session was paused",
			tostring(Controller.DebugScreamCount(armed.ScreamPump, handle)))

		-- ---------------------------------------------------------------
		-- (6) A borrower that leaves its own session running, and two ways a
		--     transaction can fail.
		-- ---------------------------------------------------------------
		borrowSession = Controller.Start(manifest, manifest.Generation or 1)
		local refused, refusedWhy = Controller.DebugResumeSession(handle)
		check(report, refused == false and refusedWhy == "another session is active",
			"a resume is REFUSED while the borrower still has a session running",
			tostring(refused) .. "/" .. tostring(refusedWhy))
		check(report, Controller.IsRunning(),
			"and the borrower's own session is left alone, not silently destroyed")
		check(report, Controller.DebugSessionPhase(handle) == "PAUSED"
			and Controller.DebugPauseHandleValid(handle) == true,
			"while the incumbent stays PAUSED and resumable",
			Controller.DebugSessionPhase(handle))

		-- The probes below break a session on purpose. They are run on the
		-- BORROWER's own throwaway session, never on the incumbent: destroying a
		-- navigator cannot be undone, and the incumbent has to go back intact.
		local borrowRefs
		local spawnDeadline = os.clock() + 20
		while os.clock() < spawnDeadline do
			borrowRefs = Controller.DebugSessionRefs()
			if borrowRefs and borrowRefs.Model and borrowRefs.Navigator then break end
			task.wait(0.2)
		end
		check(report, borrowRefs ~= nil and borrowRefs.Model ~= nil and borrowRefs.Navigator ~= nil,
			"the borrower's own session grows a creature of its own to break")

		local borrowHandle, borrowPauseWhy = Controller.DebugPauseSession()
		check(report, borrowHandle ~= nil and Controller.DebugParkedCount() == 2
			and Controller.DebugSessionRefs() == nil
			and Controller.DebugSessionPhase() == nil,
			"pausing it parks a SECOND session, and the readers refuse to guess between them",
			tostring(borrowPauseWhy))
		local twoParked = Controller.DebugResidue()
		check(report, twoParked.Parked == 2 and twoParked.PauseDepth == 2
			and twoParked.OrphanRuntimeFolders == 2,
			"and both parked sessions are counted, folders included",
			string.format("%d parked, depth %d, %d orphan folders", twoParked.Parked,
				twoParked.PauseDepth, twoParked.OrphanRuntimeFolders))

		local borrowModel = borrowRefs and borrowRefs.Model or nil
		local borrowFolder = borrowRefs and borrowRefs.RuntimeFolder or nil
		local surfaceBeforeParkedStop = slidemouthSurface(state)
		Controller.Stop(borrowHandle)
		local surfaceAfterParkedStop = slidemouthSurface(state)
		check(report, borrowModel ~= nil and wasDestroyed(borrowModel),
			"Stop(handle) on a PARKED session really destroys its model",
			borrowModel == nil and "no model to check" or "the model is still alive")
		check(report, borrowFolder ~= nil and wasDestroyed(borrowFolder),
			"and its detached runtime folder with it",
			borrowFolder == nil and "no folder to check" or "the folder is still alive")
		note(report, "rows 4 and 5: restoring the `and session.Model.Parent` guards"
			.. " (A:1545/A:1546) makes a parked session's folder and model unreachable")
		local oneParked = Controller.DebugResidue()
		check(report, Controller.DebugParkedCount() == 1 and oneParked.PauseDepth == 1
			and oneParked.OrphanRuntimeFolders == 1
			and Controller.DebugPauseHandleValid(handle) == true,
			"and takes only that one out of the registry",
			string.format("%d parked, depth %d, %d orphan folders",
				oneParked.Parked, oneParked.PauseDepth, oneParked.OrphanRuntimeFolders))
		local parkedStopProblems = surfaceDifferences(surfaceBeforeParkedStop, surfaceAfterParkedStop)
		check(report, #parkedStopProblems == 0,
			"and left the replicated Slidemouth surface byte-identical, because a parked"
			.. " session is not the published one",
			table.concat(parkedStopProblems, ", "))
		note(report, "row 6: publishing IDLE for a session nobody was watching (A:1548)"
			.. " overwrites what the incumbent's handle still owes back")

		borrowSession = Controller.Start(manifest, manifest.Generation or 1)
		local secondRefs
		spawnDeadline = os.clock() + 20
		while os.clock() < spawnDeadline do
			secondRefs = Controller.DebugSessionRefs()
			if secondRefs and secondRefs.Model and secondRefs.Navigator then break end
			task.wait(0.2)
		end
		check(report, secondRefs ~= nil and secondRefs.Navigator ~= nil,
			"a second throwaway session spawns, to fail a pause with")
		-- Stand its heartbeat down before the navigator goes: a live heartbeat
		-- driving a destroyed navigator would spend the rest of this test warning
		-- about a session nobody is asserting on.
		workspace:SetAttribute("EntityPaused", true)
		task.wait(0.2)
		if secondRefs and secondRefs.Navigator then secondRefs.Navigator:Destroy() end
		local failedHandle, failedWhy = Controller.DebugPauseSession()
		check(report, failedHandle == nil
			and failedWhy == "pause failed: navigator: the navigator is destroyed",
			"a pause whose navigator stage fails returns nil and names the stage",
			tostring(failedWhy))
		note(report, "rows 15 and 17: accepting Navigator:Pause()'s silent nil (A:1968), or"
			.. " returning the handle instead of unwinding (A:2006), hands back a session")
		note(report, "whose resume has nothing to put back")
		local afterFailedPause = Controller.DebugSessionRefs()
		check(report, Controller.IsRunning()
			and Controller.DebugSessionPhase() == "RUNNING"
			and afterFailedPause ~= nil and secondRefs ~= nil
			and afterFailedPause.Session == secondRefs.Session
			and afterFailedPause.RuntimeFolder == secondRefs.RuntimeFolder
			and secondRefs.RuntimeFolder.Parent ~= nil,
			"and leaves that session RUNNING, untouched, its folder still in the world",
			afterFailedPause and tostring(afterFailedPause.Phase) or "no references")
		check(report, Controller.DebugParkedCount() == 1,
			"and parks nothing: the failed pause is a no-op, not a half-pause",
			tostring(Controller.DebugParkedCount()))

		-- An arm that CANNOT reach the state it was asked for has to unwind
		-- itself -- and must not take a different arm's undo list with it.
		local pumpsBeforeFailedArm = workspace:GetAttribute("Level2Pumps")
		local failedArm, failedArmWhy = Controller.DebugArmForPauseTest({NavigatorMode = "blocked"})
		check(report, failedArm == nil and failedArmWhy == "could not arm a live Blocked binding",
			"a blocked-mode arm that cannot bind reports exactly that",
			tostring(failedArmWhy))
		check(report, Controller._pauseProbe == armed,
			"and unwinds itself WITHOUT clearing the first arm's probe")
		note(report, "row 33: clearing Controller._pauseProbe inside unwind (A:2470) throws"
			.. " away the only thing standing between an earlier arm and a permanently")
		note(report, "mutated world")
		check(report, workspace:GetAttribute("Level2Pumps") == pumpsBeforeFailedArm,
			"and put Level2Pumps back where it found it",
			string.format("%s, was %s", tostring(workspace:GetAttribute("Level2Pumps")),
				tostring(pumpsBeforeFailedArm)))
		note(report, "row 32: returning the reason instead of unwind()'s (A:2589) leaves the"
			.. " pump count, the deadlines and the scream tables where the failed arm put them")

		Controller.Stop(borrowSession)
		borrowSession = nil
		workspace:SetAttribute("EntityPaused", nil)
		check(report, not Controller.IsRunning() and Controller.DebugParkedCount() == 1
			and Controller.DebugResidue().Active == false,
			"the borrower's own sessions are gone, and only the parked incumbent is left",
			string.format("%d parked", Controller.DebugParkedCount()))

		-- ---------------------------------------------------------------
		-- (7) A resume that FAILS must leave the handle re-usable.
		-- ---------------------------------------------------------------
		local savedAge = handle.Navigator and handle.Navigator.LastPathAge or nil
		if handle.Navigator then handle.Navigator.LastPathAge = nil end
		local brokenResume, brokenWhy = Controller.DebugResumeSession(handle)
		check(report, brokenResume == false
			and brokenWhy == "resume failed: navigator: pause record has an invalid LastPathAge",
			"a resume whose navigator stage REFUSES -- without throwing -- fails the resume",
			tostring(brokenWhy))
		note(report, "row 19: discarding Navigator:Resume's false (A:2147) counts a navigator"
			.. " that flatly refused to come back as a successful stage")
		local afterBroken = Controller.DebugResidue()
		check(report, handle.Consumed == false
			and Controller.DebugSessionPhase(handle) == "PAUSED"
			and Controller.DebugParkedCount() == 1
			and not Controller.IsRunning()
			and Controller.DebugPauseDepth(handle) == 1
			and Controller.DebugPauseHandleValid(handle) == true,
			"and rolls back to PARKED with the handle UNCONSUMED and re-usable",
			string.format("consumed %s, phase %s, %d parked", tostring(handle.Consumed),
				tostring(Controller.DebugSessionPhase(handle)), Controller.DebugParkedCount()))
		note(report, "row 18: consuming the handle above the failure test (A:2224) spends it"
			.. " on a resume that did not happen -- the session is live, half-restored,")
		note(report, "and there is no way back")
		check(report, refs.RuntimeFolder.Parent == nil
			and afterBroken.OrphanRuntimeFolders == 1,
			"and re-detached the runtime folder its first stage had already put back",
			string.format("%d orphan folders", afterBroken.OrphanRuntimeFolders))
		if handle.Navigator then handle.Navigator.LastPathAge = savedAge end

		-- ---------------------------------------------------------------
		-- (8) Move the creature, then give it back.
		-- ---------------------------------------------------------------
		local pivotBefore = refs.Model:GetPivot()
		refs.Model:PivotTo(pivotBefore * CFrame.new(7, 3, -5) * CFrame.Angles(0, math.rad(37), 0))
		check(report, (refs.Model:GetPivot().Position - pivotBefore.Position).Magnitude > 1,
			"the borrower moves the creature, orientation and all, as a careless one would")

		local resumed, resumeError = Controller.DebugResumeSession(handle)
		if not check(report, resumed, "the paused incumbent resumes on the SAME handle",
			resumeError) then
			return setBranch(report, "resume-failed")
		end
		check(report, handle.Consumed == true,
			"and only the successful resume consumed it")

		local after = Controller.GetFullDebugSnapshot()
		local refsAfter = Controller.DebugSessionRefs()
		check(report, refsAfter ~= nil and refsAfter.Session == refs.Session,
			"it is the SAME session table, not a replacement")
		check(report, refsAfter ~= nil and refsAfter.Model == refs.Model,
			"holding the SAME model Instance -- compared by reference, not by path")
		note(report, "row 14: two different Instances share a GetFullName(), so a path string"
			.. " cannot tell a restored model from a look-alike rebuilt in the same place")
		check(report, refsAfter ~= nil and refsAfter.RuntimeFolder == refs.RuntimeFolder
			and refs.RuntimeFolder.Parent ~= nil,
			"and the SAME runtime folder, parented back into the world")
		check(report, refsAfter ~= nil and refsAfter.Navigator == refs.Navigator,
			"and the SAME navigator")
		check(report, after.Phase == "RUNNING" and after.Parked == false
			and Controller.IsRunning(), "and it is running again", after.Phase)

		local pivotWrong = {}
		local pivotAfter = after.ModelPivotComponents
		for index = 1, 12 do
			local wanted = before.ModelPivotComponents and before.ModelPivotComponents[index]
			local got = pivotAfter and pivotAfter[index]
			if type(wanted) ~= "number" or type(got) ~= "number"
				or math.abs(wanted - got) > 1e-3 then
				table.insert(pivotWrong, tostring(index))
			end
		end
		check(report, #pivotWrong == 0,
			"the creature's FULL pose came back -- all twelve CFrame components",
			table.concat(pivotWrong, ", "))
		note(report, "row 13: position alone cannot see an orientation-only corruption; a"
			.. " borrow that spun the creature 90 degrees on the spot read as identical")
		check(report, #runtimeFolders(manifest) == runtimeWithIncumbent,
			"with no duplicate runtime folder and none destroyed",
			string.format("%d, %d with the incumbent", #runtimeFolders(manifest),
				runtimeWithIncumbent))
		local afterResidue = Controller.DebugResidue()
		check(report, Controller.DebugParkedCount() == 0
			and Controller.DebugPauseDepth(handle) == 0
			and Controller.DebugIsPaused() == false
			and afterResidue.PauseDepth == 0 and afterResidue.OrphanRuntimeFolders == 0,
			"and nothing is parked, owed or orphaned any more",
			string.format("%d parked, depth %d, %d orphan folders", afterResidue.Parked,
				afterResidue.PauseDepth, afterResidue.OrphanRuntimeFolders))

		-- TIMERS. Compared as REMAINING seconds, so "did not age" is the
		-- assertion. This is what the old suspend could not do: its deadlines were
		-- absolute and the clock never stopped, so a 0.75s deadline was long
		-- expired by the time the session came back.
		local aged = {}
		for name, value in pairs(before.Timers) do
			local now = after.Timers[name]
			if type(value) == "number" and type(now) == "number" then
				if math.abs(now - value) > 1 then
					table.insert(aged, string.format("%s %s -> %s", name, tostring(value), tostring(now)))
				end
			elseif now ~= value then
				table.insert(aged, string.format("%s %s -> %s", name, tostring(value), tostring(now)))
			end
		end
		check(report, #aged == 0, "no timer aged across the borrow", table.concat(aged, ", "))

		-- NAVIGATION.
		local navAfter = after.Navigation
		check(report, navAfter ~= nil and navBefore ~= nil, "the navigator is comparable")
		check(report, navAfter ~= nil and navBefore ~= nil
			and navAfter.RequestId > navBefore.RequestId,
			"the in-flight navigator request was invalidated, not awaited",
			navAfter and navBefore and string.format("%s -> %s",
				tostring(navBefore.RequestId), tostring(navAfter.RequestId)) or nil)
		check(report, navAfter ~= nil and navAfter.Paused == false,
			"and the navigator is running again")
		check(report, navAfter ~= nil and navBefore ~= nil
			and #navAfter.Waypoints == #navBefore.Waypoints,
			"the waypoint list is the one it had, not one a stale compute wrote",
			navAfter and navBefore and string.format("%d vs %d",
				#navAfter.Waypoints, #navBefore.Waypoints) or nil)
		check(report, navAfter ~= nil and navBefore ~= nil and navAfter.Status == navBefore.Status,
			"and its status is unchanged",
			navBefore and navAfter and (tostring(navBefore.Status) .. " -> "
				.. tostring(navAfter.Status)) or nil)
		-- REPLACES the old `navAfter.HasBlockedConnection == false`, which was
		-- vacuous: _requestPath disconnects the binding at its head and the arm
		-- deliberately leaves a request in flight, so the binding was already gone
		-- before the pause and the assertion passed with the whole pause deleted.
		-- In computing mode the documented settlement is the thing to assert.
		local outcome = handle.NavigatorResumeOutcome
		check(report, outcome ~= nil and (
			(outcome.RequestRestarted == true and outcome.RequestSettled == false
				and navAfter ~= nil and navAfter.Computing == true)
			or (outcome.RequestSettled == true and outcome.RequestRestarted == false
				and navAfter ~= nil and navAfter.Computing == false
				and navAfter.LastFailure == "the in-flight path request was invalidated by a pause")),
			"and the resume reported the documented computing-mode settlement:"
			.. " the request was RESTARTED, or explicitly SETTLED",
			outcome and string.format("restarted %s, settled %s, blocked %s",
				tostring(outcome.RequestRestarted), tostring(outcome.RequestSettled),
				tostring(outcome.BlockedRestored)) or "no outcome")
		note(report, "rows 20 and 21: a resume that neither restarts nor settles leaves a"
			.. " navigator believing in a request the pause already killed")

		-- ATTRIBUTES, including the ABSENT one.
		check(report, state:GetAttribute(armed.PresentAttribute) == armed.PresentValue,
			"the present replicated attribute came back with its value",
			tostring(state:GetAttribute(armed.PresentAttribute)))
		check(report, state:GetAttribute(armed.AbsentAttribute) == nil,
			"and the ABSENT one came back ABSENT after the borrower wrote it",
			tostring(state:GetAttribute(armed.AbsentAttribute)))
		check(report, refs.Model:GetAttribute(armed.AbsentAttribute) == nil
			and refs.Model:GetAttribute("Level2_SlidemouthState") == modelStateBefore,
			"including on the MODEL -- the value it had back, the absence back to absent",
			string.format("%s / %s", tostring(refs.Model:GetAttribute(armed.AbsentAttribute)),
				tostring(refs.Model:GetAttribute("Level2_SlidemouthState"))))
		local chaseWrong = {}
		local chaseRecord = handle.PlayerChase and handle.PlayerChase[player] or nil
		for _, name in ipairs(Controller.PlayerChaseAttributes) do
			-- Read into a local rather than through `record and record[name] or nil`:
			-- clearOwnedChaseMarker writes BeingChased = FALSE, and that idiom
			-- collapses a correctly restored false into nil.
			local wanted
			if chaseRecord then wanted = chaseRecord[name] end
			if player:GetAttribute(name) ~= wanted then
				table.insert(chaseWrong, string.format("%s %s, wanted %s", name,
					tostring(player:GetAttribute(name)), tostring(wanted)))
			end
		end
		check(report, chaseRecord ~= nil and #chaseWrong == 0,
			"and every player chase attribute went back to its exact prior value, nil included",
			table.concat(chaseWrong, ", "))

		local drift = snapshotDrift(comparableSnapshot(before), comparableSnapshot(after))
		check(report, #drift == 0,
			"and the whole comparable surface matches, field by field",
			table.concat(drift, ", "))
		-- The other half of masking RunToken out of that comparison. The token is
		-- the controller's cancellation token: it is bumped on every departure
		-- from RUNNING and every return to it, and it is NEVER restored, because
		-- restoring it would hand the jobs this pause cancelled their session
		-- back. So the drift comparison must not demand it unchanged -- and this
		-- must demand that it MOVED, or the pause cancelled nothing at all. One
		-- clean borrow is exactly two bumps.
		local tokenBefore = before.Values and before.Values.RunToken
		local tokenAfter = after.Values and after.Values.RunToken
		check(report, type(tokenBefore) == "number" and type(tokenAfter) == "number"
			and tokenAfter == tokenBefore + 2,
			"the borrow moved the run token twice -- once leaving RUNNING, once"
			.. " returning -- so every job it cancelled is now permanently fenced out",
			string.format("%s -> %s", tostring(tokenBefore), tostring(tokenAfter)))
		note(report, "this replaces an ACCIDENTAL assertion: the whole-surface comparison"
			.. " used to fail on RunToken (0 vs 2) and called a textbook clean borrow")
		note(report, "corruption. Masking it without asserting it here would have been"
			.. " deleting an assertion to get green; this asserts the opposite fact.")

		-- THE PENDING SCREAM. This block is LAST of the post-resume checks because
		-- it is the only one that yields: the incumbent is live again, and seven
		-- seconds of heartbeat republishes the model's state attribute and rewrites
		-- the chase attributes on whoever it is hunting. Everything that reads the
		-- live world therefore had to be read above, before the first yield.
		local screamAfter = after.Screams[armed.ScreamPump]
		local screamBefore = before.Screams[armed.ScreamPump]
		check(report, screamBefore ~= nil,
			"the borrow really did begin with a scream pending -- the rest of this"
			.. " section would be vacuous otherwise")
		check(report, screamAfter ~= nil,
			"the pending pump scream is still scheduled after the borrow")
		check(report, screamAfter ~= nil and screamAfter.Played ~= true,
			"and has not been marked played")
		check(report, screamBefore ~= nil and screamAfter ~= nil
			and math.abs(screamAfter.RemainingSeconds - screamBefore.RemainingSeconds) <= 1,
			"with its REMAINING delay preserved, not its absolute deadline",
			screamAfter and screamBefore and string.format("%d -> %d",
				screamBefore.RemainingSeconds, screamAfter.RemainingSeconds) or nil)
		local screamWaitStart = os.clock()
		local fired = Controller.DebugWaitForScream(armed.ScreamPump, 12)
		local screamElapsed = os.clock() - screamWaitStart
		check(report, fired, "the warning still fires after the borrow, at its shifted time")
		-- Both readings, deliberately. A resume that put the ABSOLUTE deadline back
		-- would leave RemainingSeconds NEGATIVE and fire instantly, which
		-- `elapsed >= screamAfter.RemainingSeconds - 1` alone would wave through;
		-- screamBefore is the delay the borrow actually owed.
		local owedDelay = math.max(screamAfter and screamAfter.RemainingSeconds or 0,
			screamBefore and screamBefore.RemainingSeconds or 0)
		check(report, fired and screamElapsed >= owedDelay - 1,
			"and it waited out the REMAINING delay rather than firing on a stale deadline",
			string.format("%.1fs elapsed, %s owed", screamElapsed, tostring(owedDelay)))
		note(report, "nothing measured elapsed time here before, so restoring the absolute"
			.. " deadline -- the exact bug the remaining-delay code exists to prevent -- passed")
		check(report, Controller.DebugScreamCount(armed.ScreamPump) == 1,
			"exactly once -- the borrow neither lost it nor duplicated it",
			tostring(Controller.DebugScreamCount(armed.ScreamPump)))
		task.wait(1)
		check(report, Controller.DebugScreamCount(armed.ScreamPump) == 1,
			"and still exactly once a second later",
			tostring(Controller.DebugScreamCount(armed.ScreamPump)))

		-- ---------------------------------------------------------------
		-- (9) DISARM, and the TRUE pre-arm world.
		-- ---------------------------------------------------------------
		-- Nothing below this line may yield until the readings are taken. The
		-- incumbent is LIVE again: its heartbeat rewrites NextTargetRefreshAt
		-- every TARGET_REFRESH seconds and its navigator's goal every frame, so a
		-- task.wait() between the disarm and the snapshot would be measuring the
		-- next heartbeat rather than the disarm.
		local disarmedOk, disarmedWhy = Controller.DebugDisarmPauseTest()
		local disarmedTwice = Controller.DebugDisarmPauseTest()
		local disarmClock = os.clock()
		local postDisarm = Controller.GetFullDebugSnapshot()
		local postPumps = workspace:GetAttribute("Level2Pumps")
		local postPresent = state:GetAttribute(presentName)
		local postAbsent = state:GetAttribute(absentName)
		local postScreamCount = Controller.DebugScreamCount(armed.ScreamPump)
		check(report, disarmedOk == true, "the disarm reports success", tostring(disarmedWhy))
		check(report, disarmedTwice == true,
			"and reports success again when it is called twice")
		note(report, "row 31: clearing the probe pointer below the undo loop (A:2652) makes a"
			.. " second disarm re-run every undo over a world that has moved on")

		local restoreWrong = {}
		if postPumps ~= armed.Restore.Level2Pumps then
			table.insert(restoreWrong, string.format("Level2Pumps %s vs %s",
				tostring(postPumps), tostring(armed.Restore.Level2Pumps)))
		end
		if postDisarm.Values.LastPumps ~= armed.Restore.LastPumps then
			table.insert(restoreWrong, string.format("LastPumps %s vs %s",
				tostring(postDisarm.Values.LastPumps), tostring(armed.Restore.LastPumps)))
		end
		for _, name in ipairs(EXPECTED_DEADLINE_FIELDS) do
			if not timerAgrees(postDisarm.Timers[name],
				expectedTimerReading(armed.Restore.Deadlines[name], disarmClock)) then
				table.insert(restoreWrong, name)
			end
		end
		if not timerAgrees(postDisarm.Timers.ProgressAt,
			expectedTimerReading(armed.Restore.ProgressAt, disarmClock)) then
			table.insert(restoreWrong, "ProgressAt")
		end
		check(report, #restoreWrong == 0,
			"the disarm put Level2Pumps, LastPumps, all eight deadlines and ProgressAt"
			.. " back to the values the arm found them at",
			table.concat(restoreWrong, ", "))
		note(report, "row 29: a disarm that only cleared Controller._pauseProbe (A:2654) left"
			.. " every one of those holding the arm's value for whatever ran next")

		local wantedScream = armed.Restore.PumpScreamScheduled[armed.ScreamPump]
		check(report, (wantedScream == nil) == (postDisarm.Screams[armed.ScreamPump] == nil)
			and postScreamCount == (armed.Restore.PumpScreamFired[armed.ScreamPump] or 0),
			"and the probe pump's scream bookkeeping went back to its pre-arm contents",
			string.format("scheduled %s, fired %d", tostring(postDisarm.Screams[armed.ScreamPump]),
				postScreamCount))
		local navRestore = armed.Restore.Navigator and armed.Restore.Navigator.Fields or nil
		check(report, navRestore ~= nil and postDisarm.Navigation ~= nil
			and postDisarm.Navigation.Goal == navRestore.Goal
			and postDisarm.Navigation.LastRequestedGoal == navRestore.LastRequestedGoal
			and postDisarm.Navigation.Status == navRestore.Status,
			"and the navigator's goal, last requested goal and status came back too",
			postDisarm.Navigation and string.format("%s / %s", tostring(postDisarm.Navigation.Goal),
				tostring(postDisarm.Navigation.Status)) or "no navigation")
		check(report, postPresent == preArmPresent and postAbsent == preArmAbsent,
			"and both probe attributes are back at their pre-arm values, absence included",
			string.format("%s / %s", tostring(postPresent), tostring(postAbsent)))
		check(report, postDisarm.Phase == "RUNNING" and Controller.IsRunning()
			and Controller.DebugParkedCount() == 0,
			"and the incumbent is still RUNNING: a disarm stops, pauses and resumes nothing",
			tostring(postDisarm.Phase))
		-- Read the world back through the controller's OWN residue reader, which
		-- compares current values against what the arm APPLIED rather than against
		-- the pre-image, and so cannot be fooled by the live incumbent
		-- re-advancing a deadline a frame after getting it back.
		--
		-- This is where the forced spawn is settled honestly. Everything the arm
		-- APPLIED must be gone -- the raised pump count first among them -- and the
		-- one thing it could not take back must appear in Irreversible, in words,
		-- rather than being implied by a clean-looking return value. The
		-- biconditional is exact: the arm declares the spawn if and only if it
		-- actually had to raise the pump count, which is the same condition that
		-- makes CapturedBeforeAnyMutation false.
		local disarmResidue = Controller.DebugPauseProbeResidue(armed)
		local spawnDeclared = false
		for _, entry in ipairs(disarmResidue.Irreversible or {}) do
			if string.find(tostring(entry), "to force a spawn", 1, true) then
				spawnDeclared = true
			end
		end
		check(report, disarmResidue.Clean == true and disarmResidue.Disarmed == true
			and disarmResidue.AllowedIrreversibleSpawn == suiteOwnsWorld
			and spawnDeclared == (preImageIsPreArm == false),
			"nothing the arm APPLIED survived the disarm -- the raised pump count"
			.. " first -- and the forced spawn it could not take back is DECLARED"
			.. " rather than implied by a clean return value",
			string.format("%d still applied (%s); spawn declared %s, forced %s;"
				.. " irreversible: %s", disarmResidue.AppliedCount,
				table.concat(disarmResidue.Applied or {}, ", "), tostring(spawnDeclared),
				tostring(preImageIsPreArm == false),
				table.concat(disarmResidue.Irreversible or {}, " | ")))
		note(report, "B9 proof: delete the verification block inside DebugDisarmPauseTest and"
			.. " an undo entry dropped from any stage still reports success -- but"
			.. " Clean goes false here, naming the field that never went back")

		-- ---------------------------------------------------------------
		-- (10) The SECOND borrow: a live Blocked binding, not a computing one.
		-- ---------------------------------------------------------------
		-- Nothing between this arm and the pause below may yield. The incumbent
		-- repaths every RepathInterval, and _requestPath drops the binding at its
		-- head -- so a single frame between "armed with a binding" and "paused"
		-- can be the frame that takes the binding away.
		local blockedArmed, blockedWhy = Controller.DebugArmForPauseTest({
			ScreamPump = 1,
			ScreamInSeconds = 3,
			DeadlineInSeconds = 0.75,
			PresentAttribute = presentName,
			AbsentAttribute = absentName,
			NavigatorMode = "blocked",
		})
		if not check(report, blockedArmed ~= nil,
			"the incumbent can be armed with a LIVE Blocked binding", blockedWhy) then
			-- Not a pass. A hall with no computable route cannot produce a Blocked
			-- binding at all, and the honest report of that is its own branch --
			-- the blocked half of a navigator resume is simply unexercised here.
			check(report, blockedWhy == "could not arm a live Blocked binding",
				"and a blocked-mode arm that cannot bind says exactly that, having"
				.. " unwound every mutation it had applied", tostring(blockedWhy))
			note(report, "row 32: the blocked half of Navigator:Resume is NOT exercised on"
				.. " this map. Nothing here passed by pretending otherwise.")
			return setBranch(report, "no-blocked-arm")
		end
		check(report, blockedArmed.NavigatorMode == "blocked"
			and blockedArmed.NavigatorBlocked == true
			and blockedArmed.NavigatorRequesting == false,
			"and the arm achieved the mode it was asked for, with nothing in flight",
			string.format("mode %s, blocked %s", tostring(blockedArmed.NavigatorMode),
				tostring(blockedArmed.NavigatorBlocked)))
		local blockedBefore = Controller.GetFullDebugSnapshot()
		check(report, blockedBefore.Navigation ~= nil
			and blockedBefore.Navigation.HasBlockedConnection == true
			and blockedBefore.Navigation.Computing ~= true,
			"the navigator really is holding a live Blocked binding before the pause")
		note(report, "this is the state the OLD assertion could never reach: it asserted"
			.. " HasBlockedConnection == false in computing mode, where the binding was")
		note(report, "already gone before the pause, and passed with the pause deleted")

		local blockedPauseWhy
		blockedHandle, blockedPauseWhy = Controller.DebugPauseSession()
		check(report, blockedHandle ~= nil, "the blocked incumbent pauses", blockedPauseWhy)
		check(report, blockedHandle ~= nil and blockedHandle.Navigator ~= nil
			and blockedHandle.Navigator.HadBlockedConnection == true
			and blockedHandle.Navigator.BlockedPath ~= nil,
			"and the handle carries the Path the binding belonged to, not just a flag")
		local blockedParked = blockedHandle and Controller.GetFullDebugSnapshot(blockedHandle) or nil
		check(report, blockedParked ~= nil and blockedParked.Navigation ~= nil
			and blockedParked.Navigation.HasBlockedConnection == false,
			"the binding is disconnected while the session is parked")
		local blockedResumed, blockedResumeWhy
		if blockedHandle then
			blockedResumed, blockedResumeWhy = Controller.DebugResumeSession(blockedHandle)
		end
		check(report, blockedResumed == true, "the blocked incumbent resumes",
			tostring(blockedResumeWhy))
		local blockedOutcome = blockedHandle and blockedHandle.NavigatorResumeOutcome or nil
		local blockedAfter = Controller.GetFullDebugSnapshot()
		check(report, blockedOutcome ~= nil and blockedOutcome.BlockedRestored == true,
			"and the resume reports the binding REBUILT from the recorded Path",
			blockedOutcome and string.format("restored %s, restarted %s, settled %s",
				tostring(blockedOutcome.BlockedRestored), tostring(blockedOutcome.RequestRestarted),
				tostring(blockedOutcome.RequestSettled)) or "no outcome")
		note(report, "row 22: deleting the rebind block (B:986), or recording only the boolean"
			.. " (B:928), leaves a resumed navigator with no way to hear that its route broke")
		check(report, blockedOutcome ~= nil and blockedOutcome.RequestRestarted == false
			and blockedOutcome.RequestSettled == false
			and blockedAfter.Navigation ~= nil
			and blockedAfter.Navigation.HasBlockedConnection == true,
			"and because nothing was in flight to restart, the rebuilt binding is still live",
			blockedAfter.Navigation and tostring(blockedAfter.Navigation.HasBlockedConnection) or nil)
		check(report, Controller.DebugParkedCount() == 0
			and Controller.DebugResidue().PauseDepth == 0
			and Controller.DebugResidue().OrphanRuntimeFolders == 0
			and #runtimeFolders(manifest) == runtimeWithIncumbent,
			"and the second borrow left nothing parked, owed or orphaned either")

		-- The scream this arm scheduled is due AFTER the disarm, so the disarm has
		-- to make its job inert rather than merely late.
		local serialsBefore = {
			Warning = state:GetAttribute("Level2_SlidemouthWarningSerial"),
			Scream = state:GetAttribute("Level2_SlidemouthScreamSerial"),
		}
		local blockedDisarm = Controller.DebugDisarmPauseTest()
		local blockedPumps = workspace:GetAttribute("Level2Pumps")
		check(report, blockedDisarm == true and blockedPumps == blockedArmed.Restore.Level2Pumps,
			"the second disarm reports success and puts Level2Pumps back",
			string.format("%s, %s wanted", tostring(blockedPumps),
				tostring(blockedArmed.Restore.Level2Pumps)))
		task.wait(math.min(8, (blockedArmed.ScreamDueIn or 3) * 2))
		check(report, state:GetAttribute("Level2_SlidemouthWarningSerial") == serialsBefore.Warning
			and state:GetAttribute("Level2_SlidemouthScreamSerial") == serialsBefore.Scream,
			"and the disarmed scream job stayed INERT for twice its delay",
			string.format("warning %s -> %s, scream %s -> %s", tostring(serialsBefore.Warning),
				tostring(state:GetAttribute("Level2_SlidemouthWarningSerial")),
				tostring(serialsBefore.Scream),
				tostring(state:GetAttribute("Level2_SlidemouthScreamSerial"))))
		note(report, "row 30: without restoring Level2Pumps in the scream undo (A:2526) the"
			.. " job's own `pumps >= pumpNumber` gate still passes and it fires late")

		-- ---------------------------------------------------------------
		-- (11) RESIDUE. Nothing this test used may outlive it.
		-- ---------------------------------------------------------------
		check(report, Controller.DebugPauseHandleValid(handle) == false,
			"the spent pause handle cannot be reused")
		check(report, Controller._spawnInterlude == nil,
			"no spawn interlude hook was left behind")
		check(report, Controller._pauseProbe == nil,
			"and no pause probe is left armed")
		return report
	end)
end

-- Nothing this suite builds may outlive it, and nothing it changed may be left
-- changed. This runs AFTER every suite's own cleanup, so it sees the world the
-- next thing to touch this place will see.
local TEST_FOLDER_NAMES = {
	"Level 2 Slidemouth Probe Rigs", "Level 2 Slidemouth Probe Geometry",
	"Level 2 Slidemouth Adversarial Rigs", "Level 2 Slidemouth Adversarial Geometry",
	"Level 2 Slidemouth Pause Probe Rigs", "Level 2 Slidemouth Traversal Rigs",
	"Level 2 Slidemouth Substep Rigs", "Level 2 Slidemouth Substep Geometry",
	"Level 2 Slidemouth Centring Rigs",
	"Probe Diag",
}

-- WHAT SHIPPED BROKEN: the folder scan used FindFirstChild, which is NOT
-- recursive, while the model scan beside it was -- so scaffolding left one
-- level down inside a generated hall was invisible to the very check that
-- exists to find it. Both scans now walk the same recursive pass.
--
-- And a PARKED session is residue. DebugIsPaused() alone could never fire
-- while it read activeSession, which a successful pause nils; the registry is
-- now asked directly, for the count, the outstanding borrow debt AND the
-- detached runtime folders that a count of folders in the world cannot see.
local function residue(manifest)
	local found = {}
	local wanted = {}
	for _, name in ipairs(TEST_FOLDER_NAMES) do wanted[name] = true end
	local sawProbeModel = false
	for _, descendant in ipairs(manifest.World:GetDescendants()) do
		if descendant:IsA("Folder") and wanted[descendant.Name] then
			table.insert(found, "folder " .. descendant.Name)
		elseif descendant:IsA("Model") and not sawProbeModel
			and descendant.Name == "Level 2 Slidemouth Ledge Probe" then
			sawProbeModel = true
			table.insert(found, "probe model")
		end
	end
	if Controller._spawnInterlude ~= nil then table.insert(found, "spawn interlude hook") end
	if Controller._pauseProbe ~= nil then table.insert(found, "pause probe hook") end
	local live = Controller.DebugResidue()
	if live.Parked > 0 then
		table.insert(found, string.format("%d session(s) left PARKED", live.Parked))
	end
	if live.PauseDepth > 0 then
		table.insert(found, string.format("%d outstanding borrow(s)", live.PauseDepth))
	end
	if live.OrphanRuntimeFolders > 0 then
		table.insert(found, string.format("%d detached runtime folder(s)",
			live.OrphanRuntimeFolders))
	end
	if Controller.DebugIsPaused() then table.insert(found, "a session left PAUSED") end
	return found
end

function Suite.RunAll(manifest, includeLive)
	if not (manifest and manifest.World and manifest.World.Parent) then
		return "Level 2 Slidemouth Test Suite: no live Level 2 manifest", 1
	end
	-- SpawnParties sits next to Spawn because it reads the same ranking surface
	-- and mutates nothing. Traversal sits after Ledges: both build rig folders in
	-- the live world, and both must be finished and cleaned up before LiveSpawn
	-- and PauseIsolation start borrowing the incumbent.
	local runs = {Suite.Spawn, Suite.SpawnNoNeighbour, Suite.SpawnParties,
		Suite.SpawnContract, Suite.Adversarial, Suite.Ledges, Suite.Substep,
		Suite.Centring, Suite.Traversal}
	if includeLive ~= false then
		table.insert(runs, Suite.LiveSpawn)
		-- Runs AFTER LiveSpawn: it deliberately loads the incumbent up, and a
		-- suite that borrowed an armed creature and then measured "was the world
		-- restored" would be measuring this test's arming rather than its own.
		table.insert(runs, Suite.PauseIsolation)
	end
	local lines, failures, checks = {}, 0, 0
	local breakdown = {}
	local constructedBranch = nil
	for _, run in ipairs(runs) do
		local ok, report = pcall(run, manifest)
		if ok and run == Suite.SpawnNoNeighbour then constructedBranch = report.Branch end
		if ok then
			-- Exact counts, per branch. A branch that quietly stops running half
			-- its assertions fails here instead of reporting a smaller total.
			local expected = EXPECTED_CHECKS[report.Title]
			local wanted = expected and expected[report.Branch]
			local ran = report.Checks
			report.Checks += 1
			if wanted == nil then
				report.Failures += 1
				table.insert(report.Lines, string.format(
					"  FAIL no expected check count declared for %q branch %q",
					report.Title, report.Branch))
			elseif ran ~= wanted then
				report.Failures += 1
				table.insert(report.Lines, string.format(
					"  FAIL branch %q ran %d checks, expected %d",
					report.Branch, ran, wanted))
			else
				table.insert(report.Lines, string.format(
					"  ok   branch %q ran its declared %d checks", report.Branch, wanted))
			end
			table.insert(breakdown, string.format("%s [%s] %d checks, %d failed",
				report.Title, report.Branch, report.Checks, report.Failures))
			table.insert(lines, table.concat(report.Lines, "\n"))
			failures += report.Failures
			checks += report.Checks
		else
			table.insert(lines, "=== suite errored ===\n  FAIL " .. tostring(report))
			table.insert(breakdown, "a suite errored")
			failures += 1
			checks += 1
		end
	end

	-- The constructed map exists to make the no-neighbour branch reachable. If
	-- it stops reaching it, the branch's declared count is unverified again.
	checks += 1
	if constructedBranch == "no-neighbour" then
		table.insert(lines, "  ok   the constructed map reaches the no-neighbour branch")
	else
		failures += 1
		table.insert(lines, "  FAIL the constructed map reached branch "
			.. tostring(constructedBranch) .. ", not no-neighbour")
	end

	local leftovers = residue(manifest)
	checks += 1
	if #leftovers == 0 then
		table.insert(lines, "  ok   the suite left no test folders, models or hooks behind")
	else
		failures += 1
		table.insert(lines, "  FAIL the suite left test state behind  ("
			.. table.concat(leftovers, ", ") .. ")")
	end

	table.insert(lines, "BREAKDOWN:")
	for _, line in ipairs(breakdown) do table.insert(lines, "  " .. line) end
	table.insert(lines, string.format("TOTAL: %d checks, %d failed", checks, failures))
	return table.concat(lines, "\n"), failures
end

return Suite
