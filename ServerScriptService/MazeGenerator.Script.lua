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

-- decor (furniture) is solid for PLAYERS, but the entity passes straight through
-- it so it can never get snagged/stuck on a chair or table while chasing
pcall(function() PhysicsService:RegisterCollisionGroup("Decor") end)
PhysicsService:CollisionGroupSetCollidable("Decor", "Entity", false)

-- stop the entity free-falling during generation — its Studio spot has no floor
-- under it. Anchor it now; EntityAI drops it on the floor once the maze exists.
do
	local e0 = workspace:FindFirstChild("Entity")
	if e0 and e0.PrimaryPart then e0.PrimaryPart.Anchored = true end
end

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
local PIT_HOLE       = 12    -- hole size in studs
local PIT_GAP        = 1     -- beam width between holes, in studs (tight but walkable)
local PIT_DEPTH      = 50    -- how far down the shaft goes
local PIT_SAFE_CELLS = 0     -- min cell distance from the start/entity corners

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
local LIGHT_TEXTURE      = "rbxassetid://135786374638992"  -- lit fixture face
local DEAD_LIGHT_TEXTURE = "rbxassetid://107766152992499"  -- broken/dark fixture face

-- Optional elevator textures (your own decals)
local ELEV_WALL_TEXTURE  = "" -- cabin walls (over the steel)
local ELEV_FLOOR_TEXTURE = "" -- cabin floor (over the marble)
local ELEV_DOOR_TEXTURE  = "" -- door faces
local ELEV_TILE = 4           -- studs per repeat inside the cabin

-- Optional MOLD overlay (your own decals, transparent PNGs) — up to 5 variants,
-- picked at random per wall. Draw the mold hanging from the TOP of the image,
-- rest transparent — it's tiled once over the wall height, so image-top =
-- wall-top. Spawns on the top of maze walls AND wraps the top of every pit-shaft
-- wall. Plug in IDs when you have them; leave empty and no mold generates.
local MOLD_TEXTURES = {
	-- "rbxassetid://...",  -- mold 1
	-- "rbxassetid://...",  -- mold 2
	-- "rbxassetid://...",  -- mold 3
	-- "rbxassetid://...",  -- mold 4
	-- "rbxassetid://...",  -- mold 5
}
local MOLD_CHANCE  = 0.22 -- fraction of walls that get mold

-- Optional ARTWORK / drawings / clues (your own decals) — up to 5 variants.
-- Each is stamped once, CENTERED on a wall (middle height, middle of the panel).
local ARTWORK = {
	-- "rbxassetid://...",  -- artwork 1
	-- "rbxassetid://...",  -- artwork 2
	-- "rbxassetid://...",  -- artwork 3
	-- "rbxassetid://...",  -- artwork 4
	-- "rbxassetid://...",  -- artwork 5
}
local ARTWORK_CHANCE = 0.05 -- per maze wall
local ARTWORK_SIZE   = 8    -- stamp size in studs

-- Optional STAIN decals (your own) — up to 5 variants. Stamped flat on random
-- floor tiles, ANYWHERE on the carpet.
local STAIN_TEXTURES = {
	-- "rbxassetid://...",  -- stain 1
	-- "rbxassetid://...",  -- stain 2
	-- "rbxassetid://...",  -- stain 3
	-- "rbxassetid://...",  -- stain 4
	-- "rbxassetid://...",  -- stain 5
}
local STAIN_CHANCE = 0.06 -- per floor cell

-- ── decor / furniture props ───────────────────────────────
-- Self-built from primitive Parts (the Toolbox model IDs mostly failed to load /
-- came in sideways, so we build our own — always upright, correctly sized, no
-- InsertService needed). Each prop's model is defined in DECOR_BUILDERS lower
-- down; here you tune size/rarity/placement. DECOR_DENSITY is the master knob.
local DECOR_DENSITY = 0.1      -- chance PER eligible cell that it tries a prop
local DECOR_COLLIDE = true     -- props are solid for players; the entity walks through
local DECOR_SCALE_JITTER = 0.2 -- ±fraction random size wobble per prop (weird-gen look)
local DECOR_MIN_GAP = 2        -- same-type props must be MORE than this many cells apart
-- place = "room" (alone in the middle of an open cell) or "wall" (against a wall)
-- weight = relative pick chance · height = studs tall (per-object size knob)
local PROPS = {
	{ name = "Chair",            height = 3.5, place = "room", weight = 3 },
	{ name = "Table",            height = 3.2, place = "room", weight = 2, phone = true }, -- carries a phone
	{ name = "CardboardBox",     height = 2.6, place = "wall", weight = 3 },
	{ name = "Printer",          height = 4.5, place = "wall", weight = 2 },
	{ name = "GrandfatherClock", height = 8.5, place = "wall", weight = 1 },
}
-- ──────────────────────────────────────────────────────────

if SEED then math.randomseed(SEED) end

-- safety: zones must fit inside the maze with room to place — out-of-range
-- values error out in math.random/math.clamp otherwise
PIT_ZONE_CELLS = math.clamp(PIT_ZONE_CELLS, 2, math.floor(GRID / 3))

-- elevator location: centered in the maze, with an open room around it so it
-- looks like it just stands there out in the open
local ELEV_CLEAR = 2                  -- open cells on every side of the elevator
local ELEV_X = math.floor(GRID / 2)
local ELEV_Y = math.floor(GRID / 2)

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
LIGHT_TEXTURE = resolveTexture(LIGHT_TEXTURE)
DEAD_LIGHT_TEXTURE = resolveTexture(DEAD_LIGHT_TEXTURE)
ELEV_WALL_TEXTURE = resolveTexture(ELEV_WALL_TEXTURE)
ELEV_FLOOR_TEXTURE = resolveTexture(ELEV_FLOOR_TEXTURE)
ELEV_DOOR_TEXTURE = resolveTexture(ELEV_DOOR_TEXTURE)
for i, id in ipairs(MOLD_TEXTURES) do MOLD_TEXTURES[i] = resolveTexture(id) end
for i, id in ipairs(ARTWORK) do ARTWORK[i] = resolveTexture(id) end
for i, id in ipairs(STAIN_TEXTURES) do STAIN_TEXTURES[i] = resolveTexture(id) end

-- pick a random mold decal, or nil if none configured
local function pickMold()
	if #MOLD_TEXTURES == 0 then return nil end
	return MOLD_TEXTURES[math.random(#MOLD_TEXTURES)]
end

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

-- ── open room around the central elevator ─────────────────
-- clear every wall within ELEV_CLEAR cells so the elevator stands alone
for x = ELEV_X - ELEV_CLEAR, ELEV_X + ELEV_CLEAR - 1 do
	for z = ELEV_Y - ELEV_CLEAR, ELEV_Y + ELEV_CLEAR do
		if wallV[x] and wallV[x][z] ~= nil then wallV[x][z] = false end
	end
end
for x = ELEV_X - ELEV_CLEAR, ELEV_X + ELEV_CLEAR do
	for z = ELEV_Y - ELEV_CLEAR, ELEV_Y + ELEV_CLEAR - 1 do
		if wallH[x] and wallH[x][z] ~= nil then wallH[x][z] = false end
	end
end

-- the elevator shell provides this cell's 4 walls (doors on the east), so
-- suppress the maze's own copies — otherwise they clip/z-fight the shell
wallV[ELEV_X - 1][ELEV_Y] = false
wallV[ELEV_X][ELEV_Y] = false
wallH[ELEV_X][ELEV_Y - 1] = false
wallH[ELEV_X][ELEV_Y] = false

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
	-- keep away from the central elevator room and the entity's corner
	local hi = PIT_ZONE_CELLS - 1
	local function nearPoint(cx0, cz0, margin)
		return zx <= cx0 + margin and zx + hi >= cx0 - margin
			and zz <= cz0 + margin and zz + hi >= cz0 - margin
	end
	return not (nearPoint(ELEV_X, ELEV_Y, PIT_SAFE_CELLS + ELEV_CLEAR)
		or nearPoint(GRID - 1, GRID - 1, PIT_SAFE_CELLS))
end

-- pit zones placed randomly, avoiding the elevator room, the entity corner,
-- and each other
for i = 1, PIT_ZONES do
	local placed = false
	for _ = 1, 120 do -- placement attempts
		local zx = math.random(2, GRID - PIT_ZONE_CELLS)
		local zz = math.random(2, GRID - PIT_ZONE_CELLS)
		if zoneOK(zx, zz) then
			table.insert(zones, { x = zx, z = zz })
			placed = true
			break
		end
	end
	if not placed then
		warn(("MazeGenerator: couldn't place pit zone %d — map too crowded"):format(i))
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
	local blocked = { [key(ELEV_X, ELEV_Y)] = true } -- elevator cell is solid
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

	bfs(ELEV_X + 1, ELEV_Y) -- just outside the elevator doors (east)

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
print(("MazeGenerator: plaza at (%d,%d) · %d pit zone(s) at %s · elevator at (%d,%d)")
	:format(fx, fz, #zones, table.concat(zoneDesc, " "), ELEV_X, ELEV_Y))

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

-- stamp one artwork decal CENTERED on a maze wall face — dead middle of the
-- panel horizontally, wall-mid height vertically (so it reads like hung art)
local function stampArtwork(cf, size)
	if #ARTWORK == 0 or math.random() >= ARTWORK_CHANCE then return end
	local id = ARTWORK[math.random(#ARTWORK)]
	local thinX = size.X < size.Z
	local sign = (math.random() < 0.5) and 1 or -1 -- which face of the wall
	local half = (thinX and size.X or size.Z) / 2
	local y = cf.Y -- wall CFrame Y is the wall's vertical centre → middle height

	local pos, normal
	if thinX then
		normal = Vector3.new(sign, 0, 0)
		pos = Vector3.new(cf.X + sign * (half + 0.05), y, cf.Z) -- centred on Z
	else
		normal = Vector3.new(0, 0, sign)
		pos = Vector3.new(cf.X, y, cf.Z + sign * (half + 0.05)) -- centred on X
	end

	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(ARTWORK_SIZE, ARTWORK_SIZE, 0.05)
	p.CFrame = CFrame.new(pos, pos + normal) -- Front face points outward
	local d = Instance.new("Decal")
	d.Texture = id
	d.Face = Enum.NormalId.Front
	d.Parent = p
	p.Parent = maze
end

local function wallPart(size, cf, parent)
	local p = part(size, cf, WALL_COLOR, nil, parent)
	applyTexture(p, WALL_TEXTURE, WALL_FACES, WALL_TILE)
	-- random mold overlay hanging from the top of some walls
	local mold = pickMold()
	if mold and math.random() < MOLD_CHANCE then
		for _, face in ipairs(WALL_FACES) do
			local t = Instance.new("Texture")
			t.Texture = mold
			t.Face = face
			t.StudsPerTileU = 12
			t.StudsPerTileV = WALL_H -- one vertical repeat: image top = wall top
			t.OffsetStudsU = math.random(0, 11) -- so patches don't visibly repeat
			t.ZIndex = 2 -- draw above the base wall texture
			t.Parent = p
		end
	end
	-- artwork only on real maze walls (not the elevator shell / pit walls)
	if not parent then stampArtwork(cf, size) end
	return p
end

local function floorTile(size, px, pz)
	local p = part(size, CFrame.new(px, -0.5, pz), FLOOR_COLOR, Enum.Material.Fabric)
	applyTexture(p, FLOOR_TEXTURE, { Enum.NormalId.Top }, FLOOR_TILE)
	return p
end

-- stamp a stain decal flat on the carpet at a random size/rotation
local function stampStain(cx, cz)
	if #STAIN_TEXTURES == 0 or math.random() >= STAIN_CHANCE then return end
	local id = STAIN_TEXTURES[math.random(#STAIN_TEXTURES)]
	local s = math.random(6, 12)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.new(s, 0.05, s)
	p.CFrame = CFrame.new(cx, 0.03, cz) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local d = Instance.new("Decal")
	d.Texture = id
	d.Face = Enum.NormalId.Top
	d.Parent = p
	p.Parent = maze
end

local SIZE = GRID * CELL
local O = -SIZE / 2 -- world coord of the maze's min edge

-- publish maze data + shared game state for PuzzleManager / EntityAI to read
workspace:SetAttribute("GRID", GRID)
workspace:SetAttribute("CELL", CELL)
workspace:SetAttribute("WALL_H", WALL_H)
workspace:SetAttribute("ORIGIN", O)
workspace:SetAttribute("ELEV_X", ELEV_X)
workspace:SetAttribute("ELEV_Y", ELEV_Y)
workspace:SetAttribute("LightMode", "NORMAL")   -- NORMAL · ALERT · BLACKOUT
workspace:SetAttribute("FlickerBoost", 0)       -- higher = lights flicker more
workspace:SetAttribute("EntitySpeedMul", 1)     -- entity speed multiplier

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
		local bbox, size = model:GetBoundingBox()
		local pivot = model:GetPivot()
		model:PivotTo(CFrame.new(entityStartCF.X, 0.5 + (pivot.Y - (bbox.Y - size.Y / 2)), entityStartCF.Z))
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
			local fcx, fcz = O + (x - 0.5) * CELL, O + (z - 0.5) * CELL
			floorTile(Vector3.new(CELL, 1, CELL), fcx, fcz)
			stampStain(fcx, fcz)
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
		local pitMold = (yTop == -1) and pickMold() or nil
		if pitMold then
			for _, face in ipairs(WALL_FACES) do
				local t = Instance.new("Texture")
				t.Texture = pitMold
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

-- ceiling — one slab, texture offset by half a tile so a tile sits centered
-- under each light. The flush light panels (below) are opaque, so they simply
-- hide the tile behind them — no clipping.
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
	local x0, x1 = O + (ELEV_X - 1) * CELL, O + ELEV_X * CELL -- elevator cell bounds
	local z0, z1 = O + (ELEV_Y - 1) * CELL, O + ELEV_Y * CELL
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
	-- east face: a BLACK elevator frame around the doors (header + side fillers)
	-- instead of yellow wall — so from the maze it reads as a proper elevator
	-- entrance ("there's supposed to be an elevator here"). 8-stud opening.
	local FRAME = Color3.fromRGB(14, 14, 17)
	part(Vector3.new(2, WALL_H - 10, CELL), CFrame.new(x1 - 1, (WALL_H + 10) / 2, cz), FRAME, Enum.Material.Metal, elev)
	part(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z0 + 4), FRAME, Enum.Material.Metal, elev)
	part(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z1 - 4), FRAME, Enum.Material.Metal, elev)

	-- sliding stainless doors (named for GameManager; they slide ±4 now). Thicker
	-- than the 2-stud wall cavity (2.2) so no yellow shell can peek at the edges;
	-- being wider than the fillers, an open door hides them inside it (no z-fight).
	local doorL = part(Vector3.new(2.2, 10, 4), CFrame.new(x1 - 1, 5, cz - 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorL.Name = "DoorL"
	local doorR = part(Vector3.new(2.2, 10, 4), CFrame.new(x1 - 1, 5, cz + 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorR.Name = "DoorR"
	applyTexture(doorL, ELEV_DOOR_TEXTURE, WALL_FACES, ELEV_TILE)
	applyTexture(doorR, ELEV_DOOR_TEXTURE, WALL_FACES, ELEV_TILE)

	-- threshold GAP: a dark, near-flush band across the doorway — the shadow gap
	-- between a building floor and the elevator car. Cosmetic (the carpet tile
	-- under it carries the player), and it hides the door bottoms at the seam.
	local sill = part(Vector3.new(2.6, 0.3, 8), CFrame.new(x1 - 1, 0.0, cz),
		Color3.fromRGB(8, 8, 10), Enum.Material.Metal, elev)
	sill.CanCollide = false
	sill.CanQuery = false

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

		-- cosmetic FLOOR SELECTOR by the doors: a lit button panel with numbers.
		-- Purely decorative — no collision, no query, does nothing.
		do
			local selX = xFront - 1.2                 -- near the doors
			local selZ = cz + CAB_W / 2 - 0.07         -- flush against the +Z side wall (was floating)
			local plate = part(Vector3.new(1.5, 3, 0.12), CFrame.new(selX, 4.6, selZ),
				Color3.fromRGB(30, 30, 34), Enum.Material.Metal, cabin)
			plate.CanCollide = false
			plate.CanQuery = false

			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front             -- Front = -Z → faces the cabin
			gui.CanvasSize = Vector2.new(150, 300)
			gui.Parent = plate

			-- current-floor readout
			local readout = Instance.new("TextLabel")
			readout.Size = UDim2.new(1, -12, 0, 48)
			readout.Position = UDim2.new(0, 6, 0, 6)
			readout.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
			readout.TextColor3 = Color3.fromRGB(255, 140, 50)
			readout.Font = Enum.Font.Gotham
			readout.TextScaled = true
			readout.Text = "\u{25B2} 1"
			readout.Parent = gui
			local rc = Instance.new("UICorner"); rc.CornerRadius = UDim.new(0, 6); rc.Parent = readout

			-- floor buttons grid
			local holder = Instance.new("Frame")
			holder.Size = UDim2.new(1, -12, 1, -66)
			holder.Position = UDim2.new(0, 6, 0, 60)
			holder.BackgroundTransparency = 1
			holder.Parent = gui
			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.new(0, 62, 0, 46)
			grid.CellPadding = UDim2.new(0, 6, 0, 6)
			grid.Parent = holder
			for f = 1, 8 do
				local b = Instance.new("TextLabel")
				b.Text = tostring(f)
				b.Font = Enum.Font.Gotham
				b.TextScaled = true
				b.TextColor3 = Color3.fromRGB(235, 235, 240)
				b.BackgroundColor3 = (f == 1) and Color3.fromRGB(70, 120, 60) or Color3.fromRGB(45, 45, 52)
				b.Parent = holder
				local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = b
			end
		end

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
		if not (x == ELEV_X and z == ELEV_Y) then -- skip the elevator cell
			local isDead = math.random() < DEAD_CHANCE

			-- flush with the ceiling: bottom face sits 0.075 below the ceiling
			-- plane (clear of it → no z-fight) and the opaque panel hides the
			-- tile behind it. Reads as level with the ceiling.
			local panel = part(Vector3.new(LIGHT_SIZE, 0.15, LIGHT_SIZE),
				CFrame.new(O + (x - 0.5) * CELL, WALL_H, O + (z - 0.5) * CELL),
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

			-- cover the thin exposed rim (the 4 sides) with the ceiling texture
			-- so it blends into the ceiling instead of showing a lit edge
			applyTexture(panel, CEILING_TEXTURE, WALL_FACES, CEILING_TILE)

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

-- ── decor / furniture props ───────────────────────────────
-- Built from primitive Parts (self-contained, always UPRIGHT & correctly sized —
-- the Toolbox model IDs mostly failed to load / came in sideways). Room props
-- (chairs/tables) sit alone in open cells; wall props (boxes/printers/clocks)
-- stand against a wall facing in; tables carry a phone. One chair is GUARANTEED
-- in the plaza. Everything is in the Decor collision group so the entity walks
-- through it and never gets stuck. Wrapped in a function to keep its locals out
-- of the main chunk's scope (no asset loading, so it still runs synchronously).
task.spawn(function()
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = workspace

	-- one anchored part inside a decor model
	local function dpart(model, size, cf, color, material)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	local WOOD      = Color3.fromRGB(96, 64, 38)
	local WOOD_DARK = Color3.fromRGB(66, 43, 25)
	local CARD      = Color3.fromRGB(178, 142, 92)
	local CARD_DARK = Color3.fromRGB(150, 116, 72)
	local PLASTIC   = Color3.fromRGB(210, 206, 196)
	local BLACK     = Color3.fromRGB(24, 24, 26)
	local CREAM     = Color3.fromRGB(226, 220, 198)

	-- each builder returns a fresh Model, UPRIGHT, front facing -Z, base near y=0
	-- (placeOnFloor re-seats it). Natural sizes; scaleToHeight normalises them.
	local DECOR_BUILDERS = {}

	DECOR_BUILDERS.Chair = function()
		local m = Instance.new("Model"); m.Name = "Chair"
		local seatY = 1.7
		local seat = dpart(m, Vector3.new(2, 0.3, 2), CFrame.new(0, seatY, 0), WOOD)
		dpart(m, Vector3.new(2, 2, 0.25), CFrame.new(0, seatY + 1.1, -0.9), WOOD) -- backrest
		for _, c in ipairs({ { 0.8, 0.8 }, { -0.8, 0.8 }, { 0.8, -0.8 }, { -0.8, -0.8 } }) do
			dpart(m, Vector3.new(0.22, seatY, 0.22), CFrame.new(c[1], seatY / 2, c[2]), WOOD_DARK)
		end
		m.PrimaryPart = seat
		return m
	end

	DECOR_BUILDERS.Table = function()
		local m = Instance.new("Model"); m.Name = "Table"
		local topY = 2.7
		local top = dpart(m, Vector3.new(5, 0.3, 3), CFrame.new(0, topY, 0), WOOD)
		for _, c in ipairs({ { 2.2, 1.2 }, { -2.2, 1.2 }, { 2.2, -1.2 }, { -2.2, -1.2 } }) do
			dpart(m, Vector3.new(0.28, topY, 0.28), CFrame.new(c[1], topY / 2, c[2]), WOOD_DARK)
		end
		m.PrimaryPart = top
		return m
	end

	DECOR_BUILDERS.Telephone = function()
		local m = Instance.new("Model"); m.Name = "Telephone"
		local base = dpart(m, Vector3.new(1.2, 0.45, 1), CFrame.new(0, 0.22, 0), BLACK)
		dpart(m, Vector3.new(1.3, 0.28, 0.32), CFrame.new(0, 0.62, -0.15), BLACK)              -- handset
		dpart(m, Vector3.new(0.5, 0.1, 0.5), CFrame.new(0.15, 0.47, 0.2), Color3.fromRGB(60, 60, 64)) -- dial
		m.PrimaryPart = base
		return m
	end

	DECOR_BUILDERS.CardboardBox = function()
		local m = Instance.new("Model"); m.Name = "CardboardBox"
		local s = 2.4
		local bh = s * 0.85                 -- body a touch shorter so the flaps read
		local mat = Enum.Material.SmoothPlastic -- matte cardboard, not wood grain
		local body = dpart(m, Vector3.new(s, bh, s), CFrame.new(0, bh / 2, 0), CARD, mat)
		-- four lid flaps hinged at the top rim, opened outward ~48°
		local flap, ang = s * 0.55, math.rad(48)
		local dz, dy = flap * 0.33, flap * 0.37 -- outward / upward offset of the flap centre
		dpart(m, Vector3.new(s, 0.08, flap), CFrame.new(0, bh + dy, -s / 2 - dz) * CFrame.Angles(ang, 0, 0), CARD_DARK, mat)
		dpart(m, Vector3.new(s, 0.08, flap), CFrame.new(0, bh + dy,  s / 2 + dz) * CFrame.Angles(-ang, 0, 0), CARD_DARK, mat)
		dpart(m, Vector3.new(flap, 0.08, s), CFrame.new(-s / 2 - dz, bh + dy, 0) * CFrame.Angles(0, 0, -ang), CARD_DARK, mat)
		dpart(m, Vector3.new(flap, 0.08, s), CFrame.new( s / 2 + dz, bh + dy, 0) * CFrame.Angles(0, 0, ang), CARD_DARK, mat)
		-- a FULL box of files: many thin sheets packed in a neat row, standing up
		-- out of the box (packed along Z, so you read a stack of many page edges)
		local inner = s - 0.45
		local sheets = 11
		local paperCols = {
			Color3.fromRGB(236, 232, 220), Color3.fromRGB(224, 214, 190),
			Color3.fromRGB(212, 206, 192), Color3.fromRGB(230, 226, 214),
		}
		for i = 1, sheets do
			local fz = -inner / 2 + (i - 0.5) * (inner / sheets)
			local fhh = 0.8 + math.random() * 0.4 -- slight per-sheet height variation
			dpart(m, Vector3.new(inner * 0.85, fhh, 0.05),
				CFrame.new(0, bh + fhh / 2 - 0.15, fz),
				paperCols[(i % #paperCols) + 1], mat)
		end
		m.PrimaryPart = body
		return m
	end

	DECOR_BUILDERS.Printer = function()
		local m = Instance.new("Model"); m.Name = "Printer"
		local body = dpart(m, Vector3.new(3, 2, 2.4), CFrame.new(0, 1, 0), PLASTIC)
		dpart(m, Vector3.new(2.6, 0.3, 1.4), CFrame.new(0, 2.05, -0.1), Color3.fromRGB(90, 90, 96))   -- tray
		dpart(m, Vector3.new(2, 0.05, 1.2), CFrame.new(0, 2.25, -0.6), Color3.fromRGB(245, 245, 240)) -- paper
		dpart(m, Vector3.new(0.8, 0.5, 0.05), CFrame.new(0.9, 1.4, -1.22), Color3.fromRGB(40, 44, 52), Enum.Material.Neon) -- panel (front)
		m.PrimaryPart = body
		return m
	end

	DECOR_BUILDERS.GrandfatherClock = function()
		local m = Instance.new("Model"); m.Name = "GrandfatherClock"
		local cab = dpart(m, Vector3.new(2, 9, 1.2), CFrame.new(0, 4.5, 0), WOOD)      -- cabinet
		dpart(m, Vector3.new(1.5, 3, 0.1), CFrame.new(0, 4, -0.62), BLACK)             -- pendulum window
		dpart(m, Vector3.new(1.5, 1.5, 0.15), CFrame.new(0, 7.6, -0.62), CREAM)        -- clock face (front -Z)
		-- two hands pivoted at the face centre, each spun to a RANDOM angle so
		-- every clock reads a different time
		local function hand(len, w)
			local h = dpart(m, Vector3.new(w, len, 0.06), CFrame.new(0, 7.6, -0.72), BLACK)
			h.CFrame = CFrame.new(0, 7.6, -0.72) * CFrame.Angles(0, 0, math.random() * math.pi * 2) * CFrame.new(0, len / 2, 0)
			return h
		end
		hand(0.55, 0.12) -- hour
		hand(0.85, 0.08) -- minute
		m.PrimaryPart = cab
		return m
	end

	local function scaleToHeight(model, target)
		local _, size = model:GetBoundingBox()
		if size.Y > 0.01 then pcall(function() model:ScaleTo(target / size.Y) end) end
	end

	local function prep(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = DECOR_COLLIDE
				d.CollisionGroup = "Decor" -- entity passes through → never stuck
				d.CanQuery = false -- invisible to raycasts: furniture must NOT block
				                   -- the entity's line-of-sight (it was stopping the
				                   -- entity from spotting players through/past props)
			end
		end
	end

	-- drop a model so its bounding-box bottom rests on the floor (y = 0), with an
	-- optional inward-facing look direction (else random yaw) plus an extra yaw so
	-- you can correct a model whose "front" isn't -Z. Rotation-safe.
	local function placeOnFloor(model, px, pz, lookDir, extraYaw)
		local baseCF
		if lookDir then
			baseCF = CFrame.lookAt(Vector3.new(px, 100, pz), Vector3.new(px, 100, pz) + lookDir)
				* CFrame.Angles(0, extraYaw or 0, 0)
		else
			baseCF = CFrame.new(px, 100, pz) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
		end
		model:PivotTo(baseCF)
		local cf, size = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + Vector3.new(0, 0 - (cf.Y - size.Y / 2), 0))
	end

	-- build → scale (with a random size wobble) → prep → place; returns the model
	local function spawnProp(name, height, px, pz, lookDir)
		local build = DECOR_BUILDERS[name]
		if not build then return nil end
		local model = build()
		local h = height * (1 + (math.random() * 2 - 1) * DECOR_SCALE_JITTER)
		scaleToHeight(model, h)
		prep(model)
		placeOnFloor(model, px, pz, lookDir)
		model.Parent = decorFolder
		return model
	end

	-- centre a phone on top of a placed table
	local function addPhone(tableModel)
		local cf, size = tableModel:GetBoundingBox()
		local phone = DECOR_BUILDERS.Telephone()
		scaleToHeight(phone, 0.9); prep(phone)
		phone:PivotTo(CFrame.new(cf.X, 200, cf.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		local pcf, psize = phone:GetBoundingBox()
		phone:PivotTo(phone:GetPivot() + Vector3.new(
			cf.X - pcf.X, (cf.Y + size.Y / 2) - (pcf.Y - psize.Y / 2), cf.Z - pcf.Z))
		phone.Parent = decorFolder
	end

	-- which sides of a cell have a wall (border counts as a wall)
	local function presentWalls(x, z)
		return {
			east  = (x == GRID) or wallV[x][z],
			west  = (x == 1) or wallV[x - 1][z],
			north = (z == GRID) or wallH[x][z],
			south = (z == 1) or wallH[x][z - 1],
		}
	end

	-- same-type spacing: a prop can't spawn within DECOR_MIN_GAP cells of another
	-- of the SAME kind (so no two chairs / two printers cluster up)
	local placedCells = {}
	local function propHeight(name)
		for _, p in ipairs(PROPS) do if p.name == name then return p.height end end
		return 3
	end
	local function tooClose(name, x, z)
		local list = placedCells[name]
		if not list then return false end
		for _, c in ipairs(list) do
			if math.max(math.abs(c[1] - x), math.abs(c[2] - z)) <= DECOR_MIN_GAP then return true end
		end
		return false
	end
	local function record(name, x, z)
		placedCells[name] = placedCells[name] or {}
		table.insert(placedCells[name], { x, z })
	end

	-- GUARANTEED: a lone chair in the middle of the plaza
	spawnProp("Chair", propHeight("Chair"), O + (fx - 0.5) * CELL, O + (fz - 0.5) * CELL, nil)
	record("Chair", fx, fz)

	for x = 1, GRID do
		for z = 1, GRID do
			local k = key(x, z)
			if pitCellSet[k] then continue end
			-- keep clear of the elevator room and its cell
			if math.max(math.abs(x - ELEV_X), math.abs(z - ELEV_Y)) <= ELEV_CLEAR then continue end
			if math.random() > DECOR_DENSITY then continue end

			local walls = presentWalls(x, z)
			local wcount = 0
			for _, v in pairs(walls) do if v then wcount += 1 end end
			local fcx, fcz = O + (x - 0.5) * CELL, O + (z - 0.5) * CELL

			-- room props want an OPEN cell (≤1 wall); wall props want a wall — and
			-- must not sit within DECOR_MIN_GAP cells of the same prop type
			local candidates = {}
			for _, prop in ipairs(PROPS) do
				local fits = (prop.place == "room" and wcount <= 1)
					or (prop.place == "wall" and wcount >= 1)
				if fits and not tooClose(prop.name, x, z) then
					for _ = 1, prop.weight do table.insert(candidates, prop) end
				end
			end
			if #candidates == 0 then continue end

			local prop = candidates[math.random(#candidates)]
			record(prop.name, x, z)
			local model
			if prop.place == "wall" then
				-- sit against a present wall, front (-Z) facing into the room, but
				-- JITTERED along the wall so it isn't dead-centre on the panel
				local opts = {}
				if walls.east  then table.insert(opts, { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) }) end
				if walls.west  then table.insert(opts, { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0) }) end
				if walls.north then table.insert(opts, { Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) end
				if walls.south then table.insert(opts, { Vector3.new(0, 0, -1), Vector3.new(0, 0, 1) }) end
				local o = opts[math.random(#opts)]
				local wallDir, inward = o[1], o[2]
				local along = Vector3.new(-wallDir.Z, 0, wallDir.X) -- runs ALONG the wall
				local j = (math.random() * 2 - 1) * (CELL * 0.28)
				local px = fcx + wallDir.X * (CELL / 2 - 1.5) + along.X * j
				local pz = fcz + wallDir.Z * (CELL / 2 - 1.5) + along.Z * j
				model = spawnProp(prop.name, prop.height, px, pz, inward)
			else
				-- room prop: offset randomly within the cell so it isn't always
				-- dead-centre (chairs strewn about, not on a grid)
				local jx = (math.random() * 2 - 1) * (CELL * 0.25)
				local jz = (math.random() * 2 - 1) * (CELL * 0.25)
				model = spawnProp(prop.name, prop.height, fcx + jx, fcz + jz, nil)
			end

			if model and prop.phone then addPhone(model) end
		end
	end
end)

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

marker("MazeStart", CFrame.new(O + (ELEV_X - 0.5) * CELL, 3, O + (ELEV_Y - 0.5) * CELL))
marker("EntityStart", entityStartCF)

-- park the entity in its corner until GameManager takes over
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 15)
	if entity and entity.PrimaryPart then
		local bbox, size = entity:GetBoundingBox()
		local pivot = entity:GetPivot()
		entity:PivotTo(CFrame.new(entityStartCF.X, 0.5 + (pivot.Y - (bbox.Y - size.Y / 2)), entityStartCF.Z))
	end
end)

-- ── mood lighting: horror pass ────────────────────────────
Lighting.Ambient = Color3.fromRGB(4, 4, 3)      -- near-total darkness between lights
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.Brightness = 0.3
Lighting.ClockTime = 0
Lighting.GlobalShadows = true
-- an Atmosphere object OVERRIDES legacy Fog and lets you see forever — remove
-- it so the fog below actually limits how far players can see
local _atmos = Lighting:FindFirstChildOfClass("Atmosphere")
if _atmos then _atmos:Destroy() end
Lighting.FogColor = Color3.fromRGB(16, 14, 9)   -- dark, close fog — dread, not haze
Lighting.FogStart = 14
Lighting.FogEnd = 150                           -- see a bit further (~6 cells) — less oppressive than before

-- color grade: desaturated, contrast-crushed, sickly warm tint
local grade = Lighting:FindFirstChild("MongoGrade") or Instance.new("ColorCorrectionEffect")
grade.Name = "MongoGrade"
grade.Saturation = -0.3
grade.Contrast = 0.12
grade.Brightness = -0.02
grade.TintColor = Color3.fromRGB(255, 243, 220)
grade.Parent = Lighting

-- ── light control: NORMAL flicker · ALERT red pulse · BLACKOUT ──
local function lightMode() return workspace:GetAttribute("LightMode") or "NORMAL" end
local function flickerBoost() return workspace:GetAttribute("FlickerBoost") or 0 end

local function setLight(f, on)
	f[2].Enabled = on
	f[1].Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
end

local function restoreLight(L)
	L.light.Enabled = true
	L.light.Color = LIGHT_COLOR
	L.light.Brightness = 0.7
	L.panel.Color = Color3.fromRGB(255, 250, 230)
	L.panel.Material = Enum.Material.Neon
end

-- per-light buzz-flicker — NORMAL mode only; FlickerBoost shortens the calm gap
for _, f in ipairs(flicker) do
	task.spawn(function()
		while true do
			task.wait((1 + math.random() * 4) / (1 + flickerBoost()))
			if lightMode() == "NORMAL" then
				for _ = 1, math.random(4, 10) do
					setLight(f, false)
					task.wait(0.03 + math.random() * 0.06)
					setLight(f, true)
					task.wait(0.03 + math.random() * 0.06)
				end
				if math.random() < 0.3 then
					setLight(f, false)
					task.wait(0.2 + math.random() * 0.5)
					setLight(f, true)
				end
			end
		end
	end)
end

-- mode controller: ALERT pulses all lights red (continuous); NORMAL & BLACKOUT
-- are applied once on transition so the flicker/presence loops can own lights
task.spawn(function()
	local prev = "NORMAL"
	local phase = 0
	while true do
		local dt = task.wait(0.08)
		local mode = lightMode()
		if mode == "ALERT" then
			phase += dt
			local b = 0.12 + 0.55 * (0.5 + 0.5 * math.sin(phase * 1.6))
			for _, L in ipairs(allLights) do
				L.light.Enabled = true
				L.light.Color = Color3.fromRGB(255, 45, 30)
				L.light.Brightness = b
				L.panel.Color = Color3.fromRGB(120, 12, 10)
				L.panel.Material = Enum.Material.Neon
			end
		elseif mode == "BLACKOUT" then
			if prev ~= "BLACKOUT" then
				-- mostly dark, but ~12% of panels stay faintly lit so it's not
				-- pitch black — the entity beacon does the rest
				for _, L in ipairs(allLights) do
					L.keep = math.random() < 0.12
					if L.keep then
						L.light.Enabled = true
						L.light.Color = LIGHT_COLOR
						L.light.Brightness = 0.28
						L.panel.Color = Color3.fromRGB(120, 116, 96)
						L.panel.Material = Enum.Material.Neon
					else
						L.light.Enabled = false
						L.panel.Color = Color3.fromRGB(18, 18, 18)
						L.panel.Material = Enum.Material.SmoothPlastic
					end
				end
			end
		else
			if prev ~= "NORMAL" then
				for _, L in ipairs(allLights) do restoreLight(L) end
			end
		end
		prev = mode
	end
end)

-- ── entity presence ──────────────────────────────────────
-- NORMAL → the 1–2 nearest lights in front of the entity are likelier to
-- flicker · BLACKOUT → the entity is the ONLY light: the nearest panel blinks,
-- a beacon showing roughly where it is in the dark
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 30)
	if not entity then return end
	local busy = {}
	while true do
		task.wait(0.4)
		local mode = lightMode()
		if mode ~= "ALERT" then
			local root = entity:FindFirstChild("HumanoidRootPart")
			if root then
				if mode == "BLACKOUT" then
					local best, bd = nil, math.huge
					for _, L in ipairs(allLights) do
						local d = (L.pos - root.Position).Magnitude
						if d < bd then best, bd = L, d end
					end
					if best then
						best.light.Color = LIGHT_COLOR
						best.light.Brightness = 0.7
						best.light.Enabled = true
						best.panel.Material = Enum.Material.Neon
						task.wait(0.08 + math.random() * 0.12)
						-- return it to whatever its blackout state was
						if best.keep then
							best.light.Brightness = 0.28
						else
							best.light.Enabled = false
							best.panel.Material = Enum.Material.SmoothPlastic
						end
					end
				else
					local ahead = root.Position + root.CFrame.LookVector * 18
					local best, bd, best2, bd2 = nil, math.huge, nil, math.huge
					for _, L in ipairs(allLights) do
						local d = (L.pos - ahead).Magnitude
						if d < bd then best2, bd2 = best, bd; best, bd = L, d
						elseif d < bd2 then best2, bd2 = L, d end
					end
					for _, L in ipairs({ best, best2 }) do
						if L and (L.pos - ahead).Magnitude < 45 and not busy[L] and math.random() < 0.5 then
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
		end
	end
end)
