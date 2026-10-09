"""Exercise the actual metadata transaction in owned temporary repositories.

Native reader/git are fake boundaries; no Studio/network calls or real Source
initializers run. Historical native classes/properties and 96 coverage gaps are
used with synthetic Source text to test filesystem/CAS/actor-safe rollback.
"""
from pathlib import Path
import argparse
import copy
import json
import tempfile
from unittest import mock

import add_enabled_manifest_metadata as actual

INPUTS = actual.ROOT / "artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-preparation-v1/inputs"
CHECKS = 0


def check(condition, message):
    global CHECKS
    CHECKS += 1
    assert condition, message


def pinned_input(directory=INPUTS):
    index = json.loads((directory / "index.json").read_bytes())
    raw = (directory / "manifest-before.json").read_bytes()
    assert index["schema"] == "s12-offline-metadata-input-v1" and index["file"] == "manifest-before.json"
    assert actual.sha(raw) == index["rawSHA256"] == "cab2d235d9636d19d89686219b74e25dfba7fe7b360a520fe7db6c93ef043cca"
    assert len(raw) == index["rawBytes"]
    return raw


def fixture(root):
    before = json.loads(pinned_input())
    rows, report = actual.snapshot(actual.REFERENCE, 96)
    rows, report = copy.deepcopy(rows), copy.deepcopy(report)
    by_segments = {tuple(row["segments"]): row for row in rows}
    source_raw = {}
    for index, entry in enumerate(before["items"]):
        if entry["className"] not in actual.SOURCE_CLASSES:
            continue
        raw = (f"-- owned metadata fixture {index}\nreturn {index}\n").encode()
        canonical = actual.canonical_bytes(raw.decode())
        entry.update(sha256=actual.sha(canonical), bytes=len(canonical), sourceEditorMatches=True)
        entry["studioTrailingNewline"] = False
        row = by_segments[tuple(entry["segments"])]
        row.update(sourceSHA256=actual.sha(canonical), editorSHA256=actual.sha(canonical), canonicalBytes=len(canonical),
                   rawSourceSHA256=actual.sha(raw), rawEditorSHA256=actual.sha(raw), rawBytes=len(raw),
                   minusOneTrailingLFSHA256=actual.sha(canonical[:-1]), sourceEditorMatches=True)
        path = root / entry["file"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        source_raw[entry["file"]] = raw
    raw = actual.encode(before)
    (root / "studio-sync-manifest.json").write_bytes(raw)
    head = copy.deepcopy(before)
    # A distinct actor-owned RoundUI row must stay working-only in the scoped blob.
    round_row = next(row for row in head["items"] if row["studioPath"].endswith(".RoundUI"))
    round_row["sha256"] = "d" * 64
    round_row["bytes"] += 7
    return raw, actual.encode(head), rows, report, source_raw


def execute(case, before_hook=None, after_hook=None, replace_failure=False, head_change=False):
    with tempfile.TemporaryDirectory(prefix="mongotv-s12-") as directory:
        root = Path(directory)
        before, head_raw, rows, report, sources = fixture(root)
        dest, checkpoint = root / "evidence", root / "checkpoint"
        manifest = root / "studio-sync-manifest.json"
        calls = []
        state = {"head": b"fixture-head\n"}

        def git(args, **kwargs):
            if args == ["git", "rev-parse", "HEAD"]:
                return state["head"]
            assert args == ["git", "show", "HEAD:studio-sync-manifest.json"]
            return head_raw

        def diagnostic(directory, gaps):
            phase = "before" if gaps == 96 else "after"
            calls.append(phase)
            directory.mkdir(parents=True)
            hook = before_hook if phase == "before" else after_hook
            if hook:
                hook(root, before, rows, report)
            if head_change and phase == "before":
                state["head"] = b"actor-new-head\n"
            result = copy.deepcopy(report)
            result["manifestPropertyCoverageGapCount"] = gaps
            return copy.deepcopy(rows), result

        caught = None
        with mock.patch.multiple(actual, ROOT=root, DEST=dest, CHECKPOINT=checkpoint), \
             mock.patch.object(actual, "run_diagnostic", side_effect=diagnostic), \
             mock.patch.object(actual.subprocess, "check_output", side_effect=git):
            if replace_failure:
                with mock.patch.object(actual.os, "replace", side_effect=OSError("injected atomic replace failure")):
                    try: result = actual.main(True)
                    except BaseException as error: caught = error
            else:
                try: result = actual.main(True)
                except BaseException as error: caught = error
        after = manifest.read_bytes()
        if case == "success":
            check(caught is None and result["pass"] is True, "actual transaction passed")
            check(calls == ["before", "after"], "reader brackets metadata transaction")
            expected, changes = actual.proposal(before, rows)
            check(after == expected and len(changes) == 96, "exact 96-field working proposal")
            scoped, _ = actual.proposal(head_raw, rows, verify_source=False)
            check((checkpoint / "manifest-head-scoped-for-commit.json").read_bytes() == scoped, "HEAD-owned row projection retained")
            before_data, after_data = json.loads(before), json.loads(after)
            for old, new in zip(before_data["items"], after_data["items"]):
                restored = copy.deepcopy(new)
                if "Enabled" not in old.get("properties", {}) and "Enabled" in restored.get("properties", {}):
                    restored["properties"].pop("Enabled")
                check(restored == old, "all non-owned row fields unchanged")
            check({k:v for k,v in before_data.items() if k != "items"} == {k:v for k,v in after_data.items() if k != "items"}, "all top metadata/counts unchanged")
            check(json.loads((dest / "receipt.json").read_bytes())["sourcesUnchanged"] == 212, "receipt records Source coverage")
        else:
            check(caught is not None, "injected fault rejected")
            if case == "actor-row":
                current = json.loads(after)
                actor = next(row for row in current["items"] if row.get("actorNote"))
                check(actor["actorNote"] == "preserve concurrent edit" and "Enabled" in actor["properties"], "actor row retained exactly")
                check(current["actorTop"] == "preserve top metadata", "actor top metadata retained")
                clean = copy.deepcopy(current)
                clean.pop("actorTop")
                clean_actor = next(row for row in clean["items"] if row.get("actorNote"))
                clean_actor.pop("actorNote")
                clean_actor["properties"].pop("Enabled")
                check(actual.encode(clean) == before, "other 95 owned additions independently rolled back")
                rollback = json.loads((dest / "rollback.json").read_bytes())
                check(rollback["preservedActorRows"] == [actor["studioPath"]], "conflicting row named in receipt")
            elif case == "actor-manifest":
                actor_data = json.loads(after)
                check(actor_data["actorTop"] == "before write", "pre-write actor metadata retained")
                actor_data.pop("actorTop")
                check(actual.encode(actor_data) == before, "no owned fields written on CAS rejection")
            else:
                check(after == before, "owned manifest unchanged or rolled back exactly")
            if (dest / "rollback.json").exists():
                receipt = json.loads((dest / "rollback.json").read_bytes())
                check(receipt["pass"] is False and receipt["primaryError"], "failure receipt retained")
        for file, raw in sources.items():
            if case == "actor-source" and file == next(iter(sources)):
                check((root / file).read_bytes() == raw + b"-- actor edit\n", "foreign Source retained")
            else:
                check((root / file).read_bytes() == raw, "Source untouched")
        check(not list(root.glob(".studio-sync-manifest.json.cleanup-*.tmp")), "owned sibling temporary cleaned")
        return {"case": case, "pass": True, "nativeBoundaryCalls": calls}


def reject(call):
    try: call()
    except (AssertionError, KeyError):
        check(True, "negative rejected")
        return
    raise AssertionError("negative unexpectedly passed")


def run():
    cases = []
    cases.append(execute("success"))

    def raise_after(*args): raise RuntimeError("injected after-reader failure")
    def raise_before(*args): raise RuntimeError("injected before-reader failure")
    def actor_manifest(root, *args):
        path = root / "studio-sync-manifest.json"
        value = json.loads(path.read_bytes()); value["actorTop"] = "before write"
        path.write_bytes(actual.encode(value))
    def actor_row(root, *args):
        path = root / "studio-sync-manifest.json"
        value = json.loads(path.read_bytes())
        target = next(row for row in value["items"] if row["className"] == "Script" and "Enabled" in row["properties"])
        target["actorNote"] = "preserve concurrent edit"
        value["actorTop"] = "preserve top metadata"
        path.write_bytes(actual.encode(value))
    def actor_source(root, before, *args):
        file = next(row["file"] for row in json.loads(before)["items"] if row["className"] in actual.SOURCE_CLASSES)
        path = root / file; path.write_bytes(path.read_bytes() + b"-- actor edit\n")
    def native_drift(root, before, rows, report):
        report["nativeEnd"]["catalogSHA256"] = "f" * 64

    cases.extend([execute("before-reader-failure", before_hook=raise_before),
                  execute("after-reader-failure", after_hook=raise_after),
                  execute("atomic-replace-failure", replace_failure=True),
                  execute("actor-manifest", before_hook=actor_manifest),
                  execute("actor-row", after_hook=actor_row),
                  execute("actor-source", after_hook=actor_source),
                  execute("head-change", head_change=True),
                  execute("native-drift", after_hook=native_drift)])
    rows, _ = actual.snapshot(actual.REFERENCE, 96)
    raw = pinned_input()
    chosen = next(i for i,r in enumerate(rows) if "Enabled" in r["properties"])
    for label, mutate in [
        ("nonboolean-enabled", lambda r:r[chosen]["properties"].__setitem__("Enabled", 1)),
        ("noninverse-enabled", lambda r:r[chosen]["properties"].__setitem__("Enabled", r[chosen]["properties"]["Disabled"])),
        ("recorded-disabled-drift", lambda r:r[chosen]["properties"].__setitem__("Disabled", not r[chosen]["properties"]["Disabled"])),
        ("class-drift", lambda r:r[chosen].__setitem__("className", "ModuleScript")),
        ("duplicate-native-path", lambda r:r[-1].__setitem__("segments", r[0]["segments"])),
        ("source-contract-drift", lambda r:r[chosen].__setitem__("sourceSHA256", "e" * 64)),
    ]:
        changed = copy.deepcopy(rows); mutate(changed)
        reject(lambda: actual.proposal(raw, changed))
        cases.append({"case":label,"pass":True})
    manifest = json.loads(raw)
    missing = next(r for r in manifest["items"] if r["className"] == "Script" and "Enabled" not in r["properties"])
    missing["properties"]["Enabled"] = not missing["properties"]["Disabled"]
    reject(lambda:actual.proposal(actual.encode(manifest), rows))
    cases.append({"case":"changed-95-field-scope","pass":True})
    with tempfile.TemporaryDirectory(prefix="mongotv-s12-input-negative-") as directory:
        path = Path(directory)
        for name in ("manifest-before.json", "index.json"):
            (path/name).write_bytes((INPUTS/name).read_bytes())
        changed = path/"manifest-before.json"; changed.write_bytes(changed.read_bytes()+b" ")
        reject(lambda:pinned_input(path))
    cases.append({"case":"changed-pinned-input","pass":True})
    for label, mutate in [
        ("wrong-studio", lambda report,pages:report.__setitem__("studioId", "other-session")),
        ("play-mode", lambda report,pages:report["nativeEnd"].__setitem__("datamodel", "Server")),
        ("editor-conflict", lambda report,pages:report.__setitem__("nativeSourceEditorConflictCount", 1)),
        ("page-catalog-drift", lambda report,pages:pages[0]["meta"].__setitem__("catalogSHA256", "f"*64)),
        ("unreadable-source", lambda report,pages:next(row for page in pages for row in page["rows"] if row["className"] in actual.SOURCE_CLASSES).__setitem__("sourceReadable", False)),
        ("duplicate-page-row", lambda report,pages:pages[-1]["rows"][-1].__setitem__("segments", pages[0]["rows"][0]["segments"])),
    ]:
        with tempfile.TemporaryDirectory(prefix="mongotv-s12-snapshot-negative-") as directory:
            path = Path(directory)
            report = json.loads((actual.REFERENCE/"result.json").read_bytes())
            pages = [json.loads((actual.REFERENCE/f"native-page-{i:02}.json").read_bytes()) for i in range(10)]
            mutate(report,pages)
            (path/"result.json").write_bytes(actual.encode(report))
            for i,page in enumerate(pages):
                (path/f"native-page-{i:02}.json").write_bytes(actual.encode(page))
            reject(lambda:actual.snapshot(path,96))
        cases.append({"case":label,"pass":True})
    return {"schema":"s12-enabled-metadata-offline-proof-v1","pass":True,"cases":cases,"caseCount":len(cases),
            "assertions":CHECKS,"nativeCalls":0,"canonicalSourceWrites":0,"canonicalManifestWrites":0,
            "scope":"Actual transaction/atomic CAS/scoped rollback exercised against fake native/git boundaries with 212 synthetic Source files and historical classes/properties. No gameplay/native integration certificate.",
            "toolSHA256":actual.sha(Path(actual.__file__).read_bytes()),"testSHA256":actual.sha(Path(__file__).read_bytes())}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    result = run()
    if args.receipt: actual.save(args.receipt, actual.encode(result))
    print(json.dumps({k:v for k,v in result.items() if k != "cases"}))
