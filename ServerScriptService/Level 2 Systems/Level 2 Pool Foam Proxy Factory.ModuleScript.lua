--!strict
-- Resolves either of the two replaceable final templates, or creates a small
-- anchored Part-only proxy. Nothing is parented until construction succeeds.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 2 Pool Foam Configuration"))

local Factory = {}

export type CreateOptions = {
	CFrame: CFrame?,
	Pivot: CFrame?,
	Name: string?,
	AssetsFolder: Instance?,
}

local BLOOM_COLOR = Color3.fromRGB(180, 221, 216)
local BLOOM_LIGHT = Color3.fromRGB(226, 244, 236)
local BLOOM_CORE = Color3.fromRGB(83, 174, 173)
local SPIRE_COLOR = Color3.fromRGB(139, 181, 187)
local SPIRE_LIGHT = Color3.fromRGB(203, 224, 220)
local SPIRE_CORE = Color3.fromRGB(59, 133, 146)

local function finiteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function normalizeString(value: any): string
	if type(value) ~= "string" then
		return ""
	end
	return string.lower((string.gsub(value, "%s+", "")))
end

function Factory.NormalizeSlot(slot: any): any?
	if type(slot) == "table" and type(slot.Id) == "string" then
		slot = slot.Id
	end

	if type(slot) == "number" then
		slot = if slot == 1 then "Primary" elseif slot == 2 then "Secondary" else nil
	end

	local key = normalizeString(slot)
	if key == "primary" or key == "first" or key == "a" or key == "1" then
		return Configuration.Slots.Primary
	elseif key == "secondary" or key == "second" or key == "b" or key == "2" then
		return Configuration.Slots.Secondary
	end

	return nil
end

local function resolveAssetsFolder(provided: Instance?): Instance?
	if provided ~= nil then
		return provided
	end
	return ServerStorage:FindFirstChild(Configuration.AssetFolderName)
end

function Factory.ResolveTemplate(slot: any, assetsFolder: Instance?): Model?
	local slotConfiguration = Factory.NormalizeSlot(slot)
	if slotConfiguration == nil then
		return nil
	end

	local folder = resolveAssetsFolder(assetsFolder)
	if folder == nil then
		return nil
	end

	local candidate = folder:FindFirstChild(slotConfiguration.TemplateName)
	if candidate ~= nil and candidate:IsA("Model") then
		return candidate
	end
	return nil
end

local function findRoot(model: Model): BasePart?
	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	local namedRoot = model:FindFirstChild("HumanoidRootPart", true)
	if namedRoot ~= nil and namedRoot:IsA("BasePart") then
		return namedRoot
	end

	local alternateRoot = model:FindFirstChild("Root", true)
	if alternateRoot ~= nil and alternateRoot:IsA("BasePart") then
		return alternateRoot
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function configureRoot(root: BasePart)
	root.Anchored = Configuration.KeepAnchored
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.Massless = true
	root.RootPriority = 127
end

local function sanitizeTemplateClone(model: Model): boolean
	local root = findRoot(model)
	if root == nil then
		return false
	end
	model.PrimaryPart = root

	-- A final Motor6D rig keeps only its root anchored so authored animation can
	-- move the connected pieces. Non-rig templates remain fully anchored.
	local hasMotorRig = model:FindFirstChildWhichIsA("Motor6D", true) ~= nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.Anchored = Configuration.KeepAnchored and (not hasMotorRig or descendant == root)
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			-- Templates are visual assets; encounter behavior has one server owner.
			descendant.Enabled = false
		end
	end
	configureRoot(root)
	return true
end

local function createRoot(model: Model, size: Vector3): Part
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = size
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Color = Color3.new(0, 0, 0)
	root.CastShadow = false
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	configureRoot(root)
	model.PrimaryPart = root
	return root
end

local function createVisualPart(
	model: Model,
	name: string,
	size: Vector3,
	localCFrame: CFrame,
	color: Color3,
	transparency: number,
	shape: Enum.PartType,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = localCFrame
	part.Color = color
	part.Transparency = transparency
	part.Shape = shape
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute(Configuration.Attributes.ProxyVisual, true)
	part.Parent = model
	return part
end

local function buildBloom(): Model
	local model = Instance.new("Model")
	model.Name = "Pool Foam Primary Proxy"
	createRoot(model, Vector3.new(7.5, 4.8, 6.5))

	createVisualPart(model, "Body", Vector3.new(6.6, 3.0, 5.2), CFrame.new(0, -0.45, 0), BLOOM_COLOR, 0.08, Enum.PartType.Ball, nil)
	createVisualPart(model, "Crown", Vector3.new(4.2, 2.8, 3.7), CFrame.new(-0.35, 1.0, -0.1), BLOOM_LIGHT, 0.12, Enum.PartType.Ball, nil)
	createVisualPart(model, "LeftLobe", Vector3.new(2.8, 2.4, 2.9), CFrame.new(-2.7, 0.35, 0.2), BLOOM_LIGHT, 0.11, Enum.PartType.Ball, nil)
	createVisualPart(model, "RightLobe", Vector3.new(2.5, 2.0, 2.6), CFrame.new(2.75, -0.15, -0.45), BLOOM_COLOR, 0.15, Enum.PartType.Ball, nil)
	createVisualPart(model, "BackLobe", Vector3.new(2.4, 2.2, 2.8), CFrame.new(1.25, 0.2, 2.1), BLOOM_LIGHT, 0.16, Enum.PartType.Ball, nil)
	createVisualPart(model, "FrontLobe", Vector3.new(2.9, 2.1, 2.1), CFrame.new(-1.15, -0.2, -2.35), BLOOM_COLOR, 0.10, Enum.PartType.Ball, nil)
	createVisualPart(model, "BubbleA", Vector3.new(1.2, 1.2, 1.2), CFrame.new(-1.6, 2.05, 0.35), BLOOM_LIGHT, 0.18, Enum.PartType.Ball, nil)
	createVisualPart(model, "BubbleB", Vector3.new(0.85, 0.85, 0.85), CFrame.new(0.55, 2.1, -0.8), BLOOM_LIGHT, 0.20, Enum.PartType.Ball, nil)
	createVisualPart(model, "BubbleC", Vector3.new(0.65, 0.65, 0.65), CFrame.new(1.45, 1.7, 0.4), BLOOM_LIGHT, 0.24, Enum.PartType.Ball, nil)
	createVisualPart(model, "Core", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0.15, 0.45, -2.5), BLOOM_CORE, 0.06, Enum.PartType.Ball, Enum.Material.Neon)
	return model
end

local function buildSpire(): Model
	local model = Instance.new("Model")
	model.Name = "Pool Foam Secondary Proxy"
	createRoot(model, Vector3.new(4.8, 7.8, 4.8))

	createVisualPart(model, "LowerMass", Vector3.new(4.2, 3.4, 4.0), CFrame.new(0, -1.75, 0), SPIRE_COLOR, 0.08, Enum.PartType.Ball, nil)
	createVisualPart(model, "MiddleMass", Vector3.new(3.1, 3.8, 3.0), CFrame.new(0.15, 0.35, -0.1), SPIRE_LIGHT, 0.12, Enum.PartType.Ball, nil)
	createVisualPart(model, "UpperMass", Vector3.new(2.2, 3.0, 2.2), CFrame.new(-0.2, 2.45, 0.15), SPIRE_COLOR, 0.10, Enum.PartType.Ball, nil)
	createVisualPart(model, "LeftFin", Vector3.new(2.8, 0.7, 1.05), CFrame.new(-2.0, -0.7, 0.15) * CFrame.Angles(0, 0, math.rad(-24)), SPIRE_LIGHT, 0.14, Enum.PartType.Cylinder, nil)
	createVisualPart(model, "RightFin", Vector3.new(2.5, 0.65, 1.0), CFrame.new(1.9, 0.15, -0.2) * CFrame.Angles(0, 0, math.rad(31)), SPIRE_COLOR, 0.12, Enum.PartType.Cylinder, nil)
	createVisualPart(model, "Crest", Vector3.new(1.25, 1.25, 1.25), CFrame.new(0.3, 3.75, 0), SPIRE_LIGHT, 0.17, Enum.PartType.Ball, nil)
	createVisualPart(model, "SatelliteA", Vector3.new(0.75, 0.75, 0.75), CFrame.new(-1.5, 2.6, 0.55), SPIRE_LIGHT, 0.21, Enum.PartType.Ball, nil)
	createVisualPart(model, "SatelliteB", Vector3.new(0.55, 0.55, 0.55), CFrame.new(1.2, 3.0, -0.4), SPIRE_LIGHT, 0.25, Enum.PartType.Ball, nil)
	createVisualPart(model, "Core", Vector3.new(0.85, 1.9, 0.85), CFrame.new(0, 0.7, -1.45), SPIRE_CORE, 0.04, Enum.PartType.Ball, Enum.Material.Neon)
	return model
end

local function buildProxy(slotConfiguration: any): Model
	if slotConfiguration.ProxyStyle == "Spire" then
		return buildSpire()
	end
	return buildBloom()
end

local function applyMetadata(model: Model, slotConfiguration: any, isTemporaryProxy: boolean)
	model:SetAttribute(Configuration.Attributes.Slot, slotConfiguration.Id)
	model:SetAttribute(Configuration.Attributes.TemporaryProxy, isTemporaryProxy)
	model:SetAttribute(Configuration.Attributes.FactoryOwned, true)
	model:SetAttribute(Configuration.Attributes.Profile, slotConfiguration.Profile)
	model:SetAttribute(Configuration.Attributes.AnimationState, "Idle")
	model:SetAttribute(Configuration.Attributes.ResolvedAnimationState, "Idle")
	model:SetAttribute(Configuration.Attributes.MotionState, "Idle")
	model:SetAttribute(Configuration.Attributes.ActionSerial, 0)
	model:SetAttribute("PoolFoamSourceTemplate", slotConfiguration.TemplateName)
	CollectionService:AddTag(model, Configuration.GenericHostileTag)
	CollectionService:AddTag(model, Configuration.SpecificTag)
end

function Factory.IsTemporaryProxy(model: Instance?): boolean
	return model ~= nil
		and model:IsA("Model")
		and model:GetAttribute(Configuration.Attributes.TemporaryProxy) == true
end

function Factory.Create(slot: any, parent: Instance?, options: CreateOptions?): Model
	local slotConfiguration = Factory.NormalizeSlot(slot)
	if slotConfiguration == nil then
		error(string.format("Unknown Pool Foam slot: %s", tostring(slot)), 2)
	end

	local createOptions = options or {}
	local template = Factory.ResolveTemplate(slotConfiguration, createOptions.AssetsFolder)
	local model: Model
	local isTemporaryProxy = false

	if template ~= nil then
		model = template:Clone()
		if not sanitizeTemplateClone(model) then
			model:Destroy()
			model = buildProxy(slotConfiguration)
			isTemporaryProxy = true
		end
	else
		model = buildProxy(slotConfiguration)
		isTemporaryProxy = true
	end

	model.Name = createOptions.Name or string.format("Pool Foam %s", slotConfiguration.Id)
	applyMetadata(model, slotConfiguration, isTemporaryProxy)
	local groundOffset = model:GetAttribute("PoolFoamGroundOffset")
	if not finiteNumber(groundOffset) or groundOffset < 0 then
		groundOffset = model:GetAttribute("GroundOffset")
	end
	if not finiteNumber(groundOffset) or groundOffset < 0 then
		local boundsCFrame, boundsSize = model:GetBoundingBox()
		local bottomY = boundsCFrame.Position.Y - boundsSize.Y * .5
		groundOffset = math.max(0, model.PrimaryPart.Position.Y - bottomY)
	end
	model:SetAttribute("PoolFoamGroundOffset", math.clamp(groundOffset, 0, 24))

	local pivot = createOptions.CFrame or createOptions.Pivot
	if pivot ~= nil then
		model:PivotTo(pivot)
	end
	model.Parent = parent
	return model
end

function Factory.Destroy(model: Instance?): boolean
	if model == nil or not model:IsA("Model") then
		return false
	end
	if model:GetAttribute(Configuration.Attributes.FactoryOwned) ~= true then
		return false
	end

	CollectionService:RemoveTag(model, Configuration.GenericHostileTag)
	CollectionService:RemoveTag(model, Configuration.SpecificTag)
	model:Destroy()
	return true
end

return table.freeze(Factory)
