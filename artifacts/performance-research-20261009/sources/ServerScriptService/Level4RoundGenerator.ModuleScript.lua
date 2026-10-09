-- Level4RoundGenerator
-- GameManager's Build/Cleanup doorway for the Level 4 round "Den Sidste Forestilling" (LEVEL_GENERATORS[4]).
-- The cinema itself is authored (Workspace."Level 4 Cinema Blender") and is never built or destroyed here: Build
-- collects its tagged anchors into a manifest, adds the compatibility parts GameManager expects (Elevator with
-- DoorL/DoorR, MazeStart, ElevatorSpawn), and starts the Light Director, Objective Controller and Usher. Cleanup stops
-- them (each restores what it changed) and destroys only what this module owns. The lobby is not parked: the cinema
-- sits at x=29000, far from it.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

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
	pcall(Usher.Stop)
	pcall(Objectives.Stop)
	pcall(LightDirector.Stop)
	local world = workspace:FindFirstChild(Configuration.ModelName)
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
	if workspace:GetAttribute("SelectedLevel") == Configuration.Level then
		workspace:SetAttribute("SelectedLevel", 1)
	end
end

function Generator.Build()
	Generator.Cleanup()
	generation += 1
	local world = workspace:FindFirstChild(Configuration.ModelName)
	assert(world and world:IsA("Model"), "Workspace." .. Configuration.ModelName .. " is missing")
	local stateFolder = ownedFolder(ReplicatedStorage, Configuration.StateName)
	resetState(stateFolder)
	stateFolder:SetAttribute("Level4_Generation", generation)
	local clientEvent, keypadSubmit, usherMotion = ensureRemotes()
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "ENTERING_LAST_SHOW")
	isolateLevelOneRuntime()

	local ok, result = xpcall(function()
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
