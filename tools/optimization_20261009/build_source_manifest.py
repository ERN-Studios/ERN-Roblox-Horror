"""Record exact reviewed proposal bytes; this script has no Studio client."""
import hashlib
import json
from pathlib import Path

folder = Path(__file__).resolve().parent
root = folder.parents[1]
specs = [
    (["ReplicatedFirst", "Lobby Loading Screen"], "LocalScript",
     "loading/LobbyLoading.before.luau", "loading/LobbyLoading.proposed.luau"),
    (["ServerScriptService", "Level 4 Systems", "Level 4 Light Director"], "ModuleScript",
     "effects/Level4LightDirector.baseline.lua", "effects/Level4LightDirector.proposed.lua"),
    (["ServerScriptService", "GameManager"], "Script",
     "loading/spectate/GameManager.before.luau", "loading/spectate/GameManager.proposed.luau"),
    (["ReplicatedStorage", "SceneEffectBudget"], "ModuleScript", None,
     "effects/SceneEffectBudget.ModuleScript.lua"),
    (["StarterPlayer", "StarterPlayerScripts", "SceneEffectBudgetClient"], "LocalScript", None,
     "effects/SceneEffectBudgetClient.LocalScript.lua"),
]
rows = []
for segments, class_name, before, after in specs:
    row = {"segments": segments, "class": class_name}
    for key, relative in [("before", before), ("after", after)]:
        path = folder / relative if relative else None
        raw = path.read_bytes() if path else b""
        row[key + "File"] = path.relative_to(root).as_posix() if path else None
        row[key + "Sha256"] = hashlib.sha256(raw).hexdigest()
        row[key + "Bytes"] = len(raw)
    rows.append(row)
(folder / "proposed-source-manifest.json").write_text(json.dumps({
    "status": "Prepared; no Studio writes; fresh Edit baseline and tests required",
    "placeId": 131311258779917, "universeId": 10559217407, "scripts": rows,
}, indent=2) + "\n", encoding="utf-8")
print(f"Recorded {len(rows)} scoped source proposals; Studio unchanged.")
