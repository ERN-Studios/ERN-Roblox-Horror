-- Level 2 Round Adapter
-- GameManager's Build/Cleanup contract for the approved, authored Poolrooms.
-- The same map moves between ServerStorage and Workspace; its meshes, lights
-- and Terrain water are never cloned, regenerated or cleared by a round.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Runtime = require(script.Parent:WaitForChild("Level 2 Poolrooms Runtime"))
local Adapter = {}

local WORLD_NAME = "Level 2 Generated World"
local STORED_NAME = "Level2PoolroomsMap"
local COMPAT_ATTRIBUTE = "Level2_CompatibilityMarker"
local LEVEL_ONE_RUNTIME_SCRIPTS = {"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}
local generation = 0
local activeManifest
local runtimeHandle
local levelOneScriptStates

local function isAuthoredMap(object)
	return object ~= nil and object:IsA("Model") and object:GetAttribute("Level2NewMap") == true
end

local function getState()
	local folder = ReplicatedStorage:FindFirstChild("Level 2 State")
	assert(not folder or folder:IsA("Folder"), "Level 2 State must be a Folder")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Level 2 State"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

local function resetState(folder)
	folder:SetAttribute("Level2_Phase", "IDLE")
	folder:SetAttribute("Level2_LightingMode", "OFF")
	folder:SetAttribute("Level2_PumpProgress", 0)
	folder:SetAttribute("Level2_PoolSlideEnabled", false)
	folder:SetAttribute("Level2_PoolSlideState", "DISABLED")
	folder:SetAttribute("Level2_PoolSlidePhase", "DISABLED")
	for _, name in ipairs({"Level2_Error", "Level2_HallCount", "Level2_Seed", "Level2_RequestedSeed",
		"Level2_SeedPinned", "Level2_RandomRecoverySeed", "Level2_ResolvedSeed", "Level2_GenerationAttempt",
		"Level2_UsedFallback", "Level2_FallbackBaseSeed", "Level2_PoolSlideLastError", "Level2_LayoutSeconds",
		"Level2_BuildSeconds", "Level2_WorldDescendants"}) do
		folder:SetAttribute(name, nil)
	end
	for pump = 1, 3 do
		folder:SetAttribute("Level2_PumpStartedAt" .. pump, nil)
		folder:SetAttribute("Level2_PumpActivatorUserId" .. pump, nil)
		folder:SetAttribute("Level2_PumpActivatorPosition" .. pump, nil)
	end
end

local function isolateLevelOneRuntime()
	levelOneScriptStates = {}
	for _, name in ipairs(LEVEL_ONE_RUNTIME_SCRIPTS) do
		local object = ServerScriptService:FindFirstChild(name, true)
		if object and object:IsA("BaseScript") then
			levelOneScriptStates[object] = object.Enabled
			object.Enabled = false
		end
	end
end

local function restoreLevelOneRuntime()
	if not levelOneScriptStates then return end
	for object, enabled in pairs(levelOneScriptStates) do
		if object.Parent then object.Enabled = enabled end
	end
	levelOneScriptStates = nil
end

local function destroyCompatibilityObjects()
	for _, object in ipairs(workspace:GetChildren()) do
		if object:GetAttribute(COMPAT_ATTRIBUTE) == true then object:Destroy() end
	end
end

local function storeMap()
	local world = activeManifest and activeManifest.World or workspace:FindFirstChild(WORLD_NAME)
	if not isAuthoredMap(world) or world.Parent ~= workspace then return end
	local existing = ServerStorage:FindFirstChild(STORED_NAME)
	assert(not existing or existing == world, "Another Level2PoolroomsMap already exists in ServerStorage")
	world.Name = STORED_NAME
	world.Parent = ServerStorage
end

local function buildCompatibility(world, spawn)
	for _, name in ipairs({"Elevator", "MazeStart", "ElevatorSpawn"}) do
		assert(workspace:FindFirstChild(name) == nil, "Level 2 arrival conflicts with Workspace." .. name)
	end
	-- Exported markers stand three studs above their authored floor. Keep the
	-- emergency pad at that floor, facing down the stair core (+Z), rather than
	-- elevating the party onto a platform that bridges the stairs.
	local floor = spawn.Position - Vector3.yAxis * 3
	local frame = CFrame.lookAt(floor - Vector3.yAxis * .1, floor - Vector3.yAxis * .1 + Vector3.zAxis)
	local function part(name, size, cf)
		local object = Instance.new("Part")
		object.Name, object.Size, object.CFrame = name, size, cf
		object.Anchored, object.Transparency = true, 1
		object.CanCollide, object.CanTouch, object.CanQuery = false, false, false
		object.CastShadow = false
		object:SetAttribute(COMPAT_ATTRIBUTE, true)
		return object
	end
	local pad = part("ElevatorSpawn", Vector3.new(4, .2, 4), frame)
	pad:SetAttribute("Level2NewMap", true)
	-- Measured floor slots are supplied by the promotion installer. GameManager
	-- uses them instead of its procedural world's seven forward rows.
	local slotCount = world:GetAttribute("Level2ArrivalSlotCount")
	if type(slotCount) == "number" and slotCount == slotCount and slotCount >= 1 then
		slotCount = math.clamp(math.floor(slotCount), 1, 24)
		for index = 1, slotCount do
			local slot = world:GetAttribute("Level2ArrivalSlot" .. index)
			assert(typeof(slot) == "Vector3", "Level 2 arrival floor slot " .. index .. " is missing")
			pad:SetAttribute("Level2ArrivalSlot" .. index, slot)
		end
		pad:SetAttribute("Level2ArrivalSlotCount", slotCount)
	end
	pad.Parent = workspace
	local start = part("MazeStart", Vector3.new(4, .2, 4), frame)
	start.Parent = workspace
	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute(COMPAT_ATTRIBUTE, true)
	local hidden = CFrame.new(floor.X, -520, floor.Z)
	part("DoorL", Vector3.new(1, 8, 4), hidden * CFrame.new(0, 0, -2)).Parent = elevator
	part("DoorR", Vector3.new(1, 8, 4), hidden * CFrame.new(0, 0, 2)).Parent = elevator
	elevator.Parent = workspace
	return {Elevator = elevator, ElevatorSpawn = pad, MazeStart = start}
end

function Adapter.GetManifest()
	return activeManifest
end

function Adapter.Cleanup()
	-- Stop first so the stored model cannot keep killing or completing players.
	-- Stop(nil) also recovers a partially started or persisted runtime session.
	local stopped, stopError = pcall(Runtime.Stop, runtimeHandle)
	runtimeHandle = nil
	destroyCompatibilityObjects()
	local stored, storeError = pcall(storeMap)
	activeManifest = nil
	restoreLevelOneRuntime()
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level2NewMapActive", false)
	workspace:SetAttribute("Level2Pumps", 0)
	workspace:SetAttribute("Level2PumpGoal", 0)
	workspace:SetAttribute("Level2ExitPowered", false)
	workspace:SetAttribute("Level2FoamLethal", false)
	workspace:SetAttribute("Level2_ExitPosition", nil)
	workspace:SetAttribute("Level2LightingOwnedByController", false)
	workspace:SetAttribute("Level2BlenderPreviewActive", false)
	if workspace:GetAttribute("SelectedLevel") == 2 then workspace:SetAttribute("SelectedLevel", 1) end
	resetState(getState())
	if not stopped then error("[Level 2] runtime cleanup failed: " .. tostring(stopError), 0) end
	if not stored then error("[Level 2] map storage failed: " .. tostring(storeError), 0) end
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1
	local folder = getState()
	folder:SetAttribute("Level2_Phase", "BUILDING_WORLD")
	folder:SetAttribute("Level2_Generation", generation)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_2_BUILDING_WORLD")
	isolateLevelOneRuntime()
	local began = os.clock()
	local ok, result = xpcall(function()
		local world = ServerStorage:FindFirstChild(STORED_NAME)
		assert(isAuthoredMap(world), "ServerStorage.Level2PoolroomsMap approved map is missing")
		assert(workspace:FindFirstChild(WORLD_NAME) == nil, "Another Level 2 world is already in Workspace")
		local markers = world:FindFirstChild("Markers")
		local spawn = markers and markers:FindFirstChild("SPAWN")
		assert(spawn and spawn:IsA("BasePart"), "Level 2 Poolrooms has no SPAWN marker")
		world.Name = WORLD_NAME
		world.Parent = workspace
		world:SetAttribute("Level2_Generation", generation)
		activeManifest = {World = world, Generation = generation}
		-- Preparing a missing slide/safe marker raycasts real Workspace floors.
		-- Adopt first and record ownership before any preparation can fail.
		Runtime.Prepare(world)
		activeManifest.Arrival = buildCompatibility(world, spawn)
		workspace:SetAttribute("SelectedLevel", 2)
		workspace:SetAttribute("Level2NewMapActive", true)
		workspace:SetAttribute("Level2LightingOwnedByController", false)
		workspace:SetAttribute("Level2ExitPowered", true)
		local exit = markers:FindFirstChild("EXIT")
		workspace:SetAttribute("Level2_ExitPosition", exit and exit:IsA("BasePart") and exit.Position or nil)
		runtimeHandle = Runtime.Start(world)
		assert(runtimeHandle ~= nil, "Level 2 Poolrooms runtime did not start")
		activeManifest.Runtime = runtimeHandle
		folder:SetAttribute("Level2_BuildSeconds", math.round((os.clock() - began) * 100) / 100)
		folder:SetAttribute("Level2_WorldDescendants", #world:GetDescendants())
		folder:SetAttribute("Level2_Phase", "READY")
		folder:SetAttribute("Level2_LightingMode", "NORMAL")
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return world
	end, debug.traceback)
	if not ok then
		local cleaned, cleanupError = pcall(Adapter.Cleanup)
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		folder:SetAttribute("Level2_Phase", "ERROR")
		folder:SetAttribute("Level2_Error", tostring(result))
		if not cleaned then warn("[Level 2] failed-build cleanup: " .. tostring(cleanupError)) end
		error(result, 0)
	end
	return result
end

return Adapter
