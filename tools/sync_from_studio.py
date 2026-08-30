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



# A default Windows console is cp1252 and raises UnicodeEncodeError on anything
# it cannot represent -- including from argparse's --help, which renders the
# module docstring. Degrading those characters is always better than aborting a
# release tool, so replace rather than raise. Everything this file prints is
# ASCII anyway; this is the belt to that braces.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError, OSError):
        pass
sys.path.insert(0, str(Path(__file__).resolve().parent))

from studio_source_contract import (  # noqa: E402
    DRIFTED,
    EXACT,
    TRAILING_NEWLINE,
    TRAILING_NEWLINE_FLAG,
    canonical_bytes,
    classify,
    normalize,
    refresh_trailing_newline_metadata,
    sha256_of,
)

PROTOCOL_VERSION = "2024-11-05"
SCRIPT_CLASSES = {"Script", "LocalScript", "ModuleScript"}
LEGACY_STUDIO_NAME = "Backrooms: No Way Out"
RELEASE_STUDIO_NAME = "BACKROOMS: STAY QUIET [CO-OP HORROR]"
KNOWN_STUDIO_NAMES = frozenset((LEGACY_STUDIO_NAME, RELEASE_STUDIO_NAME))
EXPECTED_PLACE_ID = 131311258779917

# StudioMCP.exe needs a moment after launch before it can reach Studio's plugin;
# the wording of that transient failure has changed between Studio builds.
TRANSIENT_CONNECT_ERRORS = (
    "Not connected to the WS host",
    "Unable to reach Roblox Studio",
)
# Studio now reports instances as "Place Name (placeId: 123)"; older builds
# reported a bare name. Strip the suffix so both forms compare equal.
STUDIO_NAME_SUFFIX = re.compile(r"\s*\((?:placeId:[^)]*|[^)]*\.rbxlx?)\)\s*$")
STUDIO_PLACE_ID_SUFFIX = re.compile(r"\s*\(placeId:\s*(\d+)\)\s*$", re.IGNORECASE)
LINE_PREFIX = re.compile(r"^\s*\d+\N{RIGHTWARDS ARROW}")
INVALID_WINDOWS_NAME = re.compile(r'[<>:"/\\|?*]')


def studio_display_name(studio: dict[str, Any]) -> str:
    """Compare Studio names ignoring the trailing place-id suffix."""
    return STUDIO_NAME_SUFFIX.sub("", str(studio.get("name", ""))).strip()


def studio_place_id(studio: dict[str, Any]) -> int | None:
    """Read the published place id from a field or Studio's name suffix."""
    for key in ("placeId", "place_id"):
        raw = studio.get(key)
        if raw is not None:
            try:
                return int(raw)
            except (TypeError, ValueError):
                return -1  # advertised but malformed: fail closed
    name = str(studio.get("name", ""))
    match = STUDIO_PLACE_ID_SUFFIX.search(name)
    if match:
        return int(match.group(1))
    if re.search(r"\(placeId:", name, re.IGNORECASE):
        return -1  # suffix advertised but malformed: fail closed
    return None


def accepted_studio_names(expected_name: str) -> frozenset[str]:
    """Keep the known rename migration exact while rejecting unrelated names."""
    if expected_name in KNOWN_STUDIO_NAMES:
        return KNOWN_STUDIO_NAMES
    return frozenset((expected_name,))


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
        default=RELEASE_STUDIO_NAME,
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
            if not any(marker in str(error)
                       for marker in TRANSIENT_CONNECT_ERRORS):
                raise
            time.sleep(1)
            continue
        studios = payload.get("studios", [])
        accepted_names = accepted_studio_names(expected_name)
        name_matches = [
            studio
            for studio in studios
            if studio_display_name(studio) in accepted_names
        ]
        expected_place_id = (
            EXPECTED_PLACE_ID if expected_name in KNOWN_STUDIO_NAMES else None
        )
        matches = [
            studio
            for studio in name_matches
            if expected_place_id is None
            or studio_place_id(studio) in (None, expected_place_id)
        ]
        wrong_place = [
            studio
            for studio in name_matches
            if expected_place_id is not None
            and studio_place_id(studio) not in (None, expected_place_id)
        ]
        if wrong_place and not matches:
            raise StudioMcpError(
                f"Studio title matched {sorted(accepted_names)!r}, but place id "
                f"did not match {expected_place_id}: {wrong_place!r}"
            )
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            active = [studio for studio in matches if studio.get("active")]
            if len(active) == 1:
                return active[0]
            raise StudioMcpError(
                f"More than one Studio instance matches "
                f"{sorted(accepted_names)!r}: {matches!r}"
            )
        time.sleep(1)
    raise StudioMcpError(
        f"Studio {sorted(accepted_studio_names(expected_name))!r} did not connect "
        f"within {timeout:g}s. "
        f"Connected instances: {studios!r}"
    )


def search_instances(
    client: StudioMcpClient, studio_id: str, class_name: str
) -> list[dict[str, Any]]:
    text = client.call(
        "search_game_tree",
        {
            "studio_id": studio_id,
            "datamodel_type": "Edit",
            "instance_type": class_name,
            "head_limit": 1000,
            "max_depth": 10,
        },
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
    """Kept for callers holding raw bytes; the shared contract owns the rule."""
    return sha256_of(data.decode("utf-8"))


def read_canonical(path: Path) -> str:
    """The mirrored file as CONTENT, with the checkout's line endings removed.

    Every comparison in this tool is a comparison of content. A Windows checkout
    holds 57 of these scripts CRLF, and Studio serves LF; reading raw and
    comparing raw is how a file that agrees perfectly with Studio came to be
    reported as a verification failure.
    """
    return normalize(path.read_text(encoding="utf-8"))


def verify_mirrored(path: Path, expected_text: str) -> None:
    """The file on disk must hold `expected_text` -- as CONTENT, not as bytes.

    This runs after both branches of the reconciliation:

      * `write` just wrote LF bytes, so raw and canonical agree and this is the
        plain post-write check it always was.
      * `keep` deliberately did NOT touch the file. Its bytes are whatever the
        checkout produced -- CRLF on Windows -- and demanding they equal the
        LF-normalised expectation failed every one of the 57 CRLF scripts,
        including all 19 carrying the permitted trailing newline. Comparing
        canonically asserts the real invariant (the mirror still says what we
        decided it should say) without rewriting a file we chose to leave alone.
    """
    actual = read_canonical(path)
    if actual == normalize(expected_text):
        return
    raise StudioMcpError(
        f"Verification failed after reconciling {path}: "
        f"the file holds {len(actual)} canonical characters, expected "
        f"{len(normalize(expected_text))}"
    )


def load_manifest(project_root: Path) -> dict[str, Any]:
    path = project_root / "studio-sync-manifest.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def trailing_newline_flags(manifest: dict[str, Any]) -> set[str]:
    """Which Studio paths are allowed one extra trailing newline in Studio.

    Keyed by studioPath, not by file, so the flag survives a file being renamed
    or re-derived, and so a full sync that rebuilds every item from scratch can
    still carry it forward.
    """
    return {
        item["studioPath"]
        for item in manifest.get("items", [])
        if item.get(TRAILING_NEWLINE_FLAG) is True and item.get("studioPath")
    }


def reconcile_source(existing_text: str | None, studio_text: str, *, flagged: bool):
    """What the MIRROR should hold for one script, and why.

    Returns (action, content, verdict):

      "keep"  -- the repo file already agrees with Studio under the shared
                 contract: byte-identical, or differing only by the one trailing
                 newline this entry is flagged for. The repo file is left alone.
      "write" -- genuine drift, or no mirrored file yet. Studio's source wins,
                 because Studio is the source of truth.

    This is the whole point of integrating the contract into the FULL sync. The
    old sync wrote every Studio byte into the repo unconditionally, so one run
    would have absorbed the nineteen transport newlines into the mirror, made
    every hash "agree", and erased the contract that was documenting them --
    silently, and with no drift left for anything to detect afterwards.
    """
    if existing_text is None:
        return "write", studio_text, "created"
    verdict = classify(existing_text, studio_text, allow_trailing_newline=flagged)
    if verdict == EXACT:
        return "keep", existing_text, EXACT
    if verdict == TRAILING_NEWLINE:
        return "keep", existing_text, TRAILING_NEWLINE
    return "write", studio_text, DRIFTED


def remote_marker(item: dict[str, Any]) -> str:
    return (
        "NOT a script -- this file mirrors a RemoteEvent object in Roblox Studio.\n\n"
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


def sync(args: argparse.Namespace, client_factory=None) -> dict[str, Any]:
    """Pull every mirrored script out of Studio and rebuild the manifest.

    `client_factory` exists so a test can drive THIS function -- the real
    reconciliation, the real verification, the real manifest rebuild -- against
    a fake Studio. The previous coverage called the helpers one at a time and
    hand-built a manifest item, which is exactly why it could not see that the
    loop below verified raw checkout bytes against canonical content and aborted
    the release on all 58 CRLF files.
    """
    project_root = args.project_root.resolve()
    if not project_root.is_dir():
        raise StudioMcpError(f"Project root does not exist: {project_root}")

    client = (client_factory or (lambda: StudioMcpClient(find_mcp_batch())))()
    try:
        client.initialize()
        studio = select_studio(client, args.studio_name, args.connect_timeout)
        studio_id = studio["id"]
        state = client.call("get_studio_state", {"studio_id": studio_id})
        if "Available DataModels: Edit" not in state:
            raise StudioMcpError(f"Studio is not available in Edit mode: {state}")

        scripts = search_instances(client, studio_id, "LuaSourceContainer")
        remotes = search_instances(client, studio_id, "RemoteEvent")
        items = scripts + remotes

        previous = load_manifest(project_root)
        flagged_paths = trailing_newline_flags(previous)

        seen_paths: set[str] = set()
        manifest_items: list[dict[str, Any]] = []
        status_counts = {"created": 0, "updated": 0, "unchanged": 0}
        permitted_newlines: list[str] = []

        for index, item in enumerate(items, start=1):
            class_name = item.get("className")
            if class_name not in SCRIPT_CLASSES | {"RemoteEvent"}:
                raise StudioMcpError(f"Unexpected class in search result: {item!r}")
            verdict: str | None = None
            full_path = item.get("fullPath")
            if not isinstance(full_path, str) or full_path in seen_paths:
                raise StudioMcpError(f"Missing or duplicate Studio path: {item!r}")
            seen_paths.add(full_path)

            destination = normalized_destination(project_root, item)
            relative = destination.relative_to(project_root).as_posix()
            print(f"[{index:02d}/{len(items):02d}] {full_path} -> {relative}", flush=True)

            if class_name == "RemoteEvent":
                if destination.is_file():
                    # Canonical, like every other read here: a CRLF marker file
                    # is the same marker file.
                    content = read_canonical(destination)
                    status = "unchanged"
                else:
                    content = remote_marker(item)
                    status = write_if_changed(destination, content)
            else:
                source = client.call(
                    "script_read",
                    {
                        "studio_id": studio_id,
                        "target_file": f"game.{full_path}",
                        "should_read_entire_file": True,
                    },
                )
                studio_text = decode_script_read(source)
                existing = read_canonical(destination) if destination.is_file() else None
                flagged = full_path in flagged_paths
                action, content, verdict = reconcile_source(
                    existing, studio_text, flagged=flagged
                )
                if action == "keep":
                    status = "unchanged"
                    if verdict == TRAILING_NEWLINE:
                        permitted_newlines.append(relative)
                        print(
                            f"        keeping the mirrored file: Studio holds the one "
                            f"permitted trailing newline",
                            flush=True,
                        )
                else:
                    status = write_if_changed(destination, content)

            status_counts[status] += 1
            verify_mirrored(destination, content)
            # The manifest describes CANONICAL repo content -- never the raw
            # transport, and never the checkout's line endings. A CRLF working
            # file and its LF counterpart are the same mirrored script, so they
            # must produce the same bytes and the same hash; recording the raw
            # length made the manifest a description of one machine's checkout.
            canonical = canonical_bytes(content)
            item = {
                "studioPath": full_path,
                "className": class_name,
                "file": relative,
                "bytes": len(canonical),
                "sha256": sha256_of(content),
                "status": status,
            }
            # Re-derived from the observed landing. An exact source clears a
            # stale historical flag; only the one verified +LF outcome retains it.
            if verdict == TRAILING_NEWLINE:
                item[TRAILING_NEWLINE_FLAG] = True
            manifest_items.append(item)

        expected_files = {item["file"].lower() for item in manifest_items}
        extras = sorted(
            path
            for path in mirrored_candidates(project_root)
            if path.lower() not in expected_files
        )
        manifest = {
            "formatVersion": 1,
            "source": "Roblox Studio built-in MCP",
            "finalNewlineContract": previous.get("finalNewlineContract", ""),
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
        refresh_trailing_newline_metadata(manifest)
        if permitted_newlines:
            print(
                f"\n{len(permitted_newlines)} mirrored file(s) kept under the permitted "
                "trailing-newline contract:",
                flush=True,
            )
            for relative in sorted(permitted_newlines):
                print(f"  +1 LF in Studio  {relative}", flush=True)

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
