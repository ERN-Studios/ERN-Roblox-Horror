#!/usr/bin/env python3
"""Package exact authored/imported Pool Slide inputs and captured Studio data.

No source files, game scripts, unrelated manifests or Studio objects are edited.
Regeneration replaces only this directory's explicitly-owned generated files.
"""
from __future__ import annotations

import argparse
from collections import Counter
import gzip
import hashlib
import io
import json
from pathlib import Path
import tarfile


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PART_BYTES = 640 * 1024
STAMP = "2026-08-31"
STEM = f"poolslide-{STAMP}"
FINAL_FILES = [f"PoolSlideEntity_{name}.{extension}" for name, extension in (
    ("Rigged", "fbx"), ("Rigged", "glb"), ("Idle", "fbx"),
    ("Walk", "fbx"), ("Run", "fbx"), ("BaseColor_Level2", "png"),
    ("Foot_Blue", "png"), ("Foot_Yellow", "png"))]
IMPORT_FILES = [
    "PoolSlideEntity_Studio.fbx", "PoolSlideEntity_Studio.glb",
    "PoolSlideEntity_BaseColor_Level2.png", "PoolSlideEntity_Foot_Blue.png",
    "PoolSlideEntity_Foot_Yellow.png", "README.md", "prepare_studio_import.py",
    "audit_skinning_limit.py", "validate_roundtrip.py", "roundtrip-validation.json",
    "skinning-deformation-audit.json", "studio-import-validation.json",
]
ANIMATION_FILES = [
    "animation_source_samples.json", "sample_poolslide_animations.py",
    "retarget_poolslide_keyframes.py", "test_poolslide_retarget.py",
    "validate_actual_poolslide_keyframes.py", "actual-studio-poolslide-rest.json",
    "ANIMATION_INTEGRATION.md",
]
KEYFRAME_FILES = ["idle.json", "walk.json", "run.json", "retarget-diagnostics.json", "actual-target-validation.json"]


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def encoded(value: object, compact=False) -> bytes:
    return (json.dumps(value, ensure_ascii=False, separators=(",", ":") if compact else None,
                       indent=None if compact else 2) + "\n").encode("utf-8")


def suffix(number: int) -> str:
    result = ""
    for _ in range(4):
        result = chr(97 + number % 26) + result
        number //= 26
    assert number == 0
    return result


def build(desktop: Path, staging: Path, replace: bool) -> dict:
    pack = HERE / "source-pack"
    if (pack / "manifest.json").exists() and not replace:
        raise FileExistsError("Source pack exists; use --replace-snapshot for an intentional refresh")
    payload: dict[str, bytes] = {}
    for name in FINAL_FILES:
        payload[f"authoring/Final_Roblox/{name}"] = (desktop / "Final_Roblox" / name).read_bytes()
    payload["authoring/README.md"] = (desktop / "README.md").read_bytes()
    for name in IMPORT_FILES:
        payload[f"import/Studio_Import/{name}"] = (desktop / "Studio_Import" / name).read_bytes()
    for name in ANIMATION_FILES:
        payload[f"animation/{name}"] = (staging / name).read_bytes()
    for name in KEYFRAME_FILES:
        payload[f"animation/keyframes/{name}"] = (staging / "keyframes" / name).read_bytes()
    template_raw = (staging / "template-reconstruction.json").read_bytes()
    template = json.loads(template_raw)
    assert template["schema"] == "poolslide-template-reconstruction-v1"
    classes = Counter(record["className"] for record in template["records"])
    assert classes == {"Model": 1, "MeshPart": 7, "Motor6D": 7, "Part": 1,
                       "Bone": 24, "AnimationController": 1, "Folder": 1, "CFrameValue": 96}
    animations = [json.loads((staging / "keyframes" / name).read_bytes())
                  for name in ("idle.json", "walk.json", "run.json")]
    assert [len(clip["frames"]) for clip in animations] == [121, 32, 20]
    bundle = {"schema": "poolslide-recovery-bundle-v1", "template": template, "animations": animations}
    bundle_raw = encoded(bundle, compact=True)
    payload["studio/template-reconstruction.json"] = template_raw
    payload["studio/recovery-bundle.json"] = bundle_raw
    payload["studio/install_poolslide_template.luau"] = (staging / "install_poolslide_template.luau").read_bytes()
    for name in ("reconstruct_poolslide.luau", "build_source_pack.py", "test_recovery_archive.py", "README.md"):
        payload[f"recovery/{name}"] = (HERE / name).read_bytes()
    payload["recovery/restore-poolslide-assets.py"] = (REPO / "tools/restore-poolslide-assets.py").read_bytes()
    for name, raw in payload.items():
        assert raw, f"Empty source file: {name}"
    # Convenient, small, directly tracked copies of actual recovery data.
    (HERE / "template-reconstruction.json").write_bytes(template_raw)
    (HERE / "recovery-bundle.json").write_bytes(bundle_raw)
    (HERE / "actual-studio-poolslide-rest.json").write_bytes((staging / "actual-studio-poolslide-rest.json").read_bytes())
    (HERE / "keyframes").mkdir(exist_ok=True)
    for name in KEYFRAME_FILES:
        (HERE / "keyframes" / name).write_bytes((staging / "keyframes" / name).read_bytes())
    source_count = len(payload)
    payload["SHA256SUMS"] = "".join(f"{sha256(raw)}  {name}\n" for name, raw in sorted(payload.items())).encode()
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, filename="", mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for name, raw in sorted(payload.items()):
                entry = tarfile.TarInfo(name)
                entry.size = len(raw)
                entry.mtime = entry.uid = entry.gid = 0
                entry.mode = 0o644
                archive.addfile(entry, io.BytesIO(raw))
    raw_archive = buffer.getvalue()
    parts_directory = pack / "parts"
    parts_directory.mkdir(parents=True, exist_ok=True)
    parts = []
    for index, start in enumerate(range(0, len(raw_archive), PART_BYTES)):
        raw = raw_archive[start:start + PART_BYTES]
        name = f"{STEM}.tar.gz.part-{suffix(index)}"
        (parts_directory / name).write_bytes(raw)
        parts.append({"path": "parts/" + name, "bytes": len(raw), "sha256": sha256(raw)})
    (parts_directory / "SHA256SUMS").write_text("".join(
        f"{part['sha256']}  {Path(part['path']).name}\n" for part in parts), encoding="utf-8")
    (pack / f"{STEM}.tar.gz.sha256").write_text(f"{sha256(raw_archive)}  {STEM}.tar.gz\n", encoding="utf-8")
    manifest = {
        "schema": "poolslide-source-pack-v1", "snapshotDate": STAMP,
        "format": "split tar.gz", "partSizeBytes": PART_BYTES,
        "partCount": len(parts), "archiveBytes": len(raw_archive),
        "archiveSha256": sha256(raw_archive), "verifiedSourceFileCount": source_count,
        "files": [{"path": name, "bytes": len(raw), "sha256": sha256(raw)} for name, raw in sorted(payload.items())],
        "parts": parts, "restoreCommand": "python3 tools/restore-poolslide-assets.py",
    }
    (pack / "manifest.json").write_bytes(encoded(manifest))
    root = next(record for record in template["records"] if record.get("parent") is None)
    asset_manifest = {
        "schemaVersion": 1, "snapshotDate": STAMP,
        "experience": {"placeId": 131311258779917, "universeId": 10559217407,
                       "creatorGroupId": 1039373905},
        "templatePath": template["targetPath"], "templateInstanceCount": len(template["records"]),
        "classCounts": dict(classes), "templateAttributes": root["attributes"],
        "meshes": [{"name": record["name"], "meshId": record["properties"]["MeshId"],
                    "textureId": record["properties"]["TextureID"],
                    "material": record["properties"]["Material"], "size": record["properties"]["Size"]}
                   for record in template["records"] if record["className"] == "MeshPart"],
        "animationMode": "Local Bone.Transform playback; no published AnimationId",
        "animations": [{"name": clip["name"], "file": f"keyframes/{name}",
                        "frames": len(clip["frames"]), "durationSeconds": clip["frames"][-1][0],
                        "sha256": sha256((staging / "keyframes" / name).read_bytes())}
                       for clip, name in zip(animations, ("idle.json", "walk.json", "run.json"))],
        "sourcePack": {key: manifest[key] for key in ("format", "partSizeBytes", "partCount", "archiveBytes", "archiveSha256", "verifiedSourceFileCount", "restoreCommand")},
        "recovery": {"bundle": "recovery-bundle.json", "helper": "reconstruct_poolslide.luau",
                     "status": "offline checks only; Studio visual skin-binding recovery untested",
                     "requiresOriginalAssetAccess": True,
                     "limitations": ["Reserved RBX_ importer attributes are archived but not replayed.",
                                     "Model scale metadata is not captured; absolute part/bone transforms and dimensions are captured.",
                                     "FBX reimport or full saved place remains the definitive recovery fallback."]},
    }
    asset_manifest["sourcePack"]["directory"] = "assets/level2/poolslide/source-pack"
    (HERE / "asset-manifest.json").write_bytes(encoded(asset_manifest))
    return {key: manifest[key] for key in ("partCount", "archiveBytes", "archiveSha256", "verifiedSourceFileCount")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--desktop-root", type=Path, required=True)
    parser.add_argument("--staging-root", type=Path, required=True)
    parser.add_argument("--replace-snapshot", action="store_true")
    args = parser.parse_args()
    print(json.dumps(build(args.desktop_root.resolve(), args.staging_root.resolve(), args.replace_snapshot), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
