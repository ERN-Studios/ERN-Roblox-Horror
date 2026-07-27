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
local TRACK_TIME        = 5     -- after LOSING sight it still knows your live position this long

-- lunge: when a chase gets close it dashes to WHERE YOU ARE and stops there —
-- a committed pounce, not an endless slide. Contact still kills via EntityKill;
-- it locks its target at the start so it's dodgeable. Animation comes later.
local LUNGE_RANGE       = 12    -- starts a lunge when this close during a chase
local LUNGE_WINDUP      = 0.5   -- it FREEZES this long first (telegraph) before pouncing
local LUNGE_SPEED       = 42    -- dash speed toward the captured spot
local LUNGE_MAX_TIME    = 0.6   -- safety cap on the dash (it stops on arrival)
local LUNGE_RECOVER     = 0.35  -- brief dead stop after it lands (kills the ice-slide)
local LUNGE_COOLDOWN    = 10    -- min seconds between lunges (from wind-up start)

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
local AGENT_RADIUS      = 8     -- pathfinding agent size — bigger keeps paths OFF the
                                -- walls / out of corners while NOT chasing (lurk/search
                                -- are pathfinding-driven). Chase uses the velocity
                                -- override, which still commits into corners after you.
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
local chasePlayer = nil -- the player currently in sight (drives the lunge)
local trackPlayer = nil -- after losing sight it still tracks THIS player's live
local trackUntil = 0    -- position until this time (the TRACK_TIME "memory" window)

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

-- is a maze wall between the entity and a target? Single flat ray at body height
-- — if it hits, a straight run would ram the wall, so hand off to pathfinding to
-- go AROUND the corner. (A wider body-width check made it pathfind INTO corners
-- and wedge, so we keep this to the direct line only.)
local wbParams = RaycastParams.new()
wbParams.FilterType = Enum.RaycastFilterType.Include
local function wallBetween(targetPos)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return false end
	wbParams.FilterDescendantsInstances = { maze }
	local from = root.Position + Vector3.new(0, 2, 0)
	local flat = Vector3.new(targetPos.X - from.X, 0, targetPos.Z - from.Z)
	local d = flat.Magnitude
	if d < 4 then return false end
	-- stop 3 studs short so a wall the player is standing against doesn't count
	return workspace:Raycast(from, flat.Unit * (d - 3), wbParams) ~= nil
end

-- wall-slide: if a wall is close AHEAD in the travel direction, project the
-- heading ONTO the wall so the entity slides along it (and rounds the corner)
-- instead of driving its face into it and lodging there. Three parallel rays
-- (centre + two offsets) so a corner the body would clip is caught too. `dir`
-- must be a unit XZ vector.
local WALL_CLEARANCE = 5
local slideParams = RaycastParams.new()
slideParams.FilterType = Enum.RaycastFilterType.Include
local function wallSlide(pos, dir)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return dir end
	slideParams.FilterDescendantsInstances = { maze }
	local side = Vector3.new(-dir.Z, 0, dir.X) -- perpendicular, horizontal
	local origin0 = pos + Vector3.new(0, 2, 0)
	for _, off in ipairs({ 0, 3.5, -3.5 }) do
		local hit = workspace:Raycast(origin0 + side * off, dir * WALL_CLEARANCE, slideParams)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
			if n.Magnitude > 0.01 then
				n = n.Unit
				local slid = dir - n * dir:Dot(n) -- drop the into-wall component
				if slid.Magnitude > 0.05 then return slid.Unit end
			end
		end
	end
	return dir
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

-- ── maze-layout navigation (the entity KNOWS the whole maze) ──
-- It navigates a CELL GRID it probes by raycast — "is the edge between these two
-- adjacent cells open, or is there a wall?" — and memoises the answer. A BFS on
-- that grid returns a route of corridor-CENTRE waypoints, so walking it can NEVER
-- clip a wall (unlike the navmesh/velocity chase, which did). The grid is learned
-- once at startup, so in-game path queries are instant.
local function gAttr()
	return workspace:GetAttribute("GRID") or 40,
		workspace:GetAttribute("CELL") or 24,
		workspace:GetAttribute("ORIGIN") or -480
end
local function cellXZ(x, z)
	local _, CELL, O = gAttr()
	return O + (x - 0.5) * CELL, O + (z - 0.5) * CELL
end
local function cellOf(pos)
	local GRID, CELL, O = gAttr()
	return math.clamp(math.floor((pos.X - O) / CELL) + 1, 1, GRID),
		math.clamp(math.floor((pos.Z - O) / CELL) + 1, 1, GRID)
end

local navParams = RaycastParams.new()
navParams.FilterType = Enum.RaycastFilterType.Include
local function floorAt(cx, cz)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return nil end
	navParams.FilterDescendantsInstances = { maze }
	local hit = workspace:Raycast(Vector3.new(cx, 9, cz), Vector3.new(0, -15, 0), navParams)
	if hit and hit.Position.Y > -3 then return hit.Position.Y end
	return nil
end

-- memoised + symmetric: can you walk straight between two adjacent cells?
local navOpen = {}
local function edgeKey(x, z, nx, nz)
	if x < nx or (x == nx and z < nz) then return x .. "_" .. z .. "_" .. nx .. "_" .. nz end
	return nx .. "_" .. nz .. "_" .. x .. "_" .. z
end
local function edgeOpen(x, z, nx, nz)
	local k = edgeKey(x, z, nx, nz)
	local c = navOpen[k]; if c ~= nil then return c end
	local res = false
	local maze = workspace:FindFirstChild("Maze")
	if maze then
		local ax, az = cellXZ(x, z)
		local bx, bz = cellXZ(nx, nz)
		local fya, fyb = floorAt(ax, az), floorAt(bx, bz)
		-- both cells must have floor and not be pit cells (it can't cross a pit)
		if fya and fyb
			and not inPitZone(Vector3.new(ax, 0, az))
			and not inPitZone(Vector3.new(bx, 0, bz)) then
			navParams.FilterDescendantsInstances = { maze }
			local a = Vector3.new(ax, fya + 3, az)
			local b = Vector3.new(bx, fyb + 3, bz)
			res = workspace:Raycast(a, b - a, navParams) == nil
		end
	end
	navOpen[k] = res
	return res
end

local function gridBFS(sx, sz, gx, gz)
	if sx == gx and sz == gz then return { { sx, sz } } end
	local GRID = gAttr()
	local key = function(x, z) return x * 1000 + z end
	local q, seen, prev, head = { { sx, sz } }, { [key(sx, sz)] = true }, {}, 1
	while head <= #q do
		local cur = q[head]; head += 1
		if cur[1] == gx and cur[2] == gz then break end
		for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, nz = cur[1] + d[1], cur[2] + d[2]
			if nx >= 1 and nx <= GRID and nz >= 1 and nz <= GRID
				and not seen[key(nx, nz)] and edgeOpen(cur[1], cur[2], nx, nz) then
				seen[key(nx, nz)] = true
				prev[key(nx, nz)] = cur
				q[#q + 1] = { nx, nz }
			end
		end
	end
	if not seen[key(gx, gz)] then return nil end
	local path, cur = {}, { gx, gz }
	while cur do
		table.insert(path, 1, cur)
		cur = prev[key(cur[1], cur[2])]
	end
	return path
end

-- learn the whole layout up front, one row per frame (no hitch), so in-game
-- path queries hit the cache and never raycast
task.spawn(function()
	workspace:WaitForChild("Maze", 60)
	task.wait(1)
	local GRID = gAttr()
	for x = 1, GRID do
		for z = 1, GRID do
			if x < GRID then edgeOpen(x, z, x + 1, z) end
			if z < GRID then edgeOpen(x, z, x, z + 1) end
		end
		task.wait()
	end
	print("[EntityAI] learned the maze layout (" .. GRID .. "x" .. GRID .. ")")
end)

-- follow the grid ONE waypoint per call (non-blocking). Re-plans only when the
-- destination cell changes or the route is used up, so the main loop can react
-- (see/hear a player) every tick instead of committing to a whole path.
local navPath, navIndex, navGoal = nil, 1, nil
local function resetNav() navPath = nil end
local function stepToward(destPos, speed)
	humanoid.WalkSpeed = speed
	local gx, gz = cellOf(destPos)
	if not navPath or not navGoal or navGoal[1] ~= gx or navGoal[2] ~= gz or navIndex > #navPath then
		local sx, sz = cellOf(root.Position)
		navPath = gridBFS(sx, sz, gx, gz)
		navGoal = { gx, gz }
		navIndex = 2 -- cell 1 is where we already are
	end
	if not navPath then -- unreachable on the grid (e.g. across a pit) → straight walk
		humanoid:MoveTo(Vector3.new(destPos.X, root.Position.Y, destPos.Z))
		return
	end
	while navIndex <= #navPath do -- pop any waypoints we've reached
		local cx, cz = cellXZ(navPath[navIndex][1], navPath[navIndex][2])
		local dx, dz = root.Position.X - cx, root.Position.Z - cz
		if dx * dx + dz * dz < 30 then navIndex += 1 else break end
	end
	if navIndex > #navPath then -- in the goal cell → walk to the exact target
		humanoid:MoveTo(Vector3.new(destPos.X, root.Position.Y, destPos.Z))
	else
		local cx, cz = cellXZ(navPath[navIndex][1], navPath[navIndex][2])
		humanoid:MoveTo(Vector3.new(cx, floorAt(cx, cz) or root.Position.Y, cz))
	end
end

-- ── anti-stuck watchdog ───────────────────────────────────
-- if it hasn't moved while it should be walking, drop the cached route so it
-- re-plans from where it actually is — clears any rare physics wedge
task.spawn(function()
	local last = root.Position
	while task.wait(1.2) do
		if humanoid.Health <= 0 then break end
		local moved = (root.Position - last).Magnitude
		last = root.Position
		if moved < 2 and humanoid.WalkSpeed > 0.1 then resetNav() end
	end
end)

-- ── lunge (the only velocity override left) ───────────────
-- Movement is now the grid-walk in the main loop (which never clips a wall). The
-- Heartbeat only runs the LUNGE — a committed pounce when it gets close and has a
-- clear shot. Everything else, it does nothing and lets the grid-walk drive.
RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then return end
	if isPaused() then
		lungePhase = 0
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		return
	end
	if current ~= State.CHASE or not chasePlayer then lungePhase = 0; return end
	local char = chasePlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then lungePhase = 0; return end

	local to = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
	local dist = to.Magnitude
	local now = os.clock()
	local v = root.AssemblyLinearVelocity

	-- phase 1: WIND-UP — freeze + face you (telegraph)
	if lungePhase == 1 then
		humanoid.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		faceFlat(hrp.Position)
		if now >= lungeWindupUntil then
			lungePhase = 2
			lungeTarget = hrp.Position
			lungeUntil = now + LUNGE_MAX_TIME
		end
		return
	end

	-- phase 2: DASH to the captured spot (MoveTo-driven at a high WalkSpeed, so the
	-- legs animate — no velocity override, no ice-glide), then STOP dead
	if lungePhase == 2 then
		local toT = Vector3.new(lungeTarget.X - root.Position.X, 0, lungeTarget.Z - root.Position.Z)
		if toT.Magnitude <= 3 or now >= lungeUntil then
			lungePhase = 0
			lungeRecoverUntil = now + LUNGE_RECOVER
			resetNav() -- re-plan the grid route from where the dash landed
			humanoid.WalkSpeed = 0
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0) -- one-frame hard stop
			humanoid:MoveTo(root.Position)
			return
		end
		humanoid.WalkSpeed = LUNGE_SPEED
		humanoid:MoveTo(lungeTarget)
		return
	end

	-- brief dead stop right after a lunge lands
	if now < lungeRecoverUntil then
		humanoid.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		return
	end

	-- close + clear (no wall or pit between) + off cooldown → wind up a lunge
	if now >= lungeCooldownUntil and dist < LUNGE_RANGE and dist > 1
		and not crossesPitZone(root.Position, hrp.Position)
		and not wallBetween(hrp.Position) then
		lungePhase = 1
		lungeWindupUntil = now + LUNGE_WINDUP
		lungeCooldownUntil = now + LUNGE_COOLDOWN
		workspace:SetAttribute("EntityLunge", (workspace:GetAttribute("EntityLunge") or 0) + 1)
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
	end
	-- otherwise: nothing — the grid-walk (main loop) is doing the moving
end)

-- ── main loop ─────────────────────────────────────────────
-- picks WHO to head for, then grid-walks there (the walk never clips a wall).
-- A slow, relentless, map-aware hunter: even unseen it slowly makes its way to a
-- (random) player; SEEING you speeds it to a chase; HEARING you redirects it.
local HUNT_SPEED    = 11  -- base slow walk toward a random player (via the map)
local HUNT_RETARGET = 60  -- ALWAYS re-rolls which player it hunts after this long
local huntTarget, huntPickedAt = nil, 0

local function livingPlayers()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 and c:FindFirstChild("HumanoidRootPart") then
			table.insert(list, p)
		end
	end
	return list
end

-- position of the player it's currently hunting (re-rolls periodically / when the
-- target dies or leaves) — this is what makes it "slowly find a random player"
local function huntPos()
	local living = livingPlayers()
	if #living == 0 then huntTarget = nil; return nil end
	if not (huntTarget and table.find(living, huntTarget))
		or (os.clock() - huntPickedAt) > HUNT_RETARGET then
		huntTarget = living[math.random(#living)]
		huntPickedAt = os.clock()
		resetNav()
	end
	local hrp = huntTarget.Character and huntTarget.Character:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position
end

task.spawn(function()
	while task.wait(0.1) do
		if humanoid.Health <= 0 then break end
		if isPaused() then
			humanoid.WalkSpeed = 0
			humanoid:MoveTo(root.Position)
			chasePlayer = nil
			resetNav()
			continue
		end
		NoiseRegistry.Prune()

		local yelling = false
		local char, hrp = findVisiblePlayer()

		-- seeing a player (re)opens a TRACK window on them: for TRACK_TIME after it
		-- loses sight it STILL knows their LIVE position and keeps coming
		if char then
			trackPlayer = Players:GetPlayerFromCharacter(char)
			trackUntil = os.clock() + TRACK_TIME
		end

		-- the current chase target: the visible player, else the tracked one while
		-- its window is still open (and it's still alive)
		local targetPlayer, targetHrp = nil, nil
		if char then
			targetPlayer, targetHrp = Players:GetPlayerFromCharacter(char), hrp
		elseif trackPlayer and os.clock() < trackUntil then
			local tc = trackPlayer.Character
			local th = tc and tc:FindFirstChild("HumanoidRootPart")
			local thum = tc and tc:FindFirstChildOfClass("Humanoid")
			if th and thum and thum.Health > 0 then
				targetPlayer, targetHrp = trackPlayer, th
			else
				trackPlayer = nil
			end
		end

		if targetHrp then
			if current ~= State.CHASE then current = State.CHASE; resetNav() end
			chasePlayer = targetPlayer
			lastKnownPos = targetHrp.Position
			local seen = char ~= nil -- truly in sight vs tracking blind

			if seen and inPitZone(targetHrp.Position) then
				-- player on the beams: grid-walk to the pit EDGE, face them, yell
				local edge = pitEdgeToward(targetHrp.Position, root.Position)
				local toEdge = Vector3.new(root.Position.X - edge.X, 0, root.Position.Z - edge.Z)
				if toEdge.Magnitude <= YELL_EDGE_DIST then
					yelling = true
					humanoid:MoveTo(root.Position)
					faceFlat(targetHrp.Position)
					tryYell(char, targetHrp)
				else
					stepToward(edge, SPEED_CHASE * speedMul())
				end
			elseif lungePhase == 0 then
				-- CLEAR SHOT → beeline straight to them (don't zig-zag through cell
				-- centres / detour to the middle of the room). Only grid-walk when a
				-- wall or pit is actually in the way. (Heartbeat lunges when close.)
				if wallBetween(targetHrp.Position)
					or crossesPitZone(root.Position, targetHrp.Position) then
					stepToward(targetHrp.Position, SPEED_CHASE * speedMul())
				else
					humanoid.WalkSpeed = SPEED_CHASE * speedMul()
					humanoid:MoveTo(Vector3.new(targetHrp.Position.X, root.Position.Y, targetHrp.Position.Z))
					resetNav() -- so it re-plans fresh when a wall next blocks the line
				end
			end

		else
			chasePlayer = nil
			trackPlayer = nil -- track window is over
			if current == State.CHASE then
				current = State.SEARCH
				searchUntil = os.clock() + SEARCH_TIME
				resetNav()
			end

			-- HEARING redirects it to a fresh footstep noise
			local noise = NoiseRegistry.GetBest(root.Position, HEAR_RANGE)
			if noise then
				current = State.INVESTIGATE
				stepToward(noise.pos, SPEED_INVESTIGATE * speedMul())

			elseif current == State.SEARCH and os.clock() < searchUntil and lastKnownPos then
				current = State.SEARCH
				stepToward(lastKnownPos, SPEED_INVESTIGATE * speedMul())

			else
				-- HUNT: always, slowly, make its way toward a (random) player
				current = State.LURK
				local hp = huntPos()
				if hp then stepToward(hp, HUNT_SPEED * speedMul()) end
			end
		end

		local pubState = current
		-- in CHASE but can't actually SEE them = blindly tracking (the memory
		-- window). Publish TRACK so SoundController can slowly fade the chase music.
		if current == State.CHASE and not char then pubState = "TRACK" end
		if yelling or os.clock() < yellActiveUntil then pubState = "YELL" end
		workspace:SetAttribute("EntityState", pubState)
	end
end)
