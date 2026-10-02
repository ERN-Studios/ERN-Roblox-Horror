"""Assemble and validate a capture_native_backup.luau receiver directory."""

import hashlib
import json
import pathlib
import sys


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def write_verified(path, payload):
    if path.exists() and path.read_bytes() != payload:
        raise RuntimeError(f"Refusing to overwrite different bytes: {path}")
    path.write_bytes(payload)


def main(root):
    root = pathlib.Path(root).resolve()
    metadata = json.loads((root / "metadata.json").read_text())
    assert metadata["placeId"] == 131311258779917
    assert not metadata["editorConflicts"], metadata["editorConflicts"]
    assert not metadata["skipped"], metadata["skipped"]

    native = b"".join(
        (root / f"native-part-{index:05d}.bin").read_bytes()
        for index in range(metadata["nativeParts"])
    )
    assert len(native) == metadata["nativeBytes"]
    assert len(list(root.glob("native-part-*.bin"))) == metadata["nativeParts"]
    script_json = b"".join(
        (root / f"script-part-{index:05d}.jsonpart").read_bytes()
        for index in range(metadata["scriptJsonParts"])
    )
    assert len(list(root.glob("script-part-*.jsonpart"))) == metadata["scriptJsonParts"]
    scripts = json.loads(script_json)
    assert len(scripts) == metadata["scriptCount"]
    assert all(item["editorMatch"] for item in scripts)

    native_path = root / "all-service-children.rbxm"
    scripts_path = root / "scripts.json"
    write_verified(native_path, native)
    write_verified(scripts_path, script_json)
    hashes = {native_path.name: digest(native), scripts_path.name: digest(script_json)}
    write_verified(
        root / "backup-file-hashes.json",
        (json.dumps(hashes, indent=2) + "\n").encode(),
    )

    manifest = {
        "schema": "studio-level3-source-manifest/1",
        "placeId": metadata["placeId"],
        "universeId": metadata["universeId"],
        "placeVersion": metadata["placeVersion"],
        "sourceCount": len(scripts),
        "scripts": sorted(
            (
                {
                    "path": item["path"],
                    "class": item["class"],
                    "sourceBytes": len(item["source"].encode()),
                    "sourceSha256": digest(item["source"].encode()),
                    "editorMatch": item["editorMatch"],
                }
                for item in scripts
            ),
            key=lambda item: item["path"],
        ),
    }
    write_verified(
        root / "source-manifest.json",
        (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode(),
    )

    root_map = metadata["roots"]
    assert len(root_map) == metadata["rootCount"]
    assert sum(item["descendants"] + 1 for item in root_map) == metadata["expectedDescendants"]
    wanted = {
        "ServerScriptService.Level 3 Systems",
        "ServerScriptService.Level 6 Systems",
        "ServerStorage.Level3Assets",
        "ServerStorage.Level6BlenderSource",
        "ReplicatedStorage.Level 3 Assets",
        "ReplicatedStorage.Level 3 Remotes",
    }
    services = {item["class"]: item for item in metadata["services"]}
    workspace_props = services["Workspace"]["properties"]
    summary = {
        "schema": "studio-native-backup-summary/1",
        "phase": root.name,
        "placeId": metadata["placeId"],
        "universeId": metadata["universeId"],
        "observedPlaceVersion": metadata["placeVersion"],
        "studioVersion": metadata["studioVersion"],
        "capturedAt": metadata["capturedAt"],
        "method": metadata["method"],
        "nativeFile": native_path.name,
        "nativeFileBytes": len(native),
        "nativeFileSha256": hashes[native_path.name],
        "nativeParts": metadata["nativeParts"],
        "nativeBytes": metadata["nativeBytes"],
        "rootCount": metadata["rootCount"],
        "expectedDescendants": metadata["expectedDescendants"],
        "scriptCount": len(scripts),
        "sourceAndEditorConflicts": 0,
        "skippedRoots": 0,
        "assetRoots": [
            {key: item[key] for key in ("path", "class", "descendants")}
            for item in root_map
            if item["path"] in wanted
        ],
        "workspaceProperties": {
            key: workspace_props[key]
            for key in ("Gravity", "FallenPartsDestroyHeight", "StreamingEnabled")
        },
        "scriptsJsonSha256": hashes[scripts_path.name],
    }
    write_verified(
        root / "backup-metadata-summary.json",
        (json.dumps(summary, indent=2, ensure_ascii=False) + "\n").encode(),
    )
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: assemble_native_backup.py RECEIVER_DIRECTORY")
    main(sys.argv[1])
