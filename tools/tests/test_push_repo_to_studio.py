"""End-to-end test of tools/push_repo_to_studio.py against a fake Studio.

Dev-only: touches nothing in the game and never contacts a real Studio. It runs
the push tool's ACTUAL generated Luau through the real luau interpreter against
a stubbed DataModel, so chunking, escaping, verification, conflict detection,
compare-and-swap and buffer cleanup are all exercised for real.

    LUAU_BIN=/path/to/luau python tools/tests/test_push_repo_to_studio.py
    python tools/tests/test_push_repo_to_studio.py --fixture-only

THE PENDING QUEUE IS SYNTHESIZED. The real studio-sync-manifest.json holds no
`pending-studio-push` entries (everything landed in Studio on 2026-08-19), so a
suite that simply copied it had nothing to push: every `seed()` was a no-op,
every `main()` returned "Nothing pending", and the first `max(pending, ...)`
died on an empty sequence before TEST 2 ever ran. `fresh_repo()` therefore
rewrites its THROWAWAY copy of the manifest: a fixed list of scripts is flipped
to `pending-studio-push`, the temp copy of each of those files gets one extra
comment line appended, and `sha256`/`bytes`/`studioSha256Before` are recomputed
exactly the way tools/record_pending_push.py would -- through the shared
tools/studio_source_contract.py helpers, so there is still only one definition
of the hash. The real manifest and the real working tree are never written to.

The fake Studio is then seeded with the BASELINE content (what the manifest says
Studio still holds), honouring the `studioTrailingNewline` contract: a flagged
entry's Studio copy is the repo text plus exactly one "\\n".

`--fixture-only` builds that repo, proves its invariants and exits -- no luau
needed, so the fixture itself is verifiable on a machine that cannot run the
interpreter. Without the flag the suite needs a real luau binary; if it is
missing every TEST is still ENUMERATED, the fifteen that reach Studio are
reported as "not executed", the two that never do (TEST 8, TEST 15) still run,
and the whole run exits NON-ZERO. It never looks green without having run.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Iterable

SCRATCH = Path(__file__).resolve().parent
TOOLS = SCRATCH.parent
REPO = SCRATCH.parents[1]

sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(SCRATCH))

import fakestudio  # noqa: E402
from studio_source_contract import (  # noqa: E402
    canonical_bytes,
    matches_hash,
    normalize,
    permits_trailing_newline,
    sha256_of,
)

MANIFEST_NAME = "studio-sync-manifest.json"
REAL_MANIFEST_TEXT = (REPO / MANIFEST_NAME).read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# The synthesized queue.
# ---------------------------------------------------------------------------
# Chosen for spread, not at random: 1 KB to 242 KB, all three script classes,
# two entries flagged studioTrailingNewline, two paths containing spaces. The
# four marked (required) are addressed by name inside the tests below, so the
# suite cannot run without them.
QUEUE_FILES = [
    # required by TEST 7 / TEST 16 (spaces, backslashes) and TEST 1 (largest)
    "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua",
    # required by TESTS 2, 6, 9, 10, 11, 12
    "ServerScriptService/GameManager.Script.lua",
    "ServerScriptService/EntityAI.Script.lua",
    "ReplicatedStorage/UIDevice.ModuleScript.lua",
    # studioTrailingNewline entry, with spaces in the path
    "ServerScriptService/Level 2 Systems/Level 2 Round Adapter.ModuleScript.lua",
    # required by TEST 6 (the script deliberately missing from Studio)
    "ServerScriptService/EntityKill.Script.lua",
    # studioTrailingNewline entry
    "StarterPlayer/StarterPlayerScripts/Level 2 Objective UI.LocalScript.lua",
    # required by TEST 5 (hostile content round-trip)
    "StarterPlayer/StarterCharacterScripts/DanceEmote.LocalScript.lua",
    "ReplicatedStorage/DevAccess.ModuleScript.lua",
]

# These are fixture facts, not production-manifest facts. Exact Studio landings
# legitimately remove transport-newline flags over time, so the test must not
# lose coverage merely because the current release happens to have no flagged
# entry among QUEUE_FILES.
FIXTURE_TRAILING_NEWLINE_FILES = {
    "ServerScriptService/Level 2 Systems/Level 2 Round Adapter.ModuleScript.lua",
    "StarterPlayer/StarterPlayerScripts/Level 2 Objective UI.LocalScript.lua",
}

REQUIRED_BY_TESTS = [
    "ServerScriptService/GameManager.Script.lua",
    "StarterPlayer/StarterCharacterScripts/DanceEmote.LocalScript.lua",
    "ServerScriptService/EntityKill.Script.lua",
    "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua",
]

# The one edit that makes every queued file "pending": deterministic, so a
# re-run produces byte-identical hashes.
EDIT_MARKER = "-- pushtest: synthesized pending edit"
FIXTURE_NAME = "pushtest-fixture.json"

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
failures: list[str] = []
passes: list[str] = []
executed: list[str] = []
not_executed: list[tuple[str, str]] = []
CURRENT = {"label": "FIXTURE"}


class CheckFailure(Exception):
    """A check that cannot even be evaluated -- reported, never propagated."""


def check(name: str, condition: bool, detail: str = "") -> None:
    label = f"{CURRENT['label']}: {name}"
    (passes if condition else failures).append(
        f"{label}{(' -- ' + detail) if detail else ''}")
    # "[]" is the empty offender list a passing aggregate check produces; it is
    # noise on a PASS line and misleading on a FAIL line.
    shown = "" if (condition and detail in ("", "[]")) else detail
    print(("  PASS  " if condition else "  FAIL  ") + name
          + (f"  [{shown}]" if shown else ""))


def require_item(items: Iterable[dict], predicate: Callable[[dict], bool],
                 label: str) -> dict:
    """`next(i for i in items if ...)` that reports instead of exploding.

    Every StopIteration/ValueError in the original suite came from filtering a
    pending queue that was empty. A missing item is a fixture bug worth naming,
    not a traceback that kills the remaining sixteen tests.
    """
    pool = list(items)
    for item in pool:
        if predicate(item):
            return item
    raise CheckFailure(
        f"{label}: no matching entry among {len(pool)} candidate(s) "
        f"({[i.get('file') for i in pool][:4]})")


def require_max(items: Iterable[dict], key: Callable[[dict], object],
                label: str) -> dict:
    pool = list(items)
    if not pool:
        raise CheckFailure(f"{label}: empty sequence, nothing to take the max of")
    return max(pool, key=key)  # type: ignore[arg-type,return-value]


SHARED: dict[str, object] = {}


def require_shared(key: str, label: str) -> object:
    if key not in SHARED:
        raise CheckFailure(
            f"{label}: needs '{key}' from an earlier TEST, which did not complete")
    return SHARED[key]


# ---------------------------------------------------------------------------
# The luau interpreter
# ---------------------------------------------------------------------------
def detect_luau() -> tuple[Path | None, str]:
    """Resolve fakestudio's interpreter once, and prove it actually runs."""
    candidate = fakestudio.LUAU
    resolved: Path | None = None
    if candidate.is_file():
        resolved = candidate
    else:
        found = shutil.which(str(candidate)) or shutil.which(candidate.name)
        if found:
            resolved = Path(found)
    if resolved is None:
        return None, (f"no interpreter file at {candidate} and nothing named "
                      f"'{candidate.name}' on PATH")
    try:
        proc = subprocess.run([str(resolved), "--version"],
                              capture_output=True, text=True, timeout=60)
    except OSError as error:
        return None, f"{resolved} exists but could not be executed: {error}"
    if proc.returncode != 0:
        return None, (f"{resolved} --version exited {proc.returncode}: "
                      f"{(proc.stderr or proc.stdout).strip()[:200]}")
    return resolved, (proc.stdout or proc.stderr or "").strip()


LUAU_PATH: Path | None = None
LUAU_REASON = ""
LUAU_AVAILABLE = False


def banner(lines: list[str]) -> None:
    width = max(len(line) for line in lines) + 8
    print("#" * width)
    for line in lines:
        print("##  " + line.ljust(width - 6) + "##")
    print("#" * width)


# ---------------------------------------------------------------------------
# Fixture construction
# ---------------------------------------------------------------------------
def load_tool(repo_root: Path):
    """Import push_repo_to_studio with PROJECT_ROOT pointed at a scratch repo."""
    spec = importlib.util.spec_from_file_location(
        "push_repo_to_studio", repo_root / "tools" / "push_repo_to_studio.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["push_repo_to_studio"] = module
    spec.loader.exec_module(module)
    module.PROJECT_ROOT = repo_root
    module.MANIFEST_PATH = repo_root / MANIFEST_NAME
    return module


def modified_text(baseline: str, file: str) -> str:
    """The 'newer repo copy' of a queued file. Deterministic on purpose."""
    body = baseline
    if body and not body.endswith("\n"):
        body += "\n"
    return f"{body}{EDIT_MARKER} ({file})\n"


def fresh_repo() -> Path:
    """A throwaway repo copy WITH A SYNTHESIZED PENDING QUEUE.

    The real manifest is read, never written. Queued entries are rewritten the
    way record_pending_push.py rewrites them:
        studioSha256Before = sha256_of(baseline)      # what Studio still holds
        sha256             = sha256_of(modified)      # the newer repo copy
        bytes              = len(canonical_bytes(modified))
        status             = "pending-studio-push"
    and the temp copy of the file on disk is replaced by that modified content,
    so the entry is genuinely pending rather than merely labelled so.
    """
    workdir = Path(tempfile.mkdtemp(prefix="pushtest-"))
    target = workdir / "repo"
    target.mkdir()
    shutil.copytree(REPO / "tools", target / "tools")
    manifest = json.loads(REAL_MANIFEST_TEXT)
    # The fixture is intentionally independent of whatever release work is in
    # progress in the real checkout. Start the temporary manifest from a neutral
    # queue state, then synthesize exactly QUEUE_FILES below.
    for item in manifest["items"]:
        item["status"] = "synced"
        item.pop("studioSha256Before", None)
    for item in manifest["items"]:
        source = REPO / item["file"]
        if source.exists():
            destination = target / item["file"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)

    by_file = {i["file"]: i for i in manifest["items"]}
    queue: dict[str, dict] = {}
    for file in QUEUE_FILES:
        item = by_file.get(file)
        if item is None:
            raise CheckFailure(f"fixture: {file} is not in the manifest at all")
        if not (REPO / file).exists():
            raise CheckFailure(f"fixture: {file} is in the manifest but not on disk")
        if file in FIXTURE_TRAILING_NEWLINE_FILES:
            item["studioTrailingNewline"] = True
        else:
            item.pop("studioTrailingNewline", None)
        baseline = normalize((REPO / file).read_text(encoding="utf-8"))
        flagged = permits_trailing_newline(item)
        # The trailing-newline contract: for a flagged entry, and only a flagged
        # entry, Studio's copy is the repo text plus exactly one "\n".
        seeded = baseline + "\n" if flagged else baseline
        newer = modified_text(baseline, file)
        (target / file).write_bytes(canonical_bytes(newer))
        item["studioSha256Before"] = sha256_of(baseline)
        item["sha256"] = sha256_of(newer)
        item["bytes"] = len(canonical_bytes(newer))
        item["status"] = "pending-studio-push"
        queue[file] = {
            "studioPath": item["studioPath"],
            "className": item["className"],
            "baseline": baseline,
            "seeded": seeded,
            "trailingNewline": flagged,
        }

    (target / MANIFEST_NAME).write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    (workdir / FIXTURE_NAME).write_text(
        json.dumps({"queue": queue}), encoding="utf-8", newline="\n")
    return target


_FIXTURE_CACHE: dict[str, dict] = {}


def fixture_of(repo_root: Path) -> dict:
    key = str(repo_root)
    if key not in _FIXTURE_CACHE:
        path = repo_root.parent / FIXTURE_NAME
        if not path.exists():
            raise CheckFailure(f"fixture record missing next to {repo_root}")
        _FIXTURE_CACHE[key] = json.loads(path.read_text(encoding="utf-8"))["queue"]
    return _FIXTURE_CACHE[key]


def seeded_text(repo_root: Path, file: str) -> str:
    """Exactly what the fake Studio was seeded with for this file."""
    entry = fixture_of(repo_root).get(file)
    if entry is None:
        raise CheckFailure(f"no synthesized baseline for {file}")
    return entry["seeded"]


def repo_text(repo_root: Path, file: str) -> str:
    return normalize((repo_root / file).read_text(encoding="utf-8"))


def pending_items(repo_root: Path) -> list[dict]:
    manifest = json.loads((repo_root / MANIFEST_NAME).read_text(encoding="utf-8"))
    return [i for i in manifest["items"] if i.get("status") == "pending-studio-push"]


def seed(studio: fakestudio.FakeStudio, items: list[dict], repo_root: Path,
         overrides: dict[str, str] | None = None) -> None:
    overrides = overrides or {}
    for item in items:
        file = item["file"]
        content = overrides[file] if file in overrides else seeded_text(repo_root, file)
        studio.add_script(item["studioPath"], item["className"], content)


# ---------------------------------------------------------------------------
# Fixture verification (no luau required)
# ---------------------------------------------------------------------------
def verify_fixture(repo_root: Path) -> None:
    manifest = json.loads((repo_root / MANIFEST_NAME).read_text(encoding="utf-8"))
    items = manifest["items"]
    pending = [i for i in items if i.get("status") == "pending-studio-push"]
    queue = fixture_of(repo_root)
    tool = load_tool(repo_root)

    print("This queue is SYNTHESIZED by fresh_repo() inside a temp copy;")
    print("nothing here reflects live Studio or the real manifest's current")
    print("queue state, and the real manifest is only ever read.")
    print(f"synthesized pending entries: {len(pending)} of {len(items)} manifest items")
    for item in sorted(pending, key=lambda i: -i["bytes"]):
        flag = "  studioTrailingNewline" if permits_trailing_newline(item) else ""
        print(f"    {item['bytes']:>7}B  {item['className']:<12} {item['file']}{flag}")

    check("the queue is not empty (the defect this fixture exists to fix)",
          bool(pending), f"{len(pending)} pending")
    check("the queue has exactly the size fresh_repo() intended",
          len(pending) == len(QUEUE_FILES),
          f"{len(pending)} pending vs {len(QUEUE_FILES)} requested")
    check("live pending statuses cannot leak into the synthesized queue",
          {item["file"] for item in pending} == set(queue),
          str(sorted({item["file"] for item in pending} - set(queue))[:3]))

    missing_required = [f for f in REQUIRED_BY_TESTS
                        if f not in {i["file"] for i in pending}]
    check("every file the tests address by name is queued",
          not missing_required, str(missing_required))

    bad_class = [i["file"] for i in pending
                 if i.get("className") not in tool.SCRIPT_CLASSES]
    check("every queued entry is a script class the push tool accepts",
          not bad_class, str(bad_class[:3]))

    bad_baseline, bad_seed, bad_contract = [], [], []
    bad_sha, bad_bytes, not_really_pending = [], [], []
    not_ready, not_conflict = [], []
    for item in pending:
        record = queue.get(item["file"])
        if record is None:
            bad_baseline.append((item["file"], "no fixture record"))
            continue
        baseline, seeded = record["baseline"], record["seeded"]
        flagged = permits_trailing_newline(item)

        # (a) studioSha256Before IS the sha of the baseline the fake Studio holds.
        if sha256_of(baseline) != item.get("studioSha256Before"):
            bad_baseline.append((item["file"], "studioSha256Before != sha(baseline)"))
        # (b) the trailing-newline contract, spelled out rather than assumed.
        expected_seed = baseline + "\n" if flagged else baseline
        if seeded != expected_seed:
            bad_seed.append((item["file"],
                             "flagged" if flagged else "unflagged"))
        # (c) and the tool's own comparison agrees the seed matches the baseline.
        if not matches_hash(item["studioSha256Before"], seeded,
                            allow_trailing_newline=flagged):
            bad_contract.append(item["file"])

        # (d)/(e) the entry describes the MODIFIED file that is really on disk.
        disk = repo_text(repo_root, item["file"])
        if sha256_of(disk) != item["sha256"]:
            bad_sha.append(item["file"])
        if len(canonical_bytes(disk)) != item["bytes"]:
            bad_bytes.append(item["file"])
        # (f) pending means DIFFERENT. An entry equal to its baseline is a lie.
        if disk == baseline:
            not_really_pending.append(item["file"])

        # (g) the real decision function calls this pushable...
        verdict, why = tool.classify_pending(item, disk, seeded)
        if verdict != "ready":
            not_ready.append((item["file"], verdict, why[:60]))
        # (h) ...and calls a drifted Studio a conflict, so "ready" means something.
        verdict2, _ = tool.classify_pending(item, disk, seeded + "\n-- drift\n")
        if verdict2 != "conflict":
            not_conflict.append((item["file"], verdict2))

    check("every studioSha256Before is the sha of the baseline the fake Studio "
          "is seeded with", not bad_baseline, str(bad_baseline[:3]))
    check("flagged entries are seeded with the repo text plus exactly one "
          "newline; unflagged with the text itself", not bad_seed, str(bad_seed[:3]))
    check("studio_source_contract.matches_hash accepts every seeded baseline",
          not bad_contract, str(bad_contract[:3]))
    check("every pending entry's sha256 matches the modified file on disk",
          not bad_sha, str(bad_sha[:3]))
    check("every pending entry's bytes matches the modified file on disk",
          not bad_bytes, str(bad_bytes[:3]))
    check("every pending entry really differs from its baseline",
          not not_really_pending, str(not_really_pending[:3]))
    check("push_repo_to_studio.classify_pending returns 'ready' for all of them",
          not not_ready, str(not_ready[:2]))
    check("...and 'conflict' once the fake Studio drifts",
          not not_conflict, str(not_conflict[:2]))

    leaked = [i["file"] for i in items
              if i.get("status") != "pending-studio-push"
              and "studioSha256Before" in i]
    check("no non-pending entry carries a stray studioSha256Before",
          not leaked, str(leaked[:3]))

    largest = require_max(pending, lambda i: i["bytes"], "fixture largest entry")
    check("the queue spans a wide size range (TEST 1's 'largest file' check "
          "needs a real spread)",
          largest["bytes"] > 100_000
          and min(i["bytes"] for i in pending) < 5_000,
          f"{min(i['bytes'] for i in pending)}B .. {largest['bytes']}B "
          f"({largest['file'].split('/')[-1]})")
    classes = {i["className"] for i in pending}
    check("the queue covers Script, LocalScript and ModuleScript",
          classes == {"Script", "LocalScript", "ModuleScript"}, str(sorted(classes)))
    flagged_count = sum(1 for i in pending if permits_trailing_newline(i))
    check("the queue includes studioTrailingNewline entries",
          flagged_count >= 1, f"{flagged_count} flagged")

    check("the REAL manifest was not modified while building the fixture",
          (REPO / MANIFEST_NAME).read_text(encoding="utf-8") == REAL_MANIFEST_TEXT)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
#: (number, title, function, needs_luau)
TESTS: list[tuple[int, str, Callable[[], None], bool]] = []


def test(number: int, title: str, *, needs_luau: bool = True):
    """Register a test. `needs_luau=False` marks one that never reaches Studio.

    --list and an unmatched --file both return before push_repo_to_studio builds
    a client, so those two are real coverage even on a machine with no
    interpreter. Everything else is reported as "not executed" there.
    """
    def register(fn):
        TESTS.append((number, title, fn, needs_luau))
        return fn
    return register


@test(1, "full push of all pending scripts (happy path)")
def test_full_push() -> None:
    repo1 = fresh_repo()
    tool1 = load_tool(repo1)
    SHARED["tool1"] = tool1
    studio1 = fakestudio.FakeStudio()
    items1 = pending_items(repo1)
    seed(studio1, items1, repo1)
    fakestudio.install(tool1, studio1)

    sys.argv = ["push_repo_to_studio.py"]
    exit_code = tool1.main()
    check("tool exited 0", exit_code == 0, f"exit={exit_code}")
    check("no Luau runtime errors", not studio1.luau_errors, str(studio1.luau_errors[:2]))

    wrong = [i["file"] for i in items1
             if studio1.source_of(i["studioPath"]) != repo_text(repo1, i["file"])]
    check(f"all {len(items1)} scripts byte-identical in Studio afterwards",
          not wrong, f"{len(wrong)} wrong: {wrong[:3]}")

    manifest1 = json.loads((repo1 / MANIFEST_NAME).read_text(encoding="utf-8"))
    still_pending = [i["file"] for i in manifest1["items"]
                     if i.get("status") == "pending-studio-push"]
    leftover_baseline = [i["file"] for i in manifest1["items"]
                         if "studioSha256Before" in i]
    check("manifest: nothing left pending", not still_pending, str(still_pending[:3]))
    check("manifest: studioSha256Before cleared", not leftover_baseline,
          str(leftover_baseline[:3]))
    queued_files = {item["file"] for item in items1}
    stale_queue_flags = [
        item["file"] for item in manifest1["items"]
        if item["file"] in queued_files and permits_trailing_newline(item)
    ]
    check("manifest: exact writes remove historical trailing-newline flags",
          not stale_queue_flags, str(stale_queue_flags[:3]))
    check("manifest: published trailing-newline count matches item facts",
          manifest1["counts"]["studioTrailingNewline"]
          == sum(1 for item in manifest1["items"]
                 if permits_trailing_newline(item)))

    buffers = [p for p in studio1.objects if p[-1] == "__RepoPushBuffer"]
    check("no transfer buffer left behind in ServerStorage", not buffers, str(buffers))

    biggest = require_max(items1, lambda i: i["bytes"], "TEST 1 largest pending file")
    check(f"largest file transferred intact ({biggest['file'].split('/')[-1]}, "
          f"{biggest['bytes']}B)",
          studio1.source_of(biggest["studioPath"]) == repo_text(repo1, biggest["file"]))
    print(f"  (luau invocations: {studio1.calls})")


@test(2, "conflict detection: Studio drifted since the baseline")
def test_conflict() -> None:
    repo2 = fresh_repo()
    tool2 = load_tool(repo2)
    studio2 = fakestudio.FakeStudio()
    items2 = pending_items(repo2)
    victim = require_item(items2, lambda i: i["file"].endswith("GameManager.Script.lua"),
                          "TEST 2 victim (GameManager)")
    drifted = seeded_text(repo2, victim["file"]) + "\n-- someone edited this in Studio\n"
    seed(studio2, items2, repo2, overrides={victim["file"]: drifted})
    fakestudio.install(tool2, studio2)
    sys.argv = ["push_repo_to_studio.py"]
    exit2 = tool2.main()
    check("tool signals failure when a file conflicts", exit2 == 1, f"exit={exit2}")
    check("conflicting file was NOT overwritten",
          studio2.source_of(victim["studioPath"]) == drifted)
    manifest2 = json.loads((repo2 / MANIFEST_NAME).read_text(encoding="utf-8"))
    conflicted_entry = require_item(manifest2["items"],
                                    lambda i: i["file"] == victim["file"],
                                    "TEST 2 conflicted manifest entry")
    check("conflicting entry recorded as studio-push-conflict with baseline kept",
          conflicted_entry.get("status") == "studio-push-conflict"
          and "studioSha256Before" in conflicted_entry,
          str(conflicted_entry.get("status")))
    check("DEFAULT: nothing at all was written when a conflict exists",
          all(studio2.source_of(i["studioPath"]) == seeded_text(repo2, i["file"])
              for i in items2 if i["file"] != victim["file"]),
          "two-phase abort")


@test(3, "idempotency: re-running after a successful push")
def test_idempotent() -> None:
    tool1 = require_shared("tool1", "TEST 3")
    sys.argv = ["push_repo_to_studio.py"]
    exit3 = tool1.main()  # type: ignore[attr-defined]
    check("second run is a clean no-op", exit3 == 0, f"exit={exit3}")


@test(4, "already-applied (Studio already has the new content)")
def test_already_applied() -> None:
    repo4 = fresh_repo()
    tool4 = load_tool(repo4)
    studio4 = fakestudio.FakeStudio()
    items4 = pending_items(repo4)
    seed(studio4, items4, repo4, overrides={
        item["file"]: repo_text(repo4, item["file"])
        + ("\n" if permits_trailing_newline(item) else "")
        for item in items4
    })
    fakestudio.install(tool4, studio4)
    sys.argv = ["push_repo_to_studio.py"]
    exit4 = tool4.main()
    check("already-applied files are accepted, not treated as conflicts",
          exit4 == 0, f"exit={exit4}")
    manifest4 = json.loads((repo4 / MANIFEST_NAME).read_text(encoding="utf-8"))
    check("already-applied entries marked synced",
          not [i for i in manifest4["items"]
               if i.get("status") == "pending-studio-push"])
    by_file4 = {item["file"]: item for item in manifest4["items"]}
    lost_permitted_flags = [
        item["file"] for item in items4
        if permits_trailing_newline(item)
        and not permits_trailing_newline(by_file4[item["file"]])
    ]
    check("already-applied +LF sources retain their permitted flags",
          not lost_permitted_flags, str(lost_permitted_flags[:3]))


HOSTILE_CASES = {
    "unicode + emoji": 'local s = "héllo — 🎃 ✓ ünïcode"\nprint(s)\n',
    "quotes and backslashes": 'local s = "a\\"b\\\\c"\nlocal t = [[raw \\ string]]\nprint(s, t)\n',
    "control chars": 'local s = "tab\\there\\nnewline"\nprint(s)\n',
    "no trailing newline": 'print("no trailing newline")',
    "blank lines + trailing newlines": 'print(1)\n\n\n\nprint(2)\n\n',
    "empty file": "",
    "long single line": 'local x = "' + ("A" * 90000) + '"\n',
    "many lines": "\n".join(f"print({n})" for n in range(4000)) + "\n",
    "percent signs": 'local f = string.format("%d%% of %s", 50, "x")\nprint(f)\n',
    "luau string edge": 'local s = "\\\\" .. "\\"" .. [==[nested ]] here]==]\nprint(s)\n',
}


@test(5, "hostile content round-trip (unicode, escapes, CRLF, empty, huge)")
def test_hostile_content() -> None:
    for label, content in HOSTILE_CASES.items():
        try:
            repo_case = fresh_repo()
            tool_case = load_tool(repo_case)
            studio_case = fakestudio.FakeStudio()
            entry = require_item(
                pending_items(repo_case),
                lambda i: i["file"].endswith("DanceEmote.LocalScript.lua"),
                f"TEST 5 target for {label!r}")
            # write the hostile content and re-record the manifest entry for it
            (repo_case / entry["file"]).write_bytes(canonical_bytes(content))
            manifest_case = json.loads(
                (repo_case / MANIFEST_NAME).read_text(encoding="utf-8"))
            for item in manifest_case["items"]:
                if item["file"] == entry["file"]:
                    item["bytes"] = len(canonical_bytes(content))
                    item["sha256"] = sha256_of(content)
                elif item.get("status") == "pending-studio-push":
                    item["status"] = "synced"
                    item.pop("studioSha256Before", None)
            (repo_case / MANIFEST_NAME).write_text(
                json.dumps(manifest_case, indent=2) + "\n",
                encoding="utf-8", newline="\n")

            studio_case.add_script(entry["studioPath"], entry["className"],
                                   seeded_text(repo_case, entry["file"]))
            fakestudio.install(tool_case, studio_case)
            sys.argv = ["push_repo_to_studio.py"]
            code = tool_case.main()
            landed = studio_case.source_of(entry["studioPath"])
            check(f"round-trip: {label}", code == 0 and landed == content,
                  f"exit={code}, len {len(landed or '')} vs {len(content)}")
        except CheckFailure as error:
            check(f"round-trip: {label}", False, str(error))
        except Exception as error:  # noqa: BLE001
            check(f"round-trip: {label}", False,
                  f"raised {type(error).__name__}: {error}")


@test(6, "script missing from Studio (renamed/deleted)")
def test_missing_script() -> None:
    repo6 = fresh_repo()
    tool6 = load_tool(repo6)
    studio6 = fakestudio.FakeStudio()
    items6 = pending_items(repo6)
    require_item(items6, lambda i: i["file"].endswith("EntityKill.Script.lua"),
                 "TEST 6 script withheld from Studio")
    seed(studio6, [i for i in items6 if not i["file"].endswith("EntityKill.Script.lua")],
         repo6)
    fakestudio.install(tool6, studio6)
    sys.argv = ["push_repo_to_studio.py", "--file",
                "ServerScriptService/GameManager.Script.lua"]
    code6 = tool6.main()
    check("--file with a present script still works", code6 == 0, f"exit={code6}")


@test(7, "--file with spaces in the path")
def test_file_with_spaces() -> None:
    repo7 = fresh_repo()
    tool7 = load_tool(repo7)
    studio7 = fakestudio.FakeStudio()
    items7 = pending_items(repo7)
    seed(studio7, items7, repo7)
    fakestudio.install(tool7, studio7)
    spacey = "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua"
    spacey_item = require_item(items7, lambda i: i["file"] == spacey,
                               "TEST 7 spacey pending entry")
    sys.argv = ["push_repo_to_studio.py", "--file", spacey]
    code7 = tool7.main()
    check("--file handles paths containing spaces", code7 == 0, f"exit={code7}")
    check("that one file was pushed",
          studio7.source_of(spacey_item["studioPath"]) == repo_text(repo7, spacey))
    untouched = pending_items(repo7)
    check("other files left pending (not pushed)", len(untouched) == len(items7) - 1,
          f"{len(untouched)} pending of {len(items7)}")


@test(8, "--list must never write", needs_luau=False)
def test_list_never_writes() -> None:
    repo8 = fresh_repo()
    tool8 = load_tool(repo8)
    studio8 = fakestudio.FakeStudio()
    items8 = pending_items(repo8)
    check("--list has something to list", len(items8) > 0, f"{len(items8)} pending")
    seed(studio8, items8, repo8)
    fakestudio.install(tool8, studio8)
    before_manifest = (repo8 / MANIFEST_NAME).read_text(encoding="utf-8")
    sys.argv = ["push_repo_to_studio.py", "--list"]
    code8 = tool8.main()
    check("--list exits 0", code8 == 0, f"exit={code8}")
    check("--list made zero Studio calls", studio8.calls == 0, f"{studio8.calls} calls")
    check("--list left the manifest untouched",
          (repo8 / MANIFEST_NAME).read_text(encoding="utf-8") == before_manifest)


@test(9, "--skip-conflicts pushes the clean files, leaves the conflict")
def test_skip_conflicts() -> None:
    repo9 = fresh_repo()
    tool9 = load_tool(repo9)
    studio9 = fakestudio.FakeStudio()
    items9 = pending_items(repo9)
    victim9 = require_item(items9, lambda i: i["file"].endswith("GameManager.Script.lua"),
                           "TEST 9 victim (GameManager)")
    drift9 = seeded_text(repo9, victim9["file"]) + "\n-- edited in Studio\n"
    seed(studio9, items9, repo9, overrides={victim9["file"]: drift9})
    fakestudio.install(tool9, studio9)
    sys.argv = ["push_repo_to_studio.py", "--skip-conflicts"]
    code9 = tool9.main()
    check("--skip-conflicts still reports failure", code9 == 1, f"exit={code9}")
    check("conflicting file untouched", studio9.source_of(victim9["studioPath"]) == drift9)
    clean_ok = all(
        studio9.source_of(i["studioPath"]) == repo_text(repo9, i["file"])
        for i in items9 if i["file"] != victim9["file"])
    check("all clean files pushed", clean_ok)
    m9 = json.loads((repo9 / MANIFEST_NAME).read_text(encoding="utf-8"))
    c9 = require_item(m9["items"], lambda i: i["file"] == victim9["file"],
                      "TEST 9 conflicted manifest entry")
    check("conflict recorded as studio-push-conflict (baseline preserved)",
          c9.get("status") == "studio-push-conflict" and "studioSha256Before" in c9,
          str(c9.get("status")))


@test(10, "--overwrite-conflicts")
def test_overwrite_conflicts() -> None:
    repo10 = fresh_repo()
    tool10 = load_tool(repo10)
    studio10 = fakestudio.FakeStudio()
    items10 = pending_items(repo10)
    SHARED["repo10"] = repo10
    SHARED["items10"] = items10
    victim10 = require_item(items10,
                            lambda i: i["file"].endswith("GameManager.Script.lua"),
                            "TEST 10 victim (GameManager)")
    SHARED["victim10"] = victim10
    seed(studio10, items10, repo10,
         overrides={victim10["file"]: seeded_text(repo10, victim10["file"]) + "\n-- drift\n"})
    fakestudio.install(tool10, studio10)
    sys.argv = ["push_repo_to_studio.py", "--overwrite-conflicts"]
    code10 = tool10.main()
    check("--overwrite-conflicts succeeds", code10 == 0, f"exit={code10}")
    check("drifted file overwritten with repo content",
          studio10.source_of(victim10["studioPath"])
          == repo_text(repo10, victim10["file"]))


@test(11, "truncated staged transfer must abort BEFORE writing")
def test_truncated_transfer() -> None:
    repo11 = fresh_repo()
    tool11 = load_tool(repo11)
    studio11 = fakestudio.FakeStudio()
    items11 = pending_items(repo11)
    seed(studio11, items11, repo11)
    fakestudio.install(tool11, studio11)
    gm11 = require_item(items11, lambda i: i["file"].endswith("GameManager.Script.lua"),
                        "TEST 11 target (GameManager)")

    original_execute = studio11.execute
    state = {"dropped": False}

    # NB: the append statement is `tail.Value = tail.Value .. chunk` (the staged
    # buffer spills into numbered child parts above BUFFER_PART_MAX). The old
    # version of this test spliced on "buffer.Value = buffer.Value ..", a string
    # that has not appeared in the tool since the spill was added -- so the
    # injection never fired and the test passed without simulating anything.
    APPEND = "tail.Value = tail.Value .."
    TOTAL = """tail.Value = tail.Value .. ""
local total = #buffer.Value
for i = 1, parts do
    local part = buffer:FindFirstChild(tostring(i))
    if part then total += #part.Value end
end
return tostring(total)
"""

    def lossy(code):
        # silently drop the payload of one buffer append (simulates a short write)
        if APPEND in code and not state["dropped"]:
            state["dropped"] = True
            code = code.split(APPEND)[0] + TOTAL
        return original_execute(code)

    studio11.execute = lossy
    try:
        sys.argv = ["push_repo_to_studio.py", "--file",
                    "ServerScriptService/GameManager.Script.lua"]
        code11 = tool11.main()
        check("the short-write injection actually fired", state["dropped"])
        check("short transfer is detected", code11 == 1, f"exit={code11}")
        check("live script NOT overwritten by the truncated body",
              studio11.source_of(gm11["studioPath"]) == seeded_text(repo11, gm11["file"]))
    finally:
        studio11.execute = original_execute
        SHARED["studio11"] = studio11


@test(12, "compare-and-swap catches drift between check and write")
def test_compare_and_swap() -> None:
    repo12 = fresh_repo()
    tool12 = load_tool(repo12)
    studio12 = fakestudio.FakeStudio()
    items12 = pending_items(repo12)
    seed(studio12, items12, repo12)
    fakestudio.install(tool12, studio12)
    target12 = require_item(items12,
                            lambda i: i["file"].endswith("GameManager.Script.lua"),
                            "TEST 12 target (GameManager)")
    original12 = studio12.execute
    race = {"done": False}

    def racy(code):
        # mutate the script in Studio right before the apply lands
        if "UpdateSourceAsync" in code and not race["done"]:
            race["done"] = True
            key = tuple(target12["studioPath"].split("."))
            entry = studio12.objects.get(key)
            if entry is not None:
                cls, body, kind = entry
                studio12.objects[key] = (cls, body + "\n-- sneaked in\n", kind)
        return original12(code)

    studio12.execute = racy
    try:
        sys.argv = ["push_repo_to_studio.py", "--file",
                    "ServerScriptService/GameManager.Script.lua"]
        code12 = tool12.main()
        check("the race injection actually fired", race["done"])
        check("racing write is refused", code12 == 1, f"exit={code12}")
        check("the racer's edit survived (not clobbered)",
              "sneaked in" in (studio12.source_of(target12["studioPath"]) or ""))
    finally:
        studio12.execute = original12
        SHARED["studio12"] = studio12


@test(13, "no orphaned transfer buffer after a mid-transfer failure")
def test_no_orphan_buffer() -> None:
    studio11 = require_shared("studio11", "TEST 13")
    studio12 = require_shared("studio12", "TEST 13")
    buffers13 = [p for p in studio11.objects if p[-1] == "__RepoPushBuffer"]  # type: ignore[attr-defined]
    check("failed push left no __RepoPushBuffer in ServerStorage",
          not buffers13, str(buffers13))
    buffers12 = [p for p in studio12.objects if p[-1] == "__RepoPushBuffer"]  # type: ignore[attr-defined]
    check("refused CAS left no __RepoPushBuffer", not buffers12, str(buffers12))


@test(14, "pre-push backups written")
def test_backups() -> None:
    repo10 = require_shared("repo10", "TEST 14")
    items10 = require_shared("items10", "TEST 14")
    victim10 = require_shared("victim10", "TEST 14")
    backup_root = repo10 / ".studio-push-backups"  # type: ignore[operator]
    backups = list(backup_root.rglob("*.lua")) if backup_root.exists() else []
    check("pre-push source backed up for every written file",
          len(backups) >= len(items10) - 1,  # type: ignore[arg-type]
          f"{len(backups)} backups for {len(items10)} pending")  # type: ignore[arg-type]
    if not backups:
        raise CheckFailure("TEST 14: no backups written, nothing to inspect")
    sample = next((b for b in backups if b.name.startswith("GameManager")), backups[0])
    saved = sample.read_text(encoding="utf-8")
    check("backup holds the PRE-push Studio source, not the new one",
          "-- drift" in saved
          or normalize(saved) == seeded_text(repo10, victim10["file"]),  # type: ignore[index,arg-type]
          sample.name)


@test(15, "--file that matches nothing is reported clearly", needs_luau=False)
def test_unmatched_file() -> None:
    repo15 = fresh_repo()
    tool15 = load_tool(repo15)
    studio15 = fakestudio.FakeStudio()
    fakestudio.install(tool15, studio15)
    check("there IS a pending queue to fail to match against",
          len(pending_items(repo15)) > 0)
    sys.argv = ["push_repo_to_studio.py", "--file", "ServerScriptService/NoSuchFile.lua"]
    code15 = tool15.main()
    check("unmatched --file exits 2 (not a misleading 'nothing pending')",
          code15 == 2, f"exit={code15}")
    check("unmatched --file contacted Studio zero times", studio15.calls == 0)


@test(16, "backslash paths (Windows tab-completion) still match")
def test_backslash_path() -> None:
    repo16 = fresh_repo()
    tool16 = load_tool(repo16)
    studio16 = fakestudio.FakeStudio()
    items16 = pending_items(repo16)
    spacey = "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua"
    require_item(items16, lambda i: i["file"] == spacey, "TEST 16 backslash target")
    seed(studio16, items16, repo16)
    fakestudio.install(tool16, studio16)
    sys.argv = ["push_repo_to_studio.py", "--file", spacey.replace("/", "\\")]
    code16 = tool16.main()
    check("backslash --file path is normalized and matches", code16 == 0, f"exit={code16}")


@test(17, "stale buffer from a previous crash is cleaned at startup")
def test_stale_buffer() -> None:
    repo17 = fresh_repo()
    tool17 = load_tool(repo17)
    studio17 = fakestudio.FakeStudio()
    items17 = pending_items(repo17)
    seed(studio17, items17, repo17)
    studio17.objects[("ServerStorage", "__RepoPushBuffer")] = (
        "StringValue", "left over junk", "V")
    fakestudio.install(tool17, studio17)
    sys.argv = ["push_repo_to_studio.py", "--audit"]
    code17 = tool17.main()
    check("--audit against live Studio classifies without writing",
          code17 == 0, f"exit={code17}")
    check("stale buffer removed at startup",
          ("ServerStorage", "__RepoPushBuffer") not in studio17.objects)
    changed17 = [i["file"] for i in items17
                 if studio17.source_of(i["studioPath"]) != seeded_text(repo17, i["file"])]
    check("--audit wrote no script sources", not changed17, str(changed17[:3]))


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
def run_test(number: int, title: str, fn: Callable[[], None],
             needs_luau: bool) -> None:
    label = f"TEST {number}"
    CURRENT["label"] = label
    print()
    print("=" * 72)
    print(f"{label} -- {title}")
    print("=" * 72)
    if needs_luau and not LUAU_AVAILABLE:
        print("  NOT EXECUTED  no luau interpreter")
        not_executed.append((f"{label} -- {title}", "no luau interpreter"))
        return
    try:
        fn()
    except CheckFailure as error:
        check("completed", False, str(error))
    except Exception as error:  # noqa: BLE001
        check("completed", False, f"unexpected {type(error).__name__}: {error}")
    executed.append(f"{label} -- {title}")


def summarize(fixture_only: bool) -> int:
    print()
    print("=" * 72)
    print(f"RESULT: {len(passes)} passed, {len(failures)} failed")
    if fixture_only:
        print(f"MODE: --fixture-only. {len(TESTS)} tests enumerated, 0 executed "
              f"(the fixture is proven; the Studio round-trips were not run).")
    else:
        print(f"tests enumerated: {len(TESTS)}   executed: {len(executed)}   "
              f"not executed: {len(not_executed)}")
        if not_executed:
            print(f"NOT EXECUTED ({len(not_executed)}):")
            for name, reason in not_executed:
                print(f"  - {name}  [{reason}]")
    if failures:
        for failure in failures:
            print("  FAILED: " + failure)
    if (REPO / MANIFEST_NAME).read_text(encoding="utf-8") != REAL_MANIFEST_TEXT:
        print("  FAILED: the REAL studio-sync-manifest.json was modified by this run")
        failures.append("real manifest modified")
    if failures:
        print("VERDICT: FAILED")
        print("=" * 72)
        return 1
    if not_executed:
        print(f"VERDICT: CANNOT EXECUTE -- {LUAU_REASON}")
        print("         The fixture is sound, but nothing was actually pushed.")
        print("=" * 72)
        return 2
    print("VERDICT: PASSED")
    print("=" * 72)
    return 0


def main() -> int:
    global LUAU_PATH, LUAU_REASON, LUAU_AVAILABLE

    parser = argparse.ArgumentParser(
        description="Push-tool end-to-end suite against a fake Studio.")
    parser.add_argument(
        "--fixture-only", action="store_true",
        help="build the synthesized pending queue, prove its invariants and "
             "exit; needs no luau interpreter")
    args = parser.parse_args()

    CURRENT["label"] = "FIXTURE"
    print("=" * 72)
    print("FIXTURE -- the pending queue this suite pushes is SYNTHESIZED")
    print("=" * 72)
    try:
        verify_fixture(fresh_repo())
    except CheckFailure as error:
        check("fixture built", False, str(error))
    except Exception as error:  # noqa: BLE001
        check("fixture built", False, f"unexpected {type(error).__name__}: {error}")

    if args.fixture_only:
        return summarize(fixture_only=True)

    LUAU_PATH, LUAU_REASON = detect_luau()
    LUAU_AVAILABLE = LUAU_PATH is not None
    print()
    if LUAU_AVAILABLE:
        fakestudio.LUAU = LUAU_PATH
        print(f"luau interpreter: {LUAU_PATH}  ({LUAU_REASON})")
    else:
        banner([
            "CANNOT EXECUTE: NO LUAU INTERPRETER",
            "",
            LUAU_REASON,
            "",
            "Every TEST below is ENUMERATED. The ones that talk to Studio are",
            "reported as 'not executed' -- nothing was pushed, nothing was",
            "round-tripped, no Studio behaviour was verified. This run is a",
            "FAILURE (exit 2), not a pass.",
            "",
            "To run them, install the luau CLI (nothing is downloaded here):",
            "  https://github.com/luau-lang/luau/releases  -> luau[.exe]",
            f"  put it at {SCRATCH / 'luau'}  or set LUAU_BIN=<path>",
            "",
            "The fixture itself needs no interpreter:",
            "  python tools/tests/test_push_repo_to_studio.py --fixture-only",
        ])

    for number, title, fn, needs_luau in TESTS:
        run_test(number, title, fn, needs_luau)

    CURRENT["label"] = "SUMMARY"
    return summarize(fixture_only=False)


if __name__ == "__main__":
    sys.exit(main())
