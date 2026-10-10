"""Replay the actual Root driver against explicit synchronous fake transport.

No Studio queue, engine scheduling, cancellation or native behavior is simulated
as certified. Unknown-before/after cases deliberately leave the actual driver
with no later calls, retries, abandon, rollback or automatic native recovery.
"""
import base64
import hashlib
import importlib.util
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def run_tests():
    spec = importlib.util.spec_from_file_location("readonly_cache_actual_driver", HERE / "run-root-inventory.py")
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    collector = (HERE / "collector.luau").read_bytes()
    capture = "actual-offline-driver-capture-20261010"
    zero = {field: 0 for field in driver.ZERO_FIELDS}
    checks = 0

    def check(value, reason):
        nonlocal checks
        checks += 1
        assert value, reason

    def input_data(case):
        roots, records = [], []
        for name, klass, count in (("MongoTVEntityAnimations", "Folder", 117), ("RBX_ANIMSAVES", "Model", 27)):
            ids = [name + str(i) for i in range(count)]
            roots.append({"root": {"name": name, "className": klass, "childCount": count, "directChildIds": ids},
                          "descendantCount": count, "nodeCount": count + 1, "classHistogram": {"Folder": count},
                          "metadataRecordCount": count, "candidateIdentitySHA256": "a" * 64})
            records.extend({"instanceId": ident, "rootName": name, "topChild": True, "attributes": [], "tags": [],
                            "publishedAssetId": {"kind": "number", "value": str(1000 + i)}, "animationIdAttribute": {"kind": "nil"}}
                           for i, ident in enumerate(ids))
        sources = [{"instanceId": "source" + str(i), "className": "ModuleScript", "sourceBytes": 1,
                    "rawSourceSHA256": "a" * 64, "rawEditorSHA256": "a" * 64} for i in range(213)]
        manifest = {"schema": "mongotv-animation-cache-preservation-manifest-v1", "captureId": capture,
                    "templateSHA256": SHA(collector), "nativeReadOnly": True, "metadataComplete": True,
                    "sourceCount": 213, "sourceCatalog": sources, "sourceCatalogBeforeSHA256": "a" * 64,
                    "sourceCatalogAfterSHA256": "a" * 64, "roots": roots, "records": records, **zero,
                    "limits": "Explicit fake transport metadata only; not actual native cache evidence."}
        if case == "incomplete-metadata":
            manifest["metadataComplete"] = False
            records[0]["metadataIncomplete"] = True
        elif case == "manifest-root-class":
            roots[0]["root"]["className"] = "Model"
        elif case == "manifest-source-editor":
            sources[0]["rawEditorSHA256"] = "b" * 64
        raw = json.dumps(manifest, separators=(",", ":")).encode()
        begin = {"schema": "mongotv-animation-cache-read-begin-v1", "pass": True, "captureId": capture,
                 "templateSHA256": SHA(collector), "manifestSHA256": SHA(raw), "manifestBytes": len(raw),
                 "pageCount": math.ceil(len(raw) / 12000), "recordCount": len(records), "metadataComplete": manifest["metadataComplete"],
                 "sourceCount": 213, "sourceCatalogSHA256": "a" * 64, "roots": roots, "collectorStateWrites": 2, **zero}
        return raw, begin

    results = []
    cases = ("success", "timeout-before-begin", "timeout-after-begin", "timeout-before-page", "timeout-after-page",
             "timeout-before-finish", "timeout-after-finish", "tool-error-before-begin", "tool-error-after-begin",
             "malformed-envelope", "invalid-text-block", "invalid-json", "oversized-envelope", "oversized-completion",
             "collector-refusal-no-scratch", "collector-refusal-cleaned", "collector-refusal-pending",
             "page-wrong-sha", "page-wrong-order", "page-bad-base64", "page-claimed-writes", "begin-claimed-writes",
             "incomplete-metadata", "manifest-root-class", "manifest-source-editor", "finish-refusal-cleaned", "finish-refusal-pending")
    for case in cases:
        payload, begin = input_data(case)
        saved = {}

        def save(name, value):
            check(name not in saved, "immutable unique artifact names")
            saved[name] = value

        class FakeClient:
            def __init__(self):
                self.calls = []
                self.scratch = False

            def _request(self, method, params, timeout):
                check(method == "tools/call" and params["name"] == "execute_luau" and timeout == 600, "single bounded request")
                args = params["arguments"]
                check(args["studio_id"] == "offline-only" and args["datamodel_type"] == "Edit", "exact Edit binding")
                code = args["code"]
                check(code.encode().endswith(collector), "actual frozen collector appended unchanged")
                prefix = code.split("\n", 1)[0]
                request = json.loads(json.loads(prefix.split("JSONDecode(", 1)[1][:-1]))
                check(request["captureId"] == capture and request["templateSHA256"] == SHA(collector), "purpose/code bound")
                command = request["command"]
                self.calls.append(command)
                if case == "timeout-before-" + command:
                    raise TimeoutError("explicit fake unknown before " + command)
                if command == "begin":
                    self.scratch = case != "tool-error-before-begin"
                    report = dict(begin)
                elif command == "page":
                    page = request["page"]
                    chunk = payload[page * 12000:(page + 1) * 12000]
                    report = {"schema": "mongotv-animation-cache-read-page-v1", "captureId": capture,
                              "templateSHA256": SHA(collector), "page": page, "pageCount": begin["pageCount"],
                              "manifestSHA256": SHA(payload), "chunkBytes": len(chunk), "chunkSHA256": SHA(chunk),
                              "chunkBase64": base64.b64encode(chunk).decode(), "collectorStateWrites": page + 3, **zero}
                    if case == "page-wrong-sha":
                        report["chunkSHA256"] = "b" * 64
                    elif case == "page-wrong-order":
                        report["page"] += 1
                    elif case == "page-bad-base64":
                        report["chunkBase64"] = "invalid%%%%"
                    elif case == "page-claimed-writes":
                        report["nativeSourceWrites"] = 1
                elif command == "finish":
                    self.scratch = False
                    report = {"schema": "mongotv-animation-cache-read-finish-v1", "captureId": capture, "pass": True,
                              "manifestSHA256": SHA(payload), "sourceCount": 213, "sourceCatalogSHA256": "a" * 64,
                              "rootAndCacheMetadataUnchanged": True, "all213OriginalSourceEditorPropertiesUnchanged": True,
                              "pointInTimeGuardsOnly": True, "cleanup": {"closed": True, "collectorStateWrites": begin["pageCount"] + 4, **zero}}
                    if case.startswith("finish-refusal-"):
                        pending = case.endswith("pending")
                        self.scratch = pending
                        report = {"pass": False, "error": "completed current guard refusal", "collectorAcquired": True,
                                  "collectorCleanupPassed": not pending, **zero}
                else:
                    raise AssertionError("Unexpected later native command")
                if case == "timeout-after-" + command:
                    raise TimeoutError("explicit fake unknown after " + command)
                if command == "begin":
                    if case.startswith("tool-error-"):
                        return {"result": {"isError": True, "content": [{"type": "text", "text": "completed tool failure"}]}}
                    if case == "malformed-envelope":
                        return {"result": {}}
                    if case == "invalid-text-block":
                        return {"result": {"content": [{"type": "text", "text": 1}]}}
                    if case == "invalid-json":
                        return {"result": {"content": [{"type": "text", "text": "not JSON"}]}}
                    if case == "oversized-envelope":
                        return {"result": {"content": [{"type": "text", "text": "x" * 100001}]}}
                    if case == "oversized-completion":
                        return {"result": {"content": [{"type": "text", "text": "x" * 20001}]}}
                    if case.startswith("collector-refusal-"):
                        pending = case.endswith("pending")
                        acquired = not case.endswith("no-scratch")
                        self.scratch = pending
                        report = {"pass": False, "error": "completed refusal", "collectorAcquired": acquired,
                                  "collectorCleanupPassed": acquired and not pending, **zero}
                    if case == "begin-claimed-writes":
                        report["nativePropertyWrites"] = 1
                return {"result": {"content": [{"type": "text", "text": json.dumps(report, separators=(",", ":"))}]}}

        client = FakeClient()
        caught = None
        try:
            verdict = driver.execute_capture(client, "offline-only", collector, capture, save)
            check(case == "success" and verdict["capturePassed"] and not client.scratch, "only success certifies capture")
            check(client.calls == ["begin"] + ["page"] * begin["pageCount"] + ["finish"], "exact deterministic complete sequence")
            check(saved["cache-manifest-raw.json"] == payload and verdict["deletionApproved"] is False, "raw actual payload retained; no deletion")
        except BaseException as error:
            caught = error
            check(case != "success" and "capture-verdict.json" not in saved, "failure never gets preservation certificate")
            if case.startswith("timeout-"):
                expected = case.rsplit("-", 1)[-1]
                check(isinstance(error, driver.CaptureFailure) and error.outcome == "unknown-transport", "unknown transport distinguished")
                check(client.calls[-1] == expected and client.calls.count(expected) == 1, "no retry, abandon or later native calls")
                check(any(name.endswith("unknown-transport.json") for name in saved), "unknown evidence retained")
            elif case.startswith("tool-error-"):
                check(error.outcome == "completed-tool-error" and client.calls == ["begin"], "completed tool error distinguished")
            elif case in ("incomplete-metadata", "manifest-root-class", "manifest-source-editor"):
                check(error.outcome == "completed-metadata-refusal-owned-scratch-closed" and error.scratch_pending is False,
                      "metadata refusal after known owned cleanup")
                check(not client.scratch and client.calls[-1] == "finish", "scratch closed without claiming metadata complete")
            elif case.startswith("collector-refusal-") or case.startswith("finish-refusal-"):
                check(error.outcome == "completed-collector-refusal" and error.scratch_pending == case.endswith("pending"),
                      "known cleanup/pending distinguished")
            elif case.startswith("page-"):
                check(client.calls == ["begin", "page"], "validation refusal has no later calls")
            else:
                check(client.calls == ["begin"], "completion refusal stops later calls")
        results.append({"name": case, "passed": True, "nativeCalls": 0, "fakeRequestCount": len(client.calls),
                        "lastFakeCommand": client.calls[-1], "outcome": getattr(caught, "outcome", "validation-refusal" if caught else "success"),
                        "scratchPendingObserved": client.scratch})
    return {"passed": True, "cases": len(results), "checks": checks, "results": results,
            "nativeCalls": 0, "limits": "Actual Python driver, synchronous fake transport and metadata. Does not prove Studio cancellation, queue timing, engine scheduling or actual cache contents."}
