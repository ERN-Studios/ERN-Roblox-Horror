-- Level 2 Round Adapter
-- The Build/Cleanup surface GameManager talks to, and the owner of everything
-- Level 2 touches outside its own world model: terrain, the Level 1 runtime
-- scripts, the compatibility markers, and the replicated state folder.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Terrain = workspace.Terrain

local Configuration = require(script.Parent:WaitForChild("Level 2 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 2 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 2 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 2 Objective Controller"))
local PoolFoamController = require(script.Parent:WaitForChild("Level 2 Pool Foam Controller"))
local PoolFoamConfiguration = require(script.Parent:WaitForChild("Level 2 Pool Foam Configuration"))

local Adapter = {}
local activeManifest
local generation = 0
local levelOneScriptStates
local storedLevelOneEntity
local storedServerLobby

local STORED_LOBBY_NAME = "Level 2 Stored Server Lobby"

-- Only the level should be loaded during a round: the persistent tunnel lobby
-- is parked in ServerStorage while Level 2 is live and restored on cleanup,
-- the same trick Level 2's original generator used. GameManager's station
-- references stay valid because it is the same instance moving parents.
local function storeLobby()
	local lobby = workspace:FindFirstChild("ServerLobby")
	if lobby then
		storedServerLobby = lobby
		lobby.Name = STORED_LOBBY_NAME
		lobby.Parent = ServerStorage
	end
end

local function restoreLobby()
	local stored = storedServerLobby
	if not (stored and stored.Parent == ServerStorage) then
		stored = ServerStorage:FindFirstChild(STORED_LOBBY_NAME)
	end
	storedServerLobby = nil
	if not stored then return end
	local existing = workspace:FindFirstChild("ServerLobby")
	if existing then
		-- GameManager already rebuilt a live lobby; the stored copy is stale.
		stored:Destroy()
		return
	end
	stored.Name = "ServerLobby"
	stored.Parent = workspace
end

-- Level 1 owns these; they must be off while Level 2 is live or PuzzleManager
-- builds the fuse puzzle inside the poolrooms and EntityAI pathfinds through
-- geometry it does not understand.
local LEVEL_ONE_RUNTIME_SCRIPTS = {
	"EntityAI",
	"EntityAnimation",
	"EntityKill",
	"PuzzleManager",
}

local function getState()
	local existing = ReplicatedStorage:FindFirstChild("Level 2 State")
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
	local created = Instance.new("Folder")
	created.Name = "Level 2 State"
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
			if object.Name == name and object:GetAttribute("Level2_CompatibilityMarker") == true then
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
		entity.Name = "Level 2 Stored Level 1 Entity"
	end
end

local function restoreLevelOneRuntime(forceEnableScripts)
	local stored = storedLevelOneEntity
	if not (stored and stored.Parent) then
		stored = ServerStorage:FindFirstChild("Level 2 Stored Level 1 Entity")
	end
	if stored and stored.Parent then
		local existing = workspace:FindFirstChild("Entity")
		if existing and existing ~= stored then existing:Destroy() end
		stored.Name = "Entity"
		stored.Parent = workspace
	end
	storedLevelOneEntity = nil
	if levelOneScriptStates then
		for object, enabled in pairs(levelOneScriptStates) do
			if object.Parent then object.Enabled = enabled end
		end
	elseif forceEnableScripts then
		-- A saved/crashed Level 2 edit state cannot preserve the old Lua table.
		-- These four active Level 1 scripts are enabled in the clean place baseline.
		setScriptsEnabled(LEVEL_ONE_RUNTIME_SCRIPTS, true)
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
	local recoveringPersistedState = levelOneScriptStates == nil and (
		workspace:GetAttribute("SelectedLevel") == 2
		or workspace:FindFirstChild("Level 2 Generated World") ~= nil
		or workspace:FindFirstChild("PoolroomsLevel2") ~= nil
		or ServerStorage:FindFirstChild("Level 2 Stored Level 1 Entity") ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)
	PoolFoamController.Stop()
	ObjectiveController.Stop()
	-- Pool Foam pause is session-local; do not inherit a Studio debug pause.
	workspace:SetAttribute("EntityPaused", false)
	local state = getState()
	state:SetAttribute("Level2_Phase", "CLEANING")

	clearOwnedTerrain(activeManifest)
	if activeManifest and activeManifest.World and activeManifest.World.Parent then
		activeManifest.World:Destroy()
	end
	activeManifest = nil

	local stale = workspace:FindFirstChild("Level 2 Generated World")
	while stale do
		stale:Destroy()
		stale = workspace:FindFirstChild("Level 2 Generated World")
	end
	-- A world saved by the PRE-rewrite poolrooms build.
	local legacy = workspace:FindFirstChild("PoolroomsLevel2")
	if legacy then legacy:Destroy() end

	destroyCompatibilityObjects()
	restoreLobby()
	restoreLevelOneRuntime(recoveringPersistedState)

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level2Pumps", 0)
	workspace:SetAttribute("Level2PumpGoal", 0)
	workspace:SetAttribute("Level2ExitPowered", false)
	workspace:SetAttribute("Level2LightingOwnedByController", false)
	-- Hand the world back to Level 1, so GameManager's boot-time recovery does
	-- not see a stale SelectedLevel == 2 and try to clean up again.
	if workspace:GetAttribute("SelectedLevel") == 2 then
		workspace:SetAttribute("SelectedLevel", 1)
	end

	state:SetAttribute("Level2_Phase", "IDLE")
	state:SetAttribute("Level2_LightingMode", "OFF")
	state:SetAttribute("Level2_PumpProgress", 0)
	for pumpNumber = 1, 3 do
		state:SetAttribute("Level2_PumpStartedAt" .. tostring(pumpNumber), nil)
	end
	state:SetAttribute("Level2_HallCount", nil)
	state:SetAttribute("Level2_Error", nil)
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1

	local state = getState()
	-- The workspace attribute is a MANUAL testing override only. Never
	-- write the random pick back — doing so froze the map on the first
	-- round's seed for every round after it.
	local requestedSeed = workspace:GetAttribute("Level2Seed")
	if type(requestedSeed) ~= "number" then
		requestedSeed = DateTime.now().UnixTimestampMillis % 2147483647
	end

	state:SetAttribute("Level2_Phase", "GENERATING_LAYOUT")
	state:SetAttribute("Level2_Generation", generation)
	state:SetAttribute("Level2_Seed", requestedSeed)
	state:SetAttribute("Level2_RequestedSeed", requestedSeed)
	state:SetAttribute("Level2_ResolvedSeed", nil)
	state:SetAttribute("Level2_GenerationAttempt", nil)
	state:SetAttribute("Level2_UsedFallback", false)
	state:SetAttribute("Level2_FallbackBaseSeed", nil)
	state:SetAttribute("Level2_Error", nil)
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_2_GENERATING_LAYOUT")
	workspace:SetAttribute("Level2LightingOwnedByController", true)

	isolateLevelOneRuntime()
	clearOwnedTerrain(nil)

	-- GameManager reads success only from whether this raises, so every failure
	-- path must re-raise after cleaning up.
	local success, result = xpcall(function()
		local layout = LayoutGenerator.Generate(requestedSeed)
		state:SetAttribute("Level2_ResolvedSeed", layout.Seed)
		state:SetAttribute("Level2_GenerationAttempt", layout.Attempt)
		state:SetAttribute("Level2_UsedFallback", layout.FallbackUsed == true)
		state:SetAttribute("Level2_FallbackBaseSeed", layout.FallbackBaseSeed)

		state:SetAttribute("Level2_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_2_BUILDING_WORLD")
		local manifest = WorldBuilder.Build(layout, generation)
		activeManifest = manifest

		-- Move everyone out of the lobby BEFORE parking it, or the floor
		-- vanishes from under them and they fall into the void. The arrival
		-- platform is solid ground; GameManager re-places participants on it
		-- moments later anyway.
		local Players = game:GetService("Players")
		local arrivalSpawn = manifest.Arrival.ElevatorSpawn
		local arrivalPosition = arrivalSpawn.Position
		local arrivalLook = arrivalSpawn.CFrame.LookVector
		local forward = Vector3.new(arrivalLook.X, 0, arrivalLook.Z).Unit
		local side = Vector3.new(-forward.Z, 0, forward.X)
		local moved = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				moved += 1
				local slot = moved - 1
				local offset = side * (((slot % 3) - 1) * 2.5)
					+ forward * (math.floor(slot / 3) * 2.5)
					+ Vector3.new(0, 4, 0)
				character:PivotTo(CFrame.lookAt(
					arrivalPosition + offset, arrivalPosition + offset + forward))
			end
		end
		storeLobby()

		state:SetAttribute("Level2_Phase", "READY")
		state:SetAttribute("Level2_LightingMode", "NORMAL")
		state:SetAttribute("Level2_PumpProgress", 0)
		state:SetAttribute("Level2_HallCount", #layout.Halls)

		ObjectiveController.Start(manifest, generation)
		local poolFoamSession, poolFoamError = PoolFoamController.Start(manifest, generation)
		if not poolFoamSession then
			local message = "[Level 2] Pool Foam encounter did not start: " .. tostring(poolFoamError)
			if PoolFoamConfiguration.Enabled == true then
				error(message)
			end
			warn(message)
		end

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
