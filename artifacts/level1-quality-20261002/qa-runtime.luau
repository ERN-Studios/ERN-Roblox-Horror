-- Read-only Studio MCP Server Play probe. Run after the authorized preview round starts,
-- and once more after its teardown. No launch, prompt, teleport or round writes.
-- Engine path samples are bounded to three requests/four seconds each.
local HS = game:GetService("HttpService")
local RunService = game:GetService("RunService")
assert(RunService:IsServer() and RunService:IsRunning(), "Run this probe in the Play Server datamodel")
local began = os.clock()
local EXPECTED_MANIFEST_SHA256 = "dbfb65f59d765fdf1266734442b69f921fa7ae61295c17a715e69cf47a0b3c53"
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
local kit = game:GetService("ServerStorage"):FindFirstChild("Level1BlenderKitV2")
check(kit ~= nil and kit:GetAttribute("Ready") == true and kit:GetAttribute("Complete") == true,
	"Imported Blender kit ready/complete")
check(kit ~= nil and type(kit:GetAttribute("ManifestSha256")) == "string"
	and #kit:GetAttribute("ManifestSha256") == 64, "Native asset manifest provenance")
check(#EXPECTED_MANIFEST_SHA256 == 64 and kit ~= nil
	and kit:GetAttribute("ManifestSha256") == EXPECTED_MANIFEST_SHA256,
	"Imported kit matches the independent final native V2 manifest")
local components = kit and kit:FindFirstChild("Components")
local templates = kit and kit:FindFirstChild("Rooms")
local required = {"FloorPanel", "WallHalf", "CeilingPanel", "LightFixture", "MetalPanel",
	"Chair", "Table", "Telephone", "CardboardPile", "Printer", "GrandfatherClock",
	"RelayShell", "FuseBoxShell", "LeverShell", "ExitPortal", "ExitDoor", "RelayDoor",
	"Fluorescent", "GridFixture", "LeverShaft", "LeverKnob", "FuseCore", "FuseCap", "FuseSocket", "WallShort"}
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
-- A partial/mismatched install is a failed receipt, not an exception or a
-- plausible-looking runtime scene that the remaining inspector can approve.
if #result.failures>0 then return finish() end
local expectedPBR, approvedAssets, invalidNativeAssets = {}, {}, 0
for _, part in ipairs(kit and kit:GetDescendants() or {}) do
	if part:IsA("MeshPart") then
		local asset, sha = part:GetAttribute("BlenderAssetId"), part:GetAttribute("BlenderSourceSha256")
		if not asset or type(sha) ~= "string" or #sha ~= 64 or part.MeshId == "" then invalidNativeAssets += 1
		else approvedAssets[tostring(asset).."|"..tostring(part:GetAttribute("BlenderChunk"))] = {
			sha=sha,mesh=part.MeshId,chunk=part:GetAttribute("BlenderChunk")} end
		local surface = part:FindFirstChildOfClass("SurfaceAppearance")
		local material = part:GetAttribute("BlenderMaterial")
		if surface and material and not expectedPBR[material] then
			expectedPBR[material] = {surface.ColorMap,surface.NormalMap,surface.RoughnessMap,surface.MetalnessMap}
		end
	end
end
check(invalidNativeAssets==0 and next(approvedAssets)~=nil,"V2 native templates have actual mesh/hash identities")
for _, name in ipairs({"Carpet","Wallpaper","Ceiling"}) do
	local maps=expectedPBR[name]
	check(maps~=nil and maps[1]~="" and maps[2]~="" and maps[3]~="","Native PBR map channels: "..name)
end
check(expectedPBR.Wallpaper~=nil and expectedPBR.Wallpaper[1]=="rbxassetid://87947439437597",
	"Original authored wallpaper ColorMap restored")
local pbrCount, meshCount, sourceMissing, mapMismatch = {}, 0, 0, 0
local sceneRoots={maze,puzzle,workspace:FindFirstChild("Elevator"),workspace:FindFirstChild("Decor")}
for _, sceneRoot in pairs(sceneRoots) do
for _, part in ipairs(sceneRoot:GetDescendants()) do
	if part:IsA("MeshPart") and part:GetAttribute("BlenderChunk") ~= nil then
		meshCount += 1
		local sha, asset = part:GetAttribute("BlenderSourceSha256"), part:GetAttribute("BlenderAssetId")
		local native=approvedAssets[tostring(asset).."|"..tostring(part:GetAttribute("BlenderChunk"))]
		if not native or sha~=native.sha or part.MeshId~=native.mesh
			or part:GetAttribute("BlenderChunk")~=native.chunk then sourceMissing += 1 end
		local material = part:GetAttribute("BlenderMaterial")
		local maps = expectedPBR[material]
		if maps then
			local surface = part:FindFirstChildOfClass("SurfaceAppearance")
			if surface and surface.ColorMap == maps[1] and surface.NormalMap == maps[2]
				and surface.RoughnessMap == maps[3] and surface.MetalnessMap==maps[4] then
				pbrCount[material] = (pbrCount[material] or 0) + 1
			else mapMismatch+=1 end
		end
	end
end
end
result.counts.meshes, result.counts.pbr, result.counts.sourceMissing = meshCount, pbrCount, sourceMissing
check(meshCount > 0 and sourceMissing == 0, "Runtime meshes preserve asset/source provenance")
check(mapMismatch==0,"Runtime PBR maps match the exact approved V2 native components")
for _, name in ipairs({"Carpet","Wallpaper","Ceiling"}) do
	check((pbrCount[name] or 0) > 0, "Runtime PBR albedo/normal/roughness " .. name)
end
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
local function nativePieceKey(part)
	return tostring(part:GetAttribute("BlenderAssetId")).."|"..tostring(part:GetAttribute("BlenderSourceSha256"))
		.."|"..tostring(part:GetAttribute("BlenderChunk")).."|"..tostring(part:GetAttribute("BlenderMaterial"))
end
local function completeComponent(root, componentName)
	local template=components and components:FindFirstChild(componentName)
	if not root or not template then return false end
	local requiredPieces, actualPieces, count={},{},0
	for _, part in ipairs(template:GetDescendants()) do
		if part:IsA("MeshPart") then
			local id=nativePieceKey(part); requiredPieces[id]=(requiredPieces[id] or 0)+1; count+=1
		end
	end
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("MeshPart") and part.Transparency<1 then
			local id=nativePieceKey(part); actualPieces[id]=(actualPieces[id] or 0)+1
		end
	end
	for id, amount in pairs(requiredPieces) do if (actualPieces[id] or 0)<amount then return false end end
	return count>0
end
local function visibleBounds(root, frame)
	local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
	local count=0
	for _, mesh in ipairs(root:GetDescendants()) do
		if mesh:IsA("MeshPart") and mesh.Transparency<1 then
			count+=1
			for _, x in ipairs({-1,1}) do for _, y in ipairs({-1,1}) do for _, z in ipairs({-1,1}) do
				local p=frame:PointToObjectSpace(mesh.CFrame:PointToWorldSpace(mesh.Size*Vector3.new(x,y,z)*.5))
				low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
				high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
			end end end
		end
	end
	return count>0 and high-low or nil
end
local function colorDistance(a,b)
	return (Vector3.new(a.R,a.G,a.B)-Vector3.new(b.R,b.G,b.B)).Magnitude
end
local function weldedVisual(proxy)
	local visual=proxy and proxy:FindFirstChild("BlenderVisual")
	if not visual then return false end
	local meshes=0
	for _, mesh in ipairs(visual:GetDescendants()) do
		if mesh:IsA("MeshPart") then
			meshes+=1
			local attached=false
			for _, weld in ipairs(mesh:GetChildren()) do
				if weld:IsA("WeldConstraint") and weld.Part0==proxy and weld.Part1==mesh then attached=true end
			end
			if mesh.Anchored or not mesh.Massless or not attached or mesh.CanCollide or mesh.CanQuery or mesh.CanTouch then return false end
		end
	end
	return meshes>0
end
local fixtures, lampPieces, neonHousing, fixtureMismatch, fixtureDepthMismatch, fixtureStyles=0,0,0,0,0,{}
local fixtureTemplateMismatch,fixtureAliases=0,{}
for _, name in ipairs({"Fluorescent","GridFixture"}) do
	local template=components and components:FindFirstChild(name)
	if template then fixtureAliases[name]=template:GetAttribute("BlenderComponent") end
end
for _, part in ipairs(maze:GetDescendants()) do
	if part.ClassName=="Part" and part:FindFirstChildOfClass("SurfaceLight") then
		local visual=part:FindFirstChild("BlenderVisual")
		if visual then
			fixtures+=1
			-- GridFixture currently aliases Fluorescent. Count each physical
			-- visual once using its imported canonical identity, rather than
			-- counting every alias with the same matching mesh signatures.
			local name=visual:GetAttribute("BlenderComponent")
			local template=type(name)=="string" and components and components:FindFirstChild(name)
			if template and completeComponent(visual,name) then
				fixtureStyles[name]=(fixtureStyles[name] or 0)+1
				local _, nativeSize=template:GetBoundingBox()
				local bounds=visibleBounds(visual,part.CFrame)
				if not bounds or math.abs(bounds.Y-nativeSize.Y)>.06 then fixtureDepthMismatch+=1 end
			else fixtureTemplateMismatch+=1 end
			for _, mesh in ipairs(visual:GetDescendants()) do
				if mesh:IsA("MeshPart") then
					local emitter=mesh:GetAttribute("BlenderMaterial")=="Lamp"
					if emitter then
						lampPieces+=1
						if mesh.Material~=part.Material or (Vector3.new(mesh.Color.R,mesh.Color.G,mesh.Color.B)
							-Vector3.new(part.Color.R,part.Color.G,part.Color.B)).Magnitude>.04 then fixtureMismatch+=1 end
					elseif mesh.Material==Enum.Material.Neon then neonHousing+=1 end
				end
			end
		end
	end
end
result.counts.fixtureQuality={fixtures=fixtures,lamps=lampPieces,neonHousing=neonHousing,
	stateMismatch=fixtureMismatch,depthMismatch=fixtureDepthMismatch,styles=fixtureStyles,
	aliases=fixtureAliases,templateMismatch=fixtureTemplateMismatch}
check(fixtures>0 and lampPieces>0,"Real sparse fixtures contain authored emitter pieces")
check(fixtures>0 and fixtureTemplateMismatch==0,"Every physical fixture matches its complete authored native component once")
check(neonHousing==0,"Fixture metal/housing pieces do not become Neon")
check(fixtureMismatch==0,"Only emitter pieces follow actual live fixture color/material phase")
check(fixtureDepthMismatch==0,"Sparse ceiling fixtures retain the actual authored three-dimensional depth")

-- Independent actual-geometry inspection. The broad phase hashes world bounds;
-- narrow phase tests the fifteen OBB separating axes, including rotated pillars.
local function obb(part)
	local cf, half=part.CFrame,part.Size*.5
	local axes={cf.RightVector,cf.UpVector,cf.ZVector}
	local extent=Vector3.new(math.abs(axes[1].X)*half.X+math.abs(axes[2].X)*half.Y+math.abs(axes[3].X)*half.Z,
		math.abs(axes[1].Y)*half.X+math.abs(axes[2].Y)*half.Y+math.abs(axes[3].Y)*half.Z,
		math.abs(axes[1].Z)*half.X+math.abs(axes[2].Z)*half.Y+math.abs(axes[3].Z)*half.Z)
	return {part=part,center=cf.Position,axes=axes,half={half.X,half.Y,half.Z},low=cf.Position-extent,high=cf.Position+extent}
end
local function boxesOverlap(a,b)
	local difference=b.center-a.center
	local function separated(axis)
		local length=axis.Magnitude
		if length<1e-6 then return false end
		axis/=length
		local reach=0
		for index=1,3 do reach+=a.half[index]*math.abs(a.axes[index]:Dot(axis))+b.half[index]*math.abs(b.axes[index]:Dot(axis)) end
		return math.abs(difference:Dot(axis))>=reach-.02 -- contact/tiny joins are permitted
	end
	for index=1,3 do if separated(a.axes[index]) or separated(b.axes[index]) then return false end end
	for x=1,3 do for z=1,3 do if separated(a.axes[x]:Cross(b.axes[z])) then return false end end end
	return true
end
local function inspectExitAperture(model, sign, header)
	local detail={pieces={},vestibule={},blocking={},floorSamples={}}
	result.exitAperture=detail
	local frame=model:GetAttribute("ExitApertureFrame")
	check(model:GetAttribute("ExitApertureReady")==true and typeof(frame)=="CFrame",
		"Actual exit aperture owns a completed frame")
	if typeof(frame)~="CFrame" then return end
	local queryWalls={}
	for _,part in ipairs(maze:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("Level1ExitQueryWall")==true then queryWalls[#queryWalls+1]=part end
	end
	check(#queryWalls==1,"Exactly one original outer wall remains query-only at the exit")
	local native=queryWalls[1]
	if not native then return end
	detail.queryWall={path=native:GetFullName(),size=tostring(native.Size),collide=native.CanCollide,query=native.CanQuery}
	check(native.ClassName=="Part" and native.CanQuery and not native.CanCollide
		and math.max(native.Size.X,native.Size.Z)>=grid*cell-.02,
		"Exit preserves the full original boundary query wall without its blocking collision")
	local function localBounds(part)
		local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
		for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
			local p=frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*.5*Vector3.new(x,y,z)))
			low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
			high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
		end end end
		return low,high
	end
	local low,high=localBounds(native)
	local bottom,top=-frame.Position.Y,7.5
	local gap=obb({CFrame=frame*CFrame.new(0,(bottom+top)*.5,(low.Z+high.Z)*.5),
		Size=Vector3.new(7,top-bottom,high.Z-low.Z)})
	local physics=model:FindFirstChild("ExitAperturePhysics")
	local pieces,seen,invalid,volume,overlap={},{},0,0,0
	for _,part in ipairs(physics and physics:GetChildren() or {}) do
		if part:IsA("BasePart") then
			local key=part:GetAttribute("ExitAperturePiece")
			local a,b=localBounds(part)
			local allowed=key=="Left" or key=="Right" or key=="Header" or key=="Sill"
			if not allowed or seen[key] or not part.Anchored or not part.CanCollide or part.CanQuery or part.CanTouch
				or a.X<low.X-.02 or b.X>high.X+.02 or a.Y<low.Y-.02 or b.Y>high.Y+.02
				or math.abs(a.Z-low.Z)>.02 or math.abs(b.Z-high.Z)>.02 then invalid+=1 end
			if key then seen[key]=true end
			local box=obb(part)
			if boxesOverlap(box,gap) then invalid+=1 end
			for _,other in ipairs(pieces) do if boxesOverlap(box,other) then overlap+=1 end end
			pieces[#pieces+1]=box
			volume+=part.Size.X*part.Size.Y*part.Size.Z
			detail.pieces[#detail.pieces+1]={name=key,path=part:GetFullName(),size=tostring(part.Size)}
		else invalid+=1 end
	end
	local removed=math.max(0,math.min(high.X,3.5)-math.max(low.X,-3.5))
		*math.max(0,math.min(high.Y,top)-math.max(low.Y,bottom))*(high.Z-low.Z)
	local expected=native.Size.X*native.Size.Y*native.Size.Z-removed
	detail.sealedVolume,detail.expectedSealedVolume=volume,expected
	check((#pieces==3 or #pieces==4) and seen.Left and seen.Right and seen.Header
		and invalid==0 and overlap==0 and math.abs(volume-expected)<.1,
		"Actual side/header collision seals the boundary and leaves only the intended seven-stud aperture")
	local vestibule=model:FindFirstChild("ExitVestibule")
	local base=frame*CFrame.new(0,-frame.Position.Y,4.1)
	local expectedParts={
		Floor={Vector3.new(8,.32,8),Vector3.new(0,-.16,0)},
		Ceiling={Vector3.new(8,.36,8),Vector3.new(0,14.18,0)},
		Back={Vector3.new(8,14,1/3),Vector3.new(0,7,11.5/3)},
		Left={Vector3.new(1/3,14,8),Vector3.new(-11.5/3,7,0)},
		Right={Vector3.new(1/3,14,8),Vector3.new(11.5/3,7,0)},
	}
	local count,mismatch=0,0
	for _,part in ipairs(vestibule and vestibule:GetChildren() or {}) do
		if part:IsA("BasePart") and part:GetAttribute("ExitVestibulePhysics")==true then
			count+=1
			local rule=expectedParts[part.Name]
			local target=rule and base*CFrame.new(rule[2])
			if not rule or not part.Anchored or not part.CanCollide or part.CanQuery or part.CanTouch
				or (part.Size-rule[1]).Magnitude>.02 or (part.Position-target.Position).Magnitude>.02
				or part.CFrame.RightVector:Dot(target.RightVector)<.999 or part.CFrame.UpVector:Dot(target.UpVector)<.999 then mismatch+=1 end
			detail.vestibule[#detail.vestibule+1]={name=part.Name,size=tostring(part.Size)}
		end
	end
	check(vestibule~=nil and count==5 and mismatch==0,"Actual eight-stud exit vestibule has matching floor, ceiling and three sealed physical faces")
	check(sign~=nil and header~=nil and sign.CanCollide==(header.Text=="EXIT LOCKED"),
		"Actual exit leaf blocks the locked aperture and releases it only when open")
	local body=obb({CFrame=frame*CFrame.new(0,-frame.Position.Y+3.05,2),Size=Vector3.new(3.4,5.5,7)})
	local hiddenOriginal,croppedArt,artMismatch=0,0,0
	for _,object in ipairs(rooms:GetDescendants()) do
		if object:IsA("Model") and object:GetAttribute("ExitApertureOriginal")==true then
			hiddenOriginal+=1
			for _,part in ipairs(object:GetDescendants()) do
				if part:IsA("BasePart") and (part.Transparency~=1 or part.CanCollide or part.CanQuery) then artMismatch+=1 end
			end
		elseif object:IsA("Model") and object:GetAttribute("ExitAperturePiece")~=nil then
			croppedArt+=1
			local meshes=0
			for _,part in ipairs(object:GetDescendants()) do
				if part:IsA("BasePart") then
					if part:IsA("MeshPart") then meshes+=1 end
					if part.CanCollide or part.CanQuery or boxesOverlap(body,obb(part)) then artMismatch+=1 end
				end
			end
			if meshes==0 then artMismatch+=1 end
		end
	end
	detail.hiddenOriginal,detail.croppedArt=hiddenOriginal,croppedArt
	check(hiddenOriginal==1 and croppedArt>=3 and croppedArt<=4 and artMismatch==0,
		"Actual original shell is hidden and matching cropped Blender art leaves the avatar aperture clear")
	for _,root in ipairs({maze,puzzle,workspace:FindFirstChild("Decor")}) do
		for _,part in ipairs(root:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide and part~=sign and boxesOverlap(body,obb(part)) then
				detail.blocking[#detail.blocking+1]=part:GetFullName()
			end
		end
	end
	check(#detail.blocking==0,"Actual avatar passage crosses the aperture into the vestibule without other physical blockers")
	local floorParams=RaycastParams.new()
	floorParams.FilterType=Enum.RaycastFilterType.Include
	floorParams.FilterDescendantsInstances={maze,puzzle}
	floorParams.RespectCanCollide=true
	local missingFloor=0
	for _,x in ipairs({-1.5,0,1.5}) do for _,z in ipairs({-1.5,0,1.5,3.5,5.5}) do
		local from=frame:PointToWorldSpace(Vector3.new(x,-frame.Position.Y+1.5,z))
		local hit=workspace:Raycast(from,Vector3.new(0,-3,0),floorParams)
		local safe=hit~=nil and hit.Normal.Y>.99 and math.abs(hit.Position.Y)<.15
		if not safe then missingFloor+=1 end
		detail.floorSamples[#detail.floorSamples+1]={x=x,z=z,safe=safe,floor=hit and hit.Instance:GetFullName()}
	end end
	check(missingFloor==0,"Actual structural floor remains continuous across the exit threshold and vestibule")
	local safeRoom=workspace:FindFirstChild("SafeRoom")
	check(safeRoom~=nil and safeRoom:IsA("Model"),"Original separate escape SafeRoom remains available")
end
local wallHeight=workspace:GetAttribute("WALL_H")
local function isStructuralPlane(part,box)
	-- The original floor tiles/beams and single ceiling have anonymous Part
	-- names. Match their actual native parent, orientation and dimensions;
	-- a thin tabletop or lifted furniture panel must still enter the audit.
	if part.Parent~=maze or part.ClassName~="Part" or math.abs(part.CFrame.UpVector.Y-1)>.0001
		or math.abs(part.Size.Y-1)>.0001 then return false end
	if math.abs(box.high.Y)<.01 then return true end
	return type(wallHeight)=="number" and math.abs(box.low.Y-wallHeight)<.01
		and math.abs(part.Size.X-grid*cell)<.01 and math.abs(part.Size.Z-grid*cell)<.01
		and math.abs(part.CFrame.Position.X)<.01 and math.abs(part.CFrame.Position.Z)<.01
end
local function riserKind(wire,circuitId,terminals,height)
	for _, terminal in ipairs(terminals) do
		local point=terminal.position
		if terminal.circuit==circuitId and math.abs(wire.center.X-point.X)<.02
			and math.abs(wire.center.Z-point.Z)<.02 and math.abs(wire.high.Y-point.Y)<.02 then
			return "terminal"
		end
	end
	if type(height)=="number" and math.abs(wire.high.Y-(height-.4))<.02 and wire.low.Y<=.12 then
		return "fullHeight"
	end
	return "other"
end
local bins,obstacleCount={},0
local structuralPlanesExcluded=0
local function binKey(x,z) return x..","..z end
for _, root in pairs({maze,workspace:FindFirstChild("Decor"),workspace:FindFirstChild("Elevator")}) do
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			local box=obb(part)
			local structuralPlane=isStructuralPlane(part,box)
			if structuralPlane then structuralPlanesExcluded+=1 end
			if box.high.Y>.01 and not structuralPlane then
				obstacleCount+=1
				for x=math.floor(box.low.X/cell),math.floor(box.high.X/cell) do
					for z=math.floor(box.low.Z/cell),math.floor(box.high.Z/cell) do
						local id=binKey(x,z); bins[id]=bins[id] or {}; table.insert(bins[id],box)
					end
				end
			end
		end
	end
end
local cableCount, cableIntersections, cableUnskinned, cableMetadata=0,0,0,0
local collisions={}
local cableTerminals={}
local risers={total=0,terminal=0,fullHeight=0,other=0}
for _, jack in ipairs(puzzle and puzzle:GetDescendants() or {}) do
	if jack.ClassName=="Part" and jack.Name=="CableJack" then
		cableTerminals[#cableTerminals+1]={position=jack.Position,circuit=jack.Parent:GetAttribute("CircuitId")}
	end
end
for _, cable in ipairs(puzzle and puzzle:GetDescendants() or {}) do
	if cable.ClassName=="Part" and cable.Name=="ObjectiveCable" then
		cableCount+=1
		if not cable:FindFirstChild("BlenderVisual") then cableUnskinned+=1 end
		if type(cable:GetAttribute("CircuitId"))~="string" or type(cable:GetAttribute("SegmentIndex"))~="number" then cableMetadata+=1 end
		local wire=obb(cable); local examined={}
		if cable:GetAttribute("Vertical")==true then
			risers.total+=1
			local kind=riserKind(wire,cable:GetAttribute("CircuitId"),cableTerminals,wallHeight)
			risers[kind]+=1
			risers.minY=math.min(risers.minY or wire.low.Y,wire.low.Y)
			risers.maxY=math.max(risers.maxY or wire.high.Y,wire.high.Y)
		end
		for x=math.floor(wire.low.X/cell),math.floor(wire.high.X/cell) do
			for z=math.floor(wire.low.Z/cell),math.floor(wire.high.Z/cell) do
				for _, box in ipairs(bins[binKey(x,z)] or {}) do
					if not examined[box.part] then
						examined[box.part]=true
						if wire.high.Y>box.low.Y+.02 and wire.low.Y<box.high.Y-.02 and boxesOverlap(wire,box) then
							cableIntersections+=1
							if #collisions<12 then collisions[#collisions+1]={cable=cable:GetFullName(),
								obstacle=box.part:GetFullName(),role=box.part:GetAttribute("RoomRole"),
								circuit=cable:GetAttribute("CircuitId"),segment=cable:GetAttribute("SegmentIndex")} end
						end
					end
				end
			end
		end
	end
end
result.counts.cableQuality={segments=cableCount,obstacles=obstacleCount,intersections=cableIntersections,
	unskinned=cableUnskinned,missingMetadata=cableMetadata,structuralPlanesExcluded=structuralPlanesExcluded,
	terminals=#cableTerminals,risers=risers}
result.cableIntersections=collisions
check(cableCount>0 and obstacleCount>0,"Actual routed cable segments and physical wall/pillar cases inspected")
check(cableIntersections==0,"Actual cable OBBs clear every nearby physical wall/column/detail")
check(cableUnskinned==0 and cableMetadata==0,"Actual routed segments retain Blender art and circuit identity")
check(#cableTerminals>0 and risers.terminal==#cableTerminals and risers.other==0,
	"Actual terminal riser count matches circuit jacks and all riser kinds are identified",risers)
if risers.fullHeight==0 then table.insert(result.warnings,"No full-height overhead riser occurred in this generated round") end

local shortRooms,shortVisualMissing,shortPhysicsMissing,shortHeightMismatch=0,0,0,0
local shortTemplate=components and components:FindFirstChild("WallShort")
local shortPieces={}
for _, part in ipairs(shortTemplate and shortTemplate:GetDescendants() or {}) do
	if part:IsA("MeshPart") then shortPieces[nativePieceKey(part)]=true end
end
for _, item in pairs(cells) do
	local room=item.room
	if room:GetAttribute("ShortWall")==true and room:GetAttribute("PitCell")~=true and room:GetAttribute("ElevatorCell")~=true then
		shortRooms+=1
		if not completeComponent(room,"WallShort") then shortVisualMissing+=1 end
		local expectedHeight=room:GetAttribute("ShortWallHeight")
		if type(expectedHeight)~="number" or expectedHeight>=14 or expectedHeight<=3 then shortHeightMismatch+=1; continue end
		-- The renderer scales X/Z to the live cell size and preserves authored Y.
		local minimum,maximum=math.huge,-math.huge
		local physical=false
		for _, part in ipairs(room:GetDescendants()) do
			if part:IsA("BasePart") then
				if part:IsA("MeshPart") and shortPieces[nativePieceKey(part)] and part.Transparency<1 then
					local bounds=obb(part); minimum=math.min(minimum,bounds.low.Y); maximum=math.max(maximum,bounds.high.Y)
				elseif role(part,room)=="Collider" and part.CanCollide and math.abs(part.Size.Y-expectedHeight)<.06 then
					physical=true
				end
			end
		end
		if not physical then shortPhysicsMissing+=1 end
		if maximum-minimum==math.huge or math.abs((maximum-minimum)-expectedHeight)>.16 then shortHeightMismatch+=1 end
	end
end
result.counts.shortWalls={rooms=shortRooms,missingVisual=shortVisualMissing,missingPhysics=shortPhysicsMissing,heightMismatch=shortHeightMismatch}
check(shortRooms>0,"Generated room population includes authored low internal dividers")
check(shortVisualMissing==0 and shortPhysicsMissing==0 and shortHeightMismatch==0,
	"Low internal divider visual and physical heights match the authored 8.5-stud contract")
result.notes={"Short walls are extra internal dividers; closed topology boundary/query walls retain their original full height"}
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
local hardware={shells=0,missingShells=0,controls=0,missingControls=0,unweldedControls=0,
	cues=0,cueMismatch=0,cueStateMismatch=0,glass=0,glassMismatch=0,doorDepthMismatch=0}
local function control(model,name,componentName,moving)
	local proxy=model:FindFirstChild(name)
	hardware.controls+=1
	local visual=proxy and proxy:FindFirstChild("BlenderVisual")
	if not completeComponent(visual,componentName) then hardware.missingControls+=1 end
	if moving and not weldedVisual(proxy) then hardware.unweldedControls+=1 end
	if componentName=="ExitDoor" or componentName=="RelayDoor" then
		local _,nativeSize=components[componentName]:GetBoundingBox()
		local bounds=proxy and visual and visibleBounds(visual,proxy.CFrame)
		if not bounds or math.abs(bounds.Z-nativeSize.Z)>.08 then hardware.doorDepthMismatch+=1 end
	end
	return proxy,visual
end
local function cue(model,name)
	local proxy=model:FindFirstChild(name)
	hardware.cues+=1
	local visual=proxy and proxy:FindFirstChild("BlenderVisual")
	if not visual then hardware.cueMismatch+=1; return nil end
	local count=0
	for _, mesh in ipairs(visual:GetDescendants()) do
		if mesh:IsA("MeshPart") and mesh.Transparency<1 then
			count+=1
			local appearance=mesh:FindFirstChildOfClass("SurfaceAppearance")
			if colorDistance(mesh.Color,proxy.Color)>.04 or mesh.Material~=proxy.Material
				or appearance and colorDistance(appearance.Color,proxy.Color)>.04 then hardware.cueMismatch+=1 end
		end
	end
	if count==0 then hardware.cueMismatch+=1 end
	return proxy
end
local function shell(model,componentName,names)
	hardware.shells+=1
	if not completeComponent(model:FindFirstChild("BlenderVisual"),componentName) then hardware.missingShells+=1 end
	local visuals=0
	for _, child in ipairs(model:GetChildren()) do if child.Name=="BlenderVisual" then visuals+=1 end end
	if visuals~=1 then hardware.missingShells+=1 end
	for _, name in ipairs(names) do
		local proxy=model:FindFirstChild(name)
		if not proxy or proxy.Transparency<1 then hardware.missingShells+=1 end
	end
end
for _, model in ipairs(puzzle and puzzle:GetChildren() or {}) do
	if model.Name=="FuseRelay" then
		shell(model,"RelayShell",{"RelayBody","OuterFrame","InnerPanel"})
		control(model,"RelayDoor","RelayDoor",true)
		cue(model,"RelayIndicator")
		if model:GetAttribute("ContainsFuse")==true then
			control(model,"Fuse","FuseCore",true)
			local caps=0
			for _, cap in ipairs(model:GetChildren()) do
				if cap.Name=="FuseCap" and cap:IsA("BasePart") then
					caps+=1; hardware.controls+=1
					if not completeComponent(cap:FindFirstChild("BlenderVisual"),"FuseCap") then hardware.missingControls+=1 end
					if not weldedVisual(cap) then hardware.unweldedControls+=1 end
				end
			end
			if caps~=2 then hardware.missingControls+=1 end
		end
	elseif model.Name:sub(1,7)=="FuseBox" then
		shell(model,"FuseBoxShell",{"Body","OuterRim"})
		local indicator=cue(model,"Indicator")
		local label=model:FindFirstChild("StatusPlate")
		label=label and label:FindFirstChildWhichIsA("TextLabel",true)
		if indicator and label then
			local color=indicator.Color
			if label.Text=="MISSING FUSE" and color.R<=color.G then hardware.cueStateMismatch+=1 end
			if label.Text=="POWER RESTORED" and color.G<=color.R then hardware.cueStateMismatch+=1 end
			if label.Text=="ALERT" and color.R<=color.G then hardware.cueStateMismatch+=1 end
		end
		local slots=0
		for _, proxy in ipairs(model:GetChildren()) do
			if proxy.Name:sub(1,8)=="FuseSlot" and proxy:IsA("BasePart") then
				slots+=1; hardware.controls+=1
				if not completeComponent(proxy:FindFirstChild("BlenderVisual"),"FuseSocket") then hardware.missingControls+=1 end
			elseif proxy.Name:sub(1,13)=="InstalledFuse" and proxy:IsA("BasePart") then
				hardware.controls+=1
				if not completeComponent(proxy:FindFirstChild("BlenderVisual"),"FuseCore") then hardware.missingControls+=1 end
				if not weldedVisual(proxy) then hardware.unweldedControls+=1 end
			end
		end
		if slots==0 then hardware.missingControls+=1 end
	elseif model.Name:sub(1,5)=="Lever" then
		shell(model,"LeverShell",{"Plate","Rim"})
		control(model,"Handle","LeverShaft",true)
		control(model,"Knob","LeverKnob",true)
		local indicator=cue(model,"StatusLight")
		local label=model:FindFirstChild("StatusPlate")
		label=label and label:FindFirstChildWhichIsA("TextLabel",true)
		if indicator and label then
			local color=indicator.Color
			if label.Text=="LOCKED" and color.R<=color.G then hardware.cueStateMismatch+=1 end
			if label.Text=="LATCHED" and color.G<=color.R then hardware.cueStateMismatch+=1 end
			if label.Text=="READY" and (color.R<=color.G or color.G<.2) then hardware.cueStateMismatch+=1 end
		end
	elseif model.Name=="Exit" then
		shell(model,"ExitPortal",{"PostL","PostR","Top"})
		local sign,visual=control(model,"Sign","ExitDoor",true)
		for _, mesh in ipairs(visual and visual:GetDescendants() or {}) do
			if mesh:IsA("MeshPart") and mesh:GetAttribute("BlenderMaterial")=="GreenGlass" then
				hardware.glass+=1
				if mesh.Material~=Enum.Material.Glass or mesh.Transparency<.25 or mesh.Transparency>.65 then hardware.glassMismatch+=1 end
			end
		end
		local trigger=model:FindFirstChild("Trigger")
		check(trigger~=nil and trigger:IsA("BasePart") and trigger.Transparency==1 and not trigger.CanCollide
			and trigger.CanTouch and (trigger.Size-Vector3.new(7,11,3)).Magnitude<.02,
			"Actual exit retains the original hidden touch trigger")
		local post=model:FindFirstChild("PostL")
		local header=model:FindFirstChild("Header")
		header=header and header:FindFirstChildWhichIsA("TextLabel",true)
		if sign and post and header then
			local closed=post.CFrame*CFrame.new(3.75,0,-.25)
			local expected=closed
			if header.Text=="EXIT" then
				task.wait(.7) -- the real .6-second leaf tween can finish without a write
				expected=closed*CFrame.new(3.5,0,0)*CFrame.Angles(0,math.rad(-95),0)*CFrame.new(-3.5,0,0)
			end
			check(header.Text=="EXIT" or header.Text=="EXIT LOCKED","Actual preview exit exposes locked/open status")
			check((sign.Position-expected.Position).Magnitude<.15 and sign.CFrame.LookVector:Dot(expected.LookVector)>.995,
				"Actual exit leaf follows its locked pose or right-hinged open pose",header.Text)
		else check(false,"Actual authored exit leaf and header exist") end
		inspectExitAperture(model,sign,header)
		for _, proxy in ipairs(model:GetChildren()) do
			if proxy:IsA("BasePart") and (proxy.Name=="EnergyNode" or proxy.Name=="CenterSeam" or proxy.Name=="Reinforcement") then
				check(proxy.Transparency==1 and not proxy:FindFirstChild("BlenderVisual"),"Retired exit dressing hidden: "..proxy.Name)
			end
		end
	end
end
result.counts.hardwareQuality=hardware
check(hardware.shells==objectiveCounts.FuseRelay+objectiveCounts.FuseBox+objectiveCounts.Lever+1
	and hardware.missingShells==0,"All complete authored puzzle casings and the exit portal render once")
check(hardware.controls>0 and hardware.missingControls==0,"Actual relay doors, fuse cores/caps, sockets, lever shaft/knob and exit leaf are complete")
check(hardware.unweldedControls==0,"Actual moving Blender hardware is welded to the original control Parts")
check(hardware.cues>0 and hardware.cueMismatch==0 and hardware.cueStateMismatch==0,
	"Actual red/amber/green state cues match their live controls and labels")
check(hardware.glass>0 and hardware.glassMismatch==0,"Authored exit glazing keeps its Glass material and partial transparency")
check(hardware.doorDepthMismatch==0,"Actual cabinet and exit leaves preserve authored depth")
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
