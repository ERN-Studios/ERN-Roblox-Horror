"""Recalculate scoped R4 PBR maps and prove safe mesh candidates; no Studio writes.

This extends the existing native, deterministic scan material pipeline. It does
not repaint the source scans, overwrite the R4 package, upload or publish assets.
Use the existing material venv: /private/tmp/lobby-r4-material-venv/bin/python.
"""
from __future__ import annotations

import base64
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[4]
PACKAGE = ROOT / "assets/models/lobby-reimagined-r4-20261001"
OUT = ROOT / "assets/models/lobby-material-polish-20261002"
RECORDS = ROOT / "artifacts/lobby-polish-20261002/materials"
EXPECTED = "17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995"
SETTINGS = {
    "tunnel_concrete": dict(targetColor=[162, 158, 149], colorContrast=1.24,
        sourceChroma=.38, normalStrength=1.25, roughnessMinimum=.77,
        roughnessMaximum=.98, source="concrete_wall_008"),
    "asphalt_road": dict(targetColor=[92, 93, 89], colorContrast=1.14,
        sourceChroma=.15, normalStrength=.95, roughnessMinimum=.76,
        roughnessMaximum=.98, source="clean_asphalt"),
    "sidewalk_concrete": dict(targetColor=[159, 157, 149], colorContrast=1.01,
        sourceChroma=.35, normalStrength=.87, roughnessMinimum=.77,
        roughnessMaximum=.97, source="concrete_pavement"),
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def load_mesh(chunk: dict) -> tuple:
    raw = base64.b64decode((PACKAGE / chunk["file"]).read_bytes())
    assert digest(raw) == chunk["sha256"] and len(raw) == chunk["bytes"]
    magic, nv, nn, nu, nf = struct.unpack_from("<5I", raw)
    assert magic == 0x364D564C and nf == chunk["triangles"]
    vertices = np.frombuffer(raw, dtype="<f4", count=nv*3, offset=20).reshape(nv, 3)
    normals = np.frombuffer(raw, dtype="<f4", count=nn*3, offset=20+nv*12).reshape(nn, 3)
    uvs = np.frombuffer(raw, dtype="<f4", count=nu*2, offset=20+nv*12+nn*12).reshape(nu, 2)
    faces = np.frombuffer(raw, dtype="<u4", count=nf*9,
        offset=20+nv*12+nn*12+nu*8).reshape(nf, 3, 3)
    return vertices, normals, uvs, faces


def mesh_proof(chunk: dict) -> dict:
    vertices, normals, _, faces = load_mesh(chunk)
    edges = Counter()
    directions = Counter()
    for tri in faces[:, :, 0]:
        for i in range(3):
            a, b = int(tri[i]), int(tri[(i+1) % 3])
            edges[tuple(sorted((a, b)))] += 1
            directions[(a, b)] += 1
    p = vertices[faces[:, :, 0]].astype(np.float64)
    geometric = np.cross(p[:, 1]-p[:, 0], p[:, 2]-p[:, 0])
    lengths = np.linalg.norm(geometric, axis=1)
    degenerate = int(np.sum(lengths <= 1e-9))
    geometric /= np.maximum(lengths, 1e-20)[:, None]
    shading = normals[faces[:, :, 1]].mean(axis=1)
    shading /= np.maximum(np.linalg.norm(shading, axis=1), 1e-20)[:, None]
    agreement = np.einsum("ij,ij->i", geometric, shading)
    boundary = sum(n == 1 for n in edges.values())
    nonmanifold = sum(n != 2 for n in edges.values())
    inconsistent = sum(directions[(a, b)] != directions[(b, a)] for a, b in edges)
    # Closedness is necessary but not sufficient: reject flipped authored normals
    # and degenerate geometry too. No change is proposed for a failing chunk.
    safe = not (boundary or nonmanifold or inconsistent or degenerate) and float(agreement.min()) > .75
    return dict(id=chunk["id"], name=chunk["name"], family=chunk["family"],
        sha256=chunk["sha256"], triangles=chunk["triangles"], boundaryEdges=boundary,
        nonmanifoldEdges=nonmanifold, inconsistentEdges=inconsistent,
        degenerateTriangles=degenerate, minimumNormalAgreement=round(float(agreement.min()), 6),
        safeSingleSidedCandidate=bool(safe), automaticFidelityCandidate=bool(safe and chunk["triangles"] >= 200))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    RECORDS.mkdir(parents=True, exist_ok=True)
    raw_manifest = (PACKAGE / "manifest.json").read_bytes()
    live = json.loads((RECORDS / "live-payload-baseline.json").read_text())
    assert digest(raw_manifest) == live["manifestSHA256"] == EXPECTED
    manifest = json.loads(raw_manifest)
    for chunk in manifest["chunks"]:
        captured = live["meshRecords"][str(chunk["id"])]
        assert captured["RawSHA256"] == chunk["sha256"] and captured["RawBytes"] == chunk["bytes"]
    texture_manifest = json.loads((PACKAGE / "textures/manifest.json").read_text())
    spec = importlib.util.spec_from_file_location("r4_material_pipeline", ROOT / "tools/lobby_reimagined/r4_materials.py")
    pipeline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pipeline)
    results, provenance = {}, {}
    for key, settings in SETTINGS.items():
        maps = {}
        original = texture_manifest["materials"][key]
        source = texture_manifest["sources"][settings["source"]]
        provenance[settings["source"]] = source
        for role in ("color", "normal", "roughness"):
            record = source["maps"][role]
            input_path = PACKAGE / "textures" / record["path"]
            assert digest(input_path.read_bytes()) == record["sha256"]
            with Image.open(input_path) as image:
                image = image.copy()
            if role == "color": image = pipeline.color_map(image, settings)
            elif role == "normal": image = pipeline.normal_map(image, settings["normalStrength"])
            else: image = pipeline.roughness_map(image, settings)
            path = OUT / f"{key}_{role}.png"
            image.save(path, optimize=True)
            array = np.asarray(image)
            assert image.size == (1024, 1024) and float(array.std()) > 0
            maps[role] = dict(file=path.name, pngSHA256=digest(path.read_bytes()),
                bytes=path.stat().st_size, dimensions=list(image.size), mode=image.mode,
                minimum=int(array.min()), maximum=int(array.max()),
                median=np.median(array, axis=(0, 1)).tolist(),
                standardDeviation=round(float(array.std()), 5),
                seams=pipeline.seam_metrics(array), sourceSHA256=record["sha256"],
                originalPNG_SHA256=original["maps"][role]["sha256"],
                colorSpace="sRGB" if role == "color" else "Non-Color")
            if role == "normal":
                values=array.astype(np.float64)/127.5-1
                lengths=np.linalg.norm(values,axis=-1)
                maps[role].update(normalConvention="OpenGL", normalLengthMaximumError=float(np.abs(lengths-1).max()),
                    minimumZ=float(values[...,2].min()), tangentRMS=float(np.sqrt((values[...,:2]**2).mean())))
                assert maps[role]["normalLengthMaximumError"] < .012 and maps[role]["minimumZ"] > 0
        results[key] = dict(settings=settings, maps=maps, tileStuds=manifest["materials"][key]["tileStuds"])
    # Preserve all pixels of the original runtime atlas except the dark-steel
    # swatch sampled by the sidewalk-only atlas chunk. Other R4 meshes continue
    # to use the original atlas. Rebuild PNG from exact unconverted runtime RGBA.
    atlas_raw = base64.b64decode((PACKAGE / manifest["atlas"]["file"]).read_bytes())
    assert digest(atlas_raw) == manifest["atlas"]["sha256"]
    bottom_up = np.frombuffer(atlas_raw, dtype=np.uint8).reshape(1024,1024,4).copy()
    sidewalk = next(c for c in manifest["chunks"] if c["name"] == "SidewalkSection_atlas")
    _, _, uvs, faces = load_mesh(sidewalk)
    cells = Counter()
    for corners in faces:
        uv = uvs[corners[:,2]].mean(axis=0)
        cells[(int(uv[0]*8), int(uv[1]*8))] += 1
    candidates=[]
    for (cx,cy), count in cells.items():
        pixel = bottom_up[cy*128+16:(cy+1)*128-16,cx*128+16:(cx+1)*128-16,:3]
        candidates.append((float(pixel.mean()),cx,cy,count))
    _, cx, cy, count = min(candidates)
    tile = bottom_up[cy*128:(cy+1)*128,cx*128:(cx+1)*128,:3]
    before_median=np.median(tile,axis=(0,1))
    assert max(before_median) < 65, "Expected sidewalk dark steel tile changed"
    # Muted warm gray resembles recess dirt. Drain bodies share this material,
    # so lift them conservatively too; their edge/grill material stays unchanged.
    target=np.array([108,104,96],dtype=np.float32)
    detail=(tile.astype(np.float32)-before_median)*.7
    tile[:]=np.clip(np.rint(target+detail),0,255).astype(np.uint8)
    atlas=Image.fromarray(bottom_up[::-1].copy())
    path=OUT/"sidewalk_joint_atlas.png";atlas.save(path,optimize=True)
    atlas_record=dict(file=path.name,pngSHA256=digest(path.read_bytes()),dimensions=list(atlas.size),mode=atlas.mode,
        originalRuntimeAtlasSHA256=manifest["atlas"]["sha256"],onlyChangedBottomUpCell=[cx,cy],
        previousMedianRGB=before_median.tolist(),newMedianRGB=np.median(tile,axis=(0,1)).tolist(),
        sampledTriangles=count,scope="SidewalkSection_atlas only; drain body shares joint tile",assetId=None)
    proof=[mesh_proof(c) for c in manifest["chunks"]]
    write_json(RECORDS/"mesh-proof.json",dict(schema="lobby-material-polish-mesh-proof-v1",
        manifestSHA256=EXPECTED,exactCapturedChunkHashes=True,rows=proof,
        limitation="Static topology proof only. Runtime rendering and performance still need Play measurements."))
    result=dict(schema="lobby-material-polish-v1",placeId=131311258779917,universeId=10559217407,
        groupId=1039373905,baselineManifestSHA256=EXPECTED,materials=results,sources=provenance,
        sidewalkAtlas=atlas_record,assetsPinned=False,
        notice="Local candidate assets only. Install pinned static templates, run Play visual/performance checks, then publish current place.")
    write_json(OUT/"manifest.json",result)
    write_json(RECORDS/"asset-verification.json",dict(exactLiveManifest=True,exactLiveMeshMetadata=True,
        exactSourceScanHashes=True,alignedMaps=True,allNineMaps1024=True,allNormalsUnitWithin012=True,
        allNormalZPositive=True,allMapsNonconstant=True,assetCount=10,uploaded=False,playVerified=False))
    board=Image.new("RGB",(1200,950),(22,25,23));draw=ImageDraw.Draw(board)
    font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf",21)
    draw.text((20,12),"R4 MATERIAL POLISH · old color / candidate color / normal / roughness",font=font,fill=(224,231,219))
    for row,(key,value) in enumerate(results.items()):
        for col,role in enumerate(("old", "color", "normal", "roughness")):
            path=PACKAGE/"textures"/f"{key}_color.png" if role=="old" else OUT/value["maps"][role]["file"]
            with Image.open(path) as image: preview=image.convert("RGB").resize((275,275),Image.Resampling.LANCZOS)
            x,y=20+col*295,52+row*295;board.paste(preview,(x,y))
            draw.text((x,y+277),key+" "+role,font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf",14),fill=(205,217,206))
    board.save(RECORDS/"candidate-maps.jpg",quality=94)
    print(json.dumps({"assetCount":10,"closedCandidates":sum(r["safeSingleSidedCandidate"] for r in proof),
        "safeTriangles":sum(r["triangles"] for r in proof if r["safeSingleSidedCandidate"]),"output":str(OUT)}))


if __name__ == "__main__": main()
