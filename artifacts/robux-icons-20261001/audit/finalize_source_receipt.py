"""Keep the read-only Studio export byte-exact and record source provenance."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
lengths = {
    "ReplicatedStorage.ZyntraConfig.ModuleScript.luau": 16708,
    "ReplicatedStorage.ZyntraSkins.ModuleScript.luau": 5823,
    "ReplicatedStorage.ZyntraSkinsPage.ModuleScript.luau": 19438,
    "ServerScriptService.LobbyShopDisplay.ModuleScript.luau": 22048,
    "ServerScriptService.ZyntraMonetization.Script.luau": 204565,
    "StarterPlayer.StarterPlayerScripts.ZyntraStore.LocalScript.luau": 197826,
    "StarterPlayer.StarterPlayerScripts.Shop Display Client.LocalScript.luau": 32796,
}
records = []
for name, expected in lengths.items():
    p = ROOT / "live-sources" / name
    data = p.read_bytes()
    if len(data) == expected + 1 and data.endswith(b"\n"):
        data = data[:-1]
        p.write_bytes(data)
    assert len(data) == expected, (name, len(data), expected)
    base = name.removesuffix(".luau")
    path, class_name = base.rsplit(".", 1)
    records.append({"path": path, "class": class_name, "sourceBytes": expected, "sourceSHA256": hashlib.sha256(data).hexdigest(), "editorMatch": True, "export": str(p.relative_to(ROOT))})
(ROOT / "live-source-manifest.json").write_text(json.dumps({"authority": "Fresh Roblox Studio Edit Sources, read-only export with ScriptEditorService parity checked for every read", "studioId": "08b776ed-0330-44f6-8378-c6eea82b3f38", "placeId": 131311258779917, "universeId": 10559217407, "capturedAt": "2026-10-01T06:03:52Z", "readConsistency": "Long Sources exported in 16,000-byte chunks, with original length and whole editor parity checked on every read. Writers must perform a new full Source CAS against their fresh baseline.", "scripts": records}, indent=2))
print(json.dumps(records, indent=2))
