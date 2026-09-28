-- Vesper Cathedral: optional, undoable Studio EDIT-MODE setup.
-- The packaged copy contains generated geometry metadata in DATA. This template
-- is not runnable until __CATHEDRAL_DATA__ is replaced during packaging.
-- Select exactly the imported cathedral Model, then paste the packaged script
-- into Studio's Command Bar. This changes only that selected model.
-- It normalizes the complete visual width to the authored stud scale while
-- preserving the model's current pivot position AND orientation. A tiny import
-- is therefore enlarged around its existing pivot, not moved to world origin.
-- It anchors the visual meshes, replaces only its own tagged setup folder,
-- disables visual collisions/touch events, and adds simple invisible colliders.
-- Optional local lights do not change the global Lighting service. No scripts,
-- save, publication, asset upload, or game-service modifications are performed.
-- Keep the imported hierarchy intact; do not independently rotate its pivot,
-- deform it, merge it with other models, or add extra meshes before setup.

local DATA = __CATHEDRAL_DATA__
local ENABLE_LOCAL_LIGHTS = true

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local FOLDER_NAME = "_VesperSetup"
local OWNER_ATTRIBUTE = "VesperSetupOwner"
local OWNER = "vesper-cathedral/v1"

assert(not RunService:IsRunning(), "Run cathedral setup in Studio Edit mode, outside a Play test.")
local selected = Selection:Get()
assert(#selected == 1 and selected[1]:IsA("Model"), "Select exactly one imported cathedral Model first.")
local model = selected[1]
assert(model:IsDescendantOf(workspace), "The selected cathedral Model must be in Workspace.")

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

assert(type(DATA) == "table", "This is an unfilled template; use the packaged setup script.")
local targetDimensions = vector(DATA.dimensions, "dimensions")
local sourceCenter = vector(DATA.center, "center")
assert(math.min(targetDimensions.X, targetDimensions.Y, targetDimensions.Z) > 0, "Invalid authored dimensions.")
assert(type(DATA.colliders) == "table" and #DATA.colliders > 0, "Missing collider metadata.")
assert(type(DATA.lights) == "table", "Missing light metadata.")

-- Validate all metadata and the complete selection before any mutation.
local colliderSpecs = {}
for index, entry in ipairs(DATA.colliders) do
	assert(type(entry.name) == "string" and #entry.name > 0, "Collider has no name.")
	local size = vector(entry.size, "collider size " .. index)
	assert(math.min(size.X, size.Y, size.Z) >= 0.001, "Collider size is too small.")
	colliderSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "collider position " .. index),
		size = size,
		rotation = vector(entry.rotation, "collider rotation " .. index),
	}
end
local lightSpecs = {}
for index, entry in ipairs(DATA.lights) do
	assert(type(entry.name) == "string" and #entry.name > 0, "Light has no name.")
	local color = vector(entry.color, "light color " .. index)
	assert(math.min(color.X, color.Y, color.Z) >= 0 and math.max(color.X, color.Y, color.Z) <= 1, "Invalid light color.")
	assert(finite(entry.range) and entry.range > 0 and entry.range <= 60, "Light range must be within (0, 60].")
	assert(finite(entry.brightness) and entry.brightness >= 0, "Invalid light brightness.")
	lightSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "light position " .. index),
		color = Color3.new(color.X, color.Y, color.Z),
		range = entry.range,
		brightness = entry.brightness,
	}
end

local previousSetup
for _, child in ipairs(model:GetChildren()) do
	if child.Name == FOLDER_NAME then
		assert(previousSetup == nil, "More than one _VesperSetup exists; resolve the conflicting folders first.")
		assert(child:IsA("Folder") and child:GetAttribute(OWNER_ATTRIBUTE) == OWNER,
			"An unrecognized _VesperSetup exists. It will not be replaced.")
		previousSetup = child
		for _, descendant in ipairs(child:GetDescendants()) do
			assert(descendant:GetAttribute(OWNER_ATTRIBUTE) == OWNER,
				"_VesperSetup contains an unrecognized addition. Move it out before rerunning setup.")
		end
	end
end

local visuals = {}
local savedVisuals = {}
local visualNames = {}
for _, descendant in ipairs(model:GetDescendants()) do
	if not previousSetup or not descendant:IsDescendantOf(previousSetup) then
		assert(not descendant:IsA("LuaSourceContainer") and not descendant:IsA("Humanoid"),
			"The selection contains scripts or a character. Select only the untouched cathedral import.")
		if descendant:IsA("BasePart") then
			assert(descendant:IsA("MeshPart"), "The selection has an extra non-mesh part. Select only the cathedral import.")
			assert(string.match(descendant.Name, "^Vesper_") ~= nil,
				"The selection contains a mesh outside the Vesper import. Move additions out before setup.")
			table.insert(visuals, descendant)
			visualNames[descendant.Name] = true
			savedVisuals[descendant] = {
				Anchored = descendant.Anchored,
				CanCollide = descendant.CanCollide,
				CanTouch = descendant.CanTouch,
			}
		end
	end
end
assert(#visuals > 0, "The selected Model contains no imported MeshParts.")
assert(visualNames.Vesper_01_Foundation and visualNames.Vesper_02_InteriorFloor and visualNames.Vesper_07_NaveRoof,
	"The selected Model is not the complete Vesper Cathedral import. Preserve its supplied mesh names.")
assert(not (previousSetup and model.PrimaryPart and model.PrimaryPart:IsDescendantOf(previousSetup)),
	"The Model's PrimaryPart is inside the replaceable setup folder. Clear that PrimaryPart before rerunning setup.")

-- Use the visual meshes only, so previously installed colliders/lights cannot
-- alter the repeat-run measurement. Bounds are oriented by the model pivot,
-- matching GetBoundingBox's documented model frame. Import exports have applied
-- mesh transforms, so their part boxes match the recorded authored bounds.
local function visualBounds()
	local orientation = model:GetPivot().Rotation
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(visuals) do
		local half = part.Size * 0.5
		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					local p = orientation:PointToObjectSpace(corner)
					low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
					high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
				end
			end
		end
	end
	return orientation * CFrame.new((low + high) * 0.5), high - low
end

local _, initialDimensions = visualBounds()
assert(math.min(initialDimensions.X, initialDimensions.Y, initialDimensions.Z) > 0, "The imported visual bounds are empty.")
local resizeFactor = targetDimensions.X / initialDimensions.X
local predictedDimensions = initialDimensions * resizeFactor
local function proportionMatches(actual, expected)
	return math.abs(actual - expected) <= math.max(0.05, expected * 0.03)
end
assert(proportionMatches(predictedDimensions.Y, targetDimensions.Y)
	and proportionMatches(predictedDimensions.Z, targetDimensions.Z),
	"The model proportions do not match Vesper Cathedral. Check selection, export orientation, and added meshes; no changes were made.")

local savedPivot = model:GetPivot()
local savedScale = model:GetScale()
local desiredScale = savedScale * resizeFactor
assert(finite(desiredScale) and desiredScale > 0, "Invalid target model scale.")
local recording = ChangeHistoryService:TryBeginRecording("VesperCathedralSetup", "Set up Vesper Cathedral")
assert(recording, "Studio could not begin an undo recording. Finish the active editing operation and retry.")

local newSetup
local ok, problem = xpcall(function()
	-- Detach the old owned folder during normalization; it is retained by Studio's
	-- undo history rather than destroyed, so undo can restore its exact contents.
	if previousSetup then
		previousSetup.Parent = nil
	end
	model:ScaleTo(desiredScale)
	model:PivotTo(savedPivot)
	local boundsFrame, finalDimensions = visualBounds()
	assert(proportionMatches(finalDimensions.X, targetDimensions.X)
		and proportionMatches(finalDimensions.Y, targetDimensions.Y)
		and proportionMatches(finalDimensions.Z, targetDimensions.Z), "Scale verification failed.")
	assert(math.abs(finalDimensions.X - targetDimensions.X) <= math.max(0.01, targetDimensions.X * 0.0001),
		"Studio did not retain the requested width.")

	newSetup = Instance.new("Folder")
	newSetup.Name = FOLDER_NAME
	newSetup:SetAttribute(OWNER_ATTRIBUTE, OWNER)
	newSetup:SetAttribute("SourceWidthStuds", targetDimensions.X)
	newSetup:SetAttribute("LocalLightsEnabled", ENABLE_LOCAL_LIGHTS)

	local function newInvisiblePart(name)
		local part = Instance.new("Part")
		part.Name = name
		part:SetAttribute(OWNER_ATTRIBUTE, OWNER)
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end
	for _, spec in ipairs(colliderSpecs) do
		local part = newInvisiblePart(spec.name)
		part.CanCollide = true
		part.CanQuery = true
		part.Size = spec.size
		part.CFrame = boundsFrame * CFrame.new(spec.position - sourceCenter)
			* CFrame.Angles(spec.rotation.X, spec.rotation.Y, spec.rotation.Z)
		part.Parent = newSetup
	end
	if ENABLE_LOCAL_LIGHTS then
		for _, spec in ipairs(lightSpecs) do
			local part = newInvisiblePart(spec.name)
			part.CanCollide = false
			part.CanQuery = false
			part.Size = Vector3.new(0.1, 0.1, 0.1)
			part.CFrame = boundsFrame * CFrame.new(spec.position - sourceCenter)
			local light = Instance.new("PointLight")
			light.Name = "LocalLight"
			light:SetAttribute(OWNER_ATTRIBUTE, OWNER)
			light.Color = spec.color
			light.Range = spec.range
			light.Brightness = spec.brightness
			light.Shadows = false
			light.Parent = part
			part.Parent = newSetup
		end
	end
	for _, part in ipairs(visuals) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
	end
	newSetup.Parent = model
	model:PivotTo(savedPivot)
end, debug.traceback)

if not ok then
	local restored, restoreProblem = pcall(function()
		if newSetup then newSetup:Destroy() end
		model:ScaleTo(savedScale)
		model:PivotTo(savedPivot)
		for part, values in pairs(savedVisuals) do
			part.Anchored = values.Anchored
			part.CanCollide = values.CanCollide
			part.CanTouch = values.CanTouch
		end
		if previousSetup then previousSetup.Parent = model end
		model:PivotTo(savedPivot)
	end)
	-- If restoration fails, keep the recording available as a user Undo step.
	ChangeHistoryService:FinishRecording(recording,
		if restored then Enum.FinishRecordingOperation.Cancel else Enum.FinishRecordingOperation.Commit)
	if not restored then
		warn("Automatic restoration failed; use Undo before continuing: " .. tostring(restoreProblem))
	end
	error("Cathedral setup failed: " .. tostring(problem))
end

ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
print(string.format("Vesper Cathedral ready: %d visual meshes, %d colliders, %d local lights; width %.2f studs. Undo restores the previous model state.",
	#visuals, #colliderSpecs, if ENABLE_LOCAL_LIGHTS then #lightSpecs else 0, targetDimensions.X))
print("Walk-test entrance, nave, aisles, and altar steps in a separate test place before integrating into a game. Nothing was saved or published.")
