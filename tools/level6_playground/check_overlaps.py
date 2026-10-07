"""Two surfaces in one plane: find every place in the arena's export where that happens.

    python3 tools/level6_playground/check_overlaps.py            # the export of build_arena.py
    python3 tools/level6_playground/check_overlaps.py --all      # also what is listed as out of sight

Two faces that lie in the same plane, face the same way and cover the same ground cannot both be drawn: the
renderer picks one per pixel and the pick changes with the camera ("z-fighting"). With flat colours nobody sees
it when both are the same colour. With printed materials (the PBR pass of 2026-10-07) every one of them shows as
two patterns flickering through each other, which is what the owner photographed that day. So this is run after
every change to the geometry and has to print 0 for what can be seen.

It also lists mats that lie ON other mats within a fifth of a stud (no flicker, but one printed mat over another
at a different angle), which is how the old lid and the old decks looked.

Checked: boxes ('b'), turned boxes ('o') and cut mats ('p'), their tops, undersides and upright faces. Not
checked: cylinders, balls, nets and tubes (round things meet in a line, and a net is one sheet).
"""
import collections
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / 'artifacts' / 'level6-arena-20261006' / 'export' / 'prims.json'
CX, CY = 300.0, 200.0

# Pairs of groups whose shared planes nobody can see, and why.
HIDDEN = {
    ('Walls', 'Walls'): 'the tops of the hall wall, above the roof; and its panels where they join, inside the wall',
    ('Ceiling_Structure', 'Walls'): 'above the roof',
    ('Finale_Shaft', 'Floor_Concrete'): 'the top of the shaft wall, under the court\'s tiles',
    ('Finale_Shaft', 'Finale_Shaft'): 'the shaft wall\'s panels where they join, at the top under the tiles and at the foot',
    ('Frame_Panels', 'Frame_SoftSteps'): 'the underside of a step, standing on the deck',
    ('Frame_Panels', 'Hall_SoftBlocks'): 'undersides, standing on the floor',
    ('Frame_Lamps', 'Frame_Lamps'): 'two lamp housings back to back',
    ('ExitRoom (up against its ceiling)', 'ExitRoom'): 'faces that look up at the ceiling they hang from',
}


def P(r, a):
    return CX + r * math.cos(math.radians(a)), CY + r * math.sin(math.radians(a))


def load(path=EXPORT):
    rows = json.loads(Path(path).read_text())['prims']
    solids = []
    for i, (group, kind, n, mat) in enumerate(rows):
        if kind == 'b':
            x0, y0, z0, x1, y1, z1 = n
            x0, x1, y0, y1 = min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1)
            poly = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
            solids.append(dict(i=i, g=group, mat=mat, z0=min(z0, z1), z1=max(z0, z1), poly=poly))
        elif kind == 'o':
            cx, cy, cz, sx, sy, sz, yaw = n
            ca, sa = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
            poly = [(cx + dx * ca - dy * sa, cy + dx * sa + dy * ca) for dx, dy in ((-sx / 2, -sy / 2), (sx / 2, -sy / 2), (sx / 2, sy / 2), (-sx / 2, sy / 2))]
            solids.append(dict(i=i, g=group, mat=mat, z0=cz - sz / 2, z1=cz + sz / 2, poly=poly))
        elif kind == 'p':
            ra, rb, delta, split, am, zc, thick = n
            a0, a1 = am - delta / 2, am + delta / 2
            poly = [P(ra, a0), P(ra, a1), P(rb, a1)] + ([P(rb, am)] if split else []) + [P(rb, a0)]
            solids.append(dict(i=i, g=group, mat=mat, z0=zc - thick / 2, z1=zc + thick / 2, poly=poly))
    return rows, solids


def area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) / 2


def clip(subject, clipper):
    """Sutherland-Hodgman: the part of one convex polygon inside another."""
    n = len(clipper)
    if sum(clipper[i][0] * clipper[(i + 1) % n][1] - clipper[(i + 1) % n][0] * clipper[i][1] for i in range(n)) < 0:
        clipper = clipper[::-1]
    out = subject
    for i in range(n):
        a, b = clipper[i], clipper[(i + 1) % n]
        inp, out = out, []
        if not inp:
            break

        def inside(p):
            return (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= -1e-9

        def cross(p, q):
            d1, d2 = (b[0] - a[0], b[1] - a[1]), (q[0] - p[0], q[1] - p[1])
            den = d1[0] * d2[1] - d1[1] * d2[0]
            if abs(den) < 1e-12:
                return q
            t = ((p[0] - a[0]) * d1[1] - (p[1] - a[1]) * d1[0]) / den
            return p[0] + t * d2[0], p[1] + t * d2[1]
        for j in range(len(inp)):
            p, q = inp[j], inp[(j + 1) % len(inp)]
            if inside(q):
                if not inside(p):
                    out.append(cross(p, q))
                out.append(q)
            elif inside(p):
                out.append(cross(p, q))
    return out


def level(solids, which, lo, hi, least=0.05, cell=20.0):
    """Pairs whose `which` faces are between lo and hi studs apart in height and cover the same ground."""
    grid = collections.defaultdict(list)
    reach = int(math.ceil(hi / 0.02)) + 1
    for s in solids:
        xs, ys = [p[0] for p in s['poly']], [p[1] for p in s['poly']]
        s['bb'] = (min(xs), min(ys), max(xs), max(ys))
        for gx in range(int(s['bb'][0] // cell), int(s['bb'][2] // cell) + 1):
            for gy in range(int(s['bb'][1] // cell), int(s['bb'][3] // cell) + 1):
                grid[(gx, gy, round(s[which] / (0.02 * reach)))].append(s)
    seen, pairs = set(), []
    for (gx, gy, gz), bucket in grid.items():
        near = bucket + grid.get((gx, gy, gz + 1), [])
        for ia, a in enumerate(bucket):
            for b in near[ia + 1:]:
                key = (min(a['i'], b['i']), max(a['i'], b['i']))
                if key in seen or a['i'] == b['i']:
                    continue
                seen.add(key)
                apart = abs(a[which] - b[which])
                if not lo <= apart <= hi:
                    continue
                A, B = a['bb'], b['bb']
                if A[2] <= B[0] or B[2] <= A[0] or A[3] <= B[1] or B[3] <= A[1]:
                    continue
                shared = clip(a['poly'], b['poly'])
                size = area(shared) if len(shared) >= 3 else 0
                if size > least:
                    pairs.append((size, a, b))
    return pairs


def upright(solids, least=0.05):
    """Pairs with an upright face in the same plane, facing the same way, covering the same wall."""
    faces = []
    for s in solids:
        poly = s['poly']
        n = len(poly)
        ccw = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n)) > 0
        for i in range(n):
            p, q = poly[i], poly[(i + 1) % n]
            dx, dy = q[0] - p[0], q[1] - p[1]
            length = math.hypot(dx, dy)
            if length < 0.05:
                continue
            tx, ty = dx / length, dy / length
            nx, ny = (ty, -tx) if ccw else (-ty, tx)          # outward
            faces.append(dict(s=s, ang=round(math.degrees(math.atan2(ny, nx)) / 0.25) * 0.25 % 360, d=p[0] * nx + p[1] * ny,
                              t0=min(p[0] * tx + p[1] * ty, q[0] * tx + q[1] * ty), t1=max(p[0] * tx + p[1] * ty, q[0] * tx + q[1] * ty),
                              tan=(tx, ty)))
    buckets = collections.defaultdict(list)
    for f in faces:
        for dq in (-1, 0, 1):
            buckets[(f['ang'], round(f['d'] / 0.02) + dq)].append(f)
    seen, pairs = set(), []
    for bucket in buckets.values():
        for ia, a in enumerate(bucket):
            for b in bucket[ia + 1:]:
                if a['s']['i'] == b['s']['i']:
                    continue
                key = (min(a['s']['i'], b['s']['i']), max(a['s']['i'], b['s']['i']), a['ang'])
                if key in seen or abs(a['d'] - b['d']) > 0.011:
                    continue
                seen.add(key)
                # the same direction along the wall for both, whichever way each polygon was wound
                same = a['tan'][0] * b['tan'][0] + a['tan'][1] * b['tan'][1] > 0
                b0, b1 = (b['t0'], b['t1']) if same else (-b['t1'], -b['t0'])
                w = min(a['t1'], b1) - max(a['t0'], b0)
                h = min(a['s']['z1'], b['s']['z1']) - max(a['s']['z0'], b['s']['z0'])
                if w > 0.05 and h > 0.05 and w * h > least:
                    pairs.append((w * h, a['s'], b['s']))
    return pairs


EXIT_ROOM_CEILING = -44.882      # the padded ceiling of the room under the court (build_arena.py: EXIT_ROOM)
PRESSED = ('ExitRoom (up against its ceiling)', 'ExitRoom')


def table(title, pairs, show_all, tops=False):
    by = collections.defaultdict(lambda: [0, 0.0])
    for size, a, b in pairs:
        key = tuple(sorted((a['g'], b['g'])))
        # the collar round the slide's hole and the strip light hang from that ceiling: their tops are pressed to it
        if tops and key == ('ExitRoom', 'ExitRoom') and a['z1'] > EXIT_ROOM_CEILING - 0.6:
            key = PRESSED
        by[key][0] += 1
        by[key][1] += size
    seen = {k: v for k, v in by.items() if k not in HIDDEN}
    print(f'{title}: {sum(v[0] for v in seen.values())} in sight' + (f', {sum(v[0] for k, v in by.items() if k in HIDDEN)} out of sight' if by else ''))
    for key, (count, size) in sorted(by.items(), key=lambda kv: -kv[1][1]):
        if key in HIDDEN and not show_all:
            continue
        print(f'   {key[0]:20s} x {key[1]:20s} {count:5d} pairs {size:9.1f} sq studs' + (f'   (out of sight: {HIDDEN[key]})' if key in HIDDEN else ''))
    return sum(v[0] for v in seen.values())


def main():
    show_all = '--all' in sys.argv
    paths = [a for a in sys.argv[1:] if not a.startswith('--')]
    rows, solids = load(paths[0] if paths else EXPORT)
    bad = table('tops in one plane', level(solids, 'z1', 0, 0.011), show_all, tops=True)
    bad += table('undersides in one plane', level(solids, 'z0', 0, 0.011), show_all)
    bad += table('upright faces in one plane', upright(solids), show_all)
    table('one mat lying on another (tops 0.011 to 0.2 apart; not a flicker)', level(solids, 'z1', 0.0111, 0.2, least=0.3), True)
    print('RESULT', bad)
    return bad


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
