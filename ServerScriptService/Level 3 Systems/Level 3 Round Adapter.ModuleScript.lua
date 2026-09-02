--!strict
-- Level 3 Round Adapter
--
-- GameManager-facing lifecycle owner for Level 3. Everything Level 3 touches
-- outside its generated world is acquired here and restored by Cleanup(): the
-- persistent lobby, Level 1 server scripts, the Level 1 Workspace.Entity,
-- compatibility markers, replicated state, objective mirrors, and the dedicated
-- Level 3 Mall Manager runtime. Level 3 still never creates EntityStart.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local LayoutGenerator = require(script.Parent:WaitForChild("Level 3 Layout Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 3 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 3 Objective Controller"))
local MusicSequenceController = require(script.Parent:WaitForChild("Level 3 Music Sequence Controller"))
local HidingController = require(script.Parent:WaitForChild("Level 3 Hiding Controller"))
local MallManagerController = require(script.Parent:WaitForChild("Level 3 Mall Manager AI Controller"))

local Adapter = {}

local activeManifest: any = nil
local generation = 0
local levelOneScriptStates: {[BaseScript]: boolean}? = nil
local storedLevelOneEntity: Instance? = nil
local storedServerLobby: Instance? = nil
local managerBlackoutConnection: RBXScriptConnection? = nil
local managerLifecycleToken = 0

local STORED_LOBBY_NAME = "Level 3 Stored Server Lobby"
local STORED_LEVEL_ONE_ENTITY_NAME = "Level 3 Stored Level 1 Entity"
local MAX_SEED = 2147483647

-- A manual override only counts when it is a real, usable seed. 0 is the OFF
-- value -- it is what a tester leaves behind by typing a zero instead of
-- deleting the attribute, and the old `type(value) ~= "number"` guard accepted
-- it as a pinned seed, so every round would silently rebuild seed 0's mall.
-- Level 2 shipped exactly this bug and was fixed on 2026-08-19; this is the same
-- fix, kept deliberately identical to Level 2 Round Adapter's pinnedSeedOverride.
local function pinnedSeedOverride(): number?
	local requested = workspace:GetAttribute("Level3Seed")
	if type(requested) ~= "number" then return nil end
	if requested ~= requested then return nil end -- NaN
	-- Reject out of range rather than wrapping. `% MAX_SEED` silently aliased
	-- the top of the documented "any number >= 1" range: 2147483647 built
	-- seed 0's map, 2147483648 built seed 1's. MAX_SEED is finite, so this
	-- bound also subsumes the old math.huge check.
	if requested < 1 or requested >= MAX_SEED then return nil end
	return math.floor(requested)
end

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
	-- Retired with the furniture state machine (LEVEL3_PERMANENT_FURNITURE_20260828).
	-- Cleared rather than merely abandoned so a place saved mid-hunt under the old
	-- build cannot keep advertising suppressed furniture to anything that looks.
	"Level3FurnitureTemporarilyRemoved",
	"Level3FurnitureCollisionSuppressed",
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
	if not (existing and existing:IsA("RemoteEvent")) then
		if existing then existing:Destroy() end
		local event = Instance.new("RemoteEvent")
		event.Name = Configuration.ClientEventName
		event.Parent = remotes
	end
	local hideRequest = remotes:FindFirstChild(Configuration.HideRequestEventName)
	if not (hideRequest and hideRequest:IsA("RemoteEvent")) then
		if hideRequest then hideRequest:Destroy() end
		local event = Instance.new("RemoteEvent")
		event.Name = Configuration.HideRequestEventName
		event.Parent = remotes
	end
	local motion = remotes:FindFirstChild(Configuration.MallManagerMotionEventName)
	if not (motion and motion:IsA("UnreliableRemoteEvent")) then
		if motion then motion:Destroy() end
		local event = Instance.new("UnreliableRemoteEvent")
		event.Name = Configuration.MallManagerMotionEventName
		event.Parent = remotes
	end
end

local function setScriptsEnabled(names: {string}, enabled: boolean)
	for _, name in ipairs(names) do
		-- Recursive: Level 1's runtime scripts moved into a "Level 1 Systems"
		-- folder on 2026-09-02, and a non-recursive lookup would silently return
		-- nil there -- which is exactly how every Level 2/3 round once came to
		-- start Level 1's fuse puzzle server-side. Recursive works from either
		-- layout, so this cannot break again on the next reorganisation.
		local object = ServerScriptService:FindFirstChild(name, true)
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
		-- Recursive: Level 1's runtime scripts moved into a "Level 1 Systems"
		-- folder on 2026-09-02, and a non-recursive lookup would silently return
		-- nil there -- which is exactly how every Level 2/3 round once came to
		-- start Level 1's fuse puzzle server-side. Recursive works from either
		-- layout, so this cannot break again on the next reorganisation.
		local object = ServerScriptService:FindFirstChild(name, true)
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
	-- A failed procedural build may still be staged off-Workspace.  Sweep both
	-- owners so a retry never inherits half-built rooms or retained Instances.
	for _, parent in ipairs({workspace, ServerStorage}) do
		local stale = parent:FindFirstChild(Configuration.WorldName)
		while stale do
			stale:Destroy()
			stale = parent:FindFirstChild(Configuration.WorldName)
		end
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

local function stopMusicSequence()
	local success, problem = pcall(MusicSequenceController.Stop)
	if not success then
		warn("[Level 3] Music sequence cleanup failed: " .. tostring(problem))
	end
end

local function stopMallManager()
	local success, problem = pcall(MallManagerController.Stop)
	if not success then
		warn("[Level 3] Mall Manager cleanup failed: " .. tostring(problem))
	end
end

local function disconnectManagerLifecycle()
	managerLifecycleToken += 1
	if managerBlackoutConnection and managerBlackoutConnection.Connected then
		managerBlackoutConnection:Disconnect()
	end
	managerBlackoutConnection = nil
end

local function bindManagerToHunt(manifest: any, activeGeneration: number)
	disconnectManagerLifecycle()
	local token = managerLifecycleToken
	local function sync()
		if token ~= managerLifecycleToken or activeManifest ~= manifest
			or not manifest.World or manifest.World.Parent ~= workspace then return end
		local shouldExist = workspace:GetAttribute("Level3MallManagerHuntActive") == true
			and workspace:GetAttribute("RoundActive") == true
			and workspace:GetAttribute("SelectedLevel") == 3
		if not shouldExist then
			stopMallManager()
			return
		end
		if MallManagerController.GetSnapshot() then return end
		local ok, result = pcall(MallManagerController.Start, manifest, activeGeneration)
		if not ok then
			warn("[Level 3] Mall Manager hunt spawn failed: " .. tostring(result))
			return
		end
		if result == nil then
			-- Characters can briefly be unavailable on the exact edge. Retry only
			-- while this same hunt generation is still authoritative.
			task.delay(.35, function()
				if token == managerLifecycleToken
					and workspace:GetAttribute("Level3MallManagerHuntActive") == true then sync() end
			end)
		end
	end
	managerBlackoutConnection = workspace:GetAttributeChangedSignal("Level3MallManagerHuntActive"):Connect(sync)
	sync()
end

local function validateManifest(manifest: any)
	assert(type(manifest) == "table", "Level 3 world builder must return a manifest table")
	local layout = manifest.Layout
	assert(type(layout) == "table", "Level 3 manifest is missing its generated layout")
	local layoutValid, layoutProblem = LayoutGenerator.Validate(layout)
	assert(layoutValid, "Level 3 generated layout failed validation: " .. tostring(layoutProblem))
	assert(manifest.World:GetAttribute("Level3_LayoutHash") == layout.LayoutHash,
		"Level 3 world and manifest layout hashes do not match")
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
	assert(type(manifest.Corridors) == "table" and #manifest.Corridors == #layout.Links,
		"Level 3 manifest corridor count does not match its generated layout")
	local expectedHideTables = tonumber(layout.HideSpotCount) or Configuration.Layout.HideTableCount
	assert(type(manifest.HideTables) == "table" and #manifest.HideTables == expectedHideTables,
		"Level 3 manifest hide-table count does not match its generated layout")
	local hideIndices = {}
	for _, anchor in ipairs(manifest.HideTables) do
		assert(anchor:IsA("BasePart") and anchor:IsDescendantOf(manifest.World)
			and anchor:GetAttribute("Level3_HideTableAnchor") == true,
			"Level 3 hide table anchor is invalid")
		local index = tonumber(anchor:GetAttribute("Level3_HideTableIndex"))
		assert(index and index >= 1 and index <= expectedHideTables and not hideIndices[index],
			"Level 3 hide table indices must be unique and contiguous")
		hideIndices[index] = true
		local prompt = anchor:FindFirstChild("HideUnderTablePrompt")
		assert(prompt and prompt:IsA("ProximityPrompt"), "Level 3 hide table prompt is missing")
	end
	assert(type(manifest.BlackoutScreamOpenings) == "table"
		and #manifest.BlackoutScreamOpenings == #manifest.Corridors * 2,
		"Level 3 manifest requires two blackout scream markers per generated corridor")
	for _, opening in ipairs(manifest.BlackoutScreamOpenings) do
		assert(opening:IsA("Attachment") and opening:IsDescendantOf(manifest.World)
			and opening:GetAttribute("Level3_CorridorOpeningScreamEmitter") == true,
			"Level 3 blackout scream opening marker is invalid")
	end
	assert(manifest.MallManagerSpawn and manifest.MallManagerSpawn:IsA("BasePart")
		and manifest.MallManagerSpawn:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing Mall Manager Spawn")
	local spawnRoomId = manifest.MallManagerSpawn:GetAttribute("Level3_SpawnRoomId")
	assert(type(spawnRoomId) == "string" and layout.RoomById[spawnRoomId]
		and spawnRoomId ~= layout.Roles.ExitRoomId,
		"Level 3 Mall Manager spawn role is invalid for the generated layout")
	assert(manifest.MallManagerRuntime and manifest.MallManagerRuntime:IsA("Folder")
		and manifest.MallManagerRuntime:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing Mall Manager Runtime")
	assert(type(manifest.DiscPlayer) == "table" and manifest.DiscPlayer.Model
		and manifest.DiscPlayer.Model:IsA("Model")
		and manifest.DiscPlayer.Model:IsDescendantOf(manifest.World)
		and manifest.DiscPlayer.Prompt:IsA("ProximityPrompt")
		and type(manifest.DiscPlayer.Slots) == "table"
		and #manifest.DiscPlayer.Slots == Configuration.ModuleGoal,
		"Level 3 manifest is missing its five-slot Signal Hall disc player")
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing its escape prompt")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing its exit safe spawn")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 manifest is missing its exit position")
	local finalHall = manifest.FinalHall
	assert(type(finalHall) == "table" and finalHall.Model and finalHall.Model:IsA("Model")
		and finalHall.Model:IsDescendantOf(manifest.World),
		"Level 3 manifest is missing its generated final hall")
	assert(type(finalHall.Length) == "number"
		and math.abs(finalHall.Length - Configuration.Layout.ExitCorridorLength) <= .1,
		"Level 3 final hall length does not match configuration")
	assert(finalHall.HalfwayMarker and finalHall.HalfwayMarker:IsA("BasePart")
		and finalHall.HalfwayMarker:GetAttribute("Level3_FinalHallHalfway") == true,
		"Level 3 final hall halfway marker is invalid")
	assert(finalHall.SpawnMarker and finalHall.SpawnMarker:IsA("BasePart")
		and finalHall.SpawnMarker:GetAttribute("Level3_MallManagerFinaleSpawn") == true,
		"Level 3 final hall Manager spawn marker is invalid")
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

-- One authoritative list of every replicated Level 3 attribute. Build and the
-- round reset both consume it so the two can never drift apart; the handful of
-- values that differ between "fresh round" and "idle" arrive as overrides.
local function applyBaselineReplicatedState(levelState: Folder, overrides: {[string]: any}?)
	local o = overrides or {}
	-- Retired with the furniture state machine (LEVEL3_PERMANENT_FURNITURE_20260828).
	-- The state folder is a saved place object, so a stale replicated flag would
	-- otherwise outlive the code that wrote it.
	levelState:SetAttribute("Level3_FurnitureTemporarilyRemoved", nil)
	levelState:SetAttribute("Level3_FurnitureCollisionSuppressed", nil)
	levelState:SetAttribute("Level3_Phase", o.Phase or "IDLE")
	levelState:SetAttribute("Level3_RequestedSeed", o.RequestedSeed or 0)
	-- Visible in the state folder so "why is the map the same?" is one glance,
	-- the same readback Level 2 publishes as Level2_SeedPinned.
	levelState:SetAttribute("Level3_SeedPinned", o.SeedPinned == true)
	levelState:SetAttribute("Level3_ResolvedSeed", 0)
	levelState:SetAttribute("Level3_GenerationAttempt", 0)
	levelState:SetAttribute("Level3_UsedFallback", false)
	levelState:SetAttribute("Level3_LayoutHash", "")
	levelState:SetAttribute("Level3_GeneratorVersion", LayoutGenerator.Version)
	levelState:SetAttribute("Level3_GeneratedRoomCount", 0)
	levelState:SetAttribute("Level3_GeneratedCorridorCount", 0)
	levelState:SetAttribute("Level3_GeneratedDistrictCount", 0)
	if o.Generation ~= nil then
		levelState:SetAttribute("Level3_Generation", o.Generation)
	end
	levelState:SetAttribute("Level3_ModuleProgress", 0)
	levelState:SetAttribute("Level3_ModuleGoal", o.ModuleGoal or 0)
	levelState:SetAttribute("Level3_CDCollectedProgress", 0)
	levelState:SetAttribute("Level3_CDInsertedProgress", 0)
	levelState:SetAttribute("Level3_CDCarriedCount", 0)
	levelState:SetAttribute("Level3_CDDroppedCount", 0)
	levelState:SetAttribute("Level3_ExitUnlocked", false)
	levelState:SetAttribute("Level3_ExitPosition", nil)
	levelState:SetAttribute("Level3_LightingMode", o.LightingMode or "OFF")
	levelState:SetAttribute("Level3_RoomSongPhase", o.RoomSongPhase or "STOPPED")
	levelState:SetAttribute("Level3_RoomSongStartServerTime", 0)
	levelState:SetAttribute("Level3_CompletionSongStartServerTime", 0)
	levelState:SetAttribute("Level3_CompletionDimStartedAtServerTime", 0)
	levelState:SetAttribute("Level3_CompletionDimDuration", Configuration.MusicSequence.CompletionDimSeconds)
	levelState:SetAttribute("Level3_FinalHallEligibleCount", 0)
	levelState:SetAttribute("Level3_FinalHallCrossedCount", 0)
	levelState:SetAttribute("Level3_FinalHallChaseTriggered", false)
	levelState:SetAttribute("Level3_FinalHallChaseActive", false)
	levelState:SetAttribute("Level3_RoomSongDuration", Configuration.MusicSequence.DurationSeconds)
	levelState:SetAttribute("Level3_BlackoutStartSeconds", Configuration.MusicSequence.BlackoutStartSeconds)
	levelState:SetAttribute("Level3_RoomSongStopSeconds", Configuration.MusicSequence.DurationSeconds)
	levelState:SetAttribute("Level3_PreBlackoutDuration", Configuration.MusicSequence.PreBlackoutFlickerSeconds)
	levelState:SetAttribute("Level3_PreBlackoutStartedAtServerTime", 0)
	levelState:SetAttribute("Level3_PreBlackoutUntilServerTime", 0)
	levelState:SetAttribute("Level3_PreBlackoutSerial", 0)
	levelState:SetAttribute("Level3_PreBlackoutActive", false)
	levelState:SetAttribute("Level3_PostSongBlackoutDuration", Configuration.MusicSequence.PostSongBlackoutSeconds)
	levelState:SetAttribute("Level3_CycleEndSeconds", Configuration.MusicSequence.CycleEndSeconds)
	levelState:SetAttribute("Level3_RecoveryFlickerDuration", Configuration.MusicSequence.RecoveryFlickerSeconds)
	levelState:SetAttribute("Level3_RecoveryFlickerStartedAtServerTime", 0)
	levelState:SetAttribute("Level3_RecoveryFlickerUntilServerTime", 0)
	levelState:SetAttribute("Level3_RecoveryFlickerActive", false)
	levelState:SetAttribute("Level3_BlackoutDuration", Configuration.MusicSequence.BlackoutSeconds)
	levelState:SetAttribute("Level3_BlackoutStartedAtServerTime", 0)
	levelState:SetAttribute("Level3_BlackoutUntilServerTime", 0)
	levelState:SetAttribute("Level3_BlackoutActive", false)
	levelState:SetAttribute("Level3_BlackoutScreamAssetId", Configuration.Audio.MallManagerBlackout)
	levelState:SetAttribute("Level3_BlackoutScreamDuration", Configuration.MallManager.BlackoutScreamDurationSeconds)
	levelState:SetAttribute("Level3_BlackoutScreamVolume", Configuration.MallManager.BlackoutScreamVolume)
	levelState:SetAttribute("Level3_BlackoutScreamStartedAtServerTime", 0)
	levelState:SetAttribute("Level3_MallManagerHuntActive", false)
	levelState:SetAttribute("Level3_FlashlightsSuppressed", false)
	levelState:SetAttribute("Level3_BlackoutScreamOpeningCount", 0)
	levelState:SetAttribute("Level3_MallManagerActive", false)
	levelState:SetAttribute("Level3_MallManagerState", "OFF")
	levelState:SetAttribute("Level3_MallManagerBlackoutBoosted", false)
	levelState:SetAttribute("Level3_MallManagerTargetUserId", 0)
	levelState:SetAttribute("Level3_MallManagerSpeed", 0)
	levelState:SetAttribute("Level3_MallManagerAwarenessRange", 0)
	levelState:SetAttribute("Level3_MallManagerSpawnRoomId", Configuration.MallManager.SpawnRoomId)
	levelState:SetAttribute("Level3_MallManagerSpawnDistance", 0)
	levelState:SetAttribute("Level3_MallManagerSpawnAnchorUserId", 0)
	levelState:SetAttribute("Level3_MallManagerSpawnGroupSize", 0)
	levelState:SetAttribute("Level3_MallManagerSpawnCycle", 0)
	levelState:SetAttribute("Level3_MallManagerSpawnSerial", 0)
	levelState:SetAttribute("Level3_MallManagerPathStatus", "OFF")
	levelState:SetAttribute("Level3_MallManagerAttackSerial", 0)
	levelState:SetAttribute("Level3_MallManagerLastCaptureUserId", 0)
	levelState:SetAttribute("Level3_MallManagerChaseScreamSerial", 0)
	levelState:SetAttribute("Level3_MallManagerChaseScreamPlaying", false)
	levelState:SetAttribute("Level3_MallManagerLastChaseScreamAtServerTime", 0)
	levelState:SetAttribute("Level3_MallManagerLastChaseScreamName", "")
	levelState:SetAttribute("Level3_HiddenPlayers", 0)
	levelState:SetAttribute("Level3_Error", nil)
end

local function resetReplicatedState(levelState: Folder)
	applyBaselineReplicatedState(levelState, nil)
end

-- The live manifest for the round this adapter last built, or nil.
--
-- The deterministic test suites need the manifest the generator produced, and
-- the only alternative was to build a SECOND world alongside the real one and
-- measure that instead -- which tests the builder but not the round anybody
-- actually plays. Read-only, and nil whenever no world is standing.
function Adapter.GetManifest()
	return activeManifest
end

function Adapter.Cleanup()
	local recoveringPersistedState = levelOneScriptStates == nil and (
		workspace:GetAttribute("SelectedLevel") == 3
		or workspace:FindFirstChild(Configuration.WorldName) ~= nil
		or ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME) ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)

	-- Stop lifecycle callbacks before blackout authority is torn down.
	disconnectManagerLifecycle()
	stopMallManager()
	HidingController.Stop()
	stopMusicSequence()
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
	workspace:SetAttribute("Level3CDsCollected", 0)
	workspace:SetAttribute("Level3CDsCarried", 0)
	workspace:SetAttribute("Level3CDsDropped", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", false)
	workspace:SetAttribute("Level3PreBlackoutActive", false)
	workspace:SetAttribute("Level3BlackoutActive", false)
	workspace:SetAttribute("Level3MallManagerHuntActive", false)
	workspace:SetAttribute("Level3RecoveryFlickerActive", false)
	workspace:SetAttribute("Level3MallManagerActive", false)
	workspace:SetAttribute("Level3MallManagerState", "OFF")
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", false)
	workspace:SetAttribute("Level3HiddenPlayers", 0)
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

	-- Level3Seed is a manual reproducibility override only. Never write the
	-- random production choice back or subsequent rounds would repeat the map.
	-- The random path lands in [1, MAX_SEED - 1] so it can never produce the
	-- same 0 the override guard rejects.
	local pinnedSeed = pinnedSeedOverride()
	local requestedSeed = pinnedSeed
		or (DateTime.now().UnixTimestampMillis % (MAX_SEED - 1) + 1)

	applyBaselineReplicatedState(levelState, {
		Phase = "GENERATING_LAYOUT",
		RequestedSeed = requestedSeed,
		SeedPinned = pinnedSeed ~= nil,
		Generation = generation,
		ModuleGoal = Configuration.ModuleGoal,
		LightingMode = "NORMAL",
		RoomSongPhase = "WAITING_FOR_ROUND",
	})

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_3_GENERATING_LAYOUT")
	workspace:SetAttribute("Level3Modules", 0)
	workspace:SetAttribute("Level3ModuleGoal", Configuration.ModuleGoal)
	workspace:SetAttribute("Level3CDsCollected", 0)
	workspace:SetAttribute("Level3CDsCarried", 0)
	workspace:SetAttribute("Level3CDsDropped", 0)
	workspace:SetAttribute("Level3ExitUnlocked", false)
	workspace:SetAttribute("Level3LightingOwnedByController", true)
	workspace:SetAttribute("Level3PreBlackoutActive", false)
	workspace:SetAttribute("Level3BlackoutActive", false)
	workspace:SetAttribute("Level3MallManagerHuntActive", false)
	workspace:SetAttribute("Level3RecoveryFlickerActive", false)
	workspace:SetAttribute("Level3MallManagerActive", false)
	workspace:SetAttribute("Level3MallManagerState", "OFF")
	workspace:SetAttribute("Level3MallManagerBlackoutBoosted", false)
	workspace:SetAttribute("Level3HiddenPlayers", 0)

	isolateLevelOneRuntime()

	-- GameManager treats a raised error as a failed generation. Every failure
	-- path therefore restores the lobby and Level 1 runtime before re-raising.
	local success, result = xpcall(function()
		local layout = LayoutGenerator.Generate(requestedSeed)
		local layoutValid, layoutProblem = LayoutGenerator.Validate(layout)
		assert(layoutValid, "Level 3 layout validation failed: " .. tostring(layoutProblem))
		levelState:SetAttribute("Level3_ResolvedSeed", layout.ResolvedSeed)
		levelState:SetAttribute("Level3_GenerationAttempt", layout.Attempt)
		levelState:SetAttribute("Level3_UsedFallback", layout.UsedFallbackSeed == true)
		levelState:SetAttribute("Level3_LayoutHash", layout.LayoutHash)
		levelState:SetAttribute("Level3_GeneratorVersion", layout.Version or LayoutGenerator.Version)
		levelState:SetAttribute("Level3_GeneratedRoomCount", #layout.Rooms)
		levelState:SetAttribute("Level3_GeneratedCorridorCount", #layout.Links)
		levelState:SetAttribute("Level3_GeneratedDistrictCount", #layout.Districts)

		levelState:SetAttribute("Level3_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_3_BUILDING_WORLD")
		local manifest = WorldBuilder.Build(layout, generation)
		validateManifest(manifest)
		activeManifest = manifest

		-- Move characters onto solid Level 3 ground before the lobby is parked.
		-- GameManager will place the round party again when entry begins.
		movePlayersToArrival(manifest)
		storeLobby()

		workspace:SetAttribute("SelectedLevel", 3)
		levelState:SetAttribute("Level3_ExitPosition", manifest.ExitPosition)
		levelState:SetAttribute("Level3_MallManagerSpawnRoomId",
			manifest.Layout.Roles.MallManagerSpawnRoomId)
		levelState:SetAttribute("Level3_BlackoutScreamOpeningCount", #manifest.BlackoutScreamOpenings)
		levelState:SetAttribute("Level3_Phase", "READY")

		-- READY is established first so the objective controller may replace it
		-- with its more specific active phase without the adapter overwriting it.
		ObjectiveController.Start(manifest, generation)
		HidingController.Start(manifest, generation)
		-- Bind once to the shared hunt authority. The music timeline may use it
		-- before completion; the final-hall midpoint uses it for the finale chase.
		bindManagerToHunt(manifest, generation)
		MusicSequenceController.Start(manifest, generation)

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
