"""Read the Entity's real skinned mesh out of Studio (Edit mode) into input/mesh.json, for offline renders on the real body.

    python3 tools/level1_entity/export_mesh.py

The first motion pass was judged on a capsule figure because the old FBX did not match the live rig; on the real body its
run turned out to be the walk folded double. This reads the live MeshPart (workspace.Entity.char1) through
AssetService:CreateEditableMeshAsync: vertex positions, triangles, the four bones and weights of every vertex, the bone
names and the bones' rest CFrames in mesh space. Nothing in the place is changed (the pieces wait in CoreGui, which is
not saved, and are removed at the end). The mesh is the game's own asset: it stays in this repo's tools as QA input only.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

BUILD = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local AssetService = game:GetService("AssetService")
local CoreGui = game:GetService("CoreGui")
local part = workspace.Entity.char1
local em = AssetService:CreateEditableMeshAsync(Content.fromUri(part.MeshId))
local verts, faces, bones = em:GetVertices(), em:GetFaces(), em:GetBones()
local index = {}
for i, v in ipairs(verts) do index[v] = i - 1 end
local boneIndex, boneRows = {}, {}
for i, b in ipairs(bones) do
	boneIndex[b] = i - 1
	local cf = em:GetBoneCFrame(b)
	local c = {cf:GetComponents()}
	for k = 1, 12 do c[k] = string.format("%.6f", c[k]) end
	boneRows[i] = em:GetBoneName(b) .. "=" .. table.concat(c, ",")
end
local rows = {}
for i, v in ipairs(verts) do
	local p = em:GetPosition(v)
	local vb, vw = em:GetVertexBones(v), em:GetVertexBoneWeights(v)
	local t = {math.round(p.X * 10000), math.round(p.Y * 10000), math.round(p.Z * 10000)}
	for k = 1, 4 do t[#t + 1] = vb[k] and boneIndex[vb[k]] or -1 end
	for k = 1, 4 do t[#t + 1] = vw[k] and math.round(vw[k] * 1000) or 0 end
	rows[i] = table.concat(t, ",")
	if i % 4000 == 0 then task.wait() end
end
local tris = {}
for i, f in ipairs(faces) do
	local fv = em:GetFaceVertices(f)
	tris[i] = index[fv[1]] .. "," .. index[fv[2]] .. "," .. index[fv[3]]
	if i % 4000 == 0 then task.wait() end
end
local size = em:GetSize()
em:Destroy()
local text = table.concat({"SIZE " .. size.X .. "," .. size.Y .. "," .. size.Z .. " PART " .. part.Size.X .. "," .. part.Size.Y .. "," .. part.Size.Z,
	table.concat(boneRows, ";"), table.concat(rows, ";"), table.concat(tris, ";")}, "\\n")
local old = CoreGui:FindFirstChild("QAExport")
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = "QAExport"
local n = 0
for at = 1, #text, 50000 do
	n += 1
	local value = Instance.new("StringValue")
	value.Name = tostring(n)
	value.Value = string.sub(text, at, at + 49999)
	value.Parent = folder
end
folder.Parent = CoreGui
return n .. " pieces, " .. #text .. " characters, " .. #verts .. " vertices, " .. #faces .. " triangles, " .. #bones .. " bones"
'''


def main():
    studio = Studio()
    answer = studio.luau(BUILD)
    print(answer)
    pieces = int(answer.split()[0])
    text = ''.join(studio.luau(f'return game:GetService("CoreGui").QAExport["{i}"].Value') for i in range(1, pieces + 1))
    print(studio.luau('game:GetService("CoreGui").QAExport:Destroy() return "pieces removed"'))
    head, bones, verts, tris = text.split('\n')
    mesh = {'about': 'workspace.Entity.char1 as read from Studio; positions in mesh space x10000, weights x1000', 'head': head,
            'bones': [row.split('=')[0] for row in bones.split(';')],
            'bone_cframes': [[float(x) for x in row.split('=')[1].split(',')] for row in bones.split(';')],
            'verts': [int(x) for row in verts.split(';') for x in row.split(',')],
            'tris': [int(x) for row in tris.split(';') for x in row.split(',')]}
    out = HERE / 'input' / 'mesh.json'
    out.write_text(json.dumps(mesh, separators=(',', ':')))
    print(f'{out}: {len(mesh["verts"]) // 11} vertices, {len(mesh["tris"]) // 3} triangles, {len(mesh["bones"])} bones, {out.stat().st_size // 1024} KB; {head}')


if __name__ == '__main__':
    main()
