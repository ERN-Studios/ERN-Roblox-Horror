"""Studio -> repo for named scripts only (mac_pull_from_studio.py pulls whole services).

    python3 tools/mac_pull_one.py "ServerScriptService/GameManager.Script.lua" ...

Another session's Studio edits to exactly these files come into the working copy; nothing else is touched.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

s = studio_io.Studio()
for rel in sys.argv[1:]:
    parts = list(Path(rel).parts)
    path = parts[:-1] + [parts[-1].rsplit('.', 2)[0]]
    find = 'local n = game\nfor _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end\n' % json.dumps(json.dumps(path))
    size = int(s.luau(find + 'return tostring(#n.Source)'))
    chunks, at = [], 1
    while at <= size:
        chunks.append(s.luau(find + 'return string.sub(n.Source, %d, %d)' % (at, at + 59999)))
        at += 60000
    source = ''.join(chunks)
    f = ROOT / rel
    have = f.read_bytes().decode() if f.exists() else ''
    print(rel, len(have.encode()), '->', len(source.encode()), 'unchanged' if have == source else 'updated')
    if have != source:
        f.write_bytes(source.encode())
