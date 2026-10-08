"""Put the exit sign (build_sign.py) in the place: ServerStorage.Level3Assets.ExitSign.

    python3 tools/level3_exit_signs/install_sign.py

Each of the two meshes is uploaded from the session to the group that owns the place
(AssetService:CreateAssetAsync, a Studio Beta Feature: if it answers "not available yet", switch it on under
File > Beta Features). Ids are kept in exit_sign_mesh_ids.json with the hash of the numbers they were made from, so
unchanged numbers are not uploaded twice. The template is a Model whose PrimaryPart `Origin` sits where the rods
meet the ceiling, looking along the model's -Z; the lettered face is toward +Z. Level 3 World Builder clones it.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

EXPORT = ROOT / 'artifacts' / 'level3-exit-signs-20261008' / 'export' / 'exit_sign.json'
IDS = Path(__file__).with_name('exit_sign_mesh_ids.json')

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
		return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Level 3 " .. NAME,
			Description = "Level 3 exit corridor sign", CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
	end)
	em:Destroy()
	if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(made) end
	id = made
end
return "OK " .. id
'''

TEMPLATE = '''
local AssetService = game:GetService("AssetService")
local ServerStorage = game:GetService("ServerStorage")
local assets = ServerStorage:FindFirstChild("Level3Assets")
assert(assets, "ServerStorage.Level3Assets is missing")
local SPEC = game:GetService("HttpService"):JSONDecode([==[%s]==])
local model = Instance.new("Model")
model.Name = "ExitSign"
local origin = Instance.new("Part")
origin.Name, origin.Size, origin.Transparency = "Origin", Vector3.new(0.2, 0.2, 0.2), 1
origin.Anchored, origin.CanCollide, origin.CanTouch, origin.CanQuery, origin.CastShadow = true, false, false, false, false
origin.CFrame = CFrame.new()
origin.Parent = model
model.PrimaryPart = origin
local report = {}
for _, item in ipairs(SPEC) do
	local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(item.id), {CollisionFidelity = Enum.CollisionFidelity.Box})
	part.Name = item.name
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
	part.CFrame = CFrame.new(item.middle[1], item.middle[2], item.middle[3])    -- a MeshPart's origin is the middle of its box
	part:SetAttribute("AssetId", item.id)
	part.Parent = model
	table.insert(report, item.name .. " " .. tostring(part.Size))
end
model:SetAttribute("Built", "tools/level3_exit_signs")
local old = assets:FindFirstChild("ExitSign")
if old then old:Destroy() end
model.Parent = assets
return "template: " .. table.concat(report, " | ")
'''


def main():
    export = json.loads(EXPORT.read_text())
    known = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    spec = []
    for name, mesh in export['meshes'].items():
        numbers = {k: mesh[k] for k in ('verts', 'normals', 'colours', 'tris')}
        text = json.dumps(numbers, separators=(',', ':'))
        digest = hashlib.sha256(text.encode()).hexdigest()
        have = known.get(name, {})
        asset = have.get('id', 0) if have.get('sha256') == digest else 0
        answer = studio.luau(UPLOAD % (json.dumps(name), asset, text))
        print(name, '->', answer, flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('upload refused; nothing installed')
        asset = int(answer.split()[1])
        known[name] = {'id': asset, 'sha256': digest}
        IDS.write_text(json.dumps(known, indent=1, sort_keys=True) + '\n')
        spec.append({'name': name, 'id': asset, 'middle': mesh['middle']})
    print(studio.luau(TEMPLATE % json.dumps(spec)), flush=True)


if __name__ == '__main__':
    main()
