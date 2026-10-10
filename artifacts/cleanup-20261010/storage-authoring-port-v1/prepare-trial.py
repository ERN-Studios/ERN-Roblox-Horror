"""Assemble one artifact-only controlled absence trial from fresh frozen exports.

No subprocess, MCP, Studio, Source, production-file, manifest, index or git writes.
Output uses exclusive creation; inputs and earlier failures remain unchanged.
"""
from pathlib import Path
import hashlib
import json
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EPOCH = HERE / "before-parity-v2"
COMMON = ROOT / "tools/cleanup_20261009/retired_authoring_archive_common.luau"
ARCHIVE = ROOT / "artifacts/cleanup-serverstorage-20261009/retired-authoring-archive-v3"
HISTORICAL_CATALOG = "e0ec39a63fe5ecb9285245480d38523a7de00f900c88146ba9fc288522969630"
NATIVE_SHA = "e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7"
SHA = lambda b: hashlib.sha256(b).hexdigest()
pins = []


def read(path):
    raw = path.read_bytes()
    pins.append({"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)})
    return raw


def write(name, raw):
    with (HERE / name).open("xb") as stream:
        stream.write(raw)
    return {"path": (HERE / name).relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)}


def main():
    assert not (HERE / "trial-source.luau").exists(), "Immutable prepared source exists"
    native = read(ARCHIVE / "native.rbxm")
    assert len(native) == 8050869 and SHA(native) == NATIVE_SHA
    archive_facts = json.loads(read(ARCHIVE / "facts.json"))
    assert archive_facts["forest"]["scriptCount"] == 0 and archive_facts["totalInstances"] == 1617
    completion = json.loads(read(ARCHIVE / "native-reopen-v1-result.json"))
    assert completion["passed"] and not completion["deletionApproved"]
    manifest_raw = read(ROOT / "studio-sync-manifest.json")
    manifest = json.loads(manifest_raw)
    assert manifest["counts"]["scripts"] == 213 and manifest["counts"]["remoteEvents"] == 15
    census = json.loads(read(ROOT / "artifacts/cleanup-20261010/concurrent-export-v2/storage-census-v1.json"))
    assert census["pass"] and census["after"]["catalogSHA256"] == HISTORICAL_CATALOG and len(census["roots"]) == 52
    rows, epoch_meta, mismatches = [], None, []
    for number in range(10):
        page = json.loads(read(EPOCH / f"native-page-{number:02d}.json"))
        if epoch_meta is None:
            epoch_meta = page["meta"]
        assert page["meta"]["catalogSHA256"] == epoch_meta["catalogSHA256"]
        assert page["meta"]["sceneCount"] == epoch_meta["sceneCount"] and page["meta"]["serverStorageRootCount"] == 52
        assert page["meta"]["sourceEditorConflictCount"] == 0 and page["meta"]["datamodel"] == "Edit"
        rows.extend(page["rows"])
    assert len(rows) == 228
    manifest_items = {tuple(item["segments"]): item for item in manifest["items"]}
    sources = []
    for row in rows:
        if row["className"] not in ("Script", "LocalScript", "ModuleScript"):
            assert row["className"] == "RemoteEvent"
            continue
        assert row["readStable"] and row["sourceEditorMatches"] and not row["propertyReadErrors"]
        assert row["rawSourceSHA256"] == row["rawEditorSHA256"] == row["sourceSHA256"]
        item = manifest_items[tuple(row["segments"])]
        assert item["className"] == row["className"]
        mirror = read(ROOT / item["file"]).replace(b"\r\n", b"\n")
        if SHA(mirror) != row["rawSourceSHA256"] or len(mirror) != row["rawBytes"] or item["sha256"] != row["sourceSHA256"]:
            mismatches.append({"file": item["file"], "mirrorLFBytes": len(mirror), "mirrorLFSHA256": SHA(mirror),
                               "nativeRawBytes": row["rawBytes"], "nativeRawSHA256": row["rawSourceSHA256"],
                               "manifestSHA256": item["sha256"], "scope": "Preserved concurrent working candidate; never overwritten by this preparation"})
        if row["segments"] in (["ServerScriptService", "LobbyReimaginedPreview", "RuntimeBake"],
                               ["ServerScriptService", "Level 1 Systems", "BlenderRoomRenderer"]):
            assert SHA(mirror) == row["rawSourceSHA256"] and len(mirror) == row["rawBytes"]
        sources.append({"segments": row["segments"], "className": row["className"],
                        "rawSHA256": row["rawSourceSHA256"], "rawBytes": row["rawBytes"],
                        "properties": row["properties"]})
    assert len(sources) == 213
    bake = next(r for r in sources if r["segments"] == ["ServerScriptService", "LobbyReimaginedPreview", "RuntimeBake"])
    renderer = next(r for r in sources if r["segments"] == ["ServerScriptService", "Level 1 Systems", "BlenderRoomRenderer"])
    assert bake["rawSHA256"] == "1f564fdde835ad89b529d9069ddf87b0ed4991636f363eacbd098cc0b342ff28", "Review changed Bake initializer/resources first"
    assert renderer["rawSHA256"] == "0f217e5a3f56751e7672efc035861a2cec1b5f23d581a52020411a8d081790cf", "Review changed Renderer initializer/resources first"
    config = {"schema": "retired-authoring-controlled-absence-config-v1", "captureId": uuid.uuid4().hex,
              "expectedSourceCount": 213, "expectedRootCount": 52, "expectedSceneCount": epoch_meta["sceneCount"],
              "catalogSHA256": epoch_meta["catalogSHA256"], "nativeSHA256": NATIVE_SHA,
              "maxDetachSeconds": 60, "sources": sources, "bake": bake, "renderer": renderer}
    config_raw = (json.dumps(config, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()
    config_pin = write("trial-config.json", config_raw)
    common, core, suffix = read(COMMON), read(HERE / "transaction-core.luau"), read(HERE / "native-trial.luau")
    # Keep the complete common bytes intact. Only the subsequent suffix changes its trial lease/event behavior.
    source = (common + b"\n" + core + b"\nlocal PORT_CONFIG=A.HS:JSONDecode([====[" + config_raw
              + b"]====])\n" + suffix)
    assert b"]====]" not in config_raw
    source_pin = write("trial-source.luau", source)
    receipt = {"schema": "retired-authoring-controlled-absence-preparation-v1", "artifactOnly": True,
               "nativeCalls": 0, "productionWrites": 0, "inputs": pins, "config": config_pin,
               "assembledSource": source_pin, "freshSources": 213, "remoteRows": 15,
               "catalogSHA256": epoch_meta["catalogSHA256"], "sourceBodiesIncludedAtNativeStaging": "Exact fresh native Source, guarded against all frozen hashes",
               "globalRepoParityPending": bool(mismatches), "preservedConcurrentMirrorDifferences": mismatches,
               "nativeArchivePassIsNotDeletionPass": True, "preservedUnreadableKinds": archive_facts["references"]["unreadable"],
               "limits": "Prepared executable only; no native selector/absence/cleanup/reference or deletion claim."}
    pin = write("preparation-v1.json", (json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"prepared": True, "source": source_pin, "receipt": pin}))


if __name__ == "__main__":
    main()
