"""Make the tunnel lobby's DJ booth permanent assets, so the mall lobby can wear it (Studio in Edit).

    /usr/local/bin/python3 tools/lobby_mall/install_booth.py

BOOTH_FROM_TUNNEL_20261013 (owner: "Replace the new DJ booth in the mall lobby with the DJ booth from the live tunnel
lobby as it's much better"). The tunnel lobby's booth only ever existed for one server session at a time: its meshes
and its texture atlas are numbers in ServerStorage.LobbyReimaginedBlenderSource20261001R4 that RuntimeBake turns into
session content at every start. This reads the same numbers in Edit and uploads them once as group assets: the
1024 x 1024 atlas as an image and seven meshes (stage deck, rear rail, console, speaker tower, subwoofer, two vinyl
discs). Ids, sizes and centres go to booth_ids.json, which import_mall.py reads. Nothing is sent from this Mac.
"""
import json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

IDS = HERE / 'booth_ids.json'
FAMILIES = ['StageDeck', 'StageRearRail', 'DJConsole', 'SpeakerTower', 'Subwoofer', 'VinylDiscAmber', 'VinylDiscCyan']

HEAD = '''
local SS, AS = game:GetService("ServerStorage"), game:GetService("AssetService")
local ENC, HS = game:GetService("EncodingService"), game:GetService("HttpService")
local source = assert(SS:FindFirstChild("LobbyReimaginedBlenderSource20261001R4"), "the tunnel lobby's source is not in the place")
local function decode(folder)
	local kids, text = folder:GetChildren(), {}
	table.sort(kids, function(a, b) return a.Name < b.Name end)
	for i, piece in ipairs(kids) do text[i] = piece.Value end
	return ENC:DecompressBuffer(ENC:Base64Decode(buffer.fromstring(table.concat(text))), Enum.CompressionAlgorithm.Zstd)
end
local function upload(object, kind, name)
	local ok, result, id = pcall(function()
		return AS:CreateAssetAsync(object, kind, {Name = name, Description = "Lobby DJ booth (tools/lobby_mall/install_booth.py)",
			CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group})
	end)
	object:Destroy()
	if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
	return id
end
'''

ATLAS = HEAD + '''
local pixels = decode(source.AtlasPixels)
assert(buffer.len(pixels) == 1024 * 1024 * 4, "incomplete atlas")
local topDown = buffer.create(buffer.len(pixels))            -- Blender's rows are bottom-up
for row = 0, 1023 do buffer.copy(topDown, row * 4096, pixels, (1023 - row) * 4096, 4096) end
local image = AS:CreateEditableImage({Size = Vector2.new(1024, 1024)})
image:WritePixelsBuffer(Vector2.zero, image.Size, topDown)
return tostring(upload(image, Enum.AssetType.Image, "LobbyBooth_atlas"))
'''

MESH = HEAD + '''
local FAMILY = %s
local manifest = HS:JSONDecode(buffer.tostring(decode(source.ManifestJSON)))
local chunk
for _, c in ipairs(manifest.chunks) do if c.family == FAMILY then assert(not chunk, "more than one chunk"); chunk = c end end
assert(chunk and chunk.materialKey == "atlas", "no atlas chunk for " .. FAMILY)
local raw = decode(source.Meshes:FindFirstChild(tostring(chunk.id)))
assert(buffer.len(raw) == chunk.bytes and buffer.readu32(raw, 0) == 0x364D564C, "wrong mesh data")
local nv, nn, nu, nf = buffer.readu32(raw, 4), buffer.readu32(raw, 8), buffer.readu32(raw, 12), buffer.readu32(raw, 16)
local em = AS:CreateEditableMesh()
local V, N, U, at = {}, {}, {}, 20
for i = 1, nv do V[i] = em:AddVertex(Vector3.new(buffer.readf32(raw, at), buffer.readf32(raw, at + 4), buffer.readf32(raw, at + 8))); at += 12 end
for i = 1, nn do N[i] = em:AddNormal(Vector3.new(buffer.readf32(raw, at), buffer.readf32(raw, at + 4), buffer.readf32(raw, at + 8))); at += 12 end
for i = 1, nu do U[i] = em:AddUV(Vector2.new(buffer.readf32(raw, at), 1 - buffer.readf32(raw, at + 4))); at += 8 end
for i = 1, nf do
	local v, n, u = {}, {}, {}
	for corner = 1, 3 do
		v[corner], n[corner], u[corner] = V[buffer.readu32(raw, at) + 1], N[buffer.readu32(raw, at + 4) + 1], U[buffer.readu32(raw, at + 8) + 1]
		at += 12
	end
	local face = em:AddTriangle(v[1], v[2], v[3])
	em:SetFaceNormals(face, n); em:SetFaceUVs(face, u)
end
local id = upload(em, Enum.AssetType.Mesh, "LobbyBooth_" .. FAMILY)
return HS:JSONEncode({id = id, size = chunk.size, centre = chunk.center, triangles = nf})
'''


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    studio = Studio()
    if not isinstance(ids.get('atlas'), int):
        answer = studio.luau(ATLAS)
        print('atlas ->', answer, flush=True)
        ids['atlas'] = int(answer)
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    for family in FAMILIES:
        if isinstance(ids.get(family, {}).get('id'), int):
            continue
        answer = json.loads(studio.luau(MESH % json.dumps(family)))
        print(f'{family:16s} -> {answer}', flush=True)
        if not isinstance(answer['id'], int):
            raise SystemExit('stopped: ' + str(answer['id']))
        ids[family] = answer
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    print('booth_ids.json written; next: import_mall.py')


if __name__ == '__main__':
    main()
