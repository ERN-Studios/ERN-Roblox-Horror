-- EntityAI
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityAI"
-- REQUIRES: a model named "Entity" in Workspace with a Humanoid, a HumanoidRootPart,
--           and PrimaryPart set. All parts CanCollide = false except the root.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NoiseRegistry = require(script.Parent:WaitForChild("NoiseRegistry"))

-- ── noise intake ──────────────────────────────────────────
-- connected FIRST, before waiting on the Entity, so the ReportNoise queue is
-- always drained even if the Entity is missing / not yet built. Otherwise the
-- events pile up on the server → "invocation queue exhausted" warnings.
local lastReport = {}
RS:WaitForChild("Remotes"):WaitForChild("ReportNoise").OnServerEvent
	:Connect(function(player, stateName)
		local now = os.clock()
		if lastReport[player] and now - lastReport[player] < 0.15 then return end
		lastReport[player] = now
		if type(stateName) ~= "string" then return end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		NoiseRegistry.Add(hrp.Position, stateName)
	end)
Players.PlayerRemoving:Connect(function(p) lastReport[p] = nil end)

local entity = workspace:WaitForChild("Entity")
local humanoid = entity:WaitForChild("Humanoid")
local root = entity:WaitForChild("HumanoidRootPart")

-- Hold the entity still until the maze floor exists. Its Studio position has no
-- floor under it, so at server start it free-falls during map generation and is
-- destroyed at FallenPartsDestroyHeight → "the entity never spawns". Anchor it,
-- wait for the maze, drop it on the EntityStart corner, then release.
root.Anchored = true
task.spawn(function()
	workspace:WaitForChild("Maze", 60)
	local es = workspace:WaitForChild("EntityStart", 60)
	task.wait(0.1)
	if es then
		local bbox, size = entity:GetBoundingBox()
		local pivot = entity:GetPivot()
		entity:PivotTo(CFrame.new(es.CFrame.X, 0.5 + (pivot.Y - (bbox.Y - size.Y / 2)), es.CFrame.Z))
	end
	root.Anchored = false
end)

-- put the entity in its collision group so the invisible pit-zone barriers
-- (built by MazeGenerator) stop it — and only it
do
	local PhysicsService = game:GetService("PhysicsService")
	pcall(function() PhysicsService:RegisterCollisionGroup("Entity") end)
	for _, d in ipairs(entity:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = "Entity" end
	end
	entity.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.CollisionGroup = "Entity" end
	end)
end

-- ── tuning ────────────────────────────────────────────────
local SIGHT_RANGE       = 650   -- effectively unlimited — only walls and the cone stop it
local SIGHT_RANGE_LIT   = 1100  -- when the player's flashlight is on
local SIGHT_ANGLE       = math.rad(135) -- half-angle of the vision cone
local SIGHT_CLOSE       = 16    -- within this it notices you even outside its cone
local HEAR_RANGE        = 220
local SPEED_LURK        = 8
local SPEED_INVESTIGATE = 15
local SPEED_CHASE       = 30    -- faster than a sprinting player (sprint = 26)
local SEARCH_TIME       = 12
local AGENT_RADIUS      = 4     -- pathfinding agent size — raise if the model is big
local AGENT_HEIGHT      = 8
local WAYPOINT_TIME     = 1.5   -- seconds to reach one waypoint before re-planning
local ENTITY_SOUND      = ""    -- looping sound emitted BY the entity (growl/drone);
                                -- paste an asset id. Positional — players hear direction.
-- ──────────────────────────────────────────────────────────

-- looping positional sound emitted by the entity (players hear it directionally)
local entitySound = Instance.new("Sound")
entitySound.Name = "EntitySound"
entitySound.Looped = true
entitySound.Volume = 0.6
entitySound.RollOffMode = Enum.RollOffMode.InverseTapered
entitySound.RollOffMinDistance = 8
entitySound.RollOffMaxDistance = 140
entitySound.Parent = root
if ENTITY_SOUND ~= "" then
	entitySound.SoundId = ENTITY_SOUND
	entitySound:Play()
end

-- puzzle difficulty: PuzzleManager raises this as fuses are inserted
local function speedMul() return workspace:GetAttribute("EntitySpeedMul") or 1 end

local State = { LURK = "LURK", INVESTIGATE = "INVESTIGATE",
	CHASE = "CHASE", SEARCH = "SEARCH" }

local current = State.LURK
local lastKnownPos = nil
local searchUntil = 0
local moveToken = 0
local chasePlayer = nil -- the player being chased (steered every frame)

-- ── pit zone awareness ────────────────────────────────────
-- MazeGenerator drops invisible markers in workspace.PitZones; the entity
-- refuses to charge straight across a hole field and routes around instead
local pitZones = {}
task.spawn(function()
	local folder = workspace:WaitForChild("PitZones", 30)
	if not folder then return end
	local function add(p)
		table.insert(pitZones, {
			minX = p.Position.X - p.Size.X / 2, maxX = p.Position.X + p.Size.X / 2,
			minZ = p.Position.Z - p.Size.Z / 2, maxZ = p.Position.Z + p.Size.Z / 2,
		})
	end
	for _, p in ipairs(folder:GetChildren()) do add(p) end
	folder.ChildAdded:Connect(add)
end)

local function inPitZone(pos)
	for _, zn in ipairs(pitZones) do
		if pos.X > zn.minX and pos.X < zn.maxX
			and pos.Z > zn.minZ and pos.Z < zn.maxZ then
			return true
		end
	end
	return false
end

local function crossesPitZone(from, to)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1 then return false end
	dir = dir.Unit
	for d = 4, dist, 6 do
		if inPitZone(from + dir * d) then return true end
	end
	return false
end

-- ── perception ────────────────────────────────────────────
local function sightRangeFor(char)
	local flag = char:FindFirstChild("FlashlightOn")
	return (flag and flag.Value) and SIGHT_RANGE_LIT or SIGHT_RANGE
end

-- clear line of sight from the entity to the player — tested against both the
-- torso and the head so a bit of cover doesn't wrongly hide a visible player
local losParams = RaycastParams.new()
losParams.FilterDescendantsInstances = { entity }
losParams.FilterType = Enum.RaycastFilterType.Exclude

-- real 3D line-of-sight from the entity's eye to SEVERAL points on the player
-- (head, torso, feet) — so a player who's a bit higher or lower is still caught,
-- and it sees through open space both horizontally and vertically. The eye is
-- lifted so a slightly-sunk model still casts from above the floor.
local EYE_UP = 3
local function clearLoS(char)
	local from = root.Position + Vector3.new(0, EYE_UP, 0)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local head = char:FindFirstChild("Head")
	local targets = {}
	if head then table.insert(targets, head.Position) end
	if hrp then
		table.insert(targets, hrp.Position)
		table.insert(targets, hrp.Position - Vector3.new(0, 2.5, 0)) -- feet
	end
	for _, tp in ipairs(targets) do
		local hit = workspace:Raycast(from, tp - from, losParams)
		-- nothing blocking, or the thing we hit IS the player → visible
		if hit == nil or hit.Instance:IsDescendantOf(char) then
			return true
		end
	end
	return false
end

local function canSee(char, hrp)
	-- range + cone measured FLAT (XZ only), so the entity's vertical position
	-- can't throw off detection
	local dir = hrp.Position - root.Position
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local dist = flat.Magnitude
	if dist > sightRangeFor(char) then return false end

	-- right next to it → noticed regardless of facing (you can't sneak up on it)
	if dist < SIGHT_CLOSE then
		return clearLoS(char)
	end

	-- otherwise you must be inside its vision cone; once chasing it's 360°
	if current ~= State.CHASE and dist > 0.01 then
		local fwd = root.CFrame.LookVector
		local flatFwd = Vector3.new(fwd.X, 0, fwd.Z)
		if flatFwd.Magnitude > 0.01 then
			if math.acos(math.clamp(flatFwd.Unit:Dot(flat.Unit), -1, 1)) > SIGHT_ANGLE then
				return false
			end
		end
	end

	return clearLoS(char)
end

local function findVisiblePlayer()
	local bestChar, bestRoot, bestDist = nil, nil, math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")
		if hrp and hum and hum.Health > 0 and canSee(char, hrp) then
			local d = (hrp.Position - root.Position).Magnitude
			if d < bestDist then
				bestChar, bestRoot, bestDist = char, hrp, d
			end
		end
	end
	return bestChar, bestRoot
end

-- ── movement ──────────────────────────────────────────────
local function pathTo(destination, token)
	local path = PathfindingService:CreatePath({
		AgentRadius = AGENT_RADIUS,
		AgentHeight = AGENT_HEIGHT,
		AgentCanJump = false,
		AgentCanClimb = false,
	})

	local ok = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, wp in ipairs(path:GetWaypoints()) do
		if token ~= moveToken then return false end
		humanoid:MoveTo(wp.Position)
		-- time-boxed, interruptible wait — never hang 8s on an unreachable
		-- waypoint (the old MoveToFinished:Wait() is what caused "walking in
		-- place"); give up after WAYPOINT_TIME so the main loop re-plans
		local t0 = os.clock()
		while true do
			if token ~= moveToken or humanoid.Health <= 0 then return false end
			local dx = root.Position.X - wp.Position.X
			local dz = root.Position.Z - wp.Position.Z
			if (dx * dx + dz * dz) < 16 then break end -- within 4 studs
			if os.clock() - t0 > WAYPOINT_TIME then return false end
			task.wait(0.08)
		end
	end
	return true
end

local function interrupt()
	moveToken += 1
end

-- ── anti-stuck watchdog ───────────────────────────────────
-- if it hasn't moved while it should be walking, cancel the current move so
-- the main loop re-plans — stops it grinding against a wall forever
task.spawn(function()
	local last = root.Position
	while task.wait(2) do
		if humanoid.Health <= 0 then break end
		local moved = (root.Position - last).Magnitude
		last = root.Position
		if moved < 2 and humanoid.WalkSpeed > 0.1 then
			moveToken += 1 -- breaks the time-boxed wait in pathTo within 0.08s
		end
	end
end)

-- ── frame-tight chase steering ────────────────────────────
-- re-aim at the player EVERY frame while chasing, so it tracks your live
-- position with no lag instead of gliding past ("ice"). Pit-crossing is left to
-- the main loop's pathfinding (Heartbeat skips it then).
RunService.Heartbeat:Connect(function()
	if current ~= State.CHASE or not chasePlayer or humanoid.Health <= 0 then return end
	local char = chasePlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or crossesPitZone(root.Position, hrp.Position) then return end

	local to = hrp.Position - root.Position
	to = Vector3.new(to.X, 0, to.Z)
	if to.Magnitude > 1 then
		local dir = to.Unit
		local sp = humanoid.WalkSpeed
		-- override the horizontal velocity so it changes direction INSTANTLY
		-- (no Humanoid acceleration lag = no sliding when you juke around it).
		-- Y is preserved so gravity still applies.
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(dir.X * sp, v.Y, dir.Z * sp)
		humanoid:MoveTo(hrp.Position) -- keeps it turned/animating toward you
	end
end)

-- ── main loop ─────────────────────────────────────────────
-- decides state (spot / lose / hear); chase movement is the Heartbeat above
task.spawn(function()
	while task.wait(0.1) do
		if humanoid.Health <= 0 then break end
		NoiseRegistry.Prune()

		local char, hrp = findVisiblePlayer()

		if char then
			if current ~= State.CHASE then
				interrupt()
				current = State.CHASE
				humanoid.WalkSpeed = SPEED_CHASE * speedMul()
			end
			chasePlayer = Players:GetPlayerFromCharacter(char)
			lastKnownPos = hrp.Position
			-- straight-line chase is steered every frame by the Heartbeat above;
			-- only pit-crossing falls back to (slower) pathfinding here
			if crossesPitZone(root.Position, hrp.Position) then
				pathTo(hrp.Position, moveToken)
			end

		else
			chasePlayer = nil
			-- just lost sight of someone → mark a spot to search
			if current == State.CHASE then
				interrupt()
				current = State.SEARCH
				searchUntil = os.clock() + SEARCH_TIME
			end

			-- HEARING takes priority: a fresh footstep noise always pulls it in.
			-- This is what makes sprinting dangerous when it can't see you.
			local noise = NoiseRegistry.GetBest(root.Position, HEAR_RANGE)
			if noise then
				current = State.INVESTIGATE
				humanoid.WalkSpeed = SPEED_INVESTIGATE * speedMul()
				pathTo(noise.pos, moveToken)

			elseif current == State.SEARCH and os.clock() < searchUntil and lastKnownPos then
				humanoid.WalkSpeed = SPEED_INVESTIGATE * speedMul()
				pathTo(lastKnownPos + Vector3.new(
					math.random(-25, 25), 0, math.random(-25, 25)), moveToken)

			else
				current = State.LURK
				humanoid.WalkSpeed = SPEED_LURK * speedMul()
				pathTo(root.Position + Vector3.new(
					math.random(-70, 70), 0, math.random(-70, 70)), moveToken)
			end
		end
	end
end)
