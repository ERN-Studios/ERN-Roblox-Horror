--!strict
-- Level 4 Neighbour Controller
--
-- The world half of the entity: the placeholder rig, the senses, the path and
-- the movement. Every RULE lives in Level 4 Neighbour Brain, which is pure and
-- tested offline; this file only gathers facts, hands them over, and acts on
-- the answer.
--
-- Session / alive() / one heartbeat / Stop, the shape the Level 2 Pool Slide
-- controller uses. Not its navigator -- that one walks a bone rig along a
-- water slide. The Neighbour walks streets, so it uses PathfindingService with
-- the agent Configuration derives from the rig's own envelope.
--
-- What is deliberately impossible here:
--   * No teleport onto a player. Every frame's movement is clamped to
--     MaximumStepStuds, so a server hitch cannot move the rig through a wall.
--   * No damage through a wall. The attack re-tests line of sight at the
--     moment of the hit, not at the moment of the wind-up.
--   * No hit on a correctly hidden player. A player inside a SAFE house is
--     sheltered (the Objective Controller owns that fact) and is neither
--     targeted nor attackable.
--   * No omniscient noise. NoiseRegistry hands back a POSITION; the rig walks
--     to the position. It is never handed the player who made it.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local Brain = require(script.Parent:WaitForChild("Level 4 Neighbour Brain"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 4 Objective Controller"))
local NoiseRegistry = require(ServerScriptService:WaitForChild("NoiseRegistry"))
local PlayerProtection = require(ServerScriptService:WaitForChild("PlayerProtection"))

local Controller = {}

local CONFIG = Configuration.Neighbour
local DERIVED = Configuration.Derived
local BODY = Configuration.Body

local activeSession: any = nil

-- ---------------------------------------------------------------------------
-- The placeholder rig
--
-- Parts only. The names below are a CONTRACT: the audio pass attaches
-- footsteps to FootstepAttachment and voice to HeadAttachment, and the art
-- pass replaces the parts while keeping the names. See
-- docs/LEVEL4_CONTRACTS_2026-09-21.md.
-- ---------------------------------------------------------------------------

local function rigPart(model: Model, name: string, size: Vector3, color: Color3): BasePart
	local object = Instance.new("Part")
	object.Name = name
	object.Anchored = true
	object.CanCollide = false
	-- The rig must be visible to the player's eye but invisible to its own
	-- line-of-sight rays; the controller excludes the whole runtime folder.
	object.CanTouch = false
	object.CanQuery = false
	object.CastShadow = false
	object.Size = size
	object.Color = color
	object.Material = Enum.Material.SmoothPlastic
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object:SetAttribute("Level4_Placeholder", true)
	object.Parent = model
	return object
end

local function buildRig(parent: Instance, position: Vector3): Model
	local height = BODY.NeighbourHeight
	local shoulder = BODY.NeighbourShoulderWidth
	local workwear = Color3.fromRGB(122, 120, 106)
	local mask = Color3.fromRGB(198, 200, 196)

	local model = Instance.new("Model")
	model.Name = CONFIG.RuntimeName
	model:SetAttribute("Level4_Placeholder", true)
	model:SetAttribute("Level4_RigHeight", height)
	model:SetAttribute("Level4_RigWidth", shoulder + BODY.NeighbourArmSwing)

	-- The rig's own frame is at the hips, the way a Humanoid's root is, so the
	-- controller's CFrame arithmetic reads the same as everywhere else.
	local root = rigPart(model, "HumanoidRootPart", Vector3.new(2, 2, 1), workwear)
	root.Transparency = 1
	root.CFrame = CFrame.new(position + Vector3.new(0, height * 0.52, 0))
	model.PrimaryPart = root

	rigPart(model, "Torso", Vector3.new(shoulder, height * 0.36, 1.5), workwear)
	rigPart(model, "Head", Vector3.new(1.6, 1.9, 1.6), workwear)
	rigPart(model, "Mask", Vector3.new(1.2, 1.2, 0.2), mask).Material = Enum.Material.Glass
	for _, side in ipairs({"Left", "Right"}) do
		rigPart(model, "UpperArm" .. side, Vector3.new(0.7, height * 0.2, 0.7), workwear)
		-- Too-long forearms. Half again as long as the upper arm: the single
		-- silhouette cue that reads at street distance.
		rigPart(model, "Forearm" .. side, Vector3.new(0.6, height * 0.3, 0.6), workwear)
		rigPart(model, "Leg" .. side, Vector3.new(0.8, height * 0.44, 0.8), workwear)
	end

	local feet = Instance.new("Attachment")
	feet.Name = "FootstepAttachment"
	feet.Position = Vector3.new(0, -height * 0.5, 0)
	feet.Parent = root
	local head = Instance.new("Attachment")
	head.Name = "HeadAttachment"
	head.Position = Vector3.new(0, height * 0.46, 0)
	head.Parent = root

	model.Parent = parent
	return model
end

-- Poses the rig around its root. Called from the movement step, so it may not
-- allocate a table or a closure; only CFrame arithmetic, which is a value type.
local function poseRig(session: any, bob: number)
	local root = session.Root
	local height = BODY.NeighbourHeight
	local frame = root.CFrame
	local lean = session.Parts
	-- The unnatural head tilt. Constant, not animated: it is what makes the
	-- silhouette recognisable standing still.
	lean.Head.CFrame = frame * CFrame.new(0, height * 0.44 + bob, 0) * CFrame.Angles(0.22, 0, 0.14)
	lean.Mask.CFrame = lean.Head.CFrame * CFrame.new(0, 0, -0.85)
	lean.Torso.CFrame = frame * CFrame.new(0, height * 0.2 + bob, 0)
	-- session.Limbs is built once at Start. Concatenating "UpperArm" .. side
	-- here would allocate six strings every frame for no reason at all.
	for _, limb in ipairs(session.Limbs) do
		local swing = session.Swing * limb.Sign
		limb.Upper.CFrame = frame
			* CFrame.new(limb.X, height * 0.22 + bob, 0) * CFrame.Angles(swing * 0.5, 0, 0)
		limb.Fore.CFrame = limb.Upper.CFrame
			* CFrame.new(0, -height * 0.25, 0) * CFrame.Angles(swing * 0.35, 0, 0)
		limb.Leg.CFrame = frame
			* CFrame.new(limb.X * 0.4, -height * 0.24, 0) * CFrame.Angles(-swing * 0.6, 0, 0)
	end
end

-- ---------------------------------------------------------------------------
-- Session
-- ---------------------------------------------------------------------------

local function alive(session: any): boolean
	local world = session.Manifest.World
	return activeSession == session
		and world.Parent ~= nil
		and world:GetAttribute("Level4_Generation") == session.Generation
		and session.Model.Parent ~= nil
end

local function roundReady(session: any): boolean
	return alive(session)
		and workspace:GetAttribute("SelectedLevel") == 4
		and workspace:GetAttribute("RoundActive") == true
end

-- session.State is the BRAIN state string; session.StateFolder is the
-- replicated folder. Keeping the two apart matters: they were one field in the
-- first draft and every publish silently wrote onto a string.
local function publish(session: any, key: string, value: any)
	local folder = session.StateFolder
	if folder then folder:SetAttribute("Level4_Neighbour" .. key, value) end
end

local function livingRoot(player: Player): BasePart?
	if player.Parent ~= Players then return nil end
	if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then return nil end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end
	return root :: BasePart
end

-- A player is QUIET when they are crouched. Crouch State Server publishes the
-- attribute; NoiseRegistry already prices crouch at zero loudness, so this is
-- the same fact, read for a different purpose.
local function isQuiet(player: Player): boolean
	return player:GetAttribute("Crouching") == true
end

-- One RaycastParams, built once and reused. Building one per sense tick is an
-- allocation in the hot path for no benefit: only the filter list changes, and
-- it does not change at all.
local function sightBlocked(session: any, from: Vector3, to: Vector3, character: Model?): boolean
	local params = session.RayParams
	-- The character has to be excluded or every ray stops on the target's own
	-- body. The runtime folder is excluded so the rig cannot blind itself.
	-- One filter table, refilled in place: a fresh one per ray is garbage the
	-- think loop would generate several times a second for the whole round.
	local filter = session.RayFilter
	filter[2] = character
	params.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(from, to - from, params)
	return hit ~= nil
end

-- ---------------------------------------------------------------------------
-- Senses
--
-- Fills session.Sense IN PLACE. One table for the whole round: the think loop
-- runs seven times a second for the length of a round, and a fresh table each
-- time is pure garbage.
-- ---------------------------------------------------------------------------

local function sense(session: any, now: number)
	local out = session.Sense
	local root = session.Root
	local eye = root.Position + Vector3.new(0, BODY.NeighbourHeight * 0.46, 0)
	local facing = root.CFrame.LookVector
	local cosLimit = math.cos(math.rad(CONFIG.FieldOfViewDegrees / 2))

	out.Now = now
	out.State = session.State
	out.StateSince = session.StateSince
	out.Visible = false
	out.VisibleDistance = math.huge
	out.VisibleUserId = nil
	out.Quiet = false

	local bestDistance = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local target = livingRoot(player)
		-- A player inside a safe house is correctly hidden. Not targeted, not
		-- attacked, and not even seen -- the whole point of the mechanic.
		if target and not ObjectiveController.IsSheltered(player) then
			local offset = target.Position - eye
			local distance = offset.Magnitude
			if distance <= CONFIG.VisionRange and distance < bestDistance then
				local direction = distance > 0.01 and offset / distance or facing
				if facing:Dot(direction) >= cosLimit
					and not sightBlocked(session, eye, target.Position + Vector3.new(0, 1, 0), target.Parent) then
					bestDistance = distance
					out.Visible = true
					out.VisibleDistance = distance
					out.VisibleUserId = player.UserId
					out.Quiet = isQuiet(player)
					session.SeenPlayer = player
					session.LastSeenPosition = target.Position
					session.LastSeenAt = now
				end
			end
		end
	end

	-- Contact for the chase rule is measured from the LAST time the rig saw
	-- anybody at all, so breaking the line is what ends a chase -- not distance,
	-- and certainly not the server knowing where the player went.
	out.ContactLostFor = out.Visible and 0 or (now - (session.LastSeenAt or 0))
	if not out.Visible and session.SeenPlayer and session.SeenPlayer.Parent == Players then
		-- Out of sight, so the quiet test falls back to the player the rig was
		-- last looking at: that is whose behaviour decides how fast it loses them.
		out.Quiet = isQuiet(session.SeenPlayer)
	end

	-- Hearing. NoiseRegistry already prices crouch at zero loudness, so a
	-- crouching player emits nothing for this to find -- there is no separate
	-- quiet-hearing multiplier, and adding one would be counting it twice.
	NoiseRegistry.Prune()
	local heard = NoiseRegistry.GetBest(root.Position, CONFIG.HearingRange)
	if heard and (now - session.NoiseEpochOffset) - heard.t <= CONFIG.NoiseLifetimeSeconds then
		out.HasNoise = true
		out.NoiseAt = heard.t + session.NoiseEpochOffset
		session.NoisePosition = heard.pos
	else
		out.HasNoise = false
		out.NoiseAt = 0
	end

	local goal = session.Goal
	out.AtGoal = goal ~= nil
		and (Vector3.new(root.Position.X - goal.X, 0, root.Position.Z - goal.Z)).Magnitude
			<= CONFIG.WaypointReachDistance * 2
	out.LegExpired = now >= session.LegExpiresAt
end

-- ---------------------------------------------------------------------------
-- Goals and paths
-- ---------------------------------------------------------------------------

local function speedFor(stateName: string): number
	if stateName == Brain.CHASE then return CONFIG.ChaseSpeed end
	if stateName == Brain.SEARCH then return CONFIG.SearchSpeed end
	if stateName == Brain.INVESTIGATE then return CONFIG.InvestigateSpeed end
	if stateName == Brain.RETURN then return CONFIG.ReturnSpeed end
	-- ALERT is a standstill: the telegraph is the rig stopping and turning.
	if stateName == Brain.ALERT then return 0 end
	return CONFIG.PatrolSpeed
end

local function animationFor(stateName: string): string
	if stateName == Brain.CHASE then return "Chase" end
	if stateName == Brain.SEARCH or stateName == Brain.INVESTIGATE then return "Search" end
	if stateName == Brain.ALERT then return "Idle" end
	return "Walk"
end

local function pickPatrolNode(session: any): Vector3
	local nodes = session.Manifest.PatrolNodes
	if #nodes == 0 then return session.Home end
	-- Never the node it is standing on: a patrol leg that goes nowhere is how
	-- a patrol becomes a pillar.
	for _ = 1, 6 do
		local node = nodes[session.Random:NextInteger(1, #nodes)]
		if (node.Position - session.Root.Position).Magnitude > 24 then return node.Position end
	end
	return nodes[session.Random:NextInteger(1, #nodes)].Position
end

local function resolveGoal(session: any, goalKind: string, newGoal: boolean): Vector3?
	if goalKind == Brain.GOAL_TARGET then
		local player = session.SeenPlayer
		local root = player and livingRoot(player)
		return root and root.Position or session.LastSeenPosition
	elseif goalKind == Brain.GOAL_NOISE then
		return session.NoisePosition
	elseif goalKind == Brain.GOAL_SIGHTING or goalKind == Brain.GOAL_LASTSEEN then
		return session.LastSeenPosition
	elseif goalKind == Brain.GOAL_HOME then
		return session.Home
	end
	if newGoal or not session.Goal or session.GoalKind ~= Brain.GOAL_PATROL then
		return pickPatrolNode(session)
	end
	return session.Goal
end

-- Path computation yields, so it runs in its own thread and never blocks the
-- think loop. A second request while one is in flight is dropped: bounded
-- cadence means bounded, not "whenever anybody asks".
local function requestPath(session: any, goal: Vector3)
	if session.PathBusy then return end
	session.PathBusy = true
	local token = session.PathToken + 1
	session.PathToken = token
	task.spawn(function()
		local ok = pcall(function()
			session.Path:ComputeAsync(session.Root.Position, goal)
		end)
		if not alive(session) or session.PathToken ~= token then
			session.PathBusy = false
			return
		end
		if ok and session.Path.Status == Enum.PathStatus.Success then
			session.Waypoints = session.Path:GetWaypoints()
			session.WaypointIndex = 2 -- [1] is where the rig already is
			session.PathFailures = 0
			publish(session, "PathStatus", "OK")
		else
			session.PathFailures += 1
			publish(session, "PathStatus", "FAILED")
			-- A goal PathfindingService cannot reach is not a reason to stand
			-- still for the rest of the round: walk at it directly and let the
			-- watchdog pick a new one if that does not work either.
			session.Waypoints = nil
			if session.PathFailures >= CONFIG.MaxPathFailures then
				session.PathFailures = 0
				session.Goal = pickPatrolNode(session)
				session.GoalKind = Brain.GOAL_PATROL
				session.LegExpiresAt = os.clock() + CONFIG.PatrolLegSeconds
			end
		end
		session.PathBusy = false
	end)
end

-- ---------------------------------------------------------------------------
-- Attack
-- ---------------------------------------------------------------------------

local function tryAttack(session: any, now: number)
	if session.State ~= Brain.CHASE then return end
	if now < session.AttackReadyAt then return end
	local player = session.SeenPlayer
	local root = player and livingRoot(player)
	if not player or not root then return end
	if ObjectiveController.IsSheltered(player) then return end
	if PlayerProtection.IsActive(player) then return end
	if now < (session.GraceUntil[player] or 0) then return end
	local eye = session.Root.Position + Vector3.new(0, BODY.NeighbourHeight * 0.46, 0)
	if (root.Position - session.Root.Position).Magnitude > CONFIG.AttackRange then return end

	session.AttackReadyAt = now + CONFIG.AttackWindupSeconds + CONFIG.AttackRecoverySeconds
	publish(session, "Animation", "Attack")
	publish(session, "AttackSerial", (session.AttackSerial or 0) + 1)
	session.AttackSerial = (session.AttackSerial or 0) + 1

	-- The wind-up is a real window: the hit is re-validated at the END of it,
	-- so stepping behind a wall or into a safe house during the wind-up works.
	task.delay(CONFIG.AttackWindupSeconds, function()
		if not roundReady(session) then return end
		local nowRoot = livingRoot(player)
		if not nowRoot then return end
		if ObjectiveController.IsSheltered(player) then return end
		if PlayerProtection.IsActive(player) then return end
		if (nowRoot.Position - session.Root.Position).Magnitude > CONFIG.AttackRange + 1.5 then return end
		if sightBlocked(session, eye, nowRoot.Position + Vector3.new(0, 1, 0), nowRoot.Parent) then return end
		local humanoid = nowRoot.Parent and nowRoot.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.Health = 0 end
	end)
end

-- ---------------------------------------------------------------------------
-- Think and move
-- ---------------------------------------------------------------------------

local function think(session: any)
	local now = os.clock()
	sense(session, now)
	local decision = Brain.Step(session.Sense, CONFIG)

	if decision.Changed then
		session.State = decision.State
		session.StateSince = now
		publish(session, "State", decision.State)
		publish(session, "Animation", animationFor(decision.State))
		session.Model:SetAttribute("Level4_NeighbourState", decision.State)
		-- A fresh state always gets a fresh leg budget, so no state can run
		-- past its own watchdog by inheriting an old deadline.
		session.LegExpiresAt = now + CONFIG.PatrolLegSeconds
	end
	publish(session, "TargetUserId", decision.TargetUserId or 0)
	publish(session, "Reason", decision.Reason)

	local goal = resolveGoal(session, decision.GoalKind, decision.NewGoal == true)
	if goal then
		local moved = not session.Goal or (goal - session.Goal).Magnitude > CONFIG.PathGoalMoveThreshold
		if decision.NewGoal or session.GoalKind ~= decision.GoalKind or moved then
			session.Goal = goal
			session.GoalKind = decision.GoalKind
			session.LegExpiresAt = now + CONFIG.PatrolLegSeconds
			session.NextPathAt = 0
		end
	end
	if session.Goal then
		publish(session, "GoalX", session.Goal.X)
		publish(session, "GoalZ", session.Goal.Z)
	end
	if session.NoisePosition then
		publish(session, "NoiseX", session.NoisePosition.X)
		publish(session, "NoiseZ", session.NoisePosition.Z)
	end

	local cadence = session.State == Brain.CHASE
		and CONFIG.ChasePathRecomputeSeconds or CONFIG.PathRecomputeSeconds
	if session.Goal and now >= session.NextPathAt then
		session.NextPathAt = now + cadence
		requestPath(session, session.Goal)
	end

	tryAttack(session, now)

	-- The watchdog. A rig that has not moved for StuckSeconds is repathed; one
	-- that is still stuck after DoorWaitSeconds gets a different goal entirely.
	-- That is what makes a door a delay rather than a deadlock: whatever it is
	-- standing behind, it always leaves.
	local travelled = (session.Root.Position - session.WatchdogAnchor).Magnitude
	if travelled > 2 then
		session.WatchdogAnchor = session.Root.Position
		session.BlockedSince = now
	elseif now - session.BlockedSince >= CONFIG.DoorWaitSeconds then
		session.BlockedSince = now
		session.Goal = pickPatrolNode(session)
		session.GoalKind = Brain.GOAL_PATROL
		session.NextPathAt = 0
		publish(session, "PathStatus", "REROUTED")
	elseif now - session.BlockedSince >= CONFIG.StuckSeconds then
		session.NextPathAt = 0
	end
end

local function move(session: any, deltaTime: number)
	local step = math.min(deltaTime, CONFIG.MaximumMovementDeltaSeconds)
	local root = session.Root
	local speed = speedFor(session.State)

	local target: Vector3? = nil
	local waypoints = session.Waypoints
	if waypoints then
		local index = session.WaypointIndex
		while index <= #waypoints do
			local candidate = waypoints[index].Position
			if (Vector3.new(candidate.X - root.Position.X, 0, candidate.Z - root.Position.Z)).Magnitude
				> CONFIG.WaypointReachDistance then
				target = candidate
				break
			end
			index += 1
		end
		session.WaypointIndex = index
	end
	if not target then target = session.Goal end
	if not target then
		poseRig(session, 0)
		return
	end

	local offset = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	local distance = offset.Magnitude
	local facing = root.CFrame.LookVector

	if distance > 0.05 then
		local direction = offset / distance
		-- Turn towards the direction of travel at a bounded rate. In ALERT the
		-- rig turns but does not walk, which is exactly the telegraph.
		local blend = math.clamp(CONFIG.TurnRate * step, 0, 1)
		local newFacing = (facing + (direction - facing) * blend)
		if newFacing.Magnitude < 0.01 then newFacing = direction end
		newFacing = newFacing.Unit
		-- MaximumStepStuds is the guarantee that a hitch cannot move the rig
		-- through a wall or onto a player: whatever deltaTime says, one frame
		-- never covers more than this.
		local travel = math.min(speed * step, distance, CONFIG.MaximumStepStuds)
		local position = root.Position + direction * travel
		root.CFrame = CFrame.lookAt(position, position + newFacing)
	end

	session.Swing = math.sin(os.clock() * math.max(1, speed) * 0.5) * (speed > 0 and 0.55 or 0.08)
	poseRig(session, math.sin(os.clock() * math.max(1, speed) * 1.0) * (speed > 0 and 0.12 or 0.02))
	publish(session, "Speed", speed)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function Controller.Start(manifest: any, generation: number): any
	Controller.Stop()
	assert(type(manifest) == "table" and manifest.World and manifest.World.Parent == workspace,
		"Level 4 Neighbour needs the live world")
	assert(manifest.NeighbourRuntime and manifest.NeighbourRuntime:IsDescendantOf(manifest.World),
		"Level 4 Neighbour needs its runtime folder")
	assert(type(manifest.PatrolNodes) == "table" and #manifest.PatrolNodes >= 4,
		"Level 4 Neighbour needs patrol nodes on the streets, mailboxes and porches")

	local model = buildRig(manifest.NeighbourRuntime, manifest.NeighbourSpawn)
	local parts = {}
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") then parts[child.Name] = child end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local session: any = {
		Manifest = manifest,
		Generation = generation,
		Model = model,
		Root = model.PrimaryPart :: BasePart,
		Parts = parts,
		Limbs = {
			{Upper = parts.UpperArmLeft, Fore = parts.ForearmLeft, Leg = parts.LegLeft,
				X = -(BODY.NeighbourShoulderWidth / 2 + 0.2), Sign = 1},
			{Upper = parts.UpperArmRight, Fore = parts.ForearmRight, Leg = parts.LegRight,
				X = BODY.NeighbourShoulderWidth / 2 + 0.2, Sign = -1},
		},
		RuntimeFolder = manifest.NeighbourRuntime,
		RayFilter = {manifest.NeighbourRuntime, nil},
		RayParams = params,
		StateFolder = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName),
		State = Brain.PATROL,
		StateSince = os.clock(),
		Sense = {},
		Connections = {},
		Random = Random.new(manifest.Plan.ResolvedSeed + 977),
		Home = manifest.NeighbourSpawn,
		Goal = nil,
		GoalKind = Brain.GOAL_PATROL,
		Waypoints = nil,
		WaypointIndex = 2,
		PathBusy = false,
		PathToken = 0,
		PathFailures = 0,
		NextPathAt = 0,
		LegExpiresAt = os.clock() + CONFIG.PatrolLegSeconds,
		WatchdogAnchor = manifest.NeighbourSpawn,
		BlockedSince = os.clock(),
		AttackReadyAt = 0,
		AttackSerial = 0,
		GraceUntil = {},
		LastSeenPosition = manifest.NeighbourSpawn,
		LastSeenAt = 0,
		SeenPlayer = nil,
		NoisePosition = nil,
		Swing = 0,
		Running = true,
	}
	-- NoiseRegistry stamps os.clock(); the brain compares against its own Now,
	-- which is also os.clock(). The offset is therefore zero, and it is named
	-- rather than assumed so a future change of clock in either module fails
	-- loudly here instead of silently making every noise look stale.
	session.NoiseEpochOffset = 0
	activeSession = session

	-- The detector's documented extension point. No detector change is needed:
	-- a tagged live Model with a PrimaryPart and the right level is enough.
	CollectionService:AddTag(model, CONFIG.DetectorTag)
	model:SetAttribute("ZyntraDetectorLevel", CONFIG.DetectorLevel)
	model:SetAttribute("ZyntraDetectorActive", true)

	session.Path = PathfindingService:CreatePath({
		AgentRadius = DERIVED.AgentRadius,
		AgentHeight = DERIVED.AgentHeight,
		AgentCanJump = false,
		AgentCanClimb = false,
		WaypointSpacing = CONFIG.WaypointSpacing,
	})

	-- The think loop runs on a timer, not on Heartbeat: it raycasts and reads
	-- every player, and there is no reason for that to happen sixty times a
	-- second. Movement is the only thing that needs every frame.
	task.spawn(function()
		while session.Running and alive(session) do
			if roundReady(session) then
				local ok, problem = pcall(think, session)
				if not ok then warn("[Level 4] Neighbour think failed: " .. tostring(problem)) end
			end
			task.wait(CONFIG.ThinkIntervalSeconds)
		end
	end)

	table.insert(session.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		if not roundReady(session) then return end
		local ok, problem = pcall(move, session, deltaTime)
		if not ok then warn("[Level 4] Neighbour move failed: " .. tostring(problem)) end
	end))

	-- A freshly placed body cannot be hit instantly. Re-entry, a respawn and a
	-- round start all come through CharacterAdded.
	table.insert(session.Connections, Players.PlayerAdded:Connect(function(player)
		session.GraceUntil[player] = os.clock() + CONFIG.GraceSeconds
	end))
	for _, player in ipairs(Players:GetPlayers()) do
		session.GraceUntil[player] = os.clock() + CONFIG.GraceSeconds
		table.insert(session.Connections, player.CharacterAdded:Connect(function()
			session.GraceUntil[player] = os.clock() + CONFIG.GraceSeconds
		end))
	end

	publish(session, "State", Brain.PATROL)
	publish(session, "Animation", "Walk")
	publish(session, "PathStatus", "IDLE")
	publish(session, "TargetUserId", 0)
	workspace:SetAttribute("Level4NeighbourActive", true)
	return session
end

function Controller.Stop()
	local session = activeSession
	activeSession = nil
	if not session then return end
	session.Running = false
	for _, connection in ipairs(session.Connections) do
		if connection.Connected then connection:Disconnect() end
	end
	table.clear(session.Connections)
	table.clear(session.GraceUntil)
	session.Waypoints = nil
	if session.Model and session.Model.Parent then
		CollectionService:RemoveTag(session.Model, CONFIG.DetectorTag)
		session.Model:Destroy()
	end
	workspace:SetAttribute("Level4NeighbourActive", false)
	local folder = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	if folder then
		folder:SetAttribute("Level4_NeighbourState", "OFF")
		folder:SetAttribute("Level4_NeighbourTargetUserId", 0)
		folder:SetAttribute("Level4_NeighbourPathStatus", "OFF")
		folder:SetAttribute("Level4_NeighbourSpeed", 0)
	end
end

function Controller.GetSnapshot(): any
	local session = activeSession
	if not session then return nil end
	return {
		State = session.State,
		Goal = session.Goal,
		GoalKind = session.GoalKind,
		PathFailures = session.PathFailures,
		TargetUserId = session.Sense.VisibleUserId or 0,
		Position = session.Root and session.Root.Position or nil,
	}
end

return Controller
