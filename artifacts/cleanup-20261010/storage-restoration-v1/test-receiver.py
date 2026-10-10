"""Exercise immutable receiver boundaries with explicitly synthetic messages."""
from pathlib import Path
import argparse
import ast
import copy
import hashlib
import http.client
import importlib.util
import json
import tempfile
import threading

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--receipt", type=Path, default=HERE / "receiver-fault-proof.json")
args = parser.parse_args()
target = args.receipt.resolve()
assert target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and target.parent.is_dir() and not target.exists()
source = (HERE / "receiver.py").read_bytes()
spec = importlib.util.spec_from_file_location("storage_restoration_receiver", HERE / "receiver.py")
port = importlib.util.module_from_spec(spec)
spec.loader.exec_module(port)
checks, results = 0, []

def check(condition, message):
    global checks
    assert condition, message
    checks += 1

def rejected(name, callback):
    try:
        callback()
    except (AssertionError, ValueError, KeyError, TypeError, FileNotFoundError):
        results.append({"kind": name, "accepted": False, "pass": True})
        return
    raise AssertionError("Unsafe message accepted: " + name)

def baseline():
    return {"schema": "storage-restoration-live-baseline-v1", "placeId": 131311258779917,
        "universeId": 10559217407, "mode": "Edit", "expectedLiveSources": 213,
        "expectedLiveRoots": 15, "expectedLiveDescendants": 18000,
        "expectedLedgerRootRefs": 73, "expectedLedgerScriptRefs": 222,
        "sourceWrites": 0, "propertyWrites": 0, "originalParentWrites": 0, "modeSwitches": 0,
        "sourcePins": [{"path": "Fixture.Script" + str(i), "class": "ModuleScript", "identity": "S" + str(i),
            "parentIdentity": "P" + str(i), "sourceSHA256": port.sha(str(i).encode()),
            "metadataSHA256": "b" * 64, "bytes": i} for i in range(213)]}

def baseline_completion(session):
    return {"schema": "storage-restoration-live-baseline-completion-v1", "pass": True,
        "baselineSHA256": port.sha(session.baseline_raw), "originalSourcesUnchanged": True,
        "liveSources": 213, "liveRoots": 15, "liveDescendants": 18000,
        "nativeObjectCreations": 0, "sourceWrites": 0, "propertyWrites": 0,
        "originalParentWrites": 0, "modeSwitches": 0, "watchers": 450, "watchersReleaseAttempted": 450}

def probe_completion(session):
    value = {"schema": port.SCHEMA, "pass": True, "normalizationApplied": False, "restorationCertified": False,
        "freshSourcePinsValidated": 213, "liveBaselineSHA256": port.sha(session.baseline_raw),
        "createdRoots": 46, "destroyedRoots": 46, "adoptedRoots": 46, "testOwnedRootsRemaining": 0,
        "testOwnedCFrameSetAttempts": 8, "testOwnedCFrameWrites": 8, "supplementPasses": 2,
        "reconstructedNodes": 14079, "reconstructedSources": 12, "referenceProperties": 10,
        "roundtripBytes": 2739764, "liveSources": 213, "liveRoots": 15,
        "archiveSHA256": port.NATIVE_SHA, "roundtripSHA256": port.NATIVE_SHA, "secondNativeSHA256": port.NATIVE_SHA,
        "sourceWrites": 0, "originalParentWrites": 0, "modeSwitches": 0}
    for key in ("readableDataPass", "nativeSerializedBytesExact", "secondSupplementedReopenPass",
                "originalSourcesUnchanged", "originalSourcePinsUnchanged", "originalNativeArchiveUnchanged",
                "leaseReleased", "internalReferencesPass"):
        value[key] = True
    return value

# Compile Python syntax without creating pycache; no external Studio imports/calls.
for name in ("receiver.py", "test-receiver.py", "test-copy-faults.py", "prepare-v4.py", "record-lune-boundary.py"):
    ast.parse((HERE / name).read_bytes(), filename=name)
    checks += 1
imports = {node.names[0].name for node in ast.walk(ast.parse(source)) if isinstance(node, ast.Import)}
check(not any("roblox" in name.lower() or "mcp" in name.lower() for name in imports), "Studio import in receiver")

with tempfile.TemporaryDirectory(prefix="receiver-owned-test-", dir=HERE) as name:
    owned_dir = Path(name).resolve()
    check(owned_dir.is_relative_to(HERE), "Temporary cleanup must stay in owned port directory")
    session = port.Session(owned_dir / "primary", 15, 18000)
    clone_number = 0
    def fork(original=session):
        nonlocal_placeholder = None  # Explicitly no shared mutation of receiver state.
        global clone_number
        clone_number += 1
        clone = copy.copy(original)
        clone.dest = owned_dir / ("claim-" + str(clone_number))
        clone.dest.mkdir()
        for file, key in (("probe-source.luau", "probeSource"), ("baseline-source.luau", "baselineSource"),
                          ("restore-supplement.json", "supplement")):
            clone.save(file, clone.inputs[key])
        return clone

    rejected("context-before-baseline", session.context)
    rejected("part-before-baseline", lambda: session.accept_part(0, session.inputs["native"][:port.PART_BYTES]))
    rejected("duplicate-json", lambda: port.strict_json(b'{"schema":1,"schema":2}'))
    rejected("nonfinite-json", lambda: port.strict_json(b'{"x":NaN}'))
    rejected("existing-execution-directory", lambda: port.Session(session.dest, 15, 18000))
    malformed = []
    for key, wrong in (("placeId", 1), ("mode", "Play"), ("expectedLiveSources", 212),
                       ("expectedLiveRoots", 16), ("expectedLiveDescendants", 18001),
                       ("expectedLedgerRootRefs", 72), ("expectedLedgerScriptRefs", 221),
                       ("expectedLiveSources", 213.0), ("sourceWrites", False), ("propertyWrites", 1)):
        value = baseline(); value[key] = wrong
        malformed.append(("baseline-" + key + "-" + str(wrong), value))
    for kind in ("source-count", "duplicate-path", "duplicate-identity", "wrong-class", "bad-source-hash", "bad-parent", "bool-bytes", "nonstring-hash"):
        value = baseline()
        if kind == "source-count": value["sourcePins"].pop()
        elif kind == "duplicate-path": value["sourcePins"][1]["path"] = value["sourcePins"][0]["path"]
        elif kind == "duplicate-identity": value["sourcePins"][1]["identity"] = value["sourcePins"][0]["identity"]
        elif kind == "wrong-class": value["sourcePins"][0]["class"] = "Folder"
        elif kind == "bad-source-hash": value["sourcePins"][0]["sourceSHA256"] = "not-sha"
        elif kind == "bad-parent": value["sourcePins"][0]["parentIdentity"] = ""
        elif kind == "bool-bytes": value["sourcePins"][0]["bytes"] = False
        elif kind == "nonstring-hash": value["sourcePins"][0]["metadataSHA256"] = None
        malformed.append(("baseline-" + kind, value))
    for kind, value in malformed:
        rejected(kind, lambda v=value: session.accept_baseline(port.encode(v)))
    check(session.baseline is None, "Rejected baseline mutated receiver state")
    base_raw = port.encode(baseline())
    session.accept_baseline(base_raw)
    session.accept_baseline(base_raw)
    rejected("context-before-native-final-baseline", session.context)
    conflict = baseline(); conflict["sourcePins"][0]["bytes"] = 42
    rejected("immutable-baseline-conflict", lambda: session.accept_baseline(port.encode(conflict)))
    for key, wrong in (("pass", False), ("originalSourcesUnchanged", False), ("baselineSHA256", "0" * 64),
                       ("liveSources", 212), ("liveRoots", 16), ("liveDescendants", 18001),
                       ("nativeObjectCreations", True), ("watchersReleaseAttempted", 449), ("watchers", True)):
        clone = fork()
        value = baseline_completion(clone); value[key] = wrong
        rejected("baseline-completion-" + key, lambda c=clone,v=value: c.accept_baseline_completion(port.encode(v)))
        rejected("context-locked-after-baseline-completion-" + key, clone.context)
    clone = fork()
    failed = baseline_completion(clone); failed["pass"] = False
    rejected("baseline-final-failure", lambda: clone.accept_baseline_completion(port.encode(failed)))
    rejected("failed-baseline-retry-needs-new-dest", lambda: clone.accept_baseline_completion(port.encode(baseline_completion(clone))))
    session.accept_baseline_completion(port.encode(baseline_completion(session)))
    context = session.context()
    check(context["schema"] == port.SCHEMA and len(context["sourcePins"]) == 213 and len(context["roots"]) == 23, "Context schema/count mismatch")
    rejected("wrong-part-index", lambda: session.accept_part(4, b"wrong"))
    rejected("bool-part-index", lambda: session.accept_part(False, b"wrong"))
    wrong_part = bytearray(session.inputs["native"][:port.PART_BYTES]); wrong_part[50] ^= 1
    rejected("changed-native-byte", lambda: session.accept_part(0, bytes(wrong_part)))
    transfer = {"parts": 4, "bytes": 2739764, "sha256": port.NATIVE_SHA}
    rejected("missing-native-parts", lambda: session.finalize(port.encode(transfer)))
    for i in range(4):
        piece = session.inputs["native"][i * port.PART_BYTES:(i + 1) * port.PART_BYTES]
        session.accept_part(i, piece)
        session.accept_part(i, piece)
    for key, wrong in (("parts", 3), ("parts", 4.0), ("bytes", 2739763), ("sha256", "0" * 64)):
        value = dict(transfer); value[key] = wrong
        rejected("finalize-" + key + "-" + str(wrong), lambda v=value: session.finalize(port.encode(v)))
    extra = dict(transfer); extra["unexpected"] = 1
    rejected("finalize-extra-key", lambda: session.finalize(port.encode(extra)))
    session.finalize(port.encode(transfer))
    pre = port.strict_json((session.dest / "transfer-receipt.json").read_bytes())
    check(pre["passed"] is False and pre["restorationCertified"] is False and session.probe_completion is None,
        "Transfer receipt was incorrectly treated as final native completion")
    check((session.dest / "roundtrip.rbxm").read_bytes() == session.inputs["native"], "Part reconstruction not exact")
    for key, wrong in (("createdRoots", 45), ("destroyedRoots", 45), ("testOwnedRootsRemaining", 1),
                       ("adoptedRoots", 45), ("testOwnedCFrameSetAttempts", 7), ("testOwnedCFrameWrites", 7),
                       ("supplementPasses", 1), ("reconstructedNodes", 14078), ("reconstructedSources", 11),
                       ("referenceProperties", 9), ("freshSourcePinsValidated", 212), ("roundtripBytes", 2739763),
                       ("liveSources", 212), ("liveRoots", 16), ("roundtripSHA256", "0" * 64),
                       ("secondNativeSHA256", "0" * 64), ("liveBaselineSHA256", "0" * 64),
                       ("normalizationApplied", True), ("restorationCertified", True), ("sourceWrites", True),
                       ("createdRoots", 46.0)):
        clone = fork()
        value = probe_completion(clone); value[key] = wrong
        rejected("probe-completion-" + key + "-" + str(wrong), lambda c=clone,v=value: c.accept_probe_completion(port.encode(v)))
        check(not (clone.dest / "port-verdict.json").exists() and clone.probe_completion is None, "Invalid claim created verdict")
    for key in ("readableDataPass", "nativeSerializedBytesExact", "secondSupplementedReopenPass",
                "originalSourcesUnchanged", "originalSourcePinsUnchanged", "originalNativeArchiveUnchanged", "leaseReleased", "internalReferencesPass"):
        clone = fork()
        value = probe_completion(clone); value[key] = False
        rejected("probe-final-guard-" + key, lambda c=clone,v=value: c.accept_probe_completion(port.encode(v)))
        check(not (clone.dest / "port-verdict.json").exists(), "Failed final guard produced verdict")
    clone = fork()
    clone.finalized = None
    rejected("completion-before-transfer-finalized", lambda: clone.accept_probe_completion(port.encode(probe_completion(clone))))
    clone = fork()
    pending = {"schema": port.SCHEMA, "pass": False, "error": "synthetic setter failure"}
    clone.accept_probe_completion(port.encode(pending))
    check(port.strict_json((clone.dest / "port-verdict.json").read_bytes())["recipePassed"] is False, "Failure marked passed")
    session.accept_probe_completion(port.encode(probe_completion(session)))
    verdict = port.strict_json((session.dest / "port-verdict.json").read_bytes())
    check(verdict["recipePassed"] is True and verdict["restorationCertified"] is False, "Narrow synthetic verdict was broadened")
    results.append({"kind": "synthetic-exact-four-part-finalization-and-completion", "accepted": True, "pass": True})
    clone = fork()
    (clone.dest / "probe-source.luau").write_bytes(b"changed fixture-only execution source")
    rejected("immutable-execution-source-changed", clone.guard)
    # Test actual HTTP status/routing and request bounds, on an ephemeral localhost port.
    clone = fork()
    clone.baseline_completion = None
    server = port.http.server.HTTPServer(("127.0.0.1", 0), port.make_handler(clone))
    thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.02})
    thread.start()
    try:
        connection = http.client.HTTPConnection("127.0.0.1", server.server_address[1], timeout=10)
        for method, path, body, expected in (("GET", "/baseline-context", None, 200), ("GET", "/context", None, 409),
                                           ("GET", "/native/0", None, 409), ("GET", "/unknown", None, 409),
                                           ("POST", "/baseline-completion", b"{}", 409), ("POST", "/unknown", b"{}", 409)):
            connection.request(method, path, body)
            response = connection.getresponse(); response.read()
            check(response.status == expected, "Unexpected HTTP result: " + path)
        connection.close()
        results.append({"kind": "actual-localhost-http-routing-locks", "accepted": False, "pass": True})
    finally:
        server.shutdown(); thread.join(timeout=5); server.server_close()
        check(not thread.is_alive(), "HTTP test server leaked")
check((HERE / "receiver.py").read_bytes() == source, "Receiver source changed during tests")
receipt = {"schema": "storage-restoration-receiver-fault-proof-v1", "pass": True, "nativeCalls": 0,
    "restorationCertified": False, "normalizationApplied": False, "receiverSHA256": port.sha(source),
    "driverSHA256": port.sha(Path(__file__).read_bytes()), "checks": checks, "cases": len(results), "results": results,
    "scope": "Actual receiver/schema/HTTP tested against pinned historical binary/facts and synthetic all213 pins/completion claims. Counts 15/18000 are fixture-only. This never calls Studio, does not record synthetic claims as native receipts, and does not prove native setter/recovery/gameplay."}
with target.open("xb") as stream:
    stream.write(port.encode(receipt))
print(json.dumps({"pass": True, "cases": len(results), "checks": checks, "nativeCalls": 0}))
