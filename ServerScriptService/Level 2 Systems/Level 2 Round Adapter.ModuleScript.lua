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
local PoolSlideController = require(script.Parent:WaitForChild("Level 2 Pool Slide Controller"))
local Master = require(ReplicatedStorage:WaitForChild("MasterConfiguration"))

local Adapter = {}
local activeManifest
local generation = 0
local levelOneScriptStates
local storedLevelOneEntity
local storedServerLobby

local STORED_LOBBY_NAME = "Level 2 Stored Server Lobby"
local MAX_SEED = 2147483647

-- A manual override only counts when it is a real, usable seed. 0 is the OFF
-- value — it is what the attribute holds once a tester clears it by typing a
-- zero instead of deleting it, and the old `type(value) ~= "number"` guard
-- accepted it as a pinned seed, so every round silently rebuilt seed 0's map.
local function pinnedSeedOverride()
	local requested = workspace:GetAttribute("Level2Seed")
	if type(requested) ~= "number" then return nil end
	if requested ~= requested then return nil end -- NaN
	if requested < 1 or requested >= math.huge then return nil end
	return math.floor(requested) % MAX_SEED
end

-- A fresh seed per round. The wall clock on its own repeats if two rounds start
-- inside the same millisecond, and Random.new()'s entropy on its own can repeat
-- across a server restart, so the clock, fresh entropy and the round counter
-- all feed in. The result is NEVER written back to the Level2Seed attribute.
local function randomRoundSeed(roundNumber)
	local clockPart = DateTime.now().UnixTimestampMillis
	local entropy = Random.new():NextInteger(0, MAX_SEED - 1)
	return (clockPart + entropy + roundNumber * 7919) % (MAX_SEED - 1) + 1
end

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

-- Remove ONLY the terrain Level 2 wrote, and give back the global water look.
--
-- This used to clear one block of ComplexExtent + 700 -- 2100 x 200 x 2100 studs
-- centred on the complex -- whatever Level 2 had actually written. Anything
-- else with terrain inside that volume was erased along with the poolrooms, and
-- the volume is far larger than the level itself.
--
-- It does not have to guess: `addWater` in the World Builder is the ONLY place
-- Level 2 writes terrain, and it records every region it fills. So the exact
-- set of regions is on the manifest, and clearing those is both complete and
-- scoped. The margin covers terrain's 4-stud voxel grid, which does not align
-- to the authored rectangles.
--
-- The wide block survives ONLY as the no-manifest fallback -- recovering after a
-- crash or a reload, where nothing recorded what was written and the alternative
-- is leaving a flooded complex behind. That path is announced, because it is the
-- one that can take terrain that was never ours.
local TERRAIN_VOXEL_MARGIN = 8

local function clearOwnedTerrain(manifest)
	local regions = manifest and manifest.WaterRegions
	if type(regions) == "table" and #regions > 0 then
		local margin = Vector3.new(TERRAIN_VOXEL_MARGIN, TERRAIN_VOXEL_MARGIN, TERRAIN_VOXEL_MARGIN)
		for _, region in ipairs(regions) do
			if typeof(region.CFrame) == "CFrame" and typeof(region.Size) == "Vector3" then
				Terrain:FillBlock(region.CFrame, region.Size + margin, Enum.Material.Air)
			end
		end
	else
		local extent = Configuration.ComplexExtent
		local center = manifest and manifest.TerrainCenter or Vector3.new(
			Configuration.WorldCenterX or 0, -16, Configuration.WorldCenterZ or 0)
		local size = manifest and manifest.TerrainSize
			or Vector3.new(extent + 700, 200, extent + 700)
		warn("[Level 2] no recorded water regions; clearing the whole declared"
			.. " terrain block as a recovery fallback")
		Terrain:FillBlock(CFrame.new(center), size, Enum.Material.Air)
	end

	-- The global water APPEARANCE is not Level 2's to keep. Restore whatever was
	-- there before this build, so the lobby and the other levels stop inheriting
	-- the poolrooms' water.
	local previous = manifest and manifest.PreviousWaterAppearance
	if type(previous) == "table" then
		if typeof(previous.WaterColor) == "Color3" then Terrain.WaterColor = previous.WaterColor end
		if type(previous.WaterTransparency) == "number" then
			Terrain.WaterTransparency = previous.WaterTransparency
		end
		if type(previous.WaterReflectance) == "number" then
			Terrain.WaterReflectance = previous.WaterReflectance
		end
		if type(previous.WaterWaveSize) == "number" then
			Terrain.WaterWaveSize = previous.WaterWaveSize
		end
		if type(previous.WaterWaveSpeed) == "number" then
			Terrain.WaterWaveSpeed = previous.WaterWaveSpeed
		end
	end
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
		workspace:GetAttribute("SelectedLevel") == 2
		or workspace:FindFirstChild("Level 2 Generated World") ~= nil
		or workspace:FindFirstChild("PoolroomsLevel2") ~= nil
		or ServerStorage:FindFirstChild("Level 2 Stored Level 1 Entity") ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)
	PoolSlideController.Stop()
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
		state:SetAttribute("Level2_PumpActivatorUserId" .. tostring(pumpNumber), nil)
		state:SetAttribute("Level2_PumpActivatorPosition" .. tostring(pumpNumber), nil)
	end
	state:SetAttribute("Level2_HallCount", nil)
	state:SetAttribute("Level2_Error", nil)
end

function Adapter.Build()
	Adapter.Cleanup()
	generation += 1

	-- Developer overrides land in the configuration before anything reads it.
	-- Level 2 Configuration is the one config table that is NOT frozen, so this
	-- writes in place; ApplyInto restores the authored value when an override
	-- is cleared rather than leaving the last one stuck.
	Master.ApplyInto(Configuration, "L2")

	local state = getState()
	-- The workspace attribute is a MANUAL testing override only. Never
	-- write the random pick back — doing so froze the map on the first
	-- round's seed for every round after it.
	local pinnedSeed = pinnedSeedOverride()
	local requestedSeed = pinnedSeed or randomRoundSeed(generation)

	state:SetAttribute("Level2_Phase", "GENERATING_LAYOUT")
	state:SetAttribute("Level2_Generation", generation)
	state:SetAttribute("Level2_Seed", requestedSeed)
	state:SetAttribute("Level2_RequestedSeed", requestedSeed)
	-- Visible in the state folder so "why is the map the same?" is one glance.
	state:SetAttribute("Level2_SeedPinned", pinnedSeed ~= nil)
	state:SetAttribute("Level2_RandomRecoverySeed", nil)
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
		-- Only an unpinned round may fall back to another random stride; a pinned
		-- seed keeps its deterministic recovery so a failure stays reproducible.
		local layout = LayoutGenerator.Generate(requestedSeed, {
			AllowRandomRecovery = pinnedSeed == nil,
		})
		state:SetAttribute("Level2_RandomRecoverySeed", layout.RandomRecoverySeed)
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
		local poolSlideSession, poolSlideError = PoolSlideController.Start(manifest, generation)
		if not poolSlideSession then
			error("[Level 2] Pool Slide encounter did not start: " .. tostring(poolSlideError))
		end
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
