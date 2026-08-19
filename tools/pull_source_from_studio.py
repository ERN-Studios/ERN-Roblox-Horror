"""Audit and pull drifted script sources from Roblox Studio into the repo.

Reads .Source directly through execute_luau (never script_read, which can
return stale text after .Source writes — see project memory), compares every
mirrored Lua script against the repo copy, and rewrites repo files whose
Studio source differs. Updates studio-sync-manifest.json entries (bytes,
sha256, status) for every file it pulls.

Usage:
    python tools/pull_source_from_studio.py            # audit + pull drifted
    python tools/pull_source_from_studio.py --audit    # report only, no writes
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
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
SERVICES = (
    "ServerScriptService",
    "StarterPlayer",
    "ReplicatedStorage",
    "ServerStorage",
    "Workspace",
    "RobloxReplicatedStorage",
)
CHUNK_LINES = 1400
INVALID_WINDOWS_NAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')

ENUMERATE_LUAU = """
local services = {%s}
local out = {}
for _, serviceName in ipairs(services) do
    local ok, service = pcall(game.GetService, game, serviceName)
    if ok and service then
        for _, inst in ipairs(service:GetDescendants()) do
            if inst:IsA("LuaSourceContainer") then
                local segments = {inst.Name}
                local cur = inst.Parent
                while cur and cur ~= game do
                    table.insert(segments, 1, cur.Name)
                    cur = cur.Parent
                end
                local src = inst.Source:gsub("\\r\\n", "\\n")
                local h = 5381
                for i = 1, #src do
                    h = (h * 33 + string.byte(src, i)) %% 4294967296
                end
                local lineCount = 1
                for _ in string.gmatch(src, "\\n") do lineCount += 1 end
                table.insert(out, table.concat(
                    {table.concat(segments, "|"), inst.ClassName, #src, h, lineCount}, "\\t"))
            end
        end
    end
end
return table.concat(out, "\\n")
"""

READ_CHUNK_LUAU = """
local segments = {%s}
local cur = game
for _, name in ipairs(segments) do
    cur = cur:FindFirstChild(name)
    if not cur then return "@@MISSING@@" end
end
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


def luau_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def djb2(data: bytes) -> int:
    h = 5381
    for byte in data:
        h = (h * 33 + byte) % 4294967296
    return h


def repo_path_for(segments: list[str], class_name: str) -> Path | None:
    for segment in segments:
        if INVALID_WINDOWS_NAME.search(segment) or segment.endswith((" ", ".")):
            return None
    filename = f"{segments[-1]}.{class_name}.lua"
    return PROJECT_ROOT.joinpath(*segments[:-1], filename)


def execute_luau(client: StudioMcpClient, studio_id: str, code: str) -> str:
    return client.call(
        "execute_luau",
        {"studio_id": studio_id, "datamodel_type": "Edit", "code": code},
    )


def pull_source(
    client: StudioMcpClient, studio_id: str, segments: list[str], line_count: int
) -> str:
    seg_literals = ", ".join(luau_string(s) for s in segments)
    parts: list[str] = []
    first = 1
    while first <= line_count:
        code = READ_CHUNK_LUAU % (seg_literals, first, CHUNK_LINES)
        chunk = execute_luau(client, studio_id, code)
        if chunk == "@@MISSING@@":
            raise StudioMcpError(f"Script vanished mid-pull: {segments}")
        parts.append(chunk)
        first += CHUNK_LINES
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true", help="report drift only")
    parser.add_argument(
        "--force",
        action="store_true",
        help="also overwrite files queued for a Studio push (destroys those edits)",
    )
    args = parser.parse_args()

    # Files awaiting push_repo_to_studio.py are NEWER in the repo than in Studio.
    # Pulling them would silently replace those edits with Studio's older source.
    manifest_now = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    protected = {
        item["file"]
        for item in manifest_now.get("items", [])
        if item.get("status") in ("pending-studio-push", "studio-push-conflict")
    }

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio_id = select_studio(client, STUDIO_NAME, 20.0)

        service_list = ", ".join(luau_string(s) for s in SERVICES)
        listing = execute_luau(client, studio_id, ENUMERATE_LUAU % service_list)

        studio_files: dict[str, tuple[list[str], str, int, int, int]] = {}
        for line in listing.split("\n"):
            if not line.strip():
                continue
            path_key, class_name, size, digest, line_count = line.split("\t")
            segments = path_key.split("|")
            studio_files[path_key] = (
                segments,
                class_name,
                int(size),
                int(digest),
                int(line_count),
            )

        drifted: list[str] = []
        unmappable: list[str] = []
        matched = 0
        for path_key, (segments, class_name, size, digest, _) in studio_files.items():
            destination = repo_path_for(segments, class_name)
            if destination is None:
                unmappable.append(path_key)
                continue
            if destination.exists():
                text = destination.read_text(encoding="utf-8").replace("\r\n", "\n")
                data = text.encode("utf-8")
                if len(data) == size and djb2(data) == digest:
                    matched += 1
                    continue
            drifted.append(path_key)

        # repo mirror files with no Studio counterpart
        studio_paths = {
            str(repo_path_for(seg, cls))
            for seg, cls, *_ in studio_files.values()
            if repo_path_for(seg, cls) is not None
        }
        orphans: list[Path] = []
        for service in SERVICES:
            service_dir = PROJECT_ROOT / service
            if not service_dir.is_dir():
                continue
            for lua_file in service_dir.rglob("*.lua"):
                if str(lua_file) not in studio_paths:
                    orphans.append(lua_file.relative_to(PROJECT_ROOT))

        print(f"Studio scripts: {len(studio_files)}  matched: {matched}  "
              f"drifted/missing in repo: {len(drifted)}")
        for path_key in drifted:
            print(f"  DRIFT  {path_key.replace('|', '.')}")
        for path_key in unmappable:
            print(f"  SKIP (unmappable name)  {path_key.replace('|', '.')}")
        for orphan in orphans:
            print(f"  ORPHAN (in repo, not in Studio)  {orphan}")

        if args.audit or not drifted:
            return 0

        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        manifest_by_file = {item["file"]: item for item in manifest.get("items", [])}

        skipped_protected: list[str] = []
        for path_key in drifted:
            segments, class_name, size, digest, line_count = studio_files[path_key]
            candidate = repo_path_for(segments, class_name)
            if candidate is not None and not args.force:
                candidate_rel = candidate.relative_to(PROJECT_ROOT).as_posix()
                if candidate_rel in protected:
                    skipped_protected.append(candidate_rel)
                    continue
            source = pull_source(client, studio_id, segments, line_count)
            data = source.encode("utf-8")
            if len(data) != size or djb2(data) != digest:
                raise StudioMcpError(
                    f"Pulled source failed verification for {path_key} "
                    f"(got {len(data)} bytes, expected {size})"
                )
            destination = repo_path_for(segments, class_name)
            assert destination is not None
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(source, encoding="utf-8", newline="\n")
            rel = destination.relative_to(PROJECT_ROOT).as_posix()
            print(f"  PULLED {rel} ({len(data)} bytes)")

            entry = manifest_by_file.get(rel)
            if entry is None:
                entry = {
                    "studioPath": ".".join(segments),
                    "className": class_name,
                    "file": rel,
                }
                manifest.setdefault("items", []).append(entry)
            entry["bytes"] = len(data)
            entry["sha256"] = hashlib.sha256(data).hexdigest()
            entry["status"] = "synced"

        if skipped_protected:
            print(
                f"\n  SKIPPED {len(skipped_protected)} file(s) queued for a Studio "
                "push — pulling them would replace your unpushed edits with "
                "Studio's older source:"
            )
            for rel in skipped_protected:
                print(f"    {rel}")
            print(
                "  Run tools/push_repo_to_studio.py first, or pass --force to "
                "discard those edits."
            )

        MANIFEST_PATH.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
        )
        print("Manifest updated.")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    sys.exit(main())
