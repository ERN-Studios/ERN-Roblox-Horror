"""Upload the new Poolrooms masters to the group as Audio assets, from the session, and keep their ids.

    python3 tools/poolrooms_audio_20261010/upload.py            # every master that passed QC and has no id yet
    python3 tools/poolrooms_audio_20261010/upload.py status     # moderation state of what is uploaded

Same route as tools/lobby_reach/upload_sounds.py: the request is sent FROM the owner's signed-in Creator Dashboard tab
(tools/promo/dashboard.py), no mouse and no keyboard. A create.roblox.com tab has to be open in Chrome. Audio uploads are
free and counted against the account's monthly allowance (24 of 2000 used on 2026-10-10).

Ids go to assets/poolrooms-audio-20261010/sound_ids.json as {key: {asset_id, master_sha256, moderation}} and a master is
only uploaded again when its bytes changed.
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
PACK = ROOT / 'assets' / 'poolrooms-audio-20261010'
IDS = PACK / 'sound_ids.json'


def operation(op, tries=90, pause=2.0):
    text = ''
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
    d.stage(path)
    request = {'assetType': 'Audio', 'displayName': name, 'description': 'Backrooms: Stay Quiet, Level 2 Poolrooms ambience',
               'creationContext': {'creator': {'groupId': GROUP}}}
    status, text = d.call('POST', f'{ASSETS}/assets', form={'fileContent': [path.name]}, fields={'request': json.dumps(request)}, wait=180)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    if status != 200:
        raise RuntimeError(f'HTTP {status}: {text[:400]}')
    return int(operation(json.loads(text)['operationId'])['assetId'])


def main():
    ids = json.loads(IDS.read_text()) if IDS.exists() else {}
    if sys.argv[1:] == ['status']:
        waiting = 0
        for key, row in sorted(ids.items()):
            row['moderation'] = moderation(row['asset_id'])
            waiting += row['moderation'] != 'Approved'
            print(f'{key:24s} {row["asset_id"]}  {row["moderation"]}')
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        print(f'{len(ids) - waiting} of {len(ids)} approved')
        return
    qc = json.loads((PACK / 'qc.json').read_text())['sounds']
    done = failed = 0
    for key in sorted(qc):
        if qc[key].get('numeric_pass') is not True:
            continue
        path = PACK / 'masters' / f'{key}.ogg'
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if ids.get(key, {}).get('master_sha256') == digest:
            continue
        try:
            asset = upload(path, f'BSQ L2 {key}')
        except Exception as error:   # one refused file must not stop the other sixty
            failed += 1
            print(f'{key:24s} FAILED {str(error)[:200]}', flush=True)
            continue
        ids[key] = {'asset_id': asset, 'master_sha256': digest, 'moderation': 'uploaded'}
        IDS.write_text(json.dumps(ids, indent=1, sort_keys=True) + '\n')
        done += 1
        print(f'{key:24s} -> {asset}', flush=True)
    print(f'uploaded {done}, failed {failed}, on file {len(ids)}')


if __name__ == '__main__':
    main()
