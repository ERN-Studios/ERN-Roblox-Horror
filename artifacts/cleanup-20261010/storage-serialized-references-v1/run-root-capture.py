"""Root only: own receiver, one native readonly capture, known completion, raw decode.

Default only validates offline evidence. No native/receiver startup without
--apply and pinned peer approval. Unknown completion retains the owned receiver
until Root writes its private resolution file; no retry or follow-up native call.
Private token/request/API bytes are never written to the public artifact tree.
"""
from pathlib import Path
import argparse
import hashlib
import json
import secrets
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def save(path, value):
    raw = value if type(value) is bytes else (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    with path.open("xb") as stream: stream.write(raw)
    return SHA(raw)


def execute(client, server, session, source, studio_id, run, private, token):
    known, requested = False, False
    started = time.monotonic()
    try:
        server.start()
        requested = True
        try:
            response = client._request("tools/call", {"name": "execute_luau", "arguments": {
                "studio_id": studio_id, "datamodel_type": "Edit", "code": source.decode()}}, timeout=600)
        except BaseException as error:
            save(run / "unknown-transport.json", {"outcome": "unknown; no retry/follow-up native calls", "errorType": type(error).__name__,
                 "receiverRetained": True, "localCloseIsNotCancellation": True, "executedSourceSHA256": SHA(source)})
            raise
        api_raw = (json.dumps(response, ensure_ascii=False, indent=2) + "\n").encode()
        api_sha = save(private / "root-api.private.json", api_raw)
        result = response.get("result") if type(response) is dict else None
        if type(result) is not dict or type(result.get("content")) is not list:
            save(run / "unknown-envelope.json", {"outcome": "unknown; no follow-up native calls", "receiverRetained": True,
                 "actualAPIResponseSHA256": api_sha})
            raise AssertionError("Unknown native completion envelope")
        known = True  # Completed tool isError/malformed text still ended the native request.
        text = "\n".join(block.get("text", "") for block in result["content"] if type(block) is dict and block.get("type") == "text")
        raw = text.encode()
        save(private / "root-completion.private.txt", raw)
        save(run / "root-provenance.json", {"actualNativeResponse": True, "knownCompleted": True,
             "executedSourceSHA256": SHA(source), "actualAPIResponseSHA256": api_sha, "nativeCompletionSHA256": SHA(raw),
             "wallSeconds": round(time.monotonic() - started, 3), "noRetry": True, "tokenOnlyInPrivateRequest": True,
             "limits": "Tool duration is not performance improvement. Completed native claims retained separately from raw Ref validation."})
        assert type(result.get("isError", False)) is bool and not result.get("isError", False), "Completed tool error; private raw retained"
        assert 0 < len(raw) <= 100000 and token.encode() not in raw, "Unsafe/bounded completion refused; private raw retained"
        session.accept_completion(raw)
        save(run / "root-completion.json", raw)
        assert session.completion["passed"] is True, "Known native capture failure preserved"
        from raw_binary_refs import inspect
        refs_path = session.dest / "references.rbxm"; refs_raw = refs_path.read_bytes()
        proof = {"passed": False, "rawSHA256": SHA(refs_raw), "deletionApproved": False}
        try:
            proof.update(inspect(refs_raw)); proof["passed"] = True
        except BaseException as error:
            proof["error"] = str(error); raise
        finally:
            assert refs_path.read_bytes() == refs_raw
            save(run / "raw-reference-verdict.json", proof)
        return {"capturePassed": True, "rawProtectedFieldsPassed": True, "deletionApproved": False,
                "referenceAbsenceCertified": False}
    finally:
        try:
            client.close()  # Local close never claims cancellation.
        finally:
          if known or not requested:
            server.stop_after_known_completion()
            save(run / "receiver-stop.json", {"knownNativeCompletion": known, "receiverStopped": True, "threadsRetained": 0})
          else:
            # Root resolves the unknown request outside this driver. Keeping HTTP
            # available lets its existing readonly transfer/cleanup finish.
            save(run / "receiver-retained.json", {"reason": "Native outcome unknown", "noNativeFollowup": True,
                 "releaseRequiresRootKnownEndedConfirmation": True})
            print("Native outcome unknown; owned receiver retained. Root must resolve before private release.", flush=True)
            release = private / "root-known-ended-release.json"
            while not release.exists(): time.sleep(0.2)
            confirmation = json.loads(release.read_bytes())
            assert confirmation == {"rootConfirmedNativeRequestEnded": True, "executedSourceSHA256": SHA(source)} and confirmation["rootConfirmedNativeRequestEnded"] is True, "Exact Root release evidence required"
            server.stop_after_known_completion()
            save(run / "receiver-stop-after-root-resolution.json", {"rootConfirmedKnownEnded": True, "receiverStopped": True,
                 "releaseSHA256": SHA(release.read_bytes()), "noNativeFollowupByDriver": True})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--studio-id")
    parser.add_argument("--run-directory", type=Path)
    parser.add_argument("--private-directory", type=Path)
    parser.add_argument("--peer-review", type=Path)
    parser.add_argument("--peer-sha256")
    args = parser.parse_args()
    pins = json.loads((HERE / "frozen-pins-v1.json").read_bytes())
    for pin in pins["pins"]:
        raw = (ROOT / pin["path"]).read_bytes()
        assert len(raw) == pin["bytes"] and SHA(raw) == pin["sha256"], "Frozen input drift"
    for name in ("offline-tests-v3.json", "actual-native-archive-parser-observation-v3.json", "native-suffix-attempt-v2.json"):
        assert json.loads((HERE / name).read_bytes())["passed"] is True, "Required offline evidence failed"
    template = (HERE / "capture-source-template.luau").read_bytes()
    assert template.count(b"__ROOT_PRIVATE_TOKEN__") == 1
    if not args.apply:
        print(json.dumps({"prepared": True, "nativeCalls": 0, "receiverStarted": False,
                          "templateSHA256": SHA(template), "deletionApproved": False})); return
    assert args.studio_id and args.run_directory and args.private_directory and args.peer_review and args.peer_sha256
    peer_raw = args.peer_review.read_bytes(); assert SHA(peer_raw) == args.peer_sha256
    peer = json.loads(peer_raw)
    assert peer["capturePreparationEligible"] is True and peer["nativeExecuted"] is False and peer["deletionApproved"] is False
    assert peer["reviewedSourceTemplateSHA256"] == SHA(template)
    assert peer["reviewedDriverSHA256"] == SHA(Path(__file__).read_bytes())
    assert peer["reviewedFrozenPinsSHA256"] == SHA((HERE / "frozen-pins-v1.json").read_bytes())
    config = json.loads((HERE / "capture-config.json").read_bytes())
    assert args.studio_id == config["studioId"]
    run, private = args.run_directory.resolve(), args.private_directory.resolve()
    assert run.is_relative_to(HERE) and not run.exists() and run.parent.is_dir()
    assert not private.is_relative_to(ROOT / "artifacts") and not private.exists() and private.parent.is_dir(), "New private directory outside public artifacts required"
    run.mkdir(); private.mkdir()
    token = secrets.token_hex(32); source = template.replace(b"__ROOT_PRIVATE_TOKEN__", token.encode())
    save(private / "request.private.luau", source)
    save(run / "request-provenance.json", {"studioId": args.studio_id, "templateSHA256": SHA(template),
         "executedSourceSHA256": SHA(source), "peerReviewSHA256": SHA(peer_raw), "privateTokenNotExported": True,
         "noRetry": True, "originalWritesRequested": 0})
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, require_edit_state
    from receiver import Session, OwnedServer
    client = StudioMcpClient(find_mcp_batch())
    # Preflight occurs before any receiver/native capture startup.
    try:
        client.initialize(); require_edit_state(client, args.studio_id)
    except BaseException:
        client.close(); raise
    try:
        session = Session(private / "raw-capture", config["captureId"], token)
        server = OwnedServer(session)
    except BaseException:
        client.close(); raise
    print(json.dumps(execute(client, server, session, source, args.studio_id, run, private, token)), flush=True)


if __name__ == "__main__": main()
