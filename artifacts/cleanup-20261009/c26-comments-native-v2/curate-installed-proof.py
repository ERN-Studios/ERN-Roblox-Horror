"""Read-only C26 receipt derivation; writes only exclusive public evidence files.

No Studio, git, game Source, manifest, checkpoint or existing receipt mutation.
The private checkpoint remains private; no full Source/editor bodies are copied.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PUBLIC = Path(__file__).resolve().parent
INSTALL = PUBLIC / "c26-comments-source-install-v1"
PRIVATE = ROOT / ".git/mongotv-cleanup-20261009/c26-comments-source-install-v1"
BEFORE = "b57a2b848f7981d76225c5bb850cdcfb3de12743afadab674ee826d4747ccc64"
AFTER = "605da83a331022949004dab143012b408b899500f9e6c84188b8d71a31771aca"
TARGET = "ReplicatedStorage/UIRegression.ModuleScript.lua"
TOOLS = {
    "prepare_c26_comments.py": "6588ae6128e718406c09e100b8362999dcd46a71c67bd807924c2a5f7ad3a7d5",
    "apply_c26_comments_cleanup.py": "69dd186d018e4a4385e8f91a95a0af43e807d382cc621fb3b9a83d7bd24a3817",
    "c26_comments_source_cas.luau": "efe3a75876d3768eb41342cfba1ee93853ded375db1c29a420862ded5237ded6",
    "test_apply_c26_comments_cleanup.py": "952a05d584a69483014cecda70b8fa1e22f0114cfe3ad4f052d302a1bd6872ff",
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
    replay = load(INSTALL / "installed-contract-result.json")
    contract = load(INSTALL / "installed-contract/proof.json")
    assert result["pass"] and result["installedContractPassed"] and replay["pass"] and replay["exitCode"] == 0
    assert replay["proofSHA256"] == digest((INSTALL / "installed-contract/proof.json").read_bytes())
    assert contract["pass"] and contract["installedVerification"] and contract["candidateSHA256"] == AFTER
    assert contract["nativeCalls"] == contract["productionSourceWrites"] == contract["manifestWrites"] == 0
    assert result["beforeSourceSHA256"] == BEFORE and result["afterSourceSHA256"] == AFTER and result["bytesRemoved"] == 7195
    assert result["productionNativeWritesRequested"] == 1 and result["rollback"] == {} and result["consoleBefore"] == result["consoleAfter"]
    assert digest(protected[ROOT / TARGET]) == AFTER and len(protected[ROOT / TARGET]) == 313535
    rows = [v for v in json.loads(protected[ROOT / "studio-sync-manifest.json"])["items"] if v.get("file") == TARGET]
    assert len(rows) == 1 and rows[0]["sha256"] == AFTER and rows[0]["bytes"] == 313535

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
    assert drift == [{"instanceId": "1_42698", "studioPath": "ReplicatedStorage.UIRegression", "fields": {"sha256": {"before": BEFORE, "after": AFTER}, "bytes": {"before": 320730, "after": 313535}}}]
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
        "schema": "c26-installed-bounded-transport-and-parity-proof-v1", "pass": True,
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(), "nativeSourceRows": 212,
        "targetOnlySourceDrift": drift, "identitiesClassesParentsPropertiesAttrsTagsUnchanged": True,
        "afterAndFinalRowsByteEquivalent": True, "metadataPagesPerSnapshot": 11, "totalSavedMetadataPages": 33,
        "maxSavedPrettyPageBytes": max(p.stat().st_size for p in saved_pages),
        "wireMetadataResponseCapEnforcedByExecutedWrapper": 20000, "wireSourceResponseCapEnforcedByExecutedWrapper": 8000,
        "actualSourceReadChunkLines": 64, "staticAlignedBeforeSource": counts[0], "staticAlignedCandidateSource": counts[1],
        "sourceChunkSizeScope": "Static exact Source bytes at the actual 64-line alignment; actual response caps enforced before parsing, no measured wire size claimed.",
        "privateOriginalSourceSHA256": digest(native_source), "privateOriginalEditorSHA256": digest(native_editor), "privateOriginalEditorExact": True,
        "actualCASCodeSHA256": digest((PRIVATE / "apply.luau").read_bytes()), "actualResultSHA256": digest((INSTALL / "result.json").read_bytes()),
        "actualInstalledReplaySHA256": digest((INSTALL / "installed-contract-result.json").read_bytes()),
        "actualInstalledContractSHA256": replay["proofSHA256"], "consoleBeforeAfterExact": True,
        "other211SourceRowsPreserved": True, "noRollbackNeeded": True, "nativeCallsByProofDerivation": 0, "productionWritesByProofDerivation": 0,
        "scope": "Point-time original Source/editor/recorded metadata and pure-comment executable/UI authoring contracts. No new native UI/gameplay/assets/multiplayer/streaming/performance certificate.",
    }
    for name in ("native-before.json", "native-after.json", "apply.luau", "native-before-source-originals-final.luau", "native-after-source-originals-final.luau"):
        exclusive(INSTALL / name, (PRIVATE / name).read_bytes())
    exclusive(INSTALL / "native-final.json", encoded(final))
    exclusive(INSTALL / "bounded-transport-and-parity-proof.json", encoded(proof))
    assert all(path.read_bytes() == raw for path, raw in protected.items()), "Protected canonical/tool bytes changed during curation"
    print(json.dumps({"pass": True, "sourceRows": 212, "onlyTargetDrift": True, "nativeCalls": 0, "writesOutsideOwnedPublicEvidence": 0}))


if __name__ == "__main__":
    main()
