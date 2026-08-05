-- Level 3 Round Adapter
-- The Build/Cleanup surface GameManager talks to, and the owner of everything
-- Level 3 touches outside its own world model: terrain, the Level 1 runtime
-- scripts, the compatibility markers, and the replicated state folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 3 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 3 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 3 Objective Controller"))

local Adapter = {}
local activeManifest
local generation = 0
local levelOneScriptStates
local storedLevelOneEntity

-- Level 1 owns these; they must be off while Level 3 is live or PuzzleManager
-- builds the fuse puzzle inside the poolrooms and EntityAI pathfinds through
-- geometry it does not understand.
local LEVEL_ONE_RUNTIME_SCRIPTS = {
	"EntityAI",
	"EntityAnimation",
	"EntityKill",
	"PuzzleManager",
}

-- Level 2's tag-driven hostiles would otherwise bind to anything left tagged.
local LEVEL_TWO_RUNTIME_SCRIPTS = {
	"Level2EntityAI",
	"Level2EntityAnimation",
	"Level2EntityKill",
}

local function getState()
	local existing = ReplicatedStorage:FindFirstChild("Level 3 State")
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local created = Instance.new("Folder")
	created.Name = "Level 3 State"
	created.Parent = ReplicatedStorage
	return created
end

local function setScriptsEnabled(names, enabled)
	for _, name in ipairs(names) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then
			object.Enabled = enabled
		end
	end
end

local function destroyCompatibilityObjects()
	for _, name in ipairs({"Elevator", "MazeStart", "ElevatorSpawn", "EntityStart"}) do
		for _, object in ipairs(workspace:GetChildren()) do
			if object.Name == name and object:GetAttribute("Level3_CompatibilityMarker") == true then
				object:Destroy()
			end
		end
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
		entity.Name = "Level 3 Stored Level 1 Entity"
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
	local extent = Configuration.ComplexExtent
	local center = manifest and manifest.TerrainCenter or Vector3.new(
		Configuration.WorldCenterX or 0, -16, Configuration.WorldCenterZ or 0)
	local size = manifest and manifest.TerrainSize or Vector3.new(extent + 700, 200, extent + 700)
	Terrain:FillBlock(CFrame.new(center), size, Enum.Material.Air)
end

function Adapter.Cleanup()
	ObjectiveController.Stop()
	local state = getState()
	state:SetAttribute("Level3_Phase", "CLEANING")

	clearOwnedTerrain(activeManifest)
	if activeManifest and activeManifest.World and activeManifest.World.Parent then
		activeManifest.World:Destroy()
	end
	activeManifest = nil

	local stale = workspace:FindFirstChild("Level 3 Generated World")
	while stale do
		stale:Destroy()
		stale = workspace:FindFirstChild("Level 3 Generated World")
	end

	destroyCompatibilityObjects()
	restoreLevelOneRuntime()

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level3Pumps", 0)
	workspace:SetAttribute("Level3PumpGoal", 0)
	workspace:SetAttribute("Level3ExitPowered", false)
	workspace:SetAttribute("Level3LightingOwnedByController", false)
	-- Hand the world back to Level 1, so GameManager's boot-time recovery does
	-- not see a stale SelectedLevel == 3 and try to clean up again.
	if workspace:GetAttribute("SelectedLevel") == 3 then
		workspace:SetAttribute("SelectedLevel", 1)
	end

	state:SetAttribute("Level3_Phase", "IDLE")
	state:SetAttribute("Level3_LightingMode", "OFF")
	state:SetAttribute("Level3_PumpProgress", 0)
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1

	local state = getState()
	local requestedSeed = workspace:GetAttribute("Level3Seed")
	if type(requestedSeed) ~= "number" then
		requestedSeed = DateTime.now().UnixTimestampMillis % 2147483647
		workspace:SetAttribute("Level3Seed", requestedSeed)
	end

	state:SetAttribute("Level3_Phase", "GENERATING_LAYOUT")
	state:SetAttribute("Level3_Generation", generation)
	state:SetAttribute("Level3_Seed", requestedSeed)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_3_GENERATING_LAYOUT")
	workspace:SetAttribute("Level3LightingOwnedByController", true)

	setScriptsEnabled(LEVEL_TWO_RUNTIME_SCRIPTS, false)
	isolateLevelOneRuntime()
	clearOwnedTerrain(nil)

	-- GameManager reads success only from whether this raises, so every failure
	-- path must re-raise after cleaning up.
	local success, result = xpcall(function()
		local layout = LayoutGenerator.Generate(requestedSeed)

		state:SetAttribute("Level3_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_3_BUILDING_WORLD")
		local manifest = WorldBuilder.Build(layout, generation)
		activeManifest = manifest

		state:SetAttribute("Level3_Phase", "READY")
		state:SetAttribute("Level3_LightingMode", "NORMAL")
		state:SetAttribute("Level3_PumpProgress", 0)
		state:SetAttribute("Level3_HallCount", #layout.Halls)

		ObjectiveController.Start(manifest, generation)

		workspace:SetAttribute("SelectedLevel", 3)
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return manifest.World
	end, debug.traceback)

	if not success then
		Adapter.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		state:SetAttribute("Level3_Phase", "ERROR")
		state:SetAttribute("Level3_Error", tostring(result))
		error(result)
	end
	return result
end

return Adapter
