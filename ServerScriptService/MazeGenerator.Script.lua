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
local PhysicsService = game:GetService("PhysicsService")

-- The lobby owns server startup. Build the expensive world only when a queued
-- party finishes the launch countdown.
workspace:SetAttribute("WorldGenerated", false)
while workspace:GetAttribute("GenerateWorld") ~= true do
	workspace:GetAttributeChangedSignal("GenerateWorld"):Wait()
end
workspace:SetAttribute("LoadStage", "GENERATING_WORLD")

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
local Master = require(game:GetService("ReplicatedStorage"):WaitForChild("MasterConfiguration"))
local GRID       = Master.Effective("L1_Grid", 40)      -- maze is GRID x GRID cells
local CELL       = Master.Effective("L1_Cell", 24)      -- studs per cell (corridor width)
local WALL_H     = 14      -- wall/ceiling height
local WALL_T     = 2       -- wall thickness
local SEED       = nil     -- set a number (e.g. 1337) for the same maze every run

-- density variation — tuned corridor-first: tight maze by default, with
-- occasional distinct open rooms instead of everything blending open
local OPENNESS    = Master.Effective("L1_Openness", 0.32)   -- base wall-removal chance
local NOISE_SCALE = 6      -- cells per density blob (smaller = smaller open pockets)
local PLAZA_T     = 0.8    -- density above this = fully open plaza (rarer now)
local PLAZA_R     = 3      -- radius (cells) of the one GUARANTEED plaza

-- pitfall ZONES: big multi-cell hole fields. Each zone is one open room
-- (internal walls removed) filled with a continuous grid of square holes
-- separated by narrow walkable beams, all over one shared deep shaft.
local PIT_ZONES      = Master.Effective("L1_PitZones", 2)     -- hole fields per level
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

-- Level 1 elevator material set. The cabin/frame use a seamless brushed
-- aluminum tile, while the two sliding leaves use a dedicated ImageGen door
-- master with a centered join and pressed gunmetal panels.
local ELEV_ALUMINUM_TEXTURE = "rbxassetid://100495024153306"
local ELEV_WALL_TEXTURE = ELEV_ALUMINUM_TEXTURE
local ELEV_CEILING_TEXTURE = ELEV_ALUMINUM_TEXTURE
local ELEV_FLOOR_TEXTURE = ""
local ELEV_DOOR_TEXTURE = "rbxassetid://140048817197891"
local ELEV_FLOOR_TILE = 4
local ELEV_CEILING_TILE = 4
-- Level 1 Elevator Roof Texture: paste the uploaded decal id here to give the
-- cabin's interior ceiling its OWN texture (generate it with the ChatGPT
-- prompt from the update notes). While empty the roof falls back to the
-- brushed aluminum set above.
local ELEV_ROOF_TEXTURE = "rbxassetid://114582006074351"

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

-- Optional ARTWORK / wall writings / clues (your own decals) — any number of
-- variants; one is picked at random per stamped wall.
-- Each is stamped once, CENTERED on a wall (middle height, middle of the panel).
local ARTWORK = {
	"rbxassetid://80911770861771",  -- doodle: all-seeing eye
	"rbxassetid://117323524052782", -- doodle: maze arrow
	"rbxassetid://78127647978376",  -- doodle: spiral / tally warning
	"rbxassetid://128890112577999", -- entity face, screaming
	"rbxassetid://82718311099501",  -- entity full-body silhouette
	"rbxassetid://138148144809292", -- "DON'T LOOK when it SMILES"
	"rbxassetid://102848754825740", -- "THE LIGHTS lie"
	"rbxassetid://77821668210469",  -- "I HEARD myself breathing BEHIND THE WALL"
	"rbxassetid://98978598431949",  -- "NO EXIT only ROOMS"
	"rbxassetid://119570088683353", -- "if you hear KNOCKING DON'T ANSWER"
	"rbxassetid://132611092263750",  -- "DON'T LOOK UP"
	"rbxassetid://88834089507828",  -- "NO WAY OUT" (maze)
	"rbxassetid://76001685943173",  -- "HE STANDS IN THE CORNER"
	"rbxassetid://76020687707580",  -- "COUNT THE STEPS"
	"rbxassetid://112810513236221",  -- "IT HEARS WHEN YOU RUN"
	"rbxassetid://82045544909376",  -- "ROOM 14 IS FAKE"
	"rbxassetid://140429206489058",  -- "STAY OUT OF THE YELLOW"
	"rbxassetid://136976855633731",  -- "THE LIGHTS LIE" v2
	"rbxassetid://130188345411949",  -- "MOTHER IS IN THE CEILING"
	"rbxassetid://132247947032204",  -- "IF YOU SEE YOURSELF, HIDE"
	"rbxassetid://112921561219170",  -- "DON'T LOOK AT IT"
	"rbxassetid://110903215359276",  -- "IT'S IN THE CORNER"
	"rbxassetid://127509649473066",  -- "THE LIGHTS LIE" v3
	"rbxassetid://124830876758780",  -- "COUNT THE DAYS"
	"rbxassetid://70389270393569",  -- "EXIT BELOW"
	"rbxassetid://125582860058991",  -- "FACES IN THE WALLS"
	"rbxassetid://104295121313443",  -- "HE SEES YOU"
	"rbxassetid://92581195512731",  -- "THE VOICES ARE CALLING"
	"rbxassetid://135612703504186",  -- "TOO DEEP"
	"rbxassetid://75903303920930",  -- "NOT EVERY DOOR LEADS OUT"
	"rbxassetid://128021237955527",  -- "THE CARPET MOVES"
	"rbxassetid://93879143176717",  -- "SMILE BACK"
	"rbxassetid://93025786065772",  -- "THE HUM BECOMES WORDS"
	"rbxassetid://116440766582359",  -- "DO NOT TRUST THE ARROWS"
	"rbxassetid://121896424444172",  -- "SOME ROOMS BREATHE"
	"rbxassetid://89343444746132",  -- "WHEN IT STOPS BUZZING, RUN"
	"rbxassetid://81544261461921",  -- "COUNT THE CEILINGS"
	"rbxassetid://79163278775101",  -- "YOUR SHADOW IS EARLY"
	"rbxassetid://135373774995178",  -- "THE HALLWAY BENDS WHEN YOU BLINK"	
	}
local ARTWORK_CHANCE = 0.15 -- per maze wall
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
local DECOR_DENSITY = 0.22     -- chance PER eligible cell that it tries a prop
local DECOR_COLLIDE = true     -- props are solid for players; the entity walks through
local DECOR_SCALE_JITTER = 0.2 -- ±fraction random size wobble per prop (weird-gen look)
local DECOR_MIN_GAP = 2        -- same-type props must be MORE than this many cells apart
local PROP_WALNUT_TEXTURE = "rbxassetid://109803400965301"
-- place = "room" (alone in the middle of an open cell) or "wall" (against a wall)
-- weight = relative pick chance · height = studs tall (per-object size knob)
local PROPS = {
	{ name = "Chair",            height = 3.5, place = "room", weight = 3 },
	{ name = "Table",            height = 3.2, place = "room", weight = 2, phone = true }, -- carries a phone
	{ name = "CardboardPile",    height = 4.8, place = "wall", weight = 2,
		minGap = 2, wallInset = 4.5 },
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

-- (Texture ids are used as-is: ContentId properties resolve uploaded
-- image/decal ids themselves, so the old InsertService resolver pass is gone —
-- paste any uploaded decal id into the constants above and it just works.)

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

local function applyTexture(p, id, faces, tile, tint, tileV)
	if id == "" then return end
	for _, face in ipairs(faces) do
		local t = Instance.new("Texture")
		t.Texture = id
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tileV or tile
		if tint then t.Color3 = tint end -- darkens the texture image itself
		t.Parent = p
	end
end

local function applyDoorLeafImage(p, face, useRightHalf)
	if ELEV_DOOR_TEXTURE == "" then return end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ElevatorDoorSurface"
	gui.Face = face
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0.32
	gui.Brightness = 0.82
	-- A leaf is 4 x 10 studs. Clip the full 8 x 10 master at its normalized
	-- midpoint instead of relying on upload pixel dimensions; Roblox may resize
	-- an image internally, which made the old ImageRect midpoint drift.
	gui.CanvasSize = Vector2.new(400, 1000)
	gui.Parent = p

	local clip = Instance.new("Frame")
	clip.Name = "DoorLeafClip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Parent = gui

	local image = Instance.new("ImageLabel")
	image.Name = "DoorLeafImage"
	image.Size = UDim2.fromScale(2, 1)
	image.Position = UDim2.fromScale(useRightHalf and -1 or 0, 0)
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = ELEV_DOOR_TEXTURE
	image.ScaleType = Enum.ScaleType.Stretch
	image.Parent = clip
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
workspace:SetAttribute("LightMode", "NORMAL")   -- NORMAL · ALERT · POWERDOWN · BLACKOUT · ESCAPE (dark exit phase)
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

	local STEEL      = Color3.fromRGB(184, 187, 190) -- cool commercial elevator aluminum
	local STEEL_DARK = Color3.fromRGB(70, 75, 80)
	local CABIN_FLOOR = Color3.fromRGB(42, 46, 50)
	local CAB_W = 8 -- interior width — LONG and narrow, not wide

	-- outer shell: same textured yellow walls as the rest of the maze
	wallPart(Vector3.new(CELL, WALL_H, 2), CFrame.new(cx, WALL_H / 2, z0 + 1), elev)   -- south
	wallPart(Vector3.new(CELL, WALL_H, 2), CFrame.new(cx, WALL_H / 2, z1 - 1), elev)   -- north
	wallPart(Vector3.new(2, WALL_H, CELL), CFrame.new(x0 + 1, WALL_H / 2, cz), elev)   -- west (back)
	-- east face: a BLACK elevator frame around the doors (header + side fillers)
	-- instead of yellow wall — so from the maze it reads as a proper elevator
	-- entrance ("there's supposed to be an elevator here"). 8-stud opening.
	local FRAME = Color3.fromRGB(14, 14, 17)
	local frameTop = part(Vector3.new(2, WALL_H - 10, CELL), CFrame.new(x1 - 1, (WALL_H + 10) / 2, cz), FRAME, Enum.Material.Metal, elev)
	local frameSideA = part(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z0 + 4), FRAME, Enum.Material.Metal, elev)
	local frameSideB = part(Vector3.new(2, 10, 8), CFrame.new(x1 - 1, 5, z1 - 4), FRAME, Enum.Material.Metal, elev)
	-- The dark entrance used to stay plain black after the doors opened. Use the
	-- same brushed-steel texture on both the maze-facing and cabin-facing sides,
	-- so every visible part of the doorway reads as one material.
	for _, framePart in ipairs({ frameTop, frameSideA, frameSideB }) do
		applyTexture(framePart, ELEV_WALL_TEXTURE,
			{ Enum.NormalId.Left, Enum.NormalId.Right }, 4,
			Color3.fromRGB(118, 123, 128), 4)
	end

	-- sliding stainless doors (named for GameManager; they slide ±4 now). Thicker
	-- than the 2-stud wall cavity (2.2) so no yellow shell can peek at the edges;
	-- being wider than the fillers, an open door hides them inside it (no z-fight).
	local doorL = part(Vector3.new(0.45, 10, 4), CFrame.new(x1 - 1, 5, cz - 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorL.Name = "DoorL"
	local doorR = part(Vector3.new(0.45, 10, 4), CFrame.new(x1 - 1, 5, cz + 2),
		STEEL_DARK, Enum.Material.Metal, elev)
	doorR.Name = "DoorR"
	-- Each moving leaf shows its matching half of the single 4:5 master.
	-- Swap halves on the opposite face so the complete door reads correctly
	-- from both the cabin and the maze.
	applyDoorLeafImage(doorL, Enum.NormalId.Left, false)
	applyDoorLeafImage(doorL, Enum.NormalId.Right, true)
	applyDoorLeafImage(doorR, Enum.NormalId.Left, true)
	applyDoorLeafImage(doorR, Enum.NormalId.Right, false)

	-- threshold GAP: a dark, near-flush band across the doorway — the shadow gap
	-- between a building floor and the elevator car. Cosmetic (the carpet tile
	-- under it carries the player), and it hides the door bottoms at the seam.
	local sill = part(Vector3.new(2.6, 0.3, 8), CFrame.new(x1 - 1, 0.0, cz),
		Color3.fromRGB(8, 8, 10), Enum.Material.Metal, elev)
	sill.CanCollide = false
	sill.CanQuery = false
	applyTexture(sill, ELEV_WALL_TEXTURE,
		{ Enum.NormalId.Top, Enum.NormalId.Left, Enum.NormalId.Right }, 4,
		Color3.fromRGB(105, 110, 115), 4)

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

	local function refreshCableGuidePoster()
		if not cabin then return end
		local poster = cabin:FindFirstChild("CableGuidePoster")
		if not poster then return end
		local pg = poster:FindFirstChild("CableGuideSurface")
		local paper = pg and pg:FindFirstChild("CableGuidePaper")
		if not paper then return end

		local count = math.clamp(
			math.floor((tonumber(workspace:GetAttribute("Level1ActiveCircuitCount")) or 0) + 0.5),
			0,
			6
		)
		poster:SetAttribute("ActiveCircuitCount", count)
		poster:SetAttribute("CableGuideVersion", 2)

		for index = 1, 6 do
			local row = paper:FindFirstChild(("CircuitRow%02d"):format(index))
			if row then row.Visible = index <= count end
		end

		local summary = paper:FindFirstChild("CrewCircuitSummary")
		if summary then
			if count == 0 then
				summary.Text = "CIRCUIT ALLOCATION PENDING // CREW ASSIGNMENT IN PROGRESS"
			elseif count == 1 then
				summary.Text = "1 ACTIVE CABLE // RED ONLY // FUSE BOX + LEVER AT OPPOSITE ENDS"
			else
				summary.Text = ("%d ACTIVE CABLES // EACH COLOUR LINKS ONE FUSE BOX + ONE LEVER"):format(count)
			end
		end

		local clusterNote = paper:FindFirstChild("RelayHint")
		if clusterNote then
			clusterNote.Position = UDim2.new(0, 18, 0, 98 + count * 36)
		end

		local footer = paper:FindFirstChild("CircuitFocusHint")
		if footer then
			if count == 0 then
				footer.Text = "ACTIVE COLOURS APPEAR WHEN THE ROUND STARTS"
			elseif count == 1 then
				footer.Text = "FOCUS ONLY ON RED // CHECK BOTH ENDS"
			else
				footer.Text = ("FOCUS ONLY ON THE %d COLOURS SHOWN // CHECK BOTH ENDS"):format(count)
			end
		end
	end

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
		local roof = part(Vector3.new(depth + 1, 1, CAB_W + 2), CFrame.new(bx - 0.25, 10.5, cz), STEEL_DARK, Enum.Material.Metal, cabin)
		roof.Name = "CabinRoof"
		local floorP = part(Vector3.new(depth, 0.2, CAB_W), CFrame.new(bx, 0.1, cz), CABIN_FLOOR, Enum.Material.DiamondPlate, cabin)

		-- The generated aluminum is a square seamless tile. Keep it at the same
		-- four-stud scale on every elevator surface so its grain never stretches
		-- when the cabin changes depth for larger crews.
		applyTexture(back, ELEV_WALL_TEXTURE, { Enum.NormalId.Right }, 4, nil, 4)
		applyTexture(sideA, ELEV_WALL_TEXTURE, { Enum.NormalId.Back }, 4, nil, 4)
		applyTexture(sideB, ELEV_WALL_TEXTURE, { Enum.NormalId.Front }, 4, nil, 4)
		if ELEV_ROOF_TEXTURE ~= "" then
			-- the dedicated roof texture ships untinted — what you generate is
			-- exactly what the cabin ceiling shows
			applyTexture(roof, ELEV_ROOF_TEXTURE, { Enum.NormalId.Bottom },
				ELEV_CEILING_TILE, nil, ELEV_CEILING_TILE)
		else
			applyTexture(roof, ELEV_CEILING_TEXTURE, { Enum.NormalId.Bottom },
				ELEV_CEILING_TILE, Color3.fromRGB(205, 208, 211), ELEV_CEILING_TILE)
		end
		applyTexture(floorP, ELEV_FLOOR_TEXTURE, { Enum.NormalId.Top }, ELEV_FLOOR_TILE)

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

		-- Worn maintenance-routing poster. It owns six stable row containers, but
		-- displays only the circuits that PuzzleManager actually generated for this
		-- round's crew. Spectators and late joins therefore never add false colours.
		do
			local poster = part(
				Vector3.new(0.12, 6.5, 7.2),
				CFrame.new(xBack + 0.08, 5.1, cz),
				Color3.fromRGB(58, 54, 42),
				Enum.Material.Metal,
				cabin
			)
			poster.Name = "CableGuidePoster"
			poster.CanCollide = false
			poster.CanQuery = false

			local pg = Instance.new("SurfaceGui")
			pg.Name = "CableGuideSurface"
			pg.Face = Enum.NormalId.Right
			pg.CanvasSize = Vector2.new(420, 400)
			pg.LightInfluence = 0.25
			pg.Brightness = 1.0
			pg.Parent = poster

			local paper = Instance.new("Frame")
			paper.Name = "CableGuidePaper"
			paper.Size = UDim2.fromScale(1, 1)
			paper.BackgroundColor3 = Color3.fromRGB(72, 68, 52)
			paper.BorderSizePixel = 0
			paper.Parent = pg
			local outline = Instance.new("UIStroke")
			outline.Color = Color3.fromRGB(150, 140, 96)
			outline.Thickness = 4
			outline.Transparency = 0.35
			outline.Parent = paper

			local title = Instance.new("TextLabel")
			title.Name = "Title"
			title.Size = UDim2.new(1, -26, 0, 36)
			title.Position = UDim2.new(0, 13, 0, 10)
			title.BackgroundTransparency = 1
			title.Font = Enum.Font.Code
			title.Text = "MAINTENANCE CABLE ROUTING"
			title.TextColor3 = Color3.fromRGB(210, 202, 155)
			title.TextSize = 23
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.Parent = paper

			local sub = Instance.new("TextLabel")
			sub.Name = "CrewCircuitSummary"
			sub.Size = UDim2.new(1, -26, 0, 40)
			sub.Position = UDim2.new(0, 13, 0, 48)
			sub.BackgroundTransparency = 1
			sub.Font = Enum.Font.Code
			sub.Text = "CIRCUIT ALLOCATION PENDING // CREW ASSIGNMENT IN PROGRESS"
			sub.TextColor3 = Color3.fromRGB(180, 178, 155)
			sub.TextSize = 14
			sub.TextWrapped = true
			sub.TextYAlignment = Enum.TextYAlignment.Top
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.Parent = paper

			local function posterRow(index, color, label)
				local row = Instance.new("Frame")
				row.Name = ("CircuitRow%02d"):format(index)
				row.Position = UDim2.new(0, 0, 0, 96 + (index - 1) * 36)
				row.Size = UDim2.new(1, 0, 0, 34)
				row.BackgroundTransparency = 1
				row.Visible = false
				row:SetAttribute("CircuitIndex", index)
				row.Parent = paper

				local wire = Instance.new("Frame")
				wire.Name = "Cable"
				wire.Position = UDim2.new(0, 18, 0, 13)
				wire.Size = UDim2.new(0, 105, 0, 8)
				wire.BackgroundColor3 = color
				wire.BorderSizePixel = 0
				wire.Parent = row
				local dot = Instance.new("Frame")
				dot.Name = "Terminal"
				dot.AnchorPoint = Vector2.new(0.5, 0.5)
				dot.Position = UDim2.new(0, 122, 0, 17)
				dot.Size = UDim2.new(0, 18, 0, 18)
				dot.BackgroundColor3 = color
				dot.BorderSizePixel = 0
				dot.Parent = row
				local dc = Instance.new("UICorner")
				dc.CornerRadius = UDim.new(1, 0)
				dc.Parent = dot

				local txt = Instance.new("TextLabel")
				txt.Name = "CircuitName"
				txt.Position = UDim2.new(0, 145, 0, 0)
				txt.Size = UDim2.new(1, -160, 0, 34)
				txt.BackgroundTransparency = 1
				txt.Font = Enum.Font.Code
				txt.Text = label
				txt.TextColor3 = color
				txt.TextSize = 19
				txt.TextXAlignment = Enum.TextXAlignment.Left
				txt.Parent = row
			end

			posterRow(1, Color3.fromRGB(255, 55, 55),  "01  RED CIRCUIT")
			posterRow(2, Color3.fromRGB(55, 135, 255), "02  BLUE CIRCUIT")
			posterRow(3, Color3.fromRGB(95, 255, 95),  "03  GREEN CIRCUIT")
			posterRow(4, Color3.fromRGB(255, 220, 45), "04  YELLOW CIRCUIT")
			posterRow(5, Color3.fromRGB(245, 70, 255), "05  MAGENTA CIRCUIT")
			posterRow(6, Color3.fromRGB(20, 235, 235), "06  CYAN CIRCUIT")

			local clusterNote = Instance.new("TextLabel")
			clusterNote.Name = "RelayHint"
			clusterNote.Position = UDim2.new(0, 18, 0, 98)
			clusterNote.Size = UDim2.new(1, -36, 0, 36)
			clusterNote.BackgroundTransparency = 1
			clusterNote.Font = Enum.Font.Code
			clusterNote.Text = "VERY BRIGHT CEILING CLUSTER = FUSE RELAY"
			clusterNote.TextColor3 = Color3.fromRGB(255, 232, 145)
			clusterNote.TextSize = 15
			clusterNote.TextWrapped = true
			clusterNote.TextXAlignment = Enum.TextXAlignment.Left
			clusterNote.Parent = paper

			local footer = Instance.new("TextLabel")
			footer.Name = "CircuitFocusHint"
			footer.Size = UDim2.new(1, -26, 0, 30)
			footer.Position = UDim2.new(0, 13, 1, -34)
			footer.BackgroundTransparency = 1
			footer.Font = Enum.Font.Code
			footer.Text = "ACTIVE COLOURS APPEAR WHEN THE ROUND STARTS"
			footer.TextColor3 = Color3.fromRGB(125, 122, 98)
			footer.TextSize = 15
			footer.TextXAlignment = Enum.TextXAlignment.Left
			footer.Parent = paper
		end

		pad.Size = Vector3.new(math.max(depth - 3, 4), 1, CAB_W - 2)
		pad.Position = Vector3.new(bx, 0.5, cz)

		cabin.Parent = elev
		refreshCableGuidePoster()
	end

	local function cabinDepth()
		-- 1 player → 10 studs deep · +2 per extra player · caps at 18
		return 8 + math.clamp(#Players:GetPlayers(), 1, 5) * 2
	end
	buildCabin(cabinDepth())
	workspace:GetAttributeChangedSignal("Level1ActiveCircuitCount"):Connect(refreshCableGuidePoster)
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
			-- Elevator surroundings guarantee: the fixture in front of the doors
			-- (east) is always working, steadily lit and humming, and the fixture
			-- one panel north is always working, humming AND flickering — so the
			-- crew always steps out to an audible live lamp and a buzzing one,
			-- whatever the random rolls said.
			local elevSteady = (x == ELEV_X + LIGHT_EVERY and z == ELEV_Y)
			local elevFlicker = (x == ELEV_X and z == ELEV_Y - LIGHT_EVERY)
			local isDead = not (elevSteady or elevFlicker) and math.random() < DEAD_CHANCE

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
				-- only about half the working fixtures actually buzz: the client's
				-- SoundController hums exclusively from panels carrying HumSource
				if elevSteady or elevFlicker or math.random() < 0.5 then
					panel:SetAttribute("HumSource", true)
				end
				if elevFlicker or (not elevSteady and math.random() < FLICKER_CHANCE) then
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
workspace:SetAttribute("DecorReady", false)
task.spawn(function()
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "Decor"
	decorFolder.Parent = workspace

	-- one anchored part inside a decor model
	local function dpart(model, size, cf, color, material, textureId, tileSize, textureFaces)
		local p = Instance.new("Part")
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		if textureId and textureId ~= "" then
			for _, face in ipairs(textureFaces or {
				Enum.NormalId.Top,
				Enum.NormalId.Front,
				Enum.NormalId.Back,
			}) do
				local texture = Instance.new("Texture")
				texture.Name = "PropSurface"
				texture.Texture = textureId
				texture.Face = face
				-- The uploaded albedo must stay neutral. Multiplying it by the already
				-- dark wood colour made props look almost immune to the flashlight.
				texture.Color3 = Color3.new(1, 1, 1)
				texture.StudsPerTileU = tileSize or 2.5
				texture.StudsPerTileV = tileSize or 2.5
				texture.Parent = p
			end
		end
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
		local seat = dpart(m, Vector3.new(2, 0.3, 2), CFrame.new(0, seatY, 0), WOOD, Enum.Material.Wood, PROP_WALNUT_TEXTURE, 2.5, { Enum.NormalId.Top })
		dpart(m, Vector3.new(2, 2, 0.25), CFrame.new(0, seatY + 1.1, -0.9), WOOD, Enum.Material.Wood) -- backrest
		for _, c in ipairs({ { 0.8, 0.8 }, { -0.8, 0.8 }, { 0.8, -0.8 }, { -0.8, -0.8 } }) do
			dpart(m, Vector3.new(0.22, seatY, 0.22), CFrame.new(c[1], seatY / 2, c[2]), WOOD_DARK, Enum.Material.Wood)
		end
		m.PrimaryPart = seat
		return m
	end

	DECOR_BUILDERS.Table = function()
		local m = Instance.new("Model"); m.Name = "Table"
		local topY = 2.7
		local top = dpart(m, Vector3.new(5, 0.3, 3), CFrame.new(0, topY, 0), WOOD, Enum.Material.Wood, PROP_WALNUT_TEXTURE, 3, { Enum.NormalId.Top })
		for _, c in ipairs({ { 2.2, 1.2 }, { -2.2, 1.2 }, { 2.2, -1.2 }, { -2.2, -1.2 } }) do
			dpart(m, Vector3.new(0.28, topY, 0.28), CFrame.new(c[1], topY / 2, c[2]), WOOD_DARK, Enum.Material.Wood)
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

	DECOR_BUILDERS.CardboardPile = function()
		local m = Instance.new("Model"); m.Name = "CardboardBoxPile"
		local mat = Enum.Material.Fabric
		local paperCols = {
			Color3.fromRGB(236, 232, 220), Color3.fromRGB(224, 214, 190),
			Color3.fromRGB(212, 206, 192), Color3.fromRGB(230, 226, 214),
		}
		local primary
		local function addOpenBox(base, yaw, scale)
			local s, bh = 2.4 * scale, 2.04 * scale
			local boxCF = CFrame.new(base) * CFrame.Angles(0, yaw, 0)
			local body = dpart(m, Vector3.new(s, bh, s),
				boxCF * CFrame.new(0, bh / 2, 0), CARD, mat)
			body.Name = "BoxBody"
			primary = primary or body
			local flap, ang = s * 0.48, math.rad(40)
			local dz, dy = flap * 0.28, flap * 0.32
			dpart(m, Vector3.new(s, 0.08, flap), boxCF * CFrame.new(0, bh + dy, -s / 2 - dz) * CFrame.Angles(ang, 0, 0), CARD_DARK, mat)
			dpart(m, Vector3.new(s, 0.08, flap), boxCF * CFrame.new(0, bh + dy, s / 2 + dz) * CFrame.Angles(-ang, 0, 0), CARD_DARK, mat)
			dpart(m, Vector3.new(flap, 0.08, s), boxCF * CFrame.new(-s / 2 - dz, bh + dy, 0) * CFrame.Angles(0, 0, -ang), CARD_DARK, mat)
			dpart(m, Vector3.new(flap, 0.08, s), boxCF * CFrame.new(s / 2 + dz, bh + dy, 0) * CFrame.Angles(0, 0, ang), CARD_DARK, mat)
			for i = 1, 3 do
				local fz = -s * 0.22 + (i - 1) * s * 0.22
				local ph = (0.55 + math.random() * 0.35) * scale
				local file = dpart(m, Vector3.new(s * 0.7, ph, 0.045),
					boxCF * CFrame.new(0, bh + ph / 2 - 0.12, fz),
					paperCols[(i % #paperCols) + 1], mat)
				file.Name = "PaperFile"
			end
		end

		addOpenBox(Vector3.new(-0.85, 0, 0), math.rad(-8), 1)
		addOpenBox(Vector3.new(1.35, 0, 0.65), math.rad(13), 0.9)
		if math.random() < 0.8 then
			addOpenBox(Vector3.new(-0.65, 2.08, 0.15), math.rad(7), 0.82)
		end
		for i = 1, math.random(4, 6) do
			local px = (math.random() * 2 - 1) * 3.8
			local pz = (math.random() * 2 - 1) * 3.1
			local yaw = math.random() * math.pi * 2
			local loose = dpart(m,
				Vector3.new(1.35 + math.random() * 0.5, 0.025, 1.75 + math.random() * 0.5),
				CFrame.new(px, 0.025 + i * 0.002, pz) * CFrame.Angles(0, yaw, 0),
				paperCols[(i % #paperCols) + 1], mat)
			loose.Name = "LoosePaper"
		end
		m.PrimaryPart = primary
		return m
	end

	DECOR_BUILDERS.Printer = function()
		local m = Instance.new("Model"); m.Name = "Printer"
		local body = dpart(m, Vector3.new(3, 2, 2.4), CFrame.new(0, 1, 0), PLASTIC, Enum.Material.Plastic)
		dpart(m, Vector3.new(2.6, 0.3, 1.4), CFrame.new(0, 2.05, -0.1), Color3.fromRGB(90, 90, 96))   -- tray
		dpart(m, Vector3.new(2, 0.05, 1.2), CFrame.new(0, 2.25, -0.6), Color3.fromRGB(245, 245, 240)) -- paper
		dpart(m, Vector3.new(0.8, 0.5, 0.05), CFrame.new(0.9, 1.4, -1.22), Color3.fromRGB(40, 44, 52), Enum.Material.Neon) -- panel (front)
		m.PrimaryPart = body
		return m
	end

	DECOR_BUILDERS.GrandfatherClock = function()
		local m = Instance.new("Model"); m.Name = "GrandfatherClock"
		local cab = dpart(m, Vector3.new(2, 9, 1.2), CFrame.new(0, 4.5, 0), WOOD, Enum.Material.Wood, PROP_WALNUT_TEXTURE, 3, { Enum.NormalId.Front }) -- cabinet
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
		local gap = DECOR_MIN_GAP
		for _, prop in ipairs(PROPS) do
			if prop.name == name and prop.minGap ~= nil then gap = prop.minGap break end
		end
		for _, c in ipairs(list) do
			if math.max(math.abs(c[1] - x), math.abs(c[2] - z)) <= gap then return true end
		end
		return false
	end
	local function record(name, x, z)
		placedCells[name] = placedCells[name] or {}
		table.insert(placedCells[name], { x, z })
	end

	-- Open areas use a handful of huge furniture heaps instead of hundreds of
	-- separately scattered chairs. Each heap is a dense base, a narrower middle
	-- and a crooked top, like an abandoned office was pushed into a barricade.
	local plazaCenter = Vector3.new(O + (fx - 0.5) * CELL, 0, O + (fz - 0.5) * CELL)
	workspace:SetAttribute("ForcedPlazaCenter", plazaCenter)
	local pileChoices = {
		"Chair", "Chair", "Chair", "Table", "Table",
		"CardboardPile", "CardboardPile", "GrandfatherClock",
	}
	local function addPileLayer(center, heapIndex, count, maxRadius, minLift, maxLift, maxTilt, choices)
		for _ = 1, count do
			local angle = math.random() * math.pi * 2
			local radius = math.sqrt(math.random()) * maxRadius
			local px = center.X + math.cos(angle) * radius
			local pz = center.Z + math.sin(angle) * radius
			local available = choices or pileChoices
			local name = available[math.random(#available)]
			local placed = spawnProp(name, propHeight(name), px, pz, nil)
			if placed then
				local pivot = placed:GetPivot()
				local tiltX = math.rad(math.random(-maxTilt, maxTilt))
				local tiltZ = math.rad(math.random(-maxTilt, maxTilt))
				local yaw = math.random() * math.pi * 2
				local lift = minLift + math.random() * (maxLift - minLift)
				placed:PivotTo(CFrame.new(pivot.Position + Vector3.new(0, lift, 0))
					* CFrame.Angles(tiltX, yaw, tiltZ))
				placed:SetAttribute("PlazaPile", true)
				placed:SetAttribute("PlazaHeapIndex", heapIndex)
				if name == "Table" and math.random() < 0.55 then addPhone(placed) end
			end
		end
	end
	local function makeFurnitureHeap(center, heapIndex)
		addPileLayer(center, heapIndex, math.random(30, 35), 13.5, 0, 1.25, 26)
		addPileLayer(center, heapIndex, math.random(22, 27), 9.0, 2.5, 4.7, 44)
		addPileLayer(center, heapIndex, math.random(12, 16), 5.5, 6.4, 8.0, 58,
			{ "Chair", "Chair", "Table", "Table", "CardboardPile" })

		-- These invisible volumes affect Entity sight only. CanQuery stays false
		-- so flashlight rays still illuminate the visible furniture.
		for index, data in ipairs({
			{ size = Vector3.new(27, 8.5, 27), y = 4.25 },
			{ size = Vector3.new(15, 5.5, 15), y = 10.75 },
		}) do
			local blocker = Instance.new("Part")
			blocker.Name = ("PlazaSightBlocker%d_%d"):format(heapIndex, index)
			blocker.Anchored = true
			blocker.CanCollide = false
			blocker.CanTouch = false
			blocker.CanQuery = false
			blocker.Transparency = 1
			blocker.Size = data.size
			blocker.Position = center + Vector3.new(0, data.y, 0)
			blocker:SetAttribute("BlocksEntitySight", true)
			blocker:SetAttribute("PlazaHeapIndex", heapIndex)
			blocker.Parent = decorFolder
		end
	end

	-- Smaller narrative clusters break up ordinary corridors: an abandoned desk
	-- shoved together with its chair, a clock and another office prop. Deliberate
	-- overlap makes these read as hurried piles rather than neatly placed furniture.
	local function makeMiniPropPile(center, pileIndex)
		local yaw = math.random() * math.pi * 2
		local function rotatedOffset(x, z)
			return Vector3.new(
				x * math.cos(yaw) - z * math.sin(yaw),
				0,
				x * math.sin(yaw) + z * math.cos(yaw)
			)
		end
		local extra = math.random() < 0.5 and "Printer" or "CardboardPile"
		local specs = {
			{ "Table",            0.0,  0.0, 0.05,  5 },
			{ "Chair",            2.0,  0.7, 0.35, 24 },
			{ "GrandfatherClock", -2.0, -0.8, 0.45, 11 },
			{ extra,               0.8, -1.6, 0.85, 19 },
		}
		for order, spec in ipairs(specs) do
			local name, ox, oz, lift, tilt = table.unpack(spec)
			local offset = rotatedOffset(ox, oz)
			local placed = spawnProp(name, propHeight(name),
				center.X + offset.X, center.Z + offset.Z, nil)
			if placed then
				local pivot = placed:GetPivot()
				local side = order % 2 == 0 and 1 or -1
				placed:PivotTo(CFrame.new(pivot.Position + Vector3.new(0, lift, 0))
					* CFrame.Angles(math.rad(tilt * side), yaw + order * 0.63,
						math.rad(tilt * 0.55 * -side)))
				placed:SetAttribute("MiniPropPile", true)
				placed:SetAttribute("MiniPropPileIndex", pileIndex)
				if name == "Table" then addPhone(placed) end
			end
		end
	end

	local heapCells = { { fx, fz } }
	local openCandidates = {}
	for x = 2, GRID - 1 do
		for z = 2, GRID - 1 do
			if pitCellSet[key(x, z)] or insideForcedPlaza(x, z) then continue end
			if math.max(math.abs(x - ELEV_X), math.abs(z - ELEV_Y)) <= ELEV_CLEAR + 2 then continue end
			local walls = presentWalls(x, z)
			local wallCount = 0
			for _, present in pairs(walls) do if present then wallCount += 1 end end
			if wallCount == 0 then
				openCandidates[#openCandidates + 1] = { x, z, density(x, z) }
			end
		end
	end
	table.sort(openCandidates, function(a, b) return a[3] > b[3] end)
	for _, candidate in ipairs(openCandidates) do
		if #heapCells >= 3 then break end
		local farEnough = true
		for _, existing in ipairs(heapCells) do
			local dx, dz = candidate[1] - existing[1], candidate[2] - existing[2]
			if dx * dx + dz * dz < 10 * 10 then farEnough = false break end
		end
		if farEnough then heapCells[#heapCells + 1] = { candidate[1], candidate[2] } end
	end
	for heapIndex, cell in ipairs(heapCells) do
		makeFurnitureHeap(Vector3.new(O + (cell[1] - 0.5) * CELL, 0,
			O + (cell[2] - 0.5) * CELL), heapIndex)
	end
	workspace:SetAttribute("PlazaHeapCount", #heapCells)

	-- Spread several compact piles through non-plaza open rooms. Shuffle first so
	-- they are not biased toward the density sort used for the large heaps.
	for index = #openCandidates, 2, -1 do
		local other = math.random(index)
		openCandidates[index], openCandidates[other] = openCandidates[other], openCandidates[index]
	end
	local miniCells = {}
	for _, candidate in ipairs(openCandidates) do
		if #miniCells >= 9 then break end
		local farEnough = true
		for _, heapCell in ipairs(heapCells) do
			local dx, dz = candidate[1] - heapCell[1], candidate[2] - heapCell[2]
			if dx * dx + dz * dz < 5 * 5 then farEnough = false break end
		end
		if farEnough then
			for _, miniCell in ipairs(miniCells) do
				local dx, dz = candidate[1] - miniCell[1], candidate[2] - miniCell[2]
				if dx * dx + dz * dz < 4 * 4 then farEnough = false break end
			end
		end
		if farEnough then
			miniCells[#miniCells + 1] = { candidate[1], candidate[2] }
			makeMiniPropPile(Vector3.new(O + (candidate[1] - 0.5) * CELL, 0,
				O + (candidate[2] - 0.5) * CELL), #miniCells)
		end
	end
	workspace:SetAttribute("MiniPropPileCount", #miniCells)

	for x = 1, GRID do
		for z = 1, GRID do
			local k = key(x, z)
			if pitCellSet[k] then continue end
			-- keep clear of the elevator room and its cell
			if math.max(math.abs(x - ELEV_X), math.abs(z - ELEV_Y)) <= ELEV_CLEAR then continue end
			-- All open/plaza cells are intentionally clean around the large heaps;
			-- this prevents the old fields of dozens of isolated chairs.
			if insideForcedPlaza(x, z) or density(x, z) >= PLAZA_T then continue end
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
				local inset = prop.wallInset or 1.5
				local px = fcx + wallDir.X * (CELL / 2 - inset) + along.X * j
				local pz = fcz + wallDir.Z * (CELL / 2 - inset) + along.Z * j
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

	decorFolder:SetAttribute("ClockDongMinSeconds", 180)
	decorFolder:SetAttribute("ClockDongMaxSeconds", 300)
	workspace:SetAttribute("DecorReady", true)
	-- One synchronized, positional grandfather-clock strike every 3-5 minutes
	-- (live-tunable via the ClockDong attributes above on workspace.Decor).
	-- The stock bass sample is pitched down and reverberated into a metallic DONG;
	-- no external audio asset is required.
	task.spawn(function()
		while decorFolder.Parent do
			local minGap = tonumber(decorFolder:GetAttribute("ClockDongMinSeconds")) or 180
			local maxGap = tonumber(decorFolder:GetAttribute("ClockDongMaxSeconds")) or 300
			task.wait(math.random(math.max(minGap, 10), math.max(maxGap, minGap, 10)))
			local clocks = {}
			for _, child in ipairs(decorFolder:GetChildren()) do
				if child:IsA("Model") and child.Name == "GrandfatherClock" and child.PrimaryPart then
					clocks[#clocks + 1] = child
				end
			end
			local clockModel = clocks[math.random(1, math.max(#clocks, 1))]
			if clockModel and clockModel.PrimaryPart then
				local dong = Instance.new("Sound")
				dong.Name = "GrandfatherClockDong"
				dong.SoundId = "rbxasset://sounds/bass.wav"
				dong.Volume = 1.65
				dong.PlaybackSpeed = 0.38
				dong.RollOffMode = Enum.RollOffMode.Linear
				dong.RollOffMinDistance = 45
				dong.RollOffMaxDistance = 1200
				local reverb = Instance.new("ReverbSoundEffect")
				reverb.DecayTime = 5.5
				reverb.Density = 0.82
				reverb.Diffusion = 0.75
				reverb.DryLevel = -1
				reverb.WetLevel = -4
				reverb.Parent = dong
				dong.Parent = clockModel.PrimaryPart
				dong:Play()
				game:GetService("Debris"):AddItem(dong, 12)
			end
		end
	end)
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
Lighting.FogStart = 30
Lighting.FogEnd = 220                           -- lighter fog while keeping long corridors hidden

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

-- mode controller: ALERT pulses all lights red (continuous); NORMAL and
-- the dark BLACKOUT/ESCAPE phases apply once so flicker loops can own lights
task.spawn(function()
	local prev = "NORMAL"
	local phase = 0
	local powerdownStart, powerdownDuration, powerdownIndex = 0, 5, 0
	local powerdownOrder = {}
	while true do
		local dt = task.wait(0.08)
		local mode = lightMode()
		if mode == "ALERT" then
			phase += dt
			-- Static red-alert properties are set once on the mode edge; only the
			-- pulsing brightness needs rewriting on every 0.08s tick (~300 lights).
			if prev ~= "ALERT" then
				for _, L in ipairs(allLights) do
					L.light.Enabled = true
					L.light.Color = Color3.fromRGB(255, 45, 30)
					L.panel.Color = Color3.fromRGB(120, 12, 10)
					L.panel.Material = Enum.Material.Neon
				end
			end
			local b = 0.12 + 0.55 * (0.5 + 0.5 * math.sin(phase * 1.6))
			for _, L in ipairs(allLights) do
				L.light.Brightness = b
			end
		elseif mode == "POWERDOWN" then
			if prev ~= "POWERDOWN" then
				-- Expanding shutdown wave from the final lever. Its duration is supplied
				-- by PuzzleManager from the uploaded power-down recording itself.
				powerdownStart = os.clock()
				powerdownDuration = math.max(workspace:GetAttribute("PowerDownDuration") or 5, 0.5)
				powerdownIndex = 0
				powerdownOrder = table.clone(allLights)
				local origin = workspace:GetAttribute("PowerDownOrigin")
				if typeof(origin) ~= "Vector3" then origin = Vector3.zero end
				table.sort(powerdownOrder, function(a, b)
					return (a.pos - origin).Magnitude < (b.pos - origin).Magnitude
				end)
			end

			local progress = math.clamp((os.clock() - powerdownStart) / powerdownDuration, 0, 1)
			local target = math.floor(#powerdownOrder * progress)
			while powerdownIndex < target do
				powerdownIndex += 1
				local L = powerdownOrder[powerdownIndex]
				L.light.Enabled = false
				L.panel.Color = Color3.fromRGB(18, 18, 18)
				L.panel.Material = Enum.Material.SmoothPlastic
			end
		elseif mode == "BLACKOUT" or mode == "ESCAPE" then
			if prev ~= mode then
				-- ESCAPE stays fully dark. The objective detector and exit compass
				-- guide survivors without relighting a green ceiling route.
				for _, L in ipairs(allLights) do
					L.light.Enabled = false
					L.panel.Color = Color3.fromRGB(18, 18, 18)
					L.panel.Material = Enum.Material.SmoothPlastic
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
		-- ESCAPE stays fully dark; the entity must not flip ceiling panels back on
		if mode ~= "ALERT" and mode ~= "ESCAPE" and mode ~= "POWERDOWN" then
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
						-- back to full blackout darkness
						best.light.Enabled = false
						best.panel.Material = Enum.Material.SmoothPlastic
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


-- Tell the lobby controller that the elevator and complete maze are ready.
workspace:SetAttribute("WorldGenerated", true)
