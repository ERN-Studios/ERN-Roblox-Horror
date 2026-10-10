"""Mirror scripts and RemoteEvents from the open Roblox Studio place.

The script uses Roblox Studio's built-in MCP proxy. It is intentionally
one-way: Studio is the source of truth and this project is the destination.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
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
MIRRORED_SERVICES = (
    "ReplicatedFirst",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterPlayer",
    "Workspace",
    "RobloxReplicatedStorage",
)
LEGACY_STUDIO_NAME = "Backrooms: No Way Out"
RELEASE_STUDIO_NAME = "BACKROOMS: STAY QUIET [CO-OP HORROR]"
# The place was renamed for the update banner (2026-10-08); same place id, still checked below.
UPDATE_STUDIO_NAME = "(UPDATE) BACKROOMS: STAY QUIET"
UPDATE_STUDIO_NAME_BRACKETS = "[UPDATE] BACKROOMS: STAY QUIET"  # renamed again by the evening of 2026-10-08
KNOWN_STUDIO_NAMES = frozenset((LEGACY_STUDIO_NAME, RELEASE_STUDIO_NAME, UPDATE_STUDIO_NAME, UPDATE_STUDIO_NAME_BRACKETS))
EXPECTED_PLACE_ID = 131311258779917
EXPECTED_UNIVERSE_ID = 10559217407

# Read-only per-instance snapshot. Source stays in the existing chunk reader;
# only bounded hashes/metadata cross this response. Never reuse old repo props.
NATIVE_METADATA_LUAU = r'''
-- sync-native-metadata-v1
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local CS=game:GetService("CollectionService")
local RS=game:GetService("RunService")
local wanted={__SEGMENTS__}
local expectedClass=__CLASS__
local expectedPlace=__PLACE__
local expectedUniverse=__UNIVERSE__
assert(not RS:IsRunning(),"Native metadata requires Edit")
assert(expectedPlace==nil or game.PlaceId==expectedPlace,"Wrong place")
assert(expectedUniverse==nil or game.GameId==expectedUniverse,"Wrong universe")
local cur=game
for _,name in wanted do
 local found=nil
 for _,child in cur:GetChildren() do
  if child.Name==name then assert(found==nil,"Ambiguous native path");found=child end
 end
 assert(found,"Missing native path");cur=found
end
assert(cur.ClassName==expectedClass,"Native class changed")
local parent=cur.Parent
assert(parent,"Detached native instance")
local function sha(text)
 local b=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function properties()
 local p={Archivable=cur.Archivable}
 assert(type(p.Archivable)=="boolean","Archivable unreadable")
 if expectedClass~="RemoteEvent" then
  p.LinkedSource=cur.LinkedSource
  assert(type(p.LinkedSource)=="string","LinkedSource unreadable")
  if expectedClass~="ModuleScript" then
   p.Enabled=cur.Enabled;p.Disabled=cur.Disabled
   assert(type(p.Enabled)=="boolean" and type(p.Disabled)=="boolean" and p.Enabled~=p.Disabled,"Invalid Enabled aliases")
   local context=cur.RunContext
   assert(typeof(context)=="EnumItem","RunContext unreadable")
   p.RunContext=tostring(context)
  end
 end
 return p
end
local function attributes()
 local a=cur:GetAttributes()
 for key,value in a do
  local t=type(value)
  assert(type(key)=="string" and (t=="string" or t=="boolean" or (t=="number" and value==value and math.abs(value)<math.huge)),"Unsupported native attribute")
 end
 return a
end
local function tags()
 local values=CS:GetTags(cur)
 for _,value in values do assert(type(value)=="string","Invalid native tag") end
 table.sort(values)
 return values
end
local function same(a,b)
 for key,value in a do assert(type(b[key])==type(value) and b[key]==value,"Native metadata changed during read") end
 for key in b do assert(a[key]~=nil,"Native metadata changed during read") end
end
local props,attrs,labels=properties(),attributes(),tags()
local result={segments=wanted,path=cur:GetFullName(),className=cur.ClassName,
 instanceId=cur:GetDebugId(16),parentId=parent:GetDebugId(16),
 placeId=game.PlaceId,universeId=game.GameId,properties=props,attributes=attrs,tags=labels}
if expectedClass~="RemoteEvent" then
 local source=cur.Source
 local editor=SES:GetEditorSource(cur)
 assert(type(source)=="string" and type(editor)=="string" and source==editor,"Native Source/editor conflict")
 local canonical=source:gsub("\r\n","\n")
 result.rawSourceSHA256=sha(source);result.rawEditorSHA256=sha(editor)
 result.sourceSHA256=sha(canonical);result.canonicalBytes=#canonical
 result.sourceEditorMatches=true
 assert(cur.Source==source and SES:GetEditorSource(cur)==editor,"Native Source/editor changed during read")
end
same(props,properties());same(attrs,attributes());same(labels,tags())
assert(cur.Parent==parent and cur.ClassName==expectedClass and cur:GetFullName()==result.path,"Native identity changed during read")
assert(not RS:IsRunning() and game.PlaceId==result.placeId and game.GameId==result.universeId,"Native mode/place changed")
return H:JSONEncode(result)
'''

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


def require_edit_state(client: StudioMcpClient, studio_id: str) -> None:
    state = client.call("get_studio_state", {"studio_id": studio_id})
    modes = re.findall(r"^\s*-?\s*Current Studio Mode:\s*(.*?)\s*$", state, re.MULTILINE)
    if modes != ["Edit"] or "Available DataModels: Edit" not in state:
        raise StudioMcpError("Studio must currently be in Edit mode; no mode switch performed")


def native_metadata_code(segments: list[str], class_name: str, place_id: int | None, universe_id: int | None) -> str:
    from push_repo_to_studio import luau_string
    if class_name not in SCRIPT_CLASSES | {"RemoteEvent"}:
        raise StudioMcpError("Unsupported native metadata class")
    return (NATIVE_METADATA_LUAU.replace("__SEGMENTS__", ", ".join(luau_string(s) for s in segments))
            .replace("__CLASS__", luau_string(class_name))
            .replace("__PLACE__", "nil" if place_id is None else str(int(place_id)))
            .replace("__UNIVERSE__", "nil" if universe_id is None else str(int(universe_id))))


def validate_native_metadata(value: Any, segments: list[str], class_name: str, place_id: int | None, universe_id: int | None) -> None:
    def demand(condition: bool) -> None:
        if not condition:
            raise StudioMcpError("Invalid or conflicting native metadata; no stale repo metadata accepted")
    demand(isinstance(value, dict))
    demand(value.get("segments") == segments and value.get("path") == ".".join(segments) and value.get("className") == class_name)
    demand(all(isinstance(value.get(k), str) and value[k] for k in ("instanceId", "parentId")))
    demand(all(type(value.get(k)) is int and value[k] >= 0 for k in ("placeId", "universeId")))
    demand(place_id is None or value["placeId"] == place_id)
    demand(universe_id is None or value["universeId"] == universe_id)
    props = value.get("properties")
    wanted = {"Archivable"} if class_name == "RemoteEvent" else {"Archivable", "LinkedSource"}
    if class_name in {"Script", "LocalScript"}: wanted |= {"Enabled", "Disabled", "RunContext"}
    demand(isinstance(props, dict) and set(props) == wanted and type(props.get("Archivable")) is bool)
    if class_name != "RemoteEvent": demand(isinstance(props.get("LinkedSource"), str))
    if class_name in {"Script", "LocalScript"}:
        demand(type(props.get("Enabled")) is bool and type(props.get("Disabled")) is bool and props["Enabled"] is not props["Disabled"])
        demand(isinstance(props.get("RunContext"), str) and props["RunContext"].startswith("Enum.RunContext."))
    attrs, tags = value.get("attributes"), value.get("tags")
    demand(isinstance(attrs, dict) and all(isinstance(k, str) and (type(v) in (str, bool, int) or (type(v) is float and math.isfinite(v))) for k,v in attrs.items()))
    demand(isinstance(tags, list) and all(isinstance(t, str) for t in tags) and tags == sorted(set(tags)))
    if class_name != "RemoteEvent":
        demand(value.get("sourceEditorMatches") is True and type(value.get("canonicalBytes")) is int and value["canonicalBytes"] >= 0)
        demand(all(isinstance(value.get(k), str) and re.fullmatch(r"[0-9a-f]{64}", value[k]) for k in ("sourceSHA256", "rawSourceSHA256", "rawEditorSHA256")))
        demand(value["rawSourceSHA256"] == value["rawEditorSHA256"])


def read_native_record(client: StudioMcpClient, studio_id: str, item: dict[str, Any], place_id: int | None, universe_id: int | None) -> tuple[str | None, dict[str, Any]]:
    """Bracket the native chunk read with fresh same-instance metadata snapshots.

    Read-time per-row consistency, not a continuous epoch or atomic full export.
    Required/read/editor errors abort before this row's mirror is written.
    """
    from push_repo_to_studio import read_studio_source
    segments, class_name = checked_components(item["fullPath"]), item["className"]
    code = native_metadata_code(segments, class_name, place_id, universe_id)

    def capture() -> dict[str, Any]:
        try:
            value = json.loads(client.call("execute_luau", {"studio_id": studio_id, "datamodel_type": "Edit", "code": code}))
        except (ValueError, TypeError) as error:
            raise StudioMcpError("Unreadable native metadata response") from error
        # HttpService can encode an empty native attribute dictionary as [].
        # In this fixed schema only the empty form is equivalent to no attrs.
        if isinstance(value, dict) and value.get("attributes") == []:
            value["attributes"] = {}
        validate_native_metadata(value, segments, class_name, place_id, universe_id)
        return value

    require_edit_state(client, studio_id)
    before = capture()
    source = None if class_name == "RemoteEvent" else read_studio_source(client, studio_id, segments)
    after = capture()
    require_edit_state(client, studio_id)
    if before != after:
        raise StudioMcpError("Native Source/identity/properties/attributes/tags changed during chunk read")
    if source is not None:
        data = canonical_bytes(source)
        if len(data) != before["canonicalBytes"] or hashlib.sha256(data).hexdigest() != before["sourceSHA256"]:
            raise StudioMcpError("Native metadata/chunk Source hash mismatch")
    return source, before


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
    except (json.JSONDecodeError, OSError) as error:
        raise StudioMcpError(f"Cannot read the existing sync manifest: {path}: {error}") from error


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
    result: set[str] = set()
    for service in MIRRORED_SERVICES:
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

    previous = load_manifest(project_root)
    protected = [
        item.get("file") or item.get("studioPath") or "<unnamed entry>"
        for item in previous.get("items", [])
        if item.get("status") in {"pending-studio-push", "studio-push-conflict"}
    ]
    if protected:
        raise StudioMcpError(
            "Full sync refused: queued/conflicted repo work must be reconciled "
            "before pulling Studio: " + ", ".join(protected)
        )

    # The guarded push tool imports this MCP client, so resolve its shared
    # native reader only after this module has finished loading.
    client = (client_factory or (lambda: StudioMcpClient(find_mcp_batch())))()
    try:
        client.initialize()
        studio = select_studio(client, args.studio_name, args.connect_timeout)
        studio_id = studio["id"]
        require_edit_state(client, studio_id)
        expected_place = EXPECTED_PLACE_ID if args.studio_name in KNOWN_STUDIO_NAMES else studio_place_id(studio)
        expected_universe = EXPECTED_UNIVERSE_ID if args.studio_name in KNOWN_STUDIO_NAMES else None
        native_place: tuple[int, int] | None = None

        scripts = search_instances(client, studio_id, "LuaSourceContainer")
        remotes = search_instances(client, studio_id, "RemoteEvent")
        items = scripts + remotes

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
            studio_text, native_record = read_native_record(client, studio_id, item, expected_place, expected_universe)
            identity = (native_record["placeId"], native_record["universeId"])
            if native_place is not None and identity != native_place:
                raise StudioMcpError("Native place/universe changed during export")
            native_place = identity

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
                assert studio_text is not None
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
                "segments": native_record["segments"],
                "properties": native_record["properties"],
                "attributes": native_record["attributes"] or [],
                "tags": native_record["tags"],
            }
            if class_name in SCRIPT_CLASSES:
                item["sourceEditorMatches"] = native_record["sourceEditorMatches"]
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
