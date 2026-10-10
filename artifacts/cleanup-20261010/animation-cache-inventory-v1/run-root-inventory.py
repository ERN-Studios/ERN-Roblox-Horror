"""ROOT ONLY: bounded readonly animation-cache capture; never retry or switch Play.

Default validates frozen artifacts without loading Studio MCP. --apply requires
an exact independent peer pin and a new artifact directory. Mutations are limited
to the collector's owned shared scratch namespace, counted separately. Unknown
transport stops every later native call; closing transport is not cancellation.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import math
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda raw: hashlib.sha256(raw).hexdigest()
ZERO_FIELDS = ("nativeInstanceWrites", "nativeSourceWrites", "nativePropertyWrites", "modeSwitches")


class CaptureFailure(RuntimeError):
    def __init__(self, message, outcome, scratch_pending=True):
        super().__init__(message)
        self.outcome = outcome
        self.scratch_pending = scratch_pending


def zero_writes(report):
    for field in ZERO_FIELDS:
        assert type(report[field]) is int and report[field] == 0, field


def request_code(collector, command, capture_id, page=None):
    fields = {"command": command, "captureId": capture_id, "templateSHA256": SHA(collector)}
    if page is not None:
        fields["page"] = page
    # JSON string literal is a Lua string literal for our ASCII-only request.
    raw = json.dumps(fields, separators=(",", ":"), ensure_ascii=True)
    return ("local REQUEST=game:GetService('HttpService'):JSONDecode(" + json.dumps(raw) + ")\n").encode() + collector


def native_read(client, studio_id, code, label, save):
    save(label + "-request.json", {"executedCodeSHA256": SHA(code), "executedCodeBytes": len(code),
                                  "studioId": studio_id, "dataModel": "Edit", "singleRequestTimeoutSeconds": 600})
    started = time.monotonic()
    try:
        response = client._request("tools/call", {"name": "execute_luau", "arguments": {
            "studio_id": studio_id, "datamodel_type": "Edit", "code": code.decode("utf-8")}}, timeout=600)
    except BaseException as error:
        save(label + "-unknown-transport.json", {"error": str(error), "nativeOutcome": "unknown",
                                               "noFollowupNativeCalls": True, "localCloseIsNotCancellation": True,
                                               "executedCodeSHA256": SHA(code)})
        raise CaptureFailure(str(error), "unknown-transport") from error
    envelope = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode()
    if len(envelope) > 100000:
        save(label + "-oversized-envelope.json", {"bytes": len(envelope), "sha256": SHA(envelope),
                                                 "archivedWholeEnvelope": False, "nativeOutcome": "unknown-envelope"})
        raise CaptureFailure("Bounded envelope exceeded; full oversized envelope not archived", "unknown-envelope")
    save(label + "-api.json", envelope)
    result = response.get("result") if type(response) is dict else None
    if type(result) is not dict or type(result.get("content")) is not list:
        raise CaptureFailure("Missing completion result/content", "unknown-envelope")
    if any(type(block) is not dict or (block.get("type") == "text" and type(block.get("text")) is not str)
           for block in result["content"]):
        raise CaptureFailure("Invalid text completion block", "unknown-envelope")
    text = "\n".join(block["text"] for block in result["content"] if block.get("type") == "text")
    raw = text.encode("utf-8")
    save(label + "-completion-raw.txt", raw)
    save(label + "-provenance.json", {"executedCodeSHA256": SHA(code), "actualCompletionSHA256": SHA(raw),
                                      "rootClientWallSeconds": round(time.monotonic() - started, 3),
                                      "limits": "Actual tool duration is not a performance gain."})
    if result.get("isError"):
        raise CaptureFailure("Completed tool error; no retry or automatic scratch cleanup", "completed-tool-error")
    if len(raw) > 20000:
        raise CaptureFailure("Bounded collector completion exceeded", "completed-invalid-completion")
    try:
        report = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise CaptureFailure(str(error), "completed-invalid-completion") from error
    save(label + "-completion.json", report)
    if type(report) is not dict:
        raise CaptureFailure("Non-object collector completion", "completed-invalid-completion")
    if report.get("pass") is False:
        pending = report.get("collectorCleanupPassed") is not True and report.get("collectorAcquired") is not False
        raise CaptureFailure("Collector refused: " + str(report.get("error")), "completed-collector-refusal", pending)
    return report


def validate_manifest(manifest, begin, capture_id, collector_sha):
    assert manifest["schema"] == "mongotv-animation-cache-preservation-manifest-v1"
    assert manifest["captureId"] == capture_id and manifest["templateSHA256"] == collector_sha
    assert manifest["nativeReadOnly"] is True and manifest["metadataComplete"] is True
    assert manifest["sourceCount"] == 213 and len(manifest["sourceCatalog"]) == 213
    assert manifest["sourceCatalogBeforeSHA256"] == manifest["sourceCatalogAfterSHA256"] == begin["sourceCatalogSHA256"]
    source_ids = [row["instanceId"] for row in manifest["sourceCatalog"]]
    assert len(set(source_ids)) == 213
    for row in manifest["sourceCatalog"]:
        assert row["rawSourceSHA256"] == row["rawEditorSHA256"] and type(row["sourceBytes"]) is int
        assert row["className"] in ("Script", "LocalScript", "ModuleScript")
    roots = manifest["roots"]
    assert len(roots) == 2 and roots == begin["roots"]
    for root, name, klass, top in zip(roots, ("MongoTVEntityAnimations", "RBX_ANIMSAVES"), ("Folder", "Model"), (117, 27)):
        header = root["root"]
        assert header["name"] == name and header["className"] == klass and header["childCount"] == top
        assert len(header["directChildIds"]) == top and len(set(header["directChildIds"])) == top
        assert root["nodeCount"] == root["descendantCount"] + 1
        assert sum(root["classHistogram"].values()) == root["descendantCount"]
        assert len(root["candidateIdentitySHA256"]) == 64
    records = manifest["records"]
    assert 144 <= len(records) <= 10000 and len(records) == begin["recordCount"]
    assert len({row["instanceId"] for row in records}) == len(records)
    for root in roots:
        name = root["root"]["name"]
        current = [row for row in records if row["rootName"] == name]
        assert len(current) == root["metadataRecordCount"]
        assert {row["instanceId"] for row in current if row["topChild"]} == set(root["root"]["directChildIds"])
    assert all(row.get("metadataIncomplete") is not True and "attributes" in row and "tags" in row
               and "publishedAssetId" in row and "animationIdAttribute" in row for row in records)
    zero_writes(manifest)
    return {"schema": "mongotv-animation-cache-preservation-verdict-v1", "capturePassed": True,
            "allActualVersionsRetained": True, "cacheRecordCount": len(records), "topChildrenRetained": 144,
            "deletionApproved": False, "fullNativeArchiveCertified": False, "referenceAbsenceCertified": False,
            "limits": manifest["limits"]}


def execute_capture(client, studio_id, collector, capture_id, save):
    """Actual Root flow, separately replayed by offline fake transport fixtures."""
    begin = native_read(client, studio_id, request_code(collector, "begin", capture_id), "begin", save)
    assert begin["schema"] == "mongotv-animation-cache-read-begin-v1" and begin["pass"] is True
    assert begin["captureId"] == capture_id and begin["templateSHA256"] == SHA(collector)
    assert begin["sourceCount"] == 213 and type(begin["manifestBytes"]) is int and 0 < begin["manifestBytes"] <= 10000000
    assert type(begin["pageCount"]) is int and begin["pageCount"] == math.ceil(begin["manifestBytes"] / 12000)
    zero_writes(begin)
    chunks = []
    for page in range(begin["pageCount"]):
        report = native_read(client, studio_id, request_code(collector, "page", capture_id, page), f"page-{page:04d}", save)
        assert report["schema"] == "mongotv-animation-cache-read-page-v1" and report["page"] == page
        assert report["captureId"] == capture_id and report["templateSHA256"] == SHA(collector)
        assert report["pageCount"] == begin["pageCount"] and report["manifestSHA256"] == begin["manifestSHA256"]
        zero_writes(report)
        raw = base64.b64decode(report["chunkBase64"], validate=True)
        expected_bytes = min(12000, begin["manifestBytes"] - page * 12000)
        assert len(raw) == report["chunkBytes"] == expected_bytes and SHA(raw) == report["chunkSHA256"]
        assert report["collectorStateWrites"] == page + 3
        save(f"page-{page:04d}-manifest-chunk.bin", raw)
        chunks.append(raw)
    payload = b"".join(chunks)
    save("cache-manifest-raw.json", payload)
    assert len(payload) == begin["manifestBytes"] and SHA(payload) == begin["manifestSHA256"]
    manifest = json.loads(payload)
    # A fully received, bound manifest has a known transport outcome. Finish
    # performs fresh guards and closes owned scratch even if local metadata
    # completeness validation will subsequently refuse the preservation claim.
    finish = native_read(client, studio_id, request_code(collector, "finish", capture_id), "finish", save)
    assert finish["schema"] == "mongotv-animation-cache-read-finish-v1" and finish["pass"] is True
    assert finish["captureId"] == capture_id and finish["manifestSHA256"] == SHA(payload)
    assert finish["sourceCatalogSHA256"] == begin["sourceCatalogSHA256"] and finish["sourceCount"] == 213
    for field in ("rootAndCacheMetadataUnchanged", "all213OriginalSourceEditorPropertiesUnchanged", "pointInTimeGuardsOnly"):
        assert finish[field] is True
    zero_writes(finish["cleanup"])
    assert finish["cleanup"]["closed"] is True and finish["cleanup"]["collectorStateWrites"] == begin["pageCount"] + 4
    try:
        verdict = validate_manifest(manifest, begin, capture_id, SHA(collector))
    except BaseException as error:
        raise CaptureFailure(str(error), "completed-metadata-refusal-owned-scratch-closed", False) from error
    verdict["manifestSHA256"] = SHA(payload)
    verdict["collectorStateWrites"] = finish["cleanup"]["collectorStateWrites"]
    save("capture-verdict.json", verdict)
    return verdict


def preflight():
    pins = json.loads((HERE / "frozen-pins-v1.json").read_bytes())
    for pin in pins["files"]:
        raw = (ROOT / pin["path"]).read_bytes()
        assert SHA(raw) == pin["sha256"] and len(raw) == pin["bytes"], "Frozen candidate drift"
    offline = json.loads((HERE / "offline-final-v1.json").read_bytes())
    assert offline["passed"] is True and offline["nativeCalls"] == 0 and offline["productionWrites"] == 0
    assert offline["replay"]["cases"] >= 55 and offline["driverPort"]["cases"] >= 15
    return (HERE / "collector.luau").read_bytes()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--studio-id")
    parser.add_argument("--run-directory", type=Path)
    parser.add_argument("--peer-review", type=Path)
    parser.add_argument("--peer-sha256")
    args = parser.parse_args()
    collector = preflight()
    if not args.apply:
        print(json.dumps({"prepared": True, "nativeCalls": 0, "collectorSHA256": SHA(collector), "deletionApproved": False}))
        return
    assert args.studio_id and args.run_directory and args.peer_review and args.peer_sha256
    peer_raw = args.peer_review.read_bytes()
    assert SHA(peer_raw) == args.peer_sha256
    peer = json.loads(peer_raw)
    assert peer["nativeExecuted"] is False and peer["deletionApproved"] is False and peer["preparationEligibleForNativeRead"] is True
    assert peer["reviewedCollectorSHA256"] == SHA(collector) and peer["reviewedDriverSHA256"] == SHA(Path(__file__).read_bytes())
    run = args.run_directory.resolve()
    assert run.is_relative_to(HERE) and not run.exists(), "New owned artifact run directory required"
    run.mkdir()

    def save(name, value):
        assert Path(name).name == name
        raw = value if isinstance(value, bytes) else (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
        with (run / name).open("xb") as stream:
            stream.write(raw)

    capture_id = str(uuid.uuid4())
    save("request-provenance.json", {"studioId": args.studio_id, "collectorSHA256": SHA(collector), "captureId": capture_id,
                                    "peerSHA256": SHA(peer_raw), "driverSHA256": SHA(Path(__file__).read_bytes()),
                                    "nativeInstanceSourcePropertyWritesRequested": 0, "noRetry": True, "noModeSwitch": True,
                                    "scratchNamespace": "__MongoTVAnimationCacheInventory20261010V1_" + capture_id})
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, require_edit_state
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        require_edit_state(client, args.studio_id)
        verdict = execute_capture(client, args.studio_id, collector, capture_id, save)
        print(json.dumps(verdict))
    except BaseException as error:
        save("failure-or-pending.json", {"capturePassed": False, "error": str(error),
                                       "nativeOutcome": getattr(error, "outcome", "completed-validation-refusal"),
                                       "scratchCleanupPending": getattr(error, "scratch_pending", True),
                                       "noFollowupNativeCalls": True, "noAutomaticAbandon": True,
                                       "localCloseIsNotNativeCancellation": True, "deletionApproved": False})
        raise
    finally:
        client.close()


if __name__ == "__main__":
    main()
