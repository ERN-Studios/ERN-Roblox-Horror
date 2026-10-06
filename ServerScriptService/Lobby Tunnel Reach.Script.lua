-- Lobby Tunnel Reach (2026-10-06, owner request). TUNNEL_REACH_20261006.
--   The easter egg behind the fence at the DJ end of the lobby. Get over the fence (the road cases on the stage's
--   back corner) and something in the dark wakes: two eyes open far down the tunnel and its arms come creeping out
--   toward whoever is nearest. Get back over (the crates) and they stop, wait and draw back. Stay, and a hand takes
--   you, drags you into the dark and you die there; GameManager's own lobby respawn brings you back three seconds on.
--
--   WHAT RUNS WHERE. This script decides everything that matters: who is over the fence, where each hand is, who is
--   taken and when they die. It publishes that as attributes on ReplicatedStorage.LobbyTunnelReach, twenty times a
--   second. `Lobby Tunnel Reach Client` draws it: the eyes, each arm (a chain of bones folded between a shoulder in
--   the dark and the hand), the fingers. Nothing of the creature exists on the server but numbers.
--   THE MESHES are Blender's (tools/lobby_reach/build_reach.py). They are not assets: the session's upload call
--   was refused the day they were made, so their numbers sit in ServerStorage.LobbyTunnelReachSource and `bake`
--   turns them into MeshPart templates once per server (ReplicatedStorage.LobbyTunnelReach.Meshes), as the Level 6
--   slides are. A template that is already there (an uploaded asset placed by install_reach.py) is left alone.
--   THE PLACE (fence height, the ground behind the wall, the cases) is LobbyReimaginedPreview.Builder's; this script
--   reads `ReachFrame` / `ReachFence` / `ReachGround` from the lobby's InfiniteTunnelEnd folder.
--
--   Every position here is in the tunnel's own frame: x across, y up from the road, z = studs BEHIND the end wall
--   (the fence is at -ReachFence, the dark starts at about +70).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")

if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end      -- a reserved round server has no lobby

local CONFIG = {
	-- an arm: its shoulder (never seen), where the hand waits, how high the hand travels, which side of its prey it
	-- comes round, and how long after waking it starts
	Arms = {
		{Shoulder = Vector3.new(-19, 9, 187), Rest = Vector3.new(-13, 3.0, 152), Ride = 3.0, Side = -7, Delay = 0},
		{Shoulder = Vector3.new(17, 12, 187), Rest = Vector3.new(11, 3.0, 154), Ride = 3.0, Side = 6, Delay = 1.7},
		{Shoulder = Vector3.new(-5, 28, 187), Rest = Vector3.new(-3, 16, 156), Ride = 12.5, Side = -2, Delay = 3.6},
		{Shoulder = Vector3.new(25, 22, 187), Rest = Vector3.new(20, 12, 153), Ride = 9.0, Side = 9, Delay = 5.4},
	},
	WakeSeconds = 0.9,          -- over the fence to the eyes opening
	CreepBase = 4.5,            -- studs a second when a hand sets out ...
	CreepGain = 0.35,           -- ... and this much more for every second somebody has been over there
	CreepMax = 18,              -- quicker than a walk in the end: nobody can dance round them for ever
	AngerFade = 0.5,            -- the gain drains at this rate while nobody is there
	StrikeRange = 15,           -- a hand this close stops creeping
	WindupSeconds = 0.62,       -- it rears up: the last moment to be gone
	StrikeSeconds = 0.2,
	MissSeconds = 1.1,          -- a hand that struck where nobody was stays down this long
	HoldSeconds = 0.55,         -- closed round the body before the pull
	DragStart = 26, DragGain = 420, DragMax = 125,
	KillAt = 150,               -- studs behind the wall: well inside the dark
	GripDrop = 3.6,             -- the body's root hangs this far under the middle of the palm
	CageRise = 1.6,             -- lifted off the ground while it is held
	WaitSeconds = 1.6,          -- nobody left: the hands stay where they are this long, then draw back
	RetreatSpeed = 26,
	LingerSeconds = 2.6,        -- the eyes stay open this long after the last hand is home
	HandLimit = 1.5,            -- a creeping hand comes no nearer the fence than this far behind the wall
	HeldLimit = 7,              -- seconds; a whole taking is under three
	Publish = 0.05,
	-- how far behind the wall the eyes are: asleep and waking, and when a hand has reached the fence. The dark is
	-- sheets of black at 70, 100, 128, 152 and 170; behind the fourth nothing shows, so they start in front of it
	EyesFar = 148, EyesNear = 96,
}

local root = ReplicatedStorage:FindFirstChild("LobbyTunnelReach")
if not root then
	root = Instance.new("Folder")
	root.Name = "LobbyTunnelReach"
	root.Parent = ReplicatedStorage
end
local kit = root:FindFirstChild("Meshes")
if not kit then
	kit = Instance.new("Folder")
	kit.Name = "Meshes"
	kit.Parent = root
end
root:SetAttribute("Ready", false)
root:SetAttribute("Awake", false)
root:SetAttribute("Arms", #CONFIG.Arms)

-- ---- the meshes ----------------------------------------------------------------------------------------------------
local function bake()
	local source = ServerStorage:FindFirstChild("LobbyTunnelReachSource")
	local missing = 0
	for _, item in ipairs(source and source:GetChildren() or {}) do
		if not kit:FindFirstChild(item.Name) then
			local ok, why = pcall(function()
				local text = {}
				for i = 1, item:GetAttribute("Parts") do
					text[i] = item:FindFirstChild(string.format("Part_%02d", i)).Value
				end
				local data = HttpService:JSONDecode(table.concat(text))
				local em = assert(AssetService:CreateEditableMesh(), "no EditableMesh budget")
				local V, N, C, T = data.verts, data.normals, data.colours, data.tris
				local vid, nid, cid = {}, {}, {}
				for i = 1, #V, 3 do
					vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000)
					nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000)
					cid[#cid + 1] = em:AddColor(Color3.fromRGB(C[i], C[i + 1], C[i + 2]), 1)
				end
				for i = 1, #T, 3 do
					local a, b, c = T[i] + 1, T[i + 1] + 1, T[i + 2] + 1
					local face = em:AddTriangle(vid[a], vid[b], vid[c])
					em:SetFaceNormals(face, {nid[a], nid[b], nid[c]})
					em:SetFaceColors(face, {cid[a], cid[b], cid[c]})
					if i % 4500 == 1 then task.wait() end
				end
				local baked, result, content = pcall(AssetService.CreateDataModelContentAsync, AssetService, Content.fromObject(em))
				em:Destroy()
				if not baked or result ~= Enum.CreateContentResult.Success then error("bake: " .. tostring(result)) end
				local part = AssetService:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
				part.Name = item.Name
				part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
				part.Material, part.Color = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)
				part:SetAttribute("Offset", item:GetAttribute("Offset"))
				part.Parent = kit
			end)
			if not ok then
				missing += 1
				warn("[TunnelReach] mesh " .. item.Name .. " was not built: " .. tostring(why))
			end
		end
	end
	return missing == 0 and #kit:GetChildren() > 0
end

-- ---- the place -----------------------------------------------------------------------------------------------------
local frame, FENCE, GROUND
local function place()
	local lobby = workspace:FindFirstChild("LobbyReimaginedPreview")
	local set = lobby and lobby:GetAttribute("Ready") == true and lobby:FindFirstChild("InfiniteTunnelEnd")
	local cf = set and set:GetAttribute("ReachFrame")
	if typeof(cf) ~= "CFrame" then return false end
	frame, FENCE, GROUND = cf, set:GetAttribute("ReachFence"), set:GetAttribute("ReachGround")
	root:SetAttribute("Frame", frame)
	root:SetAttribute("Fence", FENCE)
	return true
end

-- ---- the creature --------------------------------------------------------------------------------------------------
local arms = {}
local heldSince = {}                       -- by UserId (a weak table keyed by the Player would forget them)
for i, spec in ipairs(CONFIG.Arms) do
	arms[i] = {index = i, spec = spec, tip = spec.Rest, state = "rest", since = 0}
	root:SetAttribute("T" .. i, spec.Rest)
	root:SetAttribute("S" .. i, "rest")
	root:SetAttribute("V" .. i, 0)
	root:SetAttribute("Shoulder" .. i, spec.Shoulder)
end

local function now() return workspace:GetServerTimeNow() end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function setState(arm, state)
	arm.state, arm.since = state, now()
	root:SetAttribute("S" .. arm.index, state)
	root:SetAttribute("At" .. arm.index, arm.since)
end

-- everybody alive and on their feet behind the fence, in the tunnel's frame
local function over()
	local found = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local body = character and character:FindFirstChild("HumanoidRootPart")
		-- (a Studio round is generated in this same place: somebody in a round, or in a live level, is not in the lobby)
		if humanoid and body and humanoid.Health > 0 and player:GetAttribute("TunnelReachHeld") ~= true
			and player:GetAttribute("InRound") ~= true and player:GetAttribute("Level6PlaygroundPreview") ~= true then
			local at = frame:PointToObjectSpace(body.Position)
			if at.Z > -(FENCE - 0.9) and at.Z < GROUND + 6 and math.abs(at.X) < 37 and at.Y > -4 and at.Y < 42 then
				found[#found + 1] = {player = player, character = character, humanoid = humanoid, body = body, at = at}
			end
		end
	end
	return found
end

local function release(arm)
	local player = arm.victim
	arm.victim, arm.body, arm.humanoid, arm.character = nil, nil, nil, nil
	root:SetAttribute("V" .. arm.index, 0)
	return player
end

local function seize(arm, prey)
	arm.victim, arm.body, arm.humanoid, arm.character = prey.player, prey.body, prey.humanoid, prey.character
	arm.heldFrom = prey.body.CFrame
	prey.player:SetAttribute("TunnelReachHeld", true)
	prey.humanoid.PlatformStand = true
	prey.humanoid.AutoRotate = false
	prey.body.AssemblyLinearVelocity = Vector3.zero
	prey.body.AssemblyAngularVelocity = Vector3.zero
	prey.body.Anchored = true
	root:SetAttribute("V" .. arm.index, prey.player.UserId)
	root:SetAttribute("Taken", (root:GetAttribute("Taken") or 0) + 1)
end

local function stillHeld(arm)
	return arm.victim and arm.victim.Parent and arm.character and arm.character.Parent and arm.body and arm.body.Parent
		and arm.humanoid and arm.humanoid.Health > 0
end

Players.PlayerRemoving:Connect(function(player) heldSince[player.UserId] = nil end)
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function() player:SetAttribute("TunnelReachHeld", nil) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function() player:SetAttribute("TunnelReachHeld", nil) end)
end

local awake, awakeAt, anger, lastSeen, published = false, 0, 0, 0, 0
local gaze = Vector3.new(0, 4, 0)

local function step(dt)
	local t = now()
	local prey = over()
	if #prey > 0 then
		if not awake then
			awake, awakeAt = true, t
			root:SetAttribute("AwakeAt", t)
			root:SetAttribute("Awake", true)
		end
		lastSeen = t
		anger += dt
	else
		anger = math.max(0, anger - dt * CONFIG.AngerFade)
	end
	local busy = false
	for _, arm in ipairs(arms) do
		local spec = arm.spec
		-- the nearest body to this hand that no other hand is already closing on
		local target, best = nil, math.huge
		for _, p in ipairs(prey) do
			local claimed = false
			for _, other in ipairs(arms) do
				if other ~= arm and other.claim == p.player and (other.state == "windup" or other.state == "strike") then claimed = true end
			end
			local d = flat(p.at - arm.tip).Magnitude
			if not claimed and d < best then target, best = p, d end
		end
		if arm.state == "rest" then
			arm.tip = spec.Rest
			if awake and target and t - awakeAt >= CONFIG.WakeSeconds + spec.Delay then setState(arm, "creep") end
		elseif arm.state == "creep" then
			busy = true
			if not target then
				setState(arm, "wait")
			else
				-- round one side of the prey while it is far, straight at it once it is near
				local aim = target.at + Vector3.new(spec.Side * math.clamp((best - 10) / 40, 0, 1), 0, 0)
				local to = flat(aim - arm.tip)
				local speed = math.min(CONFIG.CreepMax, CONFIG.CreepBase + CONFIG.CreepGain * anger)
				local move = to.Magnitude > 0.05 and to.Unit * math.min(speed * dt, to.Magnitude) or Vector3.zero
				-- a high hand comes down as it nears; a low one rides just over the ground its prey stands on
				local ride = spec.Ride > 6 and math.max(6.5, spec.Ride * math.clamp(best / 55, 0, 1)) or spec.Ride + math.max(0, target.at.Y - 3.4) * math.clamp(1 - best / 30, 0, 1)
				local y = arm.tip.Y + (ride - arm.tip.Y) * math.min(1, dt * 1.4)
				local nextTip = Vector3.new(math.clamp(arm.tip.X + move.X, -30, 30), y, math.max(CONFIG.HandLimit, arm.tip.Z + move.Z))
				arm.tip = nextTip
				if best <= CONFIG.StrikeRange then
					arm.claim = target.player
					arm.from = arm.tip
					setState(arm, "windup")
				end
			end
		elseif arm.state == "windup" then
			busy = true
			local u = math.clamp((t - arm.since) / CONFIG.WindupSeconds, 0, 1)
			local e = u * u * (3 - 2 * u)
			-- it rears: up, and a little back from where it stood
			arm.tip = arm.from + Vector3.new(0, 5.5 * e, 2.2 * e)
			if u >= 1 then
				arm.from = arm.tip
				setState(arm, "strike")
			end
		elseif arm.state == "strike" then
			busy = true
			local u = math.clamp((t - arm.since) / CONFIG.StrikeSeconds, 0, 1)
			local claimed
			for _, p in ipairs(prey) do
				if p.player == arm.claim then claimed = p end
			end
			if claimed then arm.mark = claimed.at end                 -- it follows a body that is still there to follow
			local mark = arm.mark or (arm.from + Vector3.new(0, 0, -8))
			local down = Vector3.new(mark.X, mark.Y + CONFIG.GripDrop, math.max(mark.Z, -(FENCE - 1.2)))
			arm.tip = arm.from:Lerp(down, u * u)
			if u >= 1 then
				arm.claim, arm.mark = nil, nil
				if claimed then
					seize(arm, claimed)
					setState(arm, "hold")
				else
					arm.tip = Vector3.new(down.X, math.max(3.0, down.Y - 2), math.max(down.Z, CONFIG.HandLimit))
					setState(arm, "miss")
				end
			end
		elseif arm.state == "miss" then
			busy = true
			if t - arm.since >= CONFIG.MissSeconds then setState(arm, target and "creep" or "wait") end
		elseif arm.state == "hold" then
			busy = true
			if not stillHeld(arm) then
				release(arm)
				setState(arm, "wait")
			else
				local u = math.clamp((t - arm.since) / CONFIG.HoldSeconds, 0, 1)
				local lifted = arm.heldFrom.Position + Vector3.new(0, CONFIG.CageRise * u * u, 0)
				arm.body.CFrame = arm.heldFrom.Rotation + lifted
				arm.tip = frame:PointToObjectSpace(lifted) + Vector3.new(0, CONFIG.GripDrop, 0)
				if u >= 1 then
					arm.from, arm.pulled = arm.tip, 0
					arm.spin = arm.heldFrom.Rotation
					setState(arm, "drag")
				end
			end
		elseif arm.state == "drag" then
			busy = true
			local s = t - arm.since
			local speed = math.min(CONFIG.DragMax, CONFIG.DragStart + CONFIG.DragGain * s)
			local into = Vector3.new(spec.Shoulder.X * 0.45, 7.5, 178)
			local to = into - arm.tip
			arm.tip += to.Unit * math.min(speed * dt, to.Magnitude)
			if stillHeld(arm) then
				local at = frame:PointToWorldSpace(arm.tip - Vector3.new(0, CONFIG.GripDrop, 0))
				arm.spin *= CFrame.Angles(dt * 2.6, dt * 0.7, dt * 1.9)   -- a body pulled along by its middle does not stay upright
				arm.body.CFrame = arm.spin + at
				if arm.tip.Z >= CONFIG.KillAt then
					local humanoid = arm.humanoid
					release(arm)
					humanoid.Health = 0
				end
			elseif arm.victim then
				release(arm)
			end
			if to.Magnitude < 1 or (not arm.victim and arm.tip.Z >= CONFIG.KillAt) then setState(arm, "retreat") end
		elseif arm.state == "wait" then
			busy = true
			if target then
				setState(arm, "creep")
			elseif t - arm.since >= CONFIG.WaitSeconds then
				setState(arm, "retreat")
			end
		elseif arm.state == "retreat" then
			busy = true
			local to = spec.Rest - arm.tip
			if target and arm.tip.Z < CONFIG.KillAt - 20 then
				setState(arm, "creep")
			elseif to.Magnitude < 0.6 then
				arm.tip = spec.Rest
				setState(arm, "rest")
			else
				arm.tip += to.Unit * math.min(CONFIG.RetreatSpeed * dt, to.Magnitude)
			end
		end
	end
	if awake and #prey == 0 and not busy and t - lastSeen >= CONFIG.LingerSeconds then
		awake = false
		root:SetAttribute("Awake", false)
	end
	if t - published >= CONFIG.Publish then
		published = t
		local nearest, pulling = 0, false
		for _, arm in ipairs(arms) do
			if root:GetAttribute("T" .. arm.index) ~= arm.tip then root:SetAttribute("T" .. arm.index, arm.tip) end
			nearest = math.max(nearest, math.clamp((arm.spec.Rest.Z - arm.tip.Z) / arm.spec.Rest.Z, 0, 1))
			if arm.state == "hold" or arm.state == "drag" then pulling = true end
		end
		-- the eyes come closer as the hands go out, and look at whoever is nearest the dark
		local look
		for _, p in ipairs(prey) do
			if not look or p.at.Z > look.Z then look = p.at end
		end
		if look then gaze = look end
		-- (they stay where they are while a body is pulled in underneath them)
		local eyes = pulling and root:GetAttribute("Eyes") or CONFIG.EyesFar + (CONFIG.EyesNear - CONFIG.EyesFar) * nearest
		if root:GetAttribute("Gaze") ~= gaze then root:SetAttribute("Gaze", gaze) end
		if root:GetAttribute("Eyes") ~= eyes then root:SetAttribute("Eyes", eyes) end
		-- nobody stays in a hand: whatever went wrong, a body still marked as held after HeldLimit dies and respawns
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("TunnelReachHeld") == true then
				heldSince[player.UserId] = heldSince[player.UserId] or t
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if t - heldSince[player.UserId] > CONFIG.HeldLimit and humanoid and humanoid.Health > 0 then humanoid.Health = 0 end
			else
				heldSince[player.UserId] = nil
			end
		end
	end
end

task.spawn(function()
	for _ = 1, 120 do                       -- the lobby is built by GameManager a little after this script starts
		if place() then break end
		task.wait(1)
	end
	if not frame then return end            -- no lobby on this server
	for attempt = 1, 20 do
		if bake() then break end
		task.wait(3 + attempt)
	end
	if #kit:GetChildren() == 0 then
		warn("[TunnelReach] no meshes: the fence stays an ordinary fence's worth of nothing")
		return
	end
	root:SetAttribute("Ready", true)
	RunService.Heartbeat:Connect(function(dt)
		local ok, why = pcall(step, math.min(dt, 0.1))
		if not ok then warn("[TunnelReach] " .. tostring(why)) end
	end)
end)
