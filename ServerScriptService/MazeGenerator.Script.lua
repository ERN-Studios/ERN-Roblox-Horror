-- MazeGenerator  (v2 — round-system compatible + Toolbox texture support)
-- PASTE INTO: ServerScriptService → Insert Object → Script → rename to "MazeGenerator"
-- REPLACES the old MazeGenerator entirely — paste over the old contents.
--
-- Generates a Backrooms-style maze at server start. No SpawnLocation here anymore:
-- GameManager owns spawning (lobby). This script leaves two invisible markers —
-- "MazeStart" (where the party teleports in) and "EntityStart" (entity corner).
--
-- BEFORE TESTING: delete the default Baseplate and default SpawnLocation.

local Lighting = game:GetService("Lighting")

-- ── tuning ────────────────────────────────────────────────
local GRID       = 40      -- maze is GRID x GRID cells
local CELL       = 24      -- studs per cell (corridor width)
local WALL_H     = 14      -- wall/ceiling height
local WALL_T     = 2       -- wall thickness
local OPENNESS   = 0.12    -- fraction of extra walls removed (loops / open areas)
local LIGHT_EVERY = 3      -- ceiling light every N cells
local FLICKER_CHANCE = 0.08 -- fraction of lights that flicker
local SEED       = nil     -- set a number (e.g. 1337) for the same maze every run

local WALL_COLOR    = Color3.fromRGB(197, 180, 116)
local FLOOR_COLOR   = Color3.fromRGB(158, 144, 96)
local CEILING_COLOR = Color3.fromRGB(222, 214, 170)
local LIGHT_COLOR   = Color3.fromRGB(255, 244, 200)

-- Optional Toolbox IMAGE textures. Leave "" for plain colors.
-- Toolbox → Marketplace → filter: Images → search e.g. "backrooms wallpaper",
-- right-click the image → Copy Asset ID → paste like: "rbxassetid://1234567890"
local WALL_TEXTURE    = ""   -- e.g. backrooms yellow wallpaper
local FLOOR_TEXTURE   = ""   -- e.g. old damp carpet
local CEILING_TEXTURE = ""   -- e.g. ceiling tiles
local TEXTURE_TILE    = 12   -- studs per texture repeat (smaller = denser pattern)
-- ──────────────────────────────────────────────────────────

if SEED then math.randomseed(SEED) end

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
local function key(x, z) return x .. "," .. z end

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

-- knock out extra walls → loops and open areas (backrooms feel, no dead-end hell)
for x = 1, GRID - 1 do
	for z = 1, GRID do
		if wallV[x][z] and math.random() < OPENNESS then wallV[x][z] = false end
	end
end
for x = 1, GRID do
	for z = 1, GRID - 1 do
		if wallH[x][z] and math.random() < OPENNESS then wallH[x][z] = false end
	end
end

-- ── build geometry ────────────────────────────────────────
local maze = Instance.new("Model")
maze.Name = "Maze"

local function part(size, cf, color, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = maze
	return p
end

local function applyTexture(p, id, faces, tile)
	if id == "" then return end
	for _, face in ipairs(faces) do
		local t = Instance.new("Texture")
		t.Texture = id
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		t.Parent = p
	end
end

local WALL_FACES = { Enum.NormalId.Front, Enum.NormalId.Back,
	Enum.NormalId.Left, Enum.NormalId.Right }

local function wallPart(size, cf)
	local p = part(size, cf, WALL_COLOR)
	applyTexture(p, WALL_TEXTURE, WALL_FACES, TEXTURE_TILE)
	return p
end

local SIZE = GRID * CELL
local O = -SIZE / 2 -- world coord of the maze's min edge

-- floor (top at y = 0) and ceiling
local floorPart = part(Vector3.new(SIZE, 1, SIZE), CFrame.new(0, -0.5, 0),
	FLOOR_COLOR, Enum.Material.Fabric)
applyTexture(floorPart, FLOOR_TEXTURE, { Enum.NormalId.Top }, TEXTURE_TILE)

local ceilingPart = part(Vector3.new(SIZE, 1, SIZE), CFrame.new(0, WALL_H + 0.5, 0),
	CEILING_COLOR)
applyTexture(ceilingPart, CEILING_TEXTURE, { Enum.NormalId.Bottom }, TEXTURE_TILE)

-- border walls
wallPart(Vector3.new(SIZE + WALL_T * 2, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, O - WALL_T / 2))
wallPart(Vector3.new(SIZE + WALL_T * 2, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, -O + WALL_T / 2))
wallPart(Vector3.new(WALL_T, WALL_H, SIZE + WALL_T * 2), CFrame.new(O - WALL_T / 2, WALL_H / 2, 0))
wallPart(Vector3.new(WALL_T, WALL_H, SIZE + WALL_T * 2), CFrame.new(-O + WALL_T / 2, WALL_H / 2, 0))

-- internal walls
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

-- ── ceiling lights ────────────────────────────────────────
local flicker = {}
for x = 2, GRID, LIGHT_EVERY do
	for z = 2, GRID, LIGHT_EVERY do
		local panel = part(Vector3.new(8, 0.4, 8),
			CFrame.new(O + (x - 0.5) * CELL, WALL_H - 0.2, O + (z - 0.5) * CELL),
			Color3.fromRGB(255, 250, 230), Enum.Material.Neon)

		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Brightness = 0.9
		light.Range = 32
		light.Angle = 140
		light.Color = LIGHT_COLOR
		light.Shadows = false -- shadows on hundreds of lights kills performance
		light.Parent = panel

		if math.random() < FLICKER_CHANCE then
			table.insert(flicker, { panel, light })
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
local entityStart = marker("EntityStart",
	CFrame.new(O + (GRID - 1.5) * CELL, 3, O + (GRID - 1.5) * CELL))

-- park the entity in its corner until GameManager takes over
task.spawn(function()
	local entity = workspace:WaitForChild("Entity", 15)
	if entity and entity.PrimaryPart then
		entity:PivotTo(entityStart.CFrame + Vector3.new(0, 5, 0))
	end
end)

-- ── mood lighting ─────────────────────────────────────────
Lighting.Ambient = Color3.fromRGB(8, 8, 6)
Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
Lighting.Brightness = 0.4
Lighting.ClockTime = 0
Lighting.GlobalShadows = true
Lighting.FogColor = Color3.fromRGB(30, 28, 18)
Lighting.FogEnd = 260
Lighting.FogStart = 40

-- ── light flicker loop ────────────────────────────────────
task.spawn(function()
	while task.wait(math.random(2, 6) / 10) do
		for _, f in ipairs(flicker) do
			if math.random() < 0.15 then
				local nowOn = not f[2].Enabled
				f[2].Enabled = nowOn
				f[1].Material = nowOn and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end
end)
