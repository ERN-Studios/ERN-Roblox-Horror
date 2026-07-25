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
local ENTITY_AREA_CELLS = 10 -- entity appears ~this many cells from the box
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
	pp.RequiresLineOfSight = false
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
	local pp = makePrompt(body, "Insert Fuse", "Fuse Box (0/" .. FUSES_PER_BOX .. ")", 9)
	model.Parent = folder
	return { model = model, body = body, ind = ind, prompt = pp, count = 0, complete = false }
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
	handle.Parent = model
	local ind = build(cf, Vector3.new(0.5, 0.5, 0.2), CFrame.new(0.7, 1.1, -0.35),
		Color3.fromRGB(200, 40, 40), Enum.Material.Neon, model, "Indicator")
	local pp = makePrompt(plate, "Pull Lever", "Lever (locked)", 9)
	pp.Enabled = false
	model.Parent = folder
	return { model = model, cf = cf, plate = plate, handle = handle, ind = ind, prompt = pp, activeUntil = 0 }
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
			workspace:SetAttribute("EntitySpeedMul",
				math.min(attr("EntitySpeedMul", 1) + SPEED_PER_FUSE, 1.5))
			entityToArea(box.body.Position, ENTITY_AREA_CELLS)

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
			lever.ind.Color = Color3.fromRGB(50, 220, 60) -- GREEN: tell your team
			setLeverHandle(lever, true)
			status:FireAllClients("lever")

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
						lever.ind.Color = Color3.fromRGB(200, 40, 40)
						setLeverHandle(lever, false)
					end
				end)
			end
		end))
	end

	-- CLUTCH: when a teammate dies or leaves, their lever latches ON for good and
	-- the levers stop needing the 10s simultaneity — survivors just flip the rest
	-- at their own pace (coordination gets unfair as the party shrinks)
	local function onParticipantDown()
		if not session or not session.active then return end
		session.latchMode = true
		-- lock in any lever currently being held so it can't time out
		for _, lv in ipairs(session.levers) do
			if not lv.latched and os.clock() < lv.activeUntil then
				lv.latched = true
				lv.prompt.Enabled = false
			end
		end
		-- latch one more — the fallen teammate's lever
		for _, lv in ipairs(session.levers) do
			if not lv.latched then
				lv.latched = true
				lv.ind.Color = Color3.fromRGB(50, 220, 60)
				setLeverHandle(lv, true)
				lv.prompt.Enabled = false
				break
			end
		end
		-- maybe that was the last one needed
		if session.stage == "levers" then
			local all = true
			for _, lv in ipairs(session.levers) do
				if not (lv.latched or os.clock() < lv.activeUntil) then all = false break end
			end
			if all then session.onLevers() end
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			table.insert(session.conns, hum.Died:Connect(onParticipantDown))
		end
	end
	table.insert(session.conns, Players.PlayerRemoving:Connect(onParticipantDown))

	-- exit: a doorway in the OUTER BORDER wall (you're actually leaving), dim
	-- and closed until the levers are pulled
	local exitCF = pickExitOnBorder(stations, 5 * CELLv) or CFrame.new(0, 4, 0)
	session.exit = makeExit(exitCF, folder)
	table.insert(session.conns, session.exit.trig.Touched:Connect(function(hit)
		if not session or not session.exit.open then return end
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if p then
			status:FireAllClients("win")
			workspace:SetAttribute("PuzzleWon", true) -- GameManager ends the round
		end
	end))

	table.insert(session.conns, Players.PlayerRemoving:Connect(function(p)
		if session then session.carried[p] = nil end
	end))

	status:FireAllClients("begin", session.boxCount * FUSES_PER_BOX, session.boxCount)

	function session.onAllBoxes()
		if session.stage ~= "fuses" then return end
		session.stage = "levers"
		for _, lv in ipairs(session.levers) do
			lv.prompt.Enabled = true
			lv.prompt.ObjectText = "Lever"
		end
		status:FireAllClients("levers")

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
