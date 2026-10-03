"""Repo -> Studio for one or more mirrored scripts on the Mac (UpdateSourceAsync, read back).

    python3 tools/mac_push_script.py "StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua" ...

Refuses when Studio's current source is not the committed (HEAD) version of the file, unless --force:
another session may have edited the script in Studio since the mirror was pulled.
"""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

force = '--force' in sys.argv
s = studio_io.Studio()
for rel in [a for a in sys.argv[1:] if not a.startswith('--')]:
    f = ROOT / rel
    source = f.read_text()
    assert ']==]' not in source, rel
    parts = list(Path(rel).parts)
    name = parts[-1].rsplit('.', 2)[0]
    path = parts[:-1] + [name]
    head = subprocess.run(['git', 'show', f'HEAD:{rel}'], cwd=ROOT, capture_output=True, text=True).stdout
    studio_len = int(s.luau('local n = game\nfor _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end\nreturn tostring(#n.Source)' % json.dumps(json.dumps(path))))
    if not force and studio_len not in (len(head.encode()), len(source.encode())):   # Luau counts bytes
        raise SystemExit(f'{rel}: Studio holds {studio_len} bytes, HEAD {len(head.encode())}, working copy {len(source.encode())}: pull first or --force')
    print(rel, s.luau('''
local source = [==[%s]==]
local n = game
for _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end
if n.Source == source then return "unchanged" end
game:GetService("ScriptEditorService"):UpdateSourceAsync(n, function() return source end)
assert(n.Source == source, "readback mismatch")
return "written " .. #source
''' % (source, json.dumps(json.dumps(path)))))
