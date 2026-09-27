-- Unfinished Level 5 reference gallery for the existing developer-only door.
-- Builds isolated visual cells; it never changes the playable Architecture or round flags.
local systems = script.Parent
local facadeModule = systems:FindFirstChild("Level 5 Reference Facades")
local anomalyModule = systems:FindFirstChild("Level 5 Reference Anomalies")
assert(facadeModule and facadeModule:IsA("ModuleScript"), "Level 5 Reference Facades is missing")
assert(anomalyModule and anomalyModule:IsA("ModuleScript"), "Level 5 Reference Anomalies is missing")
local Facades = require(facadeModule)
local Anomalies = require(anomalyModule)

local Gallery = {}
Gallery.ContentVersion = "reference-gallery-2026-09-27-v1"

local V, CF = Vector3.new, CFrame.new
local MaterialService = game:GetService("MaterialService")
local WHITE = Color3.fromRGB(241, 238, 220)
local DARK = Color3.fromRGB(31, 37, 38)
local GREEN = Color3.fromRGB(48, 86, 67)
local CARPET_TEXTURE = "rbxassetid://136282007145831"
local CLAPBOARD_TEXTURE = "rbxassetid://107441812561821"
local LAWN_TEXTURE = "rbxassetid://108216315862080"
local MATERIAL_VARIANTS = {
	[Enum.Material.Plaster] = "Level5AgedPlaster",
	[Enum.Material.WoodPlanks] = "Level5PaintedSiding",
	[Enum.Material.Grass] = "Level5LawnGrass",
	[Enum.Material.LeafyGrass] = "Level5LawnGrass",
	[Enum.Material.Slate] = "Level5RoofShingles",
	[Enum.Material.Fabric] = "Level5LoopCarpet",
}

local SECTION_NAMES = {
	"COURTYARD", "TOWNHOUSE CORRIDOR", "BRIGHT ATRIUM", "TOWER CANYON",
	"SLOPED HOUSES", "GABLED LAWN", "STAIR CUTAWAY", "UPPER WALKWAY",
	"SKYBRIDGE CANYON", "EMPTY ROOMS",
}
local FACADE_BUILDERS = {
	Facades.BuildCourtyard, Facades.BuildCorridor,
	Facades.BuildBrightAtrium, Facades.BuildTowerCanyon,
}

local function sectionName(id)
	return ("GallerySection_%02d"):format(id)
end

local function selectionName(id)
	return ("GallerySelect_%02d"):format(id)
end

local function selectionPromptName(id)
	return ("Level5GallerySection%02dPrompt"):format(id)
end

local function hubPromptName(id)
	return ("Level5GalleryHubReturn%02dPrompt"):format(id)
end

local function part(parent, name, size, frame, color, material, collide, className)
	local p = Instance.new(className or "Part")
	p.Name = name
	p.Size = size
	p.CFrame = frame
	p.Anchored = true
	p.Color = color or WHITE
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = collide ~= false
	p.CanQuery = collide ~= false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = collide ~= false
	local variantName = MATERIAL_VARIANTS[p.Material]
	local variant = variantName and MaterialService:FindFirstChild(variantName)
	if variant and variant:IsA("MaterialVariant") then p.MaterialVariant = variantName end
	p.Parent = parent
	return p
end

local function model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Facades compose their own world frame. Anomalies use Architecture-style local
-- frames, so only that kit adds the gallery origin in K.part/K.floor/K.window.
local function kit(root, originFrame)
	local K = {root = root, V = V, CF = CF, C = {green = GREEN}}
	function K.model(name, into)
		return model(into or root, name)
	end
	function K.part(into, name, size, frame, color, material, collide, className)
		return part(into, name, size, originFrame * frame, color, material, collide, className)
	end
	function K.floor(into, name, x, y, z, w, d, color, frame)
		local lawn = color == K.C.green
		local floorPart = K.part(into, name, V(w, 1.2, d),
			(frame or CFrame.identity) * CF(x, y - 0.6, z),
			color or Color3.fromRGB(162, 150, 125),
			lawn and Enum.Material.Grass or Enum.Material.Fabric, true)
		if lawn then floorPart:SetAttribute("LawnSurface", true) end
		return floorPart
	end
	function K.window(into, frame, w, h, _lit, simple)
		local glass = K.part(into, "WindowGlass", V(w, h, 0.14), frame,
			Color3.fromRGB(87, 102, 102), Enum.Material.Glass, true)
		glass.Transparency = 0.2
		glass:SetAttribute("Level5TintedWindow", true)
		for _, side in ipairs({-1, 1}) do
			K.part(into, "WindowJamb", V(0.25, h + 0.45, 0.34),
				frame * CF(side * (w / 2 + 0.08), 0, -0.08), WHITE)
			K.part(into, "WindowSill", V(w + 0.65, 0.25, 0.4),
				frame * CF(0, side * (h / 2 + 0.08), -0.12), WHITE)
		end
		K.part(into, "WindowMullion", V(0.12, h, 0.23), frame * CF(0, 0, -0.09), WHITE)
		for _, side in ipairs(simple and {0} or {-0.22, 0.22}) do
			K.part(into, "WindowCrossbar", V(w, 0.12, 0.23),
				frame * CF(0, h * side, -0.09), WHITE)
		end
		return glass
	end
	return K
end

-- Candidate imagegen textures belong only to these disposable DEV gallery cells.
-- The reference builders and the playable Level 5 material setup stay untouched.
local function tiledTexture(surface, face, assetId, studsPerTile, name)
	local texture = Instance.new("Texture")
	texture.Name = name
	texture.Face = face
	texture.Texture = assetId
	texture.StudsPerTileU = studsPerTile
	texture.StudsPerTileV = studsPerTile
	texture:SetAttribute("Level5GalleryCandidate", true)
	texture.Parent = surface
end

local LAWN_SURFACES = {
	[1] = {DarkLawn = 16},
	[5] = {DimCourtLawn = 18, DarkGreenInclineLawn = 18},
	[6] = {DarkGrassLane = 18},
	[9] = {VastCanyonLawn = 24, SlopedPlantedEdge = 24},
}

local function applyCandidateTextures(cell, id)
	local lawns = LAWN_SURFACES[id]
	local carpetBase, hiddenTiles, creamSiding = nil, 0, 0
	for _, item in ipairs(cell:GetDescendants()) do
		if item:IsA("BasePart") then
			if lawns and lawns[item.Name] then
				tiledTexture(item, Enum.NormalId.Top, LAWN_TEXTURE, lawns[item.Name], "CandidateDarkLawn")
			elseif id == 2 then
				if item.Name == "CarpetBase" then
					carpetBase = item
				elseif item.Name == "CarpetTileCrossGrain" or item.Name == "CarpetTileLengthGrain" then
					item.Transparency = 1
					item.CastShadow = false
					item.CanCollide = false
					item.CanQuery = false
					hiddenTiles += 1
				elseif item.Name == "SidingWall" and item.Color == Color3.fromRGB(196, 184, 160)
					and creamSiding < 3 then
					-- Three full-height piers in the nearest cream bay form one small material sample.
					tiledTexture(item, Enum.NormalId.Right, CLAPBOARD_TEXTURE, 18, "CandidateCreamClapboard")
					creamSiding += 1
				end
			end
		end
	end
	if id == 2 then
		assert(carpetBase and hiddenTiles == 40 and creamSiding == 3,
			"Corridor candidate texture targets changed")
		tiledTexture(carpetBase, Enum.NormalId.Top, CARPET_TEXTURE, 12, "CandidateGreigeCarpet")
	end
end

local function prompt(parent, name, action, object)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0.5
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Enabled = false -- access script connects all server checks before enabling
	p.Parent = parent
	return p
end

local function label(parent, text, width)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DraftLabel"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(width or 260, 66)
	gui.StudsOffset = V(0, 4.4, 0)
	gui.Parent = parent
	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.fromScale(1, 1)
	caption.BackgroundColor3 = DARK
	caption.BackgroundTransparency = 0.12
	caption.BorderSizePixel = 0
	caption.TextColor3 = WHITE
	caption.TextScaled = true
	caption.TextWrapped = true
	caption.Font = Enum.Font.GothamBold
	caption.Text = text
	caption.Parent = gui
end

local function upright(frame)
	local look = frame.LookVector
	local flat = V(look.X, 0, look.Z)
	return CFrame.lookAt(frame.Position, frame.Position + (if flat.Magnitude > 0.01 then flat else V(0, 0, 1)))
end

local function cameraPad(cell, cameraFrame, id, gradeY, cameraFov)
	local view = upright(cameraFrame)
	local arrivalPosition = V(view.Position.X, gradeY + 3, view.Position.Z)
	local arrival = CFrame.lookAt(arrivalPosition, arrivalPosition + view.LookVector)
	local at = arrival.Position
	local pad = part(cell, "GalleryViewPad", V(14, 0.5, 14), CF(at.X, gradeY - 0.25, at.Z), WHITE, nil, true)
	pad.Transparency = 1
	pad.CastShadow = false
	pad:SetAttribute("GalleryLanding", true)
	local padTop = pad.Position.Y + pad.Size.Y / 2
	for _, edge in ipairs({
		{V(-7.2, padTop + 4, 0), V(0.4, 8, 14.4)},
		{V(7.2, padTop + 4, 0), V(0.4, 8, 14.4)},
		{V(0, padTop + 4, -7.2), V(14.4, 8, 0.4)},
		{V(0, padTop + 4, 7.2), V(14.4, 8, 0.4)},
	}) do
		local guard = part(cell, "GalleryViewGuard", edge[2], CF(V(at.X, 0, at.Z) + edge[1]), WHITE, nil, true)
		guard.Transparency = 1
		guard.CastShadow = false
	end
	local marker = part(cell, "GalleryViewpointMarker", V(0.25, 0.25, 0.25), arrival, WHITE, nil, false)
	marker.Transparency = 1
	marker.CanQuery = false
	marker.CastShadow = false
	marker:SetAttribute("ReferenceCameraCFrame", cameraFrame)
	if cameraFov then marker:SetAttribute("ReferenceCameraFov", cameraFov) end
	local point = part(cell, "GalleryReturnPoint", V(0.25, 0.25, 0.25),
		CF(at - arrival.LookVector * 5), WHITE, nil, false)
	point.Transparency = 1
	point.CanQuery = false
	point.CastShadow = false
	point:SetAttribute("GallerySectionId", id)
	prompt(point, hubPromptName(id), "RETURN TO HUB", ("SECTION %02d - UNVERIFIED DRAFT"):format(id))
	return pad, marker, point
end

local function bounds(m)
	local frame, size = m:GetBoundingBox()
	local r, u, l = frame.RightVector, frame.UpVector, frame.LookVector
	local half = size * 0.5
	local extent = V(
		math.abs(r.X) * half.X + math.abs(u.X) * half.Y + math.abs(l.X) * half.Z,
		math.abs(r.Y) * half.X + math.abs(u.Y) * half.Y + math.abs(l.Y) * half.Z,
		math.abs(r.Z) * half.X + math.abs(u.Z) * half.Y + math.abs(l.Z) * half.Z)
	return frame.Position - extent, frame.Position + extent
end

local function assertSeparated(m, others)
	local lo, hi = bounds(m)
	for _, other in ipairs(others) do
		local a, b = bounds(other)
		assert(hi.X + 24 < a.X or b.X + 24 < lo.X or hi.Z + 24 < a.Z or b.Z + 24 < lo.Z,
			m.Name .. " overlaps " .. other.Name)
	end
end

function Gallery.Build(root, origin)
	assert(root and root:IsA("Model") and typeof(origin) == "Vector3", "Gallery.Build needs a Model and Vector3 origin")
	assert(#root:GetChildren() == 0, "Gallery.Build needs an empty preview model")
	local originFrame = CF(origin)
	root:SetAttribute("GalleryContentVersion", Gallery.ContentVersion)
	root:SetAttribute("FidelityStatus", "unverified-draft")
	root:SetAttribute("GalleryOnly", true)

	local hub = model(root, "GalleryHub")
	local hubFloor = part(hub, "Level5PreviewArrivalFloor", V(90, 0.5, 76),
		originFrame * CF(0, -0.25, -650), Color3.fromRGB(174, 168, 152), Enum.Material.Concrete, true)
	hubFloor:SetAttribute("GalleryLanding", true)
	for _, edge in ipairs({
		{V(-45.5, 3, -650), V(1, 6, 76)}, {V(45.5, 3, -650), V(1, 6, 76)},
		{V(0, 3, -688.5), V(90, 6, 1)}, {V(0, 3, -611.5), V(90, 6, 1)},
	}) do
		part(hub, "GalleryHubRail", edge[2], originFrame * CF(edge[1]), WHITE, nil, true)
	end
	local notice = part(hub, "GalleryWorkInProgressNotice", V(20, 6, 0.6),
		originFrame * CF(0, 5, -678), DARK, nil, false)
	label(notice, "LEVEL 5 REWORK - VIEW ONLY\nUNVERIFIED REFERENCE DRAFTS", 370)
	for id = 1, 10 do
		local col = (id - 1) % 5
		local row = math.floor((id - 1) / 5)
		local stand = part(hub, selectionName(id), V(2, 3, 2),
			originFrame * CF(-30 + col * 15, 1.5, -636 + row * 18), DARK, nil, true)
		stand:SetAttribute("GallerySectionId", id)
		label(stand, ("%02d  %s\nVIEW ONLY - WIP"):format(id, SECTION_NAMES[id]), 210)
		prompt(stand, selectionPromptName(id), ("VIEW SECTION %02d"):format(id), "LEVEL 5 REWORK - UNVERIFIED DRAFT")
	end
	local hubPosition = originFrame * V(0, 4, -655)
	local hubArrival = CFrame.lookAt(hubPosition, hubPosition + V(0, 0, 1))
	local marker = part(root, "Level5DeveloperPreviewArrival", V(0.25, 0.25, 0.25), hubArrival,
		WHITE, nil, false)
	marker.Transparency = 1
	marker.CanQuery = false
	marker.CastShadow = false
	local returnPoint = Instance.new("Attachment")
	returnPoint.Name = "Level5DeveloperPreviewReturnPoint"
	returnPoint.CFrame = CF(0, -1, -4)
	returnPoint.Parent = marker
	prompt(returnPoint, "Level5DeveloperPreviewReturnPrompt", "RETURN TO LOBBY", "LEVEL 5 REWORK - UNVERIFIED DRAFT")

	local placed = {hub}
	for id = 1, 10 do
		local col = (id - 1) % 4
		local row = math.floor((id - 1) / 4)
		local localFrame = CF(-1125 + col * 750, 0, row * 750)
		local cell = model(root, sectionName(id))
		cell:SetAttribute("GallerySectionId", id)
		cell:SetAttribute("FidelityStatus", "unverified-draft")
		local K = kit(cell, if id <= 4 then CFrame.identity else originFrame)
		local cameraFrame
		local cameraFov
		if id <= 4 then
			local built = FACADE_BUILDERS[id](K, cell, originFrame * localFrame)
			local cameraMarker = built:FindFirstChild("ReferenceCameraMarker")
			assert(cameraMarker and cameraMarker:IsA("BasePart"), "Facade reference camera missing for section " .. id)
			cameraFrame = cameraMarker.CFrame
			cameraFov = built:GetAttribute("EstimatedCameraFov")
		else
			local result = Anomalies.Build(K, id, localFrame)
			local camera = result.PreviewCameras[1]
			assert(camera and typeof(camera.position) == "Vector3" and typeof(camera.lookAt) == "Vector3",
				"Anomaly reference camera missing for section " .. id)
			cameraFrame = CFrame.lookAt(originFrame * camera.position, originFrame * camera.lookAt)
		end
		applyCandidateTextures(cell, id)
		local grade = if id == 7 then 11 elseif id == 8 then 24 else 0
		cameraPad(cell, cameraFrame, id, origin.Y + grade, cameraFov)
		assertSeparated(cell, placed)
		table.insert(placed, cell)
	end
	return Gallery.ReadManifest(root)
end

local function matchesPad(pad, marker, height)
	if not (pad and pad:IsA("BasePart") and marker and marker:IsA("BasePart")) then return false end
	local at = pad.CFrame:PointToObjectSpace(marker.Position)
	return math.abs(at.Y - (pad.Size.Y / 2 + height)) < 0.1
		and math.abs(at.X) <= pad.Size.X / 2 - 1
		and math.abs(at.Z) <= pad.Size.Z / 2 - 1
end

function Gallery.ReadManifest(root)
	assert(root and root:IsA("Model") and root:GetAttribute("GalleryContentVersion") == Gallery.ContentVersion,
		"Gallery content version is missing or stale")
	local hub = root:FindFirstChild("GalleryHub")
	local pad = hub and hub:FindFirstChild("Level5PreviewArrivalFloor")
	local marker = root:FindFirstChild("Level5DeveloperPreviewArrival")
	local point = marker and marker:FindFirstChild("Level5DeveloperPreviewReturnPoint")
	local lobbyPrompt = point and point:FindFirstChild("Level5DeveloperPreviewReturnPrompt")
	assert(hub and hub:IsA("Model") and pad and pad:IsA("BasePart") and pad.CanCollide and pad.CanQuery
		and marker and marker:IsA("BasePart") and point and point:IsA("Attachment")
		and lobbyPrompt and lobbyPrompt:IsA("ProximityPrompt") and matchesPad(pad, marker, 4),
		"Gallery hub is incomplete")
	local sections = {}
	for id = 1, 10 do
		local stand = hub:FindFirstChild(selectionName(id))
		local selectPrompt = stand and stand:FindFirstChild(selectionPromptName(id))
		local cell = root:FindFirstChild(sectionName(id))
		local viewPad = cell and cell:FindFirstChild("GalleryViewPad")
		local viewMarker = cell and cell:FindFirstChild("GalleryViewpointMarker")
		local returnPart = cell and cell:FindFirstChild("GalleryReturnPoint")
		local returnPrompt = returnPart and returnPart:FindFirstChild(hubPromptName(id))
		assert(stand and stand:IsA("BasePart") and stand:GetAttribute("GallerySectionId") == id
			and selectPrompt and selectPrompt:IsA("ProximityPrompt")
			and cell and cell:IsA("Model") and cell:GetAttribute("GallerySectionId") == id
			and viewPad and viewPad:IsA("BasePart") and viewPad.CanCollide and viewPad.CanQuery
			and viewMarker and viewMarker:IsA("BasePart")
			and typeof(viewMarker:GetAttribute("ReferenceCameraCFrame")) == "CFrame"
			and matchesPad(viewPad, viewMarker, 3)
			and returnPart and returnPart:IsA("BasePart") and returnPart:GetAttribute("GallerySectionId") == id
			and returnPrompt and returnPrompt:IsA("ProximityPrompt"),
			("Gallery section %02d is incomplete"):format(id))
		sections[id] = {
			Cell = cell, Pad = viewPad, Marker = viewMarker,
			SelectPrompt = selectPrompt, ReturnPrompt = returnPrompt,
		}
	end
	return {HubPad = pad, HubMarker = marker, LobbyPrompt = lobbyPrompt, Sections = sections}
end

return Gallery
