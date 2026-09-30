"""Freeze a scoped, guarded Level 3 Studio install over a live native backup.

The HTTP server serves only the eight reviewed script baselines/candidates. It
loads all bytes before listening, so local edits cannot change a running batch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BACKUP = ROOT / "artifacts/level3-rebuild-20260930/native-backup/scripts.json"
PORT = 8881
TARGETS = [
    ("Level 3 Systems", "Level 3 Configuration", "Level 3 Configuration.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Layout Generator", "Level 3 Layout Generator.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Objective Controller", "Level 3 Objective Controller.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Test Suite", "Level 3 Test Suite.ModuleScript.luau"),
    ("Level 6 Systems", "Level6BlenderRuntimeBake", "../level6_build/import/Level6BlenderRuntimeBake.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Worn Party Room Dressing", "Level 3 Worn Party Room Dressing.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Worn Party Visual Adapter", "Level 3 Worn Party Visual Adapter.ModuleScript.luau"),
    ("Level 3 Systems", "Level 3 Round Adapter", "Level 3 Round Adapter.ModuleScript.luau"),
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def first_install_source(index: int, source: bytes) -> bytes:
    """Reverse only the two later, separately guarded prompt edits."""
    replacements = {
        5: (
            b"\t\t-- The authored cabinet and its invisible collision proxy sit between the\n"
            b"\t\t-- player and this internal anchor; range and round checks still gate use.\n"
            b"\t\tprompt.RequiresLineOfSight=false",
            b"\t\tprompt.RequiresLineOfSight=true",
        ),
        6: (
            b"        module.PickupParts = {disc, hub}\n"
            b"        -- The new jewel-case mesh and the existing tabletop can occlude the\n"
            b"        -- original prompt ray. Collection still checks distance and round state.\n"
            b"        module.Prompt.RequiresLineOfSight = false",
            b"        module.PickupParts = {disc, hub}",
        ),
    }
    if index in replacements:
        newer, older = replacements[index]
        assert source.count(newer) == 1, f"Cannot reconstruct first-install source {index}"
        source = source.replace(newer, older, 1)
    return source


def build(first_install: bool = False):
    originals = {record["path"]: record for record in json.loads(BACKUP.read_text())}
    payloads: dict[str, bytes] = {}
    items = []
    for index, (folder, name, candidate_file) in enumerate(TARGETS):
        path = f"ServerScriptService.{folder}.{name}"
        source = (HERE / candidate_file).resolve().read_bytes()
        if first_install:
            source = first_install_source(index, source)
        assert source, path
        prior = originals.get(path)
        if prior:
            assert prior["class"] == "ModuleScript" and prior["editorMatch"] is True, path
            baseline = prior["source"].encode("utf-8")
            assert baseline != source, f"No scoped change in {path}"
            payloads[f"/baseline/{index}"] = baseline
        else:
            baseline = None
        payloads[f"/source/{index}"] = source
        items.append({
            "id": index, "path": path, "folder": folder, "name": name,
            "class": "ModuleScript", "create": prior is None,
            "bytes": len(source), "sha256": sha(source),
            "baselineBytes": len(baseline) if baseline is not None else None,
            "baselineSha256": sha(baseline) if baseline is not None else None,
        })
    core = {"schema": "level3-worn-party-studio-install-v1", "placeId": 131311258779917,
            "universeId": 10559217407, "items": items}
    snapshot = sha(json.dumps(core, sort_keys=True, separators=(",", ":")).encode())
    manifest = {**core, "snapshotSha256": snapshot}
    payloads["/manifest"] = json.dumps(manifest, separators=(",", ":")).encode()
    return manifest, payloads


def installer(manifest):
    paths = "\n".join(f'    [{item["id"] + 1}] = "{item["path"]}",' for item in manifest["items"])
    return '''-- Execute only in the authoritative Roblox Studio Edit DataModel.
-- Generated from the frozen local native backup and reviewed Level 3 candidates.
local HS = game:GetService("HttpService")
local SES = game:GetService("ScriptEditorService")
local RS = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local SS = game:GetService("ServerStorage")
local BASE = "http://127.0.0.1:8881"
local SNAPSHOT = "__SNAPSHOT__"
local PATHS = {
__PATHS__
}
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407, "Wrong experience")
assert(not RS:IsRunning(), "Studio must be in Edit mode")
assert(SSS:FindFirstChild("Level 3 Systems") and SSS:FindFirstChild("Level 6 Systems"), "Missing systems folder")
local source = assert(SS:FindFirstChild("Level6BlenderSource"), "Blender source missing")
assert(source:GetAttribute("Ready") == true, "Blender source is incomplete")
local kitMetadata = assert(SSS["Level 6 Systems"]:FindFirstChild("Level 6 Kit Metadata"), "Kit metadata missing")
assert(kitMetadata:IsA("ModuleScript") and kitMetadata:GetAttribute("Level6SourceSha256")
    == "c141f4c5246ece81288d1cefdedd8243057149d4844f8fea7c14ee428ff66f4b",
    "Kit metadata is not the verified v2 source")
local oldHttp = HS.HttpEnabled
local fetched, package = pcall(function()
    HS.HttpEnabled = true
    local m = HS:JSONDecode(HS:GetAsync(BASE .. "/manifest", true))
    assert(m.schema == "level3-worn-party-studio-install-v1" and m.snapshotSha256 == SNAPSHOT
        and m.placeId == game.PlaceId and m.universeId == game.GameId and #m.items == #PATHS,
        "Candidate snapshot differs from reviewed install")
    local p = {}
    for i, item in ipairs(m.items) do
        assert(item.id == i-1 and item.path == PATHS[i] and item.class == "ModuleScript", "Unexpected target " .. i)
        local candidate = HS:GetAsync(BASE .. "/source/" .. item.id, true)
        assert(#candidate == item.bytes, "Truncated source " .. item.path)
        local baseline
        if item.create then
            assert(item.baselineBytes == nil and item.baselineSha256 == nil, "Unexpected new-script baseline")
        else
            baseline = HS:GetAsync(BASE .. "/baseline/" .. item.id, true)
            assert(#baseline == item.baselineBytes and baseline ~= candidate, "Invalid baseline " .. item.path)
        end
        p[i] = {meta = item, candidate = candidate, baseline = baseline}
    end
    return p
end)
HS.HttpEnabled = oldHttp
assert(fetched, "Could not fetch reviewed local install: " .. tostring(package))
local function editorSource(target)
    local ok, value = pcall(SES.GetEditorSource, SES, target)
    assert(ok and type(value) == "string", "Cannot read current editor source: " .. target:GetFullName())
    return value
end
local folders = {
    ["Level 3 Systems"] = assert(SSS:FindFirstChild("Level 3 Systems")),
    ["Level 6 Systems"] = assert(SSS:FindFirstChild("Level 6 Systems")),
}
-- Full preflight before the first write, including unsaved editor buffers.
for _, entry in ipairs(package) do
    local item = entry.meta
    local folder = folders[item.folder]
    assert(folder and folder:IsA("Folder"), "Wrong parent: " .. item.path)
    local target = folder:FindFirstChild(item.name)
    if item.create then
        assert(target == nil, "New script already exists: " .. item.path)
    else
        assert(target and target:IsA("ModuleScript") and target.Parent == folder,
            "Wrong live instance: " .. item.path)
        assert(target.Source == entry.baseline and editorSource(target) == entry.baseline,
            "Studio Source/editor drift: " .. item.path)
    end
end
local results = {}
for _, entry in ipairs(package) do
    local item, candidate, baseline = entry.meta, entry.candidate, entry.baseline
    local folder = folders[item.folder]
    local target = folder:FindFirstChild(item.name)
    if item.create then
        assert(target == nil, "New target appeared during install: " .. item.path)
        target = Instance.new("ModuleScript")
        target.Name = item.name
        target.Source = candidate
        target.Parent = folder
    else
        assert(target and target:IsA("ModuleScript") and target.Parent == folder
            and target.Source == baseline and editorSource(target) == baseline,
            "Studio changed during install: " .. item.path)
        local drift = false
        SES:UpdateSourceAsync(target, function(old)
            if target.Parent ~= folder or old ~= baseline or target.Source ~= baseline
                or editorSource(target) ~= baseline then
                drift = true
                return old
            end
            return candidate
        end)
        assert(not drift, "Studio changed inside source update: " .. item.path)
    end
    local matched = false
    for _ = 1, 100 do
        if target.Parent == folder and target.Source == candidate
            and editorSource(target) == candidate then matched = true; break end
        task.wait(.05)
    end
    assert(matched, "Source/editor readback failed: " .. item.path)
    if item.name == "Level6BlenderRuntimeBake" then
        target:SetAttribute("Level6SourceSha256", item.sha256)
    end
    target:SetAttribute("Level3WornPartySourceSHA256", item.sha256)
    target:SetAttribute("Level3WornPartyInstallSnapshot", SNAPSHOT)
    table.insert(results, {path = item.path, sha256 = item.sha256, created = item.create, editorParity = true})
end
return HS:JSONEncode({ok = true, snapshotSha256 = SNAPSHOT,
    httpRestored = HS.HttpEnabled == oldHttp, results = results})
'''.replace("__SNAPSHOT__", manifest["snapshotSha256"]).replace("__PATHS__", paths)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["prepare", "serve"])
    args = parser.parse_args()
    manifest, payloads = build(first_install=args.action == "serve")
    if args.action == "prepare":
        manifest_path = HERE / "install-manifest.json"
        installer_path = HERE / "install_studio.luau"
        install_code = installer(manifest)
        if manifest_path.exists():
            if json.loads(manifest_path.read_text()) != manifest:
                raise RuntimeError("Refusing to overwrite the historical first-install manifest")
        if installer_path.exists():
            if installer_path.read_text() != install_code:
                raise RuntimeError("Refusing to overwrite the historical first-install code")
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        installer_path.write_text(install_code)
        print(json.dumps({"snapshotSha256": manifest["snapshotSha256"], "items": len(manifest["items"])}))
        return
    recorded = json.loads((HERE / "install-manifest.json").read_text())
    assert recorded == manifest, "Candidate changed since prepare; prepare and review a new batch"

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            data = payloads.get(self.path)
            if data is None:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "application/json" if self.path == "/manifest" else "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format, *args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Serving frozen Level 3 install {manifest['snapshotSha256']} on {PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
