"""Verify one fresh native capture in place; no Studio connection or duplicate backup tree."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess

TASK = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--phase', required=True, choices=['before', 'after'])
parser.add_argument('--dest', required=True, type=Path, help='Same backup root passed to receiver.py')
parser.add_argument('--artifacts', required=True, type=Path)
parser.add_argument('--lune', required=True, type=Path)
parser.add_argument('--native-place', type=Path, help='Optional actual Studio Save-to-File backup')
args = parser.parse_args()
directory = args.dest.resolve() / args.phase
artifact_directory = args.artifacts.resolve() / args.phase


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read(path):
    return json.loads(path.read_text())


def immutable(path, data):
    if path.exists():
        assert path.read_bytes() == data, 'Different existing backup bytes: ' + str(path)
    else:
        path.write_bytes(data)


def record(path, value):
    immutable(path, (json.dumps(value, indent=2, ensure_ascii=False) + '\n').encode())


metadata = read(directory / 'metadata.received.json')
assert metadata['task'] == 'level3-promotion-20261002' and metadata['phase'] == args.phase
assert (metadata['placeId'], metadata['universeId'], metadata['groupId']) == (131311258779917, 10559217407, 1039373905)
assert not metadata['editorConflicts'] and not metadata['skipped']
assert metadata['captureFinishedUnixMillis'] >= metadata['captureStartUnixMillis']
transfer = read(directory / 'source-transfer-receipt.json')
assert transfer == metadata['sourceTransfer']
sources_raw = (directory / 'scripts.json').read_bytes()
assert len(sources_raw) == transfer['bytes'] and digest(sources_raw) == transfer['sha256']
sources = json.loads(sources_raw)
assert len(sources) == metadata['scriptCount']
for source in sources:
    raw = source['source'].encode()
    assert source['editorMatch'] is True and len(raw) == source['sourceBytes']
    assert digest(raw) == source['sourceSha256'] == source['editorSourceSha256']

parts = sorted(directory.glob('native-part-*.bin'))
assert [path.name for path in parts] == [f'native-part-{index:05d}.bin' for index in range(metadata['nativeParts'])]
native = b''.join(path.read_bytes() for path in parts)
assert len(native) == metadata['nativeBytes'] and digest(native) == metadata['nativeSHA256']
assert len(metadata['roots']) == metadata['rootCount']
assert sum(root['descendants'] + 1 for root in metadata['roots']) == metadata['expectedDescendants']
immutable(directory / 'all-service-children.rbxm', native)
record(directory / 'metadata.json', metadata)

if args.native_place:
    place = args.native_place.resolve()
    assert place.is_file(), 'Studio native place file does not exist'
    place_method = 'Studio Save-to-File supplied by operator; native forest rechecked against capture'
else:
    subprocess.run([str(args.lune), 'run', str(TASK / 'pack_native_backup.luau'), str(directory)], check=True)
    place = directory / 'AuthoritativeStudio-CapturedForest.rbxl'
    place_method = 'Offline reconstruction from native forest and captured service metadata'

verification_path = directory / 'native-recovery-reopen-verification.json'
subprocess.run([str(args.lune), 'run', str(TASK / 'verify_native_recovery.luau'), str(directory), str(place), str(verification_path)], check=True)
verification = read(verification_path)
assert verification['verified'] and verification['captureId'] == metadata['captureId']
assert verification['nativeSHA256'] == metadata['nativeSHA256']
assert verification['nativePlaceSHA256'] == digest(place.read_bytes())
assert verification['rootErrors'] == verification['sourceErrors'] == verification['sourceEditorConflicts'] == 0
assert verification['sourceCount'] == metadata['scriptCount'] and verification['rootCount'] == metadata['rootCount']

reconstruction = read(directory / 'native-place-verification.json') if not args.native_place else None
summary = {key: metadata[key] for key in ['task', 'phase', 'captureId', 'capturedAt', 'placeId', 'universeId', 'groupId', 'placeVersion', 'rootCount', 'scriptCount', 'nativeSHA256', 'nativeBytes', 'captureStartUnixMillis', 'captureFinishedUnixMillis']}
summary.update({
    'nativeRecoveryVerified': True,
    'nativePlacePath': str(place),
    'nativePlaceMethod': place_method,
    'nativePlaceSHA256': verification['nativePlaceSHA256'],
    'nativePlaceBytes': place.stat().st_size,
    'sourceCatalogSHA256': digest(sources_raw),
    'sourceEditorConflicts': 0,
    'canonicalNativeForestSHA256': verification['canonicalNativeForestSHA256'],
    'canonicalReopenedForestSHA256': verification['canonicalReopenedForestSHA256'],
    'backupDirectory': str(directory),
    'serviceReconstructionPropertyErrors': len(reconstruction['propertyErrors']) if reconstruction else None,
    'unreadableServicePropertyLimits': sum(len(service['propertyErrors']) for service in metadata['services']),
    'limits': verification['limits'],
    'studioWritesPerformed': False,
    'publicationClaim': False,
    'verifiedAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
})
artifact_directory.mkdir(parents=True, exist_ok=True)
record(artifact_directory / 'backup-summary.json', summary)
immutable(artifact_directory / 'source-inventory.json', (directory / 'source-inventory.json').read_bytes())
print(json.dumps({key: summary[key] for key in ['phase', 'captureId', 'nativeRecoveryVerified', 'nativePlaceSHA256', 'sourceEditorConflicts', 'serviceReconstructionPropertyErrors', 'unreadableServicePropertyLimits', 'backupDirectory']}))
