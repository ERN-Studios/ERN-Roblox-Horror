-- Builds Workspace."Level 5 Quiet Suburbs" from the uploaded Level 5 mesh assets.
-- Runs as a background task in the plugin VM; progress in shared.__l5place.
local AS = game:GetService("AssetService")
local HS = game:GetService("HttpService")
local BASE = "http://127.0.0.1:8765"
local ORIGIN = Vector3.new(40000, 0, 0)
local NAME = "Level 5 Quiet Suburbs"

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

local function run()
	local data, assets = fetch()
	for _, c in ipairs(data.chunks) do
		assert(assets[tostring(c[1])], "chunk " .. c[1] .. " has no uploaded asset")
	end
	local old = workspace:FindFirstChild(NAME)
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = NAME
	model:SetAttribute("Level5Preview", true)
	model:SetAttribute("PreviewOnly", true)
	model:SetAttribute("SourceBlend", "G:/Blender/Level4_Quiet_Suburbs/Level4_Quiet_Suburbs.blend")
	model:SetAttribute("StudsPerMetre", 1 / 0.28)
	local world = Instance.new("Folder"); world.Name = "World"; world.Parent = model
	local kits = Instance.new("Folder"); kits.Name = "Kits"; kits.Parent = model
	local lights = Instance.new("Folder"); lights.Name = "Lights"; lights.Parent = model

	-- one template per chunk
	local templates, byGroup = {}, {}
	local made = 0
	for i, c in ipairs(data.chunks) do
		local id, group, matName, size = c[1], c[2], c[3], c[4]
		local st = data.styles[matName]
		local fidelity = if not st.cc then Enum.CollisionFidelity.Box
			elseif group < 0 then Enum.CollisionFidelity.PreciseConvexDecomposition
			else Enum.CollisionFidelity.Default
		local uri = Content.fromUri("rbxassetid://" .. assets[tostring(id)])
		local part
		for _, f in ipairs({fidelity, Enum.CollisionFidelity.Default, Enum.CollisionFidelity.Box}) do
			local ok, res = pcall(AS.CreateMeshPartAsync, AS, uri,
				{CollisionFidelity = f, RenderFidelity = Enum.RenderFidelity.Automatic})
			if ok then part = res; break end
			shared.__l5fallbacks = (shared.__l5fallbacks or "") .. id .. ":" .. tostring(f) .. " "
		end
		assert(part, "chunk " .. id .. " could not be built")
		part.Name = matName
		part.Anchored = true
		part.Material = Enum.Material[st.m]
		part.Color = Color3.new(st.c[1], st.c[2], st.c[3])
		part.Transparency = st.t
		part.CanCollide = st.cc
		part.CanTouch = false
		part.CanQuery = st.cc
		part:SetAttribute("L5Chunk", id)
		templates[i] = {part = part, size = vec(size), center = vec(c[5])}
		if group >= 0 then
			byGroup[group] = byGroup[group] or {}
			table.insert(byGroup[group], templates[i])
		else
			part.Size = vec(size)
			part.CFrame = CFrame.new(ORIGIN + vec(c[5]))
			part.Parent = world
		end
		made += 1
		shared.__l5place = "templates " .. made .. "/" .. #data.chunks
		if made % 20 == 0 then task.wait() end
	end

	local placed = 0
	for pi, p in ipairs(data.placements) do
		local group, pos, r, s = p[1], p[2], p[3], p[4]
		local cf = CFrame.new(ORIGIN.X + pos[1], ORIGIN.Y + pos[2], ORIGIN.Z + pos[3],
			r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		local scale = vec(s)
		for _, t in ipairs(byGroup[group]) do
			local part = t.part:Clone()
			part.Size = t.size * scale
			part.CFrame = cf * CFrame.new(t.center * scale)
			part.Parent = kits
			placed += 1
		end
		if pi % 100 == 0 then
			shared.__l5place = "placements " .. pi .. "/" .. #data.placements
			task.wait()
		end
	end
	for _, t in ipairs(templates) do
		if not t.part.Parent then t.part:Destroy() end
	end

	for _, l in ipairs(data.lights) do
		local holder = Instance.new("Part")
		holder.Name = l.name
		holder.Anchored = true; holder.CanCollide = false; holder.CanQuery = false; holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.new(1, 1, 1)
		local at = ORIGIN + vec(l.pos)
		local dir = vec(l.dir)
		holder.CFrame = CFrame.lookAt(at, at + dir)
		local light = if l.type == "SPOT" then Instance.new("SpotLight") else Instance.new("PointLight")
		if l.type == "SPOT" then
			light.Face = Enum.NormalId.Front
			light.Angle = math.clamp(l.angle, 10, 180)
		end
		light.Color = Color3.new(l.color[1], l.color[2], l.color[3])
		light.Range = math.clamp(math.sqrt(l.energy) * 0.6, 16, 60)
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = holder
		holder.Parent = lights
	end

	model:SetAttribute("PartCount", #world:GetChildren() + #kits:GetChildren())
	model.Parent = workspace
	shared.__l5place = "done world=" .. #world:GetChildren() .. " kits=" .. #kits:GetChildren()
		.. " lights=" .. #lights:GetChildren()
end

task.spawn(function()
	local ok, err = pcall(run)
	if not ok then shared.__l5place = "FAILED: " .. tostring(err) end
end)
return "started"
