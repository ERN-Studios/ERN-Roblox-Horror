"""Build Workspace."Level 5 Void" in the open Studio place from artifacts/level5-void-20261003/build/level5.json.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/level5_void/build_level5.py
    python3 tools/level5_void/import_level5.py

Native Parts only. The model carries the attributes Level5PreviewAccess checks, `Level5Exit` (the arrival pad),
`Level5Finish`, `Level5Reentry`, the loose `Balls` (unanchored, each with its `Home`), one folder per pressure
plate under `Plates` (`Plate`, `Gate`, attributes `Section` and `SectionIndex`), the moving parts of the last
room's corridor under `Finale` (`CrusherWall` x2 with `Side`, `CrusherBlock`, `CrusherGate`), and StringValues
`Route` / `Checkpoints` / `FinaleData` (JSON) for the walk-through test, the plates and the corridor.

The plaster is `MaterialService."L5 Void Plaster"` (base material Plaster). Its three maps are the PNGs the
Blender build writes; their asset ids go in TEXTURES below once they are uploaded (Asset Manager > Import).
Without ids the variant is not made and the parts show Roblox's own Plaster, which has a bump map too.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

TEXTURES = json.loads((Path(__file__).parent / 'texture_ids.json').read_text()) if (Path(__file__).parent / 'texture_ids.json').exists() else {}
data = json.loads((ROOT / 'artifacts' / 'level5-void-20261003' / 'build' / 'level5.json').read_text())
s = studio_io.Studio()
ORIGIN = ', '.join(map(str, data['origin']))

print(s.luau('''
local MaterialService = game:GetService("MaterialService")
local ids = game:GetService("HttpService"):JSONDecode([==[%s]==])
local variant = MaterialService:FindFirstChild("L5 Void Plaster")
if ids.colour and ids.normal and ids.roughness then
	if not variant then
		variant = Instance.new("MaterialVariant")
		variant.Name = "L5 Void Plaster"
		variant.BaseMaterial = Enum.Material.Plaster
		variant.Parent = MaterialService
	end
	variant.ColorMap = "rbxassetid://" .. ids.colour
	variant.NormalMap = "rbxassetid://" .. ids.normal
	variant.RoughnessMap = "rbxassetid://" .. ids.roughness
	variant.StudsPerTile = 14
	variant.MaterialPattern = Enum.MaterialPattern.Organic
end
local old = workspace:FindFirstChild("Level 5 Void")
if old then old:Destroy() end
local model = Instance.new("Model")
model.Name = "Level 5 Void"
for _, name in ipairs({"Geometry", "Lights", "Balls", "Plates"}) do
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = model
end
model.Parent = workspace
return "fresh model, plaster variant " .. tostring(variant ~= nil)
''' % json.dumps(TEXTURES)))

BUILD = '''
local data = game:GetService("HttpService"):JSONDecode([==[%s]==])
local O = Vector3.new(%s)
local model = workspace["Level 5 Void"]
local plaster = game:GetService("MaterialService"):FindFirstChild("L5 Void Plaster") ~= nil
local made = 0
for _, row in ipairs(data.parts) do
	local part = Instance.new("Part")
	part.Name = row.n
	part.Anchored = true
	part.CanCollide = row.col and row.n ~= "Monolith"      -- a body that lands on a loose monolith would be stranded there
	part.CanTouch = false
	part.CastShadow = row.n ~= "Orb" and row.n ~= "OrbRod"
	-- the original smooth finish (owner, 2026-10-04): no plaster, no bump-map variant
	part.Material = Enum.Material[row.m == "Plaster" and "SmoothPlastic" or row.m]
	local c = data.colours[row.c]
	part.Color = Color3.fromRGB(c[1], c[2], c[3])
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if row.sh == "s" then part.Shape = Enum.PartType.Ball elseif row.sh == "c" then part.Shape = Enum.PartType.Cylinder end
	part.Size = Vector3.new(row.s[1], row.s[2], row.s[3])
	part.CFrame = CFrame.new(O + Vector3.new(row.p[1], row.p[2], row.p[3]))
		* CFrame.Angles(0, -math.rad(row.yaw), 0) * CFrame.Angles(0, 0, math.rad(row.roll or 0))
	if row.t then part.Transparency = row.t end
	if row.side then part:SetAttribute("Side", row.side) end
	if row.light then
		local glow = Instance.new("PointLight")
		glow.Range, glow.Brightness, glow.Shadows = row.light[1], row.light[2], false
		glow.Color = Color3.fromRGB(255, 250, 240)
		glow.Parent = part
	end
	-- a row with a group goes in a folder of its own: the parts a script moves are not lost among the static ones
	local home = model.Geometry
	if row.g then
		home = model:FindFirstChild(row.g)
		if not home then
			home = Instance.new("Folder")
			home.Name = row.g
			home.Parent = model
		end
	end
	part.Parent = home
	made += 1
end
for _, row in ipairs(data.lights) do
	local holder = Instance.new("Part")
	holder.Name = row.n or "Light"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = O + Vector3.new(row.p[1], row.p[2], row.p[3])
	local lamp = Instance.new("PointLight")
	lamp.Range, lamp.Brightness, lamp.Shadows = row.r, row.b, false
	lamp.Color = Color3.fromRGB(255, 252, 246)
	lamp.Parent = holder
	holder.Parent = model.Lights
	made += 1
end
for i, row in ipairs(data.balls) do
	-- loose: a player walks into one and it rolls, off the edge if that is where it is pushed
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * row.r * 2
	ball.Position = O + Vector3.new(row.p[1], row.p[2], row.p[3])
	ball.Anchored = false
	ball.Material = Enum.Material.SmoothPlastic
	ball.Color = Color3.fromRGB(data.colours.sphere[1], data.colours.sphere[2], data.colours.sphere[3])
	ball.Reflectance = 0.25
	ball.TopSurface, ball.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.55, 0.25, 1, 1)
	ball:SetAttribute("Home", ball.Position)
	ball.Parent = model.Balls
	made += 1
end
return made
'''
chunk, total = 110, 0
empty = {'parts': [], 'lights': [], 'balls': [], 'colours': data['colours']}
for i in range(0, len(data['parts']), chunk):
    total += int(float(s.luau(BUILD % (json.dumps({**empty, 'parts': data['parts'][i:i + chunk]}), ORIGIN))))
for i in range(0, len(data['lights']), 300):
    total += int(float(s.luau(BUILD % (json.dumps({**empty, 'lights': data['lights'][i:i + 300]}), ORIGIN))))
total += int(float(s.luau(BUILD % (json.dumps({**empty, 'balls': data['balls']}), ORIGIN))))

print(s.luau('''
local Http = game:GetService("HttpService")
local O = Vector3.new(%s)
local model = workspace["Level 5 Void"]
local data = Http:JSONDecode([==[%s]==])
local function marker(name, at)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch = true, false, false, false
	part.Transparency = 1
	part.Size = Vector3.new(4, 1, 4)
	part.CFrame = CFrame.lookAt(O + at + Vector3.new(0, 3.5, 0), O + at + Vector3.new(10, 3.5, 0))
	part.Parent = model
	return part
end
marker("Level5Exit", Vector3.new(data.start[1], data.start[2], data.start[3]))
marker("Level5Finish", Vector3.new(data.finish[1], data.finish[2], data.finish[3]))
if data.finale and data.finale.reentry then
	marker("Level5Reentry", Vector3.new(data.finale.reentry[1], data.finale.reentry[2], data.finale.reentry[3]))
end
local index = {}
for i, name in ipairs(data.sections) do index[name] = i end
for _, row in ipairs(data.plates) do
	local folder = Instance.new("Folder")
	folder.Name = row.sec
	folder:SetAttribute("Section", row.sec)
	folder:SetAttribute("SectionIndex", index[row.sec])
	local at = O + Vector3.new(row.x, row.y, row.z)
	-- the plate: a disc the server resizes to the number of players who have to stand on it
	local plate = Instance.new("Part")
	plate.Name = "Plate"
	plate.Shape = Enum.PartType.Cylinder
	plate.Anchored, plate.CanTouch = true, false
	plate.Material = Enum.Material.SmoothPlastic
	plate.Color = Color3.fromRGB(data.colours.plate[1], data.colours.plate[2], data.colours.plate[3])
	plate.Size = Vector3.new(0.5, 8.2, 8.2)
	plate.CFrame = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	plate:SetAttribute("Rest", plate.Position)
	plate.Parent = folder
	local ring = Instance.new("Part")
	ring.Name = "PlateBed"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanTouch, ring.CanCollide = true, false, false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = Color3.fromRGB(12, 12, 14)
	ring.Size = Vector3.new(0.12, 9.4, 9.4)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = folder
	-- the gate: a slab that fills the doorway and sinks into the sill
	local gate = Instance.new("Part")
	gate.Name = "Gate"
	gate.Anchored, gate.CanTouch = true, false
	gate.Material = Enum.Material.SmoothPlastic
	gate.Color = Color3.fromRGB(10, 10, 12)
	gate.Size = Vector3.new(3, 13, 9)
	gate.CFrame = CFrame.new(O + Vector3.new(row.gate[1], row.gate[2] + 6.5, row.gate[3]))
	gate:SetAttribute("Closed", gate.Position)
	gate.Parent = folder
	-- No counter on the door (owner, 2026-10-04): the plate grows with the players and the door goes down when
	-- they all stand on it. Only the first room says so, once, on its door.
	if row.sec == "rose" then
		local face = Instance.new("SurfaceGui")
		face.Name = "Hint"
		face.Face = Enum.NormalId.Left
		face.CanvasSize = Vector2.new(360, 520)
		face.LightInfluence = 0
		face.Brightness = 1.2
		local hint = Instance.new("TextLabel")
		hint.Name = "Hint"
		hint.Size = UDim2.fromScale(0.84, 0.16)
		hint.Position = UDim2.fromScale(0.08, 0.36)
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamMedium
		hint.TextScaled = true
		hint.TextColor3 = Color3.fromRGB(240, 240, 232)
		hint.TextTransparency = 0.15
		hint.Text = "EVERYONE ON THE PLATE"
		hint.Parent = face
		face.Parent = gate
	end
	folder.Parent = model.Plates
end
for name, value in pairs({Route = data.route, Checkpoints = data.checkpoints, FinaleData = data.finale}) do
	local holder = Instance.new("StringValue")
	holder.Name = name
	holder.Value = Http:JSONEncode(value)
	holder.Parent = model
end
model:SetAttribute("Origin", O)
model:SetAttribute("Bottom", %s)
model:SetAttribute("Level5Preview", true)
model:SetAttribute("PreviewOnly", true)
model:SetAttribute("Level5PreviewReady", true)
local cf, size = model:GetBoundingBox()
model:SetAttribute("BoundsCenter", cf.Position)
model:SetAttribute("BoundsSize", size)
return "instances " .. #model:GetDescendants() .. ", bounds " .. tostring(size)
''' % (ORIGIN, json.dumps({k: data[k] for k in ('start', 'finish', 'plates', 'sections', 'colours', 'route', 'checkpoints', 'finale')}), -420)))
print('built', total)
