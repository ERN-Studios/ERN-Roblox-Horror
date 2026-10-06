"""Put the Reach's meshes (build_reach.py) in the place: ReplicatedStorage.LobbyTunnelReach.Meshes.

    python3 tools/lobby_reach/install_reach.py            # every piece
    python3 tools/lobby_reach/install_reach.py claw eye   # only these
    python3 tools/lobby_reach/install_reach.py --source   # no upload: keep the numbers for the server to bake

Each piece becomes a MeshPart template that the Lobby Tunnel Reach Client clones. Two ways, tried in this order:

1. A mesh ASSET, uploaded from the session with AssetService:CreateAssetAsync to the group that owns the place. Its
   id is kept in reach_mesh_ids.json with the hash of the numbers it was made from; unchanged numbers are not
   uploaded twice. This call comes and goes (it answered "not available yet" for most of 2026-10-06).
2. When that is refused: the numbers go to ServerStorage.LobbyTunnelReachSource and the server script (Lobby Tunnel
   Reach) bakes the template itself once per server, the way the Level 6 slides and the Counter are baked.

Either way the template carries `Offset` (where the piece's own origin is, measured from the middle of its box) and
the folder carries `Hand` (the palm, the digits and the poses, JSON) from the export.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

EXPORT = ROOT / 'artifacts' / 'lobby-reach-20261006' / 'export' / 'reach_meshes.json'
IDS = Path(__file__).with_name('reach_mesh_ids.json')

HEAD = '''
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")
local root = ReplicatedStorage:FindFirstChild("LobbyTunnelReach")
if not root then root = Instance.new("Folder"); root.Name = "LobbyTunnelReach"; root.Parent = ReplicatedStorage end
local kit = root:FindFirstChild("Meshes")
if not kit then kit = Instance.new("Folder"); kit.Name = "Meshes"; kit.Parent = root end
'''

UPLOAD = HEAD + '''
local NAME, KNOWN, OFFSET, UPLOAD = %s, %s, Vector3.new(%s), %s
local data = HttpService:JSONDecode([==[%s]==])
local id = KNOWN
if id == 0 then
	if not UPLOAD then return "SOURCE" end
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
		return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Lobby Reach " .. NAME,
			Description = "Lobby tunnel easter egg", CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
	end)
	em:Destroy()
	if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(made) end
	id = made
end
local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(id), {CollisionFidelity = Enum.CollisionFidelity.Box})
part.Name = NAME
part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
part.Material, part.Color = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)
part:SetAttribute("Offset", OFFSET)
part:SetAttribute("AssetId", id)
local old = kit:FindFirstChild(NAME)
if old then old:Destroy() end
part.Parent = kit
local source = ServerStorage:FindFirstChild("LobbyTunnelReachSource")
local stale = source and source:FindFirstChild(NAME)
if stale then stale:Destroy() end
return "OK " .. id .. " size " .. tostring(part.Size)
'''

SOURCE = HEAD + '''
local FIRST, INDEX, NAME, OFFSET = %s, %d, %s, Vector3.new(%s)
local store = ServerStorage:FindFirstChild("LobbyTunnelReachSource")
if not store then store = Instance.new("Folder"); store.Name = "LobbyTunnelReachSource"; store.Parent = ServerStorage end
local item = store:FindFirstChild(NAME)
if FIRST and item then item:Destroy(); item = nil end
if not item then item = Instance.new("Folder"); item.Name = NAME; item.Parent = store end
local v = Instance.new("StringValue")
v.Name = string.format("Part_%%02d", INDEX)
v.Value = [==[%s]==]
v.Parent = item
item:SetAttribute("Parts", INDEX)
item:SetAttribute("Offset", OFFSET)
local old = kit:FindFirstChild(NAME)           -- a template of older numbers would be cloned instead of the new bake
if FIRST and old then old:Destroy() end
return "source " .. NAME .. " part " .. INDEX .. ", " .. #v.Value .. " characters"
'''

HAND = HEAD + '''
root:SetAttribute("Hand", [==[%s]==])
local names = {}
for _, c in ipairs(kit:GetChildren()) do names[#names + 1] = c.Name end
local source = ServerStorage:FindFirstChild("LobbyTunnelReachSource")
local waiting = {}
for _, c in ipairs(source and source:GetChildren() or {}) do waiting[#waiting + 1] = c.Name end
table.sort(names); table.sort(waiting)
return "templates: " .. table.concat(names, " ") .. " | to be baked by the server: " .. table.concat(waiting, " ")
'''


def main():
    args = sys.argv[1:]
    source_only = '--source' in args
    wanted = [a for a in args if not a.startswith('--')]
    export = json.loads(EXPORT.read_text())
    known = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    upload = not source_only
    for name, mesh in export['meshes'].items():
        if wanted and name not in wanted:
            continue
        numbers = {k: mesh[k] for k in ('verts', 'normals', 'colours', 'tris')}
        text = json.dumps(numbers, separators=(',', ':'))
        digest = hashlib.sha256(text.encode()).hexdigest()
        have = known.get(name, {})
        asset = have.get('id', 0) if have.get('sha256') == digest else 0
        offset = ', '.join(format(-v, 'g') for v in mesh['offset'])     # the origin, seen from the box's middle
        answer = 'SOURCE'
        if asset or upload:
            answer = studio.luau(UPLOAD % (json.dumps(name), asset, offset, 'true' if upload else 'false', text))
        print(name, '->', answer, flush=True)
        if answer.startswith('OK '):
            known[name] = {'id': int(answer.split()[1]), 'sha256': digest}
            IDS.write_text(json.dumps(known, indent=1, sort_keys=True) + '\n')
            continue
        if answer.startswith('FAILED'):
            upload = False                                               # refused once: do not ask eight more times
        size = 150000
        for i, start in enumerate(range(0, len(text), size), 1):
            print(' ', studio.luau(SOURCE % ('true' if i == 1 else 'false', i, json.dumps(name), offset, text[start:start + size])), flush=True)
    print(studio.luau(HAND % json.dumps(export['hand'], separators=(',', ':'))), flush=True)


if __name__ == '__main__':
    main()
