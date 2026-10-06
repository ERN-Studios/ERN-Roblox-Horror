"""Upload the Level 6 PBR pictures as image assets owned by the experience's group, from the session.

    python3 tools/level6_playground/pbr/upload_pbr.py                 # every picture that is not uploaded yet
    python3 tools/level6_playground/pbr/upload_pbr.py foam_floor      # only this set (or net_knotted)
    python3 tools/level6_playground/pbr/upload_pbr.py --again ...     # upload even if this exact picture already has an id

Needs Studio's Beta Feature `CreateAssetAsync` (File > Beta Features; the owner switched it on on 2026-10-07).
Without it AssetService answers "not available yet" and collect_ids.py is the way (an Asset Manager import).

How a 1024 x 1024 picture gets into Studio through a text channel: the PNG is unpacked here to RGBA, packed with
zstd, written as base64 and sent in pieces into StringValues (a StringValue holds under 200 000 characters, and
nothing but instances survives from one execute_luau call to the next). The last call joins the pieces,
EncodingService unpacks them into a buffer, the buffer goes into an EditableImage and AssetService:CreateAssetAsync
makes the asset. The ids go to pbr_ids.json together with the hash of the PNG they were made from.
"""
import base64
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))
from import_to_studio import Studio   # noqa: E402

MAPS = ROOT / 'assets' / 'level6-pbr-20261006'
SETS = json.loads((MAPS / 'sets.json').read_text())
IDS = HERE / 'pbr_ids.json'
PIECE, PER_CALL = 199000, 4                              # characters in a StringValue, StringValues made per call

STASH = '''
local NAME, FIRST = %s, %s
local store = game:GetService("ServerStorage"):FindFirstChild("L6PBRStash")
if not store then store = Instance.new("Folder"); store.Name = "L6PBRStash"; store.Parent = game:GetService("ServerStorage") end
local item = store:FindFirstChild(NAME)
if FIRST and item then item:Destroy(); item = nil end
if not item then item = Instance.new("Folder"); item.Name = NAME; item.Parent = store end
local pieces = {%s}
for i, text in ipairs(pieces) do
	local v = Instance.new("StringValue")
	v.Name = string.format("P%%04d", %d + i)
	v.Value = text
	v.Parent = item
end
return #item:GetChildren()
'''

MAKE = '''
local NAME, SIZE, COUNT, TITLE = %s, %d, %d, %s
local AssetService = game:GetService("AssetService")
local EncodingService = game:GetService("EncodingService")
local store = game:GetService("ServerStorage"):FindFirstChild("L6PBRStash")
local item = store and store:FindFirstChild(NAME)
assert(item and #item:GetChildren() == COUNT, "the pieces are not all there")
local text = table.create(COUNT)
for i = 1, COUNT do text[i] = item:FindFirstChild(string.format("P%%04d", i)).Value end
local packed = EncodingService:Base64Decode(buffer.fromstring(table.concat(text)))
local pixels = EncodingService:DecompressBuffer(packed, Enum.CompressionAlgorithm.Zstd)
assert(buffer.len(pixels) == SIZE * SIZE * 4, "unpacked " .. buffer.len(pixels) .. " bytes, expected " .. SIZE * SIZE * 4)
local image = AssetService:CreateEditableImage({Size = Vector2.new(SIZE, SIZE)})
assert(image, "no EditableImage (memory budget)")
image:WritePixelsBuffer(Vector2.zero, Vector2.new(SIZE, SIZE), pixels)
local ok, result, id = pcall(function()
	return AssetService:CreateAssetAsync(image, Enum.AssetType.Image, {
		Name = TITLE, Description = "Level 6 arena, PBR texture set (tools/level6_playground/pbr)",
		CreatorId = game.CreatorId, CreatorType = Enum.AssetCreatorType.Group,
	})
end)
image:Destroy()
item:Destroy()
if #store:GetChildren() == 0 then store:Destroy() end
if not ok or result ~= Enum.CreateAssetResult.Success then return "FAILED " .. tostring(result) .. " " .. tostring(id) end
return "OK " .. tostring(id)
'''


def rgba(path):
    """My own PNGs only: 8 bits, RGB or RGBA, no interlace, filter 0 on every row."""
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path.name
    at, idat, width, height, colour = 8, b'', 0, 0, 0
    while at < len(data):
        length, tag = struct.unpack('>I4s', data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if tag == b'IHDR':
            width, height, depth, colour = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and colour in (2, 6), path.name
        elif tag == b'IDAT':
            idat += body
        at += 12 + length
    channels = 4 if colour == 6 else 3
    raw = zlib.decompress(idat)
    stride = width * channels + 1
    assert len(raw) == stride * height and all(raw[y * stride] == 0 for y in range(height)), path.name
    rows = b''.join(raw[y * stride + 1:(y + 1) * stride] for y in range(height))
    if channels == 4:
        return width, rows
    out = bytearray(b'\xff' * (width * height * 4))
    out[0::4], out[1::4], out[2::4] = rows[0::3], rows[1::3], rows[2::3]
    return width, bytes(out)


def wanted():
    rows = [(key, kind, MAPS / f'{key}_{kind}.png') for key in SETS for kind in ('color', 'normal', 'roughness')]
    rows.append(('net_knotted', None, MAPS / 'net_knotted.png'))
    return rows


def main():
    args = sys.argv[1:]
    again = '--again' in args
    only = [a for a in args if not a.startswith('--')]
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    hashes = ids.setdefault('_sha256', {})
    studio = Studio()
    for key, kind, path in wanted():
        if only and key not in only:
            continue
        name = f'{key}_{kind}' if kind else key
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        have = ids.get(key, {}).get(kind) if kind else ids.get(key)
        if have and hashes.get(name) == digest and not again:
            print(f'{name:26s} already {have}', flush=True)
            continue
        size, pixels = rgba(path)
        # from a FILE, not from a pipe: only then does zstd write the size of the content into the frame, and
        # EncodingService:DecompressBuffer refuses a frame without it ("decompression failed - Error (generic)")
        with tempfile.NamedTemporaryFile(suffix='.rgba') as raw:
            raw.write(pixels)
            raw.flush()
            packed = subprocess.run(['zstd', '-19', '--no-check', '-q', '-c', raw.name], capture_output=True, check=True).stdout
        text = base64.b64encode(packed).decode()
        pieces = [text[i:i + PIECE] for i in range(0, len(text), PIECE)]
        for start in range(0, len(pieces), PER_CALL):
            group = pieces[start:start + PER_CALL]
            body = ', '.join(f'[==[{p}]==]' for p in group)
            studio.luau(STASH % (json.dumps(name), 'true' if start == 0 else 'false', body, start))
        answer = studio.luau(MAKE % (json.dumps(name), size, len(pieces), json.dumps(f'L6PBR_{name}')))
        print(f'{name:26s} {len(packed) // 1024:5d} KB packed, {len(pieces):2d} pieces -> {answer}', flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        asset = int(answer.split()[1])
        if kind:
            ids.setdefault(key, {})[kind] = asset
        else:
            if ids.get(key):                              # apply_pbr finds nets that already wear an earlier upload by these
                ids.setdefault('_net_earlier', []).append(ids[key])
            ids[key] = asset
        hashes[name] = digest
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    print('pbr_ids.json written; next: apply_pbr.py --check in a play session')


if __name__ == '__main__':
    main()
