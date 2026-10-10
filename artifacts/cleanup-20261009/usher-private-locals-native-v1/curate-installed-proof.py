"""Read-only S16 Usher receipt derivation; writes only exclusive public evidence files.

No Studio, git, game Source, manifest, checkpoint or existing receipt mutation.
The private checkpoint remains private; no full Source/editor bodies are copied.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUBLIC = Path(__file__).resolve().parent
INSTALL = PUBLIC / "usher-source-install-v1"
PRIVATE = ROOT / ".git/mongotv-cleanup-20261009/usher-source-install-v1"
BEFORE = "9af1a745968b95928355707aeaf81bf36b2e9495bdc589918b72bca10d6ba7e3"
AFTER = "ec4252424a0a513ca370851a5ff45b212bab4c2bfcbe20cba58c0a740a2b2a2f"
TARGET = "ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua"
TOOLS = {
    "prepare_usher_private_locals_probe.py": "ef12efdbf411dbca2988cf5154d9599d6f1e6672e46ee2f6c8c333a0dfc0042f",
    "usher_private_locals_probe.luau": "2737a0918fa304feae6da3b379b606d0babefcb2d59a367a93bf977232f216c9",
    "apply_usher_private_locals_cleanup.py": "623293809774a27b9fe9ff636045e9a74d895370324e80fb4b6a268033c526b9",
    "usher_private_locals_source_cas.luau": "1882107e22f6ad95e630835b0890d9f2508ea8adee7cc3cdc3cc90a7ecda31fe",
    "test_apply_usher_private_locals_cleanup.py": "acb7f7fba0345e7251bd559f6785fce24ce59793266f42a424ea56e8a3314d64",
}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def exclusive(path, raw):
    assert path.resolve().is_relative_to(PUBLIC.resolve()), "Public evidence scope"
    assert path.parent.is_dir(), "No implicit foreign directory creation"
    with path.open("xb") as stream:
        stream.write(raw)


def metadata_only(value):
    if isinstance(value, dict):
        assert not set(value).intersection({"Source", "source", "editor", "editorSource", "sourceBody"}), "No raw Source/editor body export"
        for child in value.values():
            metadata_only(child)
    elif isinstance(value, list):
        for child in value:
            metadata_only(child)


def main():
    protected = {ROOT / TARGET: (ROOT / TARGET).read_bytes(), ROOT / "studio-sync-manifest.json": (ROOT / "studio-sync-manifest.json").read_bytes()}
    for name, expected in TOOLS.items():
        path = ROOT / "tools/cleanup_20261009" / name
        assert digest(path.read_bytes()) == expected, "Frozen tool changed: " + name
        protected[path] = path.read_bytes()
    attrs = ROOT / "tools/cleanup_20261009/.gitattributes"
    protected[attrs] = attrs.read_bytes()
    for name in TOOLS:
        assert (name + " -text\n").encode() in protected[attrs].replace(b"\r\n", b"\n")
    result = load(INSTALL / "result.json")
    replay = load(INSTALL / "native-installed-result.json")
    before_port = load(PUBLIC / "usher-native-before-result.json")
    proposal = load(PUBLIC / "proposal-v1/proposal.json")
    assert result["pass"] and result["installedContractPassed"]
    for phase, receipt in (("before", before_port), ("installed", replay)):
        assert receipt["pass"] and receipt["originalsUnchanged"] and receipt["ownedLeaseReleased"]
        assert receipt["originalSourceCoverage"] == 212
        assert receipt["probesCreated"] == receipt["probesDestroyed"] == 4 and receipt["remainingProbes"] == 0 and not receipt["cleanupErrors"]
        assert receipt["nativeInputSHA256"] == proposal["nativeCodeHashes"][phase]
        assert receipt["contract"]["checksPerVersion"] == 68 and receipt["contract"]["pairedChecks"] == 136 and receipt["contract"]["reentryChecks"] == 136
        assert receipt["contract"]["beforeBehaviorSHA256"] == receipt["contract"]["candidateBehaviorSHA256"]
        assert receipt["nativeOriginalSourceWrites"] == receipt["nativeOriginalParentWrites"] == receipt["nativeOriginalAttributeWrites"] == receipt["modeSwitches"] == 0
    assert before_port["contract"]["beforeBehaviorSHA256"] == replay["contract"]["beforeBehaviorSHA256"]
    assert result["beforeSourceSHA256"] == BEFORE and result["afterSourceSHA256"] == AFTER and result["bytesRemoved"] == 86
    assert result["productionNativeWritesRequested"] == 1 and result["rollback"] == {} and result["consoleBefore"] == result["consoleAfter"]
    assert digest(protected[ROOT / TARGET]) == AFTER and len(protected[ROOT / TARGET]) == 34659
    rows = [v for v in json.loads(protected[ROOT / "studio-sync-manifest.json"])["items"] if v.get("file") == TARGET]
    assert len(rows) == 1 and rows[0]["sha256"] == AFTER and rows[0]["bytes"] == 34659

    before = load(PRIVATE / "native-before.json")
    after = load(PRIVATE / "native-after.json")
    final_rows = []
    catalog = None
    final_target = None
    pages = []
    for first in range(1, 213, 20):
        path = PRIVATE / f"snapshot-3-{first:03}.json"
        page = load(path)
        assert page["pass"] and page["totalRows"] == 212 and page["pageFirst"] == first and page["pageCount"] == 20
        assert len(page["rows"]) == min(20, 213 - first)
        if catalog is None:
            catalog, final_target = page["catalogSHA256"], page["target"]
        assert page["catalogSHA256"] == catalog and page["target"] == final_target
        final_rows.extend(page["rows"])
        pages.append(path)
    final = {"pass": True, "operation": "observe", "target": final_target, "rows": final_rows, "catalogSHA256": catalog}
    for observation in (before, after, final):
        metadata_only(observation)
        assert observation["pass"] and len(observation["rows"]) == len({v["instanceId"] for v in observation["rows"]}) == 212
        assert observation["target"]["sourceEditorMatches"]
    assert before["target"]["sourceSHA256"] == BEFORE and after["target"]["sourceSHA256"] == final["target"]["sourceSHA256"] == AFTER
    assert after["rows"] == final["rows"] and after["target"] == final["target"]
    before_by_id = {v["instanceId"]: v for v in before["rows"]}
    after_by_id = {v["instanceId"]: v for v in after["rows"]}
    assert set(before_by_id) == set(after_by_id)
    drift = []
    for identity, old in before_by_id.items():
        new = after_by_id[identity]
        assert {k: v for k, v in old.items() if k not in {"sha256", "bytes"}} == {k: v for k, v in new.items() if k not in {"sha256", "bytes"}}
        changed = {k: {"before": old[k], "after": new[k]} for k in {"sha256", "bytes"} if old[k] != new[k]}
        if changed:
            drift.append({"instanceId": identity, "studioPath": old["studioPath"], "fields": changed})
    assert drift == [{"instanceId": "1_42775", "studioPath": "ServerScriptService.Level 4 Systems.Level 4 Usher Controller", "fields": {"sha256": {"before": BEFORE, "after": AFTER}, "bytes": {"before": 34745, "after": 34659}}}]
    native_source = (PRIVATE / "native-target-source.before.bin").read_bytes()
    native_editor = (PRIVATE / "native-target-editor.before.bin").read_bytes()
    assert native_source == native_editor and digest(native_source) == BEFORE
    counts = []
    for source in (native_source, protected[ROOT / TARGET]):
        lines = source.decode().splitlines()
        lengths = [len("\n".join(lines[first:first + 64]).encode()) for first in range(0, len(lines), 64)]
        counts.append({"chunks": len(lengths), "maxBytes": max(lengths), "lines": len(lines)})
    assert all(value["maxBytes"] < 8000 for value in counts)
    saved_pages = list(PRIVATE.glob("snapshot-[123]-[0-9][0-9][0-9].json"))
    assert len(saved_pages) == 33
    proof = {
        "schema": "usher-installed-bounded-transport-and-parity-proof-v1", "pass": True,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(), "nativeSourceRows": 212,
        "targetOnlySourceDrift": drift, "identitiesClassesParentsPropertiesAttrsTagsUnchanged": True,
        "afterAndFinalRowsByteEquivalent": True, "metadataPagesPerSnapshot": 11, "totalSavedMetadataPages": 33,
        "maxSavedPrettyPageBytes": max(p.stat().st_size for p in saved_pages),
        "wireMetadataResponseCapEnforcedByExecutedWrapper": 20000, "wireSourceResponseCapEnforcedByExecutedWrapper": 8000,
        "actualSourceReadChunkLines": 64, "staticAlignedBeforeSource": counts[0], "staticAlignedCandidateSource": counts[1],
        "sourceChunkSizeScope": "Static exact Source bytes at the actual 64-line alignment; actual response caps enforced before parsing, no measured wire size claimed.",
        "privateOriginalSourceSHA256": digest(native_source), "privateOriginalEditorSHA256": digest(native_editor), "privateOriginalEditorExact": True,
        "actualCASCodeSHA256": digest((PRIVATE / "apply.luau").read_bytes()), "actualResultSHA256": digest((INSTALL / "result.json").read_bytes()),
        "actualInstalledReplaySHA256": digest((INSTALL / "native-installed-result.json").read_bytes()),
        "actualBeforePortSHA256": digest((PUBLIC / "usher-native-before-result.json").read_bytes()),
        "beforeBehaviorSHA256": before_port["contract"]["beforeBehaviorSHA256"],
        "checksPerVersion": 68, "pairedChecks": 136, "reentryChecks": 136, "probesCreatedDestroyedPerRun": 4, "consoleBeforeAfterExact": True,
        "other211SourceRowsPreserved": True, "noRollbackNeeded": True, "nativeCallsByProofDerivation": 0, "productionWritesByProofDerivation": 0,
        "scope": "Point-time original Source/editor/recorded metadata and actual Source private-state/targeting/stun/Stop controlled-boundary contracts. No full initializer/nav/capture/round/gameplay/assets/multiplayer/streaming/performance certificate.",
    }
    for name in ("native-before.json", "native-after.json", "apply.luau", "native-before-source-originals-final.luau", "native-after-source-originals-final.luau", "snapshot-1-001.luau"):
        exclusive(INSTALL / name, (PRIVATE / name).read_bytes())
    exclusive(INSTALL / "native-final.json", encoded(final))
    exclusive(INSTALL / "bounded-transport-and-parity-proof.json", encoded(proof))
    assert all(path.read_bytes() == raw for path, raw in protected.items()), "Protected canonical/tool bytes changed during curation"
    print(json.dumps({"pass": True, "sourceRows": 212, "onlyTargetDrift": True, "nativeCalls": 0, "writesOutsideOwnedPublicEvidence": 0}))


if __name__ == "__main__":
    main()
