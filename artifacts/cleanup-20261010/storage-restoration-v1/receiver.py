"""Immutable localhost receiver. Import/serve never connects to Roblox Studio."""
from pathlib import Path
import argparse
import hashlib
import http.server
import json
import re

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SCHEMA = "external-held-storage-native-restoration-supplement-v4"
ARCHIVE = ROOT / "artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1"
PART_BYTES = 750000
NATIVE_SHA = "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"
FACTS_SHA = "b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33"
SUPPLEMENT_SHA = "0c83647db8c7a2c299834481c0d3b1032a97ca2aafe9aacf8091f2523392b7a1"
PROBE_SHA = "133436198c3b5a7338f9327beb8d8023c14203ee1dbb69372b2287d65b22c31b"
BASELINE_SHA = "df846a007464c2f5bf11284b69eecf32b0c8ecaf4fe776481489483fc7095a2b"
CAPTURE_COMPLETION_SHA = "e326db60c8032345efe7346cc01f177d9e3124f9121227f8819b3c448d3e8a8d"
EXPECTED_STUDIO = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
HEX = re.compile(r"[0-9a-f]{64}\Z")

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def encode(value):
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()

def strict_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            assert key not in result, "Duplicate JSON key"
            result[key] = value
        return result
    def reject(value):
        raise ValueError("Non-finite JSON value: " + value)
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=reject)

def zero_fields(value, names):
    assert all(type(value[name]) is int and value[name] == 0 for name in names), "Exact numeric zero fields required"

def integer_fields(value, expected):
    assert all(type(value[name]) is int and value[name] == number for name, number in expected.items()), "Exact integer counts required"

class Session:
    def __init__(self, dest, expected_roots, expected_descendants):
        self.dest = Path(dest).resolve()
        assert self.dest.is_relative_to(HERE) and not self.dest.exists(), "New execution directory under this port only"
        assert type(expected_roots) is int and 0 < expected_roots <= 1000
        assert type(expected_descendants) is int and 0 < expected_descendants <= 600000
        self.expected_roots = expected_roots
        self.expected_descendants = expected_descendants
        self.inputs = {
            "native": (ARCHIVE / "native.rbxm").read_bytes(),
            "facts": (ARCHIVE / "facts.json").read_bytes(),
            "captureCompletion": (ARCHIVE / "capture-completion.json").read_bytes(),
            "supplement": (HERE / "restore-supplement.json").read_bytes(),
            "probeSource": (HERE / "restoration-probe-v4.luau").read_bytes(),
            "baselineSource": (HERE / "capture-live-baseline.luau").read_bytes(),
            "receiverSource": Path(__file__).read_bytes(),
        }
        assert (len(self.inputs["native"]), sha(self.inputs["native"])) == (2739764, NATIVE_SHA)
        assert (len(self.inputs["facts"]), sha(self.inputs["facts"])) == (41912358, FACTS_SHA)
        assert sha(self.inputs["supplement"]) == SUPPLEMENT_SHA
        assert sha(self.inputs["probeSource"]) == PROBE_SHA and sha(self.inputs["baselineSource"]) == BASELINE_SHA
        assert sha(self.inputs["captureCompletion"]) == CAPTURE_COMPLETION_SHA
        self.facts = strict_json(self.inputs["facts"])
        completed = strict_json(self.inputs["captureCompletion"])
        assert completed["report"]["pass"] is True and completed["report"]["nativeSHA256"] == NATIVE_SHA
        assert self.facts["nativeSHA256"] == NATIVE_SHA and self.facts["heldNodeCount"] == 14079
        assert len(self.facts["roots"]) == 23 and len(self.facts["heldSources"]) == 12
        assert len({r["name"] for r in self.facts["roots"]}) == 23
        assert all(r["parentIsNil"] and r["originalHeldReference"] for r in self.facts["roots"])
        self.validate_supplement(strict_json(self.inputs["supplement"]))
        self.baseline = self.baseline_raw = self.baseline_completion = None
        self.finalized = self.probe_completion = None
        self.dest.mkdir(parents=True)
        self.save("probe-source.luau", self.inputs["probeSource"])
        self.save("baseline-source.luau", self.inputs["baselineSource"])
        self.save("restore-supplement.json", self.inputs["supplement"])
        self.save("inputs.json", encode({"schema": "storage-restoration-immutable-inputs-v1",
            "nativeCalls": 0, "serverStudioImports": 0, "restorationCertified": False,
            "expectedStudioId": EXPECTED_STUDIO, "expectedLiveSources": 213,
            "expectedLiveRoots": expected_roots, "expectedLiveDescendants": expected_descendants,
            "expectedLedgerRootRefs": 73, "expectedLedgerScriptRefs": 222,
            "inputs": {key: {"bytes": len(raw), "sha256": sha(raw)} for key, raw in self.inputs.items()}}))

    def guard(self):
        current = {
            "native": ARCHIVE / "native.rbxm", "facts": ARCHIVE / "facts.json",
            "captureCompletion": ARCHIVE / "capture-completion.json", "supplement": HERE / "restore-supplement.json",
            "probeSource": HERE / "restoration-probe-v4.luau", "baselineSource": HERE / "capture-live-baseline.luau",
            "receiverSource": Path(__file__),
        }
        for key, path in current.items():
            assert path.read_bytes() == self.inputs[key], "Immutable port/input changed: " + key
        for name, key in (("probe-source.luau", "probeSource"), ("baseline-source.luau", "baselineSource"),
                          ("restore-supplement.json", "supplement")):
            target = self.dest / name
            assert not target.is_symlink() and target.read_bytes() == self.inputs[key], "Immutable execution source changed: " + name

    def save(self, name, raw):
        assert Path(name).name == name, "Flat owned file only"
        target = self.dest / name
        if target.exists():
            assert not target.is_symlink() and target.is_file() and target.read_bytes() == raw, "Immutable output conflict: " + name
        else:
            with target.open("xb") as stream:
                assert stream.write(raw) == len(raw)

    def validate_supplement(self, value):
        assert value["schema"] == "s06-exact-four-bone-cframe-supplement-v1"
        assert value["nativeSHA256"] == NATIVE_SHA and value["factsSHA256"] == FACTS_SHA
        assert value["normalizationApplied"] is False and len(value["rows"]) == 4
        target_rows = [r for r in self.facts["nodes"] if r["path"] in {s["path"] for s in value["rows"]}]
        assert len(target_rows) == 4, "Exact target paths must be unique in full historical facts"
        targets = {r["path"]: r for r in target_rows}
        assert len(targets) == len({r["path"] for r in value["rows"]}) == 4
        for row in value["rows"]:
            original = targets[row["path"]]
            assert row["class"] == original["class"] == "Bone" and row["property"] == "CFrame"
            assert len(row["components"]) == 12 and row["components"] == original["properties"]["CFrame"]["value"]

    def validate_baseline(self, value):
        assert value["schema"] == "storage-restoration-live-baseline-v1"
        integer_fields(value, {"placeId": 131311258779917, "universeId": 10559217407, "expectedLiveSources": 213,
            "expectedLiveRoots": self.expected_roots, "expectedLiveDescendants": self.expected_descendants,
            "expectedLedgerRootRefs": 73, "expectedLedgerScriptRefs": 222})
        assert value["mode"] == "Edit" and type(value["sourcePins"]) is list and len(value["sourcePins"]) == 213
        zero_fields(value, ("sourceWrites", "propertyWrites", "originalParentWrites", "modeSwitches"))
        paths, identities = set(), set()
        for row in value["sourcePins"]:
            assert type(row["path"]) is str and 0 < len(row["path"]) <= 1024 and row["path"] not in paths
            assert row["class"] in {"ModuleScript", "LocalScript", "Script"}
            assert type(row["identity"]) is str and 0 < len(row["identity"]) <= 200 and row["identity"] not in identities
            assert type(row["parentIdentity"]) is str and 0 < len(row["parentIdentity"]) <= 200
            assert type(row["sourceSHA256"]) is str and type(row["metadataSHA256"]) is str
            assert HEX.fullmatch(row["sourceSHA256"]) and HEX.fullmatch(row["metadataSHA256"])
            assert type(row["bytes"]) is int and 0 <= row["bytes"] <= 10_000_000
            paths.add(row["path"])
            identities.add(row["identity"])

    def accept_baseline(self, raw):
        self.guard()
        value = strict_json(raw)
        self.validate_baseline(value)
        self.save("live-baseline.json", raw)
        if self.baseline_raw is not None:
            assert raw == self.baseline_raw
        self.baseline, self.baseline_raw = value, raw

    def accept_baseline_completion(self, raw):
        self.guard()
        assert self.baseline_raw is not None, "No received baseline"
        value = strict_json(raw)
        assert value["schema"] == "storage-restoration-live-baseline-completion-v1"
        assert value["baselineSHA256"] == sha(self.baseline_raw)
        self.save("live-baseline-native-completion.json", raw)
        assert value["pass"] is True and value["originalSourcesUnchanged"] is True, "Native baseline completion failed; new destination required"
        integer_fields(value, {"liveSources": 213, "liveRoots": self.expected_roots, "liveDescendants": self.expected_descendants})
        zero_fields(value, ("nativeObjectCreations", "sourceWrites", "propertyWrites", "originalParentWrites", "modeSwitches"))
        assert type(value["watchers"]) is int and value["watchers"] >= 4
        integer_fields(value, {"watchersReleaseAttempted": value["watchers"]})
        self.baseline_completion = value

    def context(self):
        self.guard()
        assert self.baseline_completion is not None, "Context locked until final native readonly baseline completion"
        return {"schema": SCHEMA, "roots": self.facts["roots"], "heldSources": self.facts["heldSources"],
            "heldNodeCount": 14079, "nativeBytes": len(self.inputs["native"]), "nativeSHA256": NATIVE_SHA,
            "nativeParts": (len(self.inputs["native"]) + PART_BYTES - 1) // PART_BYTES,
            "liveBaselineSchema": self.baseline["schema"], "liveBaselineSHA256": sha(self.baseline_raw),
            "expectedLiveSources": 213, "expectedLiveRoots": self.expected_roots,
            "expectedLiveDescendants": self.expected_descendants, "expectedLedgerRootRefs": 73,
            "expectedLedgerScriptRefs": 222, "sourcePins": self.baseline["sourcePins"]}

    def accept_part(self, index, raw):
        self.context()
        count = (len(self.inputs["native"]) + PART_BYTES - 1) // PART_BYTES
        assert type(index) is int and 0 <= index < count
        expected = self.inputs["native"][index * PART_BYTES:(index + 1) * PART_BYTES]
        assert raw == expected, "Supplemented native bytes differ; preserve failure, never normalize"
        self.save(f"roundtrip-part-{index:04d}.bin", raw)

    def finalize(self, raw):
        self.context()
        value = strict_json(raw)
        count = (len(self.inputs["native"]) + PART_BYTES - 1) // PART_BYTES
        integer_fields(value, {"parts": count, "bytes": len(self.inputs["native"])})
        assert value == {"parts": count, "bytes": len(self.inputs["native"]), "sha256": NATIVE_SHA}
        assembled = b"".join((self.dest / f"roundtrip-part-{i:04d}.bin").read_bytes() for i in range(count))
        assert assembled == self.inputs["native"]
        self.save("roundtrip.rbxm", assembled)
        self.save("transfer-receipt.json", encode({"schema": "storage-restoration-native-transfer-precompletion-v1",
            "passed": False, "restorationCertified": False, "originalNativeBytesExact": True,
            "transfer": value, "note": "Receipt predates final original guards and cleanup; only distinct native completion can report recipe pass."}))
        self.finalized = value

    def accept_probe_completion(self, raw):
        self.guard()
        value = strict_json(raw)
        assert value["schema"] == SCHEMA and type(value["pass"]) is bool
        self.save("probe-native-completion.received.json", raw)  # Received claims, not yet validated.
        if value["pass"]:
            assert self.finalized is not None and self.baseline_completion is not None
            assert all(value[key] is True for key in ("readableDataPass", "nativeSerializedBytesExact", "secondSupplementedReopenPass",
                "originalSourcesUnchanged", "originalSourcePinsUnchanged", "originalNativeArchiveUnchanged", "leaseReleased", "internalReferencesPass"))
            assert value["normalizationApplied"] is False and value["restorationCertified"] is False
            integer_fields(value, {"freshSourcePinsValidated": 213, "createdRoots": 46, "destroyedRoots": 46,
                "testOwnedRootsRemaining": 0, "testOwnedCFrameSetAttempts": 8, "testOwnedCFrameWrites": 8,
                "supplementPasses": 2, "reconstructedNodes": 14079, "reconstructedSources": 12, "referenceProperties": 10,
                "adoptedRoots": 46, "roundtripBytes": 2739764, "liveSources": 213, "liveRoots": self.expected_roots})
            assert value["liveBaselineSHA256"] == sha(self.baseline_raw)
            assert value["archiveSHA256"] == value["roundtripSHA256"] == value["secondNativeSHA256"] == NATIVE_SHA
            zero_fields(value, ("sourceWrites", "originalParentWrites", "modeSwitches"))
        self.save("probe-native-completion.json", raw)
        self.probe_completion = value
        self.save("port-verdict.json", encode({"schema": "storage-restoration-exact-recipe-verdict-v1",
            "recipePassed": value["pass"], "restorationCertified": False, "normalizationApplied": False,
            "completionSHA256": sha(raw), "baselineSHA256": sha(self.baseline_raw) if self.baseline_raw else None,
            "scope": "Raw archive plus exact four-Bone CFrame restoration after each reopen. Historical raw-only recovery remains failed. No native removal, full-place/assets/gameplay/multiplayer/streaming or publication certification."}))

def make_handler(session):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def answer(self, raw):
            self.send_response(200)
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
        def do_GET(self):
            try:
                session.guard()
                if self.path == "/baseline-context":
                    return self.answer(encode({"schema": "storage-restoration-live-baseline-context-v1", "expectedLiveSources": 213,
                        "expectedLiveRoots": session.expected_roots, "expectedLiveDescendants": session.expected_descendants,
                        "expectedLedgerRootRefs": 73, "expectedLedgerScriptRefs": 222}))
                if self.path == "/context":
                    return self.answer(encode(session.context()))
                if self.path == "/supplement":
                    session.context()
                    return self.answer(session.inputs["supplement"])
                pieces = self.path.strip("/").split("/")
                assert len(pieces) == 2 and pieces[0] == "native"
                session.context()
                index = int(pieces[1])
                count = (len(session.inputs["native"]) + PART_BYTES - 1) // PART_BYTES
                assert 0 <= index < count
                self.answer(session.inputs["native"][index * PART_BYTES:(index + 1) * PART_BYTES])
            except Exception as error:
                self.send_error(409, str(error))
        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                assert 0 < length <= PART_BYTES
                raw = self.rfile.read(length)
                assert len(raw) == length
                if self.path == "/baseline": session.accept_baseline(raw)
                elif self.path == "/baseline-completion": session.accept_baseline_completion(raw)
                elif self.path == "/completion": session.accept_probe_completion(raw)
                elif self.path == "/finalize": session.finalize(raw)
                else:
                    pieces = self.path.strip("/").split("/")
                    assert len(pieces) == 2 and pieces[0] == "roundtrip"
                    session.accept_part(int(pieces[1]), raw)
                self.answer(b"saved")
            except Exception as error:
                self.send_error(409, str(error))
    return Handler

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dest", type=Path, required=True)
    parser.add_argument("--expected-live-roots", type=int, required=True)
    parser.add_argument("--expected-live-descendants", type=int, required=True)
    args = parser.parse_args()
    session = Session(args.dest, args.expected_live_roots, args.expected_live_descendants)
    # A single-thread server serializes mutations; native requests happen in Root.
    server = http.server.HTTPServer(("127.0.0.1", 18916), make_handler(session))
    print(json.dumps({"ready": True, "port": 18916, "nativeCalls": 0, "dest": str(session.dest), "contextLocked": True}), flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
