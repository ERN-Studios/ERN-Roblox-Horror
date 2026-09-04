-- PuzzleManager  (v2 — wall-mounted boxes/levers, edge exit)
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "PuzzleManager"
--
-- The win objective. Per player: 2 fuse relays spawn, 1 fuse box, 1 lever.
--   • Fuses are extracted from wall-mounted ZYNTRA relays. Extraction opens
--     the cabinet, flickers nearby lights, and emits noise that attracts Entity.
--   • Fuse boxes are MOUNTED ON WALLS and need 1 fuse each. Inserting one ramps
--     the danger (more flicker, faster entity) and makes the entity appear in
--     that AREA (~10 cells away — near, not on top of you).
--   • Every box full → the levers unlock. They're on walls near the map edges,
--     spread apart, so the party must split. Flick them ALL within 10s.
--   • Flicking a lever turns its light green (a signal to teammates on voice).
--   • Once every box is full the maze goes into permanent ALERT: red pulsing
--     lights + sound until the levers finish the job.
--   • All levers together → lights go dark (a few faintly stay on; the entity is
--     a blinking beacon), the EXIT opens in the outer wall, and the entity moves
--     to guard it. Reach the exit to win.
--
-- Placeholder shapes for now — model Fuse / FuseBox / Lever / Exit later, keep
-- the names. Requires MazeGenerator (publishes maze attributes) + GameManager
-- (sets RoundActive).

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local status = RS:WaitForChild("Remotes"):WaitForChild("PuzzleStatus")
-- ServerScriptService, not script.Parent: this script moved into the
-- "Level 1 Systems" folder on 2026-09-02 and NoiseRegistry stayed in the root.
local NoiseRegistry = require(game:GetService("ServerScriptService"):WaitForChild("NoiseRegistry"))

-- The party-wide escape announcement, on the SHARED RoundStatus remote that
-- Level 2 and Level 3 already fire (PuzzleStatus above only drives this level's
-- own objective HUD). Level 1 never fired it, so its party learned who got out
-- only at the result screen -- and only ever about the first one. Per recipient
-- and in-round only, the same shape both other levels use: a lobby player has no
-- business hearing a reserved round's escapes.
local function fireEscapeStatus(player)
	local remotes = RS:FindFirstChild("Remotes")
	local roundStatus = remotes and remotes:FindFirstChild("RoundStatus")
	if not roundStatus or not roundStatus:IsA("RemoteEvent") then return end
	for _, recipient in ipairs(Players:GetPlayers()) do
		if recipient:GetAttribute("InRound") == true then
			roundStatus:FireClient(recipient, "escape", player.Name)
		end
	end
end

-- ── tuning ────────────────────────────────────────────────
local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))
local FUSES_PER_BOX = 1      -- fuses each box needs
local SPAWN_MULT    = Master.Effective("L1_FuseSpawnMultiplier", 2)  -- fuses spawned = needed x this
local LEVER_WINDOW  = Master.Effective("L1_LeverWindowSeconds", 10)  -- seconds all levers must be on together
local FLICK_PER_FUSE = 0.6   -- FlickerBoost added per fuse inserted
local SPEED_PER_FUSE = Master.Effective("L1_SpeedPerFuse", 0.06)  -- EntitySpeedMul added per fuse
local END_SPEED_MUL  = 1.3   -- entity speed once the exit opens (finale boost)
local ENTITY_AREA_CELLS = 5  -- entity appears ~this many cells from the box
local EDGE_BAND      = 3      -- levers/exit spawn within this many cells of an edge
local RELAY_HOLD_TIME = 1.8   -- deliberate extraction interaction
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

-- Decor is generated before the puzzle. Keep every relay and wall station
-- outside the horizontal footprint of furniture/box piles, including models
-- whose parts deliberately have CanQuery=false for entity line-of-sight.
local function decorClear(pos, clearance)
	local decor = workspace:FindFirstChild("Decor")
	if not decor then return true end
	for _, model in ipairs(decor:GetChildren()) do
		if model:IsA("Model") then
			local cf, size = model:GetBoundingBox()
			local dx = math.max(math.abs(pos.X - cf.X) - size.X * 0.5, 0)
			local dz = math.max(math.abs(pos.Z - cf.Z) - size.Z * 0.5, 0)
			if math.sqrt(dx * dx + dz * dz) < clearance then return false end
		end
	end
	return true
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

	local pits = pitRects()

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
		if inAnyPit(c.X, c.Z, pits) then return nil end
		local fy = floorY(c.X, c.Z)
		if not fy then return nil end
		return Vector3.new(c.X, fy, c.Z)
	end
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
					local ok = decorClear(at, 7)
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
local function updateCarriedFuse(player, count)
	local char = player.Character
	if not char then return end
	local old = char:FindFirstChild("CarriedFuseVisual")
	if old then old:Destroy() end
	if (count or 0) <= 0 then return end

	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then return end

	local visual = Instance.new("Part")
	visual.Name = "CarriedFuseVisual"
	visual.Size = Vector3.new(0.55, 1.45, 0.55)
	visual.Material = Enum.Material.Neon
	visual.Color = Color3.fromRGB(215, 178, 45)
	visual.CanCollide = false
	visual.CanQuery = false
	visual.Massless = true
	visual.CFrame = hand.CFrame * CFrame.new(0, -0.72, -0.12)
	visual.Parent = char

	local capA = Instance.new("Part")
	capA.Name = "Cap"
	capA.Size = Vector3.new(0.68, 0.16, 0.68)
	capA.Material = Enum.Material.Metal
	capA.Color = Color3.fromRGB(75, 72, 62)
	capA.CanCollide = false
	capA.CanQuery = false
	capA.Massless = true
	capA.CFrame = visual.CFrame * CFrame.new(0, 0.78, 0)
	capA.Parent = visual
	local capB = capA:Clone()
	capB.CFrame = visual.CFrame * CFrame.new(0, -0.78, 0)
	capB.Parent = visual

	for _, item in ipairs({visual, capA, capB}) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = item
		weld.Parent = item
	end

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(225, 185, 55)
	glow.Brightness = 1.4
	glow.Range = 11
	glow.Parent = visual

	-- A quick pickup flare, then settle into the normal carried-fuse glow.
	TweenService:Create(glow, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0.35,
		Range = 5,
	}):Play()
end

-- One workspace sweep per puzzle build: every relay reuses the same
-- SurfaceLight inventory instead of re-scanning every workspace descendant
-- once per relay (up to 12 full scans over the finished 40x40 maze).
local surfaceLightCache = nil
local function workspaceSurfaceLights()
	if surfaceLightCache then return surfaceLightCache end
	local list = {}
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("SurfaceLight") then list[#list + 1] = item end
	end
	surfaceLightCache = list
	return list
end

-- Wall-mounted replacement for loose floor fuses. The relay remains in the
-- world after use so its open, empty state tells players it was searched.
local function makeFuseRelay(cf, folder)
	local model = Instance.new("Model")
	model.Name = "FuseRelay"
	model:SetAttribute("ContainsFuse", true)
	model.Parent = folder

	local function relayPart(name, size, offset, color, material, transparency)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Anchored = true
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.Transparency = transparency or 0
		part.CFrame = cf * offset
		part.Parent = model
		return part
	end

	local body = relayPart("RelayBody", Vector3.new(5.4, 6.6, 0.85), CFrame.new(0, 0, -0.43),
		Color3.fromRGB(48, 51, 50), Enum.Material.Metal)
	model.PrimaryPart = body
	relayPart("OuterFrame", Vector3.new(5.85, 7.05, 0.2), CFrame.new(0, 0, -0.96),
		Color3.fromRGB(23, 25, 24), Enum.Material.Metal).CanCollide = false
	relayPart("InnerPanel", Vector3.new(4.85, 5.95, 0.2), CFrame.new(0, -0.1, -1.08),
		Color3.fromRGB(69, 72, 68), Enum.Material.Metal).CanCollide = false

	local door = relayPart("RelayDoor", Vector3.new(5.15, 6.25, 0.2), CFrame.new(0, 0, -1.42),
		Color3.fromRGB(38, 41, 40), Enum.Material.DiamondPlate, 0.18)
	door.CanCollide = false
	local openDoorCF = cf * CFrame.new(-2.58, 0, -1.42)
		* CFrame.Angles(0, math.rad(-86), 0) * CFrame.new(2.58, 0, 0)

	local core = relayPart("Fuse", Vector3.new(0.9, 2.65, 0.72), CFrame.new(0, -0.35, -1.25),
		Color3.fromRGB(218, 174, 38), Enum.Material.Neon)
	core.CanCollide = false
	core.CanQuery = false
	local coreLight = Instance.new("PointLight")
	coreLight.Color = core.Color
	coreLight.Brightness = 0.8
	coreLight.Range = 8
	coreLight.Parent = core
	local capTop = relayPart("FuseCap", Vector3.new(1.08, 0.22, 0.86), CFrame.new(0, 1.02, -1.25),
		Color3.fromRGB(81, 78, 68), Enum.Material.Metal)
	local capBottom = relayPart("FuseCap", Vector3.new(1.08, 0.22, 0.86), CFrame.new(0, -1.72, -1.25),
		Color3.fromRGB(81, 78, 68), Enum.Material.Metal)
	for _, cap in ipairs({ capTop, capBottom }) do
		cap.CanCollide = false
		cap.CanQuery = false
	end
	local fuseParts = { core, capTop, capBottom }

	local indicator = relayPart("RelayIndicator", Vector3.new(1.1, 0.55, 0.24), CFrame.new(1.65, 2.35, -1.56),
		Color3.fromRGB(255, 178, 42), Enum.Material.Neon)
	indicator.CanCollide = false
	indicator.CanQuery = false
	local indicatorLight = Instance.new("PointLight")
	indicatorLight.Color = indicator.Color
	indicatorLight.Brightness = 1.4
	indicatorLight.Range = 13
	indicatorLight.Shadows = true
	indicatorLight.Parent = indicator

	local handle = relayPart("ReleaseHandle", Vector3.new(0.38, 1.7, 0.38), CFrame.new(-1.85, 0.15, -1.72)
		* CFrame.Angles(0, 0, math.rad(-18)), Color3.fromRGB(184, 116, 31), Enum.Material.Metal)
	handle.CanCollide = false

	local labelPlate = relayPart("RelayLabel", Vector3.new(3.25, 0.72, 0.16), CFrame.new(-0.35, 2.35, -1.55),
		Color3.fromRGB(13, 16, 15), Enum.Material.Metal)
	labelPlate.CanCollide = false
	labelPlate.CanQuery = false
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(520, 120)
	surface.LightInfluence = 0.25
	surface.Parent = labelPlate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.Text = "ZYNTRA RELAY  //  LIVE"
	label.TextColor3 = Color3.fromRGB(255, 198, 76)
	label.TextScaled = true
	label.Parent = surface

	-- These controls live on the door. Weld them to it so opening the cabinet
	-- cannot leave the label, lamp, or handle floating beside the relay.
	for _, doorControl in ipairs({ indicator, handle, labelPlate }) do
		doorControl.Anchored = false
		doorControl.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = door
		weld.Part1 = doorControl
		weld.Parent = doorControl
	end

	-- Put the prompt on the visible front face instead of the recessed body.
	local promptPoint = Instance.new("Attachment")
	promptPoint.Name = "InteractionPoint"
	promptPoint.Position = Vector3.new(0, 0, -0.18)
	promptPoint.Parent = door
	local prompt = makePrompt(promptPoint, "Extract fuse", "ZYNTRA power relay", 10)
	prompt.HoldDuration = RELAY_HOLD_TIME
	prompt.KeyboardKeyCode = Enum.KeyCode.E

	local hum = Instance.new("Sound")
	hum.Name = "RelayHum"
	hum.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	hum.Volume = 0.055
	hum.PlaybackSpeed = 0.22
	hum.Looped = true
	hum.RollOffMinDistance = 4
	hum.RollOffMaxDistance = 28
	hum.Parent = body
	hum:Play()

	-- A restrained cluster of warm ceiling lamps helps exploration without
	-- turning the relay into a beacon visible across the entire maze.
	local candidates = {}
	for _, item in ipairs(workspaceSurfaceLights()) do
		if item.Parent and item.Parent:IsA("BasePart") then
			local distance = (item.Parent.Position - core.Position).Magnitude
			if distance <= 100 then
				candidates[#candidates + 1] = { light = item, distance = distance }
			end
		end
	end
	table.sort(candidates, function(a, b) return a.distance < b.distance end)

	local cluster = {}
	for index = 1, math.min(4, #candidates) do
		local light = candidates[index].light
		local panel = light.Parent
		local count = light:GetAttribute("FuseClusterCount") or 0
		if count == 0 then
			light:SetAttribute("FuseBaseBrightness", light.Brightness)
			light:SetAttribute("FuseBaseRange", light.Range)
			light:SetAttribute("FuseBaseColor", light.Color)
			panel:SetAttribute("FuseBasePanelColor", panel.Color)
			panel:SetAttribute("FuseBasePanelMaterial", panel.Material.Name)
		end
		light:SetAttribute("FuseClusterCount", count + 1)
		light.Brightness = math.max(light.Brightness, 2.6)
		light.Range = math.max(light.Range, 42)
		light.Color = Color3.fromRGB(255, 224, 150)
		light.Enabled = true
		panel.Color = Color3.fromRGB(255, 230, 155)
		panel.Material = Enum.Material.Neon
		cluster[#cluster + 1] = light
	end

	local clusterReleased = false
	local function releaseCluster()
		if clusterReleased then return end
		clusterReleased = true
		for _, light in ipairs(cluster) do
			if light and light.Parent then
				local panel = light.Parent
				local count = math.max((light:GetAttribute("FuseClusterCount") or 1) - 1, 0)
				light:SetAttribute("FuseClusterCount", count)
				if count == 0 then
					local baseBrightness = light:GetAttribute("FuseBaseBrightness") or 0.7
					local baseRange = light:GetAttribute("FuseBaseRange") or 28
					local baseColor = light:GetAttribute("FuseBaseColor") or Color3.fromRGB(255, 243, 220)
					local basePanelColor = panel:GetAttribute("FuseBasePanelColor") or Color3.fromRGB(255, 250, 230)
					local materialName = panel:GetAttribute("FuseBasePanelMaterial")
					local fade = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					TweenService:Create(light, fade, {
						Brightness = baseBrightness, Range = baseRange, Color = baseColor,
					}):Play()
					local panelFade = TweenService:Create(panel, fade, { Color = basePanelColor })
					panelFade:Play()
					panelFade.Completed:Once(function()
						if panel.Parent and (light:GetAttribute("FuseClusterCount") or 0) == 0 then
							panel.Material = materialName and Enum.Material[materialName] or Enum.Material.Neon
						end
					end)
				end
			end
		end
	end

	local function flickerAndRelease()
		task.spawn(function()
			for _ = 1, 4 do
				for _, light in ipairs(cluster) do
					if light and light.Parent then light.Brightness = 0.03 end
				end
				indicatorLight.Brightness = 0.05
				task.wait(0.08)
				for _, light in ipairs(cluster) do
					if light and light.Parent then light.Brightness = 3.4 end
				end
				indicatorLight.Brightness = 2.2
				task.wait(0.1)
			end
			releaseCluster()
		end)
	end

	model.Destroying:Connect(releaseCluster)

	return {
		model = model,
		body = body,
		core = core,
		fuseParts = fuseParts,
		door = door,
		openDoorCF = openDoorCF,
		indicator = indicator,
		indicatorLight = indicatorLight,
		label = label,
		handle = handle,
		hum = hum,
		prompt = prompt,
		flickerAndRelease = flickerAndRelease,
		cf = cf,
		extracting = false,
		extracted = false,
	}
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

	local body = build(cf, Vector3.new(4.2, 4.2, 1.25), CFrame.new(0, 0.3, -0.62),
		Color3.fromRGB(58, 60, 64), Enum.Material.Metal, model, "Body")
	local rim = build(cf, Vector3.new(4.45, 4.45, 0.18), CFrame.new(0, 0.3, -1.28),
		Color3.fromRGB(28, 29, 31), Enum.Material.Metal, model, "OuterRim")
	rim.CanQuery = false

	local ind = build(cf, Vector3.new(0.72, 0.72, 0.22), CFrame.new(1.45, 1.55, -1.4),
		Color3.fromRGB(190, 38, 38), Enum.Material.Neon, model, "Indicator")
	ind.CanQuery = false
	local indicatorLight = Instance.new("PointLight")
	indicatorLight.Color = ind.Color
	indicatorLight.Brightness = 0.7
	indicatorLight.Range = 6
	indicatorLight.Parent = ind

	local slots = {}
	for i = 1, FUSES_PER_BOX do
		local spacing = math.min(1.15, 2.5 / math.max(FUSES_PER_BOX, 1))
		local x = (i - (FUSES_PER_BOX + 1) / 2) * spacing
		local slot = build(cf, Vector3.new(0.72, 1.75, 0.2), CFrame.new(x, 0.05, -1.4),
			Color3.fromRGB(12, 13, 14), Enum.Material.Metal, model, "FuseSlot" .. i)
		slot.CanQuery = false
		slots[i] = slot
	end

	local labelPlate = build(cf, Vector3.new(2.65, 0.62, 0.2), CFrame.new(-0.45, 1.58, -1.4),
		Color3.fromRGB(20, 21, 23), Enum.Material.Metal, model, "StatusPlate")
	labelPlate.CanQuery = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(300, 70)
	gui.Parent = labelPlate
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Code
	statusLabel.Text = "MISSING FUSE"
	statusLabel.TextColor3 = Color3.fromRGB(230, 75, 70)
	statusLabel.TextScaled = true
	statusLabel.Parent = gui

	local pp = makePrompt(body, "Insert Fuse", "Fuse Box (0/" .. FUSES_PER_BOX .. ")", 12)
	pp.RequiresLineOfSight = false
	pp.MaxActivationDistance = 12
	pp.HoldDuration = 0.35
	model.Parent = folder
	return {
		model = model, cf = cf, body = body, ind = ind, indicatorLight = indicatorLight,
		slots = slots, statusLabel = statusLabel, prompt = pp, count = 0, complete = false
	}
end

local function showFuseInBox(box, index)
	local slot = box.slots[index]
	if not slot then return end
	local fuse = Instance.new("Part")
	fuse.Name = "InstalledFuse" .. index
	fuse.Size = Vector3.new(0.5, 1.45, 0.32)
	fuse.Anchored = true
	fuse.CanCollide = false
	fuse.CanQuery = false
	fuse.Material = Enum.Material.Neon
	fuse.Color = Color3.fromRGB(225, 185, 55)
	fuse.CFrame = slot.CFrame * CFrame.new(0, 0, -0.24)
	fuse.Parent = box.model

	for sign = -1, 1, 2 do
		local cap = Instance.new("Part")
		cap.Name = "FuseCap"
		cap.Size = Vector3.new(0.62, 0.14, 0.4)
		cap.Anchored = true
		cap.CanCollide = false
		cap.CanQuery = false
		cap.Material = Enum.Material.Metal
		cap.Color = Color3.fromRGB(115, 110, 92)
		cap.CFrame = fuse.CFrame * CFrame.new(0, sign * 0.76, 0)
		cap.Parent = box.model
	end

	local insertSound = Instance.new("Sound")
	insertSound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	insertSound.Volume = 0.35
	insertSound.PlaybackSpeed = 0.65
	insertSound.RollOffMaxDistance = 35
	insertSound.Parent = box.body
	insertSound:Play()
	game:GetService("Debris"):AddItem(insertSound, 3)
end

local function makeLever(cf, folder)
	local model = Instance.new("Model")
	model.Name = "Lever"
	local plate = build(cf, Vector3.new(3.2, 4.4, 0.55), CFrame.new(0, 0.4, -0.28),
		Color3.fromRGB(48, 49, 53), Enum.Material.Metal, model, "Plate")
	local rim = build(cf, Vector3.new(3.45, 4.65, 0.16), CFrame.new(0, 0.4, -0.63),
		Color3.fromRGB(22, 23, 25), Enum.Material.Metal, model, "Rim")
	rim.CanQuery = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.52, 2.45, 0.52)
	handle.Anchored = true
	handle.Material = Enum.Material.Metal
	handle.Color = Color3.fromRGB(150, 35, 28)
	handle.CFrame = cf * CFrame.new(0, 0.25, -1.0) * CFrame.Angles(math.rad(35), 0, 0)
	handle.CanQuery = false
	handle.Parent = model

	local knob = Instance.new("Part")
	knob.Name = "Knob"
	knob.Shape = Enum.PartType.Ball
	knob.Size = Vector3.new(0.82, 0.82, 0.82)
	knob.Anchored = true
	knob.CanCollide = false
	knob.CanQuery = false
	knob.Material = Enum.Material.Metal
	knob.Color = Color3.fromRGB(185, 45, 34)
	knob.CFrame = handle.CFrame * CFrame.new(0, 1.25, 0)
	knob.Parent = model

	local statusLight = build(cf, Vector3.new(0.62, 0.62, 0.2), CFrame.new(1.05, 1.75, -0.72),
		Color3.fromRGB(125, 22, 22), Enum.Material.Neon, model, "StatusLight")
	statusLight.CanQuery = false
	local statusPlate = build(cf, Vector3.new(2.1, 0.62, 0.2), CFrame.new(-0.35, 1.75, -0.72),
		Color3.fromRGB(18, 19, 21), Enum.Material.Metal, model, "StatusPlate")
	statusPlate.CanQuery = false
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(240, 70)
	sg.Parent = statusPlate
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.fromScale(1, 1)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Code
	statusLabel.Text = "LOCKED"
	statusLabel.TextColor3 = Color3.fromRGB(230, 70, 65)
	statusLabel.TextScaled = true
	statusLabel.Parent = sg

	local anchor = Instance.new("Part")
	anchor.Name = "Interact"
	anchor.Size = Vector3.new(3, 4, 0.3)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = cf * CFrame.new(0, 0.3, -1.7)
	anchor.Parent = model
	local pp = makePrompt(anchor, "Pull Lever", "Lever (locked)", 11)
	pp.RequiresLineOfSight = false
	pp.Enabled = false

	local pullSound = Instance.new("Sound")
	pullSound.Name = "LeverPullSound"
	pullSound.SoundId = "rbxassetid://106430305259947"
	pullSound.Volume = 0.7
	pullSound.PlaybackSpeed = 1
	pullSound.RollOffMaxDistance = 45
	pullSound.Parent = plate

	model.Parent = folder
	return { model = model, cf = cf, plate = plate, handle = handle, knob = knob,
		prompt = pp, statusLight = statusLight, statusLabel = statusLabel,
		pullSound = pullSound, activeUntil = 0 }
end

local function setLeverHandle(lever, pulled)
	local a = pulled and -35 or 35
	lever.handle.CFrame = lever.cf * CFrame.new(0, 0.25, -1.0) * CFrame.Angles(math.rad(a), 0, 0)
	if lever.knob then lever.knob.CFrame = lever.handle.CFrame * CFrame.new(0, 1.25, 0) end
end

local function makeExit(cf, folder)
	local model = Instance.new("Model")
	model.Name = "Exit"
	local FRAME = Color3.fromRGB(20, 28, 25)

	-- heavy outer portal frame; the original bright green energy field remains
	build(cf, Vector3.new(1.05, 12.5, 1.25), CFrame.new(-3.75, 2, -0.5), FRAME, Enum.Material.Metal, model, "PostL")
	build(cf, Vector3.new(1.05, 12.5, 1.25), CFrame.new(3.75, 2, -0.5), FRAME, Enum.Material.Metal, model, "PostR")
	build(cf, Vector3.new(8.55, 1.15, 1.25), CFrame.new(0, 8.15, -0.5), FRAME, Enum.Material.Metal, model, "Top")

	local sign = build(cf, Vector3.new(7, 11, 0.4), CFrame.new(0, 2, -0.75),
		Color3.fromRGB(20, 60, 35), Enum.Material.Neon, model, "Sign")
	sign.CanCollide = false

	-- industrial center seam and reinforcement bands over the energy field
	for _, y in ipairs({-1.0, 2.0, 5.0}) do
		local band = build(cf, Vector3.new(7.05, 0.16, 0.16), CFrame.new(0, y, -1.02),
			Color3.fromRGB(18, 35, 26), Enum.Material.Metal, model, "Reinforcement")
		band.CanCollide = false
		band.CanQuery = false
	end
	local seam = build(cf, Vector3.new(0.14, 10.8, 0.18), CFrame.new(0, 2, -1.03),
		Color3.fromRGB(12, 28, 20), Enum.Material.Metal, model, "CenterSeam")
	seam.CanCollide = false
	seam.CanQuery = false

	-- side energy capacitors preserve the green glow while adding readable machinery
	for _, x in ipairs({-3.25, 3.25}) do
		for _, y in ipairs({-1.5, 1.5, 4.5}) do
			local node = build(cf, Vector3.new(0.45, 0.85, 0.28), CFrame.new(x, y, -1.08),
				Color3.fromRGB(35, 150, 75), Enum.Material.Neon, model, "EnergyNode")
			node.CanCollide = false
			node.CanQuery = false
		end
	end

	local header = build(cf, Vector3.new(6.4, 0.72, 0.2), CFrame.new(0, 7.55, -1.15),
		Color3.fromRGB(8, 18, 12), Enum.Material.Metal, model, "Header")
	header.CanCollide = false
	header.CanQuery = false
	local hgui = Instance.new("SurfaceGui")
	hgui.Face = Enum.NormalId.Front
	hgui.CanvasSize = Vector2.new(520, 70)
	hgui.Parent = header
	local htext = Instance.new("TextLabel")
	htext.Size = UDim2.fromScale(1, 1)
	htext.BackgroundTransparency = 1
	htext.Font = Enum.Font.Code
	htext.Text = "ENERGY TRANSFER GATE"
	htext.TextColor3 = Color3.fromRGB(90, 255, 135)
	htext.TextScaled = true
	htext.Parent = hgui

	local light = Instance.new("PointLight")
	light.Range = 0
	light.Brightness = 0
	light.Color = Color3.fromRGB(70, 255, 130)
	light.Parent = sign

	local trig = build(cf, Vector3.new(7, 11, 3), CFrame.new(0, 2, -1.4),
		Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, model, "Trigger")
	trig.CanCollide = false
	trig.Transparency = 1
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
	surfaceLightCache = nil -- the maze (and its lights) is rebuilt every round
	if not session then
		workspace:SetAttribute("Level1ActiveCircuitCount", nil)
		workspace:SetAttribute("EntityObjectiveTarget", nil)
		workspace:SetAttribute("EntityObjectiveStage", nil)
		return
	end
	session.active = false
	for _, c in ipairs(session.conns) do pcall(function() c:Disconnect() end) end
	if session.folder then session.folder:Destroy() end
	session = nil
	workspace:SetAttribute("Level1ActiveCircuitCount", nil)
	workspace:SetAttribute("LightMode", "NORMAL")
	workspace:SetAttribute("FlickerBoost", 0)
	workspace:SetAttribute("EntitySpeedMul", 1)
	workspace:SetAttribute("EntityObjectiveTarget", nil)
	workspace:SetAttribute("EntityObjectiveStage", nil)
end

local function startPuzzle()
	clearPuzzle()
	local decorDeadline = os.clock() + 15
	while workspace:GetAttribute("DecorReady") ~= true and os.clock() < decorDeadline do
		task.wait(0.1)
	end
	-- The round can end (or be torn down) during the wait above; building a
	-- ghost session for a dead round leaks its folder and connections until the
	-- next round's clearPuzzle.
	if workspace:GetAttribute("RoundActive") ~= true then return end

	-- Only the party that stood in the lobby launch square owns this puzzle.
	local roundPlayers, roundPlayerSet = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InRound") == true then
			roundPlayers[#roundPlayers + 1] = player
			roundPlayerSet[player] = true
		end
	end
	local n = math.clamp(#roundPlayers, 1, 6) -- one box, lever, and paired cable per player
	local boxCount = n
	-- Replicate the generated circuit count for the in-elevator guide. This is
	-- deliberately tied to the frozen puzzle session, not total server players,
	-- so spectators and players who join later cannot advertise nonexistent cables.
	workspace:SetAttribute("Level1ActiveCircuitCount", boxCount)
	local fusesNeeded = boxCount * FUSES_PER_BOX
	local fuseCount = fusesNeeded * SPAWN_MULT
	local leverCount = n

	local folder = Instance.new("Folder")
	folder.Name = "PuzzleItems"
	folder.Parent = workspace

	session = {
		active = true, stage = "fuses", conns = {}, folder = folder,
		boxes = {}, levers = {}, circuits = {}, relays = {}, fuses = {}, carried = {}, exit = nil,
		boxesDone = 0, boxCount = boxCount, latchMode = false,
		escaped = {}, escapeAnnounced = false, -- who's out + first-escape latch
		participants = roundPlayerSet,
	}

	-- Emergency Re-entry respawns a participant mid-round: their carried count
	-- survives in session.carried, but the hand visual lived on the old
	-- character, so rebuild it on every fresh body.
	for _, participant in ipairs(roundPlayers) do
		table.insert(session.conns, participant.CharacterAdded:Connect(function()
			task.defer(function()
				if session and session.active and session.participants[participant] then
					updateCarriedFuse(participant, session.carried[participant] or 0)
				end
			end)
		end))
	end

	local function updateEntityObjectiveTarget()
		if not session or not session.active then return end
		local target
		if session.stage == "fuses" then
			local someoneCarries = false
			for _, count in pairs(session.carried) do
				if count > 0 then someoneCarries = true break end
			end
			if someoneCarries then
				for _, box in ipairs(session.boxes) do
					if not box.complete and box.body and box.body.Parent then target = box.body.Position break end
				end
			else
				for _, fuse in ipairs(session.fuses) do
					if fuse.Parent then target = fuse.Position break end
				end
			end
		elseif session.stage == "levers" then
			local now = os.clock()
			for _, lever in ipairs(session.levers) do
				if not lever.latched and now >= (lever.activeUntil or 0)
					and lever.plate and lever.plate.Parent then
					target = lever.plate.Position
					break
				end
			end
		elseif session.stage == "end" and session.exit and session.exit.sign then
			target = session.exit.sign.Position
		end
		workspace:SetAttribute("EntityObjectiveTarget", target)
		workspace:SetAttribute("EntityObjectiveStage", session.stage)
	end
	session.updateEntityObjectiveTarget = updateEntityObjectiveTarget

	-- Send an authoritative lever snapshot whenever the lever state changes.
	-- The countdown follows the earliest temporary lever that will expire.
	local function broadcastLeverStatus()
		if not session or not session.active then return end
		local now = os.clock()
		local active, earliest = 0, nil
		for _, lv in ipairs(session.levers) do
			if lv.latched then
				active += 1
			elseif now < (lv.activeUntil or 0) then
				active += 1
				local remaining = lv.activeUntil - now
				if not earliest or remaining < earliest then earliest = remaining end
			end
		end
		status:FireAllClients("lever", active, #session.levers, earliest or 0, session.latchMode)
	end
	session.broadcastLeverStatus = broadcastLeverStatus

	-- keep the interactive stations (boxes / levers / exit) well apart from
	-- EACH OTHER, not just within their own type — one shared avoid list
	local CELLv = attr("CELL", 24)
	local SIZEv = attr("GRID", 40) * CELLv
	local stations = {}

	-- Wall relays share the station avoidance list with fuse boxes, levers, and
	-- the exit, so props and puzzle machinery cannot conceal or overlap them.
	local relayFrames = pickWallSpots(fuseCount, 2.2 * CELLv, false, stations)
	if #relayFrames < fusesNeeded then
		for _, fallbackCF in ipairs(pickWallSpots(fusesNeeded - #relayFrames, 1.1 * CELLv, false, stations)) do
			table.insert(relayFrames, fallbackCF)
		end
	end
	for _, cf in ipairs(relayFrames) do
		local relay = makeFuseRelay(cf, folder)
		table.insert(session.relays, relay)
		table.insert(session.fuses, relay.core)
		local owningSession = session
		table.insert(session.conns, relay.prompt.Triggered:Connect(function(player)
			if session ~= owningSession or not session.active or relay.extracting or relay.extracted then return end
			if session.participants[player] ~= true then return end
			relay.extracting = true
			relay.prompt.Enabled = false
			relay.label.Text = "RELEASING  //  STAND BY"
			relay.hum:Stop()

			local noisePosition = relay.core.Position
			NoiseRegistry.Add(noisePosition, "relay")
			workspace:SetAttribute("LastRelayExtraction", noisePosition)

			local releaseSound = Instance.new("Sound")
			releaseSound.Name = "RelayMechanicalRelease"
			releaseSound.SoundId = "rbxassetid://106430305259947"
			releaseSound.Volume = 0.72
			releaseSound.PlaybackSpeed = 0.88
			releaseSound.RollOffMinDistance = 8
			releaseSound.RollOffMaxDistance = 105
			releaseSound.Parent = relay.body
			releaseSound:Play()
			Debris:AddItem(releaseSound, 4)

			local electricalSnap = Instance.new("Sound")
			electricalSnap.Name = "RelayElectricalSnap"
			electricalSnap.SoundId = "rbxasset://sounds/electronicpingshort.wav"
			electricalSnap.Volume = 0.5
			electricalSnap.PlaybackSpeed = 0.72
			electricalSnap.RollOffMaxDistance = 75
			electricalSnap.Parent = relay.body
			electricalSnap:Play()
			Debris:AddItem(electricalSnap, 3)

			TweenService:Create(relay.door, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				CFrame = relay.openDoorCF,
			}):Play()
			TweenService:Create(relay.handle, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = relay.handle.CFrame * CFrame.Angles(0, 0, math.rad(58)),
			}):Play()
			for _, fusePart in ipairs(relay.fuseParts) do
				TweenService:Create(fusePart, TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					CFrame = fusePart.CFrame * CFrame.new(0, 0, -2.35),
				}):Play()
			end
			relay.flickerAndRelease()

			for _ = 1, 10 do
				local spark = Instance.new("Part")
				spark.Name = "RelaySpark"
				spark.Size = Vector3.new(0.08, math.random(2, 5) * 0.08, 0.08)
				spark.Material = Enum.Material.Neon
				spark.Color = math.random() < 0.5 and Color3.fromRGB(255, 201, 64) or Color3.fromRGB(145, 215, 255)
				spark.CanCollide = false
				spark.CanQuery = false
				spark.Massless = true
				spark.CFrame = relay.core.CFrame * CFrame.new(
					math.random(-8, 8) * 0.05,
					math.random(-10, 10) * 0.05,
					-0.55
				)
				spark.Parent = folder
				spark.AssemblyLinearVelocity = cf.LookVector * math.random(8, 15)
					+ Vector3.new(math.random(-6, 6), math.random(4, 12), math.random(-6, 6))
				Debris:AddItem(spark, 0.55)
			end

			task.delay(0.55, function()
				if session ~= owningSession or not session.active or not relay.model.Parent then return end
				relay.extracted = true
				relay.model:SetAttribute("ContainsFuse", false)
				for _, fusePart in ipairs(relay.fuseParts) do
					if fusePart.Parent then fusePart:Destroy() end
				end
				relay.indicator.Color = Color3.fromRGB(106, 31, 25)
				relay.indicatorLight.Color = relay.indicator.Color
				relay.indicatorLight.Brightness = 0.18
				relay.indicatorLight.Range = 4
				relay.label.Text = "EMPTY  //  POWER ISOLATED"
				relay.label.TextColor3 = Color3.fromRGB(188, 89, 68)

				session.carried[player] = (session.carried[player] or 0) + 1
				updateCarriedFuse(player, session.carried[player])
				status:FireClient(player, "carry", session.carried[player])
				status:FireClient(player, "msg", "Fuse extracted")
				updateEntityObjectiveTarget()
			end)
		end))
	end

	-- Fuse boxes on walls, spread apart. A relaxed second pass preserves the
	-- exact one-box-per-player contract if the first spacing target is too strict.
	local boxFrames = pickWallSpots(boxCount, 4 * CELLv, false, stations)
	if #boxFrames < boxCount then
		for _, fallbackCF in ipairs(pickWallSpots(boxCount - #boxFrames, 1.4 * CELLv, false, stations)) do
			boxFrames[#boxFrames + 1] = fallbackCF
		end
	end
	-- A 40x40 maze has far more valid walls than the six-player maximum. Keep
	-- relaxing only the spacing until the gameplay count is exact; never create
	-- an unmatched box/lever just because a random placement pass was unlucky.
	local boxFallbackPass = 0
	while #boxFrames < boxCount and boxFallbackPass < 8 do
		boxFallbackPass += 1
		for _, fallbackCF in ipairs(pickWallSpots(boxCount - #boxFrames, 8, false, stations)) do
			boxFrames[#boxFrames + 1] = fallbackCF
		end
	end
	assert(#boxFrames == boxCount, ("Level 1 could not place %d fuse boxes"):format(boxCount))
	for boxIndex, cf in ipairs(boxFrames) do
		local box = makeBox(cf, folder)
		box.model.Name = ("FuseBox_%02d"):format(boxIndex)
		table.insert(session.boxes, box)
		table.insert(session.conns, box.prompt.Triggered:Connect(function(player)
			if not session or not session.active or box.complete then return end
			local have = session.carried[player] or 0
			if have <= 0 then
				status:FireClient(player, "msg", "You have no fuses")
				return
			end
			session.carried[player] = have - 1
			updateCarriedFuse(player, session.carried[player])
			status:FireClient(player, "carry", session.carried[player])
			box.count += 1
			updateEntityObjectiveTarget()
			showFuseInBox(box, box.count)
			box.ind.Color = Color3.fromRGB(235, 165, 45)
			box.indicatorLight.Color = box.ind.Color
			box.indicatorLight.Brightness = 1.1
			box.statusLabel.Text = "PARTIAL POWER"
			box.statusLabel.TextColor3 = Color3.fromRGB(245, 185, 65)
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
				box.indicatorLight.Color = box.ind.Color
				box.indicatorLight.Brightness = 1.8
				box.indicatorLight.Range = 10
				box.statusLabel.Text = "POWER RESTORED"
				box.statusLabel.TextColor3 = Color3.fromRGB(90, 255, 115)
				session.boxesDone += 1
				status:FireAllClients("boxes", session.boxesDone, session.boxCount)
				if session.boxesDone >= session.boxCount then
					session.onAllBoxes()
				end
			end
		end))
	end
	assert(#session.boxes == boxCount, "Level 1 fuse-box count changed during construction")
	session.boxCount = boxCount
	leverCount = boxCount -- every generated box receives exactly one paired lever

	-- tell the clients to show the HUD NOW (before the heavier lever/wire build),
	-- so the PuzzleUI doesn't lag behind the round start
	status:FireAllClients("begin", session.boxCount * FUSES_PER_BOX, session.boxCount)

	-- Levers on walls near the edges, far apart, locked until the boxes are done.
	-- As with boxes, relax spacing only when needed so the pair count never drops.
	local leverSpacing = math.max(6 * CELLv, 0.22 * SIZEv)
	local leverFrames = pickWallSpots(leverCount, leverSpacing, true, stations)
	if #leverFrames < leverCount then
		for _, fallbackCF in ipairs(pickWallSpots(leverCount - #leverFrames, 2 * CELLv, true, stations)) do
			leverFrames[#leverFrames + 1] = fallbackCF
		end
	end
	local leverFallbackPass = 0
	while #leverFrames < leverCount and leverFallbackPass < 8 do
		leverFallbackPass += 1
		-- Final fallback may use any clear wall. Exact party scaling is more
		-- important than keeping every lever inside the decorative edge band.
		for _, fallbackCF in ipairs(pickWallSpots(leverCount - #leverFrames, 8, false, stations)) do
			leverFrames[#leverFrames + 1] = fallbackCF
		end
	end
	assert(#leverFrames == leverCount, ("Level 1 could not place %d levers"):format(leverCount))
	for leverIndex, cf in ipairs(leverFrames) do
		local lever = makeLever(cf, folder)
		lever.model.Name = ("Lever_%02d"):format(leverIndex)
		table.insert(session.levers, lever)
		table.insert(session.conns, lever.prompt.Triggered:Connect(function(player)
			if not session or not session.active or session.stage ~= "levers" then return end
			-- Same participant contract as the relays: only the launched party
			-- may drive the exit circuit.
			if session.participants[player] ~= true then return end
			if lever.latched then return end

			if lever.pullSound then lever.pullSound:Play() end

			if session.latchMode then
				lever.latched = true          -- clutch: flip-and-stays, no timer
				lever.prompt.Enabled = false
			else
				lever.activeUntil = os.clock() + LEVER_WINDOW
			end
			setLeverHandle(lever, true)
			updateEntityObjectiveTarget()
			if session.updateLeverLights then session.updateLeverLights() end
			if session.broadcastLeverStatus then session.broadcastLeverStatus() end

			-- a lever counts as ON if it's latched OR still inside its window
			local all = true
			for _, lv in ipairs(session.levers) do
				if not (lv.latched or os.clock() < lv.activeUntil) then all = false break end
			end
			if all then session.onLevers(lever.cf.Position) end

			-- temporary (non-latched) levers reset when their window lapses
			if not lever.latched then
				task.delay(LEVER_WINDOW + 0.1, function()
					if session and session.active and session.stage == "levers"
						and not lever.latched and os.clock() >= lever.activeUntil then
						setLeverHandle(lever, false)
						if session.updateLeverLights then session.updateLeverLights() end
						if session.broadcastLeverStatus then session.broadcastLeverStatus() end
						if session.updateEntityObjectiveTarget then session.updateEntityObjectiveTarget() end
					end
				end)
			end
		end))
	end
	assert(#session.levers == session.boxCount, "Every fuse box must have exactly one paired lever")

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
		if session.broadcastLeverStatus then session.broadcastLeverStatus() end
	end

	for _, p in ipairs(roundPlayers) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			table.insert(session.conns, hum.Died:Connect(function()
				onParticipantDown("death: " .. p.Name)
			end))
		end
	end
	table.insert(session.conns, Players.PlayerRemoving:Connect(function(lp)
		if session and session.participants[lp] then
			onParticipantDown("left: " .. lp.Name)
		end
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
			local selfOn = lv.latched or os.clock() < lv.activeUntil
			if lv.statusLabel then
				if session.stage ~= "levers" then
					lv.statusLabel.Text = "LOCKED"
					lv.statusLabel.TextColor3 = Color3.fromRGB(230, 70, 65)
					lv.statusLight.Color = Color3.fromRGB(125, 22, 22)
				elseif selfOn then
					lv.statusLabel.Text = lv.latched and "LATCHED" or "ACTIVE"
					lv.statusLabel.TextColor3 = Color3.fromRGB(100, 255, 125)
					lv.statusLight.Color = Color3.fromRGB(55, 235, 80)
				else
					lv.statusLabel.Text = "READY"
					lv.statusLabel.TextColor3 = Color3.fromRGB(255, 185, 65)
					lv.statusLight.Color = Color3.fromRGB(235, 120, 30)
				end
			end
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

	-- ── one fuse box ↔ one lever circuit per player ─────────────────
	-- Every circuit passes the elevator threshold, so its unique colour is visible
	-- the instant the doors open. Neon is intentionally restrained: readable in
	-- darkness without turning hundreds of cable segments into actual light sources.
	local WIRE_COLORS = {
		Color3.fromRGB(255, 55, 55),  -- red
		Color3.fromRGB(55, 135, 255), -- blue
		Color3.fromRGB(95, 255, 95),  -- green
		Color3.fromRGB(255, 220, 45), -- yellow
		Color3.fromRGB(245, 70, 255), -- magenta
		Color3.fromRGB(20, 235, 235), -- cyan
	}
	local WIRE_COLOR_NAMES = { "RED", "BLUE", "GREEN", "YELLOW", "MAGENTA", "CYAN" }
	-- Preserve every circuit hue while reducing the Neon value enough that global
	-- Bloom no longer turns the floor route into a thick light beam.
	local WIRE_RENDER_FACTOR = 0.58
	local function renderedCableColor(color)
		return Color3.new(
			color.R * WIRE_RENDER_FACTOR,
			color.G * WIRE_RENDER_FACTOR,
			color.B * WIRE_RENDER_FACTOR
		)
	end
	local currentCircuitIndex = 0
	local currentCircuitName = ""
	local currentCircuitParent = folder
	local currentCircuitEdgeKeys = {}

	local GRIDn = attr("GRID", 40)
	local CELLn = attr("CELL", 24)
	local On = attr("ORIGIN", -480)
	local WALLHn = attr("WALL_H", 14)  -- ceiling height, for routing over pits
	local wirePits = pitRects()        -- pit fields a floor cable can't cross
	local mazeModel = workspace:FindFirstChild("Maze")
	local WIRE_LANE_GAP = 0.55         -- cable width .25: leaves a visible gap between routes

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
		local elevatorX = attr("ELEV_X", math.floor(GRIDn / 2))
		local elevatorZ = attr("ELEV_Y", math.floor(GRIDn / 2))
		if (x == elevatorX and z == elevatorZ) or (nx == elevatorX and nz == elevatorZ) then
			return false
		end
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

	-- Registry used by the final physical cable pass. Even with deterministic
	-- maze lanes, a short source/endpoint connector can occasionally land on a
	-- longer route from another circuit. In that case the later piece is nudged
	-- sideways and receives two small joiners, so the cables visibly run beside
	-- one another instead of occupying the same geometry.
	local occupiedRuns = {}
	local function registerRun(a, b)
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if math.abs(a.Y - b.Y) > 0.12 or flat.Magnitude <= 0.05 then return end
		occupiedRuns[#occupiedRuns + 1] = {
			center = (a + b) * 0.5,
			unit = flat.Unit,
			half = flat.Magnitude * 0.5,
			y = (a.Y + b.Y) * 0.5,
			circuitIndex = currentCircuitIndex,
		}
	end

	local function overlapsOccupied(a, b)
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if math.abs(a.Y - b.Y) > 0.12 or flat.Magnitude <= 0.05 then return false end
		local unit, half = flat.Unit, flat.Magnitude * 0.5
		local center = (a + b) * 0.5
		local perp = Vector3.new(-unit.Z, 0, unit.X)
		for _, run in ipairs(occupiedRuns) do
			if run.circuitIndex ~= currentCircuitIndex
				and math.abs(center.Y - run.y) <= 0.12 and math.abs(unit:Dot(run.unit)) > 0.999 then
				local delta = run.center - center
				if math.abs(delta:Dot(perp)) < 0.24 then
					local along = delta:Dot(unit)
					local overlap = math.min(half, along + run.half)
						- math.max(-half, along - run.half)
					if overlap > 0.05 then return true end
				end
			end
		end
		return false
	end

	local function circuitEdgeKey(a, b)
		local function pointKey(p)
			return ("%d,%d,%d"):format(
				math.round(p.X * 20),
				math.round(p.Y * 20),
				math.round(p.Z * 20)
			)
		end
		local ak, bk = pointKey(a), pointKey(b)
		if bk < ak then ak, bk = bk, ak end
		return ak .. "|" .. bk
	end

	local function makeRawPiece(a, b, color)
		local len = (b - a).Magnitude
		if len <= 0.05 then return end
		local edgeKey = circuitEdgeKey(a, b)
		if currentCircuitEdgeKeys[edgeKey] then return end
		currentCircuitEdgeKeys[edgeKey] = true
		local seg = Instance.new("Part")
		seg.Name = "ObjectiveCable"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Material = Enum.Material.Neon
		seg.Color = renderedCableColor(color)
		seg.Size = Vector3.new(0.34, 0.09, len)
		seg.CFrame = CFrame.lookAt((a + b) / 2, b)
		seg:SetAttribute("CircuitIndex", currentCircuitIndex)
		seg:SetAttribute("CircuitId", currentCircuitName)
		seg.Parent = currentCircuitParent or folder
		registerRun(a, b)
	end

	-- one short piece of matte cable between two fixed points
	local function layPiece(a, b, color)
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local finalA, finalB = a, b
		if math.abs(a.Y - b.Y) <= 0.12 and flat.Magnitude > 0.05
			and overlapsOccupied(a, b) then
			local perp = Vector3.new(-flat.Unit.Z, 0, flat.Unit.X)
			for ring = 1, 8 do
				for _, sign in ipairs({ 1, -1 }) do
					local shift = perp * (WIRE_LANE_GAP * ring * sign)
					local candidateA, candidateB = a + shift, b + shift
					if not overlapsOccupied(candidateA, candidateB) then
						finalA, finalB = candidateA, candidateB
						break
					end
				end
				if finalA ~= a then break end
			end
		end
		if finalA ~= a then
			-- Bevel the two joiners instead of drawing them exactly perpendicular.
			-- A perpendicular half-stud joiner can itself lie along an unrelated
			-- crossing run; the slight diagonal keeps the entire detour unique.
			local unit = flat.Unit
			local bevel = math.min(0.3, flat.Magnitude * 0.2)
			local mainA = finalA + unit * bevel
			local mainB = finalB - unit * bevel
			makeRawPiece(mainA, mainB, color)
			makeRawPiece(a, mainA, color)
			makeRawPiece(mainB, b, color)
		else
			makeRawPiece(finalA, finalB, color)
		end
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
		local a = Vector3.new(x, y0, z)
		local b = Vector3.new(x, y1, z)
		local edgeKey = circuitEdgeKey(a, b)
		if currentCircuitEdgeKeys[edgeKey] then return end
		currentCircuitEdgeKeys[edgeKey] = true
		local seg = Instance.new("Part")
		seg.Name = "ObjectiveCable"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanQuery = false
		seg.CanTouch = false
		seg.Material = Enum.Material.Neon
		seg.Color = renderedCableColor(color)
		seg.Size = Vector3.new(0.34, len, 0.34)
		seg.CFrame = CFrame.new(x, (y0 + y1) / 2, z)
		seg:SetAttribute("CircuitIndex", currentCircuitIndex)
		seg:SetAttribute("CircuitId", currentCircuitName)
		seg.Parent = currentCircuitParent or folder
	end

	-- run the cable from a floor vertex to directly under the wall object, then
	-- UP into it, so it reads as actually connected (not just stopping nearby)
	local function connectEnd(endVert, cf, color, terminalPosition)
		local ev = Vector3.new(endVert.X, (floorY(endVert.X, endVert.Z) or 0) + 0.06, endVert.Z)
		-- Use the visible colored jack as the true electrical endpoint. Older
		-- routes climbed behind the casing, leaving the jack apparently floating.
		local foot = terminalPosition or (cf * CFrame.new(0, 0, -0.12)).Position
		local y0 = ev.Y
		-- 90° L along the floor (X leg, then Z leg) — reach the wall base
		local corner = Vector3.new(foot.X, y0, ev.Z)
		laySeg(ev, corner, color)
		laySeg(corner, Vector3.new(foot.X, y0, foot.Z), color)
		-- climb into the exact glowing terminal. Legacy callers without a terminal
		-- still stop at the lower casing edge.
		local terminalY = terminalPosition and terminalPosition.Y or (cf.Position.Y - 1.5)
		layRiser(foot.X, foot.Z, y0, terminalY, color)
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
	local function layWireDirect(fromCF, toCF, color, connectStart, laneIndex, terminalPosition)
		local a = (fromCF * CFrame.new(0, 0, -3)).Position
		local b = (toCF * CFrame.new(0, 0, -3)).Position
		local y = (floorY(a.X, a.Z) or 0) + 0.06
		local p1 = Vector3.new(a.X, y, a.Z)
		local p2 = Vector3.new(b.X, y, b.Z)
		local lane = math.max((laneIndex or 1) - 1, 0) * WIRE_LANE_GAP
		local side = ((laneIndex or 1) % 2 == 0) and 1 or -1
		local q1 = Vector3.new(p1.X, y, p1.Z + side * lane)
		local corner = Vector3.new(p2.X + side * lane, y, q1.Z)
		local q2 = Vector3.new(p2.X + side * lane, y, p2.Z)
		laySeg(p1, q1, color)
		laySeg(q1, corner, color)
		laySeg(corner, q2, color)
		laySeg(q2, p2, color)
		if connectStart ~= false then
			connectEnd(p1, fromCF, color)
		else
			local raw = (fromCF * CFrame.new(0, 0, -0.2)).Position
			local source = Vector3.new(raw.X, (floorY(raw.X, raw.Z) or 0) + 0.06, raw.Z)
			local function sourceOnRun(a, b)
				local vx, vz = b.X - a.X, b.Z - a.Z
				local wx, wz = source.X - a.X, source.Z - a.Z
				local lengthSquared = vx * vx + vz * vz
				local dot = vx * wx + vz * wz
				return lengthSquared > 0.001
					and math.abs(vx * wz - vz * wx) <= 0.05
					and dot >= 0 and dot <= lengthSquared
			end
			local alreadyConnected = sourceOnRun(p1, q1)
				or sourceOnRun(q1, corner) or sourceOnRun(corner, q2)
				or sourceOnRun(q2, p2)
			if not alreadyConnected then laySeg(source, p1, color) end
		end
		connectEnd(p2, toCF, color, terminalPosition)
	end

	local function layWire(fromCF, toCF, color, connectStart, laneIndex, terminalPosition)
		if not mazeModel then return end
		local sx, sz = frontCell(fromCF)
		local gx, gz = frontCell(toCF)
		local cells = gridPath(sx, sz, gx, gz)
		if not cells or #cells < 2 then
			layWireDirect(fromCF, toCF, color, connectStart, laneIndex, terminalPosition) -- BFS failed → guarantee a wire
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
			local al = (math.abs(W[i + 1].X - W[i].X)
				>= math.abs(W[i + 1].Z - W[i].Z)) and "X" or "Z"
			local lane = math.max((laneIndex or 1) - 1, 0) * WIRE_LANE_GAP
			-- All routes use the SAME side of a corridor. Picking the nearest wall per
			-- route let lanes approaching from opposite sides meet on the same centre
			-- line (different-length Parts then visibly occupied each other). Preserve
			-- the measured wall-hug distance, but give every global lane one absolute
			-- coordinate from the negative edge inward.
			-- Derive the coordinate from the maze cell itself, rather than a raycast
			-- distance that can differ on two otherwise shared runs. This guarantees
			-- lane N has the same absolute position for every cable in that corridor.
			local off = -math.max(CELLn * 0.5 - 2, 0) + lane
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

		-- connect the route to its source. Elevator cable starts stay entirely on
		-- the floor; wall-mounted endpoints still receive a vertical riser.
		if connectStart ~= false then
			connectEnd(verts[1], fromCF, color)
		else
			local raw = (fromCF * CFrame.new(0, 0, -0.2)).Position
			local source = Vector3.new(raw.X, (floorY(raw.X, raw.Z) or 0) + 0.06, raw.Z)
			local first = Vector3.new(verts[1].X, (floorY(verts[1].X, verts[1].Z) or 0) + 0.06, verts[1].Z)
			-- If the source already lies on the first routed run, that run physically
			-- reaches the source. Adding an extra source-to-first Part would retrace
			-- (and fully overlap) the same cable for the first stud or two.
			local sourceOnRoutedRun = false
			for i = 1, #verts - 1 do
				local a, b = verts[i], verts[i + 1]
				local vx, vz = b.X - a.X, b.Z - a.Z
				local wx, wz = source.X - a.X, source.Z - a.Z
				local lengthSquared = vx * vx + vz * vz
				local dot = vx * wx + vz * wz
				if lengthSquared > 0.001
					and math.abs(vx * wz - vz * wx) <= 0.05
					and dot >= 0 and dot <= lengthSquared then
					sourceOnRoutedRun = true
					break
				end
			end
			if not sourceOnRoutedRun then
				local corner = Vector3.new(first.X, source.Y, source.Z)
				laySeg(source, corner, color)
				laySeg(corner, first, color)
			end
		end
		connectEnd(verts[#verts], toCF, color, terminalPosition)
	end

	-- One visible circuit per box/lever pair. The elevator witness point is a
	-- middle point on the same cable—not a second cable or a disconnected legend.
	local elevX = attr("ELEV_X", math.floor(GRIDn / 2))
	local elevZ = attr("ELEV_Y", math.floor(GRIDn / 2))
	local _, startWZ = cellWorld(math.clamp(elevX + 1, 1, GRIDn), elevZ)
	local startWX = On + elevX * CELLn + 1.5 -- just outside the east-facing doors
	local startY = (floorY(startWX, startWZ) or 0) + 0.06

	local function addCircuitJack(station, color, pairIndex)
		station.model:SetAttribute("CircuitIndex", pairIndex)
		station.model:SetAttribute("CircuitId", ("CIRCUIT_%02d"):format(pairIndex))
		station.model:SetAttribute("CircuitColor", color)
		station.model:SetAttribute("CircuitColorName", WIRE_COLOR_NAMES[pairIndex])

		local isFuseBox = station.model.Name:find("^FuseBox") ~= nil
		local jackY = isFuseBox and -1.76 or -1.88
		local jackZ = isFuseBox and -1.43 or -0.73
		local jack = build(station.cf, Vector3.new(isFuseBox and 2.65 or 2.45, 0.24, 0.22),
			CFrame.new(0, jackY, jackZ), renderedCableColor(color), Enum.Material.Neon,
			station.model, "CableJack")
		station.cableTerminal = jack.Position
		jack.CanCollide = false
		jack.CanQuery = false
		jack.CanTouch = false
		local jackLight = Instance.new("PointLight")
		jackLight.Name = "CableJackGlow"
		jackLight.Color = color
		jackLight.Brightness = 0.10
		jackLight.Range = 4
		jackLight.Shadows = false
		jackLight.Parent = jack

		local plate = build(station.cf, Vector3.new(2.25, 0.48, 0.16),
			CFrame.new(0, jackY + 0.41, jackZ - 0.01), Color3.fromRGB(15, 16, 18),
			Enum.Material.Metal, station.model, "CircuitLabel")
		plate.CanCollide = false
		plate.CanQuery = false
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.CanvasSize = Vector2.new(300, 70)
		gui.LightInfluence = 0.2
		gui.Parent = plate
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.Code
		text.Text = ("CIRCUIT %02d"):format(pairIndex)
		text.TextColor3 = color
		text.TextScaled = true
		text.Parent = gui
	end

	local pairCount = session.boxCount
	assert(pairCount >= 1 and pairCount <= #WIRE_COLORS, "Circuit count exceeds the six-color palette")
	assert(#session.boxes == pairCount and #session.levers == pairCount,
		("Circuit pairing mismatch: %d boxes / %d levers / %d expected")
			:format(#session.boxes, #session.levers, pairCount))

	for pairIndex = 1, pairCount do
		local box = session.boxes[pairIndex]
		local lever = session.levers[pairIndex]
		local color = WIRE_COLORS[pairIndex]
		local circuitId = ("CIRCUIT_%02d"):format(pairIndex)
		local circuit = Instance.new("Model")
		circuit.Name = "CircuitCable_" .. string.format("%02d", pairIndex)
		circuit:SetAttribute("CircuitIndex", pairIndex)
		circuit:SetAttribute("CircuitId", circuitId)
		circuit:SetAttribute("CircuitColor", color)
		circuit:SetAttribute("CircuitColorName", WIRE_COLOR_NAMES[pairIndex])
		circuit:SetAttribute("FuseBoxName", box.model.Name)
		circuit:SetAttribute("LeverName", lever.model.Name)
		circuit:SetAttribute("HasElevatorWitness", true)
		circuit.Parent = folder
		session.circuits[pairIndex] = circuit

		currentCircuitIndex = pairIndex
		currentCircuitName = circuitId
		currentCircuitParent = circuit
		currentCircuitEdgeKeys = {}
		addCircuitJack(box, color, pairIndex)
		addCircuitJack(lever, color, pairIndex)

		local laneZ = startWZ + (pairIndex - (pairCount + 1) * 0.5) * 0.72
		local witnessPosition = Vector3.new(startWX, startY, laneZ)
		local witnessCF = CFrame.lookAt(witnessPosition, witnessPosition + Vector3.new(1, 0, 0))

		local witness = Instance.new("Part")
		witness.Name = "ElevatorVisibleCablePoint"
		witness.Size = Vector3.new(0.46, 0.1, 0.46)
		witness.CFrame = CFrame.new(witnessPosition)
		witness.Anchored = true
		witness.CanCollide = false
		witness.CanQuery = false
		witness.CanTouch = false
		witness.Material = Enum.Material.Neon
		witness.Color = renderedCableColor(color)
		witness:SetAttribute("CircuitIndex", pairIndex)
		witness:SetAttribute("CircuitId", circuitId)
		witness.Parent = circuit
		local witnessLight = Instance.new("PointLight")
		witnessLight.Name = "CableThresholdGlow"
		witnessLight.Color = color
		witnessLight.Brightness = 0.04
		witnessLight.Range = 3
		witnessLight.Shadows = false
		witnessLight.Parent = witness

		-- These two routed halves share exactly one witness point and one circuit
		-- model. Same-circuit overlaps remain coincident, so a route that doubles
		-- back through a corridor still reads as one cable—not parallel duplicates.
		layWire(witnessCF, box.cf, color, false, pairIndex, box.cableTerminal)
		layWire(witnessCF, lever.cf, color, false, pairIndex, lever.cableTerminal)
	end
	currentCircuitIndex = 0
	currentCircuitName = ""
	currentCircuitParent = folder
	currentCircuitEdgeKeys = {}

	-- exit: a doorway in the OUTER BORDER wall (you're actually leaving), dim
	-- and closed until the levers are pulled
	local exitCF = pickExitOnBorder(stations, 5 * CELLv) or CFrame.new(0, 4, 0)
	session.exit = makeExit(exitCF, folder)
	session.safeSpawn = makeSafeRoom() -- the room you step into through the exit
	updateEntityObjectiveTarget()
	table.insert(session.conns, session.exit.trig.Touched:Connect(function(hit)
		if not session or not session.exit.open then return end
		local p = Players:GetPlayerFromCharacter(hit.Parent)
		if not p or session.escaped[p] or session.participants[p] ~= true then return end
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end

		-- step INTO the safe room the entity can't reach (reads as looping back
		-- into the elevator for now; becomes the level-2 start room later)
		session.escaped[p] = true
		if session.safeSpawn then hrp.CFrame = session.safeSpawn end
		hrp.Anchored = true -- parked: they spectate from here, no wandering the void
		p.CameraMode = Enum.CameraMode.Classic -- release first-person for spectate
		p:SetAttribute("Escaped", true) -- spectate + EntityAI + the win check key off this

		-- EVERY escape is announced to the party, by name. Level 2 and Level 3
		-- have always done this; Level 1 latched the whole announcement behind
		-- the first one, so the second and third escapee left in silence.
		fireEscapeStatus(p)

		-- FIRST escape only, once per round: keep the maze dark and give
		-- everyone still inside detector/compass guidance to the exit.
		-- The round itself continues — GameManager ends it when every living
		-- player has escaped (or everyone left inside is dead).
		if not session.escapeAnnounced then
			session.escapeAnnounced = true
			workspace:SetAttribute("LightMode", "ESCAPE")
			status:FireAllClients("escape", p.Name)
		end
	end))

	table.insert(session.conns, Players.PlayerRemoving:Connect(function(p)
		if session then session.carried[p] = nil end
	end))

	function session.onAllBoxes()
		if session.stage ~= "fuses" then return end
		session.stage = "levers"
		updateEntityObjectiveTarget()

		-- All distribution boxes are live: the building enters a continuous
		-- red overload alert until the levers divert power to the exit door.
		-- The LightMode attribute alone drives every client (siren + red wash);
		-- no remote event is needed.
		workspace:SetAttribute("LightMode", "ALERT")

		-- Show POWER RESTORED for three seconds, then blink ALERT.
		for _, poweredBox in ipairs(session.boxes) do
			task.spawn(function()
				task.wait(3)
				local show = true
				while session and session.active and session.stage == "levers"
					and poweredBox.model and poweredBox.model.Parent do
					poweredBox.statusLabel.Text = show and "ALERT" or ""
					poweredBox.statusLabel.TextColor3 = Color3.fromRGB(255, 65, 55)
					poweredBox.ind.Color = show and Color3.fromRGB(255, 45, 35) or Color3.fromRGB(90, 8, 8)
					poweredBox.indicatorLight.Color = poweredBox.ind.Color
					poweredBox.indicatorLight.Brightness = show and 2.2 or 0.25
					show = not show
					task.wait(0.45)
				end
			end)
		end

		for _, lv in ipairs(session.levers) do
			lv.prompt.Enabled = true
			lv.prompt.ObjectText = "Power Exit Door"
		end
		status:FireAllClients("levers", #session.levers, LEVER_WINDOW)
		if session.broadcastLeverStatus then session.broadcastLeverStatus() end
		if session.updateLeverLights then session.updateLeverLights() end

		-- keep the status rows accurate as temporary levers' windows lapse
		task.spawn(function()
			while session and session.active and session.stage == "levers" do
				if session.updateLeverLights then session.updateLeverLights() end
				task.wait(0.5)
			end
		end)
	end
	function session.onLevers(shutdownOrigin)
		if session.stage ~= "levers" then return end
		session.stage = "end"
		updateEntityObjectiveTarget()
		workspace:SetAttribute("EntitySpeedMul", END_SPEED_MUL)

		-- The final lever sound plays immediately. One second later, the uploaded
		-- power-down recording begins and drives an equally long shutdown wave.
		task.delay(1, function()
			if not session or not session.active or session.stage ~= "end" then return end

			local powerDown = Instance.new("Sound")
			powerDown.Name = "ExitPowerDown"
			powerDown.SoundId = "rbxassetid://75561087895749"
			powerDown.Volume = 1
			powerDown.PlaybackSpeed = 1
			powerDown.Looped = false
			powerDown.Parent = game:GetService("SoundService")
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ powerDown })
			end)

			local duration = powerDown.TimeLength
			if duration <= 0.1 then duration = 5 end
			workspace:SetAttribute("PowerDownOrigin", shutdownOrigin or Vector3.zero)
			workspace:SetAttribute("PowerDownDuration", duration)
			workspace:SetAttribute("LightMode", "POWERDOWN")

			powerDown.Ended:Once(function()
				powerDown:Destroy()
			end)
			powerDown:Play()

			task.delay(duration, function()
				if not session or not session.active or session.stage ~= "end" then return end

				-- The maze stays dark; only the local exit hardware glows at close range.
				local ex = session.exit
				ex.open = true
				ex.sign.Color = Color3.fromRGB(45, 255, 110)
				ex.light.Range = 40
				ex.light.Brightness = 3
				workspace:SetAttribute("ExitPos", ex.sign.Position)
				workspace:SetAttribute("LightMode", "ESCAPE")
				entityToArea(ex.sign.Position, 3)
				status:FireAllClients("exit")
			end)
		end)

	end
end

-- watch the round flag set by GameManager. Levels 2/3 raise RoundActive too,
-- but they own their own objectives — this fuse puzzle belongs to Level 1 only
-- (without the guard it stalls 15s on DecorReady, then asserts on the missing
-- Maze model every non-Level-1 round).
local function isLevelOneRound()
	local level = workspace:GetAttribute("SelectedLevel")
	return level == nil or level == 1
end

workspace:GetAttributeChangedSignal("RoundActive"):Connect(function()
	if workspace:GetAttribute("RoundActive") then
		if isLevelOneRound() then startPuzzle() end
	elseif workspace:GetAttribute("PostWinIntermissionActive") ~= true then
		clearPuzzle()
	end
end)

-- A win stops gameplay immediately but holds the solved circuit dressing for
-- the 15-second completion screen. Release it when GameManager closes that
-- intermission; GenerateWorld is a teardown fallback for aborted transitions.
workspace:GetAttributeChangedSignal("PostWinIntermissionActive"):Connect(function()
	if workspace:GetAttribute("PostWinIntermissionActive") ~= true
		and workspace:GetAttribute("RoundActive") ~= true then
		clearPuzzle()
	end
end)
workspace:GetAttributeChangedSignal("GenerateWorld"):Connect(function()
	if workspace:GetAttribute("GenerateWorld") ~= true then clearPuzzle() end
end)

if workspace:GetAttribute("RoundActive") and isLevelOneRound() then startPuzzle() end

-- Lever countdown status events added for PuzzleUI.
