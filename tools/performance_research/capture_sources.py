"""Read-only, bounded source capture for the optimization research.

Writes task-owned evidence only; never changes Studio or runtime mirrors.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio

OUT = ROOT / "artifacts/performance-research-20261009"
NAMES = {
    "GameManager", "ServerKind", "Live Level Server", "Level4RoundGenerator",
    "TunnelLobbyBuilder", "Level 3 Kit Warmup", "MazeGenerator", "EntityAI",
    "Level 2 World Builder", "Level 2 Pool Foam Controller",
    "Level 3 Mall Manager AI Controller", "Level 6 World Builder",
    "Level 6 Playground Game", "Level 6 Mall Manager AI Controller",
    "Level 4 Usher Controller", "Lobby Loading Screen", "RoundUI",
    "Round Loading Runtime", "Level 6 Playground Client",
    "Level 2 Lighting Controller", "Level 3 Lighting Controller",
    "Level 4 Lighting Controller", "Level 5 Lighting Controller",
    "Level5PreviewAccess", "Level6PreviewAccess", "Level2Generator",
    "Level3Generator", "Level6BlenderRuntimeBake", "Level 6 Visual Adapter",
    "LobbyShopDisplay",
}
if len(sys.argv) > 1:
    NAMES = set(sys.argv[1:])

def literal(value):
    return json.dumps(json.dumps(value, ensure_ascii=True))

client = StudioMcpClient(find_mcp_batch())
try:
    client.initialize()
    studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
    sid = studio.get("studio_id") or studio.get("id")
    def call(code):
        return client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
    def decode(code):
        return json.loads(call(code))
    inventory = decode('''
local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local names=H:JSONDecode(%s)
local out={placeId=game.PlaceId,universeId=game.GameId,capturedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),scripts={}}
for i,x in ipairs(game:GetDescendants()) do
 if x:IsA("LuaSourceContainer") and names[x.Name] and not x:IsDescendantOf(game:GetService("ServerStorage")) then
  local segments={};local p=x;while p~=game do table.insert(segments,1,p.Name);p=p.Parent end
  local ok,editor=pcall(function() return SES:GetEditorSource(x) end)
  table.insert(out.scripts,{path=x:GetFullName(),segments=segments,class=x.ClassName,bytes=#x.Source,editorMatches=ok and editor==x.Source,editorReadOk=ok})
 end
 if i%%2000==0 then task.wait() end
end
return H:JSONEncode(out)
''' % literal({name: True for name in NAMES}))
    def finder(row):
        return '''local H=game:GetService("HttpService");local n=game
for _,seg in ipairs(H:JSONDecode(%s)) do
 local matches={};for _,child in ipairs(n:GetChildren()) do if child.Name==seg then table.insert(matches,child) end end
 assert(#matches==1,"Missing or ambiguous instance");n=matches[1]
end
assert(n.ClassName==%s,"Class changed")
''' % (literal(row["segments"]), json.dumps(row["class"]))
    for row in inventory["scripts"]:
        assert row["editorMatches"], "Source/editor conflict: " + row["path"]
        prefix = finder(row)
        chunks = []
        for start in range(1, row["bytes"] + 1, 30000):
            data = decode(prefix + '''
local source=n.Source
assert(#source==%d,"Source changed")
assert(game:GetService("ScriptEditorService"):GetEditorSource(n)==source,"Editor conflict")
return H:JSONEncode({chunk=string.sub(source,%d,%d)})
''' % (row["bytes"], start, min(start + 29999, row["bytes"])))
            chunks.append(data["chunk"])
        source = "".join(chunks)
        assert len(source.encode("utf-8")) == row["bytes"], "Incomplete capture"
        # Verify each chunk against a fresh, exact live baseline after transfer.
        # Avoid relying on length equality or a non-cryptographic fingerprint.
        for start in range(0, len(source), 16000):
            expected = source[start:start + 16000]
            # Luau string indices are byte indices; JSON transports unicode.
            byte_start = len(source[:start].encode("utf-8")) + 1
            byte_end = byte_start + len(expected.encode("utf-8")) - 1
            result = call(prefix + '''
local source=n.Source
assert(#source==%d,"Source changed")
assert(game:GetService("ScriptEditorService"):GetEditorSource(n)==source,"Editor conflict")
assert(string.sub(source,%d,%d)==%s,"Source changed during capture")
return "exact"
''' % (row["bytes"], byte_start, byte_end, json.dumps(expected, ensure_ascii=False)))
            assert result == "exact", result
        segments = row["segments"]
        rel = Path(*segments[:-1]) / (segments[-1] + "." + row["class"] + ".lua")
        dest = OUT / "sources" / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(source.encode("utf-8"))
        row["snapshotFile"] = dest.relative_to(ROOT).as_posix()
        row["sha256"] = hashlib.sha256(source.encode("utf-8")).hexdigest()
        mirror = ROOT / rel
        row["repositoryCanonicalMatches"] = mirror.exists() and mirror.read_text(encoding="utf-8").replace("\r\n", "\n") == source.replace("\r\n", "\n")
        print(row["path"], row["bytes"], "exact", flush=True)
    OUT.mkdir(parents=True, exist_ok=True)
    inventory["completedUtc"] = decode('return game:GetService("HttpService"):JSONEncode(os.date("!%Y-%m-%dT%H:%M:%SZ"))')
    manifest = OUT / "source-manifest.json"
    if manifest.exists():
        previous = json.loads(manifest.read_text(encoding="utf-8"))
        new_paths = {row["path"] for row in inventory["scripts"]}
        inventory["previousCapturedUtc"] = previous["capturedUtc"]
        inventory["scripts"] = [row for row in previous["scripts"] if row["path"] not in new_paths] + inventory["scripts"]
    manifest.write_text(json.dumps(inventory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("Captured", len(inventory["scripts"]), "scripts; runtime mirrors untouched.", flush=True)
finally:
    client.close()
