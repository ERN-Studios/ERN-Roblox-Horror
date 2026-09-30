-- Builds Workspace."Level 4 Cinema Blender" from the uploaded Blender meshes (export_l4.py / make_place.py).
-- Runs as a background task in the plugin VM (Studio Edit); progress in shared.__l4place.
-- The Studio layout is reproduced 6000 studs east of the original preview, which is left untouched:
--   World     pooled architecture MeshParts (visual only, no collision)
--   Props     one Model per prop (seats, cabinets, tables, popcorn case, boxes ...)
--   Doors     one Model per door: anchored hinge + unanchored collider leaf + welded visual meshes
--   Collision invisible parts = every collidable part of the Studio layout (+ owner edits)
--   Signage   invisible carriers holding the original posters' Decals and signs' SurfaceGuis
--   Lights / Fixtures / Level4V4Exit  cloned from the original preview
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local BASE = "http://127.0.0.1:8765"
local NAME = "Level 4 Cinema Blender"
local OLD_NAME = "Level 4 Cinema Preview"
local SHIFT = Vector3.new(6000, 0, 0)                 -- new model = original layout + SHIFT
local ORIGIN = Vector3.new(23000, 0, 0) + SHIFT       -- Blender origin in Studio space
local PUSH_DOOR_SOURCE = __PUSH_DOOR_SOURCE__

local function fetch()
	local was = HS.HttpEnabled
	HS.HttpEnabled = true
	local ok, data, assets = pcall(function()
		return HS:JSONDecode(HS:GetAsync(BASE .. "/chunk/99999", true)),
			HS:JSONDecode(HS:GetAsync(BASE .. "/assets", true))
	end)
	HS.HttpEnabled = was
	assert(ok, data)
	return data, assets
end

local function vec(t) return Vector3.new(t[1], t[2], t[3]) end
local function cf12(t, shift)
	return CFrame.new(t[1] + shift.X, t[2] + shift.Y, t[3] + shift.Z, t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12])
end

local function pathOf(inst, root)
	local names = {}
	local c = inst
	while c and c ~= root do
		table.insert(names, 1, c.Name)
		c = c.Parent
	end
	return table.concat(names, "/")
end

local function styleMesh(part, st)
	part.Material = Enum.Material[st.m]
	part.Color = Color3.new(st.c[1], st.c[2], st.c[3])
	part.Transparency = st.t
	if st.sa then
		local sa = Instance.new("SurfaceAppearance")
		sa.ColorMap = st.sa
		sa.Color = Color3.new(st.tint[1], st.tint[2], st.tint[3])
		sa.Parent = part
	end
	part.CastShadow = st.m ~= "Neon" and st.m ~= "Glass"
end

local function invisible(part)
	part.Transparency = 1
	part.CastShadow = false
	part.Anchored = true
	part.CanTouch = false
end

local function run()
	local data, assets = fetch()
	local old = workspace:FindFirstChild(OLD_NAME)
	assert(old, "original preview missing")
	for _, c in ipairs(data.chunks) do
		assert(assets[tostring(c[1])], "chunk " .. c[1] .. " has no uploaded asset")
	end
	local prev = workspace:FindFirstChild(NAME)
	if prev then prev:Destroy() end

	-- index the original preview by path + position (paths repeat, positions do not)
	local byKey = {}
	local function key(path, pos)
		return string.format("%s@%.2f,%.2f,%.2f", path, pos.X, pos.Y, pos.Z)
	end
	for _, d in ipairs(old:GetDescendants()) do
		if d:IsA("BasePart") then byKey[key(pathOf(d, old), d.Position)] = d end
	end
	local function original(path, orig)
		return byKey[key(path, Vector3.new(orig[1], orig[2], orig[3]))]
	end

	local model = Instance.new("Model")
	model.Name = NAME
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("Level4LayoutVersion", 4)
	model:SetAttribute("Level4Revision", 8)
	model:SetAttribute("Level4PreviewReady", false)
	model:SetAttribute("Level4Source", "Blender")
	model:SetAttribute("SourceBlend", "G:/Blender/Level4_Cinema/Level4_Cinema.blend")
	model:SetAttribute("StudsPerMetre", 1 / 0.28)
	local function folder(n)
		local f = Instance.new("Folder"); f.Name = n; f.Parent = model; return f
	end
	local world, props, doors, collision = folder("World"), folder("Props"), folder("Doors"), folder("Collision")
	local signage, lights, fixtures = folder("Signage"), folder("Lights"), folder("Fixtures")

	-- one template per chunk
	local templates, byGroup = {}, {}
	for i, c in ipairs(data.chunks) do
		local id, group, matName, size = c[1], c[2], c[3], c[4]
		local st = data.styles[matName] or data.styles["None"]
		local part
		for _, f in ipairs({Enum.CollisionFidelity.Box, Enum.CollisionFidelity.Default}) do
			local ok, res = pcall(AS.CreateMeshPartAsync, AS, Content.fromUri("rbxassetid://" .. assets[tostring(id)]),
				{CollisionFidelity = f, RenderFidelity = Enum.RenderFidelity.Automatic})
			if ok then part = res; break end
		end
		assert(part, "chunk " .. id .. " could not be built")
		part.Name = matName
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		styleMesh(part, st)
		templates[i] = {part = part, size = vec(size), center = vec(c[5])}
		if group >= 0 then
			byGroup[group] = byGroup[group] or {}
			table.insert(byGroup[group], templates[i])
		else
			part.Size = vec(size)
			part.CFrame = CFrame.new(ORIGIN + vec(c[5]))
			part.Parent = world
		end
		if i % 20 == 0 then
			shared.__l4place = "templates " .. i .. "/" .. #data.chunks
			task.wait()
		end
	end

	-- props and doors
	local doorCount = 0
	for pi, p in ipairs(data.placements) do
		local group, pos, r, s, modelName, objName, attrs, door = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]
		local cf = CFrame.new(ORIGIN.X + pos[1], ORIGIN.Y + pos[2], ORIGIN.Z + pos[3],
			r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		local scale = vec(s)
		local m = Instance.new("Model")
		m.Name = modelName
		if type(attrs) == "table" then
			for k, v in pairs(attrs) do m:SetAttribute(k, v) end
		end
		local meshes = {}
		for _, t in ipairs(byGroup[group]) do
			local part = t.part:Clone()
			part.Size = t.size * scale
			part.CFrame = cf * CFrame.new(t.center * scale)
			part.Parent = m
			table.insert(meshes, part)
		end
		if type(door) == "table" then
			doorCount += 1
			local leafCf = cf12(door.leafCf, SHIFT)
			local leafSize = vec(door.leafSize)
			local hingeCf = cf                                   -- the leaf asset's origin is the hinge axis
			local anchor = Instance.new("Part")
			anchor.Name = "Hinge"
			anchor.Size = Vector3.new(0.4, leafSize.Y, 0.4)
			anchor.CFrame = hingeCf * CFrame.new(0, leafSize.Y / 2, 0)
			invisible(anchor)
			anchor.CanCollide = false
			anchor.CanQuery = false
			anchor.Parent = m
			local leaf = Instance.new("Part")
			leaf.Name = "Leaf"
			leaf.Size = leafSize
			leaf.CFrame = leafCf
			leaf.Transparency = 1
			leaf.CastShadow = false
			leaf.Anchored = false
			leaf.CanCollide = true
			leaf.CanTouch = false
			leaf.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0, 1, 1)
			leaf.Parent = m
			for _, part in ipairs(meshes) do
				part.Anchored = false
				part.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = leaf; w.Part1 = part; w.Parent = part
			end
			-- hinge axis = world up through the hinge; HingeConstraint turns about the attachments' X axis
			local axisCf = CFrame.fromMatrix(anchor.Position, Vector3.yAxis, Vector3.zAxis:Cross(Vector3.yAxis))
			local a0 = Instance.new("Attachment"); a0.Name = "HingeAttachment"; a0.Parent = anchor
			a0.WorldCFrame = axisCf
			local a1 = Instance.new("Attachment"); a1.Name = "LeafAttachment"; a1.Parent = leaf
			a1.WorldCFrame = axisCf
			local h = Instance.new("HingeConstraint")
			h.Attachment0 = a0; h.Attachment1 = a1
			h.ActuatorType = Enum.ActuatorType.Servo
			h.ServoMaxTorque = 2e5
			h.AngularSpeed = 3
			h.AngularResponsiveness = 45
			h.TargetAngle = 0
			h.LimitsEnabled = true
			h.UpperAngle = 110
			h.LowerAngle = -110
			h.Parent = anchor
			m:SetAttribute("DoorName", door.name)
			m:SetAttribute("DoorStyle", door.style)
			m:SetAttribute("OpenAngle", math.abs(door.openAngle))
			if door.fixedOpenAngle then m:SetAttribute("FixedOpenAngle", door.fixedOpenAngle) end
			if door.nonBlocking then m:SetAttribute("NonBlockingWhenOpen", true) end
			if door.decalFrom then
				local src = original(door.decalFrom, door.leafCf)
				if src then
					for _, d in ipairs(src:GetChildren()) do
						if d:IsA("Decal") or d:IsA("SurfaceGui") then d:Clone().Parent = leaf end
					end
					m:SetAttribute("ConcealedEntrance", true)
				end
			end
			m.PrimaryPart = leaf
			m.Parent = doors
		else
			m.PrimaryPart = meshes[1]
			m.Parent = props
		end
		if pi % 150 == 0 then
			shared.__l4place = "placements " .. pi .. "/" .. #data.placements
			task.wait()
		end
	end

	-- invisible collision = the Studio layout's collidable parts
	for ci, c in ipairs(data.colliders) do
		local cfT, size, shape, mat, tags = c[1], c[2], c[3], c[4], c[5]
		local part
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			part.Shape = Enum.PartType[shape] or Enum.PartType.Block
		end
		part.Name = "Collider"
		part.Size = vec(size)
		part.CFrame = cf12(cfT, SHIFT)
		invisible(part)
		part.CanCollide = true
		part.CanQuery = true
		pcall(function() part.Material = Enum.Material[mat] end)
		for _, tag in ipairs(tags) do CS:AddTag(part, tag) end
		part.Parent = collision
		if ci % 400 == 0 then
			shared.__l4place = "colliders " .. ci .. "/" .. #data.colliders
			task.wait()
		end
	end

	-- posters and signs: the original Decals / SurfaceGuis on invisible carriers 0.02 studs proud
	local missing = 0
	for _, c in ipairs(data.carriers) do
		local src = original(c[1], c[2])
		if src then
			local part = Instance.new("Part")
			part.Name = src.Name
			part.Size = vec(c[4]) + Vector3.new(0.04, 0.04, 0.04)
			part.CFrame = cf12(c[3], SHIFT)
			invisible(part)
			part.CanCollide = false
			part.CanQuery = false
			for _, d in ipairs(src:GetChildren()) do
				if d:IsA("Decal") or d:IsA("SurfaceGui") then d:Clone().Parent = part end
			end
			part.Parent = signage
		else
			missing += 1
		end
	end

	-- lights: every original light on an invisible holder with its parent's frame and size
	local flickerSet = {}
	for _, f in ipairs(data.fixtures) do
		local src = original(f[1], f[2])
		if src then
			flickerSet[src] = true
			local clone = src:Clone()
			clone.CFrame = src.CFrame + SHIFT
			clone.Parent = fixtures
		end
	end
	for _, l in ipairs(old:GetDescendants()) do
		if l:IsA("Light") and not flickerSet[l.Parent] then
			local host = l.Parent
			local holder = Instance.new("Part")
			holder.Name = host.Name .. "_Light"
			if host:IsA("BasePart") then
				holder.Size = host.Size
				holder.CFrame = host.CFrame + SHIFT
			elseif host:IsA("Attachment") then
				holder.Size = Vector3.one
				holder.CFrame = host.WorldCFrame + SHIFT
			end
			invisible(holder)
			holder.CanCollide = false
			holder.CanQuery = false
			l:Clone().Parent = holder
			holder.Parent = lights
		end
	end
	local flickerScript = old:FindFirstChild("OccasionalFixtureFlicker")
	if flickerScript then flickerScript:Clone().Parent = model end

	-- exit pad (the preview access script teleports onto it and hangs RETURN TO LOBBY on it)
	local exitSrc = old:FindFirstChild("Level4V4Exit", true)
	local exit = exitSrc:Clone()
	exit.CFrame = exitSrc.CFrame + SHIFT
	exit.Parent = model

	-- push doors
	local pushScript = Instance.new("Script")
	pushScript.Name = "PushDoors"
	pushScript.Parent = doors
	local ok = pcall(function()
		game:GetService("ScriptEditorService"):UpdateSourceAsync(pushScript, function() return PUSH_DOOR_SOURCE end)
	end)
	if not ok then pushScript.Source = PUSH_DOOR_SOURCE end

	model:SetAttribute("PartCount", #model:GetDescendants())
	model.Parent = workspace
	model:SetAttribute("Level4PreviewReady", true)
	shared.__l4place = string.format("done world=%d props=%d doors=%d colliders=%d signage=%d(missing %d) lights=%d fixtures=%d",
		#world:GetChildren(), #props:GetChildren(), doorCount, #collision:GetChildren(), #signage:GetChildren(),
		missing, #lights:GetChildren(), #fixtures:GetChildren())
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then shared.__l4place = "FAILED: " .. tostring(err) end
end)
return "started"
