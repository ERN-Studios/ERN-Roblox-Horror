"""Build a portable import bundle from the explicitly listed verified finals."""
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / 'assets/models/aero-house'
EVIDENCE = ROOT / 'artifacts/aero-import-20260929'
FILES = [
    'AeroHouse.blend', 'AeroHouse.glb', 'AeroHouse.fbx', 'README.md',
    'SetupAeroHouse.luau', 'manifest.json', 'verification.json',
    'textures/Aero_Color.png', 'textures/Aero_Roughness.png', 'textures/Aero_Metallic.png',
    'previews/studio-exterior.jpg', 'previews/studio-lounge.jpg',
]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    manifest = json.loads((ASSET/'manifest.json').read_text())
    verified = json.loads((ASSET/'verification.json').read_text())
    assert verified['overall_offline_pass']
    assert digest(ASSET/'AeroHouse.blend') == verified['source_sha256']
    assert digest(ASSET/'AeroHouse.glb') == verified['glb_roundtrip']['sha256']
    template = (ROOT/'tools/aero_house_setup_template.luau').read_text()
    setup = template.replace('__HOUSE_MANIFEST_JSON__', json.dumps(manifest, separators=(',', ':')))
    if (ASSET/'SetupAeroHouse.luau').read_text() != setup:
        raise RuntimeError('Regenerate and compile-check the packaged setup before bundling.')
    walk = json.loads((EVIDENCE/'walk-result.json').read_text())
    return_walk = json.loads((EVIDENCE/'return-walk-result.json').read_text())
    performance = json.loads((EVIDENCE/'client-performance.json').read_text())
    assert walk['passed'] and walk['placeId'] == 121672571539226
    assert return_walk['passed']
    assert performance['result']['passed']
    for name in FILES:
        assert (ASSET/name).is_file(), name
    archive = ASSET.parent/'AeroHouse_Roblox_Import.zip'
    # Stage and validate a complete archive before replacing the deliverable.
    # macOS permits native cp here where Python cannot reopen the existing file.
    with tempfile.TemporaryDirectory(prefix='aero-house-package-') as staging:
        staged_archive = Path(staging)/archive.name
        with ZipFile(staged_archive, 'w', ZIP_DEFLATED, compresslevel=6) as bundle:
            for name in FILES:
                bundle.write(ASSET/name, 'AeroHouse/'+name)
        with ZipFile(staged_archive) as bundle:
            assert bundle.testzip() is None
            assert len(bundle.namelist()) == len(FILES)
        subprocess.run(['cp', str(staged_archive), str(archive)], check=True)
    with ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert len(bundle.namelist()) == len(FILES)
    record = {
        'asset': 'Aero House', 'date': '2026-09-29',
        'files': [{'path': name, 'bytes': (ASSET/name).stat().st_size, 'sha256': digest(ASSET/name)} for name in FILES],
        'archive': {'path': str(archive.relative_to(ROOT)), 'bytes': archive.stat().st_size, 'sha256': digest(archive)},
        'setup_luau_compile': {'passed': True, 'executed': True, 'studio_place_id': 121672571539226},
        'studio_import': {
            'succeeded': True, 'place_id': 121672571539226,
            'universe_id': 10768500985, 'visual_meshes': manifest['meshCount'],
            'colliders': len(manifest['colliders']), 'lights': len(manifest['lights']),
            'verified_state_record': 'artifacts/aero-import-20260929/verified-studio-manifest.json',
            'cathedral_archive': 'ServerStorage.AeroReplacementArchive.Vesper Cathedral',
            'before_place_backup': 'artifacts/aero-import-20260929/BeforeAeroReplacement.rbxl',
        },
        'walkthrough': {
            'forward_passed': walk['passed'], 'forward_points': walk['waypoints'],
            'forward_seconds': walk['seconds'], 'reverse_passed': return_walk['passed'],
            'reverse_legs': return_walk['completedLegs'],
            'evidence': ['artifacts/aero-import-20260929/walk-result.json',
                         'artifacts/aero-import-20260929/return-walk-result.json'],
        },
        'runtime_performance': {
            'local_client_sample_completed': performance['result']['passed'],
            'evidence': 'artifacts/aero-import-20260929/client-performance.json',
            'scope': 'One local Studio client sample; whole-process memory, no house-only baseline.',
            'mobile_verified': False, 'multiplayer_verified': False,
        },
        'publication': 'Not claimed by this package record.',
    }
    destination = EVIDENCE/'package-record.json'
    destination.write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps({'archive': str(archive), 'files': len(FILES), 'bytes': archive.stat().st_size}))

if __name__ == '__main__':
    main()
