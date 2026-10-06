"""Find the uploaded PBR pictures in the group's inventory by name and write pbr_ids.json.

    python3 tools/level6_playground/pbr/collect_ids.py --folder      # (re)make the Desktop folder to import from
    python3 tools/level6_playground/pbr/collect_ids.py               # after the import: names -> asset ids

The pictures have to be owned by the GROUP that owns the experience, or the live game may not load them:
- AssetService:CreateAssetAsync would do it from the session, but it answered "not available yet" (it is a Studio
  Beta Feature that is switched off on this Mac: File > Beta Features > CreateAssetAsync).
- The MCP upload_image tool uploads to the logged-in USER; the experience then needs "Share access" clicked for
  every single picture (Output window), and until then even a Studio play session refuses them.
- Asset Manager > Import takes all of them at once and gives them to the group. That is the way used here.

So: the pictures are copied to ~/Desktop/Level 6 PBR - import these/ under names that say which round of the
textures they are (L6PBR_r<ROUND>_<set>_<map>.png), the owner imports that folder's files in Studio's Asset
Manager, and this script looks each name up (MCP search_asset, group scope) and records the id. Raise ROUND when
a picture is changed and has to be imported again: an old round's names never match.
"""
import json
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(HERE.parent))

MAPS = ROOT / 'assets' / 'level6-pbr-20261006'
SETS = json.loads((MAPS / 'sets.json').read_text())
IDS = HERE / 'pbr_ids.json'
ROUND = 1
GROUP = '1039373905'                                     # ERN Roblox Studios
DESKTOP = Path.home() / 'Desktop' / 'Level 6 PBR - import these'


def wanted():
    """(key in pbr_ids.json, map or None, file in assets/, name once imported)"""
    rows = [(key, kind, MAPS / f'{key}_{kind}.png', f'L6PBR_r{ROUND}_{key}_{kind}') for key in SETS for kind in ('color', 'normal', 'roughness')]
    rows.append(('net_knotted', None, MAPS / 'net_knotted.png', f'L6PBR_r{ROUND}_net_knotted'))
    return rows


def folder():
    if DESKTOP.exists():
        for old in DESKTOP.glob('L6PBR_*.png'):
            old.unlink()
    DESKTOP.mkdir(parents=True, exist_ok=True)
    for _, _, source, name in wanted():
        shutil.copyfile(source, DESKTOP / f'{name}.png')
    (DESKTOP / 'READ ME.txt').write_text(
        'Level 6 PBR textures (round %d): %d pictures.\n\n'
        'In Roblox Studio, with the game open:\n'
        '  1. View > Asset Manager\n'
        '  2. Import (the arrow-up button at the top of the Asset Manager)\n'
        '  3. Select ALL the .png files in this folder (click one, Cmd+A) and press Open\n'
        '  4. Start Import / Confirm, and wait until every row says it is done\n\n'
        'That is all. Tell Claude when it is done; the rest (finding the ids, building the materials,\n'
        'dressing the level, testing it) happens from the session. Nothing changes in the game until then.\n'
        % (ROUND, len(wanted())))
    print(f'{len(wanted())} pictures in {DESKTOP}')


def collect():
    from import_to_studio import Studio
    studio = Studio()
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    missing = []
    for key, kind, _, name in wanted():
        found = {}
        for query in (name, name.rsplit('_', 1)[0], f'L6PBR_r{ROUND}'):
            text = studio.call('search_asset', {'studio_id': studio.studio_id, 'query': query, 'scope': 'group', 'groupId': GROUP,
                                                'assetType': 'Image', 'maxResults': 20})
            for row in json.loads(text).get('results', []):
                stem = row['name'][:-4] if row['name'].lower().endswith('.png') else row['name']
                if stem == name:
                    found[row['assetId']] = row['name']
            if found:
                break
        if len(found) != 1:
            missing.append(f'{name}: {"not found" if not found else "found more than once: " + ", ".join(found)}')
            continue
        asset = int(next(iter(found)))
        if kind:
            ids.setdefault(key, {})[kind] = asset
        else:
            ids[key] = asset
        print(f'{name:40s} {asset}', flush=True)
    IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
    if missing:
        raise SystemExit('still to import:\n  ' + '\n  '.join(missing))
    print('pbr_ids.json is complete; next: apply_pbr.py --check (in a play session), then --play, then the apply')


if __name__ == '__main__':
    folder() if '--folder' in sys.argv else collect()
