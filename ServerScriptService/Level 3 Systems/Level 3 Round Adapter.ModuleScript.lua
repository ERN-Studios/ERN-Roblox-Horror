--!strict
-- Level 3 Round Adapter
--
-- GameManager-facing lifecycle owner for Level 3. Everything Level 3 touches
-- outside its generated world is acquired here and restored by Cleanup(): the
-- persistent lobby, Level 1 server scripts, the Level 1 Workspace.Entity,
-- compatibility markers, replicated state, and workspace objective mirrors.
--
-- Level 3 intentionally has no EntityStart and no entity/NPC/AI runtime.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 3 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 3 Objective Controller"))

local Adapter = {}

local activeManifest: any = nil
local generation = 0
local levelOneScriptStates: {[BaseScript]: boolean}? = nil
local storedLevelOneEntity: Instance? = nil
local storedServerLobby: Instance? = nil

local STORED_LOBBY_NAME = "Level 3 Stored Server Lobby"
local STORED_LEVEL_ONE_ENTITY_NAME = "Level 3 Stored Level 1 Entity"

-- These are the active Level 1 services in the clean project baseline. They
-- must not keep running after their world has been replaced by Level 3.
local LEVEL_ONE_RUNTIME_SCRIPTS = {
	"EntityAI",
	"EntityAnimation",
	"EntityKill",
	"PuzzleManager",
}

local LEGACY_LEVEL_THREE_ATTRIBUTES = {
	"Level3Pumps",
	"Level3PumpGoal",
	"Level3ExitPowered",
}

local function ownedFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local created = Instance.new("Folder")
	created.Name = name
	created.Parent = parent
	return created
end

local function state(): Folder
	return ownedFolder(ReplicatedStorage, Configuration.StateFolderName)
end

local function ensureRemotes()
	local remotes = ownedFolder(ReplicatedStorage, Configuration.RemotesFolderName)
	local existing = remotes:FindFirstChild(Configuration.ClientEventName)
	if existing and existing:IsA("RemoteEvent") then
		return
	end
	if existing then
		existing:Destroy()
	end
	local event = Instance.new("RemoteEvent")
	event.Name = Configuration.ClientEventName
	event.Parent = remotes
end

local function setScriptsEnabled(names: {string}, enabled: boolean)
	for _, name in ipairs(names) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then
			object.Enabled = enabled
		end
	end
end

-- The lobby is parked rather than cloned. GameManager's references to stations
-- and zones therefore stay valid when the same instance is restored.
local function storeLobby()
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then
		return
	end
	storedServerLobby = lobby
	lobby.Name = STORED_LOBBY_NAME
	lobby.Parent = ServerStorage
end

local function restoreLobby()
	local stored = storedServerLobby
	if not (stored and stored.Parent == ServerStorage) then
		stored = ServerStorage:FindFirstChild(STORED_LOBBY_NAME)
	end
	storedServerLobby = nil
	if not stored then
		return
	end

	local existing = workspace:FindFirstChild("ServerLobby")
	if existing then
		-- GameManager has already rebuilt a live lobby, so this stored copy is
		-- stale and must not create duplicate launch zones.
		stored:Destroy()
		return
	end
	stored.Name = "ServerLobby"
	stored.Parent = workspace
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
		entity.Name = STORED_LEVEL_ONE_ENTITY_NAME
		entity.Parent = ServerStorage
	end
end

local function restoreLevelOneRuntime(forceEnableScripts: boolean)
	local stored = storedLevelOneEntity
	if not (stored and stored.Parent) then
		stored = ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME)
	end
	if stored and stored.Parent then
		local existing = workspace:FindFirstChild("Entity")
		if existing and existing ~= stored then
			existing:Destroy()
		end
		stored.Name = "Entity"
		stored.Parent = workspace
	end
	storedLevelOneEntity = nil

	if levelOneScriptStates then
		for object, wasEnabled in pairs(levelOneScriptStates) do
			if object.Parent then
				object.Enabled = wasEnabled
			end
		end
	elseif forceEnableScripts then
		-- A saved or crashed edit state cannot preserve the old Lua table. The
		-- listed scripts are enabled in the clean Level 1 baseline.
		setScriptsEnabled(LEVEL_ONE_RUNTIME_SCRIPTS, true)
	end
	levelOneScriptStates = nil
end

local function destroyCompatibilityObjects()
	-- Deliberately no EntityStart: Level 3 does not create or require one.
	for _, name in ipairs({"Elevator", "MazeStart", "ElevatorSpawn"}) do
		for _, object in ipairs(workspace:GetChildren()) do
			if object.Name == name and object:GetAttribute("Level3_CompatibilityMarker") == true then
				object:Destroy()
			end
		end
	end
end

local function destroyGeneratedWorlds()
	local stale = workspace:FindFirstChild(Configuration.WorldName)
	while stale do
		stale:Destroy()
		stale = workspace:FindFirstChild(Configuration.WorldName)
	end
end

local function clearLegacyAttributes()
	for _, name in ipairs(LEGACY_LEVEL_THREE_ATTRIBUTES) do
		workspace:SetAttribute(name, nil)
	end
end

local function stopObjectiveController()
	local success, problem = pcall(ObjectiveController.Stop)
	if not success then
		warn("[Level 3] Objective controller cleanup failed: " .. tostring(problem))
	end
end

local function validateManifest(manifest: any)
	assert(type(manifest) == "table", "Level 3 world builder must return a manifest table")
	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent == workspace,
		"Level 3 manifest is missing its live World model")
	assert(manifest.World:GetAttribute("Level3_Generation") == generation,
		"Level 3 manifest generation does not match the active build")
	assert(manifest.Elevator and manifest.Elevator:IsA("Model") and manifest.Elevator.Parent == workspace,
		"Level 3 manifest is missing its Elevator compatibility model")
	assert(manifest.ElevatorSpawn and manifest.ElevatorSpawn:IsA("BasePart")
		and manifest.ElevatorSpawn.Parent == workspace,
		"Level 3 manifest is missing its ElevatorSpawn compatibility part")
	assert(manifest.MazeStart and manifest.MazeStart:IsA("BasePart") and manifest.MazeStart.Parent == workspace,
		"Level 3 manifest is missing its MazeStart compatibility part")
	assert(type(manifest.Modules) == "table" and #manifest.Modules == Configuration.ModuleGoal,
		"Level 3 manifest module count does not match Configuration.ModuleGoal")
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing its escape prompt")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing its exit safe spawn")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 manifest is missing its exit position")
end

local function movePlayersToArrival(manifest: any)
	local spawnPart = manifest.ElevatorSpawn :: BasePart
	local moved = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local index = moved
			moved += 1
			local column = index % 3
			local row = math.floor(index / 3)
			local target = spawnPart.CFrame * CFrame.new((column - 1) * 2.75, 4, row * 2.75)
			character:PivotTo(target)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function resetReplicatedState(levelState: Folder)
	levelState:SetAttribute("Level3_Phase", "IDLE")
	levelState:SetAttribute("Level3_ModuleProgress", 0)
	levelState:SetAttribute("Level3_ModuleGoal", 0)
	levelState:SetAttribute("Level3_ExitUnlocked", false)
	levelState:SetAttribute("Level3_ExitPosition", nil)
	levelState:SetAttribute("Level3_LightingMode", "OFF")
	levelState:SetAttribute("Level3_Error", nil)
end

function Adapter.Cleanup()
	local recoveringPersistedState = levelOneScriptStates == nil and (
		workspace:GetAttribute("SelectedLevel") == 3
		or workspace:FindFirstChild(Configuration.WorldName) ~= nil
		or ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME) ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)

	stopObjectiveController()
	local levelState = state()
	levelState:SetAttribute("Level3_Phase", "CLEANING")

	if activeManifest and activeManifest.World and activeManifest.World.Parent then
		activeManifest.World:Destroy()
	end
	activeManifest = nil
	destroyGeneratedWorlds()
	destroyCompatibilityObjects()
	restoreLobby()
	restoreLevelOneRuntime(recoveringPersistedState)

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", false)
	clearLegacyAttributes()

	-- Preserve SelectedLevel throughout GameManager's result delay. Cleanup is
	-- called only after that delay, so it is now safe to hand ownership back.
	if workspace:GetAttribute("SelectedLevel") == 3 then
		workspace:SetAttribute("SelectedLevel", 1)
	end
	resetReplicatedState(levelState)
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1

	local levelState = state()
	ensureRemotes()
	clearLegacyAttributes()

	levelState:SetAttribute("Level3_Phase", "BUILDING_WORLD")
	levelState:SetAttribute("Level3_Generation", generation)
	levelState:SetAttribute("Level3_ModuleProgress", 0)
	levelState:SetAttribute("Level3_ModuleGoal", Configuration.ModuleGoal)
	levelState:SetAttribute("Level3_ExitUnlocked", false)
	levelState:SetAttribute("Level3_ExitPosition", nil)
	levelState:SetAttribute("Level3_LightingMode", "NORMAL")
	levelState:SetAttribute("Level3_Error", nil)

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_3_BUILDING_WORLD")
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", Configuration.ModuleGoal)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", true)

	isolateLevelOneRuntime()

	-- GameManager treats a raised error as a failed generation. Every failure
	-- path therefore restores the lobby and Level 1 runtime before re-raising.
	local success, result = xpcall(function()
		local manifest = WorldBuilder.Build(generation)
		validateManifest(manifest)
		activeManifest = manifest

		-- Move characters onto solid Level 3 ground before the lobby is parked.
		-- GameManager will place the round party again when entry begins.
		movePlayersToArrival(manifest)
		storeLobby()

		workspace:SetAttribute("SelectedLevel", 3)
		levelState:SetAttribute("Level3_ExitPosition", manifest.ExitPosition)
		levelState:SetAttribute("Level3_Phase", "READY")

		-- READY is established first so the objective controller may replace it
		-- with its more specific active phase without the adapter overwriting it.
		ObjectiveController.Start(manifest, generation)

		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return manifest.World
	end, debug.traceback)

	if not success then
		Adapter.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		levelState:SetAttribute("Level3_Phase", "ERROR")
		levelState:SetAttribute("Level3_Error", tostring(result))
		error(result)
	end
	return result
end

return Adapter
