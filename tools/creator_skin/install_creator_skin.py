"""Put the creator skin in the open Studio place (Edit mode): its pictures, its topper mesh and both templates.

    /usr/local/bin/python3 tools/creator_skin/install_creator_skin.py            # whatever has no id yet
    /usr/local/bin/python3 tools/creator_skin/install_creator_skin.py --card     # the shop picture again

CREATOR_SKIN_20261012. From artifacts/creator-skin-20261012 (build_creator_skin.py): the colour map and the shop
picture go up as group images, the topper as a group mesh (AssetService:CreateAssetAsync, as the lobby creature's
pieces went); ids are kept in creator_skin_ids.json beside this file. Then ServerStorage gets
  HazmatSkin_CreatorGold_20260924      a copy of a suit template wearing the new map (the name HazmatSkinVisuals looks up)
  HazmatCreatorGoldTopper_20261012     one MeshPart, as every topper is, its attribute `Centre` saying where its
                                       middle sits about the wearer's UpperTorso (HazmatSkinVisuals' X / Y / Z)
"""
import base64, json, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

OUT = ROOT / 'artifacts' / 'creator-skin-20261012'
IDS = HERE / 'creator_skin_ids.json'
PIECE = 199000

STASH = '''
local store = game:GetService("ServerStorage"):FindFirstChild("CreatorSkinStash")
if %s and store then store:Destroy(); store = nil end
if not store then store = Instance.new("Folder"); store.Name = "CreatorSkinStash"; store.Parent = game:GetService("ServerStorage") end
for i, text in ipairs({%s}) do
	local v = Instance.new("StringValue")
	v.Name, v.Value = string.format("P%%04d", %d + i), text
	v.Parent = store
end
return #store:GetChildren()
'''

IMAGE = '''
local W, H, COUNT, TITLE = %d, %d, %d, %s
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local store = game:GetService("ServerStorage"):FindFirstChild("CreatorSkinStash")
assert(store and #store:GetChildren() == COUNT, "the pieces are not all there")
local text = table.create(COUNT)
for i = 1, COUNT do text[i] = store:FindFirstChild(string.format("P%%04d", i)).Value end
local pixels = EncodingService:DecompressBuffer(EncodingService:Base64Decode(buffer.fromstring(table.concat(text))), Enum.CompressionAlgorithm.Zstd)
assert(buffer.len(pixels) == W * H * 4, "unpacked " .. buffer.len(pixels) .. " bytes")
local image = AssetService:CreateEditableImage({Size = Vector2.new(W, H)})
image:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), pixels)
local ok, result, id = pcall(function()
	return AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {Name = TITLE, Description = "Creator skin (tools/creator_skin)",
		CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
end)
image:Destroy(); store:Destroy()
if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
return "OK " .. tostring(id)
'''

MESH = '''
local AssetService = game:GetService("AssetService")
local data = game:GetService("HttpService"):JSONDecode([==[%s]==])
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
local ok, result, id = pcall(function()
	return AssetService:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = "Creator Gold topper", Description = "Creator skin (tools/creator_skin)",
		CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
end)
em:Destroy()
if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
return "OK " .. tostring(id)
'''

TEMPLATES = '''
local ServerStorage = game:GetService("ServerStorage")
local AssetService = game:GetService("AssetService")
local MAP, MESH, CENTRE = %d, %d, Vector3.new(%s)
local out = {}
local source = ServerStorage:FindFirstChild("HazmatSkin_BlacksiteDirector_20260924")
assert(source and source:IsA("Model"), "no suit template to copy")
local old = ServerStorage:FindFirstChild("HazmatSkin_CreatorGold_20260924")
if old then old:Destroy() end
local suit = source:Clone()
suit.Name = "HazmatSkin_CreatorGold_20260924"
local mesh = suit:FindFirstChild("char1", true)
local surface = mesh:FindFirstChildOfClass("SurfaceAppearance")
surface.ColorMap = "rbxassetid://" .. MAP
surface.Color = Color3.new(1, 1, 1)
suit.Parent = ServerStorage
out[#out + 1] = "suit template wears " .. surface.ColorMap
local stale = ServerStorage:FindFirstChild("HazmatCreatorGoldTopper_20261012")
if stale then stale:Destroy() end
local part = AssetService:CreateMeshPartAsync(Content.fromAssetId(MESH), {CollisionFidelity = Enum.CollisionFidelity.Box})
part.Name = "CreatorGoldTopper"
part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery, part.CastShadow = true, false, false, false, false
part.Material, part.Color = Enum.Material.SmoothPlastic, Color3.new(1, 1, 1)
part.RenderFidelity = Enum.RenderFidelity.Precise       -- at the automatic level of detail the aerial's rod was dropped at eight studs
local topper = Instance.new("Model")
topper.Name = "HazmatCreatorGoldTopper_20261012"
part.Parent = topper
topper.PrimaryPart = part
topper:SetAttribute("Centre", CENTRE)
topper.Parent = ServerStorage
out[#out + 1] = "topper " .. tostring(part.Size) .. " mesh " .. part.MeshId
return table.concat(out, "; ")
'''


def upload_image(studio, path, title, crop=False):
    im = Image.open(path).convert('RGBA')
    if crop:                                        # the shop's cards are tight portraits: the figure with a little air
        box = im.getbbox()
        air = int(0.05 * (box[3] - box[1]))
        im = im.crop((max(0, box[0] - air), max(0, box[1] - air), min(im.size[0], box[2] + air), min(im.size[1], box[3] + air)))
    with tempfile.NamedTemporaryFile(suffix='.rgba') as raw:
        raw.write(im.tobytes()); raw.flush()
        packed = subprocess.run(['zstd', '-19', '--no-check', '-q', '-c', raw.name], capture_output=True, check=True).stdout
    text = base64.b64encode(packed).decode()
    pieces = [text[i:i + PIECE] for i in range(0, len(text), PIECE)]
    for start in range(0, len(pieces), 4):
        body = ', '.join(f'[==[{p}]==]' for p in pieces[start:start + 4])
        studio.luau(STASH % ('true' if start == 0 else 'false', body, start))
    answer = studio.luau(IMAGE % (im.size[0], im.size[1], len(pieces), json.dumps(title)))
    print(f'{path.name:22s} {len(packed) // 1024:5d} KB -> {answer}', flush=True)
    if not answer.startswith('OK '):
        raise SystemExit('stopped: ' + answer)
    return int(answer.split()[1])


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    if 'map' not in ids or '--map' in sys.argv:
        ids['map'] = upload_image(studio, OUT / 'creator_gold.png', 'CreatorGold_suit_map')
    if 'card' not in ids or '--card' in sys.argv:
        ids['card'] = upload_image(studio, OUT / 'card.png', 'CreatorGold_card', crop=True)
    topper = json.loads((OUT / 'topper.json').read_text())
    if 'mesh' not in ids or '--mesh' in sys.argv:
        answer = studio.luau(MESH % json.dumps({k: topper[k] for k in ('verts', 'normals', 'colours', 'tris')}, separators=(',', ':')))
        print('topper mesh ->', answer, flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        ids['mesh'] = int(answer.split()[1])
    ids['centre'] = topper['centre']
    IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    print(studio.luau(TEMPLATES % (ids['map'], ids['mesh'], ', '.join(map(str, topper['centre'])))))
    print('ids:', json.dumps(ids))


if __name__ == '__main__':
    main()
