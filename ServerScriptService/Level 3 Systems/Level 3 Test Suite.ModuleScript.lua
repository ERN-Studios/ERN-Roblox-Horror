--!strict
-- Level 3 deterministic structural checks. These assertions never add runtime
-- gameplay and can be called from Studio Edit mode after WorldBuilder.Build.

local Configuration = require(script.Parent:WaitForChild("Level 3 Configuration"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local TestSuite = {}

local FORBIDDEN_NAME_FRAGMENTS = {"entity", "monster", "hostile", "npc", "chase"}
local SIGN_NAME_FRAGMENTS = {"level 3 sign", "room plaque", "birthday banner", "intro directory"}
local BEIGE_ROOM_IDS = {
	BackOffice = true,
	BreakRoom = true,
	Maintenance = true,
	ChairStore = true,
	CityPlay = true,
	LostFound = true,
	Exit = true,
}
local RED_PARTY_ROOMS = {PartyA = true, Records = true}
local NEON_PARTY_ROOMS = {PartyB = true, UtilityWest = true, CentralHall = true}
local LEVEL_ONE_RUNTIME_SCRIPTS = {"EntityAI", "EntityAnimation", "EntityKill", "PuzzleManager"}

local function countMap(values: {[any]: any}): number
	local count = 0
	for _ in pairs(values) do count += 1 end
	return count
end

local function approx(a: number, b: number, tolerance: number?): boolean
	return math.abs(a - b) <= (tolerance or 0.001)
end

local function assertPart(record: {[string]: any}, key: string, root: Instance): BasePart
	local object = record[key]
	assert(object and object:IsA("BasePart") and object:IsDescendantOf(root),
		"Level 3 manifest ExitPortal." .. key .. " is missing or outside the generated world")
	return object
end

function TestSuite.ValidateConfiguration(): {[string]: any}
	assert(Configuration.Version >= 10, "Level 3 CD/audio/arrival revision must be at least 10")
	assert(Configuration.Textures.KidsDrawingsAtlas == "rbxassetid://134566516757424",
		"Level 3 must use the expanded 4x4 kids-drawing atlas")
	assert(Configuration.Textures.CDCoversAtlas == "rbxassetid://88160214591687",
		"Level 3 must use the authored CD-cover atlas")
	assert(Configuration.CorridorWidth == 14 and Configuration.CorridorHeight == 10.5,
		"Level 3 corridors must remain one 14 x 10.5 stud tunnel cross-section")
	assert(Configuration.DoorWidth == 6 and Configuration.DoorHeight == 8.5,
		"Level 3 doors must remain the approved 6 x 8.5 studs")
	assert(Configuration.ModuleGoal == 5, "Level 3 must require exactly five modules")
	assert(Configuration.MusicSequence.DurationSeconds == 180.035917
		and Configuration.MusicSequence.BlackoutSeconds == 30,
		"Level 3 room-song timing must match the complete three-minute master and 30-second blackout")
	assert(Configuration.MusicSequence.CorridorVolume < Configuration.MusicSequence.RoomVolume,
		"Level 3 room song must be quieter in corridors than inside rooms")
	assert(Configuration.Textures.StaffDoor == "rbxassetid://127165696221846",
		"Level 3 StaffDoor must use the approved published texture")
	assert(Configuration.Textures.PartyCarpetNeon == "rbxassetid://110230144446272"
		and Configuration.Textures.PartyCarpetRed == "rbxassetid://108064770913201"
		and Configuration.Textures.OrangeWall == "rbxassetid://128270554927663",
		"Level 3 Revision 4 generated texture IDs are missing or stale")
	local assets = ServerStorage:FindFirstChild("Level3Assets")
	local furniture = assets and assets:FindFirstChild("FurnitureTemplates")
	assert(furniture and furniture:IsA("Folder"), "Level 3 vetted furniture templates are missing")
	for _, templateName in ipairs({"PlasticPartyChairTemplate", "FoldingTableTemplate"}) do
		local template = furniture:FindFirstChild(templateName)
		assert(template and template:IsA("MeshPart") and template:GetAttribute("Level3_VettedTemplate") == true,
			"Missing vetted Level 3 furniture template: " .. templateName)
		for _, object in ipairs(template:GetDescendants()) do
			assert(not object:IsA("BaseScript"), "Vetted Level 3 furniture contains a script: " .. object:GetFullName())
		end
	end

	local roomsById = {}
	local moduleRooms = 0
	for _, room in ipairs(Configuration.Rooms) do
		assert(type(room.Id) == "string" and roomsById[room.Id] == nil,
			"Level 3 room ids must be unique")
		assert(room.W >= 28 and room.D >= 24, "Level 3 room is too small: " .. room.Id)
		roomsById[room.Id] = room
		if room.Module then moduleRooms += 1 end
	end
	assert(roomsById.Arrival and roomsById.Exit, "Level 3 requires authored Arrival and Exit rooms")
	assert(moduleRooms == Configuration.ModuleGoal, "Every configured module needs one authored room")
	for roomId in pairs(BEIGE_ROOM_IDS) do
		assert(roomsById[roomId], "Unknown beige-wall room id in Level 3 tests: " .. roomId)
	end
	assert(not BEIGE_ROOM_IDS.Arrival, "Arrival must be orange so the visual revision is visible at spawn")

	local adjacency = {}
	for id in pairs(roomsById) do adjacency[id] = {} end
	local edgeKeys = {}
	local hiddenExitLinks = 0
	for _, link in ipairs(Configuration.Links) do
		assert(roomsById[link.A] and roomsById[link.B], "Level 3 link references an unknown room")
		assert(link.A ~= link.B, "Level 3 link cannot connect a room to itself")
		assert(link.Door == "Open" or link.Door == "Openable" or link.Door == "HiddenExit",
			"Unsupported Level 3 link door type: " .. tostring(link.Door))
		if link.Door == "HiddenExit" then
			hiddenExitLinks += 1
			assert((link.A == "SignalHall" and link.B == "Exit")
				or (link.B == "SignalHall" and link.A == "Exit"),
				"HiddenExit must be the authored SignalHall/Exit connection")
		end
		local key = link.A < link.B and (link.A .. "|" .. link.B) or (link.B .. "|" .. link.A)
		assert(not edgeKeys[key], "Duplicate Level 3 link: " .. key)
		edgeKeys[key] = true
		table.insert(adjacency[link.A], link.B)
		table.insert(adjacency[link.B], link.A)
	end
	assert(hiddenExitLinks == 1, "Level 3 must contain exactly one HiddenExit link")

	local seen = {Arrival = true}
	local queue = {"Arrival"}
	local cursor = 1
	while cursor <= #queue do
		local id = queue[cursor]
		cursor += 1
		for _, neighbour in ipairs(adjacency[id]) do
			if not seen[neighbour] then
				seen[neighbour] = true
				table.insert(queue, neighbour)
			end
		end
	end
	assert(countMap(seen) == #Configuration.Rooms, "Every Level 3 room must be reachable from Arrival")
	assert(#Configuration.Links - #Configuration.Rooms + 1 >= 3,
		"Level 3 must preserve at least three graph loops")
	return {
		Rooms = #Configuration.Rooms,
		Links = #Configuration.Links,
		Modules = moduleRooms,
		Loops = #Configuration.Links - #Configuration.Rooms + 1,
		HiddenExitLinks = hiddenExitLinks,
	}
end

function TestSuite.ValidateWorld(manifest: {[string]: any}): {[string]: any}
	assert(type(manifest) == "table" and manifest.World and manifest.World:IsA("Model")
		and manifest.World.Parent == workspace, "Level 3 manifest must point at its live world")
	local world = manifest.World :: Model
	assert(world.Name == Configuration.WorldName, "Level 3 world has the wrong generation name")
	local liveWorlds = 0
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == Configuration.WorldName then liveWorlds += 1 end
	end
	assert(liveWorlds == 1, "Level 3 rebuild left duplicate generated worlds")
	assert(world:GetAttribute("Level3_Generation") == manifest.Generation,
		"Level 3 world/manifest generations do not match")
	assert(world:GetAttribute("Level3_VisualRevision") == Configuration.Version,
		"Level 3 world is missing the current visual revision stamp")
	assert(countMap(manifest.Rooms) == #Configuration.Rooms, "Level 3 built room count mismatch")
	assert(#manifest.Modules == Configuration.ModuleGoal, "Level 3 built module count mismatch")
	assert(manifest.ExitGateway == nil, "Legacy ExitGateway must not survive the hidden-exit rebuild")
	assert(type(manifest.ExitPortal) == "table", "Level 3 manifest is missing ExitPortal")
	assert(manifest.EscapePrompt and manifest.EscapePrompt:IsA("ProximityPrompt")
		and manifest.EscapePrompt:IsDescendantOf(world), "Level 3 escape prompt is incomplete")
	assert(manifest.ExitSafeSpawn and manifest.ExitSafeSpawn:IsA("BasePart")
		and manifest.ExitSafeSpawn:IsDescendantOf(world), "Level 3 exit safe spawn is incomplete")
	assert(typeof(manifest.ExitPosition) == "Vector3", "Level 3 ExitPosition must be a Vector3")
	assert(manifest.Elevator and manifest.ElevatorSpawn and manifest.MazeStart,
		"Level 3 compatibility arrival is incomplete")
	for _, marker in ipairs({manifest.Elevator, manifest.ElevatorSpawn, manifest.MazeStart}) do
		assert(marker.Parent == workspace and marker:GetAttribute("Level3_CompatibilityMarker") == true,
			"Level 3 compatibility arrival marker is invalid")
	end
	for _, markerName in ipairs({"Elevator", "ElevatorSpawn", "MazeStart"}) do
		local markerCount = 0
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == markerName and child:GetAttribute("Level3_CompatibilityMarker") == true then
				markerCount += 1
			end
		end
		assert(markerCount == 1, "Level 3 rebuild left duplicate " .. markerName .. " markers")
	end
	assert(workspace:FindFirstChild("EntityStart") == nil,
		"Level 3 must never create the restricted EntityStart marker")

	local portal = manifest.ExitPortal
	assert(portal.Model and portal.Model:IsA("Model") and portal.Model:IsDescendantOf(world),
		"Level 3 ExitPortal model is missing")
	local hiddenWall = assertPart(portal, "Wall", world)
	assert(hiddenWall:GetAttribute("Level3_HiddenExitWall") == true,
		"ExitPortal wall is missing Level3_HiddenExitWall")
	assert(hiddenWall.Transparency == 0 and hiddenWall.CanCollide and hiddenWall.CanQuery
		and not hiddenWall.CanTouch,
		"Hidden exit wall must begin opaque, locked, queryable, and non-touching")
	assert(hiddenWall.Material == Enum.Material.Plaster
		and hiddenWall.Color == Color3.fromRGB(183, 78, 35)
		and hiddenWall.Size == Vector3.new(Configuration.CorridorWidth,
			Configuration.CorridorHeight, Configuration.WallThickness),
		"Hidden exit wall must seal the complete standardized tunnel portal")
	assert(typeof(portal.Position) == "Vector3" and (portal.Position - hiddenWall.Position).Magnitude <= Configuration.RoomHeight,
		"ExitPortal position is invalid or detached from the wall")
	assert(type(portal.FrameParts) == "table" and #portal.FrameParts == 8,
		"ExitPortal must have exactly 8 reveal-frame parts (four edges on both faces)")
	local uniqueFrameParts = {}
	for index, framePart in ipairs(portal.FrameParts) do
		assert(framePart:IsA("BasePart") and framePart:IsDescendantOf(portal.Model),
			"ExitPortal frame part is missing at index " .. index)
		assert(not uniqueFrameParts[framePart], "ExitPortal repeats a frame part at index " .. index)
		uniqueFrameParts[framePart] = true
		assert(framePart:GetAttribute("Level3_HiddenExitFrame") == true,
			"ExitPortal frame part is missing its marker attribute")
		assert(framePart.Material == Enum.Material.Neon and framePart.Transparency == 1
			and not framePart.CanCollide and not framePart.CanQuery,
			"ExitPortal reveal frame must start invisible and nonblocking")
	end
	assert(portal.Light and portal.Light:IsA("Light") and portal.Light:IsDescendantOf(portal.Model)
		and not portal.Light.Enabled, "ExitPortal light must exist and start disabled")
	assert(portal.Model:GetAttribute("Level3_ExitUnlocked") == false,
		"ExitPortal must begin locked")

	local stats = {
		BaseParts = 0,
		Collidable = 0,
		Lights = 0,
		ShadowLights = 0,
		Prompts = 0,
		Textures = 0,
		OrangeRooms = 0,
		BeigeRooms = 0,
		RoomFloors = 0,
		PartyFloors = 0,
		RedPartyFloors = 0,
		NeonPartyFloors = 0,
		OrangeWallTextures = 0,
		CityFloors = 0,
		ExitFloors = 0,
		CorridorFloors = 0,
	}

	assert(type(manifest.Doors) == "table" and #manifest.Doors == 0,
		"Revision 3 must not generate ordinary or fake doors")
	local doorIds = {}
	for _, door in ipairs(manifest.Doors) do
		assert(type(door.Id) == "string" and not doorIds[door.Id], "Level 3 door ids must be unique")
		doorIds[door.Id] = true
		assert(door.Type == "Openable" or door.Type == "Locked",
			"HiddenExit must not be registered as a tweened door: " .. door.Id)
		assert(door.Model and door.Model:IsA("Model") and door.Model:IsDescendantOf(world)
			and door.Leaf and door.Leaf:IsA("BasePart") and door.Leaf:IsDescendantOf(door.Model)
			and door.Prompt and door.Prompt:IsA("ProximityPrompt") and door.Prompt:IsDescendantOf(door.Leaf),
			"Level 3 door record is incomplete: " .. door.Id)
		assert(door.Leaf.Size == Vector3.new(Configuration.DoorWidth, Configuration.DoorHeight, .55),
			"Level 3 door has the wrong leaf size: " .. door.Id)
		assert(door.Leaf.Material == Enum.Material.Metal,
			"Level 3 doors must use painted metal: " .. door.Id)
		assert(typeof(door.Closed) == "CFrame" and typeof(door.Open) == "CFrame"
			and (door.Closed.Position - door.Leaf.Position).Magnitude <= 0.001,
			"Level 3 door closed/open transforms are invalid: " .. door.Id)
		assert((door.Open.Position - door.Closed.Position).Magnitude >= Configuration.DoorWidth * 0.6,
			"Level 3 open transform does not clear enough of the portal: " .. door.Id)

		local bulkheads, sideFillers = 0, 0
		local frontTexture, backTexture = false, false
		for _, object in ipairs(door.Model:GetDescendants()) do
			if object.Name == "Level 3 Door Bulkhead" and object:IsA("BasePart") then
				bulkheads += 1
				assert(object.CanCollide and object.Size.Y > 0
					and approx(object.Position.Y + object.Size.Y * .5,
						Configuration.WorldOrigin.Y + Configuration.RoomHeight, 0.05),
					"Level 3 door bulkhead does not close the ceiling gap: " .. door.Id)
			elseif object.Name == "Level 3 Door Side Filler" and object:IsA("BasePart") then
				sideFillers += 1
				assert(object.CanCollide, "Level 3 door side filler must block its gap: " .. door.Id)
			elseif object:IsA("Texture") and object.Parent == door.Leaf
				and object.Texture == Configuration.Textures.StaffDoor then
				if object.Face == Enum.NormalId.Front then frontTexture = true end
				if object.Face == Enum.NormalId.Back then backTexture = true end
			end
		end
		assert(bulkheads == 1, "Level 3 door must have exactly one top bulkhead: " .. door.Id)
		assert(sideFillers == 2, "Level 3 door must have exactly two side fillers: " .. door.Id)
		assert(frontTexture and backTexture, "Level 3 StaffDoor texture must cover both faces: " .. door.Id)

		if door.Type == "Openable" then
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Exclude
			overlap.FilterDescendantsInstances = {door.Model}
			overlap.MaxParts = 100
			local clearanceSize = Vector3.new(
				Configuration.DoorWidth - 0.6,
				Configuration.DoorHeight - 0.4,
				math.max(0.7, Configuration.WallThickness * 0.8)
			)
			-- Validate the shut doorway aperture. An open swing leaf deliberately
			-- rests outside this clearance volume, so testing its CFrame would flag
			-- the adjacent structural wall as a false obstruction.
			for _, pose in ipairs({door.Closed}) do
				for _, hit in ipairs(workspace:GetPartBoundsInBox(pose, clearanceSize, overlap)) do
					assert(not hit.CanCollide,
						"Static collision obstructs openable doorway " .. door.Id .. ": " .. hit:GetFullName())
				end
			end
		end
	end

	for _, module in ipairs(manifest.Modules) do
		assert(module.Model.Parent and module.Prompt.Enabled and module.Prompt.Parent,
			"Level 3 CD record is incomplete")
		assert(module.Prompt.ActionText == "COLLECT CD"
			and string.find(module.Prompt.ObjectText, "PARTY MIX CD", 1, true),
			"Level 3 objective must be presented as a birthday music CD")
		assert(module.Model:FindFirstChild("Transparent Jewel Case", true)
			and module.Model:FindFirstChild("Party Mix Compact Disc", true)
			and module.Model:FindFirstChild("Level 3 CD Cover Surface", true),
			"Level 3 CD collectible is missing its authored jewel-case visuals")
	end

	for _, instance in ipairs(world:GetDescendants()) do
		if instance:IsA("BasePart") then
			stats.BaseParts += 1
			if instance.CanCollide then stats.Collidable += 1 end
		elseif instance:IsA("Light") then
			stats.Lights += 1
			if instance.Shadows then stats.ShadowLights += 1 end
			if instance.Name == "Level 3 Fluorescent Light" then
				assert(instance.Brightness <= 1.65 and instance.Range <= 34,
					"Level 3 fluorescent fixture exceeds the readable-atmosphere target")
			end
		elseif instance:IsA("ProximityPrompt") then
			stats.Prompts += 1
		elseif instance:IsA("Texture") or instance:IsA("Decal") then
			stats.Textures += 1
		end
		if instance:IsA("SurfaceGui") then
			local allowedDrawing = instance.Name == "Level 3 Kids Wall Art Surface"
				and instance.Parent and instance.Parent:GetAttribute("Level3_KidsWallArt") == true
			local allowedCD = instance.Name == "Level 3 CD Cover Surface"
				and instance.Parent and instance.Parent.Name == "CD Cover Insert"
			assert(allowedDrawing or allowedCD,
				"Generated Level 3 SurfaceGui/sign is forbidden: " .. instance:GetFullName())
		end
		assert(not instance:IsA("TextLabel") and not instance:IsA("TextBox") and not instance:IsA("TextButton"),
			"Generated Level 3 text UI is forbidden: " .. instance:GetFullName())
		assert(not instance:IsA("Humanoid"), "Level 3 may not contain Humanoids/NPCs")
		assert(not instance:IsA("BaseScript"), "Level 3 world may not contain per-instance scripts")
		local lowerName = string.lower(instance.Name)
		for _, fragment in ipairs(FORBIDDEN_NAME_FRAGMENTS) do
			assert(not string.find(lowerName, fragment, 1, true),
				"Forbidden Level 3 runtime name: " .. instance:GetFullName())
		end
		for _, fragment in ipairs(SIGN_NAME_FRAGMENTS) do
			assert(not string.find(lowerName, fragment, 1, true),
				"Obsolete Level 3 sign artifact: " .. instance:GetFullName())
		end
	end

	for _, room in ipairs(Configuration.Rooms) do
		local roomModel = manifest.Rooms[room.Id]
		assert(roomModel and roomModel:IsA("Model"), "Level 3 room is missing: " .. room.Id)
		local floorPart = roomModel:FindFirstChild("Level 3 Room Floor")
		assert(floorPart and floorPart:IsA("BasePart"), "Level 3 room floor is missing: " .. room.Id)
		stats.RoomFloors += 1
		local floorTexture = floorPart:FindFirstChild("Level 3 Surface Texture")
		if room.Id == "Exit" then
			assert(floorPart.Material == Enum.Material.DiamondPlate and floorTexture == nil,
				"Exit room must keep its explicit DiamondPlate floor exception")
			stats.ExitFloors += 1
		elseif BEIGE_ROOM_IDS[room.Id] then
			assert(floorPart.Material == Enum.Material.Carpet and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.CityCarpet,
				"Glossy pale room must use city carpet: " .. room.Id)
			stats.CityFloors += 1
		elseif RED_PARTY_ROOMS[room.Id] then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpetRed,
				"Authored red party room has the wrong carpet: " .. room.Id)
			stats.PartyFloors += 1
			stats.RedPartyFloors += 1
		elseif NEON_PARTY_ROOMS[room.Id] then
			assert(floorPart.Material == Enum.Material.Carpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpetNeon,
				"Authored neon party room has the wrong carpet: " .. room.Id)
			stats.PartyFloors += 1
			stats.NeonPartyFloors += 1
		else
			assert(floorPart.Material == Enum.Material.Carpet and floorPart.Color == Configuration.Colors.DarkCarpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpet,
				"Every other orange non-Exit room must use the original black party carpet: " .. room.Id)
			stats.PartyFloors += 1
		end

		local expectedWallColor = if BEIGE_ROOM_IDS[room.Id]
			then Color3.fromRGB(220, 213, 187) else Color3.fromRGB(183, 78, 35)
		for _, descendant in ipairs(roomModel:GetDescendants()) do
			if descendant:IsA("BasePart") and (
				string.find(descendant.Name, "Level 3 North Wall", 1, true)
				or string.find(descendant.Name, "Level 3 South Wall", 1, true)
				or string.find(descendant.Name, "Level 3 East Wall", 1, true)
				or string.find(descendant.Name, "Level 3 West Wall", 1, true)
				or string.find(descendant.Name, "Level 3 East Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 West Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 North Lintel", 1, true)
				or string.find(descendant.Name, "Level 3 South Lintel", 1, true)
			) then
				assert(descendant.Color == expectedWallColor,
					"Wrong wall palette in room " .. room.Id .. ": " .. descendant:GetFullName())
				for _, child in ipairs(descendant:GetChildren()) do
					local isWallpaper = child:IsA("Texture")
						and child.Texture == Configuration.Textures.PastelWallpaper
					local isOrangeFinish = child:IsA("Texture")
						and child.Texture == Configuration.Textures.OrangeWall
					assert((BEIGE_ROOM_IDS[room.Id] == true) == isWallpaper,
						"Wallpaper/wall-color mismatch in room " .. room.Id)
					if isOrangeFinish then
						assert(not BEIGE_ROOM_IDS[room.Id], "Orange finish leaked into a glossy pale room")
						stats.OrangeWallTextures += 1
					end
				end
			end
		end
		if BEIGE_ROOM_IDS[room.Id] then
			stats.BeigeRooms += 1
		else
			stats.OrangeRooms += 1
		end
	end
	assert(stats.OrangeRooms == 11 and stats.BeigeRooms == 7,
		"Level 3 must contain exactly 11 orange rooms and 7 glossy pale rooms including the exit")
	assert(stats.CityFloors == 6 and stats.ExitFloors == 1
		and stats.PartyFloors == stats.RoomFloors - 7,
		"Level 3 floor palette is inconsistent")
	assert(stats.RedPartyFloors == 2 and stats.NeonPartyFloors == 3,
		"Level 3 must preserve its authored red/neon carpet room variation")
	assert(stats.OrangeWallTextures > 0,
		"Level 3 orange rooms are missing their generated worn-wall finish")

	local corridors = world:FindFirstChild("Corridors")
	assert(corridors and corridors:IsA("Folder"), "Level 3 Corridors folder is missing")
	assert(#corridors:GetChildren() == #Configuration.Links, "Level 3 corridor model count mismatch")
	for _, corridorModel in ipairs(corridors:GetChildren()) do
		assert(corridorModel:IsA("Model")
			and corridorModel:GetAttribute("Level3_TunnelWidth") == Configuration.CorridorWidth
			and corridorModel:GetAttribute("Level3_TunnelHeight") == Configuration.CorridorHeight,
			"Level 3 corridor does not use the standardized tunnel profile: " .. corridorModel:GetFullName())
		local floorPart = corridorModel:FindFirstChild("Level 3 Corridor Floor")
		local ceilingPart = corridorModel:FindFirstChild("Level 3 Corridor Ceiling")
		assert(floorPart and floorPart:IsA("BasePart")
			and ceilingPart and ceilingPart:IsA("BasePart"),
			"Level 3 tunnel is missing a continuous floor or ceiling: " .. corridorModel:GetFullName())
		assert(approx(ceilingPart.Position.Y - ceilingPart.Size.Y * .5,
			Configuration.WorldOrigin.Y + Configuration.CorridorHeight),
			"Level 3 tunnel has inconsistent ceiling clearance: " .. corridorModel:GetFullName())
		local wallCount = 0
		for _, object in ipairs(corridorModel:GetChildren()) do
			if object:IsA("BasePart") and object.Name == "Level 3 Corridor Wall" then
				wallCount += 1
				assert(approx(object.Size.Y, Configuration.CorridorHeight),
					"Level 3 tunnel wall has inconsistent height: " .. corridorModel:GetFullName())
			end
		end
		assert(wallCount == 2, "Level 3 tunnel must have exactly two continuous side walls")
	end
	for _, instance in ipairs(corridors:GetDescendants()) do
		if instance:IsA("BasePart") and instance.Name == "Level 3 Corridor Wall" then
			assert(instance.Color == Color3.fromRGB(183, 78, 35),
				"All Level 3 corridor walls must be orange")
			for _, child in ipairs(instance:GetChildren()) do
				assert(not (child:IsA("Texture") and child.Texture == Configuration.Textures.PastelWallpaper),
					"Level 3 corridor walls must never use pastel wallpaper")
			end
		elseif instance:IsA("BasePart") and instance.Name == "Level 3 Corridor Floor" then
			stats.CorridorFloors += 1
			local floorTexture = instance:FindFirstChild("Level 3 Surface Texture")
			assert(instance.Material == Enum.Material.Carpet and instance.Color == Configuration.Colors.DarkCarpet
				and floorTexture and floorTexture:IsA("Texture")
				and floorTexture.Texture == Configuration.Textures.PartyCarpet,
				"All Level 3 corridors must use black party carpet")
		end
	end
	assert(stats.CorridorFloors == #Configuration.Links, "Level 3 corridor floor count mismatch")

	local forbiddenDecor = {"Baseboard", "Shelf", "Carton", "Box", "Desk", "CRT", "Plant", "Utility Pipe"}
	for _, instance in ipairs(world:GetDescendants()) do
		for _, fragment in ipairs(forbiddenDecor) do
			assert(not string.find(instance.Name, fragment, 1, true),
				"Revision 5 contains forbidden clutter: " .. instance:GetFullName())
		end
	end

	assert(stats.BaseParts <= 4500, "Level 3 exceeded its BasePart budget")
	assert(stats.Collidable <= 1200, "Level 3 exceeded its collision budget")
	assert(stats.Lights <= 90 and stats.ShadowLights <= 6, "Level 3 exceeded its lighting budget")
	assert(stats.Prompts <= 48, "Level 3 exceeded its interaction budget")
	return stats
end

function TestSuite.CaptureLifecycleState(): {[string]: any}
	local scripts = {}
	for _, name in ipairs(LEVEL_ONE_RUNTIME_SCRIPTS) do
		local object = ServerScriptService:FindFirstChild(name)
		if object and object:IsA("BaseScript") then scripts[object] = object.Enabled end
	end
	return {
		Lobby = workspace:FindFirstChild("ServerLobby"),
		Entity = workspace:FindFirstChild("Entity"),
		Scripts = scripts,
	}
end

function TestSuite.ValidateRuntime(expectedProgress: number): {[string]: any}
	assert(expectedProgress % 1 == 0 and expectedProgress >= 0
		and expectedProgress <= Configuration.ModuleGoal,
		"ValidateRuntime progress must be an integer from 0 through ModuleGoal")
	local world = workspace:FindFirstChild(Configuration.WorldName)
	assert(world and world:IsA("Model"), "ValidateRuntime requires a live Level 3 world")
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	assert(state and state:IsA("Folder"), "ValidateRuntime requires Level 3 replicated state")
	local unlocked = expectedProgress == Configuration.ModuleGoal
	assert(state:GetAttribute("Level3_ModuleProgress") == expectedProgress
		and state:GetAttribute("Level3_ModuleGoal") == Configuration.ModuleGoal
		and state:GetAttribute("Level3_ExitUnlocked") == unlocked
		and state:GetAttribute("Level3_Phase") == (if unlocked then "EXIT_UNLOCKED" else "SEARCH"),
		"Replicated Level 3 progress does not match the expected runtime phase")
	assert(workspace:GetAttribute("Level3Modules") == expectedProgress
		and workspace:GetAttribute("Level3ModuleGoal") == Configuration.ModuleGoal
		and workspace:GetAttribute("Level3ExitUnlocked") == unlocked,
		"Workspace Level 3 progress mirrors are stale")

	local portalModel = world:FindFirstChild("Level 3 Hidden Exit Portal", true)
	assert(portalModel and portalModel:IsA("Model"), "Live Level 3 hidden exit portal is missing")
	local hiddenWall: BasePart? = nil
	local frameParts = {}
	local portalLight: Light? = nil
	for _, instance in ipairs(portalModel:GetDescendants()) do
		if instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitWall") == true then
			hiddenWall = instance
		elseif instance:IsA("BasePart") and instance:GetAttribute("Level3_HiddenExitFrame") == true then
			table.insert(frameParts, instance)
		elseif instance:IsA("Light") then
			portalLight = instance
		end
	end
	assert(hiddenWall and hiddenWall.Transparency == 0
		and hiddenWall.CanCollide == (not unlocked)
		and hiddenWall.CanQuery and not hiddenWall.CanTouch,
		"Hidden exit wall collision/reveal state does not match objective progress")
	assert(#frameParts == 8 and portalLight,
		"Hidden exit runtime reveal objects are incomplete")
	assert(portalModel:GetAttribute("Level3_ExitUnlocked") == unlocked,
		"Hidden exit model unlock attribute is stale")
	for _, framePart in ipairs(frameParts) do
		if unlocked then
			assert(framePart.Transparency <= 0.10,
				"Unlocked hidden-exit frame did not complete its reveal tween")
		else
			assert(framePart.Transparency >= 0.99,
				"Hidden-exit frame became visible before 5/5 modules")
		end
	end
	assert(portalLight.Enabled == unlocked, "Hidden-exit blue spill has the wrong enabled state")
	local escapePrompt = world:FindFirstChild("EscapePrompt", true)
	assert(escapePrompt and escapePrompt:IsA("ProximityPrompt") and escapePrompt.Enabled == unlocked,
		"Final escape prompt enabled state does not match module progress")

	local collectedModules = 0
	for _, model in ipairs(world:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("Level3_ModuleIndex") ~= nil then
			local collected = model:GetAttribute("Level3_Collected") == true
			if collected then collectedModules += 1 end
			local prompt = model:FindFirstChild("CollectPrompt", true)
			assert(prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled ~= collected,
				"Module prompt/collected state mismatch: " .. model:GetFullName())
		end
	end
	assert(collectedModules == expectedProgress, "Collected module model count is stale")

	local stableDoors = 0
	for _, model in ipairs(world:GetDescendants()) do
		if model:IsA("Model") and model:GetAttribute("Level3_DoorId") ~= nil then
			stableDoors += 1
			local stateName = model:GetAttribute("Level3_DoorState")
			assert(stateName == "OPEN" or stateName == "CLOSED" or stateName == "LOCKED",
				"Door did not settle after its tween: " .. model:GetFullName())
			local leaf = model:FindFirstChild("Door")
			local prompt = model:FindFirstChild("DoorPrompt", true)
			assert(leaf and leaf:IsA("BasePart") and prompt and prompt:IsA("ProximityPrompt")
				and prompt.Enabled, "Settled door is missing an enabled prompt")
			assert(leaf.CanCollide == (stateName ~= "OPEN"),
				"Settled door collision state is unsafe: " .. model:GetFullName())
		end
	end
	assert(stableDoors == 0, "Revision 5 must not restore ordinary interactive Level 3 doors")
	return {Progress = expectedProgress, Frames = #frameParts, Doors = stableDoors}
end

function TestSuite.ValidateCleanup(snapshot: {[string]: any}): {[string]: any}
	assert(type(snapshot) == "table" and type(snapshot.Scripts) == "table",
		"ValidateCleanup requires a CaptureLifecycleState snapshot")
	assert(workspace:FindFirstChild(Configuration.WorldName) == nil,
		"Level 3 generated world survived cleanup")
	assert(workspace:FindFirstChild("EntityStart") == nil,
		"Restricted EntityStart marker survived Level 3 cleanup")
	for _, child in ipairs(workspace:GetChildren()) do
		assert(child:GetAttribute("Level3_CompatibilityMarker") ~= true,
			"Level 3 compatibility marker survived cleanup: " .. child:GetFullName())
	end
	if snapshot.Lobby then
		assert(snapshot.Lobby.Parent == workspace and snapshot.Lobby.Name == "ServerLobby",
			"Cleanup did not restore the original ServerLobby instance")
	end
	if snapshot.Entity then
		assert(snapshot.Entity.Parent == workspace and snapshot.Entity.Name == "Entity",
			"Cleanup did not restore the original Level 1 Entity instance")
	end
	for object, wasEnabled in pairs(snapshot.Scripts) do
		assert(object.Parent and object.Enabled == wasEnabled,
			"Cleanup did not restore Level 1 script state: " .. object.Name)
	end
	assert(ServerStorage:FindFirstChild("Level 3 Stored Server Lobby") == nil,
		"Cleanup left a parked Level 3 lobby in ServerStorage")
	assert(ServerStorage:FindFirstChild("Level 3 Stored Level 1 Entity") == nil,
		"Cleanup left a parked Level 1 entity in ServerStorage")

	assert(workspace:GetAttribute("WorldGenerated") == false
		and workspace:GetAttribute("SelectedLevel") ~= 3
		and workspace:GetAttribute("Level3Modules") == 0
		and workspace:GetAttribute("Level3ModuleGoal") == 0
		and workspace:GetAttribute("Level3ExitUnlocked") == false
		and workspace:GetAttribute("Level3LightingOwnedByController") == false,
		"Cleanup did not reset Level 3 workspace state")
	for _, legacyName in ipairs({"Level3Pumps", "Level3PumpGoal", "Level3ExitPowered"}) do
		assert(workspace:GetAttribute(legacyName) == nil,
			"Cleanup retained legacy workspace attribute " .. legacyName)
	end
	local state = ReplicatedStorage:FindFirstChild(Configuration.StateFolderName)
	assert(state and state:IsA("Folder"), "Cleanup removed the Level 3 state folder")
	assert(state:GetAttribute("Level3_Phase") == "IDLE"
		and state:GetAttribute("Level3_ModuleProgress") == 0
		and state:GetAttribute("Level3_ModuleGoal") == 0
		and state:GetAttribute("Level3_ExitUnlocked") == false
		and state:GetAttribute("Level3_ExitPosition") == nil
		and state:GetAttribute("Level3_LightingMode") == "OFF"
		and state:GetAttribute("Level3_Error") == nil,
		"Cleanup did not reset replicated Level 3 state")
	return {RestoredScripts = countMap(snapshot.Scripts)}
end

return TestSuite
