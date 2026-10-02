-- Blender art is a developer-preview skin over the live Level 1 query/collision grid.
local ServerStorage = game:GetService("ServerStorage")
local Renderer = {}
local activeState
local KIT_NAME = "Level1BlenderKitV2"
local PROP_NAMES = {"Chair", "Table", "Telephone", "CardboardPile", "Printer", "GrandfatherClock"}
local SURFACE_NAMES = {"FloorPanel", "WallHalf", "CeilingPanel", "LightFixture", "MetalPanel"}
local HARDWARE_NAMES = {"RelayShell", "FuseBoxShell", "LeverShell", "ExitPortal", "ExitDoor",
	"RelayDoor", "Fluorescent", "GridFixture", "LeverShaft", "LeverKnob", "FuseCore", "FuseCap", "FuseSocket"}

function Renderer.IsReady()
	local kit = ServerStorage:FindFirstChild(KIT_NAME)
	local components = kit and kit:FindFirstChild("Components")
	local rooms = kit and kit:FindFirstChild("Rooms")
	if not kit or kit:GetAttribute("Ready") ~= true or not components or not rooms then
		return false, "PREVIEW_NOT_READY"
	end
	for _, names in ipairs({PROP_NAMES, SURFACE_NAMES, HARDWARE_NAMES}) do
		for _, name in ipairs(names) do
			local component = components:FindFirstChild(name)
			if not component or not component:IsA("Model") or not component:FindFirstChildWhichIsA("MeshPart", true) then
				return false, "PREVIEW_NOT_READY"
			end
		end
	end
	local masks = {}
	for _, room in ipairs(rooms:GetChildren()) do
		if room:IsA("Model") and room:FindFirstChildWhichIsA("MeshPart", true) then
			local mask = room:GetAttribute("OpenMask")
			if type(mask) == "number" and mask % 1 == 0 and mask >= 0 and mask <= 15 then masks[mask] = true end
		end
	end
	for mask = 1, 15 do
		if not masks[mask] then return false, "PREVIEW_NOT_READY" end
	end
	return true
end

function Renderer.RoomWeight(room)
	local weight = room:GetAttribute("SelectionWeight")
	if type(weight) == "number" and weight == weight then return math.clamp(weight, 0, 100) end
	return room:GetAttribute("Variant") == 1 and 1 or 16
end

function Renderer.PickRoom(choices, roll)
	local total = 0
	for _, room in ipairs(choices) do total += Renderer.RoomWeight(room) end
	assert(total > 0, "Room socket has no enabled variants")
	local target = math.clamp(roll, 0, 1 - 1e-9) * total
	for _, room in ipairs(choices) do
		target -= Renderer.RoomWeight(room)
		if target < 0 then return room end
	end
	return choices[#choices]
end

function Renderer.SkinLayout(componentName, proxySize, authoredSize)
	local ratio = Vector3.new(proxySize.X / authoredSize.X, proxySize.Y / authoredSize.Y, proxySize.Z / authoredSize.Z)
	local offset = Vector3.new(0, 0, 0)
	local fixture = componentName == "LightFixture" or componentName == "Fluorescent" or componentName == "GridFixture"
	if fixture then
		ratio = Vector3.new(ratio.X, 1, ratio.Z)
		offset = Vector3.new(0, componentName == "LightFixture" and (proxySize.Y - authoredSize.Y) * .5 or authoredSize.Y * .5 - .04, 0)
	elseif componentName == "ExitDoor" or componentName == "RelayDoor" then
		ratio = Vector3.new(ratio.X, ratio.Y, 1)
		offset = Vector3.new(0, 0, (proxySize.Z - authoredSize.Z) * .5)
	end
	return ratio, offset, fixture
end

-- Four existing Blender slab pieces leave one ceiling tile open for the recessed fixture.
function Renderer.CeilingPieces(size, tile)
	local halfX, halfZ = size.X * .5, size.Z * .5
	return {
		{Vector3.new(-halfX * .5, 0, 0), Vector3.new(halfX, size.Y, size.Z)},
		{Vector3.new((tile + halfX) * .5, 0, 0), Vector3.new(halfX - tile, size.Y, size.Z)},
		{Vector3.new(tile * .5, 0, -halfZ * .5), Vector3.new(tile, size.Y, halfZ)},
		{Vector3.new(tile * .5, 0, (tile + halfZ) * .5), Vector3.new(tile, size.Y, halfZ - tile)},
	}
end

function Renderer.SkinCarriedFuse(part)
	if not activeState or activeState.closed then return end
	activeState:Skin(part, "FuseCore", true)
	for _, cap in ipairs(part:GetChildren()) do
		if cap:IsA("Part") and cap.Name == "Cap" then activeState:Skin(cap, "FuseCap", true) end
	end
end

-- EXIT_APERTURE_GEOMETRY_BEGIN
function Renderer.ExitBounds(frame, boxFrame, size)
	local relative=frame:ToObjectSpace(boxFrame)
	local x,y,z,xx,xy,xz,yx,yy,yz,zx,zy,zz=relative:GetComponents()
	local half=size*.5
	local sx=math.abs(xx)*half.X+math.abs(xy)*half.Y+math.abs(xz)*half.Z
	local sy=math.abs(yx)*half.X+math.abs(yy)*half.Y+math.abs(yz)*half.Z
	local sz=math.abs(zx)*half.X+math.abs(zy)*half.Y+math.abs(zz)*half.Z
	return {minX=x-sx,maxX=x+sx,minY=y-sy,maxY=y+sy,minZ=z-sz,maxZ=z+sz}
end

function Renderer.ExitPieces(bounds,width,bottom,top)
	local half=width*.5
	if bounds.maxX<=-half or bounds.minX>=half or bounds.maxY<=bottom or bounds.minY>=top
		or bounds.minZ>2.5 or bounds.maxZ< -1.5 or bounds.maxZ-bounds.minZ>3 then return nil end
	local pieces={}
	local function add(name,x0,x1,y0,y1)
		if x1-x0<.001 or y1-y0<.001 then return end
		pieces[#pieces+1]={name=name,center=Vector3.new((x0+x1)*.5,(y0+y1)*.5,(bounds.minZ+bounds.maxZ)*.5),
			size=Vector3.new(x1-x0,y1-y0,bounds.maxZ-bounds.minZ)}
	end
	add("Left",bounds.minX,math.min(bounds.maxX,-half),bounds.minY,bounds.maxY)
	add("Right",math.max(bounds.minX,half),bounds.maxX,bounds.minY,bounds.maxY)
	local x0,x1=math.max(bounds.minX,-half),math.min(bounds.maxX,half)
	add("Header",x0,x1,math.max(bounds.minY,top),bounds.maxY)
	add("Sill",x0,x1,bounds.minY,math.min(bounds.maxY,bottom))
	return pieces
end
-- EXIT_APERTURE_GEOMETRY_END

function Renderer.MakeExitAperture(model,frame)
	assert(activeState and not activeState.closed,"Preview exit has no active renderer")
	activeState:ExitAperture(model,frame)
end

-- N is +Z, E is +X. A set bit is an open socket, never a wall.
function Renderer.OpenMask(wallV, wallH, grid, x, z)
	local mask = 0
	if z < grid and not wallH[x][z] then mask += 1 end
	if x < grid and not wallV[x][z] then mask += 2 end
	if z > 1 and not wallH[x][z - 1] then mask += 4 end
	if x > 1 and not wallV[x - 1][z] then mask += 8 end
	return mask
end

function Renderer.Begin(maze)
	if workspace:GetAttribute("Level1BlenderPreviewActive") ~= true then return nil end
	assert(Renderer.IsReady(), "Level 1 Blender assets are incomplete")
	local kit = ServerStorage[KIT_NAME]
	local state = {connections = {}, closed = false, skinned = {}, apertureCleanups = {}, recessCells = {}}
	activeState = state
	local roomsByMask = {}
	for _, room in ipairs(kit.Rooms:GetChildren()) do
		if room:IsA("Model") then
			local mask = room:GetAttribute("OpenMask")
			if type(mask) == "number" then
				roomsByMask[mask] = roomsByMask[mask] or {}
				table.insert(roomsByMask[mask], room)
			end
		end
	end
	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(state.connections, connection)
		return connection
	end
	function state:Cleanup()
		if self.closed then return end
		self.closed = true
		if activeState == self then activeState = nil end
		for _, cleanup in pairs(self.apertureCleanups) do cleanup() end
		table.clear(self.apertureCleanups)
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
		table.clear(self.skinned)
		table.clear(self.recessCells)
	end
	connect(maze.Destroying, function() state:Cleanup() end)
	function state:Hide(part)
		part.Transparency = 1
		for _, descendant in ipairs(part:GetDescendants()) do
			if descendant:IsA("Texture") or descendant:IsA("Decal") then descendant.Transparency = 1 end
		end
	end
	function state:Prop(name)
		local model = assert(kit.Components:FindFirstChild(name), "Missing Blender prop " .. name):Clone()
		model.PrimaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		return model
	end
	function state:Rooms(wallV, wallH, grid, cell, origin, pitCells, elevatorX, elevatorZ)
		local folder = Instance.new("Folder")
		folder.Name = "BlenderRooms"
		folder.Parent = maze
		local scale = cell / 24
		for x = 1, grid do
			for z = 1, grid do
				local mask = Renderer.OpenMask(wallV, wallH, grid, x, z)
				local choices = roomsByMask[mask] or roomsByMask[15] -- only the elevator cell may have no open sockets
				assert(choices and #choices > 0, "Missing Blender room socket mask")
				local room = Renderer.PickRoom(choices, math.random()):Clone()
				local base = CFrame.new(origin + (x - .5) * cell, 0, origin + (z - .5) * cell)
				local pivot = room:GetPivot()
				for _, part in ipairs(room:GetDescendants()) do
					if part:IsA("BasePart") then
						local localFrame = pivot:ToObjectSpace(part.CFrame)
						local pos = localFrame.Position
						part.CFrame = base * CFrame.new(pos.X * scale, pos.Y, pos.Z * scale) * localFrame.Rotation
						part.Size = Vector3.new(part.Size.X * scale, part.Size.Y, part.Size.Z * scale)
						part.Anchored = true
						local collider = part:GetAttribute("RoomRole") == "Collider" or (part.Parent and part.Parent.Name == "Colliders")
						part.CanCollide, part.CanQuery, part.CanTouch = collider, false, false
						if collider then part.CollisionGroup = "Decor" end
						local role = part:GetAttribute("RoomRole")
						local ancestor = part.Parent
						while not role and ancestor and ancestor ~= room do
							if ancestor:IsA("Folder") and ancestor.Name ~= "Colliders" then role = ancestor.Name end
							ancestor = ancestor.Parent
						end
						if role == "Fixture" -- the live sparse fixtures own every lighting phase
							or (pitCells[x .. "," .. z] and role ~= "SurfaceCeiling" and role ~= "ShellWalls")
							or (x == elevatorX and z == elevatorZ and role ~= "SurfaceCeiling") then
							part.Transparency, part.CanCollide = 1, false
						end
					end
				end
				local tile = self.recessCells[x .. "," .. z]
				if tile then
					local slab
					for _, mesh in ipairs(room:GetDescendants()) do
						if mesh:IsA("MeshPart") and mesh:GetAttribute("BlenderMaterial") == "Ceiling" then
							assert(not slab, "Ambiguous ceiling slab"); slab = mesh
						end
					end
					assert(slab, "Fixture ceiling slab missing")
					for index, piece in ipairs(Renderer.CeilingPieces(slab.Size, tile)) do
						local clone = slab:Clone()
						clone.Name = "RecessCeiling" .. index
						clone.Size, clone.CFrame = piece[2], slab.CFrame * CFrame.new(piece[1])
						clone:SetAttribute("CeilingAperturePiece", true)
						clone.Parent = slab.Parent
					end
					slab.Transparency = 1
					slab:SetAttribute("CeilingApertureOriginal", true)
				end
				room.Name = ("Room_%02d_%02d"):format(x, z)
				room:SetAttribute("OpenMask", mask)
				room:SetAttribute("CellX", x); room:SetAttribute("CellZ", z)
				room:SetAttribute("PitCell", pitCells[x .. "," .. z] == true)
				room:SetAttribute("ElevatorCell", x == elevatorX and z == elevatorZ)
				room.Parent = folder
			end
			if x % 2 == 0 then task.wait() end
		end
		table.clear(self.recessCells)
		workspace:SetAttribute("Level1BlenderRoomCount", grid * grid)
	end
	-- Replace a complete fixed casing once, rather than stretching the same mesh
	-- over each primitive. The original Parts retain prompts/query/collision.
	function state:SkinGroup(model, componentName, names)
		if self.closed then return end
		local parts = {}
		for _, name in ipairs(names) do
			local part = model:FindFirstChild(name)
			if not part or not part:IsA("BasePart") then return end
			parts[#parts + 1] = part
		end
		if self.skinned[parts[1]] then return end
		local frame = parts[1].CFrame.Rotation
		local minimum, maximum = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in ipairs(parts) do
			for _, x in ipairs({-1, 1}) do for _, y in ipairs({-1, 1}) do for _, z in ipairs({-1, 1}) do
				local corner = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size * Vector3.new(x, y, z) * .5))
				minimum = Vector3.new(math.min(minimum.X, corner.X), math.min(minimum.Y, corner.Y), math.min(minimum.Z, corner.Z))
				maximum = Vector3.new(math.max(maximum.X, corner.X), math.max(maximum.Y, corner.Y), math.max(maximum.Z, corner.Z))
			end end end
		end
		local target = frame * CFrame.new((minimum + maximum) * .5)
		local visual = assert(kit.Components:FindFirstChild(componentName), componentName):Clone()
		visual.Name = "BlenderVisual"
		local box, size = visual:GetBoundingBox()
		local ratio = (maximum - minimum) / size
		for _, mesh in ipairs(visual:GetDescendants()) do
			if mesh:IsA("BasePart") then
				mesh.Anchored = true
				mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = false, false, false
				if mesh:IsA("MeshPart") then
					local localFrame = box:ToObjectSpace(mesh.CFrame)
					mesh.Size *= ratio
					mesh.CFrame = target * CFrame.new(localFrame.Position * ratio) * localFrame.Rotation
				end
			end
		end
		for _, part in ipairs(parts) do self.skinned[part] = true; self:Hide(part) end
		visual.Parent = model
	end
	-- Dynamic hardware keeps its authoritative Part, signals and prompts. Its
	-- Blender mesh follows the same frame; it never contributes a second collider.
	function state:Skin(part, componentName, dynamic, tint)
		if self.closed or self.skinned[part] or part.Transparency >= 1 then return end
		self.skinned[part] = true
		local visual = assert(kit.Components:FindFirstChild(componentName), componentName):Clone()
		if part.Shape == Enum.PartType.Ball and componentName == "MetalPanel" then
			local handle = kit.Components:FindFirstChild("LeverHandle")
			local knob = handle and handle:FindFirstChild("Red")
			if knob and knob:IsA("MeshPart") then
				visual:Destroy()
				visual = Instance.new("Model")
				knob:Clone().Parent = visual
			end
		end
		visual.Name = "BlenderVisual"
		local box, size = visual:GetBoundingBox()
		local ratio, attachmentOffset, fixture = Renderer.SkinLayout(componentName, part.Size, size)
		local styled = fixture or componentName ~= "MetalPanel" and table.find(HARDWARE_NAMES, componentName) ~= nil
		local pieces = {}
		for _, mesh in ipairs(visual:GetDescendants()) do
			if mesh:IsA("BasePart") then
				mesh.Anchored = true
				mesh.CanCollide, mesh.CanQuery, mesh.CanTouch = false, false, false
			end
			if mesh:IsA("MeshPart") then
				local frame = box:ToObjectSpace(mesh.CFrame)
				local offset = frame.Position * ratio
				mesh.Size *= ratio
				local appearance = mesh:FindFirstChildOfClass("SurfaceAppearance")
				if part.Name == "ObjectiveCable" and appearance then appearance:Destroy(); appearance = nil end
				pieces[#pieces + 1] = {mesh, CFrame.new(offset + attachmentOffset) * frame.Rotation,
					mesh.Color, mesh.Material, mesh.Transparency, appearance and appearance.Color or Color3.new(1, 1, 1)}
			end
		end
		local originalTransparency = part.Transparency
		local function updateFrame()
			for _, piece in ipairs(pieces) do piece[1].CFrame = part.CFrame * piece[2] end
		end
		local function updateColour()
			for _, piece in ipairs(pieces) do
				local mesh = piece[1]
				local materialName = mesh:GetAttribute("BlenderMaterial")
				local emitter = materialName == "Lamp" or materialName == "GreenGlass"
				if materialName == "GreenGlass" then mesh.Color, mesh.Material = part.Color, piece[4]
				elseif not styled or emitter then
					mesh.Color, mesh.Material = part.Color, part.Material
					if fixture and materialName == "Lamp" and part.Material == Enum.Material.Neon then mesh.Color = Color3.new(part.Color.R * .65, part.Color.G * .65, part.Color.B * .65) end
				else mesh.Color, mesh.Material = piece[3], piece[4] end
				if part.Name == "ObjectiveCable" then mesh.Color = Color3.new(part.Color.R * .5, part.Color.G * .5, part.Color.B * .5) end
				local appearance = mesh:FindFirstChildOfClass("SurfaceAppearance")
				if appearance and tint then
					appearance.Color = Color3.new(piece[6].R * math.clamp(part.Color.R / (197 / 255), 0, 1),
						piece[6].G * math.clamp(part.Color.G / (180 / 255), 0, 1), piece[6].B * math.clamp(part.Color.B / (116 / 255), 0, 1))
				elseif appearance and (not styled or emitter) and (dynamic or componentName == "MetalPanel") then appearance.Color = part.Color end
			end
		end
		updateFrame()
		updateColour() -- preserve circuit colours and hardware state from the first frame
		if dynamic then
			updateColour()
			connect(part:GetPropertyChangedSignal("Color"), updateColour)
			connect(part:GetPropertyChangedSignal("Material"), updateColour)
			for _, piece in ipairs(pieces) do
				local mesh = piece[1]
				mesh.Anchored, mesh.Massless = false, true
				local weld = Instance.new("WeldConstraint")
				weld.Part0, weld.Part1 = part, mesh
				weld.Parent = mesh
			end
		end
		for _, piece in ipairs(pieces) do
			piece[1].Transparency = styled and math.max(originalTransparency, piece[5]) or originalTransparency
		end
		self:Hide(part)
		visual.Parent = part
	end
	function state:Fixture(part, style)
		local cell, origin = workspace:GetAttribute("CELL"), workspace:GetAttribute("ORIGIN")
		local x = math.floor((part.Position.X - origin) / cell) + 1
		local z = math.floor((part.Position.Z - origin) / cell) + 1
		local tile = 4 * cell / 24
		self.recessCells[x .. "," .. z] = tile
		part.CFrame += Vector3.new(tile * .5, 0, tile * .5)
		part.Size = Vector3.new(tile - .08 * cell / 24, part.Size.Y, tile - .08 * cell / 24)
		self:Skin(part, style, true)
	end
	function state:ExitAperture(owner,frame)
		local width,bottom,top=7,-frame.Position.Y,7.5
		local grid,cell,origin=workspace:GetAttribute("GRID"),workspace:GetAttribute("CELL"),workspace:GetAttribute("ORIGIN")
		local rooms=assert(maze:FindFirstChild("BlenderRooms"),"Preview exit rooms are missing")
		local x=math.clamp(math.floor((frame.Position.X-origin)/cell)+1,1,grid)
		local z=math.clamp(math.floor((frame.Position.Z-origin)/cell)+1,1,grid)
		local room=assert(rooms:FindFirstChild(("Room_%02d_%02d"):format(x,z)),"Preview exit boundary room is missing")
		local walls=assert(room:FindFirstChild("ShellWalls"),"Preview exit shell is missing")
		local native,art
		for _, part in ipairs(maze:GetChildren()) do
			if part.ClassName=="Part" and part.CanCollide and part.CanQuery
				and math.max(part.Size.X,part.Size.Z)>=grid*cell then
				local bounds=Renderer.ExitBounds(frame,part.CFrame,part.Size)
				local pieces=Renderer.ExitPieces(bounds,width,bottom,top)
				if pieces then assert(not native,"Ambiguous preview exit query wall");native={part=part,pieces=pieces} end
			end
		end
		for _, wall in ipairs(walls:GetChildren()) do
			if wall:IsA("Model") then
				local cf,size=wall:GetBoundingBox()
				local bounds=Renderer.ExitBounds(frame,cf,size)
				local pieces=Renderer.ExitPieces(bounds,width,bottom,top)
				if pieces then assert(not art,"Ambiguous preview exit shell");art={model=wall,bounds=bounds,pieces=pieces} end
			end
		end
		assert(native and art,"Preview exit is not backed by the outer boundary shell")
		local template
		for _, candidate in ipairs(roomsByMask[4] or {}) do if candidate:GetAttribute("Variant")==0 then template=candidate;break end end
		assert(template,"Preview exit quiet vestibule template is missing")
		local physics=Instance.new("Folder");physics.Name="ExitAperturePhysics"
		local originalCollision=native.part.CanCollide
		local visuals,hidden={},{}
		local vestibule,restored
		local function restoreAperture()
			if restored then return end
			restored=true;self.apertureCleanups[owner]=nil
			if native.part.Parent then native.part.CanCollide=originalCollision;native.part:SetAttribute("Level1ExitQueryWall",nil) end
			for part, transparency in pairs(hidden) do if part.Parent then part.Transparency=transparency end end
			if art.model.Parent then art.model:SetAttribute("ExitApertureOriginal",nil) end
			for _, visual in ipairs(visuals) do visual:Destroy() end
			physics:Destroy()
			if vestibule then vestibule:Destroy() end
			if owner.Parent then owner:SetAttribute("ExitApertureReady",nil);owner:SetAttribute("ExitApertureFrame",nil) end
		end
		self.apertureCleanups[owner]=restoreAperture
		connect(owner.Destroying,restoreAperture)
		for _, piece in ipairs(native.pieces) do
			local part=native.part:Clone()
			part.Name="ExitBoundary"..piece.name;part.Size=piece.size;part.CFrame=frame*CFrame.new(piece.center)
			part.CanQuery=false;part.CanTouch=false;part.CanCollide=true
			part:SetAttribute("ExitAperturePiece",piece.name);self.skinned[part]=true;part.Parent=physics
		end
		physics.Parent=owner -- complete matching side/header collision before opening the original
		native.part.CanCollide=false
		native.part:SetAttribute("Level1ExitQueryWall",true)
		local oldSize=Vector3.new(art.bounds.maxX-art.bounds.minX,art.bounds.maxY-art.bounds.minY,art.bounds.maxZ-art.bounds.minZ)
		local oldCenter=Vector3.new((art.bounds.minX+art.bounds.maxX)*.5,(art.bounds.minY+art.bounds.maxY)*.5,(art.bounds.minZ+art.bounds.maxZ)*.5)
		for _, piece in ipairs(art.pieces) do
			local clone=art.model:Clone();clone.Name="ExitShell"..piece.name;clone:SetAttribute("ExitAperturePiece",piece.name)
			local ratio=Vector3.new(piece.size.X/oldSize.X,piece.size.Y/oldSize.Y,piece.size.Z/oldSize.Z)
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					local localCF=frame:ToObjectSpace(part.CFrame)
					local right,up,back=localCF.RightVector,localCF.UpVector,localCF.ZVector
					local function scaleAxis(axis) return math.abs(axis.X)*ratio.X+math.abs(axis.Y)*ratio.Y+math.abs(axis.Z)*ratio.Z end
					part.Size=Vector3.new(part.Size.X*scaleAxis(right),part.Size.Y*scaleAxis(up),part.Size.Z*scaleAxis(back))
					part.CFrame=frame*CFrame.new(piece.center+(localCF.Position-oldCenter)*ratio)*localCF.Rotation
					part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
					part:SetAttribute("ExitAperturePiece",piece.name)
				end
			end
			clone.Parent=walls;visuals[#visuals+1]=clone
		end
		for _, part in ipairs(art.model:GetDescendants()) do
			if part:IsA("BasePart") then hidden[part]=part.Transparency;part.Transparency=1 end
		end
		art.model:SetAttribute("ExitApertureOriginal",true)
		vestibule=template:Clone();vestibule.Name="ExitVestibule";vestibule:SetAttribute("ExitVestibule",true)
		local scale=8/24
		local base=frame*CFrame.new(0,-frame.Position.Y,4.1)
		local pivot=vestibule:GetPivot()
		for _, part in ipairs(vestibule:GetDescendants()) do
			if part:IsA("BasePart") then
				local localCF=pivot:ToObjectSpace(part.CFrame);local pos=localCF.Position
				part.CFrame=base*CFrame.new(pos.X*scale,pos.Y,pos.Z*scale)*localCF.Rotation
				if part:GetAttribute("RoomRole")~="Fixture" then part.Size=Vector3.new(part.Size.X*scale,part.Size.Y,part.Size.Z*scale) end
				part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
				if part:GetAttribute("BlenderMaterial")=="Lamp" then
					local light=Instance.new("SurfaceLight");light.Face=Enum.NormalId.Bottom;light.Brightness=.35;light.Range=18;light.Shadows=false;light.Parent=part
				end
			end
		end
		local function collider(name,size,offset)
			local part=Instance.new("Part");part.Name=name;part.Anchored=true;part.Transparency=1
			part.Size=size;part.CFrame=base*CFrame.new(offset);part.CanCollide=true;part.CanQuery=false;part.CanTouch=false
			part:SetAttribute("ExitVestibulePhysics",true);self.skinned[part]=true;part.Parent=vestibule
		end
		collider("Floor",Vector3.new(8,.32,8),Vector3.new(0,-.16,0))
		collider("Ceiling",Vector3.new(8,.36,8),Vector3.new(0,14.18,0))
		collider("Back",Vector3.new(8,14,scale),Vector3.new(0,7,11.5*scale))
		collider("Left",Vector3.new(scale,14,8),Vector3.new(-11.5*scale,7,0))
		collider("Right",Vector3.new(scale,14,8),Vector3.new(11.5*scale,7,0))
		vestibule.Parent=owner
		owner:SetAttribute("ExitApertureFrame",frame)
		owner:SetAttribute("ExitApertureReady",true)
	end
	function state:Watch(root, selector)
		local function added(part)
			if part.ClassName ~= "Part" then return end
			task.defer(function()
				if self.closed or not part:IsDescendantOf(root) or part:FindFirstAncestor("BlenderVisual") then return end
				local name, dynamic = selector(part)
				if name then self:Skin(part, name, dynamic) end
			end)
		end
		connect(root.DescendantAdded, added)
		for _, part in ipairs(root:GetDescendants()) do added(part) end
	end
	function state:WatchPuzzle(folder)
		self:Watch(folder, function(part)
			if part.Name == "ObjectiveCable" then return "MetalPanel", false end
			local model = part.Parent
			if model and model:IsA("Model") then
				if model.Name == "Exit" and (part.Name == "CenterSeam" or part.Name == "Reinforcement" or part.Name == "EnergyNode") then
					self.skinned[part] = true; self:Hide(part); return nil
				end
				if model.Name:match("^FuseRelay") then self:SkinGroup(model, "RelayShell", {"RelayBody", "OuterFrame", "InnerPanel"})
				elseif model.Name:match("^FuseBox") then self:SkinGroup(model, "FuseBoxShell", {"Body", "OuterRim"})
				elseif model.Name:match("^Lever") then self:SkinGroup(model, "LeverShell", {"Plate", "Rim"})
				elseif model.Name == "Exit" then self:SkinGroup(model, "ExitPortal", {"PostL", "PostR", "Top"}) end
			end
			if self.skinned[part] then return nil end
			local dynamic = part.Material == Enum.Material.Neon or part.Name == "RelayDoor"
				or part.Name == "ReleaseHandle" or part.Name == "Handle" or part.Name == "Knob"
				or part.Name == "Fuse" or part.Name == "FuseCap" or part.Name:sub(1, 13) == "InstalledFuse"
			local preferred = part.Name == "RelayDoor" and "RelayDoor"
				or part.Name == "Handle" and "LeverShaft"
				or part.Name == "Knob" and "LeverKnob"
				or (part.Name == "FuseCap" or part.Name == "Cap") and "FuseCap"
				or part.Name:sub(1, 8) == "FuseSlot" and "FuseSocket"
				or (part.Name == "Fuse" or part.Name:sub(1, 13) == "InstalledFuse") and "FuseCore"
				or (model and model.Name == "Exit" and part.Name == "Sign") and "ExitDoor"
			return preferred and kit.Components:FindFirstChild(preferred) and preferred or "MetalPanel", dynamic
		end)
	end
	connect(workspace.ChildAdded, function(child)
		if child.Name == "PuzzleItems" then state:WatchPuzzle(child) end
	end)
	local puzzle = workspace:FindFirstChild("PuzzleItems")
	if puzzle then state:WatchPuzzle(puzzle) end
	return state
end

return Renderer
