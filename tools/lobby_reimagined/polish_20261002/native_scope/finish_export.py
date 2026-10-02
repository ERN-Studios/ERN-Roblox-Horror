"""Verify a completed native audit before exporting six scoped Studio mirrors.

No Studio, network, Git, index, or publish APIs. Default mode is read-only;
--write explicitly exports only the task's local source/evidence directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def file_sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


SOURCE_DELTA_KEYS = ("path", "class", "kind", "beforeSHA256", "afterSHA256", "beforeBytes", "afterBytes")
REVIEW_KEYS = {
    "schema", "approvedForTaskSourceExportOnly", "reviewedBy", "reviewPurpose",
    "nativeAuditSHA256", "beforeCaptureId", "afterCaptureId", "beforeNativeSHA256", "afterNativeSHA256",
    "beforeSourceCatalogSHA256", "afterSourceCatalogSHA256", "sourceDeltas", "nativeDeltaDigests",
    "publicationAuthorized", "cleanupAuthorized", "ownerIdentityConfirmed", "publicationHoldReason",
}


def source_delta(row) -> dict:
    return {key: row.get(key) for key in SOURCE_DELTA_KEYS}


def validate_concurrent_review(args, report, native_raw, meta, raw_sources, index) -> tuple[dict, bytes]:
    """A closed review permits extraction; it never changes native parity."""
    assert args.concurrent_review and args.before, "Strict native audit differs; exact concurrent review and before capture required"
    raw = args.concurrent_review.read_bytes()
    review = json.loads(raw)
    assert set(review) == REVIEW_KEYS, "Unexpected/missing concurrent review fields"
    assert review["schema"] == "lobby-polish-reviewed-concurrent-export-v1"
    assert review["approvedForTaskSourceExportOnly"] is True
    assert isinstance(review["reviewedBy"], str) and review["reviewedBy"]
    assert isinstance(review["reviewPurpose"], str) and review["reviewPurpose"]
    assert review["publicationAuthorized"] is False and review["cleanupAuthorized"] is False
    assert review["ownerIdentityConfirmed"] is False
    assert isinstance(review["publicationHoldReason"], str) and review["publicationHoldReason"]
    assert review["nativeAuditSHA256"] == sha(native_raw), "Review binds a different native audit"
    for field in ("beforeCaptureId", "afterCaptureId", "beforeNativeSHA256", "afterNativeSHA256"):
        assert review[field] == report[field], "Review capture/native binding differs: " + field
    before = args.before.resolve()
    old_meta = json.loads((before / "metadata.json").read_bytes())
    assert (old_meta["placeId"], old_meta["universeId"], old_meta["groupId"]) == (meta["placeId"], meta["universeId"], meta["groupId"])
    assert old_meta["captureId"] == report["beforeCaptureId"]
    assert old_meta["nativeSHA256"] == report["beforeNativeSHA256"]
    assert file_sha(before / "all-service-children.rbxm") == report["beforeNativeSHA256"]
    old_raw = (before / "scripts.json").read_bytes()
    assert review["beforeSourceCatalogSHA256"] == sha(old_raw)
    assert review["afterSourceCatalogSHA256"] == sha(raw_sources)
    old_rows = json.loads(old_raw)
    assert len(old_rows) == old_meta["scriptCount"] == report["beforeSourceCount"]
    old_index = {}
    for row in old_rows:
        assert row["path"] not in old_index, "Before Source path collision"
        source = row["source"].encode()
        assert row["editorMatch"] is True
        assert row["sourceBytes"] == len(source)
        assert row["sourceSha256"] == row["editorSourceSha256"] == sha(source)
        old_index[row["path"]] = row
    computed = []
    for path in sorted(set(old_index) | set(index)):
        if path in EXPECTED:
            continue
        old, new = old_index.get(path), index.get(path)
        if old and new and old["source"] == new["source"] and old["class"] == new["class"]:
            continue
        assert not old or not new or old["class"] == new["class"], "Concurrent Source class change is not covered"
        computed.append({"path": path, "class": (new or old)["class"],
                         "kind": "changed" if old and new else "added" if new else "removed",
                         "beforeSHA256": old["sourceSha256"] if old else None,
                         "afterSHA256": new["sourceSha256"] if new else None,
                         "beforeBytes": old["sourceBytes"] if old else None,
                         "afterBytes": new["sourceBytes"] if new else None})
    assert isinstance(review["sourceDeltas"], list) and computed, "No closed concurrent Source review"
    for row in review["sourceDeltas"]:
        assert set(row) == set(SOURCE_DELTA_KEYS) and row["path"] not in EXPECTED
    approved_sources = sorted(review["sourceDeltas"], key=lambda row: row["path"])
    reported_sources = sorted([source_delta(row) for row in report["unclassifiedConcurrentSourceDeltas"]], key=lambda row: row["path"])
    assert canonical(approved_sources) == canonical(computed) == canonical(reported_sources), "Unreviewed/different concurrent Source delta"
    native_digests = [{"path": row["path"], "kind": row["kind"], "sha256": sha(canonical(row))}
                      for row in report["unclassifiedConcurrentNativeDeltas"]]
    assert isinstance(review["nativeDeltaDigests"], list) and native_digests
    for row in review["nativeDeltaDigests"]:
        assert set(row) == {"path", "kind", "sha256"}
    order = lambda row: (row["path"], row["kind"], row["sha256"])
    assert canonical(sorted(review["nativeDeltaDigests"], key=order)) == canonical(sorted(native_digests, key=order)), "Unreviewed/different concurrent native delta"
    return review, raw


EXPECTED = {
    "ServerScriptService.LobbyReimaginedPreview.Builder": "ModuleScript",
    "ServerScriptService.LobbyReimaginedPreview.EndBlockades": "ModuleScript",
    "ServerScriptService.LobbyReimaginedPreview.MaterialPolish": "ModuleScript",
    "ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays": "ModuleScript",
    "ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene": "ModuleScript",
    "StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController": "LocalScript",
}
SUMMARY_FILES = (
    "metadata.json", "metadata.received.json", "backup-metadata-summary.json",
    "backup-file-hashes.json", "source-manifest.json", "checkpoint-install-gate.json",
    "checkpoint-reuse-proof.json", "native-recovery-reopen-verification.json",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", type=Path, required=True)
    parser.add_argument("--frozen", type=Path, required=True)
    parser.add_argument("--native-report", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--before", type=Path)
    parser.add_argument("--concurrent-review", type=Path)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    capture = args.capture.resolve()
    meta_raw = (capture / "metadata.json").read_bytes()
    meta = json.loads(meta_raw)
    assert (meta["placeId"], meta["universeId"], meta["groupId"]) == (131311258779917, 10559217407, 1039373905)
    assert not meta["editorConflicts"] and not meta["skipped"]
    raw_sources = (capture / "scripts.json").read_bytes()
    rows = json.loads(raw_sources)
    assert len(rows) == meta["scriptCount"]
    index = {}
    for row in rows:
        assert row["path"] not in index, "Source path collision"
        index[row["path"]] = row
        source = row["source"].encode()
        digest = sha(source)
        assert row["editorMatch"] is True
        assert row["sourceBytes"] == len(source)
        assert row["sourceSha256"] == row["editorSourceSha256"] == digest
    frozen_raw = args.frozen.read_bytes()
    frozen = json.loads(frozen_raw)
    assert len(frozen) == 6 and {row["path"]: row["className"] for row in frozen} == EXPECTED
    native_raw = args.native_report.read_bytes()
    report = json.loads(native_raw)
    assert report["taskScopeVerified"] is True
    assert "errors" in report and isinstance(report["errors"], (list, dict)) and len(report["errors"]) == 0
    assert report["serverLobby"]["unchangedBeyondTaskScope"] is True
    assert report["afterCaptureId"] == meta["captureId"]
    assert report["afterNativeSHA256"] == meta["nativeSHA256"]
    assert report["afterSourceCount"] == len(rows) and report["afterRootCount"] == meta["rootCount"]
    assert sha(raw_sources) == meta["sourceTransfer"]["sha256"]
    assert len(raw_sources) == meta["sourceTransfer"]["bytes"]
    assert report["frozenSourcesSHA256"] == sha(frozen_raw), "Audit used a different final pin file"
    concurrent_review, concurrent_review_raw = None, None
    if report["verified"] is True:
        assert args.concurrent_review is None, "A strict parity pass needs no concurrent exception"
        assert report["wholeForestPreservedBeyondTaskScope"] is True
        assert not report["unclassifiedConcurrentSourceDeltas"] and not report["unclassifiedConcurrentNativeDeltas"]
    else:
        assert report["verified"] is False and report["wholeForestPreservedBeyondTaskScope"] is False
        concurrent_review, concurrent_review_raw = validate_concurrent_review(args, report, native_raw, meta, raw_sources, index)
    gate = json.loads((capture / "checkpoint-install-gate.json").read_bytes())
    assert gate["verified"] is True and gate["captureId"] == meta["captureId"]
    assert gate["nativeSHA256"] == meta["nativeSHA256"]
    assert file_sha(capture / "all-service-children.rbxm") == meta["nativeSHA256"]
    for bound in gate["files"]:
        path = (capture / bound["file"]).resolve()
        assert path.is_relative_to(capture) and path.is_file()
        assert path.stat().st_size == bound["bytes"] and file_sha(path) == bound["sha256"], "Native recovery file changed"
    source_outputs = {}
    source_receipts = []
    for pin in frozen:
        row = index[pin["path"]]
        source = row["source"].encode()
        assert row["class"] == pin["className"] and sha(source) == pin["sha256"]
        assert Path(pin["file"]).read_bytes() == source, "Frozen candidate differs from exact Studio export"
        filename = row["path"] + "." + row["class"] + ".luau"
        source_outputs[filename] = source
        source_receipts.append({"path": row["path"], "class": row["class"], "file": filename,
                                "sourceBytes": len(source), "sourceSha256": sha(source), "editorMatch": True})
    full_manifest = [{"path": row["path"], "class": row["class"], "sourceBytes": row["sourceBytes"],
                      "sourceSha256": row["sourceSha256"], "editorSourceSha256": row["editorSourceSha256"],
                      "editorMatch": True} for row in rows]
    outputs = dict(source_outputs)
    for filename in SUMMARY_FILES:
        outputs["native-after/" + filename] = (capture / filename).read_bytes()
    outputs["native-after/native-scope-verification.json"] = native_raw
    if concurrent_review_raw is not None:
        outputs["native-after/concurrent-export-review.json"] = concurrent_review_raw
    manifest = {"schema": "lobby-polish-scoped-studio-export-v1", "verified": report["verified"],
                "taskSourceExportVerified": True, "taskScopeVerified": report["taskScopeVerified"],
                "strictNativeAuditVerified": report["verified"],
                "wholeForestPreservedBeyondTaskScope": report["wholeForestPreservedBeyondTaskScope"],
                "concurrentDeltasReviewedForTaskSourceExportOnly": concurrent_review is not None,
                "concurrentReviewSHA256": sha(concurrent_review_raw) if concurrent_review_raw is not None else None,
                "concurrentSourceDeltas": report["unclassifiedConcurrentSourceDeltas"],
                "concurrentNativeDeltas": report["unclassifiedConcurrentNativeDeltas"],
                "publicationAuthorized": False, "cleanupAuthorized": False,
                "publicationHoldReason": concurrent_review["publicationHoldReason"] if concurrent_review else None,
                "exportScope": "Exactly six task Sources/editor plus full source hash inventory and native proof metadata; no unrelated Source mirrors",
                "placeId": meta["placeId"], "universeId": meta["universeId"], "groupId": meta["groupId"],
                "observedPlaceVersion": meta["placeVersion"], "captureId": meta["captureId"],
                "capturedAt": meta["capturedAt"], "nativeCaptureDirectory": str(capture),
                "nativeSHA256": meta["nativeSHA256"], "nativeBytes": meta["nativeBytes"],
                "fullNativeSourceCount": len(rows), "fullSourceCatalog": sorted(full_manifest, key=lambda row: row["path"]),
                "sourceMirrors": sorted(source_receipts, key=lambda row: row["path"]),
                "sourceCatalogBytes": len(raw_sources), "sourceCatalogSHA256": sha(raw_sources),
                "frozenPinsSHA256": sha(frozen_raw), "nativeAuditSHA256": sha(native_raw),
                "rawNativeFilesExcludedFromGit": True, "sourceEditorConflicts": 0,
                "limits": "Native/source parity does not prove multiplayer, performance, texture shader rendering or publication"}
    outputs["manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    # Validate every existing destination before any write, preserving differing bytes.
    for filename, raw in outputs.items():
        path = args.destination / filename
        if path.exists():
            assert path.read_bytes() == raw, "Refuse different existing export bytes: " + str(path)
    if args.write:
        for filename, raw in outputs.items():
            path = args.destination / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
    print(json.dumps({"taskSourceExportVerified": True, "strictNativeAuditVerified": report["verified"],
                      "wholeForestPreservedBeyondTaskScope": report["wholeForestPreservedBeyondTaskScope"],
                      "publicationAuthorized": False, "wrote": args.write, "destination": str(args.destination),
                      "sourceMirrorCount": len(source_outputs), "fullSourceCount": len(rows),
                      "files": sorted(outputs), "captureId": meta["captureId"]}))


if __name__ == "__main__":
    main()
