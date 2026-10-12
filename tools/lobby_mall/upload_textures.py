"""Upload the mall lobby's texture maps as image assets owned by the experience's group (Studio in Edit mode).

    /usr/local/bin/python3 tools/lobby_mall/upload_textures.py            # every map that has no id yet
    /usr/local/bin/python3 tools/lobby_mall/upload_textures.py terrazzo   # only these sets

Run make_pbr.py first: the build's own normal and roughness maps are flat. Same route as tools/level6_playground/pbr/upload_pbr.py (zstd + base64 into StringValues, EditableImage,
AssetService:CreateAssetAsync; needs that Beta Feature). Ids go to texture_ids.json, which import_mall.py reads.
Left out on purpose: the three suit patterns (the game's own suit models stand on the plinths), the pad's ring and the
sign face (a material tiles in world space, so neither would sit where it should; the importer draws them itself).
"""
import base64, hashlib, json, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

BUILD = ROOT / 'artifacts' / 'lobby-mall-20261011' / 'build'
IDS = HERE / 'texture_ids.json'
SKIP = {'pool_suit', 'survey_suit', 'false_suit', 'pad', 'sign_face', 'static'}   # static: the screen glows (Neon)
PIECE, PER_CALL = 199000, 4

STASH = '''
local NAME, FIRST = %s, %s
local ServerStorage = game:GetService("ServerStorage")
local store = ServerStorage:FindFirstChild("MallTextureStash")
if not store then store = Instance.new("Folder"); store.Name = "MallTextureStash"; store.Parent = ServerStorage end
local item = store:FindFirstChild(NAME)
if FIRST and item then item:Destroy(); item = nil end
if not item then item = Instance.new("Folder"); item.Name = NAME; item.Parent = store end
for i, text in ipairs({%s}) do
	local v = Instance.new("StringValue")
	v.Name, v.Value = string.format("P%%04d", %d + i), text
	v.Parent = item
end
return #item:GetChildren()
'''

MAKE = '''
local NAME, SIZE, COUNT = %s, %d, %d
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local store = game:GetService("ServerStorage"):FindFirstChild("MallTextureStash")
local item = store and store:FindFirstChild(NAME)
assert(item and #item:GetChildren() == COUNT, "the pieces are not all there")
local text = table.create(COUNT)
for i = 1, COUNT do text[i] = item:FindFirstChild(string.format("P%%04d", i)).Value end
local pixels = EncodingService:DecompressBuffer(EncodingService:Base64Decode(buffer.fromstring(table.concat(text))), Enum.CompressionAlgorithm.Zstd)
assert(buffer.len(pixels) == SIZE * SIZE * 4, "unpacked " .. buffer.len(pixels) .. " bytes")
local image = AssetService:CreateEditableImage({Size = Vector2.new(SIZE, SIZE)})
assert(image, "no EditableImage (memory budget)")
image:WritePixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE), pixels)
local ok, result, id = pcall(function()
	return AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {
		Name = "Mall_" .. NAME, Description = "Mall lobby texture (tools/lobby_mall)",
		CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group,
	})
end)
image:Destroy()
item:Destroy()
if #store:GetChildren() == 0 then store:Destroy() end
if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
return "OK " .. tostring(id)
'''


def main():
    only = sys.argv[1:]
    materials = json.loads((BUILD / 'mall.json').read_text())['materials']
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    hashes = ids.setdefault('_sha256', {})
    studio = Studio()
    # one picture that is not a surface: the lamps' sheen on the floor (make_pbr.py), key `sheen`
    jobs = [(key, kind, BUILD / m[field]) for key, m in materials.items()
            if m.get('colour_map') and key not in SKIP
            for kind, field in (('colour', 'colour_map'), ('normal', 'normal_map'), ('roughness', 'roughness_map'))]
    jobs.append(('sheen', 'colour', BUILD / 'textures_pbr' / 'sheen.png'))
    for key, kind, path in jobs:
        if only and key not in only:
            continue
        better = BUILD / 'textures_pbr' / f'{key}_{kind}.png'     # make_pbr.py (the build's own are flat) and corrected colour maps
        if better.exists():
            path = better
        name = f'{key}_{kind}'
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(key, {}).get(kind) and hashes.get(name) == digest:
            continue
        im = Image.open(path).convert('RGBA')
        assert im.size[0] == im.size[1], path.name
        # from a FILE, not a pipe: only then does zstd write the content size that DecompressBuffer insists on
        with tempfile.NamedTemporaryFile(suffix='.rgba') as raw:
            raw.write(im.tobytes())
            raw.flush()
            packed = subprocess.run(['zstd', '-19', '--no-check', '-q', '-c', raw.name], capture_output=True, check=True).stdout
        text = base64.b64encode(packed).decode()
        pieces = [text[i:i + PIECE] for i in range(0, len(text), PIECE)]
        for start in range(0, len(pieces), PER_CALL):
            body = ', '.join(f'[==[{p}]==]' for p in pieces[start:start + PER_CALL])
            studio.luau(STASH % (json.dumps(name), 'true' if start == 0 else 'false', body, start))
        answer = studio.luau(MAKE % (json.dumps(name), im.size[0], len(pieces)))
        print(f'{name:28s} {len(packed) // 1024:4d} KB -> {answer}', flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        ids.setdefault(key, {})[kind] = int(answer.split()[1])
        hashes[name] = digest
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    print('texture_ids.json written; next: import_mall.py')


if __name__ == '__main__':
    main()
