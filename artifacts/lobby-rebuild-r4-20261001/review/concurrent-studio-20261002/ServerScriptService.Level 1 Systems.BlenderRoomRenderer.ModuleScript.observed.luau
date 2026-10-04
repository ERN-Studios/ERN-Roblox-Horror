-- Blender art is a developer-preview skin over the live Level 1 query/collision grid.
local ServerStorage = game:GetService("ServerStorage")
local Renderer = {}
local PROP_NAMES = {"Chair", "Table", "Telephone", "CardboardPile", "Printer", "GrandfatherClock"}
local SURFACE_NAMES = {"FloorPanel", "WallHalf", "CeilingPanel", "LightFixture", "MetalPanel"}

function Renderer.IsReady()
	local kit = ServerStorage:FindFirstChild("Level1BlenderKit")
	local components = kit and kit:FindFirstChild("Components")
	local rooms = kit and kit:FindFirstChild("Rooms")
	if not kit or kit:GetAttribute("Ready") ~= true or not components or not rooms then
		return false, "PREVIEW_NOT_READY"
	end
	for _, names in ipairs({PROP_NAMES, SURFACE_NAMES}) do
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
	local kit = ServerStorage.Level1BlenderKit
	local state = {connections = {}, closed = false, skinned = {}}
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
		for _, connection in ipairs(self.connections) do connection:Disconnect() end
		table.clear(self.connections)
		table.clear(self.skinned)
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
				local room = choices[math.random(#choices)]:Clone()
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
				room.Name = ("Room_%02d_%02d"):format(x, z)
				room:SetAttribute("OpenMask", mask)
				room:SetAttribute("CellX", x); room:SetAttribute("CellZ", z)
				room:SetAttribute("PitCell", pitCells[x .. "," .. z] == true)
				room:SetAttribute("ElevatorCell", x == elevatorX and z == elevatorZ)
				room.Parent = folder
			end
			if x % 2 == 0 then task.wait() end
		end
		workspace:SetAttribute("Level1BlenderRoomCount", grid * grid)
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
		local ratio = Vector3.new(part.Size.X / size.X, part.Size.Y / size.Y, part.Size.Z / size.Z)
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
				pieces[#pieces + 1] = {mesh, CFrame.new(offset) * frame.Rotation}
			end
		end
		local originalTransparency = part.Transparency
		local function updateFrame()
			for _, piece in ipairs(pieces) do piece[1].CFrame = part.CFrame * piece[2] end
		end
		local function updateColour()
			for _, piece in ipairs(pieces) do
				local mesh = piece[1]
				mesh.Color, mesh.Material = part.Color, part.Material
				local appearance = mesh:FindFirstChildOfClass("SurfaceAppearance")
				if appearance and tint then
					appearance.Color = Color3.new(math.clamp(part.Color.R / (197 / 255), 0, 1),
						math.clamp(part.Color.G / (180 / 255), 0, 1), math.clamp(part.Color.B / (116 / 255), 0, 1))
				elseif appearance and (dynamic or componentName == "MetalPanel") then appearance.Color = part.Color end
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
		for _, piece in ipairs(pieces) do piece[1].Transparency = originalTransparency end
		self:Hide(part)
		visual.Parent = part
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
			local dynamic = part.Material == Enum.Material.Neon or part.Name == "RelayDoor"
				or part.Name == "ReleaseHandle" or part.Name == "Handle" or part.Name == "Knob"
				or part.Name == "Fuse" or part.Name == "FuseCap" or part.Name:sub(1, 13) == "InstalledFuse"
			local preferred = part.Name == "RelayDoor" and "RelayDoor"
				or part.Name == "Plate" and "LeverBase"
				or (part.Name == "Fuse" or part.Name:sub(1, 13) == "InstalledFuse") and "Fuse"
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
