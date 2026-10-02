"""Explicit root-invoked mirror export after strict local native/live verification.

Default is a read-only export plan. --apply preserves existing mirror bytes in
the supplied external checkpoint directory, compares again, then writes only
the five fixed mirror paths. No Studio, Git, network or DataStore capability.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

p = argparse.ArgumentParser()
p.add_argument('--verification-dir', type=Path, required=True)
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--checkpoint', type=Path, required=True)
p.add_argument('--apply', action='store_true')
args = p.parse_args()

def sha(value):
    return hashlib.sha256(value).hexdigest()

def preserve(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == value, f'Different checkpoint bytes: {path}'
    else:
        with path.open('xb') as handle:
            handle.write(value)

mapping = {
    'ServerScriptService.Level 3 Systems.Level 3 Mall Manager AI Controller': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Mall Manager AI Controller.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 Objective Controller': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 World Builder': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua'),
    'ServerScriptService.Level 3 Systems.Level 3 Worn Party Visual Adapter': ('ModuleScript', 'ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua'),
    'StarterPlayer.StarterPlayerScripts.Level 3 Reader Client': ('LocalScript', 'StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua'),
}
directory, repo, checkpoint = args.verification_dir.resolve(), args.repo.resolve(), args.checkpoint.resolve()
receipt_path = directory / 'native-five-verification.json'
receipt_bytes = receipt_path.read_bytes()
receipt = json.loads(receipt_bytes)
assert receipt['schema'] == 'level3-finale-native-five-v1' and receipt['verified']
assert receipt['placeId'] == 131311258779917 and receipt['universeId'] == 10559217407
assert receipt['sourceCount'] == 231 and receipt['changedSourceCount'] == 5 and receipt['unchangedSourceCount'] == 226
assert receipt['allSourcePathsClassesEqual'] and receipt['onlyFiveExpectedSourcesChanged']
assert receipt['all231SavedLiveSourceEditorMatch'] and receipt['sourceMaskedNativeCanonicalEqual']
assert sha(Path(receipt['liveCatalogPath']).read_bytes()) == receipt['liveCatalogSHA256'], 'Live catalog changed'
assert sha(Path(receipt['installManifestPath']).read_bytes()) == receipt['installManifestSHA256'], 'Frozen manifest changed'
assert sha(Path(receipt['afterNativePath']).read_bytes()) == receipt['afterNativeSHA256'], 'Saved native after changed'
payload_path = directory / 'native-five-sources.json'
payload_bytes = payload_path.read_bytes()
payload = json.loads(payload_bytes)
assert len(payload) == 5 and {row['path'] for row in payload} == set(mapping)
verified = {row['path']: row for row in receipt['changes']}
prepared = []
for row in payload:
    path = row['path']
    class_name, relative = mapping[path]
    assert row['class'] == class_name == verified[path]['class']
    value = row['source'].encode()
    assert sha(value) == row['sourceSHA256'] == verified[path]['afterSHA256']
    assert len(value) == row['sourceBytes'] == verified[path]['afterBytes']
    destination = repo / relative
    assert destination.resolve().is_relative_to(repo) and not destination.is_symlink()
    prior = destination.read_bytes() if destination.exists() else None
    prepared.append((row, relative, destination, value, prior))
plan = [{'instancePath': row['path'], 'class': row['class'], 'mirrorPath': relative,
         'sourceSHA256': sha(value), 'sourceBytes': len(value), 'changed': prior != value,
         'priorSHA256': sha(prior) if prior is not None else None}
        for row, relative, destination, value, prior in prepared]
if not args.apply:
    print(json.dumps({'apply': False, 'verified': True, 'mirrors': plan}, indent=2))
    raise SystemExit(0)
export_receipt = directory / 'repository-mirror-export.json'
assert not export_receipt.exists(), 'Do not overwrite export receipt'
for row, relative, destination, value, prior in prepared:
    if prior is not None:
        preserve(checkpoint / relative, prior)
preserve(checkpoint / 'manifest.json', (json.dumps({'nativeAfterSHA256': receipt['afterNativeSHA256'],
    'verificationSHA256': sha(receipt_bytes), 'mirrors': plan}, indent=2) + '\n').encode())
for row, relative, destination, value, prior in prepared:
    current = destination.read_bytes() if destination.exists() else None
    assert current == prior, f'Concurrent repository mirror edit: {relative}'
    if current != value:
        destination.parent.mkdir(parents=True, exist_ok=True)
        assert (destination.read_bytes() if destination.exists() else None) == prior
        with destination.open('wb' if prior is not None else 'xb') as handle:
            handle.write(value)
    assert destination.read_bytes() == value
result = {'schema': 'level3-finale-mirror-export-v1', 'exportedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'mirrors': plan, 'mirrorCount': 5, 'checkpoint': str(checkpoint),
          'verificationPath': str(receipt_path), 'verificationSHA256': sha(receipt_bytes),
          'nativePayloadSHA256': sha(payload_bytes), 'nativeAfterSHA256': receipt['afterNativeSHA256'],
          'studioWrites': False, 'gitWrites': False, 'publicationClaim': False}
preserve(export_receipt, (json.dumps(result, indent=2) + '\n').encode())
print(json.dumps({'exported': 5, 'changed': sum(row['changed'] for row in plan), 'receipt': str(export_receipt)}))
