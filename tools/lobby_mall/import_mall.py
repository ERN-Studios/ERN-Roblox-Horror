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

TILE = {'terrazzo': 10}        # the build's 16 studs a tile gave chips the size of a hand
materials = {}
for key, m in data['materials'].items():
    mean = None
    if m.get('colour_map'):
        im = Image.open(BUILD / m['colour_map']).convert('RGB').resize((1, 1), Image.BOX)
        mean = list(im.getpixel((0, 0)))
    materials[key] = {'base': m['base'], 'mean': mean, 'tile': TILE.get(key) or m.get('studs_per_tile') or 4, 'ids': TEXTURES.get(key)}

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
	part.Anchored, part.CanCollide, part.CanTouch = true, p.collide == true, false
	part.CastShadow = p.size[1] * p.size[2] * p.size[3] > 2
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
	part.CFrame = CFrame.new(Vector3.new(p.pos[1], p.pos[2], p.pos[3]) + offset)
		* CFrame.fromOrientation(math.rad(p.rot[1]), math.rad(p.rot[2]), math.rad(p.rot[3]))
	local m = mats[p.material]
	part.Material = p.glow and Enum.Material.Neon or Enum.Material[m.base]
	local c = p.color
	if m.mean and not (m.ids and m.ids.colour) and c[1] > 250 and c[2] > 250 and c[3] > 250 then c = m.mean end
	part.Color = Color3.fromRGB(c[1], c[2], c[3])
	if m.ids and m.ids.colour and not p.glow then part.MaterialVariant = "Mall " .. p.material end
	part.Transparency = p.transparency or 0
	part:SetAttribute("MallMaterial", p.material)
	part.Parent = group
	n += 1
end
return n
'''
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
	local g = Instance.new("SurfaceGui")
	g.Name, g.Face, g.SizingMode, g.PixelsPerStud = "MallSign", face, Enum.SurfaceGuiSizingMode.PixelsPerStud, pps
	g.ClipsDescendants = true
	local lit = sign.style == "box" or sign.style == "station"
	g.LightInfluence = lit and 0 or sign.style == "plain" and 0.35 or 1
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
local n = 0
for _, l in ipairs(game:GetService("HttpService"):JSONDecode([==[%s]==])) do
	local host = Instance.new("Part")
	host.Name, host.Anchored, host.CanCollide, host.CanTouch, host.CanQuery = l.name, true, false, false, false
	host.Transparency, host.Size = 1, Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = CFrame.new(Vector3.new(l.pos[1], l.pos[2], l.pos[3]) + offset) * CFrame.Angles(math.rad(-90), 0, 0)   -- front face down
	-- the build's lamp colours are pictures' colours; as light on yellow walls they turned the hall into mustard
	local colour = Color3.fromRGB(l.color[1], l.color[2], l.color[3]):Lerp(Color3.fromRGB(255, 246, 224), l.kind == "neon" and 0 or 0.6)
	-- the data's brightness is Blender's: the square root keeps the build's order (product lamp < skin spot < shop wash)
	local strength = 0.42 * math.sqrt(l.brightness)
	local light
	if l.kind == "panel" then
		light = Instance.new("SpotLight")
		light.Face, light.Angle = Enum.NormalId.Front, 150
		light.Brightness, light.Range = l.state == "on" and 1.0 or 0.3, 40
	elseif l.name:sub(1, 8) == "SkinSpot" then
		light = Instance.new("SpotLight")
		light.Face, light.Angle = Enum.NormalId.Front, 70
		light.Brightness, light.Range = 2.2, l.range
	else
		light = Instance.new("PointLight")
		light.Brightness, light.Range = strength, math.min(l.range, 60)
	end
	light.Color, light.Shadows = colour, false
	light.Parent = host
	if l.kind == "panel" and l.state == "on" then
		-- a panel only throws down; real tiles are lit by what comes back off the floor
		local wash = Instance.new("PointLight")
		wash.Name, wash.Color, wash.Shadows, wash.Brightness, wash.Range = "CeilingWash", colour, false, 0.3, 26
		wash.Parent = host
	end
	host:SetAttribute("MallLight", l.kind)
	if l.state ~= "on" then host:SetAttribute("Flicker", true) end
	host.Parent = model.Lights
	n += 1
end
return "lights " .. n
''' % (NAME, ', '.join(map(str, OFFSET)), J(data['lights']))))

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
	zone:SetAttribute("MallQueueId", 200 + (pad.level - 1) * 3 + pad.station)
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
-- Lobby DJ stands its DJ at this part's foot, 2.9 studs behind it: the part reaches down to the stage deck
local deckTop = a.stage_deck.max[2]
marker(anchors, "DJConsole", v3(a.dj_console), Vector3.new(4, math.max(0.5, (a.dj_console[2] - deckTop) * 2), 2))
marker(anchors, "ShopStand", v3(a.shop_stand.centre)):SetAttribute("Radius", a.shop_stand.radius)
local deck = marker(anchors, "StageDeck", (v3(a.stage_deck.min) + v3(a.stage_deck.max)) / 2, Vector3.new(a.stage_deck.max[1] - a.stage_deck.min[1], math.max(a.stage_deck.max[2] - a.stage_deck.min[2], 0.2), a.stage_deck.max[3] - a.stage_deck.min[3]))
local wing = marker(anchors, "DarkWing", (v3(a.dark_wing.min) + v3(a.dark_wing.max)) / 2, Vector3.new(a.dark_wing.max[1] - a.dark_wing.min[1], a.dark_wing.max[2] - a.dark_wing.min[2], a.dark_wing.max[3] - a.dark_wing.min[3]))
anchors:SetAttribute("TapeZ", a.tape_z)
-- the creature's second dark end (Lobby Tunnel Reach): x across, y up from the floor, z = studs past the tape
model:SetAttribute("ReachFrame", CFrame.new(v3({a.spawn[1], a.spawn[2], a.tape_z})))
model:SetAttribute("ReachFence", 1)
model:SetAttribute("ReachGround", a.dark_wing.max[3] - a.tape_z)
-- the tape is a line, not a wall: the owner's whole point is that you can walk past it
for _, d in ipairs(model.Parts.Tape:GetChildren()) do
	if d.Name == "DangerTape" then d.CanCollide = false end
end
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
			if d.Name:sub(1, #pl.skin + 1) == pl.skin .. "_" then d.Transparency = 1; d.CanCollide = false; d:SetAttribute("StandIn", true); standIns += 1 end
		end
	end
end
local total = 0
for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then total += 1 end end
model:SetAttribute("MallQueuesReady", true)
return string.format("anchors: %%d pads in %%d bays, %%d shop spots, %%d boards, %%d real suits on plinths (%%d stand-in parts hidden); model has %%d parts", #a.pads, #bays:GetChildren(), #a.shop_spots, #a.boards, placed, standIns, total)
''' % (NAME, ', '.join(map(str, OFFSET)), J(data['anchors']))))
