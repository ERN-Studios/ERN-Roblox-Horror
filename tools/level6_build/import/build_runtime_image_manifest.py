"""Pin the 27 authored RGBA maps and their PBR routes for persistent Studio source."""

from __future__ import annotations

import base64
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / "artifacts/level6-studio-revision-20261001"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main():
    source = json.loads((TASK / "taskgroup-owned-images/manifest.json").read_text())
    routes_file = TASK / "materials-studio/material-routes.json"
    routes = json.loads(routes_file.read_text())
    blend = json.loads((TASK / "import-package/runtime-manifest.json").read_text())
    assert source["imageCount"] == len(source["images"]) == 27
    assert source["sourceMaterialRoutesSha256"] == sha(routes_file.read_bytes())
    assert source["placeId"] == routes["placeId"] == blend["placeId"]
    assert source["targetCreatorId"] == routes["groupId"] == blend["groupId"]
    image_keys = {image["key"] for image in source["images"]}
    assert image_keys == {image["key"] for image in routes["images"]}
    assert "props__color" in image_keys and "red-wall-color" in image_keys
    for image in source["images"]:
        assert image["width"] == image["height"] == 1024
        assert image["pixelFormat"] == "RGBA8" and image["rgbaBytes"] == 1024 * 1024 * 4
        pieces = []
        for part in image["parts"]:
            contents = (TASK / part["path"]).read_bytes()
            assert len(contents) == part["bytes"] and sha(contents) == part["sha256"]
            pieces.append(contents)
        encoded = b"".join(pieces)
        assert len(encoded) == image["base64Chars"]
        compressed = base64.b64decode(encoded, validate=True)
        assert len(compressed) == image["compressedBytes"] and sha(compressed) == image["compressedSha256"]
        raw = subprocess.run(["zstd", "-d", "-c"], input=compressed,
                             check=True, capture_output=True, timeout=30).stdout
        assert len(raw) == image["rgbaBytes"] and sha(raw) == image["rgbaSha256"]
    output = {
        "schema": "level6-blender-runtime-images-v1",
        "placeId": source["placeId"],
        "groupId": source["targetCreatorId"],
        "sourceBlendSha256": blend["sourceBlendSha256"],
        "sourceMaterialRoutesSha256": source["sourceMaterialRoutesSha256"],
        "imageCount": 27,
        "propsAtlasKey": "props__color",
        "images": [{key: image[key] for key in (
            "key", "width", "height", "pixelFormat", "rgbaBytes", "rgbaSha256",
            "compressedBytes", "compressedSha256", "base64Chars", "parts")}
            for image in source["images"]],
        "variants": {key: {field: route[field] for field in (
            "name", "baseMaterial", "studsPerTile", "mapImageKeys")}
            for key, route in routes["variants"].items()},
    }
    target = TASK / "import-package/images-runtime.json"
    target.write_text(json.dumps(output, separators=(",", ":"), ensure_ascii=False) + "\n")
    print(json.dumps({"path": str(target), "sha256": sha(target.read_bytes()),
                      "images": len(output["images"]), "parts": sum(len(x["parts"]) for x in output["images"])}))


if __name__ == "__main__":
    main()
