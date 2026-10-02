"""Join exact R4 candidates with published-native Source/editor guards.

Read/write local artifacts only. This does not connect to Studio or execute an
installer. Finalization requires the owner to finish the RuntimeBake candidate.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASELINE = ROOT / "artifacts/level6-tube-arrival-20261001/native-after/scripts.json"
PACKAGE = ROOT / "assets/models/lobby-reimagined-r4-20261001"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def relative(path):
    return path.resolve().relative_to(ROOT).as_posix()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--finalize", action="store_true", help="Only after owner confirms RuntimeBake static-template fix")
    parser.add_argument("--output", type=Path, default=HERE / "install-catalog-r4-draft.json")
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--baseline-version", type=int, default=2461)
    parser.add_argument("--baseline-kind", choices=("published-export", "live-studio"), default="published-export")
    args = parser.parse_args()
    baseline = args.baseline.resolve()
    raw = baseline.read_bytes()
    native = json.loads(raw)
    by_path = {row["path"]: row for row in native}
    assert len(by_path) == len(native), "Duplicate native Source paths"
    queue = json.loads((HERE / "candidate-manifest.json").read_text())
    expected_keys = {
        "ServerScriptService.GameManager": "game-manager",
        "ServerScriptService.LobbyReimaginedPreview.QueueBridge": "queue-bridge",
        "ServerScriptService.Level4V4PreviewAccess": "level4-preview",
        "ServerScriptService.Level5PreviewAccess": "level5-preview",
        "ServerScriptService.Level6PreviewAccess": "level6-preview",
    }
    assert len(queue) == 5 and {row["path"] for row in queue} == set(expected_keys)
    specs = [
        {"key": "builder", "path": "ServerScriptService.LobbyReimaginedPreview.Builder", "class": "ModuleScript", "file": HERE / "Builder.ModuleScript.luau"},
        {"key": "runtime-bake", "path": "ServerScriptService.LobbyReimaginedPreview.RuntimeBake", "class": "ModuleScript", "file": HERE / "RuntimeBake.ModuleScript.luau"},
    ]
    for row in queue:
        before = (HERE / row["beforeFile"]).read_bytes()
        after = (HERE / row["candidateFile"]).read_bytes()
        assert sha(before) == row["beforeSHA256"] and sha(after) == row["afterSHA256"], "Queue candidate changed: " + row["path"]
        assert by_path[row["path"]]["source"].encode() == before, "Queue native baseline differs"
        specs.append({"key": expected_keys[row["path"]], "path": row["path"], "class": row["class"], "file": HERE / row["candidateFile"]})
    sources = []
    for spec in specs:
        original = by_path.get(spec["path"])
        assert original is not None, "Missing published native baseline: " + spec["path"]
        assert original["class"] == spec["class"] and original.get("editorMatch") is True, "Baseline class/editor conflict"
        candidate = spec["file"].read_bytes()
        before = original["source"].encode()
        pending = spec["key"] == "runtime-bake" and not args.finalize
        sources.append({
            "key": spec["key"], "path": spec["path"], "class": spec["class"], "isNew": False,
            "expectedSourceSHA256": sha(before), "expectedEditorSourceSHA256": sha(before),
            "expectedBeforeBytes": len(before), "editorMatch": True,
            "editorHashBasis": "Native Studio export editorMatch=true; editor Source byte-equal to captured Source",
            "candidateFile": relative(spec["file"]), "sourceURLPath": "/source/" + spec["key"],
            "candidateBytes": len(candidate),
            "afterSHA256": None if pending else sha(candidate),
            "observedCandidateSHA256": sha(candidate),
            "status": "PENDING_OWNER_RUNTIME_STATIC_TEMPLATE_FIX" if pending else "PINNED_LOCAL_CANDIDATE",
            "owned": ".LobbyReimaginedPreview." in spec["path"],
            "scope": "Exact scoped existing Source update; fresh live identity/Source/editor CAS still required",
        })
    preserved = []
    for path, cls in [
        ("ServerScriptService.LobbyReimaginedPreview.Bootstrap", "Script"),
        ("StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController", "LocalScript"),
    ]:
        row = by_path.get(path)
        assert row and row["class"] == cls and row.get("editorMatch") is True, "Missing/conflicted preserved baseline"
        text = row["source"].encode()
        preserved.append({"path": path, "class": cls, "bytes": len(text),
            "sourceSHA256": sha(text), "editorSourceSHA256": sha(text), "editorMatch": True,
            "scope": "Preserve; no Source write authorized by this catalog"})
    manifest_bytes = (PACKAGE / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    assert manifest["revision"] == 4 and manifest["placeId"] == 131311258779917
    missing_material_assets = []
    static_templates = []
    assert set(manifest["materials"]) == {"tunnel_concrete", "asphalt_road", "sidewalk_concrete"}
    for key, material in manifest["materials"].items():
        ids = {}
        for role in ("color", "normal", "roughness"):
            value = material["maps"][role].get("assetId")
            if not isinstance(value, str) or not value.isdecimal() or int(value) <= 0:
                missing_material_assets.append(key + "/" + role)
                ids[role] = None
            else:
                ids[role] = value
        assert material["maps"]["normal"]["normalConvention"] == "OpenGL"
        static_templates.append({"name": key, "class": "SurfaceAppearance", "assetIds": ids,
            "AlphaMode": "Overlay", "Color": [1, 1, 1], "MetalnessMapContent": "None",
            "attributes": {"LobbyReimaginedOwned": True}})
    catalog = {
        "schema": "lobby-r4-exact-install-catalog-v1",
        "createdAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "sourceCatalogReady": args.finalize,
        "readyForInstaller": args.finalize and not missing_material_assets,
        "packageBlockers": ["Missing published PBR assetId: " + value for value in missing_material_assets],
        "scope": "Local catalog only; no Studio writes, no installation/Play/publication inferred",
        "placeId": 131311258779917, "universeId": 10559217407, "groupId": 1039373905,
        "baselineKind": args.baseline_kind,
        "baselinePlaceVersion": args.baseline_version,
        "baselineVerification": "Exact captured Studio Source/editor bytes; fresh session/native guards remain required",
        "baselineFile": relative(baseline), "baselineFileSHA256": sha(raw),
        "missingBaselines": [], "newSources": 0, "sourceCount": 7,
        "sources": sources, "preservedSources": preserved,
        "payload": {"sourceName": "LobbyReimaginedBlenderSource20261001R4", "kitName": "LobbyReimaginedBlenderKit20261001R4",
            "manifestFile": relative(PACKAGE / "manifest.json"), "manifestSHA256": sha(manifest_bytes),
            "chunks": len(manifest["chunks"]), "families": len(manifest["prefabs"]),
            "manifestURLPath": "/manifest", "chunkURLPattern": "/chunk/{id}", "pixelURLPattern": "/pixels/{material}/{role}",
            "atlasURLPath": "/pixels/atlas", "additiveOnly": True,
            "StaticPBRMaterials": {"parent": "ServerStorage.LobbyReimaginedBlenderSource20261001R4.StaticPBRMaterials",
                "class": "Folder", "attributes": {"LobbyReimaginedOwned": True},
                "templates": static_templates,
                "scope": "Required Edit-authored published references; not created by this catalog"},
            "preservePriorPayloadFolders": ["LobbyReimaginedBlenderSource20261001R3", "LobbyReimaginedBlenderSource20261001R3B"]},
        "server": {"currentFile": "tools/lobby_reimagined/serve_r4.py", "defaultPort": 8896,
            "currentEndpoints": ["/manifest", "/catalog", "/chunk/{id}", "/pixels/{material}/{role}", "/pixels/atlas", "/source/{key}", "/texture/{material}/{role}.png"],
            "sourceEndpointsCurrentlyImplemented": True,
            "requiredSourceEndpoints": [row["sourceURLPath"] for row in sources]},
        "historicalR3References": ["tools/lobby_reimagined/source_module_manifest_r3.json", "tools/lobby_reimagined/revision_install_r3.py", "tools/lobby_reimagined/serve.py"],
        "requiredGuards": [
            "Correct place/universe/group; Edit mode only",
            "Fresh native recovery checkpoint before any write",
            "Resolve exact path/class/instance; compare live Source and editor bytes against expected baseline",
            "Recheck Source/editor and instance identity after downloads and inside each UpdateSourceAsync callback",
            "Verify post-write Source/editor hash; preserve all unrelated Sources and original lobby/native data",
            "Add only R4-owned payload; retain existing R3/R3B payloads and original lobby",
        ],
    }
    args.output.write_text(json.dumps(catalog, indent=2) + "\n")
    print(json.dumps({"catalog": relative(args.output), "sourceCatalogReady": args.finalize,
        "readyForInstaller": args.finalize and not missing_material_assets,
        "missingPublishedPBRAssets": missing_material_assets,
        "sourceCount": len(sources), "preservedSources": preserved,
        "pendingKeys": [row["key"] for row in sources if row["afterSHA256"] is None], "missingBaselines": []}, indent=2))


if __name__ == "__main__":
    main()
