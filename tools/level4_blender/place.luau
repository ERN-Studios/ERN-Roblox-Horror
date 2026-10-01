-- Builds Workspace."Level 4 Cinema Blender" from the uploaded Blender meshes (export_l4.py / make_place.py).
-- Runs as a background task in the plugin VM (Studio Edit); progress in shared.__l4place.
-- The Studio layout is reproduced 6000 studs east of the original preview, which is left untouched:
--   World     pooled architecture MeshParts (visual only, no collision)
--   Props     one Model per prop (seats, cabinets, tables ...), with its own colliders (propColliders)
--   Doors     one Model per door: anchored hinge + unanchored collider leaf + welded visual meshes
--   Collision invisible parts: the layout's collidable parts (minus replaced props the new colliders cover),
--             the new geometry's colliders, Seats, and non-colliding tagged markers (Level4V4Doorway)
--   Signage   invisible carriers holding the original posters' Decals and signs' SurfaceGuis
--   Lights    the exported fixture lights on invisible holders (or inside their prop's Neon lens part), plus
--             the original preview lights the manifest lists as surviving (legacyLights), cloned exactly;
--             a manifest without either clones every original light as before
--   Fixtures / Level4V4Exit  cloned from the original preview
--   OccasionalFixtureFlicker  a client-side (RunContext Client) flicker for every BasePart with a truthy
--             OccasionalFlicker attribute: flicker lenses, flicker holders and the cloned original fixtures
-- The model carries BoundsCenter / BoundsSize (Vector3) for client zone checks (Level 4 Lighting Controller).
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local BASE = "http://127.0.0.1:8765"
local NAME = "Level 4 Cinema Blender"
local OLD_NAME = "Level 4 Cinema Preview"
local SHIFT = Vector3.new(6000, 0, 0)                 -- new model = original layout + SHIFT
local ORIGIN = Vector3.new(23000, 0, 0) + SHIFT       -- Blender origin in Studio space
local PUSH_DOOR_SOURCE = __PUSH_DOOR_SOURCE__
local FLICKER_SOURCE = [==[
-- Level 4 cinema (Blender build): flickering fixtures. Runs on every client (RunContext Client): a blink costs no
-- replication, and parts that stream in join. Any BasePart in this model with a truthy OccasionalFlicker attribute
-- is a fixture: every few seconds its lights stutter off in a short burst and its lens, if visible, goes dark.
-- Written by tools/level4_blender/place.luau.
local model = script.Parent
local running = {}

local function burst(part, rng)
	local lights = {}
	for _, l in part:GetChildren() do
		if l:IsA("Light") then table.insert(lights, { l, l.Enabled }) end
	end
	local visible = part.Transparency < 1
	local material, color = part.Material, part.Color
	for _ = 1, rng:NextInteger(1, 5) do
		for _, e in lights do e[1].Enabled = false end
		if visible then
			part.Material = Enum.Material.SmoothPlastic
			part.Color = color:Lerp(Color3.new(0, 0, 0), 0.8)
		end
		task.wait(rng:NextNumber(0.04, 0.16))
		for _, e in lights do e[1].Enabled = e[2] end
		if visible then part.Material, part.Color = material, color end
		task.wait(rng:NextNumber(0.03, 0.3))
	end
end

local function watch(part)
	if not (part:IsA("BasePart") and part:GetAttribute("OccasionalFlicker")) then return end
	local token = {}
	running[part] = token
	task.spawn(function()
		local rng = Random.new()
		-- a quarter of the fixtures are dying (a stutter every 1-4 s), the rest act up every 5-18 s
		local dying = rng:NextNumber() < 0.25
		local lo, hi = if dying then 1 else 5, if dying then 4 else 18
		task.wait(rng:NextNumber(0, hi))
		while running[part] == token and part:IsDescendantOf(model) do
			burst(part, rng)
			task.wait(rng:NextNumber(lo, hi))
		end
	end)
end

for _, d in model:GetDescendants() do watch(d) end
model.DescendantAdded:Connect(watch)
model.DescendantRemoving:Connect(function(d) running[d] = nil end)
]==]

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

local function enumItem(enum, name, default)
	local ok, item = pcall(function() return enum[name] end)
	return if ok and item then item else default
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
	part.Material = enumItem(Enum.Material, st.m, Enum.Material.SmoothPlastic)
	part.Color = Color3.new(st.c[1], st.c[2], st.c[3])
	part.Transparency = st.t
	local sa = st.sa
	if type(sa) == "string" then sa = { c = sa, tint = st.tint } end     -- placement files from before PBR
	-- a SurfaceAppearance replaces the material's look, so Neon and Glass never get one
	if sa and part.Material ~= Enum.Material.Neon and part.Material ~= Enum.Material.Glass then
		local s = Instance.new("SurfaceAppearance")
		if sa.c then s.ColorMap = sa.c end
		if sa.n then s.NormalMap = sa.n end
		if sa.r then s.RoughnessMap = sa.r end
		if sa.m then s.MetalnessMap = sa.m end
		if sa.tint then s.Color = Color3.new(sa.tint[1], sa.tint[2], sa.tint[3]) end
		if sa.alpha then s.AlphaMode = enumItem(Enum.AlphaMode, sa.alpha, Enum.AlphaMode.Overlay) end
		s.Parent = part
	end
	part.CastShadow = part.Material ~= Enum.Material.Neon and part.Material ~= Enum.Material.Glass
		and not (sa and sa.alpha)
end

local function invisible(part)
	part.Transparency = 1
	part.CastShadow = false
	part.Anchored = true
	part.CanTouch = false
end

-- c = {cf12 (layout frame), size, shape, material, tags, kind, attributes?}; kind: "Part" | "Seat" | "Marker"
local function makeCollider(c, parent)
	local cfT, size, shape, mat, tags, kind, attrs = c[1], c[2], c[3], c[4], c[5], c[6] or "Part", c[7]
	local part
	if kind == "Seat" then
		part = Instance.new("Seat")
	elseif shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
	end
	if part:IsA("Part") then part.Shape = enumItem(Enum.PartType, shape, Enum.PartType.Block) end
	part.Name = if kind == "Part" then "Collider" else kind
	part.Size = vec(size)
	part.CFrame = cf12(cfT, SHIFT)
	invisible(part)
	part.CanCollide = kind ~= "Marker"
	part.CanQuery = kind ~= "Marker"
	part.CanTouch = kind == "Seat"                    -- a Seat seats whoever touches it
	part.Material = enumItem(Enum.Material, mat, Enum.Material.SmoothPlastic)
	for _, tag in ipairs(tags or {}) do CS:AddTag(part, tag) end
	if type(attrs) == "table" then
		for k, v in pairs(attrs) do part:SetAttribute(k, v) end
	end
	part.Parent = parent
	return part
end

-- the face of `part` whose outward normal is closest to a world direction
local FACES = {
	{ Enum.NormalId.Right, Vector3.xAxis }, { Enum.NormalId.Left, -Vector3.xAxis },
	{ Enum.NormalId.Top, Vector3.yAxis }, { Enum.NormalId.Bottom, -Vector3.yAxis },
	{ Enum.NormalId.Back, Vector3.zAxis }, { Enum.NormalId.Front, -Vector3.zAxis },
}
local function faceToward(part, dir)
	local d = part.CFrame:VectorToObjectSpace(dir)
	local best, bestDot = Enum.NormalId.Bottom, -math.huge
	for _, f in FACES do
		if d:Dot(f[2]) > bestDot then best, bestDot = f[1], d:Dot(f[2]) end
	end
	return best
end

-- l = {type, pos, rot, color, range, brightness, shadows, angle?, size?, prop?, name}; shines along -Y of rot
local function makeLight(l, folder, placed)
	local cf = cf12({ l.pos[1], l.pos[2], l.pos[3], table.unpack(l.rot) }, SHIFT)
	local light = Instance.new(l.type)
	light.Color = Color3.new(l.color[1], l.color[2], l.color[3])
	light.Range = l.range
	light.Brightness = l.brightness
	light.Shadows = l.shadows == true
	if l.angle and not light:IsA("PointLight") then light.Angle = l.angle end
	local model = l.prop and placed[l.prop]
	local host
	if model then                                  -- inside the prop's lens, so OccasionalFixtureFlicker dims both
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then host = d; break end
		end
	end
	if host then
		if not light:IsA("PointLight") then light.Face = faceToward(host, -cf.UpVector) end
	else
		host = Instance.new("Part")
		host.Name = l.name or l.type
		host.Size = if l.size then vec(l.size) else Vector3.new(0.2, 0.2, 0.2)
		host.CFrame = cf
		invisible(host)
		host.CanCollide = false
		host.CanQuery = false
		if not light:IsA("PointLight") then light.Face = Enum.NormalId.Bottom end
		if l.flicker then host:SetAttribute("OccasionalFlicker", true) end
		host.Parent = model or folder
	end
	light.Parent = host
end

-- an original light on an invisible holder with its parent's frame and size
local function cloneLight(l, folder)
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
	holder.Parent = folder
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
	model:SetAttribute("Level4Revision", 9)
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
	local placed = {}                                  -- placement index -> prop Model (lights, prop colliders)
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
		local flicker = m:GetAttribute("OccasionalFlicker")
		for _, t in ipairs(byGroup[group]) do
			local part = t.part:Clone()
			part.Size = t.size * scale
			part.CFrame = cf * CFrame.new(t.center * scale)
			if flicker and part.Material == Enum.Material.Neon then part:SetAttribute("OccasionalFlicker", flicker) end
			part.Parent = m
			table.insert(meshes, part)
		end
		if type(door) == "table" then
			doorCount += 1
			local leafCf = cf12(door.leafCf, SHIFT)
			local leafSize = vec(door.leafSize)
			-- hinge axis: exported hinge point, else the leaf asset's origin
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
				local src = original(door.decalFrom, door.decalOrig or door.leafCf)
				if src then
					for _, d in ipairs(src:GetChildren()) do
						if d:IsA("Decal") or d:IsA("SurfaceGui") then d:Clone().Parent = leaf end
					end
					m:SetAttribute("ConcealedEntrance", true)
				end
			end
			pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)   -- hinge + leaf arrive together
			m.PrimaryPart = leaf
			m.Parent = doors
		else
			m.PrimaryPart = meshes[1]
			m.Parent = props
			placed[pi] = m
		end
		if pi % 150 == 0 then
			shared.__l4place = "placements " .. pi .. "/" .. #data.placements
			task.wait()
		end
	end

	-- colliders of the props go into their Models
	for _, c in ipairs(data.propColliders or {}) do
		local m = placed[c[1]]
		if m then makeCollider({ c[2], c[3], c[4], c[5], c[6], c[7] }, m) end
	end

	-- invisible collision
	for ci, c in ipairs(data.colliders) do
		makeCollider(c, collision)
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

	-- flicker fixtures (the original parts, with their lights)
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
	local lightCount, legacyCount, legacyMissing = 0, 0, 0
	for li, l in ipairs(data.lights or {}) do
		makeLight(l, lights, placed)
		lightCount += 1
		if li % 100 == 0 then task.wait() end
	end
	if data.legacyLights then
		-- the original lights whose fixtures survived the facelift, by light path + original host position
		local originalLights = {}
		for _, l in ipairs(old:GetDescendants()) do
			if l:IsA("Light") and l.Parent:IsA("BasePart") then
				originalLights[key(pathOf(l, old), l.Parent.Position)] = l
			end
		end
		for _, e in ipairs(data.legacyLights) do
			local l = originalLights[key(e[1], vec(e[2]))]
			if l then
				cloneLight(l, lights)
				legacyCount += 1
			else
				legacyMissing += 1
			end
		end
	elseif lightCount == 0 then
		-- a manifest from before exported lights: every original light
		for _, l in ipairs(old:GetDescendants()) do
			if l:IsA("Light") and not flickerSet[l.Parent] then
				cloneLight(l, lights)
				legacyCount += 1
			end
		end
	end

	-- fixture flicker on every client (no replication; streaming-aware), replacing the original server script
	local flickerScript = Instance.new("Script")
	flickerScript.Name = "OccasionalFixtureFlicker"
	flickerScript.RunContext = Enum.RunContext.Client
	flickerScript.Parent = model
	local okFlicker = pcall(function()
		game:GetService("ScriptEditorService"):UpdateSourceAsync(flickerScript, function() return FLICKER_SOURCE end)
	end)
	if not okFlicker then flickerScript.Source = FLICKER_SOURCE end

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

	-- stored bounds: a client cannot measure a partly streamed model
	local boundsCf, boundsSize = model:GetBoundingBox()
	model:SetAttribute("BoundsCenter", boundsCf.Position)
	model:SetAttribute("BoundsSize", boundsSize)
	model:SetAttribute("PartCount", #model:GetDescendants())
	model.Parent = workspace
	model:SetAttribute("Level4PreviewReady", true)
	shared.__l4place = string.format("done world=%d props=%d doors=%d colliders=%d propColliders=%d signage=%d(missing %d) lights=%d legacyLights=%d(missing %d) fixtures=%d",
		#world:GetChildren(), #props:GetChildren(), doorCount, #collision:GetChildren(), #(data.propColliders or {}),
		#signage:GetChildren(), missing, lightCount, legacyCount, legacyMissing, #fixtures:GetChildren())
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then shared.__l4place = "FAILED: " .. tostring(err) end
end)
return "started"
