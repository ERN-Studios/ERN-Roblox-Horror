"""Studio's current source of named scripts into a scratch folder (NOT the repo), for reading another session's
work without taking it over:  python3 tools/mobile_qa/read_studio.py <out dir> "<repo-style path>" ..."""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
s = studio_io.Studio()
for rel in sys.argv[2:]:
    parts = list(Path(rel).parts)
    path = parts[:-1] + [parts[-1].rsplit('.', 2)[0]]
    find = 'local n = game\nfor _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end\n' % json.dumps(json.dumps(path))
    size = int(s.luau(find + 'return tostring(#n.Source)'))
    chunks, at = [], 1
    while at <= size:
        chunks.append(s.luau(find + 'return string.sub(n.Source, %d, %d)' % (at, at + 59999)))
        at += 60000
    (out / parts[-1]).write_bytes(''.join(chunks).encode())
    print(parts[-1], size)
