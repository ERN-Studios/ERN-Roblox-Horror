"""Token-earner passes: read all six, take the three upgrade passes off sale, read again."""
import sys, json, time
sys.path.insert(0, '/Users/zeanjuul4/Projects/Roblox Horror REPO/tools/promo')
from pathlib import Path
import dashboard as d
d.TAB = 'create.roblox.com/dashboard'      # any signed-in Creator Dashboard tab; the fetch does not change what it shows
U = 10559217407
UPGRADES = {1994282418: 'Token Earner Upgrade 2x to 3x', 1995812369: 'Token Earner Upgrade 3x to 5x', 1994252411: 'Token Earner Upgrade 2x to 5x'}
KEEP = {1995218405: 'Token Earner 2x', 1995716395: 'Token Earner 3x', 1994654411: 'Token Earner 5x'}
OUT = Path('/Users/zeanjuul4/Projects/Roblox Horror REPO/artifacts/store-passes-20261008')
OUT.mkdir(parents=True, exist_ok=True)

def steady(fn, tries=8):
    last = None
    for _ in range(tries):
        try:
            return fn()
        except Exception as e:            # Chrome's scripting bridge drops out now and then (-600)
            last = e
            time.sleep(2.5)
    raise SystemExit('Chrome did not answer: %s' % str(last)[-120:])

def read(pid):
    def go():
        st, tx = d.call('GET', 'https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%d/creator' % (U, pid))
        if st != 200: raise RuntimeError('%s %s' % (st, tx[:120]))
        return json.loads(tx)
    return steady(go)

def table(tag):
    rows = {str(pid): read(pid) for pid in list(UPGRADES) + list(KEEP)}
    for pid, row in rows.items():
        print(tag, pid, row['name'], '| forSale=%s' % row['isForSale'], '| price', row['priceInformation'].get('defaultPriceInRobux'), '| regional', row['priceInformation'].get('enabledFeatures'), '| managed', row.get('isManagedPricingEnabled'))
    return rows

what = sys.argv[1]
if what == 'read':
    table('now   ')
elif what == 'before':
    (OUT / 'token-earner-passes-before.json').write_text(json.dumps(table('before'), indent=1))
elif what == 'off':
    for pid, name in UPGRADES.items():
        row = read(pid)                                   # read first: never send a write on top of a failed call blind
        if row['isForSale'] is False:
            print('already off sale', pid, name); continue
        try:
            st, tx = d.call('PATCH', 'https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%d' % (U, pid), fields={'isForSale': 'false'})
            print('PATCH', pid, name, st, tx[:200])
        except Exception as e:
            print('PATCH', pid, 'call failed:', str(e)[-100:])
        time.sleep(1.5)
        print('   ->', pid, 'forSale=%s' % read(pid)['isForSale'])
    (OUT / 'token-earner-passes-after.json').write_text(json.dumps(table('after '), indent=1))
