"""Delete only pinned duplicate transport chunks; keep complete archive inputs."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'artifacts/cleanup-serverstorage-20261009'
REVIEW = BASE / 'transport-parts-review-v1'
AFTER = BASE / 'transport-parts-after-v1'
CHECKPOINT = ROOT / '.git/mongotv-cleanup-20261009/transport-parts-before-v1'
ALLOWED = {'diagnostic-archive-before-v7', 'diagnostic-archive-before-v8', 'external-storage-archive-v1', 'retired-authoring-archive-v3'}
CANDIDATE_SHA = 'fbe29bc1276790f25cec4b1cc6952e72627c7f185c750634ba780ae11875d212'
CONSUMER_SHA = '3044bce8c8496d47c21ac03425cc7f0d81780dad0d2150250d90173a05d6cfe6'

def sha(raw): return hashlib.sha256(raw).hexdigest()
def save_new(path, raw):
    with path.open('xb') as stream: assert stream.write(raw) == len(raw)
    assert path.read_bytes() == raw
def encoded(value): return (json.dumps(value, indent=2) + '\n').encode()
def safe(relative, directory=None):
    value = Path(relative)
    assert not value.is_absolute() and '..' not in value.parts
    path = ROOT / value
    assert path.resolve().is_relative_to(BASE.resolve())
    assert path.parent.resolve() == (BASE / (directory or value.parts[-2])).resolve()
    for parent in (path, *path.parents):
        assert not parent.is_symlink(), 'Symlink: ' + str(parent)
        if parent == ROOT: break
    return path
def inventory():
    return {p.relative_to(ROOT).as_posix(): sha(p.read_bytes()) for name in ALLOWED | {'external-storage-reopen-v1'} for p in (BASE/name).rglob('*') if p.is_file()}

def main():
    assert not AFTER.exists() and not CHECKPOINT.exists(), 'Refuse evidence overwrite'
    candidate_raw = (REVIEW/'candidate.json').read_bytes()
    assert sha(candidate_raw) == CANDIDATE_SHA
    candidate = json.loads(candidate_raw)
    assert candidate['pass'] and candidate['nativeCalls'] == candidate['nativeWrites'] == candidate['filesRemoved'] == 0
    assert candidate['temporaryCopiesCleaned'] and candidate['originalFiveArchiveInventoriesBeforeAfterExact']
    groups = candidate['eligibleGroups']
    parts = [p for g in groups for p in g['parts']]
    assert parts == candidate['allowedPaths'] and len(parts) == candidate['candidateFiles'] == 92
    assert sum(p['bytes'] for p in parts) == candidate['candidateBytes'] == 60168414
    assert len({p['path'] for p in parts}) == 92
    assert all(g['directory'] in ALLOWED for g in groups)
    assert all(p['pass'] for p in candidate['actualOfflineConsumerPorts'])
    helpers = {name: (ROOT/'tools/cleanup_20261009'/name).read_bytes() for name in candidate['consumerSourceHashes']}
    assert all(sha(raw) == candidate['consumerSourceHashes'][name] for name,raw in helpers.items())
    consumer = (REVIEW/'prepare-review.py').read_bytes()
    assert sha(consumer) == CONSUMER_SHA
    full = {}; retained = {}
    for g in groups:
        raw = safe(g['fullFile'],g['directory']).read_bytes()
        assert len(raw) == g['bytes'] and sha(raw) == g['fullFileSHA256']
        full[g['fullFile']] = raw; retained[g['fullFile']] = raw
        receipt = safe(g['receiptFile'],g['directory']).read_bytes()
        assert sha(receipt) == g['receiptSHA256']
        retained[g['receiptFile']] = receipt
        offset = 0
        for p in g['parts']:
            assert re.fullmatch(re.escape(g['kind'])+r'-part-\d{4}\.bin',Path(p['path']).name)
            assert p['fullFile'] == g['fullFile'] and p['offset'] == offset
            part = safe(p['path'],g['directory']).read_bytes()
            assert len(part) == p['bytes'] and sha(part) == p['sha256']
            assert part == raw[offset:offset+len(part)]
            offset += len(part)
        assert offset == len(raw)
    tracked = subprocess.check_output(['git','ls-files','-z','--',*[p['path'] for p in parts]],cwd=ROOT)
    assert tracked == b'', 'Tracked files are outside this local duplicate batch'
    initial = inventory()
    for p in parts: assert initial[p['path']] == p['sha256']
    CHECKPOINT.mkdir(parents=True)
    save_new(CHECKPOINT/'candidate-before.json',candidate_raw)
    save_new(CHECKPOINT/'inventory-before.json',encoded(initial))
    AFTER.mkdir()
    save_new(AFTER/'.gitattributes',b'* -text -whitespace\n')
    save_new(AFTER/'prepare-review.py',consumer)
    removed = []
    def inputs_guard():
        assert (REVIEW/'candidate.json').read_bytes() == candidate_raw
        assert (REVIEW/'prepare-review.py').read_bytes() == consumer
        assert all(safe(name).read_bytes() == raw for name,raw in retained.items()), 'Complete input changed'
        assert all((ROOT/'tools/cleanup_20261009'/name).read_bytes() == raw for name,raw in helpers.items()), 'Consumer changed'
    try:
        inputs_guard()
        for g in groups:
            inputs_guard()
            for p in g['parts']:
                path = safe(p['path'],g['directory'])
                raw = path.read_bytes()
                assert len(raw) == p['bytes'] and sha(raw) == p['sha256'], 'Concurrent part change'
                assert raw == full[p['fullFile']][p['offset']:p['offset']+p['bytes']]
                path.unlink()
                removed.append(p)
        inputs_guard()
        expected = {k:v for k,v in initial.items() if k not in {p['path'] for p in parts}}
        assert inventory() == expected, 'Unexpected archive inventory delta'
        completed = subprocess.run([sys.executable,'-B',str(AFTER/'prepare-review.py')],cwd=ROOT,capture_output=True,timeout=180)
        save_new(AFTER/'consumer-stdout.log',completed.stdout)
        save_new(AFTER/'consumer-stderr.log',completed.stderr)
        assert completed.returncode == 0, 'Actual post-removal archive consumer failed'
        after = json.loads((AFTER/'candidate.json').read_bytes())
        assert after['pass'] and after['candidateFiles'] == after['candidateBytes'] == after['filesRemoved'] == 0
        assert after['actualOfflineConsumerPorts'] == candidate['actualOfflineConsumerPorts']
        assert after['consumerSourceHashes'] == candidate['consumerSourceHashes']
        inputs_guard()
        assert inventory() == expected and after['temporaryCopiesCleaned']
        receipt = {'schema':'local-transport-retirement-v1','pass':True,'filesRemoved':len(removed),'bytesRemoved':sum(p['bytes'] for p in removed),'candidateSHA256':sha(candidate_raw),'toolSHA256':sha(Path(__file__).read_bytes()),'consumerSHA256':sha(consumer),'nativeCalls':0,'nativeWrites':0,'canonicalSourceWrites':0,'manifestWrites':0,'excludedRoundtripChunksPreserved':True,'retainedInputsVerifiedExact':True,'actualPostRemovalConsumersPass':True,'removed':removed,'scope':'Local duplicate transport files only. Full archives/facts/receipts retained. Disk file bytes, no runtime/performance/restoration certificate.'}
        save_new(AFTER/'removal-receipt.json',encoded(receipt))
        print(json.dumps({k:receipt[k] for k in ('pass','filesRemoved','bytesRemoved','actualPostRemovalConsumersPass','nativeCalls')}))
    except BaseException as error:
        restored=[]; preserved=[]
        for p in removed:
            path=safe(p['path'])
            raw=full[p['fullFile']][p['offset']:p['offset']+p['bytes']]
            assert len(raw)==p['bytes'] and sha(raw)==p['sha256']
            try:
                with path.open('xb') as stream: assert stream.write(raw)==len(raw)
                assert path.read_bytes()==raw
                restored.append(p['path'])
            except FileExistsError: preserved.append(p['path'])
            except BaseException as recovery: error.add_note('Owned rollback failure: '+str(recovery))
        save_new(AFTER/'rollback.json',encoded({'pass':False,'error':str(error),'restored':restored,'preservedConcurrent':preserved,'notes':getattr(error,'__notes__',[])}))
        raise

if __name__ == '__main__': main()
