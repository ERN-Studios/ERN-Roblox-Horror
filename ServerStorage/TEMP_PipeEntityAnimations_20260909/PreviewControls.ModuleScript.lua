-- Task-only Edit authoring helper. Public Sample, PlayFor, Stop; no camera changes.
-- Native Animator on the approved task model only. Never include this in release.
local Preview = {}
local RunService = game:GetService("RunService")
local MODEL_NAME = "PipeEntity_Final_20260909"
local FOLDER_NAME = "TEMP_PipeEntityAnimations_20260909"
local OWNER = "level2-entity-2026-09-09"
local TRACK_PREFIX = "TEMP_PipeNative_"

local function context()
	assert(not RunService:IsRunning(), "preview is Edit-only")
	local model = assert(workspace:FindFirstChild(MODEL_NAME), "approved task model missing")
	local folder = assert(game:GetService("ServerStorage"):FindFirstChild(FOLDER_NAME), "authoring folder missing")
	assert(folder:GetAttribute("AuthoringOwner") == OWNER and not folder:GetAttribute("Superseded"), "wrong/stale authoring folder")
	assert(math.abs(model:GetScale() - folder:GetAttribute("NormalizedModelScale")) < 1e-5, "model scale changed; rebuild sequences")
	return model, folder
end

local function stopOwned(model)
	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			assert(track.Name:sub(1, #TRACK_PREFIX) == TRACK_PREFIX, "non-preview animation active; refusing to overwrite")
			track:Stop(0)
			track:Destroy()
		end
		animator:StepAnimations(0)
	end
	for _, object in ipairs(model:GetDescendants()) do
		if object:IsA("Bone") then object.Transform = CFrame.identity end
	end
	local objects = model:FindFirstChild("TEMP_NativePreviewObjects")
	if objects then
		assert(objects:GetAttribute("AuthoringOwner") == OWNER, "foreign preview folder")
		objects:Destroy()
	end
	return animator
end

local function start(name, time)
	local model, folder = context()
	assert(name == "Idle" or name == "Walk" or name == "Run" or name == "Attack", "unknown preview clip")
	local sequence = assert(folder:FindFirstChild(name), "clip not authored")
	assert(sequence:IsA("KeyframeSequence"), "expected native sequence")
	local animator = stopOwned(model)
	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "Animator"
		animator:SetAttribute("Level2NativePreviewOwned", true)
		animator.Parent = assert(model:FindFirstChildOfClass("AnimationController"))
	end
	local objects = Instance.new("Folder")
	objects.Name = "TEMP_NativePreviewObjects"
	objects:SetAttribute("AuthoringOwner", OWNER)
	objects.Parent = model
	local animation = Instance.new("Animation")
	animation.Name, animation.Parent = TRACK_PREFIX .. name, objects
	local track
	local ok, problem = xpcall(function()
		animation.AnimationId = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(sequence)
		track = animator:LoadAnimation(animation)
		track.Name, track.Looped, track.Priority = TRACK_PREFIX .. name, sequence.Loop, sequence.Priority
		local deadline = os.clock() + 3
		while track.Length == 0 and os.clock() < deadline do task.wait(0.05) end
		assert(track.Length > 0, "temporary native clip failed to load")
		assert(type(time) == "number" and time == time and time >= 0 and time <= track.Length, "sample time outside clip")
		track:Play(0, 1, 0)
		track.TimePosition = time
		animator:StepAnimations(0.001)
	end, debug.traceback)
	if not ok then
		if track then pcall(function() track:Stop(0); track:Destroy() end) end
		stopOwned(model)
		error(problem)
	end
	return model, animator, track
end

function Preview.Sample(name, time)
	local _, _, track = start(name, time or 0)
	return {Clip = name, Time = track.TimePosition, Length = track.Length, Paused = true, Published = false}
end

function Preview.PlayFor(name, seconds)
	assert(type(seconds) == "number" and seconds == seconds and seconds > 0 and seconds <= 10, "preview duration must be 0–10 seconds")
	local model, animator, track = start(name, 0)
	local ok, problem = xpcall(function()
		track:AdjustSpeed(1)
		local elapsed = 0
		while elapsed < seconds and model.Parent == workspace and track.IsPlaying do
			local dt = RunService.Heartbeat:Wait()
			animator:StepAnimations(dt)
			elapsed += dt
		end
		track:AdjustSpeed(0)
	end, debug.traceback)
	if not ok then stopOwned(model); error(problem) end
	return {Clip = name, Time = track.TimePosition, Length = track.Length, Paused = true, Published = false}
end

function Preview.Stop()
	local model = context()
	local animator = stopOwned(model)
	if animator and animator:GetAttribute("Level2NativePreviewOwned") == true then animator:Destroy() end
	return {Stopped = true, RestoredBoneTransforms = true, Model = model.Name}
end

return Preview
