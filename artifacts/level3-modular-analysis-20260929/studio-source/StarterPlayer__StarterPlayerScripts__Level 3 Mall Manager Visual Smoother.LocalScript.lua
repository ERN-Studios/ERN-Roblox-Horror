--!strict
-- Interpolates only the Mall Manager's collisionless rendered mesh.
-- Its anchored root, navigation, perception, and attacks remain server-authoritative.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TAG = "Level3HostileEntity"
local REMOTES_FOLDER = "Level 3 Remotes"
local MOTION_EVENT = "MallManagerMotion"

-- Mirrored from the server-only Level 3 Configuration.
local INTERPOLATION_DELAY = 0.065
local MAX_SAMPLES = 8
local LONG_GAP_SECONDS = 0.30

type Sample = {
	Sequence: number,
	ServerTime: number,
	RootCFrame: CFrame,
}

type Entry = {
	Model: Model,
	Root: BasePart,
	Mesh: BasePart,
	Weld: Weld,
	BaseRelative: CFrame,
	OriginalC0: CFrame,
	DisplayRoot: CFrame,
	Samples: {Sample},
	LastSequence: number,
	LastPacketAt: number,
	Generation: number,
	SpawnSerial: number?,
}

local entries: {[Model]: Entry} = {}
local binding: {[Model]: boolean} = {}

local function unbind(model: Model)
	binding[model] = nil
	local entry = entries[model]
	if not entry then return end
	entries[model] = nil
	if entry.Weld.Parent then
		entry.Weld.C0 = entry.OriginalC0
	end
end

local function awaitRig(model: Model): (BasePart?, BasePart?, Weld?)
	local deadline = os.clock() + 5
	while model.Parent and os.clock() < deadline do
		local rootObject = model:FindFirstChild("HumanoidRootPart")
		local meshObject = model:FindFirstChild("char1")
		if rootObject and rootObject:IsA("BasePart")
			and meshObject and meshObject:IsA("BasePart") then
			local weldObject = rootObject:FindFirstChild("MallManagerRootWeld")
			if weldObject and weldObject:IsA("Weld") then
				return rootObject, meshObject, weldObject
			end
		end
		task.wait(0.05)
	end
	return nil, nil, nil
end

local function bind(instance: Instance)
	if not instance:IsA("Model") then return end
	local model = instance :: Model
	if entries[model] or binding[model] then return end
	binding[model] = true
	task.spawn(function()
		local root, mesh, weld = awaitRig(model)
		binding[model] = nil
		if not root or not mesh or not weld
			or not model.Parent
			or not CollectionService:HasTag(model, TAG)
			or entries[model] then
			return
		end
		local initialRoot = root.CFrame
		local originalC0 = weld.C0
		entries[model] = {
			Model = model,
			Root = root,
			Mesh = mesh,
			Weld = weld,
			BaseRelative = originalC0 * weld.C1:Inverse(),
			OriginalC0 = originalC0,
			DisplayRoot = initialRoot,
			Samples = {},
			LastSequence = 0,
			LastPacketAt = os.clock(),
			Generation = tonumber(model:GetAttribute("Level3_Generation")) or -1,
			SpawnSerial = nil,
		}
	end)
end

local function handleMotion(
	modelValue: any,
	generationValue: any,
	spawnSerialValue: any,
	sequenceValue: any,
	serverTimeValue: any,
	rootCFrameValue: any,
	hardSnapValue: any
)
	if typeof(modelValue) ~= "Instance" or not modelValue:IsA("Model") then return end
	if type(generationValue) ~= "number"
		or type(spawnSerialValue) ~= "number"
		or type(sequenceValue) ~= "number"
		or type(serverTimeValue) ~= "number"
		or typeof(rootCFrameValue) ~= "CFrame" then
		return
	end
	local model = modelValue :: Model
	if not model.Parent or not CollectionService:HasTag(model, TAG) then return end
	local entry = entries[model]
	if not entry then
		bind(model)
		return
	end
	if entry.Generation < 0 then
		entry.Generation = generationValue
	elseif generationValue ~= entry.Generation then
		return
	end
	local replicatedSerial = model:GetAttribute("Level3_MallManagerSpawnSerial")
	if type(replicatedSerial) == "number" and replicatedSerial ~= spawnSerialValue then return end
	if entry.SpawnSerial == nil then
		entry.SpawnSerial = spawnSerialValue
	elseif entry.SpawnSerial ~= spawnSerialValue then
		return
	end
	if sequenceValue <= entry.LastSequence then return end
	local samples = entry.Samples
	local previous = samples[#samples]
	if previous and serverTimeValue <= previous.ServerTime then return end
	entry.LastSequence = sequenceValue
	entry.LastPacketAt = os.clock()
	local longGap = previous ~= nil
		and serverTimeValue - previous.ServerTime >= LONG_GAP_SECONDS
	if hardSnapValue == true or longGap then
		table.clear(samples)
		entry.DisplayRoot = rootCFrameValue
	end
	table.insert(samples, {
		Sequence = sequenceValue,
		ServerTime = serverTimeValue,
		RootCFrame = rootCFrameValue,
	})
	while #samples > MAX_SAMPLES do table.remove(samples, 1) end
end

for _, instance in ipairs(CollectionService:GetTagged(TAG)) do bind(instance) end
CollectionService:GetInstanceAddedSignal(TAG):Connect(bind)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	if instance:IsA("Model") then unbind(instance) end
end)

task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER)
	local candidate = folder:WaitForChild(MOTION_EVENT)
	if not candidate:IsA("UnreliableRemoteEvent") then
		warn("[Level 3 Mall Manager] motion remote has the wrong class")
		return
	end
	candidate.OnClientEvent:Connect(handleMotion)
end)

RunService.RenderStepped:Connect(function()
	local renderTime = workspace:GetServerTimeNow() - INTERPOLATION_DELAY
	local localNow = os.clock()
	for model, entry in pairs(entries) do
		if not model.Parent or not entry.Root.Parent
			or not entry.Mesh.Parent or not entry.Weld.Parent then
			unbind(model)
			continue
		end
		local samples = entry.Samples
		while #samples >= 3 and samples[2].ServerTime <= renderTime do
			table.remove(samples, 1)
		end
		if localNow - entry.LastPacketAt >= LONG_GAP_SECONDS then
			-- Remote failure fallback only. Normal rendering never follows
			-- raw replicated steps and never predicts ahead.
			table.clear(samples)
			entry.DisplayRoot = entry.Root.CFrame
		elseif #samples == 1 then
			entry.DisplayRoot = samples[1].RootCFrame
		elseif #samples >= 2 then
			local older = samples[1]
			local newer = samples[2]
			if renderTime <= older.ServerTime then
				entry.DisplayRoot = older.RootCFrame
			elseif renderTime >= newer.ServerTime then
				-- Hold the latest sample; never extrapolate and recoil.
				entry.DisplayRoot = newer.RootCFrame
			else
				local duration = math.max(newer.ServerTime - older.ServerTime, 1 / 240)
				local alpha = math.clamp((renderTime - older.ServerTime) / duration, 0, 1)
				entry.DisplayRoot = older.RootCFrame:Lerp(newer.RootCFrame, alpha)
			end
		end
		local desiredMesh = entry.DisplayRoot * entry.BaseRelative
		entry.Weld.C0 = entry.Root.CFrame:ToObjectSpace(desiredMesh * entry.Weld.C1)
	end
end)
