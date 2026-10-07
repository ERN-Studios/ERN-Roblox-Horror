"""Build Level 6 "the Arena" in the open Studio place from build_arena.py's export, as native Parts.

    python3 tools/level6_playground/import_arena.py [--dry] [--only <Group>] [--nav]

Replaces Workspace."Level 6 Indoor Playground" (same name and origin as the map before it, so every script that
looks the level up keeps working). Talks to Studio through its own MCP proxy, one execute_luau per chunk.
Blender (x, y, z) studs become Roblox (x - 300, z, -(y - 200)) + ORIGIN.

--only <Group>   rebuild one group's parts in the live model and leave everything else alone
--finish         only redo what is not a primitive: anchors, lights, signs, props, slides, the graph
--nav            only rewrite the navigation graph (model.NavGraph)
"""
import json, math, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_to_studio import Studio, srgb, to_roblox, TEXTURES, MODEL_NAME, ORIGIN   # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / 'artifacts' / 'level6-arena-20261006' / 'export'
CHUNK = 1100
SLIDE_KIT = 'Level6ArenaSlideKit'

# material key -> (Enum.Material, transparency, can collide)
SURFACE = {
    'mat_green': ('SmoothPlastic', 0, True), 'mat_blue': ('SmoothPlastic', 0, True), 'concrete': ('Concrete', 0, True),
    'wall_white': ('Concrete', 0, True), 'deck': ('Metal', 0, True), 'steel': ('Metal', 0, True),
    'duct': ('Metal', 0, True), 'stainless': ('Metal', 0, True), 'lamp_on': ('Neon', 0, True),
    'lamp_warm': ('Neon', 0, True), 'lamp_green': ('Neon', 0, True), 'net_yellow': ('Fabric', 0.5, True),
    'net_black': ('Fabric', 0.75, True), 'dial': ('SmoothPlastic', 0, False),
    'tile_green': ('SmoothPlastic', 0, True), 'tile_blue': ('SmoothPlastic', 0, True),
    'stain': ('SmoothPlastic', 0.5, False),         # what has dried on the exit room's floor
    'guide': ('SmoothPlastic', 1, True),            # unseen: steers a body into the mouth of the slide under the post
    'white': ('Concrete', 0, True),
}
EXTRA_RGB = {'lamp_on': (255, 240, 205), 'lamp_warm': (255, 205, 120), 'lamp_green': (70, 255, 130),
             'net_yellow': (215, 170, 30), 'net_black': (12, 12, 12), 'dial': (232, 176, 28)}
NO_COLLIDE = ('Ceiling_', 'Hall_Balls', 'Frame_Lamps', 'Finale_Dial', 'Finale_Rim')

PRELUDE = '''
local NAME = %s
local O = Vector3.new(%d, %d, %d)
local model = workspace:FindFirstChild(NAME)
local MAT = {%s}
local NOCOLLIDE = {%s}
local folders = {}
local function folder(name)
	local f = folders[name]
	if not f then
		f = model:FindFirstChild(name)
		if not f then f = Instance.new("Folder"); f.Name = name; f.Parent = model end
		folders[name] = f
	end
	return f
end
local function loose(name)
	for _, prefix in ipairs(NOCOLLIDE) do if name:sub(1, #prefix) == prefix then return true end end
	return false
end
local function part(owner, mat, shape)
	local p = Instance.new("Part")
	local m = MAT[mat]
	p.Anchored = true
	p.Color, p.Material, p.Transparency = m[1], m[2], m[3]
	p.CanCollide = m[4] and not loose(owner)
	p.CanTouch = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Name = mat
	return p
end
local TEX = {%s}
local function texture(p, id, face, studs, colour, transparency)
	local t = Instance.new("Texture")
	t.Texture, t.Face = id, face
	t.StudsPerTileU, t.StudsPerTileV = studs, studs
	t.Color3 = colour or Color3.new(1, 1, 1)
	t.Transparency = transparency or 0
	t.Parent = p
	return t
end
-- grime: the same blotched overlay everywhere, but every part gets its own size and its own piece of it
local grimeSeed = 0
local function grime(p, face, strength, fine)
	grimeSeed += 1
	local size = fine and 3.6 + (grimeSeed %% 4) * 0.7 or 8 + (grimeSeed %% 5) * 1.6
	local t = texture(p, TEX.grime, face, size, Color3.fromRGB(24, 20, 13), 1 - strength)
	t.OffsetStudsU, t.OffsetStudsV = (grimeSeed * 3.7) %% 11, (grimeSeed * 5.3) %% 13
end
local KIT = game:GetService("ReplicatedStorage"):FindFirstChild("Level6PropKit")
local SLIDEKIT = game:GetService("ReplicatedStorage"):FindFirstChild(%s)
local SIDES = {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}
local VINYL = {yellow = true, red = true, blue = true, green = true, purple = true, orange = true, navy = true,
	mat_blue = true, mat_green = true, yellow_worn = true, yellow_dark = true, navy_worn = true, blue_worn = true}
local PADDED = {Frame_Panels = true, Frame_SoftSteps = true, Frame_PlayFeatures = true, Hall_SoftBlocks = true, Tunnel = true,
	ExitRoom = true, Finale_Shaft = true, Finale_Post = true, Finale_Rim = true, Gate = true, Frame_Entrances = true,
	Frame_Bridges = true}
local function tint(c, k)
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end
local function decorate(p, owner, mat)
	if string.sub(mat, 1, 4) == "net_" then
		-- only the cords show: the sheet itself is unseen. Left faintly visible (0.9) it cost a draw call per net,
		-- about 570 of 1500 in the view up the galleries (measured 2026-10-06), for no visible difference
		p.Transparency = 1
		p.CastShadow = false
		texture(p, TEX.net, Enum.NormalId.Front, 5)
		texture(p, TEX.net, Enum.NormalId.Back, 5)
	elseif owner == "Floor_FoamTiles" or owner == "Finale_Lid" then
		texture(p, TEX.foam_mat, Enum.NormalId.Top, 12, tint(p.Color, 1.05))
		if p.Position.Y < O.Y - 20 then grime(p, Enum.NormalId.Top, 0.8) end      -- the mats of the room under the court
	elseif owner == "ExitRoom" then
		-- the room the slide ends in: quilted vinyl on the two faces of a pad you can see, and every surface filthy
		if VINYL[mat] or mat == "concrete" or mat == "white" or mat == "steel" then
			local s = p.Size
			local faces = (s.Y <= s.X and s.Y <= s.Z) and {Enum.NormalId.Top, Enum.NormalId.Bottom}
				or (s.X <= s.Z) and {Enum.NormalId.Left, Enum.NormalId.Right} or {Enum.NormalId.Front, Enum.NormalId.Back}
			for _, face in ipairs(faces) do
				if VINYL[mat] then texture(p, TEX.vinyl_pad, face, 7, tint(p.Color, 1.2)) end
				if math.min(s.X, s.Y, s.Z) < 2 and math.max(s.X, s.Y, s.Z) > 1.5 then
					grime(p, face, VINYL[mat] and 0.95 or 0.7)
					if VINYL[mat] and math.max(s.X, s.Y, s.Z) > 3 then grime(p, face, 0.6, true) end     -- and finer dirt over the blotches
				end
			end
		end
	elseif owner == "Frame_Decks" then
		-- the galleries you look along and up into: mats underfoot and overhead
		local c = tint(p.Color, 1.2)
		texture(p, TEX.vinyl_pad, Enum.NormalId.Top, 7, c)
		texture(p, TEX.vinyl_pad, Enum.NormalId.Bottom, 7, c)
	elseif owner == "Frame_DecksDeep" then
		texture(p, TEX.vinyl_pad, Enum.NormalId.Top, 7, tint(p.Color, 1.2))
	elseif owner == "Ceiling_Structure" and mat == "deck" and p.Size.X > 100 then
		texture(p, TEX.roof_deck, Enum.NormalId.Bottom, 16, Color3.fromRGB(150, 150, 150))
	elseif owner == "Walls" then
		for _, face in ipairs(SIDES) do texture(p, TEX.block_wall, face, 14, tint(p.Color, 1.1)) end
	elseif VINYL[mat] and PADDED[owner] then
		local c = tint(p.Color, 1.2)
		texture(p, TEX.vinyl_pad, Enum.NormalId.Top, 7, c)
		for _, face in ipairs(SIDES) do texture(p, TEX.vinyl_pad, face, 7, c) end
	end
end
-- MATS_20261007: a mat is cut to the shape of its cell (kind "p": inner radius, outer radius, the sector's angle,
-- whether the outer edge has a corner in the middle, the angle the mat stands at, its height, its thickness).
-- One block per shape is cut with GeometryService and every mat of that shape is a clone of it, turned about the
-- middle of the hall. Rectangles as wide as the cell's outer edge lay over their neighbours; these meet edge to edge.
local GeometryService = game:GetService("GeometryService")
local matKit = {}
local function matTemplate(ra, rb, delta, split)
	local key = string.format("%%g,%%g,%%g,%%d", ra, rb, delta, split)
	local kit = matKit[key]
	if kit then return kit end
	local h = math.rad(delta / 2)
	local T = Vector3.new(0, 2000, 0)                     -- cut near the world's origin: out at the level the numbers are coarse
	local corners = {Vector3.new(ra * math.cos(h), 0, ra * math.sin(h)), Vector3.new(ra * math.cos(h), 0, -ra * math.sin(h)),
		Vector3.new(rb * math.cos(h), 0, -rb * math.sin(h))}
	if split == 1 then corners[#corners + 1] = Vector3.new(rb, 0, 0) end
	corners[#corners + 1] = Vector3.new(rb * math.cos(h), 0, rb * math.sin(h))
	local middle = Vector3.zero
	for _, c in ipairs(corners) do middle += c / #corners end
	local xi, xo, w = ra * math.cos(h), split == 1 and rb or rb * math.cos(h), rb * math.sin(h)
	local bench = Instance.new("Folder")
	bench.Name = "L6MatBench"
	bench.Parent = workspace
	local base = Instance.new("Part")
	base.Anchored, base.Size, base.CFrame = true, Vector3.new(xo - xi, 1, 2 * w), CFrame.new(T + Vector3.new((xi + xo) / 2, 0, 0))
	base.TopSurface, base.BottomSurface, base.Material = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth, Enum.Material.SmoothPlastic
	base.Parent = bench
	local cutters = {}
	for i, a in ipairs(corners) do
		local b = corners[i %% #corners + 1]
		if math.abs(a.X - b.X) > 1e-4 then                -- an edge that is not already a side of the block
			local d = (b - a).Unit
			local out = Vector3.new(d.Z, 0, -d.X)
			local mid = (a + b) / 2
			if out:Dot(mid - middle) < 0 then out = -out end
			local c = Instance.new("Part")
			c.Anchored, c.Size = true, Vector3.new((b - a).Magnitude + 8, 4, 10)
			c.CFrame = CFrame.fromMatrix(T + mid + out * 5, d, Vector3.yAxis)
			c.Parent = bench
			cutters[#cutters + 1] = c
		end
	end
	local cut = GeometryService:SubtractAsync(base, cutters, {CollisionFidelity = Enum.CollisionFidelity.Hull,
		RenderFidelity = Enum.RenderFidelity.Precise, SplitApart = false})
	local shape = cut[1]
	shape.UsePartColor, shape.Anchored, shape.CanTouch = true, true, false
	kit = {part = shape, rel = CFrame.new(-T) * shape.CFrame}
	bench:Destroy()
	matKit[key] = kit
	return kit
end
local function along(a, b)
	local d = b - a
	local up = math.abs(d.Unit.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local right = d.Unit
	local z = right:Cross(up).Unit
	return CFrame.fromMatrix((a + b) / 2, right, z:Cross(right).Unit, z), d.Magnitude
end
'''

BUILD = '''
local made = 0
for line in string.gmatch(DATA, "[^\\n]+") do
	local f = string.split(line, ",")
	local kind, owner, mat = f[1], f[2], f[3]
	local n = {}
	for i = 4, #f do n[i - 3] = tonumber(f[i]) end
	local parent = folder(owner)
	if kind == "b" then
		local p = part(owner, mat)
		p.Size = Vector3.new(n[4], n[5], n[6])
		p.CFrame = CFrame.new(O + Vector3.new(n[1], n[2], n[3]))
		decorate(p, owner, mat)
		p.Parent = parent
	elseif kind == "o" then
		-- a box turned about the vertical axis: size is (along its own x, up, along its own z)
		local p = part(owner, mat)
		p.Size = Vector3.new(n[4], n[6], n[5])
		p.CFrame = CFrame.new(O + Vector3.new(n[1], n[2], n[3])) * CFrame.Angles(0, math.rad(n[7]), 0)
		decorate(p, owner, mat)
		p.Parent = parent
	elseif kind == "p" then
		local kit = matTemplate(n[1], n[2], n[3], n[4])
		local p = kit.part:Clone()
		local m = MAT[mat]
		p.Name = mat
		p.Color, p.Material, p.Transparency = m[1], m[2], m[3]
		p.CanCollide = m[4] and not loose(owner)
		p.Size = Vector3.new(kit.part.Size.X, n[7], kit.part.Size.Z)
		p.CFrame = (CFrame.new(O) * CFrame.Angles(0, math.rad(n[5]), 0) * kit.rel) + Vector3.new(0, n[6], 0)
		p.Parent = parent
	elseif kind == "c" or kind == "t" then
		local a, b = O + Vector3.new(n[1], n[2], n[3]), O + Vector3.new(n[4], n[5], n[6])
		local cf, len = along(a, b)
		if kind == "c" then
			local p = part(owner, mat, Enum.PartType.Cylinder)
			p.Size = Vector3.new(len, n[7] * 2, n[7] * 2)
			p.CFrame = cf
			if PADDED[owner] and VINYL[mat] and n[7] > 1 then
				local c = tint(p.Color, 1.2)
				for _, face in ipairs({Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Front, Enum.NormalId.Back}) do
					texture(p, TEX.vinyl_pad, face, 7, c)
				end
			end
			p.Parent = parent
		else
			-- a tube is a moulded mesh to look at (placed once, at the end) and an invisible square channel to ride or crawl
			local r = n[7]
			if not SLIDEKIT then
				local tubeMesh = KIT and KIT:FindFirstChild("tube_segment")
				if tubeMesh then
					local p = tubeMesh:Clone()
					p.Name, p.Anchored, p.CanTouch, p.CanCollide, p.CastShadow = mat, true, false, false, false
					p.Color, p.Material = MAT[mat] and MAT[mat][1] or Color3.fromRGB(238, 106, 18), Enum.Material.SmoothPlastic
					p.Size = Vector3.new(len * 1.12, r * 2.18, r * 2.18)
					p.CFrame = cf
					p.Parent = parent
				end
			end
			local sliding = owner == "Frame_Slides"
			local function side(name, size, offset)
				local w = Instance.new("Part")
				w.Name, w.Anchored, w.CanTouch, w.Transparency, w.CanCollide = name, true, false, 1, true
				w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				w.Size, w.CFrame = size, cf * offset
				w.Parent = parent
				return w
			end
			local floor = side("TubeFloor", Vector3.new(len + 0.6, 1, r * 1.3), CFrame.new(0, -r * 0.75 - 0.5, 0))
			if sliding then
				floor:SetAttribute("L6Slide", true)
				-- which way this stretch runs (every slide is listed from its top). With it the client carries you along
				-- whatever the slope: a slide's mouth is almost level, and without this it never took hold of a player
				-- who walked in, who then met the roof further in standing up (found on foot, 2026-10-06)
				floor:SetAttribute("L6SlideDir", (b - a).Unit)
				-- the way out under the post also sets its pace per stretch: one speed round the spiral, easing off
				-- before the room
				if n[8] and n[8] > 0 then floor:SetAttribute("L6SlideSpeed", n[8]) end
			end
			side("TubeWall", Vector3.new(len + 0.6, r * 1.5, 0.5), CFrame.new(0, 0, r * 0.75))
			side("TubeWall", Vector3.new(len + 0.6, r * 1.5, 0.5), CFrame.new(0, 0, -r * 0.75))
			if sliding and n[9] ~= 1 then side("TubeRoof", Vector3.new(len + 0.6, 0.5, r * 1.3), CFrame.new(0, r * 0.85, 0)) end
		end
	elseif kind == "q" then
		local p0 = O + Vector3.new(n[1], n[2], n[3])
		local u = O + Vector3.new(n[4], n[5], n[6]) - p0
		local v = O + Vector3.new(n[7], n[8], n[9]) - p0
		local p = part(owner, mat)
		local normal = u.Unit:Cross(v.Unit)
		local cf = CFrame.fromMatrix(p0 + (u + v) / 2, u.Unit, v.Unit, normal)
		if owner == "Arena_SlideSurfaces" then
			if normal.Y < 0 then normal = -normal end
			p.Size = Vector3.new(u.Magnitude, v.Magnitude, 0.8)
			p.CFrame = cf + -normal * 0.4
			p:SetAttribute("L6Slide", true)
			p:SetAttribute("L6SlideSpeed", 30)        -- the funnel under the post: straight down the slope, not too fast
		else
			p.Size = Vector3.new(u.Magnitude, v.Magnitude, 0.15)
			p.CFrame = cf
		end
		decorate(p, owner, mat)
		p.Parent = parent
	elseif kind == "s" then
		local p = part(owner, mat, Enum.PartType.Ball)
		p.Size = Vector3.one * n[4] * 2
		p.CFrame = CFrame.new(O + Vector3.new(n[1], n[2], n[3]))
		p.CastShadow = false
		p.Parent = parent
	end
	made += 1
end
return "made " .. made
'''

FINISH = '''
local anchors = folder("Anchors")
for line in string.gmatch(ANCHORS, "[^\\n]+") do
	local f = string.split(line, ",")
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = f[1], true, false, false, false
	p.Transparency, p.Size = 1, Vector3.new(2, 2, 2)
	p.CFrame = CFrame.new(O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4])))
	local kind = string.match(f[1], "^L6_Hide_(.-)_%d+$")
	if kind then p:SetAttribute("HideKind", kind) end
	p.Parent = anchors
end
local lights = folder("Lights")
for line in string.gmatch(LIGHTS, "[^\\n]+") do
	local f = string.split(line, ",")
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = f[1], true, false, false, false
	p.Transparency, p.Size = 1, Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4])))
	local light
	if f[5] == "spot" then
		-- a cone straight down: pools of light on the mats, the dark between them stays dark
		light = Instance.new("SpotLight")
		light.Face, light.Angle = Enum.NormalId.Bottom, tonumber(f[8])
	else
		light = Instance.new("PointLight")
	end
	light.Shadows = false
	light.Range, light.Brightness = tonumber(f[6]), tonumber(f[7])
	light.Color = Color3.fromRGB(tonumber(f[9]), tonumber(f[10]), tonumber(f[11]))
	light.Parent = p
	-- the exit room keeps its own light: the client turns everything in "Lights" red for the last minute
	p.Parent = string.sub(f[1], 1, 11) == "L6_ExitRoom" and folder("ExitLights") or lights
end
local signs = folder("Signs")
local function nums(s)
	local t = {}
	for v in string.gmatch(s, "[^,]+") do t[#t + 1] = tonumber(v) end
	return t
end
local LETTERS = {"#E0352B", "#F2C21A", "#2FA04A", "#3A7BE0"}
for line in string.gmatch(SIGNS, "[^\\n]+") do
	local f = string.split(line, "|")
	local c, dir, bg, fg = nums(f[1]), nums(f[4]), nums(f[6]), nums(f[7])
	local w, h = tonumber(f[2]), tonumber(f[3])
	local out = Vector3.new(dir[1], dir[2], dir[3])
	local at = O + Vector3.new(c[1], c[2], c[3]) + out * 0.15
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = "Sign", true, false, false, false
	p.Size = Vector3.new(w, h, 0.2)
	p.Color, p.Material = Color3.fromRGB(bg[1], bg[2], bg[3]), Enum.Material.SmoothPlastic
	p.CFrame = CFrame.lookAt(at, at + out)
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.SizingMode = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud, gui.LightInfluence = 40, 1
	local label = Instance.new("TextLabel")
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	label.TextScaled, label.Font = true, Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(fg[1], fg[2], fg[3])
	if f[8] == "playzone_letters" then
		-- the painted lintel: every letter its own colour, worn
		p.Name = "PlayZoneSign"
		texture(p, TEX.vinyl_pad, Enum.NormalId.Front, 7, tint(p.Color, 1.2))
		local text, i = "", 0
		for ch in string.gmatch(f[5], ".") do
			if ch == " " then
				text ..= "  "
			else
				i += 1
				text ..= string.format('<font color="%s">%s</font>', LETTERS[(i - 1) % #LETTERS + 1], ch)
			end
		end
		label.RichText, label.Text = true, text
		label.TextTransparency = 0.08
	elseif f[8] == "exit_green" then
		-- lit from inside: it shows in the dark
		p.Name = "ExitSign"
		gui.LightInfluence, gui.Brightness = 0, 2
		label.Font = Enum.Font.GothamBlack
		label.Text = f[5]
	else
		label.Text = f[5]
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.04, 0), UDim.new(0.04, 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.08, 0), UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
	p.Parent = signs
end
local props = folder("Props")
local missing = {}
for line in string.gmatch(PROPS, "[^\\n]+") do
	local f = string.split(line, ",")
	local template = KIT and KIT:FindFirstChild(f[1])
	if template then
		local m = template:Clone()
		local longest = math.max(m.Size.X, m.Size.Y, m.Size.Z)
		m.Size = m.Size * (tonumber(f[6]) / longest)
		m.Anchored, m.CanCollide, m.CanTouch = true, f[7] == "1", false
		if f[1] == "pa_speaker" then m.Color, m.Material = Color3.fromRGB(150, 150, 140), Enum.Material.Metal end
		local base = O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4]))
		m.CFrame = CFrame.new(base + Vector3.new(0, m.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(tonumber(f[5])), 0)
		m.Parent = props
	else
		missing[f[1]] = true
	end
end
local slides = folder("Slides")
for line in string.gmatch(SLIDES, "[^\\n]+") do
	local f = string.split(line, ",")
	local template = SLIDEKIT and SLIDEKIT:FindFirstChild(f[1])
	if template then
		local m = template:Clone()
		m.Anchored, m.CanCollide, m.CanTouch, m.CanQuery = true, false, false, false
		-- moulded plastic: the colour and its long white highlights are painted into the mesh's vertex colours
		m.Material, m.Reflectance, m.Color, m.TextureID = Enum.Material.SmoothPlastic, 0.06, Color3.new(1, 1, 1), ""
		for _, c in ipairs(m:GetChildren()) do if c:IsA("SurfaceAppearance") then c:Destroy() end end
		-- Studio's File > Import hands meshes back turned half a turn about the vertical axis; meshes uploaded by
		-- upload_arena_slides.py come as they were modelled (the kit says which it holds)
		m.CFrame = CFrame.new(O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4])))
			* CFrame.Angles(0, math.rad(tonumber(f[5])) + (SLIDEKIT:GetAttribute("Upright") and 0 or math.pi), 0)
		m.Parent = slides
	else
		missing[f[1]] = true
	end
end
-- Level6PreviewAccess lands a party on Level6Exit: in the tunnel, facing the gate.
local spawn = anchors:FindFirstChild("L6_Anchor_Spawn")
local gate = anchors:FindFirstChild("L6_Anchor_Gate")
local exit = Instance.new("Part")
exit.Name, exit.Anchored, exit.CanCollide, exit.CanTouch, exit.CanQuery = "Level6Exit", true, false, false, false
exit.Transparency, exit.Size = 1, Vector3.new(4, 1, 4)
local at = Vector3.new(spawn.Position.X, O.Y + 0.95 + 3.05, spawn.Position.Z)
exit.CFrame = CFrame.lookAt(at, Vector3.new(gate.Position.X, at.Y, gate.Position.Z))
exit.Parent = model
-- the green light the hole is known by, dark until the post has gone down
local glow = Instance.new("Part")
glow.Name, glow.Anchored, glow.CanCollide, glow.CanTouch, glow.CanQuery = "Finale_Glow", true, false, false, false
glow.Transparency, glow.Size = 1, Vector3.new(1, 1, 1)
glow.CFrame = CFrame.new(O + Vector3.new(0, -6, 0))
for _, spec in ipairs({{"Up", Enum.NormalId.Top, 60, 150}, {"Down", Enum.NormalId.Bottom, 40, 170}}) do
	local l = Instance.new("SpotLight")
	l.Name, l.Face, l.Range, l.Angle = spec[1], spec[2], spec[3], spec[4]
	l.Color, l.Brightness, l.Shadows, l.Enabled = Color3.fromRGB(70, 255, 130), 0, false, false
	l.Parent = glow
end
do      -- and one that lights the padded wall of the shaft itself: that is the green you see in the hole from the galleries
	local l = Instance.new("PointLight")
	l.Name, l.Range, l.Color, l.Brightness, l.Shadows, l.Enabled = "Rim", 14, Color3.fromRGB(70, 255, 130), 0, false, false
	l.Parent = glow
end
do      -- and the pool of green on the court round the hole. A lamp UNDER the floor does not light the floor's top:
	-- what showed there in tests was the engine's coarse far-light grid, which arrives seconds late and not at
	-- all from close by. This one hangs unseen over the hole, so the pool is there the moment the post is gone.
	local at = Instance.new("Attachment")
	at.Name, at.Position = "PoolAt", Vector3.new(0, 13, 0)
	at.Parent = glow
	local l = Instance.new("PointLight")
	l.Name, l.Range, l.Color, l.Brightness, l.Shadows, l.Enabled = "Pool", 30, Color3.fromRGB(70, 255, 130), 0, false, false
	l.Parent = at
end
glow.Parent = model
local exitAnchor = anchors.L6_Anchor_Exit
local exitLamp = Instance.new("PointLight")
exitLamp.Name, exitLamp.Color, exitLamp.Range, exitLamp.Brightness, exitLamp.Shadows = "ExitLamp", Color3.fromRGB(80, 255, 140), 30, 2.2, false
exitLamp.Parent = exitAnchor
model:SetAttribute("Source", "tools/level6_playground/build_arena.py")
model:SetAttribute("Arena", true)
model:SetAttribute("Origin", O)
model:SetAttribute("HomePosition", anchors.L6_Anchor_HomeBase.Position)   -- for the client's see-through marker
model:SetAttribute("ExitPosition", anchors.L6_Anchor_HomeBase.Position)   -- the way out is under the post
model:SetAttribute("ExitDoorPosition", exitAnchor.Position)               -- and, once you are down, the green door
model:SetAttribute("Level6Preview", true)
model:SetAttribute("PreviewOnly", true)
model:SetAttribute("Level6PreviewReady", true)
model:SetAttribute("Ready", true)
local count, textures = 0, 0
for _, d in ipairs(model:GetDescendants()) do
	if d:IsA("BasePart") then count += 1 elseif d:IsA("Texture") then textures += 1 end
end
local cf, size = model:GetBoundingBox()
local miss = {}
for name in pairs(missing) do miss[#miss + 1] = name end
return string.format("parts %d, textures %d, centre (%.0f, %.0f, %.0f), size (%.0f, %.0f, %.0f), missing from the kits: %s",
	count, textures, cf.X, cf.Y, cf.Z, size.X, size.Y, size.Z, table.concat(miss, " "))
'''

NAV = '''
local NAME = %s
local model = workspace:FindFirstChild(NAME)
local nav = model:FindFirstChild("NavGraph")
if not nav then nav = Instance.new("Folder"); nav.Name = "NavGraph"; nav.Parent = model end
if FIRST then nav:ClearAllChildren() end
local v = Instance.new("StringValue")
v.Name = string.format("Part_%%02d", INDEX)
v.Value = DATA
v.Parent = nav
nav:SetAttribute("Parts", INDEX)
return "nav part " .. INDEX .. ", " .. #DATA .. " characters"
'''


# Slide meshes that are not assets in their present form: AssetService:CreateAssetAsync answered "not available yet"
# when they were made or last changed, so their data is kept in ServerStorage and the game module builds them once
# per server (as it does the Counter's own mesh). A mesh is an asset when upload_arena_slides.py has recorded an id
# for exactly this data in arena_slide_ids.json; run that script when uploads work again and import once more.
def baked_names():
    import hashlib
    meshes = json.loads((EXPORT / 'slide_meshes.json').read_text())
    ids = Path(__file__).with_name('arena_slide_ids.json')
    known = json.loads(ids.read_text()) if ids.exists() else {}
    return tuple(name for name, mesh in meshes.items()
                 if known.get(name, {}).get('sha256') != hashlib.sha256(json.dumps(mesh, separators=(',', ':')).encode()).hexdigest())


BAKED = baked_names()
SOURCE = '''
local FIRST, INDEX, NAME = %s, %d, %s
local store = game:GetService("ServerStorage"):FindFirstChild("Level6ArenaSlideSource")
if not store then store = Instance.new("Folder"); store.Name = "Level6ArenaSlideSource"; store.Parent = game:GetService("ServerStorage") end
local item = store:FindFirstChild(NAME)
if FIRST and item then item:Destroy(); item = nil end
if not item then item = Instance.new("Folder"); item.Name = NAME; item.Parent = store end
local v = Instance.new("StringValue")
v.Name = string.format("Part_%%02d", INDEX)
v.Value = [==[%s]==]
v.Parent = item
item:SetAttribute("Parts", INDEX)
item:SetAttribute("Centre", Vector3.new(%s))
-- an older mesh of the same name in the slide kit would be placed instead of this one
local kit = game:GetService("ReplicatedStorage"):FindFirstChild(%s)
local old = kit and kit:FindFirstChild(NAME)
if old then old:Destroy() end
return NAME .. " part " .. INDEX .. ", " .. #v.Value .. " characters"
'''


def write_slide_source(studio, data, size=150000):
    meshes = json.loads((EXPORT / 'slide_meshes.json').read_text())
    centres = {name: c for name, c, yaw in data.get('slides', [])}
    print(studio.luau(f'''
local store = game:GetService("ServerStorage"):FindFirstChild("Level6ArenaSlideSource")
local keep, gone = {{{', '.join('[' + json.dumps(n) + '] = true' for n in BAKED)}}}, 0
for _, item in ipairs(store and store:GetChildren() or {{}}) do
	if not keep[item.Name] then item:Destroy(); gone += 1 end
end
return "slide sources no longer needed: " .. gone
'''), flush=True)
    for name in BAKED:
        if name not in centres:
            continue
        text = json.dumps(meshes[name], separators=(',', ':'))
        centre = ', '.join(format(v, 'g') for v in to_roblox(*centres[name]))
        for i, start in enumerate(range(0, len(text), size), 1):
            print(studio.luau(SOURCE % ('true' if i == 1 else 'false', i, json.dumps(name), text[start:start + size], centre,
                                        json.dumps(SLIDE_KIT))), flush=True)


def nav_payload():
    """The graph in Roblox studs relative to the model's origin, as integers of a tenth of a stud."""
    nav = json.loads((EXPORT / 'nav.json').read_text())

    def ten(p):
        return [round(v * 10) for v in to_roblox(*p)]
    nodes = [c for p in nav['nodes'] for c in ten(p)]
    edges = [[a, b] + [c for p in via for c in ten(p)] for a, b, via in nav['edges']]
    return json.dumps({'home': nav['home'], 'nodes': nodes, 'edges': edges, 'cells': nav['cells'], 'open': nav['open'],
                       'radii': nav['radii'], 'sectors': nav['sectors'], 'floorHeight': nav['floorHeight']}, separators=(',', ':'))


def write_nav(studio):
    text = nav_payload()
    size = 180000
    pieces = [text[i:i + size] for i in range(0, len(text), size)]
    for i, piece in enumerate(pieces, 1):
        code = (f'local FIRST, INDEX = {"true" if i == 1 else "false"}, {i}\nlocal DATA = [==[{piece}]==]\n'
                + NAV % json.dumps(MODEL_NAME))
        print(studio.luau(code), flush=True)


def main():
    data = json.loads((EXPORT / 'prims.json').read_text())
    mats = {}
    for key, rgb in data['palette'].items():
        material, transparency, collide = SURFACE.get(key, ('SmoothPlastic', 0, True))
        mats[key] = (tuple(srgb(c) for c in rgb), material, transparency, collide)
    for key, rgb in EXTRA_RGB.items():
        material, transparency, collide = SURFACE[key]
        mats[key] = (rgb, material, transparency, collide)
    mat_lua = ', '.join(f'{k} = {{Color3.fromRGB({c[0]}, {c[1]}, {c[2]}), Enum.Material.{m}, {t}, {str(col).lower()}}}'
                        for k, (c, m, t, col) in mats.items())
    tex_lua = ', '.join(f'{k} = {json.dumps(v)}' for k, v in TEXTURES.items())
    prelude = PRELUDE % (json.dumps(MODEL_NAME), *ORIGIN, mat_lua, ', '.join(json.dumps(n) for n in NO_COLLIDE), tex_lua,
                         json.dumps(SLIDE_KIT))
    facing = {'+x': (1, 0, 0), '-x': (-1, 0, 0), '+y': (0, 0, -1), '-y': (0, 0, 1)}
    signs = '\n'.join('|'.join([','.join(format(v, 'g') for v in to_roblox(*c)), format(w, 'g'), format(h, 'g'),
                                ','.join(map(str, facing[f])), text, ','.join(map(str, bg)), ','.join(map(str, fg)), tex])
                      for c, w, h, f, text, bg, fg, tex in data['signs'])
    rows = []
    for owner, kind, d, mat in data['prims']:
        if kind != 't' and mat not in mats:
            raise SystemExit(f'no surface for material {mat}')
        if kind == 'b':
            x0, y0, z0, x1, y1, z1 = d
            centre = to_roblox((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            nums = [*centre, round(abs(x1 - x0), 3), round(abs(z1 - z0), 3), round(abs(y1 - y0), 3)]
            if min(nums[3:]) < 0.01:
                continue
        elif kind == 'o':
            nums = [*to_roblox(*d[0:3]), d[3], d[4], d[5], d[6]]
        elif kind == 'p':
            ra, rb, delta, split, yaw, zc, thick = d
            nums = [ra, rb, delta, int(split), yaw, zc, thick]      # Blender's z is Studio's height; the angle turns the same way
        elif kind in ('c', 't'):
            if math.dist(d[0:3], d[3:6]) < 0.01:
                continue
            nums = [*to_roblox(*d[0:3]), *to_roblox(*d[3:6]), *d[6:]]      # radius, then a slide's pace and "no roof"
        elif kind == 'q':
            nums = [*to_roblox(*d[0:3]), *to_roblox(*d[3:6]), *to_roblox(*d[6:9])]
        elif kind == 's':
            nums = [*to_roblox(*d[0:3]), d[3]]
        else:
            continue
        rows.append(','.join([kind, owner, mat] + [format(v, 'g') for v in nums]))
    props = '\n'.join(','.join([name] + [format(v, 'g') for v in (*to_roblox(x, y, z), -yaw, size, collide)])
                      for name, x, y, z, yaw, size, collide in data.get('props', []))
    slides = '\n'.join(','.join([name] + [format(v, 'g') for v in (*to_roblox(*c), yaw)]) for name, c, yaw in data.get('slides', [])
                       if name not in BAKED)
    anchors = '\n'.join(','.join([name] + [format(v, 'g') for v in to_roblox(*loc)]) for name, loc in data['empties'])
    lights = '\n'.join(','.join([name] + [format(v, 'g') for v in to_roblox(*loc)] + [kind, format(rng, 'g'), format(bright, 'g'),
                                                                                    format(angle, 'g')] + [str(c) for c in rgb])
                       for name, loc, kind, rng, bright, angle, rgb in data['lights'])
    print(f'{len(rows)} primitives in {math.ceil(len(rows) / CHUNK)} calls, nav {len(nav_payload())} characters', flush=True)
    if '--dry' in sys.argv:
        return

    studio = Studio()
    if '--nav' in sys.argv:
        write_nav(studio)
        return
    if '--slide-source' in sys.argv:
        write_slide_source(studio, data)
        return
    if '--finish' in sys.argv:
        finish(studio, prelude, anchors, lights, signs, slides, props)
        write_slide_source(studio, data)
        return
    if '--only' in sys.argv:
        owner = sys.argv[sys.argv.index('--only') + 1]
        mine = [r for r in rows if r.split(',')[1] == owner]
        if not mine:
            raise SystemExit(f'no parts for group {owner}')
        print(studio.luau(f'''
local model = workspace:FindFirstChild({json.dumps(MODEL_NAME)})
local group = model and model:FindFirstChild({json.dumps(owner)})
if not group then return "no such group in the live model" end
local n = #group:GetChildren()
group:ClearAllChildren()
return "cleared " .. n
'''), flush=True)
        for start in range(0, len(mine), CHUNK):
            body = '\n'.join(mine[start:start + CHUNK])
            print(start, studio.luau(prelude + f'local DATA = [==[\n{body}\n]==]\n' + BUILD), flush=True)
        return
    print(studio.luau(f'''
local NAME = {json.dumps(MODEL_NAME)}
local old = workspace:FindFirstChild(NAME)
if old then old:Destroy() end
local model = Instance.new("Model")
model.Name = NAME
model:SetAttribute("Ready", false)
model.Parent = workspace
return "fresh model"
'''), flush=True)
    for start in range(0, len(rows), CHUNK):
        body = '\n'.join(rows[start:start + CHUNK])
        print(start, studio.luau(prelude + f'local DATA = [==[\n{body}\n]==]\n' + BUILD), flush=True)
    finish(studio, prelude, anchors, lights, signs, slides, props)
    write_slide_source(studio, data)


def finish(studio, prelude, anchors, lights, signs, slides, props):
    print(studio.luau(f'''
local model = workspace:FindFirstChild({json.dumps(MODEL_NAME)})
for _, name in ipairs({{"Anchors", "Lights", "ExitLights", "Signs", "Props", "Slides", "Level6Exit", "Finale_Glow"}}) do
	local old = model:FindFirstChild(name)
	if old then old:Destroy() end
end
return "cleared what the finish makes"
'''), flush=True)
    print(studio.luau(prelude + f'local ANCHORS = [==[\n{anchors}\n]==]\nlocal LIGHTS = [==[\n{lights}\n]==]\n'
                      f'local SIGNS = [==[\n{signs}\n]==]\nlocal SLIDES = [==[\n{slides}\n]==]\nlocal PROPS = [==[\n{props}\n]==]\n' + FINISH))
    write_nav(studio)


if __name__ == '__main__':
    main()
