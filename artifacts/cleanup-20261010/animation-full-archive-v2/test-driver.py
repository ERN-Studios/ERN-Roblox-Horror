"""Actual frontier validator + pinned single-request helper; no Studio calls."""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INVENTORY = HERE.with_name("animation-cache-inventory-v1")
SHA = lambda b: hashlib.sha256(b).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    output = args.receipt.resolve()
    assert output.is_relative_to(ROOT / "artifacts/cleanup-20261010") and output.parent.is_dir() and not output.exists()
    paths = [HERE / "run-root-frontier.py", INVENTORY / "run-root-inventory.py", HERE / "frontier-source.luau", Path(__file__).resolve()]
    inputs = {p: p.read_bytes() for p in paths}
    driver = load("actual_archive_frontier_driver", paths[0])
    helper = load("pinned_readonly_transport", paths[1])
    checks, results = 0, []

    def check(value, reason):
        nonlocal checks
        checks += 1
        assert value, reason

    fixture = {"schema": "mongotv-animation-archive-reference-frontier-v1", "passed": True,
               "sourceCount": 213, "slotCount": 28, "cacheRecords": 191,
               "inventoryManifestSHA256": "4caa106ecfcf965013c4ac6759c61c3fa752ff855f51614b9392ba8e0cbc1d94",
               "sourceCatalogSHA256": "b30a806da598ab234a0ca15066e84aea8c030a48a7ab44bb9b3583f86b0092b4",
               "originalSourceEditorPropertiesUnchanged": True, "originalRootCacheMetadataUnchanged": True, "finalOriginalGuardPassed": True,
               "nativeInstanceWrites": 0, "nativeSourceWrites": 0, "nativePropertyWrites": 0, "collectorStateWrites": 0, "modeSwitches": 0,
               "deletionApproved": False, "fullNativeArchiveCertified": False, "referenceAbsenceCertified": False,
               "schemas": [{"className": name} for name in ("Animation", "AnimationRigData", "Folder", "Keyframe", "KeyframeSequence", "Model", "ObjectValue", "Pose")],
               "slots": [{"holder": {"instanceId": str(i), "className": "ObjectValue"}, "name": "Value", "readable": True,
                          "descriptor": {"scriptType": "Instance"}, "value": {"kind": "Instance"}} for i in range(27)] +
                        [{"holder": {"instanceId": "1_41652", "className": "Model"}, "name": "PrimaryPart", "readable": True,
                          "descriptor": {"scriptType": "Instance"}, "value": {"kind": "nil"}}],
               "limits": "Controlled JSON/reference boundary only."}
    receipt = {"schema": "mongotv-animation-frontier-actual-driver-offline-v1", "passed": False, "nativeCalls": 0,
               "productionWrites": 0, "inputs": [{"path": p.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)} for p, raw in inputs.items()]}
    try:
        for case in ("success", "unreadable", "unknown-with-value", "unreadable-no-error", "source-hash", "manifest-hash", "source-count",
                     "slot-count", "duplicate-slot", "model-id", "missing-class", "missing-value", "wrong-value-kind", "claimed-write", "claimed-delete", "failed-guard"):
            report = copy.deepcopy(fixture)
            if case.startswith("unreadable") or case == "unknown-with-value":
                report["slots"][0]["readable"] = False
                report["slots"][0]["error"] = "controlled access error"
                if case != "unknown-with-value":
                    del report["slots"][0]["value"]
                if case == "unreadable-no-error":
                    del report["slots"][0]["error"]
            elif case == "source-hash": report["sourceCatalogSHA256"] = "b" * 64
            elif case == "manifest-hash": report["inventoryManifestSHA256"] = "b" * 64
            elif case == "source-count": report["sourceCount"] = 212
            elif case == "slot-count": report["slotCount"] = 27
            elif case == "duplicate-slot": report["slots"][1] = report["slots"][0]
            elif case == "model-id": report["slots"][-1]["holder"]["instanceId"] = "foreign"
            elif case == "missing-class": report["schemas"].pop()
            elif case == "missing-value": del report["slots"][0]["value"]
            elif case == "wrong-value-kind": report["slots"][0]["value"]["kind"] = "string"
            elif case == "claimed-write": report["nativeSourceWrites"] = 1
            elif case == "claimed-delete": report["deletionApproved"] = True
            elif case == "failed-guard": report["finalOriginalGuardPassed"] = False
            expected = case in ("success", "unreadable")
            try:
                verdict = driver.validate(report)
                check(expected and verdict["frontierReadPassed"] and not verdict["referenceAbsenceCertified"], "only exact known read passes")
            except (AssertionError, KeyError):
                check(not expected, "every malformed/unknown certification rejected")
            results.append({"case": case, "expectedPass": expected, "passed": True})
        for case in ("completed", "unknown-before", "unknown-after", "tool-error", "malformed-envelope"):
            saved = {}
            def save(name, value):
                check(name not in saved, "immutable evidence names")
                saved[name] = value
            class Fake:
                calls = 0
                def _request(self, method, params, timeout):
                    self.calls += 1
                    check(method == "tools/call" and params["name"] == "execute_luau" and timeout == 600, "single bounded execute")
                    check(params["arguments"]["code"].encode() == inputs[paths[2]], "actual assembled frontier untouched")
                    if case.startswith("unknown-"): raise TimeoutError("explicit synchronous fake transport ambiguity")
                    if case == "tool-error": return {"result": {"isError": True, "content": [{"type": "text", "text": "completed error"}]}}
                    if case == "malformed-envelope": return {"result": {}}
                    return {"result": {"content": [{"type": "text", "text": json.dumps(fixture)}]}}
            client = Fake()
            try:
                report = helper.native_read(client, "offline-only", inputs[paths[2]], "frontier", save)
                check(case == "completed" and driver.validate(report)["frontierReadPassed"], "actual helper and validator integration")
            except helper.CaptureFailure as error:
                check(case != "completed" and error.outcome == ("unknown-transport" if case.startswith("unknown-") else "completed-tool-error" if case == "tool-error" else "unknown-envelope"), "unknown/completed outcomes distinct")
            check(client.calls == 1, "no retry, follow-up, abandon or native recovery")
            results.append({"case": case, "passed": True, "fakeRequests": client.calls})
        receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error)
        raise
    finally:
        receipt.update(cases=len(results), checks=checks, results=results)
        for path, raw in inputs.items(): assert path.read_bytes() == raw, "Actual port input drift"
        with output.open("xb") as stream:
            stream.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"passed": True, "cases": len(results), "checks": checks, "receiptSHA256": SHA(output.read_bytes())}))


if __name__ == "__main__":
    main()
