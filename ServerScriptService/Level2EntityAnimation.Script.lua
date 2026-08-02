-- Drives the same Meshy walk cycle at a faster playback rate while chasing.

local ENTITY_NAME = "PoolFoamEntity"

local function bindEntity(entity)
	local controller = entity:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", entity)
	local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator", controller)
	local animationId = entity:GetAttribute("WalkAnimationId")
	if type(animationId) ~= "string" or animationId == "" then
		warn("[Level2EntityAnimation] Pool Foam walk animation ID is missing")
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = "PoolFoamWalk"
	animation.AnimationId = animationId
	animation.Parent = entity
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not track then
		warn("[Level2EntityAnimation] Could not load walk animation", track)
		return
	end
	track.Name = "PoolFoamWalkTrack"
	track.Looped = true
	track.Priority = Enum.AnimationPriority.Movement

	local running = true
	entity.AncestryChanged:Connect(function(_, parent)
		if not parent then running = false; pcall(function() track:Stop(.15) end) end
	end)

	task.spawn(function()
		while running and entity.Parent do
			local state = entity:GetAttribute("MotionState")
			if state == "Walk" or state == "Chase" then
				if not track.IsPlaying then track:Play(.18, 1, 1) end
				track:AdjustSpeed(state == "Chase" and 1.65 or .9)
			elseif track.IsPlaying then
				track:Stop(.2)
			end
			task.wait(.12)
		end
	end)
end

local function consider(object)
	if object.Name == ENTITY_NAME and object:IsA("Model") then task.defer(bindEntity, object) end
end

workspace.ChildAdded:Connect(consider)
local existing = workspace:FindFirstChild(ENTITY_NAME)
if existing then consider(existing) end

