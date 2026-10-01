"""Read every revised Level 6 binary payload independently of Blender/Studio."""

from __future__ import annotations

import base64
import hashlib
import json
import math
import struct
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PACKAGE = ROOT / "artifacts/level6-studio-revision-20261001/import-package"
MAGIC = 0x364D564C


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_chunk(chunk):
    encoded = (PACKAGE / chunk["file"]).read_bytes()
    raw = base64.b64decode(encoded, validate=True)
    assert hashlib.sha256(raw).hexdigest() == chunk["sha256"], chunk["name"]
    assert len(raw) == chunk["bytes"], chunk["name"]
    magic, nv, nn, nu, nf = struct.unpack_from("<5I", raw)
    assert magic == MAGIC, chunk["name"]
    assert (nv, nn, nu, nf) == tuple(chunk[k] for k in ("vertices", "normals", "uvs", "triangles")), chunk["name"]
    assert len(raw) == 20 + nv*12 + nn*12 + nu*8 + nf*36, chunk["name"]
    p = 20
    vertices = [struct.unpack_from("<3f", raw, p + i*12) for i in range(nv)]
    p += nv*12
    normals = [struct.unpack_from("<3f", raw, p + i*12) for i in range(nn)]
    p += nn*12
    uvs = [struct.unpack_from("<2f", raw, p + i*8) for i in range(nu)]
    p += nu*8
    faces = [struct.unpack_from("<9I", raw, p + i*36) for i in range(nf)]
    assert all(all(math.isfinite(v) for v in point) for point in vertices), chunk["name"]
    assert all(abs(math.sqrt(sum(v*v for v in normal)) - 1) < 0.0001 for normal in normals), chunk["name"]
    assert all(-0.00001 <= v <= 1.00001 for uv in uvs for v in uv), chunk["name"]
    assert all(f[i] < (nv if i%3 == 0 else nn if i%3 == 1 else nu)
               for f in faces for i in range(9)), chunk["name"]
    lo = [min(v[i] for v in vertices) for i in range(3)]
    hi = [max(v[i] for v in vertices) for i in range(3)]
    expected = [hi[i]-lo[i] for i in range(3)]
    assert all(abs(expected[i]-chunk["geometrySize"][i]) < 0.00003 for i in range(3)), chunk["name"]
    assert all(abs((lo[i]+hi[i])/2) < 0.00002 for i in range(3)), chunk["name"]
    assert all(abs(chunk["size"][i]-max(expected[i], .01)) < 0.00003 for i in range(3)), chunk["name"]
    return {"vertices": nv, "triangles": nf, "bytes": len(raw)}


def main():
    manifest = json.loads((PACKAGE / "manifest.json").read_text())
    runtime = json.loads((PACKAGE / "runtime-manifest.json").read_text())
    materials = json.loads((PACKAGE / "materials-runtime.json").read_text())
    assert manifest["schema"] == runtime["schema"] == "level6-blender-prefabs-v2"
    assert len(manifest["families"]) == len(runtime["families"]) == 61
    assert len(manifest["chunks"]) == len(runtime["chunks"]) == 279
    assert [c["id"] for c in manifest["chunks"]] == list(range(279))
    assert sorted(manifest["families"]) == runtime["families"]
    assert sha(ROOT / manifest["sourceBlend"]) == manifest["sourceBlendSha256"]
    assert sha(ROOT / manifest["importKitBlend"]) == manifest["importKitBlendSha256"]
    by_family = Counter()
    triangles = Counter()
    totals = Counter()
    variants = Counter()
    for chunk, compact in zip(manifest["chunks"], runtime["chunks"]):
        assert all(compact[key] == chunk[key] for key in compact), chunk["name"]
        assert chunk["name"] == "m%03d__%s" % (chunk["id"], chunk["object"].split("__", 1)[1])
        if chunk["materialVariant"]:
            assert chunk["surface"] and chunk["runtimeSurface"]
            variants[chunk["materialVariant"]] += 1
        else:
            assert chunk["surface"] is None
        counts = read_chunk(chunk)
        totals.update(counts)
        by_family[chunk["family"]] += 1
        triangles[chunk["family"]] += chunk["triangles"]
    assert totals["triangles"] == runtime["uniqueTriangles"] == 74092
    assert sum(variants.values()) == 20 and len(variants) == 9
    assert materials["propsAtlasAssetId"] > 0
    assert set(variants) == {v["name"] for v in materials["variants"].values()}
    assert len(list((PACKAGE / "chunks").glob("*.b64"))) == 279
    for family, meta in manifest["families"].items():
        assert meta["chunkCount"] == by_family[family]
        assert meta["triangles"] == triangles[family]
        assert all(v > 0 for v in meta["size"])
        assert all(len(box["center"]) == len(box["size"]) == 3 for box in meta["colliders_xyz"])
        if family in ("RoomKitchenPrep", "RoomUtilityHall", "RoomStaffNook"):
            assert meta["hasFlattenedFixtureVisuals"] and meta["hasIntegratedFixtureCollision"]
            assert len(meta["lights_xyz"]) == 2
            assert {"JoinNorth", "JoinSouth"} <= set(meta["anchors_xyz"])
            assert meta["size"][0] >= 24 and meta["size"][2] >= 24
            for join in ("JoinNorth", "JoinSouth"):
                assert meta["anchorDetails"][join]["l6_port_width"] == 14
                assert meta["anchorDetails"][join]["l6_port_height"] == 10.5
            # The Manager has a 10-stud body. Preserve a straight 12-stud
            # passage through the room at all floor-height collider slices.
            for box in meta["colliders_xyz"]:
                x, y, z = box["center"]
                w, d, h = box["size"]
                if z + h/2 <= .1 or z - h/2 >= 6:
                    continue
                if y + d/2 <= -12 or y - d/2 >= 12:
                    continue
                assert x + w/2 <= -6 or x - w/2 >= 6, (family, box)
    result = {
        "schema": "level6-blender-import-verification-v1",
        "manifestSha256": sha(PACKAGE / "manifest.json"),
        "runtimeManifestSha256": sha(PACKAGE / "runtime-manifest.json"),
        "sourceBlendSha256": manifest["sourceBlendSha256"],
        "importKitBlendSha256": manifest["importKitBlendSha256"],
        "families": len(manifest["families"]),
        "chunks": len(manifest["chunks"]),
        "rawGeometryBytes": totals["bytes"],
        "triangles": totals["triangles"],
        "vertices": totals["vertices"],
        "pbrChunks": sum(variants.values()),
        "variants": dict(sorted(variants.items())),
        "collisionBoxes": sum(len(x["colliders_xyz"]) for x in manifest["families"].values()),
        "anchors": sum(len(x["anchors_xyz"]) for x in manifest["families"].values()),
        "lights": sum(len(x["lights_xyz"]) for x in manifest["families"].values()),
        "roomPortalsWideStuds": 14,
        "roomCenterLaneStuds": 12,
        "studioBaked": False,
    }
    (PACKAGE / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
