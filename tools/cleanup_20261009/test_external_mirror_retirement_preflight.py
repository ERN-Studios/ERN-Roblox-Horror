"""Exercise the actual read-only S06 validator/proposal without file mutations.

After retirement, supply the archived sources/manifest with --source-root and
--manifest. These are source-contract tests; no native/gameplay claim follows.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import prepare_external_mirror_retirement as actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=actual.ROOT)
    parser.add_argument("--manifest", type=Path, default=actual.ROOT / "studio-sync-manifest.json")
    parser.add_argument("--native-evidence", type=Path, default=actual.EVIDENCE)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.receipt:
        assert not args.receipt.exists(), "Refuse receipt overwrite"
    manifest_raw, evidence_raw = args.manifest.read_bytes(), args.native_evidence.read_bytes()
    sources = {file: (args.source_root / file).read_bytes() for file in actual.FILES}
    heads = {file: raw.replace(b"\r\n", b"\n") for file, raw in sources.items()}
    manifest, evidence = json.loads(manifest_raw), json.loads(evidence_raw)
    checks, positives, negatives = 0, [], []

    def check(value, label):
        nonlocal checks
        checks += 1
        assert value, label

    records = actual.validate(manifest_raw, evidence_raw, sources, heads)
    check(len(records) == 12, "Actual validator exact scope")
    positives.append("actual12 held-native Source/editor/digest/class/property contracts")
    crlf_sources = {file: raw.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n") for file, raw in sources.items()}
    check(len(actual.validate(manifest_raw, evidence_raw, crlf_sources, heads)) == 12, "Canonical LF contract")
    positives.append("canonical LF comparison accepts byte-recorded CRLF mirror")

    def reject(label, *, m=None, e=None, s=None, h=None):
        try:
            actual.validate(actual.encode(m) if m is not None else manifest_raw,
                            actual.encode(e) if e is not None else evidence_raw,
                            sources if s is None else s, heads if h is None else h)
        except (AssertionError, KeyError):
            negatives.append(label)
            check(True, label)
        else:
            raise AssertionError("Missing negative guard: " + label)

    first_file = sorted(actual.FILES)[0]
    changed = dict(sources)
    changed[first_file] += b"-- concurrent actor change\n"
    reject("concurrent selected Source edit", s=changed)
    changed_head = dict(heads)
    changed_head[first_file] += b"-- owner HEAD change\n"
    reject("selected source no longer equals HEAD", h=changed_head)
    for key, value in (("editorMatchesSource", False), ("editorReadable", False),
                       ("sourceMatchesCapture", False), ("class", "Script"),
                       ("sourceSHA256", "0" * 64), ("sourceBytes", 1)):
        changed_e = copy.deepcopy(evidence)
        changed_e["heldOutOfGameSources"][0][key] = value
        reject("native " + key + " guard", e=changed_e)
    changed_e = copy.deepcopy(evidence)
    changed_e["heldRemovedRoots"][0]["currentParent"] = "ServerStorage"
    # First held root is not one of the12-source roots; target its own root.
    target_root = evidence["heldOutOfGameSources"][0]["parent"]
    for root in changed_e["heldRemovedRoots"]:
        if root["name"] == target_root:
            root["currentParent"] = "ServerStorage"
    reject("target root reintroduced", e=changed_e)
    changed_e = copy.deepcopy(evidence)
    changed_e["heldOutOfGameSources"].append(copy.deepcopy(changed_e["heldOutOfGameSources"][0]))
    reject("duplicate or expanded held-source identity", e=changed_e)
    for field, value in (("className", "LocalScript"), ("attributes", {"Owner": "actor"}),
                         ("properties", {"Archivable": False, "LinkedSource": ""}),
                         ("file", "../foreign.lua"), ("studioTrailingNewline", True)):
        changed_m = copy.deepcopy(manifest)
        selected = next(r for r in changed_m["items"] if r["studioPath"] in actual.PATHS)
        selected[field] = value
        reject("manifest " + field + " guard", m=changed_m)
    changed_m = copy.deepcopy(manifest)
    changed_m["items"].append(copy.deepcopy(changed_m["items"][0]))
    reject("duplicate manifest identity", m=changed_m)

    candidate = copy.deepcopy(manifest)
    owner = {"studioPath": "ReplicatedStorage.OwnerConcurrentFixture", "className": "ModuleScript",
             "file": "ReplicatedStorage/OwnerConcurrentFixture.ModuleScript.lua", "custom": {"retain": [1, 2, 3]}}
    candidate["items"].append(owner)
    candidate["ownerMetadata"] = {"literal": "untouched", "revision": 37}
    candidate["counts"]["scripts"] = 0  # stale headers must use actual survivors
    candidate["counts"]["total"] = 0
    after = json.loads(actual.proposal(actual.encode(candidate)))
    before_rows = {r["studioPath"]: r for r in candidate["items"]}
    after_rows = {r["studioPath"]: r for r in after["items"]}
    check(set(after_rows) == set(before_rows) - actual.PATHS, "Exactly12 removed from proposal")
    check(all(after_rows[path] == row for path, row in before_rows.items() if path not in actual.PATHS), "All owner rows preserved")
    check(after["ownerMetadata"] == candidate["ownerMetadata"], "Owner top metadata preserved")
    check(after["counts"]["scripts"] == 211 and after["counts"]["total"] == 226, "Actual counts include concurrent extra row")
    check(all(after["counts"][key] == value for key, value in candidate["counts"].items()
              if key not in ("scripts", "remoteEvents", "total")), "Historical sync counters preserved")
    positives.append("proposal preserves concurrent row/top metadata and recomputes stale actual counts")
    try:
        actual.proposal(json.dumps(candidate).encode())
    except AssertionError:
        negatives.append("unexpected manifest formatting")
        check(True, "Unexpected format rejects rather than rewriting actor rows")
    else:
        raise AssertionError("Missing format guard")

    for path in (Path(actual.__file__), Path(__file__)):
        ast.parse(path.read_text(encoding="utf8"), filename=str(path))
        check(True, "Actual helper/test AST")
    check(args.manifest.read_bytes() == manifest_raw and args.native_evidence.read_bytes() == evidence_raw, "Read-only input facts unchanged")
    check(all((args.source_root / file).read_bytes() == raw for file, raw in sources.items()), "All12 source bytes unchanged")
    receipt = {"schema": "external-mirror-retirement-preflight-tests-v1", "pass": True,
               "positives": positives, "negativeControls": negatives, "checks": checks,
               "nativeCalls": 0, "runtimeRequires": 0, "canonicalSourceWrites": 0, "manifestWrites": 0,
               "helperSHA256": actual.sha(Path(actual.__file__).read_bytes()),
               "testSHA256": actual.sha(Path(__file__).read_bytes()),
               "manifestSHA256": actual.sha(manifest_raw), "nativeEvidenceSHA256": actual.sha(evidence_raw),
               "scope": "Actual read-only validator/proposal contracts; native full-object archive and gameplay tests are separate."}
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        with args.receipt.open("xb") as stream:
            stream.write(actual.encode(receipt))
    print(json.dumps(receipt))


if __name__ == "__main__":
    main()
