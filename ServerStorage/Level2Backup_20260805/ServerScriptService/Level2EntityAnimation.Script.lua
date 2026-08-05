-- Attribute-driven animation mixer for every tagged Level 2 hostile.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Profiles = require(ServerScriptService:WaitForChild("Level2EntityProfiles"))
local MeshyPlayer = require(ServerScriptService:WaitForChild("Level2MeshyAnimationPlayer"))
local TAG = Profiles.TagName
local bindings = setmetatable({}, {__mode = "k"})

local function animatorFor(entity)
	local humanoid = entity:FindFirstChildOfClass("Humanoid")
		or entity:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		return humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	end
	local controller = entity:FindFirstChildOfClass("AnimationController")
		or entity:FindFirstChildWhichIsA("AnimationController", true)
	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "EntityAnimationController"
		controller.Parent = entity
	end
	return controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
end

local function stopCurrent(binding, fade)
	local track = binding.CurrentTrack
	if track and track.IsPlaying then
		pcall(function() track:Stop(fade or 0.18) end)
	end
	binding.CurrentTrack = nil
	binding.CurrentKey = nil
	binding.CurrentMotion = nil
end

local function getTrack(binding, id, kind)
	local key = kind .. "|" .. id
	if binding.Tracks[key] then
		return binding.Tracks[key]
	end
	local animation = Instance.new("Animation")
	animation.Name = kind .. "Animation"
	animation.AnimationId = id
	animation.Parent = binding.Folder
	local ok, track = pcall(function()
		return binding.Animator:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn("[Level2EntityAnimation] Could not load", binding.Entity:GetFullName(), kind, id, track)
		animation:Destroy()
		return nil
	end
	track.Name = kind .. "Track"
	track.Priority = kind == "Attack" and Enum.AnimationPriority.Action
		or (kind == "Idle" and Enum.AnimationPriority.Idle or Enum.AnimationPriority.Movement)
	track.Looped = kind ~= "Attack"
	binding.Tracks[key] = track
	return track
end

local function playbackSpeed(binding, motion)
	if motion == "Walk" then
		return math.clamp(
			(tonumber(binding.Entity:GetAttribute("MoveSpeed")) or binding.Profile.WanderSpeed)
				/ binding.Profile.ReferenceWalkSpeed,
			0.35,
			2.4
		)
	end
	if motion == "Chase" or motion == "Burst" then
		return math.clamp(
			(tonumber(binding.Entity:GetAttribute("MoveSpeed")) or binding.Profile.ChaseSpeed)
				/ binding.Profile.ReferenceRunSpeed,
			0.5,
			2.8
		)
	end
	return 1
end

local function chooseCandidate(binding, motion)
	local candidates = Profiles.AnimationCandidates(binding.Entity, motion)
	if #candidates == 0 then
		return nil
	end
	if #candidates == 1 then
		return candidates[1]
	end
	local previous = binding.LastChoice[motion]
	local index = math.random(1, #candidates)
	if candidates[index] == previous then
		index = index % #candidates + 1
	end
	binding.LastChoice[motion] = candidates[index]
	return candidates[index]
end

local function shouldUseProcedural(binding, motion)
	if not binding.ProceduralMotors then return false end
	if binding.Entity:GetAttribute("ForceProceduralAnimation") == true then return true end
	local candidateMotion = motion
	if motion == "Recover" then candidateMotion = "Attack" end
	if motion ~= "Idle" and motion ~= "Walk" and motion ~= "Chase"
		and motion ~= "Burst" and motion ~= "Attack" and motion ~= "Recover" then
		candidateMotion = "Idle"
	end
	return #Profiles.AnimationCandidates(binding.Entity, candidateMotion) == 0
end

local function resetProcedural(binding)
	if not binding.ProceduralMotors then return end
	for _, joint in pairs(binding.ProceduralMotors) do
		joint.Transform = CFrame.identity
	end
	binding.ProceduralActive = false
end

local function applyMotion(binding, force)
	if not binding.Active then return end
	local motion = binding.Entity:GetAttribute("MotionState") or "Idle"
	local candidateMotion = motion
	if motion == "Recover" or motion == "Attack" then
		candidateMotion = "Attack"
	elseif motion ~= "Idle" and motion ~= "Walk" and motion ~= "Chase" and motion ~= "Burst" then
		candidateMotion = "Idle"
	end
	local hasPublishedSlot = #Profiles.AnimationCandidates(binding.Entity, candidateMotion) > 0
	if binding.Meshy and not hasPublishedSlot then
		if binding.UsePublishedSlots then
			stopCurrent(binding, 0.1)
		end
		binding.UsePublishedSlots = false
		MeshyPlayer.SetMotion(binding.Meshy, motion, force)
		binding.CurrentMotion = motion
		binding.Entity:SetAttribute("ActiveAnimationSource", "EmbeddedMeshyFallback")
		return
	elseif binding.Meshy then
		binding.UsePublishedSlots = true
		binding.Entity:SetAttribute("ActiveAnimationSource", "RobloxAnimationIDSlot")
	end
	if shouldUseProcedural(binding, motion) then
		stopCurrent(binding, 0.12)
		binding.ProceduralActive = true
		return
	elseif binding.ProceduralActive then
		resetProcedural(binding)
	end
	if motion == "Attack" or motion == "Recover" then
		stopCurrent(binding, 0.12)
		return
	end
	local animationMotion = motion
	if motion ~= "Idle" and motion ~= "Walk" and motion ~= "Chase" and motion ~= "Burst" then
		animationMotion = "Idle"
	end

	if not force and binding.CurrentTrack and binding.CurrentMotion == animationMotion then
		if binding.CurrentTrack.IsPlaying then
			binding.CurrentTrack:AdjustSpeed(playbackSpeed(binding, animationMotion))
		else
			binding.CurrentTrack:Play(0.16, 1, playbackSpeed(binding, animationMotion))
		end
		return
	end

	local id = chooseCandidate(binding, animationMotion)
	if not id then
		stopCurrent(binding, 0.2)
		return
	end
	local key = animationMotion .. "|" .. id
	if not force and binding.CurrentKey == key and binding.CurrentTrack then
		if binding.CurrentTrack.IsPlaying then
			binding.CurrentTrack:AdjustSpeed(playbackSpeed(binding, animationMotion))
		else
			binding.CurrentTrack:Play(0.16, 1, playbackSpeed(binding, animationMotion))
		end
		return
	end

	stopCurrent(binding, 0.16)
	local track = getTrack(binding, id, animationMotion)
	if not track then return end
	binding.CurrentTrack = track
	binding.CurrentKey = key
	binding.CurrentMotion = animationMotion
	track:Play(0.18, 1, playbackSpeed(binding, animationMotion))
	if animationMotion == "Idle" then
		binding.NextIdleChange = os.clock() + math.random(5, 11)
	end
end

local function playAction(binding)
	if not binding.Active then return end
	local serial = tonumber(binding.Entity:GetAttribute("ActionSerial")) or 0
	if serial == binding.LastActionSerial then return end
	binding.LastActionSerial = serial
	binding.ProcActionStarted = os.clock()
	binding.ProcAttackVariant = serial % 2 + 1
	local hasPublishedAttack = #Profiles.AnimationCandidates(binding.Entity, "Attack") > 0
	if binding.Meshy and not hasPublishedAttack then
		binding.UsePublishedSlots = false
		MeshyPlayer.PlayAction(binding.Meshy, serial)
		binding.Entity:SetAttribute("ActiveAnimationSource", "EmbeddedMeshyFallback")
		return
	elseif binding.Meshy then
		binding.UsePublishedSlots = true
		binding.Entity:SetAttribute("ActiveAnimationSource", "RobloxAnimationIDSlot")
	end
	if shouldUseProcedural(binding, "Attack") then
		stopCurrent(binding, 0.08)
		binding.ProceduralActive = true
		return
	end
	local id = chooseCandidate(binding, "Attack")
	if not id then
		stopCurrent(binding, 0.1)
		return
	end
	stopCurrent(binding, 0.08)
	local track = getTrack(binding, id, "Attack")
	if track then
		track.TimePosition = 0
		track:Play(0.08, 1, 1)
	end
end

local function setupProcedural(binding)
	local entity = binding.Entity
	if entity:GetAttribute("UseProceduralAnimation") ~= true
		and entity:GetAttribute("ProceduralPipeRig") ~= true then
		return
	end
	local root = entity.PrimaryPart or entity:FindFirstChild("HumanoidRootPart", true)
	if not root or not root:IsA("BasePart") then return end

	-- The generator deliberately anchors imported rigs. A procedural Motor6D rig
	-- keeps only its invisible root anchored; every visual/joint part is server-owned.
	for _, object in ipairs(entity:GetDescendants()) do
		if object:IsA("BasePart") then
			object.CanCollide = false
			object.CanTouch = false
			object.Massless = true
			if object == root then
				object.Anchored = true
				object.CanQuery = true
			else
				object.Anchored = false
				object.CanQuery = false
				pcall(function() object:SetNetworkOwner(nil) end)
			end
		end
	end

	local motors = {}
	for _, object in ipairs(entity:GetDescendants()) do
		if object:IsA("Motor6D") then
			motors[object.Name] = object
			object.Transform = CFrame.identity
		end
	end
	if not motors.RootJoint or not motors.Waist then
		warn("[Level2EntityAnimation] Procedural rig is missing core motors", entity:GetFullName())
		return
	end
	binding.ProceduralMotors = motors
	binding.ProceduralActive = true
	binding.ProcClock = 0
	binding.ProcLastMotion = ""
	binding.ProcIdleVariant = math.random(1, 5)
	binding.ProcWalkVariant = math.random(1, 3)
	binding.ProcNextIdleVariantAt = os.clock() + math.random(5, 8)
	binding.ProcActionStarted = os.clock()
	binding.ProcAttackVariant = 1
	binding.ProcActionSerial = tonumber(entity:GetAttribute("ActionSerial")) or 0
end

local function put(pose, name, value)
	pose[name] = value
end

local function fingers(pose, curl, asymmetry)
	asymmetry = asymmetry or 0
	for _, sideName in ipairs({"Left", "Right"}) do
		local sideSign = sideName == "Left" and -1 or 1
		for index = 1, 3 do
			local spread = (index - 2) * math.rad(4) * sideSign
			local individual = curl + (index == 2 and .08 or -.03)
				+ asymmetry * sideSign
			put(pose, sideName .. "Finger" .. index .. "A",
				CFrame.Angles(individual, spread, 0))
			put(pose, sideName .. "Finger" .. index .. "B",
				CFrame.Angles(individual * .72, 0, 0))
		end
	end
end

local function idlePose(binding, pose, t)
	local variant = binding.ProcIdleVariant
	if variant == 1 then
		local breath = math.sin(t * 1.35)
		put(pose, "RootJoint", CFrame.new(0, breath * .035, 0))
		put(pose, "Waist", CFrame.Angles(math.rad(2.2) * breath, 0, math.rad(1.2) * breath))
		put(pose, "Neck", CFrame.Angles(math.rad(-2) * breath, math.rad(4) * math.sin(t * .55), 0))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(3) * breath, 0, math.rad(-2)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(3) * breath, 0, math.rad(2)))
		fingers(pose, math.rad(11), math.rad(1))
	elseif variant == 2 then
		local listen = math.sin(t * .7)
		put(pose, "RootJoint", CFrame.new(-.06, 0, -.08) * CFrame.Angles(0, 0, math.rad(-2)))
		put(pose, "Waist", CFrame.Angles(math.rad(-8), math.rad(7), math.rad(-4)))
		put(pose, "Neck", CFrame.Angles(math.rad(10 + listen * 3), math.rad(27 + listen * 8), math.rad(-7)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(-5), 0, math.rad(-8)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(10), 0, math.rad(5)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(-8), math.rad(7), 0))
		fingers(pose, math.rad(19), math.rad(2))
	elseif variant == 3 then
		local twitch = math.sin(t * 18) * math.sin(t * 3.1)
		local scrape = math.sin(t * 5.7)
		put(pose, "RootJoint", CFrame.new(twitch * .025, math.abs(scrape) * .025, 0)
			* CFrame.Angles(0, math.rad(twitch * 2), math.rad(twitch * 1.5)))
		put(pose, "Waist", CFrame.Angles(math.rad(twitch * 3.5), math.rad(scrape * 2), math.rad(twitch * 2)))
		put(pose, "Neck", CFrame.Angles(math.rad(-8 + twitch * 6), math.rad(twitch * 4), math.rad(scrape * 3)))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(twitch * 9), 0, math.rad(-4)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(-twitch * 9), 0, math.rad(4)))
		fingers(pose, math.rad(24 + twitch * 5), math.rad(twitch))
	elseif variant == 4 then
		local sway = math.sin(t * .52)
		local counter = math.cos(t * .52)
		put(pose, "RootJoint", CFrame.new(sway * .11, 0, 0)
			* CFrame.Angles(0, math.rad(sway * 3), math.rad(sway * 4)))
		put(pose, "Waist", CFrame.Angles(math.rad(counter * 2), math.rad(-sway * 5), math.rad(sway * 7)))
		put(pose, "Neck", CFrame.Angles(math.rad(counter * 3), math.rad(sway * 10), math.rad(-sway * 8)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(counter * 5), 0, math.rad(-sway * 4)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-counter * 5), 0, math.rad(-sway * 4)))
		fingers(pose, math.rad(8 + counter * 3), 0)
	else
		local almostStill = math.sin(t * .35)
		put(pose, "RootJoint", CFrame.new(0, -.06, .08) * CFrame.Angles(math.rad(-3), 0, 0))
		put(pose, "Waist", CFrame.Angles(math.rad(-13 + almostStill), 0, math.rad(2)))
		put(pose, "Neck", CFrame.Angles(math.rad(19), math.rad(almostStill * 3), math.rad(-3)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(-7), math.rad(-3), math.rad(10)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-7), math.rad(3), math.rad(-10)))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(12), 0, math.rad(5)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(12), 0, math.rad(-5)))
		fingers(pose, math.rad(34), math.rad(2))
	end
end

local function walkPose(binding, pose, t, fast)
	local speed = tonumber(binding.Entity:GetAttribute("MoveSpeed")) or binding.Profile.WanderSpeed
	local reference = fast and binding.Profile.ReferenceRunSpeed or binding.Profile.ReferenceWalkSpeed
	local rate = math.clamp(speed / math.max(reference, .1), .55, 2.6)
	local phase = t * (fast and 7.4 or 4.2) * rate
	local stride = math.sin(phase)
	local lift = math.max(0, math.sin(phase))
	local oppositeLift = math.max(0, -math.sin(phase))

	if fast then
		put(pose, "RootJoint", CFrame.new(0, math.abs(math.sin(phase)) * .16, -.18)
			* CFrame.Angles(math.rad(-8), 0, math.rad(stride * 2.5)))
		put(pose, "Waist", CFrame.Angles(math.rad(-15), math.rad(-stride * 8), math.rad(stride * 4)))
		put(pose, "Neck", CFrame.Angles(math.rad(10 - math.abs(stride) * 4), math.rad(stride * 4), 0))
		put(pose, "RightHip", CFrame.new(0, lift * .1, 0) * CFrame.Angles(math.rad(stride * 48), 0, math.rad(2)))
		put(pose, "LeftHip", CFrame.new(0, oppositeLift * .1, 0) * CFrame.Angles(math.rad(-stride * 48), 0, math.rad(-2)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-stride * 62 - 10), 0, math.rad(-5)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(stride * 62 - 10), 0, math.rad(5)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(8 + stride * 9), 0, 0))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(8 - stride * 9), 0, 0))
		fingers(pose, math.rad(28 + math.abs(stride) * 7), math.rad(2))
		return
	end

	local variant = binding.ProcWalkVariant
	if variant == 1 then
		put(pose, "RootJoint", CFrame.new(0, math.abs(stride) * .09, 0)
			* CFrame.Angles(0, math.rad(-stride * 3), math.rad(stride * 2)))
		put(pose, "Waist", CFrame.Angles(math.rad(-4), math.rad(-stride * 7), math.rad(stride * 3)))
		put(pose, "Neck", CFrame.Angles(math.rad(5 - math.abs(stride) * 2), math.rad(stride * 4), 0))
		put(pose, "RightHip", CFrame.Angles(math.rad(stride * 35), 0, 0))
		put(pose, "LeftHip", CFrame.Angles(math.rad(-stride * 35), 0, 0))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-stride * 42), 0, math.rad(-3)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(stride * 42), 0, math.rad(3)))
	elseif variant == 2 then
		local drag = math.sin(phase * .5)
		put(pose, "RootJoint", CFrame.new(-.08, math.abs(stride) * .06, .03)
			* CFrame.Angles(math.rad(-3), math.rad(drag * 3), math.rad(-5)))
		put(pose, "Waist", CFrame.Angles(math.rad(-8), math.rad(-stride * 5), math.rad(-7)))
		put(pose, "Neck", CFrame.Angles(math.rad(13), math.rad(-10 + drag * 5), math.rad(7)))
		put(pose, "RightHip", CFrame.Angles(math.rad(stride * 41), 0, math.rad(4)))
		put(pose, "LeftHip", CFrame.Angles(math.rad(-stride * 19 - 6), 0, math.rad(-7)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-stride * 54), 0, math.rad(-10)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(stride * 18 + 8), 0, math.rad(12)))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(18), 0, math.rad(10)))
	else
		local march = math.sin(phase + math.pi * .18)
		put(pose, "RootJoint", CFrame.new(0, math.abs(stride) * .13, -.04)
			* CFrame.Angles(math.rad(-2), math.rad(stride * 4), math.rad(stride * 5)))
		put(pose, "Waist", CFrame.Angles(math.rad(-6 + math.abs(stride) * 3), math.rad(-stride * 10), math.rad(march * 6)))
		put(pose, "Neck", CFrame.Angles(math.rad(-3 + math.abs(stride) * 5), math.rad(stride * 7), math.rad(-march * 6)))
		put(pose, "RightHip", CFrame.Angles(math.rad(stride * 43), math.rad(3), math.rad(5)))
		put(pose, "LeftHip", CFrame.Angles(math.rad(-stride * 43), math.rad(-3), math.rad(-5)))
		put(pose, "RightShoulder", CFrame.Angles(math.rad(-march * 52), math.rad(-7), math.rad(-8)))
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(march * 52), math.rad(7), math.rad(8)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(10), math.rad(stride * 9), 0))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(10), math.rad(-stride * 9), 0))
	end
	fingers(pose, math.rad(18 + math.abs(stride) * 4), math.rad(stride))
end

local function attackPose(binding, pose, now)
	local stage = binding.Entity:GetAttribute("AttackStage") or "Windup"
	local elapsed = math.max(0, now - (binding.ProcActionStarted or now))
	local variant = binding.ProcAttackVariant or 1
	local windup = math.clamp(elapsed / .72, 0, 1)
	windup = windup * windup * (3 - 2 * windup)
	local recovery = math.clamp((elapsed - .88) / .85, 0, 1)
	local impact = stage == "Impact" or stage == "Miss"
	local recovering = stage == "Recovery" or binding.Entity:GetAttribute("MotionState") == "Recover"

	if variant == 1 then
		local raised = CFrame.Angles(math.rad(-154), math.rad(-7), math.rad(-8))
		local raisedOther = CFrame.Angles(math.rad(-154), math.rad(7), math.rad(8))
		local slammed = CFrame.Angles(math.rad(62), 0, math.rad(-3))
		local slammedOther = CFrame.Angles(math.rad(62), 0, math.rad(3))
		local right = impact and slammed or CFrame.identity:Lerp(raised, windup)
		local left = impact and slammedOther or CFrame.identity:Lerp(raisedOther, windup)
		local waist = impact and CFrame.Angles(math.rad(-31), 0, 0)
			or CFrame.identity:Lerp(CFrame.Angles(math.rad(14), 0, 0), windup)
		if recovering then
			right = slammed:Lerp(CFrame.identity, recovery)
			left = slammedOther:Lerp(CFrame.identity, recovery)
			waist = CFrame.Angles(math.rad(-31), 0, 0):Lerp(CFrame.identity, recovery)
		end
		put(pose, "RightShoulder", right)
		put(pose, "LeftShoulder", left)
		put(pose, "Waist", waist)
		put(pose, "RootJoint", impact and CFrame.new(0, -.18, -.26) or CFrame.new(0, windup * .08, windup * .1))
		put(pose, "Neck", impact and CFrame.Angles(math.rad(21), 0, 0)
			or CFrame.Angles(math.rad(-windup * 12), 0, 0))
		put(pose, "RightWrist", CFrame.Angles(math.rad(impact and 24 or -windup * 18), 0, 0))
		put(pose, "LeftWrist", CFrame.Angles(math.rad(impact and 24 or -windup * 18), 0, 0))
		fingers(pose, math.rad(impact and 57 or (25 + windup * 20)), math.rad(3))
	else
		local wound = CFrame.Angles(math.rad(-28), math.rad(-48), math.rad(-112))
		local strike = CFrame.Angles(math.rad(18), math.rad(72), math.rad(104))
		local right = impact and strike or CFrame.identity:Lerp(wound, windup)
		local waist = impact and CFrame.Angles(math.rad(-12), math.rad(58), math.rad(10))
			or CFrame.identity:Lerp(CFrame.Angles(math.rad(5), math.rad(-38), math.rad(-8)), windup)
		if recovering then
			right = strike:Lerp(CFrame.identity, recovery)
			waist = CFrame.Angles(math.rad(-12), math.rad(58), math.rad(10)):Lerp(CFrame.identity, recovery)
		end
		put(pose, "RightShoulder", right)
		put(pose, "LeftShoulder", CFrame.Angles(math.rad(-12), math.rad(8), math.rad(18)))
		put(pose, "Waist", waist)
		put(pose, "RootJoint", CFrame.Angles(0, math.rad(impact and 20 or -windup * 12), math.rad(impact and 4 or -windup * 3)))
		put(pose, "Neck", CFrame.Angles(math.rad(8), math.rad(impact and -30 or windup * 22), math.rad(-6)))
		put(pose, "RightWrist", CFrame.Angles(math.rad(20), math.rad(impact and 35 or -windup * 20), 0))
		fingers(pose, math.rad(impact and 62 or (28 + windup * 18)), math.rad(5))
	end
end

local function stepProcedural(binding, dt, now)
	if not binding.Active or not binding.ProceduralMotors or not binding.ProceduralActive then
		return
	end
	binding.ProcClock += dt
	local motion = binding.Entity:GetAttribute("MotionState") or "Idle"
	if motion ~= binding.ProcLastMotion then
		if motion == "Walk" then
			binding.ProcWalkVariant = binding.ProcWalkVariant % 3 + 1
		elseif motion == "Idle" then
			binding.ProcIdleVariant = binding.ProcIdleVariant % 5 + 1
			binding.ProcNextIdleVariantAt = now + math.random(5, 8)
		end
		binding.ProcLastMotion = motion
	end
	if motion == "Idle" and now >= binding.ProcNextIdleVariantAt then
		binding.ProcIdleVariant = binding.ProcIdleVariant % 5 + 1
		binding.ProcNextIdleVariantAt = now + math.random(5, 8)
	end

	local pose = {}
	if motion == "Walk" then
		walkPose(binding, pose, binding.ProcClock, false)
	elseif motion == "Chase" or motion == "Burst" then
		walkPose(binding, pose, binding.ProcClock, true)
	elseif motion == "Attack" or motion == "Recover" then
		attackPose(binding, pose, now)
	else
		idlePose(binding, pose, binding.ProcClock)
	end

	local impactAge = now - (binding.ProcImpactAt or -math.huge)
	if impactAge >= 0 and impactAge < .14 then
		local pulse = 1 - impactAge / .14
		local shake = math.sin(impactAge * 115) * pulse
		pose.RootJoint = (pose.RootJoint or CFrame.identity)
			* CFrame.new(shake * .08, -pulse * .08, 0)
			* CFrame.Angles(0, math.rad(shake * 3), math.rad(shake * 2))
		pose.Neck = (pose.Neck or CFrame.identity)
			* CFrame.Angles(math.rad(-pulse * 5), 0, math.rad(shake * 3))
	end

	local responsiveness = (motion == "Attack" or motion == "Recover") and 20
		or ((motion == "Chase" or motion == "Burst") and 15 or 10)
	local alpha = 1 - math.exp(-responsiveness * math.min(dt, .1))
	for name, joint in pairs(binding.ProceduralMotors) do
		local target = pose[name] or CFrame.identity
		joint.Transform = joint.Transform:Lerp(target, alpha)
	end
end

local function unbind(entity)
	local binding = bindings[entity]
	if not binding then return end
	binding.Active = false
	for _, connection in ipairs(binding.Connections) do
		connection:Disconnect()
	end
	stopCurrent(binding, 0.1)
	MeshyPlayer.Unbind(binding.Meshy)
	for _, track in pairs(binding.Tracks) do
		pcall(function() track:Stop(0.1) end)
	end
	if binding.Folder.Parent then
		binding.Folder:Destroy()
	end
	bindings[entity] = nil
end

local function bind(entity)
	if not entity:IsA("Model") or bindings[entity] or not entity:IsDescendantOf(workspace) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "RuntimeEntityAnimations"
	folder.Parent = entity
	local binding = {
		Entity = entity,
		Profile = Profiles.Resolve(entity),
		Animator = animatorFor(entity),
		Folder = folder,
		Tracks = {},
		Connections = {},
		LastChoice = {},
		CurrentTrack = nil,
		CurrentKey = nil,
		CurrentMotion = nil,
		LastActionSerial = tonumber(entity:GetAttribute("ActionSerial")) or 0,
		NextIdleChange = 0,
		ProceduralMotors = nil,
		ProceduralActive = false,
		ProcImpactAt = -math.huge,
		Meshy = nil,
		UsePublishedSlots = false,
		Active = true,
	}
	binding.Meshy = MeshyPlayer.Bind(entity, binding.Profile)
	if not binding.Meshy then
		setupProcedural(binding)
	end
	bindings[entity] = binding
	table.insert(binding.Connections, entity:GetAttributeChangedSignal("MotionState"):Connect(function()
		applyMotion(binding, true)
	end))
	table.insert(binding.Connections, entity:GetAttributeChangedSignal("MoveSpeed"):Connect(function()
		applyMotion(binding, false)
	end))
	table.insert(binding.Connections, entity:GetAttributeChangedSignal("ActionSerial"):Connect(function()
		playAction(binding)
	end))
	table.insert(binding.Connections, entity:GetAttributeChangedSignal("ImpactSerial"):Connect(function()
		binding.ProcImpactAt = os.clock()
	end))
	task.defer(applyMotion, binding, true)

	task.spawn(function()
		while binding.Active and entity.Parent do
			if not binding.Meshy
				and not binding.ProceduralMotors
				and entity:GetAttribute("MotionState") == "Idle"
				and os.clock() >= binding.NextIdleChange then
				applyMotion(binding, true)
			end
			task.wait(0.5)
		end
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, binding in pairs(bindings) do
		if binding.Meshy then
			if not binding.UsePublishedSlots then
				MeshyPlayer.Step(binding.Meshy, math.min(dt, .1))
			end
		else
			stepProcedural(binding, math.min(dt, .1), now)
		end
	end
end)

CollectionService:GetInstanceAddedSignal(TAG):Connect(bind)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unbind)
for _, entity in ipairs(CollectionService:GetTagged(TAG)) do
	bind(entity)
end
