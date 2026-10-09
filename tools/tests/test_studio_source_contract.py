"""Regression coverage for the shared repo <-> Studio source contract.

Runs entirely offline: no Studio, no MCP, no place file. What it drives is the
real decision code the push tool uses -- `classify_pending` and
`verify_written` -- plus the contract functions the pull audit and
record_pending_push call, so a change to any of them shows up here.

    python tools/tests/test_studio_source_contract.py
"""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import os  # noqa: E402
import subprocess  # noqa: E402

import studio_source_contract as contract  # noqa: E402
import pull_source_from_studio as pull  # noqa: E402
import push_repo_to_studio as push  # noqa: E402
import record_synced_source as record_synced  # noqa: E402
import verify_studio_parity as parity  # noqa: E402

REPO = "local x = 1\nreturn x\n"
PLUS_NEWLINE = REPO + "\n"
PLUS_TWO = REPO + "\n\n"
DRIFTED = "local x = 2\nreturn x\n"
CRLF = REPO.replace("\n", "\r\n")

FLAGGED = {"studioTrailingNewline": True}
PLAIN: dict = {}

failures: list[str] = []


def check(condition: bool, description: str, detail: str = "") -> None:
    if condition:
        print(f"  ok   {description}")
    else:
        failures.append(description)
        print(f"  FAIL {description}" + (f"  ({detail})" if detail else ""))


def item(*, flagged: bool, baseline: str) -> dict:
    entry = {
        "file": "ServerScriptService/Example.ModuleScript.lua",
        "sha256": contract.sha256_of(REPO),
        "studioSha256Before": contract.sha256_of(baseline),
    }
    if flagged:
        entry["studioTrailingNewline"] = True
    return entry


print("=== the contract itself ===")
check(contract.normalize(CRLF) == REPO, "line endings are not content")
check(contract.sha256_of(CRLF) == contract.sha256_of(REPO),
      "a CRLF working copy hashes the same as its LF blob")
check(contract.classify(REPO, REPO, allow_trailing_newline=False) == contract.EXACT,
      "an identical source is exact")
check(contract.classify(REPO, PLUS_NEWLINE, allow_trailing_newline=True)
      == contract.TRAILING_NEWLINE,
      "a FLAGGED entry tolerates exactly one extra trailing newline")
check(contract.classify(REPO, PLUS_NEWLINE, allow_trailing_newline=False)
      == contract.DRIFTED,
      "an UNFLAGGED entry does not")
check(contract.classify(REPO, PLUS_TWO, allow_trailing_newline=True) == contract.DRIFTED,
      "and even a flagged entry refuses TWO extra newlines")
check(contract.classify(REPO, REPO + " ", allow_trailing_newline=True) == contract.DRIFTED,
      "a trailing space is drift, flag or no flag")
check(contract.classify(REPO, DRIFTED, allow_trailing_newline=True) == contract.DRIFTED,
      "a changed line is drift, flag or no flag")
check(contract.permits_trailing_newline(FLAGGED) is True
      and contract.permits_trailing_newline(PLAIN) is False
      and contract.permits_trailing_newline(None) is False,
      "the manifest flag is what switches the tolerance on")
check(contract.matches_hash(contract.sha256_of(REPO), PLUS_NEWLINE,
                            allow_trailing_newline=True),
      "a recorded repo hash matches a Studio copy with the permitted newline")
check(not contract.matches_hash(contract.sha256_of(REPO), PLUS_NEWLINE,
                                allow_trailing_newline=False),
      "and does not when the entry is unflagged")

print("=== landing facts mutate the flag, never the acceptance rule ===")
landed_exact = item(flagged=True, baseline=DRIFTED)
verdict = push.record_landed_source(landed_exact, REPO, REPO)
check(verdict == contract.EXACT
      and not contract.permits_trailing_newline(landed_exact),
      "an exact verified landing removes a stale trailing-newline flag")

landed_plus = item(flagged=True, baseline=DRIFTED)
verdict = push.record_landed_source(landed_plus, REPO, PLUS_NEWLINE)
check(verdict == contract.TRAILING_NEWLINE
      and contract.permits_trailing_newline(landed_plus),
      "a verified permitted +LF landing retains the flag")

unflagged_plus = item(flagged=False, baseline=DRIFTED)
refused_unflagged_plus = False
try:
    push.record_landed_source(unflagged_plus, REPO, PLUS_NEWLINE)
except push.StudioMcpError:
    refused_unflagged_plus = True
check(refused_unflagged_plus
      and not contract.permits_trailing_newline(unflagged_plus),
      "recording cannot turn an unpermitted +LF into a new exception")

pull_entries = {
    "exact.lua": {"studioTrailingNewline": True},
    "plus.lua": {"studioTrailingNewline": True},
}
pull_changes = pull.apply_observed_newline_verdicts(
    pull_entries,
    {"exact.lua": contract.EXACT, "plus.lua": contract.TRAILING_NEWLINE},
)
check(pull_changes == 1
      and not contract.permits_trailing_newline(pull_entries["exact.lua"])
      and contract.permits_trailing_newline(pull_entries["plus.lua"]),
      "the pull audit removes only the stale exact flag and retains verified +LF")

print("=== push phase 1: classify_pending ===")
verdict, why = push.classify_pending(item(flagged=False, baseline=DRIFTED), REPO, REPO)
check(verdict == "already", "an exact match is already applied", why)
verdict, why = push.classify_pending(item(flagged=True, baseline=DRIFTED), REPO, PLUS_NEWLINE)
check(verdict == "already",
      "a flagged entry whose Studio copy has the permitted newline is already applied", why)
verdict, why = push.classify_pending(item(flagged=False, baseline=DRIFTED), REPO, PLUS_NEWLINE)
check(verdict == "conflict",
      "the same difference on an UNFLAGGED entry is a conflict", why)
verdict, why = push.classify_pending(item(flagged=False, baseline=DRIFTED), REPO, DRIFTED)
check(verdict == "ready", "Studio still holding the recorded baseline is ready", why)
verdict, why = push.classify_pending(item(flagged=True, baseline=DRIFTED),
                                     REPO, DRIFTED + "\n")
check(verdict == "ready",
      "a flagged baseline may also carry the permitted newline", why)
verdict, why = push.classify_pending(item(flagged=True, baseline=DRIFTED),
                                     REPO, "local x = 3\n")
check(verdict == "conflict", "real drift is a conflict even on a flagged entry", why)
stale = item(flagged=False, baseline=DRIFTED)
stale["sha256"] = contract.sha256_of(DRIFTED)
verdict, why = push.classify_pending(stale, REPO, DRIFTED)
check(verdict == "repo-drift",
      "a repo file that no longer matches its manifest entry is refused", why)

print("=== push phase 2: verify_written ===")
ok, why = push.verify_written(item(flagged=False, baseline=DRIFTED), REPO, REPO)
check(ok, "a byte-exact write verifies", why)
ok, why = push.verify_written(item(flagged=True, baseline=DRIFTED), REPO, PLUS_NEWLINE)
check(ok, "a flagged write that lands with the permitted newline verifies", why)
ok, why = push.verify_written(item(flagged=False, baseline=DRIFTED), REPO, PLUS_NEWLINE)
check(not ok, "the same landing on an unflagged entry FAILS the push", why)
ok, why = push.verify_written(item(flagged=True, baseline=DRIFTED), REPO, PLUS_TWO)
check(not ok, "two trailing newlines fail the push whatever the flag says", why)
ok, why = push.verify_written(item(flagged=True, baseline=DRIFTED), REPO, DRIFTED)
check(not ok, "and a truncated or altered write fails it", why)

print("=== the live manifest obeys its own schema ===")
manifest = json.loads((TOOLS.parent / "studio-sync-manifest.json").read_text(encoding="utf-8"))
flagged_entries = [i for i in manifest["items"]
                   if i.get(contract.TRAILING_NEWLINE_FLAG) is True]
check(all(i["className"] != "RemoteEvent" for i in flagged_entries),
      "only scripts carry the trailing-newline flag")
check(all(contract.sha256_of((TOOLS.parent / i["file"]).read_text(encoding="utf-8"))
          == i["sha256"] for i in flagged_entries),
      "and every flagged entry's hash is still the REPO file, not Studio's copy")

print("=== independent parity rejects wrong classes and duplicate paths ===")
parity_scratch = Path(tempfile.mkdtemp(prefix="parity-contract-"))
old_parity_root, old_parity_manifest = parity.ROOT, parity.MANIFEST
try:
    script_rel = "ServerScriptService/Example.ModuleScript.lua"
    script_path = parity_scratch / script_rel
    script_path.parent.mkdir(parents=True)
    script_path.write_text(REPO, encoding="utf-8", newline="\n")
    parity_manifest = {
        "counts": {"scripts": 1},
        "items": [{
            "studioPath": "ServerScriptService.Example",
            "className": "ModuleScript",
            "file": script_rel,
        }],
    }
    manifest_path = parity_scratch / "studio-sync-manifest.json"
    manifest_path.write_text(
        json.dumps(parity_manifest), encoding="utf-8", newline="\n")
    parity.ROOT, parity.MANIFEST = parity_scratch, manifest_path
    held = parity.fingerprint(parity.canonical(REPO))

    wrong_class_dump = parity_scratch / "wrong-class.txt"
    wrong_class_dump.write_text(
        f"ServerScriptService.Example\tLocalScript\t{held}\n",
        encoding="utf-8",
        newline="\n",
    )
    wrong_output = io.StringIO()
    with contextlib.redirect_stdout(wrong_output):
        wrong_code = parity.main(["verify_studio_parity.py", str(wrong_class_dump)])
    check(wrong_code == 1 and "class      1" in wrong_output.getvalue(),
          "a matching fingerprint with the wrong ClassName fails parity",
          wrong_output.getvalue().strip())

    duplicate_dump = parity_scratch / "duplicate.txt"
    duplicate_line = f"ServerScriptService.Example\tModuleScript\t{held}\n"
    duplicate_dump.write_text(
        duplicate_line + duplicate_line, encoding="utf-8", newline="\n")
    duplicate_refused = False
    try:
        parity.load_studio_dump(duplicate_dump)
    except SystemExit as error:
        duplicate_refused = "duplicate Studio path" in str(error)
    check(duplicate_refused,
          "a duplicate Studio full path is rejected instead of overwritten")

    correct_dump = parity_scratch / "correct.txt"
    correct_dump.write_text(duplicate_line, encoding="utf-8", newline="\n")
    with contextlib.redirect_stdout(io.StringIO()):
        correct_code = parity.main(["verify_studio_parity.py", str(correct_dump)])
    check(correct_code == 0,
          "the same source with the expected ClassName passes parity")
finally:
    parity.ROOT, parity.MANIFEST = old_parity_root, old_parity_manifest
    shutil.rmtree(parity_scratch, ignore_errors=True)

print("=== fallback bookkeeping reconciles exact and +LF landings ===")
record_scratch = Path(tempfile.mkdtemp(prefix="record-synced-contract-"))
old_record_root, old_record_manifest = record_synced.ROOT, record_synced.MANIFEST
try:
    exact_rel = "ServerScriptService/Exact.ModuleScript.lua"
    plus_rel = "ServerScriptService/Plus.ModuleScript.lua"
    for rel in (exact_rel, plus_rel):
        target = record_scratch / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(REPO, encoding="utf-8", newline="\n")
    record_manifest = {
        "counts": {"scripts": 2, "remoteEvents": 0, "total": 2,
                   "studioTrailingNewline": 2},
        "items": [
            {"studioPath": "ServerScriptService.Exact", "className": "ModuleScript",
             "file": exact_rel, "studioTrailingNewline": True},
            {"studioPath": "ServerScriptService.Plus", "className": "ModuleScript",
             "file": plus_rel, "studioTrailingNewline": True},
        ],
    }
    record_manifest_path = record_scratch / "studio-sync-manifest.json"
    record_manifest_path.write_text(
        json.dumps(record_manifest), encoding="utf-8", newline="\n")
    record_dump = record_scratch / "studio-dump.txt"
    record_dump.write_text(
        "ServerScriptService.Exact\tModuleScript\t"
        f"{parity.fingerprint(parity.canonical(REPO))}\n"
        "ServerScriptService.Plus\tModuleScript\t"
        f"{parity.fingerprint(parity.canonical(PLUS_NEWLINE))}\n",
        encoding="utf-8",
        newline="\n",
    )
    record_synced.ROOT, record_synced.MANIFEST = record_scratch, record_manifest_path
    with contextlib.redirect_stdout(io.StringIO()):
        record_code = record_synced.main(
            ["record_synced_source.py", str(record_dump), exact_rel, plus_rel]
        )
    recorded = json.loads(record_manifest_path.read_text(encoding="utf-8"))
    recorded_by_file = {entry["file"]: entry for entry in recorded["items"]}
    check(record_code == 0
          and not contract.permits_trailing_newline(recorded_by_file[exact_rel]),
          "record_synced_source removes the flag for an exact fallback landing")
    check(contract.permits_trailing_newline(recorded_by_file[plus_rel]),
          "record_synced_source retains the flag for a permitted +LF landing")
    check(recorded["counts"][contract.TRAILING_NEWLINE_FLAG] == 1
          and "count: 1" in recorded["finalNewlineContract"],
          "fallback bookkeeping republishes the reconciled flag count")
finally:
    record_synced.ROOT, record_synced.MANIFEST = old_record_root, old_record_manifest
    shutil.rmtree(record_scratch, ignore_errors=True)

print("=== the release tools print on a default Windows console ===")
# `--help` renders the module docstring through argparse. A cp1252 console
# cannot represent an arrow or an em dash, and the tool used to die with
# UnicodeEncodeError before printing a word of it -- so a release tool could not
# show its own help without PYTHONUTF8 set.
for tool in ("push_repo_to_studio", "pull_source_from_studio",
             "record_pending_push", "sync_from_studio"):
    environment = dict(os.environ, PYTHONIOENCODING="cp1252")
    completed = subprocess.run(
        [sys.executable, str(TOOLS / f"{tool}.py"), "--help"],
        capture_output=True, env=environment)
    check(completed.returncode == 0,
          f"{tool} --help survives a cp1252 console",
          completed.stderr.decode("utf-8", "replace")[-160:])

print()
if failures:
    print(f"FAILED: {len(failures)} of the checks above")
    for name in failures:
        print(f"  - {name}")
    sys.exit(1)
print("All contract checks passed.")
