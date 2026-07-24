-- MazeGenerator  (v4 — texture auto-resolve, guaranteed plaza+pit, built-in elevator)
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "MazeGenerator"
-- REPLACES the old MazeGenerator entirely — paste over the old contents.
--
-- v4: decal IDs are auto-resolved to image IDs (paste any Toolbox decal ID and
-- it works) · every level has at least one open plaza and one pitfall · the
-- elevator is now built HERE, from the same textured yellow walls as the maze,
-- filling its whole cell so it looks native. GameManager only drives the doors.
--
-- BEFORE TESTING: delete the default Baseplate and default SpawnLocation.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")
local PhysicsService = game:GetService("PhysicsService")

-- collision groups: pit-zone barriers stop ONLY the entity — players pass through
pcall(function() PhysicsService:RegisterCollisionGroup("PitBarrier") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Entity") end)
PhysicsService:CollisionGroupSetCollidable("PitBarrier", "Default", false)
PhysicsService:CollisionGroupSetCollidable("PitBarrier", "Entity", true)
PhysicsService:CollisionGroupSetCollidable("PitBarrier", "PitBarrier", false)

-- ── tuning ────────────────────────────────────────────────
local GRID       = 40      -- maze is GRID x GRID cells
local CELL       = 24      -- studs per cell (corridor width)
local WALL_H     = 14      -- wall/ceiling height
local WALL_T     = 2       -- wall thickness
local SEED       = nil     -- set a number (e.g. 1337) for the same maze every run

-- density variation — tuned corridor-first: tight maze by default, with
-- occasional distinct open rooms instead of everything blending open
local OPENNESS    = 0.32   -- base wall-removal chance in average areas
local NOISE_SCALE = 6      -- cells per density blob (smaller = smaller open pockets)
local PLAZA_T     = 0.8    -- density above this = fully open plaza (rarer now)
local PLAZA_R     = 3      -- radius (cells) of the one GUARANTEED plaza

-- pitfall ZONES: big multi-cell hole fields. Each zone is one open room
-- (internal walls removed) filled with a continuous grid of square holes
-- separated by narrow walkable beams, all over one shared deep shaft.
local PIT_ZONES      = 2     -- hole fields per level (always at least this many)
local PIT_ZONE_CELLS = 6     -- zone size in MAZE CELLS per axis (1 cell = 24 studs).
                             -- 6 → 144×144 studs → 6×6 = 36 big holes. Max ~12.
local PIT_HOLE       = 21    -- hole size in studs
local PIT_GAP        = 2     -- beam width between holes, in studs (tight but walkable)
local PIT_DEPTH      = 50    -- how far down the shaft goes
local PIT_SAFE_CELLS = 1     -- min cell distance from the start/entity corners

local LIGHT_EVERY = 2      -- ceiling light every N cells
local LIGHT_SIZE  = 4      -- light panel size — matches CEILING_TILE so one
                           -- ceiling-texture repeat = one office tile = one light
local FLICKER_CHANCE = 0.12 -- fraction of lights that flicker
local DEAD_CHANCE    = 0.25 -- fraction of lights that are just broken (dark panel)

local WALL_COLOR    = Color3.fromRGB(197, 180, 116)
local FLOOR_COLOR   = Color3.fromRGB(158, 144, 96)
local CEILING_COLOR = Color3.fromRGB(222, 214, 170)
local LIGHT_COLOR   = Color3.fromRGB(255, 244, 200)
local PIT_COLOR     = Color3.fromRGB(35, 32, 26)

-- Toolbox textures — DECAL or image IDs both fine, they resolve automatically.
local WALL_TEXTURE    = "rbxassetid://87947439437597"  -- our own wall decal
local FLOOR_TEXTURE   = "rbxassetid://100093931957721" -- our own floor decal
local CEILING_TEXTURE = "rbxassetid://91804597609254"  -- our own ceiling tile (one tile per image)
-- studs per texture repeat, per surface (smaller = denser pattern)
local WALL_TILE    = 6
local FLOOR_TILE   = 6
local CEILING_TILE = LIGHT_SIZE -- one repeat = one office tile = one light panel

-- Optional light-panel textures (your own decals). Each fills ONE panel face
-- exactly — draw a full office fixture (diffuser grid / frame) per image.
local LIGHT_TEXTURE      = "" -- lit fixture face
local DEAD_LIGHT_TEXTURE = "" -- broken/dark fixture face

-- Optional elevator textures (your own decals)
local ELEV_WALL_TEXTURE  = "" -- cabin walls (over the steel)
local ELEV_FLOOR_TEXTURE = "" -- cabin floor (over the marble)
local ELEV_DOOR_TEXTURE  = "" -- door faces
local ELEV_TILE = 4           -- studs per repeat inside the cabin

-- Optional mold/grime overlay (your own decal, transparent PNG).
-- Draw the mold hanging from the TOP of the image, rest transparent — it's
-- tiled once over the wall height, so image-top = wall-top.
local MOLD_TEXTURE = ""
local MOLD_CHANCE  = 0.22 -- fraction of maze walls that get mold
-- ──────────────────────────────────────────────────────────

if SEED then math.randomseed(SEED) end

-- safety: zones must fit inside the maze with room to place — out-of-range
-- values error out in math.random/math.clamp otherwise
PIT_ZONE_CELLS = math.clamp(PIT_ZONE_CELLS, 2, math.floor(GRID / 3))

-- ── resolve decal IDs → image IDs ─────────────────────────
-- Toolbox "Copy Asset ID" usually gives the DECAL id; Texture instances need
-- the underlying IMAGE id. Load the asset server-side and read the real id.
local function resolveTexture(id)
	if id == "" then return "" end
	local numeric = tonumber(string.match(id, "%d+"))
	if not numeric then return id end
	local ok, resolved = pcall(function()
		local asset = InsertService:LoadAsset(numeric)
		local decal = asset:FindFirstChildWhichIsA("Decal", true)
		local tex = decal and decal.Texture
		asset:Destroy()
		return tex
	end)
	if ok and resolved and resolved ~= "" then
		return resolved
	end
	return id -- already an image id (or offline) — use as-is
end

WALL_TEXTURE = resolveTexture(WALL_TEXTURE)
FLOOR_TEXTURE = resolveTexture(FLOOR_TEXTURE)
CEILING_TEXTURE = resolveTexture(CEILING_TEXTURE)
MOLD_TEXTURE = resolveTexture(MOLD_TEXTURE)
LIGHT_TEXTURE = resolveTexture(LIGHT_TEXTURE)
DEAD_LIGHT_TEXTURE = resolveTexture(DEAD_LIGHT_TEXTURE)
ELEV_WALL_TEXTURE = resolveTexture(ELEV_WALL_TEXTURE)
ELEV_FLOOR_TEXTURE = resolveTexture(ELEV_FLOOR_TEXTURE)
ELEV_DOOR_TEXTURE = resolveTexture(ELEV_DOOR_TEXTURE)

local function key(x, z) return x .. "," .. z end

-- ── density field (Perlin noise) ──────────────────────────
-- 0 = dense maze … 1 = wide open plaza
local nox, noz = math.random() * 100, math.random() * 100
local function density(x, z)
	return math.clamp(0.5 + math.noise(x / NOISE_SCALE + nox, z / NOISE_SCALE + noz), 0, 1)
end

-- ── maze layout (recursive backtracker) ───────────────────
-- wallV[x][z] = wall between cell (x,z) and (x+1,z)
-- wallH[x][z] = wall between cell (x,z) and (x,z+1)
local wallV, wallH = {}, {}
for x = 1, GRID do
	wallV[x], wallH[x] = {}, {}
	for z = 1, GRID do
		wallV[x][z], wallH[x][z] = true, true
	end
end

local visited = {}
local stack = { { math.random(GRID), math.random(GRID) } }
visited[key(stack[1][1], stack[1][2])] = true

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

while #stack > 0 do
	local cur = stack[#stack]
	local x, z = cur[1], cur[2]

	local options = {}
	for _, d in ipairs(DIRS) do
		local nx, nz = x + d[1], z + d[2]
		if nx >= 1 and nx <= GRID and nz >= 1 and nz <= GRID
			and not visited[key(nx, nz)] then
			table.insert(options, { nx, nz, d })
		end
	end

	if #options == 0 then
		table.remove(stack)
	else
		local pick = options[math.random(#options)]
		local nx, nz, d = pick[1], pick[2], pick[3]
		if d[1] == 1 then wallV[x][z] = false
		elseif d[1] == -1 then wallV[nx][nz] = false
		elseif d[2] == 1 then wallH[x][z] = false
		else wallH[nx][nz] = false end
		visited[key(nx, nz)] = true
		table.insert(stack, { nx, nz })
	end
end

-- ── density-driven wall removal ───────────────────────────
-- plazas lose every wall; average areas lose ~OPENNESS; dense areas keep most
local function removeChance(d)
	if d > PLAZA_T then return 1 end
	return OPENNESS * (d / PLAZA_T)
end

for x = 1, GRID - 1 do
	for z = 1, GRID do
		if wallV[x][z] then
			local d = (density(x, z) + density(x + 1, z)) / 2
			if math.random() < removeChance(d) then wallV[x][z] = false end
		end
	end
end
for x = 1, GRID do
	for z = 1, GRID - 1 do
		if wallH[x][z] then
			local d = (density(x, z) + density(x, z + 1)) / 2
			if math.random() < removeChance(d) then wallH[x][z] = false end
		end
	end
end

-- ── one GUARANTEED plaza, regardless of noise ─────────────
local margin = PIT_SAFE_CELLS + PLAZA_R
local fx = math.random(margin + 1, GRID - margin)
local fz = math.random(margin + 1, GRID - margin)

for x = fx - PLAZA_R, fx + PLAZA_R - 1 do
	for z = fz - PLAZA_R, fz + PLAZA_R do
		wallV[x][z] = false
	end
end
for x = fx - PLAZA_R, fx + PLAZA_R do
	for z = fz - PLAZA_R, fz + PLAZA_R - 1 do
		wallH[x][z] = false
	end
end

local function insideForcedPlaza(x, z)
	return math.abs(x - fx) <= PLAZA_R and math.abs(z - fz) <= PLAZA_R
end

-- keep the elevator exit clear: force the wall east of the start cell open
wallV[2][2] = false

-- the elevator shell replaces cell (2,2)'s own walls — drop the maze copies,
-- otherwise they generate overlapping the shell and z-fight/clip into it
wallV[1][2] = false
wallH[2][1] = false
wallH[2][2] = false

-- ── place pit zones (away from both corners, non-overlapping) ──
local zones = {}

local function zoneOK(zx, zz)
	-- no overlap with other zones (1-cell buffer)
	for _, zn in ipairs(zones) do
		if math.abs(zx - zn.x) < PIT_ZONE_CELLS + 1
			and math.abs(zz - zn.z) < PIT_ZONE_CELLS + 1 then
			return false
		end
	end
	-- keep away from the start/entity corners
	local hi = PIT_ZONE_CELLS - 1
	local function nearCorner(cx0, cz0)
		return zx <= cx0 + PIT_SAFE_CELLS and zx + hi >= cx0 - PIT_SAFE_CELLS
			and zz <= cz0 + PIT_SAFE_CELLS and zz + hi >= cz0 - PIT_SAFE_CELLS
	end
	return not (nearCorner(2, 2) or nearCorner(GRID - 1, GRID - 1))
end

-- the FIRST zone always sits in the guaranteed plaza → every level has a
-- big open room full of holes, and it's guaranteed to exist
do
	local zx = math.clamp(fx - math.floor(PIT_ZONE_CELLS / 2), 2, GRID - PIT_ZONE_CELLS)
	local zz = math.clamp(fz - math.floor(PIT_ZONE_CELLS / 2), 2, GRID - PIT_ZONE_CELLS)
	table.insert(zones, { x = zx, z = zz })
end

-- remaining zones placed randomly
for i = 2, PIT_ZONES do
	local placed = false
	for _ = 1, 80 do -- placement attempts
		local zx = math.random(2, GRID - PIT_ZONE_CELLS)
		local zz = math.random(2, GRID - PIT_ZONE_CELLS)
		if zoneOK(zx, zz) then
			table.insert(zones, { x = zx, z = zz })
			placed = true
			break
		end
	end
	if not placed then
		warn(("MazeGenerator: no room for pit zone %d — map too crowded for this PIT_ZONE_CELLS"):format(i))
	end
end

-- each zone becomes one big open room: remove all walls inside it
local pitCellSet = {}
for _, zn in ipairs(zones) do
	for x = zn.x, zn.x + PIT_ZONE_CELLS - 1 do
		for z = zn.z, zn.z + PIT_ZONE_CELLS - 1 do
			pitCellSet[key(x, z)] = true
			if x < zn.x + PIT_ZONE_CELLS - 1 then wallV[x][z] = false end
			if z < zn.z + PIT_ZONE_CELLS - 1 then wallH[x][z] = false end
		end
	end
end

-- ── connectivity repair: no sealed pockets, EVER ──────────
-- The elevator shell seals cell (2,2), which can orphan regions whose only
-- maze-tree connection ran through it. Flood-fill from the cell outside the
-- elevator doors and knock open walls until every cell is reachable.
do
	local blocked = { [key(2, 2)] = true } -- elevator cell is solid
	local reached = {}

	local function bfs(sx, sz)
		local q = { { sx, sz } }
		reached[key(sx, sz)] = true
		while #q > 0 do
			local c = table.remove(q)
			local x, z = c[1], c[2]
			local nbs = {}
			if x < GRID and not wallV[x][z] then table.insert(nbs, { x + 1, z }) end
			if x > 1 and not wallV[x - 1][z] then table.insert(nbs, { x - 1, z }) end
			if z < GRID and not wallH[x][z] then table.insert(nbs, { x, z + 1 }) end
			if z > 1 and not wallH[x][z - 1] then table.insert(nbs, { x, z - 1 }) end
			for _, nb in ipairs(nbs) do
				local k = key(nb[1], nb[2])
				if not reached[k] and not blocked[k] then
					reached[k] = true
					table.insert(q, nb)
				end
			end
		end
	end

	bfs(3, 2) -- just outside the elevator doors

	local repaired = 0
	local changed = true
	while changed do
		changed = false
		for x = 1, GRID do
			for z = 1, GRID do
				local k = key(x, z)
				if not reached[k] and not blocked[k] then
					if x > 1 and reached[key(x - 1, z)] and not blocked[key(x - 1, z)] then
						wallV[x - 1][z] = false; repaired += 1; bfs(x, z); changed = true
					elseif x < GRID and reached[key(x + 1, z)] and not blocked[key(x + 1, z)] then
						wallV[x][z] = false; repaired += 1; bfs(x, z); changed = true
					elseif z > 1 and reached[key(x, z - 1)] and not blocked[key(x, z - 1)] then
						wallH[x][z - 1] = false; repaired += 1; bfs(x, z); changed = true
					elseif z < GRID and reached[key(x, z + 1)] and not blocked[key(x, z + 1)] then
						wallH[x][z] = false; repaired += 1; bfs(x, z); changed = true
					end
				end
			end
		end
	end
	if repaired > 0 then
		print("MazeGenerator: opened " .. repaired .. " wall(s) to fix sealed pockets")
	end
end

local zoneDesc = {}
for _, zn in ipairs(zones) do
	table.insert(zoneDesc, ("(%d,%d)"):format(zn.x, zn.z))
end
print(("MazeGenerator: plaza at (%d,%d) · %d pit zone(s) at %s · elevator at (2,2)")
	:format(fx, fz, #zones, table.concat(zoneDesc, " ")))

-- ── build geometry ────────────────────────────────────────
local maze = Instance.new("Model")
maze.Name = "Maze"

local function part(size, cf, color, material, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or maze
	return p
end

local function applyTexture(p, id, faces, tile, tint)
	if id == "" then return end
	for _, face in ipairs(faces) do
		local t = Instance.new("Texture")
		t.Texture = id
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		if tint then t.Color3 = tint end -- darkens the texture image itself
		t.Parent = p
	end
end

local WALL_FACES = { Enum.NormalId.Front, Enum.NormalId.Back,
	Enum.NormalId.Left, Enum.NormalId.Right }

local function wallPart(size, cf, parent)
	local p = part(size, cf, WALL_COLOR, nil, parent)
	applyTexture(p, WALL_TEXTURE, WALL_FACES, WALL_TILE)
	-- random mold overlay hanging from the top of some walls
	if MOLD_TEXTURE ~= "" and math.random() < MOLD_CHANCE then
		for _, face in ipairs(WALL_FACES) do
			local t = Instance.new("Texture")
			t.Texture = MOLD_TEXTURE
			t.Face = face
			t.StudsPerTileU = 12
			t.StudsPerTileV = WALL_H -- one vertical repeat: image top = wall top
			t.OffsetStudsU = math.random(0, 11) -- so patches don't visibly repeat
			t.ZIndex = 2 -- draw above the base wall texture
			t.Parent = p
		end
	end
	return p
end

local function floorTile(size, px, pz)
	local p = part(size, CFrame.new(px, -0.5, pz), FLOOR_COLOR, Enum.Material.Fabric)
	applyTexture(p, FLOOR_TEXTURE, { Enum.NormalId.Top }, FLOOR_TILE)
	return p
end

local SIZE = GRID * CELL
local O = -SIZE / 2 -- world coord of the maze's min edge

local entityStartCF = CFrame.new(O + (GRID - 1.5) * CELL, 3, O + (GRID - 1.5) * CELL)

-- ── pit touch handler ─────────────────────────────────────
local function ownerModel(hit)
	local m = hit.Parent
	while m and m ~= workspace do
		if m:FindFirstChildOfClass("Humanoid") then return m end
		m = m.Parent
	end
	return nil
end

local function onPitTouch(hit)
	local model = ownerModel(hit)
	if not model then return end
	if model.Name == "Entity" then
		-- the entity climbs back out instead of soft-locking the round
		model:PivotTo(entityStartCF + Vector3.new(0, 5, 0))
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if Players:GetPlayerFromCharacter(model) and hum and hum.Health > 0 then
		hum.Health = 0
	end
end

-- ── floor (per-cell tiles; pit zones get their own hole grids) ──
for x = 1, GRID do
	for z = 1, GRID do
		if not pitCellSet[key(x, z)] then
			floorTile(Vector3.new(CELL, 1, CELL),
				O + (x - 0.5) * CELL, O + (z - 0.5) * CELL)
		end
	end
end

-- ── pit zones: continuous hole grid over one deep shaft ──
-- invisible zone markers let EntityAI route around the hole fields
local pitZoneFolder = Instance.new("Folder")
pitZoneFolder.Name = "PitZones"
pitZoneFolder.Parent = workspace

-- matches the first depth band's shade, so the wallpaper runs seamlessly
-- from the floor's top edge all the way down — no bare strip anywhere
local SIDE_TINT = Color3.new(0.5, 0.5, 0.5)

-- walkway strip: floor texture on top, wall texture on the sides at the same
-- tile scale as the depth bands below (continuous wallpaper)
local function walkway(size, px, pz)
	local p = floorTile(size, px, pz)
	applyTexture(p, WALL_TEXTURE, WALL_FACES, WALL_TILE, SIDE_TINT)
	return p
end

-- depth bands: exponential fade — light being swallowed, not stripes of tint.
-- Each band is roughly half as bright as the one above; band heights grow so
-- no seam sits at an obvious even interval.
local BEAM_BANDS = {}
do
	local shades  = { 0.50, 0.28, 0.15, 0.07, 0.03 }
	local heights = { 4, 5, 7, 9 }
	heights[5] = math.max(PIT_DEPTH - 1 - (4 + 5 + 7 + 9), 2)
	for i = 1, 5 do BEAM_BANDS[i] = { shades[i], heights[i] } end
end

-- full-depth beam, clean square edges: every hole gets real walls with
-- wallpaper running from the floor's top edge all the way down
local function deepBeam(alongX, px, pz, length)
	local W = PIT_GAP

	-- full-width top plate (floor texture top, wallpapered sides)
	if alongX then
		walkway(Vector3.new(length, 1, W), px, pz)
	else
		walkway(Vector3.new(W, 1, length), px, pz)
	end

	-- full-width depth bands (these faces ARE the hole walls)
	local yTop = -1
	for _, band in ipairs(BEAM_BANDS) do
		local shade, h = band[1], band[2]
		local col = Color3.new(WALL_COLOR.R * shade, WALL_COLOR.G * shade, WALL_COLOR.B * shade)
		local size = alongX and Vector3.new(length, h, W) or Vector3.new(W, h, length)
		local p = part(size, CFrame.new(px, yTop - h / 2, pz), col)
		if shade > 0.05 then -- texture contributes nothing in the near-black bands
			applyTexture(p, WALL_TEXTURE, WALL_FACES, WALL_TILE, Color3.new(shade, shade, shade))
		end
		-- mold wraps the top band of every hole wall in the pit zones
		if MOLD_TEXTURE ~= "" and yTop == -1 then
			for _, face in ipairs(WALL_FACES) do
				local t = Instance.new("Texture")
				t.Texture = MOLD_TEXTURE
				t.Face = face
				t.StudsPerTileU = 8
				t.StudsPerTileV = h
				t.OffsetStudsU = math.random(0, 7)
				t.ZIndex = 2
				t.Parent = p
			end
		end
		yTop -= h
	end
end

for _, zn in ipairs(zones) do
	local span = PIT_ZONE_CELLS * CELL
	local x0 = O + (zn.x - 1) * CELL
	local z0 = O + (zn.z - 1) * CELL
	local cx, cz = x0 + span / 2, z0 + span / 2

	-- marker for the AI (no collision, no rendering)
	local zoneMark = Instance.new("Part")
	zoneMark.Name = "Zone"
	zoneMark.Size = Vector3.new(span, 2, span)
	zoneMark.CFrame = CFrame.new(cx, 1, cz)
	zoneMark.Anchored = true
	zoneMark.CanCollide = false
	zoneMark.CanQuery = false
	zoneMark.Transparency = 1
	zoneMark.Parent = pitZoneFolder

	-- how many holes fit, and the leftover solid border on each side
	local n = math.floor((span - PIT_GAP) / (PIT_HOLE + PIT_GAP))
	local used = PIT_GAP + n * (PIT_HOLE + PIT_GAP)
	local pad = (span - used) / 2

	-- solid edge pads
	if pad > 0.05 then
		walkway(Vector3.new(pad, 1, span), x0 + pad / 2, cz)
		walkway(Vector3.new(pad, 1, span), x0 + span - pad / 2, cz)
		walkway(Vector3.new(span, 1, pad), cx, z0 + pad / 2)
		walkway(Vector3.new(span, 1, pad), cx, z0 + span - pad / 2)
	end

	-- walkable beams criss-crossing the whole zone — full-depth slabs, so
	-- every hole is its own four-walled shaft
	for i = 0, n do
		local off = pad + i * (PIT_HOLE + PIT_GAP) + PIT_GAP / 2
		deepBeam(false, x0 + off, cz, span) -- runs along Z
		deepBeam(true, cx, z0 + off, span)  -- runs along X
	end

	-- entity-only invisible barrier around the zone: the entity physically
	-- cannot enter the hole field (players pass straight through), and the
	-- barrier blocks the navmesh so its pathfinding routes around too
	local function barrier(size, cf)
		local b = Instance.new("Part")
		b.Name = "Barrier"
		b.Size = size
		b.CFrame = cf
		b.Anchored = true
		b.Transparency = 1
		b.CanQuery = false -- must not block the entity's sight raycasts
		b.CollisionGroup = "PitBarrier"
		b.Parent = pitZoneFolder
	end
	barrier(Vector3.new(span + 2, WALL_H, 1), CFrame.new(cx, WALL_H / 2, z0 - 0.5))
	barrier(Vector3.new(span + 2, WALL_H, 1), CFrame.new(cx, WALL_H / 2, z0 + span + 0.5))
	barrier(Vector3.new(1, WALL_H, span + 2), CFrame.new(x0 - 0.5, WALL_H / 2, cz))
	barrier(Vector3.new(1, WALL_H, span + 2), CFrame.new(x0 + span + 0.5, WALL_H / 2, cz))

	-- bottom: lethal for players, a rescue teleport for the entity
	local bottom = part(Vector3.new(span, 1, span),
		CFrame.new(cx, -PIT_DEPTH, cz), PIT_COLOR, Enum.Material.Concrete)
	bottom.Touched:Connect(onPitTouch)
end

-- ceiling — texture offset by half a tile so a tile sits CENTERED under each
-- light panel (cell centers land on the tile grid lines otherwise)
local ceilingPart = part(Vector3.new(SIZE, 1, SIZE), CFrame.new(0, WALL_H + 0.5, 0),
	CEILING_COLOR)
if CEILING_TEXTURE ~= "" then
	local t = Instance.new("Texture")
	t.Texture = CEILING_TEXTURE
	t.Face = Enum.NormalId.Bottom
	t.StudsPerTileU = CEILING_TILE
	t.StudsPerTileV = CEILING_TILE
	t.OffsetStudsU = CEILING_TILE / 2
	t.OffsetStudsV = CEILING_TILE / 2
	t.Parent = ceilingPart
end

-- border walls
wallPart(Vector3.new(SIZE + WALL_T * 2, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, O - WALL_T / 2))
wallPart(Vector3.new(SIZE + WALL_T * 2, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, -O + WALL_T / 2))
wallPart(Vector3.new(WALL_T, WALL_H, SIZE + WALL_T * 2), CFrame.new(O - WALL_T / 2, WALL_H / 2, 0))
wallPart(Vector3.new(WALL_T, WALL_H, SIZE + WALL_T * 2), CFrame.new(-O + WALL_T / 2, WALL_H / 2, 0))

-- internal walls (skip the elevator cell — its shell replaces them)
for x = 1, GRID - 1 do
	for z = 1, GRID do
		if wallV[x][z] then
			wallPart(Vector3.new(WALL_T, WALL_H, CELL + WALL_T),
				CFrame.new(O + x * CELL, WALL_H / 2, O + (z - 0.5) * CELL))
		end
	end
end
for x = 1, GRID do
	for z = 1, GRID - 1 do
		if wallH[x][z] then
			wallPart(Vector3.new(CELL + WALL_T, WALL_H, WALL_T),
				CFrame.new(O + (x - 0.5) * CELL, WALL_H / 2, O + z * CELL))
		end
	end
end

-- ── elevator: fills the whole start cell, flush with the wall grid ──
-- Yellow textured shell outside (native backrooms wall), metal cabin inside,
-- metal doors on the east face. GameManager finds "Elevator" and drives the doors.
do
	local x0, x1 = O + CELL, O + 2 * CELL          -- start cell bounds (cell 2,2)
	local z0, z1 = O + CELL, O + 2 * CELL
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2

	local elev = Instance.new("Model")
	elev.Name = "Elevator"

	local STEEL      = Color3.fromRGB(118, 122, 128) -- dark brushed steel
	local STEEL_DARK = Color3.fromRGB(88, 92, 98)
	local MARBLE     = Color3.fromRGB(24, 24, 28)    -- near-black marble floor
	local CAB_W = 8 -- interior width — LONG and narrow, not wide

	-- outer shell: same textured yellow walls as the rest of the maze
	wallPart(Vector3.new(CELL, WALL_H, 2), CFrame.new(cx, WALL_H / 2, z0 + 1), elev)   -- south
	wallPart(Vector3.new(CELL, WALL_H, 2), CFrame.new(cx, WALL_H / 2, z1 - 1), elev)   -- north
	wallPart(Vector3.new(2, WALL_H, CELL), CFrame.new(x0 + 1, WALL_H / 2, cz), elev)   -- west (back)
	-- east face: header above the doors + fillers leaving an 8-stud opening
	wallPart(Vector3.new(2, WALL_H - 10, CELL), CFrame.new(x1 - 1, (WALL_H + 10) / 2, cz), elev)
	wallPart(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z0 + 4), elev)
	wallPart(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z1 - 4), elev)

	-- sliding stainless doors (named for GameManager; they slide ±4 now)
	local doorL = part(Vector3.new(1, 10, 4), CFrame.new(x1 - 1, 5, cz - 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorL.Name = "DoorL"
	local doorR = part(Vector3.new(1, 10, 4), CFrame.new(x1 - 1, 5, cz + 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorR.Name = "DoorR"
	applyTexture(doorL, ELEV_DOOR_TEXTURE, WALL_FACES, ELEV_TILE)
	applyTexture(doorR, ELEV_DOOR_TEXTURE, WALL_FACES, ELEV_TILE)

	elev.Parent = workspace

	-- the ONLY SpawnLocation in the game → everyone spawns inside the cabin
	local pad = Instance.new("SpawnLocation")
	pad.Name = "ElevatorSpawn"
	pad.Anchored = true
	pad.CanCollide = false
	pad.Transparency = 1
	pad.Neutral = true
	pad.Duration = 0
	pad.Parent = workspace

	-- cabin interior: deep, tight, and it GROWS with the player count.
	-- Rebuilt in place; walls sit flush with the 8-stud door opening so
	-- nothing pokes through the yellow shell.
	local cabin
	local function buildCabin(depth)
		depth = math.clamp(depth, 8, 18)
		if cabin then cabin:Destroy() end
		cabin = Instance.new("Model")
		cabin.Name = "Cabin"

		local xFront = x1 - 2         -- interior front, right behind the doors
		local xBack = xFront - depth
		local bx = (xFront + xBack) / 2

		local back = part(Vector3.new(0.5, 10, CAB_W + 1), CFrame.new(xBack - 0.25, 5, cz), STEEL, Enum.Material.Metal, cabin)
		local sideA = part(Vector3.new(depth, 10, 0.5), CFrame.new(bx, 5, cz - CAB_W / 2 - 0.25), STEEL, Enum.Material.Metal, cabin)
		local sideB = part(Vector3.new(depth, 10, 0.5), CFrame.new(bx, 5, cz + CAB_W / 2 + 0.25), STEEL, Enum.Material.Metal, cabin)
		part(Vector3.new(depth + 1, 1, CAB_W + 2), CFrame.new(bx - 0.25, 10.5, cz), STEEL_DARK, Enum.Material.Metal, cabin) -- roof
		local floorP = part(Vector3.new(depth, 0.2, CAB_W), CFrame.new(bx, 0.1, cz), MARBLE, Enum.Material.Marble, cabin)

		-- optional custom cabin textures
		applyTexture(back, ELEV_WALL_TEXTURE, WALL_FACES, ELEV_TILE)
		applyTexture(sideA, ELEV_WALL_TEXTURE, WALL_FACES, ELEV_TILE)
		applyTexture(sideB, ELEV_WALL_TEXTURE, WALL_FACES, ELEV_TILE)
		applyTexture(floorP, ELEV_FLOOR_TEXTURE, { Enum.NormalId.Top }, ELEV_TILE)

		local lightPanel = part(Vector3.new(2, 0.3, 2), CFrame.new(bx, 9.7, cz),
			Color3.fromRGB(255, 250, 230), Enum.Material.Neon, cabin)
		local elevLamp = Instance.new("PointLight")
		elevLamp.Brightness = 1
		elevLamp.Range = depth + 8
		elevLamp.Color = Color3.fromRGB(255, 240, 210)
		elevLamp.Parent = lightPanel

		pad.Size = Vector3.new(math.max(depth - 3, 4), 1, CAB_W - 2)
		pad.Position = Vector3.new(bx, 0.5, cz)

		cabin.Parent = elev
	end

	local function cabinDepth()
		-- 1 player → 10 studs deep · +2 per extra player · caps at 18
		return 8 + math.clamp(#Players:GetPlayers(), 1, 5) * 2
	end
	buildCabin(cabinDepth())
	Players.PlayerAdded:Connect(function()
		task.delay(0.1, function() buildCabin(cabinDepth()) end)
	end)
	Players.PlayerRemoving:Connect(function()
		task.delay(0.5, function() buildCabin(cabinDepth()) end)
	end)
end

-- ── ceiling lights ────────────────────────────────────────
local flicker = {}
local allLights = {} -- every WORKING light, for the entity-presence effect
for x = 2, GRID, LIGHT_EVERY do
	for z = 2, GRID, LIGHT_EVERY do
		if not (x == 2 and z == 2) then -- skip the elevator cell
			local isDead = math.random() < DEAD_CHANCE

			-- panel embedded in the ceiling slab, face sitting a hair (0.1)
			-- below the ceiling plane so it never clips the ceiling texture
			local panel = part(Vector3.new(LIGHT_SIZE, 0.4, LIGHT_SIZE),
				CFrame.new(O + (x - 0.5) * CELL, WALL_H + 0.1, O + (z - 0.5) * CELL),
				isDead and Color3.fromRGB(118, 115, 102) or Color3.fromRGB(255, 250, 230),
				isDead and Enum.Material.SmoothPlastic or Enum.Material.Neon)

			-- optional fixture texture on the panel face (one image per panel)
			local texId = isDead and DEAD_LIGHT_TEXTURE or LIGHT_TEXTURE
			if texId ~= "" then
				local ft = Instance.new("Texture")
				ft.Texture = texId
				ft.Face = Enum.NormalId.Bottom
				ft.StudsPerTileU = LIGHT_SIZE
				ft.StudsPerTileV = LIGHT_SIZE
				ft.Parent = panel
			end

			local light = Instance.new("SurfaceLight")
			light.Face = Enum.NormalId.Bottom
			light.Brightness = 0.7 -- dim enough that darkness pools between lights
			light.Range = 28
			light.Angle = 140
			light.Color = LIGHT_COLOR
			light.Shadows = false -- shadows on hundreds of lights kills performance
			light.Enabled = not isDead
			light.Parent = panel

			if not isDead then
				table.insert(allLights, { panel = panel, light = light, pos = panel.Position })
				if math.random() < FLICKER_CHANCE then
					table.insert(flicker, { panel, light })
				end
			end
		end
	end
end

maze.Parent = workspace

-- ── markers for GameManager (invisible, no collision) ─────
local function marker(name, cf)
	local m = Instance.new("Part")
	m.Name = name
	m.Size = Vector3.new(2, 2, 2)
	m.CFrame = cf
	m.Anchored = true
	m.CanCollide = false
	m.CanQuery = false
	m.Transparency = 1
	m.Parent = workspace
	return m
end

marker("MazeStart", CFrame.new(O + 1.5 * CELL, 3, O + 1.5 * CELL))
marker("EntityStart", entityStartCF)

-- park the entity in its corner until GameManager takes over
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 15)
	if entity and entity.PrimaryPart then
		entity:PivotTo(entityStartCF + Vector3.new(0, 5, 0))
	end
end)

-- ── mood lighting: horror pass ────────────────────────────
Lighting.Ambient = Color3.fromRGB(4, 4, 3)      -- near-total darkness between lights
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.Brightness = 0.3
Lighting.ClockTime = 0
Lighting.GlobalShadows = true
Lighting.FogColor = Color3.fromRGB(16, 14, 9)   -- darker, closer fog — dread, not haze
Lighting.FogEnd = 160
Lighting.FogStart = 12

-- color grade: desaturated, contrast-crushed, sickly warm tint
local grade = Lighting:FindFirstChild("MongoGrade") or Instance.new("ColorCorrectionEffect")
grade.Name = "MongoGrade"
grade.Saturation = -0.3
grade.Contrast = 0.12
grade.Brightness = -0.02
grade.TintColor = Color3.fromRGB(255, 243, 220)
grade.Parent = Lighting

-- ── light flicker: fast fluorescent buzz-bursts ───────────
-- each flickering light idles, then strobes rapidly for a moment
local function setLight(f, on)
	f[2].Enabled = on
	f[1].Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
end

for _, f in ipairs(flicker) do
	task.spawn(function()
		while true do
			task.wait(1 + math.random() * 4)          -- calm period
			for _ = 1, math.random(4, 10) do          -- rapid strobe burst
				setLight(f, false)
				task.wait(0.03 + math.random() * 0.06)
				setLight(f, true)
				task.wait(0.03 + math.random() * 0.06)
			end
			-- occasionally stay dark a beat before recovering
			if math.random() < 0.3 then
				setLight(f, false)
				task.wait(0.2 + math.random() * 0.5)
				setLight(f, true)
			end
		end
	end)
end

-- ── entity presence: lights ahead of it are just LIKELIER to flicker ──
-- not a constant strobe — every 2s the 1–2 nearest lights in front of the
-- entity each have a 50% chance of one short burst (~double the ambient rate)
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 30)
	if not entity then return end
	local busy = {}
	while true do
		task.wait(2)
		local root = entity:FindFirstChild("HumanoidRootPart")
		if root then
			local ahead = root.Position + root.CFrame.LookVector * 18

			-- two nearest working lights to the point the entity is facing
			local best, bestD = nil, math.huge
			local best2, bestD2 = nil, math.huge
			for _, L in ipairs(allLights) do
				local d = (L.pos - ahead).Magnitude
				if d < bestD then
					best2, bestD2 = best, bestD
					best, bestD = L, d
				elseif d < bestD2 then
					best2, bestD2 = L, d
				end
			end

			for _, L in ipairs({ best, best2 }) do
				if L and (L.pos - ahead).Magnitude < 45 and not busy[L]
					and math.random() < 0.5 then
					busy[L] = true
					task.spawn(function()
						for _ = 1, math.random(2, 5) do
							setLight({ L.panel, L.light }, false)
							task.wait(0.04 + math.random() * 0.05)
							setLight({ L.panel, L.light }, true)
							task.wait(0.04 + math.random() * 0.05)
						end
						busy[L] = nil
					end)
				end
			end
		end
	end
end)
