"""Halloween sale 2026: the shop's Robux prices on Roblox, 66.6 % off, donations excepted.

    python3 tools/promo/halloween_prices.py            # read every price, print the plan, change nothing
    python3 tools/promo/halloween_prices.py --apply    # set the sale prices, read them back
    python3 tools/promo/halloween_prices.py --restore  # put the regular prices back (from before.json)

The owner, 2026-10-13: "66,6% på alt så gå ind og ændre prisen på aaalt i vores butik undtagen [donationer]".
Requests go from the owner's signed-in Creator Dashboard tab (tools/promo/dashboard.py): no keys, no clicks.
Only the ids listed here are touched: the donation products, the 20K support pass and the three upgrade passes
that are off sale are not in the list.
"""
import json, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import dashboard as d
d.TAB = 'create.roblox.com/dashboard'
U = 10559217407
OUT = Path(__file__).resolve().parents[2] / 'artifacts' / 'store-prices-halloween-20261013'
PASSES = {1982715834: 'Zyntra Entity Detector', 1941938256: 'Zyntra Supporter', 1945402536: 'Advanced Equipment', 1946086261: 'Glowstick Customizer',
          1995218405: 'Token Earner 2x', 1995716395: 'Token Earner 3x', 1994654411: 'Token Earner 5x', 1994666374: 'Skin Static Wraith', 1994816385: 'Skin False Sun'}
PRODUCTS = {3713829859: 'Expedition Pack', 3707755089: '4 Research Tokens', 3707755233: '20 Research Tokens', 3707755318: 'Emergency Re-entry'}
sale = lambda regular: max(1, int(regular * (1 - 0.666) + 0.5))


def steady(fn, tries=8):
    last = None
    for _ in range(tries):
        try:
            return fn()
        except Exception as e:
            last = e
            time.sleep(2.5)
    raise SystemExit('Chrome did not answer: %s' % str(last)[-160:])


def get(url):
    def go():
        st, tx = d.call('GET', url)
        if st != 200: raise RuntimeError('%s %s' % (st, tx[:160]))
        return json.loads(tx)
    return steady(go)


def read():
    rows = {}
    for pid, name in PASSES.items():
        r = get('https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%d/creator' % (U, pid))
        rows[str(pid)] = {'kind': 'pass', 'name': r['name'], 'ours': name, 'forSale': r['isForSale'], 'price': r['priceInformation'].get('defaultPriceInRobux'),
                          'features': r['priceInformation'].get('enabledFeatures'), 'managed': r.get('isManagedPricingEnabled')}
    for pid, name in PRODUCTS.items():
        r = get('https://apis.roblox.com/developer-products/v2/universes/%d/developer-products/%d/creator' % (U, pid))
        info = r.get('priceInformation') or {}
        rows[str(pid)] = {'kind': 'product', 'name': r.get('name'), 'ours': name, 'forSale': r.get('isForSale'), 'price': info.get('defaultPriceInRobux'),
                          'features': info.get('enabledFeatures'), 'managed': r.get('isManagedPricingEnabled'), 'raw_keys': sorted(r.keys())}
    return rows


def show(rows, target=None):
    for pid, r in rows.items():
        print('%-8s %-11s %-26s forSale=%-5s price %-5s %s%s' % (r['kind'], pid, r['name'][:26], r['forSale'], r['price'], r.get('features'),
              ('  -> ' + str(target[pid])) if target else ''))


def put(pid, kind, price):
    url = ('https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%s' if kind == 'pass' else 'https://apis.roblox.com/developer-products/v2/universes/%d/developer-products/%s') % (U, pid)
    def go():
        st, tx = d.call('PATCH', url, fields={'price': str(price)})
        if st not in (200, 204): raise RuntimeError('%s %s' % (st, tx[:200]))
        return st
    return steady(go, tries=3)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    now = read()
    if '--restore' in sys.argv:
        before = json.loads((OUT / 'before.json').read_text())
        target = {pid: before[pid]['price'] for pid in now}
    else:
        if not (OUT / 'before.json').exists():
            (OUT / 'before.json').write_text(json.dumps(now, indent=1) + '\n')
        before = json.loads((OUT / 'before.json').read_text())
        target = {pid: sale(before[pid]['price']) for pid in now}
    show(now, target)
    if '--apply' not in sys.argv and '--restore' not in sys.argv:
        print('plan only: nothing changed'); return
    for pid, r in now.items():
        if r['price'] != target[pid]:
            print('set', pid, r['name'], r['price'], '->', target[pid], put(pid, r['kind'], target[pid]), flush=True)
            time.sleep(1.2)
    after = read()
    (OUT / ('restored.json' if '--restore' in sys.argv else 'after.json')).write_text(json.dumps(after, indent=1) + '\n')
    print('--- read back'); show(after)
    wrong = [pid for pid in after if after[pid]['price'] != target[pid]]
    print('ALL SET' if not wrong else 'NOT SET: %s' % wrong)


main()
