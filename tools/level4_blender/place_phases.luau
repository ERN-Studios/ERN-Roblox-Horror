
-- ===== sandbox phases (2026-10-02): Studio's MCP execute_luau thread has no Network capability, no shared/_G
-- between calls, and may not create Scripts under Workspace. So: the placement packet and asset map are staged
-- as StringValues in ServerStorage.L4PlaceStaging, the build runs in three synchronous phases that keep state in
-- instances, and the model's existing OccasionalFixtureFlicker and Doors.PushDoors scripts are kept and updated
-- through ScriptEditorService instead of being recreated.
local PHASE = "__PHASE__"
local SS = game:GetService("ServerStorage")
local STAGE = SS:WaitForChild("L4PlaceStaging")

local function staged(prefix)
	local parts = {}
	for _, v in ipairs(STAGE:GetChildren()) do
		if v:IsA("StringValue") and v.Name:sub(1, #prefix) == prefix then table.insert(parts, v) end
	end
	table.sort(parts, function(a, b) return a.Name < b.Name end)
	local buf = table.create(#parts)
	for i, v in ipairs(parts) do buf[i] = v.Value end
	return HS:JSONDecode(table.concat(buf))
end

local data, assets = staged("P"), staged("A")
local old = workspace:FindFirstChild(OLD_NAME)
assert(old, "original preview missing")
local model = workspace:FindFirstChild(NAME)
assert(model, "existing model missing (scripts must be reused)")

local byKey = {}
local function key(path, pos)
	return string.format("%s@%.2f,%.2f,%.2f", path, pos.X, pos.Y, pos.Z)
end
local function original(path, orig)
	if next(byKey) == nil then
		for _, d in ipairs(old:GetDescendants()) do
			if d:IsA("BasePart") then byKey[key(pathOf(d, old), d.Position)] = d end
		end
	end
	return byKey[key(path, Vector3.new(orig[1], orig[2], orig[3]))]
end

local function child(n)
	local f = model:FindFirstChild(n)
	if not f then f = Instance.new("Folder"); f.Name = n; f.Parent = model end
	return f
end

if PHASE == "templates" then
	for _, c in ipairs(data.chunks) do
		assert(assets[tostring(c[1])], "chunk " .. c[1] .. " has no uploaded asset")
	end
	-- clear everything except the two scripts we must keep
	local doorsFolder = model:FindFirstChild("Doors")
	for _, ch in ipairs(model:GetChildren()) do
		if ch ~= doorsFolder and not ch:IsA("BaseScript") then ch:Destroy() end
	end
	if doorsFolder then
		for _, ch in ipairs(doorsFolder:GetChildren()) do
			if not ch:IsA("BaseScript") then ch:Destroy() end
		end
	end
	local world = child("World")
	local tf = STAGE:FindFirstChild("Templates")
	if tf then tf:Destroy() end
	tf = Instance.new("Folder"); tf.Name = "Templates"; tf.Parent = STAGE
	for i, c in ipairs(data.chunks) do
		local id, group, matName, size, chunkTags = c[1], c[2], c[3], c[4], c[6]
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
		for _, tag in ipairs(st.tags or {}) do CS:AddTag(part, tag) end
		for _, tag in ipairs(chunkTags or {}) do CS:AddTag(part, tag) end
		if group >= 0 then
			part:SetAttribute("L4T", i)
			part:SetAttribute("L4Group", group)
			part:SetAttribute("L4Size", vec(size))
			part:SetAttribute("L4Center", vec(c[5]))
			part.Parent = tf
		else
			part.Size = vec(size)
			part.CFrame = CFrame.new(ORIGIN + vec(c[5]))
			part.Parent = world
		end
		if i % 25 == 0 then task.wait() end
	end
	return string.format("templates done: world=%d templates=%d", #world:GetChildren(), #tf:GetChildren())

elseif PHASE == "placements" then
	local tf = STAGE:FindFirstChild("Templates")
	assert(tf, "run the templates phase first")
	local list = tf:GetChildren()
	table.sort(list, function(a, b) return a:GetAttribute("L4T") < b:GetAttribute("L4T") end)
	local byGroup = {}
	for _, part in ipairs(list) do
		local g = part:GetAttribute("L4Group")
		byGroup[g] = byGroup[g] or {}
		table.insert(byGroup[g], {part = part, size = part:GetAttribute("L4Size"), center = part:GetAttribute("L4Center")})
	end
	local props, doors = child("Props"), child("Doors")
	local doorCount, propCount = 0, 0
	local decorativeFolders = {}
	for pi, p in ipairs(data.placements) do
		local group, pos, r, s, modelName, objName, attrs, door = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]
		local cf = CFrame.new(ORIGIN.X + pos[1], ORIGIN.Y + pos[2], ORIGIN.Z + pos[3],
			r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		local scale = vec(s)
		local bare, propTags = p[9] == true, p[10]
		local decorativeAsset = p[11] or modelName
		local m
		if bare then
			assert(not door and (not attrs or next(attrs) == nil) and #byGroup[group] == 1, "invalid decorative placement")
			m = decorativeFolders[decorativeAsset]
			if not m then
				m = Instance.new("Folder")
				m.Name = decorativeAsset
				m.Parent = props
				decorativeFolders[decorativeAsset] = m
			end
		else
			m = Instance.new("Model")
			m.Name = modelName
		end
		if not bare and type(attrs) == "table" then
			for k, v in pairs(attrs) do m:SetAttribute(k, v) end
		end
		local meshes = {}
		for _, t in ipairs(byGroup[group]) do
			local part = t.part:Clone()
			part:SetAttribute("L4T", nil); part:SetAttribute("L4Group", nil)
			part:SetAttribute("L4Size", nil); part:SetAttribute("L4Center", nil)
			part.Size = t.size * scale
			part.CFrame = cf * CFrame.new(t.center * scale)
			if bare then part.Name = objName end
			for _, tag in ipairs(propTags or {}) do CS:AddTag(part, tag) end
			part.Parent = m
			table.insert(meshes, part)
		end
		if type(door) == "table" then
			doorCount += 1
			local leafCf = cf12(door.leafCf, SHIFT)
			local leafSize = vec(door.leafSize)
			local hingePos = if door.hingePos then vec(door.hingePos) + SHIFT else cf.Position
			local anchor = Instance.new("Part")
			anchor.Name = "Hinge"
			anchor.Size = Vector3.new(0.4, leafSize.Y, 0.4)
			anchor.CFrame = CFrame.new(hingePos.X, leafCf.Position.Y, hingePos.Z)
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
			leaf.Anchored = true                     -- anchored while building inside the live Workspace; unanchored at the end
			leaf.CanCollide = true
			leaf.CanTouch = false
			leaf.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0, 1, 1)
			leaf:SetAttribute("L4UnanchorAtEnd", true)
			leaf.Parent = m
			for _, part in ipairs(meshes) do
				part.Anchored = false
				part.Massless = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = leaf; w.Part1 = part; w.Parent = part
			end
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
				local src = original(door.decalFrom, door.decalOrig or door.leafCf)
				if src then
					for _, d in ipairs(src:GetChildren()) do
						if d:IsA("Decal") or d:IsA("SurfaceGui") then d:Clone().Parent = leaf end
					end
					m:SetAttribute("ConcealedEntrance", true)
				end
			end
			pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
			m.PrimaryPart = leaf
			m.Parent = doors
		elseif not bare then
			m:SetAttribute("L4PI", pi)
			m.PrimaryPart = meshes[1]
			m.Parent = props
			propCount += 1
		end
		if pi % 150 == 0 then task.wait() end
	end
	return string.format("placements done: props=%d doors=%d", propCount, doorCount)

elseif PHASE == "rest" then
	local props, doors, collision = child("Props"), child("Doors"), child("Collision")
	local signage, lights = child("Signage"), child("Lights")
	local placed = {}
	for _, m in ipairs(props:GetChildren()) do
		local pi = m:GetAttribute("L4PI")
		if pi then placed[pi] = m end
	end
	for _, c in ipairs(data.propColliders or {}) do
		local m = placed[c[1]]
		if m then makeCollider({ c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9] }, m) end
	end
	for ci, c in ipairs(data.colliders) do
		makeCollider(c, collision)
		if ci % 400 == 0 then task.wait() end
	end
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
	local lightCount, legacyCount, legacyMissing = 0, 0, 0
	for li, l in ipairs(data.lights or {}) do
		makeLight(l, lights, placed)
		lightCount += 1
		if li % 100 == 0 then task.wait() end
	end
	local originalLights = {}
	for _, l in ipairs(old:GetDescendants()) do
		if l:IsA("Light") and l.Parent:IsA("BasePart") then
			originalLights[key(pathOf(l, old), l.Parent.Position)] = l
		end
	end
	for _, e in ipairs(data.legacyLights or {}) do
		local l = originalLights[key(e[1], vec(e[2]))]
		if l then cloneLight(l, lights); legacyCount += 1 else legacyMissing += 1 end
	end
	-- the two kept scripts get their v3 sources
	local SES = game:GetService("ScriptEditorService")
	local flicker = model:FindFirstChild("OccasionalFixtureFlicker")
	assert(flicker and flicker:IsA("Script"), "OccasionalFixtureFlicker script missing")
	SES:UpdateSourceAsync(flicker, function() return FLICKER_SOURCE end)
	local push = doors:FindFirstChild("PushDoors")
	assert(push and push:IsA("Script"), "Doors.PushDoors script missing")
	SES:UpdateSourceAsync(push, function() return PUSH_DOOR_SOURCE end)
	-- exit pad
	local exitSrc = old:FindFirstChild("Level4V4Exit", true)
	local exit = exitSrc:Clone()
	exit.CFrame = exitSrc.CFrame + SHIFT
	exit.Parent = model
	-- door leaves were anchored while building
	for _, d in ipairs(doors:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("L4UnanchorAtEnd") then
			d:SetAttribute("L4UnanchorAtEnd", nil)
			d.Anchored = false
		end
	end
	model:SetAttribute("Level4Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("Level4LayoutVersion", 4)
	model:SetAttribute("Level4Revision", 11)
	model:SetAttribute("Level4Source", "Blender")
	model:SetAttribute("SourceBlend", "G:/Blender/Level4_Cinema/Level4_Cinema.blend")
	model:SetAttribute("StudsPerMetre", 1 / 0.28)
	local boundsCf, boundsSize = model:GetBoundingBox()
	model:SetAttribute("BoundsCenter", boundsCf.Position)
	model:SetAttribute("BoundsSize", boundsSize)
	model:SetAttribute("PartCount", #model:GetDescendants())
	model:SetAttribute("Level4PreviewReady", true)
	local occluders = 0
	for _, part in ipairs(collision:GetChildren()) do
		if part.Name == "Occluder" then occluders += 1 end
	end
	STAGE:Destroy()
	return string.format("done world=%d props=%d doors=%d colliders=%d occluders=%d propColliders=%d signage=%d(missing %d) lights=%d legacyLights=%d(missing %d) descendants=%d",
		#child("World"):GetChildren(), #props:GetChildren(), #doors:GetChildren() - 1, #collision:GetChildren(), occluders,
		#(data.propColliders or {}), #signage:GetChildren(), missing, lightCount, legacyCount, legacyMissing, #model:GetDescendants())
end
error("unknown phase " .. PHASE)
