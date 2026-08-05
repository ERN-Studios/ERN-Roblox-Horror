-- CollectionService bootstrap for independent Level 2 hostile controllers.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Profiles = require(ServerScriptService:WaitForChild("Level2EntityProfiles"))
local Controller = require(ServerScriptService:WaitForChild("Level2EntityController"))
local TAG = Profiles.TagName

-- Level 1 owns the richer noise response, but its controller is disabled in
-- Level 2. Keep the shared reporter drained here so footsteps and party audio
-- never exhaust the RemoteEvent queue or spam Studio output.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local reportNoise = remotes:WaitForChild("ReportNoise")
reportNoise.OnServerEvent:Connect(function(player, loudness, position)
	if typeof(loudness) == "number" then
		player:SetAttribute("LastReportedNoise", math.clamp(loudness, 0, 1))
	end
	if typeof(position) == "Vector3" then
		player:SetAttribute("LastReportedNoisePosition", position)
	end
end)

local function isLegacyHostile(instance)
	if not instance:IsA("Model") then return false end
	if instance.Name == "PoolPipeEntity" then
		return true
	end
	local profile = instance:GetAttribute("EntityProfile")
	return profile == "PoolPipe"
end

local function bind(instance)
	if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
		Controller.Start(instance)
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(bind)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
	if instance:IsA("Model") then
		Controller.Stop(instance)
	end
end)

workspace.DescendantAdded:Connect(function(instance)
	if not isLegacyHostile(instance) then return end
	if not CollectionService:HasTag(instance, TAG) then
		CollectionService:AddTag(instance, TAG)
	end
	-- Generators may tag a complete entity before parenting it to Workspace.
	-- The tag signal then fires too early, so bind once the parent operation settles.
	task.defer(bind, instance)
end)

for _, instance in ipairs(workspace:GetDescendants()) do
	if isLegacyHostile(instance) and not CollectionService:HasTag(instance, TAG) then
		CollectionService:AddTag(instance, TAG)
	end
end
for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
	bind(instance)
end

-- Keep registration resilient when map generators destroy/rebuild tagged models
-- in the same frame. Start is idempotent, so this is cheap insurance.
task.spawn(function()
	while true do
		task.wait(1)
		for _, instance in ipairs(CollectionService:GetTagged(TAG)) do
			bind(instance)
		end
	end
end)
