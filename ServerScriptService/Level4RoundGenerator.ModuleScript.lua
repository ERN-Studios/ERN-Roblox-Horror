-- Level4RoundGenerator
-- GameManager's Build/Cleanup doorway for the Level 4 round "Den Sidste Forestilling" (LEVEL_GENERATORS[4]).
-- The authored cinema stays in ServerStorage until Build mounts the same instance. Build collects its tagged
-- anchors, adds the compatibility parts GameManager expects, and starts the round systems. Cleanup restores
-- those systems before parking the cinema; only round-owned compatibility objects are destroyed.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local WorldStorage = require(script.Parent:WaitForChild("LevelWorldStorage"))

local Systems = script.Parent:WaitForChild("Level 4 Systems")
local Configuration = require(Systems:WaitForChild("Level 4 Configuration"))
local LightDirector = require(Systems:WaitForChild("Level 4 Light Director"))
local Objectives = require(Systems:WaitForChild("Level 4 Objective Controller"))
local Usher = require(Systems:WaitForChild("Level 4 Usher Controller"))

local Generator = {}

local COMPAT_ATTRIBUTE = "Level4_CompatibilityMarker"
local USHER_VISUAL_NAME = "Level 4 Usher Visual"
local LEVEL_ONE_RUNTIME_SCRIPTS = { "EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager" }

local generation = 0
local activeManifest = nil
local levelOneScriptStates = nil
local doorStateWorld, doorStates = nil, {}
local persistentCollision = nil
local persistentPlayers, watchedPlayers, persistentConnections = {}, {}, {}

-- Capture neutral authored doors before their first activation. PushDoors caches its leaf basis at startup,
-- so every re-entry must restore that basis while physics and the embedded server script are parked.
local function rememberDoors(world)
	if doorStateWorld == world then return end
	doorStateWorld = world
	table.clear(doorStates)
	local folder = world:FindFirstChild("Doors")
	if not folder then return end
	for _, door in ipairs(folder:GetChildren()) do
		local hingePart = door:IsA("Model") and door:FindFirstChild("Hinge")
		local leaf = door:IsA("Model") and door:FindFirstChild("Leaf")
		local hinge = hingePart and hingePart:FindFirstChildOfClass("HingeConstraint")
		if hinge and leaf and leaf:IsA("BasePart") then
			doorStates[#doorStates + 1] = {
				Leaf = leaf, CFrame = leaf.CFrame, Anchored = leaf.Anchored, CanCollide = leaf.CanCollide,
				Hinge = hinge, Enabled = hinge.Enabled, TargetAngle = hinge.TargetAngle,
			}
		end
	end
end

local function resetDoors(world)
	if world ~= doorStateWorld then return end
	for _, state in ipairs(doorStates) do
		if state.Leaf:IsDescendantOf(world) and state.Hinge:IsDescendantOf(world) then
			state.Hinge.Enabled = false
			state.Leaf.CFrame = state.CFrame
			state.Leaf.AssemblyLinearVelocity = Vector3.zero
			state.Leaf.AssemblyAngularVelocity = Vector3.zero
			state.Leaf.Anchored = state.Anchored
			state.Leaf.CanCollide = state.CanCollide
			state.Hinge.TargetAngle = state.TargetAngle
			state.Hinge.Enabled = state.Enabled
		end
	end
end

local function removePersistentPlayer(player)
	if persistentPlayers[player] then
		persistentPlayers[player] = nil
		if persistentCollision then persistentCollision:RemovePersistentPlayer(player) end
	end
end

local function syncPersistentPlayer(player)
	local eligible = player.Parent == Players and player:GetAttribute("InRound") == true
		and player:GetAttribute("Level6PlaygroundPreview") ~= true
		and player:GetAttribute("Level2NewMapPreview") ~= true
	if eligible and persistentCollision then
		if not persistentPlayers[player] then
			persistentCollision:AddPersistentPlayer(player)
			persistentPlayers[player] = true
		end
	else
		removePersistentPlayer(player)
	end
end

local function unwatchPersistentPlayer(player)
	for _, connection in ipairs(watchedPlayers[player] or {}) do connection:Disconnect() end
	watchedPlayers[player] = nil
	removePersistentPlayer(player)
end

local function watchPersistentPlayer(player)
	if watchedPlayers[player] then return end
	local connections = {}
	watchedPlayers[player] = connections
	for _, attribute in ipairs({"InRound", "Level6PlaygroundPreview", "Level2NewMapPreview"}) do
		connections[#connections + 1] = player:GetAttributeChangedSignal(attribute):Connect(function()
			syncPersistentPlayer(player)
		end)
	end
	syncPersistentPlayer(player)
end

local function stopPersistence()
	for _, connection in ipairs(persistentConnections) do connection:Disconnect() end
	table.clear(persistentConnections)
	for player in pairs(watchedPlayers) do unwatchPersistentPlayer(player) end
	for player in pairs(persistentPlayers) do removePersistentPlayer(player) end
	persistentCollision = nil
end

local function startPersistence(world)
	stopPersistence()
	local collision = world:FindFirstChild("Collision")
	assert(collision and collision:IsA("Model"), "Level 4 Collision model is missing")
	-- Lobby players do not receive the entire floor. Entrants keep the proven persistent floor contract.
	collision.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	persistentCollision = collision
	persistentConnections[#persistentConnections + 1] = Players.PlayerAdded:Connect(watchPersistentPlayer)
	persistentConnections[#persistentConnections + 1] = Players.PlayerRemoving:Connect(unwatchPersistentPlayer)
	for _, player in ipairs(Players:GetPlayers()) do watchPersistentPlayer(player) end
end

local function ownedFolder(parent, name, className)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new(className or "Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function ensureRemotes()
	local folder = ownedFolder(ReplicatedStorage, Configuration.RemotesName)
	local function remote(name, className)
		local r = folder:FindFirstChild(name)
		if r and not r:IsA(className) then r:Destroy(); r = nil end
		if not r then
			r = Instance.new(className)
			r.Name = name
			r.Parent = folder
		end
		return r
	end
	return remote("ClientEvent", "RemoteEvent"), remote("KeypadSubmit", "RemoteEvent"),
		remote("UsherMotion", "UnreliableRemoteEvent")
end

local STATE_DEFAULTS = {
	Level4_Phase = "Idle", Level4_PowerState = "Preview", Level4_SequenceProgress = 0, Level4_SequenceGoal = 0,
	Level4_ReelsCollected = 0, Level4_ReelsLoaded = 0, Level4_ReelGoal = 0, Level4_BreakerHolder = 0,
	Level4_FuseUntil = 0, Level4_BreakerEngaged = false, Level4_ExitUnlocked = false, Level4_UsherActive = false,
	Level4_UsherState = "Dormant", Level4_UsherTarget = 0, Level4_ThreadScreen = 0, Level4_Escalation = 0,
	Level4_Generation = 0,
}

local function resetState(folder)
	for k, v in pairs(STATE_DEFAULTS) do folder:SetAttribute(k, v) end
	for _, k in ipairs({ "Level4_ExitPosition", "Level4_NotePosition", "Level4_PowerUpStartedAt", "Level4_Error" }) do
		folder:SetAttribute(k, nil)
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
	for object, wasEnabled in pairs(levelOneScriptStates) do
		if object.Parent then object.Enabled = wasEnabled end
	end
	levelOneScriptStates = nil
end

local function destroyCompatibilityObjects()
	for _, object in ipairs(workspace:GetChildren()) do
		if object:GetAttribute(COMPAT_ATTRIBUTE) == true then object:Destroy() end
	end
end

local function tagged(world, tag)
	local list = {}
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsDescendantOf(world) then list[#list + 1] = inst end
	end
	return list
end

local function bySlot(list)
	table.sort(list, function(a, b) return (a:GetAttribute("Slot") or 99) < (b:GetAttribute("Slot") or 99) end)
	return list
end

local function partOf(inst)
	if inst:IsA("BasePart") then return inst end
	return inst:IsA("Model") and (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)) or nil
end

local function collectManifest(world)
	for tag, minimum in pairs(Configuration.Required) do
		local n = #tagged(world, tag)
		assert(n >= minimum, ("Level 4 cinema has %d %s (needs %d)"):format(n, tag, minimum))
	end
	local manifest = {
		World = world,
		Templates = ServerStorage:FindFirstChild(Configuration.TemplatesName),
		Audio = Configuration.Audio,
		EntrySpawns = bySlot(tagged(world, "L4EntrySpawn")),
		ExitSafeSpawns = bySlot(tagged(world, "L4ExitSafeSpawn")),
		NoteSpots = tagged(world, "L4NoteSpot"),
		Breakers = tagged(world, "L4Breaker"),
		ReelSpots = tagged(world, "L4ReelSpot"),
		HideZones = tagged(world, "L4HideZone"),
		Projectors = {},
		Screens = {},
	}
	local main = tagged(world, "L4MainBreaker")[1]
	manifest.MainBreaker = main
	manifest.MainBreakerLever = main:FindFirstChild("Lever", true) or partOf(main)
	manifest.FuseSocket = partOf(tagged(world, "L4FuseSocket")[1])
	manifest.ExitScreen = partOf(tagged(world, "L4ExitScreen")[1])
	for _, projector in ipairs(tagged(world, "L4Projector")) do
		local screen = projector:GetAttribute("Screen")
		assert(type(screen) == "number" and not manifest.Projectors[screen], "Level 4 projector Screen attribute invalid")
		manifest.Projectors[screen] = projector
	end
	for _, marker in ipairs(tagged(world, "L4Screen")) do
		local screen = marker:GetAttribute("Screen")
		assert(type(screen) == "number" and not manifest.Screens[screen], "Level 4 screen Screen attribute invalid")
		manifest.Screens[screen] = partOf(marker)
	end
	for i = 1, Configuration.Reels.Goal do
		assert(manifest.Projectors[i] and manifest.Screens[i], "Level 4 needs projector + screen " .. i)
	end
	manifest.ArcadeCode = tagged(world, "L4ArcadeCode")[1]
	manifest.PrizeKeypad = partOf(tagged(world, "L4PrizeKeypad")[1] or Instance.new("Folder"))
	manifest.PrizeCase = tagged(world, "L4PrizeCase")[1]
	-- the dead zones (the Usher's homes) never cover the start or the main breaker
	local protected = {}
	for _, s in ipairs(manifest.EntrySpawns) do protected[#protected + 1] = s.Position end
	protected[#protected + 1] = manifest.MainBreakerLever.Position
	manifest.ProtectedLightPoints = protected
	return manifest
end

-- GameManager places the party on Workspace.ElevatorSpawn (rows ahead of the pad along its LookVector) and opens
-- Workspace.Elevator's doors; the cinema has no elevator, so the doors live out of sight.
local function buildCompatibility(manifest)
	local first = manifest.EntrySpawns[1]
	local origin = first.Position
	local ahead = Vector3.zero
	for i = 2, #manifest.EntrySpawns do ahead += manifest.EntrySpawns[i].Position - origin end
	ahead = Vector3.new(ahead.X, 0, ahead.Z)
	local look = ahead.Magnitude > 0.5 and ahead.Unit or first.CFrame.LookVector
	local floorY = first.Position.Y + first.Size.Y * 0.5
	local padCFrame = CFrame.lookAt(Vector3.new(origin.X, floorY - 0.5, origin.Z),
		Vector3.new(origin.X + look.X, floorY - 0.5, origin.Z + look.Z))

	local function part(name, size, cf)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p:SetAttribute(COMPAT_ATTRIBUTE, true)
		return p
	end
	local pad = part("ElevatorSpawn", Vector3.new(4, 1, 4), padCFrame)
	pad.Parent = workspace
	local start = part("MazeStart", Vector3.new(4, 1, 4), padCFrame)
	start.Parent = workspace
	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute(COMPAT_ATTRIBUTE, true)
	local hidden = CFrame.new(origin.X, -520, origin.Z)
	part("DoorL", Vector3.new(1, 8, 4), hidden * CFrame.new(0, 0, -2)).Parent = elevator
	part("DoorR", Vector3.new(1, 8, 4), hidden * CFrame.new(0, 0, 2)).Parent = elevator
	elevator.Parent = workspace
	manifest.ElevatorSpawn, manifest.MazeStart, manifest.Elevator = pad, start, elevator
end

local function publishUsherVisual(manifest)
	local existing = ReplicatedStorage:FindFirstChild(USHER_VISUAL_NAME)
	if existing then existing:Destroy() end
	local template = manifest.Templates and manifest.Templates:FindFirstChild("Usher")
	if not template then
		warn("[Level 4] ServerStorage.Level 4 Templates.Usher is missing; clients draw a placeholder")
		return
	end
	local visual = template:Clone()
	visual.Name = USHER_VISUAL_NAME
	visual.Parent = ReplicatedStorage
end

function Generator.GetManifest()
	return activeManifest
end

function Generator.Cleanup()
	local stopErrors = {}
	for _, system in ipairs({{"Usher", Usher}, {"Objectives", Objectives}, {"LightDirector", LightDirector}}) do
		local ok, problem = pcall(system[2].Stop)
		if not ok then stopErrors[#stopErrors + 1] = system[1] .. ": " .. tostring(problem) end
	end
	local world = WorldStorage.Get(4)
	local runtime = world and world:FindFirstChild(Configuration.RuntimeName)
	if runtime then runtime:Destroy() end
	destroyCompatibilityObjects()
	local visual = ReplicatedStorage:FindFirstChild(USHER_VISUAL_NAME)
	if visual then visual:Destroy() end
	restoreLevelOneRuntime()
	activeManifest = nil
	local folder = ReplicatedStorage:FindFirstChild(Configuration.StateName)
	if folder then resetState(folder) end
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("Level4RoundActive", false)
	if #stopErrors > 0 then
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		error("Level 4 cleanup failed: " .. table.concat(stopErrors, "; "))
	end
	stopPersistence()
	WorldStorage.Deactivate(4)
	resetDoors(world)
	if workspace:GetAttribute("SelectedLevel") == Configuration.Level then
		workspace:SetAttribute("SelectedLevel", 1)
	end
end

function Generator.Build()
	Generator.Cleanup()
	generation += 1
	local world = WorldStorage.Get(4)
	assert(world and world:IsA("Model"), "Authored " .. Configuration.ModelName .. " is missing")
	rememberDoors(world)
	resetDoors(world)
	local stateFolder = ownedFolder(ReplicatedStorage, Configuration.StateName)
	resetState(stateFolder)
	stateFolder:SetAttribute("Level4_Generation", generation)
	local clientEvent, keypadSubmit, usherMotion = ensureRemotes()
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "ENTERING_LAST_SHOW")
	isolateLevelOneRuntime()

	local ok, result = xpcall(function()
		startPersistence(world)
		assert(WorldStorage.Activate(4) == world, "Level 4 authored map changed during activation")
		local manifest = collectManifest(world)
		manifest.State = stateFolder
		manifest.ClientEvent = clientEvent
		manifest.KeypadSubmit = keypadSubmit
		manifest.UsherMotion = usherMotion
		local runtime = Instance.new("Folder")
		runtime.Name = Configuration.RuntimeName
		runtime.Parent = world
		manifest.Runtime = runtime
		buildCompatibility(manifest)
		publishUsherVisual(manifest)
		activeManifest = manifest

		workspace:SetAttribute("SelectedLevel", Configuration.Level)
		local zones = LightDirector.Start(manifest, generation)
		stateFolder:SetAttribute("Level4_ZoneCount", zones)
		Objectives.Start(manifest, generation, LightDirector, Usher)
		stateFolder:SetAttribute("Level4_NavNodes", Usher.Start(manifest, generation, LightDirector, Objectives))
		workspace:SetAttribute("Level4RoundActive", true)
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return world
	end, debug.traceback)

	if not ok then
		Generator.Cleanup()
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		stateFolder:SetAttribute("Level4_Error", tostring(result))
		error(result)
	end
	return result
end

return Generator
