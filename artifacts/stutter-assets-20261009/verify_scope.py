"""Record exact verified native sources, mirror/manifest parity and scoped metadata."""
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / "artifacts/stutter-assets-20261009"
records = json.loads(Path(sys.argv[1]).read_bytes())
manifest = json.loads((ROOT / "studio-sync-manifest.json").read_bytes())
expected = {
 "ReplicatedFirst.Lobby Loading Screen": "lobby-bounded-pool",
 "StarterPlayer.StarterPlayerScripts.Round Entry Client": "entry-opaque-content",
 "StarterPlayer.StarterPlayerScripts.Shop Display Client": "shop-scan",
 "StarterPlayer.StarterPlayerScripts.Lobby DJ Client": "dj-cache",
 "ServerScriptService.Level 1 Systems.BlenderRoomRenderer": "level1-room-streaming",
}
assert len(records) == len(expected) and {r["path"] for r in records} == set(expected)
out = []
for row in records:
 receipt = json.loads((TASK / (expected[row["path"]] + "-native-install.json")).read_bytes())
 native = Path(row["sourceFile"]).read_bytes()
 matches = [e for e in manifest["items"] if e.get("studioPath") == row["path"]]
 assert len(matches) == 1
 entry = matches[0]
 mirror = (ROOT / entry["file"]).read_bytes()
 digest = hashlib.sha256(native).hexdigest()
 assert mirror == native and digest == row["sha256"] == entry["sha256"] == receipt["afterSHA256"]
 assert row["bytes"] == len(native) == entry["bytes"]
 assert row["class"] == entry["className"] == receipt["class"]
 assert entry["sourceEditorMatches"] is True and entry["status"] == "synced"
 assert row["properties"] == receipt["baselineRecord"]["properties"]
 assert row["attributes"] == receipt["baselineRecord"]["attributes"]
 out.append({k: v for k,v in row.items() if k != "sourceFile"} | {
  "mirror": entry["file"], "sourceEditorMatches": True, "mirrorMatchesNative": True,
  "manifestMatchesNative": True, "propertiesUnchanged": True, "attributesUnchanged": True,
 })
result = {"capturedAtUtc": datetime.now(timezone.utc).isoformat(), "placeId": 131311258779917,
 "universeId": 10559217407, "sources": out, "limits": "Five scoped native Source/editor exports only; not whole-place parity or a native place backup."}
(TASK / "verified-scope.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"verifiedSources":len(out), "hashesMatch":True, "propertiesAndAttributesUnchanged":True}))
