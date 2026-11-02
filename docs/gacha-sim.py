import random, statistics as st
ODDS = dict(Common=60.0, Rare=27.0, Epic=9.4, Legendary=3.0, Mythic=0.6)
P = dict(epicEvery=10, softStart=60, softStep=6.0, hard=75, mythicHard=150)
POOL = {'Rare': ['ice', 'gun'], 'Epic': ['fk', 'bers', 'ma'], 'Legendary': ['summ'], 'Mythic': ['dk']}
ESS = dict(Rare=40, Epic=100, Legendary=250, Mythic=600)
PRICE = dict(Rare=350, Epic=900, Legendary=2000, Mythic=4000)
RAR = {c: r for r, l in POOL.items() for c in l}
SPARK = 100
MIL = {25: 100, 50: 200, 100: 400, 200: 800}

def run(rng, use_spark=True, use_essence=True, featured='fk', stop_all=True, max_pulls=2000):
    owned = set(); essence = 0; star = 0
    sE = sL = sM = 0; guar = False; n = 0
    first = {}
    while n < max_pulls:
        n += 1; sE += 1; sL += 1; sM += 1; star += 1
        if sM >= P['mythicHard']: r = 'Mythic'
        elif rng.random() * 100 < ODDS['Mythic']: r = 'Mythic'
        elif sL >= P['hard']: r = 'Legendary'
        else:
            leg = ODDS['Legendary'] + (max(0, sL - P['softStart'] + 1) * P['softStep'] if sL >= P['softStart'] else 0)
            if rng.random() * 100 < leg: r = 'Legendary'
            elif sE >= P['epicEvery']: r = 'Epic'
            else:
                lower = ODDS['Common'] + ODDS['Rare'] + ODDS['Epic']
                x = rng.random() * lower
                r = 'Epic' if x < ODDS['Epic'] else ('Rare' if x < ODDS['Epic'] + ODDS['Rare'] else 'Common')
        if r in ('Epic', 'Legendary', 'Mythic'): sE = 0
        if r in ('Legendary', 'Mythic'): sL = 0
        if r == 'Mythic': sM = 0
        if r == 'Common':
            essence += 10
        else:
            if r == 'Epic':
                if guar or rng.random() < 0.5: c = featured; guar = False
                else: c = rng.choice([x for x in POOL['Epic'] if x != featured]); guar = True
            else:
                c = rng.choice(POOL[r])
            if c in owned: essence += ESS[r]
            else: owned.add(c); first[c] = n
        essence += MIL.get(n, 0)
        locked = [c for c in RAR if c not in owned]
        order = ['Mythic', 'Legendary', 'Epic', 'Rare']
        if use_spark and star >= SPARK and locked:
            c = sorted(locked, key=lambda c: order.index(RAR[c]))[0]
            owned.add(c); first[c] = n; star -= SPARK
        if use_essence:
            for c in sorted([c for c in RAR if c not in owned], key=lambda c: order.index(RAR[c])):
                if essence >= PRICE[RAR[c]]:
                    essence -= PRICE[RAR[c]]; owned.add(c); first[c] = n
        if stop_all and len(owned) == 7: break
    return n, first, essence

rng = random.Random(7)
N = 20000
def pct(xs, q): xs = sorted(xs); return xs[int(q * (len(xs) - 1))]
for label, kw in [('pulls, no spark/essence', dict(use_spark=False, use_essence=False)), ('pulls, all systems', dict())]:
    res = [run(rng, **kw) for _ in range(N)]
    ns = [r[0] for r in res]
    print(label, 'all 7: mean %.1f median %d p90 %d p99 %d max %d' % (st.mean(ns), pct(ns, .5), pct(ns, .9), pct(ns, .99), max(ns)))
    for c in ['ice', 'gun', 'fk', 'bers', 'ma', 'summ', 'dk']:
        f = [r[1][c] for r in res]
        print('   %-5s first at: mean %.1f median %d p90 %d' % (c, st.mean(f), pct(f, .5), pct(f, .9)))
# expected Mythic pulls (pity only)
res = []
for _ in range(N):
    s = 0
    while True:
        s += 1
        if s >= 150 or rng.random() < 0.006: break
    res.append(s)
print('Mythic pulls (base+hard pity) mean %.1f' % st.mean(res))
# essence per pull after full collection
r = run(rng, stop_all=False, max_pulls=1000)
print('essence left after 1000 pulls w/ auto-buys:', r[2])
# essence per pull once everything owned: steady state
tot = 0; M = 200000
for _ in range(M):
    x = rng.random() * 100
    tot += 10 if x < 60 else 40 if x < 87 else 100 if x < 96.4 else 250 if x < 99.4 else 600
print('steady essence/pull (no pity) %.1f' % (tot / M))
