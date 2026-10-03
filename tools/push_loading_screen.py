"""Write ReplicatedFirst."Lobby Loading Screen" into the open Studio place (UpdateSourceAsync, read back).

    python3 tools/push_loading_screen.py

The LocalScript has to exist already: the Studio MCP sandbox cannot create scripts under ReplicatedFirst,
so it was created once from Studio's command bar.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

source = (ROOT / 'ReplicatedFirst' / 'Lobby Loading Screen.LocalScript.lua').read_text()
assert ']==]' not in source
print(studio_io.Studio().luau('''
local source = [==[%s]==]
local scr = game:GetService("ReplicatedFirst"):FindFirstChild("Lobby Loading Screen")
assert(scr and scr:IsA("LocalScript"), "create the LocalScript in ReplicatedFirst first")
game:GetService("ScriptEditorService"):UpdateSourceAsync(scr, function() return source end)
assert(scr.Source == source, "source readback mismatch")
return "written " .. #source .. " bytes"
''' % source))
