"""Level 6 concept v5, "the Arena" with tall walls and the way out under the post, drawn to scale.

Writes SVG and PNG (headless Chrome) to artifacts/level6-concept-20261006b/plan:
  plan_arena.png      the round hall from above
  section_arena.png   the side view, and the middle of it enlarged: the post, the shaft and the exit under the floor

Nothing here builds the level. The constants below are the proposal a Blender build would start from.

    python3 tools/level6_playground/concept_v5/draw_arena.py
"""
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts' / 'level6-concept-20261006b' / 'plan'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"
BG, CREAM, TEAL, AMBER, CORAL, GREEN = '#161D20', '#F3ECDA', '#4FADAA', '#EDA827', '#F2725D', '#57D98A'
POSTS = ['#F2C21A', '#D8342A', '#2A62D8', '#2FA04A']

# ------------------------------------------------------------------ the proposal, in studs
COURT = 44                       # radius of the open court; the post stands in its centre
TIERS = [                        # inner radius, outer radius, floors: a tall wall with two narrow ledges, then solid frame
    (44, 60, 4),
    (60, 76, 8),
    (76, 272, 12),
]
FLOOR = 10                       # studs between decks, as today
FRAME = TIERS[-1][1]
WALL = 274
ROOF = 150
LANE = 14                        # the way in, and wide enough for the Counter
TUNNEL = (12, 40, 8)             # width, length, height: the Counter is 8.2 studs tall and does not fit
RINGS = (118, 196)               # ring corridors for the Counter, on every floor
SPOKES = [(COURT, RINGS[0], (0, 90, 180)), (RINGS[0], RINGS[1], (45, 135, 225, 315)), (RINGS[1], FRAME - 8, (0, 90, 180))]
COUNTDOWN = 60                   # seconds from the third touch to the post going down
SHAFT = (5, 30)                  # radius and depth of the shaft under the post
ROOM = (-9, 52, 14)              # the exit room under the court: from x, to x, height
TODAY = {'hall': (600, 400), 'roof': 46, 'frame': (144, 168), 'floors': 3}
TINT = {4: '#F2C84B', 8: '#E88A38', 12: '#C9382B'}


def polar(r, deg):
    a = math.radians(deg)
    return r * math.cos(a), r * math.sin(a)


def numbers():
    hall = math.pi * WALL ** 2
    frame = math.pi * (FRAME ** 2 - COURT ** 2) - LANE * (FRAME - COURT)
    decks = sum(math.pi * (r1 ** 2 - r0 ** 2) * n for r0, r1, n in TIERS)
    today = TODAY['frame'][0] * TODAY['frame'][1]
    # which floors on a tier's face see the foot of the post over the tier in front of it
    seen = []
    for i, (r0, r1, n) in enumerate(TIERS):
        first = (TIERS[i - 1][2] if i else 0)
        for k in range(first, n):
            eye = k * FLOOR + 4
            if all(eye * q0 / r0 >= m * FLOOR for q0, q1, m in TIERS[:i]):
                seen.append(k + 1)
    return {
        'hall_across': WALL * 2, 'roof': ROOF, 'frame_share': round(frame / hall * 100),
        'frame_share_today': round(today / (TODAY['hall'][0] * TODAY['hall'][1]) * 100),
        'cells_today': round(today * TODAY['floors'] / 144), 'cells': round(decks / 144),
        'lane_length': FRAME - COURT, 'top_floor': TIERS[-1][2], 'top_height': TIERS[-1][2] * FLOOR,
        'floors_that_see_the_post': seen, 'countdown': COUNTDOWN,
    }


def t(x, y, s, size, fill=CREAM, anchor='start', weight=700, spacing=1.5, opacity=1.0):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}" '
            f'letter-spacing="{spacing}" opacity="{opacity}">{s}</text>')


def pill(x, y, s, size, fill, ink=BG):
    w = len(s) * size * 0.6 + size * 1.1
    h = size * 1.7
    return (f'<rect x="{x - w / 2:.1f}" y="{y - h / 2:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{size * 0.5:.1f}" fill="{fill}" '
            f'stroke="{BG}" stroke-width="2"/><text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{ink}" text-anchor="middle" '
            f'font-weight="800" letter-spacing="1.5" dominant-baseline="central">{s}</text>')


def page(name, wide, high, body):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{wide}" height="{high}" viewBox="0 0 {wide} {high}" '
           f'font-family="{FONT}"><rect width="{wide}" height="{high}" fill="{BG}"/>{body}</svg>')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f'{name}.svg').write_text(svg)
    html = OUT / f'{name}.html'
    html.write_text(f'<html><body style="margin:0;background:{BG}">{svg}</body></html>')
    target = OUT / f'{name}.png'
    target.unlink(missing_ok=True)
    subprocess.run([CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    f'--window-size={wide},{high}', f'--screenshot={target}', f'file://{html}'], capture_output=True)
    html.unlink()
    print(target.name, target.exists())


STEPS = [
    ('THE THIRD TOUCH', f'every light turns red; the post starts counting down from {COUNTDOWN}'),
    ('THE MINUTE', 'the floor ring is the clock, readable from every gallery; stay alive'),
    ('ZERO', 'the post sinks into the floor; green light comes up out of the hole'),
    ('DOWN', 'a slide winds down the shaft round the post, to a room under the court'),
    ('OUT', 'the green EXIT door; through it the level is cleared'),
]


# ====================================================================== the plan
def plan(facts):
    S, CX, CY = 2.5, 930, 962
    wide, high = 3040, 1880
    o = []

    def P(r, deg):
        x, y = polar(r, deg)
        return CX + x * S, CY - y * S

    def curve(points, colour, thick):
        q = [P(*p) for p in points]
        d = f'M{q[0][0]:.1f} {q[0][1]:.1f}'
        for i in range(len(q) - 1):
            p0, p1, p2, p3 = q[max(i - 1, 0)], q[i], q[i + 1], q[min(i + 2, len(q) - 1)]
            d += (f' C{p1[0] + (p2[0] - p0[0]) / 6:.1f} {p1[1] + (p2[1] - p0[1]) / 6:.1f} '
                  f'{p2[0] - (p3[0] - p1[0]) / 6:.1f} {p2[1] - (p3[1] - p1[1]) / 6:.1f} {p2[0]:.1f} {p2[1]:.1f}')
        o.append(f'<path d="{d}" fill="none" stroke="{BG}" stroke-width="{(thick + 2.5) * S:.1f}" stroke-linecap="round"/>')
        o.append(f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{thick * S:.1f}" stroke-linecap="round"/>')

    tile = 12 * S
    o.append(f'<defs><pattern id="floor" x="{CX}" y="{CY}" width="{tile * 2}" height="{tile * 2}" patternUnits="userSpaceOnUse">'
             f'<rect width="{tile * 2}" height="{tile * 2}" fill="#1C3458"/><rect width="{tile}" height="{tile}" fill="#1D5238"/>'
             f'<rect x="{tile}" y="{tile}" width="{tile}" height="{tile}" fill="#1D5238"/></pattern>'
             f'<marker id="arrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
             f'<path d="M0 0 L10 5 L0 10 z" fill="{CREAM}"/></marker></defs>')

    # the hall: frame everywhere inside the wall, tinted by how many floors stand there
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{WALL * S:.1f}" fill="#0C1216"/>')
    for r0, r1, n in TIERS:
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{(r0 + r1) / 2 * S:.1f}" fill="none" stroke="{TINT[n]}" '
                 f'stroke-width="{(r1 - r0) * S:.1f}" opacity="0.40"/>')
    # net lines and padded posts
    r = COURT
    while r < FRAME:
        spokes = 24 if r < 80 else 48 if r < 150 else 96
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{r * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="0.8" opacity="0.20"/>')
        for k in range(spokes):
            a = 360 / spokes * k
            (x0, y0), (x1, y1) = P(r, a), P(min(r + 14, FRAME), a)
            o.append(f'<path d="M{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f}" stroke="{CREAM}" stroke-width="0.8" opacity="0.20"/>')
            o.append(f'<circle cx="{x0:.1f}" cy="{y0:.1f}" r="2" fill="{POSTS[(k + int(r)) % 4]}" opacity="0.9"/>')
        r += 14
    # the two ledges and the court's edge
    for r0, r1, n in TIERS:
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{r0 * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="3" opacity="0.9"/>')

    # corridors wide enough for the Counter: two rings and the spokes between them, staggered
    for r in RINGS:
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{r * S:.1f}" fill="none" stroke="#3A5D80" stroke-width="{9 * S:.1f}"/>')
    for r0, r1, angles in SPOKES:
        for a in angles:
            (x0, y0), (x1, y1) = P(r0, a), P(r1, a)
            o.append(f'<path d="M{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f}" stroke="#3A5D80" stroke-width="{9 * S:.1f}"/>')
    for r in RINGS:
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{r * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="1.6" '
                 f'stroke-dasharray="10 10" opacity="0.45"/>')
    # stair cores where a spoke meets a ring
    cores = [(RINGS[0], a) for a in (0, 90, 180)] + [(RINGS[0], a) for a in (45, 135, 225, 315)] + \
            [(RINGS[1], a) for a in (45, 135, 225, 315)] + [(RINGS[1], a) for a in (0, 90, 180)]
    for r, a in cores:
        x, y = P(r, a)
        o.append(f'<rect x="{x - 15:.1f}" y="{y - 15:.1f}" width="30" height="30" rx="4" fill="{BG}" stroke="{CREAM}" stroke-width="2.4"/>')
        o.append(''.join(f'<path d="M{x - 9:.1f} {y - 8 + i * 5.4:.1f} h18" stroke="{CREAM}" stroke-width="1.8"/>' for i in range(4)))

    # the court
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{COURT * S:.1f}" fill="url(#floor)" stroke="{CREAM}" stroke-width="3.4"/>')
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{28 * S:.1f}" fill="none" stroke="{AMBER}" stroke-width="{3 * S:.1f}" '
             f'stroke-dasharray="{2 * math.pi * 28 * S / 60 * 0.7:.2f} {2 * math.pi * 28 * S / 60 * 0.3:.2f}"/>')

    # the way in: tunnel, gate, lane
    tw, tl, th = TUNNEL
    x0, y0 = CX - LANE / 2 * S, CY + COURT * S
    o.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{LANE * S:.1f}" height="{(WALL - COURT) * S:.1f}" fill="url(#floor)"/>')
    o.append(f'<path d="M{x0:.1f} {y0:.1f} V{CY + WALL * S:.1f} M{x0 + LANE * S:.1f} {y0:.1f} V{CY + WALL * S:.1f}" stroke="{CREAM}" stroke-width="2.6"/>')
    o.append(f'<path d="M{CX} {CY + (WALL + tl - 6) * S:.1f} V{CY + (COURT + 12) * S:.1f}" stroke="{CREAM}" stroke-width="3" '
             f'stroke-dasharray="14 12" marker-end="url(#arrow)" opacity="0.8"/>')
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{(WALL + 2) * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="{4 * S:.1f}"/>')
    o.append(f'<rect x="{CX - tw / 2 * S:.1f}" y="{CY + (WALL - 2) * S:.1f}" width="{tw * S:.1f}" height="{(tl + 2) * S:.1f}" fill="#22323F" '
             f'stroke="{CREAM}" stroke-width="3"/>')
    o.append(f'<rect x="{CX - (LANE / 2 + 3) * S:.1f}" y="{CY + (WALL - 7) * S:.1f}" width="{(LANE + 6) * S:.1f}" height="{2.6 * S:.1f}" '
             f'fill="#2A62D8" stroke="{BG}" stroke-width="2"/>')
    o.append(f'<circle cx="{CX}" cy="{CY + (WALL + tl - 9) * S:.1f}" r="{3.4 * S:.1f}" fill="{TEAL}" stroke="{BG}" stroke-width="2"/>')

    # net bridges over the court, slides down the face
    for a in (150, 30):
        (xa, ya), (xb, yb) = P(COURT + 3, a), P(COURT + 3, a + 180)
        o.append(f'<path d="M{xa:.1f} {ya:.1f} L{xb:.1f} {yb:.1f}" stroke="#E9A45A" stroke-width="{4.6 * S:.1f}" opacity="0.95"/>')
        o.append(f'<path d="M{xa:.1f} {ya:.1f} L{xb:.1f} {yb:.1f}" stroke="{BG}" stroke-width="{4.6 * S:.1f}" stroke-dasharray="3 8" opacity="0.7"/>')
    curve([(84, 58), (72, 55), (60, 50), (47, 46)], '#E07B2A', 6)
    curve([(84, 118), (72, 121), (60, 126), (47, 130)], '#2A62D8', 6)
    curve([(86, 322), (72, 319), (60, 314), (47, 310)], '#2FA04A', 6)

    # the post, the hole it leaves, the Counter
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{SHAFT[0] * S:.1f}" fill="{GREEN}" stroke="{BG}" stroke-width="2.5"/>')
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{1.9 * S:.1f}" fill="{CORAL}" stroke="{BG}" stroke-width="2"/>')
    o.append(f'<circle cx="{CX + 11 * S:.1f}" cy="{CY - 6 * S:.1f}" r="{2.4 * S:.1f}" fill="#E9DCC8" stroke="{BG}" stroke-width="2"/>')

    # floors, along the west radius
    for (r0, r1, n), rr in zip(TIERS, (52, 68, 160)):
        x, y = P(rr, 180 if rr > 100 else 197)
        o.append(pill(x, y, str(n), 24 if rr < 100 else 32, TINT[n]))
    x, y = P(WALL + 16, 180)
    o.append(t(x, y - 34, 'FLOORS', 30, CREAM, 'end', 800, 2))
    o.append(t(x, y + 2, 'STANDING THERE', 22, CREAM, 'end', 700, 1.5, 0.7))
    o.append(f'<path d="M{x + 8:.1f} {y - 12:.1f} h34" stroke="{CREAM}" stroke-width="3" marker-end="url(#arrow)"/>')

    # labels
    o.append(pill(CX, CY - (COURT + 13) * S, 'THE POST', 27, BG, AMBER))
    o.append(pill(CX + 150, CY + (COURT + 16) * S, 'THE WAY OUT IS UNDER IT', 23, GREEN))
    x, y = P(WALL + tl * 0.45, 270)
    o.append(t(x + 30, y - 14, 'YOU ARRIVE HERE', 30, TEAL, 'start', 800, 2))
    o.append(t(x + 30, y + 20, 'a hole in the wall: a tunnel too low for the Counter', 24, CREAM, 'start', 600, 0.8, 0.8))
    x, y = P(WALL - 18, 270)
    o.append(pill(x - 150, y, 'PLAY ZONE GATE', 24, '#2A62D8', CREAM))
    x, y = P(160, 270)
    o.append(f'<g transform="translate({x - 26:.1f} {y:.1f}) rotate(-90)">{t(0, 0, "THE WAY IN  ·  " + str(FRAME - COURT) + " STUDS", 24, CREAM, "middle", 800, 3)}</g>')

    # ------------------------------------------------------------ the right-hand column
    lx = CX + WALL * S + 150
    o.append(t(90, 110, 'LEVEL 6  ·  THE ARENA  ·  DRAFT 3', 62, CREAM, weight=800, spacing=3))
    o.append(t(90, 170, 'One structure, wall to wall. Twelve floors of galleries stand round the post, and the way out is under it.',
               33, TEAL, weight=600, spacing=1))
    y = 300
    o.append(t(lx, y, 'WHAT CHANGES', 40, AMBER, weight=800, spacing=3))
    rows = [
        ('HALL', f'{TODAY["hall"][0]} x {TODAY["hall"][1]}', f'round, {WALL * 2} studs across'),
        ('ROOF', f'{TODAY["roof"]} studs', f'{ROOF} studs'),
        ('THE FRAME', f'{facts["frame_share_today"]}% of the floor', f'{facts["frame_share"]}% of the floor'),
        ('FLOORS', '3', '12, from the court to the wall'),
        ('ROUND THE POST', 'open hall', 'a wall of galleries, two narrow ledges'),
        ('HOW YOU ARRIVE', 'reception', 'a tunnel, then the PLAY ZONE gate'),
        ('THE WAY OUT', 'by the arcade', 'under the post'),
    ]
    y += 62
    for head, was, now in rows:
        o.append(t(lx, y, head, 24, CREAM, weight=800, spacing=2, opacity=0.6))
        o.append(t(lx, y + 38, was, 28, CREAM, weight=600, spacing=1, opacity=0.55))
        o.append(t(lx + 222, y + 38, '&#8594;', 28, CREAM, weight=600, opacity=0.55))
        o.append(t(lx + 262, y + 38, now, 30, CREAM, weight=800, spacing=0.6))
        y += 88
    y += 14
    o.append(t(lx, y, 'KEY', 40, AMBER, weight=800, spacing=3))
    y += 20
    key = [('tint', 'Frame; the number is how many floors stand there'),
           ('lane', 'Corridor wide enough for the Counter, on every floor'),
           ('core', 'Stairs wide enough for the Counter'),
           ('slide', 'Tube slide down the face, one colour each'),
           ('bridge', 'Net bridge over the court')]
    for kind, text in key:
        y += 52
        if kind == 'tint':
            for i, c in enumerate((TINT[4], TINT[8], TINT[12])):
                o.append(f'<rect x="{lx + i * 22}" y="{y - 28}" width="22" height="36" fill="#0C1216"/><rect x="{lx + i * 22}" y="{y - 28}" width="22" height="36" fill="{c}" opacity="0.5"/>')
            o.append(f'<rect x="{lx}" y="{y - 28}" width="66" height="36" fill="none" stroke="{CREAM}" stroke-width="2"/>')
        elif kind == 'lane':
            o.append(f'<rect x="{lx}" y="{y - 22}" width="66" height="24" rx="12" fill="#3A5D80"/>'
                     f'<path d="M{lx + 8} {y - 10} h50" stroke="{CREAM}" stroke-width="1.6" stroke-dasharray="8 8" opacity="0.6"/>')
        elif kind == 'core':
            o.append(f'<rect x="{lx + 18}" y="{y - 26}" width="30" height="30" rx="4" fill="{BG}" stroke="{CREAM}" stroke-width="2.4"/>'
                     + ''.join(f'<path d="M{lx + 24} {y - 19 + i * 5.4:.1f} h18" stroke="{CREAM}" stroke-width="1.8"/>' for i in range(4)))
        elif kind == 'slide':
            o.append(f'<path d="M{lx + 4} {y - 2} q28 -34 58 -6" stroke="{BG}" stroke-width="20" fill="none" stroke-linecap="round"/>'
                     f'<path d="M{lx + 4} {y - 2} q28 -34 58 -6" stroke="{POSTS[1]}" stroke-width="15" fill="none" stroke-linecap="round"/>')
        else:
            o.append(f'<rect x="{lx}" y="{y - 17}" width="66" height="13" fill="#E9A45A"/>'
                     f'<path d="M{lx} {y - 10} h66" stroke="{BG}" stroke-width="13" stroke-dasharray="3 8" opacity="0.7"/>')
        o.append(t(lx + 90, y, text, 26, CREAM, weight=600, spacing=0.5))
    y += 76
    o.append(t(lx, y, 'HOW THE ROUND ENDS', 40, AMBER, weight=800, spacing=3))
    y += 14
    for i, (name, text) in enumerate(STEPS):
        y += 66
        o.append(f'<circle cx="{lx + 24}" cy="{y - 12}" r="24" fill="{CORAL if i < 2 else GREEN}"/>')
        o.append(f'<text x="{lx + 24}" y="{y - 12}" font-size="30" fill="{BG}" text-anchor="middle" font-weight="800" dominant-baseline="central">{i + 1}</text>')
        o.append(t(lx + 66, y - 16, name, 28, CREAM, weight=800, spacing=1.5))
        o.append(t(lx + 66, y + 13, text, 23, CREAM, weight=600, spacing=0.4, opacity=0.8))

    by = high - 62
    o.append(f'<path d="M90 {by} h{100 * S} M90 {by - 12} v24 M{90 + 100 * S} {by - 12} v24" stroke="{CREAM}" stroke-width="4"/>')
    o.append(t(90 + 100 * S + 24, by + 10, '100 studs: about 6 seconds at a walk, 4 at a sprint', 28, CREAM, weight=600, spacing=1))
    page('plan_arena', wide, high, ''.join(o))


# ====================================================================== the side view
def section(facts):
    E, wide, high = 3.4, 3040, 2500
    o = []

    def box(base, ground, x0, x1, h0, h1, scale=None, **style):
        e = scale or E
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        o.append(f'<rect x="{base + x0 * e:.1f}" y="{ground - h1 * e:.1f}" width="{(x1 - x0) * e:.1f}" height="{(h1 - h0) * e:.1f}" {attrs}/>')

    def block(base, ground, x0, x1, n, tint, pitch=14, scale=None, first=0):
        e = scale or E
        top = n * FLOOR
        box(base, ground, x0, x1, 0, top, e, fill='#0C1216')
        box(base, ground, x0, x1, 0, top, e, fill=tint, opacity=0.34)
        box(base, ground, x0, x1, 0, top, e, fill='url(#enet)')
        mats = ['#D8342A', '#2A62D8', '#2FA04A', '#F2C21A']
        for k in range(1, n):
            x, i = x0, 0
            while x < x1 - 0.1:
                box(base, ground, x, min(x + pitch * 2, x1), k * FLOOR - 0.8, k * FLOOR + 0.8, e, fill=mats[(k + i) % 4])
                x += pitch * 2
                i += 1
        x, i = x0, 0
        while x <= x1 + 0.1:
            o.append(f'<path d="M{base + x * e:.1f} {ground:.1f} V{ground - top * e:.1f}" stroke="{POSTS[i % 4]}" stroke-width="{3 if e < 5 else 5}"/>')
            x += pitch
            i += 1
        o.append(f'<path d="M{base + x0 * e:.1f} {ground - top * e:.1f} H{base + x1 * e:.1f}" stroke="{CREAM}" stroke-width="2.6"/>')

    def hall(base, ground, x0, x1, roof):
        box(base, ground, x0, x1, 0, roof, fill='#1B2328')
        box(base, ground, x0, x1, roof, roof + 3, fill='#5C666C')
        x = x0 + 8
        while x < x1 - 12:
            o.append(f'<path d="M{base + x * E:.1f} {ground - roof * E:.1f} l{6 * E:.1f} {3.4 * E:.1f} l{6 * E:.1f} {-3.4 * E:.1f}" '
                     f'stroke="#5C666C" stroke-width="2" fill="none"/>')
            x += 12
        x = x0 + 30
        while x < x1 - 20:
            box(base, ground, x, x + 9, roof - 6.2, roof - 5.2, fill='#FFF6D8')
            x += 62
        x, i = x0, 0
        while x < x1 - 0.1:
            box(base, ground, x, min(x + 12, x1), -4, 0, fill='#1C3458' if i % 2 else '#1D5238')
            x += 12
            i += 1

    def figure(base, ground, x, h, tall, colour, scale=None):
        e = scale or E
        head = tall * 0.24
        box(base, ground, x - tall * 0.16, x + tall * 0.16, h, h + tall - head, e, fill=colour)
        o.append(f'<circle cx="{base + x * e:.1f}" cy="{ground - (h + tall - head / 2) * e:.1f}" r="{head * e / 2:.1f}" fill="{colour}"/>')

    def rise(base, ground, x, h, label, side=1):
        px = base + x * E
        o.append(f'<path d="M{px:.1f} {ground:.1f} V{ground - h * E:.1f} M{px - 9:.1f} {ground:.1f} h18 M{px - 9:.1f} {ground - h * E:.1f} h18" '
                 f'stroke="{AMBER}" stroke-width="3"/>')
        o.append(t(px + side * 16, ground - h * E / 2 + 9, label, 27, AMBER, 'start' if side > 0 else 'end', 800, 1))

    def under(base, ground, scale=None):
        """The shaft under the post and the exit room, below the court floor."""
        e = scale or E
        r, depth = SHAFT
        x0, x1, tall = ROOM
        box(base, ground, x0 - 6, x1 + 14, -(depth + tall + 6), -4 if e < 5 else -1.2, e, fill='#10171B')
        box(base, ground, -r, r, -depth, 0, e, fill='#1E2B33', stroke=CREAM, stroke_width=1.6)
        box(base, ground, x0, x1, -(depth + tall), -depth, e, fill='#123524', stroke=CREAM, stroke_width=1.6)
        box(base, ground, -r + 0.3, r - 0.3, -depth - 1, -depth + 1, e, fill='#123524')
        # the slide winding down the shaft
        pts = []
        for k in range(0, 9):
            pts.append(((r - 1.2) * (1 if k % 2 == 0 else -1), -2 - k * (depth - 2) / 8))
        pts += [(r + 4, -depth - tall + 3), (r + 12, -depth - tall + 1.2)]
        d = ' L'.join(f'{base + x * e:.1f} {ground - h * e:.1f}' for x, h in pts)
        o.append(f'<path d="M{d}" stroke="{BG}" stroke-width="{max(6, e * 1.5):.1f}" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
        o.append(f'<path d="M{d}" stroke="#F2C21A" stroke-width="{max(4, e * 1.05):.1f}" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
        # the exit door and its light
        box(base, ground, x1 - 0.8, x1 + 0.8, -(depth + tall), -(depth + tall) + 9, e, fill=GREEN)
        box(base, ground, x1 - 5, x1 - 0.8, -(depth + tall) + 10, -(depth + tall) + 12.4, e, fill=GREEN)

    o.append(f'<defs><pattern id="enet" width="{2 * E}" height="{2 * E}" patternUnits="userSpaceOnUse">'
             f'<path d="M0 0 H{2 * E} M0 0 V{2 * E}" stroke="{CREAM}" stroke-width="0.6" opacity="0.26"/></pattern></defs>')
    o.append(t(90, 110, 'LEVEL 6  ·  THE ARENA FROM THE SIDE, SAME SCALE', 60, CREAM, weight=800, spacing=3))
    o.append(t(90, 170, 'Twelve floors stand round the court like a wall, broken by two narrow ledges. Under the post: the shaft and the exit.',
               33, TEAL, weight=600, spacing=1))

    # ---- row 1: today, and the arena cut wall to wall
    g1 = 850
    a = 150
    hall(a, g1, 0, 200, TODAY['roof'])
    block(a, g1, 28, 172, 3, '#F2C21A', pitch=12)
    figure(a, g1, 14, 0, 5, '#F2C21A')
    rise(a, g1, -8, TODAY['roof'], str(TODAY['roof']), -1)
    rise(a, g1, 180, 30, '30')
    o.append(t(a, g1 - TODAY['roof'] * E - 46, 'TODAY', 44, CREAM, weight=800, spacing=4))
    o.append(t(a + 168, g1 - TODAY['roof'] * E - 46, '3 floors under a 46-stud roof', 28, CREAM, weight=600, spacing=1, opacity=0.7))

    b = 150 + 200 * E + 150 + WALL * E
    hall(b, g1, -WALL, WALL, ROOF)
    under(b, g1)
    for r0, r1, n in reversed(TIERS):
        block(b, g1, -r1, -r0, n, TINT[n])
        block(b, g1, r0, r1, n, TINT[n])
    box(b, g1, -COURT, COURT, 0, 0.9, fill=AMBER)
    box(b, g1, -1.6, 1.6, 0, 6, fill=CORAL)
    figure(b, g1, 9, 0, 8.2, '#E9DCC8')
    for r0, h in ((TIERS[0][0], 34), (TIERS[1][0], 74), (TIERS[2][0], 114)):
        o.append(f'<path d="M{b - r0 * E:.1f} {g1 - h * E:.1f} L{b:.1f} {g1 - 5 * E:.1f}" stroke="{TEAL}" stroke-width="2.4" '
                 f'stroke-dasharray="12 9" opacity="0.85"/>')
        figure(b, g1, -r0 - 3, h - 4, 5, '#F2C21A')
    rise(b, g1, -WALL - 10, ROOF, str(ROOF), -1)
    o.append(t(b - (WALL - 40) * E, g1 - 120 * E - 18, '12 floors, 120 studs', 25, AMBER, 'start', 800, 1))
    o.append(t(b - WALL * E, g1 - ROOF * E - 46, 'DRAFT 3', 44, AMBER, weight=800, spacing=4))
    o.append(t(b - WALL * E + 220, g1 - ROOF * E - 46, 'cut through the middle of the hall, wall to wall', 28, CREAM, weight=600, spacing=1, opacity=0.7))
    o.append(t(b, g1 + 190, 'the Counter (8 studs) at the post  ·  players (5 studs) in three galleries  ·  dashed: what they see', 23, CREAM, 'middle', 600, 0.6, 0.75))
    o.append(t(b + (ROOM[1] + 22) * E, g1 + (SHAFT[1] + ROOM[2] / 2) * E + 8, 'THE WAY OUT', 26, GREEN, 'start', 800, 2))

    # ---- row 2: the middle enlarged
    Z = 9.5
    g2 = 1770
    zx = 2030
    span = 76
    o.append(f'<clipPath id="zoom"><rect x="{zx - span * Z:.1f}" y="{g2 - 62 * Z:.1f}" width="{span * 2 * Z:.1f}" height="{(62 + 52) * Z:.1f}"/></clipPath>')
    o.append(f'<rect x="{zx - span * Z:.1f}" y="{g2 - 62 * Z:.1f}" width="{span * 2 * Z:.1f}" height="{(62 + 52) * Z:.1f}" fill="#1B2328"/>')
    o.append('<g clip-path="url(#zoom)">')
    o.append(f'<defs><pattern id="znet" width="{2 * Z}" height="{2 * Z}" patternUnits="userSpaceOnUse">'
             f'<path d="M0 0 H{2 * Z} M0 0 V{2 * Z}" stroke="{CREAM}" stroke-width="0.8" opacity="0.2"/></pattern></defs>')
    under(zx, g2, Z)
    for r0, r1, n in reversed(TIERS):
        block(zx, g2, -min(r1, span + 20), -r0, n, TINT[n], scale=Z)
        block(zx, g2, r0, min(r1, span + 20), n, TINT[n], scale=Z)
    x, i = -COURT, 0
    while x < COURT - 0.1:          # the court floor, with the hole in the middle
        if not (-SHAFT[0] <= x < SHAFT[0]):
            box(zx, g2, x, x + 4, -1.2, 0, Z, fill='#1C3458' if i % 2 else '#1D5238')
        x += 4
        i += 1
    for side in (-1, 1):            # the dial on the floor
        box(zx, g2, side * 28 - 1.5, side * 28 + 1.5, 0, 0.5, Z, fill='#FFFFFF')
    # the post: where it stands, and where it ends up
    box(zx, g2, -1.6, 1.6, 0, 6, Z, fill=CORAL, stroke=BG, stroke_width=2)
    box(zx, g2, -1.6, 1.6, 4.3, 5.6, Z, fill='#FFFFFF')
    box(zx, g2, -1.6, 1.6, -SHAFT[1] - ROOM[2], -SHAFT[1] - ROOM[2] + 6, Z, fill='none', stroke=CORAL, stroke_width=3, stroke_dasharray='9 7')
    o.append(f'<path d="M{zx:.1f} {g2 + 3 * Z:.1f} V{g2 + (SHAFT[1] + ROOM[2] - 9) * Z:.1f}" stroke="{CORAL}" stroke-width="3" stroke-dasharray="9 7" marker-end="url(#zarrow)"/>')
    figure(zx, g2, 11, 0, 8.2, '#E9DCC8', Z)
    figure(zx, g2, -20, 0, 5, '#F2C21A', Z)
    figure(zx, g2, 30, -SHAFT[1] - ROOM[2], 5, '#F2C21A', Z)
    o.append('</g>')
    o.append(f'<defs><marker id="zarrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto">'
             f'<path d="M0 0 L10 5 L0 10 z" fill="{CORAL}"/></marker></defs>')
    o.append(f'<rect x="{zx - span * Z:.1f}" y="{g2 - 62 * Z:.1f}" width="{span * 2 * Z:.1f}" height="{(62 + 52) * Z:.1f}" fill="none" stroke="{CREAM}" stroke-width="3"/>')
    o.append(t(zx - 2.6 * Z, g2 - 8.2 * Z, '0:47', 30, CREAM, 'end', 800, 1))
    o.append(t(zx + (ROOM[1] + 2) * Z, g2 + (SHAFT[1] + 1.2) * Z, 'EXIT', 30, GREEN, 'start', 800, 2))
    o.append(t(zx - span * Z, g2 - 62 * Z - 26, 'THE MIDDLE, ENLARGED', 44, CREAM, weight=800, spacing=4))
    o.append(t(zx - span * Z + 570, g2 - 62 * Z - 26, 'the post, the shaft under it and the exit room', 28, CREAM, weight=600, spacing=1, opacity=0.7))

    y = g2 - 62 * Z + 36
    o.append(t(90, y, 'HOW THE ROUND ENDS', 40, AMBER, weight=800, spacing=3))
    y += 20
    for i, (name, text) in enumerate(STEPS):
        y += 104
        o.append(f'<circle cx="118" cy="{y - 14}" r="28" fill="{CORAL if i < 2 else GREEN}"/>')
        o.append(f'<text x="118" y="{y - 14}" font-size="34" fill="{BG}" text-anchor="middle" font-weight="800" dominant-baseline="central">{i + 1}</text>')
        o.append(t(170, y - 20, name, 34, CREAM, weight=800, spacing=1.5))
        o.append(t(170, y + 18, text, 27, CREAM, weight=600, spacing=0.4, opacity=0.85))
    y += 96
    for line in ('The post goes down the middle of the shaft and the slide winds round it,',
                 'so the hole is never blocked. The tunnel and the exit room are both too',
                 'low for the Counter: once you are on the slide it cannot follow.'):
        o.append(t(90, y, line, 27, CREAM, weight=600, spacing=0.4, opacity=0.75))
        y += 38

    fy = high - 96
    cells = [(f'{TODAY["roof"]} &#8594; {ROOF}', 'studs up to the roof'), (f'3 &#8594; {facts["top_floor"]}', 'floors round the post'),
             (f'{facts["frame_share_today"]}% &#8594; {facts["frame_share"]}%', 'of the floor is frame'),
             (f'{COUNTDOWN} s', 'from the third touch to the way out')]
    step = (wide - 180) / len(cells)
    for i, (big, small) in enumerate(cells):
        o.append(t(90 + step * i, fy, big, 70, AMBER, weight=800, spacing=1))
        o.append(t(90 + step * i, fy + 50, small, 29, CREAM, weight=600, spacing=1, opacity=0.8))
    page('section_arena', wide, high, ''.join(o))


if __name__ == '__main__':
    facts = numbers()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'numbers.json').write_text(json.dumps(facts, indent=1))
    print(facts)
    plan(facts)
    section(facts)
