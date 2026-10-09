"""Run the actual S02 wrapper only in temporary copies, including failure ports.

The successful fixture compiles all ten historical sources and their archives
with the actual Luau executable. Negative fixtures mock only that compiler
boundary. No Studio calls, canonical batch rerun, or historical receipt edits.
"""
from __future__ import annotations

import argparse
from contextlib import ExitStack, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from unittest import mock

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WRAPPER = HERE / "retire_absent_codex_mirrors.py"
HISTORICAL = ROOT / "artifacts/cleanup-serverstorage-20261009/retired-repo-mirrors"
METADATA = HISTORICAL.parent / "native-script-metadata.json"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, help="Optional NEW JSON receipt")
    args = parser.parse_args()
    if args.receipt:
        assert not args.receipt.exists(), "Refuse existing test receipt"
    before_inputs = {path: path.read_bytes() for path in
                     (WRAPPER, METADATA, HISTORICAL / "manifest-before.json", HISTORICAL / "removal-receipt.json")}
    historic_receipt = json.loads(before_inputs[HISTORICAL / "removal-receipt.json"])
    source_bytes = {}
    for row in historic_receipt["archived"]:
        archive = ROOT / row["archiveFile"]
        raw = archive.read_bytes()
        assert digest(raw) == row["rawSHA256"] and len(raw) == row["rawBytes"]
        before_inputs[archive] = raw
        source_bytes[row["file"]] = raw
    assert len(source_bytes) == 10
    assert digest(before_inputs[METADATA]) == historic_receipt["nativeEvidenceSHA256"]
    spec = importlib.util.spec_from_file_location("retire_mirrors_under_test", WRAPPER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    assert module.LUAU.is_file(), "Actual success compile executable missing"
    real_compile = subprocess.run
    real_fdopen = module.os.fdopen
    real_replace = module.os.replace
    real_unlink = Path.unlink
    real_open = Path.open
    real_prepare = module.prepare_manifest_temp
    checks, cases = 0, []

    def check(value, label):
        nonlocal checks
        checks += 1
        assert value, label

    def scenario(label, fault=None, *, expected=None, real_compiles=False):
        primary = RuntimeError("fixture-" + str(fault))
        compiler_calls = []
        # luau-compile on Windows cannot open the archive's longest basename
        # under the user's long default TEMP directory. Keep owned fixtures at
        # the workspace drive root; TemporaryDirectory removes only this root.
        with tempfile.TemporaryDirectory(prefix="s02-", dir=ROOT.anchor) as owned:
            root = Path(owned).resolve()
            dest = root / "artifacts/cleanup-serverstorage-20261009/retired-repo-mirrors"
            dest.parent.mkdir(parents=True)
            metadata = dest.parent / "native-script-metadata.json"
            metadata.write_bytes(before_inputs[METADATA])
            manifest = root / "studio-sync-manifest.json"
            original_manifest = before_inputs[HISTORICAL / "manifest-before.json"]
            manifest.write_bytes(original_manifest)
            for name, raw in source_bytes.items():
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)
            owner_file = root / "ServerStorage/owner-concurrent.lua"
            owner_file.write_bytes(b"owner runtime source stays untouched\n")
            owner_tmp = root / ".studio-sync-manifest.json.cleanup-owner.tmp"
            owner_tmp.write_bytes(b"unrelated temporary file")
            targets = [root / name for name in source_bytes]
            metadata_owner = before_inputs[METADATA] + b"\n "
            manifest_owner = original_manifest + b"\n "
            source_owner = b"-- concurrent owner source\nreturn 'owner'\n"
            called = set()

            def once(name, callback):
                if name not in called:
                    called.add(name)
                    callback()

            def compiler(command, **kwargs):
                check(command[:2] == [str(module.LUAU), "--binary"] and
                      kwargs == {"stdout": subprocess.DEVNULL, "check": True}, label + ": compile port changed")
                target = Path(command[-1]).resolve()
                check(target.is_relative_to(root) and target.is_file(), label + ": compile escaped fixture")
                compiler_calls.append(command[2])
                if fault == "metadata-during-initial-compiles":
                    once("compile-change", lambda: metadata.write_bytes(metadata_owner))
                if fault == "metadata-during-archive-compiles" and command[2] == "-O1":
                    once("compile-change", lambda: metadata.write_bytes(metadata_owner))
                if real_compiles:
                    return real_compile(command, **kwargs)
                return SimpleNamespace(returncode=0)

            class FailingStream:
                def __init__(self, stream):
                    self.stream = stream
                def __enter__(self):
                    self.stream.__enter__()
                    return self
                def __exit__(self, *arguments):
                    return self.stream.__exit__(*arguments)
                def write(self, value):
                    if fault in ("partial-temp-write", "short-temp-write", "temp-write-and-cleanup-failure"):
                        size = max(1, len(value) // 3)
                        self.stream.write(value[:size])
                        if fault == "short-temp-write":
                            return size
                        raise primary
                    return self.stream.write(value)
                def flush(self):
                    return self.stream.flush()
                def fileno(self):
                    return self.stream.fileno()

            def fdopen(descriptor, mode):
                stream = real_fdopen(descriptor, mode)
                return FailingStream(stream) if fault in (
                    "partial-temp-write", "short-temp-write", "temp-write-and-cleanup-failure") else stream

            def prepare(path, encoded):
                temporary = real_prepare(path, encoded)
                if fault == "metadata-before-unlink":
                    metadata.write_bytes(metadata_owner)
                if fault == "manifest-before-unlink":
                    manifest.write_bytes(manifest_owner)
                if fault == "source-before-unlink":
                    targets[0].write_bytes(source_owner)
                return temporary

            def unlink(path, *arguments, **keywords):
                if fault == "temp-write-and-cleanup-failure" and path.parent == root and path != owner_tmp:
                    check(path.name.startswith(".studio-sync-manifest.json.cleanup-"), label + ": unrelated cleanup attempted")
                    raise OSError("fixture-owned-temp-cleanup")
                result = real_unlink(path, *arguments, **keywords)
                if path in targets:
                    if fault == "metadata-after-first-unlink":
                        once("unlink-change", lambda: metadata.write_bytes(metadata_owner))
                    if fault == "manifest-after-first-unlink":
                        once("unlink-change", lambda: manifest.write_bytes(manifest_owner))
                return result

            def replace(source, destination):
                check(Path(source).parent == root and Path(destination) == manifest,
                      label + ": atomic replace escaped fixture")
                check(Path(source).read_bytes() != original_manifest and manifest.read_bytes() == original_manifest,
                      label + ": original manifest changed before commit")
                if fault == "owner-reintroduced-on-replace-failure":
                    targets[0].write_bytes(source_owner)
                    raise primary
                if fault in ("atomic-replace-failure", "rollback-write-failure"):
                    raise primary
                result = real_replace(source, destination)
                if fault == "metadata-after-atomic-commit":
                    metadata.write_bytes(metadata_owner)
                return result

            def opening(path, mode="r", *arguments, **keywords):
                if fault == "rollback-write-failure" and path == targets[0] and mode == "xb":
                    raise OSError("fixture-recovery-first-file")
                return real_open(path, mode, *arguments, **keywords)

            caught, stdout = None, io.StringIO()
            with ExitStack() as stack:
                stack.enter_context(mock.patch.object(module, "ROOT", root))
                stack.enter_context(mock.patch.object(module, "DEST", dest))
                stack.enter_context(mock.patch.object(module.subprocess, "run", compiler))
                stack.enter_context(mock.patch.object(module.os, "fdopen", fdopen))
                stack.enter_context(mock.patch.object(module.os, "replace", replace))
                stack.enter_context(mock.patch.object(module, "prepare_manifest_temp", prepare))
                stack.enter_context(mock.patch.object(Path, "unlink", unlink))
                stack.enter_context(mock.patch.object(Path, "open", opening))
                stack.enter_context(redirect_stdout(stdout))
                try:
                    module.main()
                except BaseException as error:
                    caught = error
            if expected == "primary":
                check(caught is primary, label + ": primary error replaced")
            elif expected:
                check(isinstance(caught, AssertionError) and expected in str(caught), label + ": expected guard not reached")
            else:
                check(caught is None, label + ": unexpected exception " + repr(caught))
            check(owner_file.read_bytes() == b"owner runtime source stays untouched\n", label + ": unrelated source changed")
            check(owner_tmp.read_bytes() == b"unrelated temporary file", label + ": unrelated temporary removed")
            leftovers = [path for path in root.glob(".studio-sync-manifest.json.cleanup-*.tmp") if path != owner_tmp]
            check(len(leftovers) == (1 if fault == "temp-write-and-cleanup-failure" else 0), label + ": owned temp lifecycle differs")
            committed = not fault or fault == "metadata-after-atomic-commit"
            if committed:
                check(all(not target.exists() for target in targets), label + ": committed files not retired")
                after = json.loads(manifest.read_bytes())
                before = json.loads(original_manifest)
                missing = set(json.loads(before_inputs[METADATA])["manifestOnlyPaths"])
                check(after["items"] == [row for row in before["items"] if row["studioPath"] not in missing],
                      label + ": unrelated manifest entries changed")
                for key in ("created", "updated", "unchanged", "studioTrailingNewline"):
                    check(after["counts"][key] == before["counts"][key], label + ": old sync metric changed")
                check(after["counts"]["total"] == len(after["items"]), label + ": count not recomputed")
            else:
                expected_manifest = manifest_owner if fault in ("manifest-before-unlink", "manifest-after-first-unlink") else original_manifest
                check(manifest.read_bytes() == expected_manifest, label + ": original/owner manifest lost")
                for index, (name, raw) in enumerate(source_bytes.items()):
                    target = root / name
                    if fault == "rollback-write-failure" and index == 0:
                        check(not target.exists(), label + ": injected restore failure unexpectedly succeeded")
                    else:
                        current = source_owner if index == 0 and fault in ("source-before-unlink", "owner-reintroduced-on-replace-failure") else raw
                        check(target.read_bytes() == current, label + ": deleted/concurrent source not recovered exactly")
            changed_metadata = bool(fault and fault.startswith("metadata-"))
            check(metadata.read_bytes() == (metadata_owner if changed_metadata else before_inputs[METADATA]),
                  label + ": concurrent metadata was overwritten")
            if not fault:
                receipt = json.loads((dest / "removal-receipt.json").read_bytes())
                check(receipt["nativeEvidenceSHA256"] == digest(before_inputs[METADATA]), label + ": receipt not pinned to used bytes")
                check(receipt["manifestRawBeforeSHA256"] == digest(original_manifest) and
                      receipt["manifestRawAfterSHA256"] == digest(manifest.read_bytes()), label + ": receipt manifest hashes differ")
                check(compiler_calls == ["-O0"] * 10 + ["-O1"] * 10, label + ": actual compile coverage incomplete")
                check(receipt["nativeMutations"] == 0 and receipt["studioModeChanges"] == 0, label + ": proof scope incorrect")
                check((dest / "manifest-before.json").read_bytes() == original_manifest, label + ": manifest backup differs")
                for row in receipt["archived"]:
                    check((root / row["archiveFile"]).read_bytes() == source_bytes[row["file"]], label + ": archive not byte exact")
            else:
                check(not (dest / "removal-receipt.json").exists(), label + ": failed batch certified")
            if fault == "metadata-during-initial-compiles":
                check(not dest.exists(), label + ": archive created before fresh evidence guard")
            if fault in ("rollback-write-failure", "temp-write-and-cleanup-failure"):
                notes = "\n".join(getattr(caught, "__notes__", []))
                check("fixture-recovery-first-file" in notes if fault == "rollback-write-failure" else "fixture-owned-temp-cleanup" in notes,
                      label + ": secondary cleanup error lost")
            cases.append({"name": label, "passed": True, "realLuauCompiles": 20 if real_compiles else 0})

    scenario("actual historical inputs archive and atomic commit", real_compiles=True)
    for fault in ("partial-temp-write", "atomic-replace-failure", "owner-reintroduced-on-replace-failure",
                  "rollback-write-failure", "temp-write-and-cleanup-failure"):
        scenario(fault, fault, expected="primary")
    scenario("short-temp-write", "short-temp-write", expected="Incomplete temporary manifest write")
    for fault in ("metadata-during-initial-compiles", "metadata-during-archive-compiles", "metadata-before-unlink",
                  "metadata-after-first-unlink", "metadata-after-atomic-commit"):
        scenario(fault, fault, expected="Concurrent native evidence changed")
    for fault in ("manifest-before-unlink", "source-before-unlink"):
        scenario(fault, fault, expected="Concurrent baseline changed")
    scenario("manifest-after-first-unlink", "manifest-after-first-unlink", expected="Manifest changed during batch")
    for path, raw in before_inputs.items():
        check(path.read_bytes() == raw, "Historical input or wrapper changed during temporary fixture: " + str(path))
    report = {"schema": "retire-mirror-wrapper-offline-tests-v2", "passed": True, "checks": checks,
              "caseCount": len(cases), "cases": cases, "wrapperSHA256": digest(before_inputs[WRAPPER]),
              "testSHA256": digest(Path(__file__).read_bytes()), "actualLuauCompiles": 20,
              "historicS02ReceiptSHA256": digest(before_inputs[HISTORICAL / "removal-receipt.json"]),
              "inputSHA256": {path.relative_to(ROOT).as_posix(): digest(raw) for path, raw in before_inputs.items()},
              "historicalInputsUnchanged": True, "canonicalBatchRerun": False, "noStudio": True,
              "limits": "Actual wrapper in temporary copies. Compiler real for success, mocked for fault fixtures. Ordinary guarded atomic replacement is not a lock against uncooperative concurrent writes between guard and replace. No native deletion, gameplay or serializer proof."}
    if args.receipt:
        with args.receipt.open("x", encoding="utf8", newline="\n") as stream:
            json.dump(report, stream, indent=2); stream.write("\n")
    print(json.dumps({key: report[key] for key in ("passed", "checks", "caseCount", "actualLuauCompiles", "wrapperSHA256", "historicalInputsUnchanged", "canonicalBatchRerun")}))


if __name__ == "__main__":
    main()
