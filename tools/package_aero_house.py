"""Build a portable import bundle from the explicitly listed verified finals."""
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / 'assets/models/aero-house'
FILES = [
    'AeroHouse.blend', 'AeroHouse.glb', 'AeroHouse.fbx', 'README.md',
    'SetupAeroHouse.luau', 'manifest.json', 'verification.json',
    'textures/Aero_Color.png', 'textures/Aero_Roughness.png', 'textures/Aero_Metallic.png',
    'previews/exterior.png', 'previews/lounge.png',
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
    for name in FILES:
        assert (ASSET/name).is_file(), name
    archive = ASSET.parent/'AeroHouse_Roblox_Import.zip'
    with ZipFile(archive, 'w', ZIP_DEFLATED, compresslevel=6) as bundle:
        for name in FILES:
            bundle.write(ASSET/name, 'AeroHouse/'+name)
    with ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert len(bundle.namelist()) == len(FILES)
    record = {
        'asset': 'Aero House', 'date': '2026-09-29',
        'files': [{'path': name, 'bytes': (ASSET/name).stat().st_size, 'sha256': digest(ASSET/name)} for name in FILES],
        'archive': {'path': str(archive.relative_to(ROOT)), 'bytes': archive.stat().st_size, 'sha256': digest(archive)},
        'setup_luau_compile': {'passed': True, 'executed': False, 'studio_place_id': 121672571539226},
        'studio_import': 'not performed', 'runtime_performance': 'not tested',
        'repository_remote_read': 'ERN-Studios/ERN-Roblox-Horror',
        'remote_head_before_task': 'b60701178804689954f83c564fe759ce2d4cc19c',
    }
    destination = ROOT/'artifacts/aero-house-20260929/package-record.json'
    destination.write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps({'archive': str(archive), 'files': len(FILES), 'bytes': archive.stat().st_size}))

if __name__ == '__main__':
    main()
