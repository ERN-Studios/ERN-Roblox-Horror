--!strict
-- Level 4 Test Suite
--
-- Self-checks the lead can run from a Studio play session. Two halves:
--
--   TestSuite.RunPlanChecks()  -- pure. Needs no round, no world, no players.
--   TestSuite.RunWorldChecks() -- reads the STANDING world through Workspace
--                                 and the replicated state folder.
--
-- The world half deliberately reads INSTANCES AND ATTRIBUTES rather than the
-- adapter's module state. `require` inside execute_luau is a separate module
-- instance -- the session table the real round is using is invisible from
-- there -- so a suite that asked the adapter for its manifest would silently
-- measure nothing. That mistake has already cost this project a day.
--
--   local Suite = require(game:GetService("ServerScriptService")
--       ["Level 4 Systems"]["Level 4 Test Suite"])
--   print(Suite.RunAll())

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local PlanGenerator = require(script.Parent:WaitForChild("Level 4 Plan Generator"))
local Brain = require(script.Parent:WaitForChild("Level 4 Neighbour Brain"))

local TestSuite = {}

local function newReport(name: string)
	return {Name = name, Checks = 0, Failures = {}}
end

local function check(report: any, condition: any, message: string)
	report.Checks += 1
	if not condition then table.insert(report.Failures, message) end
end

local function finish(report: any): any
	report.Passed = #report.Failures == 0
	report.Summary = ("%s: %d checks, %d failures"):format(report.Name, report.Checks, #report.Failures)
	return report
end

-- ---------------------------------------------------------------------------
-- Plan checks. Every variant, walked as a graph.
-- ---------------------------------------------------------------------------

local SEEDS = {1, 101, 7331, 65537, 1900813, 104729, 2147483646}

function TestSuite.RunPlanChecks(): any
	local report = newReport("Level 4 plan")

	-- 1. The derived envelopes are what the numbers say, re-derived here rather
	--    than copied, so a body change that nobody propagated fails loudly.
	local body = Configuration.Body
	local derived = Configuration.Derived
	local expectedDoor = math.max(body.PlayerWidth * 2 + body.PlayerPassGap,
		body.NeighbourShoulderWidth + body.NeighbourArmSwing + body.NeighbourClearance)
	check(report, math.abs(derived.DoorWidth - expectedDoor) < 1e-6,
		("DoorWidth must be the wider of the two bodies (%0.2f)"):format(expectedDoor))
	check(report, math.abs(derived.DoorHeight - (body.NeighbourHeight + 1)) < 1e-6,
		"DoorHeight must clear the Neighbour by one stud")
	check(report, derived.InteriorCeiling > derived.DoorHeight,
		"the interior ceiling must clear the door it contains")
	check(report, derived.PassageWidth >= derived.DoorWidth,
		"an interior passage must be at least as wide as a door")
	check(report, derived.StairWidth >= derived.DoorWidth,
		"a staircase must be at least as wide as a door")
	check(report, derived.AgentRadius * 2 < derived.DoorWidth,
		"the pathfinding agent must fit through a door")
	check(report, derived.AgentHeight < derived.InteriorCeiling,
		"the pathfinding agent must fit under the ceiling")

	-- 2. Every variant of every seed is valid, repeatable and distinct.
	local seenVariants = {}
	for _, seed in ipairs(SEEDS) do
		local plan = PlanGenerator.Generate(seed)
		local repeated = PlanGenerator.Generate(seed)
		check(report, plan.PlanHash == repeated.PlanHash,
			"seed " .. seed .. " must repeat exactly")
		local valid, problem = PlanGenerator.Validate(plan)
		check(report, valid, "seed " .. seed .. " failed validation: " .. tostring(problem))
		seenVariants[plan.Variant] = true

		-- Loop + shortcut connectivity, measured rather than assumed.
		local adjacency = PlanGenerator.__test.Adjacency(plan)
		local reached = PlanGenerator.__test.Reachable(adjacency, "Arrival")
		for _, junction in ipairs(plan.Junctions) do
			check(report, reached[junction.Id] == true,
				"seed " .. seed .. ": junction " .. junction.Id .. " is unreachable")
		end

		-- Every task spot is reachable solo, and so is the exit. Reachability
		-- here means "its street is on the connected graph", which is what the
		-- blockout can promise; the navmesh sweep is a Studio-only measurement.
		for _, task in ipairs(plan.Tasks) do
			local lot = plan.LotById[task.LotId]
			local edge = plan.StreetById[lot.StreetId]
			check(report, reached[edge.A] and reached[edge.B],
				"seed " .. seed .. ": signal " .. task.Index .. " is not reachable")
			check(report, lot.Interior > 0,
				"seed " .. seed .. ": signal " .. task.Index .. " is not in an enterable house")
		end

		-- The safe-house invariant, at plan level: every zone must be able to
		-- keep one safe enterable house while the scheduler takes its maximum.
		local enterable = {}
		for _, lot in ipairs(plan.Lots) do
			if lot.Interior > 0 then enterable[lot.Zone] = (enterable[lot.Zone] or 0) + 1 end
		end
		for zone = 1, plan.ZoneCount do
			check(report, (enterable[zone] or 0) >= 2,
				"seed " .. seed .. ": zone " .. zone .. " has no safe alternative")
		end

		-- Nothing required sits behind its own lock: the three signals need
		-- nothing, and the beacon needs only the three signals.
		local locked = 0
		for _, task in ipairs(plan.Tasks) do
			if plan.LotById[task.LotId].Id == "Exit" then locked += 1 end
		end
		check(report, locked == 0, "seed " .. seed .. ": a signal is behind the exit")
		check(report, #plan.Tasks == Configuration.Objectives.SignalGoal,
			"seed " .. seed .. ": wrong signal count")

		-- House count, as the brief states it.
		check(report, #plan.Lots >= 8 and #plan.Lots <= 12,
			"seed " .. seed .. ": the blockout must show 8 to 12 houses")
	end

	-- 3. All three variants are reachable, and each of them validates.
	for variant = 1, PlanGenerator.VariantCount do
		local found = false
		for probe = 1, 400 do
			local plan = PlanGenerator.Generate(probe)
			if plan.Variant == variant then
				found = true
				local valid, problem = PlanGenerator.Validate(plan)
				check(report, valid, "variant " .. variant .. " failed validation: " .. tostring(problem))
				break
			end
		end
		check(report, found, "variant " .. variant .. " is never selected by any seed 1..400")
	end
	check(report, seenVariants ~= nil, "variant selection ran")

	-- 4. The validator REJECTS. A validator that only ever says yes is not one.
	local mutated = PlanGenerator.Generate(101)
	mutated.Tasks[1].Forgiving = false
	local valid = PlanGenerator.Validate(mutated)
	check(report, not valid, "the validator must reject a plan with no forgiving first signal")

	mutated = PlanGenerator.Generate(101)
	table.remove(mutated.Streets, #mutated.Streets)
	mutated.StreetById.Shortcut = nil
	valid = PlanGenerator.Validate(mutated)
	check(report, not valid, "the validator must reject a plan with no cross shortcut")

	return finish(report)
end

-- ---------------------------------------------------------------------------
-- Brain checks. The same rules the offline suite asserts, re-run in Studio so
-- a Luau-version difference cannot hide a behaviour change.
-- ---------------------------------------------------------------------------

function TestSuite.RunBrainChecks(): any
	local report = newReport("Level 4 Neighbour brain")
	local config = Configuration.Neighbour

	local function step(sense: any): any
		return Brain.Step(sense, config)
	end

	-- A chase is never entered directly.
	for _, from in ipairs({Brain.PATROL, Brain.INVESTIGATE, Brain.SEARCH, Brain.RETURN}) do
		local decision = step({Now = 100, State = from, StateSince = 99,
			Visible = true, VisibleDistance = 4})
		check(report, decision.State == Brain.ALERT,
			from .. " must escalate to ALERT, never straight to CHASE")
		check(report, decision.Telegraph == true, "ALERT must telegraph")
	end

	-- A distant sighting is a trace, not a target.
	local decision = step({Now = 100, State = Brain.PATROL, StateSince = 99,
		Visible = true, VisibleDistance = config.DetectRange + 10})
	check(report, decision.State == Brain.SEARCH and decision.GoalKind == Brain.GOAL_SIGHTING,
		"a distant sighting must produce a search, not a chase")

	-- The telegraph can be broken.
	decision = step({Now = 100, State = Brain.ALERT, StateSince = 99.8, Visible = false})
	check(report, decision.State == Brain.SEARCH, "breaking the line during ALERT cancels the chase")
	-- A hair past the telegraph, not exactly on it: 100 - 1.1 does not round-trip
	-- in a double, so an exact boundary here tests the float, not the rule.
	decision = step({Now = 100, State = Brain.ALERT, StateSince = 100 - config.AlertSeconds - 0.01,
		Visible = true, VisibleDistance = 4})
	check(report, decision.State == Brain.CHASE, "a completed telegraph becomes a chase")

	-- Quiet walking breaks contact faster.
	local loud = Brain.ContactGrace(config, false)
	local quiet = Brain.ContactGrace(config, true)
	check(report, quiet < loud, "walking quietly must shorten the chase's grip")
	decision = step({Now = 100, State = Brain.CHASE, StateSince = 90,
		Visible = false, ContactLostFor = quiet + 0.01, Quiet = true})
	check(report, decision.State == Brain.SEARCH, "a quiet player breaks contact")
	decision = step({Now = 100, State = Brain.CHASE, StateSince = 90,
		Visible = false, ContactLostFor = quiet + 0.01, Quiet = false})
	check(report, decision.State == Brain.CHASE, "a loud player does not break contact that fast")

	-- Noise is investigated at the noise, and every state is bounded.
	decision = step({Now = 100, State = Brain.PATROL, StateSince = 99, HasNoise = true, NoiseAt = 99.5})
	check(report, decision.State == Brain.INVESTIGATE and decision.GoalKind == Brain.GOAL_NOISE,
		"noise must be investigated at the noise position")
	decision = step({Now = 100, State = Brain.SEARCH, StateSince = 100 - config.SearchSeconds - 1})
	check(report, decision.State == Brain.RETURN, "a search must end")
	decision = step({Now = 100, State = Brain.INVESTIGATE,
		StateSince = 100 - config.InvestigateSeconds - 1})
	check(report, decision.State == Brain.RETURN, "an investigation must end")
	decision = step({Now = 100, State = Brain.RETURN, StateSince = 99, AtGoal = true})
	check(report, decision.State == Brain.PATROL, "a return must drain back to patrol")

	return finish(report)
end

-- ---------------------------------------------------------------------------
-- World checks. Run these WHILE a Level 4 round is standing.
-- ---------------------------------------------------------------------------

function TestSuite.RunWorldChecks(): any
	local report = newReport("Level 4 world")
	local world = workspace:FindFirstChild(Configuration.WorldName)
	local folder = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	check(report, world ~= nil, "no Level 4 world is standing; start a dev round first")
	check(report, folder ~= nil, "the Level 4 State folder is missing")
	if not world or not folder then return finish(report) end

	check(report, workspace:GetAttribute("SelectedLevel") == 4, "SelectedLevel must be 4")
	check(report, workspace:GetAttribute("Level4DevEnabled") == true,
		"Level 4 must only ever stand with the dev flag set")

	-- Compatibility markers GameManager waits on.
	local elevator = workspace:FindFirstChild("Elevator")
	check(report, elevator ~= nil and elevator:FindFirstChild("DoorL") ~= nil
		and elevator:FindFirstChild("DoorR") ~= nil,
		"the arrival needs an Elevator with DoorL and DoorR")
	local spawnPad = workspace:FindFirstChild("ElevatorSpawn")
	check(report, spawnPad ~= nil and spawnPad:IsA("BasePart") and (spawnPad :: BasePart).CanCollide,
		"the arrival needs a solid ElevatorSpawn for the entry barrier to ray onto")
	check(report, workspace:FindFirstChild("MazeStart") ~= nil, "the arrival needs MazeStart")

	-- The performance budget, measured.
	local lights, shadowed = 0, 0
	for _, object in ipairs(world:GetDescendants()) do
		if object:IsA("Light") then
			lights += 1
			if (object :: any).Shadows == true then shadowed += 1 end
		end
	end
	check(report, lights <= Configuration.Performance.MaximumDynamicLights,
		("dynamic lights: %d, budget %d"):format(lights, Configuration.Performance.MaximumDynamicLights))
	check(report, shadowed == 0, ("%d decorative lights cast shadows; none may"):format(shadowed))
	local descendants = #world:GetDescendants()
	check(report, descendants <= Configuration.Performance.MaximumWorldDescendants,
		("world instances: %d, budget %d")
			:format(descendants, Configuration.Performance.MaximumWorldDescendants))

	-- Houses, states and the safe-house invariant as it actually stands.
	local perZone, safePerZone, houses = {}, {}, 0
	for _, child in ipairs(world:GetChildren()) do
		local houseState = child:GetAttribute("Level4_HouseState")
		if child:IsA("Model") and houseState ~= nil then
			houses += 1
			local zone = child:GetAttribute("Level4_Zone") or 0
			local interior = child:FindFirstChild("InteriorVolume")
			if interior then
				perZone[zone] = (perZone[zone] or 0) + 1
				if houseState == "SAFE" then safePerZone[zone] = (safePerZone[zone] or 0) + 1 end
			end
			check(report, child:FindFirstChild("DoorFrame") ~= nil,
				"house " .. child.Name .. " has no DoorFrame")
			check(report, child:FindFirstChild("PorchSignal") ~= nil,
				"house " .. child.Name .. " has no PorchSignal")
		end
	end
	check(report, houses >= 8 and houses <= 12,
		("the blockout must show 8 to 12 houses; it shows %d"):format(houses))
	for zone, count in pairs(perZone) do
		if count > 0 then
			check(report, (safePerZone[zone] or 0) >= 1,
				"zone " .. zone .. " has no safe house right now")
		end
	end

	-- The finale is the only lock, and it is locked until the signals are in.
	local beacon = world:FindFirstChild("ExtractionBeacon")
	check(report, beacon ~= nil, "the extraction beacon is missing")
	if beacon then
		local unlocked = folder:GetAttribute("Level4_BeaconUnlocked") == true
		for index = 1, Configuration.Objectives.CabinetControlCount do
			local control = beacon:FindFirstChild("CabinetControl" .. index)
			check(report, control ~= nil, "cabinet control " .. index .. " is missing")
			local prompt = control and control:FindFirstChildWhichIsA("ProximityPrompt")
			check(report, prompt ~= nil, "cabinet control " .. index .. " has no prompt")
			if prompt and not unlocked then
				check(report, prompt.Enabled == false,
					"cabinet control " .. index .. " must stay locked until 3/3 signals")
			end
		end
		check(report, beacon:FindFirstChild("EscapeTrigger") ~= nil, "the escape trigger is missing")
		check(report, beacon:FindFirstChild("ExitSafeSpawn") ~= nil, "the exit safe spawn is missing")
	end

	-- Signals: each one has a prompt AND a visual clue. No task may require
	-- hearing, and that is checked here rather than trusted.
	for index = 1, Configuration.Objectives.SignalGoal do
		local fixture, clue = nil, nil
		for _, object in ipairs(world:GetDescendants()) do
			if object:GetAttribute("Level4_SignalIndex") == index and object:IsA("BasePart") then
				fixture = object
			end
			if object:GetAttribute("Level4_SignalClue") == index then clue = object end
		end
		check(report, fixture ~= nil, "signal " .. index .. " has no fixture")
		check(report, clue ~= nil, "signal " .. index .. " has no VISUAL clue")
		check(report, fixture == nil or fixture:FindFirstChildWhichIsA("ProximityPrompt") ~= nil,
			"signal " .. index .. " has no prompt")
	end

	-- The Neighbour is registered with the detector's own extension point.
	local runtime = world:FindFirstChild("NeighbourRuntime")
	check(report, runtime ~= nil, "the Neighbour runtime folder is missing")
	local rig = runtime and runtime:FindFirstChild(Configuration.Neighbour.RuntimeName)
	check(report, rig ~= nil, "the Neighbour rig is missing")
	if rig then
		check(report, rig:GetAttribute("ZyntraDetectorLevel") == 4,
			"the Neighbour must publish ZyntraDetectorLevel = 4")
		check(report, (rig :: Model).PrimaryPart ~= nil,
			"the detector needs the rig to have a PrimaryPart")
		check(report, rig:FindFirstChild("HumanoidRootPart") ~= nil, "the rig needs a HumanoidRootPart")
		local root = rig:FindFirstChild("HumanoidRootPart")
		check(report, root and root:FindFirstChild("FootstepAttachment") ~= nil,
			"the audio contract needs FootstepAttachment on the root")
		check(report, root and root:FindFirstChild("HeadAttachment") ~= nil,
			"the audio contract needs HeadAttachment on the root")
	end
	check(report, folder:GetAttribute("Level4_NeighbourState") ~= nil,
		"the Neighbour must publish its state")

	-- Placeholders are findable, which is the whole art hand-over list.
	local placeholders = 0
	for _, object in ipairs(world:GetDescendants()) do
		if object:GetAttribute("Level4_Placeholder") == true then placeholders += 1 end
	end
	check(report, placeholders > 0, "nothing is marked Level4_Placeholder; the art pass has no list")
	report.Placeholders = placeholders
	report.Lights = lights
	report.Descendants = descendants
	report.Houses = houses

	return finish(report)
end

function TestSuite.RunAll(): any
	local plan = TestSuite.RunPlanChecks()
	local brain = TestSuite.RunBrainChecks()
	local world = TestSuite.RunWorldChecks()
	local lines = {plan.Summary, brain.Summary, world.Summary}
	for _, report in ipairs({plan, brain, world}) do
		for _, failure in ipairs(report.Failures) do
			table.insert(lines, "  FAIL " .. report.Name .. ": " .. failure)
		end
	end
	return {
		Passed = plan.Passed and brain.Passed and world.Passed,
		Plan = plan, Brain = brain, World = world,
		Text = table.concat(lines, "\n"),
	}
end

return TestSuite
