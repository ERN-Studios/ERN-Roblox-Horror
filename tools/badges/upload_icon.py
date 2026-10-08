"""Upload badge icons as images owned by the experience's group, from the session, and print their ids for the
`Icon` field of ZyntraConfig.Achievements.

    python3 tools/badges/upload_icon.py LunaKind [OtherKey ...]

Reads assets/badges/icons-512/badge_<Key>.png (made by build_badges.py). The transport is the one
tools/level6_playground/pbr/upload_pbr.py describes (pixels -> zstd -> base64 -> StringValues -> EditableImage ->
AssetService:CreateAssetAsync), so it needs Studio open on the place in Edit mode and the Beta Feature
`CreateAssetAsync`. Ids are kept in tools/badges/icon_ids.json with the hash of the picture they were made from.
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
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground' / 'pbr'))
from import_to_studio import Studio                         # noqa: E402
from upload_pbr import STASH, MAKE, PIECE, PER_CALL         # noqa: E402

ICONS = ROOT / 'assets' / 'badges' / 'icons-512'
IDS = HERE / 'icon_ids.json'
MAKE = MAKE.replace('Level 6 arena, PBR texture set (tools/level6_playground/pbr)', 'Achievement icon (tools/badges)')


def rgba(path):
    """Any 8-bit RGB or RGBA PNG without interlace (Chrome's screenshots use every row filter)."""
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', path.name
    at, idat, width, height, colour = 8, b'', 0, 0, 0
    while at < len(data):
        length, tag = struct.unpack('>I4s', data[at:at + 8])
        body = data[at + 8:at + 8 + length]
        if tag == b'IHDR':
            width, height, depth, colour, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and colour in (2, 6) and interlace == 0, path.name
        elif tag == b'IDAT':
            idat += body
        at += 12 + length
    n = 4 if colour == 6 else 3
    raw, stride = zlib.decompress(idat), width * n
    assert len(raw) == (stride + 1) * height, path.name
    rows, before = [], bytearray(stride)
    for y in range(height):
        kind = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            left = row[i - n] if i >= n else 0
            up = before[i]
            corner = before[i - n] if i >= n else 0
            if kind == 1:
                row[i] = (row[i] + left) & 255
            elif kind == 2:
                row[i] = (row[i] + up) & 255
            elif kind == 3:
                row[i] = (row[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - corner
                a, b, c = abs(p - left), abs(p - up), abs(p - corner)
                row[i] = (row[i] + (left if a <= b and a <= c else up if b <= c else corner)) & 255
            else:
                assert kind == 0, (path.name, kind)
        rows.append(bytes(row))
        before = row
    pixels = b''.join(rows)
    if n == 4:
        return width, height, pixels
    out = bytearray(b'\xff' * (width * height * 4))
    out[0::4], out[1::4], out[2::4] = pixels[0::3], pixels[1::3], pixels[2::3]
    return width, height, bytes(out)


def main():
    keys = sys.argv[1:]
    if not keys:
        raise SystemExit(__doc__)
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    hashes = ids.setdefault('_sha256', {})
    studio = Studio()
    for key in keys:
        path = ICONS / f'badge_{key}.png'
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(key) and hashes.get(key) == digest:
            print(f'{key:20s} already {ids[key]}')
            continue
        width, height, pixels = rgba(path)
        assert width == height, 'a badge icon is square'
        # from a FILE: only then does zstd write the content's size into the frame, which DecompressBuffer needs
        with tempfile.NamedTemporaryFile(suffix='.rgba') as raw:
            raw.write(pixels)
            raw.flush()
            packed = subprocess.run(['zstd', '-19', '--no-check', '-q', '-c', raw.name], capture_output=True, check=True).stdout
        text = base64.b64encode(packed).decode()
        pieces = [text[i:i + PIECE] for i in range(0, len(text), PIECE)]
        name = f'badge_{key}'
        for start in range(0, len(pieces), PER_CALL):
            body = ', '.join(f'[==[{p}]==]' for p in pieces[start:start + PER_CALL])
            studio.luau(STASH % (json.dumps(name), 'true' if start == 0 else 'false', body, start))
        answer = studio.luau(MAKE % (json.dumps(name), width, len(pieces), json.dumps(f'BSQ achievement {key}')))
        print(f'{key:20s} {len(packed) // 1024} KB packed -> {answer}', flush=True)
        if not answer.startswith('OK '):
            raise SystemExit('stopped: ' + answer)
        ids[key], hashes[key] = int(answer.split()[1]), digest
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
