"""Freeze five fresh Source-matched candidates and emit scoped CAS instructions only.

This script never talks to Studio or changes Git. The parent runs the installer
only after review. All paths/classes/hashes come from the task's measured live
baseline; matching full Source bytes are retained as frozen baseline files.
"""
from pathlib import Path
import difflib, hashlib, json

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[1]
OUT = TASK / 'install'
OUT.mkdir(exist_ok=True)
sha = lambda b: hashlib.sha256(b).hexdigest()
fresh = json.loads((TASK / 'prewrite-live-five.json').read_text())
assert fresh['placeId'] == 131311258779917 and fresh['universeId'] == 10559217407
assert fresh['isRunning'] is False
observed = {r['path']: r for r in fresh['sources']}
rows = []
def add(path, baseline, candidate, expected_candidate=None):
    rec = observed[path]
    b, c = Path(baseline).read_bytes(), Path(candidate).read_bytes()
    assert rec['editorMatch'] and sha(b) == rec['sourceSHA256'] == rec['editorSHA256'], path
    assert len(b) == rec['sourceBytes'] == rec['editorBytes'], path
    if expected_candidate:
        assert sha(c) == expected_candidate, path
    baseline_copy = OUT / (path + '.baseline.luau')
    if baseline_copy.exists():
        assert baseline_copy.read_bytes() == b, 'Frozen baseline changed'
    else:
        baseline_copy.write_bytes(b)
    rows.append(dict(path=path, className=rec['class'], baselineSHA256=sha(b),
                     editorSHA256=rec['editorSHA256'], baselineBytes=len(b),
                     candidateSHA256=sha(c), candidateBytes=len(c),
                     baselineFile=str(baseline_copy), candidateFile=str(Path(candidate).resolve()),
                     before=b.decode(), candidate=c.decode()))

for name in ['Level 3 World Builder', 'Level 3 Worn Party Visual Adapter']:
    add('ServerScriptService.Level 3 Systems.' + name,
        TASK / 'device' / (name + '.ModuleScript.lua.baseline.luau'),
        TASK / 'device' / (name + '.candidate.luau'))
for rec in json.loads((TASK / 'finale/candidate-manifest-v2.json').read_text())['changes']:
    add(rec['path'], ROOT / 'ServerScriptService/Level 3 Systems' /
        (rec['path'].split('.')[-1] + '.ModuleScript.lua'), rec['candidateFile'], rec['candidateSHA256'])
reader = json.loads((TASK / 'reader/candidate-manifest.v2.json').read_text())
add(reader['path'], ROOT / reader['baselinePath'], ROOT / reader['candidatePath'], reader['candidateHash'])
assert len(rows) == 5 and len({r['path'] for r in rows}) == 5

def replacements(before, after):
    a, b = before.splitlines(True), after.splitlines(True)
    # Increase equal-line context only when a region is not uniquely locatable.
    # Groups are recomputed together, so expanded adjacent regions never overlap.
    matcher = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    context = 3
    while context <= max(len(a), len(b)):
        patches = []
        for group in matcher.get_grouped_opcodes(context):
            i1, i2 = group[0][1], group[-1][2]
            j1, j2 = group[0][3], group[-1][4]
            old, new = ''.join(a[i1:i2]), ''.join(b[j1:j2])
            patches.append(dict(before=old, after=new))
        current = before
        if patches and all(p['before'] and before.count(p['before']) == 1 for p in patches):
            for p in patches:
                if current.count(p['before']) != 1:
                    break
                current = current.replace(p['before'], p['after'], 1)
            else:
                assert current == after
                return patches
        context *= 2
    raise AssertionError('Unable to derive unique exact-context replacements')

def lua_string(value):
    # Luau strips a newline immediately after the opening long bracket. Prefix
    # one harmless byte and remove it at runtime so exact source bytes survive.
    level = 0
    while ']' + '=' * level + ']' in value:
        level += 1
    return '(' + '[' + '=' * level + '[_' + value + ']' + '=' * level + ']' + '):sub(2)'

chunks = []
for row in rows:
    row['patches'] = replacements(row['before'], row['candidate'])
    fields = ['path', 'className', 'baselineSHA256', 'editorSHA256', 'candidateSHA256']
    parts = [f'{field}={lua_string(row[field])}' for field in fields]
    parts += [f'baselineBytes={row["baselineBytes"]}', f'candidateBytes={row["candidateBytes"]}']
    parts.append('patches={' + ','.join('{before=' + lua_string(p['before']) +
                                      ',after=' + lua_string(p['after']) + '}' for p in row['patches']) + '}')
    chunks.append('{' + ','.join(parts) + '}')
template = (TASK / 'delta-install.template.luau').read_text()
installer = template.replace('__ROWS__', '{' + ',\n'.join(chunks) + '}')
assert '__ROWS__' not in installer
encoded = installer.encode()
assert len(encoded) < 65536, f'Compact installer unexpectedly large: {len(encoded)}'
target = OUT / 'install-five-scoped.v2.luau'
target.write_bytes(encoded)
manifest = dict(task='level3-finale-player-20261002', studioId='c1e8b040-e549-408a-8a5b-7fe6905c2d55',
                placeId=131311258779917, universeId=10559217407,
                prewriteCaptureAtUTC=fresh['capturedAtUTC'],
                prewriteReceipt=str(TASK / 'prewrite-live-five.json'),
                installerFile=str(target), installerSHA256=sha(encoded), installerBytes=len(encoded),
                nativeBeforeSHA256='bc32152e6fd668aab75108576c454ef84a3c914ec4e606f094e5599c5e34f378',
                sourceCount=5, changes=[{k: v for k, v in row.items() if k not in ['before', 'candidate', 'patches']}
                                       | {'patchCount': len(row['patches'])} for row in rows])
(OUT / 'source-manifest.v2.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({k:v for k,v in manifest.items() if k != 'changes'}))
