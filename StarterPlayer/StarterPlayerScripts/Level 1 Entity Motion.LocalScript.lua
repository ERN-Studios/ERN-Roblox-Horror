-- ENTITY_MOTION_20261010: the root owns travel; these in-place poses own the visible gait.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BIND_NAME = "L1EntityMotion"
local CLIP_NAMES = {"Walk", "Prowl", "Run", "Lunge_Windup", "Lunge_Flight", "Lunge_Land"}
local ACTION_IDS = { ["102035504530432"] = true, ["132425538759403"] = true, ["94135265462008"] = true }
local ACTION_NAMES = { Yell_Howl = true, Yell_FromRun = true, Kill_GroundPinPunch = true }
local LAND_COMPRESS_DEGREES = {Spine02 = 6, Spine01 = 4, Spine = 2, Head = -12}
local IDENTITY = CFrame.identity
local clips = {}
local sourceFolder, sourceConnections = nil, {}
local valueConnections = {}
local connections = {}
local rig, rigDirty = nil, true
local speed, verticalSpeed, lastPosition = 0, 0, nil
local moving, weight, gaitPhase = false, 0, 0
local walkWeight, prowlWeight, runWeight = 1, 0, 0
local phase, phaseAge, groundY, absorbAge = nil, 0, nil, 1
-- LUNGE_GROUND_20261010 (seen in play): the height the body stands at, as a low-water mark that can only
-- creep up half a stud a second. A leap is measured against it, never against a height first seen in
-- mid-air: on a slow client that ended the flight a tenth of a second in, 2.4 studs off the floor.
local standY = nil
local reseatSerial = workspace:GetAttribute("EntityReseatCount")
local transitionAge, transitionDuration = 1, 0
local lungeSerial = workspace:GetAttribute("EntityLunge")
local pendingWindup, pendingWindupAt = false, 0
local stepSerial = 0
local debugClip, debugPhase = nil, 0
local debugClock, actionClock, rigRetryAt = 0, 0, 0
local lastBeat = 0
local actionTracks = {}
local dataDirty, renderBound, closed = true, false, false
local maintenanceClock = 0

local function disconnectAll(list)
	for _, connection in ipairs(list) do connection:Disconnect() end
	table.clear(list)
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function decodeClip(raw)
	local data = HttpService:JSONDecode(raw)
	assert(type(data) == "table" and finite(data.frames) and data.frames >= 2 and data.frames % 1 == 0, "invalid frames")
	assert(finite(data.fps) and data.fps > 0 and type(data.loop) == "boolean" and type(data.bones) == "table", "invalid metadata")
	local duration = data.frames / data.fps
	local stride, authoredSpeed = tonumber(data.stride) or 0, tonumber(data.speed) or 0
	assert(finite(duration) and duration > 0 and finite(stride) and stride >= 0 and finite(authoredSpeed) and authoredSpeed >= 0, "invalid timing/stride")
	assert(not data.loop or stride > 0, "zero gait stride")
	local count = data.frames
	assert(count <= 600, "clip too large")
	local tracks = {}
	for name, quaternions in pairs(data.bones) do
		assert(type(name) == "string" and type(quaternions) == "table" and #quaternions == count * 4, "invalid bone track")
		local frames = table.create(count)
		for f = 0, count - 1 do
			local i = f * 4
			local x, y, z, w = quaternions[i + 1], quaternions[i + 2], quaternions[i + 3], quaternions[i + 4]
			assert(finite(x) and finite(y) and finite(z) and finite(w), "invalid quaternion")
			local norm = math.sqrt(x * x + y * y + z * z + w * w)
			assert(finite(norm) and norm > 0.01, "invalid quaternion norm")
			frames[f + 1] = CFrame.new(0, 0, 0, x / norm, y / norm, z / norm, w / norm)
		end
		tracks[name] = frames
	end
	local hips = nil
	if data.hips ~= nil then
		assert(type(data.hips) == "table" and #data.hips == count * 3, "invalid hips track")
		hips = table.create(count)
		for f = 0, count - 1 do
			local i = f * 3
			local x, y, z = data.hips[i + 1], data.hips[i + 2], data.hips[i + 3]
			assert(finite(x) and finite(y) and finite(z), "invalid hips position")
			local position = Vector3.new(x / 1000, y / 1000, z / 1000)
			assert(finite(position.X) and finite(position.Y) and finite(position.Z), "hips overflow")
			hips[f + 1] = position
		end
		-- Cache complete Hips poses: CFrame:Lerp already interpolates translation.
		local rotations = tracks.Hips
		if rotations then
			local poses = table.create(count)
			for f = 1, count do poses[f] = CFrame.new(hips[f]) * rotations[f] end
			tracks.Hips = poses
		end -- An absent Hips bone track leaves its entire Animator pose untouched.
	end
	local contacts = data.contacts
	if contacts ~= nil then
		assert(type(contacts) == "table" and (#contacts == 2 or (not data.loop and #contacts == 0)), "invalid contacts")
		for _, contact in ipairs(contacts) do assert(finite(contact) and contact >= 0 and contact < 1, "invalid contact phase") end
	end
	return {frames = count, fps = data.fps, duration = duration, loop = data.loop,
		tracks = tracks, stride = stride, speed = authoredSpeed,
		contacts = contacts or {0, 0.5}}
end

local function loadClip(name)
	local value = sourceFolder and sourceFolder:FindFirstChild(name)
	clips[name] = nil
	if not value or not value:IsA("StringValue") then return end
	local ok, result = pcall(decodeClip, value.Value)
	if ok then
		clips[name] = result
	else
		warn("[L1EntityMotion] " .. name .. ": " .. tostring(result))
	end
end

local function refreshData()
	local owner = ReplicatedStorage:FindFirstChild("Level1EntityMotion")
	local folder = owner and owner:FindFirstChild("Clips")
	if folder == sourceFolder then return end
	disconnectAll(sourceConnections)
	for value, connection in pairs(valueConnections) do connection:Disconnect(); valueConnections[value] = nil end
	sourceFolder = folder
	table.clear(clips)
	if not folder then return end
	local function watchValue(value)
		if value:IsA("StringValue") and table.find(CLIP_NAMES, value.Name) then
			valueConnections[value] = value:GetPropertyChangedSignal("Value"):Connect(function() loadClip(value.Name) end)
			loadClip(value.Name)
		end
	end
	for _, value in ipairs(folder:GetChildren()) do watchValue(value) end
	table.insert(sourceConnections, folder.ChildAdded:Connect(watchValue))
	table.insert(sourceConnections, folder.ChildRemoved:Connect(function(value)
		local connection = valueConnections[value]
		if connection then connection:Disconnect(); valueConnections[value] = nil end
		loadClip(value.Name)
	end))
end

local function actionOwned(track)
	if ACTION_NAMES[track.Name] then return true end
	local animation = track.Animation
	return animation ~= nil and ACTION_IDS[string.match(animation.AnimationId, "%d+$")] == true
end

local function observeAction(track)
	if actionOwned(track) then actionTracks[track] = true end
end

local function reconcileActions()
	if not rig or not rig.animator then return end
	table.clear(actionTracks)
	for _, track in ipairs(rig.animator:GetPlayingAnimationTracks()) do observeAction(track) end
end

local function hasServerAction()
	for track in pairs(actionTracks) do
		if track.IsPlaying and track.WeightCurrent > 0.001 then return true end
	end
	return false
end

local function restoreRig()
	if not rig then return end
	for _, record in ipairs(rig.records) do
		local bone = record.bone
		if bone.Parent and record.lastWritten and bone.Transform == record.lastWritten then
			bone.Transform = record.lastAnimator or IDENTITY
		end
		record.lastWritten, record.lastTarget, record.from = nil, nil, nil
	end
end

local function resetMotion()
	lastPosition, groundY, standY = nil, nil, nil
	speed, verticalSpeed, weight = 0, 0, 0
	moving, phase, pendingWindup = false, nil, false
	gaitPhase, phaseAge, absorbAge = 0, 0, 1
	walkWeight, prowlWeight, runWeight = 1, 0, 0
	transitionAge, transitionDuration = 1, 0
	workspace:SetAttribute("L1EntityStep", nil)
end

local function discardRig(preserveMotion)
	restoreRig()
	if rig then disconnectAll(rig.connections) end
	rig = nil
	table.clear(actionTracks)
	if not preserveMotion then resetMotion() end
end

local function collectRig()
	local entity = workspace:FindFirstChild("Entity")
	if not entity then
		if rig then discardRig() end
		rigDirty = false -- ChildAdded wakes discovery; lobby frames do no searches.
		return nil
	end
	local mesh = entity and entity:FindFirstChild("char1")
	local root = entity and entity:FindFirstChild("HumanoidRootPart")
	if not entity or not entity:IsA("Model") or not mesh or not mesh:IsA("MeshPart") or not root or not root:IsA("BasePart") then
		if rig then discardRig() end
		return nil
	end
	if rig and rig.entity == entity and rig.mesh == mesh and rig.root == root and not rigDirty then return rig end
	if not rig and os.clock() < rigRetryAt then return nil end
	rigRetryAt = os.clock() + 0.15
	-- Bone/Animator arrival on this root must not restart an airborne lunge.
	local preserveMotion = rig and rig.entity == entity and rig.mesh == mesh and rig.root == root
	discardRig(preserveMotion)
	local records, bones = {}, {}
	for _, descendant in ipairs(mesh:GetDescendants()) do
		if descendant:IsA("Bone") then
			bones[descendant.Name] = descendant
			local restRootRotation = root.CFrame:ToObjectSpace(descendant.WorldCFrame).Rotation
			table.insert(records, {name = descendant.Name, bone = descendant, lastAnimator = IDENTITY,
				restRootRotation = restRootRotation,
				restRootInverse = restRootRotation:Inverse(),
				rootUpLocal = descendant.Name == "Hips" and restRootRotation:VectorToObjectSpace(Vector3.new(0, 1, 0)) or nil,
				landingPitch = math.rad(LAND_COMPRESS_DEGREES[descendant.Name] or 0)})
		end
	end
	if not bones.Hips or not bones.Head then resetMotion(); return nil end
	table.sort(records, function(a, b) return a.name < b.name end)
	local humanoid = entity:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	rig = {entity = entity, mesh = mesh, root = root, records = records, animator = animator, connections = {}}
	local function boneChanged(descendant) if descendant:IsA("Bone") then rigDirty = true end end
	table.insert(rig.connections, mesh.DescendantAdded:Connect(boneChanged))
	table.insert(rig.connections, mesh.DescendantRemoving:Connect(boneChanged))
	table.insert(rig.connections, entity.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Animator") then rigDirty = true end
	end))
	table.insert(rig.connections, entity.DescendantRemoving:Connect(function(descendant)
		if descendant == root or descendant == mesh or descendant == animator then rigDirty = true end
	end))
	if animator then table.insert(rig.connections, animator.AnimationPlayed:Connect(observeAction)) end
	rigDirty = false
	reconcileActions()
	return rig
end

-- Loops contain no duplicate end frame. Nonloops reach their final pose at phase one.
local function atPhase(c, p)
	local f = c.loop and ((p % 1) * c.frames) or (math.clamp(p, 0, 1) * (c.frames - 1))
	local i = math.floor(f)
	local nextIndex = c.loop and ((i + 1) % c.frames + 1) or math.min(i + 2, c.frames)
	return i + 1, nextIndex, f - i
end

local function sampleBone(c, name, i0, i1, a)
	if not c then return nil end
	local frames = c.tracks[name]
	return frames and frames[i0]:Lerp(frames[i1], a) or nil
end

local function beginPhase(nextPhase, duration)
	phase, phaseAge = nextPhase, 0
	transitionAge, transitionDuration = 0, duration
	if rig then
		for _, record in ipairs(rig.records) do record.from = record.lastTarget end
	end
end

local function readDebug()
	debugClip, debugPhase = nil, 0
	local value = workspace:GetAttribute("L1EntityMotionDebug")
	if type(value) ~= "string" then return end
	local name, p = string.match(value, "^([%w_]+)@([%+%-]?[%d%.]+)$")
	p = tonumber(p)
	if name and finite(p) and table.find(CLIP_NAMES, name) then debugClip, debugPhase = name, math.clamp(p, 0, 1) end
end

local function crossedContacts(c, fromPhase, toPhase)
	local count = 0
	for _, contact in ipairs(c.contacts) do count += math.floor(toPhase - contact) - math.floor(fromPhase - contact) end
	return count
end

local function publishDebug(gait)
	script:SetAttribute("Phase", phase or "gait")
	script:SetAttribute("Gait", gait)
	script:SetAttribute("Weight", weight)
	script:SetAttribute("GaitPhase", gaitPhase % 1)
	script:SetAttribute("MeasuredSpeed", speed)
end

local function step(dt)
	if not finite(dt) or dt <= 0 then return end
	-- Bound arithmetic after a hitch; a second already expires every one-shot.
	local elapsed = dt
	dt = math.min(dt, 1)
	local currentRig = rigDirty and collectRig() or rig
	if not currentRig then
		if renderBound then RunService:UnbindFromRenderStep(BIND_NAME); renderBound = false end
		debugClock = 0
		publishDebug("unavailable")
		return
	end
	local root = currentRig.root
	local position = root.Position
	if not finite(position.X) or not finite(position.Y) or not finite(position.Z) then
		restoreRig(); resetMotion(); return
	end
	local kill = workspace:GetAttribute("EntityKillActive") == true
	local paused = workspace:GetAttribute("EntityPaused") == true
	local state = workspace:GetAttribute("EntityState")
	local disabled = workspace:GetAttribute("L1EntityMotionOff") == true
	local isLunging = workspace:GetAttribute("EntityIsLunging") == true
	local serial = workspace:GetAttribute("EntityReseatCount")
	local snapped = finite(serial) and serial ~= reseatSerial
	reseatSerial = serial
	local measuredSpeed, measuredVertical = 0, 0
	if lastPosition then
		local dx, dy, dz = position.X - lastPosition.X, position.Y - lastPosition.Y, position.Z - lastPosition.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local displacement = math.sqrt(dx * dx + dy * dy + dz * dz)
		if not snapped and displacement <= math.max(18, elapsed * 180) then
			measuredSpeed, measuredVertical = distance / elapsed, dy / elapsed
			if not finite(measuredSpeed) or not finite(measuredVertical) then snapped = true end
		else
			snapped = true
		end
	end
	if snapped then
		restoreRig()
		resetMotion()
		measuredSpeed, measuredVertical = 0, 0
	end
	lastPosition = position
	if root.Anchored or paused or kill or disabled then measuredSpeed = 0 end
	speed += (measuredSpeed - speed) * (1 - math.exp(-dt / 0.10))
	verticalSpeed += (measuredVertical - verticalSpeed) * (1 - math.exp(-dt / 0.05))
	local serverAction = state == "ALERT" or state == "YELL" or hasServerAction()
	-- A kill deliberately dips the root; airborne samples are not standing height.
	-- Preserve a known baseline through windup/flight, including same-root recollection.
	if not kill and not paused and not disabled and not serverAction and not root.Anchored
		and not isLunging and phase ~= "flight" and phase ~= "windup" then
		standY = standY and math.min(position.Y, standY + dt * 0.5) or position.Y
	end
	if kill or paused or disabled then
		phase, pendingWindup, absorbAge = nil, false, 1
	elseif pendingWindup and os.clock() - pendingWindupAt <= 0.6 then
		pendingWindup = false
		if isLunging then
			groundY = standY
			beginPhase("flight", 0.04)
		else
			groundY = standY or position.Y
			beginPhase("windup", 0.08)
		end
	else
		pendingWindup = false
	end
	phaseAge += dt
	transitionAge += dt
	absorbAge += dt
	if not kill and not paused and not disabled then
		if phase == "windup" then
			if isLunging or (groundY and position.Y - groundY > 0.3) then
				beginPhase("flight", 0.04)
			elseif phaseAge >= 0.6 then beginPhase(nil, 0.10) end
		elseif phase == "flight" then
			local aboveLaunch = groundY and position.Y - groundY or math.huge
			-- the real arc is 0.43 s (42 studs/s up against gravity): nothing lands in under 0.22
			-- LUNGE_GROUND_20261010 (seen in play): after a touchdown with the slightest rebound the filtered
			-- vertical speed stays a hair above zero for ever, and a strict <= 0 held the flight pose until the
			-- 0.9 s watchdog. Back at standing height and not rising to speak of is a landing.
			if (phaseAge > 0.22 and aboveLaunch < 0.35 and verticalSpeed <= 1.5) or phaseAge > 0.9 then
				if speed >= 8 then
					beginPhase("moving_land", 0.06)
					absorbAge, gaitPhase = 0, 0
				else
					beginPhase("land", 0.06)
				end
			end
		elseif phase == "land" then
			if phaseAge >= 0.35 then beginPhase(nil, 0.08); gaitPhase = 0 end
		elseif phase == "moving_land" then
			if phaseAge >= 0.35 then beginPhase(nil, 0.08) end
		elseif isLunging then
			-- On an airborne first observation there is no trustworthy floor sample.
			-- Use the watchdog instead of calling that airborne height a landing.
			groundY = standY
			beginPhase("flight", 0.04)
		elseif math.abs(verticalSpeed) < 2 then
			groundY = position.Y
		end
	end

	if moving then moving = speed > 0.18 else moving = speed > 0.55 end
	local walk, prowl, run = clips.Walk, clips.Prowl, clips.Run
	if prowl and (not prowl.loop or prowl.stride <= 0) then prowl = nil end
	local validGaits = walk and run and walk.loop and run.loop and walk.stride > 0 and run.stride > 0
	-- ENTITY_MOTION_LIVE_20261010: the step sound and the camera stomp hand their timing to this layer only
	-- while it proves, ten times a second, that it is running and able to step. Switched off, without gait
	-- data, or dead for any reason, their own timers take over again: this script can never make the Entity
	-- silent.
	if validGaits and not disabled and os.clock() - lastBeat >= 0.1 then
		lastBeat = os.clock()
		workspace:SetAttribute("L1EntityMotionBeat", lastBeat)
	end
	local lungeClip = phase == "windup" and clips.Lunge_Windup or phase == "flight" and clips.Lunge_Flight or phase == "land" and clips.Lunge_Land or nil
	local frozen = debugClip and clips[debugClip] or nil
	local gaitPlaying = phase == nil or phase == "moving_land"
	local want = not disabled and not kill and not paused and not serverAction and (frozen ~= nil or (lungeClip ~= nil) or (validGaits and gaitPlaying and (moving or phase == "moving_land")))
	local fadeSeconds = want and 0.18 or (kill and 0.12 or 0.22)
	weight = want and math.min(1, weight + dt / fadeSeconds) or math.max(0, weight - dt / fadeSeconds)
	if disabled then weight = 0 end
	if weight <= 0 then
		restoreRig()
		workspace:SetAttribute("L1EntityStep", nil)
		debugClock += dt
		if debugClock >= 0.1 then debugClock = 0; publishDebug("idle") end
		return
	end

	local multiplier = workspace:GetAttribute("EntitySpeedMul")
	if not finite(multiplier) or multiplier <= 0 then multiplier = 1 end
	local v = speed / multiplier
	local desiredWalk, desiredProwl, desiredRun = 0, 0, 0
	if v < 10.5 then desiredWalk = 1
	elseif v < 14 then desiredProwl = (v - 10.5) / 3.5; desiredWalk = 1 - desiredProwl
	elseif v < 20.5 then desiredProwl = 1
	elseif v < 24 then desiredRun = (v - 20.5) / 3.5; desiredProwl = 1 - desiredRun
	else desiredRun = 1 end
	if not prowl then
		desiredRun = math.clamp((v - 10.5) / 13.5, 0, 1)
		desiredWalk, desiredProwl = 1 - desiredRun, 0
	end
	local alpha = 1 - math.exp(-dt / 0.15)
	walkWeight += (desiredWalk - walkWeight) * alpha
	prowlWeight += (desiredProwl - prowlWeight) * alpha
	runWeight += (desiredRun - runWeight) * alpha
	if phase == "moving_land" then walkWeight, prowlWeight, runWeight = 0, 0, 1 end
	-- Quaternion blends bend the foot path below either source; a measured pair lift preserves clearance.
	local blendLift = 0.68 * walkWeight * prowlWeight + 0.68 * prowlWeight * runWeight + 1.40 * walkWeight * runWeight
	local stride = validGaits and (walk.stride * walkWeight + (prowl and prowl.stride or 0) * prowlWeight + run.stride * runWeight) or 1
	if validGaits and gaitPlaying and not lungeClip and not frozen then
		local nextPhase = gaitPhase + speed * dt / math.max(stride, 0.01)
		if want and moving then
			if workspace:GetAttribute("L1EntityStep") == nil then workspace:SetAttribute("L1EntityStep", stepSerial) end
			local count = crossedContacts(walk, gaitPhase, nextPhase)
			if count > 0 then stepSerial += count; workspace:SetAttribute("L1EntityStep", stepSerial) end
		else workspace:SetAttribute("L1EntityStep", nil) end
		gaitPhase = nextPhase % 1
	else workspace:SetAttribute("L1EntityStep", nil) end

	local wi0, wi1, wa, pi0, pi1, pa, ri0, ri1, ra = 1, 1, 0, 1, 1, 0, 1, 1, 0
	if walk then wi0, wi1, wa = atPhase(walk, gaitPhase) end
	if prowl then pi0, pi1, pa = atPhase(prowl, gaitPhase) end
	if run then ri0, ri1, ra = atPhase(run, gaitPhase) end
	local single = frozen or lungeClip
	local si0, si1, sa = 1, 1, 0
	if single then
		local p = frozen and debugPhase or (phase == "flight" and phaseAge / 0.428 or phaseAge / single.duration)
		si0, si1, sa = atPhase(single, p)
	end
	local transition = transitionDuration > 0 and math.clamp(transitionAge / transitionDuration, 0, 1) or 1
	for _, record in ipairs(currentRig.records) do
		local bone = record.bone
		if bone.Parent then
			local animatorPose = bone.Transform
			if record.lastWritten and animatorPose == record.lastWritten then animatorPose = record.lastAnimator or IDENTITY end
			record.lastAnimator = animatorPose
			local target, owned = animatorPose, false
			if single then
				local sampled = sampleBone(single, record.name, si0, si1, sa)
				if sampled then target, owned = sampled, true end
			elseif validGaits then
				local a = sampleBone(walk, record.name, wi0, wi1, wa)
				local b = sampleBone(prowl, record.name, pi0, pi1, pa)
				local c = sampleBone(run, record.name, ri0, ri1, ra)
				owned = a ~= nil or b ~= nil or c ~= nil
				local sum = walkWeight + prowlWeight
				if sum > 0.000001 then target = (a or animatorPose):Lerp(b or animatorPose, prowlWeight / sum) end
				target = target:Lerp(c or animatorPose, runWeight)
			end
			if owned and record.rootUpLocal and not single and blendLift > 0 then
				target = CFrame.new(target.Position + record.rootUpLocal * blendLift) * target.Rotation
			end
			-- The brief's extra Hips dip buries a planted Run foot; absorption stays above the pelvis.
			if owned and record.landingPitch ~= 0 and absorbAge < 0.25 and not single then
				local absorb = (1 - absorbAge / 0.25) ^ 2
				local rest = record.restRootRotation
				local pitch = record.restRootInverse * CFrame.Angles(-record.landingPitch * absorb, 0, 0) * rest
				target = CFrame.new(target.Position) * pitch * target.Rotation
			end
			if owned and record.from and transition < 1 and not frozen then target = record.from:Lerp(target, transition) end
			-- A late Flight-to-Run handoff can dip the toe between endpoints; this small lift eases to zero.
			if phase == "moving_land" and owned and record.rootUpLocal and not single and record.from and transition < 1 then
				local lift = 0.06 * math.sin(math.pi * transition) ^ 2
				target = CFrame.new(target.Position + record.rootUpLocal * lift) * target.Rotation
			end
			if owned or record.lastWritten then
				local written = animatorPose:Lerp(target, weight)
				bone.Transform = written
				record.lastWritten, record.lastTarget = written, target
			end
		end
	end
	debugClock += dt
	if debugClock >= 0.1 then
		debugClock = 0
		local gait = frozen and debugClip or lungeClip and (phase or "lunge") or (runWeight >= prowlWeight and runWeight > walkWeight and "Run" or prowlWeight > walkWeight and "Prowl" or "Walk")
		publishDebug(gait)
	end
end

table.insert(connections, workspace:GetAttributeChangedSignal("EntityLunge"):Connect(function()
	local serial = workspace:GetAttribute("EntityLunge")
	if finite(serial) and serial ~= lungeSerial then pendingWindup, pendingWindupAt = true, os.clock() end
	lungeSerial = serial
end))
table.insert(connections, workspace:GetAttributeChangedSignal("L1EntityMotionDebug"):Connect(readDebug))
table.insert(connections, workspace.ChildAdded:Connect(function(child)
	if child.Name == "Entity" then rigDirty, rigRetryAt = true, 0 end
end))
table.insert(connections, workspace.ChildRemoved:Connect(function(child)
	if child.Name == "Entity" or (rig and rig.entity == child) then
		rigDirty = true
		if rig and rig.entity == child then
			if renderBound then RunService:UnbindFromRenderStep(BIND_NAME); renderBound = false end
			discardRig()
			publishDebug("unavailable")
		end
	end
end))
local function dataChanged(child)
	if child.Name == "Level1EntityMotion" or child.Name == "Clips" then dataDirty = true end
end
table.insert(connections, ReplicatedStorage.DescendantAdded:Connect(dataChanged))
table.insert(connections, ReplicatedStorage.DescendantRemoving:Connect(dataChanged))
local function maintain(dt)
	if closed then return end
	if dataDirty then dataDirty = false; refreshData() end
	if rig and finite(dt) and dt > 0 then
		actionClock += math.min(dt, 1)
		if actionClock >= 0.1 then actionClock = 0; reconcileActions() end
	end
	if not rigDirty then return end
	if finite(dt) and dt > 0 then maintenanceClock += math.min(dt, 1) end
	if maintenanceClock < 0.15 then return end
	maintenanceClock = 0
	local available = collectRig() ~= nil
	if available and not renderBound then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Character.Value + 1, step)
		renderBound = true
	elseif not available and renderBound then
		RunService:UnbindFromRenderStep(BIND_NAME)
		renderBound = false
		publishDebug("unavailable")
	end
end
table.insert(connections, RunService.Heartbeat:Connect(maintain))
readDebug()
refreshData()
dataDirty = false
maintain(0.15)
if not rig then publishDebug("unavailable") end
script.Destroying:Connect(function()
	closed = true
	RunService:UnbindFromRenderStep(BIND_NAME)
	renderBound = false
	discardRig()
	disconnectAll(connections)
	disconnectAll(sourceConnections)
	for value, connection in pairs(valueConnections) do connection:Disconnect(); valueConnections[value] = nil end
end)
