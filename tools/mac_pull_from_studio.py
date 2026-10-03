"""Studio -> repo for the Mac (the Windows bridge tools do not run here): writes every script under the given
services whose Studio source differs from the mirrored file. Read-only towards Studio.

    python3 tools/mac_pull_from_studio.py [--audit] [StarterPlayer ReplicatedStorage ...]
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io

args = [a for a in sys.argv[1:] if not a.startswith('--')]
services = args or ['StarterPlayer', 'ReplicatedStorage', 'ReplicatedFirst', 'ServerScriptService', 'StarterGui']
audit = '--audit' in sys.argv
s = studio_io.Studio()
listing = json.loads(s.luau('''
local out = {}
for _, name in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do
	for _, d in ipairs(game:GetService(name):GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			local path, node = {}, d
			while node and node ~= game do table.insert(path, 1, node.Name) node = node.Parent end
			table.insert(out, {path = path, class = d.ClassName, size = #d.Source})
		end
	end
end
return game:GetService("HttpService"):JSONEncode(out)
''' % json.dumps(json.dumps(services))))
changed = 0
for item in listing:
    path = item['path']
    f = ROOT.joinpath(*path[:-1]) / f"{path[-1]}.{item['class']}.lua"
    have = f.read_bytes().decode() if f.exists() else None
    if have is not None and len(have) == item['size'] and '\r' not in have and have.isascii():
        continue                                    # same length, plain ASCII: treat as unchanged
    chunks, at = [], 1
    while at <= item['size']:
        chunks.append(s.luau('local n = game\nfor _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end\nreturn string.sub(n.Source, %d, %d)'
                             % (json.dumps(json.dumps(path)), at, at + 59999)))
        at += 60000
    source = ''.join(chunks)
    if have == source:
        continue
    changed += 1
    print(('would update ' if audit else 'updated ') + str(f.relative_to(ROOT)), len(have or ''), '->', len(source))
    if not audit:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(source.encode())
print(len(listing), 'scripts,', changed, 'differ')
