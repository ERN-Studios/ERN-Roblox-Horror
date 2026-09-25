-- Window Watcher physical white-eye emission. Module-style API:
--   require(module).Apply(rig, uploadedMaskAssetId, optionalStrength)
-- New technical mask is baked from the exact iris geometry into original UVs.
-- Unlike the superseded BillboardGui version, SurfaceAppearance is on the actual
-- skinned surface and must receive native visual QA behind the map's tinted Glass.
-- No PointLight/SpotLight/SurfaceLight, GUI, geometry, albedo edits, or bone changes.
local Eyes = {}

local OWNER_ATTRIBUTE = "WindowWatcherEyeOwner"
local OWNER = "WindowWatcherEmissionEyes20260925"
local OLD_BILLBOARD_OWNER = "WindowWatcherWhiteEyes20260925"
local MODEL_SHA256 = "cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e"
local MASK_SHA256 = "99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738"
local BASE_COLOR = "rbxassetid://91091934459636"
local APPEARANCE_NAME = "WindowWatcherEyeEmission"

local function normalizeAssetId(value)
	local text = tostring(value)
	local id = text:match("^rbxassetid://(%d+)$") or text:match("^(%d+)$")
	assert(id and tonumber(id) and tonumber(id) > 0,
		"WindowWatcher eyes: pass the uploaded emission-mask asset ID")
	return "rbxassetid://" .. id
end

local function assertOwnedTree(instance, owner)
	assert(instance:GetAttribute(OWNER_ATTRIBUTE) == owner,
		"WindowWatcher eyes: foreign " .. instance.Name .. " preserved")
	for _, child in ipairs(instance:GetDescendants()) do
		assert(child:GetAttribute(OWNER_ATTRIBUTE) == owner,
			"WindowWatcher eyes: foreign content inside " .. instance.Name .. " preserved")
	end
end

function Eyes.Apply(rig, maskAssetId, strength)
	assert(typeof(rig) == "Instance" and rig:IsA("Model"),
		"WindowWatcher eyes: expected the exact native rig Model")
	assert(rig:GetAttribute("SourceGlbSha256") == MODEL_SHA256,
		"WindowWatcher eyes: SourceGlbSha256 does not match the measured model")
	local actorHeight = rig:GetAttribute("ActorHeightStuds")
	assert(typeof(actorHeight) == "number" and math.abs(actorHeight - 8) < 0.00001,
		"WindowWatcher eyes: exact 8-stud ActorHeightStuds contract required")
	local maskUri = normalizeAssetId(maskAssetId)
	strength = strength == nil and 200 or strength
	assert(typeof(strength) == "number" and strength == strength and strength >= 5 and strength <= 200,
		"WindowWatcher eyes: EmissiveStrength must be between 5 and 200")

	-- Full preflight before mutating any existing instance.
	local mesh
	local obsoleteEyes = {}
	local eyeNames = {}
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant.Name == "WindowWatcherMesh" then
			assert(not mesh and descendant:IsA("MeshPart"),
				"WindowWatcher eyes: one WindowWatcherMesh MeshPart is required")
			mesh = descendant
		elseif descendant.Name == "EyeL" or descendant.Name == "EyeR" then
			assert(not eyeNames[descendant.Name], "WindowWatcher eyes: duplicate eye marker names")
			eyeNames[descendant.Name] = true
			assert(descendant.ClassName == "Attachment" and descendant.Parent
				and descendant.Parent:IsA("Bone") and descendant.Parent.Name == "Head",
				"WindowWatcher eyes: foreign eye marker location/class preserved")
			assertOwnedTree(descendant, OLD_BILLBOARD_OWNER)
			table.insert(obsoleteEyes, descendant)
		end
	end
	assert(mesh, "WindowWatcher eyes: WindowWatcherMesh missing")
	assert(mesh.TextureID == BASE_COLOR,
		"WindowWatcher eyes: unexpected base-color texture; preserve and inspect before applying")
	local previousAppearance
	for _, child in ipairs(mesh:GetChildren()) do
		if child:IsA("SurfaceAppearance") then
			assert(not previousAppearance, "WindowWatcher eyes: multiple SurfaceAppearances preserved")
			assert(child.Name == APPEARANCE_NAME, "WindowWatcher eyes: foreign SurfaceAppearance preserved")
			assertOwnedTree(child, OWNER)
			assert(child.ColorMap == BASE_COLOR,
				"WindowWatcher eyes: changed ColorMap on owned appearance; preserved")
			previousAppearance = child
		elseif child.Name == APPEARANCE_NAME then
			error("WindowWatcher eyes: conflicting appearance name/class preserved")
		end
	end

	-- Configure detached first: unsupported native properties fail before existing
	-- eyes/appearance are removed. There is never a GUI layer over the new emission.
	local appearance = previousAppearance and previousAppearance:Clone() or Instance.new("SurfaceAppearance")
	appearance.Name = APPEARANCE_NAME
	appearance:SetAttribute(OWNER_ATTRIBUTE, OWNER)
	appearance:SetAttribute("WindowWatcherSourceSha256", MODEL_SHA256)
	appearance:SetAttribute("WindowWatcherEmissionMaskSha256", MASK_SHA256)
	appearance:SetAttribute("WindowWatcherEyeCoreDiameterStuds", 0.067)
	appearance:SetAttribute("WindowWatcherActorHeightStuds", 8)
	appearance.ColorMap = BASE_COLOR
	appearance.EmissiveMaskContent = Content.fromUri(maskUri)
	appearance.EmissiveTint = Color3.fromRGB(255, 255, 255)
	appearance.EmissiveStrength = strength
	if previousAppearance then previousAppearance:Destroy() end
	appearance.Parent = mesh
	for _, attachment in ipairs(obsoleteEyes) do attachment:Destroy() end

	return {
		Mesh = mesh,
		SurfaceAppearance = appearance,
		EmissiveMaskUri = maskUri,
		EmissiveStrength = strength,
		CoreDiameterStuds = 0.067,
		SourceModelSha256 = MODEL_SHA256,
		MaskSha256 = MASK_SHA256,
		RemovedOwnedBillboardEyes = #obsoleteEyes,
	}
end

return Eyes
