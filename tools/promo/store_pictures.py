"""The game's store pictures on Roblox: read what is live, and the calls that replaced them on 2026-10-07.

    python3 tools/promo/store_pictures.py status      # what players get right now (reads only)

Everything goes through the owner's own signed-in Creator Dashboard tab (`dashboard.py`): no password, no
cookie and no key is read or stored, and the mouse and keyboard are not touched. The tab has to be open:

    open -a "Google Chrome" "https://create.roblox.com/dashboard/creations/experiences/10559217407/places/131311258779917/thumbnails"

There are TWO sets of pictures and they live in different services.

EXPERIENCE DETAIL (the gallery on the game's page, at most 10)
  It is the place asset's `previews`: a list of {"asset": "assets/<image id>", "altText": ...} in display order.
  read     GET   apis.roblox.com/assets/user-auth/v1/assets/<place>?readMask=previews
  add      POST  publish.roblox.com/v1/games/<universe>/thumbnail/image     form field "request.files"
           (the new picture is put at the front of the list and goes to moderation; the answer's targetId is
           not the image id: find the id by reading the list again)
  set      PATCH apis.roblox.com/assets/user-auth/v1/assets/<place>?updateMask=previews
           form field "request" = {"assetId": <place>, "previews": [...]}: the whole list, so this one call
           removes, reorders and sets alt texts. It answers with an operation; the list passes through
           half-changed states for some seconds after the operation says done, so read until it matches.
  The older develop.roblox.com/v1/universes/<universe>/thumbnails/<id> DELETE answers 200 and removes nothing.

HOME PAGE (the tile on Roblox's Home, one shown unless personalization is on)
  service  apis.roblox.com/thumbnail-personalization-api/v1/universe/<universe>
  read     GET    /thumbnails?limit=50          and  /personalization?status=Active
  add      POST   /thumbnails/uploads           form field "files"; answers an operation id per file
           GET    /thumbnails/uploads/status?operationIds=...   gives homepageThumbnailId and moderation
  show     POST   /personalization/create       {"homepageThumbnailIds": [...]}, as application/json-patch+json
  remove   DELETE /thumbnails?homepageThumbnailIds=...

Order that never leaves the page empty: add new ones beside the old (10 at most), wait until the public list
says approved, set the list to the approved new ones, add the rest, set the final order. Moderation took
seconds that night. Keep a copy of what is live first (the public CDN serves 768 x 432).
"""
import json
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dashboard as d  # noqa: E402

UNIVERSE, PLACE = '10559217407', '131311258779917'
ASSETS = 'https://apis.roblox.com/assets/user-auth/v1'
HOME = f'https://apis.roblox.com/thumbnail-personalization-api/v1/universe/{UNIVERSE}'
RECORD = Path(__file__).resolve().parents[2] / 'artifacts' / 'promo-20261007' / 'store-upload.json'


def public_gallery():
    """What anybody gets, signed in or not."""
    return json.load(urllib.request.urlopen(f'https://games.roblox.com/v2/games/{UNIVERSE}/media'))['data']


def previews():
    status, text = d.call('GET', f'{ASSETS}/assets/{PLACE}?readMask=previews')
    assert status == 200, (status, text)
    return json.loads(text).get('previews', [])


def add_to_gallery(path):
    """Upload one picture to the gallery; returns its image id."""
    known = {p['asset'] for p in previews()}
    path = Path(path)
    d.stage(path)
    status, text = d.call('POST', f'https://publish.roblox.com/v1/games/{UNIVERSE}/thumbnail/image',
                          form={'request.files': [path.name]}, wait=120)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    assert status == 200, (status, text)
    for _ in range(15):
        time.sleep(2)
        new = {p['asset'] for p in previews()} - known
        if new:
            return int(new.pop().split('/')[1])
    raise RuntimeError('the new picture did not show up in the list')


def set_gallery(rows):
    """rows: [(image id, alt text)] in display order. Whatever is not in it leaves the page."""
    want = [{'asset': f'assets/{image}', 'altText': alt} for image, alt in rows]
    status, text = d.call('PATCH', f'{ASSETS}/assets/{PLACE}?updateMask=previews',
                          fields={'request': json.dumps({'assetId': int(PLACE), 'previews': want})})
    assert status == 200, (status, text)
    for _ in range(40):
        time.sleep(3)
        if previews() == want:
            return True
    return False


def home_thumbnails():
    status, text = d.call('GET', HOME + '/thumbnails?limit=50')
    assert status == 200, (status, text)
    return json.loads(text)['homepageThumbnails']


def add_to_home(path):
    """Upload one picture to the Home Page set; returns {homepageThumbnailId, assetId, moderationStatus}."""
    path = Path(path)
    d.stage(path)
    status, text = d.call('POST', HOME + '/thumbnails/uploads', form={'files': [path.name]}, wait=120)
    d.js(f'(delete window.__files[{json.dumps(path.name)}], "freed")')
    assert status == 200, (status, text)
    operation = list(json.loads(text)['fileToOperationIdDict'].values())[0]
    for _ in range(30):
        time.sleep(2)
        status, text = d.call('GET', HOME + '/thumbnails/uploads/status?operationIds=' + operation)
        rows = json.loads(text).get('uploadThumbnailStatusDict', {}) if status == 200 else {}
        if rows:
            return list(rows.values())[0]
    raise RuntimeError('no status for the upload')


def show_on_home(thumbnail_ids):
    """Which Home Page thumbnails are shown. One id = that picture; several = Roblox tests them."""
    return d.call('POST', HOME + '/personalization/create', body={'homepageThumbnailIds': list(thumbnail_ids)},
                  kind='application/json-patch+json')


def remove_from_home(thumbnail_ids):
    return d.call('DELETE', HOME + '/thumbnails?' + '&'.join('homepageThumbnailIds=' + i for i in thumbnail_ids))


def status():
    record = json.loads(RECORD.read_text()) if RECORD.exists() else {}
    name = {v: k for k, v in record.get('detail', {}).items()}
    print('EXPERIENCE DETAIL, public:')
    for n, m in enumerate(public_gallery(), 1):
        print(f"  {n:2d} {name.get(m['imageId'], m['imageId'])!s:30s} {'approved' if m['approved'] else 'in moderation'}  {(m.get('altText') or '')[:50]}")
    home = {v['assetId']: k for k, v in record.get('home', {}).items()}
    print('HOME PAGE (through the dashboard tab):')
    for t in home_thumbnails():
        print(f"  {home.get(t['assetId'], t['assetId'])!s:30s} {t['moderationStatus']:10s} {'SHOWN' if t['personalizedConfigStatus'] == 'Active' else 'not shown'}")


if __name__ == '__main__':
    if sys.argv[1:] == ['status']:
        status()
    else:
        print(__doc__)
