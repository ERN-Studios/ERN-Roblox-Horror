-- Exact frozen Meshy/Blender GLB transfer. Returns an incremental Studio module.
-- Only explicit publishMesh() uploads. Rig builders return UNPARENTED models.
-- buildPreview() is opt-in, Studio-only and does not create persistent content.
-- Source coordinates are floor-origin, 8 studs high, facing -Z. To remove native
-- mesh-centering ambiguity, positions AND mesh-world bone binds are centered by
-- the measured bounds center. MeshPart.CFrame restores this offset; its pivot is
-- actor floor origin. Bone-local animation deltas require no further conversion.
local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local M = {}
local S = nil
local EXPECTED = "cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"

local function v3(a)
	return Vector3.new(a[1], a[2], a[3])
end
local function cf(a)
	return CFrame.new(table.unpack(a))
end
local function vec(a)
	return {a.X, a.Y, a.Z}
end
local function components(a)
	return {a:GetComponents()}
end
local function fetch(path)
	assert(S, "Call begin first")
	return HttpService:JSONDecode(HttpService:GetAsync(S.base .. path, true))
end
local function ready()
	assert(S and S.mesh, "Call begin first")
	assert(S.vertexChunk > #S.manifest.vertexChunks, "Vertex chunks remain")
	assert(S.faceChunk > #S.manifest.faceChunks, "Face chunks remain")
	assert(#S.mesh:GetVertices() == S.manifest.vertices, "Wrong vertex count")
	assert(#S.mesh:GetFaces() == S.manifest.triangles, "Wrong face count")
end
local function maxCFError(a, b)
	local aa, bb = components(a), components(b)
	local maximum = 0
	for i = 1, 12 do maximum = math.max(maximum, math.abs(aa[i] - bb[i])) end
	return maximum
end

function M.begin(baseUrl)
	assert(not S, "Session exists; destroy() before restarting")
	S = {base = baseUrl, vertexChunk = 1, faceChunk = 1, vertices = {}, normals = {}, uvs = {}, boneIds = {}, model = nil}
	if string.sub(S.base, -1) ~= "/" then S.base ..= "/" end
	S.manifest = fetch("manifest.json")
	assert(S.manifest.sourceGlbSha256 == EXPECTED, "Unexpected frozen source")
	assert(S.manifest.triangles <= 20000 and #S.manifest.bones == 25, "Unexpected geometry contract")
	S.center = v3(S.manifest.bounds.center)
	S.size = v3(S.manifest.bounds.size)
	S.mesh = assert(AssetService:CreateEditableMesh(), "CreateEditableMesh returned nil")
	for _, bone in S.manifest.bones do
		local options = {Name = bone.name, CFrame = CFrame.new(-S.center) * cf(bone.bindWorld), Virtual = false}
		if bone.parent then options.ParentId = assert(S.boneIds[bone.parent], "Bone order must be parent-first") end
		S.boneIds[bone.name] = S.mesh:AddBone(options)
	end
	return M.report()
end

function M.nextVertices()
	assert(S and S.mesh, "Call begin first")
	local chunkInfo = S.manifest.vertexChunks[S.vertexChunk]
	if not chunkInfo then return {done = true, kind = "vertices", total = #S.vertices} end
	local chunk = fetch(chunkInfo.path)
	for at, row in chunk.rows do
		local sourceIndex = chunk.start + at - 1
		assert(not S.vertices[sourceIndex], "Repeated vertex chunk")
		local id = S.mesh:AddVertex(Vector3.new(row[1], row[2], row[3]) - S.center)
		S.vertices[sourceIndex] = id
		S.normals[sourceIndex] = S.mesh:AddNormal(Vector3.new(row[4], row[5], row[6]))
		S.uvs[sourceIndex] = S.mesh:AddUV(Vector2.new(row[7], row[8]))
		local boneIds, weights = {}, {}
		for k = 9, 15, 2 do
			if row[k + 1] > 0 then
				local boneId = assert(S.boneIds[S.manifest.jointNames[row[k]]], "Unknown joint index")
				table.insert(boneIds, boneId)
				table.insert(weights, row[k + 1])
			end
		end
		assert(#boneIds > 0 and #boneIds <= 4, "Invalid skin influences")
		S.mesh:SetVertexBones(id, boneIds)
		S.mesh:SetVertexBoneWeights(id, weights)
		if at % 500 == 0 then task.wait() end
	end
	S.vertexChunk += 1
	return {done = S.vertexChunk > #S.manifest.vertexChunks, kind = "vertices", chunk = S.vertexChunk - 1, total = #S.vertices}
end

function M.nextFaces()
	assert(S and S.mesh, "Call begin first")
	assert(S.vertexChunk > #S.manifest.vertexChunks, "Finish vertices before faces")
	local chunkInfo = S.manifest.faceChunks[S.faceChunk]
	if not chunkInfo then return {done = true, kind = "faces", total = #S.mesh:GetFaces()} end
	local chunk = fetch(chunkInfo.path)
	for at, row in chunk.rows do
		local face = S.mesh:AddTriangle(S.vertices[row[1]], S.vertices[row[2]], S.vertices[row[3]])
		S.mesh:SetFaceNormals(face, {S.normals[row[1]], S.normals[row[2]], S.normals[row[3]]})
		S.mesh:SetFaceUVs(face, {S.uvs[row[1]], S.uvs[row[2]], S.uvs[row[3]]})
		if at % 500 == 0 then task.wait() end
	end
	S.faceChunk += 1
	return {done = S.faceChunk > #S.manifest.faceChunks, kind = "faces", chunk = S.faceChunk - 1, total = #S.mesh:GetFaces()}
end

function M.report()
	assert(S, "Call begin first")
	local r = {sourceGlbSha256 = EXPECTED, nextVertexChunk = S.vertexChunk, nextFaceChunk = S.faceChunk,
		vertexChunks = #S.manifest.vertexChunks, faceChunks = #S.manifest.faceChunks,
		centerRemoved = vec(S.center), expectedSize = vec(S.size), meshAssetId = S.meshAssetId,
		sourceUnits = "8-stud floor-origin actor, -Z front", meshUnits = "AABB-centered studs"}
	if S.mesh then
		r.vertices = #S.mesh:GetVertices()
		r.faces = #S.mesh:GetFaces()
		r.bones = #S.mesh:GetBones()
		if r.vertices > 0 then r.actualCenter = vec(S.mesh:GetCenter()); r.actualSize = vec(S.mesh:GetSize()) end
	end
	return r
end

function M.publishMesh()
	ready()
	if S.meshAssetId then return {alreadyPublished = true, assetId = S.meshAssetId} end
	assert(S.mesh:GetCenter().Magnitude < 0.0001, "Centered bounds unexpectedly shifted")
	assert((S.mesh:GetSize() - S.size).Magnitude < 0.0001, "Geometry dimensions changed")
	local status, assetId = AssetService:CreateAssetAsync(S.mesh, Enum.AssetType.Mesh, {
		Name = "Level5 Window Watcher exact Meshy rig",
		Description = "Original Meshy Window Watcher with 25 Blender-authored rig bones, exact GLB geometry and weights.",
		CreatorId = 1039373905,
		CreatorType = Enum.AssetCreatorType.Group,
	})
	assert(status == Enum.CreateAssetResult.Success, "Mesh upload failed: " .. tostring(status) .. " " .. tostring(assetId))
	S.meshAssetId = tostring(assetId)
	return {status = tostring(status), assetId = S.meshAssetId, vertices = S.manifest.vertices, triangles = S.manifest.triangles, bones = 25}
end

-- Explicit round-trip guard. Can retry this read-only load if asset processing is pending.
function M.verifyPublished()
	assert(S and S.meshAssetId, "Publish mesh first")
	local loaded = assert(AssetService:CreateEditableMeshAsync(Content.fromUri("rbxassetid://" .. S.meshAssetId)), "Published mesh could not be read")
	local r = {assetId = S.meshAssetId, vertices = #loaded:GetVertices(), faces = #loaded:GetFaces(), bones = #loaded:GetBones(),
		center = vec(loaded:GetCenter()), size = vec(loaded:GetSize()), maximumBoneFrameError = 0, missingBones = {}, parentMismatches = {}}
	local ids = {}
	for _, id in loaded:GetBones() do ids[loaded:GetBoneName(id)] = id end
	for _, bone in S.manifest.bones do
		local id = ids[bone.name]
		if not id then table.insert(r.missingBones, bone.name) else
			r.maximumBoneFrameError = math.max(r.maximumBoneFrameError, maxCFError(loaded:GetBoneCFrame(id), CFrame.new(-S.center) * cf(bone.bindWorld)))
			if bone.parent and loaded:GetBoneParent(id) ~= ids[bone.parent] then table.insert(r.parentMismatches, bone.name) end
		end
	end
	r.pass = r.vertices == S.manifest.vertices and r.faces == S.manifest.triangles and r.bones == 25
		and loaded:GetCenter().Magnitude < 0.0001 and (loaded:GetSize() - S.size).Magnitude < 0.0001
		and r.maximumBoneFrameError < 0.0001 and #r.missingBones == 0 and #r.parentMismatches == 0
	loaded:Destroy()
	S.roundTrip = r
	return r
end

-- Shared constructor: published runtime and transient preview use identical rig math.
-- PivotTo(actorOrigin) is safe: the primary part's pivot restores actor floor origin.
local function constructRig(meshContent, textureAssetId, actorOrigin, temporaryPreview)
	assert(not S.model, "Model already built; use getModel()")
	actorOrigin = actorOrigin or CFrame.identity
	local part = AssetService:CreateMeshPartAsync(meshContent, {
		CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise,
	})
	assert((part.MeshSize - S.size).Magnitude < 0.001, "Native MeshSize differs from validated mesh coordinates")
	part.Name = "WindowWatcherMesh"
	part.Size = part.MeshSize
	part.CFrame = actorOrigin * CFrame.new(S.center)
	part.PivotOffset = CFrame.new(-S.center)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.DoubleSided = true
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.new(1, 1, 1)
	part.TextureID = "rbxassetid://" .. tostring(textureAssetId or 91091934459636)
	-- Only clean auto-created bones on this brand-new, unparented part.
	for _, child in part:GetChildren() do if child:IsA("Bone") then child:Destroy() end end
	local model = Instance.new("Model")
	model.Name = temporaryPreview and "WindowWatcher_TemporaryStudioPreview" or "WindowWatcher"
	part.Parent = model
	model.PrimaryPart = part
	local bones = {}
	for _, data in S.manifest.bones do
		local bone = Instance.new("Bone")
		bone.Name = data.name
		bone.CFrame = data.parent and cf(data.restLocal) or CFrame.new(-S.center) * cf(data.restLocal)
		bone.Parent = data.parent and assert(bones[data.parent]) or part
		bones[data.name] = bone
	end
	local controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	controller.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = controller
	-- Eye attachments are installed separately from eye-placement/eye-placement.json.
	-- Manifest's earlier estimatedEyeAttachments are obsolete and must NOT be used.
	model:SetAttribute("SourceGlbSha256", EXPECTED)
	model:SetAttribute("Source", "Meshy geometry; authored in Blender; exact EditableMesh transfer")
	if not temporaryPreview then model:SetAttribute("MeshAssetId", S.meshAssetId) end
	model:SetAttribute("TemporaryStudioPreview", temporaryPreview)
	part:SetAttribute("TemporaryStudioPreview", temporaryPreview)
	model:SetAttribute("PersistenceStatus", temporaryPreview and "Transient editable content; NOT a published asset" or "Published mesh asset; round-trip verified")
	model:SetAttribute("RigBones", 25)
	model:SetAttribute("Triangles", S.manifest.triangles)
	model:SetAttribute("ActorHeightStuds", 8)
	model:SetAttribute("ActorFront", "-Z")
	S.model, S.runtimeBones, S.temporaryPreview = model, bones, temporaryPreview
	return model, {MeshSize = vec(part.MeshSize), Size = vec(part.Size), meshCFrame = components(part.CFrame),
		meshPivotOffset = components(part.PivotOffset), modelPivot = components(model:GetPivot()),
		rootLocalFrame = components(bones.Root.CFrame), boneCount = #S.manifest.bones, textureAssetId = tostring(textureAssetId or 91091934459636),
		TemporaryStudioPreview = temporaryPreview, persistentMesh = not temporaryPreview}
end

-- Durable runtime path: requires an uploaded URI and independently verified readback.
function M.buildRuntime(textureAssetId, actorOrigin)
	assert(S and S.meshAssetId, "Publish mesh first")
	assert(S.roundTrip and S.roundTrip.pass, "verifyPublished() must pass before rig creation")
	return constructRig(Content.fromUri("rbxassetid://" .. S.meshAssetId), textureAssetId, actorOrigin, false)
end

-- Explicit temporary QA path. This does NOT upload, serialize or persist the mesh.
-- The caller must not treat a visible preview or saved model as production delivery.
function M.buildPreview(textureAssetId, actorOrigin)
	assert(game:GetService("RunService"):IsStudio(), "Temporary preview is Studio-only")
	ready()
	assert(#S.mesh:GetBones() == 25, "Unexpected bone count")
	assert(S.mesh:GetCenter().Magnitude < 0.0001, "Centered bounds unexpectedly shifted")
	assert((S.mesh:GetSize() - S.size).Magnitude < 0.0001, "Geometry dimensions changed")
	return constructRig(Content.fromObject(S.mesh), textureAssetId, actorOrigin, true)
end

-- Explicit cleanup allows a later verified runtime build in the same import session.
function M.discardPreview()
	assert(S and S.temporaryPreview and S.model, "No temporary preview to discard")
	S.model:Destroy()
	S.model, S.runtimeBones, S.temporaryPreview = nil, nil, false
end

function M.getModel()
	return S and S.model
end

-- Studio pose preview only; runtime Animator may override these Transform values.
-- These are deltas derived from actual serialized GLB local bases, already in studs.
function M.applyPose(clipName, frameIndex)
	assert(S and S.runtimeBones, "Build runtime or temporary preview first")
	assert(clipName == "WatchingIdle" or clipName == "SlowWindowLean" or clipName == "GlassTap", "Unknown clip")
	S.clips = S.clips or {}
	S.clips[clipName] = S.clips[clipName] or fetch(clipName .. "-8stud.json")
	local clip = S.clips[clipName]
	local frame = assert(clip.frames[frameIndex or 1], "Invalid frame")
	for _, pose in frame.poses do
		local x, y, z, w = pose[5], pose[6], pose[7], pose[8]
		S.runtimeBones[pose[1]].Transform = CFrame.new(pose[2], pose[3], pose[4],
			1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w),
			2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w),
			2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y))
	end
	return {name = clipName, frame = frameIndex or 1, time = frame.time, count = #frame.poses}
end

function M.destroy()
	-- Keeps any returned model and published asset. Destroys only the temporary EM.
	-- A live preview references that EM and becomes unusable; discardPreview first.
	assert(not (S and S.temporaryPreview and S.model), "discardPreview() before destroying its editable content")
	if S and S.mesh then S.mesh:Destroy() end
	S = nil
end

return M
