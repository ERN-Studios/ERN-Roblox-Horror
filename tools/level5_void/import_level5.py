"""Build Workspace."Level 5 Void" in the open Studio place from artifacts/level5-void-20261003/build/level5.json.

    python3 tools/level5_void/build_level5.py && python3 tools/level5_void/import_level5.py

Native Parts only. The model carries the attributes Level5PreviewAccess checks, `Level5Exit` (the arrival pad,
where the script mounts RETURN TO LOBBY), `Level5Finish`, and StringValues `Route` / `Checkpoints` (JSON) for
the walk-through test and the fall recovery.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

data = json.loads((ROOT / 'artifacts' / 'level5-void-20261003' / 'build' / 'level5.json').read_text())
s = studio_io.Studio()

print(s.luau('''
local old = workspace:FindFirstChild("Level 5 Void")
if old then old:Destroy() end
local model = Instance.new("Model")
model.Name = "Level 5 Void"
for _, name in ipairs({"Geometry", "Lights"}) do
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = model
end
model.Parent = workspace
return "fresh model"
'''))

BUILD = '''
local data = game:GetService("HttpService"):JSONDecode([==[%s]==])
local O = Vector3.new(%s)
local model = workspace["Level 5 Void"]
local made = 0
for _, row in ipairs(data.parts) do
	local part = Instance.new("Part")
	part.Name = row.n
	part.Anchored = true
	part.CanCollide = row.col
	part.CanTouch = false
	part.CastShadow = row.n ~= "Orb"
	part.Material = Enum.Material[row.m]
	local c = data.colours[row.c]
	part.Color = Color3.fromRGB(c[1], c[2], c[3])
	part.TopSurface, part.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if row.sh == "s" then part.Shape = Enum.PartType.Ball elseif row.sh == "c" then part.Shape = Enum.PartType.Cylinder end
	part.Size = Vector3.new(row.s[1], row.s[2], row.s[3])
	part.CFrame = CFrame.new(O + Vector3.new(row.p[1], row.p[2], row.p[3]))
		* CFrame.Angles(0, -math.rad(row.yaw), 0) * CFrame.Angles(0, 0, math.rad(row.pitch + (row.roll or 0)))
	if row.refl then part.Reflectance = row.refl end
	if row.light then
		local glow = Instance.new("PointLight")
		glow.Range, glow.Brightness, glow.Shadows = row.light[1], row.light[2], false
		glow.Color = Color3.fromRGB(255, 250, 240)
		glow.Parent = part
	end
	part.Parent = model.Geometry
	made += 1
end
for _, row in ipairs(data.lights) do
	local holder = Instance.new("Part")
	holder.Name = "Light"
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
return made
'''
chunk = 120
total = 0
for i in range(0, len(data['parts']), chunk):
    piece = {'parts': data['parts'][i:i + chunk], 'lights': [], 'colours': data['colours']}
    total += int(float(s.luau(BUILD % (json.dumps(piece), ', '.join(map(str, data['origin']))))))
total += int(float(s.luau(BUILD % (json.dumps({'parts': [], 'lights': data['lights'], 'colours': data['colours']}),
                                   ', '.join(map(str, data['origin']))))))

print(s.luau('''
local O = Vector3.new(%s)
local model = workspace["Level 5 Void"]
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
marker("Level5Exit", Vector3.new(%s))
marker("Level5Finish", Vector3.new(%s))
for name, text in pairs({Route = [==[%s]==], Checkpoints = [==[%s]==]}) do
	local value = Instance.new("StringValue")
	value.Name = name
	value.Value = text
	value.Parent = model
end
model:SetAttribute("Origin", O)
model:SetAttribute("Level5Preview", true)
model:SetAttribute("PreviewOnly", true)
model:SetAttribute("Level5PreviewReady", true)
local cf, size = model:GetBoundingBox()
model:SetAttribute("BoundsCenter", cf.Position)
model:SetAttribute("BoundsSize", size)
return "instances " .. #model:GetDescendants() .. ", bounds " .. tostring(size)
''' % (', '.join(map(str, data['origin'])), ', '.join(map(str, data['start'])), ', '.join(map(str, data['finish'])),
       json.dumps(data['route']), json.dumps(data['checkpoints']))))
print('built', total)
