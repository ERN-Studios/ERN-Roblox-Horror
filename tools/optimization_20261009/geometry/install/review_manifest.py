"""Review the exact native export before the root-owned geometry apply phase."""
import collections
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
receipt = json.loads((HERE / 'runner-receipt.json').read_text())
rows, identities = [], set()
expected = 1
for entry in receipt['manifest']['pages']:
    raw = (ROOT / entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
    page = json.loads(raw)
    assert page['startIndex'] == expected
    assert page['total'] == receipt['manifest']['totalRows']
    assert len(page['rows']) == entry['rows']
    rows.extend(page['rows'])
    expected += len(page['rows'])
kinds, classes = collections.Counter(), collections.Counter()
archived = reduction = lod = 0
for row in rows:
    kinds[row['kind']] += 1
    baselines = row['before'] if isinstance(row['before'], list) else [row['before']]
    for baseline in baselines:
        assert baseline['id'] not in identities, 'Overlapping mutation ownership'
        identities.add(baseline['id'])
        classes[baseline['className']] += 1
        assert json.loads(baseline['fingerprint']) == baseline['values']
    if row['kind'] == 'renderFidelity':
        assert row['before']['className'] == 'UnionOperation'
        assert row['after'] == 'Enum.RenderFidelity.Automatic'
        props = dict(row['before']['values'][4])
        assert props['RenderFidelity'] == ['EnumItem', 'Enum.RenderFidelity.Precise']
        assert props['CollisionFidelity'] == ['EnumItem', 'Enum.CollisionFidelity.Hull']
        assert props['Anchored'] == ['boolean', True]
        assert any('.' + folder + '.' in row['before']['path'] for folder in ('Frame_DeckPads','Frame_Decks','Frame_DecksDeep'))
        lod += 1
    elif row['kind'] == 'exactColliderMerge':
        proxy = row['proxyExpectedValues']
        assert json.loads(row['proxyExpectedFingerprint']) == proxy
        assert len(baselines) >= 2
        for baseline in baselines:
            values = baseline['values']
            assert baseline['className'] == 'Part'
            assert baseline['path'] == 'ServerStorage.Level2PoolroomsMap.Collision.Part'
            assert values[:2] == proxy[:2] and values[4:] == proxy[4:], 'Proxy changes non-geometric semantics'
            assert values[2][3:] == proxy[2][3:], 'Proxy rotates an original'
            assert values[-1] == 0
        archived += len(baselines)
        reduction += len(baselines) - 1
    else:
        raise AssertionError('Unreviewed geometry action')
assert len(rows) == 6729 and lod == 6605 and archived == 267 and reduction == 143
probe = receipt['nativeProbe']
assert probe['groups'] == 124 and probe['rays'] == 6696 and probe['overlaps'] == 1860
assert probe['maxHitPositionDifference'] == probe['maxHitDistanceDifference'] == 0
assert probe['authoritativeOriginalsUnchanged'] and probe['testObjectsCleaned']
review = {'reviewed':True,'exactManifestRows':len(rows),'uniqueBaselineIdentities':len(identities),
          'kinds':dict(kinds),'classes':dict(classes),'archivedOriginals':archived,'newProxies':124,
          'netColliderReduction':reduction,'lodOnlyChanges':lod,'originalsDeleted':False,
          'nativeOccupancyQueryEvidence':probe,'gameplayVerified':False,'performanceVerified':False}
(HERE / 'manifest-review.json').write_text(json.dumps(review,indent=2)+'\n')
print(json.dumps({k:v for k,v in review.items() if k!='nativeOccupancyQueryEvidence'},indent=2))
