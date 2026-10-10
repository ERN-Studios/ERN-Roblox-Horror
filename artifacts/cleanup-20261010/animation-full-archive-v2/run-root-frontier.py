"""ROOT ONLY: one frozen readonly reference-frontier request; never retry.

No serialization/deserialization, upload, Instance creation or original write.
Default preflight does not load MCP. --apply needs exact independent review.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INVENTORY = HERE.with_name("animation-cache-inventory-v1")
SHA = lambda b: hashlib.sha256(b).hexdigest()
HELPER_SHA = "55b57e6a6224c793138eaeffcb25e206c5d3526ff9e541f7f0bb111257e768e8"


def preflight():
    pins = json.loads((HERE / "frontier-frozen-pins-v1.json").read_bytes())
    for pin in pins["files"]:
        raw = (ROOT / pin["path"]).read_bytes()
        assert SHA(raw) == pin["sha256"] and len(raw) == pin["bytes"], "Frozen frontier drift"
    proof = json.loads((HERE / "frontier-preparation.json").read_bytes())
    source = (HERE / "frontier-source.luau").read_bytes()
    assert proof["preparedCode"] == {"bytes": len(source), "sha256": SHA(source)}
    offline = json.loads((HERE / "frontier-offline-attempt-v1.json").read_bytes())
    assert offline["passed"] is True and offline["nativeCalls"] == 0 and offline["replay"]["cases"] == 11
    helper = INVENTORY / "run-root-inventory.py"
    assert SHA(helper.read_bytes()) == HELPER_SHA
    spec = importlib.util.spec_from_file_location("immutable_readonly_inventory_driver", helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return source, module


def validate(report):
    assert report["schema"] == "mongotv-animation-archive-reference-frontier-v1" and report["passed"] is True
    assert report["sourceCount"] == 213 and report["slotCount"] == 28 and report["cacheRecords"] == 191
    assert report["inventoryManifestSHA256"] == "4caa106ecfcf965013c4ac6759c61c3fa752ff855f51614b9392ba8e0cbc1d94"
    assert report["sourceCatalogSHA256"] == "b30a806da598ab234a0ca15066e84aea8c030a48a7ab44bb9b3583f86b0092b4"
    for field in ("originalSourceEditorPropertiesUnchanged", "originalRootCacheMetadataUnchanged", "finalOriginalGuardPassed"):
        assert report[field] is True
    for field in ("nativeInstanceWrites", "nativeSourceWrites", "nativePropertyWrites", "collectorStateWrites", "modeSwitches"):
        assert type(report[field]) is int and report[field] == 0
    for field in ("deletionApproved", "fullNativeArchiveCertified", "referenceAbsenceCertified"):
        assert report[field] is False
    assert {row["className"] for row in report["schemas"]} == {"Animation", "AnimationRigData", "Folder", "Keyframe", "KeyframeSequence", "Model", "ObjectValue", "Pose"}
    slots = report["slots"]
    assert len(slots) == 28 and len({(row["holder"]["instanceId"], row["name"]) for row in slots}) == 28
    assert sum(row["holder"]["className"] == "ObjectValue" and row["name"] == "Value" for row in slots) == 27
    assert sum(row["holder"]["instanceId"] == "1_41652" and row["name"] == "PrimaryPart" for row in slots) == 1
    for row in slots:
        assert row["descriptor"]["scriptType"] == "Instance" and type(row["readable"]) is bool
        if row["readable"]:
            assert row["value"]["kind"] in ("nil", "Instance")
        else:
            assert "error" in row and "value" not in row
    return {"frontierReadPassed": True, "actualSlotsRetained": 28, "unreadableSlots": sum(not row["readable"] for row in slots),
            "deletionApproved": False, "fullNativeArchiveCertified": False, "referenceAbsenceCertified": False,
            "limits": report["limits"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--studio-id")
    parser.add_argument("--run-directory", type=Path)
    parser.add_argument("--peer-review", type=Path)
    parser.add_argument("--peer-sha256")
    args = parser.parse_args()
    source, module = preflight()
    if not args.apply:
        print(json.dumps({"prepared": True, "nativeCalls": 0, "sourceSHA256": SHA(source), "deletionApproved": False}))
        return
    assert args.studio_id and args.run_directory and args.peer_review and args.peer_sha256
    peer_raw = args.peer_review.read_bytes()
    assert SHA(peer_raw) == args.peer_sha256
    peer = json.loads(peer_raw)
    assert peer["nativeExecuted"] is False and peer["preparationEligibleForNativeRead"] is True and peer["deletionApproved"] is False
    assert peer["reviewedSourceSHA256"] == SHA(source) and peer["reviewedDriverSHA256"] == SHA(Path(__file__).read_bytes())
    run = args.run_directory.resolve()
    assert run.is_relative_to(HERE) and not run.exists(), "Fresh owned output directory required"
    run.mkdir()

    def save(name, value):
        assert Path(name).name == name
        raw = value if isinstance(value, bytes) else (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
        with (run / name).open("xb") as stream:
            stream.write(raw)

    save("root-provenance.json", {"studioId": args.studio_id, "sourceSHA256": SHA(source), "driverSHA256": SHA(Path(__file__).read_bytes()),
                                  "peerSHA256": SHA(peer_raw), "oneReadonlyRequest": True, "noRetry": True, "noModeSwitch": True,
                                  "nativeInstanceSourcePropertyWritesRequested": 0, "scratchWritesRequested": 0})
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, require_edit_state
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        require_edit_state(client, args.studio_id)
        report = module.native_read(client, args.studio_id, source, "frontier", save)
        verdict = validate(report)
        save("frontier-verdict.json", verdict)
        print(json.dumps(verdict))
    except BaseException as error:
        save("failure-or-pending.json", {"frontierReadPassed": False, "error": str(error),
                                       "nativeOutcome": getattr(error, "outcome", "known-completed-validation-refusal"),
                                       "noFollowupNativeCalls": True, "scratchStateCreated": False,
                                       "localCloseIsNotNativeCancellation": True, "deletionApproved": False})
        raise
    finally:
        client.close()


if __name__ == "__main__":
    main()
