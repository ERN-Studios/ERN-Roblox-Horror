"""ROOT ONLY: execute one frozen controlled-absence operation; never retry/stop Play.

Default is a local validation. --apply requires exact peer-review pin and a fresh
owned receipt directory. Unknown transport creates a receipt and makes no further
native calls. Closing the local transport is not native cancellation.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda b: hashlib.sha256(b).hexdigest()


def validate(report):
    assert report["schema"] == "retired-authoring-controlled-absence-v1" and report["stage"] == "mcp-completion"
    assert report["passed"] is True
    for field in ("originalNativeArchiveUnchanged", "currentSelectedNativeUnchanged", "currentSelectedFactsUnchanged",
                  "all213SourcesUnchanged", "scopedOriginalRecoveryPassed", "finalOriginalGuardPassed", "postCleanupOriginalGuardPassed",
                  "ownedLeaseReleased", "ownedCurrentLedgerReleased", "currentPurposeLedgerOnly", "originalHeldMetadataIsHistorical"):
        assert report[field] is True, field
    for field in ("deletionApproved", "referenceAbsenceCertified", "permanentRemoval", "historicalHeldOriginalsVerified"):
        assert report[field] is False, field
    expected = {"currentSourcesPinned": 213, "originalSourceWrites": 0, "foreignWrites": 0, "modeSwitches": 0,
                "parentWrites": 10, "probeCreated": 2, "probeDestroyed": 2, "probeRemaining": 0,
                "probeSourceAttempts": 2, "probeSourceReadbacks": 2, "connectionsRetained": 0}
    for field, count in expected.items():
        assert type(report[field]) is int and report[field] == count, field
    assert report["cleanupErrors"] == [] and report["pendingOriginals"] == []
    transaction = report["transaction"]
    assert transaction["passed"] is True and not transaction["rollbackErrors"] and not transaction["setterErrors"] and not transaction["pending"]
    for field in ("detachAttempts", "restoreAttempts", "detachReadbacks", "restoreReadbacks"):
        assert type(transaction[field]) is int and transaction[field] == 5, field
    phases = report["selectorPhases"]
    assert [p["phase"] for p in phases] == ["before", "absent", "restored"]
    for phase in phases:
        assert phase["actualFreshFactories"] is True and phase["manifestEqual"] is True and phase["ready"] is True
        assert phase["assetSelectors"] == {"bake": ["LobbyReimaginedBlenderSource20261001R4"],
                                           "renderer": ["Level1BlenderKitV2", "Level1ElevatorInsetKit"]}
        cases = phase["failureCases"]
        assert len(cases) == 6 and all(c["controlledBoundary"] is True for c in cases)
        names = ["LobbyReimaginedBlenderSource20261001R4", "Level1BlenderKitV2", "Level1ElevatorInsetKit"]
        assert [c["missing"] for c in cases[:3]] == names and [c["incomplete"] for c in cases[3:]] == names
    return {"schema": "retired-authoring-controlled-absence-verdict-v1", "trialPassed": True,
            "deletionApproved": False, "referenceAbsenceCertified": False,
            "limits": "Exact same-original trial and current asset selectors only; unreadable reference boundary and permanent deletion remain pending."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--studio-id")
    parser.add_argument("--run-directory", type=Path)
    parser.add_argument("--peer-review", type=Path)
    parser.add_argument("--peer-sha256")
    args = parser.parse_args()
    preparation = json.loads((HERE / "preparation-v1.json").read_bytes())
    source = (HERE / "trial-source.luau").read_bytes()
    assert SHA(source) == preparation["assembledSource"]["sha256"] and len(source) == preparation["assembledSource"]["bytes"]
    offline = json.loads((HERE / "offline-faults-v1.json").read_bytes())
    assert offline["passed"] is True
    for pin in offline["inputs"]:
        assert SHA((ROOT / pin["path"]).read_bytes()) == pin["sha256"], "Offline candidate drift"
    if not args.apply:
        print(json.dumps({"prepared": True, "nativeCalls": 0, "sourceSHA256": SHA(source), "deletionApproved": False}))
        return
    assert args.studio_id and args.run_directory and args.peer_review and args.peer_sha256
    peer_raw = args.peer_review.read_bytes()
    assert SHA(peer_raw) == args.peer_sha256
    peer = json.loads(peer_raw)
    assert peer["preparationEligibleForNativeTrial"] is True and peer["nativeExecuted"] is False and peer["deletionApproved"] is False
    assert peer["reviewedSourceSHA256"] == SHA(source), "Peer reviewed a different executable"
    run = args.run_directory.resolve()
    assert run.is_relative_to(HERE) and not run.exists(), "New owned run directory required"
    run.mkdir()

    def save(name, value):
        raw = value if isinstance(value, bytes) else (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
        with (run / name).open("xb") as stream:
            stream.write(raw)
        return SHA(raw)

    save("request-provenance.json", {"studioId": args.studio_id, "executedSourceSHA256": SHA(source),
                                    "peerReviewSHA256": SHA(peer_raw), "samePlace": 131311258779917,
                                    "sameUniverse": 10559217407, "noRetry": True, "noModeSwitch": True})
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, require_edit_state
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        require_edit_state(client, args.studio_id)
        started = time.monotonic()
        try:
            response = client._request("tools/call", {"name": "execute_luau", "arguments": {
                "studio_id": args.studio_id, "datamodel_type": "Edit", "code": source.decode("utf-8")}}, timeout=600)
        except BaseException as error:
            save("unknown-transport.json", {"nativeOutcome": "unknown; no retry or follow-up native calls", "error": str(error),
                                             "executedSourceSHA256": SHA(source), "localCloseIsNotCancellation": True})
            raise
        save("root-api.json", response)
        result = response.get("result")
        if type(result) is not dict or type(result.get("content")) is not list:
            save("unknown-envelope.json", {"nativeOutcome": "unknown; no follow-up native calls", "reason": "Missing result/content list"})
            raise AssertionError("Unknown native completion envelope")
        text = "\n".join(c.get("text", "") for c in result["content"] if c.get("type") == "text")
        raw = text.encode("utf-8")
        save("root-completion-raw.txt", raw)
        assert not result.get("isError"), "Completed native tool error; preserved, no retry"
        assert len(raw) <= 50000, "Bounded completion exceeded; preserved, no retry"
        proof = json.loads(raw)
        save("root-completion.json", proof)
        save("root-provenance.json", {"actualNativeResponse": True, "executedSourceSHA256": SHA(source),
                                       "actualCompletionRawSHA256": SHA(raw), "rootClientWallSeconds": round(time.monotonic() - started, 3),
                                       "noRetry": True, "limits": "Elapsed tool duration is not a performance improvement."})
        verdict = validate(proof)
        save("port-verdict.json", verdict)
        print(json.dumps(verdict))
    finally:
        client.close()


if __name__ == "__main__":
    main()
