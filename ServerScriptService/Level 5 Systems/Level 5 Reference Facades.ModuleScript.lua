-- Level 5 Reference Facades
-- Decorative, non-colliding facade anchors that match the Level 5 rework reference views.
-- The corridor uses small local PointLights for its sconces; nothing touches Lighting or
-- adds paths/doors/gates you can walk through.
-- Every numeric dimension is an ESTIMATE (the source screenshot was not available); tune in Studio.

local Facades = {}

-- Descendant budgets = everything generated under each root Model (root itself excluded).
-- NOT INTEGRATED. Live baseline is 29,240 / 30,000 (hard cap, never raise it). All four anchors
-- together add 604 (-> ~29,844), so integration needs old-geometry consolidation first.
-- View 1: 3 sub-Models + 177 Parts (54 cottage, 36 porch, 86 tower, 1 marker) = 180.
-- View 2: 335 generated descendants (including 3 sub-Models, 40 carpet tiles,
-- 6 local PointLights, 1 SurfaceGui and 1 TextLabel). Build records the actual count.
-- View 3: 4 sub-Models + 140 Parts (52 cottage, 57 apartments, 16 round tower, 14 ceiling, 1 marker) = 144.
-- View 4: 3 sub-Models + 128 Parts (73 house, 51 towers, 3 haze, 1 marker) = 131.
local VIEW1_BUDGET = 180
local VIEW2_BUDGET = 350
local VIEW3_BUDGET = 160
local VIEW4_BUDGET = 160

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
}

-- Estimated reference cameras, each in its builder's local space.
-- View 1: origin = ground level at the center of the cottage front wall; cottage faces local -Z.
local VIEW1_CAMERA = { offset = Vector3.new(-10, 6, -48), target = Vector3.new(0, 20, 10), fov = 70 }
-- View 2: origin = floor at the corridor centerline, near end; the hall runs toward local -Z.
local VIEW2_CAMERA = { offset = Vector3.new(1, 5.5, -2), target = Vector3.new(0, 5, -120), fov = 70 }
-- View 3: origin = ground at the center of the cottage front wall; cottage faces local -Z.
local VIEW3_CAMERA = { offset = Vector3.new(8, 6, -50), target = Vector3.new(-6, 22, 20), fov = 70 }
-- View 4: same convention; low camera tilted up to stress tower height.
local VIEW4_CAMERA = { offset = Vector3.new(-14, 5, -40), target = Vector3.new(4, 40, 30), fov = 70 }

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

function Facades.BuildCourtyard(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local SMOOTH = Enum.Material.SmoothPlastic

	local root = model("Level5_RefView1_Courtyard", parent)
	local cottage = model("Cottage", root)
	local porch = model("Porch", root)
	local tower = model("Tower", root)

	-- Cottage shell (estimated 28 wide x 22 tall x 16 deep, two 11-stud stories) ----------
	local W, H, D = 28, 22, 16
	piece(cottage, "Body", V(W, H, D), CF(0, H / 2, D / 2), COLORS.sage)

	-- Siding course reveal lines: 10 courses at 2-stud spacing (est.)
	for i = 0, 9 do
		piece(cottage, "SidingCourse", V(W - 1.8, 0.18, 0.12), CF(0, 2 + i * 2, -0.06), COLORS.sageReveal)
	end

	for _, side in ipairs({ -1, 1 }) do
		piece(cottage, "CornerBoard", V(1, H, 0.5), CF(side * (W / 2 - 0.4), H / 2, -0.25), COLORS.trim)
	end
	piece(cottage, "EaveFrieze", V(W + 1, 1, 0.8), CF(0, H - 0.5, -0.3), COLORS.trim)

	-- Front gable (estimated 9 studs tall, ~33 degree pitch) ---------------------------
	local GH = 9
	local halfW = W / 2
	local pitch = math.atan2(GH, halfW)
	local slopeLen = math.sqrt(GH * GH + halfW * halfW)

	-- Two full-depth wedges form the triangular gable and the roof mass behind it.
	piece(cottage, "GableLeft", V(D, GH, halfW), CF(-halfW / 2, H + GH / 2, D / 2) * CFrame.Angles(0, math.rad(90), 0), COLORS.sage, SMOOTH, "WedgePart")
	piece(cottage, "GableRight", V(D, GH, halfW), CF(halfW / 2, H + GH / 2, D / 2) * CFrame.Angles(0, math.rad(-90), 0), COLORS.sage, SMOOTH, "WedgePart")

	-- Siding courses continue into the gable, shortening with the triangle.
	for _, h in ipairs({ 2, 4, 6 }) do
		piece(cottage, "GableCourse", V(W * (1 - h / GH) - 0.8, 0.18, 0.12), CF(0, H + h, -0.06), COLORS.sageReveal)
	end

	-- side = -1 (left slope) or 1 (right slope); offset pushes the piece out along the slope normal.
	local function slopeCF(side, offset, z)
		local nx, ny = side * math.sin(pitch), math.cos(pitch)
		return CF(side * halfW / 2 + nx * offset, H + GH / 2 + ny * offset, z) * CFrame.Angles(0, 0, -side * pitch)
	end

	for _, side in ipairs({ -1, 1 }) do
		piece(cottage, "RakeTrim", V(slopeLen + 1, 0.8, 0.6), slopeCF(side, 0.4, -0.3), COLORS.trim)
		piece(cottage, "RoofSlab", V(slopeLen + 2, 0.7, D + 1.5), slopeCF(side, 1.15, D / 2), COLORS.roof, Enum.Material.Slate)
	end
	piece(cottage, "RidgeCap", V(1.2, 0.6, D + 1.5), CF(0, H + GH + 1.15 / math.cos(pitch) + 0.3, D / 2), COLORS.roof, Enum.Material.Slate)
	piece(cottage, "GableVent", V(2.4, 3, 0.3), CF(0, H + 5.2, -0.15), COLORS.trim)

	-- Framed four-pane windows: 7 parts each (glass, head, sill, 2 jambs, 2 muntins) ----
	local function window(cx, cy, w, h)
		piece(cottage, "WindowGlass", V(w, h, 0.2), CF(cx, cy, -0.12), COLORS.glass)
		piece(cottage, "WindowHead", V(w + 1.6, 0.6, 0.6), CF(cx, cy + h / 2 + 0.3, -0.3), COLORS.trim)
		piece(cottage, "WindowSill", V(w + 1.4, 0.35, 0.9), CF(cx, cy - h / 2 - 0.18, -0.45), COLORS.trim)
		for _, side in ipairs({ -1, 1 }) do
			piece(cottage, "WindowJamb", V(0.5, h + 0.6, 0.5), CF(cx + side * (w / 2 + 0.25), cy, -0.25), COLORS.trim)
		end
		piece(cottage, "WindowMuntinV", V(0.2, h, 0.2), CF(cx, cy, -0.3), COLORS.trim)
		piece(cottage, "WindowMuntinH", V(w, 0.2, 0.2), CF(cx, cy, -0.3), COLORS.trim)
	end

	window(-7, 17, 4, 5.5) -- upper left
	window(5, 17, 4, 5.5) -- upper right, over the door
	window(-7, 5.5, 4, 6) -- lower left, behind the porch rail

	-- Recessed door (decorative slab only; not a functional door) --------------------
	local DOOR_X, DECK_TOP = 5, 1.5
	piece(cottage, "DoorRecessReveal", V(4.8, 8.1, 0.2), CF(DOOR_X, DECK_TOP + 4.05, -0.1), COLORS.doorShadow)
	piece(cottage, "DoorSlabDecor", V(3.6, 7.5, 0.2), CF(DOOR_X, DECK_TOP + 3.75, -0.2), COLORS.door)
	piece(cottage, "DoorHead", V(6, 0.6, 0.6), CF(DOOR_X, DECK_TOP + 8.4, -0.3), COLORS.trim)
	for _, side in ipairs({ -1, 1 }) do
		piece(cottage, "DoorJamb", V(0.6, 8.1, 0.6), CF(DOOR_X + side * 2.7, DECK_TOP + 4.05, -0.3), COLORS.trim)
	end

	-- Wall sconce beside the door (Neon glow only; no PointLight/SurfaceLight)
	piece(cottage, "SconcePlate", V(0.5, 1.2, 0.2), CF(DOOR_X + 4.2, 7, -0.1), COLORS.lampMetal)
	piece(cottage, "SconceLantern", V(0.6, 0.9, 0.6), CF(DOOR_X + 4.2, 7, -0.55), COLORS.lamp, Enum.Material.Neon)
	piece(cottage, "SconceCap", V(0.9, 0.25, 0.9), CF(DOOR_X + 4.2, 7.55, -0.55), COLORS.lampMetal)

	-- Deep porch (estimated 8 deep, full width, columns 8.5 tall) --------------------
	local PORCH_D = 8
	local COL_Z = -PORCH_D + 0.6
	piece(porch, "Deck", V(W + 0.6, DECK_TOP, PORCH_D), CF(0, DECK_TOP / 2, -PORCH_D / 2), COLORS.deck, Enum.Material.WoodPlanks)

	-- Columns leave the bay in front of the door open (1.3 .. 8.7), matching the existing layout.
	local columnXs = { -13.3, -6, 1.3, 8.7, 13.3 }
	for _, x in ipairs(columnXs) do
		piece(porch, "Column", V(0.9, 8.5, 0.9), CF(x, DECK_TOP + 4.25, COL_Z), COLORS.trim)
	end
	piece(porch, "Beam", V(W + 0.6, 1, 1), CF(0, 10.5, COL_Z), COLORS.trim)
	piece(porch, "Ceiling", V(W + 0.6, 0.3, PORCH_D), CF(0, 10.85, -PORCH_D / 2), COLORS.trim)
	-- Shed roof: ~7.8 degree fall from the wall (y 12.5) to the fascia (y 11.3)
	piece(porch, "PorchRoof", V(W + 1.4, 0.5, PORCH_D + 1.2), CF(0, 12.2, -PORCH_D / 2 - 0.3) * CFrame.Angles(math.rad(-7.8), 0, 0), COLORS.roof, Enum.Material.Slate)
	piece(porch, "Fascia", V(W + 1.4, 0.9, 0.3), CF(0, 11.4, -PORCH_D - 0.8), COLORS.trim)

	-- Picket rail: 5 bays x (top + bottom rail) + 16 pickets = 26 parts
	local function railBay(a, b, fixed, alongZ, pickets)
		local len = math.abs(b - a) - 0.9
		local mid = (a + b) / 2
		local function at(t, y)
			if alongZ then
				return CF(fixed, y, t)
			end
			return CF(t, y, fixed)
		end
		local function size(l, h, d)
			if alongZ then
				return V(d, h, l)
			end
			return V(l, h, d)
		end
		piece(porch, "RailBottom", size(len, 0.3, 0.3), at(mid, DECK_TOP + 0.6), COLORS.trim)
		piece(porch, "RailTop", size(len, 0.35, 0.5), at(mid, DECK_TOP + 3.1), COLORS.trim)
		for i = 1, pickets do
			local t = a + (b - a) * i / (pickets + 1)
			piece(porch, "Picket", V(0.3, 2.5, 0.3), at(t, DECK_TOP + 1.85), COLORS.trim)
		end
	end

	railBay(-13.3, -6, COL_Z, false, 4)
	railBay(-6, 1.3, COL_Z, false, 4)
	railBay(8.7, 13.3, COL_Z, false, 4)
	railBay(COL_Z, 0, -13.3, true, 2)
	railBay(COL_Z, 0, 13.3, true, 2)

	-- Cream balcony tower backdrop (estimated 84 wide x 90 tall, face at z = 42) -----
	-- Bounded rhythm: 5 balcony floors at 14-stud spacing, 4 pilasters.
	-- Parts: wall 1 + 5 x (recess + slab + rail 2 + 12 balusters) + 4 pilasters + cap 1 = 86.
	local TOWER_W, TOWER_H, TOWER_FACE = 84, 90, 42
	piece(tower, "TowerWall", V(TOWER_W, TOWER_H, 4), CF(0, TOWER_H / 2, TOWER_FACE + 2), COLORS.tower, Enum.Material.Plaster)
	for floor = 0, 4 do
		local y = 12 + floor * 14
		piece(tower, "BalconyRecess", V(TOWER_W - 8, 8, 0.4), CF(0, y + 4.5, TOWER_FACE - 0.1), COLORS.towerRecess)
		piece(tower, "BalconySlab", V(TOWER_W - 4, 0.8, 4), CF(0, y, TOWER_FACE - 2), COLORS.tower, Enum.Material.Plaster)
		-- White rail at the slab's front edge, standing on the slab top (y + 0.4).
		Facades.BuildBalconyRail(piece, tower, CF(0, y + 0.4, TOWER_FACE - 3.8), TOWER_W - 4, TOWER_RAIL_STYLE)
	end
	for _, x in ipairs({ -40, -13.3, 13.3, 40 }) do
		piece(tower, "Pilaster", V(2, TOWER_H - 4, 6.2), CF(x, (TOWER_H - 4) / 2, TOWER_FACE - 1), COLORS.tower, Enum.Material.Plaster)
	end
	piece(tower, "ParapetCap", V(TOWER_W + 2, 2, 5), CF(0, TOWER_H + 1, TOWER_FACE + 1.5), COLORS.tower, Enum.Material.Plaster)

	-- Reference camera marker (invisible) plus attributes on the root -----------------
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
	local PLASTER = Enum.Material.Plaster

	local root = model("Level5_RefView3_BrightAtrium", parent)
	local cottage = model("Cottage", root)
	local apartments = model("ApartmentWall", root)
	local roundTower = model("RoundTower", root)
	local ceiling = model("CofferedCeiling", root)

	-- Cottage (est. 22 wide, 12-stud eave, 8-stud gable rise, 6-stud porch) -> 52 parts:
	-- body 1 + courses 5 + corners 2 + gable 7 + attic window 4 + 2 shuttered windows 14 + door 2 + porch 17
	local W, H, D, DECK = 22, 12, 14, 1.2
	piece(cottage, "Body", V(W, H, D), CF(0, H / 2, D / 2), COLORS.oliveGray)
	for i = 1, 5 do
		piece(cottage, "SidingCourse", V(W - 1.6, 0.16, 0.12), CF(0, i * 2, -0.06), COLORS.oliveReveal)
	end
	for _, side in ipairs({ -1, 1 }) do
		piece(cottage, "CornerBoard", V(0.9, H, 0.5), CF(side * (W / 2 - 0.35), H / 2, -0.25), COLORS.trim)
	end
	addFrontGable(b, cottage, { cx = 0, baseY = H, width = W, rise = 8, depth = D, wallColor = COLORS.oliveGray, roofColor = COLORS.roofTan, roofThick = 0.6 })
	addWindow(b, cottage, 0, H + 3.6, 2.6, 3)
	for _, side in ipairs({ -1, 1 }) do
		addWindow(b, cottage, side * 6.2, 6, 3.6, 5, { sill = true, shutterColor = COLORS.shutter })
	end
	-- Centered door (decorative slab only; not a functional door).
	piece(cottage, "DoorFrame", V(4.2, 7.8, 0.2), CF(0, DECK + 3.9, -0.1), COLORS.trim)
	piece(cottage, "DoorSlabDecor", V(3.2, 7.2, 0.2), CF(0, DECK + 3.6, -0.2), COLORS.door)

	-- White porch: deck 1 + 4 columns + beam 1 + shed roof 1 + 2 rail bays x 5 = 17
	local PORCH_Z = -5.5
	piece(cottage, "PorchDeck", V(W + 1, DECK, 6), CF(0, DECK / 2, -3), COLORS.porchWhite, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -10.6, -2.8, 2.8, 10.6 }) do
		piece(cottage, "PorchColumn", V(0.8, 7.6, 0.8), CF(x, DECK + 3.8, PORCH_Z), COLORS.trim)
	end
	piece(cottage, "PorchBeam", V(W + 1, 0.8, 0.9), CF(0, DECK + 8, PORCH_Z), COLORS.trim)
	piece(cottage, "PorchRoof", V(W + 1.6, 0.4, 7.2), CF(0, 10.2, -3.2) * CFrame.Angles(math.rad(-10), 0, 0), COLORS.roofTan, Enum.Material.Slate)
	for _, bay in ipairs({ { -10.6, -2.8 }, { 2.8, 10.6 } }) do
		Facades.BuildBalconyRail(piece, cottage, CF((bay[1] + bay[2]) / 2, DECK, PORCH_Z), bay[2] - bay[1] - 0.8, PORCH_RAIL_STYLE)
	end

	-- Cream apartment wall (est. 72 wide x 60 tall, face z = 30) -> 57 parts:
	-- wall 1 + 4 tiers x (recess + slab + rail 9) + stair bay 12
	local APT_FACE = 30
	piece(apartments, "Wall", V(72, 60, 4), CF(6, 30, APT_FACE + 2), COLORS.tower, PLASTER)
	local tierYs = { 10, 22, 34, 46 }
	for _, y in ipairs(tierYs) do
		piece(apartments, "BalconyRecess", V(48, 7, 0.4), CF(-4, y + 4.2, APT_FACE - 0.1), COLORS.towerRecess)
		piece(apartments, "BalconySlab", V(48, 0.8, 4), CF(-4, y, APT_FACE - 2), COLORS.tower, PLASTER)
		Facades.BuildBalconyRail(piece, apartments, CF(-4, y + 0.4, APT_FACE - 3.8), 48, APT_RAIL_STYLE)
	end
	-- Exposed zigzag stair in the right bay (x 22..38): 4 landings + 4 flights x (stringer + handrail).
	local lows = { 0, 10, 22, 34 }
	for k, y in ipairs(tierYs) do
		piece(apartments, "StairLanding", V(16, 0.8, 5), CF(30, y, APT_FACE - 2.5), COLORS.tower, PLASTER)
		local rise = y - lows[k]
		local len = math.sqrt(14 * 14 + rise * rise)
		local tilt = CFrame.Angles(0, 0, (k % 2 == 1 and 1 or -1) * math.atan2(rise, 14))
		piece(apartments, "StairFlight", V(len, 0.6, 2.2), CF(30, lows[k] + rise / 2, APT_FACE - 6.1) * tilt, COLORS.stairGray)
		piece(apartments, "StairHandrail", V(len, 0.25, 0.25), CF(30, lows[k] + rise / 2 + 3, APT_FACE - 7.1) * tilt, COLORS.trim)
	end

	-- Rounded modern tower, left rear (est. radius 11, 70 tall) -> 16 parts:
	-- core 1 + 8 glass bands + 6 front-facing fins + crown 1
	local TX, TZ, R, TH = -46, 22, 11, 70
	local function verticalCylinder(name, height, radius, y, color)
		local size = V(height, radius * 2, radius * 2)
		return setShape(piece(roundTower, name, size, CF(TX, y, TZ) * CFrame.Angles(0, 0, math.rad(90)), color), Enum.PartType.Cylinder, size)
	end
	verticalCylinder("Core", TH, R, TH / 2, COLORS.towerWhite)
	for i = 0, 7 do
		verticalCylinder("GlassBand", 3.6, R + 0.15, 8 + i * 7.5, COLORS.glassBlue)
	end
	for _, deg in ipairs({ -75, -45, -15, 15, 45, 75 }) do
		local a = math.rad(180 + deg)
		piece(roundTower, "Fin", V(0.8, TH - 4, 1.4), CF(TX + (R + 0.4) * math.sin(a), TH / 2, TZ + (R + 0.4) * math.cos(a)) * CFrame.Angles(0, a, 0), COLORS.trim)
	end
	verticalCylinder("Crown", 1.5, R + 0.6, TH + 0.75, COLORS.trim)

	-- Coffered ceiling cue at y = 76 -> 14 parts: slab 1 + 4 beams (3x3 coffers) + 9 Neon squares
	local CEIL_Y, CX, CZ, CWID, CDEP = 76, -7, 5, 110, 70
	piece(ceiling, "CeilingSlab", V(CWID, 1, CDEP), CF(CX, CEIL_Y + 0.5, CZ), COLORS.ceilingTile)
	for _, s in ipairs({ -1, 1 }) do
		piece(ceiling, "CofferBeamZ", V(2.5, 2.5, CDEP), CF(CX + s * CWID / 6, CEIL_Y - 1.25, CZ), COLORS.cofferBeam)
		piece(ceiling, "CofferBeamX", V(CWID, 2.5, 2.5), CF(CX, CEIL_Y - 1.25, CZ + s * CDEP / 6), COLORS.cofferBeam)
	end
	for ix = -1, 1 do
		for iz = -1, 1 do
			piece(ceiling, "LuminousPanel", V(10, 0.2, 10), CF(CX + ix * CWID / 3, CEIL_Y - 0.1, CZ + iz * CDEP / 3), COLORS.fluorescent, Enum.Material.Neon)
		end
	end

	return b.finish(root, 3, VIEW3_BUDGET, VIEW3_CAMERA)
end

-- View 4: misty tower canyon. Steep dark-gabled two-story porch house in front of calm,
-- very tall cream shafts with narrow window runs and recessed balcony stacks fading into haze.
function Facades.BuildTowerCanyon(K, parent, frame)
	local b = newBuilder(K, frame)
	local V, CF = b.V, b.CF
	local model, piece = b.model, b.piece
	local PLASTER = Enum.Material.Plaster

	local root = model("Level5_RefView4_TowerCanyon", parent)
	local house = model("House", root)
	local towers = model("Towers", root)
	local haze = model("Haze", root)

	-- House (est. 24 wide, 20-stud eave, steep 13-stud gable ~47 deg, 9-stud porch) -> 73 parts:
	-- body 1 + courses 8 + gable courses 3 + corners 2 + frieze 1 + gable 7 + gable window 4
	-- + 2 upper windows 10 + lower window 5 + door 2 + lamp 2 + porch 23 + planting 5
	local W, H, D, DECK, RISE = 24, 20, 16, 1.5, 13
	piece(house, "Body", V(W, H, D), CF(0, H / 2, D / 2), COLORS.taupe)
	for i = 1, 8 do
		piece(house, "SidingCourse", V(W - 1.8, 0.16, 0.12), CF(0, i * 2.1, -0.06), COLORS.taupeReveal)
	end
	for _, h in ipairs({ 3, 6, 9 }) do
		piece(house, "GableCourse", V(W * (1 - h / RISE) - 0.8, 0.16, 0.12), CF(0, H + h, -0.06), COLORS.taupeReveal)
	end
	for _, side in ipairs({ -1, 1 }) do
		piece(house, "CornerBoard", V(1, H, 0.5), CF(side * (W / 2 - 0.4), H / 2, -0.25), COLORS.trim)
	end
	piece(house, "EaveFrieze", V(W + 1, 1, 0.8), CF(0, H - 0.5, -0.3), COLORS.trim)
	addFrontGable(b, house, { cx = 0, baseY = H, width = W, rise = RISE, depth = D, wallColor = COLORS.taupe, roofColor = COLORS.shingle, roofThick = 0.8 })
	addWindow(b, house, 0, H + 4.5, 3, 4.2)
	for _, side in ipairs({ -1, 1 }) do
		addWindow(b, house, side * 6, 15, 3.4, 5.2, { sill = true })
	end
	addWindow(b, house, -6, 5.8, 3.4, 5, { sill = true })

	-- Door (decorative slab only) and entry lamp (Neon glow; no light object).
	local DOOR_X = 5
	piece(house, "DoorFrame", V(4.2, 8, 0.2), CF(DOOR_X, DECK + 4, -0.1), COLORS.trim)
	piece(house, "DoorSlabDecor", V(3.2, 7.4, 0.2), CF(DOOR_X, DECK + 3.7, -0.2), COLORS.door)
	piece(house, "EntryLampGlow", V(0.6, 0.9, 0.6), CF(DOOR_X + 3.2, 7, -0.55), COLORS.lamp, Enum.Material.Neon)
	piece(house, "EntryLampCap", V(0.9, 0.3, 1.1), CF(DOOR_X + 3.2, 7.6, -0.55), COLORS.lampMetal)

	-- Deep porch: deck 1 + 5 square columns + beam 1 + roof 1 + fascia 1 + balustrades 14 (6 + 5 + 3) = 23.
	-- Entry bay 1.8 .. 8.2 stays open in front of the door.
	local PD = 9
	local COL_Z = -PD + 0.7
	piece(house, "PorchDeck", V(W + 0.6, DECK, PD), CF(0, DECK / 2, -PD / 2), COLORS.deck, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -11.4, -4.6, 1.8, 8.2, 11.4 }) do
		piece(house, "PorchColumn", V(1.1, 8.5, 1.1), CF(x, DECK + 4.25, COL_Z), COLORS.trim)
	end
	piece(house, "PorchBeam", V(W + 0.6, 0.9, 1.2), CF(0, 10.45, COL_Z), COLORS.trim)
	piece(house, "PorchRoof", V(W + 1.4, 0.5, PD + 1.6), CF(0, 11.15, -PD / 2 - 0.4) * CFrame.Angles(math.rad(-4.7), 0, 0), COLORS.shingle, Enum.Material.Slate)
	piece(house, "PorchFascia", V(W + 1.4, 0.8, 0.3), CF(0, 10.8, -PD - 1.35), COLORS.trim)
	for _, bay in ipairs({ { -11.4, -4.6 }, { -4.6, 1.8 }, { 8.2, 11.4 } }) do
		Facades.BuildBalconyRail(piece, house, CF((bay[1] + bay[2]) / 2, DECK, COL_Z), bay[2] - bay[1] - 1.1, BALUSTRADE_STYLE)
	end

	-- Small planted borders flanking the entry: 2 beds + 3 round shrubs.
	local BED_Z = -PD - 1.9
	piece(house, "PlantingBed", V(12.6, 0.8, 2.4), CF(-5.1, 0.4, BED_Z), COLORS.planting, Enum.Material.LeafyGrass)
	piece(house, "PlantingBed", V(2.8, 0.8, 2.4), CF(10, 0.4, BED_Z), COLORS.planting, Enum.Material.LeafyGrass)
	for _, x in ipairs({ -9, -5, -1 }) do
		setShape(piece(house, "Shrub", V(2.2, 2.2, 2.2), CF(x, 1.5, BED_Z), COLORS.shrub, Enum.Material.LeafyGrass), Enum.PartType.Ball, V(2.2, 2.2, 2.2))
	end

	-- Tower shafts -> 51 parts. Detailed shaft = body 1 + 2 window runs + recess column 1 + 10 tiers x 2 bands = 24.
	local function shaft(cx, faceZ, w, h)
		piece(towers, "ShaftBody", V(w, h, 20), CF(cx, h / 2, faceZ + 10), COLORS.tower, PLASTER)
		local runH = h - 24
		for _, side in ipairs({ -1, 1 }) do
			piece(towers, "WindowRun", V(1.6, runH, 0.3), CF(cx + side * (w / 2 - 4), 12 + runH / 2, faceZ - 0.15), COLORS.glass)
		end
		piece(towers, "BalconyRecessStack", V(10, runH, 0.3), CF(cx, 12 + runH / 2, faceZ - 0.15), COLORS.towerRecess)
		for t = 0, 9 do
			Facades.BuildBalconyRail(piece, towers, CF(cx, 16 + t * 12, faceZ - 0.6), 10.4, TOWER_BAND_STYLE)
		end
	end
	shaft(-24, 34, 30, 160) -- left shaft (est.)
	shaft(16, 46, 26, 190) -- right shaft, set back (est.)
	-- Distant silhouette shaft seen through the gap: body + 2 window runs = 3.
	piece(towers, "DistantShaft", V(34, 220, 20), CF(52, 110, 100), COLORS.hazeTower, PLASTER)
	for _, x in ipairs({ 44, 60 }) do
		piece(towers, "DistantWindowRun", V(1.6, 190, 0.3), CF(x, 107, 89.85), COLORS.towerRecess)
	end

	-- Haze without global Lighting: 2 translucent veils + 1 overhead lid (no shadows) = 3.
	local function veil(name, size, cf, transparency)
		local part = piece(haze, name, size, cf, COLORS.haze)
		if part then
			part.Transparency = transparency
			part.CastShadow = false
		end
	end
	veil("HazeVeilNear", V(160, 80, 0.2), CF(0, 150, 30), 0.55)
	veil("HazeVeilFar", V(200, 140, 0.2), CF(10, 150, 70), 0.45)
	veil("HazeLid", V(220, 0.2, 160), CF(10, 200, 40), 0.35)

	return b.finish(root, 4, VIEW4_BUDGET, VIEW4_CAMERA)
end

return Facades
