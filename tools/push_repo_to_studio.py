"""Push repo-side script fixes into the open Roblox Studio place.

Counterpart to pull_source_from_studio.py for the rare Studio-write direction.
Targets manifest entries whose status is "pending-studio-push": each such entry
records the NEW repo content (bytes/sha256) plus "studioSha256Before" — the
hash Studio is expected to still hold. The tool:

1. reads Studio's live .Source (execute_luau, chunked — never script_read),
2. refuses to overwrite when Studio drifted from studioSha256Before (unless the
   live source already equals the new content, which just marks it synced),
3. writes through ScriptEditorService:UpdateSourceAsync so open editors and
   LocalScript bytecode pick the change up (raw .Source writes do not),
4. re-reads and verifies, then flips the manifest entry to "synced".

Usage:
    python tools/push_repo_to_studio.py            # push all pending entries
    python tools/push_repo_to_studio.py --audit    # report only, no writes
    python tools/push_repo_to_studio.py --file ServerScriptService/EntityAI.Script.lua
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
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
STUDIO_NAME = "Backrooms: No Way Out"
READ_CHUNK_LINES = 1400
WRITE_CHUNK_BYTES = 60_000
BUFFER_NAME = "__RepoPushBuffer"

PATH_WALK_LUAU = """
local segments = {%s}
local cur = game
for _, name in ipairs(segments) do
    cur = cur:FindFirstChild(name)
    if not cur then return "@@MISSING@@" end
end
"""

READ_META_LUAU = PATH_WALK_LUAU + """
local src = cur.Source:gsub("\\r\\n", "\\n")
local h = 5381
for i = 1, #src do
    h = (h * 33 + string.byte(src, i)) %% 4294967296
end
local lineCount = 1
for _ in string.gmatch(src, "\\n") do lineCount += 1 end
return #src .. "\\t" .. h .. "\\t" .. lineCount
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

APPLY_LUAU = PATH_WALK_LUAU + """
local storage = game:GetService("ServerStorage")
local buffer = storage:FindFirstChild(%s)
if not buffer then return "@@NO_BUFFER@@" end
local newSource = buffer.Value
buffer:Destroy()
local ok, err = pcall(function()
    game:GetService("ScriptEditorService"):UpdateSourceAsync(cur, function()
        return newSource
    end)
end)
if not ok then return "@@WRITE_FAILED@@ " .. tostring(err) end
return "@@OK@@"
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


def execute_luau(client: StudioMcpClient, studio_id: str, code: str) -> str:
    return client.call(
        "execute_luau",
        {"studio_id": studio_id, "datamodel_type": "Edit", "code": code},
    )


def read_studio_source(client, studio_id, segments: list[str]) -> str:
    seg_literals = ", ".join(luau_string(s) for s in segments)
    meta = execute_luau(client, studio_id, READ_META_LUAU % seg_literals)
    if meta == "@@MISSING@@":
        raise StudioMcpError(f"Script not found in Studio: {segments}")
    size, digest, line_count = (int(part) for part in meta.split("\t"))
    parts: list[str] = []
    first = 1
    while first <= line_count:
        chunk = execute_luau(
            client, studio_id, READ_CHUNK_LUAU % (seg_literals, first, READ_CHUNK_LINES)
        )
        if chunk == "@@MISSING@@":
            raise StudioMcpError(f"Script vanished mid-read: {segments}")
        parts.append(chunk)
        first += READ_CHUNK_LINES
    source = "\n".join(parts)
    data = source.encode("utf-8")
    if len(data) != size or djb2(data) != digest:
        raise StudioMcpError(f"Chunked read failed verification for {segments}")
    return source


def push_source(client, studio_id, segments: list[str], source: str) -> None:
    buffer_literal = luau_string(BUFFER_NAME)
    data = source.encode("utf-8")
    offset = 0
    first = True
    while offset < len(data) or first:
        end = offset + WRITE_CHUNK_BYTES
        # never split a UTF-8 sequence or an escape across chunks: back up to
        # a byte boundary that starts a character
        while end < len(data) and (data[end] & 0xC0) == 0x80:
            end -= 1
        chunk = data[offset:end].decode("utf-8")
        result = execute_luau(
            client,
            studio_id,
            BUFFER_APPEND_LUAU
            % (
                buffer_literal,
                "true" if first else "false",
                buffer_literal,
                luau_string(chunk),
            ),
        )
        if result == "@@NO_BUFFER@@":
            raise StudioMcpError("Push buffer disappeared mid-transfer")
        first = False
        offset = end
    seg_literals = ", ".join(luau_string(s) for s in segments)
    result = execute_luau(
        client, studio_id, APPLY_LUAU % (seg_literals, buffer_literal)
    )
    if result != "@@OK@@":
        raise StudioMcpError(f"UpdateSourceAsync failed for {segments}: {result}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true", help="report only, no writes")
    parser.add_argument(
        "--file",
        action="append",
        default=None,
        help="limit to this manifest file path (repeatable)",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    pending = [
        item
        for item in manifest.get("items", [])
        if item.get("status") == "pending-studio-push"
        and (args.file is None or item["file"] in args.file)
    ]
    if not pending:
        print("Nothing pending: no manifest entries with status 'pending-studio-push'.")
        return 0
    for item in pending:
        if "studioSha256Before" not in item:
            raise StudioMcpError(
                f"{item['file']} is pending but has no studioSha256Before hash"
            )

    print(f"{len(pending)} script(s) pending push:")
    for item in pending:
        print(f"  {item['file']}")
    if args.audit:
        return 0

    client = StudioMcpClient(find_mcp_batch())
    pushed = 0
    conflicts: list[str] = []
    try:
        client.initialize()
        studio_id = select_studio(client, STUDIO_NAME, 20.0)

        for item in pending:
            segments = item["studioPath"].split(".")
            desired = (
                (PROJECT_ROOT / item["file"])
                .read_text(encoding="utf-8")
                .replace("\r\n", "\n")
            )
            desired_sha = sha256(desired)
            if desired_sha != item["sha256"]:
                raise StudioMcpError(
                    f"{item['file']}: repo content no longer matches its manifest "
                    "entry — re-run the repo-side manifest refresh first"
                )

            live = read_studio_source(client, studio_id, segments)
            live_sha = sha256(live)
            if live_sha == desired_sha:
                print(f"  ALREADY APPLIED {item['file']}")
            elif live_sha != item["studioSha256Before"]:
                conflicts.append(item["file"])
                print(
                    f"  CONFLICT {item['file']}: Studio drifted from the recorded "
                    "baseline — merge by hand, then re-record"
                )
                continue
            else:
                push_source(client, studio_id, segments, desired)
                reread = read_studio_source(client, studio_id, segments)
                if sha256(reread) != desired_sha:
                    raise StudioMcpError(
                        f"Post-push verification failed for {item['file']}"
                    )
                print(f"  PUSHED {item['file']} ({len(desired.encode('utf-8'))} bytes)")
                pushed += 1
            item["status"] = "synced"
            item.pop("studioSha256Before", None)
            MANIFEST_PATH.write_text(
                json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
            )

        print(
            f"Done: {pushed} pushed, "
            f"{len(pending) - pushed - len(conflicts)} already applied, "
            f"{len(conflicts)} conflict(s)."
        )
        return 1 if conflicts else 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
