from pathlib import Path
import json, hashlib, difflib

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
BASE = REPO / 'artifacts/lobby-access-spawn-20261002/baseline'
OUT = ROOT / 'combined'
OUT.mkdir(exist_ok=True)
baseline_catalog = {r['path']: r for r in json.loads((BASE / 'manifest.json').read_text())['catalog']}
rows = []

def add(path, class_name, source, baseline_file=None):
    row = baseline_catalog.get(path)
    if row:
        assert row['className'] == class_name and row['editorSHA256'] == row['sourceSHA256']
    file = OUT / (path + '.' + class_name + '.candidate.luau')
    raw = source.encode('utf-8')
    file.write_bytes(raw)
    entry = {'path': path, 'className': class_name, 'new': row is None,
             'baselineSHA256': row['sourceSHA256'] if row else None,
             'baselineBytes': row['bytes'] if row else None,
             'candidateSHA256': hashlib.sha256(raw).hexdigest(),
             'candidateBytes': len(raw), 'file': str(file.relative_to(REPO))}
    if baseline_file:
        before = Path(baseline_file).read_bytes()
        assert hashlib.sha256(before).hexdigest() == row['sourceSHA256']
        diff = ''.join(difflib.unified_diff(before.decode().splitlines(True), source.splitlines(True),
                    fromfile=path + ' (fresh Studio)', tofile=path + ' (candidate)'))
        (OUT / (path + '.diff')).write_text(diff)
        entry['baselineFile'] = str(Path(baseline_file).relative_to(REPO))
    rows.append(entry)

spawn = json.loads((ROOT / 'spawn/candidate-manifest.json').read_text())
friend = json.loads((ROOT / 'spawn/friend-boost-candidate-manifest.json').read_text())
spawn['rows'].append(friend['row'] if 'row' in friend else friend)
for r in spawn['rows']:
    source = (REPO / r['candidate']).read_text()
    assert hashlib.sha256(source.encode()).hexdigest() == r['candidateSha256']
    if r['path'] == 'ServerScriptService.GameManager':
        old = ' if station.revisionOwned and not (RunService:IsStudio() or DevAccess.IsLevel6PreviewAllowed(player)) then return false end'
        new = ' -- Public revision queues stay open; both unfinished bays require real DEV authorization.\n if station.revisionOwned and station.level >= 5 and not DevAccess.IsLevel6PreviewAllowed(player) then return false end'
        assert source.count(old) == 1
        source = source.replace(old, new)
    add(r['path'], r['class'], source, REPO / r['baseline'])

for path, cls, file in [
    ('StarterPlayer.StarterPlayerScripts.R4DevGateController', 'LocalScript', 'R4DevGateController.LocalScript.candidate.luau'),
    ('ServerScriptService.Level5PreviewAccess', 'Script', 'Level5PreviewAccess.Script.candidate.luau'),
    ('ServerScriptService.LobbyReimaginedPreview.DevBayAccessGuard', 'ModuleScript', 'DevBayAccessGuard.ModuleScript.candidate.luau')]:
    source = (ROOT / 'devgates' / file).read_text()
    add(path, cls, source)

path = 'ServerScriptService.LobbyReimaginedPreview.Builder'
file = BASE / (path + '.ModuleScript.luau')
source = file.read_text()
old = '\t\treturn existing\n'
new = '\t\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(existing)\n\t\treturn existing\n'
assert source.count(old) == 1
source = source.replace(old, new)
old = '\tmodel.Parent = workspace\n\treturn model\n'
new = '\tmodel.Parent = workspace\n\trequire(script.Parent:WaitForChild("DevBayAccessGuard")).Start(model)\n\treturn model\n'
assert source.count(old) == 1
source = source.replace(old, new)
add(path, 'ModuleScript', source, file)

manifest = {'schema': 'lobby-access-spawn-scoped-candidates-v1',
            'placeId': 131311258779917, 'universeId': 10559217407,
            'nativeBeforeCaptureId': 'dd47c97b-033d-40a3-9ae3-f23d88cacab1',
            'canonicalSpawnPath': 'Workspace.ServerLobby.LobbySpawn',
            'spawnPosition': [220, 30.4, -860], 'spawnLookAt': [220, 30.4, -760],
            'rows': rows}
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'sources': len(rows), 'new': sum(r['new'] for r in rows), 'rows': rows}))
