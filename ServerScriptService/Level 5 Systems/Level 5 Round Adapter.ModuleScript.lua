--!strict
-- Level 5 map-only preview lifecycle. Independent of Level 4 and its gameplay.
-- GameManager owns entry, Back to Lobby and round cleanup. This module never
-- sets Escaped/PuzzleWon, loads an entity or grants completion/rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local DevAccess = require(ReplicatedStorage:WaitForChild("DevAccess"))

local Adapter = {}
local WORLD_NAME = "Level 5 Generated World"
local STATE_NAME = "Level 5 State"
local BACKUP_NAME = "Level 5 Runtime Backup"
local LOBBY_NAME = "Level 5 Stored Server Lobby"
local ENTITY_NAME = "Level 5 Stored Level 1 Entity"
local ORIGIN = Vector3.new(17000, 24, 0)
local OWNED = "Level5Owned"
local COMPATIBILITY = "Level5_CompatibilityMarker"
local SCRIPT_NAMES = {"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}
local generation = 0
local manifest: any = nil

-- The client reads this same profile from the replicated state, so there are
-- no separately tuned server/client constants. Server properties are touched
-- only for an edit-mode architectural preview, never for a runtime lobby.
local LIGHTING_PROFILE: {[string]: any} = {
	ClockTime = 13.5,
	Brightness = 1.8,
	Ambient = Color3.fromRGB(115, 108, 90),
	OutdoorAmbient = Color3.fromRGB(94, 90, 78),
	ColorShift_Top = Color3.new(0, 0, 0),
	ColorShift_Bottom = Color3.new(0, 0, 0),
	GlobalShadows = true,
	EnvironmentDiffuseScale = 0.35,
	EnvironmentSpecularScale = 0.15,
	ExposureCompensation = -0.1,
	FogColor = Color3.fromRGB(194, 187, 164),
	FogStart = 300,
	FogEnd = 1100,
}
local ATMOSPHERE_PROFILE: {[string]: any} = {
	Density = 0.06, Offset = 0, Haze = 0.8, Glare = 0,
	Color = Color3.fromRGB(241, 233, 209),
	Decay = Color3.fromRGB(174, 170, 148),
}

local function ownedFolder(parent: Instance, name: string): Folder
	local found = parent:FindFirstChild(name)
	if found then
		assert(found:IsA("Folder") and found:GetAttribute(OWNED) == true,
			"Level 5 refuses to replace an unrelated instance named " .. name)
		return found :: Folder
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute(OWNED, true)
	folder.Parent = parent
	return folder
end

local function state(): Folder
	return ownedFolder(ReplicatedStorage, STATE_NAME)
end

local function backup(): Folder
	return ownedFolder(ServerStorage, BACKUP_NAME)
end

local function snapshotProperties(target: Instance, parent: Instance, name: string, values: {[string]: any})
	local record = Instance.new("ObjectValue")
	record.Name, record.Value = name, target
	for property in pairs(values) do record:SetAttribute(property, (target :: any)[property]) end
	record.Parent = parent
end

local function editLighting()
	if RunService:IsRunning() then return end
	local saved = backup()
	snapshotProperties(Lighting, saved, "LightingSnapshot", LIGHTING_PROFILE)
	for property, value in pairs(LIGHTING_PROFILE) do (Lighting :: any)[property] = value end
	local air = Lighting:FindFirstChildOfClass("Atmosphere")
	if air then
		snapshotProperties(air, saved, "AtmosphereSnapshot", ATMOSPHERE_PROFILE)
		for property, value in pairs(ATMOSPHERE_PROFILE) do (air :: any)[property] = value end
	end
end

local function preserveRuntime()
	local saved = backup()
	for _, name in ipairs(SCRIPT_NAMES) do
		local object = ServerScriptService:FindFirstChild(name, true)
		if object and object:IsA("BaseScript") then
			local record = Instance.new("ObjectValue")
			record.Name, record.Value = "ScriptState", object
			record:SetAttribute("WasEnabled", object.Enabled)
			record.Parent = saved
			object.Enabled = false
		end
	end
	-- Existing Level 1 compatibility geometry is preserved intact, not destroyed.
	local compatibility = Instance.new("Folder")
	compatibility.Name = "PreservedCompatibility"
	compatibility.Parent = saved
	for _, name in ipairs({"Elevator", "ElevatorSpawn", "MazeStart"}) do
		for _, object in ipairs(workspace:GetChildren()) do
			if object.Name == name then object.Parent = compatibility end
		end
	end
	local entity = workspace:FindFirstChild("Entity")
	if entity then
		assert(ServerStorage:FindFirstChild(ENTITY_NAME) == nil, "Level 5 entity backup already exists")
		entity:SetAttribute("Level5OriginalName", entity.Name)
		entity.Name, entity.Parent = ENTITY_NAME, ServerStorage
	end
end

local function parkLobby()
	-- Studio's real Back to Lobby route requires its existing spawn to remain
	-- in Workspace. This map is 17,000 studs away, so keeping that local floor
	-- does not expose it from the preview. Published reserved servers teleport
	-- players home and may still park their unused lobby as before.
	if RunService:IsStudio() then return end
	local lobby = workspace:FindFirstChild("ServerLobby")
	if not lobby then return end
	assert(ServerStorage:FindFirstChild(LOBBY_NAME) == nil, "Level 5 lobby backup already exists")
	lobby:SetAttribute("Level5OriginalName", lobby.Name)
	lobby.Name, lobby.Parent = LOBBY_NAME, ServerStorage
end

local function restoreStored(name: string, expectedName: string)
	local object = ServerStorage:FindFirstChild(name)
	if not object or object:GetAttribute("Level5OriginalName") ~= expectedName then return end
	if workspace:FindFirstChild(expectedName) then
		-- Another owner has rebuilt the object; never delete its work. Leave the
		-- preserved copy available to inspect rather than create a duplicate.
		warn("[Level 5] Kept preserved " .. name .. "; Workspace already contains " .. expectedName)
		return
	end
	object:SetAttribute("Level5OriginalName", nil)
	object.Name, object.Parent = expectedName, workspace
end

local function restoreRuntime()
	restoreStored(LOBBY_NAME, "ServerLobby")
	restoreStored(ENTITY_NAME, "Entity")
	local saved = ServerStorage:FindFirstChild(BACKUP_NAME)
	if not saved or saved:GetAttribute(OWNED) ~= true then return end
	for _, record in ipairs(saved:GetChildren()) do
		if record:IsA("ObjectValue") and record.Value and record.Value.Parent then
			if record.Name == "ScriptState" and record.Value:IsA("BaseScript") then
				(record.Value :: BaseScript).Enabled = record:GetAttribute("WasEnabled") == true
			elseif record.Name == "LightingSnapshot" or record.Name == "AtmosphereSnapshot" then
				for property, value in pairs(record:GetAttributes()) do
					local ok, err = pcall(function() (record.Value :: any)[property] = value end)
					if not ok then warn("[Level 5] Lighting restore: " .. tostring(err)) end
				end
			end
		end
	end
	local preserved = saved:FindFirstChild("PreservedCompatibility")
	if preserved then
		for _, object in ipairs(preserved:GetChildren()) do
			if workspace:FindFirstChild(object.Name) == nil then object.Parent = workspace end
		end
		if #preserved:GetChildren() > 0 then
			warn("[Level 5] Preserved compatibility objects retained because replacement names already exist")
			-- Remove consumed snapshots so a second Cleanup cannot restore stale
			-- values over a new round, while retaining unresolved geometry.
			for _, child in ipairs(saved:GetChildren()) do
				if child ~= preserved then child:Destroy() end
			end
			return
		end
	end
	saved:Destroy()
end

local function part(parent: Instance, name: string, frame: CFrame, size: Vector3): Part
	local object = Instance.new("Part")
	object.Name, object.CFrame, object.Size = name, frame, size
	object.Anchored = true
	object.TopSurface, object.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	object.Color, object.Material = Color3.fromRGB(202, 193, 169), Enum.Material.SmoothPlastic
	object:SetAttribute(COMPATIBILITY, true)
	object.Parent = parent
	return object
end

local function buildCompatibility(spawnFrame: CFrame)
	local pad = part(workspace, "ElevatorSpawn", spawnFrame * CFrame.new(0, -0.25, 0), Vector3.new(16, 0.5, 16))
	pad.Transparency = 1
	pad.CanCollide, pad.CanQuery, pad.CanTouch = true, true, false
	local marker = part(workspace, "MazeStart", spawnFrame, Vector3.new(2, 0.25, 2))
	marker.Transparency, marker.CanCollide, marker.CanTouch = 1, false, false
	local elevator = Instance.new("Model")
	elevator.Name = "Elevator"
	elevator:SetAttribute(COMPATIBILITY, true)
	elevator.Parent = workspace
	-- This framed entrance stands behind the arrival, not across its route.
	-- The door's local Z is lateral because GameManager slides local Z.
	local doorFrame = spawnFrame * CFrame.new(0, 5, 7) * CFrame.Angles(0, math.pi / 2, 0)
	local left = part(elevator, "DoorL", doorFrame * CFrame.new(0, 0, -3), Vector3.new(0.5, 10, 6))
	local right = part(elevator, "DoorR", doorFrame * CFrame.new(0, 0, 3), Vector3.new(0.5, 10, 6))
	left.Color, right.Color = Color3.fromRGB(222, 216, 196), Color3.fromRGB(222, 216, 196)
	part(elevator, "EntranceHeader", doorFrame * CFrame.new(0, 5.5, 0), Vector3.new(1.1, 1, 14))
	for _, side in ipairs({-1, 1}) do
		part(elevator, "EntranceJamb", doorFrame * CFrame.new(0, 0, side * 6.5), Vector3.new(1.1, 10, 1))
	end
	elevator.PrimaryPart = left
	return elevator, pad, marker
end

local function protectArrival(spawnFrame: CFrame)
	-- Studio keeps the lobby floor: GameManager places only the queued roster.
	-- Moving everyone here would drag an observing developer out of the lobby.
	if RunService:IsStudio() then return end
	-- All present players were checked against DevAccess before any mutation.
	-- Place current rigs onto finished ground before parking their lobby; the
	-- authoritative GameManager entry barrier then reloads/places its roster.
	local index = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") then
			local across = (index % 3 - 1) * 4
			local along = math.floor(index / 3) * 4
			character:PivotTo(spawnFrame * CFrame.new(across, 4, along))
			root.AssemblyLinearVelocity, root.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
			index += 1
		end
	end
end

function Adapter.GetManifest() return manifest end

function Adapter.Cleanup()
	workspace:SetAttribute("Level5LightingOwnedByController", false)
	for _, object in ipairs(workspace:GetChildren()) do
		if object:GetAttribute(COMPATIBILITY) == true
			or (object.Name == WORLD_NAME and object:GetAttribute(OWNED) == true) then
			object:Destroy()
		end
	end
	manifest = nil
	restoreRuntime()
	local currentState = ReplicatedStorage:FindFirstChild(STATE_NAME)
	if currentState and currentState:GetAttribute(OWNED) == true then
		currentState:SetAttribute("Level5_Phase", "IDLE")
		currentState:SetAttribute("Level5_WorldDescendants", 0)
	end
	if workspace:GetAttribute("SelectedLevel") == 5 then
		workspace:SetAttribute("SelectedLevel", 1)
		workspace:SetAttribute("WorldGenerated", false)
	end
end

function Adapter.Build()
	assert(workspace:GetAttribute("Level5DevEnabled") == true, "Level 5 map preview is developer-only")
	for _, player in ipairs(Players:GetPlayers()) do
		assert(DevAccess.IsAllowed(player), "Level 5 preview refuses a non-developer roster")
	end
	for _, level in ipairs({2, 3, 4}) do
		assert(workspace:FindFirstChild("Level " .. level .. " Generated World") == nil,
			"End the existing level before starting the Level 5 map preview")
	end
	Adapter.Cleanup()
	assert(workspace:FindFirstChild(WORLD_NAME) == nil, "Level 5 world name is occupied by unowned content")
	assert(ServerStorage:FindFirstChild(BACKUP_NAME) == nil, "Inspect unresolved Level 5 preserved geometry before rebuilding")
	generation += 1
	local currentState = state()
	currentState:SetAttribute("Level5_Phase", "BUILDING")
	currentState:SetAttribute("Level5_MapOnly", true)
	currentState:SetAttribute("Level5_Generation", generation)
	currentState:SetAttribute("Level5_Error", nil)
	for property, value in pairs(LIGHTING_PROFILE) do currentState:SetAttribute("Lighting_" .. property, value) end
	for property, value in pairs(ATMOSPHERE_PROFILE) do currentState:SetAttribute("Atmosphere_" .. property, value) end
	workspace:SetAttribute("WorldGenerated", false)
	workspace:SetAttribute("LoadStage", "LEVEL_5_BUILDING_MAP")
	local started = os.clock()
	local ok, result = xpcall(function()
		preserveRuntime()
		local world = Instance.new("Model")
		world.Name = WORLD_NAME
		world:SetAttribute(OWNED, true)
		world:SetAttribute("Level5_MapOnly", true)
		world:SetAttribute("Level5_Generation", generation)
		world.Parent = workspace
		local architectureModule = script.Parent:WaitForChild("Level 5 Architecture", 10)
		assert(architectureModule and architectureModule:IsA("ModuleScript"), "Missing Level 5 Architecture")
		local architecture = require(architectureModule :: ModuleScript)
		manifest = architecture.Build(world, ORIGIN, {
			Generation = generation, MapOnly = true,
			CarpetTexture = script:GetAttribute("CarpetTexture"),
			FloralTexture = script:GetAttribute("FloralTexture"),
			ArrowTexture = script:GetAttribute("ArrowTexture"),
		})
		assert(type(manifest) == "table" and typeof(manifest.SpawnCFrame) == "CFrame", "Architecture needs an arrival SpawnCFrame")
		manifest.World, manifest.Origin = world, ORIGIN
		-- Architecture supplies a HumanoidRootPart-height pose, three studs
		-- above its entry carpet. GameManager's compatibility pad is the FLOOR.
		manifest.ArrivalFloorCFrame = manifest.SpawnCFrame * CFrame.new(0, -3, 0)
		manifest.Elevator, manifest.ElevatorSpawn, manifest.MazeStart = buildCompatibility(manifest.ArrivalFloorCFrame)
		local descendants = #world:GetDescendants()
		assert(descendants <= 18000, "Level 5 exceeds the 18,000-instance map preview budget")
		currentState:SetAttribute("Level5_WorldDescendants", descendants)
		currentState:SetAttribute("Level5_BuildSeconds", math.round((os.clock() - started) * 100) / 100)
		currentState:SetAttribute("Level5_SpawnCFrame", manifest.SpawnCFrame)
		protectArrival(manifest.ArrivalFloorCFrame)
		parkLobby()
		editLighting()
		workspace:SetAttribute("SelectedLevel", 5)
		workspace:SetAttribute("Level5LightingOwnedByController", true)
		currentState:SetAttribute("Level5_Phase", "MAP_PREVIEW")
		workspace:SetAttribute("LoadStage", "READY")
		workspace:SetAttribute("WorldGenerated", true)
		return world
	end, debug.traceback)
	if not ok then
		Adapter.Cleanup()
		currentState:SetAttribute("Level5_Phase", "ERROR")
		currentState:SetAttribute("Level5_Error", tostring(result))
		workspace:SetAttribute("LoadStage", "WORLD_ERROR")
		error(result)
	end
	return result
end

return Adapter
