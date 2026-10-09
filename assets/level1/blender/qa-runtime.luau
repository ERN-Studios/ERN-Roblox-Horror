-- Read-only Studio MCP Server Play probe. Run after the authorized preview round starts,
-- and once more after its teardown. No launch, prompt, teleport or round writes.
-- Engine path samples are bounded to three requests/four seconds each.
local HS = game:GetService("HttpService")
local RunService = game:GetService("RunService")
assert(RunService:IsServer() and RunService:IsRunning(), "Run this probe in the Play Server datamodel")
local began = os.clock()
local result = {mode = "active", checks = {}, failures = {}, warnings = {}, paths = {}, counts = {},
	unverified = {"Gameplay actions/escape", "Multiplayer", "Client button input/visibility", "Server CPU profiler"}}
local function check(ok, label, detail)
	table.insert(result.checks, {passed = ok == true, label = label, detail = detail})
	if ok ~= true then table.insert(result.failures, label) end
end
local function finish()
	result.elapsedSeconds = os.clock() - began
	result.passed = #result.failures == 0
	return HS:JSONEncode(result)
end
local function memory()
	local ok, value = pcall(function() return game:GetService("Stats"):GetTotalMemoryUsageMb() end)
	return if ok then value else nil
end
result.serverMemoryMbBefore = memory()
result.flags = {
	preview = workspace:GetAttribute("Level1BlenderPreviewActive") == true,
	round = workspace:GetAttribute("RoundActive") == true,
	level = workspace:GetAttribute("SelectedLevel"),
	world = workspace:GetAttribute("WorldGenerated") == true,
	decor = workspace:GetAttribute("DecorReady") == true,
}
local maze = workspace:FindFirstChild("Maze")
local rooms = maze and maze:FindFirstChild("BlenderRooms")
local puzzle = workspace:FindFirstChild("PuzzleItems")
if not result.flags.preview then
	result.mode = "reset-or-public"
	check(not rooms, "No preview rooms remain after reset/public entry")
	check(workspace:GetAttribute("Level1BlenderRoomCount") == nil, "Preview room-count attribute reset")
	result.counts.puzzleItems = puzzle and #puzzle:GetDescendants() or 0
	result.serverMemoryMbAfter = memory()
	return finish()
end
check(result.flags.round, "Preview has entered the actual gameplay round")
check(result.flags.level == 1, "Preview uses SelectedLevel 1")
check(result.flags.world and result.flags.decor, "World/decor readiness completed")
check(maze ~= nil and rooms ~= nil, "Blender room scene exists")
if not maze or not rooms then return finish() end
local grid, cell, origin = workspace:GetAttribute("GRID"), workspace:GetAttribute("CELL"), workspace:GetAttribute("ORIGIN")
check(type(grid) == "number" and grid % 1 == 0 and grid >= 2 and grid <= 60
	and type(cell) == "number" and cell > 0 and type(origin) == "number", "Bounded valid topology metadata")
if #result.failures > 0 then return finish() end
local kit = game:GetService("ServerStorage"):FindFirstChild("Level1BlenderKit")
check(kit ~= nil and kit:GetAttribute("Ready") == true and kit:GetAttribute("Complete") == true,
	"Imported Blender kit ready/complete")
check(kit ~= nil and type(kit:GetAttribute("ManifestSha256")) == "string"
	and #kit:GetAttribute("ManifestSha256") == 64, "Native asset manifest provenance")
local components = kit and kit:FindFirstChild("Components")
local templates = kit and kit:FindFirstChild("Rooms")
local required = {"FloorPanel", "WallHalf", "CeilingPanel", "LightFixture", "MetalPanel",
	"Chair", "Table", "Telephone", "CardboardPile", "Printer", "GrandfatherClock"}
for _, name in ipairs(required) do
	local item = components and components:FindFirstChild(name)
	check(item ~= nil and item:IsA("Model") and item:FindFirstChildWhichIsA("MeshPart", true) ~= nil,
		"Blender component " .. name)
end
local masks = {}
for _, model in ipairs(templates and templates:GetChildren() or {}) do
	local mask = model:GetAttribute("OpenMask")
	if type(mask) == "number" then masks[mask] = true end
end
for mask = 1, 15 do check(masks[mask] == true, "Imported socket mask " .. mask) end
local expectedPBR = {
	Carpet = {"rbxassetid://88740987992118", "rbxassetid://112651048790918", "rbxassetid://119613328534087"},
	Wallpaper = {"rbxassetid://73926493570331", "rbxassetid://85462985577099", "rbxassetid://82647239498889"},
	Ceiling = {"rbxassetid://83397021691558", "rbxassetid://95726546265735", "rbxassetid://123084910119207"},
}
local pbrCount, meshCount, sourceMissing = {}, 0, 0
for _, part in ipairs(maze:GetDescendants()) do
	if part:IsA("MeshPart") and part:GetAttribute("BlenderChunk") ~= nil then
		meshCount += 1
		local sha, asset = part:GetAttribute("BlenderSourceSha256"), part:GetAttribute("BlenderAssetId")
		if type(sha) ~= "string" or #sha ~= 64 or not asset or part.MeshId == "" then sourceMissing += 1 end
		local material = part:GetAttribute("BlenderMaterial")
		local maps = expectedPBR[material]
		if maps then
			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			if surface and surface.ColorMap == maps[1] and surface.NormalMap == maps[2]
				and surface.RoughnessMap == maps[3] then pbrCount[material] = (pbrCount[material] or 0) + 1 end
		end
	end
end
result.counts.meshes, result.counts.pbr, result.counts.sourceMissing = meshCount, pbrCount, sourceMissing
check(meshCount > 0 and sourceMissing == 0, "Runtime meshes preserve asset/source provenance")
for name in pairs(expectedPBR) do check((pbrCount[name] or 0) > 0, "Runtime PBR albedo/normal/roughness " .. name) end
local cells, duplicate, invalid, blockedDetails, visiblePitFloors, pitRooms = {}, 0, 0, 0, 0, 0
local function key(x, z) return x .. "," .. z end
local function role(part, room)
	local tagged = part:GetAttribute("RoomRole")
	if tagged then return tagged end
	local parent = part.Parent
	while parent and parent ~= room do
		if parent.Name == "SurfaceFloor" or parent.Name == "SurfaceCeiling" or parent.Name == "ShellWalls" then return parent.Name end
		parent = parent.Parent
	end
	return nil
end
for _, room in ipairs(rooms:GetChildren()) do
	local x, z, mask = room:GetAttribute("CellX"), room:GetAttribute("CellZ"), room:GetAttribute("OpenMask")
	if type(x) ~= "number" or type(z) ~= "number" or type(mask) ~= "number"
		or x % 1 ~= 0 or z % 1 ~= 0 or x < 1 or x > grid or z < 1 or z > grid
		or mask % 1 ~= 0 or mask < 0 or mask > 15 then invalid += 1; continue end
	if cells[key(x,z)] then duplicate += 1 end
	cells[key(x,z)] = {x = x, z = z, mask = mask, room = room}
	local pit = room:GetAttribute("PitCell") == true
	local elevator = room:GetAttribute("ElevatorCell") == true
	if pit then pitRooms += 1 end
	for _, part in ipairs(room:GetDescendants()) do
		if part:IsA("BasePart") then
			local kind = role(part, room)
			if kind == "Collider" and not part.CanCollide and not pit and not elevator then blockedDetails += 1 end
			if kind == "SurfaceFloor" and pit and part.Transparency < 1 then visiblePitFloors += 1 end
		end
	end
end
local children = #rooms:GetChildren()
result.counts.rooms, result.counts.invalidRooms, result.counts.duplicateRooms = children, invalid, duplicate
result.counts.disabledDetailColliders, result.counts.visiblePitFloors = blockedDetails, visiblePitFloors
result.counts.pitRooms = pitRooms
check(children == grid * grid and duplicate == 0 and invalid == 0, "One authored room per grid cell")
check(workspace:GetAttribute("Level1BlenderRoomCount") == grid * grid, "Published Blender room count matches scene")
check(blockedDetails == 0, "Authored pillar/detail colliders remain physical")
check(pitRooms > 0, "Original pit-room population retained and marked")
check(visiblePitFloors == 0, "Blender carpet does not conceal lethal pit openings")
local dirs = {{0,1,1,4}, {1,0,2,8}, {0,-1,4,1}, {-1,0,8,2}}
local reciprocal, boundary, edges = 0, 0, 0
for _, item in pairs(cells) do
	for _, d in ipairs(dirs) do
		local open = bit32.band(item.mask, d[3]) ~= 0
		local other = cells[key(item.x+d[1], item.z+d[2])]
		if not other and open then boundary += 1
		elseif other and open ~= (bit32.band(other.mask,d[4]) ~= 0) then reciprocal += 1 end
		if open then edges += 1 end
	end
end
check(boundary == 0 and reciprocal == 0, "Sockets seal borders and match every adjacent room")
local queue, seen = {}, {}
local first = next(cells)
if first then queue[1]=cells[first]; seen[first]=true end
local index = 1
while index <= #queue do
	local item = queue[index]; index += 1
	for _, d in ipairs(dirs) do
		local id = key(item.x+d[1],item.z+d[2]); local other = cells[id]
		if other and not seen[id] and bit32.band(item.mask,d[3]) ~= 0 then seen[id]=true; table.insert(queue,other) end
	end
end
result.counts.connectedCells, result.counts.openEdges = #queue, edges / 2
check(#queue == grid * grid, "Socket graph reaches every room")
-- MCP cannot require privileged Studio modules. These IDs are the freshly
-- inspected central DevAccess allowlist for this receipt, not game authority.
local DevAccess = {IsAllowed = function(player)
	return player.UserId == 40920547 or player.UserId == 9488575949
end}
local participants = 0
for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
	if player:GetAttribute("InRound") == true then
		participants += 1
		check(DevAccess.IsAllowed(player), "Preview participant authorized: " .. player.UserId)
	end
end
result.counts.participants = participants
check(participants > 0, "Original round owns real participants")
check(workspace:FindFirstChild("MazeStart") ~= nil and workspace:FindFirstChild("EntityStart") ~= nil
	and workspace:FindFirstChild("Elevator") ~= nil and workspace:FindFirstChild("Entity") ~= nil,
	"Original elevator/entity/start-marker loop preserved")
local objectiveCounts, targets, targetKinds = {FuseRelay=0,FuseBox=0,Lever=0}, {}, {}
for _, model in ipairs(puzzle and puzzle:GetChildren() or {}) do
	local kind = if model.Name == "FuseRelay" then "FuseRelay" elseif model.Name:sub(1,7) == "FuseBox" then "FuseBox"
		elseif model.Name:sub(1,5) == "Lever" then "Lever" else nil
	if kind then
		objectiveCounts[kind] += 1
		check(model:FindFirstChildWhichIsA("ProximityPrompt",true) ~= nil, "Original objective prompt: " .. model.Name)
		if not targetKinds[kind] and model:IsA("Model") then
			targetKinds[kind] = true
			targets[#targets+1] = {kind=kind,model=model}
		end
	end
end
result.counts.objectives = objectiveCounts
local circuits = math.clamp(math.ceil(participants / 2),1,3)
check(objectiveCounts.FuseBox == circuits and objectiveCounts.Lever == circuits, "Original party-sized boxes/levers")
check(objectiveCounts.FuseRelay == workspace:GetAttribute("Level1RelaySpawnTarget")
	and objectiveCounts.FuseRelay == workspace:GetAttribute("Level1RelaysPlaced"), "Original relay population complete")
local ray = RaycastParams.new(); ray.FilterType=Enum.RaycastFilterType.Include
ray.FilterDescendantsInstances={maze}; ray.RespectCanCollide=true
local function landing(p)
	local hit=workspace:Raycast(Vector3.new(p.X,9,p.Z),Vector3.new(0,-15,0),ray)
	return hit and hit.Normal.Y > .7 and hit.Position.Y > -3 and hit.Position+Vector3.new(0,2.5,0) or nil
end
local elevatorX, elevatorZ = workspace:GetAttribute("ELEV_X"), workspace:GetAttribute("ELEV_Y")
check(type(elevatorX) == "number" and type(elevatorZ) == "number", "Original elevator cell metadata available")
if type(elevatorX) ~= "number" or type(elevatorZ) ~= "number" then return finish() end
local start = landing(Vector3.new(origin + elevatorX * cell + 5, 0, origin + (elevatorZ-.5)*cell))
check(start ~= nil, "Colliding start floor outside elevator doors")
for _, target in ipairs(targets) do
	local cf = target.model:GetPivot()
	local goal = landing(cf.Position + cf.LookVector * 6)
	local sample = {objective = target.model.Name, status = "NO_SAFE_ENDPOINT"}
	if start and goal then
		local path = game:GetService("PathfindingService"):CreatePath({AgentRadius=1.6,AgentHeight=5,AgentCanJump=true,WaypointSpacing=6})
		local done, success, problem = false, false, nil
		local started = os.clock()
		local worker = task.spawn(function() success,problem=pcall(function() path:ComputeAsync(start,goal) end); done=true end)
		while not done and os.clock()-started < 4 do task.wait(.05) end
		if not done then task.cancel(worker); sample.status="TIMEOUT"
		elseif not success then sample.status="ERROR"; sample.error=tostring(problem)
		else sample.status=path.Status.Name; sample.waypoints=#path:GetWaypoints() end
		sample.elapsedSeconds=os.clock()-started
		path:Destroy()
	end
	result.paths[#result.paths+1]=sample
	check(sample.status=="Success", "Engine navigation sample: " .. target.model.Name, sample.status)
end
check(#result.paths==3, "Three bounded engine navigation samples executed")
local frames, frameSum, longest = 0, 0, 0
for _=1,12 do local dt=RunService.Heartbeat:Wait(); frames+=1; frameSum+=dt; longest=math.max(longest,dt) end
result.heartbeat={samples=frames,meanSeconds=frameSum/frames,maxSeconds=longest,
	note="Heartbeat timing is not a server CPU measurement"}
result.serverMemoryMbAfter=memory()
result.flagsStillActive=workspace:GetAttribute("RoundActive")==true and workspace:GetAttribute("Level1BlenderPreviewActive")==true
check(result.flagsStillActive, "Round remained active throughout probe")
return finish()
