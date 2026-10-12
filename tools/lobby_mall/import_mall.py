"""Build Workspace.LobbyMallPreview in the open Studio place (Edit mode) from the Blender build's data.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup --threads 2 --python tools/lobby_mall/build_mall.py
    /usr/local/bin/python3 tools/lobby_mall/check_mall.py
    /usr/local/bin/python3 tools/lobby_mall/import_mall.py            # needs Pillow for the textures' mean colours

MALL_LOBBY_20261012. Native Parts from `artifacts/lobby-mall-20261011/build/mall.json`, moved by OFFSET so the new
lobby stands BESIDE the present one (owner: "place it out and beside the existing lobby so we as DEVs can noclip out
and look at it"). Signs are SurfaceGuis in the owner's sign style (cream box, dark grey condensed bold: Oswald Bold is
Roblox's nearest face to DIN Condensed Bold). Lights are made from the data's list. Under `Anchors` the model carries
what the game's systems will be wired to: `QueueBays` (three round zones a level with LevelNumber, QueueDisplayIndex
and QueueRadius; NOT yet R3 queue zones, so the live lobby's queue is untouched), `ShopSpots` (ProductKey),
`SkinPlinths` (SkinId; the game's own suit model stands on each when its template is in ServerStorage), `Boards`
(blank faces for the leaderboards) and markers for the spawn, the DJ console, the stage, the tape and the dark wing.
Textured materials are shown in their texture's mean colour until the maps are uploaded (`texture_ids.json` beside
this file, key -> {"colour": id, "normal": id, "roughness": id}, makes MaterialVariants `Mall <key>`).
"""
import json, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

BUILD = ROOT / 'artifacts' / 'lobby-mall-20261011' / 'build'
OFFSET = (300, 0, 0)
NAME = 'LobbyMallPreview'
data = json.loads((BUILD / 'mall.json').read_text())
ids_file = Path(__file__).parent / 'texture_ids.json'
TEXTURES = json.loads(ids_file.read_text()) if ids_file.exists() else {}

TILE = {}                      # studs a texture sheet, where the build's own number is not wanted
materials = {}
for key, m in data['materials'].items():
    mean = None
    if m.get('colour_map'):
        im = Image.open(BUILD / m['colour_map']).convert('RGB').resize((1, 1), Image.BOX)
        mean = list(im.getpixel((0, 0)))
    materials[key] = {'base': m['base'], 'mean': mean, 'tile': TILE.get(key) or m.get('studs_per_tile') or 4, 'ids': TEXTURES.get(key)}

# MALL_FINISH_20261013 (owner: "randomly sluk flere lys i loftet og lad nogle blinke at random som en døende
# fluorescent lampe"). Of the hall's lit panels, six more are dead and five flicker (the build's one dim panel too);
# the draw is seeded, so a re-import gives the same ceiling. A dead panel's lens is grey like the build's own dead
# ones and it has no lamp and no sheen; a flickering one keeps its lamp, and Lobby Mall Client makes it stutter.
import random
panels = [l for l in data['lights'] if l['kind'] == 'panel']
steady = [l for l in panels if l['state'] == 'on']
pick = random.Random(20261013).sample(steady, 11)
for l in pick[:6]: l['state'] = 'dead'
# FLICKER_ONLY_PAST_TAPE_20261013 (owner: "The lights in the lobby should only flicker past the do not cross point").
# In the hall every lamp that is on is steady (five drawn above used to flicker, and the build's one dim panel);
# the six dead ones stay dead. Only the dark wing's five panels are dying tubes.
tape = data['anchors']['tape_z']
for l in panels:
    if l['state'] == 'dim_flicker': l['state'] = 'flicker' if l['pos'][2] > tape else 'on'
# DIMMER_20261013 (owner: "dim the lights down by 30% in the lobby and make some light be even darker"). Five of the
# hall's seventeen lit panels (a second seeded draw) are tired tubes: a third of a lamp's light, a duller lens, a
# faint sheen. They are steady: only the wing flickers. The other lamps and the hall's ambient light are turned down
# in the Luau below and in RoundUI.
for l in random.Random(20261014).sample([l for l in panels if l['state'] == 'on' and l['pos'][2] <= tape], 5): l['dim'] = True
by_name = {p['name']: p for p in data['parts']}
for l in panels: l['wing'] = l['pos'][2] > data['anchors']['tape_z']

# BOOTH_FROM_TUNNEL_20261013 (owner: "Replace the new DJ booth in the mall lobby with the DJ booth from the live tunnel
# lobby as it's much better"). The build's own deck, steps, folding table, console and speakers are not put in the
# place; the tunnel lobby's booth (install_booth.py made it permanent assets) stands where they stood, and it stood on
# the same spot in the tunnel. The banner and the chairs stay. The .blend still holds the build's own booth.
BOOTH = json.loads((Path(__file__).parent / 'booth_ids.json').read_text())
REPLACED = ('StageDeck', 'StageStep', 'DJTable', 'DJConsole', 'DJTurntable', 'Speaker')
data['parts'] = [p for p in data['parts'] if not (p['group'] == 'Stage' and p['name'].startswith(REPLACED))]

# DARK_FADE_20261013 (owner: the end "fading into darkness, so some of the start is visible ... but like it fades down
# to darkness"). A part's colour is one colour, so the wing's long floors, walls and ceilings are cut across into
# lengths of twenty studs or less; the importer then darkens each by how far past the tape it stands. A material's
# sheet is laid from the world's origin, so a cut shows no seam.
def slices(p):
    wing = p['group'] == 'DarkWing' or p['name'].startswith('Dark')
    if not (wing and p['shape'] == 'Block' and p['rot'] == [0.0, 0.0, 0.0] and p['size'][2] > 24):
        return [p]
    n = int(-(-p['size'][2] // 20))
    step, start = p['size'][2] / n, p['pos'][2] - p['size'][2] / 2
    return [dict(p, name=f"{p['name']}_s{k}", pos=[p['pos'][0], p['pos'][1], start + step * (k + 0.5)],
                 size=[p['size'][0], p['size'][1], step]) for k in range(n)]
data['parts'] = [piece for p in data['parts'] for piece in slices(p)]

# CITY_CARPET_20261013 (owner: "For the level 3 I specifically want the city car carpet on the floor"). MALL PARTY's
# queue floor and showcase floor become ONE part, so that Level 3's own carpet picture (a Texture, 52 studs a repeat,
# as Level 3 World Builder lays it) runs across the whole shop without restarting at a seam.
shop3 = [p for p in data['parts'] if p['name'] in ('Shop3_QueueFloor', 'Shop3_ShowFloor')]
assert len(shop3) == 2
lo = min(p['pos'][0] - p['size'][0] / 2 for p in shop3); hi = max(p['pos'][0] + p['size'][0] / 2 for p in shop3)
data['parts'] = [p for p in data['parts'] if p not in shop3]
data['parts'].append(dict(shop3[0], name='Shop3_Floor', pos=[(lo + hi) / 2, shop3[0]['pos'][1], shop3[0]['pos'][2]],
                          size=[hi - lo, shop3[0]['size'][1], shop3[0]['size'][2]], city_carpet=True))
dark = next(p for p in data['parts'] if p['name'].startswith('PanelLens') and not p['glow'])
for l in panels:
    lens = by_name[l['name'].replace('PanelLight', 'PanelLens')]
    l['lens'] = lens['name']
    if l['state'] == 'dead':
        lens['glow'], lens['material'], lens['color'] = False, dark['material'], dark['color']
data['lights'] = [l for l in data['lights'] if l['state'] != 'dead']
print('ceiling panels:', {s: sum(1 for l in panels if l['state'] == s) for s in ('on', 'flicker', 'dead')})

s = studio_io.Studio()
J = lambda v: json.dumps(v, separators=(',', ':'))

print(s.luau('''
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local old = workspace:FindFirstChild("%s")
if old then old:Destroy() end
local model = Instance.new("Model")
model.Name = "%s"
model:SetAttribute("MallLobbyBuild", "MALL_LOBBY_20261012")
model:SetAttribute("Offset", Vector3.new(%s))
model:SetAttribute("BoundsMin", Vector3.new(%s))
model:SetAttribute("BoundsMax", Vector3.new(%s))
for _, name in ipairs({"Parts", "Lights", "Anchors"}) do
	local f = Instance.new("Folder"); f.Name = name; f.Parent = model
end
model.Parent = workspace
local MaterialService = game:GetService("MaterialService")
local made = 0
for key, m in pairs(game:GetService("HttpService"):JSONDecode([==[%s]==])) do
	if m.ids and m.ids.colour then
		local v = MaterialService:FindFirstChild("Mall " .. key) or Instance.new("MaterialVariant")
		v.Name, v.BaseMaterial = "Mall " .. key, Enum.Material[m.base]
		v.ColorMap = "rbxassetid://" .. m.ids.colour
		if m.ids.normal then v.NormalMap = "rbxassetid://" .. m.ids.normal end
		if m.ids.roughness then v.RoughnessMap = "rbxassetid://" .. m.ids.roughness end
		v.StudsPerTile = m.tile
		v.Parent = MaterialService
		made += 1
	end
end
return "model ready, material variants " .. made
''' % (NAME, NAME, ', '.join(map(str, OFFSET)), *(', '.join(str(v + o) for v, o in zip(data['bounds'][k], OFFSET)) for k in ('min', 'max')), J(materials))))

PARTS = '''
local HttpService = game:GetService("HttpService")
local model = workspace:FindFirstChild("%s")
local holder = model.Parts
local mats = HttpService:JSONDecode([==[%s]==])
local offset = Vector3.new(%s)
local n = 0
for _, p in ipairs(HttpService:JSONDecode([==[%s]==])) do
	local group = holder:FindFirstChild(p.group)
	if not group then group = Instance.new("Folder"); group.Name = p.group; group.Parent = holder end
	local part
	if p.shape == "Wedge" then part = Instance.new("WedgePart") else
		part = Instance.new("Part")
		part.Shape = p.shape == "Cylinder" and Enum.PartType.Cylinder or p.shape == "Ball" and Enum.PartType.Ball or Enum.PartType.Block
	end
	part.Name = p.name
	-- a station's pole and plate stand on the straight line from the hall to its pad: on foot (2026-10-12) the
	-- character walked into the pole and stopped. The round base still collides.
	local thin = p.name:find("StationPost", 1, true) or p.name:match("_Station%%d+_") ~= nil
	part.Anchored, part.CanCollide, part.CanTouch = true, p.collide == true and not thin, false
	-- MALL_LIGHT_20261012: nothing in here throws a shadow (no lamp has Shadows on and there is no sun indoors),
	-- so no part is a shadow caster; and a part nobody collides with is not in the way of any raycast either
	part.CastShadow = false
	if not part.CanCollide then part.CanQuery = false end
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
	part.CFrame = CFrame.new(Vector3.new(p.pos[1], p.pos[2], p.pos[3]) + offset)
		* CFrame.fromOrientation(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
	local m = mats[p.material]
	part.Material = p.glow and Enum.Material.Neon or Enum.Material[m.base]
	local c = p.color
	if m.mean and not (m.ids and m.ids.colour) and c[1] > 250 and c[2] > 250 and c[3] > 250 then c = m.mean end
	part.Color = Color3.fromRGB(c[1], c[2], c[3])
	-- the hall is lit by ambient light now (see the lights below), which a wall cannot switch off: the wing past
	-- the tape is dark because its own surfaces are
	-- DARK_FADE_20261013: full colour at the tape, two thirds of it forty studs in, a third at eighty, black from a
	-- hundred and fifty (the wing is two hundred long)
	if p.group == "DarkWing" or p.name:sub(1, 4) == "Dark" then
		local shade = math.max(0.02, (1 - math.clamp((p.pos[3] - TAPE_Z) / 150, 0, 1)) ^ 1.5)
		part.Color = Color3.new(part.Color.R * shade, part.Color.G * shade, part.Color.B * shade)
	end
	if m.ids and m.ids.colour and not p.glow then part.MaterialVariant = "Mall " .. p.material end
	part.Transparency = p.transparency or 0
	part:SetAttribute("MallMaterial", p.material)
	if p.city_carpet then
		local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Level 3 Assets")
		local slot = assets and assets:FindFirstChild("CityPlayCarpetTexture")
		part.Material, part.MaterialVariant, part.Color = Enum.Material.Carpet, "", Color3.fromRGB(190, 188, 166)
		local carpet = Instance.new("Texture")
		carpet.Name, carpet.Face = "CityCarpet", Enum.NormalId.Top
		carpet.Texture = (slot and slot:IsA("StringValue") and slot.Value ~= "") and slot.Value or "rbxassetid://75635502248205"
		carpet.StudsPerTileU, carpet.StudsPerTileV = 52, 52
		carpet.Parent = part
	end
	part.Parent = group
	n += 1
end
return n
'''
PARTS = PARTS.replace('TAPE_Z', str(data['anchors']['tape_z']))
parts = data['parts']
done = 0
for i in range(0, len(parts), 180):
    done += int(float(s.luau(PARTS % (NAME, J(materials), ', '.join(map(str, OFFSET)), J(parts[i:i + 180])))))
print('parts', done, 'of', len(parts))

print(s.luau('''
local HttpService = game:GetService("HttpService")
local model = workspace:FindFirstChild("%s")
local byName = {}
for _, d in ipairs(model.Parts:GetDescendants()) do if d:IsA("BasePart") then byName[d.Name] = d end end
local FACE = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
local INK = Color3.fromRGB(72, 66, 54)
local function faceFor(part, normal)
	local best, bestDot = Enum.NormalId.Front, -2
	for _, id in ipairs(Enum.NormalId:GetEnumItems()) do
		local dot = part.CFrame:VectorToWorldSpace(Vector3.FromNormalId(id)):Dot(normal)
		if dot > bestDot then best, bestDot = id, dot end
	end
	return best
end
local CREAM, PLATE = Color3.fromRGB(236, 226, 160), Color3.fromRGB(226, 216, 178)
local TALL = {box = 1.3, station = 1.15, plain = 1.2, banner = 1.1, tape = 1.25}   -- label height over the sign's: Oswald's capitals are ~42%% of its line
local function gui(part, face, sign)
	local h = sign.size[2]
	local tall = TALL[sign.style] or 1.1
	-- TextScaled stops at 100 px: keep the label near 145 px high so the lettering really fills the sign
	local pps = math.clamp(math.floor(145 / (tall * h)), 12, 220)
	-- the tape is 71 studs long: at the 220 px a stud its 0.46 height asks for, each face was a 15,840 px canvas
	if sign.style == "tape" then pps = 70 end
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.SizingMode, g.PixelsPerStud = "MallSign", face, Enum.SurfaceGuiSizingMode.PixelsPerStud, pps
	g.ClipsDescendants = true
	local lit = sign.style == "box" or sign.style == "station"
	g.LightInfluence = lit and 0 or sign.style == "plain" and 0.35 or 1
	-- a sign is not drawn from further than it can be read
	g.MaxDistance = ({box = 260, station = 110, plain = 45, banner = 160, tape = 130})[sign.style] or 120
	if sign.style ~= "tape" and sign.style ~= "banner" then
		-- the face itself: a backlit cream box, brighter toward the middle (the owner's sign reference)
		local back = Instance.new("Frame")
		back.Name, back.Size, back.BorderSizePixel = "Face", UDim2.fromScale(1, 1), 0
		back.BackgroundColor3 = lit and CREAM or PLATE
		if lit then
			local grade = Instance.new("UIGradient")
			grade.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(238, 236, 224)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(238, 236, 224))})
			grade.Parent = back
		end
		back.Parent = g
	end
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency, label.FontFace, label.TextColor3 = 1, FACE, sign.style == "tape" and Color3.fromRGB(20, 18, 14) or INK
	label.AnchorPoint, label.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(sign.style == "tape" and 1 or 0.95, tall)
	-- one centred line, as on the reference: no-break spaces, because TextScaled wraps to two lines when that is
	-- bigger, and TextWrapped = false with TextScaled draws the text as a dot (seen in play 2026-10-12)
	label.TextScaled, label.Text = true, (sign.text:gsub(" ", utf8.char(160)))
	label.Parent = g
	g.Parent = part
end
local n, missing = 0, {}
for _, sign in ipairs(HttpService:JSONDecode([==[%s]==])) do
	local part = byName[sign.part]
	if part then
		local normal = Vector3.new(sign.normal[1], sign.normal[2], sign.normal[3])
		local face = faceFor(part, normal)
		gui(part, face, sign)
		if sign.style == "tape" then gui(part, faceFor(part, -normal), sign) end
		if sign.style == "box" or sign.style == "station" then part.Material, part.Color = Enum.Material.SmoothPlastic, CREAM end
		part:SetAttribute("MallSign", sign.style)
		n += 1
	else
		missing[#missing + 1] = sign.name
	end
end
-- the pads' pale ring (the build's ring is a texture; a material cannot be centred on a disc)
local rings = 0
for _, d in ipairs(model.Parts:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("MallMaterial") == "pad" then
		local g = Instance.new("SurfaceGui")
		g.Name, g.Face, g.SizingMode, g.PixelsPerStud = "PadRing", faceFor(d, Vector3.yAxis), Enum.SurfaceGuiSizingMode.PixelsPerStud, 24
		g.MaxDistance = 120
		g.LightInfluence = 1
		local ring = Instance.new("Frame")
		ring.AnchorPoint, ring.Position, ring.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.9, 0.9)
		ring.BackgroundTransparency = 1
		local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0.5, 0); corner.Parent = ring
		local stroke = Instance.new("UIStroke"); stroke.Thickness, stroke.Color = 7, Color3.fromRGB(150, 178, 140); stroke.Parent = ring
		ring.Parent = g
		g.Parent = d
		rings += 1
	end
end
return "signs " .. n .. ", pad rings " .. rings .. (#missing > 0 and (" MISSING " .. table.concat(missing, ",")) or "")
''' % (NAME, J(data['signs']))))

print(s.luau('''
local model = workspace:FindFirstChild("%s")
local offset = Vector3.new(%s)
local FLOOR_Y, SHEEN = %s, %s
local PANEL_ON, PANEL_DIM = 1.5, 0.4
local n = 0
for _, l in ipairs(game:GetService("HttpService"):JSONDecode([==[%s]==])) do
	local host = Instance.new("Part")
	host.Name, host.Anchored, host.CanCollide, host.CanTouch, host.CanQuery = l.name, true, false, false, false
	host.Transparency, host.Size = 1, Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(Vector3.new(l.pos[1], l.pos[2], l.pos[3]) + offset) * CFrame.Angles(math.rad(-90), 0, 0)   -- front face down
	-- the build's lamp colours are pictures' colours; as light on yellow walls they turned the hall into mustard
	local colour = Color3.fromRGB(l.color[1], l.color[2], l.color[3]):Lerp(Color3.fromRGB(255, 246, 224), l.kind == "neon" and 0 or 0.6)
	-- the data's brightness is Blender's: the square root keeps the build's order (product lamp < skin spot < shop wash)
	-- MALL_LIGHT_20261012 (owner: "make sure that it doesnt fuck with load speed, client FPS"). The hall's light
	-- is AMBIENT now (RoundUI raises Lighting.Ambient inside the mall), which costs nothing and looks the same on a
	-- phone at graphics level 1, where the engine drops most local lamps: at a lower level the first version's
	-- ceiling went black. Lamps are only pools on top of that: ONE PointLight a lit panel (it lights the floor and
	-- the ceiling round it; it was a SpotLight down plus a PointLight up), one a shop, the cinema's, the Void's and
	-- a spot on each suit. The counters' product lamps and the stand's globes have none: the globes are Neon.
	local skip = l.name:sub(1, 12) == "ProductLight" or l.name:sub(1, 9) == "StandLamp"
	local strength = 0.21 * math.sqrt(l.brightness)          -- DIMMER_20261013: every lamp 30 percent down
	local light
	if skip then
		light = nil
	elseif l.kind == "panel" then
		if l.wing then
			light = Instance.new("PointLight")
			light.Brightness, light.Range = 1.3, 50            -- past the tape a lamp is most of the light there is
		else
			-- DIMMER_20261013: a cone down from 27 studs up, so that a tired tube leaves a darker stretch of hall
			-- under it (a PointLight that high gave the floor next to nothing, and the hall was all ambient)
			light = Instance.new("SpotLight")
			light.Face, light.Angle, light.Range = Enum.NormalId.Front, 125, 60
			light.Brightness = l.dim and PANEL_DIM or PANEL_ON
		end
		host.CFrame = host.CFrame - Vector3.new(0, 1.6, 0)
	elseif l.name:sub(1, 8) == "SkinSpot" then
		light = Instance.new("SpotLight")
		light.Face, light.Angle = Enum.NormalId.Front, 70
		light.Brightness, light.Range = 1.0, l.range
	else
		light = Instance.new("PointLight")
		light.Brightness, light.Range = strength, math.min(l.range, 40)
	end
	if light then
		light.Color, light.Shadows = colour, false
		light.Parent = host
	end
	if l.dim then
		local lens = model.Parts.Ceiling:FindFirstChild(l.lens)
		if lens then lens.Color = Color3.fromRGB(150, 144, 118) end
		host:SetAttribute("Dim", true)
	end
	-- FLOOR_GLOSS_20261012 (owner: the floor tiles "skal være glossy"). The tile's roughness map is glossy, but
	-- the engine draws no reflection of a lamp in a floor here. So every lit panel lays a soft sheen on the tiles
	-- under it: one small picture on an unseen plate, stretched down the hall as a lamp's streak is.
	if l.kind == "panel" and l.state == "on" and SHEEN then
		local plate = Instance.new("Part")
		plate.Name, plate.Anchored, plate.CanCollide, plate.CanTouch, plate.CanQuery, plate.CastShadow = "PanelSheen", true, false, false, false, false
		plate.Transparency, plate.Size = 1, Vector3.new(7, 0.04, 15)
		plate.CFrame = CFrame.new(l.pos[1] + offset.X, FLOOR_Y + 0.03, l.pos[3] + offset.Z)
		local g = Instance.new("SurfaceGui")
		g.Name, g.Face, g.SizingMode, g.CanvasSize = "Sheen", Enum.NormalId.Top, Enum.SurfaceGuiSizingMode.FixedSize, Vector2.new(64, 64)
		g.LightInfluence, g.Brightness, g.MaxDistance, g.Active = 0, 1, 170, false
		local picture = Instance.new("ImageLabel")
		picture.BackgroundTransparency, picture.Size, picture.Image = 1, UDim2.fromScale(1, 1), SHEEN
		picture.ImageColor3, picture.ImageTransparency = Color3.fromRGB(255, 252, 240), l.dim and 0.8 or 0.4
		picture.Parent = g
		g.Parent = plate
		plate.Parent = model.Lights
	end
	host:SetAttribute("MallLight", l.kind)
	if l.state == "flicker" then host:SetAttribute("Flicker", true); host:SetAttribute("Lens", l.lens) end
	if light then
		host.Parent = model.Lights
		n += 1
	end
end
return "lights " .. n
''' % (NAME, ', '.join(map(str, OFFSET)), data['anchors']['spawn'][1], ('"rbxassetid://%d"' % TEXTURES['sheen']['colour']) if TEXTURES.get('sheen') else 'nil', J(data['lights']))))

print(s.luau('''
local model = workspace:FindFirstChild("%s")
local offset = Vector3.new(%s)
local a = game:GetService("HttpService"):JSONDecode([==[%s]==])
local anchors = model.Anchors
local function v3(t) return Vector3.new(t[1], t[2], t[3]) + offset end
local function marker(parent, name, pos, size)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Transparency = name, true, false, false, false, 1
	p.Size, p.CFrame = size or Vector3.new(1, 1, 1), CFrame.new(pos)
	p.Parent = parent
	return p
end
local function folder(name) local f = Instance.new("Folder"); f.Name = name; f.Parent = anchors; return f end
-- queue bays: what QueueBridge.BuildMall reads. One bay Model a pad (the engine puts a turned-away player back
-- inside the bay's diameter), the zone turned so its front looks at the concourse (a cancelled host is set down
-- five studs in front of it), and a hanging dot-matrix board as the render owner with the two lines the engine writes.
local bays = folder("QueueBays")
local AMBER = Color3.fromRGB(255, 176, 60)
local MONO = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
for _, pad in ipairs(a.pads) do
	local at = v3(pad.pos)
	local out = Vector3.new(pad.pos[1] < a.spawn[1] and 1 or -1, 0, 0)
	local bay = Instance.new("Model")
	bay.Name = string.format("QueueBay_L%%d_S%%d", pad.level, pad.station)
	bay:SetAttribute("LevelNumber", pad.level)
	bay:SetAttribute("CircularBayDiameter", 26)
	bay.Parent = bays
	marker(bay, "ChamberFloor", at, Vector3.new(26, 0.1, 26))
	local zone = marker(bay, "QueueZone", at + Vector3.new(0, 0.4, 0), Vector3.new(pad.radius * 2, 1, pad.radius * 2))
	zone.CFrame = CFrame.lookAt(zone.Position, zone.Position + out)
	zone.Color = AMBER
	zone:SetAttribute("MallQueueId", 200 + (pad.level - 1) * 4 + pad.station)
	zone:SetAttribute("LevelNumber", pad.level)
	zone:SetAttribute("QueueDisplayIndex", pad.station)
	zone:SetAttribute("QueueRadius", pad.radius)
	zone:SetAttribute("QueueDetectorShape", "Circle")
	local render = Instance.new("Model")
	render.Name = "QueueRender"
	render.Parent = bay
	local board = Instance.new("Part")
	board.Name, board.Anchored, board.CanCollide, board.CanTouch, board.CanQuery = "QueueBoard", true, false, false, false
	board.Material, board.Color, board.Size = Enum.Material.SmoothPlastic, Color3.fromRGB(18, 16, 14), Vector3.new(9.6, 2.7, 0.35)
	board.CFrame = CFrame.lookAt(at + Vector3.new(0, 9.2, 0), at + Vector3.new(0, 9.2, 0) + out)
	board.Parent = render
	for side = -1, 1, 2 do
		local rod = Instance.new("Part")
		rod.Name, rod.Anchored, rod.CanCollide, rod.CanTouch, rod.CanQuery = "QueueBoardRod", true, false, false, false
		rod.Material, rod.Color, rod.Size = Enum.Material.Metal, Color3.fromRGB(62, 58, 46), Vector3.new(0.14, 2.4, 0.14)
		rod.CFrame = board.CFrame * CFrame.new(side * 4.2, 2.55, 0)
		rod.Parent = render
	end
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.SizingMode, g.PixelsPerStud, g.LightInfluence, g.Brightness = "QueueDisplay", Enum.NormalId.Front, Enum.SurfaceGuiSizingMode.PixelsPerStud, 50, 0, 1.4
	g.MaxDistance = 130
	local function line(name, y, h, text)
		local l = Instance.new("TextLabel")
		l.Name, l.BackgroundTransparency, l.FontFace, l.TextColor3 = name, 1, MONO, AMBER
		l.AnchorPoint, l.Position, l.Size = Vector2.new(0.5, 0), UDim2.fromScale(0.5, y), UDim2.fromScale(0.94, h)
		l.TextScaled, l.Text = true, text
		l.Parent = g
		return l
	end
	line("QueueTitle", 0.07, 0.5, "STATION " .. pad.station .. "  •  0/6")
	line("QueueSubtitle", 0.62, 0.28, "STEP ON THE PAD")
	g.Parent = board
	local ref = Instance.new("ObjectValue")
	ref.Name, ref.Value = "QueueRenderOwner", render
	ref.Parent = zone
end
local spots = folder("ShopSpots")
-- a buy spot: LobbyShopDisplay opens the item's card for whoever stands within 1.9 studs of it; a pale ring on the
-- carpet says where
for _, spot in ipairs(a.shop_spots) do
	local m = marker(spots, spot.key, v3(spot.pos), Vector3.new(3.8, 0.2, 3.8))
	m:SetAttribute("ShopItemKey", spot.key)
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.SizingMode, g.PixelsPerStud, g.LightInfluence = "SpotRing", Enum.NormalId.Top, Enum.SurfaceGuiSizingMode.PixelsPerStud, 30, 1
	g.MaxDistance = 70
	local ring = Instance.new("Frame")
	ring.AnchorPoint, ring.Position, ring.Size, ring.BackgroundTransparency = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.86, 0.86), 1
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0.5, 0); corner.Parent = ring
	local stroke = Instance.new("UIStroke"); stroke.Thickness, stroke.Color, stroke.Transparency = 4, Color3.fromRGB(236, 226, 160), 0.25; stroke.Parent = ring
	ring.Parent = g
	g.Parent = m
end
local boards = folder("Boards")
for _, b in ipairs(a.boards) do
	local normal = Vector3.new(b.normal[1], b.normal[2], b.normal[3])
	local p = marker(boards, b.key, v3(b.pos), Vector3.new(b.size[1], b.size[2], 0.1))
	p.CFrame = CFrame.lookAt(v3(b.pos), v3(b.pos) + normal)
	p:SetAttribute("BoardKey", b.key)
end
marker(anchors, "Spawn", v3(a.spawn))
-- BOOTH_FROM_TUNNEL_20261013: the tunnel lobby's DJ booth, on the spot it had there (measured from the same centre the
-- tunnel lobby used). The console is `Anchors.DJConsole`, the desk Lobby DJ stands its DJ behind; the deck and its
-- six steps are walked on through unseen blocks, as in the tunnel. Lobby Mall Client turns the two discs.
do
	local AssetService = game:GetService("AssetService")
	local booth = game:GetService("HttpService"):JSONDecode([==[%s]==])
	local centre = Vector3.new(a.spawn[1], a.spawn[2], a.spawn[3] + 100) + offset
	local visuals = model.Parts:FindFirstChild("Stage")
	local function piece(family, at, yaw, parent, solid)
		local spec = booth[family]
		local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(spec.id), {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise})
		local cf = CFrame.new(centre + at) * CFrame.Angles(0, yaw, 0)
		part.Name, part.Size = family, Vector3.new(spec.size[1], spec.size[2], spec.size[3])
		part.CFrame = cf * CFrame.new(spec.centre[1], spec.centre[2], spec.centre[3])
		part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, solid, false, solid, false
		part.Material, part.Color, part.DoubleSided = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1), true
		part.TextureID = "rbxassetid://" .. booth.atlas
		part.Parent = parent
		return part, cf
	end
	piece("StageDeck", Vector3.new(0, 0, 120), 0, visuals, false)
	piece("StageRearRail", Vector3.new(0, 0, 120), 0, visuals, false)
	piece("DJConsole", Vector3.new(0, 4.5, 121), math.pi, anchors, true)
	for _, side in ipairs({-21, 21}) do
		piece("SpeakerTower", Vector3.new(side, 0, 120), math.pi, visuals, true)
		piece("Subwoofer", Vector3.new(side, 0, 114), math.pi, visuals, true)
	end
	for family, at in pairs({VinylDiscAmber = Vector3.new(2.96, 8.273, 120.79), VinylDiscCyan = Vector3.new(-2.64, 8.273, 120.79)}) do
		local disc, cf = piece(family, at, math.pi, visuals, false)
		disc:SetAttribute("RecordPivot", cf)
		disc:SetAttribute("RecordMeshOffset", CFrame.new(booth[family].centre[1], booth[family].centre[2], booth[family].centre[3]))
	end
	local function block(name, size, at)
		local part = marker(anchors, name, centre + at, size)
		part.CanCollide, part.CanQuery = true, true
	end
	block("StageDeckCollision", Vector3.new(30, 4.5, 17), Vector3.new(0, 2.25, 120))
	block("StageRearGuard", Vector3.new(28.2, 3.1, 0.18), Vector3.new(0, 6.05, 128.4))
	for step = 1, 6 do
		block("StageStepCollision" .. step, Vector3.new(30, 0.75 * step, step == 6 and 2.02 or 1.02), Vector3.new(0, 0.375 * step, step == 6 and 110.5 or 104.5 + step))
	end
end
marker(anchors, "ShopStand", v3(a.shop_stand.centre)):SetAttribute("Radius", a.shop_stand.radius)
local deck = marker(anchors, "StageDeck", (v3(a.stage_deck.min) + v3(a.stage_deck.max)) / 2, Vector3.new(a.stage_deck.max[1] - a.stage_deck.min[1], math.max(a.stage_deck.max[2] - a.stage_deck.min[2], 0.2), a.stage_deck.max[3] - a.stage_deck.min[3]))
local wing = marker(anchors, "DarkWing", (v3(a.dark_wing.min) + v3(a.dark_wing.max)) / 2, Vector3.new(a.dark_wing.max[1] - a.dark_wing.min[1], a.dark_wing.max[2] - a.dark_wing.min[2], a.dark_wing.max[3] - a.dark_wing.min[3]))
anchors:SetAttribute("TapeZ", a.tape_z)
-- the creature's second dark end (Lobby Tunnel Reach): x across, y up from the floor, z = studs past the tape
model:SetAttribute("ReachFrame", CFrame.new(v3({a.spawn[1], a.spawn[2], a.tape_z})))
model:SetAttribute("ReachFence", 1)
model:SetAttribute("ReachGround", a.dark_wing.max[3] - a.tape_z)
-- MALL_FINISH_20261013 (owner: "collision effekt på tape og pæle ... så man ikke kan gå igennem det, men sagtens hoppe
-- over"). The tape itself is a ribbon 3 studs up, which a walking body went under and between the poles. One unseen
-- block from wall to wall, floor to the tape's top edge: it stops a walk and a jump (6.4 studs) clears it.
for _, d in ipairs(model.Parts.Tape:GetChildren()) do
	if d.Name == "DangerTape" then d.CanCollide = false end
end
local blocker = marker(anchors, "TapeBlocker", Vector3.new(a.spawn[1] + offset.X, a.spawn[2] + 1.75, a.tape_z), Vector3.new(80, 3.5, 0.6))
blocker.CanCollide = true
-- the six skins: the game's own suit model on each plinth when its template is in the place
local plinths, placed, standIns = folder("SkinPlinths"), 0, 0
local ServerStorage = game:GetService("ServerStorage")
for _, pl in ipairs(a.skin_plinths) do
	local at = v3(pl.pos)
	local facing = Vector3.new(pl.facing[1], 0, pl.facing[3])
	local m = marker(plinths, pl.skin, at)
	m.CFrame = CFrame.lookAt(at, at + facing)
	m:SetAttribute("SkinId", pl.skin)
	local prompt = Instance.new("ProximityPrompt")          -- Shop Display Client opens the Skins page at this skin
	prompt.Name, prompt.ActionText, prompt.ObjectText = "MallSkinPrompt", "VIEW SKIN", "SHOP & SUPPLIES"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 9, false
	prompt.UIOffset = Vector2.new(0, -40)
	prompt:SetAttribute("SkinId", pl.skin)
	prompt.Parent = m
	local template = ServerStorage:FindFirstChild("HazmatSkin_" .. pl.skin .. "_20260924", true)
	m:SetAttribute("TemplateFound", template ~= nil)
	if template and template:IsA("Model") then
		local suit = template:Clone()
		suit.Name = "ShopSkin_" .. pl.skin
		for _, d in ipairs(suit:GetDescendants()) do
			if d:IsA("BasePart") then d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery = true, false, false, false
			elseif d:IsA("LuaSourceContainer") then d:Destroy() end
		end
		suit.Parent = plinths
		local _, size = suit:GetBoundingBox()
		if size.Y > 0.5 then suit:ScaleTo(5.4 / size.Y * suit:GetScale()) end
		local cf, sized = suit:GetBoundingBox()
		suit:PivotTo(suit:GetPivot() + (at + Vector3.new(0, sized.Y / 2, 0) - cf.Position))
		suit:PivotTo(CFrame.lookAt(suit:GetPivot().Position, suit:GetPivot().Position + facing))
		local now = suit:GetBoundingBox()
		suit:PivotTo(suit:GetPivot() + Vector3.new(at.X - now.Position.X, 0, at.Z - now.Position.Z))
		placed += 1
		for _, d in ipairs(model.Parts.Stand:GetChildren()) do
			if d.Name:sub(1, #pl.skin + 1) == pl.skin .. "_" then d:Destroy(); standIns += 1 end   -- the build's stand-in mannequin
		end
	end
end
local total = 0
for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then total += 1 end end
model:SetAttribute("MallQueuesReady", true)
return string.format("anchors: %%d pads in %%d bays, %%d shop spots, %%d boards, %%d real suits on plinths (%%d stand-in parts removed); model has %%d parts", #a.pads, #bays:GetChildren(), #a.shop_spots, #a.boards, placed, standIns, total)
''' % (NAME, ', '.join(map(str, OFFSET)), J(data['anchors']), J(BOOTH))))
