"""Level 6 entity: put the skinned doll and its clips into the open Studio place.

    python3 tools/level6_entity/import_to_studio.py mesh       # build the EditableMesh, upload it, record the id
    python3 tools/level6_entity/import_to_studio.py assemble   # ReplicatedStorage.Level6Counter: Doll + Clips

The Studio MCP sandbox takes about 1 MB of code per call and keeps no Lua state between calls, so the mesh
is staged as StringValue chunks under ServerStorage.Level6CounterSource and decoded by the build call.
"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'level6_playground'))
import import_to_studio as studio_io

ROOT = studio_io.ROOT
EXPORT = ROOT / 'artifacts' / 'level6-entity-20261003' / 'export'
ASSETS = Path(__file__).with_name('counter_assets.json')
CHUNK = 150_000

STAGE = '''
local ss = game:GetService("ServerStorage")
local f = ss:FindFirstChild("Level6CounterSource")
if %s then if f then f:Destroy() end; f = Instance.new("Folder"); f.Name = "Level6CounterSource"; f.Parent = ss end
local v = Instance.new("StringValue"); v.Name = %s; v.Value = [==[%s]==]; v.Parent = f
return #f:GetChildren()
'''

BUILD = '''
local AS, H = game:GetService("AssetService"), game:GetService("HttpService")
local stage = game:GetService("ServerStorage"):FindFirstChild("Level6CounterSource")
local function load(key)
	local parts, i = {}, 1
	while true do
		local sv = stage:FindFirstChild(key .. "_" .. i)
		if not sv then break end
		parts[#parts + 1] = sv.Value; i += 1
	end
	return H:JSONDecode(table.concat(parts))
end
local em = AS:CreateEditableMesh()
local V, UV, N, T, W, bones = load("V"), load("UV"), load("N"), load("T"), load("W"), load("B")
local vid, uid, nid, bid = {}, {}, {}, {}
for i = 1, #V, 3 do vid[#vid + 1] = em:AddVertex(Vector3.new(V[i], V[i + 1], V[i + 2]) / 1000) end
for i = 1, #UV, 2 do uid[#uid + 1] = em:AddUV(Vector2.new(UV[i], UV[i + 1]) / 10000) end
for i = 1, #N, 3 do nid[#nid + 1] = em:AddNormal(Vector3.new(N[i], N[i + 1], N[i + 2]) / 1000) end
for i = 1, #T, 9 do
	local f = em:AddTriangle(vid[T[i] + 1], vid[T[i + 1] + 1], vid[T[i + 2] + 1])
	em:SetFaceUVs(f, {uid[T[i + 3] + 1], uid[T[i + 4] + 1], uid[T[i + 5] + 1]})
	em:SetFaceNormals(f, {nid[T[i + 6] + 1], nid[T[i + 7] + 1], nid[T[i + 8] + 1]})
end
local byName = {}
for i, b in ipairs(bones) do
	bid[i] = em:AddBone({Name = b.name, CFrame = CFrame.new(b.pos[1], b.pos[2], b.pos[3]), Virtual = false})
	byName[b.name] = bid[i]
end
for i, b in ipairs(bones) do
	if b.parent then em:SetBoneParent(bid[i], byName[b.parent]) end
end
local i, v = 1, 1
while i <= #W do
	local n = W[i]; i += 1
	local ids, ws = {}, {}
	for k = 1, n do ids[k] = bid[W[i] + 1]; ws[k] = W[i + 1] / 1000; i += 2 end
	em:SetVertexBones(vid[v], ids); em:SetVertexBoneWeights(vid[v], ws)
	v += 1
end
-- Probe only: bake to session content the way the lobby's RuntimeBake does and stand the result up in Workspace.
local ok, result, content = pcall(AS.CreateDataModelContentAsync, AS, Content.fromObject(em))
local out = {verts = #vid, faces = #T / 9, bones = #bid, ok = ok, result = tostring(result)}
if ok and result == Enum.CreateContentResult.Success then
	local old = workspace:FindFirstChild("__CounterProbe"); if old then old:Destroy() end
	local part = AS:CreateMeshPartAsync(content, {CollisionFidelity = Enum.CollisionFidelity.Box})
	part.Name = "__CounterProbe"; part.Anchored = true; part.CanCollide = false
	local made = {}
	for _, b in ipairs(bones) do
		local bone = Instance.new("Bone"); bone.Name = b.name
		local pos = Vector3.new(b.pos[1], b.pos[2], b.pos[3])
		made[b.name] = {bone = bone, pos = pos}
		if b.parent then bone.CFrame = CFrame.new(pos - made[b.parent].pos); bone.Parent = made[b.parent].bone
		else bone.CFrame = CFrame.new(pos); bone.Parent = part end
	end
	local cam = workspace.CurrentCamera
	part.CFrame = CFrame.lookAt(cam.CFrame.Position + cam.CFrame.LookVector * 9, cam.CFrame.Position)
	part.Parent = workspace
	made.LeftArm.bone.Transform = CFrame.Angles(0, 0, math.rad(70))
	made.Head.bone.Transform = CFrame.Angles(0, math.rad(40), 0)
	out.size = tostring(part.Size); out.hasSkin = part.HasSkinnedMesh
end
return H:JSONEncode(out)
'''


def chunks(text):
    return [text[i:i + CHUNK] for i in range(0, len(text), CHUNK)]


def mesh(s):
    data = json.loads((EXPORT / 'roblox_mesh.json').read_text())
    first = True
    for key, value in (('V', data['V']), ('UV', data['UV']), ('N', data['N']), ('T', data['T']), ('W', data['W']), ('B', data['bones'])):
        for n, part in enumerate(chunks(json.dumps(value, separators=(',', ':'))), 1):
            s.luau(STAGE % ('true' if first else 'false', json.dumps(f'{key}_{n}'), part))
            first = False
        print('staged', key, flush=True)
    if '--probe' in sys.argv:
        print(json.loads(s.luau(BUILD)))


if __name__ == '__main__':
    s = studio_io.Studio()
    {'mesh': mesh}[sys.argv[1]](s)
