-- R15 clip for the player who pets Luna: kneel on the left knee, stroke her head twice, hold the right hand
-- out palm-up to take her paw (with her little shake), let go and stand up. 4.6 s, timed from her SitDown.
-- Joint C0s on the game's R15 rigs (AnimationConstraints) are axis-aligned, so each pose is a rotation in the
-- parent part's frame: +X swings a hanging limb forward, -X leans the torso / nods the head forward-down.
-- Run inside execute_luau with a harness appended (preview or upload); defines build() -> KeyframeSequence.

local function A(x, y, z)
	return CFrame.Angles(math.rad(x or 0), math.rad(y or 0), math.rad(z or 0))
end
local function T(x, y, z)
	return CFrame.new(x or 0, y or 0, z or 0)
end

local TREE = {
	HumanoidRootPart = {"LowerTorso"},
	LowerTorso = {"UpperTorso", "LeftUpperLeg", "RightUpperLeg"},
	UpperTorso = {"Head", "LeftUpperArm", "RightUpperArm"},
	LeftUpperArm = {"LeftLowerArm"}, LeftLowerArm = {"LeftHand"},
	RightUpperArm = {"RightLowerArm"}, RightLowerArm = {"RightHand"},
	LeftUpperLeg = {"LeftLowerLeg"}, LeftLowerLeg = {"LeftFoot"},
	RightUpperLeg = {"RightLowerLeg"}, RightLowerLeg = {"RightFoot"},
}

local function merge(...)
	local out = {}
	for _, t in ipairs({...}) do
		for k, v in pairs(t) do out[k] = v end
	end
	return out
end

-- kneeling on the left knee, right foot planted forward, leaning in and looking down at her
local KNEEL = {
	LowerTorso = T(0, -1.42, 0.2) * A(-6),
	UpperTorso = A(-20),
	Head = A(-16),
	RightUpperLeg = A(86, 0, 4), RightLowerLeg = A(-90), RightFoot = A(4),
	LeftUpperLeg = A(-2, 0, -3), LeftLowerLeg = A(-92), LeftFoot = A(-20),
	LeftUpperArm = A(28, 0, 6), LeftLowerArm = A(34), LeftHand = A(0),
}
local ARM_REST = {RightUpperArm = A(26, 0, -6), RightLowerArm = A(34), RightHand = A(0)}
local function petArm(swing) -- 0 = hand back on her neck, 1 = forward over her head
	return {
		RightUpperArm = A(62 + 14 * swing, 0, -6),
		RightLowerArm = A(24 - 14 * swing),
		RightHand = A(-28),
	}
end
local function pawArm(bob) -- hand out palm-up under her paw
	return {
		RightUpperArm = A(46 + bob, 0, -10),
		RightLowerArm = A(30 - bob * 0.5),
		RightHand = A(0, -80, 0),
	}
end

local KEYS = {
	{0.00, {}},
	{0.45, merge(KNEEL, petArm(0.6))},
	{0.75, merge(KNEEL, petArm(0))},
	{1.05, merge(KNEEL, petArm(1))},
	{1.35, merge(KNEEL, petArm(0))},
	{1.65, merge(KNEEL, petArm(1))},
	{2.05, merge(KNEEL, pawArm(0))},
	{2.30, merge(KNEEL, pawArm(4))},
	{2.55, merge(KNEEL, pawArm(-3))},
	{2.80, merge(KNEEL, pawArm(4))},
	{3.05, merge(KNEEL, pawArm(0))},
	{3.45, merge(KNEEL, ARM_REST)},
	{3.95, merge(KNEEL, ARM_REST)},
	{4.60, {}},
}

-- Belly rub: the same kneel leaning further in, both hands down on her belly rubbing in turn (she lies on her back
-- in front of the player, head towards them). 5.4 s: reach 0-0.5, eight alternating strokes to 4.5, stand by 5.4.
local LEAN = merge(KNEEL, {UpperTorso = A(-34), Head = A(-24), LowerTorso = T(0, -1.42, 0.2) * A(-10)})
local function rubArms(phase) -- phase in [-1, 1]: +1 right hand forward / left back, -1 the other way
	return {
		RightUpperArm = A(52 + 9 * phase, 0, -8), RightLowerArm = A(26 - 8 * phase), RightHand = A(-34),
		LeftUpperArm = A(52 - 9 * phase, 0, 8), LeftLowerArm = A(26 + 8 * phase), LeftHand = A(-34),
	}
end
local BELLY_KEYS = {{0.00, {}}, {0.50, merge(LEAN, rubArms(0))}}
for i = 1, 8 do
	table.insert(BELLY_KEYS, {0.50 + i * 0.5, merge(LEAN, rubArms(i % 2 == 1 and 1 or -1))})
end
table.insert(BELLY_KEYS, {4.70, merge(LEAN, rubArms(0))})
table.insert(BELLY_KEYS, {5.40, {}})

local function sequence(name, keys)
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = false
	kfs.Priority = Enum.AnimationPriority.Action4
	for _, key in ipairs(keys) do
		local kf = Instance.new("Keyframe")
		kf.Time = key[1]
		local function add(parent, part)
			local pose = Instance.new("Pose")
			pose.Name = part
			pose.CFrame = key[2][part] or CFrame.identity
			pose.EasingStyle = Enum.PoseEasingStyle.Cubic
			pose.EasingDirection = Enum.PoseEasingDirection.InOut
			pose.Weight = 1
			pose.Parent = parent
			for _, child in ipairs(TREE[part] or {}) do add(pose, child) end
		end
		add(kf, "HumanoidRootPart")
		kf.Parent = kfs
	end
	return kfs
end

function buildBelly()
	return sequence("Luna Belly Rub (player R15) v1", BELLY_KEYS)
end

function build()
	return sequence("Luna Pet (player R15) v1", KEYS)
end
