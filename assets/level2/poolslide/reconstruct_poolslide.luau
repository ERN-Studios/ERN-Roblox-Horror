-- Offline recovery helper. This module is NOT a runtime game script.
-- Build() returns detached instances; Install() explicitly installs into Edit.
-- It never publishes assets, replaces an existing template, or runs scripts.
-- Mesh downloads require access to the original ERN Roblox Studios assets.
-- JSON recovery has NOT been visually round-trip tested in Studio; retain the
-- original FBX and a saved place as the definitive skin-binding fallback.
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Recovery = {}
local TEMPLATE_NAME = "Level 2 Pool Slide Template"
local TARGET_PATH = "ServerStorage.Level2Assets." .. TEMPLATE_NAME
local PLACE_ID = 131311258779917
local CLASS_PROPERTIES = {
	Model = {Pivot = true, PrimaryPart = true},
	Part = {}, MeshPart = {MeshId = true, TextureID = true, DoubleSided = true,
		CollisionFidelity = true, RenderFidelity = true},
	Bone = {CFrame = true, Transform = true},
	Motor6D = {C0 = true, C1 = true, Transform = true, Part0 = true, Part1 = true, Enabled = true},
	CFrameValue = {Value = true}, AnimationController = {}, Folder = {},
}
local BASE_PROPERTIES = {CFrame = true, Size = true, Color = true, Material = true,
	Anchored = true, CanCollide = true, CanTouch = true, CanQuery = true,
	CastShadow = true, Massless = true, Reflectance = true, Transparency = true}
local CFRAMES = {CFrame = true, Transform = true, C0 = true, C1 = true, Value = true, Pivot = true}
local REFERENCES = {PrimaryPart = true, Part0 = true, Part1 = true}
local BOOLEANS = {Anchored = true, CanCollide = true, CanTouch = true,
	CanQuery = true, CastShadow = true, Massless = true, DoubleSided = true, Enabled = true}
local CLIP_NAMES = {
	["Level 2 Pool Slide Idle Keyframes"] = true,
	["Level 2 Pool Slide Walk Keyframes"] = true,
	["Level 2 Pool Slide Run Keyframes"] = true,
}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function numbers(value, count)
	assert(type(value) == "table" and #value == count, "invalid numeric array length")
	for _, number in ipairs(value) do assert(finite(number), "nonfinite numeric array") end
	return value
end

local function frame(value)
	return CFrame.new(table.unpack(numbers(value, 12)))
end

local function vector(value)
	return Vector3.new(table.unpack(numbers(value, 3)))
end

local function enumValue(enumType, name)
	assert(type(name) == "string", "enum name must be a string")
	local item = enumType[name]
	assert(item, "unknown enum value: " .. name)
	return item
end

local function decode(value)
	return type(value) == "string" and HttpService:JSONDecode(value) or value
end

local function validateBundle(bundle)
	assert(type(bundle) == "table" and bundle.schema == "poolslide-recovery-bundle-v1", "wrong recovery schema")
	local template = bundle.template
	assert(template.schema == "poolslide-template-reconstruction-v1" and template.targetPath == TARGET_PATH,
		"unexpected template schema or target")
	local records = template.records
	assert(type(records) == "table" and #records == 138, "expected the captured 138-instance template")
	local recordById, roots, bones = {}, {}, {}
	for _, record in ipairs(records) do
		assert(finite(record.id) and record.id % 1 == 0 and record.id > 0 and not recordById[record.id], "invalid/duplicate ID")
		assert(CLASS_PROPERTIES[record.className], "unsupported class: " .. tostring(record.className))
		assert(type(record.name) == "string" and record.name ~= "", "missing name")
		assert(type(record.properties) == "table" and type(record.attributes) == "table", "missing instance data")
		recordById[record.id] = record
		if record.parent == nil then table.insert(roots, record) end
		if record.className == "Bone" then
			assert(not bones[record.name], "unexpected duplicated Bone name")
			bones[record.name] = record
		end
		for property, value in pairs(record.properties) do
			assert(CLASS_PROPERTIES[record.className][property]
				or ((record.className == "Part" or record.className == "MeshPart") and BASE_PROPERTIES[property]),
				"unsupported property: " .. record.className .. "." .. property)
			if CFRAMES[property] then numbers(value, 12)
			elseif property == "Size" or property == "Color" then numbers(value, 3)
			elseif BOOLEANS[property] then assert(type(value) == "boolean", "expected boolean: " .. property)
			elseif property == "Transparency" or property == "Reflectance" then assert(finite(value), "expected number") end
		end
		for key, value in pairs(record.attributes) do
			assert(type(key) == "string" and (type(value) == "string" or type(value) == "boolean" or finite(value)),
				"unsupported attribute encoding")
		end
	end
	assert(#roots == 1 and roots[1].className == "Model" and roots[1].name == TEMPLATE_NAME, "invalid root")
	for _, record in ipairs(records) do
		local seen, cursor = {}, record
		while cursor.parent ~= nil do
			assert(not seen[cursor.id], "parent cycle")
			seen[cursor.id] = true
			cursor = assert(recordById[cursor.parent], "missing parent ID")
		end
		for property in pairs(REFERENCES) do
			local id = record.properties[property]
			if id ~= nil then
				local target = assert(recordById[id], "missing reference ID")
				assert(target.className == "Part" or target.className == "MeshPart", "reference must target a BasePart")
			end
		end
	end
	assert(type(bundle.animations) == "table" and #bundle.animations == 3, "expected three animations")
	local names = {}
	for _, clip in ipairs(bundle.animations) do
		assert(CLIP_NAMES[clip.name] and not names[clip.name], "unexpected/duplicate clip")
		names[clip.name] = true
		assert(type(clip.frames) == "table" and #clip.frames > 0 and type(clip.parents) == "table", "invalid clip")
		local previousTime = -math.huge
		for _, values in ipairs(clip.frames) do
			assert(finite(values[1]) and values[1] >= 0 and values[1] > previousTime, "unordered clip frames")
			previousTime = values[1]
			assert(#values[2] == 24, "expected 24 Bone poses per frame")
			local seen = {}
			for _, pose in ipairs(values[2]) do
				assert(#pose == 8 and bones[pose[1]] and not seen[pose[1]], "unexpected Bone pose")
				seen[pose[1]] = true
				for index = 2, 8 do assert(finite(pose[index]), "invalid pose component") end
				local record = bones[pose[1]]
				local parent = recordById[record.parent]
				local expectedParent = parent and parent.className == "Bone" and parent.name or nil
				assert(clip.parents[pose[1]] == expectedParent, "animation hierarchy differs from captured bind")
			end
		end
	end
	return roots[1].id
end

function Recovery.Build(input)
	local bundle = decode(input)
	local rootId = validateBundle(bundle)
	local instances, created, sequences, skippedAttributes = {}, {}, {}, {}
	local success, result = xpcall(function()
		for _, record in ipairs(bundle.template.records) do
			local properties = record.properties
			local instance
			if record.className == "MeshPart" then
				assert(type(properties.MeshId) == "string" and properties.MeshId:match("^rbxassetid://%d+$"), "invalid mesh ID")
				instance = AssetService:CreateMeshPartAsync(Content.fromUri(properties.MeshId), {
					CollisionFidelity = enumValue(Enum.CollisionFidelity, properties.CollisionFidelity),
					RenderFidelity = enumValue(Enum.RenderFidelity, properties.RenderFidelity),
				})
				assert(instance and instance:IsA("MeshPart"), "mesh download failed")
				-- These are newly-created import defaults, never existing user data.
				-- Replay the captured hierarchy below instead of duplicating bones.
				for _, child in ipairs(instance:GetChildren()) do child:Destroy() end
			else instance = Instance.new(record.className) end
			table.insert(created, instance)
			instances[record.id] = instance
			instance.Name = record.name
			if instance:IsA("BasePart") then instance.CanCollide = false end
			for property, value in pairs(properties) do
				if REFERENCES[property] or property == "Pivot" or property == "MeshId"
					or property == "CollisionFidelity" or property == "RenderFidelity" then continue end
				if CFRAMES[property] then instance[property] = frame(value)
				elseif property == "Size" then instance.Size = vector(value)
				elseif property == "Color" then instance.Color = Color3.new(table.unpack(numbers(value, 3)))
				elseif property == "Material" then instance.Material = enumValue(Enum.Material, value)
				elseif instance[property] ~= value then instance[property] = value end
			end
			for key, value in pairs(record.attributes) do
				-- Reserved importer metadata is archived but not required to animate.
				if key:sub(1, 4) == "RBX_" then table.insert(skippedAttributes, record.name .. "." .. key)
				else instance:SetAttribute(key, value) end
			end
		end
		for _, record in ipairs(bundle.template.records) do
			if record.parent ~= nil then instances[record.id].Parent = instances[record.parent] end
		end
		for _, record in ipairs(bundle.template.records) do
			for property in pairs(REFERENCES) do
				local id = record.properties[property]
				if id ~= nil then instances[record.id][property] = instances[id] end
			end
		end
		local root = instances[rootId]
		for _, record in ipairs(bundle.template.records) do
			if record.id == rootId then root:PivotTo(frame(record.properties.Pivot)) break end
		end
		assert(#root:GetDescendants() == 137, "reconstruction instance count mismatch")
		for _, clip in ipairs(bundle.animations) do
			local sequence = Instance.new("KeyframeSequence")
			table.insert(created, sequence)
			sequence.Name = clip.name
			sequence.Loop = clip.looped == true
			sequence.Priority = enumValue(Enum.AnimationPriority, clip.priority)
			for _, frameData in ipairs(clip.frames) do
				local keyframe = Instance.new("Keyframe")
				keyframe.Time = frameData[1]
				keyframe.Parent = sequence
				local poses = {}
				for _, values in ipairs(frameData[2]) do
					local pose = Instance.new("Pose")
					pose.Name = values[1]
					pose.CFrame = CFrame.new(table.unpack(values, 2, 8))
					pose.Weight = 1
					pose.EasingStyle = Enum.PoseEasingStyle.Linear
					pose.EasingDirection = Enum.PoseEasingDirection.InOut
					pose.Parent = keyframe -- parent immediately for error cleanup
					poses[pose.Name] = pose
				end
				for name, pose in pairs(poses) do
					local parent = clip.parents[name]
					pose.Parent = parent and poses[parent] or keyframe
				end
			end
			table.insert(sequences, sequence)
		end
		return {Template = root, Sequences = sequences, SkippedImporterAttributes = skippedAttributes}
	end, debug.traceback)
	if not success then
		for _, instance in ipairs(created) do instance:Destroy() end
		error(result, 0)
	end
	return result
end

function Recovery.Install(input)
	assert(not RunService:IsRunning(), "recovery installation requires Studio Edit mode")
	assert(game.PlaceId == PLACE_ID, "wrong place; inspect and adapt deliberately for a new recovery place")
	local function destinationsAvailable()
		local server = ServerStorage:FindFirstChild("Level2Assets")
		local replicated = ReplicatedStorage:FindFirstChild("Level 2 Assets")
		assert(not server or server:IsA("Folder"), "Level2Assets must be a Folder")
		assert(not replicated or replicated:IsA("Folder"), "Level 2 Assets must be a Folder")
		assert(not server or not server:FindFirstChild(TEMPLATE_NAME), "template already exists; refusing overwrite")
		for name in pairs(CLIP_NAMES) do
			assert(not replicated or not replicated:FindFirstChild(name), "keyframes already exist; refusing overwrite")
		end
		return server, replicated
	end
	destinationsAvailable()
	local built = Recovery.Build(input) -- yields while downloading, still detached
	local newFolders = {}
	local ok, failure = xpcall(function()
		assert(not RunService:IsRunning() and game.PlaceId == PLACE_ID, "Studio changed during recovery")
		local server, replicated = destinationsAvailable() -- recheck after all yields
		if not server then
			server = Instance.new("Folder")
			server.Name = "Level2Assets"
			table.insert(newFolders, server)
			server.Parent = ServerStorage
		end
		if not replicated then
			replicated = Instance.new("Folder")
			replicated.Name = "Level 2 Assets"
			table.insert(newFolders, replicated)
			replicated.Parent = ReplicatedStorage
		end
		built.Template.Parent = server
		for _, sequence in ipairs(built.Sequences) do sequence.Parent = replicated end
	end, debug.traceback)
	if not ok then
		built.Template:Destroy()
		for _, sequence in ipairs(built.Sequences) do sequence:Destroy() end
		for _, folder in ipairs(newFolders) do folder:Destroy() end
		error(failure, 0)
	end
	return built
end

return Recovery
