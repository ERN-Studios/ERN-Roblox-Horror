"""Freeze only reviewed public Level 3 promotion candidates; never write Studio."""
from pathlib import Path
import hashlib, json

ROOT = Path(__file__).resolve().parents[2]
TASK = Path(__file__).resolve().parent
BEFORE = Path('/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/before')
def digest(raw): return hashlib.sha256(raw).hexdigest()
inventory = json.loads((BEFORE / 'scripts.json').read_text())
baseline = {r['path']: r for r in inventory}
summary = json.loads((ROOT / 'artifacts/level3-promotion-20261002/backup/before/backup-source-structure-summary.json').read_text())
rows = []
for r in json.loads((TASK / 'public3/layout-world-candidate-manifest-v2.json').read_text()):
    rows.append(dict(path=r['targetPath'], className=r['className'], new=r['operation']=='create',
                     baselineSHA256=r['beforeHash'], candidateSHA256=r['candidateHash'], candidateFile=str(ROOT/r['candidatePath'])))
for r in json.loads((TASK / 'gameplay_boards/candidate-manifest.json').read_text())['changes']:
    rows.append(dict(path=r['path'], className=r['class'], new=False, baselineSHA256=r['baselineSHA256'],
                     candidateSHA256=r['candidateSHA256'], candidateFile=r['candidateFile']))
admission = TASK / 'admission/candidate-manifest.json'
assert admission.exists(), 'Public3 cold-kit admission candidate is required before integration'
for r in json.loads(admission.read_text())['changes']:
    rows.append(dict(path=r['path'], className=r['class'], new=r.get('new',False), baselineSHA256=r.get('baselineSHA256'),
                     candidateSHA256=r['candidateSHA256'], candidateFile=r['candidateFile']))
assert len({r['path'] for r in rows}) == len(rows), 'Duplicate target'
for r in rows:
    raw = Path(r['candidateFile']).read_bytes()
    assert digest(raw) == r['candidateSHA256'], r['path']
    r['candidateBytes'] = len(raw)
    r['source'] = raw.decode()
    if r['new']:
        assert r['path'] not in baseline, r['path']
    else:
        b = baseline[r['path']]
        assert b['class'] == r['className'] and b['sourceSha256'] == r['baselineSHA256'] == b['editorSourceSha256'] and b['editorMatch'], r['path']
snapshot = TASK / 'install-snapshot'
snapshot.mkdir(exist_ok=True)
payload = dict(task='level3-promotion-20261002', nativeBeforeVerified=True,
               nativeBeforeCaptureId='551b88e1-2e3a-4333-8157-00e622b7bc54', rows=rows)
raw = (json.dumps(payload,ensure_ascii=False,separators=(',',':'))+'\n').encode()
(snapshot/'payload.json').write_bytes(raw)
template = (TASK/'install-scoped.template.luau').read_text()
install = template.replace('__PAYLOAD_SHA256__',digest(raw)).encode()
(snapshot/'install-scoped.luau').write_bytes(install)
manifest = dict(task=payload['task'], payloadSHA256=digest(raw), installSHA256=digest(install),
                sourceCount=len(rows), rows=[{k:v for k,v in r.items() if k!='source'} for r in rows])
(snapshot/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({k:v for k,v in manifest.items() if k!='rows'}))
