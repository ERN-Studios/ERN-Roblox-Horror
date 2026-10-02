-- Builds Workspace."Level 4 Cinema Blender" from the uploaded Blender meshes (export_l4.py / make_place.py).
-- Runs as a background task in the plugin VM (Studio Edit); progress in shared.__l4place.
-- The Studio layout is reproduced 6000 studs east of the original preview, which is left untouched:
--   World     pooled architecture MeshParts (visual only, no collision); CollectionService tags from the material
--             (style tags) and from the chunk (objects pooled with their own l4_tags), e.g. L4StarTwinkleA/B/C
--   Props     gameplay/solid props remain Models; single-mesh decorative props share per-asset Folders
--   Doors     one Model per door: anchored hinge + unanchored collider leaf + welded visual meshes
--   Collision the layout's collidable parts (minus replaced props the new colliders cover), the new geometry's
--             colliders, Seats, and non-colliding tagged markers (Level4V4Doorway). Invisible, except occluders
--   Signage   invisible carriers holding the original posters' Decals and signs' SurfaceGuis
--   Lights    the exported lights on invisible holders (a prop's lights: holders inside that prop's Model), plus
--             the original preview lights the placement file lists (legacyLights: never ceiling ones), cloned
--   Level4V4Exit  cloned from the original preview (the preview access script teleports onto it)
--   OccasionalFixtureFlicker  the one place lights flicker (client script, FLICKER_SOURCE below)
-- The original preview's ceiling Fixtures and their lights are no longer cloned (v3, owner: "overlaps").
--
-- Camera occluders (v3, owner: "I can see through the roof / the walls"). Poppercam only stops at parts with
-- CanCollide = true and Transparency < 0.25, and every visual mesh here is CanCollide = false while the colliders
-- were invisible, so the camera passed through everything. A collider the placement file flags as an occluder is
-- now drawn: Transparency 0, Color OCCLUDER_COLOR (8,8,8), CastShadow false, CanQuery true, CanTouch false, named
-- "Occluder", keeping its tags and attributes, with SmoothPlastic material. make_place.py has already inset it
-- 0.1 stud on every axis (both faces) so it hides inside the visual surface; an axis that would drop below 0.3 stud
-- keeps its original size and the whole thin collider stays invisible. Which colliders qualify (export_l4.py):
-- collidable visible layout parts (Transparency < 1), except Glass / door leaves and anything thinner than 0.5 stud,
-- and Blender colliders explicitly flagged l4_occluder. Non-occluder colliders stay invisible.
-- Signage carriers and legacyLights are filtered in make_place.py: no removed C1 zone / closed A1 west entry signs,
-- no original ceiling lights; CARRIER_MOVE there supports path + original centre -> new layout CFrame overrides.
--
-- Flicker: a unit is a Model with a truthy OccasionalFlicker attribute (FlickerLens / NeonFlicker props: their
-- Neon parts and every Light inside them) or a BasePart with it outside such a Model (a light holder). Every few
-- seconds a unit stutters and usually stays OFF for 0.3-4 s (12 %: a 6-15 s outage), long enough for its area to go
-- dark. With ReduceFlashing (anything but an explicit false, so a profile that has not loaded never strobes) it
-- fades out over 1.5 s, holds and fades back instead. Lights go off through Brightness, lenses go matte and dark.
-- The model carries BoundsCenter / BoundsSize (Vector3) for client zone checks (Level 4 Lighting Controller).
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local CS = game:GetService("CollectionService")
local BASE = "http://127.0.0.1:8765"
local NAME = "Level 4 Cinema Blender"
local OLD_NAME = "Level 4 Cinema Preview"
local SHIFT = Vector3.new(6000, 0, 0)                 -- new model = original layout + SHIFT
local ORIGIN = Vector3.new(23000, 0, 0) + SHIFT       -- Blender origin in Studio space
local OCCLUDER_COLOR = Color3.fromRGB(8, 8, 8)
local PUSH_DOOR_SOURCE = __PUSH_DOOR_SOURCE__
local FLICKER_SOURCE = [==[
-- Level 4 cinema (Blender build): flickering lights. Runs on every client (RunContext Client): a blink costs no
-- replication, and parts that stream in join. A unit is a Model with a truthy OccasionalFlicker attribute (its Neon
-- parts and every Light inside it) or a BasePart with the attribute outside such a Model (a light holder). Every few
-- seconds a unit stutters and usually stays OFF for 0.3-4 s (12 %: a 6-15 s outage), so its area goes dark. With
-- ReduceFlashing (anything but an explicit false: a profile that has not loaded yet never strobes) it fades out,
-- holds and fades back instead. Written by tools/level4_blender/place.luau.
local TweenService = game:GetService("TweenService")
local player = game:GetService("Players").LocalPlayer
local model = script.Parent
local running = {}
local FADE = 1.5

local function reduced()
	return player == nil or player:GetAttribute("ReduceFlashing") ~= false
end

local function members(unit)
	local lights, lenses = {}, {}
	local list = unit:GetDescendants()
	table.insert(list, unit)
	for _, d in list do
		if d:IsA("Light") then
			table.insert(lights, { d, d.Brightness })
		elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Transparency < 1 then
			table.insert(lenses, { d, d.Color })
		end
	end
	return lights, lenses
end

local function set(lights, lenses, on)
	for _, e in lights do e[1].Brightness = if on then e[2] else 0 end
	for _, e in lenses do
		e[1].Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		e[1].Color = if on then e[2] else e[2]:Lerp(Color3.new(0, 0, 0), 0.85)
	end
end

local function fade(state, lights, lenses, on)
	local info = TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	local function tween(part, goals)
		local t = TweenService:Create(part, info, goals)
		table.insert(state.tweens, t)
		t:Play()
	end
	for _, e in lights do tween(e[1], { Brightness = if on then e[2] else 0 }) end
	for _, e in lenses do      -- stays Neon: a near-black Neon tube reads as dead without a material snap
		e[1].Material = Enum.Material.Neon
		tween(e[1], { Color = if on then e[2] else e[2]:Lerp(Color3.new(0, 0, 0), 0.9) })
	end
	task.wait(FADE)
	table.clear(state.tweens)
end

local function offTime(rng)
	return if rng:NextNumber() < 0.12 then rng:NextNumber(6, 15) else rng:NextNumber(0.3, 4)
end

local function event(unit, rng, state)
	local lights, lenses = members(unit)
	state.lights, state.lenses = lights, lenses
	if #lights + #lenses == 0 then return end
	local function slow()
		fade(state, lights, lenses, false)
		task.wait(offTime(rng))
		fade(state, lights, lenses, true)
	end
	if reduced() then slow(); return end
	for _ = 1, rng:NextInteger(1, 4) do                   -- the stutter
		if reduced() then slow(); return end
		set(lights, lenses, false)
		task.wait(rng:NextNumber(0.04, 0.16))
		if reduced() then slow(); return end
		set(lights, lenses, true)
		task.wait(rng:NextNumber(0.03, 0.25))
	end
	if rng:NextNumber() < 0.7 then                         -- and usually it gives out for a while
		set(lights, lenses, false)
		task.wait(offTime(rng))
		for _ = 1, rng:NextInteger(0, 2) do                -- a catch or two on the way back
			if reduced() then slow(); return end
			set(lights, lenses, true)
			task.wait(rng:NextNumber(0.04, 0.12))
			if reduced() then slow(); return end
			set(lights, lenses, false)
			task.wait(rng:NextNumber(0.05, 0.2))
		end
	end
	if reduced() then fade(state, lights, lenses, true); return end
	set(lights, lenses, true)
end

local function unitOf(d)
	if not d:GetAttribute("OccasionalFlicker") then return nil end
	if d:IsA("Model") then return d end
	if not d:IsA("BasePart") then return nil end
	local owner = d:FindFirstAncestorWhichIsA("Model")
	if owner and owner ~= model and owner:GetAttribute("OccasionalFlicker") then return nil end   -- the Model is the unit
	return d
end

local function watch(d)
	local unit = unitOf(d)
	if not unit or running[unit] then return end
	local state = { tweens = {} }
	running[unit] = state
	state.thread = task.spawn(function()
		local rng = Random.new()
		-- a quarter of the units are dying (an episode every 2-6 s), the rest act up every 6-20 s
		local dying = rng:NextNumber() < 0.25
		local lo, hi = if dying then 2 else 6, if dying then 6 else 20
		task.wait(rng:NextNumber(0, hi))
		while running[unit] == state and unit:IsDescendantOf(model) do
			event(unit, rng, state)
			task.wait(rng:NextNumber(lo, hi))
		end
	end)
end

local function stop(unit)
	local state = running[unit]
	if not state then return end
	running[unit] = nil
	if state.thread then task.cancel(state.thread) end
	for _, t in state.tweens do t:Cancel() end
	set(state.lights or {}, state.lenses or {}, true)
end

for _, d in model:GetDescendants() do watch(d) end
local added = model.DescendantAdded:Connect(watch)
local removing = model.DescendantRemoving:Connect(stop)
script.Destroying:Connect(function()
	added:Disconnect()
	removing:Disconnect()
	for unit in running do stop(unit) end
end)
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

-- c = {cf12 (layout frame), size, shape, material, tags, kind, occluder, attributes?}
-- kind: "Part" | "Seat" | "Marker"; occluder = true: a camera occluder (see the header; size already inset)
local function makeCollider(c, parent)
	local cfT, size, shape, mat, tags, kind, occ, attrs = c[1], c[2], c[3], c[4], c[5], c[6] or "Part", c[7], c[8]
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
	if occ == true and kind == "Part" and math.min(size[1], size[2], size[3]) >= 0.3 then
		part.Name = "Occluder"
		part.Transparency = 0
		part.Color = OCCLUDER_COLOR
		part.Material = Enum.Material.SmoothPlastic
	end
	for _, tag in ipairs(tags or {}) do CS:AddTag(part, tag) end
	if type(attrs) == "table" then
		for k, v in pairs(attrs) do part:SetAttribute(k, v) end
	end
	part.Parent = parent
	return part
end

-- l = {type, pos, rot, color, range, brightness, shadows, angle?, size?, prop?, flicker?, kind?, name}; shines
-- along -Y of rot. A prop's light sits on its holder inside the prop's Model, so the prop's flicker unit switches it.
local function makeLight(l, folder, placed)
	local light = Instance.new(l.type)
	light.Color = Color3.new(l.color[1], l.color[2], l.color[3])
	light.Range = l.range
	light.Brightness = l.brightness
	light.Shadows = l.shadows == true
	if not light:IsA("PointLight") then
		light.Face = Enum.NormalId.Bottom
		if l.angle then light.Angle = l.angle end
	end
	local host = Instance.new("Part")
	host.Name = l.name or l.type
	host.Size = if l.size then vec(l.size) else Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = cf12({ l.pos[1], l.pos[2], l.pos[3], table.unpack(l.rot) }, SHIFT)
	invisible(host)
	host.CanCollide = false
	host.CanQuery = false
	if l.flicker then host:SetAttribute("OccasionalFlicker", true) end
	if l.kind then host:SetAttribute("L4Kind", l.kind) end
	light.Parent = host
	host.Parent = (l.prop and placed[l.prop]) or folder
end

-- an original light on an invisible holder with its parent's frame and size; legacy lights never consume
-- the six hero shadow slots controlled by ceilings.py's final lighting pass
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
	local copy = l:Clone()
	copy.Shadows = false
	copy.Parent = holder
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
	model:SetAttribute("Level4Revision", 10)
	model:SetAttribute("Level4PreviewReady", false)
	model:SetAttribute("Level4Source", "Blender")
	model:SetAttribute("SourceBlend", "G:/Blender/Level4_Cinema/Level4_Cinema.blend")
	model:SetAttribute("StudsPerMetre", 1 / 0.28)
	local function folder(n)
		local f = Instance.new("Folder"); f.Name = n; f.Parent = model; return f
	end
	local world, props, doors, collision = folder("World"), folder("Props"), folder("Doors"), folder("Collision")
	local signage, lights = folder("Signage"), folder("Lights")

	-- one template per chunk
	local templates, byGroup = {}, {}
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
		elseif not bare then
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
		if m then makeCollider({ c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9] }, m) end
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

	local lightCount, legacyCount, legacyMissing = 0, 0, 0
	for li, l in ipairs(data.lights or {}) do
		makeLight(l, lights, placed)
		lightCount += 1
		if li % 100 == 0 then task.wait() end
	end
	-- the original lights the placement file keeps (never ceiling ones), by light path + original host position
	local originalLights = {}
	for _, l in ipairs(old:GetDescendants()) do
		if l:IsA("Light") and l.Parent:IsA("BasePart") then
			originalLights[key(pathOf(l, old), l.Parent.Position)] = l
		end
	end
	for _, e in ipairs(data.legacyLights or {}) do
		local l = originalLights[key(e[1], vec(e[2]))]
		if l then
			cloneLight(l, lights)
			legacyCount += 1
		else
			legacyMissing += 1
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
	local occluders = 0
	for _, part in ipairs(collision:GetChildren()) do
		if part.Name == "Occluder" then occluders += 1 end
	end
	shared.__l4place = string.format("done world=%d props=%d doors=%d colliders=%d occluders=%d propColliders=%d signage=%d(missing %d) lights=%d legacyLights=%d(missing %d)",
		#world:GetChildren(), #props:GetChildren(), doorCount, #collision:GetChildren(), occluders,
		#(data.propColliders or {}), #signage:GetChildren(), missing, lightCount, legacyCount, legacyMissing)
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then shared.__l4place = "FAILED: " .. tostring(err) end
end)
return "started"
