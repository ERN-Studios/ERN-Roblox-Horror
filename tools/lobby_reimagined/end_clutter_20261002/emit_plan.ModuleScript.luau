-- Candidate helper only; root must compare authoritative Studio before using.
-- Call after the existing R4 manifest placements. All geometry reuses the
-- exact Blender mesh kit; native parts supply collision and luminous lenses.
local Module = {}
local OWNED = "LobbyReimaginedOwned"
local function v(a) return Vector3.new(table.unpack(a)) end
function Module.Emit(plan, center, visuals, collisions, lighting, place)
	assert(plan.schema == "lobby-r4-additive-end-clutter-v1")
	assert(plan.statistics.uniqueNewMeshes == 0 and plan.statistics.archCornerFailures == 0)
	assert(not visuals:FindFirstChild("Reference End Furniture Piles"), "Owned pile already exists")
	local folder = Instance.new("Folder")
	folder.Name = "Reference End Furniture Piles"
	folder:SetAttribute(OWNED, true)
	folder:SetAttribute("ClutterRevision20261002", true)
	folder.Parent = visuals
	for _, item in ipairs(plan.placements) do
		local cf = CFrame.new(center + v(item.robloxPosition)) * CFrame.Angles(table.unpack(item.rotation))
		local object = place(item.family, cf, folder)
		object.Name = item.name
		object:SetAttribute(OWNED, true)
		object:SetAttribute("EndClutterFamily", item.family)
	end
	for _, item in ipairs(plan.colliders) do
		local p = Instance.new("Part")
		p.Name = item.name; p.Anchored = true
		p.Size = v(item.size); p.CFrame = CFrame.new(center + v(item.position))
		p.CanCollide = true; p.CanQuery = true; p.CanTouch = false
		p.Transparency = 1; p.CastShadow = false
		p:SetAttribute(OWNED, true); p:SetAttribute("FurnitureEndBlocker", true)
		p.Parent = collisions
	end
	-- Keep the established warm/cyan room fills and global Lighting untouched.
	-- A luminous underside makes the existing fixtures readable from eye level.
	local count = 0
	for _, host in ipairs(lighting:GetChildren()) do
		if host.Name == "Tunnel Lamp" and host:IsA("BasePart") then
			local fill = host:FindFirstChild("Preview Fill")
			if fill and fill:IsA("PointLight") then fill.Brightness = .55 end
			count += 1
			local lens = Instance.new("Part")
			lens.Name = string.format("Ceiling Tube Luminous Lens %02d", count)
			lens.Size = Vector3.new(3.0, .035, .74)
			lens.CFrame = host.CFrame * CFrame.new(0, .73, 0)
			lens.Anchored = true; lens.CanCollide = false
			lens.CanTouch = false; lens.CanQuery = false
			lens.Material = Enum.Material.Neon
			lens.Color = Color3.fromRGB(95, 220, 213)
			lens.Transparency = .12; lens.CastShadow = false
			lens:SetAttribute(OWNED, true); lens.Parent = lighting
		end
	end
	folder:SetAttribute("AddedFurnitureInstances", #plan.placements)
	folder:SetAttribute("AddedInstancedTriangles", plan.statistics.extraInstancedTriangles)
	return folder
end
return Module
