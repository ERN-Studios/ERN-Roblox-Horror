local RunService = game:GetService("RunService")

-- Blender action mapping. Empty slots are safe: the controller falls back to a
-- compatible clip until the exported action has received its Roblox asset id.
local ANIMATION_IDS = {
	Watch = "",                    -- Blender: Watch (idle loop)
	Walk = "74979742062849",       -- Blender: Walk
	Run = "138859570115399",       -- Blender: Run_Chase
	Howl = "117128353689729",      -- Blender: Yell_Howl (first sight)
	YellFromRun = "",              -- Blender: Yell_FromRun (pit yell)
	Lunge = "",                   -- Blender: Lunge (fallback)
	LungeFromRun = "",            -- Blender: Lunge_FromRun (normal chase lunge)
}

local WALK_ANIM_SPEED = 9
local RUN_ANIM_SPEED = 15
local ANIM_SPEED_MIN = 0.6
local ANIM_SPEED_MAX = 2.5
local LOCOMOTION_FADE = 0.2
local ACTION_FADE = 0.12

local entity = workspace:WaitForChild("Entity", 30)
if not entity then
	warn("[EntityAnimations] Entity was not found")
	return
end

local humanoid = entity:WaitForChild("Humanoid", 10)
local root = entity:WaitForChild("HumanoidRootPart", 10)
if not humanoid or not root then
	warn("[EntityAnimations] Humanoid or HumanoidRootPart was not found")
	return
end

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

for _, oldTrack in ipairs(animator:GetPlayingAnimationTracks()) do
	oldTrack:Stop(0)
end

local function loadTrack(name, id, looped, priority)
	if id == "" then return nil end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = "rbxassetid://" .. id
	animation.Parent = script
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if not ok then
		warn("[EntityAnimations] Could not load " .. name .. ": " .. tostring(track))
		return nil
	end
	track.Name = name
	track.Looped = looped
	track.Priority = priority
	return track
end

local tracks = {
	Watch = loadTrack("Watch", ANIMATION_IDS.Watch, true, Enum.AnimationPriority.Idle),
	Walk = loadTrack("Walk", ANIMATION_IDS.Walk, true, Enum.AnimationPriority.Movement),
	Run = loadTrack("Run_Chase", ANIMATION_IDS.Run, true, Enum.AnimationPriority.Movement),
	Howl = loadTrack("Yell_Howl", ANIMATION_IDS.Howl, false, Enum.AnimationPriority.Action4),
	YellFromRun = loadTrack("Yell_FromRun", ANIMATION_IDS.YellFromRun, false, Enum.AnimationPriority.Action4),
	Lunge = loadTrack("Lunge", ANIMATION_IDS.Lunge, false, Enum.AnimationPriority.Action4),
	LungeFromRun = loadTrack("Lunge_FromRun", ANIMATION_IDS.LungeFromRun, false, Enum.AnimationPriority.Action4),
}

if not tracks.Walk or not tracks.Run then
	warn("[EntityAnimations] Walk/Run ids must be valid for locomotion")
	return
end

local currentLocomotion = nil
local currentAction = nil

local function stopLocomotion(fade)
	for _, name in ipairs({ "Watch", "Walk", "Run" }) do
		local track = tracks[name]
		if track and track.IsPlaying then track:Stop(fade) end
	end
	currentLocomotion = nil
end

local function switchLocomotion(name)
	if currentLocomotion == name then return end
	for _, other in ipairs({ "Watch", "Walk", "Run" }) do
		if other ~= name then
			local track = tracks[other]
			if track and track.IsPlaying then track:Stop(LOCOMOTION_FADE) end
		end
	end
	currentLocomotion = name
	local track = tracks[name]
	if track and not track.IsPlaying then track:Play(LOCOMOTION_FADE) end
end

local function playAction(track)
	if not track then return end
	if currentAction and currentAction ~= track and currentAction.IsPlaying then
		currentAction:Stop(ACTION_FADE)
	end
	stopLocomotion(ACTION_FADE)
	currentAction = track
	track:Play(ACTION_FADE, 1, 1)
	local thisTrack = track
	task.spawn(function()
		thisTrack.Ended:Wait()
		if currentAction == thisTrack then currentAction = nil end
	end)
end

local function bindEvent(name, callback)
	local old = entity:FindFirstChild(name)
	if old and old:IsA("BindableEvent") then old:Destroy() end
	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = entity
	event.Event:Connect(callback)
	return event
end

bindEvent("PlayHowl", function()
	playAction(tracks.Howl)
end)

bindEvent("PlayYell", function()
	playAction(tracks.YellFromRun or tracks.Howl)
end)

workspace:GetAttributeChangedSignal("EntityLunge"):Connect(function()
	playAction(tracks.LungeFromRun or tracks.Lunge)
end)

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		stopLocomotion(0.15)
		return
	end
	if currentAction and currentAction.IsPlaying then return end
	if currentAction then currentAction = nil end

	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local aiState = workspace:GetAttribute("EntityState")

	if horizontalSpeed < 0.3 then
		switchLocomotion("Watch")
	elseif aiState == "CHASE" then
		switchLocomotion("Run")
		tracks.Run:AdjustSpeed(math.clamp(horizontalSpeed / RUN_ANIM_SPEED, ANIM_SPEED_MIN, ANIM_SPEED_MAX))
	else
		-- TRACK/SEARCH is intentionally a fast walk after sight is lost.
		switchLocomotion("Walk")
		tracks.Walk:AdjustSpeed(math.clamp(horizontalSpeed / WALK_ANIM_SPEED, ANIM_SPEED_MIN, ANIM_SPEED_MAX))
	end
end)

print("[EntityAnimations] Transition controller active")
