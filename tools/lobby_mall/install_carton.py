"""Put the shop's product carton in the open Studio place (Edit mode): ServerStorage.MallShopCarton.

    /usr/local/bin/python3 tools/lobby_mall/install_carton.py

MALL_CARTON_20261013. From artifacts/lobby-mall-20261011/carton/carton.json (build_carton.py). The mesh goes up once
as a group mesh (the Halloween kit's route; its id and hash are kept in carton_ids.json beside this file), then one
MeshPart named MallShopCarton is left in ServerStorage. LobbyShopDisplay clones it for every product over the mall
stand's buy spots and prints the label on it; without it the game falls back to a plain cardboard-coloured block.
"""
import hashlib, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
sys.path.insert(0, str(HERE))
from import_to_studio import Studio   # noqa: E402
from install_halloween import MESH, J  # noqa: E402   (the same EditableMesh upload)

IDS = HERE / 'carton_ids.json'

PLACE = '''
assert(not game:GetService("RunService"):IsRunning(), "Edit mode only")
local ServerStorage = game:GetService("ServerStorage")
local old = ServerStorage:FindFirstChild("MallShopCarton")
if old then old:Destroy() end
local part = game:GetService("AssetService"):CreateMeshPartAsync(Content.fromAssetId(%d), {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise})
part.Name = "MallShopCarton"
part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
part.Material, part.Color = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)
part:SetAttribute("Build", "MALL_CARTON_20261013")
part.Parent = ServerStorage
return "MallShopCarton " .. tostring(part.Size) .. " mesh " .. part.MeshId
'''


def main():
    mesh = json.loads((ROOT / 'artifacts' / 'lobby-mall-20261011' / 'carton' / 'carton.json').read_text())
    body = {k: mesh[k] for k in ('verts', 'normals', 'colours', 'tris')}
    digest = hashlib.sha256(J(body).encode()).hexdigest()
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    if ids.get('sha256') != digest:
        upload = MESH.replace('"Halloween_" .. ', '"Mall_" .. ').replace('Mall lobby Halloween kit', 'Mall lobby shop carton')
        answer = studio.luau(upload % (J(body), json.dumps('carton')))
        print('carton', mesh['triangles'], 'triangles ->', answer, flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        ids = {'id': int(answer.split()[1]), 'sha256': digest}
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    print(studio.luau(PLACE % ids['id']))


if __name__ == '__main__':
    main()
