"""Pack the exact authored PNG pixels for group-owned Roblox image upload.

This is a local, deterministic packaging step only; it never contacts Roblox.
Requires Pillow and the zstd CLI. Each RGBA buffer is Zstandard-compressed,
Base64-encoded, and divided into small HTTP-friendly text parts. Roblox Luau can
concatenate the parts, Base64Decode, DecompressBuffer, and WritePixelsBuffer.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
from pathlib import Path

from PIL import Image


REPO = Path(__file__).resolve().parents[3]
TASK = REPO / "artifacts/level6-studio-revision-20261001"
ROUTES = TASK / "materials-studio/material-routes.json"
ZEN_IDS = TASK / "materials-studio/asset-ids.normalized.json"
OUTPUT = TASK / "taskgroup-owned-images"
PART_CHARS = 128_000


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pack(record: dict, zen_id: int, raw_base64: bool = False) -> dict:
    source = REPO / record["source"]
    png = source.read_bytes()
    assert sha(png) == record["sha256"], f"Authored PNG changed: {source}"
    with Image.open(source) as image:
        assert image.format == "PNG", f"Expected PNG: {source}"
        rgba_image = image.convert("RGBA")
        assert rgba_image.size == (1024, 1024), f"Wrong dimensions: {source}"
        rgba = rgba_image.tobytes()
    assert len(rgba) == 1024 * 1024 * 4
    # Roblox EncodingService:DecompressBuffer expects Zstd's frame content
    # size. zstd omits it for stdin unless --stream-size is explicitly set.
    compressed = rgba if raw_base64 else subprocess.run(
        ["zstd", "--quiet", "-7", f"--stream-size={len(rgba)}", "--stdout"],
        input=rgba, capture_output=True, check=True,
    ).stdout
    encoded = base64.b64encode(compressed).decode("ascii")
    pieces = []
    name = record["key"]
    for index, start in enumerate(range(0, len(encoded), PART_CHARS)):
        payload = encoded[start:start + PART_CHARS].encode("ascii")
        filename = f"{name}.{'raw' if raw_base64 else 'zstd'}.b64.{index:03d}.txt"
        (OUTPUT / filename).write_bytes(payload)
        pieces.append({
            "path": f"taskgroup-owned-images/{filename}",
            "bytes": len(payload),
            "sha256": sha(payload),
        })
    return {
        "key": name,
        "source": record["source"],
        "sourcePngSha256": sha(png),
        "sourcePngBytes": len(png),
        "oldZenImageAssetId": zen_id,
        "width": 1024,
        "height": 1024,
        "pixelFormat": "RGBA8",
        "rgbaBytes": len(rgba),
        "rgbaSha256": sha(rgba),
        "compression": "None" if raw_base64 else "Zstd",
        "compressedBytes": len(compressed),
        "compressedSha256": sha(compressed),
        "base64Chars": len(encoded),
        "parts": pieces,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", help="Pack one map for a single-asset upload probe")
    parser.add_argument("--raw-base64", action="store_true", help="Serve uncompressed RGBA Base64 chunks as fallback")
    args = parser.parse_args()
    routes = json.loads(ROUTES.read_text())
    zen_ids = json.loads(ZEN_IDS.read_text())
    records = routes["images"]
    assert len(records) == 27 and set(zen_ids) == {r["key"] for r in records}
    if args.only:
        records = [r for r in records if r["key"] == args.only]
        assert len(records) == 1, f"Unknown map {args.only}"
    OUTPUT.mkdir(parents=True, exist_ok=True)
    images = [pack(record, int(zen_ids[record["key"]]), args.raw_base64) for record in records]
    manifest = {
        "schema": "level6-group-owned-rgba-upload/1",
        "placeId": routes["placeId"],
        "universeId": routes["universeId"],
        "targetCreatorType": "Group",
        "targetCreatorId": routes["groupId"],
        "sourceMaterialRoutesSha256": sha(ROUTES.read_bytes()),
        "imageCount": len(images),
        "images": images,
    }
    filename = ("probe" if args.only else "manifest") + ("-raw" if args.raw_base64 else "") + ".json"
    (OUTPUT / filename).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{OUTPUT / filename}: {len(images)} exact RGBA maps, {sum(len(x['parts']) for x in images)} HTTP parts")


if __name__ == "__main__":
    main()
