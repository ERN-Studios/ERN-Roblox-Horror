"""Actual raw decoder/receiver/Root execution lifecycle tests; never starts HTTP.

The native engine archives stay unchanged. Fake API/server boundaries execute
the actual wrapper; local fixture setters are never native Instance operations.
"""
from pathlib import Path
import argparse
import copy
import importlib.util
import json
import struct
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), HERE / (name + ".py"))
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def string(raw): return struct.pack("<I", len(raw)) + raw
def ref_array(values):
    prior, encoded = 0, []
    for value in values:
        delta = value - prior; prior = value
        encoded.append(((delta << 1) ^ (delta >> 31)).to_bytes(4, "big"))
    return b"".join(bytes(v[lane] for v in encoded) for lane in range(4))
def chunk(tag, payload): return tag + struct.pack("<III", 0, len(payload), 0) + payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args(); target = args.receipt.resolve()
    assert target.parent.is_dir() and target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and not target.exists()
    refs, receiver, driver = load("raw_binary_refs"), load("receiver"), load("run-root-capture")
    pins = {name: (HERE / name).read_bytes() for name in ("raw_binary_refs.py", "receiver.py", "run-root-capture.py", "native-capture.luau", "capture-config.json")}
    oldpath = ROOT / "artifacts/cleanup-serverstorage-20261009/retired-authoring-archive-v3/native.rbxm"
    old = oldpath.read_bytes(); olddom = refs.parse(old)
    assert refs.sha(old) == "e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7"
    checks, cases = 0, []
    receipt = {"schema": "retired-authoring-reference-capture-offline-v1", "passed": False, "nativeCalls": 0,
               "receiverHTTPStarted": False, "inputs": [{"path": (HERE / n).relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": refs.sha(raw)} for n, raw in pins.items()],
               "actualOldArchiveSHA256": refs.sha(old), "limits": "Actual wrapper/decoder/receiver with fake API/server. Raw engine archive prefix plus synthetic appended Ref columns; native capture/listener cleanup/full reference/deletion ports remain separate."}
    def check(value, why):
        nonlocal checks
        checks += 1; assert value, why
    def refused(name, callback):
        try: callback()
        except (AssertionError, ValueError, KeyError, TypeError, IndexError, UnicodeDecodeError, FileExistsError):
            cases.append({"case": name, "refused": True}); return
        raise AssertionError("Unsafe case accepted: " + name)
    classes = len(olddom["classes"]); total = len(olddom["nodes"])
    starter_kind = max(olddom["classes"]) + 1; weld_kind = starter_kind + 1
    starter_ref = max(olddom["nodes"]) + 100
    weld_refs = list(range(starter_ref + 1, starter_ref + 110))
    oldchunks = [old[c["offset"]:c["offset"] + c["storedBytes"]] for c in olddom["chunks"] if c["tagHex"] not in (b"PRNT".hex(), b"END\0".hex())]
    target_ref = next(ref for ref, node in olddom["nodes"].items() if node["name"] == refs.NAMES[0] and olddom["parents"][ref] == -1)
    def fixture(change=None):
        pieces = list(oldchunks)
        pieces += [chunk(b"INST", struct.pack("<I", starter_kind) + string(b"StarterPlayer") + b"\1" + struct.pack("<I", 1) + ref_array([starter_ref]) + b"\1"),
                   chunk(b"INST", struct.pack("<I", weld_kind) + string(b"WeldConstraint") + b"\0" + struct.pack("<I", 109) + ref_array(weld_refs))]
        props = [(starter_kind, "Name", 1, string(b"StarterPlayer")), (weld_kind, "Name", 1, b"".join(string(b"WeldConstraint") for _ in weld_refs)),
                 (starter_kind, "PlaceAvatarRules", 0x13, ref_array([-1])),
                 (weld_kind, "Part0Internal", 0x13, ref_array([-1] * 109)),
                 (weld_kind, "Part1Internal", 0x13, ref_array([-1] * 109)),
                 (weld_kind, "FutureOpaqueField", 0xFA, b"opaque-future-value-preserved")]
        if change: change(props)
        for kind, name, code, payload in props: pieces.append(chunk(b"PROP", struct.pack("<I", kind) + string(name.encode()) + bytes([code]) + payload))
        subjects = list(olddom["nodes"]) + [starter_ref] + weld_refs
        parents = [olddom["parents"][ref] for ref in olddom["nodes"]] + [-1] + [starter_ref] * 2 + [-1] * 107
        pieces += [chunk(b"PRNT", b"\0" + struct.pack("<I", len(subjects)) + ref_array(subjects) + ref_array(parents)), chunk(b"END\0", b"</roblox>")]
        return old[:16] + struct.pack("<II", classes + 2, total + 110) + b"\0" * 8 + b"".join(pieces)
    try:
      raw = fixture(); proof = refs.inspect(raw)
      check(proof["rawProtectedFieldsPassed"] and proof["targetNodes"] == 1617 and proof["weldConstraints"] == 109, "Complete raw fixture closure")
      check({row["referent"] for row in proof["targetIdentities"]} == set(olddom["nodes"]) and len(proof["targetIdentities"]) == 1617, "Every original raw target identity maps exactly once")
      check(set().union(*(set(row["referents"]) for row in proof["targetForests"])) == set(olddom["nodes"]) and sum(row["nodes"] for row in proof["targetForests"]) == 1617, "All five raw target memberships are explicit and complete")
      check({(row["ownerReferent"], row["property"]) for row in proof["protectedWitnessReferences"]} == ({(ref, name) for ref in weld_refs for name in ("Part0Internal", "Part1Internal")} | {(starter_ref, "PlaceAvatarRules")}) and len(proof["protectedWitnessReferences"]) == 219, "Every required owner/field maps exactly once")
      check(any(row["name"] == "FutureOpaqueField" and row["typeCode"] == 0xFA for row in proof["opaquePropertyColumns"]), "Unknown property preserved")
      check(not proof["deletionApproved"] and not proof["referenceAbsenceCertified"], "No expanded certificate")
      cases.append({"case": "raw-complete-columns-unknown-preserved", "passed": True})
      def resolved_external(p):
        at = next(i for i, r in enumerate(p) if r[1] == "PlaceAvatarRules")
        p[at] = (starter_kind, "PlaceAvatarRules", 0x13, ref_array([weld_refs[0]]))
      resolved = refs.inspect(fixture(resolved_external))
      slot = next(row for row in resolved["protectedWitnessReferences"] if row["property"] == "PlaceAvatarRules")
      check(slot["targetReferent"] == weld_refs[0] and slot["resolvedTargetClass"] == "WeldConstraint" and not slot["serializedNull"] and not slot["targetsRetiredForest"], "Resolved actual Ref stays nonnull and externally mapped")
      cases.append({"case": "raw-resolved-external-stays-nonnull", "passed": True})
      for name in ("Part0Internal", "Part1Internal", "PlaceAvatarRules"):
        refused("omitted-" + name, lambda name=name: refs.inspect(fixture(lambda p: p.__setitem__(slice(None), [r for r in p if r[1] != name]))))
        def wrong_type(p, name=name):
            at = next(i for i, r in enumerate(p) if r[1] == name); row = p[at]; p[at] = (row[0], row[1], 0xFA, row[3])
        refused("wrong-type-" + name, lambda: refs.inspect(fixture(wrong_type)))
        def inbound(p, name=name):
            at = next(i for i, r in enumerate(p) if r[1] == name); row = p[at]; count = 1 if name == "PlaceAvatarRules" else 109
            p[at] = (row[0], row[1], row[2], ref_array([target_ref] + [-1] * (count - 1)))
        refused("inbound-" + name, lambda: refs.inspect(fixture(inbound)))
      def public_alias(p):
        at = next(i for i, r in enumerate(p) if r[1] == "Part0Internal"); row = p[at]; p[at] = (row[0], "Part0", row[2], row[3])
      refused("public-alias-is-not-hidden-slot", lambda: refs.inspect(fixture(public_alias)))
      refused("duplicate-native-column", lambda: refs.inspect(fixture(lambda p: p.append(p[2]))))
      refused("truncated-native", lambda: refs.inspect(raw[:-1]))
      refused("trailing-native", lambda: refs.inspect(raw + b"x"))
      refused("unresolved-raw-referent", lambda: refs.inspect(fixture(lambda p: p.__setitem__(2, (starter_kind, "PlaceAvatarRules", 0x13, ref_array([2**30]))))))
      refused("witness-count-drift", lambda: refs.inspect(raw, expected_welds=108))
      with tempfile.TemporaryDirectory(prefix="mongotv-read-reference-offline-") as directory:
        temp = Path(directory)
        def session(label): return receiver.Session(temp / label, "a" * 32, "b" * 64)
        def completion(s, **changes):
            value = {"schema": receiver.SCHEMA, "stage": "mcp-completion", "passed": True, "captureId": "a" * 32,
                "all213SourcesUnchanged": True, "rawEngineSerializationCaptured": True, "finalOriginalGuardPassed": True,
                "postCleanupOriginalGuardPassed": True, "ownedLeaseReleased": True, "ownedLedgerReleased": True,
                "opaqueSlotsRemainUncertified": True, "referenceAbsenceCertified": False, "deletionApproved": False,
                "nativeExecutedByAuthor": False, "originalWrites": 0, "instancesCreated": 0, "modeSwitches": 0,
                "connectionsRetained": 0, "weldConstraints": 109, "placeId": 131311258779917, "universeId": 10559217407,
                "cleanupErrors": [], "inputRootCount": 113, "referenceBytes": len(raw), "referenceSHA256": refs.sha(raw),
                "transfer": {"parts": len(s.parts), "bytes": len(raw), "sha256": refs.sha(raw)}}
            value.update(changes); return receiver.encode(value)
        def uploaded(label):
            s = session(label)
            for index, at in enumerate(range(0, len(raw), receiver.PART_BYTES)): s.accept_part(index, raw[at:at + receiver.PART_BYTES])
            return s
        s = uploaded("receiver-good"); s.accept_completion(completion(s))
        check((s.dest / "references.rbxm").read_bytes() == raw, "Transport original raw bytes")
        cases.append({"case": "actual-receiver-raw-transfer", "passed": True})
        refused("wrong-private-token", lambda: s.authenticate("a" * 32, "c" * 64))
        refused("wrong-capture-id", lambda: s.authenticate("c" * 32, "b" * 64))
        refused("duplicate-part", lambda: s.accept_part(0, b"x"))
        refused("reordered-part", lambda: session("receiver-order").accept_part(1, b"x"))
        short = session("receiver-short"); short.accept_part(0, b"x")
        refused("part-after-short", lambda: short.accept_part(1, b"x"))
        for key, value in (("originalWrites", True), ("connectionsRetained", 1), ("weldConstraints", 108),
                           ("deletionApproved", True), ("referenceAbsenceCertified", True), ("finalOriginalGuardPassed", False),
                           ("referenceSHA256", "f" * 64), ("referenceBytes", 1), ("ownedLeaseReleased", False),
                           ("inputRootCount", 113.0)):
            bad = uploaded("bad-" + key); refused("completion-" + key, lambda bad=bad, key=key, value=value: bad.accept_completion(completion(bad, **{key: value})))
            check((bad.dest / "native-completion.received.json").exists() and not (bad.dest / "references.rbxm").exists(), "Failed messages preserved but never assembled/certified")
        for key in ("parts", "bytes"):
            bad = uploaded("transfer-float-" + key)
            claim = {"parts": len(bad.parts), "bytes": len(raw), "sha256": refs.sha(raw)}
            claim[key] = float(claim[key])
            refused("completion-transfer-float-" + key, lambda bad=bad, claim=claim: bad.accept_completion(completion(bad, transfer=claim)))
            check((bad.dest / "native-completion.received.json").exists() and not (bad.dest / "references.rbxm").exists(), "Inexact typed transfer count remains failed raw evidence")
        failed = session("known-native-failure"); failed.accept_completion(receiver.encode({"schema": receiver.SCHEMA, "stage": "mcp-completion", "passed": False, "captureId": "a" * 32, "error": "controlled failure"}))
        check(failed.completion["passed"] is False, "Known failed native completion retained")
        cases.append({"case": "known-failed-native-claim", "passed": True})
        # Actual execute wrapper, fake API/server only. It must not bind HTTP.
        class Server:
            def __init__(self): self.starts = self.stops = 0
            def start(self): self.starts += 1
            def stop_after_known_completion(self): self.stops += 1
        class Client:
            def __init__(self, mode): self.mode, self.calls, self.closes = mode, 0, 0
            def _request(self, *args, **kwargs):
                self.calls += 1
                if self.mode == "transport-unknown": raise TimeoutError("explicit synthetic transport")
                if self.mode == "envelope-unknown": return {"result": {}}
                if self.mode == "completed-error": return {"result": {"isError": True, "content": [{"type": "text", "text": "completed error"}]}}
                if self.mode == "completed-malformed": return {"result": {"content": [{"type": "text", "text": "wrong json"}]}}
                if self.mode == "completed-failure": return {"result": {"content": [{"type": "text", "text": receiver.encode({"schema": receiver.SCHEMA, "stage": "mcp-completion", "passed": False, "captureId": "a" * 32}).decode()}]}}
                return {"result": {"content": [{"type": "text", "text": completion(native_session).decode()}]}}
            def close(self): self.closes += 1
        # Driver's actual local decoder import resolves this frozen candidate.
        import sys
        sys.path.insert(0, str(HERE))
        for mode in ("completed-error", "completed-malformed", "completed-failure", "transport-unknown", "envelope-unknown", "success"):
            run, private = temp / (mode + "-run"), temp / (mode + "-private"); run.mkdir(); private.mkdir()
            native_session = uploaded(mode + "-native") if mode == "success" else session(mode + "-native")
            client, server = Client(mode), Server(); source = b"exact-fake-request-source"
            unknown = mode.endswith("unknown")
            if unknown: (private / "root-known-ended-release.json").write_bytes(receiver.encode({"rootConfirmedNativeRequestEnded": True, "executedSourceSHA256": refs.sha(source)}))
            try:
                verdict = driver.execute(client, server, native_session, source, "fake-SID", run, private, "b" * 64)
                check(mode == "success" and verdict["rawProtectedFieldsPassed"], "Only fully decoded success returns verdict")
            except (AssertionError, ValueError, TimeoutError): check(mode != "success", "Success should not fail")
            check(client.calls == 1 and client.closes == 1 and server.starts == 1 and server.stops == 1, "One request/no retry + independent lifecycle")
            if unknown: check((run / "receiver-retained.json").exists() and (run / "receiver-stop-after-root-resolution.json").exists(), "Unknown retains until explicit Root resolution")
            else: check((run / "receiver-stop.json").exists(), "Completed failure stops owned receiver")
            check(all(b"b" * 64 not in p.read_bytes() for p in run.iterdir() if p.is_file()), "No private token public")
            cases.append({"case": "actual-wrapper-" + mode, "passed": True, "nativeCalls": 0, "fakeAPICalls": client.calls})
      receipt.update(passed=True, cases=len(cases), checks=checks, results=cases)
    except BaseException as error:
      receipt.update(error=str(error), cases=len(cases), checks=checks, results=cases); raise
    finally:
      for name, raw_input in pins.items(): assert (HERE / name).read_bytes() == raw_input
      assert oldpath.read_bytes() == old
      with target.open("xb") as stream: stream.write(receiver.encode(receipt))
    print(json.dumps({"passed": True, "cases": len(cases), "checks": checks, "receiptSHA256": refs.sha(target.read_bytes())}))


if __name__ == "__main__": main()
