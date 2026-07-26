local RunService = game:GetService("RunService")

-- ══ ANIMATION IDS — paste yours here (just the number, no "rbxassetid://") ══
local WALK_ANIM_ID  = "74979742062849"   -- plays while the Entity walks / roams
local RUN_ANIM_ID   = "138859570115399"  -- plays while the Entity runs (chasing)
local YELL_ANIM_ID  = "117128353689729"  -- one-shot roar when it shoves a pit player ("" = none)
local LUNGE_ANIM_ID = ""                 -- one-shot pounce as it winds up a lunge ("" = none)
-- ═══════════════════════════════════════════════════════════════════════════

print("[EntityAnimations] Script started")

local entity = workspace:WaitForChild("Entity", 30)

if not entity then
	warn("[EntityAnimations] FEJL: Entity blev ikke fundet i Workspace")
	return
end

print("[EntityAnimations] Entity found:", entity:GetFullName())

local humanoid = entity:WaitForChild("Humanoid", 10)
local root = entity:WaitForChild("HumanoidRootPart", 10)

if not humanoid then
	warn("[EntityAnimations] FEJL: Humanoid blev ikke fundet")
	return
end

if not root then
	warn("[EntityAnimations] FEJL: HumanoidRootPart blev ikke fundet")
	return
end

print("[EntityAnimations] Humanoid found")
print("[EntityAnimations] HumanoidRootPart found")

local animator = humanoid:FindFirstChildOfClass("Animator")

if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
	print("[EntityAnimations] New Animator created")
else
	print("[EntityAnimations] Existing Animator found")
end

for _, oldTrack in ipairs(animator:GetPlayingAnimationTracks()) do
	print("[EntityAnimations] Stopping old track:", oldTrack.Name)
	oldTrack:Stop(0)
end

local function loadAnimation(name, id)
	print("[EntityAnimations] Loading", name, "ID:", id)

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = "rbxassetid://" .. id
	animation.Parent = script

	local success, result = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success then
		warn("[EntityAnimations] LOAD ERROR for", name, ":", result)
		return nil
	end

	result.Looped = true
	result.Priority = Enum.AnimationPriority.Action

	print("[EntityAnimations]", name, "track created")

	return result
end

local walkTrack = loadAnimation("ExplorerWalk", WALK_ANIM_ID)
local runTrack = loadAnimation("ExplorerRun", RUN_ANIM_ID)

-- ── yell (a one-shot roar EntityAI triggers when it shoves a pit player) ──
-- YELL_ANIM_ID is set in the config block at the top. "" = no anim, just the push.
local yellTrack
if YELL_ANIM_ID ~= "" then
	yellTrack = loadAnimation("EntityYell", YELL_ANIM_ID)
	if yellTrack then
		yellTrack.Looped = false                        -- play once
		yellTrack.Priority = Enum.AnimationPriority.Action4 -- overrides walk/run
	end
end

-- EntityAI fires this BindableEvent to make the entity play its yell. Parented
-- to the Entity so EntityAI can find it with entity:FindFirstChild("PlayYell").
local playYell = Instance.new("BindableEvent")
playYell.Name = "PlayYell"
playYell.Parent = entity
playYell.Event:Connect(function()
	if yellTrack then
		yellTrack:Play(0.1)
	else
		print("[EntityAnimations] PlayYell fired but YELL_ANIM_ID is empty")
	end
end)

-- ── lunge (one-shot pounce prep; EntityAI bumps the EntityLunge attribute at
-- the start of its wind-up, and we play the animation off that) ──
local lungeTrack
if LUNGE_ANIM_ID ~= "" then
	lungeTrack = loadAnimation("EntityLunge", LUNGE_ANIM_ID)
	if lungeTrack then
		lungeTrack.Looped = false                         -- play once
		lungeTrack.Priority = Enum.AnimationPriority.Action4 -- overrides walk/run
	end
end
workspace:GetAttributeChangedSignal("EntityLunge"):Connect(function()
	if lungeTrack then lungeTrack:Play(0.1) end
end)

if not walkTrack or not runTrack then
	warn("[EntityAnimations] FEJL: En eller flere tracks kunne ikke indlæses")
	return
end

task.wait(3)

print("========== ANIMATION LOAD REPORT ==========")
print("[EntityAnimations] Walk Length:", walkTrack.Length)
print("[EntityAnimations] Run Length:", runTrack.Length)

local boneCount = 0

for _, object in ipairs(entity:GetDescendants()) do
	if object:IsA("Bone") then
		boneCount += 1
	end
end

print("[EntityAnimations] Bone count:", boneCount)
print("===========================================")

if walkTrack.Length == 0 then
	warn("[EntityAnimations] WALK LENGTH IS 0")
end

if runTrack.Length == 0 then
	warn("[EntityAnimations] RUN LENGTH IS 0")
end

local currentState = "None"

local function switchState(newState)
	if newState == currentState then
		return
	end

	print(
		"[EntityAnimations] STATE CHANGE:",
		currentState,
		"→",
		newState,
		"| WalkSpeed:",
		humanoid.WalkSpeed
	)

	currentState = newState

	if newState == "Idle" then
		walkTrack:Stop(0.15)
		runTrack:Stop(0.15)

	elseif newState == "Walk" then
		runTrack:Stop(0.1)

		if not walkTrack.IsPlaying then
			walkTrack:Play(0.15)
			print("[EntityAnimations] WALK started")
		end

	elseif newState == "Run" then
		walkTrack:Stop(0.1)

		if not runTrack.IsPlaying then
			runTrack:Play(0.1)
			print("[EntityAnimations] RUN started")
		end
	end
end

local lastDiagnostic = 0

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		switchState("Idle")
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(
		velocity.X,
		0,
		velocity.Z
	).Magnitude

	if horizontalSpeed < 0.3 then
		switchState("Idle")
	elseif humanoid.WalkSpeed >= 20 then
		switchState("Run")
	else
		switchState("Walk")
	end

	if os.clock() - lastDiagnostic >= 2 then
		lastDiagnostic = os.clock()

		print(
			"[EntityAnimations] DIAGNOSTIC | State:",
			currentState,
			"| Horizontal speed:",
			math.round(horizontalSpeed * 10) / 10,
			"| WalkSpeed:",
			humanoid.WalkSpeed,
			"| Walk playing:",
			walkTrack.IsPlaying,
			"| Run playing:",
			runTrack.IsPlaying,
			"| Walk length:",
			walkTrack.Length,
			"| Run length:",
			runTrack.Length
		)
	end
end)

print("[EntityAnimations] Heartbeat connection active")