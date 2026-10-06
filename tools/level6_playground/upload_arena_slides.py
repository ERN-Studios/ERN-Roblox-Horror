"""Upload the Arena's moulded slides and tubes as mesh assets, straight from the session, and put them in
ReplicatedStorage.Level6ArenaSlideKit as MeshParts.

    python3 tools/level6_playground/upload_arena_slides.py [name ...]

build_arena.py writes every slide as plain numbers (export/slide_meshes.json). For each one this builds an
EditableMesh in Studio, uploads it with AssetService:CreateAssetAsync to the group that owns the place, and
makes a MeshPart from the new asset. The asset ids are kept in arena_slide_ids.json; a mesh whose numbers have
not changed since its last upload is not uploaded again. Run import_arena.py --finish afterwards to place them.
(CreateAssetAsync answered "not available yet" from this Mac on 2026-10-03 and worked on 2026-10-06; before
that the only way was File > Import of the GLB, by hand or by synthetic clicks.)
"""
import hashlib, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_to_studio import Studio   # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'artifacts' / 'level6-arena-20261006' / 'export' / 'slide_meshes.json'
IDS = Path(__file__).with_name('arena_slide_ids.json')
KIT = 'Level6ArenaSlideKit'

LUAU = '''
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NAME, KNOWN = %s, %s
local data = game:GetService("HttpService"):JSONDecode([==[%s]==])
local id = KNOWN
if id == 0 then
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
		if i %% 9000 == 1 then task.wait() end
	end
	local ok, result, made = pcall(function()
		return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Level 6 " .. NAME, Description = "Level 6 arena slide",
			CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
	end)
	em:Destroy()
	if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(made) end
	id = made
end
local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {CollisionFidelity = Enum.CollisionFidelity.Box})
part.Name = NAME
part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
part.Material, part.Color = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)
local kit = ReplicatedStorage:FindFirstChild(%s)
if not kit then
	kit = Instance.new("Folder")
	kit.Name = %s
	kit.Parent = ReplicatedStorage
end
kit:SetAttribute("Upright", true)      -- these were not through File > Import, which turns a mesh half a turn
local old = kit:FindFirstChild(NAME)
if old then old:Destroy() end
part.Parent = kit
return string.format("OK %%d size %%.1f x %%.1f x %%.1f", id, part.Size.X, part.Size.Y, part.Size.Z)
'''


def main():
    meshes = json.loads(DATA.read_text())
    known = json.loads(IDS.read_text()) if IDS.exists() else {}
    wanted = sys.argv[1:] or list(meshes)
    studio = Studio()
    for name in wanted:
        payload = json.dumps(meshes[name], separators=(',', ':'))
        digest = hashlib.sha256(payload.encode()).hexdigest()
        have = known.get(name, {})
        asset = have.get('id', 0) if have.get('sha256') == digest else 0
        answer = studio.luau(LUAU % (json.dumps(name), asset, payload, json.dumps(KIT), json.dumps(KIT)))
        print(name, answer, flush=True)
        if answer.startswith('OK '):
            known[name] = {'id': int(answer.split()[1]), 'sha256': digest}
            IDS.write_text(json.dumps(known, indent=1))


if __name__ == '__main__':
    main()
