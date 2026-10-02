"""Read a fresh after capture; write compact receipts only, never Studio/mirrors/Git."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

p = argparse.ArgumentParser()
p.add_argument('--dest', type=Path, required=True)
p.add_argument('--artifacts', type=Path, required=True)
p.add_argument('--install-manifest', type=Path, required=True)
args = p.parse_args()

def read(path):
    return json.loads(path.read_text())

def digest(raw):
    return hashlib.sha256(raw).hexdigest()

def check_catalog(directory, phase):
    metadata = read(directory / 'metadata.received.json')
    assert metadata['task'] == 'level3-promotion-20261002' and metadata['phase'] == phase
    assert (metadata['placeId'], metadata['universeId'], metadata['groupId']) == (131311258779917, 10559217407, 1039373905)
    assert not metadata['editorConflicts'] and not metadata['skipped']
    transfer = read(directory / 'source-transfer-receipt.json')
    assert transfer == metadata['sourceTransfer']
    raw = (directory / 'scripts.json').read_bytes()
    assert digest(raw) == transfer['sha256'] and len(raw) == transfer['bytes']
    sources = json.loads(raw)
    assert len(sources) == metadata['scriptCount']
    rows = {}
    for row in sources:
        assert row['path'] not in rows
        value = row['source'].encode()
        assert row['editorMatch'] is True and len(value) == row['sourceBytes']
        assert digest(value) == row['sourceSha256'] == row['editorSourceSha256']
        rows[row['path']] = row
    native_hash = hashlib.sha256()
    native_bytes = 0
    files = sorted(directory.glob('native-part-*.bin'))
    assert [f.name for f in files] == [f'native-part-{i:05d}.bin' for i in range(metadata['nativeParts'])]
    for file in files:
        value = file.read_bytes()
        native_hash.update(value)
        native_bytes += len(value)
    assert native_hash.hexdigest() == metadata['nativeSHA256'] and native_bytes == metadata['nativeBytes']
    return metadata, rows, digest(raw)

before, baseline, before_catalog_hash = check_catalog(args.dest / 'before', 'before')
after, current, after_catalog_hash = check_catalog(args.dest / 'after', 'after')
install = read(args.install_manifest)
assert install['task'] == 'level3-promotion-20261002' and install['sourceCount'] == 14
targets = {r['path']: r for r in install['rows']}
assert len(targets) == 14
scope = []
for path, candidate in targets.items():
    actual = current.get(path)
    parts = path.split('.')
    mirror = '/'.join(parts[:-1] + [parts[-1] + '.' + candidate['className'] + '.lua'])
    scope.append({'path': path, 'class': candidate['className'], 'mirrorPath': mirror,
                  'new': candidate['new'], 'expectedSHA256': candidate['candidateSHA256'],
                  'actualSHA256': actual['sourceSha256'] if actual else None,
                  'verified': bool(actual and actual['class'] == candidate['className']
                                   and actual['sourceSha256'] == candidate['candidateSHA256'])})
added = sorted(set(current) - set(baseline))
removed = sorted(set(baseline) - set(current))
changed = sorted(path for path in set(baseline) & set(current)
                 if baseline[path]['class'] != current[path]['class']
                 or baseline[path]['sourceSha256'] != current[path]['sourceSha256'])
original6 = sorted(path for path in baseline if 'Level 6' in path or 'Level6' in path)
level6_rows = [{'path': path, 'class': baseline[path]['class'],
                'beforeSHA256': baseline[path]['sourceSha256'],
                'afterSHA256': current[path]['sourceSha256'] if path in current else None,
                'unchanged': bool(path in current and baseline[path]['class'] == current[path]['class']
                                  and baseline[path]['sourceSha256'] == current[path]['sourceSha256'])}
               for path in original6]
expected_added = sorted(path for path, row in targets.items() if row['new'])
expected_changed = sorted(path for path, row in targets.items() if not row['new'])
report = {
    'task': install['task'], 'phase': 'after', 'beforeCaptureId': before['captureId'], 'captureId': after['captureId'],
    'beforeSourceCount': len(baseline), 'sourceCount': len(current), 'expectedSourceCount': 231,
    'sourceCountMatchesExpected': len(current) == 231, 'sourceEditorConflicts': 0,
    'beforeSourceCatalogSHA256': before_catalog_hash, 'sourceCatalogSHA256': after_catalog_hash,
    'nativeForestSHA256': after['nativeSHA256'], 'nativeForestBytes': after['nativeBytes'],
    'taskSourceRows': scope, 'all14TaskSourcesMatchFrozenInstall': all(r['verified'] for r in scope),
    'addedSources': added, 'removedSources': removed, 'changedSources': changed,
    'expectedAddedSources': expected_added, 'expectedChangedSources': expected_changed,
    'sourceChangesExactlyMatchTaskScope': added == expected_added and not removed and changed == expected_changed,
    'unexpectedAddedSources': sorted(set(added) - set(expected_added)),
    'unexpectedChangedSources': sorted(set(changed) - set(expected_changed)),
    'originalLevel6SourceCount': len(original6), 'originalLevel6SourceRows': level6_rows,
    'allOriginalLevel6SourcesUnchanged': all(r['unchanged'] for r in level6_rows),
    'studioWritesPerformed': False, 'repositoryMirrorsWritten': False, 'gitIndexWrites': False,
    'limits': 'Fresh complete Source/editor and native-transfer integrity plus scoped Source delta verification. Source-only receipt does not claim native place recovery, geometry parity, gameplay or publication. Unexpected concurrent changes are reported, never restored.',
    'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
output = args.artifacts / 'after'
output.mkdir(parents=True, exist_ok=True)
serialized = (json.dumps(report, indent=2) + '\n').encode()
receipt = output / 'source-scope-verification.json'
if receipt.exists():
    raise RuntimeError('Do not overwrite an existing verification receipt: ' + str(receipt))
receipt.write_bytes(serialized)
(output / 'source-inventory.json').write_bytes((args.dest / 'after' / 'source-inventory.json').read_bytes())
print(json.dumps({k: report[k] for k in ['captureId', 'sourceCount', 'sourceCountMatchesExpected',
    'all14TaskSourcesMatchFrozenInstall', 'sourceChangesExactlyMatchTaskScope',
    'originalLevel6SourceCount', 'allOriginalLevel6SourcesUnchanged']}))
