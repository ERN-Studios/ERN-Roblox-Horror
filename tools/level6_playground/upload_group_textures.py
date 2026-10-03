"""Upload the Level 6 texture overlays as images owned by the experience's group.

    python3 tools/level6_playground/upload_group_textures.py

Images uploaded with the MCP upload_image tool belong to the user, and the group-owned experience may not
use them ("The experience doesn't have access permission to use asset id ..."). This builds each image as an
EditableImage inside Studio and calls AssetService:CreateAssetAsync with the place's group as creator, then
rewrites textures.json.
"""
import base64, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import import_to_studio as studio_io
import make_textures as mt

HERE = Path(__file__).parent
SIZE = 256
IMAGES = {
    'net': mt.net(cells=4, cord=0.16),
    'foam_seams': mt.foam_seams(),
    'grime': mt.grime(),
    'padding': mt.padding(),
}

UPLOAD = '''
local NAME, SIZE, B64 = %s, %d, "%s"
local AssetService = game:GetService("AssetService")
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local lookup = {}
for i = 1, 64 do lookup[string.byte(alphabet, i)] = i - 1 end
local n = #B64
local pad = (string.sub(B64, -2) == "==" and 2) or (string.sub(B64, -1) == "=" and 1) or 0
local out = buffer.create(n // 4 * 3 - pad)
local o = 0
for i = 1, n, 4 do
	local a, b, c, d = string.byte(B64, i, i + 3)
	local v = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
	buffer.writeu8(out, o, v // 65536); o += 1
	if o < buffer.len(out) then buffer.writeu8(out, o, (v // 256) %% 256); o += 1 end
	if o < buffer.len(out) then buffer.writeu8(out, o, v %% 256); o += 1 end
end
local image = AssetService:CreateEditableImage({Size = Vector2.new(SIZE, SIZE)})
image:WritePixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE), out)
local result, id = AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {
	Name = "Level6Playground_" .. NAME, Description = "Level 6 Indoor Playground texture overlay",
	CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group,
})
image:Destroy()
if result ~= Enum.CreateAssetResult.Success then error("CreateAssetAsync " .. tostring(result)) end
return tostring(id)
'''


def pixels(fn):
    raw = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            raw.extend(int(max(0, min(255, round(c)))) for c in fn(x, y))
    return bytes(raw)


def main():
    s = studio_io.Studio()
    ids = json.loads((HERE / 'textures.json').read_text())
    for name, fn in IMAGES.items():
        b64 = base64.b64encode(pixels(fn)).decode()
        asset = s.luau(UPLOAD % (json.dumps(name), SIZE, b64)).strip()
        ids[name] = 'rbxassetid://' + asset
        print(name, ids[name], flush=True)
    (HERE / 'textures.json').write_text(json.dumps(ids, indent=1))


if __name__ == '__main__':
    main()
