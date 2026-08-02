"""Mirror scripts and RemoteEvents from the open Roblox Studio place.

The script uses Roblox Studio's built-in MCP proxy. It is intentionally
one-way: Studio is the source of truth and this project is the destination.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time
from typing import Any


PROTOCOL_VERSION = "2024-11-05"
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}
LINE_PREFIX = re.compile(r"^\s*\d+\N{RIGHTWARDS ARROW}")
INVALID_WINDOWS_NAME = re.compile(r'[<>:"/\\|?*]')


class StudioMcpError(RuntimeError):
    """Raised when Studio MCP cannot complete a requested operation."""


class StudioMcpClient:
    def __init__(self, mcp_batch: Path) -> None:
        self._next_id = 0
        self._stdout: queue.Queue[str] = queue.Queue()
        self._stderr: queue.Queue[str] = queue.Queue()
        self._process = subprocess.Popen(
            ["cmd.exe", "/c", str(mcp_batch)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        assert self._process.stdout is not None
        assert self._process.stderr is not None
        threading.Thread(
            target=self._collect_lines,
            args=(self._process.stdout, self._stdout),
            daemon=True,
        ).start()
        threading.Thread(
            target=self._collect_lines,
            args=(self._process.stderr, self._stderr),
            daemon=True,
        ).start()

    @staticmethod
    def _collect_lines(stream: Any, destination: queue.Queue[str]) -> None:
        for line in stream:
            destination.put(line.rstrip("\r\n"))

    def close(self) -> None:
        if self._process.poll() is not None:
            return
        self._process.terminate()
        try:
            self._process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self._process.kill()
            self._process.wait(timeout=2)

    def _send(self, payload: dict[str, Any]) -> None:
        if self._process.poll() is not None:
            diagnostics = "\n".join(list(self._stderr.queue))
            raise StudioMcpError(
                f"Studio MCP exited with code {self._process.returncode}: {diagnostics}"
            )
        assert self._process.stdin is not None
        self._process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        self._process.stdin.flush()

    def _request(
        self, method: str, params: dict[str, Any], timeout: float = 60
    ) -> dict[str, Any]:
        self._next_id += 1
        request_id = self._next_id
        self._send(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params,
            }
        )
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                line = self._stdout.get(timeout=0.25)
            except queue.Empty:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("id") != request_id:
                continue
            if "error" in message:
                raise StudioMcpError(json.dumps(message["error"], ensure_ascii=False))
            return message
        diagnostics = "\n".join(list(self._stderr.queue))
        raise StudioMcpError(
            f"Timed out waiting for MCP method {method}. Diagnostics: {diagnostics}"
        )

    def initialize(self) -> None:
        response = self._request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "MongoTV Studio Sync", "version": "1.0"},
            },
        )
        server = response.get("result", {}).get("serverInfo", {})
        if server.get("name") != "RobloxStudio":
            raise StudioMcpError(f"Unexpected MCP server: {server!r}")
        self._send(
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            }
        )

    def call(self, tool: str, arguments: dict[str, Any] | None = None) -> str:
        response = self._request(
            "tools/call",
            {"name": tool, "arguments": arguments or {}},
        )
        result = response.get("result", {})
        blocks = result.get("content", [])
        text = "\n".join(
            block.get("text", "") for block in blocks if block.get("type") == "text"
        )
        if result.get("isError"):
            raise StudioMcpError(f"{tool} failed: {text}")
        return text

    def list_tools(self) -> list[dict[str, Any]]:
        response = self._request("tools/list", {})
        return response.get("result", {}).get("tools", [])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Mirror every Studio script and RemoteEvent into this project."
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Destination project root (defaults to the parent of tools/).",
    )
    parser.add_argument(
        "--studio-name",
        default="Backrooms: No Way Out",
        help="Exact Studio place name to select.",
    )
    parser.add_argument(
        "--connect-timeout",
        type=float,
        default=15,
        help="Seconds to wait for Studio to connect to its MCP proxy.",
    )
    return parser.parse_args()


def find_mcp_batch() -> Path:
    local_app_data = os.environ.get("LOCALAPPDATA")
    if not local_app_data:
        raise StudioMcpError("LOCALAPPDATA is not defined")
    batch = Path(local_app_data) / "Roblox" / "mcp.bat"
    if not batch.is_file():
        raise StudioMcpError(f"Roblox Studio MCP launcher was not found: {batch}")
    return batch


def select_studio(
    client: StudioMcpClient, expected_name: str, timeout: float
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    studios: list[dict[str, Any]] = []
    while time.monotonic() < deadline:
        try:
            payload = json.loads(client.call("list_roblox_studios"))
        except StudioMcpError as error:
            if "Not connected to the WS host" not in str(error):
                raise
            time.sleep(1)
            continue
        studios = payload.get("studios", [])
        matches = [studio for studio in studios if studio.get("name") == expected_name]
        if len(matches) == 1:
            selected = matches[0]
            client.call("set_active_studio", {"studio_id": selected["id"]})
            return selected
        if len(matches) > 1:
            active = [studio for studio in matches if studio.get("active")]
            if len(active) == 1:
                client.call("set_active_studio", {"studio_id": active[0]["id"]})
                return active[0]
            raise StudioMcpError(
                f"More than one Studio instance is named {expected_name!r}: {matches!r}"
            )
        time.sleep(1)
    raise StudioMcpError(
        f"Studio {expected_name!r} did not connect within {timeout:g}s. "
        f"Connected instances: {studios!r}"
    )


def search_instances(client: StudioMcpClient, class_name: str) -> list[dict[str, Any]]:
    text = client.call(
        "search_game_tree",
        {"instance_type": class_name, "head_limit": 1000, "max_depth": 10},
    )
    items = json.loads(text)
    if not isinstance(items, list):
        raise StudioMcpError(f"Unexpected search_game_tree response: {text[:500]}")
    return items


def decode_script_read(text: str) -> str:
    decoded: list[str] = []
    for line_number, line in enumerate(text.split("\n"), start=1):
        line = line.removesuffix("\r")
        if not LINE_PREFIX.match(line):
            raise StudioMcpError(
                "script_read returned an unnumbered line at response line "
                f"{line_number}: {line[:200]!r}"
            )
        decoded.append(LINE_PREFIX.sub("", line, count=1))
    return "\n".join(decoded)


def checked_components(full_path: str) -> list[str]:
    components = full_path.split(".")
    if len(components) < 2:
        raise StudioMcpError(f"Unexpected Studio path: {full_path!r}")
    for component in components:
        if not component or component in {".", ".."}:
            raise StudioMcpError(f"Unsafe Studio path component: {full_path!r}")
        if INVALID_WINDOWS_NAME.search(component) or component.endswith((" ", ".")):
            raise StudioMcpError(
                f"Studio name cannot be mirrored exactly on Windows: {full_path!r}"
            )
    return components


def normalized_destination(root: Path, item: dict[str, Any]) -> Path:
    components = checked_components(item["fullPath"])
    class_name = item["className"]
    extension = ".txt" if class_name == "RemoteEvent" else ".lua"
    filename = f"{components[-1]}.{class_name}{extension}"
    return root.joinpath(*components[:-1], filename)


def normalize_existing_case(path: Path) -> None:
    if not path.parent.is_dir():
        return
    match = next(
        (candidate for candidate in path.parent.iterdir() if candidate.name.lower() == path.name.lower()),
        None,
    )
    if match is None or match.name == path.name:
        return
    temporary = match.with_name(match.name + ".case-normalizing")
    counter = 0
    while temporary.exists():
        counter += 1
        temporary = match.with_name(match.name + f".case-normalizing-{counter}")
    match.rename(temporary)
    temporary.rename(path)


def write_if_changed(path: Path, content: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalize_existing_case(path)
    encoded = content.encode("utf-8")
    if path.is_file() and path.read_bytes() == encoded:
        return "unchanged"
    state = "updated" if path.exists() else "created"
    path.write_bytes(encoded)
    return state


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def remote_marker(item: dict[str, Any]) -> str:
    return (
        "NOT a script — this file mirrors a RemoteEvent object in Roblox Studio.\n\n"
        f"Studio path: {item['fullPath']}\n"
        "Object type: RemoteEvent\n"
    )


def mirrored_candidates(root: Path) -> set[str]:
    patterns = (
        re.compile(r"\.(?:Script|LocalScript|ModuleScript)\.lua$", re.IGNORECASE),
        re.compile(r"\.RemoteEvent\.txt$", re.IGNORECASE),
    )
    services = ["Workspace", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer"]
    result: set[str] = set()
    for service in services:
        service_root = root / service
        if not service_root.is_dir():
            continue
        for path in service_root.rglob("*"):
            if path.is_file() and any(pattern.search(path.name) for pattern in patterns):
                result.add(path.relative_to(root).as_posix())
    return result


def sync(args: argparse.Namespace) -> dict[str, Any]:
    project_root = args.project_root.resolve()
    if not project_root.is_dir():
        raise StudioMcpError(f"Project root does not exist: {project_root}")

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, args.studio_name, args.connect_timeout)
        state = client.call("get_studio_state")
        if "Available DataModels: Edit" not in state:
            raise StudioMcpError(f"Studio is not available in Edit mode: {state}")

        scripts = search_instances(client, "LuaSourceContainer")
        remotes = search_instances(client, "RemoteEvent")
        items = scripts + remotes

        seen_paths: set[str] = set()
        manifest_items: list[dict[str, Any]] = []
        status_counts = {"created": 0, "updated": 0, "unchanged": 0}

        for index, item in enumerate(items, start=1):
            class_name = item.get("className")
            if class_name not in SCRIPT_CLASSES | {"RemoteEvent"}:
                raise StudioMcpError(f"Unexpected class in search result: {item!r}")
            full_path = item.get("fullPath")
            if not isinstance(full_path, str) or full_path in seen_paths:
                raise StudioMcpError(f"Missing or duplicate Studio path: {item!r}")
            seen_paths.add(full_path)

            destination = normalized_destination(project_root, item)
            relative = destination.relative_to(project_root).as_posix()
            print(f"[{index:02d}/{len(items):02d}] {full_path} -> {relative}", flush=True)

            if class_name == "RemoteEvent":
                if destination.is_file():
                    content = destination.read_text(encoding="utf-8", errors="strict")
                    status = "unchanged"
                else:
                    content = remote_marker(item)
                    status = write_if_changed(destination, content)
            else:
                source = client.call(
                    "script_read",
                    {
                        "target_file": f"game.{full_path}",
                        "should_read_entire_file": True,
                    },
                )
                content = decode_script_read(source)
                status = write_if_changed(destination, content)

            status_counts[status] += 1
            data = destination.read_bytes()
            expected = content.encode("utf-8")
            if data != expected:
                raise StudioMcpError(f"Verification failed after writing {destination}")
            manifest_items.append(
                {
                    "studioPath": full_path,
                    "className": class_name,
                    "file": relative,
                    "bytes": len(data),
                    "sha256": sha256_bytes(data),
                    "status": status,
                }
            )

        expected_files = {item["file"].lower() for item in manifest_items}
        extras = sorted(
            path
            for path in mirrored_candidates(project_root)
            if path.lower() not in expected_files
        )
        manifest = {
            "formatVersion": 1,
            "source": "Roblox Studio built-in MCP",
            "studio": {"name": studio["name"], "id": studio["id"]},
            "counts": {
                "scripts": len(scripts),
                "remoteEvents": len(remotes),
                "total": len(items),
                **status_counts,
            },
            "extraMirroredFilesNotInStudio": extras,
            "items": manifest_items,
        }
        manifest_path = project_root / "studio-sync-manifest.json"
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        return manifest
    finally:
        client.close()


def main() -> int:
    args = parse_args()
    try:
        manifest = sync(args)
    except (StudioMcpError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"SYNC FAILED: {error}", file=sys.stderr)
        return 1
    counts = manifest["counts"]
    print(
        "SYNC COMPLETE: "
        f"{counts['scripts']} scripts, {counts['remoteEvents']} RemoteEvents; "
        f"{counts['created']} created, {counts['updated']} updated, "
        f"{counts['unchanged']} unchanged."
    )
    extras = manifest["extraMirroredFilesNotInStudio"]
    if extras:
        print("Extra mirror-shaped files not present in Studio:")
        for path in extras:
            print(f"  - {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
