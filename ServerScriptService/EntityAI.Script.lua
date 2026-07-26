-- EntityAI
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityAI"
-- REQUIRES: a model named "Entity" in Workspace with a Humanoid, a HumanoidRootPart,
--           and PrimaryPart set. All parts CanCollide = false except the root.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- NoiseRegistry must be a ModuleScript that `return`s its table. If it's the
-- wrong object type, empty, or errors, we don't want it to kill the whole
-- entity + noise pipeline (that also leaves ReportNoise unconnected → its
-- queue exhausts). Load defensively and fall back to a no-op (hearing off).
local NoiseRegistry
do
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild("NoiseRegistry"))
	end)
	if ok and type(mod) == "table" and mod.Add then
		NoiseRegistry = mod
	else
		warn("EntityAI: NoiseRegistry failed to load (" .. tostring(mod) ..
			") — is it a ModuleScript that returns its table? Hearing disabled.")
		NoiseRegistry = {
			Add = function() end,
			Prune = function() end,
			GetBest = function() return nil end,
		}
	end
end

-- ── noise intake ──────────────────────────────────────────
-- connected FIRST, before waiting on the Entity, so the ReportNoise queue is
-- always drained even if the Entity is missing / not yet built. Otherwise the
-- events pile up on the server → "invocation queue exhausted" warnings.
local lastReport = {}
local lastYell = {}    -- per-player yell cooldown (declared early: used just below)
local immunePush = {}  -- dev cheat: players who are immune to the yell push-back
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
Players.PlayerRemoving:Connect(function(p)
	lastReport[p] = nil; lastYell[p] = nil; immunePush[p] = nil
end)

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
local SIGHT_CLOSE       = 48    -- within this it notices you even outside its cone
local HEAR_RANGE        = 220
local SPEED_LURK        = 8
local SPEED_INVESTIGATE = 15
local SPEED_CHASE       = 27.2  -- just faster than a sprinting player (sprint = 26)
local SEARCH_TIME       = 12

-- lunge: when a chase gets close it dashes to WHERE YOU ARE and stops there —
-- a committed pounce, not an endless slide. Contact still kills via EntityKill;
-- it locks its target at the start so it's dodgeable. Animation comes later.
local LUNGE_RANGE       = 12    -- starts a lunge when this close during a chase
local LUNGE_WINDUP      = 0.5   -- it FREEZES this long first (telegraph) before pouncing
local LUNGE_SPEED       = 42    -- dash speed toward the captured spot
local LUNGE_MAX_TIME    = 0.6   -- safety cap on the dash (it stops on arrival)
local LUNGE_RECOVER     = 0.35  -- brief dead stop after it lands (kills the ice-slide)
local LUNGE_COOLDOWN    = 2.5   -- min seconds between lunges (from wind-up start)

-- yell: it can't walk onto the pit beams, so it first WALKS TO THE PIT EDGE
-- nearest you, faces you, winds up, then roars and shoves you off with a STEADY
-- push (like a gust of wind). Gravity stays free, so once you're pushed off the
-- beam edge you fall. The roar animation is owned by EntityAnimation (PlayYell).
local YELL_PUSH         = 12    -- push speed it aims for (studs/s; sprint is 26)
local YELL_FORCE        = 2200  -- how hard it shoves — LOW enough that you can walk
                                -- AGAINST it (raise to make it harder to resist)
local YELL_DURATION     = 3     -- seconds the steady push lasts
local YELL_COOLDOWN     = 10    -- min seconds between yells at the same player (> duration)
local YELL_WINDUP       = 0.6   -- pause after the roar before the push lands (sync w/ anim)
local YELL_SOUND_LEAD   = 0.5   -- start the SOUND this long before the anim (it has an inhale)
local YELL_EDGE_DIST    = 6     -- how close to the pit edge it must get before yelling
local AGENT_RADIUS      = 6     -- pathfinding agent size — bigger keeps paths OFF the
                                -- walls (walks nearer room centres); raise if model is big
local AGENT_HEIGHT      = 8
local WAYPOINT_TIME     = 1.5   -- seconds to reach one waypoint before re-planning
-- ──────────────────────────────────────────────────────────
-- (The Entity's growl now lives with every other sound id in SoundController —
--  ENTITY_SOUND there. This script no longer owns any audio.)

-- ── self fill-light ───────────────────────────────────────
-- The maze runs on very low ambient (horror), so a model that isn't bright-
-- coloured reads as near-black even with lights nearby. Subtle PointLights on
-- the entity lift the model itself out of pure black without flooding the room.
-- One at the head and one at the torso, so the WHOLE body catches some fill
-- instead of only the inner faces near a single bulb. Turn FILL_BRIGHTNESS to 0
-- if you'd rather it only catch real lights.
-- (The proper fix for dark moving models is Lighting → Technology → Future in
-- Studio, which lights MeshParts per-pixel; this is a safety net either way.)
local FILL_BRIGHTNESS = 1.1  -- per light (two lights, so a touch lower each)
local FILL_RANGE      = 14
for _, host in ipairs({ entity:FindFirstChild("Head"), root }) do
	if host then
		local fill = Instance.new("PointLight")
		fill.Name = "FillLight"
		fill.Brightness = FILL_BRIGHTNESS
		fill.Range = FILL_RANGE
		fill.Color = Color3.fromRGB(255, 250, 245)
		fill.Shadows = false
		fill.Parent = host
	end
end

-- ── dev: pause the entity (from DevCheats, testing only) ───
-- DevCheats (client) fires DevControl; we flip a workspace attribute the AI
-- loops read. Safe to ship without DevControl existing — we just skip it.
local DEV_ALLOWED = {} -- empty = anyone; add usernames to lock it down
local function devAllowed(p)
	if #DEV_ALLOWED == 0 then return true end
	for _, n in ipairs(DEV_ALLOWED) do if n == p.Name then return true end end
	return false
end
-- wait for the RemoteEvent in a task (robust to load order) so the handler
-- always connects if DevControl exists at all
task.spawn(function()
	local remotes = RS:WaitForChild("Remotes", 20)
	local devControl = remotes and remotes:WaitForChild("DevControl", 20)
	if not devControl then
		warn("EntityAI: DevControl RemoteEvent not found — P/I dev cheats disabled")
		return
	end
	devControl.OnServerEvent:Connect(function(p, cmd, arg)
		if not devAllowed(p) then return end
		if cmd == "pauseEntity" then
			workspace:SetAttribute("EntityPaused", arg == true)
			print("[EntityAI] pause =", arg == true, "by", p.Name)
		elseif cmd == "immunePush" then
			immunePush[p] = (arg == true) or nil -- immune to the yell push-back
			print("[EntityAI] push-immunity =", immunePush[p] == true, "for", p.Name)
		end
	end)
	print("[EntityAI] DevControl handler connected")
end)
local function isPaused() return workspace:GetAttribute("EntityPaused") == true end

-- safety net for the push-immunity dev cheat: an immune player never keeps a
-- YellPush, even one applied the instant before they toggled immunity on
RunService.Heartbeat:Connect(function()
	for p in pairs(immunePush) do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local push = hrp and hrp:FindFirstChild("YellPush")
		if push then push:Destroy() end
	end
end)

-- puzzle difficulty: PuzzleManager raises this as fuses are inserted
local function speedMul() return workspace:GetAttribute("EntitySpeedMul") or 1 end

local State = { LURK = "LURK", INVESTIGATE = "INVESTIGATE",
	CHASE = "CHASE", SEARCH = "SEARCH" }

local current = State.LURK
local lastKnownPos = nil
local searchUntil = 0
local moveToken = 0
local chasePlayer = nil -- the player being chased (steered every frame)
local lurkTarget = nil  -- current patrol goal (a room-middle it walks toward)
local lurkPickedAt = 0

-- lunge state (driven in the chase Heartbeat)
local lungePhase = 0            -- 0 idle · 1 wind-up (frozen telegraph) · 2 dashing
local lungeTarget = Vector3.zero
local lungeWindupUntil = 0      -- end of the freeze/telegraph
local lungeUntil = 0            -- safety timeout for the current dash
local lungeCooldownUntil = 0
local lungeRecoverUntil = 0     -- brief post-lunge dead stop
local yellActiveUntil = 0       -- while >now the entity is mid-yell (chase sound off)
-- (lastYell is declared up top — it's used by the PlayerRemoving cleanup there)

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

-- is a maze wall between the entity and a target? Cast flat at body height (not
-- the lenient eye-to-head sight ray) — if it hits, a straight run would ram the
-- wall, so we hand off to pathfinding to go AROUND the corner instead.
local function wallBetween(targetPos)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return false end
	local from = root.Position + Vector3.new(0, 2, 0)
	local flat = Vector3.new(targetPos.X - from.X, 0, targetPos.Z - from.Z)
	local d = flat.Magnitude
	if d < 4 then return false end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { maze }
	-- stop 3 studs short so a wall the player is standing against doesn't count
	local hit = workspace:Raycast(from, flat.Unit * (d - 3), rp)
	return hit ~= nil
end

-- turn to face a target (flat), so it doesn't stare into the air at a pit player
local function faceFlat(targetPos)
	local look = Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
	if (look - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, look)
	end
end

-- walk-up point on the entity's side of the pit, stepping from the pit player
-- back toward the entity until we're off the hole field (the near edge)
local function pitEdgeToward(pitPos, entityPos)
	local dir = Vector3.new(entityPos.X - pitPos.X, 0, entityPos.Z - pitPos.Z)
	if dir.Magnitude < 1 then return entityPos end
	dir = dir.Unit
	for d = 4, 240, 4 do
		local pt = pitPos + dir * d
		if not inPitZone(pt) then
			return pt + dir * 2 -- a touch past the edge, onto solid floor
		end
	end
	return entityPos
end

-- how open is a point? min distance to a wall in the 4 directions — higher means
-- more like the middle of a room. Used to make LURK patrol through open rooms.
local function openness(cx, cz, y)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return 0 end
	local origin = Vector3.new(cx, y, cz)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { maze }
	local minD, reach = math.huge, 90
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		local hit = workspace:Raycast(origin, d * reach, rp)
		minD = math.min(minD, hit and (hit.Position - origin).Magnitude or reach)
	end
	return minD
end

-- pick a LURK destination biased toward the middle of an open room (the most
-- open of a handful of random cells), so it roams THROUGH rooms rather than
-- jittering in corners
local function pickLurkTarget()
	local GRID = workspace:GetAttribute("GRID") or 40
	local CELL = workspace:GetAttribute("CELL") or 24
	local O = workspace:GetAttribute("ORIGIN") or -480
	local y = root.Position.Y
	local best, bestScore
	for _ = 1, 14 do
		local x = math.random(2, GRID - 1)
		local z = math.random(2, GRID - 1)
		local cx = O + (x - 0.5) * CELL
		local cz = O + (z - 0.5) * CELL
		if not inPitZone(Vector3.new(cx, y, cz)) then
			local score = openness(cx, cz, y)
			if not bestScore or score > bestScore then
				best, bestScore = Vector3.new(cx, y, cz), score
			end
		end
	end
	return best
end

-- YELL: shove a player who's out over a pit off their beam. Instead of a single
-- nudge, hold a STEADY horizontal velocity for YELL_DURATION (like being blown
-- back by the roar). A BodyVelocity forces the horizontal velocity constant and
-- overpowers their walking; Y is left unforced so gravity still pulls them into
-- the pit once they're off the edge. It replicates to the owning client, so no
-- network-ownership juggling is needed.
local function tryYell(char, hrp)
	local p = Players:GetPlayerFromCharacter(char)
	local now = os.clock()
	if p and lastYell[p] and now - lastYell[p] < YELL_COOLDOWN then return end
	if p then lastYell[p] = now end
	-- mark the whole yell (lead + wind-up + push) so the chase sound goes quiet
	yellActiveUntil = now + YELL_SOUND_LEAD + YELL_WINDUP + YELL_DURATION

	task.spawn(function()
		-- the roar SOUND has an inhale before the yell, so start it FIRST and
		-- let the inhale play; then trigger the animation so the visual lands on
		-- the actual yell (id lives in SoundController, keyed off this attribute)
		workspace:SetAttribute("EntityYell", (workspace:GetAttribute("EntityYell") or 0) + 1)
		task.wait(YELL_SOUND_LEAD)

		-- roar animation, owned by EntityAnimation (it has the id ready)
		local ev = entity:FindFirstChild("PlayYell")
		if ev then ev:Fire() end

		-- wind up with the roar, THEN shove — so the push lands with the animation
		task.wait(YELL_WINDUP)

		if p and immunePush[p] then return end -- dev cheat: no push-back

		local char2 = p and p.Character or char
		local hrp2 = char2 and char2:FindFirstChild("HumanoidRootPart")
		local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
		if not (hrp2 and hum2 and hum2.Health > 0) then return end
		if not inPitZone(hrp2.Position) then return end -- they already got off

		-- recompute at shove time (they may have shuffled during the wind-up)
		local away = hrp2.Position - root.Position
		away = Vector3.new(away.X, 0, away.Z)
		away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(1, 0, 0)
		local side = Vector3.new(-away.Z, 0, away.X) * (math.random() < 0.5 and -1 or 1)
		local pushDir = (away * 0.85 + side * 0.5)
		pushDir = (pushDir.Magnitude > 0.1) and pushDir.Unit or away

		local existing = hrp2:FindFirstChild("YellPush")
		if existing then existing:Destroy() end
		local bv = Instance.new("BodyVelocity")
		bv.Name = "YellPush"
		-- LIMITED horizontal force (not 1e5) so your walking can fight it — you
		-- can push back against the shove instead of being fully locked. Y free
		-- so gravity still drops you off the beam.
		bv.MaxForce = Vector3.new(1, 0, 1) * YELL_FORCE
		bv.P = 1250
		bv.Velocity = pushDir * YELL_PUSH
		bv.Parent = hrp2
		task.delay(YELL_DURATION, function()
			if bv and bv.Parent then bv:Destroy() end
		end)
	end)
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

	-- right next to it, OR out over a pit (where it wants to yell you off a
	-- beam) → noticed regardless of which way it's facing. Pit players kept
	-- getting missed because they stand still (no noise) and outside the cone.
	if dist < SIGHT_CLOSE or inPitZone(hrp.Position) then
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
	if humanoid.Health <= 0 then return end
	if isPaused() then -- dev pause: hold it in place every frame
		lungePhase = 0
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		return
	end
	if current ~= State.CHASE or not chasePlayer then lungePhase = 0; return end
	local char = chasePlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or crossesPitZone(root.Position, hrp.Position) then lungePhase = 0; return end
	-- a wall is in the way → don't drive straight into it; the main loop's
	-- pathfinding takes over and routes around the corner (skip while lunging)
	if lungePhase == 0 and wallBetween(hrp.Position) then return end

	local to = hrp.Position - root.Position
	to = Vector3.new(to.X, 0, to.Z)
	local dist = to.Magnitude
	local now = os.clock()
	local v = root.AssemblyLinearVelocity

	-- ── LUNGE state machine ──
	-- phase 1: WIND-UP — freeze in place and face you for LUNGE_WINDUP seconds,
	-- clearly telegraphing "I'm about to pounce"
	if lungePhase == 1 then
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		faceFlat(hrp.Position)
		if now >= lungeWindupUntil then
			lungePhase = 2
			lungeTarget = hrp.Position          -- lock the target at launch
			lungeUntil = now + LUNGE_MAX_TIME
		end
		return
	end

	-- phase 2: DASH to the captured spot, then STOP dead (no ice-slide)
	if lungePhase == 2 then
		local toT = Vector3.new(lungeTarget.X - root.Position.X, 0, lungeTarget.Z - root.Position.Z)
		if toT.Magnitude <= 3 or now >= lungeUntil then
			lungePhase = 0
			lungeRecoverUntil = now + LUNGE_RECOVER
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			humanoid:MoveTo(root.Position)
			return
		end
		local dir = toT.Unit
		root.AssemblyLinearVelocity =
			Vector3.new(dir.X * LUNGE_SPEED, v.Y, dir.Z * LUNGE_SPEED)
		humanoid:MoveTo(lungeTarget)
		return
	end

	-- brief dead stop right after a lunge lands
	if now < lungeRecoverUntil then
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		return
	end

	-- close enough + off cooldown → BEGIN a wind-up (also fires the telegraph
	-- sound via the EntityLunge attribute)
	if now >= lungeCooldownUntil and dist < LUNGE_RANGE and dist > 1 then
		lungePhase = 1
		lungeWindupUntil = now + LUNGE_WINDUP
		lungeCooldownUntil = now + LUNGE_COOLDOWN
		workspace:SetAttribute("EntityLunge", (workspace:GetAttribute("EntityLunge") or 0) + 1)
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		return
	end

	-- normal chase steering
	if dist > 1 then
		local dir = to.Unit
		local sp = humanoid.WalkSpeed
		-- override the horizontal velocity so it changes direction INSTANTLY
		-- (no Humanoid acceleration lag = no sliding when you juke around it).
		-- Y is preserved so gravity still applies.
		root.AssemblyLinearVelocity = Vector3.new(dir.X * sp, v.Y, dir.Z * sp)
		humanoid:MoveTo(hrp.Position) -- keeps it turned/animating toward you
	end
end)

-- ── main loop ─────────────────────────────────────────────
-- decides state (spot / lose / hear); chase movement is the Heartbeat above
task.spawn(function()
	while task.wait(0.1) do
		if humanoid.Health <= 0 then break end
		if isPaused() then -- dev pause: stop dead, drop any target, don't plan
			humanoid.WalkSpeed = 0
			humanoid:MoveTo(root.Position)
			interrupt()
			chasePlayer = nil
			continue
		end
		NoiseRegistry.Prune()

		local yelling = false -- true while parked at a pit edge dealing with a pit player
		local char, hrp = findVisiblePlayer()

		if char then
			if current ~= State.CHASE then
				interrupt()
				current = State.CHASE
				humanoid.WalkSpeed = SPEED_CHASE * speedMul()
			end
			chasePlayer = Players:GetPlayerFromCharacter(char)
			lastKnownPos = hrp.Position

			if inPitZone(hrp.Position) then
				-- player out on the beams: walk to the pit EDGE nearest them,
				-- face them, and only yell once we're actually at the edge
				local edge = pitEdgeToward(hrp.Position, root.Position)
				local toEdge = Vector3.new(root.Position.X - edge.X, 0, root.Position.Z - edge.Z)
				if toEdge.Magnitude <= YELL_EDGE_DIST then
					yelling = true                 -- parked at the edge → not "chasing"
					humanoid:MoveTo(root.Position) -- stop dead at the edge
					faceFlat(hrp.Position)         -- point at them, not into the air
					tryYell(char, hrp)             -- winds up, then shoves them off
				else
					humanoid.WalkSpeed = SPEED_CHASE * speedMul()
					pathTo(edge, moveToken)
				end

			-- straight-line chase is steered every frame by the Heartbeat above.
			-- If a pit OR a wall is in the way, pathfind AROUND it (this is what
			-- stops it ramming corners and getting stuck).
			elseif crossesPitZone(root.Position, hrp.Position)
				or wallBetween(hrp.Position) then
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
				-- patrol toward the middle of an open room; keep the same goal
				-- until we reach it (or after a while), so it actually crosses
				-- rooms instead of re-rolling a nearby point every tick
				local reached = lurkTarget and Vector3.new(
					root.Position.X - lurkTarget.X, 0, root.Position.Z - lurkTarget.Z).Magnitude < 8
				if not lurkTarget or reached or (os.clock() - lurkPickedAt) > 10 then
					lurkTarget = pickLurkTarget()
					lurkPickedAt = os.clock()
				end
				if lurkTarget then
					pathTo(lurkTarget, moveToken)
				else
					pathTo(root.Position + Vector3.new(
						math.random(-70, 70), 0, math.random(-70, 70)), moveToken)
				end
			end
		end

		-- publish state so SoundController knows when it's just roaming (idle
		-- vocalisations) vs actively hunting vs mid-yell (chase sound off)
		local pubState = current
		if yelling or os.clock() < yellActiveUntil then pubState = "YELL" end
		workspace:SetAttribute("EntityState", pubState)
	end
end)
