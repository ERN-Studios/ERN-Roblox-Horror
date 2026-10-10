"""Upload the shadow face's flipbook sheets as group Image assets and keep their ids.

    python3 tools/level2_shade/upload_face.py            # every sheet that has no id yet, or whose bytes changed
    python3 tools/level2_shade/upload_face.py status     # moderation state of what is uploaded

Sheets: artifacts/level2-shade-face-20261010/sheets/ (tools/level2_shade/build_face.py), listed in face.json there.
Same route as the audio uploads: the request is sent from the owner's signed-in Creator Dashboard tab
(tools/promo/dashboard.py); a create.roblox.com tab has to be open in Chrome. Ids go to tools/level2_shade/face_ids.json.
"""
import hashlib
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'promo'))
import dashboard as d  # noqa: E402

d.TAB = 'create.roblox.com'
ASSETS = 'https://apis.roblox.com/assets/user-auth/v1'
GROUP = '1039373905'
PACK = ROOT / 'artifacts' / 'level2-shade-face-20261010'
IDS = HERE / 'face_ids.json'


def moderation(asset):
    status, text = d.call('GET', f'{ASSETS}/assets/{asset}?readMask=moderationResult')
    return json.loads(text).get('moderationResult', {}).get('moderationState', '?') if status == 200 else f'HTTP {status} {text[:120]}'


def upload(path, name):
    d.stage(path)
    request = {'assetType': 'Image', 'displayName': name, 'description': 'Backrooms: Stay Quiet, Level 2 shadow entity',
               'creationContext': {'creator': {'groupId': GROUP}}}
    status, text = d.call('POST', f'{ASSETS}/assets', form={'fileContent': [path.name]}, fields={'request': json.dumps(request)}, wait=180)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    if status != 200:
        raise RuntimeError(f'HTTP {status}: {text[:400]}')
    op = json.loads(text)['operationId']
    for _ in range(60):
        time.sleep(2)
        status, text = d.call('GET', f'{ASSETS}/operations/{op}')
        done = json.loads(text) if status == 200 else {}
        if done.get('done'):
            if done.get('error'):
                raise RuntimeError(json.dumps(done['error']))
            return int(done['response']['assetId'])
    raise RuntimeError('operation did not finish: ' + text[:300])


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    if sys.argv[1:] == ['status']:
        for name, row in sorted(ids.items()):
            row['moderation'] = moderation(row['asset_id'])
            print(f'{name:22s} {row["asset_id"]}  {row["moderation"]}')
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        return
    spec = json.loads((PACK / 'face.json').read_text())
    for name in spec['sheets']:
        path = PACK / 'sheets' / name
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(name, {}).get('sha256') == digest:
            continue
        asset = upload(path, f'BSQ L2 shade {Path(name).stem}')
        ids[name] = {'asset_id': asset, 'sha256': digest, 'moderation': 'uploaded'}
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        print(f'{name:22s} -> {asset}', flush=True)
    print(f'on file {len(ids)}')


if __name__ == '__main__':
    main()
