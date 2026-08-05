local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 2 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 2 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 2 Objective Controller"))

local Adapter = {}
local activeManifest
local generation = 0
local levelOneScriptStates
local storedLevelOneEntity

local LEGACY_LEVEL_TWO_SCRIPTS = {
	"Level2EntityAI",
	"Level2EntityAnimation",
	"Level2EntityKill",
}

local LEVEL_ONE_RUNTIME_SCRIPTS = {
	"EntityAI",
	"EntityAnimation",
	"EntityKill",
	"PuzzleManager",
}

local function getState()
	return ReplicatedStorage:WaitForChild("Level 2 State")
end

local function destroyCompatibilityObjects()
	for _, name in ipairs({"Elevator", "MazeStart", "ElevatorSpawn", "EntityStart"}) do
		local object = workspace:FindFirstChild(name)
		if object and object:GetAttribute("Level2_CompatibilityMarker") == true then object:Destroy()
		elseif object and name == "Elevator" and object:FindFirstChild("Level 2 Arrival Elevator Shell", true) then object:Destroy() end
	end
end

local function isolateLevelOneRuntime()
	levelOneScriptStates = {}
	for _, name in ipairs(LEVEL_ONE_RUNTIME_SCRIPTS) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then
			levelOneScriptStates[object] = object.Enabled
			object.Enabled = false
		end
	end
	local entity = workspace:FindFirstChild("Entity")
	if entity then
		storedLevelOneEntity = entity
		entity.Parent = ServerStorage
		entity.Name = "Level 2 Stored Level 1 Entity"
	end
end

local function restoreLevelOneRuntime()
	if storedLevelOneEntity and storedLevelOneEntity.Parent then
		local existing = workspace:FindFirstChild("Entity")
		if existing and existing ~= storedLevelOneEntity then existing:Destroy() end
		storedLevelOneEntity.Name = "Entity"
		storedLevelOneEntity.Parent = workspace
	end
	storedLevelOneEntity = nil
	for object, enabled in pairs(levelOneScriptStates or {}) do
		if object.Parent then object.Enabled = enabled end
	end
	levelOneScriptStates = nil
end

local function clearOwnedTerrain(manifest)
	local center = manifest and manifest.TerrainCenter or Vector3.new(0, -8, 0)
	local size = manifest and manifest.TerrainSize or Vector3.new(1000, 100, 1000)
	Terrain:FillBlock(CFrame.new(center), size, Enum.Material.Air)
end

function Adapter.Cleanup()
	ObjectiveController.Stop()
	local state = getState()
	state:SetAttribute("Level2_Phase", "CLEANING")
	clearOwnedTerrain(activeManifest)
	if activeManifest and activeManifest.World and activeManifest.World.Parent then activeManifest.World:Destroy() end
	activeManifest = nil
	for _, name in ipairs({"Level 2 Generated World", "PoolroomsLevel2"}) do
		local object = workspace:FindFirstChild(name)
		if object then object:Destroy() end
	end
	destroyCompatibilityObjects()
	restoreLevelOneRuntime()
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level2Valves", 0)
	workspace:SetAttribute("Level2ExitPowered", false)
	workspace:SetAttribute("ValveColorWashUntil", 0)
	workspace:SetAttribute("ValveBlackoutActive", false)
	workspace:SetAttribute("Level2LightingOwnedByController", false)
	state:SetAttribute("Level2_Phase", "IDLE")
	state:SetAttribute("Level2_LightingMode", "OFF")
	state:SetAttribute("Level2_ValveProgress", 0)
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1
	local state = getState()
	local requestedSeed = workspace:GetAttribute("Level2Seed")
	if type(requestedSeed) ~= "number" then
		requestedSeed = DateTime.now().UnixTimestampMillis % 2147483647
		workspace:SetAttribute("Level2Seed", requestedSeed)
	end
	state:SetAttribute("Level2_Phase", "GENERATING_LAYOUT")
	state:SetAttribute("Level2_Generation", generation)
	state:SetAttribute("Level2_Seed", requestedSeed)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_2_GENERATING_LAYOUT")
	workspace:SetAttribute("Level2LightingOwnedByController", true)
	workspace:SetAttribute("ValveColorWashUntil", 0)
	workspace:SetAttribute("ValveBlackoutActive", false)

	for _, name in ipairs(LEGACY_LEVEL_TWO_SCRIPTS) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then object.Enabled = false end
	end
	isolateLevelOneRuntime()
	clearOwnedTerrain(nil)

	local success, result = xpcall(function()
		local layout = LayoutGenerator.Generate(requestedSeed)
		state:SetAttribute("Level2_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_2_BUILDING_WORLD")
		local manifest = WorldBuilder.Build(layout, generation)
		activeManifest = manifest
		state:SetAttribute("Level2_Phase", "READY")
		state:SetAttribute("Level2_LightingMode", "NORMAL")
		state:SetAttribute("Level2_ValveProgress", 0)
		ObjectiveController.Start(manifest, generation)
		workspace:SetAttribute("SelectedLevel", 2)
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return manifest.World
	end, debug.traceback)
	if not success then
		Adapter.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		state:SetAttribute("Level2_Phase", "ERROR")
		state:SetAttribute("Level2_Error", tostring(result))
		error(result)
	end
	return result
end

return Adapter
