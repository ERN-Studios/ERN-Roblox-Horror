-- Plays the exact KeyframeSequences imported from the Meshy FBX files on the
-- skinned Pool Pipe Entity. This intentionally does not depend on uploaded
-- AnimationId placeholders: the imported bone transforms ship with the place.
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local Player = {}

local CLIPS = {
	Idle = {"idle_primary", "idle_secondary", "idle_restless", "idle_breathing", "idle_ominous"},
	Walk = {"walk_monster", "walk_slow_heavy", "walk_unsteady"},
	Run = {"run_fast"},
	Attack = {"attack_downward_slam", "attack_heavy_swing"},
}

local compiled = {}

local function sequenceFor(sourceName)
	local saves = ServerStorage:FindFirstChild("RBX_ANIMSAVES")
	local holder = saves and saves:FindFirstChild(sourceName)
	if not holder then return nil end
	return holder:FindFirstChildWhichIsA("KeyframeSequence", true)
end

local function compile(sourceName)
	if compiled[sourceName] then return compiled[sourceName] end
	local sequence = sequenceFor(sourceName)
	if not sequence then
		warn("[Level2MeshyAnimationPlayer] Missing imported sequence", sourceName)
		return nil
	end

	local frames = sequence:GetKeyframes()
	table.sort(frames, function(a, b) return a.Time < b.Time end)
	local packed = {}
	for _, keyframe in ipairs(frames) do
		local poses = {}
		for _, object in ipairs(keyframe:GetDescendants()) do
			if object:IsA("Pose") then
				poses[object.Name] = {
					CFrame = object.CFrame,
					Style = object.EasingStyle,
					Direction = object.EasingDirection,
				}
			end
		end
		table.insert(packed, {Time = keyframe.Time, Poses = poses})
	end
	if #packed == 0 then return nil end

	local clip = {
		Name = sourceName,
		Frames = packed,
		Duration = math.max(packed[#packed].Time, 1 / 30),
	}
	compiled[sourceName] = clip
	return clip
end

local function capturePose(state)
	local pose = {}
	for name, bone in pairs(state.Bones) do
		pose[name] = bone.Transform
	end
	return pose
end

local function choose(state, kind, forcedIndex)
	local candidates = CLIPS[kind]
	if not candidates or #candidates == 0 then return nil end
	if forcedIndex then
		return candidates[(forcedIndex - 1) % #candidates + 1]
	end
	if #candidates == 1 then return candidates[1] end
	local index = math.random(1, #candidates)
	if candidates[index] == state.LastChoice[kind] then
		index = index % #candidates + 1
	end
	state.LastChoice[kind] = candidates[index]
	return candidates[index]
end

local function speedFor(state, kind)
	local entity = state.Entity
	local speed = tonumber(entity:GetAttribute("MoveSpeed"))
	if kind == "Walk" then
		return math.clamp(
			(speed or state.Profile.WanderSpeed) / state.Profile.ReferenceWalkSpeed,
			0.35,
			2.4
		)
	elseif kind == "Run" then
		return math.clamp(
			(speed or state.Profile.ChaseSpeed) / state.Profile.ReferenceRunSpeed,
			0.5,
			2.8
		)
	end
	return 1
end

local function startClip(state, kind, sourceName, looped)
	local clip = compile(sourceName)
	if not clip then return false end
	state.Clip = clip
	state.Kind = kind
	state.Clock = 0
	state.FrameIndex = 1
	state.Looped = looped
	state.Speed = speedFor(state, kind)
	state.BlendFrom = capturePose(state)
	state.BlendClock = 0
	state.BlendDuration = kind == "Attack" and 0.08 or 0.16
	state.Entity:SetAttribute("MeshyActiveClip", sourceName)
	state.Entity:SetAttribute("MeshyActiveClipFrames", #clip.Frames)
	state.Entity:SetAttribute("MeshyActiveClipDuration", clip.Duration)
	if kind == "Idle" then
		state.NextVariantAt = os.clock() + math.random(5, 11)
	end
	return true
end

local function scaledCFrame(value, scale)
	return CFrame.new(value.Position * scale) * (value - value.Position)
end

local function sample(state)
	local clip = state.Clip
	if not clip then return nil end
	local time = state.Clock
	local frames = clip.Frames
	local index = state.FrameIndex
	if time < frames[index].Time then index = 1 end
	while index < #frames and frames[index + 1].Time <= time do
		index += 1
	end
	state.FrameIndex = index

	local from = frames[index]
	local to = frames[math.min(index + 1, #frames)]
	local span = math.max(to.Time - from.Time, 1 / 1000)
	local alpha = math.clamp((time - from.Time) / span, 0, 1)
	local targets = {}
	for name in pairs(state.Bones) do
		local a = from.Poses[name]
		local b = to.Poses[name] or a
		if a then
			local eased = alpha
			local ok, value = pcall(
				TweenService.GetValue,
				TweenService,
				alpha,
				a.Style,
				a.Direction
			)
			if ok then eased = value end
			local fromCFrame = scaledCFrame(a.CFrame, state.TranslationScale)
			local toCFrame = b and scaledCFrame(b.CFrame, state.TranslationScale) or fromCFrame
			targets[name] = fromCFrame:Lerp(toCFrame, eased)
		else
			targets[name] = CFrame.identity
		end
	end
	return targets
end

local function emphasizeLocomotion(state, targets)
	if state.Kind ~= "Walk" and state.Kind ~= "Run" then return end
	local running = state.Kind == "Run"
	local cadence = running and 9.2 or 5.6
	local stride = math.sin(state.Clock * cadence)
	local counterStride = -stride
	local legAngle = math.rad((running and 31 or 19) * stride)
	local armAngle = math.rad((running and 25 or 15) * counterStride)
	local kneeLift = math.rad((running and 19 or 11) * math.max(0, -stride))
	local oppositeKnee = math.rad((running and 19 or 11) * math.max(0, stride))
	local bob = math.abs(math.sin(state.Clock * cadence)) * (running and 0.11 or 0.055) * state.TranslationScale

	local function add(name, value)
		if state.Bones[name] then
			targets[name] = (targets[name] or CFrame.identity) * value
		end
	end
	add("LeftUpLeg", CFrame.Angles(legAngle, 0, 0))
	add("RightUpLeg", CFrame.Angles(-legAngle, 0, 0))
	add("LeftLeg", CFrame.Angles(kneeLift, 0, 0))
	add("RightLeg", CFrame.Angles(oppositeKnee, 0, 0))
	add("LeftArm", CFrame.Angles(armAngle, 0, math.rad(running and -4 or -2)))
	add("RightArm", CFrame.Angles(-armAngle, 0, math.rad(running and 4 or 2)))
	add("Hips", CFrame.new(0, bob, 0) * CFrame.Angles(0, 0, math.rad(stride * (running and 2.8 or 1.6))))
end

function Player.Bind(entity, profile)
	if entity:GetAttribute("MeshyRig") ~= true then return nil end
	local bones = {}
	for _, object in ipairs(entity:GetDescendants()) do
		if object:IsA("Bone") then bones[object.Name] = object end
	end
	local count = 0
	for _ in pairs(bones) do count += 1 end
	if count < 10 then
		warn("[Level2MeshyAnimationPlayer] Refusing non-skinned rig", entity:GetFullName(), count)
		return nil
	end
	local state = {
		Entity = entity,
		Profile = profile,
		Bones = bones,
		BoneCount = count,
		TranslationScale = entity:GetScale(),
		LastChoice = {},
		Clip = nil,
		Kind = nil,
		Clock = 0,
		FrameIndex = 1,
		Looped = true,
		Speed = 1,
		BlendFrom = nil,
		BlendClock = 0,
		BlendDuration = 0.16,
		NextVariantAt = 0,
		PoseSerial = 0,
		NextDiagnosticAt = 0,
		Active = true,
	}
	entity:SetAttribute("MeshyAnimationDriver", "ImportedBoneKeyframes")
	entity:SetAttribute("MeshyRuntimeBoneCount", count)
	return state
end

function Player.SetMotion(state, motion, force)
	if not state or not state.Active then return end
	local kind = motion == "Walk" and "Walk"
		or ((motion == "Chase" or motion == "Burst") and "Run" or "Idle")
	if not force and state.Kind == kind and state.Clip then
		state.Speed = speedFor(state, kind)
		return
	end
	startClip(state, kind, choose(state, kind), true)
end

function Player.PlayAction(state, serial)
	if not state or not state.Active then return end
	local candidates = CLIPS.Attack
	local index = (tonumber(serial) or 0) % #candidates + 1
	startClip(state, "Attack", choose(state, "Attack", index), false)
end

function Player.Step(state, dt)
	if not state or not state.Active then return end
	local motion = state.Entity:GetAttribute("MotionState") or "Idle"
	local desiredKind = motion == "Walk" and "Walk"
		or ((motion == "Chase" or motion == "Burst") and "Run" or "Idle")
	if not state.Clip or (state.Kind ~= "Attack" and state.Kind ~= desiredKind) then
		startClip(state, desiredKind, choose(state, desiredKind), true)
	end
	if not state.Clip then return end
	dt = math.min(dt, 0.1)
	state.Speed = speedFor(state, state.Kind)
	state.Clock += dt * state.Speed
	state.BlendClock += dt

	local duration = state.Clip.Duration
	if state.Clock >= duration then
		if state.Looped then
			state.Clock %= duration
			state.FrameIndex = 1
		else
			state.Clock = duration
		end
	end
	if state.Kind == "Idle" and os.clock() >= state.NextVariantAt then
		startClip(state, "Idle", choose(state, "Idle"), true)
	end

	local targets = sample(state)
	if not targets then return end
	emphasizeLocomotion(state, targets)
	local blend = state.BlendDuration > 0
		and math.clamp(state.BlendClock / state.BlendDuration, 0, 1)
		or 1
	blend = blend * blend * (3 - 2 * blend)
	for name, bone in pairs(state.Bones) do
		local target = targets[name] or CFrame.identity
		local origin = state.BlendFrom and state.BlendFrom[name] or CFrame.identity
		bone.Transform = blend < 1 and origin:Lerp(target, blend) or target
	end
	state.PoseSerial += 1
	if os.clock() >= state.NextDiagnosticAt then
		state.NextDiagnosticAt = os.clock() + 0.5
		state.Entity:SetAttribute("MeshyPoseSerial", state.PoseSerial)
		state.Entity:SetAttribute("MeshyAnimationHealthy", true)
	end
end

function Player.Unbind(state)
	if not state then return end
	state.Active = false
	for _, bone in pairs(state.Bones) do bone.Transform = CFrame.identity end
end

return Player
