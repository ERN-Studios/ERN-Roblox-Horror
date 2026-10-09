"""Verify research files and re-read exact live source chunks; never write Studio."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio

OUT = ROOT / "artifacts/performance-research-20261009"
manifest = json.loads((OUT / "source-manifest.json").read_text(encoding="utf-8"))
client = StudioMcpClient(find_mcp_batch())
try:
    client.initialize()
    studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
    sid = studio.get("studio_id") or studio.get("id")
    results = []
    for row in manifest["scripts"]:
        raw = (ROOT / row["snapshotFile"]).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == row["sha256"], row["path"]
        assert len(raw) == row["bytes"], row["path"]
        source = raw.decode("utf-8")
        prefix = '''local H=game:GetService("HttpService");local n=game
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
for _,seg in ipairs(H:JSONDecode(%s)) do
 local matches={};for _,child in ipairs(n:GetChildren()) do if child.Name==seg then table.insert(matches,child) end end
 assert(#matches==1,"Missing or ambiguous instance");n=matches[1]
end
assert(n.ClassName==%s,"Class changed")
''' % (json.dumps(json.dumps(row["segments"])), json.dumps(row["class"]))
        for start in range(0, len(source), 16000):
            expected = source[start:start + 16000]
            byte_start = len(source[:start].encode("utf-8")) + 1
            byte_end = byte_start + len(expected.encode("utf-8")) - 1
            code = prefix + '''local source=n.Source
assert(#source==%d,"Source length changed")
assert(game:GetService("ScriptEditorService"):GetEditorSource(n)==source,"Editor conflict")
assert(string.sub(source,%d,%d)==%s,"Live source changed")
return "exact"
''' % (row["bytes"], byte_start, byte_end, json.dumps(expected, ensure_ascii=False))
            response = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
            assert response == "exact", response
        results.append({"path": row["path"], "class": row["class"], "sha256": row["sha256"], "localHashMatches": True, "liveSourceChunksExact": True, "editorMatchesSource": True})
    captured = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": 'return os.date("!%Y-%m-%dT%H:%M:%SZ")'})
    result = {"verifiedUtc": captured, "mode": "Edit", "count": len(results), "results": results, "scope": "Selected research snapshots; no complete-place parity or gameplay claim."}
    (OUT / "verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("PASS:", len(results), "local SHA-256 hashes, exact live source chunks, and editor agreement; Studio untouched.")
finally:
    client.close()
