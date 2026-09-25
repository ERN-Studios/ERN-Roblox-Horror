-- Local Studio QA only. Uses temporary animation IDs; uploads NOTHING.
-- Compares both candidate Pose trees against actual Bone.Transform outputs from
-- Animator:StepAnimations. Original pose is restored, even after a failed test.
-- Requires the explicitly tagged transient WWImport model already in Workspace.
local H = game:GetService("HttpService")
local RS = game:GetService("RunService")
local KSP = game:GetService("KeyframeSequenceProvider")
assert(RS:IsStudio() and not RS:IsRunning(), "Run this preview test in Studio Edit mode")
local importer = assert(_G.WWImport, "Exact import helper missing")
local model = assert(importer.getModel(), "Build the transient preview first")
assert(model:GetAttribute("TemporaryStudioPreview") == true, "Refusing to alter a production model")
assert(model:IsDescendantOf(workspace), "Animator preview requires model in Workspace")
local part = assert(model.PrimaryPart, "Primary mesh missing")
local controller = assert(model:FindFirstChildOfClass("AnimationController"), "AnimationController missing")
local animator = assert(controller:FindFirstChildOfClass("Animator"), "Animator missing")
assert(#animator:GetPlayingAnimationTracks() == 0, "Existing tracks must be stopped by their owner before this isolated test")

local base = "http://127.0.0.1:8769/mesh-import/"
local manifest = H:JSONDecode(H:GetAsync(base .. "manifest.json", true))
local clip = H:JSONDecode(H:GetAsync(base .. "WatchingIdle-8stud.json", true))
assert(clip.modelGlbSha256 == model:GetAttribute("SourceGlbSha256"), "Clip and rig source differ")
local bones, original, parents = {}, {}, {}
for _, b in manifest.bones do
	local bone = assert(model:FindFirstChild(b.name, true), "Missing bone: " .. b.name)
	assert(bone:IsA("Bone"), "Name resolves to non-Bone: " .. b.name)
	bones[b.name], original[b.name], parents[b.name] = bone, bone.Transform, b.parent
end

local function poseFrame(p)
	local x, y, z, w = p[5], p[6], p[7], p[8]
	return CFrame.new(p[2], p[3], p[4],
		1 - 2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w),
		2*(x*y+z*w), 1 - 2*(x*x+z*z), 2*(y*z-x*w),
		2*(x*z-y*w), 2*(y*z+x*w), 1 - 2*(x*x+y*y))
end
local function errorBetween(a, b)
	local aa, bb = {a:GetComponents()}, {b:GetComponents()}
	local maximum = 0
	for i = 1, 12 do maximum = math.max(maximum, math.abs(aa[i] - bb[i])) end
	return maximum
end
local function resetIdentity()
	for _, bone in bones do bone.Transform = CFrame.identity end
end
local function restore()
	for name, bone in bones do bone.Transform = original[name] end
end
local function makeSequence(withPartParent)
	local seq = Instance.new("KeyframeSequence")
	seq.Name = withPartParent and "WW_QA_MeshPartPose" or "WW_QA_DirectRootPose"
	seq.Loop = false
	seq.Priority = Enum.AnimationPriority.Action4
	for _, frame in clip.frames do
		local key = Instance.new("Keyframe")
		key.Time = frame.time
		local rootParent = key
		if withPartParent then
			local meshPose = Instance.new("Pose")
			meshPose.Name = part.Name
			meshPose.CFrame = CFrame.identity
			meshPose.Weight = 0
			meshPose.Parent = key
			rootParent = meshPose
		end
		local poses = {}
		for _, p in frame.poses do
			local pose = Instance.new("Pose")
			pose.Name, pose.CFrame, pose.Weight = p[1], poseFrame(p), 1
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.EasingDirection = Enum.PoseEasingDirection.InOut
			poses[p[1]] = pose
		end
		for name, pose in poses do pose.Parent = parents[name] and poses[parents[name]] or rootParent end
		key.Parent = seq
	end
	return seq
end

local report = {
	scope = "Studio-only temporary Animator binding test; no durable asset or published-play claim",
	clip = clip.name, model = model:GetFullName(), meshPart = part.Name, sourceGlbSha256 = manifest.sourceGlbSha256,
	expectedBones = #manifest.bones, tolerance = 0.001, variants = {},
}
for _, withPartParent in {false, true} do
	local result = {hierarchy = withPartParent and "MeshPartPose > Root > Hips" or "Root > Hips", samples = {}, pass = false}
	local sequence, animation, track
	local ok, err = xpcall(function()
		resetIdentity()
		sequence = makeSequence(withPartParent)
		animation = Instance.new("Animation")
		animation.Name = "TEMPORARY_Watcher_Animator_QA"
		animation.AnimationId = KSP:RegisterKeyframeSequence(sequence)
		result.temporaryAnimationId = animation.AnimationId
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		track:Play(0, 1, 0)
		local deadline = os.clock() + 8
		while track.Length == 0 and os.clock() < deadline do task.wait(0.05) end
		assert(track.Length > 0, "Temporary animation did not load within eight seconds")
		result.loadedLength = track.Length
		result.pass = true
		for _, frameIndex in {1, 46, 91, 136} do
			local frame = clip.frames[frameIndex]
			resetIdentity()
			track.TimePosition = frame.time
			animator:StepAnimations(0)
			-- A second zero-time evaluation permits any queued binding work to settle.
			task.wait()
			animator:StepAnimations(0)
			local sample = {requestedTime = frame.time, actualTime = track.TimePosition, maximumError = 0,
				matchedBones = 0, expectedNonIdentityBones = 0, matchedNonIdentityBones = 0,
				actualNonIdentityBones = 0, mismatchExamples = {}}
			for _, p in frame.poses do
				local expected = poseFrame(p)
				local actual = bones[p[1]].Transform
				local e = errorBetween(actual, expected)
				local nonIdentity = errorBetween(expected, CFrame.identity) > report.tolerance
				if nonIdentity then sample.expectedNonIdentityBones += 1 end
				if errorBetween(actual, CFrame.identity) > report.tolerance then sample.actualNonIdentityBones += 1 end
				if e <= report.tolerance then
					sample.matchedBones += 1
					if nonIdentity then sample.matchedNonIdentityBones += 1 end
				elseif #sample.mismatchExamples < 5 then
					table.insert(sample.mismatchExamples, {bone = p[1], matrixError = e})
				end
				sample.maximumError = math.max(sample.maximumError, e)
			end
			sample.pass = sample.matchedBones == #manifest.bones and sample.expectedNonIdentityBones > 0
				and sample.matchedNonIdentityBones == sample.expectedNonIdentityBones
			result.pass = result.pass and sample.pass
			table.insert(result.samples, sample)
		end
	end, debug.traceback)
	if not ok then result.pass = false; result.error = tostring(err) end
	-- Always stop/destroy only this test's track and restore the captured original pose.
	if track then pcall(function() track:Stop(0); animator:StepAnimations(0); track:Destroy() end) end
	if animation then animation:Destroy() end
	if sequence then sequence:Destroy() end
	restore()
	table.insert(report.variants, result)
end
report.restoredOriginalPose = true
report.passingHierarchies = {}
for _, result in report.variants do
	if result.pass then table.insert(report.passingHierarchies, result.hierarchy) end
end
report.pass = #report.passingHierarchies > 0
return report
