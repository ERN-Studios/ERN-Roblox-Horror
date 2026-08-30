"""Integration coverage for the FULL sync path's source contract.

tools/tests/test_studio_source_contract.py covers the shared helper and the push
tool. This file covers the thing that helper was missing from for longest: the
canonical full sync, which reads every script out of Studio and writes the
mirror. That path used to write every Studio byte unconditionally -- so one run
would have absorbed the nineteen transport newlines into the repo, made every
hash agree, and erased the contract that documented them, with no drift left
behind for anything to detect.

The important half of this file is `sync.sync()` itself, driven end to end
against a fake Studio in a temporary directory. The previous version of this
file called `reconcile_source` a helper at a time and hand-built a manifest
item, which is precisely why it reported green while the production loop
verified RAW checkout bytes against CANONICAL content and aborted the release on
all 58 CRLF-checked-out files. A test that never runs the loop cannot see a bug
in the loop.

Runs entirely offline: no Studio, no MCP, no place file.

    python tools/tests/test_full_sync_contract.py
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))

import studio_source_contract as contract  # noqa: E402
import sync_from_studio as sync  # noqa: E402

REPO = "local x = 1\nreturn x\n"
PLUS_NEWLINE = REPO + "\n"
PLUS_TWO = REPO + "\n\n"
CHANGED = "local x = 2\nreturn x\n"

failures: list[str] = []


def check(condition: bool, description: str, detail: str = "") -> None:
    if condition:
        print(f"  ok   {description}")
    else:
        failures.append(description)
        print(f"  FAIL {description}" + (f"  ({detail})" if detail else ""))


# ---------------------------------------------------------------------------
# A fake Studio that answers the four calls sync() makes.
# ---------------------------------------------------------------------------


class FakeStudioClient:
    """Speaks the StudioMcpClient surface sync() uses: initialize/call/close.

    `sources` maps a Studio path to the text Studio serves for it. Everything
    else -- the numbered script_read framing, the search_game_tree payload, the
    Edit-mode handshake -- is reproduced exactly as the real proxy emits it, so
    the production decoders are under test too.
    """

    def __init__(self, sources: dict[str, str], remotes: list[str]) -> None:
        self.sources = sources
        self.remotes = remotes
        self.initialized = False
        self.closed = False
        self.reads: list[str] = []

    def initialize(self) -> None:
        self.initialized = True

    def close(self) -> None:
        self.closed = True

    def call(self, tool: str, arguments: dict[str, Any] | None = None) -> str:
        arguments = arguments or {}
        if tool == "list_roblox_studios":
            return json.dumps(
                {"studios": [{
                    "id": "fake-1",
                    "name": (
                        "BACKROOMS: STAY QUIET [CO-OP HORROR] "
                        f"(placeId: {sync.EXPECTED_PLACE_ID})"
                    ),
                }]}
            )
        if tool == "get_studio_state":
            return (
                "- Current Studio Mode: Edit\n"
                "- Available DataModels: Edit\n"
                "- Focused DataModel in the viewport: Edit"
            )
        if tool == "search_game_tree":
            wanted = arguments.get("instance_type")
            if wanted == "RemoteEvent":
                return json.dumps(
                    [
                        {"fullPath": path, "className": "RemoteEvent"}
                        for path in self.remotes
                    ]
                )
            return json.dumps(
                [
                    {"fullPath": path, "className": "ModuleScript"}
                    for path in sorted(self.sources)
                ]
            )
        if tool == "script_read":
            target = arguments["target_file"].removeprefix("game.")
            self.reads.append(target)
            text = self.sources[target]
            # The proxy numbers every line with a rightwards arrow separator,
            # and the last line of a file ending in "\n" is an empty one that
            # still gets a number. Framing it exactly as the proxy does puts
            # decode_script_read under test rather than around it.
            return "\n".join(
                f"{index}\N{RIGHTWARDS ARROW}{line}"
                for index, line in enumerate(text.split("\n"), start=1)
            )
        raise AssertionError(f"fake Studio got an unexpected call: {tool}")


def run_sync(root: Path, client: FakeStudioClient) -> dict[str, Any]:
    args = argparse.Namespace(
        project_root=root,
        studio_name="Backrooms: No Way Out",
        connect_timeout=1.0,
    )
    return sync.sync(args, client_factory=lambda: client)


class StudioListClient:
    def __init__(self, studios: list[dict[str, Any]]) -> None:
        self.studios = studios

    def call(self, tool: str, arguments: dict[str, Any] | None = None) -> str:
        assert tool == "list_roblox_studios"
        return json.dumps({"studios": self.studios})


# ---------------------------------------------------------------------------
print("=== Studio rename selection stays exact and place-id safe ===")
# ---------------------------------------------------------------------------
new_title = StudioListClient([{
    "id": "new-title",
    "name": f"{sync.RELEASE_STUDIO_NAME} (placeId: {sync.EXPECTED_PLACE_ID})",
}])
selected = sync.select_studio(new_title, sync.LEGACY_STUDIO_NAME, 0.2)
check(selected["id"] == "new-title",
      "the legacy selector accepts the exact renamed Studio title")

old_title = StudioListClient([{
    "id": "old-title",
    "name": f"{sync.LEGACY_STUDIO_NAME} (placeId: {sync.EXPECTED_PLACE_ID})",
}])
selected = sync.select_studio(old_title, sync.RELEASE_STUDIO_NAME, 0.2)
check(selected["id"] == "old-title",
      "the renamed selector accepts the exact legacy Studio title during migration")

wrong_place = StudioListClient([{
    "id": "wrong-place",
    "name": f"{sync.RELEASE_STUDIO_NAME} (placeId: {sync.EXPECTED_PLACE_ID + 1})",
}])
wrong_place_refused = False
try:
    sync.select_studio(wrong_place, sync.RELEASE_STUDIO_NAME, 0.2)
except sync.StudioMcpError as error:
    wrong_place_refused = "place id did not match" in str(error)
check(wrong_place_refused,
      "the title alias never bypasses the expected Roblox place id")

malformed_place = StudioListClient([{
    "id": "malformed-place",
    "name": f"{sync.RELEASE_STUDIO_NAME} (placeId: not-a-number)",
}])
malformed_refused = False
try:
    sync.select_studio(malformed_place, sync.RELEASE_STUDIO_NAME, 0.2)
except sync.StudioMcpError as error:
    malformed_refused = "place id did not match" in str(error)
check(malformed_refused,
      "a malformed advertised place id also fails closed")


# ---------------------------------------------------------------------------
print("=== reconcile_source: what the mirror should hold ===")
# ---------------------------------------------------------------------------
action, content, verdict = sync.reconcile_source(REPO, REPO, flagged=False)
check(action == "keep" and content == REPO and verdict == contract.EXACT,
      "an exact match keeps the mirrored file untouched", f"{action}/{verdict}")

action, content, verdict = sync.reconcile_source(REPO, PLUS_NEWLINE, flagged=True)
check(action == "keep" and content == REPO and verdict == contract.TRAILING_NEWLINE,
      "a FLAGGED entry keeps the repo file when Studio has the permitted newline",
      f"{action}/{verdict}")
check(content == REPO,
      "and specifically does NOT absorb the transport newline into the mirror",
      repr(content[-3:]))

action, content, verdict = sync.reconcile_source(REPO, PLUS_NEWLINE, flagged=False)
check(action == "write" and content == PLUS_NEWLINE and verdict == contract.DRIFTED,
      "the same difference on an UNFLAGGED entry is real drift and is pulled",
      f"{action}/{verdict}")

action, content, verdict = sync.reconcile_source(REPO, PLUS_TWO, flagged=True)
check(action == "write" and content == PLUS_TWO,
      "two extra newlines are drift even on a flagged entry", f"{action}/{verdict}")

action, content, verdict = sync.reconcile_source(REPO, CHANGED, flagged=True)
check(action == "write" and content == CHANGED,
      "a genuinely changed line is always pulled", f"{action}/{verdict}")

action, content, verdict = sync.reconcile_source(None, REPO, flagged=False)
check(action == "write" and content == REPO and verdict == "created",
      "a script with no mirrored file yet is created", f"{action}/{verdict}")

action, content, _ = sync.reconcile_source(REPO.replace("\n", "\r\n"), REPO, flagged=False)
check(action == "keep",
      "a CRLF working copy is not mistaken for drift", action)

# ---------------------------------------------------------------------------
print("=== flags survive a full rebuild ===")
# ---------------------------------------------------------------------------
manifest = {
    "items": [
        {"studioPath": "ServerScriptService.Flagged", "file": "a.lua",
         "studioTrailingNewline": True},
        {"studioPath": "ServerScriptService.Plain", "file": "b.lua"},
        {"studioPath": "ServerScriptService.AlsoFlagged", "file": "c.lua",
         "studioTrailingNewline": True},
    ]
}
flags = sync.trailing_newline_flags(manifest)
check(flags == {"ServerScriptService.Flagged", "ServerScriptService.AlsoFlagged"},
      "trailing_newline_flags reads every flag, keyed by Studio path", str(sorted(flags)))
check(sync.trailing_newline_flags({}) == set(),
      "and copes with a manifest that has no items at all")

# ---------------------------------------------------------------------------
print("=== END TO END: the real sync() against a fake Studio ===")
# ---------------------------------------------------------------------------
# Every case below is a file the production loop must classify, act on, verify
# and describe in the manifest. Five of the six mirrored scripts are checked
# out CRLF, because that is what the release machine actually holds.
scratch = Path(tempfile.mkdtemp(prefix="mongotv-fullsync-"))
try:
    service = scratch / "ServerScriptService"
    service.mkdir(parents=True)
    (scratch / "ReplicatedStorage").mkdir(parents=True)

    def put(path: Path, text: str, *, crlf: bool) -> None:
        body = text.replace("\n", "\r\n") if crlf else text
        path.write_bytes(body.encode("utf-8"))

    flagged_crlf = service / "FlaggedCrlf.ModuleScript.lua"
    stale_exact = service / "StaleExact.ModuleScript.lua"
    plain_crlf = service / "PlainCrlf.ModuleScript.lua"
    drifted = service / "Drifted.ModuleScript.lua"
    plain_lf = service / "PlainLf.ModuleScript.lua"
    # "New" has no mirrored file at all yet.
    remote_marker_path = scratch / "ReplicatedStorage" / "RoundStatus.RemoteEvent.txt"

    put(flagged_crlf, REPO, crlf=True)
    put(stale_exact, REPO, crlf=True)
    put(plain_crlf, REPO, crlf=True)
    put(drifted, REPO, crlf=True)
    put(plain_lf, REPO, crlf=False)
    put(remote_marker_path,
        sync.remote_marker({"fullPath": "ReplicatedStorage.RoundStatus"}), crlf=True)

    raw_before = {
        path: path.read_bytes()
        for path in (
            flagged_crlf, stale_exact, plain_crlf, plain_lf, remote_marker_path
        )
    }

    seed_manifest = {
        "formatVersion": 1,
        "finalNewlineContract": "carried forward by the sync",
        "items": [
            {"studioPath": "ServerScriptService.FlaggedCrlf",
             "file": "ServerScriptService/FlaggedCrlf.ModuleScript.lua",
             "studioTrailingNewline": True},
            {"studioPath": "ServerScriptService.StaleExact",
             "file": "ServerScriptService/StaleExact.ModuleScript.lua",
             "studioTrailingNewline": True},
            {"studioPath": "ServerScriptService.PlainCrlf",
             "file": "ServerScriptService/PlainCrlf.ModuleScript.lua"},
            {"studioPath": "ServerScriptService.Drifted",
             "file": "ServerScriptService/Drifted.ModuleScript.lua"},
            {"studioPath": "ServerScriptService.PlainLf",
             "file": "ServerScriptService/PlainLf.ModuleScript.lua"},
        ],
    }
    (scratch / "studio-sync-manifest.json").write_text(
        json.dumps(seed_manifest, indent=2) + "\n", encoding="utf-8", newline="\n")

    client = FakeStudioClient(
        sources={
            # Flagged, and Studio really does hold the permitted extra newline.
            "ServerScriptService.FlaggedCrlf": PLUS_NEWLINE,
            # Previously flagged, but a later transport landed exact bytes.
            "ServerScriptService.StaleExact": REPO,
            # Unflagged, CRLF on disk, semantically identical in Studio.
            "ServerScriptService.PlainCrlf": REPO,
            # Genuine drift: Studio changed a line.
            "ServerScriptService.Drifted": CHANGED,
            "ServerScriptService.PlainLf": REPO,
            # Not mirrored yet.
            "ServerScriptService.NewScript": "return {}\n",
        },
        remotes=["ReplicatedStorage.RoundStatus"],
    )

    # Named, not incidental: the release blocker was sync() ABORTING here, so
    # "sync() completes over a CRLF checkout" has to be an assertion with a name
    # rather than a traceback that happens to end the run.
    built = None
    sync_error = ""
    try:
        built = run_sync(scratch, client)
    except Exception as error:  # noqa: BLE001 -- any failure is the regression
        sync_error = f"{type(error).__name__}: {error}"
    check(built is not None,
          "sync() runs to completion over a CRLF-checked-out mirror", sync_error)
    if built is None:
        built = {"items": [], "counts": {}, "finalNewlineContract": None}

    check(client.initialized and client.closed,
          "sync() initialised and closed its client")
    check(len(client.reads) == 6,
          "sync() read every script out of Studio", str(len(client.reads)))

    # --- the release blocker: an exact/permitted CRLF file survives untouched
    for path in (flagged_crlf, stale_exact, plain_crlf, plain_lf, remote_marker_path):
        check(path.read_bytes() == raw_before[path],
              f"a 'keep' left {path.name} byte-for-byte untouched on disk",
              f"{len(path.read_bytes())} vs {len(raw_before[path])}")
    check(b"\r\n" in flagged_crlf.read_bytes() and b"\r\n" in plain_crlf.read_bytes(),
          "and those files are genuinely still CRLF, i.e. the case really was exercised")
    check(contract.normalize(flagged_crlf.read_text(encoding="utf-8")) == REPO,
          "the flagged mirror did NOT absorb Studio's permitted extra newline",
          repr(flagged_crlf.read_text(encoding="utf-8")[-4:]))

    # --- real drift is still pulled, and lands LF
    check(drifted.read_bytes() == CHANGED.encode("utf-8"),
          "real drift was pulled from Studio and written LF",
          repr(drifted.read_bytes()[-12:]))
    new_script = service / "NewScript.ModuleScript.lua"
    check(new_script.is_file() and new_script.read_bytes() == b"return {}\n",
          "a script with no mirror yet was created")

    # --- statuses
    by_path = {item["studioPath"]: item for item in built["items"]}
    if not by_path:  # the sync aborted; the named check above already failed
        by_path = {key: {"status": "", "bytes": -1, "sha256": ""} for key in (
            "ServerScriptService.FlaggedCrlf", "ServerScriptService.StaleExact",
            "ServerScriptService.PlainCrlf",
            "ServerScriptService.Drifted", "ServerScriptService.NewScript",
            "ServerScriptService.PlainLf")}
    check(by_path["ServerScriptService.FlaggedCrlf"]["status"] == "unchanged",
          "the flagged CRLF entry is reported unchanged",
          by_path["ServerScriptService.FlaggedCrlf"]["status"])
    check(by_path["ServerScriptService.PlainCrlf"]["status"] == "unchanged",
          "the unflagged CRLF entry is reported unchanged",
          by_path["ServerScriptService.PlainCrlf"]["status"])
    check(by_path["ServerScriptService.Drifted"]["status"] == "updated",
          "the drifted entry is reported updated",
          by_path["ServerScriptService.Drifted"]["status"])
    check(by_path["ServerScriptService.NewScript"]["status"] == "created",
          "the new entry is reported created",
          by_path["ServerScriptService.NewScript"]["status"])

    # --- the manifest describes CANONICAL content, not the checkout
    flagged_item = by_path["ServerScriptService.FlaggedCrlf"]
    check(flagged_item["bytes"] == len(contract.canonical_bytes(REPO)),
          "manifest bytes are canonical, not the CRLF checkout's raw length",
          f"{flagged_item['bytes']} vs {len(contract.canonical_bytes(REPO))} "
          f"(raw on disk {len(flagged_crlf.read_bytes())})")
    check(flagged_item["sha256"] == contract.sha256_of(REPO),
          "the rebuilt hash is the REPO file's, not Studio's copy")
    check(by_path["ServerScriptService.PlainCrlf"]["bytes"]
          == by_path["ServerScriptService.PlainLf"]["bytes"],
          "a CRLF checkout and an LF checkout of the same script describe identically",
          f"{by_path['ServerScriptService.PlainCrlf']['bytes']} vs "
          f"{by_path['ServerScriptService.PlainLf']['bytes']}")

    # --- flags and contract survive the rebuild
    check(contract.permits_trailing_newline(flagged_item),
          "the rebuilt item still carries the flag")
    check(not contract.permits_trailing_newline(
              by_path["ServerScriptService.StaleExact"]),
          "an exact landing removes a stale flag during the full rebuild")
    check(not contract.permits_trailing_newline(by_path["ServerScriptService.PlainCrlf"]),
          "and an unflagged item did not acquire one")
    check("count: 1" in built["finalNewlineContract"],
          "finalNewlineContract publishes the reconciled flag count",
          str(built.get("finalNewlineContract")))
    check(built["counts"]["scripts"] == 6 and built["counts"]["remoteEvents"] == 1,
          "counts describe what Studio actually held", str(built["counts"]))
    check(built["counts"][contract.TRAILING_NEWLINE_FLAG] == 1,
          "counts includes the exact number of permitted +LF landings",
          str(built["counts"]))

    # --- a later push still recognises Studio's copy from the rebuilt manifest
    check(contract.matches_hash(flagged_item["sha256"], PLUS_NEWLINE,
                                allow_trailing_newline=True),
          "post-sync, a push recognises Studio's permitted copy as the same source")
    check(not contract.matches_hash(by_path["ServerScriptService.PlainCrlf"]["sha256"],
                                    PLUS_NEWLINE, allow_trailing_newline=False),
          "and does NOT bless the same newline on an unflagged entry")

    # --- rerunning over the now-settled mirror must be a complete no-op
    client2 = FakeStudioClient(sources=dict(client.sources),
                               remotes=list(client.remotes))
    client2.sources["ServerScriptService.Drifted"] = CHANGED
    raw_again = {
        p: p.read_bytes() for p in (flagged_crlf, stale_exact, plain_crlf, plain_lf)
    }
    second = run_sync(scratch, client2)
    check(second["counts"]["created"] == 0 and second["counts"]["updated"] == 0,
          "a second sync over a settled mirror changes nothing", str(second["counts"]))
    check(all(p.read_bytes() == raw_again[p] for p in raw_again),
          "and still leaves the CRLF working files untouched")
    check(len(sync.trailing_newline_flags(second)) == 1,
          "the flag survived a second full rebuild too")
finally:
    shutil.rmtree(scratch, ignore_errors=True)

# ---------------------------------------------------------------------------
print("=== the PRODUCTION checkout reconciles, read-only ===")
# ---------------------------------------------------------------------------
# The regression that mattered: on this machine 58 mirrored files are checked
# out CRLF, including all nineteen flagged ones. Reconciling and verifying every
# one of them, against a Studio serving exactly what the contract permits, must
# not raise. This walks the real manifest and never writes anything.
project_root = TOOLS.parent
live = json.loads((project_root / "studio-sync-manifest.json").read_text(encoding="utf-8"))
live_flags = sync.trailing_newline_flags(live)
crlf_seen = 0
reconcile_failures: list[str] = []
describe_failures: list[str] = []
for entry in live["items"]:
    path = project_root / entry["file"]
    if not path.is_file():
        reconcile_failures.append(f"{entry['file']}: missing")
        continue
    if b"\r\n" in path.read_bytes():
        crlf_seen += 1
    canonical = sync.read_canonical(path)
    permitted = entry["studioPath"] in live_flags
    studio_text = canonical + ("\n" if permitted else "")
    if entry["className"] == "RemoteEvent":
        expected = canonical
    else:
        action, expected, verdict = sync.reconcile_source(
            canonical, studio_text, flagged=permitted)
        if action != "keep":
            reconcile_failures.append(f"{entry['file']}: {action}/{verdict}")
            continue
    try:
        sync.verify_mirrored(path, expected)
    except sync.StudioMcpError as error:
        reconcile_failures.append(f"{entry['file']}: {error}")
    if (len(contract.canonical_bytes(expected)) != entry["bytes"]
            or contract.sha256_of(expected) != entry["sha256"]):
        describe_failures.append(entry["file"])

check(crlf_seen >= 57,
      "the production checkout really does hold the CRLF files this guards",
      f"{crlf_seen} CRLF of {len(live['items'])}")
check(not reconcile_failures,
      "every mirrored file in the real checkout reconciles and verifies",
      "; ".join(reconcile_failures[:4]))
check(not describe_failures,
      "and the live manifest already describes canonical content for all of them",
      "; ".join(describe_failures[:4]))

# ---------------------------------------------------------------------------
print("=== the live manifest keeps its contract ===")
# ---------------------------------------------------------------------------
check(isinstance(live.get("finalNewlineContract"), str)
      and len(live["finalNewlineContract"]) > 0,
      "finalNewlineContract is present")
# The flag COUNT is not a constant: it drops whenever a push lands the repo
# bytes exactly, which the .rbxmx transport does. It was 19 while every flagged
# file had last reached Studio through a route that appended a newline, and it
# is 14 now that five of them have been pushed directly. Pinning the number was
# therefore asserting a transport accident. What must hold is that the manifest
# and the contract prose AGREE, and that the number the manifest publishes is
# the number of entries actually carrying the flag -- so a flag silently
# dropped, or a count edited without the entries, still fails here.
published = live["counts"].get("studioTrailingNewline")
check(published == len(live_flags),
      "the published trailing-newline count is the number of entries that carry"
      " the flag",
      f"counts says {published}, {len(live_flags)} entries carry it")
check(str(len(live_flags)) in live["finalNewlineContract"],
      "and the contract prose names that same number rather than a stale one",
      f"{len(live_flags)} not found in the contract text")
counts = live["counts"]
check(counts["scripts"] + counts["remoteEvents"] == counts["total"] == len(live["items"]),
      "counts still reconcile",
      f"{counts['scripts']}+{counts['remoteEvents']} vs {counts['total']}/{len(live['items'])}")
check(counts["scripts"] == 114 and counts["remoteEvents"] == 13,
      "and are the 114 scripts + 13 remotes this place holds",
      f"{counts['scripts']}+{counts['remoteEvents']}")

print()
if failures:
    print(f"FAILED: {len(failures)} of the checks above")
    for name in failures:
        print(f"  - {name}")
    sys.exit(1)
print("All full-sync contract checks passed.")
