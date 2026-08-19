"""Push repo-side script fixes into the open Roblox Studio place.

Counterpart to pull_source_from_studio.py for the rare Studio-write direction.
Targets manifest entries whose status is "pending-studio-push": each such entry
records the NEW repo content (bytes/sha256) plus "studioSha256Before" — the
hash Studio is expected to still hold.

The run is deliberately two-phase, because a half-applied batch in a live place
is worse than no batch at all:

  Phase 1 (read-only)  every pending script's live .Source is read and classified
                       as already-applied / ready / conflict / missing / wrong
                       class. Nothing is written. Any problem aborts the run
                       before a single byte changes (--skip-conflicts overrides).
  Phase 2 (write)      the ready set is transferred through a staged
                       ServerStorage StringValue and applied with
                       ScriptEditorService:UpdateSourceAsync, which is also used
                       as a compare-and-swap: the callback re-checks the baseline
                       inside Studio, closing the read→write race. Length is
                       verified before the write and the source re-read after it.

Sources are read through execute_luau (never script_read, which can serve a
stale editor buffer after programmatic writes — see project memory).

Usage:
    python tools/push_repo_to_studio.py                 # classify, then push
    python tools/push_repo_to_studio.py --audit         # classify only, no writes
    python tools/push_repo_to_studio.py --list          # offline: list pending
    python tools/push_repo_to_studio.py --skip-conflicts
    python tools/push_repo_to_studio.py --file ServerScriptService/EntityAI.Script.lua
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import (  # noqa: E402
    StudioMcpClient,
    StudioMcpError,
    find_mcp_batch,
    select_studio,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "studio-sync-manifest.json"
BACKUP_ROOT = PROJECT_ROOT / ".studio-push-backups"
STUDIO_NAME = "Backrooms: No Way Out"
READ_CHUNK_LINES = 1400
# Kept well under the wire sizes the proven read path has demonstrated; the
# staged-buffer transfer has no track record at larger request sizes.
WRITE_CHUNK_BYTES = 24_000
BUFFER_NAME = "__RepoPushBuffer"
SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")

PATH_WALK_LUAU = """
local segments = {%s}
local cur = game
for _, name in ipairs(segments) do
    cur = cur:FindFirstChild(name)
    if not cur then return "@@MISSING@@" end
end
"""

CLASS_GUARD_LUAU = """
if cur.ClassName ~= "Script" and cur.ClassName ~= "LocalScript"
    and cur.ClassName ~= "ModuleScript" then
    return "@@WRONG_CLASS@@ " .. cur.ClassName
end
"""

READ_META_LUAU = PATH_WALK_LUAU + CLASS_GUARD_LUAU + """
local src = cur.Source:gsub("\\r\\n", "\\n")
local h = 5381
for i = 1, #src do
    h = (h * 33 + string.byte(src, i)) %% 4294967296
end
local lineCount = 1
for _ in string.gmatch(src, "\\n") do lineCount += 1 end
return #src .. "\\t" .. h .. "\\t" .. lineCount .. "\\t" .. cur.ClassName
"""

READ_CHUNK_LUAU = PATH_WALK_LUAU + """
local src = cur.Source:gsub("\\r\\n", "\\n")
local lines = {}
local pos = 1
while true do
    local nl = string.find(src, "\\n", pos, true)
    if nl then
        table.insert(lines, string.sub(src, pos, nl - 1))
        pos = nl + 1
    else
        table.insert(lines, string.sub(src, pos))
        break
    end
end
local first, count = %d, %d
local slice = {}
for i = first, math.min(first + count - 1, #lines) do
    table.insert(slice, lines[i])
end
return table.concat(slice, "\\n")
"""

BUFFER_APPEND_LUAU = """
local storage = game:GetService("ServerStorage")
local buffer = storage:FindFirstChild(%s)
if %s then
    if buffer then buffer:Destroy() end
    buffer = Instance.new("StringValue")
    buffer.Name = %s
    buffer.Parent = storage
end
if not buffer then return "@@NO_BUFFER@@" end
buffer.Value = buffer.Value .. %s
return tostring(#buffer.Value)
"""

# The apply is a compare-and-swap. UpdateSourceAsync hands the callback the live
# source; re-hashing it there closes the window between the phase-1 read and
# this write. Length is checked before anything destructive happens.
APPLY_LUAU = PATH_WALK_LUAU + CLASS_GUARD_LUAU + """
local storage = game:GetService("ServerStorage")
local buffer = storage:FindFirstChild(%s)
if not buffer then return "@@NO_BUFFER@@" end
local newSource = buffer.Value
if #newSource ~= %d then
    local got = #newSource
    buffer:Destroy()
    return "@@SHORT@@ " .. got
end
local expectedBaseline = %d
local function djb2(text)
    local h = 5381
    for i = 1, #text do
        h = (h * 33 + string.byte(text, i)) %% 4294967296
    end
    return h
end
local drifted = nil
local ok, err = pcall(function()
    game:GetService("ScriptEditorService"):UpdateSourceAsync(cur, function(old)
        local normalized = old:gsub("\\r\\n", "\\n")
        if djb2(normalized) ~= expectedBaseline then
            drifted = djb2(normalized)
            return old
        end
        return newSource
    end)
end)
buffer:Destroy()
if drifted ~= nil then return "@@DRIFT@@ " .. drifted end
if not ok then return "@@WRITE_FAILED@@ " .. tostring(err) end
return "@@OK@@"
"""

CLEAN_BUFFER_LUAU = """
local storage = game:GetService("ServerStorage")
local buffer = storage:FindFirstChild(%s)
if buffer then
    local size = #buffer.Value
    buffer:Destroy()
    return "@@CLEANED@@ " .. size
end
return "@@NONE@@"
"""


def luau_string(value: str) -> str:
    out = ['"']
    for ch in value:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 32 or code == 127:
            out.append("\\%03d" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def djb2(data: bytes) -> int:
    h = 5381
    for byte in data:
        h = (h * 33 + byte) % 4294967296
    return h


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def studio_id_of(selected: object) -> str:
    """select_studio returns the whole studio record; the tools disagree on this.

    push_level1_to_studio.py (which pushed this place successfully) uses
    selected["id"], while pull_source_from_studio.py passes the record straight
    through. Accept either shape so a write can never be misrouted.
    """
    if isinstance(selected, dict):
        identifier = selected.get("id")
        if not identifier:
            raise StudioMcpError(f"Studio record has no id: {selected!r}")
        return str(identifier)
    return str(selected)


def execute_luau(client: StudioMcpClient, studio_id: str, code: str) -> str:
    return client.call(
        "execute_luau",
        {"studio_id": studio_id, "datamodel_type": "Edit", "code": code},
    )


def segments_of(item: dict) -> list[str]:
    return item["studioPath"].split(".")


def read_studio_source(client, studio_id: str, segments: list[str]) -> str:
    """Read a script's live .Source, verified by length and djb2."""
    seg_literals = ", ".join(luau_string(s) for s in segments)
    meta = execute_luau(client, studio_id, READ_META_LUAU % seg_literals)
    if meta == "@@MISSING@@":
        raise StudioMcpError("script not found in Studio")
    if meta.startswith("@@WRONG_CLASS@@"):
        raise StudioMcpError(f"not a script instance ({meta.split(' ', 1)[-1]})")
    parts = meta.split("\t")
    if len(parts) != 4 or not all(p.isdigit() for p in parts[:3]):
        raise StudioMcpError(f"unexpected metadata response: {meta!r}")
    size, digest, line_count = (int(p) for p in parts[:3])

    chunks: list[str] = []
    first = 1
    while first <= line_count:
        chunk = execute_luau(
            client, studio_id, READ_CHUNK_LUAU % (seg_literals, first, READ_CHUNK_LINES)
        )
        if chunk == "@@MISSING@@":
            raise StudioMcpError("script vanished mid-read")
        chunks.append(chunk)
        first += READ_CHUNK_LINES
    source = "\n".join(chunks)
    data = source.encode("utf-8")
    if len(data) != size or djb2(data) != digest:
        raise StudioMcpError(
            f"chunked read failed verification ({len(data)}B vs {size}B reported)"
        )
    return source


def clean_buffer(client, studio_id: str) -> str:
    return execute_luau(
        client, studio_id, CLEAN_BUFFER_LUAU % luau_string(BUFFER_NAME))


def push_source(client, studio_id: str, segments: list[str], source: str,
                baseline: str) -> None:
    """Stage the source in ServerStorage, then compare-and-swap it into place."""
    buffer_literal = luau_string(BUFFER_NAME)
    data = source.encode("utf-8")
    sent = 0
    offset = 0
    first = True
    try:
        while offset < len(data) or first:
            end = min(offset + WRITE_CHUNK_BYTES, len(data))
            # never split a UTF-8 sequence across chunks
            while end < len(data) and (data[end] & 0xC0) == 0x80:
                end -= 1
            chunk_bytes = data[offset:end]
            chunk = chunk_bytes.decode("utf-8")
            result = execute_luau(
                client,
                studio_id,
                BUFFER_APPEND_LUAU % (
                    buffer_literal,
                    "true" if first else "false",
                    buffer_literal,
                    luau_string(chunk),
                ),
            )
            if result == "@@NO_BUFFER@@":
                raise StudioMcpError("push buffer disappeared mid-transfer")
            sent += len(chunk_bytes)
            # The buffer reports its own length; a short append must abort
            # BEFORE anything overwrites the live script.
            try:
                staged = int(result)
            except ValueError:
                raise StudioMcpError(
                    f"unexpected buffer response: {result!r}") from None
            if staged != sent:
                raise StudioMcpError(
                    f"staged transfer is short: Studio holds {staged}B, sent {sent}B")
            first = False
            offset = end

        seg_literals = ", ".join(luau_string(s) for s in segments)
        result = execute_luau(
            client,
            studio_id,
            APPLY_LUAU % (
                seg_literals, buffer_literal, len(data), djb2(baseline.encode("utf-8"))
            ),
        )
    except BaseException:
        # Never leave up to a few hundred KB of source parked in the live place.
        try:
            clean_buffer(client, studio_id)
        except Exception:  # noqa: BLE001 - cleanup must not mask the real error
            pass
        raise

    if result == "@@OK@@":
        return
    if result == "@@MISSING@@":
        raise StudioMcpError("script disappeared before the write")
    if result == "@@NO_BUFFER@@":
        raise StudioMcpError("staged buffer vanished before the write")
    if result.startswith("@@WRONG_CLASS@@"):
        raise StudioMcpError(f"not a script instance ({result.split(' ', 1)[-1]})")
    if result.startswith("@@SHORT@@"):
        raise StudioMcpError(
            f"staged source was truncated ({result.split(' ', 1)[-1]}B of {len(data)}B)"
            " — live script left untouched")
    if result.startswith("@@DRIFT@@"):
        raise StudioMcpError(
            "Studio changed this script between the check and the write — not applied")
    raise StudioMcpError(f"UpdateSourceAsync failed: {result}")


def write_manifest(manifest: dict) -> None:
    """Atomic: a crash mid-write must never destroy the recorded baselines."""
    temporary = MANIFEST_PATH.with_name(MANIFEST_PATH.name + ".tmp")
    temporary.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, MANIFEST_PATH)


def backup(item: dict, live: str, stamp: str) -> Path:
    destination = BACKUP_ROOT / stamp / item["file"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(live, encoding="utf-8", newline="\n")
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true",
                        help="classify against live Studio, write nothing")
    parser.add_argument("--list", action="store_true",
                        help="list pending entries without contacting Studio")
    parser.add_argument("--skip-conflicts", action="store_true",
                        help="push the clean files even if others conflict")
    parser.add_argument("--overwrite-conflicts", action="store_true",
                        help="accept Studio's current source as the baseline and "
                             "push over it (still race-safe: the swap re-checks "
                             "that exact source inside Studio)")
    parser.add_argument("--studio-name", default=STUDIO_NAME)
    parser.add_argument("--file", action="append", default=None,
                        help="limit to this manifest file path (repeatable)")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    all_pending = [i for i in manifest.get("items", [])
                   if i.get("status") == "pending-studio-push"]

    requested = None
    if args.file:
        requested = {f.replace("\\", "/").lstrip("./") for f in args.file}
        pending = [i for i in all_pending if i["file"] in requested]
        unmatched = requested - {i["file"] for i in pending}
        if unmatched:
            for name in sorted(unmatched):
                entry = next((i for i in manifest.get("items", [])
                              if i["file"] == name), None)
                state = entry.get("status", "?") if entry else "not in manifest"
                print(f"--file did not match a pending entry: {name}  ({state})")
            return 2
    else:
        pending = all_pending

    if not pending:
        print("Nothing pending: no manifest entries with status "
              "'pending-studio-push'.")
        return 0

    for item in pending:
        if "studioSha256Before" not in item:
            raise StudioMcpError(
                f"{item['file']} is pending but has no studioSha256Before hash")
        if item.get("className") not in SCRIPT_CLASSES:
            raise StudioMcpError(
                f"{item['file']} is a {item.get('className')}, not a script")

    print(f"{len(pending)} script(s) pending push:")
    for item in pending:
        print(f"  {item['file']}")
    if args.list:
        return 0

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio_id = studio_id_of(select_studio(client, args.studio_name, 20.0))

        stale = clean_buffer(client, studio_id)
        if stale.startswith("@@CLEANED@@"):
            print(f"  note: removed a stale {BUFFER_NAME} left in ServerStorage "
                  f"({stale.split(' ', 1)[-1]} bytes) — a previous run was interrupted")

        # ── phase 1: classify everything, write nothing ──────────────────
        print("\nPhase 1 — checking live Studio sources (no writes):", flush=True)
        ready, already, problems = [], [], []
        for index, item in enumerate(pending, start=1):
            label = f"[{index}/{len(pending)}] {item['file']}"
            desired = (PROJECT_ROOT / item["file"]).read_text(
                encoding="utf-8").replace("\r\n", "\n")
            if sha256(desired) != item["sha256"]:
                problems.append((item, "repo file no longer matches its manifest "
                                       "entry — re-run record_pending_push.py"))
                print(f"  {label}: REPO DRIFT", flush=True)
                continue
            try:
                live = read_studio_source(client, studio_id, segments_of(item))
            except StudioMcpError as error:
                problems.append((item, str(error)))
                print(f"  {label}: ERROR — {error}", flush=True)
                continue
            live_sha = sha256(live)
            if live_sha == item["sha256"]:
                already.append(item)
                print(f"  {label}: already applied", flush=True)
            elif live_sha == item["studioSha256Before"]:
                ready.append((item, desired, live))
                print(f"  {label}: ready", flush=True)
            elif args.overwrite_conflicts:
                ready.append((item, desired, live))
                print(f"  {label}: ready (overwriting Studio's drifted copy)",
                      flush=True)
            else:
                problems.append((item, f"Studio drifted from the recorded baseline "
                                       f"(live {live_sha[:12]}, expected "
                                       f"{item['studioSha256Before'][:12]})"))
                print(f"  {label}: CONFLICT", flush=True)

        print(f"\nready: {len(ready)}   already applied: {len(already)}   "
              f"problems: {len(problems)}")
        for item, reason in problems:
            print(f"  ! {item['file']}: {reason}")

        if args.audit:
            print("\n--audit: nothing was written.")
            if problems:
                print("Resolve the entries above, or re-run with "
                      "--skip-conflicts / --overwrite-conflicts.")
            return 1 if problems else 0

        if problems and not args.skip_conflicts:
            print("\nAborting before any write. Resolve the entries above, or "
                  "re-run with --skip-conflicts to push the clean ones.")
            for item, _ in problems:
                item["status"] = "studio-push-conflict"
            write_manifest(manifest)
            return 1

        # ── phase 2: write ───────────────────────────────────────────────
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        pushed = 0
        failed: list[tuple[dict, str]] = []
        if already:
            for item in already:
                item["status"] = "synced"
                item.pop("studioSha256Before", None)
            write_manifest(manifest)

        if ready:
            print(f"\nPhase 2 — writing {len(ready)} script(s):", flush=True)
        for index, (item, desired, live) in enumerate(ready, start=1):
            label = f"[{index}/{len(ready)}] {item['file']}"
            saved = backup(item, live, stamp)
            try:
                push_source(client, studio_id, segments_of(item), desired, live)
                reread = read_studio_source(client, studio_id, segments_of(item))
                if sha256(reread) != item["sha256"]:
                    raise StudioMcpError(
                        "post-write verification failed; the pre-push source is at "
                        f"{saved}")
            except StudioMcpError as error:
                failed.append((item, str(error)))
                print(f"  {label}: FAILED — {error}", flush=True)
                continue
            item["status"] = "synced"
            item.pop("studioSha256Before", None)
            write_manifest(manifest)
            pushed += 1
            print(f"  {label}: pushed ({len(desired.encode('utf-8'))} bytes)",
                  flush=True)

        for item, _ in problems:
            item["status"] = "studio-push-conflict"
        write_manifest(manifest)

        print(f"\nDone: {pushed} pushed, {len(already)} already applied, "
              f"{len(problems)} conflict(s), {len(failed)} failed.")
        if ready:
            print(f"Pre-push sources saved under {BACKUP_ROOT / stamp}")
        for item, reason in failed:
            print(f"  FAILED {item['file']}: {reason}")
        return 1 if (problems or failed) else 0
    finally:
        client.close()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (StudioMcpError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"PUSH FAILED: {error}", file=sys.stderr)
        sys.exit(1)
