#!/usr/bin/env python3
"""Read-only strict verification and export of the four approved Studio edits.

All comparisons use fresh authoritative native captures. This utility never
connects to Studio, changes purchase settings, stages files, or publishes.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

TASK = Path(__file__).resolve().parent
SCOPED = {
    "ReplicatedStorage.ZyntraConfig": "ModuleScript",
    "ReplicatedStorage.ZyntraSkinsPage": "ModuleScript",
    "ServerScriptService.LobbyShopDisplay": "ModuleScript",
    "StarterPlayer.StarterPlayerScripts.ZyntraStore": "LocalScript",
}


def read_json(path):
    return json.loads(Path(path).read_bytes())


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_map(records):
    result = {}
    for record in records:
        assert record["path"] not in result, record["path"]
        assert record["editorMatch"] is True, record["path"]
        result[record["path"]] = record
    return result


def source_identity(item):
    return {"class": item["class"], "sourceBytes": len(item["source"].encode()),
            "sourceSha256": digest(item["source"].encode()), "editorMatch": item["editorMatch"]}


def service_changes(before, after):
    previous = {item["class"]: item for item in before["services"]}
    current = {item["class"]: item for item in after["services"]}
    changes = []
    for name in sorted(previous.keys() | current.keys()):
        old, new = previous.get(name), current.get(name)
        if old == new:
            continue
        fields = {}
        for field in sorted((old or {}).keys() | (new or {}).keys()):
            old_value, new_value = (old or {}).get(field), (new or {}).get(field)
            if old_value == new_value:
                continue
            if isinstance(old_value, dict) and isinstance(new_value, dict):
                fields[field] = {key: {"before": old_value.get(key), "after": new_value.get(key)}
                                 for key in sorted(old_value.keys() | new_value.keys())
                                 if old_value.get(key) != new_value.get(key)}
            else:
                fields[field] = {"before": old_value, "after": new_value}
        changes.append({"service": name, "changes": fields})
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
    parser.add_argument("--published-mapping", type=Path, required=True)
    parser.add_argument("--after-catalog", type=Path)
    parser.add_argument("--output", type=Path, default=TASK / "native-scope-verification.json")
    args = parser.parse_args()
    before_meta, after_meta = read_json(args.before / "metadata.json"), read_json(args.after / "metadata.json")
    for metadata in (before_meta, after_meta):
        assert metadata["placeId"] == 131311258779917 and metadata["universeId"] == 10559217407
        assert not metadata["editorConflicts"] and not metadata["skipped"]
    before = source_map(read_json(args.before / "scripts.json"))
    after = source_map(read_json(args.after / "scripts.json"))
    assert len(before) == 205, "Fresh baseline does not contain the audited 205 Sources"
    assert before.keys() == after.keys(), "Source instances added or removed"
    changes = []
    for path in sorted(before):
        old, new = before[path], after[path]
        assert old["class"] == new["class"], "Source class changed: " + path
        if old["source"] != new["source"]:
            changes.append({"path": path, "before": source_identity(old), "after": source_identity(new)})
    changed_paths = {item["path"] for item in changes}
    assert set(SCOPED) <= changed_paths, "An approved Source edit is absent"
    unscoped_sources = [item for item in changes if item["path"] not in SCOPED]

    spec = importlib.util.spec_from_file_location("shop_icon_scope", TASK / "verify_shop_icon_scope.py")
    icon_verifier = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(icon_verifier)
    ids = icon_verifier.mapping_ids(read_json(args.published_mapping))
    icon_check = icon_verifier.verify_sources(
        before["ReplicatedStorage.ZyntraConfig"]["source"], after["ReplicatedStorage.ZyntraConfig"]["source"],
        before["ServerScriptService.LobbyShopDisplay"]["source"], after["ServerScriptService.LobbyShopDisplay"]["source"], ids)
    if args.after_catalog:
        icon_check["evaluated_catalog"] = icon_verifier.compare_catalogs(
            read_json(TASK / "audit/live-catalog.json"), read_json(args.after_catalog), ids)

    pricing = read_json(TASK / "pricing-fix/exact-replacements.json")
    pricing_checks = []
    for entry in pricing["scripts"]:
        path = entry["path"]
        old_source = before[path]["source"]
        assert before[path]["class"] == after[path]["class"] == entry["class"] == SCOPED[path]
        assert digest(old_source.encode()) == entry["beforeSourceSHA256"], "Pricing baseline mismatch " + path
        proposed = old_source
        for replacement in entry["replacements"]:
            assert proposed.count(replacement["old"]) == 1, "Pricing span is absent or ambiguous " + path
            proposed = proposed.replace(replacement["old"], replacement["new"], 1)
        assert digest(proposed.encode()) == entry["afterSourceSHA256"]
        assert proposed == after[path]["source"], "Actual Source differs from approved pricing spans " + path
        pricing_checks.append({"path": path, "exactApprovedSpans": len(entry["replacements"]),
                               "beforeSha256": entry["beforeSourceSHA256"],
                               "afterSha256": entry["afterSourceSHA256"],
                               "actualSourceExactlyMatchesProposal": True})

    old_native, new_native = read_json(args.before_native_report), read_json(args.after_native_report)
    expected_roots = {entry["root"] for entry in new_native["sourceNormalization"]}
    assert len(expected_roots) == 4 and {entry["path"] for entry in new_native["sourceNormalization"]} == set(SCOPED)
    root_changes, unscoped_native = [], []
    for path in sorted(old_native["rootRecords"].keys() | new_native["rootRecords"].keys()):
        old, new = old_native["rootRecords"].get(path), new_native["rootRecords"].get(path)
        old_hash, new_hash = (old or {}).get("actualSHA256"), (new or {}).get("actualSHA256")
        if old_hash != new_hash:
            root_changes.append({"path": path, "beforeSha256": old_hash, "afterSha256": new_hash})
        if not old or not new or old["actualSHA256"] != new["sourceNormalizedSHA256"]:
            unscoped_native.append({"path": path, "before": old, "after": new})
    services = service_changes(before_meta, after_meta)
    forest_equal = old_native["canonicalWholeForestSHA256"] == new_native["sourceNormalizedWholeForestSHA256"]
    errors = []
    if unscoped_sources:
        errors.append("Concurrent or unscoped Source changes require review")
    if unscoped_native or not forest_equal:
        errors.append("Native properties or objects differ beyond the four approved Source edits")
    if services:
        errors.append("Service properties, attributes, tags or global settings differ and require review")

    mirror = TASK / "verified-studio-mirror"
    manifest = []
    for path, klass in SCOPED.items():
        assert after[path]["class"] == klass
        file = mirror / Path(*path.split(".")).with_suffix("." + klass + ".luau")
        file.parent.mkdir(parents=True, exist_ok=True)
        payload = after[path]["source"].encode()
        if file.exists():
            assert file.read_bytes() == payload, "Refusing to overwrite a different verified Source export"
        file.write_bytes(payload)
        manifest.append({"path": path, **source_identity(after[path]), "file": str(file.relative_to(TASK))})
    report = {
        "schema": "robux-icons-authoritative-native-scope/1", "passed": not errors,
        "placeId": before_meta["placeId"], "universeId": before_meta["universeId"],
        "beforeCapturedAt": before_meta["capturedAt"], "afterCapturedAt": after_meta["capturedAt"],
        "beforeNativeSha256": digest((args.before / "all-service-children.rbxm").read_bytes()),
        "afterNativeSha256": digest((args.after / "all-service-children.rbxm").read_bytes()),
        "sources": {"beforeCount": len(before), "afterCount": len(after), "approvedChangeCount": 4,
                    "byteIdenticalUnrelatedCount": len(before) - len(changes),
                    "sourceEditorParityAll": True, "changes": changes, "unscopedChanges": unscoped_sources},
        "icons": icon_check, "pricing": pricing_checks,
        "native": {"beforeRootCount": old_native["rootCount"], "afterRootCount": new_native["rootCount"],
                   "expectedChangedRoots": sorted(expected_roots), "rootChanges": root_changes,
                   "unscopedObjectOrPropertyChanges": unscoped_native,
                   "allNativePropertiesEqualAfterComparisonOnlySourceNormalization": forest_equal,
                   "beforeCanonicalForestSHA256": old_native["canonicalWholeForestSHA256"],
                   "afterSourceNormalizedForestSHA256": new_native["sourceNormalizedWholeForestSHA256"],
                   "servicePropertyAttributeTagAndGlobalSettingChanges": services},
        "verifiedStudioMirror": manifest, "publishedImageIds": ids,
        "errors": errors,
        "limitations": ["Source contracts and native comparisons do not prove completed real purchases or multiplayer behavior.",
                        "Native reconstruction property limitations remain recorded in each native-place-verification.json; raw native children and live service metadata are retained."]}
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    (mirror / "manifest.json").write_text(json.dumps({"placeId": after_meta["placeId"],
        "universeId": after_meta["universeId"], "capturedAt": after_meta["capturedAt"],
        "sourceAndEditorVerified": True, "scripts": manifest}, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "sources": len(after), "changes": len(changes),
                      "nativeRoots": new_native["rootCount"], "unscopedSourceChanges": len(unscoped_sources),
                      "unscopedNativeChanges": len(unscoped_native), "serviceChanges": len(services),
                      "report": str(args.output)}, indent=2))
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
