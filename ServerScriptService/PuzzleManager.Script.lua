-- PuzzleManager  (v2 — wall-mounted boxes/levers, edge exit)
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "PuzzleManager"
--
-- The win objective. Per player: 2 fuses spawn, 1 fuse box, 1 lever.
--   • Fuses lie on the ground; pick them up and carry them.
--   • Fuse boxes are MOUNTED ON WALLS and need 1 fuse each. Inserting one ramps
--     the danger (more flicker, faster entity) and makes the entity appear in
--     that AREA (~10 cells away — near, not on top of you).
--   • Every box full → the levers unlock. They're on walls near the map edges,
--     spread apart, so the party must split. Flick them ALL within 10s.
--   • Flicking a lever turns its light green (a signal to teammates on voice).
--   • Once all boxes are full there's a chance each 10s of ALERT: red pulsing
--     lights + sound. 50% on the first roll, 5% after.
--   • All levers together → lights go dark (a few faintly stay on; the entity is
--     a blinking beacon), the EXIT opens in the outer wall, and the entity moves
--     to guard it. Reach the exit to win.
--
-- Placeholder shapes for now — model Fuse / FuseBox / Lever / Exit later, keep
-- the names. Requires MazeGenerator (publishes maze attributes) + GameManager
-- (sets RoundActive).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")

local status = RS:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")

-- ── tuning ────────────────────────────────────────────────
local FUSES_PER_BOX = 1      -- fuses each box needs
local SPAWN_MULT    = 2      -- fuses spawned = needed × this
local LEVER_WINDOW  = 10     -- seconds all levers must be on together
local ALERT_INTERVAL = 10    -- seconds between alert rolls
local ALERT_FIRST   = 1.00   -- alert chance on the first roll (guaranteed)
local ALERT_AFTER   = 0.05   -- alert chance on every roll after
local ALERT_TIME    = 8      -- seconds an alert lasts
local FLICK_PER_FUSE = 0.6   -- FlickerBoost added per fuse inserted
local SPEED_PER_FUSE = 0.06  -- EntitySpeedMul added per fuse inserted
local END_SPEED_MUL  = 1.6   -- entity speed once the exit opens
local ENTITY_AREA_CELLS = 5  -- entity appears ~this many cells from the box
local EDGE_BAND      = 3      -- levers/exit spawn within this many cells of an edge
-- ──────────────────────────────────────────────────────────

local function attr(name, default)
	local v = workspace:GetAttribute(name)
	if v == nil then return default end
	return v
end

local session -- current round's puzzle state (nil between rounds)

-- ── geometry helpers ──────────────────────────────────────
local function cellCenter(x, z, CELL, O)
	return Vector3.new(O + (x - 0.5) * CELL, 0, O + (z - 0.5) * CELL)
end

-- floor height at (cx,cz), or nil over a pit hole
local function floorY(cx, cz)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return nil end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { maze }
	local hit = workspace:Raycast(Vector3.new(cx, 9, cz), Vector3.new(0, -15, 0), rp)
	if hit and hit.Position.Y > -3 then return hit.Position.Y end
	return nil
end

-- pit zone rectangles (things must not spawn ON the hole fields)
local function pitRects()
	local list = {}
	local pf = workspace:FindFirstChild("PitZones")
	if pf then
		for _, z in ipairs(pf:GetChildren()) do
			if z.Name == "Zone" then
				table.insert(list, {
					minX = z.Position.X - z.Size.X / 2, maxX = z.Position.X + z.Size.X / 2,
					minZ = z.Position.Z - z.Size.Z / 2, maxZ = z.Position.Z + z.Size.Z / 2,
				})
			end
		end
	end
	return list
end
local function inAnyPit(cx, cz, list)
	for _, r in ipairs(list) do
		if cx > r.minX and cx < r.maxX and cz > r.minZ and cz < r.maxZ then return true end
	end
	return false
end

-- nearest vertical wall around a floor point → (wallPos, inwardNormal) or nil
local function nearestWall(basePos)
	local CELL = attr("CELL", 24)
	local maze = workspace:FindFirstChild("Maze")
	if not maze then return nil end
	local origin = basePos + Vector3.new(0, 4, 0)
	local dirs = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	}
	local bestPos, bestN, bestD
	for _, d in ipairs(dirs) do
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { maze }
		local hit = workspace:Raycast(origin, d * CELL, rp)
		if hit and math.abs(hit.Normal.Y) < 0.5 then
			local dist = (hit.Position - origin).Magnitude
			if not bestD or dist < bestD then
				bestPos, bestN, bestD = hit.Position, hit.Normal, dist
			end
		end
	end
	if bestPos then return bestPos, bestN end
	return nil
end

local function makePrompt(parent, action, obj, dist)
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = obj or ""
	pp.HoldDuration = 0
	pp.MaxActivationDistance = dist or 9
	pp.RequiresLineOfSight = true -- can't interact through walls
	pp.Parent = parent
	return pp
end

-- candidate cells avoiding pits + the elevator room
local function eligibleCell()
	local GRID = attr("GRID", 40)
	local CELL = attr("CELL", 24)
	local O = attr("ORIGIN", -480)
	local ELEV_X = attr("ELEV_X", 20)
	local ELEV_Y = attr("ELEV_Y", 20)

	local pits = {}
	local pf = workspace:FindFirstChild("PitZones")
	if pf then
		for _, z in ipairs(pf:GetChildren()) do
			if z.Name == "Zone" then
				table.insert(pits, {
					minX = z.Position.X - z.Size.X / 2, maxX = z.Position.X + z.Size.X / 2,
					minZ = z.Position.Z - z.Size.Z / 2, maxZ = z.Position.Z + z.Size.Z / 2,
				})
			end
		end
	end
	local function inPit(cx, cz)
		for _, r in ipairs(pits) do
			if cx > r.minX and cx < r.maxX and cz > r.minZ and cz < r.maxZ then return true end
		end
		return false
	end

	return function(edgeOnly)
		local x = math.random(2, GRID - 1)
		local z = math.random(2, GRID - 1)
		if edgeOnly then
			local nearEdge = x <= 1 + EDGE_BAND or x >= GRID - EDGE_BAND
				or z <= 1 + EDGE_BAND or z >= GRID - EDGE_BAND
			if not nearEdge then return nil end
		end
		if math.max(math.abs(x - ELEV_X), math.abs(z - ELEV_Y)) <= 3 then return nil end
		local c = cellCenter(x, z, CELL, O)
		if inPit(c.X, c.Z) then return nil end
		local fy = floorY(c.X, c.Z)
		if not fy then return nil end
		return Vector3.new(c.X, fy, c.Z)
	end
end

-- floor spots (for fuses on the ground)
local function pickFloorSpots(count, minDist)
	local nextCell = eligibleCell()
	local spots, minD = {}, minDist
	for _ = 1, count do
		local placed
		for attempt = 1, 400 do
			if attempt % 80 == 0 then minD = minD * 0.7 end
			local pos = nextCell(false)
			if pos then
				local ok = true
				for _, s in ipairs(spots) do
					if (s - pos).Magnitude < minD then ok = false break end
				end
				if ok then placed = pos break end
			end
		end
		if placed then table.insert(spots, placed) end
	end
	return spots
end

-- wall-mount frames (front faces into the room) for boxes / levers / exit.
-- `avoid` is a shared list of already-placed station positions so DIFFERENT
-- object types stay apart too (not just within their own type); picks append
-- to it.
local function pickWallSpots(count, minDist, edgeOnly, avoid)
	avoid = avoid or {}
	local nextCell = eligibleCell()
	local frames = {}
	for _ = 1, count do
		local placedCF
		local minD = minDist
		for attempt = 1, 600 do
			if attempt % 100 == 0 then minD = minD * 0.7 end -- relax if crowded
			local pos = nextCell(edgeOnly)
			if pos then
				local wp, n = nearestWall(pos)
				if wp then
					local at = Vector3.new(wp.X, pos.Y + 4, wp.Z)
					local ok = true
					for _, u in ipairs(avoid) do
						if (u - at).Magnitude < minD then ok = false break end
					end
					if ok then
						placedCF = CFrame.lookAt(at, at + n) -- Front (-Z) faces into room
						table.insert(avoid, at)
						break
					end
				end
			end
		end
		if placedCF then table.insert(frames, placedCF) end
	end
	return frames
end

-- exit mount flush against one of the 4 OUTER BORDER walls, facing inward, so
-- the doorway actually leads out of the level
local function pickExitOnBorder(avoid, minDist)
	avoid = avoid or {}
	local GRID = attr("GRID", 40)
	local CELL = attr("CELL", 24)
	local O = attr("ORIGIN", -480)
	local lo = O                       -- interior min edge
	local hi = O + GRID * CELL          -- interior max edge
	local pits = pitRects()

	-- each side: given a row/col index → (mountPos, inwardNormal, frontCellCenter)
	local sides = {
		function(i) local cc = Vector3.new(lo + 0.5 * CELL, 0, O + (i - 0.5) * CELL)
			return Vector3.new(lo + 0.1, 0, cc.Z), Vector3.new(1, 0, 0), cc end,   -- west
		function(i) local cc = Vector3.new(hi - 0.5 * CELL, 0, O + (i - 0.5) * CELL)
			return Vector3.new(hi - 0.1, 0, cc.Z), Vector3.new(-1, 0, 0), cc end,  -- east
		function(i) local cc = Vector3.new(O + (i - 0.5) * CELL, 0, lo + 0.5 * CELL)
			return Vector3.new(cc.X, 0, lo + 0.1), Vector3.new(0, 0, 1), cc end,   -- south
		function(i) local cc = Vector3.new(O + (i - 0.5) * CELL, 0, hi - 0.5 * CELL)
			return Vector3.new(cc.X, 0, hi - 0.1), Vector3.new(0, 0, -1), cc end,  -- north
	}

	for _ = 1, 400 do
		local side = sides[math.random(#sides)]
		local mountPos, normal, cc = side(math.random(2, GRID - 1))
		local fy = floorY(cc.X, cc.Z)
		if fy and not inAnyPit(cc.X, cc.Z, pits) then
			local at = Vector3.new(mountPos.X, fy + 4, mountPos.Z)
			local ok = true
			for _, u in ipairs(avoid) do
				if (u - at).Magnitude < minDist then ok = false break end
			end
			if ok then
				table.insert(avoid, at)
				return CFrame.lookAt(at, at + normal) -- Front (-Z) faces into the maze
			end
		end
	end
	-- fallback: any edge wall spot
	local fb = pickWallSpots(1, minDist, true, avoid)
	return fb[1]
end

-- teleport the entity to the valid floor cell whose distance from `pos` is
-- closest to `cells` away (adapts to the map — on a small map the ring of
-- exactly `cells` would be off-map, so we just take the best it can do)
local function entityToArea(pos, cells)
	local GRID = attr("GRID", 40)
	local CELL = attr("CELL", 24)
	local O = attr("ORIGIN", -480)
	local e = workspace:FindFirstChild("Entity")
	if not (e and e.PrimaryPart) then return end

	local pits = pitRects()
	local target = cells * CELL
	local bx, bz, bfy, bestScore
	for _ = 1, 150 do
		local x = math.random(2, GRID - 1)
		local z = math.random(2, GRID - 1)
		local cx = O + (x - 0.5) * CELL
		local cz = O + (z - 0.5) * CELL
		local fy = floorY(cx, cz)
		if fy and not inAnyPit(cx, cz, pits) then -- never onto a pit beam (it'd trap it)
			local dx, dz = cx - pos.X, cz - pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d >= 2 * CELL then -- never right on top of the player
				local score = math.abs(d - target)
				if not bestScore or score < bestScore then
					bx, bz, bfy, bestScore = cx, cz, fy, score
				end
			end
		end
	end
	if bx then
		-- place the model so its FEET rest on the floor, whatever its size
		local bbox, size = e:GetBoundingBox()
		local pivot = e:GetPivot()
		local bottomToPivot = pivot.Y - (bbox.Y - size.Y / 2)
		e:PivotTo(CFrame.new(bx, bfy + 0.5 + bottomToPivot, bz))
	end
end

-- ── builders (placeholder shapes) ─────────────────────────
local function makeFuse(pos, folder)
	local p = Instance.new("Part")
	p.Name = "Fuse"
	p.Size = Vector3.new(1, 2, 0.7)
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(250, 220, 90)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 1.4, 0))
	local pl = Instance.new("PointLight")
	pl.Range = 9; pl.Brightness = 2; pl.Color = p.Color; pl.Parent = p
	local pp = makePrompt(p, "Pick up", "Fuse", 8)
	p.Parent = folder
	return p, pp
end

local function build(cf, size, off, color, material, folder, name)
	local p = Instance.new("Part")
	p.Name = name or "Part"
	p.Size = size
	p.Anchored = true
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CFrame = cf * off
	p.Parent = folder
	return p
end

local function makeBox(cf, folder)
	local model = Instance.new("Model")
	model.Name = "FuseBox"
	-- mounted flush on the wall (front = -Z into the room)
	local body = build(cf, Vector3.new(3, 3, 1), CFrame.new(0, 0, -0.5),
		Color3.fromRGB(70, 70, 75), Enum.Material.Metal, model, "Body")
	local ind = build(cf, Vector3.new(0.8, 0.8, 0.2), CFrame.new(0.9, 0.9, -1.02),
		Color3.fromRGB(200, 40, 40), Enum.Material.Neon, model, "Indicator")
	ind.CanQuery = false -- must not block the prompt's / entity's line of sight
	local pp = makePrompt(body, "Insert Fuse", "Fuse Box (0/" .. FUSES_PER_BOX .. ")", 9)
	model.Parent = folder
	return { model = model, cf = cf, body = body, ind = ind, prompt = pp, count = 0, complete = false }
end

local function makeLever(cf, folder)
	local model = Instance.new("Model")
	model.Name = "Lever"
	local plate = build(cf, Vector3.new(2, 3, 0.4), CFrame.new(0, 0, -0.2),
		Color3.fromRGB(60, 60, 65), Enum.Material.Metal, model, "Plate")
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.8, 0.4)
	handle.Anchored = true
	handle.Color = Color3.fromRGB(160, 30, 30)
	handle.CFrame = cf * CFrame.new(0, 0.2, -0.6) * CFrame.Angles(math.rad(35), 0, 0)
	handle.CanQuery = false -- red handle must not block line of sight to the prompt
	handle.Parent = model
	-- put the prompt on an invisible anchor set OUT IN FRONT of the handle, so
	-- the protruding red handle can never sit between the player and the prompt
	-- (the line-of-sight check still hits real walls → no interacting through them)
	local anchor = Instance.new("Part")
	anchor.Name = "Interact"
	anchor.Size = Vector3.new(2, 3, 0.3)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = cf * CFrame.new(0, 0.2, -1.4)
	anchor.Parent = model
	local pp = makePrompt(anchor, "Pull Lever", "Lever (locked)", 9)
	pp.Enabled = false
	model.Parent = folder
	-- no own indicator: the status-light column already shows this lever's state
	return { model = model, cf = cf, plate = plate, handle = handle, prompt = pp, activeUntil = 0 }
end

local function setLeverHandle(lever, pulled)
	local a = pulled and -35 or 35
	lever.handle.CFrame = lever.cf * CFrame.new(0, 0.2, -0.6) * CFrame.Angles(math.rad(a), 0, 0)
end

local function makeExit(cf, folder)
	local model = Instance.new("Model")
	model.Name = "Exit"
	-- a doorway set into the (outer) wall, opening inward
	build(cf, Vector3.new(0.8, 12, 1), CFrame.new(-3.6, 2, -0.5),
		Color3.fromRGB(25, 40, 30), Enum.Material.Metal, model, "PostL")
	build(cf, Vector3.new(0.8, 12, 1), CFrame.new(3.6, 2, -0.5),
		Color3.fromRGB(25, 40, 30), Enum.Material.Metal, model, "PostR")
	build(cf, Vector3.new(8, 1, 1), CFrame.new(0, 8, -0.5),
		Color3.fromRGB(25, 40, 30), Enum.Material.Metal, model, "Top")
	local sign = build(cf, Vector3.new(7, 11, 0.4), CFrame.new(0, 2, -0.75),
		Color3.fromRGB(20, 60, 35), Enum.Material.Neon, model, "Sign") -- dim until open
	sign.CanCollide = false
	local light = Instance.new("PointLight")
	light.Range = 0; light.Brightness = 0; light.Color = Color3.fromRGB(70, 255, 130)
	light.Parent = sign
	local trig = build(cf, Vector3.new(7, 11, 3), CFrame.new(0, 2, -1.4),
		Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, model, "Trigger")
	trig.CanCollide = false; trig.Transparency = 1
	model.Parent = folder
	return { model = model, sign = sign, light = light, trig = trig, open = false }
end

-- the SAFE ROOM you step into through the exit — a sealed elevator-style cabin
-- built far OUTSIDE the maze, so the entity (barriered into the maze, no navmesh
-- out here) can never reach it. For now it just looks like the start elevator, so
-- escaping reads as "you looped"; later this becomes the level-2 start room.
local function makeSafeRoom()
	-- persistent: parented to workspace, NOT the puzzle folder. On a win
	-- GameManager flips RoundActive off → clearPuzzle destroys the puzzle folder,
	-- so a room parented there would vanish out from under the escaped player
	-- (they'd fall until respawn). This survives until the next round rebuilds it.
	local existing = workspace:FindFirstChild("SafeRoom")
	if existing then existing:Destroy() end
	local O = attr("ORIGIN", -480)
	local cx, cz = O - 120, 0 -- well west of the maze, out of the entity's world
	local model = Instance.new("Model")
	model.Name = "SafeRoom"

	local STEEL      = Color3.fromRGB(118, 122, 128)
	local STEEL_DARK = Color3.fromRGB(88, 92, 98)
	local MARBLE     = Color3.fromRGB(24, 24, 28)
	local W, D, H = 16, 14, 11 -- interior width / depth / height

	local function sp(pos, size, color, mat)
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = CFrame.new(pos)
		p.Color = color
		p.Material = mat or Enum.Material.Metal
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	sp(Vector3.new(cx, 0, cz), Vector3.new(W, 1, D), MARBLE, Enum.Material.Marble)          -- floor
	sp(Vector3.new(cx, H, cz), Vector3.new(W, 1, D), STEEL_DARK)                            -- ceiling
	sp(Vector3.new(cx - W / 2, H / 2, cz), Vector3.new(1, H, D), STEEL)                     -- back (west)
	sp(Vector3.new(cx, H / 2, cz - D / 2), Vector3.new(W, H, 1), STEEL)                     -- south
	sp(Vector3.new(cx, H / 2, cz + D / 2), Vector3.new(W, H, 1), STEEL)                     -- north
	-- east face: header + two closed steel doors (the "elevator" you arrive in)
	sp(Vector3.new(cx + W / 2, H - 1.5, cz), Vector3.new(1, 3, D), STEEL)                   -- header
	sp(Vector3.new(cx + W / 2, (H - 3) / 2, cz - D / 4), Vector3.new(1, H - 3, D / 2), STEEL_DARK) -- door L
	sp(Vector3.new(cx + W / 2, (H - 3) / 2, cz + D / 4), Vector3.new(1, H - 3, D / 2), STEEL_DARK) -- door R

	local panel = sp(Vector3.new(cx, H - 0.6, cz), Vector3.new(3, 0.3, 3),
		Color3.fromRGB(255, 250, 230), Enum.Material.Neon)
	local lamp = Instance.new("PointLight")
	lamp.Brightness = 1.5; lamp.Range = 26; lamp.Color = Color3.fromRGB(255, 240, 210)
	lamp.Parent = panel

	model.Parent = workspace
	return CFrame.new(cx, 3.5, cz) -- where the escaping player lands
end

-- ── round lifecycle ───────────────────────────────────────
local function clearPuzzle()
	if not session then return end
	session.active = false
	for _, c in ipairs(session.conns) do pcall(function() c:Disconnect() end) end
	if session.folder then session.folder:Destroy() end
	session = nil
	workspace:SetAttribute("LightMode", "NORMAL")
	workspace:SetAttribute("FlickerBoost", 0)
	workspace:SetAttribute("EntitySpeedMul", 1)
end

local function startPuzzle()
	clearPuzzle()

	local n = math.max(#Players:GetPlayers(), 1)
	local boxCount = n
	local fusesNeeded = boxCount * FUSES_PER_BOX
	local fuseCount = fusesNeeded * SPAWN_MULT
	local leverCount = n

	local folder = Instance.new("Folder")
	folder.Name = "PuzzleItems"
	folder.Parent = workspace

	session = {
		active = true, stage = "fuses", conns = {}, folder = folder,
		boxes = {}, levers = {}, carried = {}, exit = nil,
		boxesDone = 0, boxCount = boxCount, latchMode = false,
	}

	-- fuses on the ground, spread across the map
	for _, pos in ipairs(pickFloorSpots(fuseCount, 40)) do
		local part, pp = makeFuse(pos, folder)
		table.insert(session.conns, pp.Triggered:Connect(function(player)
			if not session or not session.active or not part.Parent then return end
			part:Destroy()
			session.carried[player] = (session.carried[player] or 0) + 1
			status:FireClient(player, "carry", session.carried[player])
		end))
	end

	-- keep the interactive stations (boxes / levers / exit) well apart from
	-- EACH OTHER, not just within their own type — one shared avoid list
	local CELLv = attr("CELL", 24)
	local SIZEv = attr("GRID", 40) * CELLv
	local stations = {}

	-- fuse boxes on walls, spread apart
	for _, cf in ipairs(pickWallSpots(boxCount, 4 * CELLv, false, stations)) do
		local box = makeBox(cf, folder)
		table.insert(session.boxes, box)
		table.insert(session.conns, box.prompt.Triggered:Connect(function(player)
			if not session or not session.active or box.complete then return end
			local have = session.carried[player] or 0
			if have <= 0 then
				status:FireClient(player, "msg", "You have no fuses")
				return
			end
			session.carried[player] = have - 1
			status:FireClient(player, "carry", session.carried[player])
			box.count += 1
			box.prompt.ObjectText = ("Fuse Box (%d/%d)"):format(box.count, FUSES_PER_BOX)

			-- ramp the danger; the entity shows up in the AREA (not on top of you)
			workspace:SetAttribute("FlickerBoost",
				math.min(attr("FlickerBoost", 0) + FLICK_PER_FUSE, 4))
			-- fuse boxes ramp the entity's speed by at most +10% total (the big
			-- finale boost happens later, when the exit opens: END_SPEED_MUL)
			workspace:SetAttribute("EntitySpeedMul",
				math.min(attr("EntitySpeedMul", 1) + SPEED_PER_FUSE, 1.1))
			-- summon the entity to the AREA — but NOT if it's already near the
			-- player (don't teleport it right on top of them / it's already here)
			local pchar = player.Character
			local phrp = pchar and pchar:FindFirstChild("HumanoidRootPart")
			local ent = workspace:FindFirstChild("Entity")
			local eroot = ent and ent.PrimaryPart
			local alreadyNear = phrp and eroot
				and (phrp.Position - eroot.Position).Magnitude < ENTITY_AREA_CELLS * CELLv
			if not alreadyNear then
				entityToArea(box.body.Position, ENTITY_AREA_CELLS)
			end

			if box.count >= FUSES_PER_BOX then
				box.complete = true
				box.prompt.Enabled = false
				box.ind.Color = Color3.fromRGB(50, 220, 60)
				session.boxesDone += 1
				status:FireAllClients("boxes", session.boxesDone, session.boxCount)
				if session.boxesDone >= session.boxCount then
					session.onAllBoxes()
				end
			end
		end))
	end
	session.boxCount = #session.boxes -- target = boxes actually placed

	-- tell the clients to show the HUD NOW (before the heavier lever/wire build),
	-- so the PuzzleUI doesn't lag behind the round start
	status:FireAllClients("begin", session.boxCount * FUSES_PER_BOX, session.boxCount)

	-- levers on walls near the edges, far apart, locked until the boxes are done
	local leverSpacing = math.max(6 * CELLv, 0.22 * SIZEv)
	for _, cf in ipairs(pickWallSpots(leverCount, leverSpacing, true, stations)) do
		local lever = makeLever(cf, folder)
		table.insert(session.levers, lever)
		table.insert(session.conns, lever.prompt.Triggered:Connect(function()
			if not session or not session.active or session.stage ~= "levers" then return end
			if lever.latched then return end

			if session.latchMode then
				lever.latched = true          -- clutch: flip-and-stays, no timer
				lever.prompt.Enabled = false
			else
				lever.activeUntil = os.clock() + LEVER_WINDOW
			end
			setLeverHandle(lever, true)
			status:FireAllClients("lever")
			if session.updateLeverLights then session.updateLeverLights() end

			-- a lever counts as ON if it's latched OR still inside its window
			local all = true
			for _, lv in ipairs(session.levers) do
				if not (lv.latched or os.clock() < lv.activeUntil) then all = false break end
			end
			if all then session.onLevers() end

			-- temporary (non-latched) levers reset when their window lapses
			if not lever.latched then
				task.delay(LEVER_WINDOW + 0.1, function()
					if session and session.active and session.stage == "levers"
						and not lever.latched and os.clock() >= lever.activeUntil then
						setLeverHandle(lever, false)
						if session.updateLeverLights then session.updateLeverLights() end
					end
				end)
			end
		end))
	end

	-- CLUTCH: when a teammate dies or leaves, their lever latches ON for good and
	-- the levers stop needing the 10s simultaneity — survivors just flip the rest
	-- at their own pace (coordination gets unfair as the party shrinks)
	local function onParticipantDown(reason)
		if not session or not session.active then return end
		if session.latchMode then return end -- already clutched; don't re-log
		-- a death only DROPS the 10s simultaneity requirement — levers now
		-- flip-and-STAY. It does NOT turn any lever on: survivors still have to
		-- find and pull every lever themselves, just without the timing pressure.
		-- (If levers "stay on with nobody dead", this print will name the cause —
		-- usually a teammate you didn't see die, since there's no alive count.)
		print("[Puzzle] Clutch engaged (" .. tostring(reason) ..
			"): levers are now flip-and-stay, 10s sync dropped")
		session.latchMode = true
		-- lock in any lever currently being held so it can't time out on them
		for _, lv in ipairs(session.levers) do
			if not lv.latched and os.clock() < lv.activeUntil then
				lv.latched = true
				lv.prompt.Enabled = false
			end
		end
		if session.updateLeverLights then session.updateLeverLights() end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			table.insert(session.conns, hum.Died:Connect(function()
				onParticipantDown("death: " .. p.Name)
			end))
		end
	end
	table.insert(session.conns, Players.PlayerRemoving:Connect(function(lp)
		onParticipantDown("left: " .. lp.Name)
	end))

	-- ── lever status lights: each lever wears a row showing EVERY lever's state
	do
		local N = #session.levers
		for _, lv in ipairs(session.levers) do
			lv.statusLights = {}
			for j = 1, N do
				-- one light per lever, stacked DOWN a column on the side of the
				-- plate; past 4 it starts a second column on the other side
				local col = math.floor((j - 1) / 4) -- 0 = left, 1 = right
				local row = (j - 1) % 4
				local ox = (col == 0) and -0.7 or 0.7
				local oy = 1.05 - row * 0.6
				lv.statusLights[j] = build(lv.cf, Vector3.new(0.32, 0.32, 0.15),
					CFrame.new(ox, oy, -0.5),
					Color3.fromRGB(120, 20, 20), Enum.Material.Neon, lv.model, "Status")
				lv.statusLights[j].CanQuery = false
			end
		end
	end

	function session.updateLeverLights()
		if not session then return end
		for _, lv in ipairs(session.levers) do
			if lv.statusLights then
				for j, sl in ipairs(lv.statusLights) do
					local other = session.levers[j]
					local on = other and (other.latched or os.clock() < other.activeUntil)
					sl.Color = on and Color3.fromRGB(50, 220, 60) or Color3.fromRGB(120, 20, 20)
				end
			end
		end
	end
	session.updateLeverLights()

	-- ── fuse box → lever wire: a glowing floor cable you can follow, plus
	-- matching coloured tags on the box and its paired lever
	-- bold, distinct "wire" colours (pair 1 = red)
	local WIRE_COLORS = {
		Color3.fromRGB(230, 40, 40),  -- red
		Color3.fromRGB(50, 120, 255), -- blue
		Color3.fromRGB(50, 200, 70),  -- green
		Color3.fromRGB(240, 210, 40), -- yellow
		Color3.fromRGB(210, 70, 230), -- purple
		Color3.fromRGB(0, 210, 210),  -- cyan
	}

	local GRIDn = attr("GRID", 40)
	local CELLn = attr("CELL", 24)
	local On = attr("ORIGIN", -480)
	local WALLHn = attr("WALL_H", 14)  -- ceiling height, for routing over pits
	local wirePits = pitRects()        -- pit fields a floor cable can't cross
	local mazeModel = workspace:FindFirstChild("Maze")

	local function cellWorld(x, z) return On + (x - 0.5) * CELLn, On + (z - 0.5) * CELLn end
	local function cellOf(p)
		return math.clamp(math.floor((p.X - On) / CELLn) + 1, 1, GRIDn),
			math.clamp(math.floor((p.Z - On) / CELLn) + 1, 1, GRIDn)
	end
	local function frontCell(cf)
		local p = (cf * CFrame.new(0, 0, -3)).Position
		return cellOf(p)
	end

	-- can you walk straight between two adjacent cells (no wall between)? memoised
	local openCache = {}
	local function openBetween(x, z, nx, nz)
		local k = x .. "," .. z .. ">" .. nx .. "," .. nz
		if openCache[k] ~= nil then return openCache[k] end
		local ax, az = cellWorld(x, z)
		local bx, bz = cellWorld(nx, nz)
		local fya, fyb = floorY(ax, az), floorY(bx, bz)
		local res = false
		if fya and fyb and mazeModel then
			local a = Vector3.new(ax, fya + 3, az)
			local b = Vector3.new(bx, fyb + 3, bz)
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Include
			rp.FilterDescendantsInstances = { mazeModel }
			res = workspace:Raycast(a, b - a, rp) == nil
		end
		openCache[k] = res
		return res
	end

	-- BFS on the maze grid → list of cells (axis-aligned steps only, never diagonal)
	local function gridPath(sx, sz, gx, gz)
		local key = function(x, z) return x .. "," .. z end
		local q, seen, prev, head = { { sx, sz } }, { [key(sx, sz)] = true }, {}, 1
		while head <= #q do
			local cur = q[head]; head += 1
			if cur[1] == gx and cur[2] == gz then break end
			for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local nx, nz = cur[1] + d[1], cur[2] + d[2]
				if nx >= 1 and nx <= GRIDn and nz >= 1 and nz <= GRIDn
					and not seen[key(nx, nz)] and openBetween(cur[1], cur[2], nx, nz) then
					seen[key(nx, nz)] = true
					prev[key(nx, nz)] = cur
					q[#q + 1] = { nx, nz }
				end
			end
		end
		if not seen[key(gx, gz)] then return nil end
		local path, cur = {}, { gx, gz }
		while cur do
			table.insert(path, 1, cur)
			cur = prev[key(cur[1], cur[2])]
		end
		return path
	end

	local function turningPoints(cells)
		if #cells <= 2 then return cells end
		local turns = { cells[1] }
		for i = 2, #cells - 1 do
			local a, b, c = cells[i - 1], cells[i], cells[i + 1]
			if (b[1] - a[1]) ~= (c[1] - b[1]) or (b[2] - a[2]) ~= (c[2] - b[2]) then
				turns[#turns + 1] = b
			end
		end
		turns[#turns + 1] = cells[#cells]
		return turns
	end

	-- offset a straight run toward the nearer perpendicular wall (~2 studs off)
	local function runOffset(a, b)
		local along = (math.abs(b.X - a.X) > math.abs(b.Z - a.Z)) and "X" or "Z"
		local mid = (a + b) / 2
		local origin = Vector3.new(mid.X, (floorY(mid.X, mid.Z) or 0) + 3, mid.Z)
		local pDir = (along == "X") and Vector3.new(0, 0, 1) or Vector3.new(1, 0, 0)
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		rp.FilterDescendantsInstances = { mazeModel }
		local hp = workspace:Raycast(origin, pDir * CELLn, rp)
		local hm = workspace:Raycast(origin, -pDir * CELLn, rp)
		local dp = hp and (hp.Position - origin).Magnitude or math.huge
		local dm = hm and (hm.Position - origin).Magnitude or math.huge
		if dp <= dm and hp then return along, math.max(dp - 2, 0)
		elseif hm then return along, -math.max(dm - 2, 0)
		else return along, 0 end
	end

	-- one short piece of matte cable between two fixed points
	local function layPiece(a, b, color)
		local len = (b - a).Magnitude
		if len <= 0.05 then return end
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.Material = Enum.Material.SmoothPlastic
		seg.Color = color
		seg.Size = Vector3.new(0.25, 0.06, len)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		seg.Parent = folder
	end

	-- lay cable from a→b RIDING THE ACTUAL FLOOR, breaking over holes so it never
	-- floats across a pit — it sits on the beams instead. Solid runs stay a single
	-- part (fast path); only pit-crossing runs get subdivided.
	local function laySeg(a, b, color)
		local total = (b - a).Magnitude
		if total <= 0.05 then return end
		local dir = b - a
		local checks = math.max(2, math.floor(total / 6))
		local simple = true
		for i = 0, checks do
			local p = a + dir * (i / checks)
			if not floorY(p.X, p.Z) then simple = false break end
		end
		if simple then
			layPiece(
				Vector3.new(a.X, (floorY(a.X, a.Z) or 0) + 0.06, a.Z),
				Vector3.new(b.X, (floorY(b.X, b.Z) or 0) + 0.06, b.Z), color)
			return
		end
		-- crosses a hole field: step along, follow the floor, skip the gaps
		local steps = math.max(1, math.ceil(total / 3))
		local prev = nil
		for i = 0, steps do
			local p = a + dir * (i / steps)
			local fy = floorY(p.X, p.Z)
			if fy then
				local gp = Vector3.new(p.X, fy + 0.06, p.Z)
				if prev then layPiece(prev, gp, color) end
				prev = gp
			else
				prev = nil -- over a hole → break the cable (don't bridge the void)
			end
		end
	end

	-- a vertical riser (the cable climbing the wall up into a box / lever)
	local function layRiser(x, z, y0, y1, color)
		local len = math.abs(y1 - y0)
		if len <= 0.05 then return end
		local seg = Instance.new("Part")
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.Material = Enum.Material.SmoothPlastic
		seg.Color = color
		seg.Size = Vector3.new(0.25, len, 0.25)
		seg.CFrame = CFrame.new(x, (y0 + y1) / 2, z)
		seg.Parent = folder
	end

	-- run the cable from a floor vertex to directly under the wall object, then
	-- UP into it, so it reads as actually connected (not just stopping nearby)
	local function connectEnd(endVert, cf, color)
		local ev = Vector3.new(endVert.X, (floorY(endVert.X, endVert.Z) or 0) + 0.06, endVert.Z)
		-- floor point flush against the wall, right under the object
		local foot = (cf * CFrame.new(0, 0, -0.12)).Position
		local y0 = ev.Y
		-- 90° L along the floor (X leg, then Z leg) — reach the wall base
		local corner = Vector3.new(foot.X, y0, ev.Z)
		laySeg(ev, corner, color)
		laySeg(corner, Vector3.new(foot.X, y0, foot.Z), color)
		-- climb the wall and STOP at the object's bottom (cf.Y is the centre,
		-- body ~3 tall → bottom is 1.5 below) so it vanishes into it, no overshoot
		layRiser(foot.X, foot.Z, y0, cf.Position.Y - 1.5, color)
	end

	-- does a straight floor run pass over a pit (no floor under it)?
	local function segCrossesPit(a, b)
		local dx, dz = b.X - a.X, b.Z - a.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		local steps = math.max(2, math.floor(dist / 4))
		for s = 0, steps do
			local t = s / steps
			local x, z = a.X + dx * t, a.Z + dz * t
			if inAnyPit(x, z, wirePits) or floorY(x, z) == nil then return true end
		end
		return false
	end

	-- a run that would cross a pit instead climbs the wall, runs across the
	-- CEILING, and drops back down on the far side (so it never floats over/into
	-- the void). a,b are the raw (y=0) floor vertices.
	local function layOverhead(a, b, color)
		local ay = (floorY(a.X, a.Z) or 0) + 0.06
		local by = (floorY(b.X, b.Z) or 0) + 0.06
		local topY = WALLHn - 0.4 -- just under the ceiling slab
		layRiser(a.X, a.Z, ay, topY, color)
		-- layPiece (NOT laySeg): a fixed straight part that ignores the floor, so
		-- it stays up at the ceiling across the void instead of dropping into it
		layPiece(Vector3.new(a.X, topY, a.Z), Vector3.new(b.X, topY, b.Z), color)
		layRiser(b.X, b.Z, by, topY, color)
	end

	-- fallback when the grid BFS can't route (e.g. a station tucked in an odd
	-- spot): a plain right-angle L on the floor so a wire ALWAYS appears
	local function layWireDirect(fromCF, toCF, color)
		local a = (fromCF * CFrame.new(0, 0, -3)).Position
		local b = (toCF * CFrame.new(0, 0, -3)).Position
		local y = (floorY(a.X, a.Z) or 0) + 0.06
		local p1 = Vector3.new(a.X, y, a.Z)
		local corner = Vector3.new(b.X, y, a.Z)
		local p2 = Vector3.new(b.X, y, b.Z)
		laySeg(p1, corner, color)
		laySeg(corner, p2, color)
		connectEnd(p1, fromCF, color)
		connectEnd(p2, toCF, color)
	end

	local function layWire(fromCF, toCF, color)
		if not mazeModel then return end
		local sx, sz = frontCell(fromCF)
		local gx, gz = frontCell(toCF)
		local cells = gridPath(sx, sz, gx, gz)
		if not cells or #cells < 2 then
			layWireDirect(fromCF, toCF, color) -- BFS failed → guarantee a wire
			return
		end
		local turns = turningPoints(cells)

		local W = {}
		for _, t in ipairs(turns) do
			local wx, wz = cellWorld(t[1], t[2])
			W[#W + 1] = Vector3.new(wx, 0, wz)
		end

		-- per-segment perpendicular offset (hug the wall)
		local axis, konst = {}, {}
		for i = 1, #W - 1 do
			local al, off = runOffset(W[i], W[i + 1])
			axis[i] = al
			konst[i] = (al == "X") and ((W[i].Z + W[i + 1].Z) / 2 + off)
				or ((W[i].X + W[i + 1].X) / 2 + off)
		end

		-- vertices: start · corners (offset-line intersections) · end — all 90°
		local verts = {}
		verts[1] = (axis[1] == "X") and Vector3.new(W[1].X, 0, konst[1])
			or Vector3.new(konst[1], 0, W[1].Z)
		for i = 1, #axis - 1 do
			if axis[i] == "X" then
				verts[#verts + 1] = Vector3.new(konst[i + 1], 0, konst[i])
			else
				verts[#verts + 1] = Vector3.new(konst[i], 0, konst[i + 1])
			end
		end
		local L = #axis
		verts[#verts + 1] = (axis[L] == "X") and Vector3.new(W[#W].X, 0, konst[L])
			or Vector3.new(konst[L], 0, W[#W].Z)

		for i = 1, #verts - 1 do
			if segCrossesPit(verts[i], verts[i + 1]) then
				layOverhead(verts[i], verts[i + 1], color) -- up wall, over ceiling, down
			else
				local a = Vector3.new(verts[i].X, (floorY(verts[i].X, verts[i].Z) or 0) + 0.06, verts[i].Z)
				local b = Vector3.new(verts[i + 1].X, (floorY(verts[i + 1].X, verts[i + 1].Z) or 0) + 0.06, verts[i + 1].Z)
				laySeg(a, b, color)
			end
		end

		-- tie both ends up into the box and the lever
		connectEnd(verts[1], fromCF, color)
		connectEnd(verts[#verts], toCF, color)
	end

	for i, box in ipairs(session.boxes) do
		local lever = session.levers[i]
		if lever then
			local color = WIRE_COLORS[((i - 1) % #WIRE_COLORS) + 1]
			layWire(box.cf, lever.cf, color)
		end
	end

	-- exit: a doorway in the OUTER BORDER wall (you're actually leaving), dim
	-- and closed until the levers are pulled
	local exitCF = pickExitOnBorder(stations, 5 * CELLv) or CFrame.new(0, 4, 0)
	session.exit = makeExit(exitCF, folder)
	session.safeSpawn = makeSafeRoom() -- the room you step into through the exit
	table.insert(session.conns, session.exit.trig.Touched:Connect(function(hit)
		if not session or not session.exit.open then return end
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if p then
			-- step INTO the safe room the entity can't reach (reads as looping back
			-- into the elevator for now; becomes the level-2 start room later)
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and session.safeSpawn then hrp.CFrame = session.safeSpawn end
			status:FireAllClients("win")
			workspace:SetAttribute("PuzzleWon", true) -- GameManager ends the round
		end
	end))

	table.insert(session.conns, Players.PlayerRemoving:Connect(function(p)
		if session then session.carried[p] = nil end
	end))

	function session.onAllBoxes()
		if session.stage ~= "fuses" then return end
		session.stage = "levers"
		for _, lv in ipairs(session.levers) do
			lv.prompt.Enabled = true
			lv.prompt.ObjectText = "Lever"
		end
		status:FireAllClients("levers")

		-- keep the status rows accurate as temporary levers' windows lapse
		task.spawn(function()
			while session and session.active and session.stage == "levers" do
				if session.updateLeverLights then session.updateLeverLights() end
				task.wait(0.5)
			end
		end)

		task.spawn(function()
			local first = true
			while session and session.active and session.stage == "levers" do
				task.wait(ALERT_INTERVAL)
				if not (session and session.active and session.stage == "levers") then break end
				local chance = first and ALERT_FIRST or ALERT_AFTER
				first = false
				if math.random() < chance then
					workspace:SetAttribute("LightMode", "ALERT")
					status:FireAllClients("alert")
					task.wait(ALERT_TIME)
					if session and session.active and session.stage == "levers" then
						workspace:SetAttribute("LightMode", "NORMAL")
						status:FireAllClients("alertEnd")
					end
				end
			end
		end)
	end

	function session.onLevers()
		if session.stage ~= "levers" then return end
		session.stage = "end"
		workspace:SetAttribute("LightMode", "BLACKOUT")
		workspace:SetAttribute("EntitySpeedMul", END_SPEED_MUL)

		local ex = session.exit
		ex.open = true
		ex.sign.Color = Color3.fromRGB(45, 255, 110)
		ex.light.Range = 40
		ex.light.Brightness = 3
		entityToArea(ex.sign.Position, 3) -- it guards the way out (close by)

		status:FireAllClients("exit")
	end
end

-- watch the round flag set by GameManager
workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") then
		startPuzzle()
	else
		clearPuzzle()
	end
end)

if workspace:GetAttribute("RoundActive") then startPuzzle() end
