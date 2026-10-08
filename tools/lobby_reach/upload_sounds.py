"""Upload the creature's cleaned sounds to the group as Audio assets, from the session, and keep their ids.

    python3 tools/lobby_reach/upload_sounds.py            # every file in levels.json that has no id yet
    python3 tools/lobby_reach/upload_sounds.py status     # moderation state of what is uploaded

No mouse, no keyboard: the request is sent FROM the owner's signed-in Creator Dashboard tab (tools/promo/
dashboard.py), the way the dashboard's own audio upload does it: POST apis.roblox.com/assets/user-auth/v1/assets
with the form fields `request` ({"assetType": "Audio", "displayName", "description", "creationContext": {"creator":
{"groupId"}}}) and `fileContent`, then the operation is polled for the asset id. A Creator Dashboard tab has to be
open in Chrome (`open -g -a "Google Chrome" https://create.roblox.com/dashboard/creations` opens one in the
background). Audio uploads are free but counted against the account's monthly allowance.
Ids go to tools/lobby_reach/sound_ids.json with the hash of the file they were made from.
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
SOUNDS = ROOT / 'assets' / 'lobby-reach-20261008'
IDS = HERE / 'sound_ids.json'


def operation(op, tries=60, pause=2.0):
    for _ in range(tries):
        time.sleep(pause)
        status, text = d.call('GET', f'{ASSETS}/operations/{op}')
        done = json.loads(text) if status == 200 else {}
        if done.get('done'):
            if done.get('error'):
                raise RuntimeError(json.dumps(done['error']))
            return done.get('response', {})
    raise RuntimeError('operation did not finish: ' + text[:300])


def moderation(asset):
    status, text = d.call('GET', f'{ASSETS}/assets/{asset}?readMask=moderationResult')
    return json.loads(text).get('moderationResult', {}).get('moderationState', '?') if status == 200 else f'HTTP {status} {text[:120]}'


def upload(path, name):
    print(' ', d.stage(path))
    request = {'assetType': 'Audio', 'displayName': name, 'description': 'Backrooms: Stay Quiet, the creature behind the lobby fence',
               'creationContext': {'creator': {'groupId': GROUP}}}
    status, text = d.call('POST', f'{ASSETS}/assets', form={'fileContent': [path.name]}, fields={'request': json.dumps(request)}, wait=180)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    if status != 200:
        raise RuntimeError(f'HTTP {status}: {text[:400]}')
    return int(operation(json.loads(text)['operationId'])['assetId'])


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    hashes = ids.setdefault('_sha256', {})
    if sys.argv[1:] == ['status']:
        for key, asset in sorted(ids.items()):
            if not key.startswith('_'):
                print(f'{key:22s} {asset}  {moderation(asset)}')
        return
    levels = json.loads((SOUNDS / 'levels.json').read_text())
    for key, row in levels.items():
        path = SOUNDS / row['file']
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(key) and hashes.get(key) == digest:
            print(f'{key:22s} already {ids[key]}')
            continue
        asset = upload(path, f'BSQ lobby {key}')
        ids[key], hashes[key] = asset, digest
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        print(f'{key:22s} -> {asset}')


if __name__ == '__main__':
    main()
