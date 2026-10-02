"""Verify bounded direct-return Sources and two fresh Source/editor catalogs."""
from pathlib import Path
import argparse
import base64
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


def digest(value):
    return hashlib.sha256(value).hexdigest()


def immutable(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == value, 'Different existing receipt: ' + str(path)
    else:
        path.write_bytes(value)


def record(path, value):
    immutable(path, (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode())


directory = args.dest.resolve() / 'after' / 'direct-source'
first = read(directory / 'catalog-first.json')
second = read(directory / 'catalog-second.json')
for catalog in (first, second):
    assert catalog['task'] == 'level3-promotion-20261002' and catalog['phase'] == 'after'
    assert (catalog['placeId'], catalog['universeId'], catalog['groupId']) == (131311258779917, 10559217407, 1039373905)
    assert not catalog['skipped'] and catalog['scriptCount'] == 231
    assert len(catalog['sources']) == 231 and len(catalog['roots']) == catalog['rootCount']
assert first['sources'] == second['sources'], 'Concurrent Source/editor catalog change'
assert first['roots'] == second['roots'], 'Concurrent root structure change'
expected = {row['path']: row for row in first['sources']}
assert len(expected) == 231
rows, chunks = {}, {}
parts = sorted(directory.glob('part-*.json'))
assert [f.name for f in parts] == [f'part-{i:04d}.json' for i in range(len(parts))]
for part in parts:
    data = read(part)
    if data['kind'] == 'small':
        for row in data['rows']:
            assert row['path'] not in rows and row['path'] not in chunks
            rows[row['path']] = row
    else:
        assert data['kind'] == 'chunk' and data['path'] not in rows
        value = base64.b64decode(data['base64'], validate=True)
        assert len(value) == data['length']
        reference = expected[data['path']]
        for key in ['path', 'class', 'sourceBytes', 'sourceSha256', 'editorSourceSha256', 'editorMatch']:
            assert data[key] == reference[key]
        chunks.setdefault(data['path'], []).append((data['offset'], value))
for path, pieces in chunks.items():
    offset, values = 0, []
    for start, value in sorted(pieces):
        assert start == offset, 'Missing/overlapping Source chunk: ' + path
        offset += len(value)
        values.append(value)
    rows[path] = dict(expected[path], source=b''.join(values).decode('utf-8'))
assert set(rows) == set(expected)
for path, row in rows.items():
    reference = expected[path]
    for key in ['path', 'class', 'sourceBytes', 'sourceSha256', 'editorSourceSha256', 'editorMatch']:
        assert row[key] == reference[key]
    value = row['source'].encode()
    assert row['editorMatch'] is True
    assert len(value) == row['sourceBytes'] and digest(value) == row['sourceSha256'] == row['editorSourceSha256']
source_bytes = (json.dumps([rows[path] for path in sorted(rows)], ensure_ascii=False, separators=(',', ':')) + '\n').encode()
immutable(directory / 'scripts.json', source_bytes)
before = read(args.dest / 'before' / 'metadata.received.json')
baseline_rows = read(args.dest / 'before' / 'scripts.json')
baseline = {row['path']: row for row in baseline_rows}
assert len(baseline) == before['scriptCount'] == 228
for row in baseline.values():
    assert row['editorMatch'] and digest(row['source'].encode()) == row['sourceSha256'] == row['editorSourceSha256']
manifest = read(args.install_manifest)
assert manifest['sourceCount'] == 14 and len(manifest['rows']) == 14
targets = {row['path']: row for row in manifest['rows']}
scope = []
for path, candidate in targets.items():
    actual = rows.get(path)
    pieces = path.split('.')
    mirror = '/'.join(pieces[:-1] + [pieces[-1] + '.' + candidate['className'] + '.lua'])
    scope.append({'path': path, 'class': candidate['className'], 'mirrorPath': mirror,
                  'new': candidate['new'], 'expectedSHA256': candidate['candidateSHA256'],
                  'actualSHA256': actual['sourceSha256'] if actual else None,
                  'verified': bool(actual and actual['class'] == candidate['className'] and actual['sourceSha256'] == candidate['candidateSHA256'])})
added = sorted(set(rows) - set(baseline))
removed = sorted(set(baseline) - set(rows))
changed = sorted(path for path in set(rows) & set(baseline) if rows[path]['class'] != baseline[path]['class'] or rows[path]['sourceSha256'] != baseline[path]['sourceSha256'])
expected_added = sorted(path for path, row in targets.items() if row['new'])
expected_changed = sorted(path for path, row in targets.items() if not row['new'])
original6 = sorted(path for path in baseline if 'Level 6' in path or 'Level6' in path)
level6_rows = [{'path': path, 'class': baseline[path]['class'], 'beforeSHA256': baseline[path]['sourceSha256'],
               'afterSHA256': rows[path]['sourceSha256'] if path in rows else None,
               'unchanged': bool(path in rows and baseline[path]['class'] == rows[path]['class'] and baseline[path]['sourceSha256'] == rows[path]['sourceSha256'])} for path in original6]
old_roots = {row['path']: row for row in before['roots']}
new_roots = {row['path']: row for row in first['roots']}
root_changes = [{'path': path, 'beforeDescendants': old_roots[path]['descendants'], 'afterDescendants': new_roots[path]['descendants'],
                 'sameClassAndName': old_roots[path]['class'] == new_roots[path]['class'] and old_roots[path]['name'] == new_roots[path]['name']}
                for path in sorted(set(old_roots) & set(new_roots))
                if any(old_roots[path][key] != new_roots[path][key] for key in ['class', 'name', 'descendants'])]
report = {'task': manifest['task'], 'phase': 'after', 'beforeCaptureId': before['captureId'], 'captureId': first['captureId'],
          'method': first['method'], 'beforeSourceCount': 228, 'sourceCount': len(rows), 'expectedSourceCount': 231,
          'sourceCountMatchesExpected': len(rows) == 231, 'sourceEditorConflicts': 0,
          'sourceCatalogSHA256': digest(source_bytes), 'sourceCatalogPath': str(directory / 'scripts.json'),
          'boundedDirectReturnParts': len(parts), 'twoCompleteSourceHashReadsMatch': True, 'twoRootStructureReadsMatch': True,
          'taskSourceRows': scope, 'all14TaskSourcesMatchFrozenInstall': all(row['verified'] for row in scope),
          'addedSources': added, 'removedSources': removed, 'changedSources': changed,
          'expectedAddedSources': expected_added, 'expectedChangedSources': expected_changed,
          'sourceChangesExactlyMatchTaskScope': added == expected_added and not removed and changed == expected_changed,
          'unexpectedAddedSources': sorted(set(added) - set(expected_added)), 'unexpectedChangedSources': sorted(set(changed) - set(expected_changed)),
          'originalLevel6SourceCount': len(original6), 'originalLevel6SourceRows': level6_rows,
          'allOriginalLevel6SourcesUnchanged': all(row['unchanged'] for row in level6_rows),
          'beforeRootCount': len(old_roots), 'rootCount': len(new_roots),
          'addedRootPaths': sorted(set(new_roots) - set(old_roots)), 'removedRootPaths': sorted(set(old_roots) - set(new_roots)),
          'rootStructureChanges': root_changes, 'nativeForestTransferred': False, 'nativeRecoveryVerified': False,
          'studioWritesPerformed': False, 'repositoryMirrorsWritten': False, 'gitIndexWrites': False,
          'limits': 'All fresh Sources/editor hashes and root identities/descendant counts were read twice with no changes. Native geometry/properties are not established by counts. No fresh after native file/forest, gameplay, or publication claim. Actual before native file remains preserved.',
          'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat()}
output = args.artifacts / 'after'
record(output / 'source-scope-verification.json', report)
record(output / 'source-inventory.json', {'count': len(rows), 'editorConflicts': 0, 'sources': first['sources']})
record(output / 'direct-source-transfer.json', {'task': manifest['task'], 'captureId': first['captureId'],
    'sourceCatalogPath': str(directory / 'scripts.json'), 'sourceCatalogSHA256': digest(source_bytes),
    'sourceCatalogBytes': len(source_bytes), 'parts': len(parts), 'sourceCount': len(rows),
    'sourceHashesVerifiedLocally': True, 'nativeForestTransferred': False})
print(json.dumps({key: report[key] for key in ['captureId', 'sourceCount', 'all14TaskSourcesMatchFrozenInstall', 'sourceChangesExactlyMatchTaskScope', 'originalLevel6SourceCount', 'allOriginalLevel6SourcesUnchanged', 'addedRootPaths', 'rootStructureChanges']}))
