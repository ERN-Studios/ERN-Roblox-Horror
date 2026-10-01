#!/usr/bin/env python3
"""Read-only comparison of the lobby art-lighting change against native captures.

Requires the exact root-approved after Source, not an older repository baseline.
Every other Source, native object/property and service/global setting is compared.
"""
import argparse
import hashlib
import json
from pathlib import Path

TASK = Path(__file__).resolve().parent
PATH = "ServerScriptService.LobbyShopDisplay"


def read(path):
    return json.loads(path.read_bytes())


def digest(value):
    return hashlib.sha256(value).hexdigest()


def source_map(records):
    result = {}
    for item in records:
        assert item["path"] not in result and item["editorMatch"] is True
        result[item["path"]] = item
    return result


def source_identity(item):
    return {"class": item["class"], "sourceBytes": len(item["source"].encode()),
            "sourceSHA256": digest(item["source"].encode()), "editorMatch": item["editorMatch"]}


def service_changes(before, after):
    old = {item["class"]: item for item in before["services"]}
    new = {item["class"]: item for item in after["services"]}
    changes = []
    for name in sorted(old.keys() | new.keys()):
        previous, current = old.get(name), new.get(name)
        if previous != current:
            changes.append({"service": name, "before": previous, "after": current})
    for field in ("collisionGroups", "collisionMatrix", "materialOverrides"):
        if before.get(field) != after.get(field):
            changes.append({"field": field, "before": before.get(field), "after": after.get(field)})
    return changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, required=True)
    parser.add_argument("--after", type=Path, required=True)
    parser.add_argument("--before-native-report", type=Path, required=True)
    parser.add_argument("--after-native-report", type=Path, required=True)
    parser.add_argument("--approved-after-source", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=TASK / "native-scope-verification.json")
    args = parser.parse_args()
    before_meta, after_meta = read(args.before / "metadata.json"), read(args.after / "metadata.json")
    for metadata in (before_meta, after_meta):
        assert metadata["placeId"] == 131311258779917 and metadata["universeId"] == 10559217407
        assert not metadata["editorConflicts"] and not metadata["skipped"]
    before, after = source_map(read(args.before / "scripts.json")), source_map(read(args.after / "scripts.json"))
    assert len(before) == 205 and before.keys() == after.keys()
    approved = args.approved_after_source.read_bytes()
    assert before[PATH]["class"] == after[PATH]["class"] == "ModuleScript"
    assert after[PATH]["source"].encode() == approved, "Actual captured Source differs from exact approved proposal"
    replacements = read(TASK / "approved-source-replacements.json")
    assert replacements["path"] == PATH and replacements["class"] == "ModuleScript"
    assert digest(before[PATH]["source"].encode()) == replacements["beforeSha256"]
    assert digest(approved) == replacements["afterSha256"]
    assert len(replacements["replacements"]) == 2, "Expected only helper insertion and one call substitution"
    expected = before[PATH]["source"]
    for replacement in replacements["replacements"]:
        assert expected.count(replacement["before"]) == 1, "Approved span is absent or ambiguous"
        expected = expected.replace(replacement["before"], replacement["after"], 1)
    assert expected.encode() == approved, "Proposal changes Source beyond the two approved spans"
    changes = []
    for path in sorted(before):
        old, new = before[path], after[path]
        assert old["class"] == new["class"], "Source class changed: " + path
        if old["source"] != new["source"]:
            changes.append({"path": path, "before": source_identity(old), "after": source_identity(new)})
    assert PATH in {entry["path"] for entry in changes}, "Approved LobbyShopDisplay edit is absent"
    unscoped_sources = [entry for entry in changes if entry["path"] != PATH]
    old_native, new_native = read(args.before_native_report), read(args.after_native_report)
    assert len(new_native["sourceNormalization"]) == 1 and new_native["sourceNormalization"][0]["path"] == PATH
    expected_root = new_native["sourceNormalization"][0]["root"]
    root_changes, unscoped_native = [], []
    for path in sorted(old_native["rootRecords"].keys() | new_native["rootRecords"].keys()):
        old, new = old_native["rootRecords"].get(path), new_native["rootRecords"].get(path)
        old_hash, new_hash = (old or {}).get("actualSHA256"), (new or {}).get("actualSHA256")
        if old_hash != new_hash:
            root_changes.append({"path": path, "beforeSHA256": old_hash, "afterSHA256": new_hash})
        if not old or not new or old["actualSHA256"] != new["sourceNormalizedSHA256"]:
            unscoped_native.append({"path": path, "before": old, "after": new})
    forest_equal = old_native["canonicalWholeForestSHA256"] == new_native["sourceNormalizedWholeForestSHA256"]
    services = service_changes(before_meta, after_meta)
    errors = []
    if unscoped_sources:
        errors.append("Concurrent or unscoped Source changes require review")
    if unscoped_native or not forest_equal:
        errors.append("Native objects or properties differ beyond the approved Source edit")
    if services:
        errors.append("Service/global setting changes require review")
    target = TASK / "verified-studio-mirror/ServerScriptService/LobbyShopDisplay.ModuleScript.luau"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert target.read_bytes() == approved, "Refusing to overwrite different verified Source bytes"
    target.write_bytes(approved)
    manifest = {"path": PATH, **source_identity(after[PATH]), "file": str(target.relative_to(TASK))}
    report = {"schema": "lobby-box-glow-authoritative-native-scope/1", "passed": not errors,
        "placeId": after_meta["placeId"], "universeId": after_meta["universeId"],
        "beforeCapturedAt": before_meta["capturedAt"], "afterCapturedAt": after_meta["capturedAt"],
        "beforeNativeSHA256": digest((args.before / "all-service-children.rbxm").read_bytes()),
        "afterNativeSHA256": digest((args.after / "all-service-children.rbxm").read_bytes()),
        "sources": {"beforeCount": len(before), "afterCount": len(after), "sourceEditorParityAll": True,
            "actualSourceExactlyMatchesApprovedProposal": True, "changes": changes,
            "exactApprovedReplacementSpans": len(replacements["replacements"]),
            "unrelatedByteIdenticalCount": len(before) - len(changes), "unscopedChanges": unscoped_sources},
        "native": {"beforeRootCount": old_native["rootCount"], "afterRootCount": new_native["rootCount"],
            "expectedChangedRoot": expected_root, "rootChanges": root_changes,
            "unscopedObjectOrPropertyChanges": unscoped_native,
            "allNativePropertiesEqualAfterComparisonOnlySourceNormalization": forest_equal,
            "beforeCanonicalForestSHA256": old_native["canonicalWholeForestSHA256"],
            "afterSourceNormalizedForestSHA256": new_native["sourceNormalizedWholeForestSHA256"],
            "serviceAndGlobalSettingChanges": services},
        "verifiedStudioMirror": manifest, "errors": errors,
        "limitations": ["Native/source comparison is not a gameplay or rendering test.",
            "The complete raw native capture and service metadata are preserved alongside reconstruction property limitations."]}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    (target.parent.parent / "manifest.json").write_text(json.dumps({"placeId": after_meta["placeId"],
        "universeId": after_meta["universeId"], "capturedAt": after_meta["capturedAt"], "scripts": [manifest]}, indent=2) + "\n")
    print(json.dumps({"passed": not errors, "sources": len(after), "changes": len(changes),
        "unrelatedSourcesEqual": len(before) - len(changes), "unscopedNativeChanges": len(unscoped_native),
        "serviceChanges": len(services), "report": str(args.output)}, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
