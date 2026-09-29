-- Level 5 reference sections, built one at a time from assets/level5/rework20260927/reference-spec.md.
-- Geometry only: no gameplay, remotes, Lighting changes, entities or quests, and nothing is destroyed.
--
-- API:  Anomalies.Build(K, sectionId, anchorFrame?) -> result
--   K            the kit Level 5 Architecture builds (K.root, K.model, K.part, K.floor, K.material,
--                K.window, K.C, K.V, K.CF). K.part/K.floor apply the Architecture origin themselves.
--   sectionId    reference screenshot number. Implemented: 5, 6, 7, 8, 9 and 10.
--   anchorFrame  CFrame, defaults to CFrame.identity. Every authored position below is local to it;
--                the result's cameras, waypoints, zones and footprint are architecture-local
--                (anchor applied, origin NOT applied), the same space Landmark Districts returns.
--
-- Result: { Model, SectionId, PreviewCameras, Waypoints, Zones, EstimatedParts, EstimatedLights,
--           EstimatedInstances, Footprint }.
-- EstimatedParts is COUNTED, not guessed: every part goes through the part/floor/window wrappers in
-- kit() below, which increment the counter (window counts the children K.window actually added).
--
-- Collision intent. Every part carries attribute Level5CollisionIntent:
--   Walkable        grade, incline, stair flights and landings, bridge decks (CanCollide true)
--   Blocking        tower masses, house bodies, end walls (CanCollide true)
--   DropProtection  visible rails at open upper drops (CanCollide true)
--   DropGuard       invisible 7-stud barrier behind each DropProtection rail (CanCollide true);
--                   raycast filters must exclude these guards if sight checks need to pass through
--   Scenic          facade dressing, balconies, ceilings, lights (CanCollide false)
--
-- FIDELITY LIMITS (unverified; nothing here has been compared with the screenshots in Studio):
--   * The screenshots are not in this checkout. Every dimension is an interpretation of the written
--     spec, not a measurement: storey height 12, tower heights, canyon width, bridge heights and all
--     counts of bays, levels and houses are guesses to be checked at the matched preview camera.
--   * Part orientation for Cylinder/Ball shapes and every CFrame.Angles composition has been
--     reasoned about but not rendered. Expect to fix at least one rotation sign in Studio.
--   * No FOV is set on the preview cameras; the reference composition may need a narrower FOV.
--   * Haze, fog, dimness and colour temperature come from Lighting/Atmosphere, which this module
--     does not touch. "Dim grass court" and "dark canyon" are only as dim as the round's Lighting.
--   * Curves are faceted: rounded balcony corners are cylinder discs, the corner rails are two
--     chords per quarter, and the section 9 balcony noses are one long cylinder each.
--   * Section 5 stair flights and section 6 distant porch stairs are single tilted slabs (walkable
--     ramps); section 6 near porch stairs have stepped treads.
--     Section 7 has walkable stepped treads, not yet walked by an avatar; section 8's distant
--     stepped stair stack is scenic only.
--   * Unseen sides are invented: the tower backs, the incline's far end, the canyon's rear void,
--     the cottages' rear faces, section 6's far-side lane wall and section 7's side walls.
--   * Upper walkable surfaces (section 5 stairs, section 9 bridges) are NOT connected to any route.
--     Bridges are tagged Level5Reachability="Unwired". Balconies are scenic and not walkable.
--     Section 7's stair joins its own floor to its top landing, but no landing door leads anywhere.
--   * Section 6's large black opening is a recessed blind pocket, not a passable route.
--   * Section 7's torn wall edge is stepped rectangular chunks, not a sculpted fracture.
--   * The front edge (local z = 0) of every section is left open for a threshold to be added later.
--   * K.floor registers these lawns in Architecture's floor-surface ownership pass. Whether that
--     pass trims or re-materials them depends on when Build is called relative to the pass; untested.
--   * Instance budget: live Studio sat at 29,240 of a 30k descendant cap on 2026-09-27. A section
--     built here must REPLACE geometry it stands in for, never be added on top of it. Check the
--     returned EstimatedInstances against the headroom before calling Build.
local Anomalies = {}

Anomalies.ImplementedSections = table.freeze({5, 6, 7, 8, 9, 10})

local COLLIDES = {Walkable=true, Blocking=true, DropProtection=true, DropGuard=true, Scenic=false}

local PAL = {
	cream=Color3.fromRGB(226,214,186), creamDim=Color3.fromRGB(196,186,160), pale=Color3.fromRGB(236,230,212),
	white=Color3.fromRGB(240,238,228), pane=Color3.fromRGB(30,34,38), grid=Color3.fromRGB(10,10,10),
	warm=Color3.fromRGB(255,196,128), ceiling=Color3.fromRGB(170,166,146), ceilingGrid=Color3.fromRGB(122,121,110),
	panel=Color3.fromRGB(236,232,212), roof=Color3.fromRGB(46,44,44), door=Color3.fromRGB(228,224,210),
	sage=Color3.fromRGB(142,156,132), beige=Color3.fromRGB(196,182,152), slate=Color3.fromRGB(128,134,140),
	darkCeil=Color3.fromRGB(34,33,31), rib=Color3.fromRGB(52,50,46), void=Color3.fromRGB(6,6,7),
	cool=Color3.fromRGB(226,234,236), shrub=Color3.fromRGB(30,58,40), bridge=Color3.fromRGB(205,196,172),
}

local M = Enum.Material

-- Counting wrappers around the K API. All frames passed in are anchor-local.
local function kit(K, anchor)
	local V, CF = K.V, K.CF
	local counts = {parts=0, lights=0, models=0}
	local k = {V=V, CF=CF, counts=counts, anchor=anchor}

	function k.model(name, into)
		counts.models += 1
		return K.model(name, into)
	end

	function k.part(into, name, size, cf, color, mat, intent, className)
		intent = intent or "Scenic"
		local collide = COLLIDES[intent]
		assert(collide ~= nil, "Unknown collision intent " .. tostring(intent))
		local p = K.part(into, name, size, anchor * cf, color, mat, collide, className)
		p:SetAttribute("Level5CollisionIntent", intent)
		if intent == "DropGuard" then
			p.Transparency = 1; p.CastShadow = false
		end
		counts.parts += 1
		return p
	end

	function k.shaped(into, name, size, cf, color, mat, intent, shape)
		local p = k.part(into, name, size, cf, color, mat, intent, "Part")
		p.Shape = shape
		return p
	end

	function k.floor(into, name, x, y, z, w, d, color, frame)
		local p = K.floor(into, name, x, y, z, w, d, color, anchor * (frame or CFrame.identity))
		p:SetAttribute("Level5CollisionIntent", "Walkable")
		counts.parts += 1
		return p
	end

	-- K.window parents every piece it makes into `into`; classify and count each piece.
	function k.window(into, frame, w, h, lit, simple, intent)
		intent = intent or "Scenic"
		assert(COLLIDES[intent] ~= nil, "Unknown window collision intent " .. tostring(intent))
		local before = #into:GetChildren()
		local glass = K.window(into, anchor * frame, w, h, lit, simple)
		local children = into:GetChildren()
		for i = before + 1, #children do
			local p = children[i]
			if p:IsA("BasePart") then
				p:SetAttribute("Level5CollisionIntent", intent)
				p.CanCollide = COLLIDES[intent]
				p.CanQuery = COLLIDES[intent]
				p.CanTouch = false
				counts.parts += 1
			end
		end
		return glass
	end

	function k.bar(into, name, a, b, thick, color, intent)
		local len = (b - a).Magnitude
		if len < 1e-3 then return nil end
		return k.part(into, name, V(thick, thick, len), CFrame.lookAt((a + b) / 2, b), color or PAL.white, M.SmoothPlastic, intent)
	end

	function k.light(p, className, props)
		local l = Instance.new(className)
		for key, value in pairs(props) do l[key] = value end
		l.Parent = p
		counts.lights += 1
		return l
	end

	return k
end

-- A black gridded window facing `frame.LookVector`. Grid bars only where `grid` is set (near LOD).
local function gridWindow(k, into, frame, w, h, grid, muntinColor)
	local V, CF = k.V, k.CF
	k.part(into, "BlackGridPane", V(w, h, .25), frame, PAL.pane, M.Glass, "Scenic")
	if not grid then return end
	local line = muntinColor or PAL.grid
	k.part(into, "GridMuntin", V(.22, h, .22), frame * CF(0, 0, -.16), line, nil, "Scenic")
	for _, t in ipairs({-1/6, 1/6}) do
		k.part(into, "GridMuntin", V(w, .22, .22), frame * CF(0, h * t, -.16), line, nil, "Scenic")
	end
end

-- A tall arched opening: rectangle plus a cylinder disc for the round head. `base` is the bottom
-- centre on the facade, `outward` the facade normal.
local function archWindow(k, into, base, outward, w, h)
	local V, CF = k.V, k.CF
	local rectH = h - w / 2
	local rectCenter = base + V(0, rectH / 2, 0)
	local frame = CFrame.lookAt(rectCenter, rectCenter + outward)
	k.part(into, "ArchedOpening", V(w, rectH, .25), frame, PAL.pane, M.Glass, "Scenic")
	local headCenter = base + V(0, rectH, 0)
	-- Cylinder axis is local X; the yaw turns it onto the facade normal.
	k.shaped(into, "ArchedOpeningHead", V(.25, w, w), CFrame.lookAt(headCenter, headCenter + outward) * CFrame.Angles(0, math.pi / 2, 0), PAL.pane, M.Glass, "Scenic", Enum.PartType.Cylinder)
	k.part(into, "ArchMuntin", V(.22, h, .22), frame * CF(0, (h - rectH) / 2, -.16), PAL.grid, nil, "Scenic")
	for _, t in ipairs({-1/4, 0, 1/4}) do
		k.part(into, "ArchMuntin", V(w, .22, .22), frame * CF(0, rectH * t, -.16), PAL.grid, nil, "Scenic")
	end
end

-- A small pitched-roof house whose front faces the frame's -Z. Roof pitch is fixed at 45 degrees
-- so a rotated square can fill the gable. `sink` buries the base (used on the incline).
local function gabledHouse(k, into, name, frame, w, h, dep, wall, opts)
	opts = opts or {}
	local V, CF = k.V, k.CF
	local m = k.model(name, into)
	local sink = opts.sink or 0
	local rt2 = math.sqrt(2)
	k.part(m, "HouseBody", V(w, h + sink, dep), frame * CF(0, (h - sink) / 2, 0), wall, M.WoodPlanks, "Blocking")
	-- Rotated square: its lower half sits inside the body, its upper half is the gable triangle.
	-- Slightly shallower than the body so no face is coplanar with the body's front or back.
	k.part(m, "GableInfill", V(w / rt2, w / rt2, dep - .1), frame * CF(0, h, 0) * CFrame.Angles(0, 0, math.rad(45)), wall, M.WoodPlanks, "Blocking")
	local overhang = .9
	local length = (w / 2) * rt2 + overhang * rt2
	for _, s in ipairs({-1, 1}) do
		local x = s * (w / 4 + overhang / 2 + .2)
		k.part(m, "RoofPanel", V(length, .5, dep + 1.2), frame * CF(x, h + w / 4 - overhang / 2 + .2, 0) * CFrame.Angles(0, 0, -s * math.rad(45)), PAL.roof, M.Slate, "Blocking")
	end
	local dh = math.min(5, h * .7)
	local doorX = opts.doorX or -w * .22
	k.part(m, "FrontDoor", V(math.min(2.6, w * .28), dh, .16), frame * CF(doorX, dh / 2, -dep / 2 - .08), PAL.door, M.Wood, "Scenic")
	local winFrame = frame * CF(w * .22, h * .56, -dep / 2 - .1)
	if opts.detail then
		k.window(m, winFrame, 2.6, math.min(3.4, h * .45), opts.lit, true)
	else
		k.part(m, "HouseWindowPane", V(math.min(2.6, w * .28), math.min(3.4, h * .45), .16), winFrame, PAL.pane, M.Glass, "Scenic")
	end
	if opts.lit then
		local lamp = k.part(m, "WarmEntryLamp", V(.45, .7, .45), frame * CF(doorX + 1.9, dh + .4, -dep / 2 - .3), PAL.warm, M.Neon, "Scenic")
		if opts.pointLight then k.light(lamp, "PointLight", {Color=PAL.warm, Brightness=.8, Range=12, Shadows=false}) end
	end
	return m
end

local function aabb(anchor, minimum, maximum)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, x in ipairs({minimum.X, maximum.X}) do for _, y in ipairs({minimum.Y, maximum.Y}) do for _, z in ipairs({minimum.Z, maximum.Z}) do
		local p = anchor * Vector3.new(x, y, z)
		lo = lo:Min(p); hi = hi:Max(p)
	end end end
	return lo, hi
end

---------------------------------------------------------------------------------------------------
-- Section 5: sloped-house anomaly between rounded towers.
-- Local layout: camera side is z = -120 looking +Z. Court x -100..100, z -120..222, ceiling at 112.
-- Towers: inner facades at x = +-50, masses to +-98, z 45..175, seven 12-stud storeys.
-- Incline: 118-stud dark green slab at 34 degrees, yawed 29 degrees so it crosses the view
-- diagonally, rising from z ~58 to ~y 66 at the back; pale structural slab and ribs beneath.
---------------------------------------------------------------------------------------------------
local function buildSection5(k, K, root)
	local V, CF = k.V, k.CF
	local W, D, FRONT, CEIL, STOREY, STOREYS = 200, 222, -120, 112, 12, 7
	local TH = STOREY * STOREYS + 6
	local cameras, waypoints, zones = {}, {}, {}

	local grade = k.model("Grade", root)
	local courtLawn = k.floor(grade, "DimCourtLawn", 0, 0, (FRONT + D) / 2, W, D - FRONT, K.C.green)
	courtLawn.Color = Color3.fromRGB(25, 49, 34)
	k.part(grade, "CourtBackWall", V(W, CEIL, 2), CF(0, CEIL / 2, D + 1), PAL.creamDim, M.Plaster, "Blocking")
	for _, side in ipairs({-1, 1}) do
		k.part(grade, "CourtSideWall", V(2, CEIL, D - FRONT),
			CF(side * (W / 2 + 1), CEIL / 2, (FRONT + D) / 2), PAL.creamDim, M.Plaster, "Blocking")
	end
	local function framedTowerArch(into, base, normal, width, height)
		archWindow(k, into, base, normal, width, height)
		local straight = height - width / 2
		local frame = CFrame.lookAt(base + V(0, straight / 2, 0),
			base + V(0, straight / 2, 0) + normal)
		for _, edge in ipairs({-1, 1}) do
			k.part(into, "WhiteArchJamb", V(.28, straight, .24),
				frame * CF(edge * (width / 2 + .08), 0, -.2), PAL.white, M.Plaster, "Scenic")
		end
		k.part(into, "WhiteArchCenterMullion", V(.18, straight, .25),
			frame * CF(0, 0, -.23), PAL.white, M.Wood, "Scenic")
		for _, fraction in ipairs({-.2, .2}) do
			k.part(into, "WhiteArchCrossbar", V(width, .18, .25),
				frame * CF(0, straight * fraction, -.23), PAL.white, M.Wood, "Scenic")
		end
		local arcCenter = base + V(0, straight, 0) + normal * .22
		local function arcPoint(j)
			local a = math.pi * j / 6
			return arcCenter + frame.RightVector * (width / 2 * math.cos(a))
				+ V(0, width / 2 * math.sin(a), 0)
		end
		for j = 0, 5 do
			k.bar(into, "WhiteArchHeadCasing", arcPoint(j), arcPoint(j + 1), .25, PAL.white, "Scenic")
		end
	end

	-- Towers --------------------------------------------------------------------------------------
	local BAYS = {66, 88, 110, 132, 154}
	local BAL_Z0, BAL_Z1, RAIL_R = 55, 165, 5.7
	for _, side in ipairs({-1, 1}) do
		local t = k.model(side < 0 and "RoundedTower_Left" or "RoundedTower_Right", root)
		local face, out = side * 50, -side
		local outV = V(out, 0, 0)
		-- The camera looks along +Z, so world -X is screen right.
		local towerWall = side > 0 and Color3.fromRGB(220, 206, 173) or PAL.cream
		-- The near end is an actual cylindrical tower mass. Its front half remains
		-- visible between balcony decks, instead of relying on rounded slab corners
		-- pasted onto a long rectangular wall.
		k.part(t, "TowerMainMass", V(48, TH, 126), CF(side * 74, TH / 2, 112), towerWall, M.Plaster, "Blocking")
		-- The two rounded ends have different depths in the reference view; a larger
		-- right nose also breaks the mirrored arcade silhouette.
		local towerCx, towerCz = side * 74, 50
		local towerRadius = side < 0 and 28.5 or 25
		k.shaped(t, "RoundedTowerEndMass", V(TH, towerRadius * 2, towerRadius * 2),
			CF(towerCx, TH / 2, towerCz) * CFrame.Angles(0, 0, math.pi / 2),
			towerWall, M.Plaster, "Blocking", Enum.PartType.Cylinder)
		k.part(t, "TowerCornice", V(3, 1.6, 134), CF(face + out * 1.2, TH - .8, 110), PAL.white, nil, "Scenic")

		-- Balconies from storey 2 up, so none crosses the two-storey arched openings.
		-- A round deck and a segmented half-circle rail trace the cylindrical front.
		for s = 2, STOREYS - 1 do
			local y = s * STOREY
			local bal = k.model("Balcony_" .. s, t)
			k.part(bal, "BalconySlab", V(6, 1, BAL_Z1 - BAL_Z0), CF(face + out * 3, y - .5, (BAL_Z0 + BAL_Z1) / 2), PAL.pale, M.Plaster, "Scenic")
			local rx = face + out * RAIL_R
			k.bar(bal, "BalconyRailTop", V(rx, y + 3.4, BAL_Z0), V(rx, y + 3.4, BAL_Z1), .26, PAL.white, "Scenic")
			k.bar(bal, "BalconyRailBottom", V(rx, y + .55, BAL_Z0), V(rx, y + .55, BAL_Z1), .18, PAL.white, "Scenic")
			for z = BAL_Z0, BAL_Z1, 12 do
				k.part(bal, "BalconyRailPost", V(.22, 3.4, .22), CF(rx, y + 1.7, z), PAL.white, nil, "Scenic")
			end
			local deckRadius, railRadius, arcSteps = towerRadius + 1, towerRadius + 1.3, 8
			k.shaped(bal, "RoundedFrontBalconyDeck", V(1, deckRadius * 2, deckRadius * 2),
				CF(towerCx, y - .5, towerCz) * CFrame.Angles(0, 0, math.pi / 2),
				PAL.pale, M.Plaster, "Scenic", Enum.PartType.Cylinder)
			if side < 0 then
				k.shaped(bal, "WrappedWhiteBalconyFascia", V(.65, (deckRadius + .35) * 2, (deckRadius + .35) * 2),
					CF(towerCx, y - 1.33, towerCz) * CFrame.Angles(0, 0, math.pi / 2),
					PAL.white, M.Plaster, "Scenic", Enum.PartType.Cylinder)
			end
			local function arcPoint(j, railY)
				local a = math.pi * j / arcSteps
				return V(towerCx + side * railRadius * math.cos(a), railY,
					towerCz - railRadius * math.sin(a))
			end
			for j = 0, arcSteps - 1 do
				k.bar(bal, "RoundedFrontRailTop", arcPoint(j, y + 3.4), arcPoint(j + 1, y + 3.4), .26, PAL.white, "Scenic")
				k.bar(bal, "RoundedFrontRailBottom", arcPoint(j, y + .55), arcPoint(j + 1, y + .55), .18, PAL.white, "Scenic")
			end
			for j = 0, arcSteps do
				local p = arcPoint(j, y + 1.7)
				k.part(bal, "RoundedFrontRailPost", V(.22, 3.4, .22), CF(p), PAL.white, nil, "Scenic")
			end
			k.bar(bal, "SideToFrontRail", V(rx, y + 3.4, BAL_Z0),
				V(towerCx - side * railRadius, y + 3.4, towerCz), .26, PAL.white, "Scenic")
		end

		-- Windows: tall arched openings span storeys 0-1 on the middle three bays.
		local win = k.model("Windows", t)
		for s = 0, STOREYS - 1 do
			local y = s * STOREY
			for b, z in ipairs(BAYS) do
				local arched = b >= 2 and b <= 4
				if s == 0 and arched then
					archWindow(k, win, V(face + out * .1, .5, z), outV, 6.5, 19)
				elseif not (s == 1 and arched) then
					local c = V(face + out * .1, y + 2 + 3.4, z)
					gridWindow(k, win, CFrame.lookAt(c, c + outV), 5.2, 6.8, s <= 3, PAL.white)
				end
			end
			if s <= 2 then
				for _, z in ipairs({77, 143}) do
					local sconce = k.part(win, "WarmWallLight", V(.5, 1.4, .9), CF(face + out * .35, y + 7.5, z), PAL.warm, M.Neon, "Scenic")
					if s <= 1 then k.light(sconce, "PointLight", {Color=PAL.warm, Brightness=.8, Range=14, Shadows=false}) end
				end
			end
		end
		-- Three vertical window bays follow the faceted front: one on the near center,
		-- one on each shoulder. Ground arches span two storeys beneath gridded panes.
		local front = k.model("CameraFacingFacade", t)
		local frontOffset = towerRadius * .62
		local frontZ = towerCz - towerRadius * math.sqrt(1 - .62 ^ 2) - .3
		local diagonalNormalZ = -math.sqrt(1 - .62 ^ 2)
		local frontBays = {
			{bx=74 - frontOffset, z=frontZ, normal=V(out * .62, 0, diagonalNormalZ)},
			{bx=74, z=towerCz - towerRadius - .3, normal=V(0, 0, -1)},
			{bx=74 + frontOffset, z=frontZ, normal=V(-out * .62, 0, diagonalNormalZ)},
		}
		for bayIndex, bay in ipairs(frontBays) do
			local groundWidth = if side < 0 and bayIndex == 2 then 9.5 else 5.9
			framedTowerArch(front, V(side * bay.bx, .6, bay.z), bay.normal, groundWidth, 19)
			for s = 2, STOREYS - 1 do
				if side < 0 and bayIndex == 2 then
					framedTowerArch(front, V(side * bay.bx, s * STOREY + 1, bay.z),
						bay.normal, 9.5, 9.5)
				else
					local c = V(side * bay.bx, s * STOREY + 5.4, bay.z)
					local windowWidth = if side > 0 and bayIndex == 2 then 8 else 5.2
					gridWindow(k, front, CFrame.lookAt(c, c + bay.normal), windowWidth, 7.4, true, PAL.white)
				end
			end
		end
		local pierZ = towerCz - towerRadius * math.sqrt(1 - .43 ^ 2) - .2
		for _, bx in ipairs({74 - towerRadius * .43, 74 + towerRadius * .43}) do
			k.part(front, "WhiteVerticalPier", V(.55, TH, .65),
				CF(side * bx, TH / 2, pierZ), PAL.white, M.Plaster, "Scenic")
		end

		-- Five full switchback flights sit on the inner tower flank. Each ramp, its
		-- horizontal tread rhythm and its landing share the same endpoints, rather
		-- than crossing the new round front windows as disconnected diagonal bars.
		local st = k.model("SwitchbackStairs", t)
		local stairX, openX = side * 40, side * 36.8
		local nearZ, farZ = 58, 82
		for i = 1, 5 do
			local y0, y1 = (i - 1) * STOREY, i * STOREY
			local z0, z1 = nearZ, farZ
			if i % 2 == 0 then z0, z1 = farZ, nearZ end
			local dz = z1 - z0
			local len = math.sqrt(dz * dz + STOREY * STOREY)
			local angle = -math.atan2(STOREY, dz)
			local cz, cy = (z0 + z1) / 2, (y0 + y1) / 2
			k.part(st, "StairFlight", V(6, 1, len),
				CF(stairX, cy - .5, cz) * CFrame.Angles(angle, 0, 0), PAL.pale, M.Plaster, "Walkable")
			for step = 1, 8 do
				local tStep = step / 9
				k.part(st, "StairTreadEdge", V(6.2, .16, .38),
					CF(stairX, y0 + STOREY * tStep + .12, z0 + dz * tStep), PAL.white, nil, "Scenic")
			end
			k.bar(st, "StairHandrail", V(openX, y0 + 3.4, z0), V(openX, y1 + 3.4, z1), .26, PAL.white, "DropProtection")
			for post = 0, 4 do
				local fraction = post / 4
				k.part(st, "StairRailPost", V(.22, 3.4, .22),
					CF(openX, y0 + STOREY * fraction + 1.7, z0 + dz * fraction), PAL.white, nil, "Scenic")
			end
			k.part(st, "StairDropGuard", V(.3, 7, len),
				CF(openX - side * .25, cy + 3.5, cz) * CFrame.Angles(angle, 0, 0), nil, nil, "DropGuard")
			k.part(st, "StairLanding", V(6, 1, 5), CF(stairX, y1 - .5, z1), PAL.pale, M.Plaster, "Walkable")
			k.bar(st, "LandingRail", V(openX, y1 + 3.4, z1 - 2.5),
				V(openX, y1 + 3.4, z1 + 2.5), .26, PAL.white, "DropProtection")
			k.part(st, "LandingDropGuard", V(.3, 7, 5),
				CF(openX - side * .25, y1 + 3.5, z1), nil, nil, "DropGuard")
		end
		table.insert(waypoints, V(stairX, 3, nearZ))
	end

	-- Incline -------------------------------------------------------------------------------------
	local inc = k.model("SkewedHouseIncline", root)
	local THETA, L, IW = math.rad(34), 118, 38
	-- The lengthwise yaw shifts the high end toward the left of the camera image;
	-- its green face remains walkable while the pale belly reads as a separate mass.
	local base = CF(-21, 0, 58) * CFrame.Angles(0, math.rad(29), 0)
	local IF = base * CFrame.Angles(-THETA, 0, 0)
	local inclineLawn = k.floor(inc, "DarkGreenInclineLawn", 0, 0, L / 2, IW, L, K.C.green, IF)
	inclineLawn.Color = Color3.fromRGB(23, 44, 31)
	k.part(inc, "PaleStructuralUnderside", V(IW, 15, L),
		IF * CF(0, -8.7, L / 2), PAL.pale, M.Plaster, "Blocking")
	-- This projected edge is wide and deep enough to remain visible next to the
	-- green face at the reference camera, rather than becoming one white stripe.
	k.part(inc, "PaleProjectedSideSupport", V(18, 20, L + 2),
		IF * CF(-IW / 2 - 8, -11, L / 2), PAL.pale, M.Plaster, "Blocking")
	k.part(inc, "PaleSoffitLip", V(IW + 18, 3, L + 2),
		IF * CF(-7, -17.8, L / 2), PAL.creamDim, M.Plaster, "Blocking")
	-- Pale ribs under the slope and an end wall under the high edge (heights reach the slab soffit).
	local soffitDrop = 9.2 / math.cos(THETA)
	for _, s in ipairs({40, 80, 100}) do
		local h = s * math.sin(THETA) - soffitDrop + 1
		k.part(inc, "PaleSupportRib", V(IW - 4, h, 3), base * CF(0, h / 2, s * math.cos(THETA)), PAL.pale, M.Plaster, "Blocking")
	end
	local endH = L * math.sin(THETA) - 7
	k.part(inc, "PaleUndersideEndWall", V(IW, endH, 3), base * CF(0, endH / 2, L * math.cos(THETA) + 2), PAL.pale, M.Plaster, "Blocking")
	for _, sx in ipairs({-1, 1}) do
		k.part(inc, "InclineEdgeGuard", V(.3, 7, L), IF * CF(sx * (IW / 2 + .2), 3.5, L / 2), nil, nil, "DropGuard")
	end
	k.part(inc, "InclineTopGuard", V(IW, 7, .3), IF * CF(0, 3.5, L + .2), nil, nil, "DropGuard")

	-- Three larger fronts overlap near the high end. Each keeps most of the slope's
	-- pitch, then acquires its own roll/yaw and roof pitch, making the cluster visibly askew.
	local HOUSES = {
		{s=50, x=-11, w=39, h=28, depth=18, pitch=47, yaw=19,  lean=.82, roll=20,  col=PAL.beige},
		{s=66, x=12,  w=43, h=30, depth=20, pitch=36, yaw=-17, lean=.95, roll=-24, col=PAL.creamDim},
		{s=86, x=-3,  w=35, h=26, depth=17, pitch=42, yaw=9,   lean=.9,  roll=17,  col=PAL.sage},
	}
	for i, h in ipairs(HOUSES) do
		local hf = IF * CF(h.x, 0, h.s) * CFrame.Angles(THETA * (1 - h.lean), 0, 0)
			* CFrame.Angles(0, math.rad(h.yaw), 0) * CFrame.Angles(0, 0, math.rad(h.roll))
		local m = k.model("SkewedHouse_" .. i, inc)
		local pitch = math.rad(h.pitch)
		local rise = h.w / 2 * math.tan(pitch)
		k.part(m, "ClapboardHouseBody", V(h.w, h.h + 3, h.depth), hf * CF(0, (h.h - 3) / 2, 0), h.col, M.WoodPlanks, "Blocking")
		if i == 1 then
			-- This is the broad house face nearest the camera. Keep its photographed
			-- pale clapboard legible instead of letting the dark siding variant dominate.
			k.part(m, "PaleCameraFacingSiding", V(h.w - .35, h.h, .16),
				hf * CF(0, h.h / 2, -h.depth / 2 - .1),
				Color3.fromRGB(222, 212, 190), M.SmoothPlastic, "Scenic")
			for course = 2, h.h - 2, 2.5 do
				k.part(m, "ClapboardCourse", V(h.w - .5, .1, .12),
					hf * CF(0, course, -h.depth / 2 - .23), PAL.creamDim, M.Wood, "Scenic")
			end
		end
		-- Tapered horizontal courses fill the variable-pitch front gable without a
		-- generic 45-degree diamond protruding below its eave.
		for row = 1, 3 do
			local fraction = (row - .5) / 3
			k.part(m, "SteppedGableInfill", V(h.w * (1 - fraction), rise / 3 + .08, h.depth - .2),
				hf * CF(0, h.h + fraction * rise, 0), h.col, M.WoodPlanks, "Blocking")
		end
		local overhang = .9
		local roofLength = (h.w / 2 + overhang) / math.cos(pitch)
		for _, s in ipairs({-1, 1}) do
			k.part(m, "DistinctPitchRoof", V(roofLength, .5, h.depth + 1.2),
				hf * CF(s * (h.w / 4 + overhang / 2),
					h.h + (h.w / 4 - overhang / 2) * math.tan(pitch), 0)
					* CFrame.Angles(0, 0, -s * pitch), PAL.roof, M.Slate, "Blocking")
			k.bar(m, "WhiteGableRake",
				hf * V(0, h.h + rise, -h.depth / 2 - .55),
				hf * V(s * h.w / 2, h.h, -h.depth / 2 - .55), .28, PAL.white, "Scenic")
		end
		local doorX = i == 2 and 0 or -h.w * .22
		k.part(m, "WhitePanelDoor", V(3.1, 6.2, .2), hf * CF(doorX, 3.1, -h.depth / 2 - .14), PAL.door, M.Wood, "Scenic")
		for _, edge in ipairs({-1, 1}) do
			k.part(m, "FrontCornerBoard", V(.32, h.h, .3),
				hf * CF(edge * (h.w / 2 - .13), h.h / 2, -h.depth / 2 - .2), PAL.white, M.Wood, "Scenic")
			k.part(m, "DoorJamb", V(.23, 6.5, .24),
				hf * CF(doorX + edge * 1.68, 3.25, -h.depth / 2 - .25), PAL.white, M.Wood, "Scenic")
		end
		k.part(m, "DoorHead", V(3.65, .24, .25),
			hf * CF(doorX, 6.48, -h.depth / 2 - .25), PAL.white, M.Wood, "Scenic")
		k.part(m, "SecondStoreyBelt", V(h.w - .3, .3, .3),
			hf * CF(0, h.h * .52, -h.depth / 2 - .2), PAL.white, M.Wood, "Scenic")
		local frontWindows = if i == 1 then {
			{x=0, y=h.h * .4}, {x=h.w * .28, y=h.h * .4},
			{x=-h.w * .25, y=h.h * .75}, {x=0, y=h.h * .75},
			{x=h.w * .25, y=h.h * .75},
		} elseif i == 2 then {
			{x=-h.w * .28, y=h.h * .36}, {x=h.w * .28, y=h.h * .36},
			{x=-h.w * .28, y=h.h * .75}, {x=h.w * .28, y=h.h * .75},
		} else {
			{x=h.w * .22, y=h.h * .4},
			{x=-h.w * .2, y=h.h * .74},
			{x=h.w * .22, y=h.h * .74},
		}
		for _, window in ipairs(frontWindows) do
			local x, y, z = window.x, window.y, -h.depth / 2 - .22
			k.part(m, "DividedHousePane", V(3.8, 3.5, .16), hf * CF(x, y, z), PAL.pane, M.Glass, "Scenic")
			for _, edge in ipairs({-2.02, 2.02}) do
				k.part(m, "WindowSideTrim", V(.22, 3.85, .22), hf * CF(x + edge, y, z - .06), PAL.white, nil, "Scenic")
			end
			for _, edge in ipairs({-1.88, 1.88}) do
				k.part(m, "WindowHeadSill", V(4.3, .22, .22), hf * CF(x, y + edge, z - .06), PAL.white, nil, "Scenic")
			end
			k.part(m, "WindowMullion", V(.18, 3.5, .2), hf * CF(x, y, z - .07), PAL.white, nil, "Scenic")
			k.part(m, "WindowCrossbar", V(3.8, .18, .2), hf * CF(x, y, z - .07), PAL.white, nil, "Scenic")
		end
		-- Two storeys remain legible from oblique angles: divided side lights,
		-- corner boards, and a projecting roofed porch rather than a bare box.
		local visibleFlank = i == 2 and -1 or 1
		for _, y in ipairs({h.h * .32, h.h * .74}) do
			k.window(m,
				hf * CF(visibleFlank * (h.w / 2 + .14), y, 0)
					* CFrame.Angles(0, -visibleFlank * math.pi / 2, 0),
				3.8, 3.7, false, true)
		end
		local porchFront = -h.depth / 2 - 4.2
		k.part(m, "TiltedPorchLanding", V(h.w * .68, .48, 4.3),
			hf * CF(-h.w * .1, 1.6, -h.depth / 2 - 2.2), PAL.pale, M.WoodPlanks, "Scenic")
		k.part(m, "PorchCanopy", V(h.w * .76, .38, 5),
			hf * CF(-h.w * .1, 6.25, -h.depth / 2 - 2.3), PAL.roof, M.Slate, "Scenic")
		local porchHalf = h.w * .76 / 2
		local porchPitch = math.rad(8)
		local porchRise = porchHalf * math.tan(porchPitch)
		for _, slope in ipairs({-1, 1}) do
			k.part(m, "PorchGableRoof", V((porchHalf + .4) / math.cos(porchPitch), .32, 5.2),
				hf * CF(-h.w * .1 + slope * porchHalf / 2,
					6.38 + porchRise / 2, -h.depth / 2 - 2.3)
					* CFrame.Angles(0, 0, -slope * porchPitch), PAL.roof, M.Slate, "Scenic")
		end
		k.part(m, "PorchWhiteFascia", V(h.w * .76, .32, .32),
			hf * CF(-h.w * .1, 6.1, porchFront - .2), PAL.white, M.Wood, "Scenic")
		for _, px in ipairs({-h.w * .43, h.w * .23}) do
			k.part(m, "TiltedPorchColumn", V(.42, 4.5, .42),
				hf * CF(px, 3.85, porchFront), PAL.white, M.Wood, "Scenic")
		end
		k.bar(m, "TiltedPorchRail", hf * V(-h.w * .03, 4.1, porchFront),
			hf * V(h.w * .23, 4.1, porchFront), .24, PAL.white, "Scenic")
		if i == 1 then
			k.bar(m, "PorchLeftRail", hf * V(-h.w * .43, 4.1, porchFront),
				hf * V(-h.w * .3, 4.1, porchFront), .24, PAL.white, "Scenic")
			for _, px in ipairs({-h.w * .43, -h.w * .3}) do
				k.part(m, "PorchLeftRailPost", V(.2, 2.5, .2),
					hf * CF(px, 2.9, porchFront), PAL.white, nil, "Scenic")
			end
		end
		for _, px in ipairs({-h.w * .03, h.w * .06, h.w * .15, h.w * .23}) do
			k.part(m, "TiltedPorchRailPost", V(.2, 2.5, .2),
				hf * CF(px, 2.9, porchFront), PAL.white, nil, "Scenic")
		end
		for step = 1, 3 do
			k.part(m, "PorchEntryStep", V(5.3, .35, .85),
				hf * CF(doorX, 1.5 - step * .38, porchFront - step * .8),
				PAL.pale, M.WoodPlanks, "Scenic")
		end
		m:SetAttribute("SkewYaw", h.yaw); m:SetAttribute("SkewRoll", h.roll)
		m:SetAttribute("SlopeFractionKept", h.lean); m:SetAttribute("RoofPitchDegrees", h.pitch)
	end
	local inclineTop = IF * V(0, 0, L)

	-- Ceiling -------------------------------------------------------------------------------------
	local ceil = k.model("TiledCeiling", root)
	k.part(ceil, "CeilingSlab", V(W, 2, D - FRONT),
		CF(0, CEIL + 1, (FRONT + D) / 2), PAL.ceiling, M.Plaster, "Scenic")
	for x = -W / 2 + 20, W / 2 - 20, 20 do
		k.part(ceil, "CeilingGrid", V(.12, .12, D - FRONT),
			CF(x, CEIL - .06, (FRONT + D) / 2), PAL.ceilingGrid, nil, "Scenic")
	end
	for z = FRONT + 20, D - 2, 20 do k.part(ceil, "CeilingGrid", V(W, .12, .12), CF(0, CEIL - .06, z), PAL.ceilingGrid, nil, "Scenic") end
	local ix = 0
	for _, x in ipairs({-60, -20, 20, 60}) do
		for _, z in ipairs({-90, -50, -10, 30, 72, 114, 156, 198}) do
			ix += 1
			local panel = k.part(ceil, "RectCeilingLight", V(10, .3, 4), CF(x, CEIL - .2, z), PAL.panel, M.Neon, "Scenic")
			panel.Transparency = .3
			if ix % 3 == 1 then k.light(panel, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.panel, Brightness=.7, Range=45, Angle=90, Shadows=false}) end
		end
	end

	cameras = {
		{name="S05_Reference", position=V(0, 5, -65), lookAt=V(0, 44, 123)},
		{name="S05_LeftTowerAndStairs", position=V(-15, 7, -8), lookAt=V(-64, 36, 49)},
		{name="S05_InclineUnderside", position=V(37, 5, 22), lookAt=V(8, 31, 112)},
	}
	table.insert(waypoints, 1, V(0, 3, 10))
	table.insert(waypoints, 2, V(0, 3, 55))
	-- IF.LookVector points down-slope (local -Z), so this sits 6 studs below the top edge.
	table.insert(waypoints, inclineTop + V(0, 3, 0) + IF.LookVector * 6)
	table.insert(zones, {Name="S05_Court", Min=V(-W / 2, 0, FRONT), Max=V(W / 2, CEIL, D), CeilingHeight=CEIL,
		Description="Dim grass court, rounded cream towers with arched openings and switchbacks, skewed houses on a pale-bellied incline."})
	local footprint = {Min=V(-W / 2 - 4, 0, FRONT), Max=V(W / 2 + 4, CEIL + 2, D + 2), CeilingY=CEIL, GradeY=0,
		TowerHeight=TH, TowerFacadeX=50, InclineAngleDegrees=34, InclineTopY=inclineTop.Y, SkewedHouseCount=#HOUSES}
	return cameras, waypoints, zones, footprint
end

---------------------------------------------------------------------------------------------------
-- Section 9: dark monumental skybridge canyon.
-- Local layout: canyon x -60..60 between tower walls, z 0..520, dark ribbed ceiling at 240.
-- Eighteen balcony bands per wall with rounded projecting bays; three slim bridges at different levels;
-- lawn between planted berms; a tiny cottage cluster at the far end before a black void.
---------------------------------------------------------------------------------------------------
local function buildSection9(k, K, root)
	local V, CF = k.V, k.CF
	local W, D, CEIL, STOREY, LEVELS = 120, 520, 240, 12, 18
	local half = W / 2
	local cameras, waypoints, zones = {}, {}, {}

	local grade = k.model("Grade", root)
	k.floor(grade, "VastCanyonLawn", 0, 0, D / 2, 90, D, K.C.green)
	local run, rise = 15, 9
	local bermLen, phi = math.sqrt(run * run + rise * rise), math.atan2(rise, run)
	for _, side in ipairs({-1, 1}) do
		local bf = CF(side * 45, 0, D / 2) * CFrame.Angles(0, 0, side * phi)
		k.floor(grade, "SlopedPlantedEdge", side * bermLen / 2, 0, 0, bermLen, D, K.C.green, bf)
		k.part(grade, "BermToeHedge", V(1.5, 1.2, D), CF(side * 45.6, .6, D / 2), PAL.shrub, M.Grass, "Scenic")
		-- Shrubs only on the near half; the far half reads as bare slope at canyon scale.
		for z = 20, 145, 25 do
			k.shaped(grade, "BermShrub", V(3.6, 3.6, 3.6), CF(side * 52.5, 5.9, z), PAL.shrub, M.Grass, "Scenic", Enum.PartType.Ball)
		end
	end
	k.part(grade, "RearDarkVoid", V(W + 24, CEIL, 2), CF(0, CEIL / 2, D + 1), PAL.void, M.SmoothPlastic, "Blocking")

	-- Tower walls ---------------------------------------------------------------------------------
	local WARM = {{1, 52}, {2, 117}, {1, 182}, {3, 91}, {4, 30}, {2, 221}}
	local RECESS = Color3.fromRGB(17, 18, 15)
	for _, side in ipairs({-1, 1}) do
		local tw = k.model(side < 0 and "BalconyTowerWall_Left" or "BalconyTowerWall_Right", root)
		local face, out = side * half, -side
		k.part(tw, "TowerWallMass", V(12, CEIL, D), CF(side * (half + 6), CEIL / 2, D / 2), PAL.cream, M.Plaster, "Blocking")
		-- The camera-facing ends are actual rounded towers. Their stacked balcony discs
		-- project into the canyon, instead of relying on a rounded edge on a straight slab.
		for _, pod in ipairs({{z=75, radius=12}, {z=215, radius=9}}) do
			k.shaped(tw, "RoundedTowerEndMass", V(CEIL, pod.radius * 2, pod.radius * 2),
				CF(face, CEIL / 2, pod.z) * CFrame.Angles(0, 0, math.pi / 2),
				PAL.cream, M.Plaster, "Blocking", Enum.PartType.Cylinder)
		end
		archWindow(k, tw, V(face, .5, 62.8), V(0, 0, -1), 6.5, 18)
		for lvl = 1, LEVELS do
			local y = lvl * STOREY
			local band = k.model("BalconyBand_" .. lvl, tw)
			k.part(band, "RecessedWindowBand", V(.2, 6.5, D), CF(face + out * .1, y + 4.6, D / 2), RECESS, M.SmoothPlastic, "Scenic")
			k.part(band, "BalconyBandSlab", V(4.4, 1, D), CF(face + out * 2.2, y - .5, D / 2), PAL.pale, M.Plaster, "Scenic")
			-- Cylinder axis turned onto Z: the band's rounded nose runs the full canyon length.
			k.shaped(band, "CurvedBalconyNose", V(D, 2.4, 2.4), CF(face + out * 4.4, y - .7, D / 2) * CFrame.Angles(0, math.pi / 2, 0), PAL.pale, M.Plaster, "Scenic", Enum.PartType.Cylinder)
			k.part(band, "BalconyBandRail", V(.28, .28, D), CF(face + out * 4.9, y + 3.2, D / 2), PAL.white, nil, "Scenic")
			-- Real rail posts and apartment-bay piers where the primary camera can read them.
			-- The upper/far bands keep their continuous, lower-detail silhouette.
			if lvl <= 8 then
				for z = 18, 282, 24 do
					if math.abs(z - 75) > 20 and math.abs(z - 215) > 15 then
						k.part(band, "NearRunRailPost", V(.22, 3.1, .22),
							CF(face + out * 4.9, y + 1.7, z), PAL.white, nil, "Scenic")
					end
				end
				for z = 30, 270, 48 do
					if math.abs(z - 75) > 20 and math.abs(z - 215) > 15 then
						k.part(band, "ApartmentBayPier", V(.45, 6.5, .85),
							CF(face + out * .28, y + 4.6, z), PAL.pale, nil, "Scenic")
					end
				end
			end
			for _, pod in ipairs({{z=75, radius=18, chords=6, posts=true}, {z=215, radius=13, chords=4, posts=false}}) do
				local zc, radius = pod.z, pod.radius
				k.shaped(band, "RoundedTowerEndBalcony", V(1, radius * 2, radius * 2),
					CF(face, y - .44, zc) * CFrame.Angles(0, 0, math.pi / 2),
					PAL.pale, M.Plaster, "Scenic", Enum.PartType.Cylinder)
				local function railPoint(step)
					local a = -math.pi / 2 + step * math.pi / pod.chords
					return V(face + out * (4.9 + (radius - 5) * math.cos(a)),
						y + 3.2, zc + radius * math.sin(a))
				end
				local previous = railPoint(0)
				for step = 1, pod.chords do
					local current = railPoint(step)
					k.bar(band, "TowerEndCurvedRail", previous, current, .24, PAL.white, "Scenic")
					if pod.posts and step < pod.chords then
						k.part(band, "TowerEndRailPost", V(.22, 3.1, .22),
							CF(current.X, y + 1.65, current.Z), PAL.white, nil, "Scenic")
					end
					previous = current
				end
			end
			k.part(band, "RoundEndDarkWindow", V(6, 6.5, .2),
				CF(face, y + 4.6, 62.8), RECESS, M.SmoothPlastic, "Scenic")
		end
		for i, w in ipairs(WARM) do
			local lit = k.part(tw, "WarmLitWindow", V(.3, 5, 3.2), CF(face + out * .25, w[1] * STOREY + 4.6, w[2]), PAL.warm, M.Neon, "Scenic")
			if i <= 2 then k.light(lit, "PointLight", {Color=PAL.warm, Brightness=.9, Range=16, Shadows=false}) end
		end
	end

	-- Bridges -------------------------------------------------------------------------------------
	-- Deck ends meet the balcony noses (centre +-55.6, radius 1.2) rather than overlapping the band
	-- slabs, so no deck top is coplanar with a slab top.
	local BRIDGES = {{130, 8}, {265, 6}, {395, 4}}
	local span = 2 * (half - 4.4 - 1.2)
	local bridges = k.model("Skybridges", root)
	local bridgeLevels = {}
	for i, b in ipairs(BRIDGES) do
		local z, y = b[1], b[2] * STOREY
		table.insert(bridgeLevels, y)
		local m = k.model("Skybridge_" .. i, bridges)
		m:SetAttribute("Level5Reachability", "Unwired")
		local deck = k.part(m, "BridgeDeck", V(span, 1, 6), CF(0, y - .5, z), PAL.bridge, M.Plaster, "Walkable")
		deck:SetAttribute("Level5Reachability", "Unwired")
		k.part(m, "BridgeSoffitBeam", V(span, 1.6, 1.4), CF(0, y - 1.8, z), PAL.creamDim, nil, "Scenic")
		for _, sz in ipairs({-1, 1}) do
			k.part(m, "BridgeRailTop", V(span, .26, .26), CF(0, y + 3.4, z + sz * 2.85), PAL.white, nil, "DropProtection")
			k.part(m, "BridgeDropGuard", V(span, 7, .3), CF(0, y + 3.5, z + sz * 3.1), nil, nil, "DropGuard")
			if i <= 3 then
				k.part(m, "BridgeRailBottom", V(span, .18, .18), CF(0, y + .5, z + sz * 2.85), PAL.white, nil, "DropProtection")
				for x = -54, 54, 18 do
					k.part(m, "BridgeRailPost", V(.18, 3, .18), CF(x, y + 1.9, z + sz * 2.85), PAL.white, nil, "DropProtection")
				end
			end
		end
	end

	-- Ceiling -------------------------------------------------------------------------------------
	local ceil = k.model("DarkRibbedCeiling", root)
	k.part(ceil, "DarkCeilingSlab", V(W, 3, D), CF(0, CEIL + 1.5, D / 2), PAL.darkCeil, M.Concrete, "Scenic")
	for z = 13, D - 13, 26 do k.part(ceil, "CeilingRib", V(W, 3, 1.6), CF(0, CEIL - 1.5, z), PAL.rib, M.Concrete, "Scenic") end
	for _, x in ipairs({-30, 30}) do k.part(ceil, "CeilingSpineRib", V(1.6, 3, D), CF(x, CEIL - 1.5, D / 2), PAL.rib, M.Concrete, "Scenic") end
	local n = 0
	for z = 26, D - 26, 26 do
		n += 1
		local panel = k.part(ceil, "CentralCeilingLight", V(9, .3, 4.5), CF(0, CEIL - .2, z), PAL.cool, M.Neon, "Scenic")
		if n % 4 == 1 then k.light(panel, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.cool, Brightness=1.2, Range=60, Angle=100, Shadows=false}) end
	end

	-- The distant group is small against the canyon, yet its front walls and roofs must
	-- remain individually readable in the primary camera and a portrait crop.
	local cottages = k.model("DistantCottages", root)
	local COTTAGES = {
		{x=-39, z=394, w=19, h=9,  depth=9,  col=PAL.creamDim, yaw=3, roof=Color3.fromRGB(45, 46, 42), porch=false},
		{x=-14, z=388, w=23, h=11, depth=10, col=PAL.white, yaw=-4, roof=Color3.fromRGB(40, 43, 39), porch=true},
		{x=13,  z=401, w=21, h=10, depth=10, col=Color3.fromRGB(201, 205, 188), yaw=2, roof=Color3.fromRGB(52, 49, 43), porch=false},
		{x=39,  z=391, w=20, h=9,  depth=9,  col=PAL.pale, yaw=-3, roof=Color3.fromRGB(43, 46, 45), porch=true},
	}
	for i, c in ipairs(COTTAGES) do
		local houseFrame = CF(c.x, 0, c.z) * CFrame.Angles(0, math.rad(c.yaw), 0)
		local house = gabledHouse(k, cottages, "Cottage_" .. i, houseFrame,
			c.w, c.h, c.depth, c.col, {detail=true})
		for _, piece in ipairs(house:GetChildren()) do
			if piece.Name == "RoofPanel" then piece.Color = c.roof end
		end
		if c.porch then
			local frontZ = -c.depth / 2 - 2
			k.part(house, "CottagePorchDeck", V(c.w * .64, .35, 2.6),
				houseFrame * CF(-c.w * .05, .18, -c.depth / 2 - 1.3),
				PAL.pale, M.WoodPlanks, "Scenic")
			k.part(house, "CottagePorchCanopy", V(c.w * .64, .32, 2.6),
				houseFrame * CF(-c.w * .05, c.h * .69, -c.depth / 2 - 1.3),
				c.roof, M.Slate, "Scenic")
			for _, px in ipairs({-.3, .2}) do
				k.part(house, "CottagePorchColumn", V(.24, c.h * .69, .24),
					houseFrame * CF(c.w * px, c.h * .345, frontZ),
					PAL.white, M.Wood, "Scenic")
			end
		end
	end

	cameras = {
		{name="S09_Reference", position=V(0, 7, 4), lookAt=V(0, 95, 420)},
		{name="S09_BridgeTiersUpward", position=V(0, 4, 60), lookAt=V(0, 200, 150)},
		{name="S09_CottageScale", position=V(0, 4, 345), lookAt=V(0, 7, 425)},
	}
	waypoints = {V(0, 3, 10), V(0, 3, 150), V(0, 3, 300), V(0, 3, 390)}
	table.insert(zones, {Name="S09_Canyon", Min=V(-half, 0, 0), Max=V(half, CEIL, D), CeilingHeight=CEIL,
		Description="Dark skybridge canyon: curved balcony bands on both walls, bridge tiers into a black void, lawn with planted berms, tiny cottages."})
	local footprint = {Min=V(-half - 12, 0, 0), Max=V(half + 12, CEIL + 3, D + 2), CeilingY=CEIL, GradeY=0,
		CanyonWidth=W, CanyonLength=D, BalconyLevels=LEVELS, BridgeLevelsY=bridgeLevels, CottageCount=#COTTAGES}
	return cameras, waypoints, zones, footprint
end

---------------------------------------------------------------------------------------------------
-- Section 6: long dark lawn beside a dense gabled clapboard facade.
-- Local layout: camera side z = 0 looking +Z. Authored lane x -66..14, z 0..396; detailed facade is
-- mirrored to x = -26 so it occupies screen-right in the primary camera. Six 12-stud storeys
-- plus 22-stud gable bays frame a multi-level dark break in the near-middle wall.
-- Ceiling at 96. Near detail has more mullions, gables and actual stair treads than distant bays.
---------------------------------------------------------------------------------------------------
local function buildSection6(k, K, root)
	local V, CF = k.V, k.CF
	local LEN, CEIL, STOREY, STOREYS = 400, 96, 12, 6
	local FX, MASS, BAY, GD, LANE_X0, DECK = 14, 26, 22, 10, -66, 2.4
	local H = STOREY * STOREYS
	local VOID_Z, VOID_W, VOID_H = 5 * BAY, 4 * BAY, 66
	local SIDING, SIDING_ALT = Color3.fromRGB(172, 166, 150), Color3.fromRGB(150, 152, 146)
	local rt2, ov = math.sqrt(2), .9
	local NB = math.floor((LEN - 4) / BAY)
	-- Mirror authored X coordinates before the architecture anchor is applied. This keeps
	-- existing bay, gable, stair and balcony construction intact while putting its detailed
	-- face on the reference image's right-hand side. Two reflections preserve CFrame handedness.
	-- Keep the detailed wall in the established preview position while widening the lawn on
	-- its opposite side. Mirroring about the moving lane centre would shift every facade bay.
	local mirrorSum = -12
	local function mirrorV(p) return V(mirrorSum - p.X, p.Y, p.Z) end
	local function mirrorCF(cf)
		local r, u, b = cf.RightVector, cf.UpVector, -cf.LookVector
		return CFrame.fromMatrix(mirrorV(cf.Position),
			V(r.X, -r.Y, -r.Z), V(-u.X, u.Y, u.Z), V(-b.X, b.Y, b.Z))
	end
	local rawPart, rawFloor = k.part, k.floor
	k.part = function(into, name, size, cf, color, mat, intent, className)
		return rawPart(into, name, size, mirrorCF(cf), color, mat, intent, className)
	end
	k.floor = function(into, name, x, y, z, w, d, color, frame)
		return rawFloor(into, name, mirrorSum - x, y, z, w, d, color, frame and mirrorCF(frame))
	end

	local grade = k.model("Grade", root)
	k.floor(grade, "DarkGrassLane", (LANE_X0 + FX) / 2, 0, LEN / 2, FX - LANE_X0, LEN, K.C.green)
	k.part(grade, "LaneFarSideWall", V(2, CEIL, LEN), CF(LANE_X0 - 1, CEIL / 2, LEN / 2), PAL.creamDim, M.Plaster, "Blocking")

	local fac = k.model("DenseGabledFacade", root)
	-- Split the wall instead of painting a black rectangle onto an opaque mass.
	-- The dark recess has real side returns and depth; its back remains sealed.
	local voidZ0, voidZ1 = VOID_Z - VOID_W / 2, VOID_Z + VOID_W / 2
	k.part(fac, "ClapboardMassNear", V(MASS, H, voidZ0), CF(FX + MASS / 2, H / 2, voidZ0 / 2), SIDING, M.WoodPlanks, "Blocking")
	k.part(fac, "ClapboardMassFar", V(MASS, H, LEN - 4 - voidZ1), CF(FX + MASS / 2, H / 2, (voidZ1 + LEN - 4) / 2), SIDING, M.WoodPlanks, "Blocking")
	k.part(fac, "ClapboardMassAboveVoid", V(MASS, H - VOID_H, VOID_W), CF(FX + MASS / 2, (VOID_H + H) / 2, VOID_Z), SIDING, M.WoodPlanks, "Blocking")

	-- A gable facing -X whose base sits at `top`: rotated square (lower half buried) plus two roof
	-- panels whose ridge runs along X. Same 45-degree construction as gabledHouse, turned 90 degrees.
	local function sideGable(into, zc, top, wg, color, gx, depth, intent, pitchDegrees)
		gx, depth, intent = gx or FX + GD / 2 - .3, depth or GD, intent or "Blocking"
		local pitch = math.rad(pitchDegrees or 45)
		if intent == "Blocking" then
			-- Only the structural roofline can bury the lower half of this rotated square.
			k.part(into, "GableInfill", V(depth, wg / rt2, wg / rt2), CF(gx, top, zc) * CFrame.Angles(math.rad(45), 0, 0), color, M.WoodPlanks, intent)
		else
			k.part(into, "GableEaveTrim", V(depth + 1.2, .28, wg + 1), CF(gx, top, zc), PAL.white, nil, "Scenic")
		end
		local length = (wg / 2 + ov) / math.cos(pitch)
		for _, s in ipairs({-1, 1}) do
			k.part(into, "GableRoof", V(depth + 1.2, .5, length),
				CF(gx, top + (wg / 4 - ov / 2) * math.tan(pitch) + .2, zc + s * (wg / 4 + ov / 2 + .2))
					* CFrame.Angles(s * pitch, 0, 0), PAL.roof, M.Slate, intent)
		end
	end

	for i = 1, NB do
		local zc = (i - .5) * BAY
		local near, inVoid = zc < 182, math.abs(zc - VOID_Z) < VOID_W / 2
		local b = k.model("Bay_" .. i, fac)
		local top = H + (i % 2 == 0 and 8 or 0)
		local col = i % 2 == 0 and SIDING_ALT or SIDING
		if top > H and not inVoid then
			k.part(b, "RaisedBayBlock", V(GD, top - H, BAY - 1), CF(FX + GD / 2 - .3, (H + top) / 2, zc), col, M.WoodPlanks, "Blocking")
		end
		if not inVoid then sideGable(b, zc, top, BAY - 2, col) end

		-- Near bays have individual projecting clapboard fronts and pitched crowns,
		-- rather than flat windows pasted onto the large structural wall.
		for st = 1, STOREYS - 1 do
			local y = st * STOREY
			if not (inVoid and y < VOID_H) and (near or st % 2 == 1) then
				local faceX = near and FX - 5.1 or FX - .12
				if near then
					k.part(b, "ProjectingClapboardBay", V(5.2, 8.2, BAY - 2),
						CF(FX - 2.5, y + 6.1, zc), col, M.WoodPlanks, "Scenic")
				end
				local offsets = near and {-4.5, 4.5} or {0}
				for _, dz in ipairs(offsets) do
					k.part(b, "RecessedDarkWindow", V(.3, 6, 3.6), CF(faceX - .12, y + 5.5, zc + dz), PAL.pane, M.Glass, "Scenic")
					if near then
						k.part(b, "WindowSill", V(.8, .35, 4.4), CF(faceX - .4, y + 2.3, zc + dz), PAL.white, nil, "Scenic")
						k.part(b, "WindowHead", V(.8, .35, 4.4), CF(faceX - .4, y + 8.7, zc + dz), PAL.white, nil, "Scenic")
						for _, edge in ipairs({-1.9, 1.9}) do
							k.part(b, "WindowJamb", V(.8, 6.4, .3), CF(faceX - .4, y + 5.5, zc + dz + edge), PAL.white, nil, "Scenic")
						end
						k.part(b, "WindowMullion", V(.32, 5.8, .2), CF(faceX - .34, y + 5.5, zc + dz), PAL.white, nil, "Scenic")
						if st <= 3 then
							k.part(b, "WindowCrossbar", V(.32, .22, 3.8), CF(faceX - .35, y + 5.5, zc + dz), PAL.white, nil, "Scenic")
						end
					end
				end
				if near then sideGable(b, zc, y + 10.2, BAY - 2, col, FX - 4.7, 6.2, "Scenic", 30) end
			end
		end

		-- Ground entrance: each projecting porch has its own pitched gable and white stair rails.
		if not inVoid then
			k.part(b, "EntryDoor", V(.2, 7, 3.2), CF(FX - .1, DECK + 3.5, zc), PAL.door, M.Wood, "Scenic")
			k.part(b, "PorchDeck", V(5, 1, 9), CF(FX - 2.5, DECK - .5, zc), PAL.bridge, M.WoodPlanks, "Walkable")
			sideGable(b, zc, DECK + 8, 9.5, col, FX - 2.7, 6.5, "Scenic")
			local run = 4
			if near and i <= 4 then
				for step = 1, 4 do
					local stepH = DECK * step / 4
					k.part(b, "EntryStairTread", V(run / 4, stepH, 3.2),
						CF(FX - 5 - run + step - .5, stepH / 2, zc), PAL.pale, M.Plaster, "Walkable")
				end
			else
				k.part(b, "EntryStair", V(math.sqrt(run * run + DECK * DECK), 1, 3.2),
					CF(FX - 5 - run / 2, DECK / 2 - .5, zc) * CFrame.Angles(0, 0, math.atan2(DECK, run)),
					PAL.pale, M.Plaster, "Walkable")
			end
			if near then
				for _, s in ipairs({-1, 1}) do
					k.part(b, "PorchPost", V(.4, 8, .4), CF(FX - 5.2, DECK + 4, zc + s * 4.2), PAL.white, nil, "Scenic")
					k.bar(b, "PorchRail", V(FX - 5.2, DECK + 3, zc + s * 4.2), V(FX - 5.2, DECK + 3, zc + s * 1.8), .22, PAL.white, "Scenic")
					k.bar(b, "StairRail", V(FX - 9, 3.2, zc + s * 1.7), V(FX - 5.2, DECK + 3.2, zc + s * 1.7), .2, PAL.white, "Scenic")
				end
			else
				for _, s in ipairs({-1, 1}) do
					k.bar(b, "DistantStairRail", V(FX - 9, 3.2, zc + s * 1.7),
						V(FX - 5.2, DECK + 3.2, zc + s * 1.7), .18, PAL.white, "Scenic")
				end
			end
		end
	end

	-- The mass is actually cut away. All dark returns and the sealed back are inside
	-- the wall thickness, so the lawn sees a deep opening instead of a freestanding slab.
	local void = k.part(fac, "CentralBlackOpening", V(.4, VOID_H, VOID_W),
		CF(FX + MASS - .2, VOID_H / 2, VOID_Z), PAL.void, M.SmoothPlastic, "Blocking")
	void:SetAttribute("Level5Reachability", "SealedPanel")
	local pocketLeft, pocketRight = FX + 1, FX + MASS - 1
	local pocketWidth, pocketCenter = pocketRight - pocketLeft, (pocketLeft + pocketRight) / 2
	local pocketBack = k.part(fac, "CameraFacingBlackPocket", V(pocketWidth, VOID_H, .4),
		CF(pocketCenter, VOID_H / 2, voidZ1 - .25), PAL.void, M.SmoothPlastic, "Blocking")
	pocketBack:SetAttribute("Level5Reachability", "SealedPanel")
	k.part(fac, "BlackPocketSideReturn", V(.4, VOID_H, VOID_W),
		CF(pocketRight, VOID_H / 2, VOID_Z), PAL.void, M.SmoothPlastic, "Blocking")
	k.part(fac, "BlackPocketSoffit", V(pocketWidth, .4, VOID_W),
		CF(pocketCenter, VOID_H - .2, VOID_Z), PAL.void, M.SmoothPlastic, "Scenic")
	k.part(fac, "BlackPocketFloor", V(pocketWidth, .2, VOID_W),
		CF(pocketCenter, .1, VOID_Z), PAL.void, M.SmoothPlastic, "Walkable")
	k.part(fac, "BlackPocketEntryLintel", V(pocketWidth + .8, 1.2, .6),
		CF(pocketCenter, VOID_H + .6, voidZ0), PAL.white, nil, "Scenic")
	-- Dark internal landings make the break read as a deep stair shaft from the lawn;
	-- their alternating setbacks preserve the black void instead of filling it flat.
	for level = 1, 5 do
		local setback = level % 2 == 0 and 7 or 2
		k.part(fac, "DarkShaftLanding", V(pocketWidth - setback, .7, 7),
			CF(pocketCenter + setback / 2, level * STOREY - .35, voidZ1 - 7 - level * 2),
			Color3.fromRGB(18, 18, 18), M.Concrete, "Scenic")
		k.part(fac, "DarkShaftRiser", V(pocketWidth - setback, 2.2, .4),
			CF(pocketCenter + setback / 2, level * STOREY - 1.5, voidZ1 - 3 - level * 2),
			Color3.fromRGB(11, 11, 11), M.Concrete, "Scenic")
	end
	k.part(fac, "VoidDarkFloor", V(MASS, 1, VOID_W), CF(FX + MASS / 2, -.5, VOID_Z), PAL.void, M.SmoothPlastic, "Walkable")
	-- Leave the camera-facing end at voidZ0 open. A full-height near return would
	-- hide the black interior from the long-lawn viewpoint and read as a tower plate.
	k.part(fac, "VoidFarReturn", V(MASS, VOID_H, .35),
		CF(FX + MASS / 2, VOID_H / 2, voidZ1), PAL.void, M.Plaster, "Blocking")
	k.part(fac, "VoidDarkSoffit", V(MASS, .35, VOID_W), CF(FX + MASS / 2, VOID_H - .18, VOID_Z), PAL.void, M.SmoothPlastic, "Scenic")
	k.part(fac, "OpeningLintel", V(1.2, 1.2, VOID_W + 2), CF(FX - .6, VOID_H + .6, VOID_Z), PAL.white, nil, "Scenic")

	-- Individual balcony bays keep the white rail and gable cadence visible from the lawn.
	for st = 2, STOREYS - 1 do
		local y = st * STOREY
		local bal = k.model("BalconyRun_" .. st, fac)
		for i = 1, NB do
			local zc = (i - .5) * BAY
			local inVoid = math.abs(zc - VOID_Z) < VOID_W / 2
			if not (inVoid and y < VOID_H) then
				local near = zc < 182
				local railX = near and FX - 7.1 or FX - 4
				k.part(bal, "BalconySlab", V(near and 7.4 or 4.2, .85, BAY - 3),
					CF(near and FX - 3.7 or FX - 2.1, y - .43, zc), PAL.pale, M.Plaster, "Scenic")
				k.bar(bal, "BalconyRailTop", V(railX, y + 3.4, zc - 9), V(railX, y + 3.4, zc + 9), .24, PAL.white, "Scenic")
				k.bar(bal, "BalconyRailBottom", V(railX, y + .7, zc - 9), V(railX, y + .7, zc + 9), .16, PAL.white, "Scenic")
				for dz = -9, 9, near and 3 or 9 do
					k.part(bal, "BalconyRailPost", V(.2, 3, .2), CF(railX, y + 1.9, zc + dz), PAL.white, nil, "Scenic")
				end
			end
		end
	end

	-- The opposite edge is another house-faced wall in the reference, especially at
	-- the distant terminus. Give it a distinct, quieter rhythm instead of a blank slab.
	local opposite = k.model("OppositeGabledFacade", root)
	for i = 1, NB do
		local zc = (i - .5) * BAY
		local close = zc < 170
		local color = i % 3 == 0 and PAL.beige or SIDING_ALT
		local top = H + (i % 3 == 0 and 6 or 0)
		if close or i % 2 == 0 then
			sideGable(opposite, zc, top, BAY - 4, color, LANE_X0 - 2, 8, "Scenic")
		end
		for st = 1, STOREYS - 1 do
			if (close and st <= 4) or (not close and st % 2 == 0) then
				local y = st * STOREY
				for _, dz in ipairs(close and {-4.3, 4.3} or {0}) do
					k.part(opposite, "OppositeDarkWindow", V(.24, 6, 4),
						CF(LANE_X0 + .22, y + 5.5, zc + dz), PAL.pane, M.Glass, "Scenic")
					if close then
						k.part(opposite, "OppositeWindowJamb", V(.48, 6.5, .25),
							CF(LANE_X0 + .35, y + 5.5, zc + dz - 2), PAL.white, nil, "Scenic")
						k.part(opposite, "OppositeWindowJamb", V(.48, 6.5, .25),
							CF(LANE_X0 + .35, y + 5.5, zc + dz + 2), PAL.white, nil, "Scenic")
					end
				end
				if close then
					k.part(opposite, "OppositeWindowHead", V(.55, .36, 13.4),
						CF(LANE_X0 + .35, y + 8.65, zc), PAL.white, nil, "Scenic")
					k.part(opposite, "OppositeWindowSill", V(.55, .36, 13.4),
						CF(LANE_X0 + .35, y + 2.35, zc), PAL.white, nil, "Scenic")
					if st <= 3 then
						k.part(opposite, "OppositeBalconySlab", V(3.2, .55, 17),
							CF(LANE_X0 + 1.6, y - .28, zc), PAL.pale, M.Plaster, "Scenic")
						k.bar(opposite, "OppositeBalconyRail", V(LANE_X0 + 3.1, y + 3.2, zc - 8.2),
							V(LANE_X0 + 3.1, y + 3.2, zc + 8.2), .22, PAL.white, "Scenic")
						for dz = -8, 8, 4 do
							k.part(opposite, "OppositeRailPost", V(.2, 3, .2),
								CF(LANE_X0 + 3.1, y + 1.7, zc + dz), PAL.white, nil, "Scenic")
						end
					end
				end
			end
		end
	end

	-- Terminating facade across the lane's far end: three gables, windows, ground doors.
	local far = k.model("TerminatingFacade", root)
	local x0, x1 = LANE_X0, FX + MASS
	local FW, fxc = x1 - x0, (x0 + x1) / 2
	k.part(far, "FarClapboardWall", V(FW, H, 4), CF(fxc, H / 2, LEN - 2), SIDING_ALT, M.WoodPlanks, "Blocking")
	k.part(far, "FarCeilingReturn", V(FW, CEIL - H, 4),
		CF(fxc, (CEIL + H) / 2, LEN - 2), PAL.creamDim, M.Plaster, "Blocking")
	local wg = FW / 3 - 2
	for j = -1, 1 do
		local xj = fxc + j * FW / 3
		k.part(far, "FarGableInfill", V(wg / rt2, wg / rt2, 3.6), CF(xj, H, LEN - 2) * CFrame.Angles(0, 0, math.rad(45)), SIDING_ALT, M.WoodPlanks, "Blocking")
		local length = (wg / 2) * rt2 + ov * rt2
		for _, s in ipairs({-1, 1}) do
			k.part(far, "FarGableRoof", V(length, .5, 5.2), CF(xj + s * (wg / 4 + ov / 2 + .2), H + wg / 4 - ov / 2 + .2, LEN - 2) * CFrame.Angles(0, 0, -s * math.rad(45)), PAL.roof, M.Slate, "Blocking")
		end
		k.part(far, "FarDoor", V(3.2, 7, .2), CF(xj, 3.5, LEN - 4.1), PAL.door, M.Wood, "Scenic")
		for st = 1, STOREYS - 1 do
			for _, dx in ipairs({-4.5, 4.5}) do
				k.part(far, "FarDarkWindow", V(3.6, 6, .3), CF(xj + dx, st * STOREY + 5.5, LEN - 4.12), PAL.pane, M.Glass, "Scenic")
			end
		end
	end

	-- Ceiling: one row of rectangular panels over the lawn.
	local ceil = k.model("TiledCeiling", root)
	k.part(ceil, "CeilingSlab", V(FW, 2, LEN), CF(fxc, CEIL + 1, LEN / 2), PAL.ceiling, M.Plaster, "Scenic")
	for x = x0 + 10, x1 - 6, 10 do k.part(ceil, "CeilingGrid", V(.12, .12, LEN), CF(x, CEIL - .06, LEN / 2), PAL.ceilingGrid, nil, "Scenic") end
	for z = 20, LEN - 2, 20 do k.part(ceil, "CeilingGrid", V(FW, .12, .12), CF(fxc, CEIL - .06, z), PAL.ceilingGrid, nil, "Scenic") end
	local n = 0
	for z = 18, LEN - 18, 24 do
		n += 1
		local panel = k.part(ceil, "RectCeilingLight", V(12, .3, 5), CF((LANE_X0 + FX) / 2, CEIL - .2, z), PAL.panel, M.Neon, "Scenic")
		if n % 4 == 1 then k.light(panel, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.panel, Brightness=.8, Range=50, Angle=90, Shadows=false}) end
	end

	local laneX = mirrorSum - (LANE_X0 + FX) / 2
	local cameras = {
		{name="S06_Reference", position=V(10, 7, 2), lookAt=V(-26, 28, 132)},
		{name="S06_BlackOpening", position=V(5, 6, VOID_Z - 66), lookAt=V(-36, 22, VOID_Z)},
		{name="S06_GableRoofline", position=V(-14, 30, 48), lookAt=V(-27, 58, 130)},
	}
	local waypoints = {V(laneX, 3, 10), V(4, 3, VOID_Z), V(laneX, 3, LEN - 20)}
	local zones = {{Name="S06_Lane", Min=V(mirrorSum - FX, 0, 0), Max=V(mirrorSum - LANE_X0, CEIL, LEN - 4), CeilingHeight=CEIL,
		Description="Long dark lawn beside a dense gabled clapboard facade with porches, balconies and a large black opening; far facade closes the lane."}}
	local footprint = {Min=V(mirrorSum - x1, 0, 0), Max=V(mirrorSum - (LANE_X0 - 2), CEIL + 2, LEN), CeilingY=CEIL, GradeY=0,
		LaneWidth=FX - LANE_X0, FacadeX=mirrorSum - FX, BayCount=NB, VoidCenterZ=VOID_Z, VoidWidth=VOID_W, VoidHeight=VOID_H}
	return cameras, waypoints, zones, footprint
end

---------------------------------------------------------------------------------------------------
-- Section 7: pale apartment stair-stack cutaway.
-- Local layout: camera side z = 0 looking +Z. Room x -30..30, back wall face at z = 42.5, ceiling
-- at 46. A torn front wall at z = 30 leaves a jagged gap around x = -13..13 that reveals a carpeted
-- switchback: front lane z 32.5..37 climbs +X, back lane z 37.5..42 climbs -X, half landings at
-- x 6..12, floor landings at x -12..-6 with a white door each. Storeys are 11; three of them.
---------------------------------------------------------------------------------------------------
local function buildSection7(k, K, root)
	local V, CF = k.V, k.CF
	local W, CEIL, STOREY, LEVELS = 60, 46, 11, 3
	local HALF, N = STOREY / 2, 8 -- denser carpet treads and turned balusters per half flight
	local RISE, RUN = HALF / N, 12 / (N - 1)
	local EDGE_Z, WALL_Z, LANE_W = 32.5, 42.5, 4.5
	local FRONT_Z, BACK_Z = EDGE_Z + LANE_W / 2, WALL_Z - LANE_W / 2
	local CARPET, CORE = Color3.fromRGB(172, 157, 139), Color3.fromRGB(187, 176, 157)
	local WALL = Color3.fromRGB(222, 211, 192)
	local INSET = Color3.fromRGB(226, 222, 208)
	local function wallSpan(into, name, x0, x1, y0, y1, z)
		if x1 <= x0 or y1 <= y0 then return end
		k.part(into, name, V(x1 - x0, y1 - y0, 2), CF((x0 + x1) / 2, (y0 + y1) / 2, z), WALL, M.Plaster, "Blocking")
	end

	local shell = k.model("ApartmentShell", root)
	k.floor(shell, "PaleCarpetFloor", 0, 0, WALL_Z / 2, W, WALL_Z, CARPET)
	-- Split the rear wall around each door and tall opening. The inset door slabs below close
	-- the passages visually; the openings themselves are real voids in the plaster mass.
	for lvl = 0, LEVELS do
		local y = lvl * STOREY
		wallSpan(shell, "BackDoorLeftPier", -30, -11.1, y, y + 7.6, WALL_Z + 1)
		wallSpan(shell, "BackBetweenOpenings", -6.9, 6.5, y, y + 7.6, WALL_Z + 1)
		wallSpan(shell, "BackWindowRightPier", 11.5, 30, y, y + 7.6, WALL_Z + 1)
		wallSpan(shell, "BackDoorLintel", -30, 6.5, y + 7.6, y + STOREY, WALL_Z + 1)
		wallSpan(shell, "BackWindowRightLintel", 11.5, 30, y + 7.6, y + STOREY, WALL_Z + 1)
	end
	wallSpan(shell, "BackTopCap", -30, 30, (LEVELS + 1) * STOREY, CEIL, WALL_Z + 1)
	for _, s in ipairs({-1, 1}) do
		k.part(shell, "SideWall", V(2, CEIL, WALL_Z), CF(s * (W / 2 + 1), CEIL / 2, WALL_Z / 2), WALL, M.Plaster, "Blocking")
	end
	-- The split rear wall's unfilled apertures otherwise reveal bright outdoor sky behind
	-- the indoor cutaway. A recessed plaster backing keeps the stairwell enclosed.
	k.part(shell, "RecessedWarmBackingWall", V(W, CEIL, 2),
		CF(0, CEIL / 2, WALL_Z + 8), WALL, M.Plaster, "Blocking")
	k.part(shell, "RearCeilingReturn", V(W, 2, 10),
		CF(0, CEIL + 1, WALL_Z + 5), PAL.ceiling, M.Plaster, "Scenic")

	-- A white panel door facing -Z with two insets, a head trim and a warm sconce.
	local function panelDoor(into, x, y, z, lit)
		k.part(into, "PanelDoor", V(3.2, 7.2, .2), CF(x, y + 3.6, z), PAL.white, M.SmoothPlastic, "Blocking")
		for _, dy in ipairs({1.9, 5.3}) do k.part(into, "DoorPanelInset", V(2.2, 2.6, .12), CF(x, y + dy, z - .14), INSET, M.SmoothPlastic, "Scenic") end
		for _, sx in ipairs({-1, 1}) do
			k.part(into, "DoorOpeningJamb", V(.32, 7.6, .42), CF(x + sx * 1.95, y + 3.8, z - .1), PAL.white, M.Wood, "Scenic")
		end
		k.part(into, "DoorHeadTrim", V(4, .4, .35), CF(x, y + 7.4, z - .05), PAL.white, nil, "Scenic")
		local sconce = k.part(into, "WarmSconce", V(.4, .9, .4), CF(x + 2.6, y + 6, z - .15), PAL.warm, M.Neon, "Scenic")
		if lit then k.light(sconce, "PointLight", {Color=PAL.warm, Brightness=.7, Range=12, Shadows=false}) end
	end

	-- Torn front wall: level-by-level stepped fracture around genuine apertures.
	local torn = k.model("TornFrontWall", root)
	local OFF = {{0, 1.4}, {3.4, 3.8}, {-2.2, 1.2}, {2.1, 4.6}}
	for lvl = 0, LEVELS do
		local y = lvl * STOREY
		local xL, xR = -13 - OFF[lvl + 1][1], 13 + OFF[lvl + 1][2]
		wallSpan(torn, "LeftDoorPier", -30, -25, y, y + 7.6, 30)
		wallSpan(torn, "LeftBrokenPier", -21, xL, y, y + 7.6, 30)
		wallSpan(torn, "RightBrokenPier", xR, 16, y, y + 7.6, 30)
		wallSpan(torn, "RightWindowPier", 28, 30, y, y + 7.6, 30)
		wallSpan(torn, "LeftDoorLintel", -30, xL, y + 7.6, y + STOREY, 30)
		wallSpan(torn, "RightWindowLintel", xR, 30, y + 7.6, y + STOREY, 30)
		-- The raw edge steps forward and back through the wall depth. Three battered
		-- segments per floor show plaster thickness rather than one straight gray stripe.
		for _, edge in ipairs({xL, xR}) do
			for cut = 1, 3 do
				local jag = (cut == 2 and .9 or -.35) * (edge < 0 and -1 or 1)
				k.part(torn, "ExposedBrokenCore", V(.9, STOREY / 3 + .2, 2.6 + cut * .45),
					CF(edge + jag, y + (cut - .5) * STOREY / 3, 29.7 - cut * .25),
					CORE, M.Concrete, "Scenic")
			end
		end
		-- Larger tilted shards bridge between offsets while leaving the stairwell open.
		for _, edge in ipairs({xL, xR}) do
			k.part(torn, "JaggedPlasterShard", V(1.4, 2.6, 2.3),
				CF(edge, y + 2.2 + (lvl % 2) * 3.2, 28.9)
					* CFrame.Angles(math.rad(lvl % 2 == 0 and 14 or -11), 0, math.rad(edge < 0 and -27 or 24)),
				CORE, M.Concrete, "Scenic", "WedgePart")
			k.part(torn, "TornPlasterLip", V(2.5, .65, 3.2),
				CF(edge + (edge < 0 and .7 or -.7), y + STOREY - .4, 28.5)
					* CFrame.Angles(0, 0, math.rad(edge < 0 and 12 or -16)),
				WALL, M.Plaster, "Scenic", "WedgePart")
		end
		for _, wx in ipairs({16, 28}) do
			k.part(torn, "WhiteOpeningJamb", V(.35, 7.3, .45), CF(wx, y + 3.65, 28.85), PAL.white, M.Wood, "Scenic")
		end
		k.part(torn, "WhiteWindowHeader", V(12.4, .35, .45), CF(22, y + 7.4, 28.85), PAL.white, M.Wood, "Scenic")
	end
	wallSpan(torn, "LeftBrokenTopCap", -30, -13, (LEVELS + 1) * STOREY, CEIL, 30)
	wallSpan(torn, "RightBrokenTopCap", 13, 30, (LEVELS + 1) * STOREY, CEIL, 30)
	wallSpan(torn, "BrokenTopCeilingReturn", -13, 13, (LEVELS + 1) * STOREY, CEIL, 30)
	-- Front-wall faces: stacked doors on one side, open room boxes on the other.
	for lvl = 0, LEVELS do
		local y = lvl * STOREY
		panelDoor(torn, -23, y, 28.9, lvl <= 1)
		local bay = k.model("ExposedRoom_" .. lvl, torn)
		k.part(bay, "RoomCarpetFloor", V(11.7, .75, 12), CF(22, y - .38, 36), CARPET, M.Fabric, "Scenic")
		k.part(bay, "RoomCeilingReturn", V(11.7, .4, 12), CF(22, y + 7.85, 36), WALL, M.Plaster, "Scenic")
		for _, sx in ipairs({16, 28}) do
			k.part(bay, "RoomDeepJamb", V(.45, 7.5, 10.5), CF(sx, y + 3.75, 35.2), WALL, M.Plaster, "Scenic")
		end
		panelDoor(bay, 22, y, WALL_Z - .5, lvl <= 1)
		if lvl > 0 then
			for _, xc in ipairs({-23, 22}) do
				k.part(torn, "NarrowLanding", V(8, .8, 2.6), CF(xc, y - .4, 27.7), PAL.pale, M.Plaster, "Scenic")
				k.bar(torn, "NarrowLandingRail", V(xc - 4, y + 3.2, 26.5), V(xc + 4, y + 3.2, 26.5), .24, PAL.white, "Scenic")
			end
		end
	end

	-- Switchback ----------------------------------------------------------------------------------
	local st = k.model("CarpetSwitchback", root)
	local function newel(into, x, y, z)
		k.part(into, "NewelPost", V(.8, 4.2, .8), CF(x, y + 2.1, z), PAL.white, M.Wood, "DropProtection")
		k.part(into, "NewelCap", V(1.1, .4, 1.1), CF(x, y + 4.25, z), PAL.white, M.Wood, "Scenic")
		k.shaped(into, "NewelFinial", V(.65, .65, .65), CF(x, y + 4.7, z), PAL.white, M.Wood, "Scenic", Enum.PartType.Ball)
	end
	-- Stepped carpet treads from x0 (floor y0) to x1 (y0 + HALF), balusters and handrail on railZ,
	-- and a tilted invisible guard on guardZ when that side is an open drop.
	local function flight(name, x0, x1, y0, zc, railZ, guardZ)
		local m = k.model(name, st)
		local dir, dx = x1 > x0 and 1 or -1, math.abs(x1 - x0)
		k.part(m, "StructuralFlightSoffit", V(dx + .6, .45, LANE_W),
			CF((x0 + x1) / 2, y0 + HALF / 2 - 2, zc)
				* CFrame.Angles(0, 0, dir * math.atan2(HALF, dx)),
			CORE, M.Concrete, "Scenic")
		for i = 1, N - 1 do
			local xc, top = x0 + dir * (i - .5) * RUN, y0 + i * RISE
			k.part(m, "CarpetTread", V(RUN + .02, RISE + 1.2, LANE_W), CF(xc, top - (RISE + 1.2) / 2, zc), CARPET, M.Fabric, "Walkable")
			local railY = y0 + 3.4 + HALF * (i - .5) / (N - 1)
			k.shaped(m, "TurnedBaluster", V(railY - top, .32, .32),
				CF(xc, (railY + top) / 2, railZ) * CFrame.Angles(0, 0, math.pi / 2),
				PAL.white, M.Wood, "Scenic", Enum.PartType.Cylinder)
			if i % 2 == 0 then
				k.shaped(m, "BalusterTurnedCollar", V(.45, .45, .45),
					CF(xc, top + (railY - top) * .48, railZ), PAL.white, M.Wood, "Scenic", Enum.PartType.Ball)
			end
		end
		k.bar(m, "Handrail", V(x0, y0 + 3.4, railZ), V(x1, y0 + HALF + 3.4, railZ), .3, PAL.white, "DropProtection")
		newel(m, x0, y0, railZ); newel(m, x1, y0 + HALF, railZ)
		if guardZ then
			k.part(m, "FlightDropGuard", V(math.sqrt(dx * dx + HALF * HALF), 7, .3), CF((x0 + x1) / 2, y0 + HALF / 2 + 3.5, guardZ) * CFrame.Angles(0, 0, dir * math.atan2(HALF, dx)), nil, nil, "DropGuard")
		end
	end
	local function landing(name, xc, y, endSign)
		local m = k.model(name, st)
		k.part(m, "CarpetLanding", V(6, 1, WALL_Z - EDGE_Z), CF(xc, y - .5, (EDGE_Z + WALL_Z) / 2), CARPET, M.Fabric, "Walkable")
		k.bar(m, "LandingRail", V(xc - 3, y + 3.4, EDGE_Z + .25), V(xc + 3, y + 3.4, EDGE_Z + .25), .3, PAL.white, "DropProtection")
		k.part(m, "LandingDropGuard", V(6.4, 7, .3), CF(xc, y + 3.5, EDGE_Z - .1), nil, nil, "DropGuard")
		k.bar(m, "LandingEndRail", V(xc + endSign * 2.8, y + 3.4, EDGE_Z), V(xc + endSign * 2.8, y + 3.4, WALL_Z), .3, PAL.white, "DropProtection")
		k.part(m, "LandingEndDropGuard", V(.3, 7, WALL_Z - EDGE_Z), CF(xc + endSign * 3.2, y + 3.5, (EDGE_Z + WALL_Z) / 2), nil, nil, "DropGuard")
	end

	for s = 0, LEVELS - 1 do
		local y = s * STOREY
		flight("FrontFlight_" .. s, -6, 6, y, FRONT_Z, EDGE_Z + .25, EDGE_Z - .1)
		landing("HalfLanding_" .. s, 9, y + HALF, 1)
		flight("BackFlight_" .. s, 6, -6, y + HALF, BACK_Z, BACK_Z - LANE_W / 2 + .25, nil)
		landing("FloorLanding_" .. (s + 1), -9, y + STOREY, -1)
		-- The lanes are a half storey apart; this keeps a walker from dropping between them.
		k.part(st, "LaneDividerGuard", V(12, 18, .3), CF(0, y + 9, (FRONT_Z + BACK_Z) / 2), nil, nil, "DropGuard")
		k.part(st, "HalfLandingOpening", V(4.6, 6, .2), CF(9, y + HALF + 3.4, WALL_Z - .1), PAL.pane, M.Glass, "Scenic")
	end
	local topY = LEVELS * STOREY
	-- Nothing climbs on from the top landing's +X side over the front lane: close it.
	k.bar(st, "TopLandingSideRail", V(-5.9, topY + 3.4, EDGE_Z), V(-5.9, topY + 3.4, EDGE_Z + LANE_W), .3, PAL.white, "DropProtection")
	k.part(st, "TopLandingSideGuard", V(.3, 7, LANE_W), CF(-5.7, topY + 3.5, FRONT_Z), nil, nil, "DropGuard")
	for lvl = 0, LEVELS do panelDoor(st, -9, lvl * STOREY, WALL_Z - .1, lvl <= 1) end

	-- Fluorescent tile ceiling ------------------------------------------------------------------------
	local ceil = k.model("FluorescentTileCeiling", root)
	k.part(ceil, "CeilingSlab", V(W, 2, WALL_Z), CF(0, CEIL + 1, WALL_Z / 2), PAL.ceiling, M.Plaster, "Scenic")
	for x = -24, 24, 6 do k.part(ceil, "CeilingGrid", V(.12, .12, WALL_Z), CF(x, CEIL - .06, WALL_Z / 2), PAL.ceilingGrid, nil, "Scenic") end
	for z = 6, WALL_Z - 1, 6 do k.part(ceil, "CeilingGrid", V(W, .12, .12), CF(0, CEIL - .06, z), PAL.ceilingGrid, nil, "Scenic") end
	local n = 0
	for _, x in ipairs({-18, 0, 18}) do
		for _, z in ipairs({9, 21, 33}) do
			n += 1
			local panel = k.part(ceil, "FluorescentPanel", V(4, .3, 8), CF(x, CEIL - .2, z), PAL.panel, M.Neon, "Scenic")
			if n % 3 == 2 then k.light(panel, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.cool, Brightness=.8, Range=30, Angle=90, Shadows=false}) end
		end
	end

	local cameras = {
		{name="S07_Reference", position=V(-4, 5, 4), lookAt=V(2, 22, 37)},
		{name="S07_TornEdge", position=V(-14, 6, 15), lookAt=V(-4, 21, 31)},
		{name="S07_StairWellUp", position=V(2, 3, 26), lookAt=V(0, 34, 38)},
	}
	local waypoints = {V(0, 3, 10), V(-9, 3, 37.5), V(9, HALF + 3, 37.5), V(-9, topY + 3, 37.5)}
	local zones = {{Name="S07_Cutaway", Min=V(-W / 2, 0, 0), Max=V(W / 2, CEIL, WALL_Z), CeilingHeight=CEIL,
		Description="Pale apartment cutaway: torn front wall revealing a carpeted switchback with white balusters, newels and landing doors under a fluorescent tile ceiling."}}
	local footprint = {Min=V(-W / 2 - 2, 0, 0), Max=V(W / 2 + 2, CEIL + 2, WALL_Z + 2), CeilingY=CEIL, GradeY=0,
		StoreyHeight=STOREY, Levels=LEVELS, TreadCount=2 * LEVELS * (N - 1), RiserHeight=RISE, TopLandingY=topY}
	return cameras, waypoints, zones, footprint
end

---------------------------------------------------------------------------------------------------
-- Section 8: carpeted upper atrium walkway. The upper floor is a broad U around a real 48-stud
-- drop; the lower galleries and visible stairs are scenic until a safe route is authored.
---------------------------------------------------------------------------------------------------
local function buildSection8(k, K, root)
	local V, CF = k.V, k.CF
	local W, D, CEIL, TOP, PIT, EDGE, FRONT, BACK = 136, 300, 50, 24, -24, 38, 30, 260
	local carpet = Color3.fromRGB(180, 169, 151)
	local shell = k.model("CarpetedUpperAtrium", root)
	-- Four non-overlapping slabs leave the centre entirely open at the upper grade.
	k.floor(shell, "ArrivalWalkway", 0, TOP, FRONT / 2, W, FRONT, carpet)
	k.floor(shell, "LeftWalkway", -(W / 2 + EDGE) / 2, TOP, (FRONT + BACK) / 2, W / 2 - EDGE, BACK - FRONT, carpet)
	k.floor(shell, "RightWalkway", (W / 2 + EDGE) / 2, TOP, (FRONT + BACK) / 2, W / 2 - EDGE, BACK - FRONT, carpet)
	k.floor(shell, "ReturnWalkway", 0, TOP, (BACK + D) / 2, W, D - BACK, carpet)
	-- The pit grade also continues beneath the side galleries, so the lower view has
	-- a solid floor instead of exposing the blue exterior below the upper slabs.
	k.floor(shell, "DeepAtriumFloor", 0, PIT, D / 2, W, D, carpet)
	for _, s in ipairs({-1, 1}) do
		k.part(shell, "PitSideFooting", V(1, 6, BACK - FRONT), CF(s * (EDGE + .5), PIT + 3, (FRONT + BACK) / 2), PAL.cream, M.Plaster, "Blocking")
		for z = FRONT, BACK, 46 do
			k.part(shell, "AtriumSupportPier", V(1.5, TOP - PIT, 1.5), CF(s * EDGE, (TOP + PIT) / 2, z), PAL.pale, M.Plaster, "Blocking")
		end
		k.part(shell, "OuterApartmentWall", V(2, CEIL - PIT, D), CF(s * (W / 2 + 1), (CEIL + PIT) / 2, D / 2), PAL.cream, M.Plaster, "Blocking")
		-- Continuous visible white rail and a separate collision guard around the upper drop.
		k.bar(shell, "UpperAtriumRail", V(s * EDGE, TOP + 3.4, FRONT), V(s * EDGE, TOP + 3.4, BACK), .28, PAL.white, "DropProtection")
		k.part(shell, "UpperAtriumDropGuard", V(.3, 7, BACK - FRONT), CF(s * EDGE, TOP + 3.5, (FRONT + BACK) / 2), nil, nil, "DropGuard")
		for z = FRONT, BACK, 10 do
			k.part(shell, "UpperRailPost", V(.22, 3.2, .22), CF(s * EDGE, TOP + 1.8, z), PAL.white, M.Metal, "DropProtection")
		end
	end
	for _, z in ipairs({FRONT, BACK}) do
		k.bar(shell, "AtriumEndRail", V(-EDGE, TOP + 3.4, z), V(EDGE, TOP + 3.4, z), .28, PAL.white, "DropProtection")
		k.part(shell, "AtriumEndDropGuard", V(EDGE * 2, 7, .3), CF(0, TOP + 3.5, z), nil, nil, "DropGuard")
	end
	for _, z in ipairs({FRONT, BACK}) do
		k.part(shell, "PitEndWall", V(EDGE * 2, TOP - PIT, 1), CF(0, (TOP + PIT) / 2, z), PAL.cream, M.Plaster, "Blocking")
	end
	k.part(shell, "RearAtriumWall", V(W, CEIL - PIT, 2), CF(0, (CEIL + PIT) / 2, D + 1), PAL.cream, M.Plaster, "Blocking")

	-- Separate apartment fronts: small balconies face inward from the outer walls, while the
	-- galleries across the central opening repeat on several levels below the broad walkway.
	local fronts = k.model("ApartmentFronts", root)
	for _, s in ipairs({-1, 1}) do
		local inward = V(-s, 0, 0)
		for _, y in ipairs({0, 12, 24, 36}) do
			local bay = 0
			for z = 48, BACK - 22, 30 do
				bay += 1
				local f = k.model("Apartment_" .. s .. "_" .. y .. "_" .. bay, fronts)
				local x = s * (W / 2 - .2)
				local door = k.part(f, "WhitePanelDoor", V(.3, 7.4, 3.4), CF(x - s * .3, y + 3.7, z - 3.5), PAL.door, M.Wood, "Scenic")
				for dy = 1, 5, 2 do
					k.part(f, "DoorInset", V(.12, 1.5, 2.5), CF(x - s * .52, y + dy + .1, z - 3.5), PAL.pale, M.Wood, "Scenic")
				end
				door:SetAttribute("ScenicClosed", true)
				local wc = V(x - s * .3, y + 5.5, z + 3.2)
				local windowFrame = CFrame.lookAt(wc, wc + inward)
				gridWindow(k, f, windowFrame, 3.8, 6.6, y >= 12)
				-- The near facade needs a legible white casing against the cream wall. Give the
				-- opposite apartments the same detail so the cross-atrium view stays consistent.
				for _, side in ipairs({-1, 1}) do
					k.part(f, "WindowSideCasing", V(.26, 6.86, .28),
						windowFrame * CF(side * 2.03, 0, -.2), PAL.white, M.Wood, "Scenic")
					k.part(f, "WindowHeadSill", V(4.32, .26, .28),
						windowFrame * CF(0, side * 3.43, -.2), PAL.white, M.Wood, "Scenic")
				end
				local lamp = k.part(f, "WarmSconce", V(.65, .8, .65), CF(x - s * .7, y + 7.8, z), PAL.warm, M.Neon, "Scenic")
				if y == TOP and bay % 2 == 1 then k.light(lamp, "PointLight", {Color=PAL.warm, Brightness=.55, Range=11, Shadows=false}) end
				-- At the broad upper grade, doors open onto carpet. Only the storey above
				-- it has separate projecting balconies; lower levels use full galleries.
				if y > TOP and y < CEIL - 8 then
					local bx = s * (W / 2 - 2.7)
					k.part(f, "TinyBalcony", V(5, .55, 10), CF(bx, y - .28, z), PAL.pale, M.Plaster, "Scenic")
					k.bar(f, "TinyBalconyRail", V(bx - s * 2.4, y + 3.2, z - 5), V(bx - s * 2.4, y + 3.2, z + 5), .22, PAL.white, "Scenic")
					for _, dz in ipairs({-4.8, 0, 4.8}) do
						k.part(f, "TinyBalconyPost", V(.22, 3.2, .22),
							CF(bx - s * 2.4, y + 1.6, z + dz), PAL.white, M.Metal, "Scenic")
					end
				end
			end
		end
		for _, y in ipairs({-12, 0, 12}) do
			local gx = s * (W / 2 + EDGE) / 2
			k.part(fronts, "OppositeGallery", V(W / 2 - EDGE, .8, BACK - FRONT),
				CF(gx, y - .4, (FRONT + BACK) / 2), PAL.pale, M.Plaster, "Scenic")
			-- The far side has a stair opening between the two rail spans. Every
			-- lower gallery now reaches its apartment doors at the outer wall.
			local spans = if s < 0 then {{FRONT, 136}, {180, BACK}} else {{FRONT, BACK}}
			for _, span in ipairs(spans) do
				k.bar(fronts, "OppositeGalleryRail", V(s * EDGE, y + 3.4, span[1]),
					V(s * EDGE, y + 3.4, span[2]), .23, PAL.white, "Scenic")
				for z = span[1], span[2], 12 do
					k.part(fronts, "OppositeGalleryPost", V(.2, 3.2, .2),
						CF(s * EDGE, y + 1.8, z), PAL.white, M.Metal, "Scenic")
				end
			end
		end
	end
	-- The far stair stack projects just inside the open drop. Its landings meet the
	-- far galleries at their inner edge; all stair parts remain scenic until an
	-- authored ascent and separate collision/guard check are added.
	local stairs = k.model("AcrossVoidStairStack", root)
	local stairX, railX, nearZ, farZ = -EDGE + 5, -EDGE + 9.3, 142, 174
	for level = 0, 4 do
		local landingZ = if level % 2 == 0 then nearZ else farZ
		k.part(stairs, "CarpetStairLanding", V(10, .7, 7),
			CF(stairX, PIT + level * 12 - .35, landingZ), carpet, M.Fabric, "Scenic")
	end
	for level = 0, 3 do
		local y0, z0 = PIT + level * 12, if level % 2 == 0 then nearZ else farZ
		local z1 = if level % 2 == 0 then farZ else nearZ
		for i = 1, 8 do
			local z = z0 + (z1 - z0) * (i - .5) / 8
			k.part(stairs, "CarpetTread", V(8, 1.5, 4.05),
				CF(stairX, y0 + i * 1.5 - .75, z), carpet, M.Fabric, "Scenic")
		end
		k.bar(stairs, "WhiteStairHandrail", V(railX, y0 + 3.4, z0),
			V(railX, y0 + 15.4, z1), .23, PAL.white, "Scenic")
		for i = 0, 8 do
			k.part(stairs, "WhiteStairPost", V(.22, 3.2, .22),
				CF(railX, y0 + 1.8 + i * 1.5, z0 + (z1 - z0) * i / 8),
				PAL.white, M.Metal, "Scenic")
		end
	end

	-- The end wall is a distant apartment face rather than a bare plaster plane.
	local rear = k.model("AtriumEndApartments", root)
	for _, y in ipairs({TOP, 36}) do
		for bay = -2, 2 do
			local x = bay * W / 5
			local frame = CFrame.lookAt(V(x, y + 5.5, D - .3), V(x, y + 5.5, D - 1.3))
			gridWindow(k, rear, frame, 4.2, 6.6, true, PAL.white)
			for _, side in ipairs({-1, 1}) do
				k.part(rear, "EndWindowSideCasing", V(.26, 6.86, .28),
					frame * CF(side * 2.23, 0, -.2), PAL.white, M.Wood, "Scenic")
				k.part(rear, "EndWindowHeadSill", V(4.72, .26, .28),
					frame * CF(0, side * 3.43, -.2), PAL.white, M.Wood, "Scenic")
			end
		end
	end
	k.part(rear, "EndGalleryLedge", V(W - 8, .7, 5),
		CF(0, 36 - .35, D - 2.5), PAL.pale, M.Plaster, "Scenic")
	k.bar(rear, "EndGalleryRail", V(-W / 2 + 4, 39.4, D - 5),
		V(W / 2 - 4, 39.4, D - 5), .23, PAL.white, "Scenic")
	for x = -W / 2 + 4, W / 2 - 4, 12 do
		k.part(rear, "EndGalleryPost", V(.2, 3.2, .2),
			CF(x, 37.8, D - 5), PAL.white, M.Metal, "Scenic")
	end

	local ceil = k.model("OfficeTileCeiling", root)
	k.part(ceil, "CeilingSlab", V(W, 2, D), CF(0, CEIL + 1, D / 2), PAL.ceiling, M.Plaster, "Scenic")
	for x = -W / 2 + 8, W / 2 - 8, 12 do
		k.part(ceil, "CeilingGrid", V(.12, .12, D), CF(x, CEIL - .06, D / 2), PAL.ceilingGrid, nil, "Scenic")
	end
	for z = 12, D - 4, 12 do k.part(ceil, "CeilingGrid", V(W, .12, .12), CF(0, CEIL - .06, z), PAL.ceilingGrid, nil, "Scenic") end
	for _, fraction in ipairs({-.375, -.125, .125, .375}) do for z = 24, D - 16, 48 do
		local x = W * fraction
		local p = k.part(ceil, "FluorescentPanel", V(5, .3, 9), CF(x, CEIL - .2, z), PAL.cool, M.Neon, "Scenic")
		if z % 96 == 72 then k.light(p, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.cool, Brightness=.7, Range=26, Angle=100, Shadows=false}) end
	end end

	local cameras = {
		-- The apartment frontage and broad carpet stay on screen left; the protected
		-- opening and cross-atrium galleries fall to screen right, as in reference 08.
		{name="S08_Reference", position=V(55, TOP + 7, 62), lookAt=V(36, TOP - 5, 138)},
		{name="S08_AcrossVoid", position=V(56, TOP + 4, 103), lookAt=V(-65, 4, 150)},
		{name="S08_DeepDrop", position=V(51, TOP + 5, 70), lookAt=V(0, PIT, 112)},
	}
	local sideWaypointX = (EDGE + W / 2) / 2
	local waypoints = {V(0, TOP + 3, 8), V(sideWaypointX, TOP + 3, 48),
		V(sideWaypointX, TOP + 3, BACK - 22), V(0, TOP + 3, D - 16)}
	local zones = {{Name="S08_UpperAtrium", Min=V(-W / 2, PIT, 0), Max=V(W / 2, CEIL, D), CeilingHeight=CEIL,
		Description="Broad carpeted upper walkway around an open deep atrium; small apartment balconies, doors, windows and opposite stair galleries."}}
	local footprint = {Min=V(-W / 2 - 2, PIT, 0), Max=V(W / 2 + 2, CEIL + 2, D + 2), CeilingY=CEIL, GradeY=TOP,
		VoidMin=V(-EDGE, PIT, FRONT), VoidMax=V(EDGE, TOP, BACK), WalkwayWidth=W / 2 - EDGE}
	return cameras, waypoints, zones, footprint
end

---------------------------------------------------------------------------------------------------
-- Section 10: intentionally sparse rooms. The left windows are actual openings in a divided wall,
-- so the stacked balconies across the interior void remain visible from the broad front doorway.
---------------------------------------------------------------------------------------------------
local function buildSection10(k, K, root)
	local V, CF = k.V, k.CF
	local W, D, CEIL = 84, 112, 16
	local PART_Z = 31
	local carpet = Color3.fromRGB(190, 177, 158)
	local beige = Color3.fromRGB(219, 210, 194)
	-- The original authored room has its balcony windows on world -X, which appears
	-- screen-right when looking +Z. Mirror before the architecture anchor so the
	-- windows appear left and the partition passage appears right, as in the image.
	local function mirrorV(p) return V(-p.X, p.Y, p.Z) end
	local function mirrorCF(cf)
		local r, u, b = cf.RightVector, cf.UpVector, -cf.LookVector
		return CFrame.fromMatrix(mirrorV(cf.Position),
			V(r.X, -r.Y, -r.Z), V(-u.X, u.Y, u.Z), V(-b.X, b.Y, b.Z))
	end
	local rawPart, rawFloor, rawWindow = k.part, k.floor, k.window
	k.part = function(into, name, size, cf, color, mat, intent, className)
		return rawPart(into, name, size, mirrorCF(cf), color, mat, intent, className)
	end
	k.floor = function(into, name, x, y, z, w, d, color, frame)
		return rawFloor(into, name, -x, y, z, w, d, color, frame and mirrorCF(frame))
	end
	k.window = function(into, frame, w, h, lit, simple, intent)
		return rawWindow(into, mirrorCF(frame), w, h, lit, simple, intent)
	end
	local room = k.model("UnfurnishedCarpetRooms", root)
	k.floor(room, "EmptyRoomCarpet", 0, 0, (D - 24) / 2, W, D + 24, carpet)
	k.part(room, "RightWall", V(1.5, CEIL, D), CF(W / 2 + .75, CEIL / 2, D / 2), beige, M.Plaster, "Blocking")
	k.part(room, "RearWall", V(W, CEIL, 1.5), CF(0, CEIL / 2, D + .75), beige, M.Plaster, "Blocking")
	-- The threshold is wider toward the interior-window wall, so two tall bays are
	-- visible through the portal instead of being blocked by its near-left pier.
	for _, entry in ipairs({
		{wallX=-41, wallW=2, jambX=-40, innerX=-39.45},
		{wallX=33, wallW=18, jambX=24, innerX=23.45},
	}) do
		local side = k.part(room, "EntrySideWall", V(entry.wallW, CEIL, 2.5), CF(entry.wallX, CEIL / 2, 0), beige, M.Plaster, "Blocking")
		side.CastShadow = false
		k.part(room, "WideEntryJamb", V(.8, 12.7, 3.2), CF(entry.jambX, 6.35, -.9), PAL.white, M.Wood, "Scenic")
		k.part(room, "EntryInnerReturn", V(.25, 12.7, 2.4), CF(entry.innerX, 6.35, -1), PAL.white, M.Wood, "Scenic")
	end
	local entryHeader = k.part(room, "WideEntryHeader", V(65, .85, 3.2), CF(-8, 12.7, -.9), PAL.white, M.Wood, "Scenic")
	entryHeader.CastShadow = false
	local entryLintel = k.part(room, "EntryLintel", V(64, CEIL - 12.7, 2.5), CF(-8, (CEIL + 12.7) / 2, 0), beige, M.Plaster, "Blocking")
	entryLintel.CastShadow = false
	-- A central partition holds the closed six-panel door. A 16-stud opening to its right leads
	-- into the second empty room; no furniture is placed in either room.
	k.part(room, "PartitionWall", V(64, CEIL, 1.3), CF(-10, CEIL / 2, PART_Z), beige, M.Plaster, "Blocking")
	k.part(room, "PartitionRightReturn", V(4, CEIL, 1.3), CF(40, CEIL / 2, PART_Z), beige, M.Plaster, "Blocking")
	for _, s in ipairs({-1, 1}) do
		k.part(room, "RightOpeningJamb", V(.5, 11, 1.8), CF(30 + s * 8, 5.5, PART_Z - .7), PAL.white, M.Wood, "Scenic")
	end
	k.part(room, "RightOpeningHeader", V(17, .5, 1.8), CF(30, 11, PART_Z - .7), PAL.white, M.Wood, "Scenic")
	local door = k.model("SixPanelPartitionDoor", room)
	k.part(door, "DoorSlab", V(6.2, 9.6, .25), CF(0, 4.8, PART_Z - .84), Color3.fromRGB(234, 232, 226), M.SmoothPlastic, "Scenic")
	for _, x in ipairs({-1.27, 1.27}) do for _, y in ipairs({1.8, 4.7, 7.55}) do
		k.part(door, "RaisedDoorPanel", V(2.15, 2.15, .07), CF(x, y, PART_Z - 1.02), Color3.fromRGB(225, 223, 218), M.SmoothPlastic, "Scenic")
	end end
	for _, x in ipairs({-3.3, 3.3}) do
		k.part(door, "DoorJamb", V(.38, 10.1, .5), CF(x, 5.05, PART_Z - .95), PAL.white, M.SmoothPlastic, "Scenic")
	end
	k.part(door, "DoorHeader", V(7, .42, .5), CF(0, 10, PART_Z - .95), PAL.white, M.SmoothPlastic, "Scenic")
	local knob = k.shaped(door, "SmallMetalKnob", V(.32, .32, .32), CF(2.45, 4.1, PART_Z - 1.26), Color3.fromRGB(156, 143, 105), M.Metal, "Scenic", Enum.PartType.Ball)
	knob:SetAttribute("ScenicClosed", true)
	k.part(room, "RearBaseboard", V(W - 2, .48, .25), CF(0, .24, D - .55), PAL.white, M.Wood, "Scenic")
	k.part(room, "PartitionBaseboardLeft", V(39, .48, .25), CF(-22.5, .24, PART_Z - .9), PAL.white, M.Wood, "Scenic")
	k.part(room, "PartitionBaseboardRight", V(19, .48, .25), CF(12.5, .24, PART_Z - .9), PAL.white, M.Wood, "Scenic")
	for _, s in ipairs({-1, 1}) do
		k.part(room, "SideBaseboard", V(.25, .48, D), CF(s * 41, .24, D / 2), PAL.white, M.Wood, "Scenic")
	end

	-- Left wall is split above and below four tall interior-facing windows. The bays between
	-- the panes remain solid; the dark opening behind the glass reveals the opposite balconies.
	local windows = k.model("AtriumFacingWindows", room)
	k.part(windows, "LeftWindowSillWall", V(1.5, 3, D), CF(-W / 2 - .75, 1.5, D / 2), beige, M.Plaster, "Blocking")
	k.part(windows, "LeftWindowHeadWall", V(1.5, 4, D), CF(-W / 2 - .75, CEIL - 2, D / 2), beige, M.Plaster, "Blocking")
	local last = 0
	for _, z in ipairs({8, 20, 52, 82}) do
		local near = z - 4.5
		k.part(windows, "WindowBayPier", V(1.5, 9, near - last), CF(-W / 2 - .75, 7.5, (last + near) / 2), beige, M.Plaster, "Blocking")
		local p = V(-W / 2 - .15, 7.5, z)
		local pane = k.window(windows, CFrame.lookAt(p, p + V(-1, 0, 0)), 8.5, 8.8, false, false, "Blocking")
		pane.Color = Color3.fromRGB(35, 34, 32)
		pane.Material = M.SmoothPlastic
		pane.Reflectance = 0
		pane.Transparency = .94
		last = z + 4.5
	end
	k.part(windows, "WindowBayPier", V(1.5, 9, D - last), CF(-W / 2 - .75, 7.5, (last + D) / 2), beige, M.Plaster, "Blocking")
	-- There is no floor across the narrow void outside these windows. Balcony slabs are scenic,
	-- and the glass itself blocks a player leaving the empty interior.
	local opposite = k.model("BalconiesSeenThroughWindows", root)
	k.part(opposite, "OppositeApartmentWall", V(2, 54, D), CF(-72, 27, D / 2),
		Color3.fromRGB(111, 105, 94), M.Plaster, "Blocking")
	for level = 0, 5 do
		local y = level * 8
		k.part(opposite, "OppositeBalcony", V(5, .7, D - 16), CF(-67.8, y - .35, D / 2), PAL.pale, M.Plaster, "Scenic")
		k.bar(opposite, "OppositeWhiteRail", V(-65.4, y + 3.2, 8), V(-65.4, y + 3.2, D - 8), .23, PAL.white, "Scenic")
		for _, z in ipairs({8, 20, 52, 82}) do
			k.part(opposite, "DarkBalconyDoor", V(.3, 6.8, 5), CF(-70.8, y + 3.6, z), PAL.pane, M.SmoothPlastic, "Scenic")
		end
		for z = 8, D - 8, 4 do
			k.part(opposite, "OppositeBalconyPost", V(.18, 3, .18),
				CF(-65.4, y + 1.75, z), PAL.white, M.Metal, "Scenic")
		end
	end

	local ceiling = k.model("LowSuspendedCeiling", root)
	k.part(ceiling, "CeilingPlane", V(W, 2, D + 24), CF(0, CEIL + 1, (D - 24) / 2), PAL.ceiling, M.Plaster, "Scenic")
	for x = -36, 36, 12 do k.part(ceiling, "CeilingGrid", V(.1, .1, D + 24), CF(x, CEIL - .06, (D - 24) / 2), PAL.ceilingGrid, nil, "Scenic") end
	for z = -12, D - 4, 12 do k.part(ceiling, "CeilingGrid", V(W, .1, .1), CF(0, CEIL - .06, z), PAL.ceilingGrid, nil, "Scenic") end
	for _, x in ipairs({-18, 18}) do for _, z in ipairs({-9, 21, 45, 69, 93}) do
		local p = k.part(ceiling, "LongFluorescentPanel", V(7, .22, 3), CF(x, CEIL - .2, z), PAL.cool, M.Neon, "Scenic")
		if z == 45 or z == 93 then k.light(p, "SurfaceLight", {Face=Enum.NormalId.Bottom, Color=PAL.cool, Brightness=.7, Range=22, Angle=100, Shadows=false}) end
	end end
	for _, z in ipairs({34, 83}) do
		k.part(ceiling, "DarkVentSlot", V(6, .08, 2), CF(26, CEIL - .21, z), PAL.pane, M.Metal, "Scenic")
	end

	local cameras = {
		{name="S10_Reference", position=V(15, 5, -21), lookAt=V(23, 5, 40)},
		{name="S10_ThroughWindows", position=V(-12, 5, 28), lookAt=V(68, 14, 55)},
		{name="S10_SecondEmptyRoom", position=V(-30, 5, 53), lookAt=V(3, 6, 94)},
	}
	local waypoints = {V(0, 3, 8), V(-15, 3, 32), V(-30, 3, 52), V(0, 3, 100)}
	local zones = {{Name="S10_EmptyRoom", Min=V(-W / 2, 0, -24), Max=V(73, 54, D), CeilingHeight=CEIL,
		Description="Empty beige carpet rooms through a wide white opening, six-panel door and right passage, interior windows to opposite balcony stacks."}}
	local footprint = {Min=V(-W / 2 - 2, 0, -24), Max=V(73, 54, D + 2), CeilingY=CEIL, GradeY=0,
		EntryOpeningWidth=64, RightOpeningWidth=16, InteriorWindowCount=4, DoorPanelCount=6}
	return cameras, waypoints, zones, footprint
end

local BUILDERS = {
	[5] = {name="ReferenceSection_05_SlopedHouseAnomaly", build=buildSection5},
	[6] = {name="ReferenceSection_06_GabledFacadeLawn", build=buildSection6},
	[7] = {name="ReferenceSection_07_StairStackCutaway", build=buildSection7},
	[8] = {name="ReferenceSection_08_UpperAtriumWalkway", build=buildSection8},
	[9] = {name="ReferenceSection_09_SkybridgeCanyon", build=buildSection9},
	[10] = {name="ReferenceSection_10_EmptyBalconyRoom", build=buildSection10},
}

function Anomalies.Build(K, sectionId, anchorFrame)
	assert(type(K) == "table" and K.root and K.part and K.floor and K.model and K.window, "Anomalies.Build needs the Level 5 Architecture kit")
	local spec = BUILDERS[sectionId]
	assert(spec, ("Reference section %s is not implemented (implemented: 5, 6, 7, 8, 9, 10)"):format(tostring(sectionId)))
	local anchor = anchorFrame or CFrame.identity
	assert(typeof(anchor) == "CFrame", "anchorFrame must be a CFrame")
	-- Nothing is ever destroyed here, so a second build of the same section is refused instead of
	-- silently duplicating it.
	assert(not K.root:FindFirstChild(spec.name), spec.name .. " is already built under " .. K.root:GetFullName())

	local k = kit(K, anchor)
	local root = k.model(spec.name, K.root)
	root:SetAttribute("GeometryOnly", true)
	root:SetAttribute("ReferenceSectionId", sectionId)
	root:SetAttribute("AnchorFrame", anchor)
	root:SetAttribute("FidelityStatus", "unverified-draft")

	local cameras, waypoints, zones, footprint = spec.build(k, K, root)

	for _, c in ipairs(cameras) do c.position = anchor * c.position; c.lookAt = anchor * c.lookAt end
	for i, p in ipairs(waypoints) do waypoints[i] = anchor * p end
	for _, z in ipairs(zones) do
		z.Model = root
		z.Min, z.Max = aabb(anchor, z.Min, z.Max)
		z.Space = "architecture-local"
	end
	footprint.LocalMin, footprint.LocalMax = footprint.Min, footprint.Max
	footprint.Min, footprint.Max = aabb(anchor, footprint.LocalMin, footprint.LocalMax)
	footprint.Space = "architecture-local (Min/Max); anchor-local (LocalMin/LocalMax)"
	footprint.AnchorFrame = anchor

	local counts = k.counts
	local actualParts, actualLights = 0, 0
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("BasePart") then actualParts += 1 end
		if item:IsA("Light") then actualLights += 1 end
	end
	assert(actualParts == counts.parts, "Reference section part accounting mismatch")
	assert(actualLights == counts.lights, "Reference section light accounting mismatch")
	local actualInstances = #root:GetDescendants() + 1 -- include section root itself
	root:SetAttribute("EstimatedParts", actualParts)
	root:SetAttribute("EstimatedLights", actualLights)
	root:SetAttribute("EstimatedInstances", actualInstances)
	return {
		Model=root,
		SectionId=sectionId,
		PreviewCameras=cameras,
		Waypoints=waypoints,
		Zones=zones,
		EstimatedParts=actualParts,
		EstimatedLights=actualLights,
		-- Count the finished model tree so carpet fallback textures are included.
		EstimatedInstances=actualInstances,
		Footprint=footprint,
	}
end

return Anomalies
