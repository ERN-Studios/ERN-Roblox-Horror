"""Read-only verification of the rolled-back transport trial and setup repair.

Writes only new diagnostic proof files beside this file. Never calls the
retirement tool, removes a part, imports a helper, or contacts Studio.
"""
from pathlib import Path
import ast
import difflib
import hashlib
import json
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BASE = HERE.parent
BEFORE = ROOT / '.git/mongotv-cleanup-20261009/transport-parts-before-v1'
REVIEW = BASE / 'transport-parts-review-v1'
TOOL = ROOT / 'tools/cleanup_20261009/retire_transport_parts.py'
ALLOWED = {'diagnostic-archive-before-v7', 'diagnostic-archive-before-v8',
           'external-storage-archive-v1', 'retired-authoring-archive-v3'}
BEFORE_SHA = '54d4961f3117f8ebb7136259edfa269b1017895b836afc80f373ffd9679ecfda'
CANDIDATE_SHA = 'fbe29bc1276790f25cec4b1cc6952e72627c7f185c750634ba780ae11875d212'
CONSUMER_SHA = '3044bce8c8496d47c21ac03425cc7f0d81780dad0d2150250d90173a05d6cfe6'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(name, raw):
    with (HERE / name).open('xb') as stream:
        assert stream.write(raw) == len(raw)
    assert (HERE / name).read_bytes() == raw


def current(relative):
    path = ROOT / relative
    assert path.resolve().is_relative_to(BASE.resolve())
    assert not path.is_symlink()
    return path.read_bytes()


def main():
    old = (HERE / 'source-before-trial.py').read_bytes()
    new = TOOL.read_bytes()
    assert sha(old) == BEFORE_SHA
    assert not (BASE / 'transport-parts-after-v2').exists()
    assert not (ROOT / '.git/mongotv-cleanup-20261009/transport-parts-before-v2').exists()
    # Exact byte delta, including retained newline encoding. No other guards,
    # ports, paths, pins, rollback code or assertions may change.
    nl = b'\r\n' if b'\r\n' in old else b'\n'
    expected = old.replace(b"AFTER = BASE / 'transport-parts-after-v1'",
                           b"AFTER = BASE / 'transport-parts-after-v2'")
    expected = expected.replace(b"CHECKPOINT = ROOT / '.git/mongotv-cleanup-20261009/transport-parts-before-v1'",
                                b"CHECKPOINT = ROOT / '.git/mongotv-cleanup-20261009/transport-parts-before-v2'")
    attrs = b"    save_new(AFTER/'.gitattributes',b'* -text -whitespace\\n')" + nl
    assert expected.count(attrs) == 1
    expected = expected.replace(attrs, b'')
    marker = b'        raise' + nl + nl + b"if __name__ == '__main__': main()"
    replacement = (b'        raise' + nl + b'    finally:' + nl
                   + b"        if not (AFTER/'.gitattributes').exists():" + nl
                   + b"            save_new(AFTER/'.gitattributes',b'* -text -whitespace\\n')" + nl
                   + nl + b"if __name__ == '__main__': main()")
    assert expected.count(marker) == 1
    expected = expected.replace(marker, replacement)
    assert new == expected, 'Repair contains changes outside the exact scoped delta'
    old_ast = ast.parse(old, filename='source-before-trial.py')
    new_ast = ast.parse(new, filename=str(TOOL))
    compile(old_ast, 'source-before-trial.py', 'exec')
    compile(new_ast, str(TOOL), 'exec')
    old_asserts = [ast.dump(n, include_attributes=False) for n in ast.walk(old_ast) if isinstance(n, ast.Assert)]
    new_asserts = [ast.dump(n, include_attributes=False) for n in ast.walk(new_ast) if isinstance(n, ast.Assert)]
    assert old_asserts == new_asserts

    candidate_raw = (REVIEW / 'candidate.json').read_bytes()
    assert sha(candidate_raw) == CANDIDATE_SHA
    assert (BEFORE / 'candidate-before.json').read_bytes() == candidate_raw
    consumer = (REVIEW / 'prepare-review.py').read_bytes()
    assert sha(consumer) == CONSUMER_SHA
    assert (HERE / 'prepare-review.py').read_bytes() == consumer
    candidate = json.loads(candidate_raw)
    groups = candidate['eligibleGroups']
    parts = [p for g in groups for p in g['parts']]
    assert parts == candidate['allowedPaths'] and len(parts) == 92
    assert sum(p['bytes'] for p in parts) == 60168414
    assert all(g['directory'] in ALLOWED for g in groups)
    for g in groups:
        full = current(g['fullFile'])
        assert len(full) == g['bytes'] and sha(full) == g['fullFileSHA256']
        assert sha(current(g['receiptFile'])) == g['receiptSHA256']
        for p in g['parts']:
            raw = current(p['path'])
            assert len(raw) == p['bytes'] and sha(raw) == p['sha256']
            assert raw == full[p['offset']:p['offset'] + p['bytes']]
    for name, value in candidate['consumerSourceHashes'].items():
        assert sha((ROOT / 'tools/cleanup_20261009' / name).read_bytes()) == value
    initial = json.loads((BEFORE / 'inventory-before.json').read_bytes())
    inventory = {p.relative_to(ROOT).as_posix(): sha(p.read_bytes())
                 for name in ALLOWED | {'external-storage-reopen-v1'}
                 for p in (BASE / name).rglob('*') if p.is_file()}
    assert inventory == initial, 'The complete five-archive inventory differs from the v1 checkpoint'
    rollback = json.loads((HERE / 'rollback.json').read_bytes())
    assert rollback['pass'] is False
    assert rollback['restored'] == [p['path'] for p in parts]
    assert rollback['preservedConcurrent'] == rollback['notes'] == []
    stderr = (HERE / 'consumer-stderr.log').read_bytes()
    assert b'FileExistsError' in stderr and b'.gitattributes' in stderr
    old_evidence = {name: sha((HERE / name).read_bytes()) for name in
                    ('rollback.json', 'consumer-stdout.log', 'consumer-stderr.log',
                     'prepare-review.py', '.gitattributes', 'source-before-trial.py')}
    diff = ''.join(difflib.unified_diff(old.decode().splitlines(keepends=True),
                                      new.decode().splitlines(keepends=True),
                                      fromfile='executed-v1', tofile='prepared-v2')).encode()
    receipt = {
        'schema': 'transport-setup-repair-review-v1', 'pass': True,
        'executedV1SHA256': sha(old), 'preparedV2SHA256': sha(new),
        'candidateSHA256': sha(candidate_raw), 'consumerSHA256': sha(consumer),
        'all92PartsRestoredExact': True, 'partCount': len(parts),
        'partBytes': sum(p['bytes'] for p in parts),
        'allFiveArchiveInventoriesEqualV1Checkpoint': True,
        'inventoryFileCount': len(initial),
        'retainedFullFilesReceiptsAndConsumerHelpersExact': True,
        'exactScopedByteDelta': True, 'allAssertionsASTUnchanged': True,
        'pythonParseAndCompileBeforeAfter': True,
        'v1EvidenceSHA256': old_evidence, 'diffSHA256': sha(diff),
        'reviewSourceSHA256': sha(Path(__file__).read_bytes()),
        'changes': ['after-v2/before-v2 evidence paths',
                    'remove pre-consumer .gitattributes creation',
                    'finally create .gitattributes only when absent'],
        'applyExecuted': False, 'filesRemoved': 0, 'nativeCalls': 0,
        'nativeWrites': 0, 'canonicalSourceWrites': 0, 'manifestWrites': 0,
        'actualV2PostRemovalConsumersAndInventoryGate': 'pending root execution',
        'scope': 'Static/AST repair review and exact rollback/input verification. No retirement or consumer execution.',
    }
    assert TOOL.read_bytes() == new
    assert all(sha((HERE / name).read_bytes()) == value for name, value in old_evidence.items())
    save('setup-repair.diff', diff)
    save('setup-repair-review.json', (json.dumps(receipt, indent=2) + '\n').encode())
    print(json.dumps({k: receipt[k] for k in
                      ('pass', 'executedV1SHA256', 'preparedV2SHA256',
                       'all92PartsRestoredExact', 'inventoryFileCount', 'applyExecuted')}))


if __name__ == '__main__':
    main()
