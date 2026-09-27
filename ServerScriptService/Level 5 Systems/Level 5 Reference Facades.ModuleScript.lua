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
	corridorWall = Color3.fromRGB(224, 207, 177), -- warm cream right wall
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
-- View 2: camera sits by the near left frontage and looks obliquely down local -Z.
local VIEW2_CAMERA = { offset = Vector3.new(-3.5, 5.5, -0.5), target = Vector3.new(-29.5, 5, -120), fov = 70 }
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
	if o.porchGableRise then
		-- Section 01's nearest house has a peaked entry canopy; other shared
		-- cottage facades keep their existing low porch roof.
		local function entryPiece(parentModel, name, size, localCf, color, material, className)
			return p(parentModel, name, size, CF(doorX, 0, -porchDepth - 0.5) * localCf, color, material, className)
		end
		addFrontGable({ V = V, CF = CF, piece = entryPiece }, house, {
			cx = 0, baseY = deck + 9.5, width = 10.5, rise = o.porchGableRise,
			depth = 4.4, wallColor = wall, roofColor = roof, roofThick = 0.5,
		})
	end
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
	for k = 0, 13 do
		local z = -54 + k * 17
		local x = 12 - 0.22 * (z + 54) + 0.0005 * (z + 54) ^ 2
		local tangent = -0.22 + 0.001 * (z + 54)
		piece(garden, "CurvedPaleWalk", V(13.4, 0.12, 17.5), CF(x, 0.05, z) * CFrame.Angles(0, math.atan(tangent), 0), COLORS.path, Enum.Material.Concrete)
	end
	for _, patch in ipairs({
		{ -17, -46, 17, 13 }, { -20, -17, 20, 12 }, { -22, 16, 19, 14 },
		{ -25, 51, 21, 15 }, { -25, 84, 17, 14 }, { -24, 118, 18, 13 },
		{ 29, -25, 18, 14 }, { 30, 24, 20, 15 }, { 29, 79, 18, 14 },
	}) do
		piece(garden, "MulchedPlantingBed", V(patch[3], 0.32, patch[4]), CF(-patch[1], 0.05, patch[2]) * CFrame.Angles(0, math.rad(12), 0), COLORS.soil, Enum.Material.Ground)
	end
	local shrubs = {
		{ -17, -48, 3.4 }, { -22, -42, 2.8 }, { -25, -18, 3.6 }, { -16, -13, 2.5 },
		{ -19, 11, 3.0 }, { -27, 20, 4 }, { -20, 47, 3.1 }, { -30, 54, 4.2 },
		{ -19, 80, 3 }, { -27, 87, 3.8 }, { -21, 111, 2.8 }, { -28, 120, 3.4 },
		{ 28, -27, 2.8 }, { 33, -20, 3.4 }, { 31, 24, 2.8 }, { 25, 31, 3.5 },
		{ 31, 73, 3.3 }, { 24, 83, 2.8 },
	}
	for _, shrub in ipairs(shrubs) do
		local size = V(shrub[3], shrub[3] * 0.95, shrub[3])
		setShape(piece(garden, "Shrub", size, CF(-shrub[1], shrub[3] * 0.4, shrub[2]), COLORS.shrub, Enum.Material.LeafyGrass), Enum.PartType.Ball, size)
	end
	for _, tree in ipairs({ { 20, -39, 8 }, { 24, 40, 10 }, { -32, 27, 7 } }) do
		piece(garden, "GardenTreeStem", V(0.65, tree[3], 0.65), CF(-tree[1], tree[3] / 2, tree[2]), COLORS.brownHouse, Enum.Material.Wood)
		for _, branch in ipairs({ { -2, 0, 0 }, { 2, 0.7, 1 }, { 0, 2, -1 } }) do
			local radius = tree[3] * 0.54
			local foliageSize = V(radius, radius * 0.8, radius)
			setShape(piece(garden, "GardenTreeFoliage", foliageSize,
				CF(-tree[1] + branch[1], tree[3] + branch[2], tree[2] + branch[3]), COLORS.shrub,
				Enum.Material.LeafyGrass), Enum.PartType.Ball, foliageSize)
		end
	end
	for _, location in ipairs({ { 14, -42 }, { 16, 16 }, { 18, 54 }, { 17, 110 } }) do
		piece(garden, "PaleGardenFlower", V(0.55, 0.65, 0.55), CF(-location[1], 0.8, location[2]), COLORS.flowers)
	end

	-- The first three fronts use distinct porch depths, gables, openings and
	-- roof tones. The small distant pair use a cheaper silhouette builder.
	for _, house in ipairs({
		{ name = "SageNear", x = -27, z = -34, width = 28, height = 20, rise = 11,
			wall = COLORS.sage, roof = COLORS.roof, porchDepth = 8.5, doorSide = 1, porchGableRise = 3.4 },
		{ name = "OatmealPorch", x = -29, z = -3, width = 23, height = 17, rise = 7,
			wall = COLORS.oatmeal, roof = COLORS.roofTan, porchDepth = 5.2, doorSide = -1, shutters = COLORS.shutter },
		{ name = "MutedGreenMiddle", x = -31, z = 27, width = 26, height = 19, rise = 9,
			wall = COLORS.lightSage, roof = COLORS.roof, porchDepth = 7, doorSide = 1 },
	}) do
		house.yaw = -90
		addClapboardHouse(b, cottages, house)
	end
	local function distantCottage(name, x, z, width, height, rise, wall, roof)
		local house = model(name, cottages)
		local placement = CF(x, 0, z) * CFrame.Angles(0, math.rad(-90), 0)
		local function p(parentModel, partName, size, localCf, color, material, className)
			return piece(parentModel, partName, size, placement * localCf, color, material, className)
		end
		p(house, "ClapboardBody", V(width, height, 14), CF(0, height / 2, 7), wall)
		addFrontGable({ V = V, CF = CF, piece = p }, house, {
			cx = 0, baseY = height, width = width, rise = rise, depth = 14,
			wallColor = wall, roofColor = roof, roofThick = 0.55,
		})
		for _, windowX in ipairs({ -width * 0.26, width * 0.26 }) do
			p(house, "DarkWindow", V(4, 5.2, 0.16), CF(windowX, 8, -0.37), COLORS.glass)
			p(house, "WindowMullion", V(0.16, 5.2, 0.18), CF(windowX, 8, -0.5), COLORS.trim)
			p(house, "WindowHead", V(4.8, 0.35, 0.5), CF(windowX, 10.75, -0.4), COLORS.trim)
			p(house, "WindowSill", V(4.8, 0.35, 0.5), CF(windowX, 5.2, -0.4), COLORS.trim)
		end
		p(house, "PorchDeck", V(width, 1, 4.5), CF(0, 0.5, -2.25), COLORS.deck)
		p(house, "PorchRoof", V(width + 1, 0.5, 5), CF(0, 10.2, -2.5), roof, Enum.Material.Slate)
		for _, columnX in ipairs({ -width / 2 + 1, width / 2 - 1 }) do
			p(house, "PorchColumn", V(0.7, 9, 0.7), CF(columnX, 5.5, -4.4), COLORS.trim)
		end
		p(house, "EntryShadow", V(3.8, 7.5, 0.16), CF(0, 4.6, -0.4), COLORS.doorShadow)
		p(house, "PorchLamp", V(0.55, 0.75, 0.5), CF(3, 6.5, -0.65), COLORS.lamp, Enum.Material.Neon)
		return house
	end
	distantCottage("GrayGreenFar", -32, 59, 24, 17, 8, COLORS.sage, COLORS.roof)
	distantCottage("CreamFar", -32, 91, 22, 16, 7, COLORS.beigeHouse, COLORS.roofTan)

	-- A low cream frontage with narrow dark windows frames the left entrance.
	-- The real balcony canyon begins beyond it; a single striped tower could
	-- never reproduce the reference's near-wall / far-balcony transition.
	local leftNear = model("LeftNearCreamFrontage", towers)
	piece(leftNear, "UpperCreamWall", V(1.4, 207, 68), CF(47, 111.5, -23), COLORS.tower, Enum.Material.Plaster)
	for _, span in ipairs({ { -57, -43 }, { -15, 11 } }) do
		piece(leftNear, "GroundCreamPier", V(1.4, 8, span[2] - span[1]),
			CF(47, 4, (span[1] + span[2]) / 2), COLORS.tower, Enum.Material.Plaster)
	end
	piece(leftNear, "CoveredPassageShadow", V(0.16, 7.5, 28), CF(49, 3.75, -29), COLORS.doorShadow)
	piece(leftNear, "CoveredPassageCanopy", V(7, 0.7, 30), CF(43.5, 8.1, -29), COLORS.trim)
	for _, floor in ipairs({ 0, 1, 2 }) do
		for _, z in ipairs({ -48, -34, -20, -6 }) do
			local y = 12 + floor * 8
			piece(leftNear, "NarrowWindowSurround", V(0.18, 6.9, 4.3), CF(46.17, y, z), COLORS.trim)
			piece(leftNear, "NarrowDarkWindow", V(0.2, 6.2, 3.5), CF(46.02, y, z), COLORS.glass)
			piece(leftNear, "WindowCrossbar", V(0.23, 0.15, 3.5), CF(45.88, y + 0.7, z), COLORS.trim)
		end
	end
	for floor = 0, 11 do
		for _, z in ipairs({ -40, -12 }) do
			local y = 45 + floor * 13
			piece(leftNear, "UpperNarrowWindowSurround", V(0.18, 6.9, 4.3), CF(46.17, y, z), COLORS.trim)
			piece(leftNear, "UpperNarrowDarkWindow", V(0.2, 6.2, 3.5), CF(46.02, y, z), COLORS.glass)
		end
	end
	for _, z in ipairs({ -55, 11 }) do
		piece(leftNear, "CreamCornerPier", V(1.8, 215, 0.8), CF(46.5, 107.5, z), COLORS.trim)
	end
	piece(leftNear, "CreamCornice", V(2.2, 0.8, 69), CF(46.5, 37.4, -23), COLORS.trim)

	local function railAlongZ(parentModel, name, x, y, z, length, outward, detailed)
		piece(parentModel, name .. "Top", V(0.44, 0.4, length), CF(x, y + 3.1, z), COLORS.trim)
		piece(parentModel, name .. "Bottom", V(0.3, 0.22, length), CF(x, y + 0.55, z), COLORS.trim)
		if detailed then
			for n = 1, math.floor(length / 9) - 1 do
				local postZ = z - length / 2 + length * n / math.floor(length / 9)
				piece(parentModel, name .. "Baluster", V(0.24, 2.45, 0.24), CF(x + outward * 0.1, y + 1.78, postZ), COLORS.trim)
			end
		end
	end

	local leftStack = model("LeftRecessedBalconyStacks", towers)
	piece(leftStack, "SetbackCreamCore", V(1.8, 202, 152), CF(65, 101, 88), COLORS.tower, Enum.Material.Plaster)
	for floor = 0, 14 do
		local y = 4 + floor * 13
		for _, bay in ipairs({ { 40, 61 }, { 116, 61 } }) do
			piece(leftStack, "LeftBalconyDarkRecess", V(0.16, 8.1, bay[2] - 4),
				CF(63.96, y + 4.6, bay[1]), COLORS.towerRecess)
			piece(leftStack, "LeftBalconyWindowMullion", V(0.2, 7.5, 0.25),
				CF(63.79, y + 4.6, bay[1]), COLORS.trim)
			piece(leftStack, "LeftBalconySlab", V(15, 0.7, bay[2]),
				CF(57, y, bay[1]), COLORS.tower, Enum.Material.Plaster)
			railAlongZ(leftStack, "LeftBalconyRail", 49.3, y + 0.35, bay[1], bay[2] - 1, -1, true)
		end
	end
	for _, z in ipairs({ 10, 78, 163 }) do
		piece(leftStack, "LeftVerticalShaftPier", V(3, 202, 2.2), CF(62.8, 101, z), COLORS.trim)
	end

	-- The opposite wall is a deeper three-stack apartment facade. Its nearest
	-- floors get real vertical balusters; small high tiers use two rail bands.
	local rightStack = model("RightTieredBalconyStacks", towers)
	piece(rightStack, "SetbackCreamCore", V(1.8, 205, 194), CF(-75, 102.5, 86), COLORS.tower, Enum.Material.Plaster)
	for floor = 0, 15 do
		local y = 4 + floor * 12.6
		for _, bay in ipairs({ { 18, 43 }, { 75, 43 }, { 132, 43 } }) do
			piece(rightStack, "RightBalconyDarkRecess", V(0.16, 7.6, bay[2] - 4),
				CF(-73.93, y + 4.4, bay[1]), COLORS.towerRecess)
			for _, offset in ipairs({ -6, 6 }) do
				piece(rightStack, "RightBalconyWindowMullion", V(0.2, 7.2, 0.25),
					CF(-73.75, y + 4.4, bay[1] + offset), COLORS.trim)
			end
			piece(rightStack, "RightBalconySlab", V(12.2, 0.7, bay[2]),
				CF(-68, y, bay[1]), COLORS.tower, Enum.Material.Plaster)
			railAlongZ(rightStack, "RightBalconyRail", -61.7, y + 0.35, bay[1], bay[2] - 1, 1, true)
			if floor % 4 == 1 then
				piece(rightStack, "WarmLandingWindow", V(0.2, 3, 2.4),
					CF(-73.78, y + 5, bay[1] + 8), COLORS.lamp, Enum.Material.Neon)
			end
		end
	end
	for _, z in ipairs({ -11, 47, 104, 160, 183 }) do
		piece(rightStack, "RightVerticalShaftPier", V(2.3, 205, 2.2), CF(-72.7, 102.5, z), COLORS.trim)
	end

	-- Paired railings and landings make each exposed flight read as a connected
	-- zigzag, instead of a detached diagonal stripe on the right backdrop.
	local stair = model("RightExteriorSwitchbackStairs", towers)
	local runLen = math.sqrt(18 * 18 + 16 * 16)
	local pitch = math.atan2(16, 18)
	for floor = 0, 9 do
		local y = 15 + floor * 16
		local startX = floor % 2 == 0 and -59 or -41
		local endX = floor % 2 == 0 and -41 or -59
		local sign = floor % 2 == 0 and 1 or -1
		piece(stair, "StairLanding", V(7.2, 0.55, 5.5), CF(startX, y, 121), COLORS.tower, Enum.Material.Plaster)
		local runCf = CF((startX + endX) / 2, y + 8, 121) * CFrame.Angles(0, 0, sign * pitch)
		piece(stair, "ConnectedStairRun", V(runLen, 0.6, 4.2), runCf, COLORS.stairGray)
		for _, side in ipairs({ -1, 1 }) do
			piece(stair, "SlopedHandrail", V(runLen, 0.25, 0.25),
				CF((startX + endX) / 2, y + 10.8, 121 + side * 2.2)
					* CFrame.Angles(0, 0, sign * pitch), COLORS.trim)
		end
		for step = 1, 3 do
			local t = step / 4
			piece(stair, "VisibleStairTread", V(3.8, 0.17, 4.2),
				CF(startX + (endX - startX) * t, y + 16 * t + 0.2, 121), COLORS.deck)
		end
	end

	-- The far termination is a staggered residential cluster, not a blue-glass
	-- office grid. Hazy cream colors and changing depth carry the long canyon.
	local farStack = model("StaggeredFarResidentialTowers", towers)
	local function distantBalconyShaft(name, x, z, width, floors, floorHeight, color)
		local shaft = model(name, farStack)
		local height = floors * floorHeight
		piece(shaft, "PaleTowerCore", V(width, height, 5), CF(x, height / 2, z + 2.5), color, Enum.Material.Plaster)
		for floor = 0, floors - 1 do
			local y = 3 + floor * floorHeight
			piece(shaft, "DistantDarkOpening", V(width - 5, floorHeight - 5, 0.15),
				CF(x, y + 3.8, z - 0.1), COLORS.towerRecess)
			piece(shaft, "DistantBalconySlab", V(width + 0.6, 0.6, 4.3), CF(x, y, z - 1.9), color)
			piece(shaft, "DistantRailTop", V(width, 0.27, 0.25), CF(x, y + 3.15, z - 4.1), COLORS.trim)
			piece(shaft, "DistantRailBottom", V(width, 0.2, 0.25), CF(x, y + 0.8, z - 4.1), COLORS.trim)
			if floor % 2 == 0 then
				local posts = math.floor(width / 8)
				for n = 1, posts - 1 do
					piece(shaft, "DistantRailBaluster", V(0.23, 2.1, 0.23),
						CF(x - width / 2 + width * n / posts, y + 1.95, z - 4.1), COLORS.trim)
				end
			end
		end
		for _, offset in ipairs({ -width / 2 + 1, 0, width / 2 - 1 }) do
			piece(shaft, "DistantCreamPier", V(1, height, 1.5), CF(x + offset, height / 2, z - 0.1), color)
		end
	end
	distantBalconyShaft("MiddleSetbackShaft", 7, 158, 51, 15, 12.5, COLORS.tower)
	distantBalconyShaft("LeftFarShaft", 48, 188, 51, 16, 11.9, COLORS.hazeTower)
	distantBalconyShaft("RightFarShaft", -33, 207, 59, 15, 12.1, COLORS.hazeTower)

	-- The very high warm-gray enclosure recedes beyond the staggered towers.
	-- The T-bars are subdued so the light points read through the distance.
	local CEIL_Y = 215
	piece(ceiling, "SuspendedCeiling", V(380, 0.7, 340), CF(20, CEIL_Y + 0.35, 70), Color3.fromRGB(137, 132, 128))
	for _, x in ipairs({ -74, -44, -18, 8, 34, 62, 82 }) do
		piece(ceiling, "CeilingTBarLong", V(0.16, 0.08, 340), CF(x, CEIL_Y - 0.05, 70), Color3.fromRGB(151, 147, 141))
	end
	for z = -60, 228, 24 do
		piece(ceiling, "CeilingTBarCross", V(380, 0.08, 0.16), CF(20, CEIL_Y - 0.05, z), Color3.fromRGB(151, 147, 141))
		for _, x in ipairs({ -41, -7, 26 }) do
			local drift = z % 48 == 0 and 3.5 or -2
			piece(ceiling, "SmallCeilingLight", V(2.7, 0.12, 2.7),
				CF(x + drift, CEIL_Y - 0.11, z + 10), COLORS.fluorescent, Enum.Material.Neon)
		end
	end
	piece(ceiling, "HazyFarCanyonClosure", V(380, CEIL_Y, 1.5), CF(20, CEIL_Y / 2, 239), COLORS.hazeTower, Enum.Material.Plaster)
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
	-- The first open doorway is seen obliquely; extend the ceiling over its
	-- recessed room so the upper-left edge cannot reveal the outdoor sky.
	piece(shell, "Ceiling", V(CW + 7, 0.5, CL + 4), CF(-2.5, CH + 0.25, -CL / 2 + 2), COLORS.ceilingTile)
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

	-- Right-hand cream wall: five narrower openings recede at a regular pace.
	-- White side returns lead to dark back walls, rather than flush dark plates.
	local RIGHT_X = CW / 2 + 0.3
	local OPEN_H, OPEN_W = 7.5, 3.8
	local function rightPier(z0, z1)
		local span = z1 - z0
		piece(right, "CreamWallPier", V(0.6, CH, span), CF(RIGHT_X, CH / 2, (z0 + z1) / 2), COLORS.corridorWall)
		piece(right, "Baseboard", V(0.22, 0.6, span), CF(CW / 2 - 0.1, FLOOR_TOP + 0.3, (z0 + z1) / 2), COLORS.trim)
	end
	-- A continuous dark wall catches oblique rays through every recess. Its
	-- lower edge extends below the floor for the low camera's sight lines.
	piece(right, "RecessedRoomShadow", V(0.1, CH + 6, CL + 60), CF(CW / 2 + 3.3, (CH - 6) / 2, -CL / 2 - 30), COLORS.opening)
	local cursor = -CL
	for _, z in ipairs({ -108, -84, -60, -36, -12 }) do
		local z0, z1 = z - OPEN_W / 2, z + OPEN_W / 2
		rightPier(cursor, z0)
		local top = FLOOR_TOP + OPEN_H
		piece(right, "CreamWallLintel", V(0.6, CH - top, OPEN_W), CF(RIGHT_X, (top + CH) / 2, z), COLORS.corridorWall)
		for _, side in ipairs({ -1, 1 }) do
			piece(right, "OpeningReturn", V(2.3, OPEN_H, 0.2), CF(CW / 2 + 1.15, FLOOR_TOP + OPEN_H / 2, z + side * OPEN_W / 2), COLORS.trim)
		end
		piece(right, "OpeningHead", V(0.3, 0.28, OPEN_W + 0.5), CF(CW / 2 - 0.22, top, z), COLORS.trim)
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
		local dz, dw = cz + 5, 3.2
		local doorTop = k == 0 and 8.4 or 7.2
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
		if k <= 1 then
			-- Extra close-range courses where the reference camera sees the siding.
			for _, y in ipairs({ 1.2, 3.1 }) do
				sidingCourse(bay0, d0, y, color)
				sidingCourse(d1, bay1, y, color)
			end
			sidingCourse(bay0, bay1, 8.8, color)
			if k == 0 then
				sidingCourse(bay0, bay1, 10.3, color)
			end
		end
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
			local returnDepth = k == 0 and 0.65 or 1.45
			local returnX = k == 0 and -CW / 2 - 0.3 or -CW / 2 - 0.7
			piece(left, "DoorReturn", V(returnDepth, doorTop - FLOOR_TOP, 0.12), CF(returnX, (FLOOR_TOP + doorTop) / 2, dz + side * dw / 2), COLORS.trim)
		end
		piece(left, "DoorHead", V(0.28, 0.32, dw + 0.6), CF(-CW / 2 + 0.22, doorTop, dz), COLORS.trim)
		if k == 0 then
			-- A whole recessed room back wall covers side rays through the near
			-- doorway, while the opening and its white returns remain in front.
			piece(left, "OpenDoorInteriorShadow", V(0.1, CH + 6, BAY + 12), CF(-CW / 2 - 2.7, (CH - 6) / 2, cz), COLORS.opening)
		elseif k % 3 ~= 0 then
			piece(left, "RecessedDoorPanel", V(0.14, doorTop - FLOOR_TOP, dw), CF(-CW / 2 - 1.5, (FLOOR_TOP + doorTop) / 2, dz), COLORS.corridorDoor)
		end

		-- The tall open foreground door is flush; later doors have dark gabled canopies.
		if k > 0 then
			for _, side in ipairs({ -1, 1 }) do
				piece(left, "AwningSlab", V(AWNING_P, 0.25, awningSlope + 0.2), CF(-CW / 2 + AWNING_P / 2, 8.1 + AWNING_RISE / 2, dz + side * AWNING_HALF / 2) * CFrame.Angles(side * awningPitch, 0, 0), COLORS.roof, Enum.Material.Slate)
			end
		end

		-- Warm shaded sconce between the window and the doorway.
		local lampZ = cz + 0.8
		piece(left, "SconceStem", V(0.4, 0.45, 0.18), CF(-CW / 2 + 0.55, 6.2, lampZ), COLORS.lampMetal)
		local bulb = piece(left, "SconceGlow", V(0.42, 0.3, 0.42), CF(-CW / 2 + 0.75, 6.4, lampZ), COLORS.lamp, Enum.Material.Neon)
		local shade = piece(left, "SconceShade", V(0.55, 0.84, 0.84), CF(-CW / 2 + 0.76, 6.65, lampZ) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(245, 223, 187), FABRIC)
		if shade and shade:IsA("Part") then
			shade.Shape = Enum.PartType.Cylinder
			shade.Transparency = 0.16
			shade.CastShadow = false
		end
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
