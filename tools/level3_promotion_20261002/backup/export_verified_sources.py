"""Export only the 14 verified task Sources, preserving current mirror bytes first."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

p = argparse.ArgumentParser()
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--dest', type=Path, required=True)
p.add_argument('--artifacts', type=Path, required=True)
p.add_argument('--install-manifest', type=Path, required=True)
p.add_argument('--source-dir', type=Path, help='Explicit direct-return Source directory when native capture is unavailable')
args = p.parse_args()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def read(path):
    return json.loads(path.read_text())


def immutable(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == value, 'Different checkpoint bytes: ' + str(path)
    else:
        path.write_bytes(value)


repo = args.repo.resolve()
directory = args.source_dir.resolve() if args.source_dir else args.dest.resolve() / 'after'
artifacts = args.artifacts.resolve() / 'after'
receipt_path = artifacts / 'repository-mirror-export.json'
assert not receipt_path.exists(), 'Do not overwrite an export receipt'
scope = read(artifacts / 'source-scope-verification.json')
assert scope['sourceCountMatchesExpected'] and scope['all14TaskSourcesMatchFrozenInstall']
assert scope['sourceChangesExactlyMatchTaskScope'] and scope['allOriginalLevel6SourcesUnchanged']
manifest_raw = args.install_manifest.read_bytes()
manifest = json.loads(manifest_raw)
assert manifest['sourceCount'] == 14 and len(manifest['rows']) == 14
sources_raw = (directory / 'scripts.json').read_bytes()
assert digest(sources_raw) == scope['sourceCatalogSHA256']
sources = {row['path']: row for row in json.loads(sources_raw)}
scope_rows = {row['path']: row for row in scope['taskSourceRows']}
prepared = []
for target in manifest['rows']:
    actual = sources[target['path']]
    verified = scope_rows[target['path']]
    value = actual['source'].encode()
    assert actual['editorMatch'] is True
    assert actual['class'] == target['className']
    assert digest(value) == actual['sourceSha256'] == actual['editorSourceSha256'] == target['candidateSHA256']
    assert verified['verified'] and verified['actualSHA256'] == digest(value)
    relative = Path(verified['mirrorPath'])
    assert not relative.is_absolute() and '..' not in relative.parts
    destination = repo / relative
    assert destination.resolve().is_relative_to(repo)
    assert not destination.is_symlink()
    prior = destination.read_bytes() if destination.exists() else None
    prepared.append((target, value, relative, destination, prior))

# Preserve every current task mirror before changing any mirror.
checkpoint = directory / 'repository-mirror-prior'
checkpoint_rows = []
for target, value, relative, destination, prior in prepared:
    if prior is not None:
        immutable(checkpoint / relative, prior)
    checkpoint_rows.append({'path': str(relative), 'existed': prior is not None,
                            'sha256': digest(prior) if prior is not None else None,
                            'bytes': len(prior) if prior is not None else 0})
immutable(checkpoint / 'manifest.json', (json.dumps({'task': manifest['task'],
    'captureId': scope['captureId'], 'mirrors': checkpoint_rows}, indent=2) + '\n').encode())

exported = []
for target, value, relative, destination, prior in prepared:
    current = destination.read_bytes() if destination.exists() else None
    assert current == prior, 'Concurrent repository mirror change: ' + str(relative)
    changed = current != value
    if changed:
        destination.parent.mkdir(parents=True, exist_ok=True)
        # This workspace permits scoped in-place writes but rejects atomic
        # replacement of existing cloud-backed files. Prior bytes are already
        # durable above; compare again immediately before the authorized write.
        current = destination.read_bytes() if destination.exists() else None
        assert current == prior, 'Concurrent repository mirror change before write: ' + str(relative)
        with destination.open('wb' if prior is not None else 'xb') as handle:
            handle.write(value)
    assert destination.read_bytes() == value
    exported.append({'instancePath': target['path'], 'class': target['className'],
                     'mirrorPath': str(relative), 'sourceSHA256': digest(value),
                     'sourceBytes': len(value), 'changed': changed,
                     'priorSHA256': digest(prior) if prior is not None else None})

report = {'task': manifest['task'], 'captureId': scope['captureId'],
          'sourceCount': len(exported), 'sourceEditorConflicts': 0,
          'sourceCatalogSHA256': digest(sources_raw),
          'finalInstallManifestPath': str(args.install_manifest),
          'finalInstallManifestSHA256': digest(manifest_raw),
          'priorMirrorCheckpoint': str(checkpoint), 'mirrors': exported,
          'writeMethod': 'Scoped in-place writes after exact prior-byte comparison and durable checkpoint; new mirrors use exclusive creation',
          'studioWritesPerformed': False, 'gitIndexWrites': False,
          'limits': 'Exact 14 task Source/editor mirrors from the fresh after capture. Prior local mirror bytes are preserved. This receipt does not claim whole-repository parity, gameplay, publication, or native-place recovery.',
          'exportedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat()}
immutable(receipt_path, (json.dumps(report, indent=2) + '\n').encode())
print(json.dumps({'captureId': report['captureId'], 'mirrorsVerified': len(exported),
                  'mirrorsChanged': sum(row['changed'] for row in exported),
                  'priorMirrorCheckpoint': str(checkpoint), 'gitIndexWrites': False}))
