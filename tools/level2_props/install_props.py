"""Put the Level 2 wall lamps (build_props.py) into the stored Poolrooms map: ServerStorage.Level2PoolroomsMap."Owner Props".

    python3 tools/level2_props/install_props.py            # upload what is new, rebuild the folder (Studio in Edit)
    python3 tools/level2_props/install_props.py --dry      # print what it would place, change nothing

Owner, 2026-10-10: pool lamps set into the walls of the five bottomless pits of the second hall (A3), on every side,
all the way down, fading with depth; and a small green lamp over the open door to the exit in the last hall (A6).

The map is ONE model that moves between ServerStorage and Workspace each round, so what is saved inside it in Edit is in
every round. Nothing here touches the map's own parts: it rebuilds one folder, `Owner Props`, from scratch each run.
A whole-map re-import from the Blender project (on the Windows PC) drops that folder: run this again afterwards.

Positions come from the model, not from constants: the pit rectangles are the five box-shaped parts named Hazard with
KillZone = true in area A3 (the sixth, a cylinder, is the pump-bay drain and gets no lamps); the hall's floor is marker
A3_05 minus 3 studs; the exit door is marker EXIT. The three numbers that were measured with rays in a play session
(DOOR below) are tied to the map's CollisionPacket: if the map is re-exported the installer stops and says so.

Meshes go up as group assets through AssetService:CreateAssetAsync (a Studio Beta Feature); ids are kept beside this file
with the hash of the numbers they were made from, so unchanged meshes are not uploaded twice.
"""
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

EXPORT = ROOT / 'artifacts' / 'level2-props-20261010' / 'props.json'
IDS = HERE / 'mesh_ids.json'

SPEC = {
    'revision': 'L2_PROPS_20261010',
    'packet': '5a613ab5f50b009c',          # Level2PoolroomsMap.CollisionPacket the DOOR numbers were measured against
    # Pit lamps. Rows start 3 studs under the hall floor and step down to just over the opaque black sheet that ends
    # each shaft (8 "Veil" sheets, the last 62.9 studs down). The sheets do the fading: a lamp is seen through every
    # sheet above it (85%, 68%, 49%, 30%, 15%, 6%, 1.5% of its light). A row never sits in a sheet's plane.
    'first': 3.0, 'step': 5.2, 'rows': 12, 'veilClear': 0.9,
    'column': 12.0,                        # one column of lamps per this many studs of wall
    # Every mesh goes up with WHITE vertex colours: the build script's own tints multiply the part colour, which made
    # the lens glow a dull teal and the cast-metal box of the exit lamp plain black. The part colour alone decides.
    'lens': [208, 246, 255], 'lensFade': 0.015,   # the lens colour loses this share per row on top of the sheets
    'bezel': [198, 204, 208],
    'litRows': 2, 'light': {'brightness': [0.55, 0.3], 'range': 15, 'colour': [190, 238, 255]},
    # The exit door: measured in play on 2026-10-10 with rays from the gallery. Wall face 0.33 studs west of the EXIT
    # marker, opening 1.8 studs wide centred 0.2 north of it, head 6.4 over the gallery floor, soffit 8.2 over it.
    'door': {'wallFromMarkerX': -0.33, 'centreFromMarkerZ': 0.2, 'lampOverFloor': 7.3},
    # The first light (1.1 over 16 studs) painted the whole gallery wall green: it is a marker, not a floodlight.
    # The lens is a yellower green than it should look: the level's own grade takes 30% of the saturation and tints
    # everything cool, and (60, 255, 120) came out mint.
    'exit': {'lens': [0, 255, 40], 'base': [150, 156, 152], 'cage': [58, 64, 62],
             'light': {'brightness': 0.4, 'range': 8, 'colour': [40, 255, 90]}},
}

UPLOAD = '''
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local NAME, KNOWN = %s, %s
local id = KNOWN
if id == 0 then
	local data = HttpService:JSONDecode([==[%s]==])
	local em = AssetService:CreateEditableMesh()
	local V, N, C, T = data.verts, data.normals, data.colours, data.tris
	local vid, nid, cid = {}, {}, {}
	for i = 1, #V, 3 do
		vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000)
		nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000)
		cid[#cid + 1] = em:AddColor(Color3.fromRGB(C[i], C[i + 1], C[i + 2]), 1)
	end
	for i = 1, #T, 3 do
		local a, b, c = T[i] + 1, T[i + 1] + 1, T[i + 2] + 1
		local f = em:AddTriangle(vid[a], vid[b], vid[c])
		em:SetFaceNormals(f, {nid[a], nid[b], nid[c]})
		em:SetFaceColors(f, {cid[a], cid[b], cid[c]})
	end
	local ok, result, made = pcall(function()
		return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Level 2 " .. NAME,
			Description = "Level 2 Poolrooms wall lamp", CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
	end)
	em:Destroy()
	if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(made) end
	id = made
end
return "OK " .. id
'''

BUILD = '''
local AssetService = game:GetService("AssetService")
local ServerStorage = game:GetService("ServerStorage")
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
assert(game.PlaceId == 131311258779917, "wrong place")
local SPEC = game:GetService("HttpService"):JSONDecode([==[%s]==])
local DRY = %s
local map = ServerStorage:FindFirstChild("Level2PoolroomsMap")
assert(map and map:IsA("Model") and map:GetAttribute("Level2NewMap") == true, "ServerStorage.Level2PoolroomsMap is missing")
assert(workspace:FindFirstChild("Level 2 Generated World") == nil, "a Level 2 world is in Workspace: stop play first")
assert(map:GetAttribute("CollisionPacket") == SPEC.packet, "the map was re-exported (CollisionPacket "
	.. tostring(map:GetAttribute("CollisionPacket")) .. "): measure the exit door again before installing")
local markers = map:FindFirstChild("Markers")
local floorMarker, exitMarker = markers:FindFirstChild("A3_05"), markers:FindFirstChild("EXIT")
assert(floorMarker and exitMarker, "markers A3_05 / EXIT are missing")
local floorY = floorMarker.Position.Y - 3

local pits, veils = {}, {}
for _, d in ipairs(map.Collision:GetDescendants()) do
	if d:IsA("BasePart") and d.Name == "Hazard" and d:GetAttribute("KillZone") == true and d:GetAttribute("Area") == "A3"
		and d:IsA("Part") and d.Shape == Enum.PartType.Block and math.abs(d.CFrame.UpVector.Y) > 0.999 then
		table.insert(pits, d)
	elseif d:IsA("BasePart") and d.Name == "Veil" then
		table.insert(veils, d)
	end
end
table.sort(pits, function(a, b) return a.Position.X < b.Position.X end)
assert(#pits == 5, "expected the five box pits of A3, found " .. #pits)

local function clone(template, cf, middle)
	local part = template:Clone()
	part.CFrame = cf * CFrame.new(middle[1], middle[2], middle[3])   -- a MeshPart's own origin is the middle of its box
	return part
end
local function dress(part, name, material, colour)
	part.Name, part.Material, part.Color = name, material, Color3.fromRGB(colour[1], colour[2], colour[3])
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.Massless = true
end
local templates = {}
if not DRY then
	for name, item in pairs(SPEC.meshes) do
		local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(item.id), {CollisionFidelity = Enum.CollisionFidelity.Box})
		part:SetAttribute("AssetId", item.id)
		templates[name] = part
	end
end

local root = Instance.new("Folder")
root.Name = "Owner Props"
root:SetAttribute("PropsRevision", SPEC.revision)
root:SetAttribute("Built", "tools/level2_props/install_props.py")
root:SetAttribute("SourceCollisionPacket", SPEC.packet)
local pitFolder = Instance.new("Folder")
pitFolder.Name = "A3 Pit Lamps"
pitFolder.Parent = root

local report, lamps, lights = {}, 0, 0
for index, hazard in ipairs(pits) do
	local centre, size = hazard.Position, hazard.Size
	-- the sheets of this shaft, to keep rows out of their planes
	local planes = {}
	for _, veil in ipairs(veils) do
		if math.abs(veil.Position.X - centre.X) < 1 and math.abs(veil.Position.Z - centre.Z) < 1 then table.insert(planes, veil.Position.Y) end
	end
	table.sort(planes, function(a, b) return a > b end)
	local bottom = planes[#planes] or (floorY - 63)
	local rows = {}
	for k = 0, SPEC.rows - 1 do
		local y = floorY - SPEC.first - SPEC.step * k
		for _, plane in ipairs(planes) do
			if math.abs(y - plane) < SPEC.veilClear then y = plane + SPEC.veilClear end
		end
		if y > bottom + 1.2 and (#rows == 0 or rows[#rows] - y > 2.5) then table.insert(rows, y) end
	end
	local model = Instance.new("Model")
	model.Name = "Pit " .. index .. " Lamps"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic   -- a column never arrives half-built
	local walls = {
		{normal = Vector3.new(1, 0, 0), along = Vector3.new(0, 0, 1), length = size.Z, at = centre - Vector3.new(size.X / 2, 0, 0)},
		{normal = Vector3.new(-1, 0, 0), along = Vector3.new(0, 0, 1), length = size.Z, at = centre + Vector3.new(size.X / 2, 0, 0)},
		{normal = Vector3.new(0, 0, 1), along = Vector3.new(1, 0, 0), length = size.X, at = centre - Vector3.new(0, 0, size.Z / 2)},
		{normal = Vector3.new(0, 0, -1), along = Vector3.new(1, 0, 0), length = size.X, at = centre + Vector3.new(0, 0, size.Z / 2)},
	}
	local count = 0
	for w, wall in ipairs(walls) do
		local columns = math.max(1, math.floor(wall.length / SPEC.column + 0.5))
		for c = 1, columns do
			local offset = wall.length * ((c - 0.5) / columns - 0.5)
			for r, y in ipairs(rows) do
				local point = Vector3.new(wall.at.X, y, wall.at.Z) + wall.along * offset
				local cf = CFrame.lookAt(point, point + wall.normal)   -- the mesh's front is its -Z
				count += 1
				if not DRY then
					local tag = string.format("A3_PitLamp_%%d_%%d_%%d_%%02d", index, w, c, r)
					local bezel = clone(templates.PoolLamp_Bezel, cf, SPEC.meshes.PoolLamp_Bezel.middle)
					dress(bezel, tag .. "_Bezel", Enum.Material.Metal, SPEC.bezel)
					bezel.Parent = model
					local lens = clone(templates.PoolLamp_Lens, cf, SPEC.meshes.PoolLamp_Lens.middle)
					local fade = math.max(0.35, 1 - SPEC.lensFade * (r - 1))
					dress(lens, tag, Enum.Material.Neon, {SPEC.lens[1] * fade, SPEC.lens[2] * fade, SPEC.lens[3] * fade})
					lens:SetAttribute("Row", r)
					if r <= SPEC.litRows then
						local light = Instance.new("PointLight")
						light.Brightness, light.Range, light.Shadows = SPEC.light.brightness[r], SPEC.light.range, false
						light.Color = Color3.fromRGB(SPEC.light.colour[1], SPEC.light.colour[2], SPEC.light.colour[3])
						light.Parent = lens
						lens:SetAttribute("BaseBrightness", light.Brightness)
						lights += 1
					end
					lens.Parent = model
				end
			end
		end
	end
	lamps += count
	model:SetAttribute("Lamps", count)
	model.Parent = pitFolder
	table.insert(report, string.format("pit %%d (%%.1f x %%.1f): %%d lamps in %%d rows, lowest %%.1f under the floor", index, size.X, size.Z, count, #rows, floorY - rows[#rows]))
end

-- the green lamp over the open door to the exit
local door = SPEC.door
local floorAtDoor = exitMarker.Position.Y - 3
local at = Vector3.new(exitMarker.Position.X + door.wallFromMarkerX, floorAtDoor + door.lampOverFloor, exitMarker.Position.Z + door.centreFromMarkerZ)
local exitModel = Instance.new("Model")
exitModel.Name = "A6 Exit Lamp"
exitModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent   -- one small lamp that has to be seen across the atrium
if not DRY then
	local cf = CFrame.lookAt(at, at + Vector3.new(-1, 0, 0))   -- the wall faces west, into the gallery
	local base = clone(templates.ExitLamp_Base, cf, SPEC.meshes.ExitLamp_Base.middle)
	dress(base, "A6_ExitGreen_Base", Enum.Material.Metal, SPEC.exit.base)
	base.Parent = exitModel
	local cage = clone(templates.ExitLamp_Cage, cf, SPEC.meshes.ExitLamp_Cage.middle)
	dress(cage, "A6_ExitGreen_Cage", Enum.Material.Metal, SPEC.exit.cage)
	cage.Parent = exitModel
	local lens = clone(templates.ExitLamp_Lens, cf, SPEC.meshes.ExitLamp_Lens.middle)
	dress(lens, "A6_ExitGreen", Enum.Material.Neon, SPEC.exit.lens)
	local light = Instance.new("PointLight")
	light.Brightness, light.Range, light.Shadows = SPEC.exit.light.brightness, SPEC.exit.light.range, false
	light.Color = Color3.fromRGB(SPEC.exit.light.colour[1], SPEC.exit.light.colour[2], SPEC.exit.light.colour[3])
	light.Parent = lens
	lens:SetAttribute("BaseBrightness", light.Brightness)
	lens.Parent = exitModel
	exitModel.PrimaryPart = lens
end
exitModel.Parent = root
local origin = map:GetAttribute("Origin")
table.insert(report, string.format("exit lamp at origin-relative (%%.2f, %%.2f, %%.2f), facing west", at.X - origin.X, at.Y - origin.Y, at.Z - origin.Z))

root:SetAttribute("PitLamps", lamps)
root:SetAttribute("Lights", lights + 1)
if DRY then
	root:Destroy()
	for _, t in pairs(templates) do t:Destroy() end
	return "DRY RUN, nothing changed\\n" .. table.concat(report, "\\n")
end
for _, t in pairs(templates) do t:Destroy() end
local old = map:FindFirstChild("Owner Props")
if old then old:Destroy() end
root.Parent = map
return string.format("installed %%d pit lamps (%%d lights) and the exit lamp; the model now has %%d descendants\\n", lamps, lights, #map:GetDescendants()) .. table.concat(report, "\\n")
'''


def main():
    dry = '--dry' in sys.argv
    export = json.loads(EXPORT.read_text())
    known = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    spec = dict(SPEC, meshes={})
    for name, mesh in export['meshes'].items():
        numbers = {k: mesh[k] for k in ('verts', 'normals', 'colours', 'tris')}
        numbers['colours'] = [255] * len(numbers['colours'])
        text = json.dumps(numbers, separators=(',', ':'))
        digest = hashlib.sha256(text.encode()).hexdigest()
        have = known.get(name, {})
        asset = have.get('id', 0) if have.get('sha256') == digest else 0
        if dry and not asset:
            print(name, '-> would upload', flush=True)
        else:
            answer = studio.luau(UPLOAD % (json.dumps(name), asset, text))
            print(name, '->', answer, flush=True)
            if not answer.startswith('OK '):
                raise SystemExit('upload refused; nothing installed')
            asset = int(answer.split()[1])
            known[name] = {'id': asset, 'sha256': digest}
            IDS.write_text(json.dumps(known, indent=1, sort_keys=True) + '\n')
        spec['meshes'][name] = {'id': asset, 'middle': mesh['middle']}
    print(studio.luau(BUILD % (json.dumps(spec), 'true' if dry else 'false')), flush=True)


if __name__ == '__main__':
    main()
