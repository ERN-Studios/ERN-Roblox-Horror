"""Archive a fully recoverable after snapshot with explicit concurrent changes.

The strict original 'only task changes' check is preserved as false. This
separate route requires exact accounted-difference verification, all eight
current Source/editor pins, and all nine native static PBR references.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os

TASK = Path(__file__).resolve().parent
SOURCE = Path('/private/tmp/lobby-r4-native-after-20261001')
DEST = TASK / 'native-after'

def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()

def copy_exact(source, destination):
    digest = sha(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        assert destination.stat().st_size == source.stat().st_size and sha(destination) == digest, f'Existing archive differs: {destination}'
    else:
        partial = destination.with_name(destination.name + '.partial')
        with source.open('rb') as incoming, partial.open('xb') as outgoing:
            for block in iter(lambda: incoming.read(1024 * 1024), b''): outgoing.write(block)
            outgoing.flush(); os.fsync(outgoing.fileno())
        os.replace(partial, destination)
        assert sha(destination) == digest
    return {'file': destination.relative_to(TASK).as_posix(), 'bytes': destination.stat().st_size, 'sha256': digest}

def main():
    def read(name): return json.loads((SOURCE / name).read_bytes())
    gate = read('checkpoint-install-gate.json')
    strict = read('scoped-native-preservation.json')
    accounted = read('accounted-concurrent-native-preservation.json')
    mirrors = read('final-scoped-source-mirror.json')
    pbr = read('static-pbr-native-reference-verification-final.json')
    assert gate['verified'] is True and strict['verified'] is False
    assert accounted['verified'] is True and accounted['allDifferencesAccountedAfterExactLocalNormalization'] is True
    assert accounted['allUnrelatedStateUnchanged'] is False and accounted['strictOnlyTaskPreservationVerified'] is False
    assert gate['captureId'] == accounted['afterCaptureId'] == strict['afterCaptureId']
    assert gate['nativeSHA256'] == accounted['afterNativeSHA256'] == strict['afterNativeSHA256']
    assert accounted['beforeSourceCount'] == 210 and accounted['afterSourceCount'] == 213
    assert accounted['beforeRootCount'] == 186 and accounted['afterRootCount'] == 189
    assert len(accounted['concurrentSourceRows']) == 5 and len(accounted['concurrentNativeRootRows']) == 2
    assert len(accounted['additiveRoots']) == 3 and accounted['scopedSourceCount'] == 8
    assert accounted['baselineForestCanonicalEqual'] is True and len(accounted['errors']) == 0
    assert all(row['equal'] for row in accounted['serviceRows'])
    for proof in (mirrors, pbr):
        assert proof['verified'] is True and proof['captureId'] == gate['captureId']
        assert proof['nativeSHA256'] == gate['nativeSHA256'] and proof['catalogSHA256'] == accounted['catalogSHA256']
    assert mirrors['sourceCount'] == 8 and pbr['templateCount'] == 3 and pbr['imageReferenceCount'] == 9
    assert gate['placeId'] == 131311258779917 and gate['universeId'] == 10559217407 and gate['groupId'] == 1039373905
    for row in gate['files']:
        source = (SOURCE / row['file']).resolve()
        assert source.is_relative_to(SOURCE.resolve()) and source.stat().st_size == row['bytes'] and sha(source) == row['sha256']
    records = []
    for source in sorted(SOURCE.rglob('*')):
        if not source.is_file(): continue
        assert not source.is_symlink() and not source.name.endswith('.partial')
        relative = source.relative_to(SOURCE)
        destination = TASK / 'fresh-source-after' / relative.relative_to('fresh-source') if relative.parts[0] == 'fresh-source' else DEST / relative
        records.append(copy_exact(source, destination))
    receipt = {'schema': 'lobby-r4-authoritative-native-after-archive-v2', 'verified': True,
        'archivedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'captureId': gate['captureId'], 'nativeSHA256': gate['nativeSHA256'], 'nativePlaceSHA256': gate['nativePlaceSHA256'],
        'noncloudSource': str(SOURCE), 'archiveDirectory': str(DEST), 'sourceExportDirectory': str(TASK / 'fresh-source-after'),
        'recoveryGateVerified': True, 'strictOnlyTaskPreservationVerified': False,
        'allUnrelatedStateUnchanged': False, 'concurrentChangesPreservedAndExactlyAccounted': True,
        'accountedConcurrentPreservationFile': 'native-after/accounted-concurrent-native-preservation.json',
        'finalEightSourceMirrorsVerified': True, 'completeCapturedSourceCount': 213,
        'staticPBRNativeReferencesVerified': True, 'catalogSHA256': accounted['catalogSHA256'],
        'fileCount': len(records), 'files': records, 'studioActions': False, 'beforeCheckpointChanged': False,
        'scope': 'Recoverable exact authoritative after archive. Concurrent Level1 and PushDoors work is explicitly preserved, not attributed to this task or reverted. Exact normalized comparison accounts every native difference; unchanged-state claim remains false.'}
    (TASK / 'review/native-after-archive-verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'verified': True, 'captureId': gate['captureId'], 'fileCount': len(records), 'archiveDirectory': str(DEST), 'concurrentChangesPreserved': True}), flush=True)

if __name__ == '__main__': main()
