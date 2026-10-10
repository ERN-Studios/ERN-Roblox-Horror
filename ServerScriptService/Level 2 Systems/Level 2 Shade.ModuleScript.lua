-- Level 2 Shade (SHADE_20261010): the shadow with no owner.
--
-- Owner, 2026-10-10: "man ser den på vægge, søjler og sådan noget i et kort sekund ... den kan komme tættere på en
-- bagfra og hvis man ikke ser på den, så kan man blive konsumeret ind i mørket og dø af den, hvor den går fra skygge til
-- skyggen bliver ægte og kommer ud af væggen eller jorden og trækker en med ned med dens hænder."
--
-- THE RULE A PLAYER CAN LEARN: it hunts one player at a time, from behind. While nobody looks it closes in; the hunted
-- player turning round and holding it in view sends it away. Unseen at arm's length it takes them.
-- Owner, 2026-10-10 (night): "den skal konsekvent komme efter en bagved en hvis man står stille for længe. Står man
-- stille i mere end 10 sek så kommer den efter en og andre spillere kan godt se den, det er spilleren den chaser der
-- skal kigge rundt." So: a player who has not left a four-stud circle for ten seconds is hunted at once, every time
-- (STILL_20261010). Everybody sees the shadow; only the hunted player's look sends it away.
--
-- The server owns: who is hunted, how far behind them the shadow is, where on the map that puts it (a wall or the
-- floor), whether the hunted player has it in view, the warning and the kill. It owns nothing you see or hear:
-- StarterPlayerScripts."Level 2 Shade Client" draws and plays from the state below, and the harmless glimpses on far
-- walls are that script's alone.
--
-- State, replicated as attributes of ReplicatedStorage.Level2Shade (the folder tools/level2_shade/install_shade.py
-- builds; without it, without its meshes, or while its attribute Enabled is not true, Start does nothing and Level 2
-- plays as it did before):
--   ShadeLive      true while a round has the entity running (the client makes glimpses only then)
--   ShadePhase     "idle" | "stalk" | "recoil" | "warn" | "kill"
--   ShadeTarget    UserId of the hunted player, 0 when idle
--   ShadeSerial    goes up by one with every stalk
--   ShadeAnchor    CFrame on the surface. Wall: Position = where the figure's feet meet the wall, LookVector = out of
--                  the wall. Floor: Position = its fingertips, LookVector = up, UpVector = toward the hunted player.
--   ShadeSurface   "wall" | "floor"
--   ShadeDistance  studs between the shadow and the hunted player
-- Events on ReplicatedStorage."Level 2 Remotes"."Level 2 Shade Event":
--   client -> server  "seen", serial                       (the hunted player's client: it is on my screen, unobstructed)
--   server -> client  "recoil", serial, anchor, surface
--                     "warn", serial, userId, floorPoint, direction
--                     "kill", serial, userId, floorPoint, direction, seconds, realmSeconds
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local DeathAdvice = require(ReplicatedStorage:WaitForChild("DeathAdvice"))
local PlayerProtection = require(ServerScriptService:WaitForChild("PlayerProtection"))

local Shade = {}

Shade.Config = {
	GraceSeconds = 45,             -- nothing hunts this long after the round starts
	GapSeconds = {32, 58},         -- quiet between two stalks with one player; shorter with more (see gap)
	AfterWarningGap = {16, 26},    -- it comes back sooner after the one warning
	StartDistance = 46,
	StrikeDistance = 4.5,
	StalkSeconds = 17,             -- StartDistance to StrikeDistance when nobody looks
	FirstStalkSeconds = 22,        -- the first one against each player is slower
	FirstIsWarning = true,         -- and ends in a scare, not a death: the player has not been taught the rule yet
	SeenSeconds = 0.3,             -- how long the hunted player must hold it in view
	SeenReportHold = 0.25,         -- a client report counts for this long
	SeenServerDot = math.cos(math.rad(85)),   -- the body must at least face its side of the world (first person)
	BearingDriftDegrees = 16,      -- per second: it slides round to stay behind a slowly turning player
	RecoilSeconds = 1.4,
	WarnSeconds = 1.8,
	KillSeconds = 3.6,
	RealmSeconds = 3.4,            -- after the drag the victim is in the dark with its face before the death is counted
	StillSeconds = 10,             -- owner: standing still longer than this brings it, every time
	StillRadius = 4,               -- "still" = has not left a circle of this radius
	KillSinkFrom = 1.5,
	KillSinkStuds = 7,
	WallCheckHeight = 5,           -- a wall counts when it is still there this far up: kerbs and steps are floor
	FootDrop = 18,
	FloorDrop = 40,
	RootHeight = 3,                -- root to sole, for a floor nobody could find
	LoudSpeed = 20,                -- a player moving faster than this is running
	LoudWeight = 2,                -- a runner is this much more likely to be picked
	SafeSections = {"S", "P0"},    -- the arrival room and its stairs
	Step = 0.1,
}
local C = Shade.Config

local REQUIRED = {"Shade_Stand", "Shade_Reach", "Shade_Crawl", "Shade_Hands", "Shade_Rise", "Shade_Claw", "Shade_Arm",
	"Shade_ArmGrip", "Shade_Pool"}
local REMOTE_NAME = "Level 2 Shade Event"
local random = Random.new()
local active

local remotes = ReplicatedStorage:WaitForChild("Level 2 Remotes")
local remote = remotes:FindFirstChild(REMOTE_NAME)
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = remotes
end

local function bankReady(force)
	local bank = ReplicatedStorage:FindFirstChild("Level2Shade")
	local meshes = bank and bank:FindFirstChild("Meshes")
	if not meshes or (bank:GetAttribute("Enabled") ~= true and not force) then return nil end
	for _, name in ipairs(REQUIRED) do
		local part = meshes:FindFirstChild(name)
		if not (part and part:IsA("MeshPart")) then return nil end
	end
	return bank
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 1e-4 and f.Unit or nil
end

local function lifeOf(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not root or humanoid.Health <= 0 or not character:IsDescendantOf(workspace) then return nil end
	return character, humanoid, root
end

local function validWorld(handle)
	local world = handle.World
	return active == handle and handle.Stopped ~= true and world.Parent == workspace
		and world:GetAttribute("Level2NewMap") == true and workspace:GetAttribute("SelectedLevel") == 2
end

-- The first thing a ray meets that a player would see as a surface: the map's colliders without its invisible
-- guards, the kill volumes of the pits and the black sheets in them.
local function cast(handle, origin, displacement)
	local length = displacement.Magnitude
	if length < 1e-3 then return nil end
	local unit = displacement / length
	local from, left = origin, length
	for _ = 1, 6 do
		local hit = workspace:Raycast(from, unit * left, handle.Params)
		if not hit then return nil end
		local instance = hit.Instance
		if instance.CanCollide and instance.Name ~= "Hazard" and instance.Name ~= "Veil" and instance.Name ~= "A2ReflectorCollider"
			and not (handle.Guards and instance:IsDescendantOf(handle.Guards)) then
			return hit
		end
		local gone = (hit.Position - from).Magnitude + 0.05
		if gone >= left then return nil end
		from, left = hit.Position + unit * 0.05, left - gone
	end
	return nil
end

local function inSafeSection(handle, position)
	local p = position - handle.Origin
	for _, box in ipairs(handle.Safe) do
		if p.X >= box.min.X and p.X <= box.max.X and p.Y >= box.min.Y and p.Y <= box.max.Y
			and p.Z >= box.min.Z and p.Z <= box.max.Z then return true end
	end
	return false
end

local function eligible(handle, player)
	if player.Parent ~= Players or player:GetAttribute("InRound") ~= true or player:GetAttribute("Escaped") == true
		or player:GetAttribute("Level2_ExitTransition") == true or player:GetAttribute("Spectating") == true then return nil end
	local character, humanoid, root = lifeOf(player)
	if not root or humanoid.SeatPart or root.Anchored then return nil end
	if PlayerProtection.IsActive(player, character) then return nil end
	return character, humanoid, root
end

local function publish(handle, phase, userId)
	local bank = handle.Bank
	bank:SetAttribute("ShadeSerial", handle.Serial)
	bank:SetAttribute("ShadeTarget", userId or 0)
	bank:SetAttribute("ShadePhase", phase)
	handle.Phase = phase
end

local function send(handle, ...)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true then remote:FireClient(player, ...) end
	end
end

local function gap(handle, range)
	local living = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if eligible(handle, player) then living += 1 end
	end
	return random:NextNumber(range[1], range[2]) / (0.55 + 0.45 * math.max(1, living))
end

local function rest(handle, range)
	handle.Stalk = nil
	if handle.LastTarget then handle.Still[handle.LastTarget] = nil end   -- ten new seconds for the one it just left
	handle.NextAt = os.clock() + gap(handle, range or C.GapSeconds)
	publish(handle, "idle", 0)
end

-- Where a shadow `distance` studs from the root along `direction` falls: on the wall in between, or on the floor.
local function place(handle, stalk, root, direction)
	local origin = root.Position
	local reach = math.max(stalk.Distance, 0.5)
	local hit = cast(handle, origin, direction * reach)
	local anchor, surface
	if hit and math.abs(hit.Normal.Y) < 0.5 then
		local higher = cast(handle, origin + Vector3.new(0, C.WallCheckHeight, 0), direction * (hit.Distance + 1.2))
		if higher and math.abs(higher.Normal.Y) < 0.5 and math.abs(higher.Distance - hit.Distance) < 1 then
			local normal = flat(hit.Normal) or -direction
			local foot = cast(handle, hit.Position + normal * 0.35, Vector3.new(0, -C.FootDrop, 0))
			local feet = Vector3.new(hit.Position.X, foot and foot.Position.Y or origin.Y - C.RootHeight, hit.Position.Z)
			anchor, surface = CFrame.lookAt(feet, feet + normal), "wall"
		end
	end
	if not anchor then
		local over = hit and (hit.Position - direction * 0.4) or (origin + direction * reach)
		local floor = cast(handle, over + Vector3.new(0, 1.5, 0), Vector3.new(0, -C.FloorDrop, 0))
		if floor and floor.Normal.Y > 0.5 then
			local toward = flat(origin - floor.Position) or -direction
			anchor, surface = CFrame.lookAt(floor.Position, floor.Position + floor.Normal, toward), "floor"
		end
	end
	if anchor then
		stalk.Anchor, stalk.Surface = anchor, surface
		handle.Bank:SetAttribute("ShadeAnchor", anchor)
		handle.Bank:SetAttribute("ShadeSurface", surface)
	end
	handle.Bank:SetAttribute("ShadeDistance", stalk.Distance)
end

local function floorUnder(handle, root)
	local floor = cast(handle, root.Position, Vector3.new(0, -C.FootDrop, 0))
	return floor and floor.Position or root.Position - Vector3.new(0, C.RootHeight, 0)
end

local function recoil(handle, why)
	local stalk = handle.Stalk
	handle.Stalk = nil
	handle.LastEnd = why
	publish(handle, "recoil", stalk and stalk.Player.UserId or 0)
	if stalk and stalk.Anchor then send(handle, "recoil", handle.Serial, stalk.Anchor, stalk.Surface) end
	local serial = handle.Serial
	task.delay(C.RecoilSeconds, function()
		if validWorld(handle) and handle.Serial == serial and handle.Phase == "recoil" then rest(handle) end
	end)
end

local function warn_(handle, player, root, direction)
	handle.Warned[player] = true
	handle.Stalk = nil
	handle.LastEnd = "warned"
	publish(handle, "warn", player.UserId)
	send(handle, "warn", handle.Serial, player.UserId, floorUnder(handle, root), direction)
	local serial = handle.Serial
	task.delay(C.WarnSeconds, function()
		if validWorld(handle) and handle.Serial == serial and handle.Phase == "warn" then rest(handle, C.AfterWarningGap) end
	end)
end

local function kill(handle, player, direction)
	local character, humanoid, root = eligible(handle, player)
	if not root then return recoil(handle, "protected") end
	handle.Stalk = nil
	handle.LastEnd = "kill"
	publish(handle, "kill", player.UserId)
	local token = {}
	handle.Kill = token
	local start = root.CFrame
	local held = {humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate}
	humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate = 0, 0, false
	root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	root.Anchored = true
	send(handle, "kill", handle.Serial, player.UserId, floorUnder(handle, root), direction, C.KillSeconds, C.RealmSeconds)
	task.spawn(function()
		local t0 = os.clock()
		local whole = true
		while os.clock() - t0 < C.KillSeconds + C.RealmSeconds do
			if handle.Kill ~= token or not validWorld(handle) or player.Character ~= character or humanoid.Health <= 0
				or not root:IsDescendantOf(workspace) then
				whole = false
				break
			end
			local t = os.clock() - t0
			if t > C.KillSinkFrom then
				local u = math.clamp((t - C.KillSinkFrom) / (C.KillSeconds - C.KillSinkFrom), 0, 1)
				root.CFrame = start - Vector3.new(0, C.KillSinkStuds * u * u, 0)   -- everybody else sees the body go down
			end
			task.wait()
		end
		if whole and not PlayerProtection.IsActive(player, character) then
			DeathAdvice.Mark(player, "L2Shade")
			humanoid.Health = 0
		elseif root:IsDescendantOf(workspace) and humanoid.Health > 0 then
			root.CFrame = start
			root.Anchored = false
			humanoid.WalkSpeed, humanoid.JumpPower, humanoid.AutoRotate = held[1], held[2], held[3]
		end
		if handle.Kill == token then
			handle.Kill = nil
			if validWorld(handle) then rest(handle) end
		end
	end)
end

local function begin(handle, player, root)
	handle.Serial += 1
	handle.LastTarget = player
	local back = flat(-root.CFrame.LookVector) or Vector3.zAxis
	handle.Stalk = {Player = player, Bearing = math.atan2(back.X, back.Z), Distance = C.StartDistance, Seen = 0,
		LastSeenReport = -math.huge, LastReportAt = -math.huge,
		Rate = (C.StartDistance - C.StrikeDistance) / (handle.Warned[player] and C.StalkSeconds or C.FirstStalkSeconds)}
	place(handle, handle.Stalk, root, back)
	publish(handle, "stalk", player.UserId)
end

local function pick(handle)
	local pool, total = {}, 0
	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, root = eligible(handle, player)
		if root and not inSafeSection(handle, root.Position)
			and (humanoid.FloorMaterial ~= Enum.Material.Air or humanoid:GetState() == Enum.HumanoidStateType.Swimming) then
			local weight = 1 + C.LoudWeight * (handle.Loud[player] or 0)
			total += weight
			table.insert(pool, {player, root, weight})
		end
	end
	if total <= 0 then return nil end
	local roll = random:NextNumber(0, total)
	for _, entry in ipairs(pool) do
		roll -= entry[3]
		if roll <= 0 then return entry[1], entry[2] end
	end
	return pool[#pool][1], pool[#pool][2]
end

-- The player who has stood still the longest, if anybody has for StillSeconds.
local function pickStill(handle, now)
	local best, bestRoot, longest = nil, nil, C.StillSeconds
	for _, player in ipairs(Players:GetPlayers()) do
		local mark = handle.Still[player]
		if mark and now - mark.Since >= longest then
			local _, _, root = eligible(handle, player)
			if root and not inSafeSection(handle, root.Position) then
				best, bestRoot, longest = player, root, now - mark.Since
			end
		end
	end
	return best, bestRoot
end

local function stalkStep(handle, dt, now)
	local stalk = handle.Stalk
	local player = stalk.Player
	local _, _, root = eligible(handle, player)
	if not root then
		handle.LastEnd = "lost"
		return rest(handle)
	end
	local look = flat(root.CFrame.LookVector) or Vector3.zAxis
	local direction = Vector3.new(math.sin(stalk.Bearing), 0, math.cos(stalk.Bearing))
	local watched = now - stalk.LastSeenReport <= C.SeenReportHold and look:Dot(direction) >= C.SeenServerDot
	if watched then
		stalk.Seen += dt
		if stalk.Seen >= C.SeenSeconds then
			place(handle, stalk, root, direction)
			return recoil(handle, "seen")
		end
	else
		stalk.Seen = math.max(0, stalk.Seen - dt)
		local want = math.atan2(-look.X, -look.Z)
		local delta = (want - stalk.Bearing + math.pi) % (2 * math.pi) - math.pi
		local turn = math.rad(C.BearingDriftDegrees) * dt
		stalk.Bearing += math.clamp(delta, -turn, turn)
		stalk.Distance = math.max(0, stalk.Distance - stalk.Rate * dt)
		direction = Vector3.new(math.sin(stalk.Bearing), 0, math.cos(stalk.Bearing))
	end
	place(handle, stalk, root, direction)
	if stalk.Distance <= C.StrikeDistance and not watched then
		if C.FirstIsWarning and not handle.Warned[player] then
			warn_(handle, player, root, direction)
		else
			kill(handle, player, direction)
		end
	end
end

local function step(handle, dt)
	if not validWorld(handle) or workspace:GetAttribute("RoundActive") ~= true then
		if handle.Stalk then rest(handle) end
		return
	end
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local _, _, root = lifeOf(player)
		if root and player:GetAttribute("InRound") == true then
			local v = root.AssemblyLinearVelocity
			local running = Vector3.new(v.X, 0, v.Z).Magnitude > C.LoudSpeed and 1 or 0
			handle.Loud[player] = (handle.Loud[player] or 0) * 0.98 + running * 0.02
			local mark = handle.Still[player]
			if not mark or (root.Position - mark.At).Magnitude > C.StillRadius then
				handle.Still[player] = {At = root.Position, Since = now}
			end
		else
			handle.Still[player] = nil
		end
	end
	if handle.Stalk then
		stalkStep(handle, dt, now)
	elseif handle.Phase == "idle" and now >= handle.GraceUntil then
		-- standing still brings it at once; otherwise it comes when its own quiet time is over
		local player, root = pickStill(handle, now)
		if player then
			handle.LastReason = "still"
			begin(handle, player, root)
		elseif now >= handle.NextAt then
			player, root = pick(handle)
			handle.LastReason = "timer"
			if player then begin(handle, player, root) else handle.NextAt = now + 4 end
		end
	end
end

remote.OnServerEvent:Connect(function(player, what, serial)
	local handle = active
	local stalk = handle and handle.Stalk
	if what ~= "seen" or not stalk or stalk.Player ~= player or serial ~= handle.Serial then return end
	local now = os.clock()
	if now - stalk.LastReportAt < 0.04 then return end
	stalk.LastReportAt, stalk.LastSeenReport = now, now
end)

function Shade.Stop(handle)
	handle = handle or active
	if not handle then return end
	handle.Stopped = true
	handle.Kill = nil   -- a kill in flight sees this and puts its player back
	if handle.Connection then handle.Connection:Disconnect(); handle.Connection = nil end
	if handle.Bank.Parent then
		handle.Bank:SetAttribute("ShadePhase", "idle")
		handle.Bank:SetAttribute("ShadeTarget", 0)
		handle.Bank:SetAttribute("ShadeLive", false)
	end
	if active == handle then active = nil end
end

-- `force` is for a play test from the server console while the folder's Enabled switch is still off.
function Shade.Start(world, force)
	Shade.Stop()
	local bank = bankReady(force)
	if not bank then return nil end
	local collision = world:FindFirstChild("Collision")
	if not collision then return nil end
	local handle = {World = world, Bank = bank, Serial = bank:GetAttribute("ShadeSerial") or 0, Warned = {}, Loud = {}, Still = {},
		Guards = collision:FindFirstChild("Guards"), Safe = {}, Stopped = false, Phase = "idle",
		Origin = world:GetAttribute("Origin") or Vector3.zero}
	if typeof(handle.Origin) ~= "Vector3" then handle.Origin = Vector3.zero end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = {collision}
	params.IgnoreWater, params.RespectCanCollide = true, false
	handle.Params = params
	-- the arrival room and its stairs, from the audio plan's own section boxes
	local audio = ReplicatedStorage:FindFirstChild("Level2Poolrooms")
	local planValue = audio and audio:FindFirstChild("Plan")
	local ok, plan = pcall(function() return HttpService:JSONDecode(planValue.Value) end)
	if ok and type(plan) == "table" and type(plan.sections) == "table" then
		if type(plan.origin) == "table" and #plan.origin == 3 then
			handle.Origin = Vector3.new(plan.origin[1], plan.origin[2], plan.origin[3])
		end
		for _, id in ipairs(C.SafeSections) do
			local box = plan.sections[id]
			if type(box) == "table" and type(box.min) == "table" and type(box.max) == "table" then
				table.insert(handle.Safe, {min = Vector3.new(box.min[1], box.min[2], box.min[3]) - Vector3.new(4, 4, 4),
					max = Vector3.new(box.max[1], box.max[2], box.max[3]) + Vector3.new(4, 4, 4)})
			end
		end
	end
	handle.NextAt = os.clock() + C.GraceSeconds
	handle.GraceUntil = handle.NextAt
	active = handle
	publish(handle, "idle", 0)
	bank:SetAttribute("ShadeLive", true)
	local elapsed = 0
	handle.Connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < C.Step then return end
		local whole = elapsed
		elapsed = 0
		local ok2, err = pcall(step, handle, whole)
		if not ok2 then
			-- a fault in the entity must never take the level with it
			warn("[Level 2 Shade] stopped after a fault: " .. tostring(err))
			Shade.Stop(handle)
		end
	end)
	return handle
end

-- For play tests from the server console: start a stalk against a player now, whatever the timers say.
function Shade.ForceStalk(player, warned)
	local handle = active
	if not handle or handle.Stalk or handle.Kill then return false, "busy or not running" end
	local _, _, root = eligible(handle, player)
	if not root then return false, "player is not eligible" end
	if warned ~= nil then handle.Warned[player] = warned or nil end
	begin(handle, player, root)
	return true
end

function Shade.Active()
	return active
end

return Shade
