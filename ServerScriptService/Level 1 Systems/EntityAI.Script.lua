-- EntityAI
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "EntityAI"
-- REQUIRES: a model named "Entity" in Workspace with a Humanoid, a HumanoidRootPart,
--           and PrimaryPart set. All parts CanCollide = false except the root.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- NoiseRegistry must be a ModuleScript that `return`s its table. If it's the
-- wrong object type, empty, or errors, we don't want it to kill the whole
-- entity + noise pipeline (that also leaves ReportNoise unconnected → its
-- queue exhausts). Load defensively and fall back to a no-op (hearing off).
-- ServerScriptService, not script.Parent: this script lives in the
-- "Level 1 Systems" folder since 2026-09-02, while NoiseRegistry stayed in the
-- root as a shared service. script.Parent yielded here forever.
--
-- And a TIMEOUT, because the fallback below was unreachable without one:
-- WaitForChild with no timeout does not error, it yields, so the pcall never
-- returned and "hearing disabled" could never actually happen.
local ServerScriptService = game:GetService("ServerScriptService")
local NoiseRegistry
do
	local ok, mod = pcall(function()
		return require(ServerScriptService:WaitForChild("NoiseRegistry", 10))
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
local CLIENT_NOISE = {walk = true, sprint = true}
RS:WaitForChild("Remotes"):WaitForChild("ReportNoise").OnServerEvent
	:Connect(function(player, stateName)
		local now = os.clock()
		if lastReport[player] and now - lastReport[player] < 0.15 then return end
		lastReport[player] = now
		if type(stateName) ~= "string" or not CLIENT_NOISE[stateName] then return end
		if player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true then return end
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (humanoid and humanoid.Health > 0 and hrp) then return end
		local horizontalSpeed = Vector3.new(
			hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z
		).Magnitude
		if horizontalSpeed < 2 then return end
		if stateName == "sprint" and horizontalSpeed < 12 then return end
		NoiseRegistry.Add(hrp.Position, stateName)
	end)
Players.PlayerRemoving:Connect(function(p)
	lastReport[p] = nil; lastYell[p] = nil
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
	-- Wait as long as it takes: lobby servers never generate a maze, and a
	-- Studio-fallback server can idle between rounds. Unanchoring before the
	-- floor exists drops the entity past FallenPartsDestroyHeight and every
	-- later round runs with no entity.
	local es = workspace:FindFirstChild("EntityStart")
	while not es and root.Parent do
		task.wait(0.25)
		es = workspace:FindFirstChild("EntityStart")
	end
	if not (es and root.Parent) then return end
	task.wait(0.1)
	local bbox, size = entity:GetBoundingBox()
	local pivot = entity:GetPivot()
	entity:PivotTo(CFrame.new(es.CFrame.X, 0.5 + (pivot.Y - (bbox.Y - size.Y / 2)), es.CFrame.Z))
	root.Anchored = false
	-- CRITICAL: the SERVER must own the entity's physics forever. By default an
	-- unanchored NPC near a player is simulated on THAT PLAYER'S machine — every
	-- control change then does a network round-trip and the entity coasts through
	-- turns like a car on ice (worst exactly when it's close to someone).
	pcall(function() root:SetNetworkOwner(nil) end)
	-- verify the claim in the console (run up to the entity, watch this line):
	task.spawn(function()
		while root.Parent and not root.Anchored do
			local ok, owner = pcall(function() return root:GetNetworkOwner() end)
			if ok then
				if owner ~= nil then
					warn("[EntityAI] physics owner is " .. owner.Name .. " — NOT the server! (this causes the ice-glide)")
				end
			end
			task.wait(5)
		end
	end)
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

-- ── stop it sliding "on ice" ──────────────────────────────
-- The imported rig is heavy: it carries so much momentum that the Humanoid can't
-- kill the sideways drift in time and it sails PAST corners (a car braking on
-- ice). Two fixes: (1) strip the mass off every non-root limb so the whole
-- assembly is light and turns on a dime; (2) give the grounded root very high
-- friction so it grips the floor instead of skating. Re-applied to any part that
-- streams in later.
local GRIP = PhysicalProperties.new(
	1.0,   -- density
	2.0,   -- friction (Roblox maximum; grips hard without runtime clamping)
	0,     -- elasticity (no bounce)
	100,   -- frictionWeight (dominate the floor's friction)
	1      -- elasticityWeight
)
for _, d in ipairs(entity:GetDescendants()) do
	if d:IsA("BasePart") and d ~= root then d.Massless = true end
end
root.CustomPhysicalProperties = GRIP
entity.DescendantAdded:Connect(function(d)
	if d:IsA("BasePart") and d ~= root then d.Massless = true end
end)

-- ── drift killer ──────────────────────────────────────────
-- Belt-and-braces on top of the network-ownership fix: every physics step,
-- any velocity that ISN'T pointing where the Humanoid is trying to walk gets
-- cancelled — sideways momentum can never carry it past a corner. When it's
-- not trying to move at all, the leftover coast bleeds off in a blink.
--
-- NOTE: intent is read from WalkToPoint (the current MoveTo goal), NOT from
-- Humanoid.MoveDirection — MoveDirection reads ZERO for a server-driven MoveTo
-- humanoid, which made an earlier version brake the entity to a ~4 stud/s crawl.
RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 or root.Anchored then return end
	-- A lunge is deliberately ballistic; do not let the anti-skid safety net
	-- flatten its horizontal velocity while the creature is airborne.
	if workspace:GetAttribute("EntityIsLunging") == true then return end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local goal = humanoid.WalkToPoint
	local toGoal = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if humanoid.WalkSpeed > 0.5 and toGoal.Magnitude > 0.75 then
		-- walking somewhere: keep ALL the forward speed, strip only the skid
		local dir = toGoal.Unit
		local along = math.max(flat:Dot(dir), 0)
		root.AssemblyLinearVelocity = Vector3.new(dir.X * along, v.Y, dir.Z * along)
	elseif humanoid.WalkSpeed <= 0.5 then
		-- deliberately stopped: bleed off any coasting fast
		root.AssemblyLinearVelocity = Vector3.new(flat.X * 0.85, v.Y, flat.Z * 0.85)
	end
	-- (walking but basically AT the goal → leave physics alone; the AI issues a
	-- fresh MoveTo within 0.1s)
end)

-- ── tuning ────────────────────────────────────────────────
local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))
local SIGHT_RANGE       = Master.Effective("L1_EntitySightRange", 650)   -- effectively unlimited — only walls and the cone stop it
local SIGHT_RANGE_LIT   = Master.Effective("L1_EntitySightRangeLit", 1100)  -- flashlight on
local SIGHT_ANGLE       = math.rad(135) -- half-angle of the vision cone
local HEAR_RANGE        = Master.Effective("L1_EntityHearRange", 220)
local SPEED_LURK        = Master.Effective("L1_EntityLurkSpeed", 8)
local SPEED_INVESTIGATE = 8     -- heard a player: normal walk, never a proximity speed-up
local SPEED_CHASE       = Master.Effective("L1_EntityChaseSpeed", 27.2)  -- sprint is 26
local SPEED_LOST        = 17    -- alert search pace after LOS is broken
local SEARCH_TIME       = 12
local TRACK_TIME        = Master.Effective("L1_EntityTrackSeconds", 5)     -- keeps your live position this long after losing sight
local SPOT_HOWL_TIME    = 2.2   -- 66 frames at 30 fps: finish howl before chase
local SPOT_COOLDOWN     = 7     -- avoids repeated howls on rapid reacquisition

-- lunge: when a chase gets close it dashes to WHERE YOU ARE and stops there —
-- a committed pounce, not an endless slide. Contact still kills via EntityKill;
-- it locks its target at the start so it's dodgeable. Animation comes later.
local LUNGE_RANGE       = 28    -- former 12 + requested 16 studs; still chance/cooldown gated
local LUNGE_WINDUP      = 0.32  -- short readable crouch before the physical jump
local LUNGE_SPEED       = 62    -- enough horizontal travel to threaten from the full 28-stud window
local LUNGE_UP_SPEED    = 42    -- visible arc without Humanoid's default jump impulse taking over
local LUNGE_MAX_TIME    = 0.82  -- lets the stronger jump complete before the safety stop
local LUNGE_RECOVER     = 0.35  -- brief dead stop after it lands (kills the ice-slide)
local LUNGE_COOLDOWN    = 10    -- min seconds between lunges (from wind-up start)
local LUNGE_CHANCE      = Master.Effective("L1_EntityLungeChance", 0.35)  -- rolled once per close-range opportunity

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
-- distant scream broadcast: how often the Entity lets out one of the four
-- "Level 1 Distant Entity Scream" takes (the ids live in SoundController).
-- The SERVER picks the moment and the take so every player hears the same
-- scream at the same time, positionally from wherever the Entity is.
local SCREAM_MIN_GAP    = 22    -- min seconds between distant screams
local SCREAM_MAX_GAP    = 55    -- max seconds between them
local SCREAM_TAKES      = 4     -- number of scream slots SoundController exposes
-- ──────────────────────────────────────────────────────────
-- (The Entity's growl now lives with every other sound id in SoundController —
--  ENTITY_SOUND there. This script plays no audio itself; for the distant
--  screams it only publishes WHICH take plays WHEN, via workspace attributes.)

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
		-- The entity model persists across EntityAI restarts (round cleanup only
		-- toggles this script), so drop the previous run's light first.
		local stale = host:FindFirstChild("FillLight")
		if stale then stale:Destroy() end
		local fill = Instance.new("PointLight")
		fill.Name = "FillLight"
		fill.Brightness = FILL_BRIGHTNESS
		fill.Range = FILL_RANGE
		fill.Color = Color3.fromRGB(255, 250, 245)
		fill.Shadows = false
		fill.Parent = host
	end
end

-- ── glowing eyes ──────────────────────────────────────────
-- Two small NEON dots (visible as bright points even far off in the dark) plus
-- a soft PointLight glow that catches nearby walls. Amber while it roams; RED
-- the moment it's hunting someone (CHASE / TRACK / YELL). Mounted on the
-- "EyeL" / "EyeR" attachments on the rig (the modeller places those); if
-- they're missing it falls back to Head-offset knobs so it still works.
local EYE_COLOR_IDLE   = Color3.fromRGB(255, 190, 110) -- soft amber, roaming
local EYE_COLOR_HUNT   = Color3.fromRGB(255, 38, 28)   -- red, after someone
local EYE_DOT_SIZE     = 0.18  -- neon dot diameter (studs)
local EYE_BRIGHTNESS   = 0.7   -- idle glow on nearby surfaces (keep subtle)
local EYE_RANGE        = 9     -- idle glow reach in studs — NOT far, by design
local EYE_ANGLE        = 55    -- glow cone width (degrees) — it shines WHERE IT FACES
local EYE_NUDGE        = 0.15  -- studs the dot is pushed FORWARD out of the face,
-- so the head mesh doesn't swallow the neon
local EYE_HUNT_BRIGHTNESS = 1.5 -- the red glow is angrier…
local EYE_HUNT_RANGE      = 13  -- …and reaches a bit further
-- fallback placement when no EyeL/EyeR attachments exist (offsets from Head):
local EYE_FB_SPACING = 0.4   -- studs between the two eyes
local EYE_FB_UP      = 0.05  -- above the head part's centre
local EYE_FB_FORWARD = 0.6   -- out of the face (-Z)

task.spawn(function()
	-- the modeller can mark the eyes with EITHER:
	--   • two Attachments named EyeL / EyeR (on any part of the rig), or
	--   • two small Parts/MeshParts named EyeL / EyeR (the eyeballs themselves)
	local function findEyes()
		local L, R
		for _, d in ipairs(entity:GetDescendants()) do
			if (d:IsA("Attachment") or d:IsA("BasePart")) then
				if d.Name == "EyeL" then L = d
				elseif d.Name == "EyeR" then R = d end
			end
		end
		return L, R
	end

	-- give the rig (and the modeller's markers) time to stream in
	local eyeL, eyeR
	for _ = 1, 30 do
		eyeL, eyeR = findEyes()
		if eyeL and eyeR then break end
		task.wait(1)
	end
	if not (eyeL and eyeR) then
		warn("EntityAI: no EyeL/EyeR attachments or parts found — using Head-offset fallback for the eye glow")
		local head = entity:FindFirstChild("Head") or root
		local function fbEye(name, side)
			local at = Instance.new("Attachment")
			at.Name = name
			at.Position = Vector3.new(side * EYE_FB_SPACING / 2, EYE_FB_UP, -EYE_FB_FORWARD)
			at.Parent = head
			return at
		end
		eyeL = eyeL or fbEye("EyeL", -1)
		eyeR = eyeR or fbEye("EyeR", 1)
	end

	print("[EntityAI] eye markers: " .. eyeL:GetFullName() .. " · " .. eyeR:GetFullName())

	-- These authored markers currently sit directly under the Entity model. A
	-- Model has no animated transform, so attach them to the real Head bone while
	-- preserving their exact world-space placement.
	local headBone = entity:FindFirstChild("Head", true)
	if headBone and headBone:IsA("Bone") then
		for _, marker in ipairs({ eyeL, eyeR }) do
			if marker:IsA("Attachment") and not marker:FindFirstAncestorWhichIsA("Bone") then
				local authoredWorld = marker.WorldCFrame
				marker.Parent = headBone
				marker.CFrame = headBone.WorldCFrame:ToObjectSpace(authoredWorld)
			end
		end
	end

	local eyes = {}
	for _, marker in ipairs({ eyeL, eyeR }) do
		local ok, err = pcall(function()
			-- The persistent entity keeps last run's eye instances across EntityAI
			-- restarts; clear them so lights and billboards never stack.
			local staleGlow = marker:FindFirstChild("EyeGlow")
			if staleGlow then staleGlow:Destroy() end
			local staleLight = marker:FindFirstChild("EyeLight")
			if staleLight then staleLight:Destroy() end

			local dot
			local glowHost
			if marker:IsA("BasePart") then
				-- he added PARTS: the part IS the eyeball — make it glow directly
				dot = marker
				dot.Material = Enum.Material.Neon
				dot.CastShadow = false
				dot.CanCollide = false
				dot.CanQuery = false -- must never block sight/flashlight raycasts
				dot.CanTouch = false
				dot.Massless = true
				glowHost = dot
			else
				-- Billboard content parented to an Attachment follows Bone deformation.
				-- A welded Part only followed the skinned MeshPart shell and floated.
				local billboard = Instance.new("BillboardGui")
				billboard.Name = "EyeGlow"
				billboard.Adornee = marker
				billboard.Size = UDim2.fromScale(EYE_DOT_SIZE, EYE_DOT_SIZE)
				billboard.StudsOffsetWorldSpace = marker.WorldCFrame.LookVector * EYE_NUDGE
				billboard.AlwaysOnTop = false
				billboard.LightInfluence = 0
				billboard.Parent = marker
				dot = Instance.new("Frame")
				dot.Name = "Dot"
				dot.Size = UDim2.fromScale(1, 1)
				dot.BorderSizePixel = 0
				dot.Parent = billboard
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = dot
				glowHost = marker
			end
			if dot:IsA("GuiObject") then dot.BackgroundColor3 = EYE_COLOR_IDLE else dot.Color = EYE_COLOR_IDLE end

			local glow = Instance.new("SpotLight")
			glow.Name = "EyeLight"
			glow.Face = Enum.NormalId.Front -- out of the emitter's forward face
			glow.Angle = EYE_ANGLE
			glow.Brightness = EYE_BRIGHTNESS
			glow.Range = EYE_RANGE
			glow.Color = EYE_COLOR_IDLE
			glow.Shadows = false
			glow.Parent = glowHost

			table.insert(eyes, { dot = dot, glow = glow })
		end) -- pcall: one bad eye must not kill the other (or the colour watcher)
		if not ok then
			warn("[EntityAI] eye build FAILED for " .. marker:GetFullName() .. ": " .. tostring(err))
		end
	end
	print("[EntityAI] glowing eyes active: " .. #eyes .. "/2")

	local function refreshEyes()
		local st = workspace:GetAttribute("EntityState")
		local hunting = (st == "ALERT" or st == "CHASE" or st == "TRACK" or st == "YELL")
		local c = hunting and EYE_COLOR_HUNT or EYE_COLOR_IDLE
		for _, e in ipairs(eyes) do
			if e.dot:IsA("GuiObject") then e.dot.BackgroundColor3 = c else e.dot.Color = c end
			e.glow.Color = c
			e.glow.Brightness = hunting and EYE_HUNT_BRIGHTNESS or EYE_BRIGHTNESS
			e.glow.Range = hunting and EYE_HUNT_RANGE or EYE_RANGE
		end
	end
	workspace:GetAttributeChangedSignal("EntityState"):Connect(refreshEyes)
	refreshEyes()
end)

local function isPaused()
	return workspace:GetAttribute("EntityPaused") == true
		or workspace:GetAttribute("EntityKillActive") == true
end

-- (No Heartbeat safety net for the push-immunity dev cheat any more: it polled
-- every player every frame for an attribute that is nil in production, and the
-- window it guarded is already closed by the DevPushImmune check in tryYell,
-- which runs with no yield between it and the YellPush it creates. Toggling
-- immunity ON while a push is already in flight now waits out YELL_DURATION.)

-- puzzle difficulty: PuzzleManager raises this as fuses are inserted
local function speedMul() return workspace:GetAttribute("EntitySpeedMul") or 1 end

local State = { LURK = "LURK", INVESTIGATE = "INVESTIGATE",
	ALERT = "ALERT", CHASE = "CHASE", SEARCH = "SEARCH" }

local current = State.LURK
local lastKnownPos = nil
local searchUntil = 0
local chasePlayer = nil -- the player currently in sight (drives the lunge)
local trackPlayer = nil -- after losing sight it still tracks THIS player's live
local trackUntil = 0    -- position until this time (the TRACK_TIME "memory" window)
local spottingPlayer = nil
local spotUntil = 0
local spotCooldownUntil = 0

-- lunge state (driven in the chase Heartbeat)
local lungePhase = 0            -- 0 idle · 1 wind-up (frozen telegraph) · 2 dashing
local lungeTarget = Vector3.zero
local lungeWindupUntil = 0      -- end of the freeze/telegraph
local lungeUntil = 0            -- safety timeout for the current dash
local lungeLaunchAt = 0
local lungeDirection = Vector3.zero
local lungeCooldownUntil = 0
local lungeRecoverUntil = 0     -- brief post-lunge dead stop
local lungeRollArmed = true     -- one chance roll each time the target enters range
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

-- BODY-WIDTH version for the CHASE beeline: the single centre ray can be clear
-- while a shoulder still catches the corner — it then grinds the edge and hangs
-- there. Three parallel rays require the WHOLE body to fit the straight line
-- before it commits to it. Failing this just hands off to the grid-walk, which
-- rounds the corner through the cell centres — so being strict costs nothing.
-- (A wide check was tried before and caused wedging, but that was under the OLD
-- pathfinding movement; with grid navigation the fallback is safe.)
local BEELINE_HALF_W = 2.6 -- half the body width the straight line must clear
local function wallBetweenWide(targetPos)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return false end
	wbParams.FilterDescendantsInstances = { maze }
	local from = root.Position + Vector3.new(0, 2, 0)
	local flat = Vector3.new(targetPos.X - from.X, 0, targetPos.Z - from.Z)
	local d = flat.Magnitude
	if d < 4 then return false end
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for _, off in ipairs({ 0, BEELINE_HALF_W, -BEELINE_HALF_W }) do
		if workspace:Raycast(from + side * off, dir * (d - 3), wbParams) then
			return true
		end
	end
	return false
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
	if p and lastYell[p] and now - lastYell[p] < YELL_COOLDOWN then return false end
	if p then lastYell[p] = now end
	-- mark the whole yell (lead + wind-up + push) so the chase sound goes quiet
	yellActiveUntil = now + YELL_SOUND_LEAD + YELL_WINDUP + YELL_DURATION

	task.spawn(function()
		-- the roar SOUND has an inhale before the yell, so start it FIRST and
		-- let the inhale play; then trigger the animation so the visual lands on
		-- the actual yell (id lives in SoundController, keyed off this attribute)
		workspace:SetAttribute("EntityYell", (workspace:GetAttribute("EntityYell") or 0) + 1)
		local ev = entity:FindFirstChild("PlayYell")
		if ev then ev:Fire() end

		-- wind up with the roar, THEN shove — so the push lands with the animation
		task.wait(YELL_SOUND_LEAD + YELL_WINDUP)

		if p and p:GetAttribute("DevPushImmune") == true then return end

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
	return true
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

-- Decor remains CanQuery=false so it never breaks the player's flashlight.
-- The plaza heap therefore supplies explicit sight-only volumes; test the
-- sight segment against their oriented boxes without Roblox raycasts.
local function segmentHitsBox(from, to, box)
	local a = box.CFrame:PointToObjectSpace(from)
	local b = box.CFrame:PointToObjectSpace(to)
	local delta = b - a
	local half = box.Size * 0.5
	local tMin, tMax = 0, 1
	for _, axis in ipairs({ "X", "Y", "Z" }) do
		local origin, direction, extent = a[axis], delta[axis], half[axis]
		if math.abs(direction) < 1e-5 then
			if origin < -extent or origin > extent then return false end
		else
			local t1 = (-extent - origin) / direction
			local t2 = (extent - origin) / direction
			if t1 > t2 then t1, t2 = t2, t1 end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then return false end
		end
	end
	return true
end

local function blockedByPlazaPile(from, to)
	local decor = workspace:FindFirstChild("Decor")
	if not decor then return false end
	for _, item in ipairs(decor:GetChildren()) do
		if item:IsA("BasePart") and item:GetAttribute("BlocksEntitySight") == true
			and segmentHitsBox(from, to, item) then
			return true
		end
	end
	return false
end

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
		if not blockedByPlazaPile(from, tp) then
			local hit = workspace:Raycast(from, tp - from, losParams)
			-- nothing blocking, or the thing we hit IS the player → visible
			if hit == nil or hit.Instance:IsDescendantOf(char) then
				return true
			end
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
	if inPitZone(hrp.Position) then
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
		-- escaped players are OUT (safe room) — invisible to the entity
		if p:GetAttribute("Escaped") ~= true
			and hrp and hum and hum.Health > 0 and canSee(char, hrp) then
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
-- re-plans from where it actually is — and force the chase onto the GRID for a
-- moment (cell-centre waypoints pull it cleanly off whatever corner caught it)
local forceGridUntil = 0
task.spawn(function()
	local last = root.Position
	while task.wait(1.2) do
		if humanoid.Health <= 0 then break end
		local moved = (root.Position - last).Magnitude
		last = root.Position
		if moved < 2 and humanoid.WalkSpeed > 0.1 then
			resetNav()
			forceGridUntil = os.clock() + 1.5 -- brief grid detour to unwedge
		end
	end
end)

-- ── lunge (the only velocity override left) ───────────────
-- Movement is now the grid-walk in the main loop (which never clips a wall). The
-- Heartbeat only runs the LUNGE — a committed pounce when it gets close and has a
-- clear shot. Everything else, it does nothing and lets the grid-walk drive.
local function launchBallisticLunge(targetPosition, now)
	lungePhase = 2
	lungeTarget = targetPosition
	local launch = Vector3.new(lungeTarget.X - root.Position.X, 0, lungeTarget.Z - root.Position.Z)
	lungeDirection = launch.Magnitude > 0.01 and launch.Unit or root.CFrame.LookVector
	lungeLaunchAt = now
	lungeUntil = now + LUNGE_MAX_TIME
	workspace:SetAttribute("EntityIsLunging", true)
	-- Jumping applies the Humanoid's unrelated JumpPower and can keep
	-- FloorMaterial stale for several frames. Freefall + explicit velocity gives
	-- the same deterministic arc in Studio and live servers.
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = lungeDirection * LUNGE_SPEED + Vector3.new(0, LUNGE_UP_SPEED, 0)
end

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then return end
	if isPaused() then
		lungePhase = 0
		workspace:SetAttribute("EntityIsLunging", false)
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		return
	end
	local now = os.clock()
	local v = root.AssemblyLinearVelocity
	-- Deterministic Studio-only smoke hook. This never runs in a published
	-- server; it lets the automated test verify the real ballistic phase rather
	-- than waiting on the deliberately random gameplay roll.
	if RunService:IsStudio() and workspace:GetAttribute("TestForceEntityLunge") == true
		and lungePhase == 0 then
		workspace:SetAttribute("TestForceEntityLunge", false)
		local testPlayer = Players:GetPlayers()[1]
		local testCharacter = testPlayer and testPlayer.Character
		local testRoot = testCharacter and testCharacter:FindFirstChild("HumanoidRootPart")
		if testRoot then
			current = State.CHASE
			chasePlayer = testPlayer
			launchBallisticLunge(testRoot.Position, now)
		end
	end

	-- A launched pounce is committed to its captured position, even if the
	-- player breaks line of sight while the entity is airborne.
	if lungePhase == 2 then
		local toTarget = Vector3.new(lungeTarget.X - root.Position.X, 0, lungeTarget.Z - root.Position.Z)
		local flightAge = now - lungeLaunchAt
		local landed = flightAge > 0.28
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and root.AssemblyLinearVelocity.Y <= 0
		if toTarget.Magnitude <= 2.5 or landed or now >= lungeUntil then
			lungePhase = 0
			workspace:SetAttribute("EntityIsLunging", false)
			lungeRecoverUntil = now + LUNGE_RECOVER
			resetNav()
			humanoid.WalkSpeed = 0
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			humanoid:MoveTo(root.Position)
			return
		end
		humanoid.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.new(
			lungeDirection.X * LUNGE_SPEED,
			root.AssemblyLinearVelocity.Y,
			lungeDirection.Z * LUNGE_SPEED
		)
		return
	end

	if current ~= State.CHASE or not chasePlayer then
		lungePhase = 0
		workspace:SetAttribute("EntityIsLunging", false)
		return
	end
	local char = chasePlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		lungePhase = 0
		workspace:SetAttribute("EntityIsLunging", false)
		return
	end

	local to = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
	local dist = to.Magnitude
	if dist >= LUNGE_RANGE + 3 then
		lungeRollArmed = true
	end

	-- phase 1: WIND-UP — freeze + face you (telegraph)
	if lungePhase == 1 then
		humanoid.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		faceFlat(hrp.Position)
		if now >= lungeWindupUntil then
			launchBallisticLunge(hrp.Position, now)
		end
		return
	end

	-- phase 2: DASH to the captured spot (MoveTo-driven at a high WalkSpeed, so the
	-- legs animate — no velocity override, no ice-glide), then STOP dead
	-- brief dead stop right after a lunge lands
	if now < lungeRecoverUntil then
		humanoid.WalkSpeed = 0
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		humanoid:MoveTo(root.Position)
		return
	end

	-- Roll ONCE when a target enters the close-range window. A failed roll stays
	-- failed until they create distance and enter again; a successful roll keeps
	-- the original cooldown, so Heartbeat cannot turn the chance into certainty.
	if lungeRollArmed and now >= lungeCooldownUntil and dist < LUNGE_RANGE and dist > 1
		and not crossesPitZone(root.Position, hrp.Position)
		and not wallBetween(hrp.Position) then
		lungeRollArmed = false
		if math.random() <= LUNGE_CHANCE then
			lungePhase = 1
			lungeWindupUntil = now + LUNGE_WINDUP
			lungeCooldownUntil = now + LUNGE_COOLDOWN
			workspace:SetAttribute("EntityLunge", (workspace:GetAttribute("EntityLunge") or 0) + 1)
			workspace:SetAttribute("EntityIsLunging", false)
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			humanoid:MoveTo(root.Position)
		end
	end
	-- otherwise: nothing — the grid-walk (main loop) is doing the moving
end)

-- ── main loop ─────────────────────────────────────────────
-- Neutral behaviour never uses a player's location. It picks open maze cells,
-- walks there, pauses briefly, then picks another. Players only influence it by
-- being seen or heard.
local WANDER_REACH = 5
local WANDER_MIN_TIME = 8
local WANDER_MAX_TIME = 18
local WANDER_PAUSE_MIN = 0.8
local WANDER_PAUSE_MAX = 2.2
local wanderTarget = nil
local wanderRetargetAt = 0
local wanderPauseUntil = 0
local activeObjectiveTarget = nil
local lastChaseTarget = nil -- who currently carries the BeingChased attribute

local function wanderPos(now)
	local objectiveTarget = workspace:GetAttribute("EntityObjectiveTarget")
	if typeof(objectiveTarget) == "Vector3" then
		if activeObjectiveTarget ~= objectiveTarget then
			activeObjectiveTarget = objectiveTarget
			wanderTarget = nil
			resetNav()
		end
		local flat = Vector3.new(objectiveTarget.X - root.Position.X, 0,
			objectiveTarget.Z - root.Position.Z)
		-- Wait near the current objective instead of selecting a random player or
		-- a new room; PuzzleManager advances this marker with the objective stage.
		if flat.Magnitude <= WANDER_REACH + 3 then return nil end
		return objectiveTarget
	elseif activeObjectiveTarget then
		activeObjectiveTarget = nil
		resetNav()
	end
	if wanderTarget then
		local flat = Vector3.new(wanderTarget.X - root.Position.X, 0, wanderTarget.Z - root.Position.Z)
		if flat.Magnitude <= WANDER_REACH then
			wanderTarget = nil
			wanderPauseUntil = now + math.random() * (WANDER_PAUSE_MAX - WANDER_PAUSE_MIN) + WANDER_PAUSE_MIN
			resetNav()
		end
	end
	if now < wanderPauseUntil then return nil end
	if not wanderTarget or now >= wanderRetargetAt then
		wanderTarget = pickLurkTarget()
		wanderRetargetAt = now + math.random(WANDER_MIN_TIME, WANDER_MAX_TIME)
		resetNav()
	end
	return wanderTarget
end

local function setChaseMarker(player)
	if player == lastChaseTarget then return end
	if lastChaseTarget then lastChaseTarget:SetAttribute("BeingChased", nil) end
	if player then player:SetAttribute("BeingChased", true) end
	lastChaseTarget = player
end

-- distant scream scheduler: at a random cadence, publish which of the four
-- scream takes plays. Every client's SoundController reacts to the
-- EntityScream counter and plays SCREAM_SOUNDS[EntityScreamIndex] positionally
-- at the Entity — one shared scream, heard by the whole server from the
-- Entity's direction. Skipped while it is actively hunting someone (the chase
-- soundscape owns those moments) and while the round isn't running.
task.spawn(function()
	while true do
		task.wait(math.random(SCREAM_MIN_GAP, SCREAM_MAX_GAP))
		if humanoid.Health <= 0 then break end
		if workspace:GetAttribute("RoundActive") ~= true then continue end
		if not root.Parent then continue end
		local st = workspace:GetAttribute("EntityState")
		if st == "ALERT" or st == "CHASE" or st == "YELL" or st == "TRACK" then continue end
		workspace:SetAttribute("EntityScreamIndex", math.random(1, SCREAM_TAKES))
		workspace:SetAttribute("EntityScream", (workspace:GetAttribute("EntityScream") or 0) + 1)
	end
end)

task.spawn(function()
	while task.wait(0.1) do
		if humanoid.Health <= 0 then break end
		if isPaused() then
			humanoid.WalkSpeed = 0
			humanoid:MoveTo(root.Position)
			chasePlayer = nil
			setChaseMarker(nil)
			resetNav()
			continue
		end
		NoiseRegistry.Prune()

		local now = os.clock()
		local yelling = false
		local char, hrp = findVisiblePlayer()
		local visiblePlayer = char and Players:GetPlayerFromCharacter(char) or nil

		-- A newly spotted player gets a complete, stationary howl before pursuit.
		-- Rapid reacquisition inside SPOT_COOLDOWN resumes the chase immediately.
		if current == State.ALERT and now < spotUntil then
			local sc = spottingPlayer and spottingPlayer.Character
			local shrp = sc and sc:FindFirstChild("HumanoidRootPart")
			humanoid.WalkSpeed = 0
			humanoid:MoveTo(root.Position)
			chasePlayer = nil
			if shrp then faceFlat(shrp.Position) end
			setChaseMarker(spottingPlayer)
			workspace:SetAttribute("EntityState", "ALERT")
			continue
		elseif current == State.ALERT then
			current = State.CHASE
			spottingPlayer = nil
			resetNav()
		end

		if char then
			trackPlayer = visiblePlayer
			trackUntil = now + TRACK_TIME
			if current ~= State.CHASE then
				if now >= spotCooldownUntil then
					current = State.ALERT
					spottingPlayer = visiblePlayer
					spotUntil = now + SPOT_HOWL_TIME
					spotCooldownUntil = now + SPOT_COOLDOWN
					trackUntil = spotUntil + TRACK_TIME
					humanoid.WalkSpeed = 0
					humanoid:MoveTo(root.Position)
					faceFlat(hrp.Position)
					local ev = entity:FindFirstChild("PlayHowl")
					if ev then ev:Fire() end
					-- Only the player actually spotted receives the alert-shake serial.
					-- Everyone still hears the spatial spotted-scream through
					-- EntitySpotScream (SPOT_SOUND in SoundController); the pit-shove
					-- roar keeps its own EntityYell channel.
					if visiblePlayer then
						visiblePlayer:SetAttribute(
							"Level1EntityAlertSerial",
							(tonumber(visiblePlayer:GetAttribute("Level1EntityAlertSerial")) or 0) + 1
						)
					end
					-- Publish the exact stationary howl position first. Clients use this
					-- streaming-safe snapshot as a 3D emitter even when the far-away Entity
					-- model itself has not streamed in yet.
					workspace:SetAttribute("EntitySpotPosition", root.Position)
					workspace:SetAttribute("EntitySpotScream", (workspace:GetAttribute("EntitySpotScream") or 0) + 1)
					setChaseMarker(visiblePlayer)
					workspace:SetAttribute("EntityState", "ALERT")
					continue
				else
					current = State.CHASE
					resetNav()
				end
			end
		end

		-- Visible targets are chased at full speed. During the short memory window,
		-- it follows at a faster WALK instead of continuing a full-speed blind chase.
		local targetPlayer, targetHrp = nil, nil
		if char then
			targetPlayer, targetHrp = visiblePlayer, hrp
		elseif trackPlayer and now < trackUntil then
			local tc = trackPlayer.Character
			local th = tc and tc:FindFirstChild("HumanoidRootPart")
			local thum = tc and tc:FindFirstChildOfClass("Humanoid")
			if th and thum and thum.Health > 0 then
				targetPlayer, targetHrp = trackPlayer, th
			else
				trackPlayer = nil
			end
		end
		setChaseMarker(targetPlayer)

		if targetHrp then
			if current ~= State.CHASE then current = State.CHASE; resetNav() end
			local seen = char ~= nil
			chasePlayer = seen and targetPlayer or nil
			lastKnownPos = targetHrp.Position

			if seen and inPitZone(targetHrp.Position) then
				local edge = pitEdgeToward(targetHrp.Position, root.Position)
				local toEdge = Vector3.new(root.Position.X - edge.X, 0, root.Position.Z - edge.Z)
				if toEdge.Magnitude <= YELL_EDGE_DIST then
					humanoid.WalkSpeed = 0
					humanoid:MoveTo(root.Position)
					local velocity = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
					faceFlat(targetHrp.Position)
					yelling = tryYell(char, targetHrp) or now < yellActiveUntil
				else
					stepToward(edge, SPEED_CHASE * speedMul())
				end
			elseif not seen then
				stepToward(targetHrp.Position, SPEED_LOST * speedMul())
			elseif lungePhase == 0 then
				if now < forceGridUntil
					or wallBetweenWide(targetHrp.Position)
					or crossesPitZone(root.Position, targetHrp.Position) then
					stepToward(targetHrp.Position, SPEED_CHASE * speedMul())
				else
					humanoid.WalkSpeed = SPEED_CHASE * speedMul()
					humanoid:MoveTo(Vector3.new(targetHrp.Position.X, root.Position.Y, targetHrp.Position.Z))
					resetNav()
				end
			end
		else
			local lost = lastChaseTarget or trackPlayer
			chasePlayer = nil
			trackPlayer = nil
			if current == State.CHASE or current == State.ALERT then
				current = State.SEARCH
				searchUntil = now + SEARCH_TIME
				resetNav()
				if lost then
					lost:SetAttribute("PostChaseBreath", (lost:GetAttribute("PostChaseBreath") or 0) + 1)
				end
			end
			setChaseMarker(nil)

			local noise = NoiseRegistry.GetBest(root.Position, HEAR_RANGE)
			if noise then
				current = State.INVESTIGATE
				stepToward(noise.pos, SPEED_INVESTIGATE * speedMul())
			elseif current == State.SEARCH and now < searchUntil and lastKnownPos then
				stepToward(lastKnownPos, SPEED_LOST * speedMul())
			else
				current = State.LURK
				local wp = wanderPos(now)
				if wp then
					stepToward(wp, SPEED_LURK * speedMul())
				else
					humanoid.WalkSpeed = 0
					humanoid:MoveTo(root.Position)
				end
			end
		end

		local pubState = current
		if current == State.CHASE and not char then pubState = "TRACK" end
		if yelling or now < yellActiveUntil then pubState = "YELL" end
		workspace:SetAttribute("EntityState", pubState)
	end
end)
