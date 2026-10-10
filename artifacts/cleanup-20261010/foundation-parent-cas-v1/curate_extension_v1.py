"""New immutable exact-path curation including V5 negative/V6 correction."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
FOUNDATION = ROOT/'artifacts/cleanup-20261010/foundation-next-v1'
EXTRA = Path(__file__).resolve().parent
OUT = FOUNDATION/'CURATION-v2.json'
assert not OUT.exists()
SHA = lambda raw: hashlib.sha256(raw).hexdigest()
old_path = FOUNDATION/'CURATION-v1.json'
assert SHA(old_path.read_bytes()) == '9b9cee631a0eb50cc321bc2ae4b8573cf9785f1e59f54b3f1e333917a9e7cedc'
old = json.loads(old_path.read_bytes())
paths = [ROOT/row['path'] for row in old['files']]
for row in old['files']:
    raw = (ROOT/row['path']).read_bytes()
    assert (len(raw), SHA(raw)) == (row['bytes'], row['sha256']), row['path']
paths += [old_path, FOUNDATION/'CURATION-v1.md']
paths += [p for p in (FOUNDATION/'installer-v6').rglob('*') if p.is_file()]
paths += [p for p in EXTRA.rglob('*') if p.is_file()]
patterns = [
    rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    rb'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})',
    rb'\bsk-(?:proj-)?[A-Za-z0-9_-]{24,}',
    rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    rb'_\|WARNING:-DO-NOT-SHARE-THIS\.',
    rb'https?://[^\s"\'<>/:]+:[^\s"\'<>/@]+@',
    rb'(?i)\b(?:authorization|bearer|api[_-]?key|password|secret|token)\b\s*[:=]\s*["\'][A-Za-z0-9_./+\-=]{16,}["\']',
]
rows, findings = [], []
for p in sorted(set(paths)):
    assert not p.is_symlink() and '__pycache__' not in p.parts and p.suffix not in {'.pyc','.pyo'}
    raw = p.read_bytes(); label = p.relative_to(ROOT).as_posix()
    for index, expression in enumerate(patterns):
        for match in re.finditer(expression, raw):
            findings.append({'path': label, 'patternIndex': index, 'line': raw[:match.start()].count(b'\n')+1, 'matchedBytesSHA256': SHA(match.group())})
    rows.append({'path': label, 'bytes': len(raw), 'sha256': SHA(raw)})
assert not findings, 'Secret candidate detected; values not emitted'
value = {'schema':'completed-foundation-curation-v2', 'supersedesAsCurrentCuration':'CURATION-v1.json; prior file unchanged',
    'candidateStatus':'V6 candidate only; native authoring/editor/large-write pending; no production promotion',
    'V5CombinedOwnershipGatePassed':False,'V6OfflineComposedGatePassed':True,
    'files':rows,'excluded':old['excluded'],'secretScan':{'patterns':7,'filesScanned':len(rows),'bytesScanned':sum(r['bytes'] for r in rows),'findings':findings,'scope':'Static recognizable secret-pattern scan, no runtime/private-config read; unknown/encoded credentials not universally excluded.'},
    'nativeCalls':0,'productionWrites':0,'indexWrites':0,'commitWrites':0,
    'limits':'Root explicitly stages exact pinned paths after hash/diff review. Curation output itself is new and not self-pinned; no git add -A. V5 earlier ports do not certify its failed combined state. V6 remains pending native authoring/transport.'}
with OUT.open('xb') as stream: stream.write((json.dumps(value,indent=2)+'\n').encode())
print(json.dumps({'pass':True,'files':len(rows),'bytes':sum(r['bytes'] for r in rows),'secretFindings':0,'curationSHA256':SHA(OUT.read_bytes())}))
