"""Build the Level 6 playground in the open Studio place from export/prims.json, as native Parts.

    python3 tools/level6_playground/import_to_studio.py [--dry]

Talks to Studio through its own MCP proxy (StudioMCP, stdio JSON-RPC), so the geometry never passes
through a chat. Every call is one execute_luau; the first one replaces any earlier copy of the model.
Blender (x, y, z) studs become Roblox (x - 300, z, -(y - 200)) + ORIGIN.
"""
import json, math, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / 'artifacts' / 'level6-playground-20261002' / 'export'
STUDIO_MCP = '/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP'
MODEL_NAME = 'Level 6 Indoor Playground'
ORIGIN = (52000, 100, 0)
PLACE_HINT = 'BACKROOMS'
CHUNK = 1200

# material key -> (Enum.Material, transparency, can collide)
SURFACE = {
    'mat_green': ('SmoothPlastic', 0, True), 'mat_blue': ('SmoothPlastic', 0, True), 'concrete': ('Concrete', 0, True),
    'wall_yellow': ('Plaster', 0, True), 'wall_blue': ('Plaster', 0, True), 'wall_red': ('Plaster', 0, True),
    'wall_white': ('Plaster', 0, True), 'deck': ('Metal', 0, True), 'steel': ('Metal', 0, True),
    'duct': ('Metal', 0, True), 'pipe_red': ('Metal', 0, True), 'stainless': ('Metal', 0, True),
    'wood': ('Wood', 0, True), 'lamp_on': ('Neon', 0, True), 'lamp_warm': ('Neon', 0, True),
    'exit_sign': ('Neon', 0, True), 'lamp_magenta': ('Neon', 0, True), 'glass': ('Glass', 0.55, True),
    'mat_pink': ('Rubber', 0, True), 'mat_mint': ('Rubber', 0, True), 'inflate_a': ('Rubber', 0, True),
    'inflate_b': ('Rubber', 0, True), 'navy': ('Rubber', 0, True), 'carpet': ('Carpet', 0, True),
    'arcade_carpet': ('Carpet', 0, True), 'arcade_carpet2': ('Carpet', 0, True), 'floor_purple': ('Carpet', 0, True),
    'floor_pink': ('SmoothPlastic', 0, True), 'snack_a': ('SmoothPlastic', 0, True), 'snack_b': ('SmoothPlastic', 0, True),
    'wall_staff': ('Plaster', 0, True), 'wall_pink': ('Plaster', 0, True), 'wall_purple': ('Plaster', 0, True),
    'ceiling_tile': ('Plaster', 0, True), 'room_wall': ('Plaster', 0, True), 'ballsea': ('SmoothPlastic', 0, True), 'column': ('Plaster', 0, True), 'plant': ('Grass', 0, True), 'net_blue': ('Fabric', 0.6, True),
    'net_yellow': ('Fabric', 0.5, True), 'net_black': ('Fabric', 0.75, True),
}
EXTRA_RGB = {'lamp_magenta': (255, 40, 200), 'lamp_on': (255, 240, 205), 'lamp_warm': (255, 205, 120), 'exit_sign': (235, 30, 20),
             'net_blue': (20, 40, 150), 'net_yellow': (215, 170, 30), 'net_black': (12, 12, 12)}
NO_COLLIDE = ('Ceiling_', 'BallOcean_Balls', 'BallOcean_Surface', 'Hall_Balls', 'Toddler_Balls', 'Frame_Lamps', 'Frame_Rollers')
TEXTURES = json.loads((Path(__file__).with_name('textures.json')).read_text())

# Signs (SurfaceGuis) are listed by the build script and arrive in prims.json as data['signs'].


def srgb(v):
    v = max(0.0, min(1.0, v))
    return round(255 * (12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055))


def to_roblox(x, y, z):
    return (round(x - 300, 3), round(z, 3), round(-(y - 200), 3))


class Studio:
    def __init__(self):
        self.proc = subprocess.Popen([STUDIO_MCP], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.next_id = 0
        self.request('initialize', {'protocolVersion': '2024-11-05', 'capabilities': {},
                                    'clientInfo': {'name': 'level6-import', 'version': '1'}})
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
        text = self.call('list_roblox_studios', {})
        studios = json.loads(text)['studios']
        match = [s for s in studios if PLACE_HINT in s['name']]
        if len(match) != 1:
            raise SystemExit(f'expected one Studio with {PLACE_HINT!r}, found: {[s["name"] for s in studios]}')
        self.studio_id = match[0]['id']
        print('studio:', match[0]['name'], flush=True)

    def send(self, msg):
        self.proc.stdin.write(json.dumps(msg) + '\n')
        self.proc.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({'jsonrpc': '2.0', 'id': self.next_id, 'method': method, 'params': params})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise SystemExit('StudioMCP closed the pipe')
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get('id') == self.next_id:
                if 'error' in msg:
                    raise SystemExit(f'{method}: {msg["error"]}')
                return msg['result']

    def call(self, tool, args):
        res = self.request('tools/call', {'name': tool, 'arguments': args})
        text = '\n'.join(c.get('text', '') for c in res.get('content', []) if c.get('type') == 'text')
        if res.get('isError'):
            raise SystemExit(f'{tool} failed: {text[:600]}')
        return text

    def luau(self, code):
        return self.call('execute_luau', {'studio_id': self.studio_id, 'datamodel_type': 'Edit', 'code': code})


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
end
local KIT = game:GetService("ReplicatedStorage"):FindFirstChild("Level6PropKit")
-- one moulded mesh per slide (Level6Slides.glb); when it is there, the segment parts are only invisible colliders
local SLIDEKIT = game:GetService("ReplicatedStorage"):FindFirstChild("Level6SlideKit")
local SIDES = {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}
local VINYL = {yellow = true, red = true, blue = true, green = true, purple = true, pink = true, cyan = true, orange = true, navy = true}
local function tint(c, k)
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end
local function decorate(p, owner, mat)
	if string.sub(mat, 1, 4) == "net_" then
		local colour = p.Color
		-- a faint tinted sheet keeps the net readable even before (or without) the cord texture
		p.Transparency = owner == "Frame_RoofNet" and 0.97 or 0.9
		-- public knotted-net image (Creator Store decal 81104945973317); the cords are dark, so no tint
		texture(p, TEX.net, Enum.NormalId.Front, 5)
		texture(p, TEX.net, Enum.NormalId.Back, 5)
	elseif owner == "Floor_FoamTiles" then
		-- a neutral grey mat photo tinted with the tile's own colour
		texture(p, TEX.foam_mat, Enum.NormalId.Top, 12, tint(p.Color, 1.05))
	elseif owner == "BallOcean_Surface" then
		texture(p, TEX.ballpit, Enum.NormalId.Top, 7)      -- the printed balls match the loose ones in size
		for _, face in ipairs(SIDES) do texture(p, TEX.ballpit, face, 13) end
	elseif mat == "wall_staff" then
		for _, face in ipairs(SIDES) do texture(p, TEX.wallpaper_staff, face, 11) end
	elseif mat == "floor_pink" then
		texture(p, TEX.carpet_staff, Enum.NormalId.Top, 12, Color3.fromRGB(150, 70, 62))
	elseif mat == "carpet" then
		texture(p, TEX.carpet_staff, Enum.NormalId.Top, 12)
	elseif mat == "ceiling_tile" then
		texture(p, TEX.ceiling_tiles, Enum.NormalId.Bottom, 8)
	elseif mat == "arcade_carpet" or mat == "arcade_carpet2" then
		texture(p, TEX.arcade_carpet, Enum.NormalId.Top, 12)
	elseif mat == "room_wall" then
		for _, face in ipairs(SIDES) do texture(p, TEX.party_wall, face, 9, Color3.fromRGB(215, 205, 190)) end
	elseif mat == "floor_purple" then
		texture(p, TEX.carpet_staff, Enum.NormalId.Top, 12, Color3.fromRGB(200, 190, 175))
	elseif owner == "PartyRooms" and mat == "wall_blue" then
		for _, face in ipairs(SIDES) do texture(p, TEX.block_wall, face, 14, tint(p.Color, 1.1)) end
	elseif owner == "Ceiling_Structure" and mat == "deck" and p.Size.X > 100 then
		texture(p, TEX.roof_deck, Enum.NormalId.Bottom, 16, Color3.fromRGB(150, 150, 150))
	elseif owner == "Walls" or (owner == "Reception" and mat == "wall_yellow") or owner == "Inflatables" then
		for _, face in ipairs(SIDES) do texture(p, TEX.block_wall, face, 14, tint(p.Color, 1.1)) end
	elseif VINYL[mat] and owner ~= "Frame_Posts" and owner ~= "Frame_Beams" and owner ~= "BallOcean_Balls" and owner ~= "Toddler_Balls" then
		-- padded vinyl: the same grey photo, tinted
		local c = tint(p.Color, 1.2)
		texture(p, TEX.vinyl_pad, Enum.NormalId.Top, 7, c)
		for _, face in ipairs(SIDES) do texture(p, TEX.vinyl_pad, face, 7, c) end
	elseif owner == "SnackShack" or owner == "Reception" then
		for _, face in ipairs(SIDES) do texture(p, TEX.grime, face, 36, nil, 0.15) end
	end
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
	elseif kind == "c" or kind == "t" then
		local a, b = O + Vector3.new(n[1], n[2], n[3]), O + Vector3.new(n[4], n[5], n[6])
		local cf, len = along(a, b)
		local p
		local tubeMesh = kind == "t" and KIT and KIT:FindFirstChild("tube_segment")
		if tubeMesh then
			-- a real hollow tube section with a joint flange, tinted like the padding
			p = tubeMesh:Clone()
			p.Name, p.Anchored, p.CanTouch = mat, true, false
			p.Color, p.Material = MAT[mat][1], Enum.Material.SmoothPlastic
			p.Size = Vector3.new(len * 1.12, n[7] * 2.18, n[7] * 2.18)     -- overlap, so bends do not open gaps
			local skin = Instance.new("SurfaceAppearance")
			skin.ColorMap, skin.Color = TEX.vinyl_pad, tint(MAT[mat][1], 1.5)
			skin.Parent = p
		else
			p = part(owner, mat, Enum.PartType.Cylinder)
			p.Size = Vector3.new(len, n[7] * 2, n[7] * 2)
		end
		p.CFrame = cf
		if kind == "t" then
			-- the tube is only a shell to look at; an invisible trough inside is what you ride
			p.CanCollide = false
			p.CastShadow = false
			local r = n[7]
			local floor = part(owner, mat)
			floor.Name = "TubeFloor"
			floor.Transparency = 1
			floor.CanCollide = true
			floor.Size = Vector3.new(len + 0.6, 1, r * 1.3)
			floor.CFrame = cf * CFrame.new(0, -r * 0.75 - 0.5, 0)
			if owner == "Frame_Slides" then floor:SetAttribute("L6Slide", true) end
			floor.Parent = parent
			for _, side in ipairs({-1, 1}) do
				local wall = part(owner, mat)
				wall.Name = "TubeWall"
				wall.Transparency = 1
				wall.CanCollide = true
				wall.Size = Vector3.new(len + 0.6, r * 1.3, 0.4)
				wall.CFrame = cf * CFrame.new(0, -r * 0.2, side * r * 0.72)
				wall.Parent = parent
			end
		end
		if kind == "t" and SLIDEKIT then p:Destroy() else p.Parent = parent end
	elseif kind == "q" then
		local p0 = O + Vector3.new(n[1], n[2], n[3])
		local u = O + Vector3.new(n[4], n[5], n[6]) - p0
		local v = O + Vector3.new(n[7], n[8], n[9]) - p0
		local p = part(owner, mat)
		local normal = u.Unit:Cross(v.Unit)
		local cf = CFrame.fromMatrix(p0 + (u + v) / 2, u.Unit, v.Unit, normal)
		if owner == "Frame_WaveSlide" and math.abs(normal.Y) > 0.3 then   -- lanes, not the upright side rails
			-- slide lanes get real thickness below the riding surface and are marked for the slide client
			if normal.Y < 0 then normal = -normal end
			p.Size = Vector3.new(u.Magnitude, v.Magnitude, 0.8)
			p.CFrame = cf + -normal * 0.4
			p:SetAttribute("L6Slide", true)
		else
			p.Size = Vector3.new(u.Magnitude, v.Magnitude, 0.15)
			p.CFrame = cf
		end
		decorate(p, owner, mat)
		if owner == "Frame_WaveSlide" and SLIDEKIT then      -- the moulded chute is what you see; this is what you ride
			p.Transparency = 1
			p:ClearAllChildren()
		end
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
	local light = Instance.new("PointLight")
	light.Shadows = false
	if string.find(f[1], "Troffer") then
		-- a cone straight down: pools of light on the floor, the roof stays dark
		light:Destroy()
		light = Instance.new("SpotLight")
		light.Shadows, light.Face, light.Angle = false, Enum.NormalId.Bottom, 170
		light.Range, light.Brightness, light.Color = 70, 0.6, Color3.fromRGB(255, 240, 215)
	elseif string.find(f[1], "SnackBar") then
		light.Range, light.Brightness, light.Color = 30, 0.38, Color3.fromRGB(255, 214, 140)
	elseif string.find(f[1], "PartyBlock") then
		light.Range, light.Brightness, light.Color = 40, 1.1, Color3.fromRGB(255, 226, 180)
	elseif string.find(f[1], "Arcade") then
		light.Range, light.Brightness, light.Color = 34, 2.2, Color3.fromRGB(255, 50, 200)
	elseif string.find(f[1], "Staff") then
		light.Range, light.Brightness, light.Color = 20, 0.4, Color3.fromRGB(255, 220, 150)
	elseif string.find(f[1], "Reception") then
		light.Range, light.Brightness, light.Color = 60, 1.4, Color3.fromRGB(255, 235, 215)
	else
		light.Range, light.Brightness, light.Color = 26, 1.1, Color3.fromRGB(255, 225, 170)
	end
	light.Parent = p
	p.Parent = lights
end
local signs = folder("Signs")
local function nums(s)
	local t = {}
	for v in string.gmatch(s, "[^,]+") do t[#t + 1] = tonumber(v) end
	return t
end
for line in string.gmatch(SIGNS, "[^\\n]+") do
	local f = string.split(line, "|")
	local c, dir, bg, fg = nums(f[1]), nums(f[4]), nums(f[6]), nums(f[7])
	local w, h = tonumber(f[2]), tonumber(f[3])
	local out = Vector3.new(dir[1], dir[2], dir[3])
	local at = O + Vector3.new(c[1], c[2], c[3]) + out * 0.15
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = "Sign", true, false, false, false
	p.Size = Vector3.new(w, h, 0.2)
	-- printed boards, not screens: dusty, and lit only by the room
	p.Color, p.Material = Color3.fromRGB(bg[1] * 0.55, bg[2] * 0.55, bg[3] * 0.55), Enum.Material.SmoothPlastic
	p.CFrame = CFrame.lookAt(at, at + out)
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.SizingMode = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud, gui.LightInfluence = 40, 1
	local art = f[8] and f[8] ~= "" and TEX[f[8]]
	if art then
		p.Color = Color3.fromRGB(30, 30, 30)
		local image = Instance.new("ImageLabel")
		image.Size, image.BackgroundTransparency, image.Image = UDim2.fromScale(1, 1), 1, art
		image.ImageColor3 = Color3.fromRGB(215, 215, 215)
		image.Parent = gui
	end
	local label = Instance.new("TextLabel")
	label.Visible = not art
	label.Size, label.BackgroundTransparency = UDim2.fromScale(1, 1), 1
	label.Text = string.gsub(f[5], "\\\\n", "\\n")
	label.TextScaled, label.Font = true, Enum.Font.FredokaOne
	label.TextColor3 = Color3.fromRGB(fg[1] * 0.75, fg[2] * 0.75, fg[3] * 0.75)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.04, 0), UDim.new(0.04, 0)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0.08, 0), UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
	p.Parent = signs
end
local kit = game:GetService("ReplicatedStorage"):FindFirstChild("Level6PropKit")
local props = folder("Props")
local missing = {}
for line in string.gmatch(PROPS, "[^\\n]+") do
	local f = string.split(line, ",")
	local template = kit and kit:FindFirstChild(f[1])
	if template then
		local m = template:Clone()
		local longest = math.max(m.Size.X, m.Size.Y, m.Size.Z)
		m.Size = m.Size * (tonumber(f[6]) / longest)
		m.Anchored, m.CanCollide, m.CanTouch = true, f[7] == "1", false
		if f[1] == "pa_speaker" then m.Color, m.Material = Color3.fromRGB(150, 150, 140), Enum.Material.Metal end
		local base = O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4]))
		m.CFrame = CFrame.new(base + Vector3.new(0, m.Size.Y / 2, 0)) * CFrame.Angles(0, math.rad(tonumber(f[5])), 0)
		m.Parent = props
		if f[1] == "claw_machine" then
			-- the generated model has no glass: a pane box round the prize area, fitted to the placed mesh
			local glass = Instance.new("Part")
			glass.Name, glass.Anchored, glass.CanCollide, glass.CanTouch, glass.CanQuery = "Glass", true, false, false, false
			glass.Material, glass.Transparency, glass.Color = Enum.Material.Glass, 0.6, Color3.fromRGB(190, 225, 240)
			glass.Size = Vector3.new(m.Size.X * 0.9, m.Size.Y * 0.4, m.Size.Z * 0.9)
			glass.CFrame = m.CFrame * CFrame.new(0, m.Size.Y * 0.14, 0)
			glass.Parent = props
		end
	else
		missing[f[1]] = true
	end
end
if SLIDEKIT then
	local slides = folder("Slides")
	for line in string.gmatch(SLIDES, "[^\\n]+") do
		local f = string.split(line, ",")
		local template = SLIDEKIT:FindFirstChild(f[1])
		if template then
			local m = template:Clone()
			m.Anchored, m.CanCollide, m.CanTouch, m.CanQuery = true, false, false, false
			-- moulded, glossy plastic in one solid colour
			m.Material, m.Reflectance = Enum.Material.SmoothPlastic, 0
			m.Color = Color3.fromRGB(tonumber(f[5]), tonumber(f[6]), tonumber(f[7]))
			m.TextureID = ""
			local gloss = Instance.new("SurfaceAppearance")      -- plain colour, very low roughness: the shine
			gloss.ColorMap, gloss.RoughnessMap, gloss.Color = TEX.gloss_white, TEX.gloss_rough, m.Color
			gloss.Parent = m
			m.CFrame = CFrame.new(O + Vector3.new(tonumber(f[2]), tonumber(f[3]), tonumber(f[4])))
			m.Parent = slides
		else
			missing[f[1]] = true
		end
	end
end
local boards = folder("Boards")
for line in string.gmatch(BOARDS, "[^\\n]+") do
	local f = string.split(line, "|")
	local c, dir = nums(f[1]), nums(f[4])
	local out = Vector3.new(dir[1], dir[2], dir[3])
	local at = O + Vector3.new(c[1], c[2], c[3]) + out * 0.12
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = "Board_" .. f[5], true, false, false, false
	p.Size = Vector3.new(tonumber(f[2]), tonumber(f[3]), 0.2)
	p.Color, p.Material = Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic
	p.CFrame = CFrame.lookAt(at, at + out)
	local gui = Instance.new("SurfaceGui")
	gui.Face, gui.SizingMode, gui.PixelsPerStud = Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 30
	gui.LightInfluence = f[6] == "1" and 0 or 1
	if f[6] == "1" then gui.Brightness = 1.6 end
	local image = Instance.new("ImageLabel")
	image.Size, image.BackgroundTransparency, image.Image = UDim2.fromScale(1, 1), 1, TEX[f[5]]
	image.Parent = gui
	gui.Parent = p
	p.Parent = boards
end
-- Level6PreviewAccess lands developers on Level6Exit and mounts its RETURN TO LOBBY prompt there.
local spawn = anchors:FindFirstChild("L6_Anchor_Spawn")
local exit = Instance.new("Part")
exit.Name, exit.Anchored, exit.CanCollide, exit.CanTouch, exit.CanQuery = "Level6Exit", true, false, false, false
exit.Transparency, exit.Size = 1, Vector3.new(4, 1, 4)
local at = Vector3.new(spawn.Position.X, O.Y + 0.35 + 3.05, spawn.Position.Z)
exit.CFrame = CFrame.lookAt(at, at + Vector3.xAxis)
exit.Parent = model
model:SetAttribute("Source", "tools/level6_playground")
model:SetAttribute("HomePosition", anchors.L6_Anchor_HomeBase.Position)   -- for the client's see-through marker
model:SetAttribute("ExitPosition", anchors.L6_Anchor_Exit.Position)
model:SetAttribute("Level6Preview", true)
model:SetAttribute("PreviewOnly", true)
model:SetAttribute("Level6PreviewReady", true)
model:SetAttribute("Ready", true)
local count = 0
for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then count += 1 end end
local cf, size = model:GetBoundingBox()
local miss = {}
for name in pairs(missing) do miss[#miss + 1] = name end
return string.format("parts %d, centre (%.0f, %.0f, %.0f), size (%.0f, %.0f, %.0f), kit props missing: %s", count, cf.X, cf.Y, cf.Z, size.X, size.Y, size.Z, table.concat(miss, " "))
'''


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
    prelude = PRELUDE % (json.dumps(MODEL_NAME), *ORIGIN, mat_lua, ', '.join(json.dumps(n) for n in NO_COLLIDE), tex_lua)
    facing = {'+x': (1, 0, 0), '-x': (-1, 0, 0), '+y': (0, 0, -1), '-y': (0, 0, 1)}
    signs = '\n'.join('|'.join([','.join(format(v, 'g') for v in to_roblox(*c)), format(w, 'g'), format(h, 'g'),
                                ','.join(map(str, facing[f])), text.replace('\n', '\\n'), ','.join(map(str, bg)),
                                ','.join(map(str, fg)), tex]) for c, w, h, f, text, bg, fg, tex in data['signs'])

    rows = []
    for owner, kind, d, mat in data['prims']:
        if mat not in mats:
            raise SystemExit(f'no surface for material {mat}')
        if kind == 'b':
            x0, y0, z0, x1, y1, z1 = d
            centre = to_roblox((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            nums = [*centre, round(abs(x1 - x0), 3), round(abs(z1 - z0), 3), round(abs(y1 - y0), 3)]
            if min(nums[3:]) < 0.01:
                continue
        elif kind in ('c', 't'):
            if math.dist(d[0:3], d[3:6]) < 0.01:
                continue
            nums = [*to_roblox(*d[0:3]), *to_roblox(*d[3:6]), d[6]]
        elif kind == 'q':
            nums = [*to_roblox(*d[0:3]), *to_roblox(*d[3:6]), *to_roblox(*d[6:9])]
        elif kind == 's':
            nums = [*to_roblox(*d[0:3]), d[3]]
        else:
            continue
        rows.append(','.join([kind, owner, mat] + [format(v, 'g') for v in nums]))
    props = '\n'.join(','.join([name] + [format(v, 'g') for v in (*to_roblox(x, y, z), -yaw, size, collide)])
                      for name, x, y, z, yaw, size, collide in data.get('props', []))
    boards = '\n'.join('|'.join([','.join(format(v, 'g') for v in to_roblox(*c)), format(w, 'g'), format(h, 'g'),
                                 ','.join(map(str, facing[f])), tex, str(lit)]) for c, w, h, f, tex, lit in data.get('boards', []))
    slides = '\n'.join(','.join([name] + [format(v, 'g') for v in (*to_roblox(*c), *rgb)]) for name, c, size, rgb in data.get('slides', []))
    anchors = '\n'.join(','.join([name] + [format(v, 'g') for v in to_roblox(*loc)]) for name, loc in data['empties'])
    lights = '\n'.join(','.join([name] + [format(v, 'g') for v in to_roblox(*loc)]) for name, loc in data['lights'])
    print(f'{len(rows)} parts in {math.ceil(len(rows) / CHUNK)} calls', flush=True)
    if '--dry' in sys.argv:
        return

    studio = Studio()
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
    print(studio.luau(prelude + f'local ANCHORS = [==[\n{anchors}\n]==]\nlocal LIGHTS = [==[\n{lights}\n]==]\n'
                      f'local SIGNS = [==[\n{signs}\n]==]\nlocal SLIDES = [==[\n{slides}\n]==]\nlocal PROPS = [==[\n{props}\n]==]\nlocal BOARDS = [==[\n{boards}\n]==]\n' + FINISH))


if __name__ == '__main__':
    main()
