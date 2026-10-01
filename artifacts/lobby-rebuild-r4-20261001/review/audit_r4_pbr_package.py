"""Independent read-only numeric audit of the R4 material-aware export."""
from pathlib import Path
import base64, collections, datetime, hashlib, json, math, struct
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/models/lobby-reimagined-r4-20261001"
REVIEW = Path(__file__).resolve().parent

def sha(data):
    return hashlib.sha256(data).hexdigest()

def main():
    manifest_bytes = (OUT / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    families = collections.defaultdict(list)
    chunk_rows, pixel_rows = [], []
    for chunk in manifest["chunks"]:
        raw = base64.b64decode((OUT / chunk["file"]).read_bytes(), validate=True)
        assert sha(raw) == chunk["sha256"] and len(raw) == chunk["bytes"]
        magic, nv, nn, nu, nf = struct.unpack_from("<5I", raw)
        assert magic == 0x364D564C and len(raw) == 20+nv*12+nn*12+nu*8+nf*36
        position = np.frombuffer(raw, dtype="<f4", count=nv*3, offset=20).reshape((-1, 3))
        normal = np.frombuffer(raw, dtype="<f4", count=nn*3, offset=20+nv*12).reshape((-1, 3))
        uv = np.frombuffer(raw, dtype="<f4", count=nu*2, offset=20+nv*12+nn*12).reshape((-1, 2))
        faces = np.frombuffer(raw, dtype="<u4", count=nf*9, offset=20+nv*12+nn*12+nu*8).reshape((-1, 3, 3))
        assert np.isfinite(position).all() and np.isfinite(normal).all() and np.isfinite(uv).all()
        assert faces[:, :, 0].max() < nv and faces[:, :, 1].max() < nn and faces[:, :, 2].max() < nu
        p = position[faces[:, :, 0]]
        cross = np.cross(p[:, 1]-p[:, 0], p[:, 2]-p[:, 0])
        area2 = np.linalg.norm(cross, axis=1)
        face_n = cross / np.maximum(area2[:, None], 1e-20)
        corners = normal[faces[:, :, 1]]
        winding_dot = (corners*face_n[:, None]).sum(axis=2)
        face_uv = uv[faces[:, :, 2]]
        ua, ub = face_uv[:, 1]-face_uv[:, 0], face_uv[:, 2]-face_uv[:, 0]
        uv_determinant = ua[:, 0]*ub[:, 1]-ua[:, 1]*ub[:, 0]
        norms = np.linalg.norm(normal, axis=1)
        pbr = chunk["materialKey"] in manifest["materials"]
        row = {"family": chunk["family"], "name": chunk["name"], "material": chunk["materialKey"],
               "triangles": nf, "vertices": nv, "normals": nn, "uvs": nu,
               "normalUnitMaxError": float(np.abs(norms-1).max()),
               "degenerateTriangleCount": int((area2 < 1e-8).sum()),
               "opposedCornerNormalCount": int((winding_dot < -.01).sum()),
               "normalWindingDotMinimum": float(winding_dot.min()),
               "collapsedUVTriangleCount": int((np.abs(uv_determinant) < 1e-10).sum()),
               "pbr": pbr, "sha256": sha(raw)}
        assert row["normalUnitMaxError"] < 2e-5, row
        if pbr:
            assert row["degenerateTriangleCount"] == 0 and row["opposedCornerNormalCount"] == 0, row
            assert row["collapsedUVTriangleCount"] == 0, row
        chunk_rows.append(row)
        families[chunk["family"]].append(chunk)
    for key, material in manifest["materials"].items():
        for role, spec in material["maps"].items():
            raw = base64.b64decode((OUT / spec["file"]).read_bytes(), validate=True)
            assert len(raw) == spec["bytes"] == 1024*1024*4 and sha(raw) == spec["sha256"]
            rgba = np.frombuffer(raw, dtype=np.uint8).reshape((1024, 1024, 4))
            png = np.asarray(Image.open(OUT / "textures" / f"{key}_{role}.png").convert("RGBA"))
            assert spec["rowOrder"] == "top-down" and np.array_equal(rgba, png), (key, role)
            assert (rgba[:, :, 3] == 255).all()
            pixel_rows.append({"key": key, "role": role, "sha256": sha(raw),
                               "matchesPNGWithoutGammaOrFlip": True, "rowOrder": "top-down"})
    special = [p for p in manifest["placements"] if p.get("runtimeKind") == "VinylDisc"]
    for family in [p["family"] for p in special] + ["HologramRing", "HologramBand"]:
        assert len(families[family]) == 1 and families[family][0]["materialKey"] == "atlas", family
    source_names = ["tools/lobby_reimagined/r4_candidates/RuntimeBake.ModuleScript.luau",
                    "tools/lobby_reimagined/r4_candidates/Builder.ModuleScript.luau",
                    "tools/lobby_reimagined/r4_pbr_export.py", "tools/lobby_reimagined/build_r4.py",
                    "tools/level6_build/import/export_prefabs.py"]
    source_hashes = {name: sha((ROOT/name).read_bytes()) for name in source_names}
    report = {"schema": "independent-r4-pbr-export-audit-v1",
              "capturedUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "manifestSHA256": sha(manifest_bytes), "sourceHashes": source_hashes,
              "studioChecked": False, "published": False,
              "budget": {"families": len(families), "chunks": len(chunk_rows),
                         "uniqueTriangles": manifest["uniqueTriangles"],
                         "instantiatedTriangles": manifest["instantiatedTriangles"],
                         "maxChunkTriangles": max(row["triangles"] for row in chunk_rows),
                         "meshRawBytes": sum(c["bytes"] for c in manifest["chunks"]),
                         "pbrMaterials": len(manifest["materials"]), "pbrImages": len(pixel_rows),
                         "pbrRawRGBABytes": 1024*1024*4*len(pixel_rows),
                         "instantiatedPBRMeshParts": sum(sum(c["materialKey"] in manifest["materials"] for c in families[p["family"]]) for p in manifest["placements"]),
                         "instantiatedMeshParts": sum(len(families[p["family"]]) for p in manifest["placements"])},
              "singleMeshRuntimeSpecials": [p["family"] for p in special]+["HologramRing", "HologramBand"],
              "chunks": chunk_rows, "pixels": pixel_rows,
              "checks": {"pbrTrianglesNondegenerate": True, "pbrNormalsNotOpposedToWinding": True,
                         "pbrUVTrianglesNoncollapsed": True, "normalVectorsUnitLength": True,
                         "exactPNGTopDownBytes": True, "specialRuntimeMeshPartAssumptions": True},
              "limits": ["Numeric UV/normal checks do not prove Roblox generates tangent frames.",
                         "Actual normal-map lighting and multiplayer replication require Studio Play tests.",
                         "No source/editor parity or current full native checkpoint is claimed."]}
    (REVIEW / "pbr-package-audit.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({k: report[k] for k in ("manifestSHA256", "sourceHashes", "budget", "checks", "limits")}, indent=2))

if __name__ == "__main__":
    main()
