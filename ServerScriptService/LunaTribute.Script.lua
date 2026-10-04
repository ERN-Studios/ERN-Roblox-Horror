-- Luna, in memory of the owner's dog. She sleeps in her bed in the lobby, gets up now and then to wander
-- and sniff around, and when someone pets her she sits, gives her paw and follows that player for a while.
-- Everything is built at runtime from group-owned assets (rig + bed via InsertService, clips by id); the
-- pipeline that made them is tools/luna/README.md.
if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then return end -- reserved round server

local InsertService = game:GetService("InsertService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DOG_ASSET = 123942446229463 -- 29-bone rig, rest pose of tools/luna (receipts/luna_rigtest_v1.json)
local BED_ASSET = 130867070552114
local ANIMS = { -- KeyframeSequences from tools/luna/glb_to_rbxmx.py (receipts/luna_<clip>_v1.json)
	Idle = 126786816607054, Walk = 103802473375899, Run = 102273883403776, Sniff = 113212912040174,
	SitDown = 117349775636197, Sit = 98286663489268, GivePaw = 109042539941659, StandUp = 112870979215682,
	LieDown = 102191286557976, Sleep = 74699347617141, WakeUp = 94046810034417,
}
local PLAYER_PET_ANIM = 135130382947090 -- R15 clip the petting player plays (receipts/luna_player_pet_v1.json)
local EYES_CLOSED_TEXTURE = 86024350432064 -- her texture with closed eyes, worn while she sleeps (receipts/luna_eyes_closed_v1.json)
local WALK_REF, RUN_REF = 3.0645, 16 -- studs/s at which the Walk / Run clips' paws stay planted
local WALK_SPEED, RUN_SPEED, BED_WALK_SPEED = WALK_REF * 1.15, RUN_REF, WALK_REF * 0.8
local TURN_RATE = math.rad(300)
local FOLLOW_SECONDS, FOLLOW_GAP, RUN_BEYOND = 5, 3.5, 11
local PET_DISTANCE = 9
local PET_GAP = 3.3 -- she sits this far in front of the petting player (their kneeling reach)
local CUSHION_HEIGHT = 0.7 -- top of the bed cushion above the floor (studs)
-- Layout relative to the revised lobby's PreviewCenter (220, 30, -760); heights come from floor raycasts.
-- Her bed is on the west wall between the Level 3 and Level 5 gates, opening towards the road.
-- (rel z 52 keeps it clear of the wall service panel at rel z 38..41 and of the Level 5 gate)
local BED_OFFSET, BED_YAW = Vector3.new(-30.2, 0, 52), -math.pi / 2
-- floor points she strolls between: sidewalks and road, away from gates, pads, the shop, spawn and stage
local WANDER = {
	Vector3.new(-26, 0, 20), Vector3.new(-24, 0, 56), Vector3.new(-20, 0, 34), Vector3.new(-8, 0, 30),
	Vector3.new(6, 0, 12), Vector3.new(8, 0, 58), Vector3.new(24, 0, 30), Vector3.new(22, 0, 54),
	Vector3.new(-24, 0, -30), Vector3.new(-21, 0, -56), Vector3.new(0, 0, -40), Vector3.new(-20, 0, -115),
	Vector3.new(18, 0, -118),
}

local function lobbyReady()
	local deadline = os.clock() + 600 -- the lobby's mesh bake can take minutes
	repeat
		local model = workspace:FindFirstChild("LobbyReimaginedPreview")
		if model and model:IsA("Model") and model:GetAttribute("LobbyReimaginedOwned") == true
			and model:GetAttribute("Ready") == true and workspace:GetAttribute("LobbySpawnMigrationReady") == true then
			return model, model:GetAttribute("PreviewCenter")
		end
		if workspace:GetAttribute("LobbySpawnMigrationError") then return nil end
		task.wait(0.5)
	until os.clock() >= deadline
	return nil
end

local function load(id)
	for attempt = 1, 4 do
		local ok, root = pcall(InsertService.LoadAsset, InsertService, id)
		if ok then return root:FindFirstChildWhichIsA("Model") or root end
		warn(string.format("[Luna] LoadAsset %d failed (%d/4): %s", id, attempt, tostring(root)))
		task.wait(2 ^ attempt)
	end
end

local lobby, center = lobbyReady()
if not lobby or DOG_ASSET == 0 then
	warn("[Luna] lobby not ready or rig not configured; Luna stays away this server")
	return
end
local dogSource, bedSource = load(DOG_ASSET), load(BED_ASSET)
if not dogSource or not bedSource then return end

local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Include
floorParams.FilterDescendantsInstances = {lobby}
floorParams.RespectCanCollide = true
local function floorAt(p, fallback)
	local hit = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), floorParams)
	return hit and hit.Position.Y or fallback
end
local function ground(offset)
	local p = center + offset
	return Vector3.new(p.X, floorAt(p, center.Y), p.Z)
end

-- Bed + memorial plate ---------------------------------------------------------------------------------
local home = Instance.new("Model")
home.Name = "Luna's Bed"
home.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
local bedFloor = ground(BED_OFFSET)
local bedFrame = CFrame.new(bedFloor) * CFrame.Angles(0, BED_YAW, 0)
local bed = bedSource:FindFirstChildWhichIsA("MeshPart", true)
bed.Name = "Bed"
bed.Anchored, bed.CanTouch = true, false
bed.CFrame = bedFrame * CFrame.new(0, bed.Size.Y / 2, 0)
bed.Parent = home
local passThrough = Instance.new("PathfindingModifier") -- her path into the bed may cross it
passThrough.PassThrough = true
passThrough.Parent = bed
-- the opening faces the bed's -Z (LookVector); she walks in from there
local bedEntry = bedFrame * CFrame.new(0, 0, -(bed.Size.Z / 2 + 2.5))

-- the brass plate hangs on the wall behind the bed (found by a ray), else it stands at the bed's foot.
-- Its face is drawn by the SurfaceGui itself (LightInfluence 0) so it reads in the dim tunnel.
local plate = Instance.new("Part")
plate.Name = "Memorial Plate"
plate.Size = Vector3.new(3.6, 1.4, 0.12)
plate.Material = Enum.Material.Metal
plate.Color = Color3.fromRGB(150, 118, 58)
plate.Anchored, plate.CanCollide, plate.CanTouch, plate.CanQuery = true, false, false, false
local eye = bedFloor + Vector3.new(0, 3.4, 0)
local wall = workspace:Raycast(eye, -bedFrame.LookVector * 12, floorParams)
if wall and math.abs(wall.Normal.Y) < 0.3 then
	plate.CFrame = CFrame.lookAt(wall.Position + wall.Normal * 0.07, wall.Position + wall.Normal)
else
	plate.CFrame = bedFrame * CFrame.new(0, 0.55, -(bed.Size.Z / 2 + 0.6)) * CFrame.Angles(math.rad(-15), 0, 0)
end
plate.Parent = home
local gui = Instance.new("SurfaceGui")
gui.Face = Enum.NormalId.Front
gui.CanvasSize = Vector2.new(360, 140)
gui.LightInfluence = 0
gui.Brightness = 1
gui.MaxDistance = 80
gui.Parent = plate
local face = Instance.new("Frame")
face.Size = UDim2.fromScale(1, 1)
face.BackgroundColor3 = Color3.fromRGB(214, 176, 96)
face.Parent = gui
local rim = Instance.new("UIStroke")
rim.Thickness = 6
rim.Color = Color3.fromRGB(120, 86, 34)
rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
rim.Parent = face
local name = Instance.new("TextLabel")
name.BackgroundTransparency = 1
name.Position = UDim2.fromScale(0, 0.04)
name.Size = UDim2.fromScale(1, 0.62)
name.Font = Enum.Font.Garamond
name.Text = "LUNA"
name.TextScaled = true
name.TextColor3 = Color3.fromRGB(52, 34, 12)
name.Parent = face
local mark = name:Clone()
mark.Position = UDim2.fromScale(0, 0.64)
mark.Size = UDim2.fromScale(1, 0.3)
mark.Font = Enum.Font.GothamMedium
mark.Text = "\u{1F43E} \u{2764} \u{1F43E}" -- paw, heart, paw
mark.Parent = face
-- a warm lamp over her bed; the tunnel is dark along the walls
local lamp = Instance.new("Part")
lamp.Name = "Bed Light"
lamp.Size = Vector3.new(0.2, 0.2, 0.2)
lamp.Transparency = 1
lamp.Anchored, lamp.CanCollide, lamp.CanTouch, lamp.CanQuery = true, false, false, false
lamp.CFrame = CFrame.new(bedFloor + Vector3.new(0, 6.5, 0)) * CFrame.Angles(-math.pi / 2, 0, 0)
lamp.Parent = home
local glow = Instance.new("SpotLight")
glow.Face = Enum.NormalId.Front
glow.Angle = 95
glow.Range = 13
glow.Brightness = 2.2
glow.Color = Color3.fromRGB(255, 214, 168)
glow.Shadows = true
glow.Parent = lamp
home.Parent = workspace

-- Luna herself -----------------------------------------------------------------------------------------
local luna = dogSource
luna.Name = "Luna"
luna.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
local mesh = luna:FindFirstChildWhichIsA("MeshPart", true)
local rootBone = mesh:FindFirstChild("Root")
-- the import turns the rig 180 degrees (nose along the mesh's +Z) and centres the mesh on its bounds
local feet = mesh.CFrame:PointToObjectSpace(rootBone.WorldPosition)
local root = Instance.new("Part")
root.Name = "LunaRoot"
root.Size = Vector3.new(1, 1, 1)
root.Transparency = 1
root.CanCollide, root.CanTouch, root.CanQuery = false, false, false
root.Parent = luna
luna.PrimaryPart = root
for _, d in ipairs(luna:GetDescendants()) do
	if d:IsA("BasePart") and d ~= root then
		d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.Massless = false, false, false, false, true
	elseif d:IsA("JointInstance") then
		d:Destroy() -- importer bind joints; the weld below replaces them
	end
end
local weld = Instance.new("Weld")
weld.Part0, weld.Part1 = root, mesh
weld.C0 = CFrame.new(0, -0.5, 0) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-feet)
weld.Parent = root
local attachment = Instance.new("Attachment")
attachment.Parent = root
local alignPos = Instance.new("AlignPosition")
alignPos.Mode = Enum.PositionAlignmentMode.OneAttachment
alignPos.Attachment0 = attachment
alignPos.RigidityEnabled = true
alignPos.Parent = root
local alignRot = Instance.new("AlignOrientation")
alignRot.Mode = Enum.OrientationAlignmentMode.OneAttachment
alignRot.Attachment0 = attachment
alignRot.RigidityEnabled = true
alignRot.Parent = root

local promptAnchor = Instance.new("Attachment")
promptAnchor.Name = "PetPoint"
promptAnchor.Position = Vector3.new(0, 1.9, -0.6)
promptAnchor.Parent = root
local prompt = Instance.new("ProximityPrompt")
prompt.Name = "PetLuna"
prompt.ActionText = "Pet"
prompt.ObjectText = "Luna"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 8
prompt.RequiresLineOfSight = false
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.Parent = promptAnchor

local animator = luna:FindFirstChildWhichIsA("AnimationController") or Instance.new("AnimationController", luna)
animator = animator:FindFirstChildWhichIsA("Animator") or Instance.new("Animator", animator)
local pos = bedFloor + Vector3.new(0, CUSHION_HEIGHT, 0)
local yaw = BED_YAW -- lying in the bed, facing out of the opening (the bed's LookVector)
root.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, yaw, 0)
alignPos.Position = root.Position
alignRot.CFrame = root.CFrame.Rotation
luna.Parent = workspace
root:SetNetworkOwner(nil)

local tracks = {}
for clip, id in pairs(ANIMS) do
	local anim = Instance.new("Animation")
	anim.Name = clip
	anim.AnimationId = "rbxassetid://" .. id
	anim.Parent = luna
	tracks[clip] = animator:LoadAnimation(anim)
end
local loadDeadline = os.clock() + 15
for _, t in pairs(tracks) do
	while t.Length == 0 and os.clock() < loadDeadline do task.wait(0.1) end
end

-- Locomotion layer (Idle/Walk/Run) follows the measured speed; actions are full-body and sit on top.
local loco, action, sniffing = nil, nil, false
local function setLoco(clip, rate)
	local t = tracks[clip]
	if loco ~= t then
		if loco then loco:Stop(0.25) end
		loco = t
		t:Play(0.25)
	end
	t:AdjustSpeed(rate or 1)
end
local function playAction(clip, fade)
	local t = tracks[clip]
	if action and action ~= t then action:Stop(fade or 0.2) end
	action = t
	t:Play(fade or 0.2)
	return t
end
local function clearAction(fade)
	if action then action:Stop(fade or 0.25) end
	action = nil
end
-- play a one-shot and hand over to `hold` (a looping action) just before it ends
local function oneShot(clip, hold)
	local t = playAction(clip, 0.2)
	local length = t.Length > 0 and t.Length or 1
	task.wait(math.max(length - 0.12, 0.05))
	if hold then playAction(hold, 0.12) else clearAction(0.15) end
end

-- Movement: the brain sets a path; Heartbeat walks it and feeds the align targets.
local path, speed, liftTo, liftRate, faceTarget = {}, 0, pos.Y, 12, nil -- she starts on the cushion
local velocity = 0
RunService.Heartbeat:Connect(function(dt)
	local moved = 0
	local goal = path[1]
	if goal then
		local flat = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
		local dist = flat.Magnitude
		if dist < 0.25 then
			table.remove(path, 1)
		else
			local want = math.atan2(-flat.X, -flat.Z)
			local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += math.clamp(diff, -TURN_RATE * dt, TURN_RATE * dt)
			-- slow down while turning sharply so she does not moonwalk sideways
			local step = math.min(dist, speed * dt * math.clamp(1 - math.abs(diff) / math.pi * 1.6, 0.15, 1))
			pos += flat.Unit * step
			moved = step
		end
	elseif faceTarget then
		local flat = Vector3.new(faceTarget.X - pos.X, 0, faceTarget.Z - pos.Z)
		if flat.Magnitude > 0.1 then
			local diff = (math.atan2(-flat.X, -flat.Z) - yaw + math.pi) % (2 * math.pi) - math.pi
			local turn = math.clamp(diff, -TURN_RATE * dt, TURN_RATE * dt)
			yaw += turn
			moved = math.abs(turn) * 0.8 -- turning on the spot steps the paws (slow walk) instead of sliding
		end
	end
	local y = liftTo or floorAt(pos, pos.Y)
	pos = Vector3.new(pos.X, pos.Y + (y - pos.Y) * math.min(1, dt * liftRate), pos.Z)
	alignPos.Position = pos + Vector3.new(0, 0.5, 0)
	alignRot.CFrame = CFrame.Angles(0, yaw, 0)
	velocity += (moved / math.max(dt, 1e-3) - velocity) * math.min(1, dt * 10)
	if not action then
		if velocity > (WALK_SPEED + RUN_SPEED) / 2 then
			setLoco("Run", math.clamp(velocity / RUN_REF, 0.6, 1.4))
		elseif velocity > 0.4 then
			setLoco("Walk", math.clamp(velocity / WALK_REF, 0.5, 1.6))
		else
			setLoco(sniffing and "Sniff" or "Idle")
		end
	end
end)

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
wallParams.FilterDescendantsInstances = {lobby}
wallParams.RespectCanCollide = true
local function clearLine(a, b)
	local from, to = a + Vector3.new(0, 1.2, 0), Vector3.new(b.X, a.Y + 1.2, b.Z)
	return workspace:Raycast(from, to - from, wallParams) == nil
end

local function route(target)
	local out
	pcall(function()
		local p = PathfindingService:CreatePath({AgentRadius = 1.4, AgentHeight = 3.4, AgentCanJump = false,
			AgentCanClimb = false, WaypointSpacing = 3})
		p:ComputeAsync(pos + Vector3.new(0, 1, 0), target + Vector3.new(0, 1, 0))
		if p.Status == Enum.PathStatus.Success then
			out = {}
			for i, w in ipairs(p:GetWaypoints()) do
				if i > 1 then table.insert(out, w.Position) end
			end
		end
	end)
	if (not out or #out == 0) and clearLine(pos, target) then out = {target} end
	return out
end

local function walkTo(target, walkSpeed, lift, rate)
	local r = lift and {target} or route(target) -- the last step into the bed is a short straight line
	if not r then return false end
	speed, liftTo, liftRate, path = walkSpeed, lift, rate or 12, r
	local deadline = os.clock() + 60
	while #path > 0 and os.clock() < deadline do task.wait(0.1) end
	path = {}
	return true
end

local function settleFacing(point, seconds)
	faceTarget = point
	task.wait(seconds)
	faceTarget = nil
end

-- Brain ----------------------------------------------------------------------------------------------
local inBed = true
local brain
local openEyes = mesh.TextureID
mesh.Color = Color3.fromRGB(238, 236, 230) -- what shows for a moment while a swapped texture loads
local function eyes(open)
	if EYES_CLOSED_TEXTURE ~= 0 then mesh.TextureID = open and openEyes or ("rbxassetid://" .. EYES_CLOSED_TEXTURE) end
end
local function state(name) luna:SetAttribute("State", name) end -- readback for playtests
local function life()
	while true do
		if inBed then
			state("Sleeping")
			oneShot("LieDown", "Sleep")
			eyes(false)
			task.wait(math.random(45, 90))
			state("WakingUp")
			eyes(true)
			oneShot("WakeUp")
			inBed = false
			walkTo(bedEntry.Position, BED_WALK_SPEED, nil, 2.5)
		end
		state("Wandering")
		for _ = 1, math.random(2, 4) do
			if #WANDER == 0 then break end
			walkTo(ground(WANDER[math.random(#WANDER)]), WALK_SPEED)
			sniffing = math.random() < 0.5
			task.wait(math.random(3, 7))
			sniffing = false
		end
		-- home: to the opening, then step up onto the cushion and turn round to face out
		state("GoingHome")
		walkTo(bedEntry.Position, WALK_SPEED)
		walkTo(bedFloor, BED_WALK_SPEED, bedFloor.Y + CUSHION_HEIGHT, 2.5)
		settleFacing(bedEntry.Position, 0.8)
		inBed = true
	end
end

local function startLife()
	brain = task.spawn(life)
end

local function inLobby(player)
	local character = player.Character
	local human = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (human and hrp and human.Health > 0) then return nil end
	if player:GetAttribute("InRound") == true or player:GetAttribute("Level6InRound") == true then return nil end
	if (hrp.Position - pos).Magnitude > PET_DISTANCE + 4 then return nil end
	return hrp
end

local function follow(player)
	local untilTime = os.clock() + FOLLOW_SECONDS
	while os.clock() < untilTime do
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or player:GetAttribute("InRound") == true then break end
		local target = hrp.Position
		local away = Vector3.new(pos.X - target.X, 0, pos.Z - target.Z)
		local dist = away.Magnitude
		if dist > FOLLOW_GAP + 0.6 then
			local goal = Vector3.new(target.X, pos.Y, target.Z) + away.Unit * FOLLOW_GAP
			speed = dist > RUN_BEYOND and RUN_SPEED or WALK_SPEED
			liftTo, liftRate, faceTarget = nil, 12, nil
			path = clearLine(pos, goal) and {goal} or route(goal) or {}
		else
			path, faceTarget = {}, target
		end
		task.wait(0.15)
	end
	path, faceTarget = {}, nil
end

-- the petting player kneels, strokes her head and takes the paw (their own Animator, server-played)
local petAnim
if PLAYER_PET_ANIM ~= 0 then
	petAnim = Instance.new("Animation")
	petAnim.Name = "PlayerPetsLuna"
	petAnim.AnimationId = "rbxassetid://" .. PLAYER_PET_ANIM
	petAnim.Parent = luna
end
local function playerPets(player)
	local character = player.Character
	local human = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local animator = human and human:FindFirstChildOfClass("Animator")
	if not (petAnim and animator and hrp) then return end
	local toward = Vector3.new(pos.X, hrp.Position.Y, pos.Z)
	if (toward - hrp.Position).Magnitude > 0.5 then hrp.CFrame = CFrame.lookAt(hrp.Position, toward) end
	local track = animator:LoadAnimation(petAnim)
	track.Priority = Enum.AnimationPriority.Action4
	track:Play(0.25)
	local start = hrp.Position
	task.spawn(function() -- walking off ends it
		while track.IsPlaying do
			if (hrp.Position - start).Magnitude > 2 then track:Stop(0.3) break end
			task.wait(0.1)
		end
		track:Destroy()
	end)
end

local function playerRoot(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

prompt.Triggered:Connect(function(player)
	local hrp = inLobby(player)
	if not hrp or not prompt.Enabled then return end
	prompt.Enabled = false
	if brain then task.cancel(brain) end
	brain = task.spawn(function()
		state("Petted")
		path, sniffing = {}, false
		if not inBed then liftTo, liftRate = nil, 4 end
		if inBed then
			eyes(true)
			oneShot("WakeUp")
		end
		-- come up to the player and sit just in front of them
		hrp = playerRoot(player) or hrp
		local them = Vector3.new(hrp.Position.X, pos.Y, hrp.Position.Z)
		if (them - pos).Magnitude > PET_GAP + 1 then
			if inBed then
				inBed = false
				walkTo(bedEntry.Position, BED_WALK_SPEED, nil, 2.5)
			end
			hrp = playerRoot(player) or hrp
			them = Vector3.new(hrp.Position.X, pos.Y, hrp.Position.Z)
			walkTo(them + (pos - them).Unit * PET_GAP, WALK_SPEED)
		end
		hrp = playerRoot(player) or hrp
		settleFacing(hrp.Position, 0.7)
		playerPets(player)
		oneShot("SitDown", "Sit")
		task.wait(0.4)
		oneShot("GivePaw", "Sit")
		task.wait(0.6)
		oneShot("StandUp")
		if inBed then
			inBed = false
			walkTo(bedEntry.Position, BED_WALK_SPEED, nil, 2.5)
		end
		prompt.Enabled = true
		state("Following")
		follow(player)
		brain = task.spawn(life)
	end)
end)

startLife()
