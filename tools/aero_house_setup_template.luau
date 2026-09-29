-- Aero House: select the complete imported Model in Studio Edit mode, then run
-- the packaged SetupAeroHouse.luau in the Command Bar. This template is filled
-- during export. The three named decorative anchors must remain in the import.
-- This changes only the selected house. It does not add scripts, change gravity,
-- create a spawn, save, or publish. Standard Roblox gravity is 196.2 studs/s^2.
-- Setup is one undoable operation. Undo before rerunning; existing data is never
-- replaced. Import at the documented stud scale, then move/rotate the whole house.

local MANIFEST_JSON = [==[__HOUSE_MANIFEST_JSON__]==]
local ENABLE_LOCAL_LIGHTS = true

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local RUNTIME_NAME = "AeroRuntime"
local OWNER = "aero-house"

assert(not RunService:IsRunning(), "Run Aero House setup in Edit mode, outside a Play test.")
local selected = Selection:Get()
assert(#selected == 1 and selected[1]:IsA("Model"), "Select exactly the complete imported Aero House Model.")
local model = selected[1]
assert(model:IsDescendantOf(workspace), "The selected house must be in Workspace.")
assert(not model:FindFirstChild(RUNTIME_NAME, true), "AeroRuntime already exists. Undo the previous setup before rerunning.")

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function vector(values, label)
	assert(type(values) == "table" and #values == 3, label .. " must have three numbers.")
	for _, n in ipairs(values) do
		assert(finite(n), label .. " contains an invalid number.")
	end
	return Vector3.new(values[1], values[2], values[3])
end

local function validName(name)
	return type(name) == "string" and #name > 0 and #name <= 120
end

local DATA = HttpService:JSONDecode(MANIFEST_JSON)
assert(type(DATA) == "table" and DATA.modelName == "Aero House", "Use the packaged Aero House setup file.")
assert(type(DATA.version) == "string" or finite(DATA.version), "Invalid manifest version.")
assert(type(DATA.colliders) == "table" and #DATA.colliders > 0, "Missing collision metadata.")
assert(type(DATA.lights) == "table" and #DATA.lights <= 5, "Invalid local-light metadata.")

-- Validate every generated specification before changing the selected model.
local colliderSpecs, lightSpecs = {}, {}
local names = {}
for index, entry in ipairs(DATA.colliders) do
	assert(validName(entry.name) and not names[entry.name], "Missing or duplicate collider name.")
	names[entry.name] = true
	local size = vector(entry.size, "Collider size " .. index)
	assert(math.min(size.X, size.Y, size.Z) >= 0.01, "Collider size is too small.")
	colliderSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "Collider position " .. index),
		size = size,
		rotation = vector(entry.rotation, "Collider rotation " .. index),
	}
end
for index, entry in ipairs(DATA.lights) do
	assert(validName(entry.name) and not names[entry.name], "Missing or duplicate local-light name.")
	names[entry.name] = true
	local color = vector(entry.color, "Light color " .. index)
	assert(math.min(color.X, color.Y, color.Z) >= 0 and math.max(color.X, color.Y, color.Z) <= 1,
		"Light colors must be in the range 0 to 1.")
	assert(finite(entry.range) and entry.range > 0 and entry.range <= 60, "Invalid light range.")
	assert(finite(entry.brightness) and entry.brightness >= 0 and entry.brightness <= 10, "Invalid light brightness.")
	lightSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "Light position " .. index),
		color = Color3.new(color.X, color.Y, color.Z),
		range = entry.range,
		brightness = entry.brightness,
	}
end

local markerNames = {
	Aero_Anchor_Entry = true,
	Aero_Anchor_RearRight = true,
	Aero_Anchor_RearLeft = true,
}
local markers, visuals, baseline = {}, {}, {}
local originalParent, originalName = model.Parent, model.Name
local originalPivot, originalPrimaryPart = model:GetPivot(), model.PrimaryPart
local previousVersion = model:GetAttribute("AeroSetupVersion")
local previousManifest = model:GetAttribute("AeroSetupManifest")
assert(previousVersion == nil and previousManifest == nil,
	"This house already has setup metadata. Undo the previous setup before rerunning.")

for _, instance in ipairs(model:GetDescendants()) do
	assert(not instance:IsA("LuaSourceContainer") and not instance:IsA("Humanoid"),
		"The selection contains a script or character. Select only the untouched house import.")
	local snapshot = { Parent = instance.Parent, Name = instance.Name }
	baseline[instance] = snapshot
	if instance:IsA("BasePart") then
		assert(instance:IsA("MeshPart") and string.match(instance.Name, "^Aero_"),
			"The selection contains a part outside the house export. Select only the intact import.")
		table.insert(visuals, instance)
		for _, property in ipairs({ "CFrame", "Size", "Anchored", "CanCollide", "CanTouch", "CanQuery",
			"Transparency", "CastShadow", "RenderFidelity", "CollisionFidelity", "MeshId", "TextureID" }) do
			snapshot[property] = instance[property]
		end
	end
	if markerNames[instance.Name] then
		assert(instance:IsA("MeshPart") and not markers[instance.Name], "The three anchors must be unique MeshParts.")
		markers[instance.Name] = instance
	end
end
assert(#visuals > 3, "The selected Model is not the complete Aero House import.")
for name in pairs(markerNames) do
	assert(markers[name], "Missing " .. name .. ". Keep all three anchors and original mesh names during import.")
end

-- The front of the authored house is Roblox +Z. Derive the import frame from
-- real mesh centers, not the model pivot; Studio may rotate/recenter that pivot.
local entry = markers.Aero_Anchor_Entry.Position
local rearRight = markers.Aero_Anchor_RearRight.Position
local rearLeft = markers.Aero_Anchor_RearLeft.Position
local rearSpan = rearRight - rearLeft
local frontSpan = entry - (rearRight + rearLeft) * 0.5
assert(rearSpan.Magnitude > 0.01 and frontSpan.Magnitude > 0.01, "The import anchors overlap.")
local right = rearSpan.Unit
local forwardComponent = frontSpan - right * frontSpan:Dot(right)
assert(forwardComponent.Magnitude > 0.01, "The import anchors are collinear.")
local front = forwardComponent.Unit
local up = front:Cross(right).Unit
front = right:Cross(up).Unit
local scale = rearSpan.Magnitude / 80
local depthScale = forwardComponent.Magnitude / 78
assert(math.abs(scale - 1) <= 0.01,
	"Import scale is incorrect. Use the documented stud scale; this setup does not resize your model.")
assert(math.abs(depthScale / scale - 1) <= 0.01 and math.abs(frontSpan:Dot(right)) <= 0.78 * scale,
	"The house has uneven scaling or distorted anchors. Reimport with the documented uniform scale.")
assert(up:Dot(Vector3.yAxis) >= 0.999,
	"Keep the house upright. Whole-house translation and yaw rotation are supported.")
local origin = entry - up * (2 * scale) - front * (42 * scale)
local frame = CFrame.fromMatrix(origin, right, up, front)

-- If present, marker dimensions also detect vertical-only scaling, which three
-- coplanar marker centers cannot measure. The exporter uses identical anchors.
if DATA.anchorSizeRoblox then
	local anchorSize = vector(DATA.anchorSizeRoblox, "Authored anchor size")
	assert(math.min(anchorSize.X, anchorSize.Y, anchorSize.Z) > 0, "Invalid authored anchor size.")
	for name, marker in pairs(markers) do
		local localSize = marker.Size
		assert(math.abs(localSize.X / (anchorSize.X * scale) - 1) <= 0.01
			and math.abs(localSize.Y / (anchorSize.Y * scale) - 1) <= 0.01
			and math.abs(localSize.Z / (anchorSize.Z * scale) - 1) <= 0.01,
			name .. " has uneven scaling. Reimport the untouched house.")
	end
end

local function assertFreshBaseline()
	assert(model.Parent == originalParent and model.Name == originalName
		and model:GetPivot() == originalPivot and model.PrimaryPart == originalPrimaryPart,
		"The selected model changed during setup. Rerun against its current state.")
	assert(model:GetAttribute("AeroSetupVersion") == previousVersion
		and model:GetAttribute("AeroSetupManifest") == previousManifest,
		"Setup metadata changed during preparation. Rerun against the current model.")
	local count = 0
	for _, instance in ipairs(model:GetDescendants()) do
		local snapshot = baseline[instance]
		assert(snapshot, "An instance was added during preparation. Rerun against the current model.")
		for property, value in pairs(snapshot) do
			assert(instance[property] == value, instance.Name .. " changed during preparation. Rerun setup.")
		end
		count += 1
	end
	local originalCount = 0
	for _ in pairs(baseline) do originalCount += 1 end
	assert(count == originalCount, "An instance was removed during preparation. Rerun setup.")
	local currentSelection = Selection:Get()
	assert(#currentSelection == 1 and currentSelection[1] == model, "Selection changed during setup.")
end

local recording = ChangeHistoryService:TryBeginRecording("AeroHouseSetup", "Set up Aero House collisions and lights")
assert(recording, "Could not start an undo recording. Finish the current Studio edit and retry.")
local runtime
local changedVisuals = {}
local metadataWritten = false
local ok, problem = xpcall(function()
	-- Recheck inside the write, before touching any authoritative Studio data.
	assertFreshBaseline()
	runtime = Instance.new("Model")
	runtime.Name = RUNTIME_NAME
	runtime:SetAttribute("Owner", OWNER)
	runtime:SetAttribute("SetupVersion", tostring(DATA.version))
	runtime:SetAttribute("ImportScale", scale)
	runtime:SetAttribute("LocalLightsEnabled", ENABLE_LOCAL_LIGHTS)

	local function invisiblePart(name)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part:SetAttribute("Owner", OWNER)
		return part
	end
	for _, spec in ipairs(colliderSpecs) do
		local part = invisiblePart(spec.name)
		part.Size = spec.size * scale
		part.CFrame = frame * CFrame.new(spec.position * scale)
			* CFrame.Angles(math.rad(spec.rotation.X), math.rad(spec.rotation.Y), math.rad(spec.rotation.Z))
		part.CanCollide = true
		part.CanQuery = true
		part.Parent = runtime
	end
	if ENABLE_LOCAL_LIGHTS then
		for _, spec in ipairs(lightSpecs) do
			local fixture = invisiblePart(spec.name)
			fixture.Size = Vector3.new(0.1, 0.1, 0.1) * scale
			fixture.CFrame = frame * CFrame.new(spec.position * scale)
			fixture.CanCollide = false
			fixture.CanQuery = false
			local light = Instance.new("PointLight")
			light.Name = "LocalLight"
			light.Color = spec.color
			light.Range = spec.range * scale
			light.Brightness = spec.brightness
			light.Shadows = false
			light.Parent = fixture
			fixture.Parent = runtime
		end
	end
	for _, part in ipairs(visuals) do
		table.insert(changedVisuals, part)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = true
		part.RenderFidelity = Enum.RenderFidelity.Automatic
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		if string.find(part.Name, "Glass", 1, true) then
			part.Transparency = 0.35
			part.CastShadow = false
		end
	end
	runtime.Parent = model
	metadataWritten = true
	model:SetAttribute("AeroSetupVersion", tostring(DATA.version))
	model:SetAttribute("AeroSetupManifest", MANIFEST_JSON)
end, debug.traceback)

if not ok then
	-- Cancel discards the recording; explicitly restore only properties this
	-- operation touched. Never delete or replace a pre-existing Studio instance.
	local restored, restoreProblem = pcall(function()
		if runtime then runtime:Destroy() end
		for _, part in ipairs(changedVisuals) do
			for _, property in ipairs({ "Anchored", "CanCollide", "CanTouch", "CanQuery",
				"Transparency", "CastShadow", "RenderFidelity", "CollisionFidelity" }) do
				part[property] = baseline[part][property]
			end
		end
		if metadataWritten then
			model:SetAttribute("AeroSetupVersion", previousVersion)
			model:SetAttribute("AeroSetupManifest", previousManifest)
		end
	end)
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
	assert(restored, tostring(problem) .. "\nRollback needs attention: " .. tostring(restoreProblem))
	error(problem)
end

ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
print(string.format("Aero House ready: %d anchored visual meshes, %d simple colliders, %d local lights. Gravity unchanged (%g).",
	#visuals, #colliderSpecs, ENABLE_LOCAL_LIGHTS and #lightSpecs or 0, workspace.Gravity))
print("Test the house in Play mode after adding your normal player spawn. Undo once to remove this setup.")
