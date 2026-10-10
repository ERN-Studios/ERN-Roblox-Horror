"""Read-only baseline diagnostics for the current generic installer.

The actual Python main() runs only against an owned temporary mirror/manifest
and a fake MCP adapter. Generated lookup/update bodies run in real offline
Luau, with the existing FakeStudio DataModel and a documented JSON boundary.
No real MCP client, native Studio, production source or manifest writes occur.
"""
from __future__ import annotations

import argparse
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "tests"))
if not os.environ.get("LUAU_BIN"):
    os.environ["LUAU_BIN"] = str(Path(tempfile.gettempdir()) / "codex-luau-0.737" / "luau.exe")

import install_new_scripts as installer
import fakestudio

FILE = "ServerScriptService/InstallerProbe.ModuleScript.lua"
STUDIO_PATH = "ServerScriptService.InstallerProbe"
SOURCE = "return 'candidate'\n"
OLD = "return 'old baseline'\n"
FOREIGN = "return 'concurrent Studio author'\n"

JSON_BOUNDARY = r'''
local hs = game:GetService("HttpService")
local meta, previous = getmetatable(hs), getmetatable(hs).__index
meta.__index = function(self, key)
    if key == "JSONEncode" then
        return function(_, value)
            if value.missing then return "MISSING" end
            return value.class .. "|" .. tohex(value.source)
        end
    end
    return previous(self, key)
end
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pins() -> dict[str, dict[str, str | int]]:
    paths = ["tools/install_new_scripts.py", "tools/install_trello_new_scripts.py",
             "tools/sync_from_studio.py", "tools/push_repo_to_studio.py",
             "tools/studio_source_contract.py", "tools/tests/test_install_new_scripts.py",
             "tools/tests/fakestudio.py", "studio-sync-manifest.json",
             "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"]
    return {path: {"bytes": len(data := (ROOT / path).read_bytes()), "sha256": digest(data)}
            for path in paths}


class OwnedClient:
    def __init__(self, held: str, class_name: str, race: bool) -> None:
        self.studio = fakestudio.FakeStudio()
        self.studio.add_script(STUDIO_PATH, class_name, held)
        self.race = race
        self.closed = False
        self.initialized = False
        self.calls: list[str] = []
        self.lookup_count = 0
        self.update_count = 0

    def initialize(self) -> None:
        self.initialized = True

    def close(self) -> None:
        self.closed = True

    def call(self, tool: str, arguments: dict | None = None) -> str:
        self.calls.append(tool)
        arguments = arguments or {}
        if tool == "list_roblox_studios":
            return json.dumps({"studios": [{"id": "offline-owned-installer",
                "name": f"{installer.PLACE} (placeId: 131311258779917)"}]})
        if tool != "execute_luau":
            raise AssertionError(f"Unexpected call; no native fallback permitted: {tool}")
        assert arguments["studio_id"] == "offline-owned-installer"
        assert arguments["datamodel_type"] == "Edit"
        code = arguments["code"]
        if code == installer.lua_lookup(STUDIO_PATH):
            self.lookup_count += 1
            payload = self.studio.execute(JSON_BOUNDARY + code)
            if payload == "MISSING":
                return json.dumps({"missing": True})
            class_name, rawhex = payload.split("|", 1)
            return json.dumps({"class": class_name, "source": bytes.fromhex(rawhex).decode("utf8")})
        assert code == installer.lua_update(STUDIO_PATH, SOURCE), "Unreviewed payload rejected"
        self.update_count += 1
        interleave = ""
        if self.race:
            # Real generated UpdateSourceAsync callback is handed a Source that
            # differs from the Python lookup baseline. This controlled engine
            # boundary interleaving models a concurrent editor write.
            interleave = '''
local ses = game:GetService("ScriptEditorService")
local meta, previous = getmetatable(ses), getmetatable(ses).__index
meta.__index = function(self, key)
 if key == "UpdateSourceAsync" then
  return function(_, target, callback)
   target.Source = fromhex("''' + FOREIGN.encode().hex() + '''")
   return previous(self, key)(self, target, callback)
  end
 end
 return previous(self, key)
end
'''
        return self.studio.execute(interleave + code)


def case(name: str, held: str, *, class_name: str = "ModuleScript", overwrite: bool = False,
         race: bool = False, status: str = "synced") -> dict:
    with tempfile.TemporaryDirectory(prefix="mongotv-installer-diagnostic-") as tmp:
        root = Path(tmp)
        mirror = root / FILE
        mirror.parent.mkdir(parents=True)
        mirror.write_bytes(SOURCE.encode())
        row = {"studioPath": STUDIO_PATH, "file": FILE, "className": "ModuleScript",
               "bytes": len(SOURCE.encode()), "sha256": digest(SOURCE.encode()), "status": status,
               "segments": STUDIO_PATH.split("."),
               "properties": {"Archivable": False, "LinkedSource": ""},
               "attributes": {"AuthoringRevision": 17}, "tags": ["AuthoringProbe"],
               "sourceEditorMatches": True}
        if status != "synced":
            row["studioSha256Before"] = digest(OLD.encode())
        original = {"items": [row], "counts": {"scripts": 1, "remoteEvents": 0, "total": 1},
                    "formatVersion": 1, "source": "owned offline fixture"}
        manifest = root / "studio-sync-manifest.json"
        manifest.write_bytes((json.dumps(original, indent=2) + "\n").encode())
        manifest_before = manifest.read_bytes()
        client = OwnedClient(held, class_name, race)
        output = io.StringIO()
        argv = ["install_new_scripts.py", FILE] + (["--overwrite"] if overwrite else [])
        with patch.object(installer, "ROOT", root), \
             patch.object(installer, "StudioMcpClient", lambda _: client), \
             patch.object(installer, "find_mcp_batch", lambda: root / "NO-REAL-MCP"), \
             patch.object(installer.time, "sleep", lambda _: None), \
             patch.object(sys, "argv", argv), redirect_stdout(output):
            result = installer.main()
        after = json.loads(manifest.read_text(encoding="utf8"))
        current = next(r for r in after["items"] if r["file"] == FILE)
        dropped = sorted(set(row) - set(current))
        held_after = client.studio.source_of(STUDIO_PATH)
        assert client.initialized and client.closed
        assert mirror.read_bytes() == SOURCE.encode()
        if name in {"default-different-refuses", "class-mismatch-refuses"}:
            assert result == 1 and held_after == held and client.update_count == 0
            assert manifest.read_bytes() == manifest_before
        else:
            assert result == 0 and held_after == SOURCE
            assert {"segments", "properties", "attributes", "tags", "sourceEditorMatches"} <= set(dropped)
        if race:
            assert client.update_count == 1 and held_after != FOREIGN
        if status != "synced":
            assert current["status"] == "synced" and "studioSha256Before" in dropped
        return {"case": name, "observedExpectedBaseline": True, "exitCode": result,
                "fakeLuauCalls": client.studio.calls, "lookupCount": client.lookup_count,
                "updateCount": client.update_count, "droppedManifestFields": dropped,
                "manifestChanged": manifest.read_bytes() != manifest_before,
                "heldSourceAfterSHA256": digest((held_after or "").encode()),
                "concurrentSourceOverwritten": race and held_after != FOREIGN,
                "stdout": output.getvalue()}


def run() -> dict:
    assert fakestudio.LUAU.is_file(), "Real offline Luau binary required"
    before = pins()
    cases = [case("exact-existing-erases-metadata", SOURCE),
             case("default-different-refuses", OLD),
             case("class-mismatch-refuses", SOURCE, class_name="Script"),
             case("overwrite-concurrent-source", OLD, overwrite=True, race=True),
             case("exact-existing-clears-pending-baseline", SOURCE, status="pending-studio-push")]
    after = pins()
    assert before == after, "Protected production inputs changed; reject result"
    return {"schema": "foundation-next-installer-baseline-v1", "diagnosticCompleted": True,
            "caseCount": len(cases), "cases": cases, "protectedInputsBefore": before,
            "protectedInputsAfter": after, "protectedInputsUnchanged": True,
            "realMcpCalls": 0, "nativeStudioWrites": 0, "productionWrites": 0,
            "scope": "Current Python installer main and actual generated Luau on owned temporary fake DataModel; JSON and concurrent editor boundaries are synthetic. Existing bugs reproduced, not a fix or native authoring certification.",
            "diagnosticSHA256": digest(Path(__file__).read_bytes()), "luauBinary": str(fakestudio.LUAU)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    result = run()
    with args.receipt.open("x", encoding="utf8", newline="\n") as stream:
        stream.write(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: result[k] for k in ("diagnosticCompleted", "caseCount", "protectedInputsUnchanged", "realMcpCalls", "nativeStudioWrites", "productionWrites")}))
