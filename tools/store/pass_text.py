"""Read or change a game pass's description on Roblox through the signed-in dashboard tab."""
import sys, json, time
sys.path.insert(0, '/Users/zeanjuul4/Projects/Roblox Horror REPO/tools/promo')
import dashboard as d
d.TAB = 'create.roblox.com/dashboard'
U = 10559217407

def steady(fn, tries=10):
    last = None
    for _ in range(tries):
        try:
            return fn()
        except Exception as e:
            last = e
            time.sleep(3)
    raise SystemExit('Chrome did not answer: %s' % str(last)[-120:])

def read(pid):
    def go():
        st, tx = d.call('GET', 'https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%d/creator' % (U, pid))
        if st != 200: raise RuntimeError('%s %s' % (st, tx[:120]))
        return json.loads(tx)
    return steady(go)

def describe(pid, text):
    before = read(pid)
    if before['description'] == text:
        print(pid, 'already says that'); return
    st, tx = d.call('PATCH', 'https://apis.roblox.com/game-passes/v1/universes/%d/game-passes/%d' % (U, pid), fields={'description': text})
    print('PATCH', pid, st, tx[:160])
    time.sleep(1.5)
    after = read(pid)
    print('  now:', after['description'])
    print('  name %s | forSale %s | price %s' % (after['name'], after['isForSale'], after['priceInformation'].get('defaultPriceInRobux')))
    return before, after

if __name__ == '__main__':
    for pid in map(int, sys.argv[1:]):
        row = read(pid)
        print(pid, '|', row['name'], '| forSale', row['isForSale'], '| price', row['priceInformation'].get('defaultPriceInRobux'))
        print('   ', row['description'])
