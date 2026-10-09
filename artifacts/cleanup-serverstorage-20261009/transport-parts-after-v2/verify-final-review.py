"""Verify completed local retirement evidence without restoring/deleting files.

Writes one new receipt beside this helper. Reads completed archives and private
before checkpoints; never executes the retirement tool, a capture, or Studio.
"""
from pathlib import Path
import ast
import hashlib
import json
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
BASE = HERE.parent
ROOT = HERE.parents[2]
REVIEW = BASE / 'transport-parts-review-v1'
FAILED = BASE / 'transport-parts-after-v1'
PRIVATE = ROOT / '.git/mongotv-cleanup-20261009'
DIRS = ('diagnostic-archive-before-v7', 'diagnostic-archive-before-v8',
        'external-storage-archive-v1', 'external-storage-reopen-v1',
        'retired-authoring-archive-v3')
TOOL = ROOT / 'tools/cleanup_20261009/retire_transport_parts.py'
CANDIDATE_SHA = 'fbe29bc1276790f25cec4b1cc6952e72627c7f185c750634ba780ae11875d212'
TOOL_SHA = '17618f16d82d29346072df635bdbdc690ffad4aee81d68069bb01e23e25dbb48'
CONSUMER_SHA = '3044bce8c8496d47c21ac03425cc7f0d81780dad0d2150250d90173a05d6cfe6'
REMOVAL_SHA = '60e100e3688c7740a71c10067363b0c873d42bcb30ae82bcb1411e27541c2b73'
AFTER_SHA = 'ca4886f0cde2fe691b71c5372192591706fc0e0fdb5ac7f3d635da0c6f5b267f'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path):
    assert not path.is_symlink()
    return path.read_bytes()


def pinned(path, value):
    raw = read(path)
    assert sha(raw) == value, str(path)
    return raw


def main():
    before_raw = pinned(REVIEW / 'candidate.json', CANDIDATE_SHA)
    after_raw = pinned(HERE / 'candidate.json', AFTER_SHA)
    removal_raw = pinned(HERE / 'removal-receipt.json', REMOVAL_SHA)
    tool_raw = pinned(TOOL, TOOL_SHA)
    for folder in (REVIEW, FAILED, HERE):
        pinned(folder / 'prepare-review.py', CONSUMER_SHA)
        assert not any(p.is_dir() and p.name.startswith('.transport-consumer-')
                       for p in folder.rglob('*')), 'Owned temporary copy remains'
    before = json.loads(before_raw)
    after = json.loads(after_raw)
    removal = json.loads(removal_raw)
    assert before['pass'] and after['pass'] and removal['pass']
    assert removal['candidateSHA256'] == CANDIDATE_SHA
    assert removal['toolSHA256'] == TOOL_SHA and removal['consumerSHA256'] == CONSUMER_SHA
    assert removal['filesRemoved'] == before['candidateFiles'] == 92
    assert removal['bytesRemoved'] == before['candidateBytes'] == 60168414
    assert removal['removed'] == before['allowedPaths']
    assert removal['excludedRoundtripChunksPreserved']
    assert removal['retainedInputsVerifiedExact'] and removal['actualPostRemovalConsumersPass']
    assert all(removal[k] == 0 for k in
               ('nativeCalls', 'nativeWrites', 'canonicalSourceWrites', 'manifestWrites'))
    assert after['candidateFiles'] == after['candidateBytes'] == after['filesRemoved'] == 0
    assert after['eligibleGroups'] == []
    assert before['actualOfflineConsumerPorts'] == after['actualOfflineConsumerPorts']
    assert all(p['pass'] for p in after['actualOfflineConsumerPorts'])
    assert before['consumerSourceHashes'] == after['consumerSourceHashes']
    assert before['excludedGroups'] == after['excludedGroups']
    assert after['temporaryCopiesCleaned'] and after['originalFiveArchiveInventoriesBeforeAfterExact']
    assert read(HERE / 'consumer-stderr.log') == b''
    stdout = json.loads(read(HERE / 'consumer-stdout.log'))
    assert stdout == {'pass': True, 'filesRemoved': 0, 'candidateFiles': 0,
                      'candidateBytes': 0, 'temporaryCopiesCleaned': True}
    for name, value in before['consumerSourceHashes'].items():
        pinned(ROOT / 'tools/cleanup_20261009' / name, value)
    initial_raw = read(PRIVATE / 'transport-parts-before-v2/inventory-before.json')
    assert read(PRIVATE / 'transport-parts-before-v2/candidate-before.json') == before_raw
    initial_v1_raw = read(PRIVATE / 'transport-parts-before-v1/inventory-before.json')
    # Set iteration can reorder JSON object keys between processes. Compare the
    # path-to-byte-hash inventory contract, recording both original raw hashes.
    assert json.loads(initial_v1_raw) == json.loads(initial_raw)
    assert read(PRIVATE / 'transport-parts-before-v1/candidate-before.json') == before_raw
    initial = json.loads(initial_raw)
    removed_paths = {p['path'] for p in removal['removed']}
    expected = {k: v for k, v in initial.items() if k not in removed_paths}
    inventory = {p.relative_to(ROOT).as_posix(): sha(read(p))
                 for name in DIRS for p in (BASE / name).rglob('*') if p.is_file()}
    assert len(initial) == 138 and len(expected) == len(inventory) == 46
    assert inventory == expected, 'Unexpected retained-input addition/removal/change'
    groups = before['eligibleGroups']
    for group in groups:
        full_path = ROOT / group['fullFile']
        assert full_path.resolve().is_relative_to((BASE / group['directory']).resolve())
        full = pinned(full_path, group['fullFileSHA256'])
        assert len(full) == group['bytes']
        pinned(ROOT / group['receiptFile'], group['receiptSHA256'])
        offset = 0
        for part in group['parts']:
            path = ROOT / part['path']
            assert not path.exists()
            assert part['fullFile'] == group['fullFile'] and part['offset'] == offset
            raw = full[offset:offset + part['bytes']]
            assert len(raw) == part['bytes'] and sha(raw) == part['sha256']
            assert initial[part['path']] == part['sha256']
            offset += part['bytes']
        assert offset == len(full)
    excluded_parts = [p for g in before['excludedGroups'] for p in g['parts']]
    assert len(excluded_parts) == 4
    for part in excluded_parts:
        raw = pinned(ROOT / part['path'], part['sha256'])
        assert len(raw) == part['bytes']
    repair_raw = read(FAILED / 'setup-repair-review.json')
    repair = json.loads(repair_raw)
    assert repair['pass'] and repair['all92PartsRestoredExact']
    assert repair['allFiveArchiveInventoriesEqualV1Checkpoint'] and repair['inventoryFileCount'] == 138
    assert repair['preparedV2SHA256'] == TOOL_SHA
    assert repair['applyExecuted'] is False
    for name, value in repair['v1EvidenceSHA256'].items():
        pinned(FAILED / name, value)
    pinned(FAILED / 'setup-repair.diff', repair['diffSHA256'])
    pinned(FAILED / 'review-setup-repair.py', repair['reviewSourceSHA256'])
    rollback = json.loads(read(FAILED / 'rollback.json'))
    assert rollback['pass'] is False and rollback['restored'] == [p['path'] for p in removal['removed']]
    assert rollback['preservedConcurrent'] == rollback['notes'] == []
    compile(ast.parse(tool_raw), str(TOOL), 'exec')
    receipt = {
        'schema': 'completed-transport-final-review-v1', 'pass': True,
        'candidateBeforeSHA256': CANDIDATE_SHA, 'candidateAfterSHA256': AFTER_SHA,
        'removalReceiptSHA256': REMOVAL_SHA, 'toolSHA256': TOOL_SHA,
        'consumerSHA256': CONSUMER_SHA, 'setupRepairReceiptSHA256': sha(repair_raw),
        'privateBeforeInventorySHA256': sha(initial_raw),
        'privateBeforeV1InventorySHA256': sha(initial_v1_raw),
        'all138V1V2InventoryPathsAndFileHashesEqual': True,
        'retainedInventory': inventory, 'beforeFiles': 138, 'afterFiles': 46,
        'removedFiles': 92, 'removedBytes': 60168414,
        'all92MissingAndReconstructibleFromExactFullfileSlices': True,
        'actualCompletedConsumerRowsExactBeforeAfter': True,
        'actualOfflineConsumerPorts': after['actualOfflineConsumerPorts'],
        'allHelpersPinnedExact': True, 'all46ProtectedInputsExact': True,
        'excludedFourRoundtripChunksExact': True,
        'historicalV1FailedTrialAndCompleteRollbackEvidenceExact': True,
        'noPrivateConsumerCopiesRemain': True,
        'reviewSourceSHA256': sha(Path(__file__).read_bytes()),
        'reviewFilesRemoved': 0, 'reviewNativeCalls': 0, 'reviewNativeWrites': 0,
        'reviewCanonicalSourceWrites': 0, 'reviewManifestWrites': 0,
        'scope': 'Local completed transport-file retirement only; actual consumers reran in root v2. No new native restore/gameplay/streaming/multiplayer/performance certification.',
    }
    assert TOOL.read_bytes() == tool_raw
    with (HERE / 'final-review.json').open('xb') as stream:
        raw = (json.dumps(receipt, indent=2) + '\n').encode()
        assert stream.write(raw) == len(raw)
    assert (HERE / 'final-review.json').read_bytes() == raw
    print(json.dumps({k: receipt[k] for k in
                      ('pass', 'beforeFiles', 'afterFiles', 'removedFiles',
                       'removedBytes', 'all46ProtectedInputsExact',
                       'excludedFourRoundtripChunksExact')}))


if __name__ == '__main__':
    main()
