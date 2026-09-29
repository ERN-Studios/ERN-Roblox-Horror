"""Record exact hashes of the reviewed offline Level 6 import handoff."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/level6-worn-party"
DESTINATION = ASSETS / "package-manifest.json"

REQUIRED = [
    "assets/level6-worn-party/IMPORT_READY.md",
    "assets/level6-worn-party/Level6_FULL_Seed101.blend",
    "assets/level6-worn-party/Level6_FULL_Seed101_Overview.png",
    "assets/level6-worn-party/Level6_WornParty_v2.blend",
    "assets/level6-worn-party/Level6_ImportKit.blend",
    "assets/level6-worn-party/Level6_ReusableKit.fbx",
    "assets/level6-worn-party/full-map-record.json",
    "assets/level6-worn-party/kit-manifest-v2.json",
    "assets/level6-worn-party/exports-v2/manifest.json",
    "assets/level6-worn-party/runtime-source/atlas-pixels.json",
    "assets/level6-worn-party/runtime-source/atlas-rgba.b64",
    "assets/level6-worn-party/textures/WornParty_Atlas1024.png",
    "assets/level6-worn-party/textures/WornParty_Atlas.png",
    "tools/level6_build/gameplay-candidates/candidate-manifest.json",
    "tools/level6_build/import/Level6KitMetadataReconcile.luau",
    "artifacts/level6-build-20260930/offline-package-handoff.json",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify the recorded package without rewriting it")
    args = parser.parse_args()
    paths = [ROOT / relative for relative in REQUIRED]
    paths.extend(sorted((ASSETS / "previews-v2").glob("*.png")))
    audio_root = ASSETS / "audio"
    if audio_root.exists():
        paths.extend(sorted(path for path in audio_root.rglob("*") if path.is_file()))
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.is_file()]
    if missing:
        raise SystemExit(f"Missing package files: {missing}")
    files = [
        {
            "path": str(path.relative_to(ROOT)),
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        }
        for path in paths
    ]
    manifest = {
        "schema": "level6-offline-import-package/1",
        "scope": "Prepared locally; not a verified Studio import or publish",
        "files": files,
    }
    if args.check:
        recorded = json.loads(DESTINATION.read_text())
        if recorded != manifest:
            raise SystemExit("Level 6 package manifest differs from the current files")
        action = "verified"
    else:
        DESTINATION.write_text(json.dumps(manifest, indent=2) + "\n")
        action = "written"
    print(f"Level 6 package manifest {action}: {len(files)} files, {sum(file['bytes'] for file in files)} bytes")


if __name__ == "__main__":
    main()
