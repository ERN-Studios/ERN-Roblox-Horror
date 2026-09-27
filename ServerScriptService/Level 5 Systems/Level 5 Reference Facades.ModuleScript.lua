-- Level 5 Reference Facades
-- Decorative, non-colliding facade anchors that match the Level 5 rework reference views.
-- The corridor uses small local PointLights for its sconces; nothing touches Lighting or
-- adds paths/doors/gates you can walk through.
-- Every numeric dimension is an ESTIMATE (the source screenshot was not available); tune in Studio.

local Facades = {}

-- Descendant budgets include everything under the root Model. These reference
-- drafts are not installed. Integration must replace old geometry within the
-- live 30,000-descendant limit; the budget is not permission to raise that cap.
local VIEW1_BUDGET = 1800
local VIEW2_BUDGET = 350
local VIEW3_BUDGET = 1100
local VIEW4_BUDGET = 1200

-- Local palette so we don't depend on which keys K.C happens to expose (estimated tones).
local COLORS = {
	sage = Color3.fromRGB(143, 160, 137), -- muted sage clapboard
	sageReveal = Color3.fromRGB(110, 126, 106), -- shadow line under each siding course
	trim = Color3.fromRGB(236, 236, 228), -- white gable/eave/porch trim
	roof = Color3.fromRGB(52, 55, 58), -- dark pitched roof
	glass = Color3.fromRGB(38, 46, 52),
	doorShadow = Color3.fromRGB(46, 52, 50), -- recess reveal around the door
	door = Color3.fromRGB(64, 74, 70),
	deck = Color3.fromRGB(196, 194, 186),
	lamp = Color3.fromRGB(255, 196, 120), -- warm entry fixture (Neon material only, no light object)
	lampMetal = Color3.fromRGB(40, 38, 36),
	tower = Color3.fromRGB(232, 224, 204), -- cream balcony tower
	towerRecess = Color3.fromRGB(150, 144, 130),

	-- View 2 corridor
	carpet = Color3.fromRGB(150, 140, 125),
	carpetAlt = Color3.fromRGB(140, 131, 117), -- rotated tiles: grain turns 90 degrees
	ceilingTile = Color3.fromRGB(205, 205, 198),
	ceilingDark = Color3.fromRGB(120, 118, 112), -- uneven/dark tile bays
	tBar = Color3.fromRGB(225, 225, 220),
	fluorescent = Color3.fromRGB(228, 236, 236), -- Neon panel only, no light object
	corridorWall = Color3.fromRGB(226, 218, 198), -- plain cream right wall
	corridorBacking = Color3.fromRGB(214, 206, 188),
	corridorEnd = Color3.fromRGB(200, 192, 172),
	opening = Color3.fromRGB(34, 34, 36),
	bayBeige = Color3.fromRGB(196, 184, 160),
	baySlate = Color3.fromRGB(104, 120, 140),
	bayLavender = Color3.fromRGB(150, 140, 165),
	corridorDoor = Color3.fromRGB(48, 50, 56),
	exitHousing = Color3.fromRGB(240, 240, 236),
	exitRed = Color3.fromRGB(230, 30, 30),

	-- View 3 bright atrium
	oliveGray = Color3.fromRGB(168, 170, 148), -- pale olive/gray clapboard
	oliveReveal = Color3.fromRGB(136, 138, 118),
	roofTan = Color3.fromRGB(120, 100, 76),
	shutter = Color3.fromRGB(70, 82, 72),
	porchWhite = Color3.fromRGB(228, 226, 218),
	stairGray = Color3.fromRGB(210, 204, 190),
	towerWhite = Color3.fromRGB(218, 220, 222), -- modern round tower
	glassBlue = Color3.fromRGB(40, 52, 62),
	cofferBeam = Color3.fromRGB(226, 224, 216),

	-- View 4 tower canyon
	taupe = Color3.fromRGB(150, 142, 132), -- gray-taupe clapboard
	taupeReveal = Color3.fromRGB(120, 113, 105),
	shingle = Color3.fromRGB(44, 44, 48),
	planting = Color3.fromRGB(52, 78, 46),
	shrub = Color3.fromRGB(46, 70, 42),
	haze = Color3.fromRGB(196, 196, 192),
	hazeTower = Color3.fromRGB(190, 186, 178),
	oatmeal = Color3.fromRGB(183, 179, 157),
	lightSage = Color3.fromRGB(182, 190, 168),
	beigeHouse = Color3.fromRGB(205, 197, 171),
	brownHouse = Color3.fromRGB(169, 157, 137),
	grass = Color3.fromRGB(47, 76, 39),
	grassDark = Color3.fromRGB(36, 60, 33),
	path = Color3.fromRGB(193, 188, 173),
	soil = Color3.fromRGB(54, 47, 39),
	flowers = Color3.fromRGB(152, 134, 116),
	modernWindow = Color3.fromRGB(51, 59, 63),
}

-- Estimated reference cameras, each in its builder's local space.
-- View 1: origin = ground level at the center of the cottage front wall; cottage faces local -Z.
local VIEW1_CAMERA = { offset = Vector3.new(-8, 5.5, -58), target = Vector3.new(2, 55, 78), fov = 70 }
-- View 2: origin = floor at the corridor centerline, near end; the hall runs toward local -Z.
local VIEW2_CAMERA = { offset = Vector3.new(1, 5.5, -2), target = Vector3.new(0, 5, -120), fov = 70 }
-- View 3: origin = ground at the center of the cottage front wall; cottage faces local -Z.
local VIEW3_CAMERA = { offset = Vector3.new(-8, 5.5, -50), target = Vector3.new(8, 58, 42), fov = 74 }
-- View 4: same convention; low camera tilted up to stress tower height.
local VIEW4_CAMERA = { offset = Vector3.new(-14, 5, -45), target = Vector3.new(6, 60, 55), fov = 80 }

-- Reusable balcony rail: white top + bottom rail with evenly spaced vertical balusters.
-- Style fields (studs, estimates): height, topHeight, topDepth, bottomHeight, bottomDepth,
-- bottomLift, balusterSize, spacing (or an explicit balusters count), color, material.
Facades.DEFAULT_RAIL_STYLE = {
	height = 3.2,
	topHeight = 0.35,
	topDepth = 0.5,
	bottomHeight = 0.25,
	bottomDepth = 0.3,
	bottomLift = 0.5,
	balusterSize = 0.3,
	spacing = 4,
	color = COLORS.trim,
	material = Enum.Material.SmoothPlastic,
}

function Facades.RailStyle(overrides)
	local style = table.clone(Facades.DEFAULT_RAIL_STYLE)
	for key, value in pairs(overrides or {}) do
		style[key] = value
	end
	return style
end

-- piece: a builder's piece function (takes local-space CFrames).
-- baseCf: bottom-center of the rail, which runs along baseCf's X axis.
-- Creates 2 + balusters parts; balusters = round(length / spacing) - 1 unless style.balusters is set.
function Facades.BuildBalconyRail(piece, parentModel, baseCf, length, style)
	style = style or Facades.DEFAULT_RAIL_STYLE
	local balusters = style.balusters or math.max(0, math.floor(length / style.spacing + 0.5) - 1)
	local postHeight = style.height - style.topHeight - style.bottomLift
	piece(parentModel, "BalconyRailTop", Vector3.new(length, style.topHeight, style.topDepth), baseCf * CFrame.new(0, style.height - style.topHeight / 2, 0), style.color, style.material)
	piece(parentModel, "BalconyRailBottom", Vector3.new(length, style.bottomHeight, style.bottomDepth), baseCf * CFrame.new(0, style.bottomLift, 0), style.color, style.material)
	for i = 1, balusters do
		local x = -length / 2 + length * i / (balusters + 1)
		piece(parentModel, "BalconyBaluster", Vector3.new(style.balusterSize, postHeight, style.balusterSize), baseCf * CFrame.new(x, style.bottomLift + postHeight / 2, 0), style.color, style.material)
	end
	return 2 + balusters
end

-- Chunkier rail for the distant view 1 tower: 80-stud run at 6-stud spacing -> 12 balusters.
local TOWER_RAIL_STYLE = Facades.RailStyle({ topHeight = 0.5, topDepth = 0.6, balusterSize = 0.45, spacing = 6 })

-- Shared builder: counts every generated instance and applies the local frame.
local function newBuilder(K, frame)
	frame = frame or CFrame.new()
	local SMOOTH = Enum.Material.SmoothPlastic
	local b = { V = K.V, CF = K.CF, count = 0 }

	function b.model(name, modelParent)
		b.count += 1
		return K.model(name, modelParent)
	end

	-- All pieces are decorative: non-colliding, not touchable, not queryable.
	function b.piece(modelParent, name, size, localCf, color, material, className)
		b.count += 1
		local part = K.part(modelParent, name, size, frame * localCf, color, material or SMOOTH, false, className)
		if part then
			part.Anchored = true
			part.CanTouch = false
			part.CanQuery = false
		end
		return part
	end

	-- For non-Part instances (e.g. SurfaceGui) created outside piece().
	function b.extra(n)
		b.count += n
	end

	-- Invisible camera marker plus reference attributes; call last so the count is final.
	function b.finish(root, viewId, budget, camera)
		local marker = b.piece(root, "ReferenceCameraMarker", Vector3.new(1, 1, 1), CFrame.lookAt(camera.offset, camera.target), COLORS.trim)
		if marker then
			marker.Transparency = 1
			marker.CastShadow = false
		end

		local descendants = b.count - 1 -- excludes the root itself
		root:SetAttribute("ReferenceViewId", viewId)
		root:SetAttribute("GeometryIsEstimate", true)
		root:SetAttribute("EstimatedCameraOffset", camera.offset)
		root:SetAttribute("EstimatedCameraTarget", camera.target)
		root:SetAttribute("EstimatedCameraFov", camera.fov)
		root:SetAttribute("PartBudget", budget)
		root:SetAttribute("GeneratedDescendants", descendants)

		if descendants > budget then
			warn(("[Level5ReferenceFacades] View %d generated %d descendants (budget %d)"):format(viewId, descendants, budget))
		end
		return root
	end

	return b
end

-- Shared pieces for views 3 and 4 --------------------------------------------------

-- Front gable on a body whose front face is at z = 0 (facing -Z), centered on o.cx.
-- Parts: 2 wedges + 2 rake trims + 2 roof slabs + ridge cap = 7.
local function addFrontGable(b, parentModel, o)
	local V, CF, piece = b.V, b.CF, b.piece
	local halfW = o.width / 2
	local pitch = math.atan2(o.rise, halfW)
	local slopeLen = math.sqrt(o.rise * o.rise + halfW * halfW)
	local midY = o.baseY + o.rise / 2
	local t = o.roofThick or 0.7
	local sinP, cosP = math.sin(pitch), math.cos(pitch)

	-- offset: out along the slope normal; along: shift downhill so the top end stops at the apex.
	local function slopeCF(side, offset, along, z)
		return CF(o.cx + side * (halfW / 2 + sinP * offset + cosP * along), midY + cosP * offset - sinP * along, z)
			* CFrame.Angles(0, 0, -side * pitch)
	end

	for _, side in ipairs({ -1, 1 }) do
		piece(parentModel, "GableWedge", V(o.depth, o.rise, halfW), CF(o.cx + side * halfW / 2, midY, o.depth / 2) * CFrame.Angles(0, math.rad(-90 * side), 0), o.wallColor, nil, "WedgePart")
		piece(parentModel, "RakeTrim", V(slopeLen + 1, 0.8, 0.6), slopeCF(side, 0.4, 0.5, -0.3), COLORS.trim)
		piece(parentModel, "RoofSlab", V(slopeLen + 1.5, t, o.depth + 1.5), slopeCF(side, 0.8 + t / 2, 0.75, o.depth / 2), o.roofColor, Enum.Material.Slate)
	end
	piece(parentModel, "RidgeCap", V(1.4, 0.6, o.depth + 1.5), CF(o.cx, o.baseY + o.rise + (0.8 + t) / cosP - 0.1, o.depth / 2), o.roofColor, Enum.Material.Slate)
end

-- Framed divided window on a -Z facing wall at z = 0.
-- Parts: frame plate + glass + 2 muntins = 4; +1 with o.sill; +2 with o.shutterColor.
local function addWindow(b, parentModel, cx, cy, w, h, o)
	o = o or {}
	local V, CF, piece = b.V, b.CF, b.piece
	piece(parentModel, "WindowFrame", V(w + 0.8, h + 0.8, 0.2), CF(cx, cy, -0.1), COLORS.trim)
	piece(parentModel, "WindowGlass", V(w, h, 0.2), CF(cx, cy, -0.2), COLORS.glass)
	piece(parentModel, "WindowMuntinV", V(0.18, h, 0.15), CF(cx, cy, -0.35), COLORS.trim)
	piece(parentModel, "WindowMuntinH", V(w, 0.18, 0.15), CF(cx, cy, -0.35), COLORS.trim)
	if o.sill then
		piece(parentModel, "WindowSill", V(w + 1.2, 0.3, 0.7), CF(cx, cy - h / 2 - 0.55, -0.35), COLORS.trim)
	end
	if o.shutterColor then
		for _, side in ipairs({ -1, 1 }) do
			piece(parentModel, "Shutter", V(1.6, h + 0.6, 0.2), CF(cx + side * (w / 2 + 1.2), cy, -0.2), o.shutterColor)
		end
	end
end

-- Re-shape a part created by piece(); Size is re-applied because Ball forces uniform size.
local function setShape(part, partType, size)
	if part then
		part.Shape = partType
		part.Size = size
	end
	return part
end

-- Small porch rail (7-stud bays -> 3 balusters) and a heavier balustrade for view 4.
local PORCH_RAIL_STYLE = Facades.RailStyle({ height = 2.8, topHeight = 0.3, topDepth = 0.4, bottomHeight = 0.2, bottomDepth = 0.25, bottomLift = 0.4, balusterSize = 0.25, spacing = 1.75 })
local BALUSTRADE_STYLE = Facades.RailStyle({ height = 3, topHeight = 0.35, topDepth = 0.55, bottomHeight = 0.3, bottomDepth = 0.4, bottomLift = 0.35, balusterSize = 0.35, spacing = 1.2 })
-- Apartment balconies: 48-stud run at 6-stud spacing -> 7 balusters.
local APT_RAIL_STYLE = Facades.RailStyle({ spacing = 6 })
-- Distant recessed-balcony lips: just two white bands, no balusters (2 parts per tier).
local TOWER_BAND_STYLE = Facades.RailStyle({ balusters = 0, height = 3, topHeight = 0.4, topDepth = 0.5, bottomHeight = 0.4, bottomDepth = 0.6, bottomLift = 0.2 })

-- Each cottage is a complete small facade, rather than a window plate on a
-- solid block. The front wall is divided around four actual recessed openings.
-- The houses can face across a court or toward the reference camera.
local function addClapboardHouse(b, parent, o)
	local house = b.model(o.name, parent)
	local V, CF = b.V, b.CF
	local placement = CF(o.x, 0, o.z) * CFrame.Angles(0, math.rad(o.yaw or 0), 0)
	local function p(modelParent, name, size, localCf, color, material, className)
		return b.piece(modelParent, name, size, placement * localCf, color, material, className)
	end
	local W, H, D = o.width or 25, o.height or 19, o.depth or 17
	local rise, deck, porchDepth = o.rise or 10, o.deck or 1.3, o.porchDepth or 7
	local wall, roof = o.wall or COLORS.sage, o.roof or COLORS.roof
	local reveal = wall:Lerp(Color3.new(0, 0, 0), 0.2)
	local doorX, windowX = W * 0.2 * (o.doorSide or 1), W * 0.255
	local lowWindowX = -windowX * (o.doorSide or 1)
	local lowWindowY = deck + 4.8
	local upperWindowY = H - 4.2
	local openings = {
		{ x0 = lowWindowX - 2.3, x1 = lowWindowX + 2.3, y0 = lowWindowY - 2.8, y1 = lowWindowY + 2.8, kind = "Window" },
		{ x0 = doorX - 2.15, x1 = doorX + 2.15, y0 = deck, y1 = deck + 8.2, kind = "Door" },
		{ x0 = -windowX - 2.3, x1 = -windowX + 2.3, y0 = upperWindowY - 2.8, y1 = upperWindowY + 2.8, kind = "Window" },
		{ x0 = windowX - 2.3, x1 = windowX + 2.3, y0 = upperWindowY - 2.8, y1 = upperWindowY + 2.8, kind = "Window" },
	}
	local function openIntervals(y)
		local active = {}
		for _, opening in ipairs(openings) do
			if y > opening.y0 and y < opening.y1 then
				table.insert(active, opening)
			end
		end
		table.sort(active, function(a, c) return a.x0 < c.x0 end)
		local solid = {}
		local cursor = -W / 2
		for _, opening in ipairs(active) do
			if opening.x0 > cursor + 0.05 then
				table.insert(solid, { cursor, opening.x0 })
			end
			cursor = math.max(cursor, opening.x1)
		end
		if cursor < W / 2 - 0.05 then
			table.insert(solid, { cursor, W / 2 })
		end
		return solid
	end
	local yCuts = { 0, H }
	for _, opening in ipairs(openings) do
		table.insert(yCuts, opening.y0)
		table.insert(yCuts, opening.y1)
	end
	table.sort(yCuts)
	for i = 1, #yCuts - 1 do
		local y0, y1 = yCuts[i], yCuts[i + 1]
		if y1 - y0 > 0.05 then
			for _, span in ipairs(openIntervals((y0 + y1) / 2)) do
				p(house, "ClapboardWall", V(span[2] - span[1], y1 - y0, 0.55), CF((span[1] + span[2]) / 2, (y0 + y1) / 2, 0), wall)
			end
		end
	end
	-- The setback core and dark inner face preserve depth behind the cutouts.
	p(house, "HouseCore", V(W, H, D - 3), CF(0, H / 2, (D + 3) / 2), wall)
	p(house, "ShadowBehindOpenings", V(W - 1, H - 0.6, 0.2), CF(0, H / 2, 2.2), COLORS.doorShadow)
	for _, side in ipairs({ -1, 1 }) do
		p(house, "SideWall", V(0.55, H, D), CF(side * W / 2, H / 2, D / 2), wall)
		p(house, "CornerBoard", V(0.9, H, 0.8), CF(side * (W / 2 - 0.45), H / 2, -0.3), COLORS.trim)
		for course = 1, math.floor(H / 4) - 1 do
			p(house, "SideSidingCourse", V(0.12, 0.12, D - 1), CF(side * (W / 2 + 0.06), course * 4, D / 2), reveal)
		end
	end
	for course = 1, math.floor(H / 1.8) - 1 do
		local y = course * 1.8
		for _, span in ipairs(openIntervals(y)) do
			p(house, "SidingCourse", V(span[2] - span[1] - 0.1, 0.1, 0.12), CF((span[1] + span[2]) / 2, y, -0.34), reveal)
		end
	end
	for _, opening in ipairs(openings) do
		local cx = (opening.x0 + opening.x1) / 2
		local cy = (opening.y0 + opening.y1) / 2
		local ow, oh = opening.x1 - opening.x0, opening.y1 - opening.y0
		if opening.kind == "Window" then
			p(house, "WindowGlass", V(ow, oh, 0.14), CF(cx, cy, 1.6), COLORS.glass)
			p(house, "WindowMullionVertical", V(0.16, oh, 0.2), CF(cx, cy, 1.43), COLORS.trim)
			for _, y in ipairs({ cy - oh / 6, cy + oh / 6 }) do
				p(house, "WindowMullionHorizontal", V(ow, 0.15, 0.2), CF(cx, y, 1.43), COLORS.trim)
			end
			p(house, "WindowSill", V(ow + 0.9, 0.3, 0.8), CF(cx, opening.y0 - 0.14, -0.25), COLORS.trim)
			if o.shutters then
				for _, side in ipairs({ -1, 1 }) do
					p(house, "Shutter", V(1.1, oh + 0.2, 0.2), CF(cx + side * (ow / 2 + 0.65), cy, -0.35), o.shutters)
				end
			end
		else
			p(house, "RecessedDoor", V(ow - 0.4, oh - 0.15, 0.2), CF(cx, cy, 1.8), COLORS.door)
			p(house, "DoorPanelInset", V(ow - 1.2, oh * 0.44, 0.08), CF(cx, cy + 0.8, 1.65), COLORS.doorShadow)
			p(house, "DoorKnob", V(0.25, 0.25, 0.25), CF(cx + 1.25, cy - 0.3, 1.53), COLORS.lampMetal)
		end
		for _, side in ipairs({ -1, 1 }) do
			p(house, "OpeningJamb", V(0.38, oh + 0.5, 0.75), CF(cx + side * (ow / 2 + 0.19), cy, -0.2), COLORS.trim)
		end
		p(house, "OpeningHead", V(ow + 0.8, 0.4, 0.75), CF(cx, opening.y1 + 0.2, -0.2), COLORS.trim)
	end
	p(house, "EaveFrieze", V(W + 1, 0.85, 0.8), CF(0, H - 0.4, -0.35), COLORS.trim)
	addFrontGable({ V = V, CF = CF, piece = p }, house, { cx = 0, baseY = H, width = W, rise = rise, depth = D, wallColor = wall, roofColor = roof, roofThick = 0.7 })
	-- Small divided attic light in the triangular front gable.
	p(house, "GableWindowGlass", V(2.5, 2.8, 0.18), CF(0, H + rise * 0.42, -0.3), COLORS.glass)
	p(house, "GableWindowTrim", V(3.1, 3.4, 0.13), CF(0, H + rise * 0.42, -0.42), COLORS.trim)
	p(house, "GableWindowDark", V(2.5, 2.8, 0.14), CF(0, H + rise * 0.42, -0.55), COLORS.glass)
	p(house, "GableWindowMullion", V(0.16, 2.8, 0.16), CF(0, H + rise * 0.42, -0.68), COLORS.trim)
	-- Projecting porch, with an open central stair bay aligned to the door.
	local frontZ = -porchDepth + 0.5
	p(house, "PorchDeck", V(W + 0.8, deck, porchDepth), CF(0, deck / 2, -porchDepth / 2), COLORS.deck, Enum.Material.WoodPlanks)
	local columnXs = { -W / 2 + 0.6, doorX - 3.4, doorX + 3.4, W / 2 - 0.6 }
	for _, x in ipairs(columnXs) do
		p(house, "PorchColumn", V(0.85, 8.5, 0.85), CF(x, deck + 4.25, frontZ), COLORS.trim)
	end
	p(house, "PorchBeam", V(W + 0.8, 0.8, 1), CF(0, deck + 8.7, frontZ), COLORS.trim)
	p(house, "PorchCeiling", V(W + 0.8, 0.25, porchDepth), CF(0, deck + 9.1, -porchDepth / 2), COLORS.trim)
	p(house, "PorchRoof", V(W + 1.6, 0.55, porchDepth + 1.3), CF(0, deck + 9.5, -porchDepth / 2) * CFrame.Angles(math.rad(-7), 0, 0), roof, Enum.Material.Slate)
	p(house, "PorchFascia", V(W + 1.6, 0.85, 0.3), CF(0, deck + 9.1, -porchDepth - 0.55), COLORS.trim)
	for _, span in ipairs({ { columnXs[1], columnXs[2] }, { columnXs[3], columnXs[4] } }) do
		Facades.BuildBalconyRail(p, house, CF((span[1] + span[2]) / 2, deck, frontZ), span[2] - span[1] - 0.9, PORCH_RAIL_STYLE)
	end
	for step = 1, 3 do
		p(house, "EntryStep", V(6.4, 0.32, 1.5), CF(doorX, deck - step * 0.36, -porchDepth - 0.55 - step * 1.15), COLORS.deck)
	end
	local lampX = doorX + 3.3 * (o.doorSide or 1)
	p(house, "PorchLampGlow", V(0.58, 0.85, 0.55), CF(lampX, 6.3, -0.55), COLORS.lamp, Enum.Material.Neon)
	p(house, "PorchLampCap", V(0.85, 0.22, 0.85), CF(lampX, 6.85, -0.55), COLORS.lampMetal)
	return house
end

local function addBalconyTower(b, parent, o)
	local tower = b.model(o.name, parent)
	local V, CF = b.V, b.CF
	local placement = CF(o.x, 0, o.z) * CFrame.Angles(0, math.rad(o.yaw or 0), 0)
	local function p(modelParent, name, size, localCf, color, material)
		return b.piece(modelParent, name, size, placement * localCf, color, material)
	end
	local W, floors, floorH = o.width, o.floors, o.floorH or 12
	local H, bays, bayW = floors * floorH, o.bays or 4, W / (o.bays or 4)
	local color = o.color or COLORS.tower
	p(tower, "TowerCore", V(W, H, o.depth or 15), CF(0, H / 2, (o.depth or 15) / 2 + 1), color, Enum.Material.Plaster)
	for floor = 0, floors - 1 do
		local baseY = floor * floorH + 2.5
		if o.modern then
			for bay = 1, bays do
				local x = -W / 2 + (bay - 0.5) * bayW
				p(tower, "DarkModernWindow", V(bayW - 1.2, floorH - 3.2, 0.16), CF(x, baseY + 3.4, -0.2), COLORS.modernWindow)
				if not o.simpleModern then
					p(tower, "ModernWindowMullion", V(0.15, floorH - 3.2, 0.18), CF(x, baseY + 3.4, -0.32), COLORS.trim)
				end
			end
			p(tower, "WhiteFloorBand", V(W + 0.8, 0.55, 0.8), CF(0, baseY, -0.42), COLORS.trim)
		else
			for bay = 1, bays do
				local x = -W / 2 + (bay - 0.5) * bayW
				p(tower, "BalconyRecess", V(bayW - 1.3, floorH - 4.8, 0.18), CF(x, baseY + 4.3, -0.2), COLORS.towerRecess)
					if not o.distant or bay % 2 == 0 then
						p(tower, "BalconyWindow", V(bayW - 3.8, floorH - 5.4, 0.2), CF(x, baseY + 4.3, -0.4), COLORS.glass)
					end
					if not o.distant then
						p(tower, "BalconyDoorMullion", V(0.14, floorH - 5.4, 0.2), CF(x, baseY + 4.3, -0.55), COLORS.trim)
					end
			end
			local projection = o.projection or 5.3
			p(tower, "BalconySlab", V(W + 0.5, 0.7, projection), CF(0, baseY, 0.35 - projection / 2), color, Enum.Material.Plaster)
			Facades.BuildBalconyRail(p, tower, CF(0, baseY + 0.35, 0.65 - projection), W, o.railStyle or TOWER_RAIL_STYLE)
		end
	end
	for bay = 0, bays do
		p(tower, "VerticalPier", V(0.75, H, 1.1), CF(-W / 2 + bay * bayW, H / 2, -0.25), COLORS.trim)
	end
	p(tower, "Parapet", V(W + 1.5, 1.5, 3), CF(0, H + 0.75, 0.6), color, Enum.Material.Plaster)
	return tower
end

function Facades.BuildCourtyard(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local root = model("Level5_RefView1_Courtyard", parent)
	local garden = model("CurvedPathAndPlanting", root)
	local cottages = model("RightCottageRow", root)
	local towers = model("OpposingTowerWalls", root)
	local ceiling = model("HighSuspendedCeiling", root)

	-- The path curves from the low camera between dark lawns; clusters of
	-- planted beds and shrubs interrupt the ground instead of a flat strip.
	piece(garden, "DarkLawn", V(125, 0.3, 255), CF(1, -0.22, 56), COLORS.grassDark, Enum.Material.LeafyGrass)
	for k = 0, 12 do
		local z = -54 + k * 17
		local x = -10 + 0.11 * (z + 54) - 0.00042 * (z + 54) ^ 2
		local tangent = 0.11 - 0.00084 * (z + 54)
		piece(garden, "CurvedPaleWalk", V(17.5, 0.12, 17.35), CF(-x, 0.05, z) * CFrame.Angles(0, -math.atan(tangent), 0), COLORS.path, Enum.Material.Concrete)
	end
	for _, patch in ipairs({
		{ 10, -43, 13, 10 }, { 15, -17, 15, 10 }, { 13, 15, 14, 12 },
		{ 16, 49, 17, 11 }, { 13, 82, 15, 12 }, { 15, 113, 16, 12 },
		{ -27, -20, 12, 10 }, { -31, 28, 14, 12 }, { -30, 76, 16, 13 },
	}) do
		piece(garden, "MulchedPlantingBed", V(patch[3], 0.32, patch[4]), CF(-patch[1], 0.05, patch[2]), COLORS.soil, Enum.Material.Ground)
	end
	local shrubs = {
		{ 9, -46, 2.9 }, { 15, -40, 2.2 }, { 17, -19, 3.4 }, { 13, -14, 2.1 },
		{ 12, 12, 2.6 }, { 18, 19, 3.1 }, { 12, 45, 2.6 }, { 20, 52, 3.5 },
		{ 11, 77, 2.4 }, { 19, 83, 3 }, { 10, 108, 2.7 }, { 20, 115, 3.4 },
		{ -29, -22, 2 }, { -33, -16, 3 }, { -33, 26, 2.5 }, { -27, 32, 3.1 },
		{ -33, 74, 3.6 }, { -26, 80, 2.5 },
	}
	for _, shrub in ipairs(shrubs) do
		local size = V(shrub[3], shrub[3] * 0.95, shrub[3])
		setShape(piece(garden, "Shrub", size, CF(-shrub[1], shrub[3] * 0.4, shrub[2]), COLORS.shrub, Enum.Material.LeafyGrass), Enum.PartType.Ball, size)
	end
	for _, location in ipairs({ { 14, -42 }, { 16, 16 }, { 18, 54 }, { 17, 110 } }) do
		piece(garden, "PaleGardenFlower", V(0.55, 0.65, 0.55), CF(-location[1], 0.8, location[2]), COLORS.flowers)
	end

	-- Each right-side unit has its own gable, siding tone, divided windows,
	-- entry and deep white porch. Their fronts face the path, not the camera.
	for _, house in ipairs({
		{ "SageNear", 27, -33, 25, 18, 9, COLORS.sage, COLORS.roof },
		{ "MutedGreen", 29, -3, 24, 19, 10, COLORS.lightSage, COLORS.roof },
		{ "OatmealMiddle", 29, 27, 25, 19, 9, COLORS.oatmeal, COLORS.roofTan },
		{ "GrayGreenFar", 29, 59, 25, 18, 9, COLORS.sage, COLORS.roof },
		{ "CreamFar", 29, 91, 24, 17, 8, COLORS.beigeHouse, COLORS.roofTan },
	}) do
		addClapboardHouse(b, cottages, {
			name = house[1], x = -house[2], z = house[3], yaw = -90,
			width = house[4], height = house[5], rise = house[6],
			wall = house[7], roof = house[8], porchDepth = 7,
			doorSide = house[3] == -3 and -1 or 1,
		})
	end

	-- Tall flanking apartment walls extend well behind the row. Balcony
	-- recesses, floor plates and repeated white rails give the vertical scale.
	local farRail = Facades.RailStyle({ height = 3, spacing = 13, topHeight = 0.35, balusterSize = 0.25 })
	addBalconyTower(b, towers, {
		name = "LeftApartmentWall", x = 47, z = 48, yaw = 90,
		width = 190, floors = 15, floorH = 13, bays = 8,
		railStyle = farRail, distant = true,
	})
	addBalconyTower(b, towers, {
		name = "RightStackedBalconies", x = -67, z = 60, yaw = -90,
		width = 210, floors = 16, floorH = 12.5, bays = 7,
		railStyle = farRail, distant = true,
	})
	-- A more distant central wall closes the canyon through the hazy gap.
	addBalconyTower(b, towers, {
		name = "DistantEndTower", x = 2, z = 178, width = 97,
		floors = 15, floorH = 12.5, bays = 5, modern = true,
		color = COLORS.hazeTower, simpleModern = true,
	})
	-- Explicit zigzag circulation on the right backdrop, not a flat balcony
	-- texture. The runs alternate direction up the apartment face.
	for floor = 0, 9 do
		local y = 15 + floor * 16
		local x = -51 - (floor % 2) * 13
		piece(towers, "RightStairLanding", V(14, 0.55, 4.5), CF(x, y, 121), COLORS.tower, Enum.Material.Plaster)
		piece(towers, "RightStairRun", V(17.5, 0.5, 2.8), CF(-57.5, y + 6.4, 117) * CFrame.Angles(0, 0, (floor % 2 == 0 and -1 or 1) * math.rad(35)), COLORS.stairGray)
		piece(towers, "RightStairHandrail", V(17.5, 0.2, 0.2), CF(-57.5, y + 9.2, 115.4) * CFrame.Angles(0, 0, (floor % 2 == 0 and -1 or 1) * math.rad(35)), COLORS.trim)
	end

	-- Enclose the courtyard with the high gray tile ceiling and repeated
	-- small luminous fixtures; the original draft exposed an outdoor blue sky.
	local CEIL_Y = 215
	piece(ceiling, "SuspendedCeiling", V(180, 0.7, 290), CF(0, CEIL_Y + 0.35, 65), COLORS.ceilingDark)
	for _, x in ipairs({ -70, -42, -21, 0, 21, 42, 70 }) do
		piece(ceiling, "CeilingTBarLong", V(0.25, 0.1, 290), CF(x, CEIL_Y - 0.05, 65), COLORS.ceilingTile)
	end
	for z = -60, 170, 20 do
		piece(ceiling, "CeilingTBarCross", V(180, 0.1, 0.25), CF(0, CEIL_Y - 0.05, z), COLORS.ceilingTile)
		for _, x in ipairs({ -32, -10, 12, 34 }) do
			piece(ceiling, "SmallCeilingLight", V(2.3, 0.12, 2.3), CF(x, CEIL_Y - 0.11, z + 9), COLORS.fluorescent, Enum.Material.Neon)
		end
	end
	piece(ceiling, "HazyFarCanyonClosure", V(180, CEIL_Y, 1.5), CF(0, CEIL_Y / 2, 208), COLORS.hazeTower, Enum.Material.Plaster)
	return b.finish(root, 1, VIEW1_BUDGET, VIEW1_CAMERA)
end

-- View 2: long, low townhouse corridor with strong one-point perspective.
-- Estimated 12 wide x 11 tall x 120 long; townhouse fronts on the left (x = -6),
-- comparatively plain cream wall right. The walls are built around actual apertures.
function Facades.BuildCorridor(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local FABRIC = Enum.Material.Fabric

	local CW, CH, CL = 12, 11, 120
	local FLOOR_TOP = 0.2
	local TILE = 6

	local root = model("Level5_RefView2_Corridor", parent)
	local shell = model("Shell", root)
	local left = model("LeftFacades", root)
	local right = model("RightWall", root)

	-- Each of the 40 squares is a real tile. Alternating the rotation changes the
	-- Fabric grain direction as well as the tone; the base masks the fine gaps.
	piece(shell, "CarpetBase", V(CW, FLOOR_TOP, CL), CF(0, FLOOR_TOP / 2, -CL / 2), COLORS.carpet, FABRIC)
	for row = 0, CL / TILE - 1 do
		for col = 0, CW / TILE - 1 do
			local alt = (row + col) % 2 == 1
			local x = -CW / 2 + TILE * (col + 0.5)
			local z = -TILE * (row + 0.5)
			piece(shell, alt and "CarpetTileCrossGrain" or "CarpetTileLengthGrain", V(TILE - 0.05, 0.05, TILE - 0.05), CF(x, FLOOR_TOP + 0.025, z) * CFrame.Angles(0, alt and math.rad(90) or 0, 0), alt and COLORS.carpetAlt or COLORS.carpet, FABRIC)
		end
	end

	-- Three tile columns and thirty rows, with the transverse bars kept visible
	-- from the low camera. The light panels sit inside the central tile column.
	piece(shell, "Ceiling", V(CW, 0.5, CL), CF(0, CH + 0.25, -CL / 2), COLORS.ceilingTile)
	for _, x in ipairs({ -2, 2 }) do
		piece(shell, "CeilingTBar", V(0.25, 0.1, CL), CF(x, CH - 0.05, -CL / 2), COLORS.tBar)
	end
	for row = 1, CL / 4 - 1 do
		piece(shell, "CeilingTBarCross", V(CW, 0.1, 0.12), CF(0, CH - 0.05, -row * 4), COLORS.tBar)
	end
	-- Uneven fluorescent rhythm and two unlit bays from the reference ceiling.
	for i = 0, 9 do
		piece(shell, "FluorescentPanel", V(3.1, 0.09, 3.5), CF(0, CH - 0.055, -6 - i * 12), COLORS.fluorescent, Enum.Material.Neon)
	end
	piece(shell, "DarkCeilingBay", V(3.6, 0.08, 3.6), CF(-4, CH - 0.04, -42), COLORS.ceilingDark)
	piece(shell, "DarkCeilingBay", V(3.6, 0.08, 3.6), CF(4, CH - 0.04, -78), COLORS.ceilingDark)

	piece(shell, "EndWall", V(CW, CH, 0.6), CF(0, CH / 2, -CL - 0.3), COLORS.corridorEnd)

	-- Hanging EXIT sign facing the camera (+Z = Back face): housing + SurfaceGui + TextLabel.
	local exitSign = piece(shell, "ExitSignHanging", V(2.6, 1, 0.35), CF(0, CH - 0.9, -58), COLORS.exitHousing)
	if exitSign then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "ExitSignGui"
		gui.Face = Enum.NormalId.Back
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		local label = Instance.new("TextLabel")
		label.Name = "ExitText"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "EXIT"
		label.TextColor3 = COLORS.exitRed
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.Parent = gui
		gui.Parent = exitSign
		b.extra(2)
	end
	-- Distant EXIT sign on the end wall: housing + red Neon face.
	piece(shell, "ExitSignEnd", V(2.6, 1, 0.3), CF(0, 8.6, -CL + 0.15), COLORS.exitHousing)
	piece(shell, "ExitSignEndFace", V(2.2, 0.6, 0.06), CF(0, 8.6, -CL + 0.33), COLORS.exitRed, Enum.Material.Neon)

	-- Right-hand cream wall: solid piers and lintels surround three holes. The
	-- dark back walls are 2+ studs beyond the opening, never flush facade plates.
	local RIGHT_X = CW / 2 + 0.3
	local OPEN_H, OPEN_W = 7.5, 4.5
	local function rightPier(z0, z1)
		local span = z1 - z0
		piece(right, "CreamWallPier", V(0.6, CH, span), CF(RIGHT_X, CH / 2, (z0 + z1) / 2), COLORS.corridorWall)
		piece(right, "Baseboard", V(0.22, 0.6, span), CF(CW / 2 - 0.1, FLOOR_TOP + 0.3, (z0 + z1) / 2), COLORS.trim)
	end
	local cursor = -CL
	for _, z in ipairs({ -88, -56, -24 }) do
		local z0, z1 = z - OPEN_W / 2, z + OPEN_W / 2
		rightPier(cursor, z0)
		local top = FLOOR_TOP + OPEN_H
		piece(right, "CreamWallLintel", V(0.6, CH - top, OPEN_W), CF(RIGHT_X, (top + CH) / 2, z), COLORS.corridorWall)
		for _, side in ipairs({ -1, 1 }) do
			piece(right, "OpeningJamb", V(0.3, OPEN_H, 0.28), CF(CW / 2 - 0.22, FLOOR_TOP + OPEN_H / 2, z + side * (OPEN_W / 2 + 0.12)), COLORS.trim)
			piece(right, "OpeningReturn", V(1.6, OPEN_H, 0.12), CF(CW / 2 + 0.8, FLOOR_TOP + OPEN_H / 2, z + side * OPEN_W / 2), COLORS.trim)
		end
		piece(right, "OpeningHead", V(0.3, 0.28, OPEN_W + 0.5), CF(CW / 2 - 0.22, top, z), COLORS.trim)
		piece(right, "OpeningCeilingReturn", V(1.6, 0.12, OPEN_W), CF(CW / 2 + 0.8, top, z), COLORS.trim)
		piece(right, "RecessedRoomShadow", V(0.1, OPEN_H, OPEN_W), CF(CW / 2 + 2.5, FLOOR_TOP + OPEN_H / 2, z), COLORS.opening)
		cursor = z1
	end
	rightPier(cursor, 0)

	-- Six 20-stud house-front bays span the whole corridor, rather than ending
	-- short of the camera or at a blank stretch. Each has a door and window hole.
	local BAY = 20
	local bayColors = { COLORS.bayBeige, COLORS.baySlate, COLORS.bayLavender }
	local AWNING_P, AWNING_HALF, AWNING_RISE = 2.6, 2.3, 1.0
	local awningPitch = math.atan2(AWNING_RISE, AWNING_HALF)
	local awningSlope = math.sqrt(AWNING_HALF * AWNING_HALF + AWNING_RISE * AWNING_RISE)
	local LEFT_X = -CW / 2 - 0.3
	local function wallSpan(z0, z1, y0, y1, color, name)
		piece(left, name or "SidingWall", V(0.6, y1 - y0, z1 - z0), CF(LEFT_X, (y0 + y1) / 2, (z0 + z1) / 2), color)
	end
	local function sidingCourse(z0, z1, y, color)
		piece(left, "SidingCourse", V(0.08, 0.11, z1 - z0), CF(-CW / 2 + 0.04, y, (z0 + z1) / 2), color:Lerp(Color3.new(0, 0, 0), 0.2))
	end

	for k = 0, 5 do
		local cz = -BAY / 2 - k * BAY
		local color = bayColors[k % 3 + 1]
		local wz, wy, ww, wh = cz - 4, 5.6, 4, 4.4
		local dz, dw, doorTop = cz + 5, 3.2, 7.2
		local bay0, bay1 = cz - BAY / 2, cz + BAY / 2
		local w0, w1 = wz - ww / 2, wz + ww / 2
		local d0, d1 = dz - dw / 2, dz + dw / 2
		local windowBottom, windowTop = wy - wh / 2, wy + wh / 2

		-- A cut-out facade: three full piers, a window sill and lintel, and a
		-- door lintel. No solid wall is hidden behind the glazing or doorway.
		wallSpan(bay0, w0, FLOOR_TOP, CH, color)
		wallSpan(w0, w1, FLOOR_TOP, windowBottom, color, "WindowSillWall")
		wallSpan(w0, w1, windowTop, CH, color, "WindowHeadWall")
		wallSpan(w1, d0, FLOOR_TOP, CH, color)
		wallSpan(d0, d1, doorTop, CH, color, "DoorHeadWall")
		wallSpan(d1, bay1, FLOOR_TOP, CH, color)

		-- Reveal lines stop at openings; none bridge the door or window hole.
		sidingCourse(bay0, d0, 2.2, color)
		sidingCourse(d1, bay1, 2.2, color)
		for _, span in ipairs({ { bay0, w0 }, { w1, d0 }, { d1, bay1 } }) do
			sidingCourse(span[1], span[2], 4.6, color)
		end
		sidingCourse(bay0, bay1, 9.4, color)
		piece(left, "CornerBoard", V(0.3, CH, 0.45), CF(-CW / 2 + 0.22, CH / 2, bay1), COLORS.trim)

		-- The dark six-pane window is recessed behind the wall's actual hole.
		for _, side in ipairs({ -1, 1 }) do
			piece(left, "WindowJamb", V(0.26, wh + 0.45, 0.28), CF(-CW / 2 + 0.22, wy, wz + side * (ww / 2 + 0.1)), COLORS.trim)
			piece(left, "WindowReturn", V(1.15, wh, 0.12), CF(-CW / 2 - 0.35, wy, wz + side * ww / 2), COLORS.trim)
		end
		for _, y in ipairs({ windowBottom, windowTop }) do
			piece(left, "WindowRail", V(0.26, 0.28, ww + 0.5), CF(-CW / 2 + 0.22, y, wz), COLORS.trim)
		end
		piece(left, "WindowGlass", V(0.12, wh, ww), CF(-CW / 2 - 0.95, wy, wz), COLORS.glass)
		piece(left, "WindowMuntinV", V(0.12, wh, 0.15), CF(-CW / 2 - 0.86, wy, wz), COLORS.trim)
		for _, y in ipairs({ wy - 0.75, wy + 0.75 }) do
			piece(left, "WindowMuntinH", V(0.12, 0.15, ww), CF(-CW / 2 - 0.86, y, wz), COLORS.trim)
		end

		-- Real doorway aperture, with shallow white returns. The first and
		-- fourth doors stay dark and open; other panels sit well behind the trim.
		for _, side in ipairs({ -1, 1 }) do
			piece(left, "DoorJamb", V(0.28, doorTop - FLOOR_TOP, 0.32), CF(-CW / 2 + 0.22, (FLOOR_TOP + doorTop) / 2, dz + side * (dw / 2 + 0.12)), COLORS.trim)
			piece(left, "DoorReturn", V(1.45, doorTop - FLOOR_TOP, 0.12), CF(-CW / 2 - 0.7, (FLOOR_TOP + doorTop) / 2, dz + side * dw / 2), COLORS.trim)
		end
		piece(left, "DoorHead", V(0.28, 0.32, dw + 0.6), CF(-CW / 2 + 0.22, doorTop, dz), COLORS.trim)
		if k % 3 ~= 0 then
			piece(left, "RecessedDoorPanel", V(0.14, doorTop - FLOOR_TOP, dw), CF(-CW / 2 - 1.5, (FLOOR_TOP + doorTop) / 2, dz), COLORS.corridorDoor)
		end

		-- Small projecting gabled awning over the door: two dark slabs, ridge perpendicular to the wall.
		for _, side in ipairs({ -1, 1 }) do
			piece(left, "AwningSlab", V(AWNING_P, 0.25, awningSlope + 0.2), CF(-CW / 2 + AWNING_P / 2, 8.1 + AWNING_RISE / 2, dz + side * AWNING_HALF / 2) * CFrame.Angles(side * awningPitch, 0, 0), COLORS.roof, Enum.Material.Slate)
		end

		-- Warm shaded sconce between the window and the doorway.
		local lampZ = cz + 0.8
		piece(left, "SconceStem", V(0.4, 0.45, 0.18), CF(-CW / 2 + 0.55, 6.2, lampZ), COLORS.lampMetal)
		local bulb = piece(left, "SconceGlow", V(0.42, 0.3, 0.42), CF(-CW / 2 + 0.75, 6.4, lampZ), COLORS.lamp, Enum.Material.Neon)
		piece(left, "SconceShade", V(0.7, 0.6, 0.8), CF(-CW / 2 + 0.76, 6.65, lampZ), COLORS.trim)
		if bulb then
			local light = Instance.new("PointLight")
			light.Name = "WarmSconceLight"
			light.Color = COLORS.lamp
			light.Brightness = 0.55
			light.Range = 8
			light.Shadows = false
			light.Parent = bulb
			b.extra(1)
		end
	end

	return b.finish(root, 2, VIEW2_BUDGET, VIEW2_CAMERA)
end

-- View 3: bright atrium. Low shuttered cottage in front, stacked cream balcony + zigzag stair wall
-- behind, a rounded glass tower at the left rear, and a coffered luminous ceiling cue.
function Facades.BuildBrightAtrium(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local root = model("Level5_RefView3_BrightAtrium", parent)
	local houses = model("VariedForegroundCottageRow", root)
	local apartments = model("TieredWhiteApartmentWall", root)
	local modernTower = model("ManyWindowTowerAtLeft", root)
	local coffer = model("CofferedTileCeiling", root)
	local court = model("SmallFrontGardens", root)

	-- The small fronts are distinct houses with tan, green and brown shingles;
	-- the apartment tiers are a separate plane behind their pitched roofs.
	for _, house in ipairs({
		{ "LeftGreenRoof", -42, 8, 22, 16, 8, COLORS.lightSage, COLORS.sageReveal, COLORS.shutter },
		{ "TanMiddle", -17, 5, 24, 18, 9, COLORS.oatmeal, COLORS.roofTan, nil },
		{ "BrownMiddle", 11, 8, 24, 17, 9, COLORS.brownHouse, COLORS.roofTan, COLORS.shutter },
		{ "RightOliveRoof", 39, 4, 27, 19, 10, COLORS.oliveGray, COLORS.roof, COLORS.shutter },
	}) do
		addClapboardHouse(b, houses, {
			name = house[1], x = -house[2], z = house[3],
			width = house[4], height = house[5], rise = house[6],
			wall = house[7], roof = house[8], shutters = house[9],
			porchDepth = 6.5, doorSide = house[2] == -17 and -1 or 1,
		})
	end
	piece(court, "CourtWalk", V(125, 0.25, 22), CF(-1, -0.14, -18), COLORS.path, Enum.Material.Concrete)
	for _, x in ipairs({ -43, -18, 12, 41 }) do
		piece(court, "FrontGardenBed", V(14, 0.3, 3.2), CF(-x, 0.05, -4.8), COLORS.soil, Enum.Material.Ground)
		for _, dx in ipairs({ -4, 0, 4 }) do
			local size = V(1.7, 1.8, 1.7)
			setShape(piece(court, "FloweringShrub", size, CF(-x + dx, 0.9, -4.8), COLORS.shrub, Enum.Material.LeafyGrass), Enum.PartType.Ball, size)
		end
	end

	local apartmentRail = Facades.RailStyle({ height = 3.1, spacing = 8, balusterSize = 0.22 })
	addBalconyTower(b, apartments, {
		name = "CreamStackedBalconies", x = -13, z = 63,
		width = 124, floors = 9, floorH = 12, bays = 6,
		color = COLORS.tower, railStyle = apartmentRail, distant = true,
	})
	-- Exposed switchback stairs in the right bay: usable-looking landings and
	-- crossing flights remain visibly separate from the balcony faces.
	for floor = 0, 8 do
		local y = 5 + floor * 12
		local side = floor % 2 == 0 and 1 or -1
		piece(apartments, "StairLanding", V(13, 0.6, 5), CF(-68, y, 54), COLORS.tower, Enum.Material.Plaster)
		piece(apartments, "ZigzagFlight", V(18.5, 0.48, 2.8), CF(-68, y + 5.8, 49) * CFrame.Angles(0, 0, -side * math.rad(40)), COLORS.stairGray)
		piece(apartments, "ZigzagHandrail", V(18.5, 0.2, 0.22), CF(-68, y + 8.4, 47.2) * CFrame.Angles(0, 0, -side * math.rad(40)), COLORS.trim)
		piece(apartments, "LandingFrontRail", V(13, 0.22, 0.24), CF(-68, y + 3.1, 51.3), COLORS.trim)
	end

	-- This is a many-windowed, modern rectangular tower, unlike the
	-- continuous curved balcony canyon in reference #9.
	addBalconyTower(b, modernTower, {
		name = "LeftManyWindowTower", x = 69, z = 73,
		width = 41, depth = 21, floors = 16, floorH = 10.8, bays = 6,
		modern = true, color = COLORS.towerWhite,
	})
	for floor = 0, 15 do
		piece(modernTower, "WhiteCornerGlazingBand", V(0.55, 7.5, 13), CF(89.8, 6 + floor * 10.8, 67), COLORS.trim)
	end

	-- Broad suspended-tile ceiling with thick coffer beams and luminous
	-- squares. Its comparatively bright cream tone is specific to this view.
	local CY, CX, CZ = 191, 4, 16
	piece(coffer, "CreamCeilingField", V(300, 0.8, 330), CF(CX, CY + 0.4, CZ), COLORS.ceilingTile)
	for x = -145, 145, 16 do
		piece(coffer, "CeilingTileBarLong", V(0.17, 0.11, 330), CF(x, CY - 0.06, CZ), COLORS.tBar)
	end
	for z = -142, 164, 17 do
		piece(coffer, "CeilingTileBarCross", V(300, 0.11, 0.17), CF(CX, CY - 0.06, z), COLORS.tBar)
	end
	for _, x in ipairs({ -65, 65 }) do
		piece(coffer, "DeepCofferLongBeam", V(3.5, 3.8, 330), CF(x, CY - 1.9, CZ), COLORS.cofferBeam)
	end
	for _, z in ipairs({ -50, 75 }) do
		piece(coffer, "DeepCofferCrossBeam", V(300, 3.8, 3.5), CF(CX, CY - 1.9, z), COLORS.cofferBeam)
	end
	for _, x in ipairs({ -110, -54, 0, 54, 110 }) do
		for _, z in ipairs({ -96, -27, 42, 111 }) do
			piece(coffer, "LuminousSquarePanel", V(6.7, 0.15, 6.7), CF(x, CY - 0.16, z), COLORS.fluorescent, Enum.Material.Neon)
		end
	end
	piece(coffer, "CreamAtriumClosure", V(300, CY, 1.5), CF(CX, CY / 2, 180), COLORS.tower, Enum.Material.Plaster)
	return b.finish(root, 3, VIEW3_BUDGET, VIEW3_CAMERA)
end

-- View 4: misty tower canyon. Steep dark-gabled two-story porch house in front of calm,
-- very tall cream shafts with narrow window runs and recessed balcony stacks fading into haze.
function Facades.BuildTowerCanyon(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local root = model("Level5_RefView4_TowerCanyon", parent)
	local homes = model("TwoStoreyPorchHomes", root)
	local towers = model("VeryTallPaleApartmentShafts", root)
	local borders = model("GardenBorders", root)
	local haze = model("HighMistyEnclosure", root)

	-- Three individually pitched porch homes establish the domestic scale.
	-- Their four-panel recessed openings, clapboard, rails and roofs are not
	-- shared with the very different rounded-tower or dense-gable sections.
	for _, house in ipairs({
		{ "GrayTaupeLeft", -37, 5, 28, 21, 13, COLORS.taupe, COLORS.shingle },
		{ "MutedCenter", -6, 3, 27, 20, 12, COLORS.brownHouse, COLORS.roof },
		{ "PaleRight", 25, 8, 27, 20, 12, COLORS.beigeHouse, COLORS.shingle },
	}) do
		addClapboardHouse(b, homes, {
			name = house[1], x = house[2], z = house[3],
			width = house[4], height = house[5], rise = house[6],
			wall = house[7], roof = house[8], porchDepth = 9,
		})
	end
	piece(borders, "SmallFrontLawn", V(115, 0.28, 42), CF(-5, -0.18, -23), COLORS.grass, Enum.Material.LeafyGrass)
	piece(borders, "FrontWalk", V(116, 0.18, 4), CF(-5, 0.04, -33), COLORS.path, Enum.Material.Concrete)
	for _, x in ipairs({ -46, -34, -22, -16, -4, 7, 17, 30, 41 }) do
		piece(borders, "StoneEdge", V(4.4, 0.4, 0.7), CF(x, 0.2, -11), COLORS.path)
		local size = V(2.5, 2.4, 2.5)
		setShape(piece(borders, "GardenShrub", size, CF(x, 1.05, -9), COLORS.shrub, Enum.Material.LeafyGrass), Enum.PartType.Ball, size)
	end

	-- Separate tall cream shafts sit immediately behind the two-storey
	-- houses. Balconies are recessed tier by tier, not continuous bright
	-- horizontal strips; slim dark window runs punctuate the pale piers.
	local rail = Facades.RailStyle({ height = 3.1, balusters = 7, topHeight = 0.32, balusterSize = 0.22 })
	addBalconyTower(b, towers, {
		name = "NearLeftBalconyShaft", x = -47, z = 40,
		width = 48, floors = 21, floorH = 12.5, bays = 3,
		railStyle = rail, distant = true, projection = 3.4,
	})
	addBalconyTower(b, towers, {
		name = "NearRightBalconyShaft", x = 19, z = 52,
		width = 45, floors = 22, floorH = 12.5, bays = 3,
		railStyle = rail, distant = true, projection = 3.4,
	})
	addBalconyTower(b, towers, {
		name = "FarCentralVerticalShaft", x = 74, z = 106,
		width = 39, floors = 22, floorH = 12.5, bays = 3,
		modern = true, color = COLORS.hazeTower, simpleModern = true,
	})
	for floor = 0, 20 do
		local y = 8 + floor * 12.5
		for _, x in ipairs({ -67, -27 }) do
			piece(towers, "LeftNarrowWindow", V(1.3, 8.2, 0.2), CF(x, y, 39.45), COLORS.glass)
		end
		for _, x in ipairs({ 0, 38 }) do
			piece(towers, "RightNarrowWindow", V(1.3, 8.2, 0.2), CF(x, y, 51.45), COLORS.glass)
		end
	end

	-- Local translucent planes soften the upper silhouettes without
	-- changing global Lighting or masking the house fronts.
	local function veil(name, size, cf, transparency)
		local part = piece(haze, name, size, cf, COLORS.haze)
		if part then
			part.Transparency = transparency
			part.CastShadow = false
		end
	end
	veil("UpperMistNear", V(300, 205, 0.2), CF(8, 190, 25), 0.93)
	veil("UpperMistFar", V(320, 240, 0.2), CF(14, 180, 82), 0.91)
	veil("GrayDistantRoof", V(300, 0.7, 330), CF(0, 286, 48), 0)
	piece(haze, "FarMistBackdrop", V(320, 286, 1.5), CF(0, 143, 170), COLORS.hazeTower, Enum.Material.Plaster)
	piece(haze, "LeftPaleCanyonWall", V(2, 286, 310), CF(-135, 143, 49), COLORS.hazeTower, Enum.Material.Plaster)
	piece(haze, "RightPaleCanyonWall", V(2, 286, 310), CF(135, 143, 49), COLORS.hazeTower, Enum.Material.Plaster)
	return b.finish(root, 4, VIEW4_BUDGET, VIEW4_CAMERA)
end

return Facades
