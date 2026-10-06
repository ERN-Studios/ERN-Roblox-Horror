"""Create (once) and push the Reach's two scripts, and push the lobby Builder.

    python3 tools/lobby_reach/push_scripts.py

`Lobby Tunnel Reach` (Script, ServerScriptService) and `Lobby Tunnel Reach Client` (LocalScript,
StarterPlayerScripts) did not exist before 2026-10-06. The session could create scripts that day (it could not on
2026-10-03); if it refuses again, make two empty scripts of those names by hand and run this once more.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
from import_to_studio import Studio   # noqa: E402

NEW = [
    ('ServerScriptService', 'Script', 'Lobby Tunnel Reach', 'ServerScriptService/Lobby Tunnel Reach.Script.lua'),
    ('StarterPlayer.StarterPlayerScripts', 'LocalScript', 'Lobby Tunnel Reach Client',
     'StarterPlayer/StarterPlayerScripts/Lobby Tunnel Reach Client.LocalScript.lua'),
]
LUAU = '''
local parent = game
for seg in string.gmatch(%s, "[^.]+") do parent = parent:FindFirstChild(seg) or game:GetService(seg) end
local CLASS, NAME = %s, %s
local source = [==[%s]==]
local node = parent:FindFirstChild(NAME)
local made = false
if not node then
	node = Instance.new(CLASS)
	node.Name = NAME
	node.Parent = parent
	made = true
end
assert(node.ClassName == CLASS, NAME .. " is a " .. node.ClassName)
if node.Source ~= source then
	game:GetService("ScriptEditorService"):UpdateSourceAsync(node, function() return source end)
end
assert(node.Source == source, "readback mismatch")
return (made and "created " or "updated ") .. node:GetFullName() .. " " .. #source
'''

studio = Studio()
for parent, cls, name, rel in NEW:
    source = (ROOT / rel).read_text()
    assert ']==]' not in source, rel
    print(studio.luau(LUAU % (json.dumps(parent), json.dumps(cls), json.dumps(name), source)), flush=True)
del studio
subprocess.run([sys.executable, str(ROOT / 'tools' / 'mac_push_script.py'),
                'ServerScriptService/LobbyReimaginedPreview/Builder.ModuleScript.lua'], cwd=ROOT, check=True)
