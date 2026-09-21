--!strict
-- Level 4 Round Adapter
--
-- GameManager-facing lifecycle owner for Level 4, deliberately shaped like the
-- Level 3 adapter: everything Level 4 touches outside its generated world is
-- acquired here and given back by Cleanup() -- the persistent lobby, the Level
-- 1 server scripts, the Level 1 Workspace.Entity, the compatibility markers and
-- the replicated state.
--
-- LEVEL 4 IS DEV-ONLY AND THIS IS WHERE THAT IS ENFORCED AT BUILD TIME.
-- Routing refuses to hand a normal player level 4 and GameManager refuses to
-- start one, but a generator that would happily build a world for anybody who
-- called it is one typo away from shipping an unfinished level. Build() raises
-- unless workspace.Level4DevEnabled is true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Configuration = require(script.Parent:WaitForChild("Level 4 Configuration"))
local PlanGenerator = require(script.Parent:WaitForChild("Level 4 Plan Generator"))
local WorldBuilder = require(script.Parent:WaitForChild("Level 4 World Builder"))
local ObjectiveController = require(script.Parent:WaitForChild("Level 4 Objective Controller"))
local NeighbourController = require(script.Parent:WaitForChild("Level 4 Neighbour Controller"))
local NoiseRegistry = require(ServerScriptService:WaitForChild("NoiseRegistry"))

local Adapter = {}

local activeManifest: any = nil
local generation = 0
local levelOneScriptStates: {[BaseScript]: boolean}? = nil
local storedLevelOneEntity: Instance? = nil
local storedServerLobby: Instance? = nil

local STORED_LOBBY_NAME = "Level 4 Stored Server Lobby"
local STORED_LEVEL_ONE_ENTITY_NAME = "Level 4 Stored Level 1 Entity"
local DEV_ATTRIBUTE = "Level4DevEnabled"
local MAX_SEED = 2147483647

-- Identical to Level 2's and Level 3's pinnedSeedOverride, deliberately: 0 is
-- the OFF value a tester leaves behind, not a pinned seed, and this project has
-- shipped that bug twice already.
local function pinnedSeedOverride(): number?
	local requested = workspace:GetAttribute("Level4Seed")
	if type(requested) ~= "number" then return nil end
	if requested ~= requested then return nil end -- NaN
	if requested < 1 or requested >= MAX_SEED then return nil end
	return math.floor(requested)
end

local LEVEL_ONE_RUNTIME_SCRIPTS = {"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}

local function ownedFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then return existing end
	if existing then existing:Destroy() end
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
end

local function setScriptsEnabled(names: {string}, enabled: boolean)
	for _, name in ipairs(names) do
		-- Recursive: Level 1's runtime scripts live in a "Level 1 Systems"
		-- folder, and a non-recursive lookup silently returns nil there. That
		-- nil is how every Level 2/3 round once started Level 1's fuse puzzle.
		local object = ServerScriptService:FindFirstChild(name, true)
		if object and object:IsA("BaseScript") then object.Enabled = enabled end
	end
end

local function storeLobby()
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then return end
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
	if not stored then return end
	if workspace:FindFirstChild("ServerLobby") then
		-- GameManager already rebuilt a live lobby, so this copy is stale and
		-- must not create duplicate launch zones.
		stored:Destroy()
		return
	end
	stored.Name = "ServerLobby"
	stored.Parent = workspace
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
		if existing and existing ~= stored then existing:Destroy() end
		stored.Name = "Entity"
		stored.Parent = workspace
	end
	storedLevelOneEntity = nil

	if levelOneScriptStates then
		for object, wasEnabled in pairs(levelOneScriptStates) do
			if object.Parent then object.Enabled = wasEnabled end
		end
	elseif forceEnableScripts then
		setScriptsEnabled(LEVEL_ONE_RUNTIME_SCRIPTS, true)
	end
	levelOneScriptStates = nil
end

local function destroyCompatibilityObjects()
	for _, name in ipairs({"Elevator", "MazeStart", "ElevatorSpawn"}) do
		for _, object in ipairs(workspace:GetChildren()) do
			if object.Name == name and object:GetAttribute("Level4_CompatibilityMarker") == true then
				object:Destroy()
			end
		end
	end
end

local function destroyGeneratedWorlds()
	for _, parent in ipairs({workspace, ServerStorage}) do
		local stale = parent:FindFirstChild(Configuration.WorldName)
		while stale do
			stale:Destroy()
			stale = parent:FindFirstChild(Configuration.WorldName)
		end
	end
end

-- One authoritative list of every replicated Level 4 attribute. Build and the
-- idle reset both consume it, so the two cannot drift; the handful of values
-- that differ between "fresh round" and "idle" arrive as overrides.
local function applyBaselineReplicatedState(levelState: Folder, overrides: {[string]: any}?)
	local o = overrides or {}
	levelState:SetAttribute("Level4_Phase", o.Phase or "IDLE")
	levelState:SetAttribute("Level4_RequestedSeed", o.RequestedSeed or 0)
	levelState:SetAttribute("Level4_SeedPinned", o.SeedPinned == true)
	levelState:SetAttribute("Level4_ResolvedSeed", 0)
	levelState:SetAttribute("Level4_PlanHash", "")
	levelState:SetAttribute("Level4_Variant", 0)
	levelState:SetAttribute("Level4_VariantName", "")
	levelState:SetAttribute("Level4_GeneratorVersion", PlanGenerator.Version)
	levelState:SetAttribute("Level4_Generation", o.Generation or 0)
	levelState:SetAttribute("Level4_Briefing", Configuration.Objectives.BriefingLine)
	levelState:SetAttribute("Level4_SignalGoal", o.SignalGoal or 0)
	levelState:SetAttribute("Level4_SignalProgress", 0)
	for index = 1, Configuration.Objectives.SignalGoal do
		levelState:SetAttribute("Level4_Signal" .. index, "OFF")
	end
	levelState:SetAttribute("Level4_BeaconUnlocked", false)
	levelState:SetAttribute("Level4_CabinetProgress", 0)
	levelState:SetAttribute("Level4_CabinetGoal", Configuration.Objectives.CabinetControlCount)
	levelState:SetAttribute("Level4_ExitWarningEndsAt", 0)
	levelState:SetAttribute("Level4_ExitOpen", false)
	levelState:SetAttribute("Level4_ExitPosition", nil)
	levelState:SetAttribute("Level4_UnsafeHouses", 0)
	levelState:SetAttribute("Level4_DynamicLightCount", 0)
	levelState:SetAttribute("Level4_WorldDescendants", 0)
	levelState:SetAttribute("Level4_PlanSeconds", 0)
	levelState:SetAttribute("Level4_BuildSeconds", 0)
	levelState:SetAttribute("Level4_NeighbourState", "OFF")
	levelState:SetAttribute("Level4_NeighbourAnimation", "Idle")
	levelState:SetAttribute("Level4_NeighbourTargetUserId", 0)
	levelState:SetAttribute("Level4_NeighbourPathStatus", "OFF")
	levelState:SetAttribute("Level4_NeighbourSpeed", 0)
	levelState:SetAttribute("Level4_NeighbourReason", "")
	levelState:SetAttribute("Level4_NeighbourNoiseX", 0)
	levelState:SetAttribute("Level4_NeighbourNoiseZ", 0)
	levelState:SetAttribute("Level4_NeighbourGoalX", 0)
	levelState:SetAttribute("Level4_NeighbourGoalZ", 0)
	levelState:SetAttribute("Level4_NeighbourAttackSerial", 0)
	levelState:SetAttribute("Level4_Error", nil)
end

local function validateManifest(manifest: any)
	assert(type(manifest) == "table", "Level 4 world builder must return a manifest table")
	local plan = manifest.Plan
	assert(type(plan) == "table", "Level 4 manifest is missing its plan")
	local planValid, planProblem = PlanGenerator.Validate(plan)
	assert(planValid, "Level 4 generated plan failed validation: " .. tostring(planProblem))

	assert(manifest.World and manifest.World:IsA("Model") and manifest.World.Parent == workspace,
		"Level 4 manifest is missing its live World model")
	assert(manifest.World:GetAttribute("Level4_Generation") == generation,
		"Level 4 manifest generation does not match the active build")
	assert(manifest.World:GetAttribute("Level4_PlanHash") == plan.PlanHash,
		"Level 4 world and manifest plan hashes do not match")

	assert(manifest.Elevator and manifest.Elevator:IsA("Model") and manifest.Elevator.Parent == workspace,
		"Level 4 manifest is missing its Elevator compatibility model")
	assert(manifest.Elevator:FindFirstChild("DoorL") and manifest.Elevator:FindFirstChild("DoorR"),
		"Level 4 Elevator needs DoorL and DoorR: GameManager's connectElevator waits on them")
	assert(manifest.ElevatorSpawn and manifest.ElevatorSpawn:IsA("BasePart")
		and manifest.ElevatorSpawn.Parent == workspace and manifest.ElevatorSpawn.CanCollide,
		"Level 4 manifest needs a solid ElevatorSpawn: the entry barrier rays onto it")
	assert(manifest.MazeStart and manifest.MazeStart:IsA("BasePart") and manifest.MazeStart.Parent == workspace,
		"Level 4 manifest is missing its MazeStart compatibility part")

	assert(type(manifest.Lots) == "table" and #manifest.Lots == #plan.Lots,
		"Level 4 manifest lot count does not match its plan")
	local visible = 0
	for _, record in ipairs(manifest.Lots) do
		assert(record.Model and record.Model:IsDescendantOf(manifest.World),
			"Level 4 house " .. tostring(record.Lot.Id) .. " is not part of this world")
		assert(record.PorchSignal and record.PorchSignal:GetAttribute("Level4_PorchSignal") == true,
			"Level 4 house " .. tostring(record.Lot.Id) .. " has no porch signal")
		assert(record.DoorFrame and record.DoorFrame:GetAttribute("Level4_DoorWidth")
			== Configuration.Derived.DoorWidth,
			"Level 4 house " .. tostring(record.Lot.Id) .. " door does not match the derived width")
		visible += 1
	end
	assert(visible >= 8 and visible <= 12,
		"Level 4 must show 8 to 12 houses; this build shows " .. visible)

	for index = 1, Configuration.Objectives.SignalGoal do
		local signal = manifest.Signals[index]
		assert(signal and signal.Prompt and signal.Prompt:IsA("ProximityPrompt"),
			"Level 4 signal " .. index .. " has no prompt")
		assert(signal.Clue and signal.Clue:IsDescendantOf(manifest.World),
			"Level 4 signal " .. index .. " has no VISUAL clue; no task may require hearing")
	end

	local finale = manifest.Finale
	assert(type(finale) == "table" and #finale.Controls == Configuration.Objectives.CabinetControlCount,
		"Level 4 finale needs exactly " .. Configuration.Objectives.CabinetControlCount .. " controls")
	for _, control in ipairs(finale.Controls) do
		assert(control.Prompt.Enabled == false,
			"Level 4 beacon controls must start disabled: the finale is the only lock")
	end
	assert(manifest.EscapeTrigger and manifest.EscapeTrigger:IsDescendantOf(manifest.World),
		"Level 4 manifest is missing its escape trigger")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsDescendantOf(manifest.World),
		"Level 4 manifest is missing its exit safe spawn")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 4 manifest is missing its exit position")
	assert(manifest.Tower and manifest.Tower:IsDescendantOf(manifest.World),
		"Level 4 manifest is missing the landmark tower")
	assert(type(manifest.PatrolNodes) == "table" and #manifest.PatrolNodes >= 4,
		"Level 4 manifest needs patrol nodes")
	assert(manifest.NeighbourRuntime and manifest.NeighbourRuntime:IsDescendantOf(manifest.World),
		"Level 4 manifest is missing the Neighbour runtime folder")

	-- The performance budget. These are the two numbers that decide whether a
	-- phone can run this, and neither of them is something to keep by eye.
	local lights = manifest.DynamicLightCount
	assert(type(lights) == "number" and lights <= Configuration.Performance.MaximumDynamicLights,
		("Level 4 built %s dynamic lights; the budget is %d")
			:format(tostring(lights), Configuration.Performance.MaximumDynamicLights))
	local descendants = #manifest.World:GetDescendants()
	assert(descendants <= Configuration.Performance.MaximumWorldDescendants,
		("Level 4 world holds %d instances; the budget is %d")
			:format(descendants, Configuration.Performance.MaximumWorldDescendants))
	return descendants
end

local function movePlayersToArrival(manifest: any)
	local spawnPart = manifest.ElevatorSpawn :: BasePart
	local arrivals = Players:GetPlayers()
	local columns = math.min(6, math.max(1, #arrivals))
	local rows = math.ceil(#arrivals / columns)
	local moved = 0
	for _, player in ipairs(arrivals) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local column = moved % columns
			local row = math.floor(moved / columns)
			moved += 1
			character:PivotTo(spawnPart.CFrame
				* CFrame.new((column - (columns - 1) / 2) * 4, 4, (row - (rows - 1) / 2) * 4))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function Adapter.GetManifest()
	return activeManifest
end

function Adapter.Cleanup()
	local recoveringPersistedState = levelOneScriptStates == nil and (
		workspace:GetAttribute("SelectedLevel") == 4
		or workspace:FindFirstChild(Configuration.WorldName) ~= nil
		or ServerStorage:FindFirstChild(STORED_LEVEL_ONE_ENTITY_NAME) ~= nil
		or ServerStorage:FindFirstChild(STORED_LOBBY_NAME) ~= nil
	)

	local ok, problem = pcall(NeighbourController.Stop)
	if not ok then warn("[Level 4] Neighbour cleanup failed: " .. tostring(problem)) end
	ok, problem = pcall(ObjectiveController.Stop)
	if not ok then warn("[Level 4] Objective cleanup failed: " .. tostring(problem)) end
	-- One global noise list serves every level and only one level is ever live,
	-- so the level tearing its round down drops the whole list.
	NoiseRegistry.Clear()

	local levelState = state()
	levelState:SetAttribute("Level4_Phase", "CLEANING")

	if activeManifest and activeManifest.World and activeManifest.World.Parent then
		activeManifest.World:Destroy()
	end
	activeManifest = nil
	destroyGeneratedWorlds()
	destroyCompatibilityObjects()
	restoreLobby()
	restoreLevelOneRuntime(recoveringPersistedState)

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level4SignalProgress", 0)
	workspace:SetAttribute("Level4SignalGoal", 0)
	workspace:SetAttribute("Level4BeaconUnlocked", false)
	workspace:SetAttribute("Level4ExitOpen", false)
	workspace:SetAttribute("Level4NeighbourActive", false)

	if workspace:GetAttribute("SelectedLevel") == 4 then
		workspace:SetAttribute("SelectedLevel", 1)
	end
	applyBaselineReplicatedState(levelState, nil)
end

function Adapter.Build()
	Adapter.Cleanup()
	-- The dev gate, enforced at the only point that matters: the place has to
	-- be told, explicitly, that Level 4 may be built. Routing and GameManager
	-- both check as well; this is the one that cannot be routed around.
	assert(workspace:GetAttribute(DEV_ATTRIBUTE) == true,
		"Level 4 is a development build. Set workspace:SetAttribute(\"" .. DEV_ATTRIBUTE
			.. "\", true) before starting a Level 4 round.")
	generation += 1

	local levelState = state()
	ensureRemotes()

	local pinnedSeed = pinnedSeedOverride()
	local requestedSeed = pinnedSeed
		or (DateTime.now().UnixTimestampMillis % (MAX_SEED - 1) + 1)

	applyBaselineReplicatedState(levelState, {
		Phase = "GENERATING_PLAN",
		RequestedSeed = requestedSeed,
		SeedPinned = pinnedSeed ~= nil,
		Generation = generation,
		SignalGoal = Configuration.Objectives.SignalGoal,
	})

	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_4_GENERATING_PLAN")
	workspace:SetAttribute("Level4SignalProgress", 0)
	workspace:SetAttribute("Level4SignalGoal", Configuration.Objectives.SignalGoal)
	workspace:SetAttribute("Level4BeaconUnlocked", false)
	workspace:SetAttribute("Level4ExitOpen", false)

	isolateLevelOneRuntime()

	-- GameManager treats a raised error as a failed generation, so every
	-- failure path restores the lobby and the Level 1 runtime before re-raising.
	local success, result = xpcall(function()
		local planBegan = os.clock()
		local plan = PlanGenerator.Generate(requestedSeed)
		levelState:SetAttribute("Level4_PlanSeconds", math.round((os.clock() - planBegan) * 100) / 100)
		local planValid, planProblem = PlanGenerator.Validate(plan)
		assert(planValid, "Level 4 plan validation failed: " .. tostring(planProblem))
		levelState:SetAttribute("Level4_ResolvedSeed", plan.ResolvedSeed)
		levelState:SetAttribute("Level4_PlanHash", plan.PlanHash)
		levelState:SetAttribute("Level4_Variant", plan.Variant)
		levelState:SetAttribute("Level4_VariantName", plan.VariantName)
		levelState:SetAttribute("Level4_GeneratorVersion", plan.Version)

		levelState:SetAttribute("Level4_Phase", "BUILDING_WORLD")
		workspace:SetAttribute("LoadStage", "LEVEL_4_BUILDING_WORLD")
		local buildBegan = os.clock()
		local manifest = WorldBuilder.Build(plan, generation)
		local descendants = validateManifest(manifest)
		activeManifest = manifest
		levelState:SetAttribute("Level4_BuildSeconds", math.round((os.clock() - buildBegan) * 100) / 100)
		levelState:SetAttribute("Level4_WorldDescendants", descendants)
		levelState:SetAttribute("Level4_DynamicLightCount", manifest.DynamicLightCount)

		-- Characters go onto solid Level 4 ground BEFORE the lobby is parked;
		-- GameManager places the round party again when entry begins.
		movePlayersToArrival(manifest)
		storeLobby()

		workspace:SetAttribute("SelectedLevel", 4)
		levelState:SetAttribute("Level4_ExitPosition", manifest.ExitPosition)
		levelState:SetAttribute("Level4_Phase", "READY")

		-- READY first, so the objective controller may replace it with its own
		-- more specific phase without the adapter overwriting it afterwards.
		ObjectiveController.Start(manifest, generation)
		NeighbourController.Start(manifest, generation)

		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return manifest.World
	end, debug.traceback)

	if not success then
		Adapter.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		levelState:SetAttribute("Level4_Phase", "ERROR")
		levelState:SetAttribute("Level4_Error", tostring(result))
		error(result)
	end
	return result
end

return Adapter
