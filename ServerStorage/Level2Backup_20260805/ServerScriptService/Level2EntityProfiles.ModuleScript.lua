--!strict
-- Central tuning and attribute overrides for every Level 2 hostile entity.
local Profiles = {}

Profiles.TagName = "Level2HostileEntity"

local DEFAULT = {
	Name = "Default",
	WanderSpeed = 6.5,
	ChaseSpeed = 17.5,
	BlackoutBurstSpeed = 0,
	BlackoutOnlyAggro = false,
	BurstStopDistance = 34,
	SightRange = 105,
	HearingRange = 42,
	GiveUpRange = 155,
	LastSeenSeconds = 6,
	WanderRadiusMin = 22,
	WanderRadiusMax = 68,
	WanderPauseMin = 0.65,
	WanderPauseMax = 2.1,
	PathRefreshWander = 4.25,
	PathRefreshChase = 0.72,
	WaypointReach = 2.2,
	AgentRadius = 2.4,
	AgentHeight = 9,
	WaypointSpacing = 6,
	MaxFloorDelta = 3.1,
	MaxWaterDepth = 1.65,
	MaxStepHeight = 2.25,
	MoveClearance = 0.35,
	StuckSeconds = 1.15,
	StuckDistance = 0.75,
	AttackRange = 5.4,
	AttackHitRange = 6.1,
	AttackConeDegrees = 105,
	AttackWindup = 0.48,
	AttackRecovery = 0.72,
	AttackCooldown = 1.45,
	AttackDamage = math.huge,
	ReferenceWalkSpeed = 7.5,
	ReferenceRunSpeed = 18,
}

local DEFINITIONS = {
	PoolPipe = {
		Name = "PoolPipe",
		WanderSpeed = 5.4,
		ChaseSpeed = 18.75,
		BlackoutBurstSpeed = 44,
		-- It stalks/chases visible players under normal lighting; blackout still
		-- unlocks the much faster unseen burst phase.
		BlackoutOnlyAggro = false,
		BurstStopDistance = 38,
		SightRange = 132,
		HearingRange = 58,
		GiveUpRange = 205,
		LastSeenSeconds = 8.5,
		WanderRadiusMin = 32,
		WanderRadiusMax = 86,
		PathRefreshWander = 3.6,
		PathRefreshChase = 0.5,
		AgentRadius = 3,
		AgentHeight = 13,
		WaypointSpacing = 5,
		MaxFloorDelta = 3.6,
		MaxWaterDepth = 1.8,
		MaxStepHeight = 2.6,
		StuckSeconds = 0.9,
		AttackRange = 8.2,
		AttackHitRange = 9.1,
		AttackConeDegrees = 92,
		AttackWindup = 0.78,
		AttackRecovery = 0.95,
		AttackCooldown = 1.9,
		ReferenceWalkSpeed = 5.4,
		ReferenceRunSpeed = 18.75,
	},
}

local OVERRIDABLE = {
	"WanderSpeed", "ChaseSpeed", "BlackoutBurstSpeed", "BurstStopDistance",
	"SightRange", "HearingRange", "GiveUpRange", "LastSeenSeconds",
	"WanderRadiusMin", "WanderRadiusMax", "WanderPauseMin", "WanderPauseMax",
	"PathRefreshWander", "PathRefreshChase", "WaypointReach",
	"AgentRadius", "AgentHeight", "WaypointSpacing",
	"MaxFloorDelta", "MaxWaterDepth", "MaxStepHeight", "MoveClearance",
	"StuckSeconds", "StuckDistance", "AttackRange", "AttackHitRange",
	"AttackConeDegrees", "AttackWindup", "AttackRecovery", "AttackCooldown",
	"AttackDamage", "ReferenceWalkSpeed", "ReferenceRunSpeed",
}

local function copyInto(target, source)
	for key, value in pairs(source) do
		target[key] = value
	end
end

function Profiles.InferName(entity: Instance): string
	local explicit = entity:GetAttribute("EntityProfile")
	if type(explicit) == "string" and DEFINITIONS[explicit] then
		return explicit
	end
	local lowered = string.lower(entity.Name)
	if string.find(lowered, "pipe", 1, true) then
		return "PoolPipe"
	end
	return "PoolPipe"
end

function Profiles.Resolve(entity: Instance)
	local resolved = {}
	copyInto(resolved, DEFAULT)
	copyInto(resolved, DEFINITIONS[Profiles.InferName(entity)] or DEFINITIONS.PoolPipe)

	for _, key in ipairs(OVERRIDABLE) do
		local value = entity:GetAttribute(key)
		if value ~= nil and typeof(value) == typeof(resolved[key]) then
			resolved[key] = value
		end
	end

	local blackoutOverride = entity:GetAttribute("BlackoutOnlyAggro")
	if type(blackoutOverride) == "boolean" then
		resolved.BlackoutOnlyAggro = blackoutOverride
	end
	return resolved
end

function Profiles.AnimationCandidates(entity: Instance, motionState: string): {string}
	local keys
	local slotNames
	if motionState == "Idle" then
		keys = {"IdleAnimationId1", "IdleAnimationId2", "IdleAnimationId3", "IdleAnimationId4", "IdleAnimationId5"}
		slotNames = {"Idle_1", "Idle_2", "Idle_3", "Idle_4", "Idle_5"}
	elseif motionState == "Walk" then
		keys = {"WalkAnimationId1", "WalkAnimationId2", "WalkAnimationId3", "WalkAnimationId"}
		slotNames = {"Walk_1", "Walk_2", "Walk_3"}
	elseif motionState == "Chase" or motionState == "Burst" then
		keys = {"RunAnimationId", "WalkAnimationId"}
		slotNames = {"Run"}
	elseif motionState == "Attack" then
		keys = {"AttackAnimationId1", "AttackAnimationId2", "AttackAnimationId"}
		slotNames = {"Attack_1", "Attack_2"}
	else
		keys = {}
		slotNames = {}
	end

	local ids = {}
	local seen = {}
	local function addId(id)
		if type(id) == "number" then
			id = "rbxassetid://" .. tostring(math.floor(id))
		elseif type(id) == "string" and string.match(id, "^%d+$") then
			id = "rbxassetid://" .. id
		end
		if type(id) == "string" and id ~= "" and id ~= "rbxassetid://" and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end

	-- Legacy attributes remain supported.
	for _, key in ipairs(keys) do
		addId(entity:GetAttribute(key))
	end

	-- User-facing slots live directly under the entity template.  These are
	-- normal Animation instances, making IDs easy to paste in Studio Properties.
	local slots = entity:FindFirstChild("PoolPipeAnimationIDs")
	if slots then
		for _, slotName in ipairs(slotNames) do
			local slot = slots:FindFirstChild(slotName)
			if slot and slot:IsA("Animation") then
				addId(slot.AnimationId)
			end
		end
	end
	return ids
end

return Profiles
