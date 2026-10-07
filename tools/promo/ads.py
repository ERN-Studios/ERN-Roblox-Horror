"""Roblox Ads Manager from a session: the asset library and campaigns of the group's ad account.

    python3 tools/promo/ads.py status        # balance, library, campaigns (reads only)

Like `store_pictures.py` it talks through the owner's own signed-in tab (`dashboard.py`), here a tab on
`create.roblox.com/advertise`. Nothing is typed or clicked and no credential is read. The Ads Manager does not
draw its pages while its tab is in the background, so everything here is the requests its own buttons send;
the addresses and field names were read out of its public script files.

service  https://apis.roblox.com/ads-management-api
  GET   /v1/adCreditBalance?groupId=            the group's ad credit, in micro (1 credit = 1 000 000)
  GET   /v1/advertiser?groupId=                 the ad account
  GET   /v1/metadata                            limits (minimum daily budget and so on)
  GET   /v1/adCreatives?groupId=&page_size=&is_archived=     the asset library
  POST  /v1/adCreatives?groupId=                {"ad_creatives": [{asset_id, asset_type, source, universe_id, width, height}]}
  DELETE /v1/adCreatives/<id>?groupId=          archives it (the library's "archive"; a PATCH to true is refused)
  PATCH /v1/adCreatives/<id>?groupId=           {"is_archived": false, "update_mask": ["is_archived"]} brings it back
  POST  /v3/native/campaigns?groupId=           {"campaign": {...}, "idempotency_key": "..."}   CREATES AND SUBMITS
  POST  /v3/native/campaigns/status?groupId=    {"campaign_ids": [...]}: display_status (1 paused, 2 scheduled, 6 in review,
                                                9 active, 14 learning, 5 completed, 7 cancelled) and is_on
  PATCH /v3/native/campaigns/<id>               {"campaign": {"status": 3}} switches it off, 2 on again, 5 cancels
                                                (a cancel within 6 hours of the start is refused)
  GET   /v3/native/campaigns/<id>?groupId=      one campaign as it stands (status 2 = enabled, 3 stopped, 5 cancelled,
                                                6 paused for lack of credit)
  POST  /v2/native/ads/dateFilter?request_timestamp=&time_period=&reporting_view=   {"campaign_ids": [...]}: results
                                                per picture (the query's enum values were not worked out on 2026-10-08)

An ad picture is first an ordinary group-owned image asset (the same upload the Icon page does), then it is
registered in the library with its size. Sponsored tiles are 16:9; a campaign shows its pictures (ten at most)
to players in even shares, so a weak picture costs as much as a strong one.

An existing campaign's budget TYPE cannot be changed (the edit form does not even send it): for another type,
switch the old one off and create a new one.

Campaign numbers: objective 2 = Plays; budget_type 1 = daily, 2 = lifetime; payment_type 4 = the group's ad
credit (2 = a user's own, 1 = card); detailed_targeting_match_type 0 = all players, 3 = new, 2 = recent,
1 = lapsed. Targeting: ages 5 = all (sent as all_ages), 1 = 13-17, 2 = 18-24, 3 = 25+, 4 = 5-12; devices 1 =
all, 2 computer, 3 phone, 4 tablet, 5 console; gender 1 = any; genres [1] = all; regions [1] = everywhere.
"""
import json
import struct
import sys
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dashboard as d  # noqa: E402

API = 'https://apis.roblox.com/ads-management-api'
ASSETS = 'https://apis.roblox.com/assets/user-auth/v1'
GROUP, UNIVERSE = '1039373905', 10559217407
RECORD = Path(__file__).resolve().parents[2] / 'artifacts' / 'promo-20261007' / 'ads-campaign.json'


def tab():
    d.TAB = 'create.roblox.com/advertise'


def get(path):
    tab()
    status, text = d.call('GET', API + path)
    assert status == 200, (status, path, text[:300])
    return json.loads(text)


def balance():
    return get(f'/v1/adCreditBalance?groupId={GROUP}')['ad_credit_balance_in_micro'] / 1e6


def library(archived=False):
    """Every creative in the asset library (archived ones only when asked)."""
    rows, cursor = [], ''
    while True:
        page = get(f'/v1/adCreatives?groupId={GROUP}&page_size=50&is_archived={"true" if archived else "false"}' + (f'&cursor={cursor}' if cursor else ''))
        got = page.get('ad_creatives') or []
        rows += got
        cursor = page.get('next_cursor') or page.get('cursor') or ''
        if not got or not cursor or len(rows) > 500:
            return rows


def archive(creative_id, archived=True):
    """Archive = the library's DELETE (nothing is really deleted: it moves to the archived list); bring one back
    with archived=False. A PATCH with is_archived true is refused (400)."""
    tab()
    if archived:
        return d.call('DELETE', f'{API}/v1/adCreatives/{creative_id}?groupId={GROUP}')
    return d.call('PATCH', f'{API}/v1/adCreatives/{creative_id}?groupId={GROUP}',
                  body={'is_archived': False, 'update_mask': ['is_archived']})


def png_size(path):
    with open(path, 'rb') as f:
        head = f.read(24)
    assert head[:8] == b'\x89PNG\r\n\x1a\n', path
    return struct.unpack('>II', head[16:24])


def upload(path, name=None):
    """One picture into the asset library: image asset first, then its registration. Returns the asset id."""
    tab()
    path = Path(path)
    name = (name or path.stem)[:50]
    width, height = png_size(path)
    d.stage(path)
    request = {'assetType': 'Image', 'displayName': name, 'creationContext': {'creator': {'groupId': GROUP}}}
    status, text = d.call('POST', f'{ASSETS}/assets', form={'fileContent': [path.name]},
                          fields={'request': json.dumps(request), 'additionalParameters': json.dumps({'AssetPrivacy': 'OpenUse'})}, wait=150)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    assert status == 200, (status, text[:300])
    op = json.loads(text)['operationId']
    asset = None
    for _ in range(40):
        time.sleep(1.5)
        status, text = d.call('GET', f'{ASSETS}/operations/{op}')
        done = json.loads(text) if status == 200 else {}
        if done.get('done'):
            assert not done.get('error'), done
            asset = int(done['response']['assetId'])
            break
    assert asset, 'the upload did not finish'
    body = {'ad_creatives': [{'asset_id': asset, 'asset_type': 'AD_ASSET_TYPE_IMAGE', 'source': 'AD_CREATIVE_ASSET_SOURCE_UPLOAD',
                              'universe_id': UNIVERSE, 'width': width, 'height': height}]}
    status, text = d.call('POST', f'{API}/v1/adCreatives?groupId={GROUP}', body=body)
    assert status == 200, (status, text[:300])
    return asset


BROAD = {'age_bucket_criteria': {'all_ages': True}, 'device_criteria': {'devices': [1]}, 'gender_criteria': {'gender': 1},
         'genre_criteria': {'genres': [1]}, 'language_criteria': {'languages': [1]},
         'location_criteria': {'countries': [], 'regions': [1]}}


def campaign(name, asset_ids, budget, days, start_ms, targeting=None, lifetime=True):
    """The campaign as the create form sends it: Plays, auto-bid, paid from the group's ad credit, no auto-reload."""
    return {'asset_ids': list(asset_ids), 'budget_in_micro_usd': int(round(budget * 1e6)), 'budget_type': 2 if lifetime else 1,
            'detailed_targeting_match_type': 0, 'duration_in_days': days, 'is_auto_reload_ad_credit_enabled': False,
            'is_off_platform_request': False, 'name': name, 'objective': 2, 'payment_type': 4,
            'start_timestamp_ms': int(start_ms), 'target_universe_id': UNIVERSE, 'targeting_criteria': targeting or BROAD}


def submit(body, key=None):
    """CREATES AND SUBMITS the campaign: it goes to review and then spends ad credit as it delivers."""
    tab()
    key = key or str(uuid.uuid4())
    return d.call('POST', f'{API}/v3/native/campaigns?groupId={GROUP}', body={'campaign': body, 'idempotency_key': key}, wait=120) + (key,)


def states(campaign_ids):
    tab()
    status, text = d.call('POST', f'{API}/v3/native/campaigns/status?groupId={GROUP}', body={'campaign_ids': list(campaign_ids)})
    assert status == 200, (status, text[:300])
    return json.loads(text)


def switch(campaign_id, on):
    """On (2) or off (3). Off stops delivery at once; nothing is charged while it is off."""
    tab()
    return d.call('PATCH', f'{API}/v3/native/campaigns/{campaign_id}', body={'campaign': {'status': 2 if on else 3}})


def read_campaign(campaign_id):
    return get(f'/v3/native/campaigns/{campaign_id}?groupId={GROUP}')


def status():
    print('ad credit:', balance())
    rows = library()
    print(len(rows), 'pictures in the asset library (not archived):')
    for r in rows:
        print(f"  {r['asset_id']}  {str(r.get('asset_name'))[:40]:40s} {r.get('width')}x{r.get('height')}  {r.get('content_moderation_status')}")
    print(len(library(archived=True)), 'archived')
    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    names = {1: 'paused', 2: 'scheduled', 5: 'completed', 6: 'in review', 7: 'cancelled', 9: 'active', 14: 'learning'}
    for key in ('campaign', 'campaign_previous'):
        answer = record.get(key, {}).get('answer')
        if not answer:
            continue
        cid = json.loads(answer)['campaign_id']
        c = read_campaign(cid)
        c = c.get('campaign', c)
        st = states([cid])[0]
        print(f"{key}: {c.get('name')} | {names.get(st.get('display_status'), st.get('display_status'))}, {'ON' if st.get('is_on') else 'off'}",
              '|', 'daily' if c.get('budget_type') == 1 else 'lifetime', c.get('budget_in_micro_usd', 0) / 1e6, '| days', c.get('duration_in_days'),
              '| pictures', len(c.get('asset_ids') or []), '| results', json.dumps(c.get('performance'))[:300])

if __name__ == '__main__':
    if sys.argv[1:] == ['status']:
        status()
    else:
        print(__doc__)
