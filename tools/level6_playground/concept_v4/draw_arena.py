"""Level 6 concept v4, "the Arena": one structure wall to wall, drawn to scale.

Writes SVG and PNG (headless Chrome) to artifacts/level6-concept-20261006/plan:
  plan_arena.png      the round hall from above
  section_arena.png   the side view: today, the bowl (proposed) and the well (the other way to build it)

Nothing here builds the level. The constants below are the proposal a Blender build would start from.

    python3 tools/level6_playground/concept_v4/draw_arena.py
"""
import json
import math
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts' / 'level6-concept-20261006' / 'plan'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"
BG, CREAM, TEAL, AMBER, CORAL, GREEN = '#161D20', '#F3ECDA', '#4FADAA', '#EDA827', '#F2725D', '#57D98A'
POSTS = ['#F2C21A', '#D8342A', '#2A62D8', '#2FA04A']

# ------------------------------------------------------------------ the proposal, in studs
COURT = 44            # radius of the open court; the post stands in its centre
RING = 38             # depth of one ring of frame (never deeper than the court's radius, or a terrace loses the post)
RINGS = 6
STEP = 2              # floors each ring adds to the one in front of it
FLOOR = 10            # studs between decks, as today
FRAME = COURT + RING * RINGS      # 272: where the last ring meets the wall
WALL = 274
ROOF = 150
LANE = 14             # the way in, and wide enough for the Counter
TUNNEL = (12, 40, 8)  # width, length, height: the Counter is 8.2 studs tall and does not fit
AISLES = [22.5 + 45 * k for k in range(8)]       # stair aisles up the terraces, degrees (0 = east, 90 = north)
TODAY = {'hall': (600, 400), 'roof': 46, 'frame': (144, 168), 'floors': 3}
TINT = ['#F2D36B', '#F2B84B', '#EE9A3C', '#E67A34', '#DB572F', '#C9382B']     # 2 floors .. 12 floors


def floors(n):
    return STEP * n


def polar(r, deg):
    a = math.radians(deg)
    return r * math.cos(a), r * math.sin(a)


def numbers():
    hall = math.pi * WALL ** 2
    frame = math.pi * (FRAME ** 2 - COURT ** 2) - LANE * (FRAME - COURT)
    decks = sum(math.pi * ((COURT + RING * n) ** 2 - (COURT + RING * (n - 1)) ** 2) * floors(n) for n in range(1, RINGS + 1))
    well = math.pi * (FRAME ** 2 - COURT ** 2) * floors(RINGS)
    today = TODAY['frame'][0] * TODAY['frame'][1]
    return {
        'hall_across': WALL * 2, 'roof': ROOF, 'frame_share': round(frame / hall * 100),
        'frame_share_today': round(today / (TODAY['hall'][0] * TODAY['hall'][1]) * 100),
        'footprint_factor': round(frame / today, 1),
        'cells_today': round(today * TODAY['floors'] / 144), 'cells_bowl': round(decks / 144), 'cells_well': round(well / 144),
        'well_over_bowl_percent': round((well / decks - 1) * 100),
        'lane_length': FRAME - COURT, 'top_floor': floors(RINGS), 'top_height': floors(RINGS) * FLOOR,
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


# ====================================================================== the plan
def plan(facts):
    S, CX, CY = 2.5, 930, 962
    wide, high = 3040, 1880
    o = []

    def P(r, deg):
        x, y = polar(r, deg)
        return CX + x * S, CY - y * S

    def arc_band(r0, r1, a0, a1, **style):
        """An annular sector between two radii and two angles (degrees, counter-clockwise)."""
        (x0, y0), (x1, y1), (x2, y2), (x3, y3) = P(r1, a0), P(r1, a1), P(r0, a1), P(r0, a0)
        big = 1 if abs(a1 - a0) > 180 else 0
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        o.append(f'<path d="M{x0:.1f} {y0:.1f} A{r1 * S:.1f} {r1 * S:.1f} 0 {big} 0 {x1:.1f} {y1:.1f} L{x2:.1f} {y2:.1f} '
                 f'A{r0 * S:.1f} {r0 * S:.1f} 0 {big} 1 {x3:.1f} {y3:.1f} Z" {attrs}/>')

    def curve(points, colour, thick):
        q = [P(*p) for p in points]
        d = f'M{q[0][0]:.1f} {q[0][1]:.1f}'
        for i in range(len(q) - 1):
            p0, p1, p2, p3 = q[max(i - 1, 0)], q[i], q[i + 1], q[min(i + 2, len(q) - 1)]
            d += (f' C{p1[0] + (p2[0] - p0[0]) / 6:.1f} {p1[1] + (p2[1] - p0[1]) / 6:.1f} '
                  f'{p2[0] - (p3[0] - p1[0]) / 6:.1f} {p2[1] - (p3[1] - p1[1]) / 6:.1f} {p2[0]:.1f} {p2[1]:.1f}')
        o.append(f'<path d="{d}" fill="none" stroke="{BG}" stroke-width="{(thick + 2.5) * S:.1f}" stroke-linecap="round"/>')
        o.append(f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="{thick * S:.1f}" stroke-linecap="round"/>')
        o.append(f'<path d="{d}" fill="none" stroke="#FFFFFF" stroke-width="{1.3 * S:.1f}" stroke-linecap="round" opacity="0.35"/>')

    tile = 12 * S
    o.append(f'<defs><pattern id="floor" x="{CX}" y="{CY}" width="{tile * 2}" height="{tile * 2}" patternUnits="userSpaceOnUse">'
             f'<rect width="{tile * 2}" height="{tile * 2}" fill="#1C3458"/><rect width="{tile}" height="{tile}" fill="#1D5238"/>'
             f'<rect x="{tile}" y="{tile}" width="{tile}" height="{tile}" fill="#1D5238"/></pattern>'
             f'<marker id="arrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
             f'<path d="M0 0 L10 5 L0 10 z" fill="{CREAM}"/></marker></defs>')

    # the hall: dark frame everywhere inside the wall
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{WALL * S:.1f}" fill="#0C1216"/>')
    for n in range(1, RINGS + 1):
        r0, r1 = COURT + RING * (n - 1), COURT + RING * n
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{(r0 + r1) / 2 * S:.1f}" fill="none" stroke="{TINT[n - 1]}" '
                 f'stroke-width="{RING * S:.1f}" opacity="0.42"/>')
    # net lines and padded posts: rings every 13 studs, spokes closer together the further out
    for n in range(1, RINGS + 1):
        r0 = COURT + RING * (n - 1)
        spokes = 24 * (1 if n == 1 else 2 if n <= 3 else 4)
        for k in range(spokes):
            a = 360 / spokes * k
            (x0, y0), (x1, y1) = P(r0, a), P(r0 + RING, a)
            o.append(f'<path d="M{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f}" stroke="{CREAM}" stroke-width="0.8" opacity="0.22"/>')
        for j in range(3):
            r = r0 + 13 * j
            o.append(f'<circle cx="{CX}" cy="{CY}" r="{r * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="0.8" opacity="0.22"/>')
            for k in range(spokes):
                x, y = P(r, 360 / spokes * k)
                o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.1" fill="{POSTS[(k + j + n) % 4]}" opacity="0.9"/>')
    # terrace edges: where one ring's top steps up to the next
    for n in range(1, RINGS + 1):
        r = COURT + RING * (n - 1)
        o.append(f'<circle cx="{CX}" cy="{CY}" r="{r * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="{2.6 if n > 1 else 3.4}" opacity="0.85"/>')

    # stair aisles up the terraces
    for a in AISLES:
        half = math.degrees(5.0 / 150)
        (x0, y0), (x1, y1) = P(COURT + 4, a), P(FRAME - 6, a)
        o.append(f'<path d="M{x0:.1f} {y0:.1f} L{x1:.1f} {y1:.1f}" stroke="#3A5D80" stroke-width="{9 * S:.1f}" stroke-linecap="round"/>')
        for r in range(COURT + 10, FRAME - 6, 7):
            (xa, ya), (xb, yb) = P(r, a - math.degrees(3.6 / r)), P(r, a + math.degrees(3.6 / r))
            o.append(f'<path d="M{xa:.1f} {ya:.1f} L{xb:.1f} {yb:.1f}" stroke="{BG}" stroke-width="1.6" opacity="0.6"/>')

    # the court
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{COURT * S:.1f}" fill="url(#floor)" stroke="{CREAM}" stroke-width="3.4"/>')
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{26 * S:.1f}" fill="none" stroke="{AMBER}" stroke-width="{2.4 * S:.1f}"/>')

    # the way in: tunnel, gate, lane
    tw, tl, th = TUNNEL
    x0, y0 = CX - LANE / 2 * S, CY + COURT * S
    o.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{LANE * S:.1f}" height="{(WALL - COURT) * S:.1f}" fill="url(#floor)"/>')
    o.append(f'<path d="M{x0:.1f} {y0:.1f} V{CY + WALL * S:.1f} M{x0 + LANE * S:.1f} {y0:.1f} V{CY + WALL * S:.1f}" stroke="{CREAM}" stroke-width="2.6"/>')
    o.append(f'<path d="M{CX} {CY + (WALL + tl - 6) * S:.1f} V{CY + (COURT + 12) * S:.1f}" stroke="{CREAM}" stroke-width="3" '
             f'stroke-dasharray="14 12" marker-end="url(#arrow)" opacity="0.8"/>')
    # the wall, then the tunnel through it
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{(WALL + 2) * S:.1f}" fill="none" stroke="{CREAM}" stroke-width="{4 * S:.1f}"/>')
    tx = CX - tw / 2 * S
    o.append(f'<rect x="{tx:.1f}" y="{CY + (WALL - 2) * S:.1f}" width="{tw * S:.1f}" height="{(tl + 2) * S:.1f}" fill="#22323F" '
             f'stroke="{CREAM}" stroke-width="3"/>')
    o.append(f'<rect x="{CX - (LANE / 2 + 3) * S:.1f}" y="{CY + (WALL - 7) * S:.1f}" width="{(LANE + 6) * S:.1f}" height="{2.6 * S:.1f}" '
             f'fill="#2A62D8" stroke="{BG}" stroke-width="2"/>')
    o.append(f'<circle cx="{CX}" cy="{CY + (WALL + tl - 9) * S:.1f}" r="{3.4 * S:.1f}" fill="{TEAL}" stroke="{BG}" stroke-width="2"/>')

    # net bridges over the court, slides down the steps
    for a in (150, 30):
        (xa, ya), (xb, yb) = P(COURT + 3, a), P(COURT + 3, a + 180)
        o.append(f'<path d="M{xa:.1f} {ya:.1f} L{xb:.1f} {yb:.1f}" stroke="#E9A45A" stroke-width="{4.6 * S:.1f}" opacity="0.95"/>')
        o.append(f'<path d="M{xa:.1f} {ya:.1f} L{xb:.1f} {yb:.1f}" stroke="{BG}" stroke-width="{4.6 * S:.1f}" stroke-dasharray="3 8" opacity="0.7"/>')
    curve([(142, 52), (118, 47), (92, 45), (68, 41), (49, 38)], '#E07B2A', 6)
    curve([(250, 138), (214, 133), (176, 132), (138, 128), (102, 126)], '#2A62D8', 6)
    curve([(196, 322), (158, 327), (120, 330), (84, 333)], '#2FA04A', 6)
    curve([(252, 222), (214, 217), (176, 214), (136, 211)], '#F2C21A', 6)
    spiral = [(262 - 2.2 * k + 9 * math.cos(k * 1.25), 90 + 3.2 * math.sin(k * 1.25)) for k in range(0, 9)]
    curve(spiral + [(262, 86.6), (278, 86.2), (296, 86.4)], '#D8342A', 7)

    # the post and the Counter
    o.append(f'<circle cx="{CX}" cy="{CY}" r="{3.2 * S:.1f}" fill="{CORAL}" stroke="{BG}" stroke-width="2.5"/>')
    o.append(f'<circle cx="{CX + 8 * S:.1f}" cy="{CY - 5 * S:.1f}" r="{2.4 * S:.1f}" fill="#E9DCC8" stroke="{BG}" stroke-width="2"/>')

    # floors per ring, along the west radius
    for n in range(1, RINGS + 1):
        x, y = P(COURT + RING * (n - 0.5), 180)
        o.append(pill(x, y, str(floors(n)), 30, TINT[n - 1]))
    x, y = P(WALL + 16, 180)
    o.append(t(x, y - 34, 'FLOORS', 30, CREAM, 'end', 800, 2))
    o.append(t(x, y + 2, 'IN EACH RING', 22, CREAM, 'end', 700, 1.5, 0.7))
    o.append(f'<path d="M{x + 8:.1f} {y - 12:.1f} h34" stroke="{CREAM}" stroke-width="3" marker-end="url(#arrow)"/>')

    # labels
    o.append(pill(CX, CY - (COURT + 13) * S, 'THE POST', 27, BG, AMBER))
    x, y = P(WALL + tl * 0.45, 270)
    o.append(t(x + 30, y - 14, 'YOU ARRIVE HERE', 30, TEAL, 'start', 800, 2))
    o.append(t(x + 30, y + 20, 'a hole in the wall: a tunnel too low for the Counter', 24, CREAM, 'start', 600, 0.8, 0.8))
    x, y = P(WALL - 18, 270)
    o.append(pill(x - 150, y, 'PLAY ZONE GATE', 24, '#2A62D8', CREAM))
    x, y = P(160, 270)
    o.append(f'<g transform="translate({x - 26:.1f} {y:.1f}) rotate(-90)">{t(0, 0, "THE WAY IN  ·  " + str(FRAME - COURT) + " STUDS", 24, CREAM, "middle", 800, 3)}</g>')

    # the four ways out
    marks = [('A', P(246, 98)), ('B', P(WALL + 14, 258)), ('C', (CX - 52, CY + 44)), ('D', P(WALL + 2, 14)), ('D', P(WALL + 2, 166))]
    for letter, (x, y) in marks:
        o.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="24" fill="{GREEN}" stroke="{BG}" stroke-width="3"/>')
        o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="30" fill="{BG}" text-anchor="middle" font-weight="800" dominant-baseline="central">{letter}</text>')

    # ------------------------------------------------------------ the right-hand column
    lx = CX + WALL * S + 150
    o.append(t(90, 110, 'LEVEL 6  ·  THE ARENA  ·  NEW DRAFT', 62, CREAM, weight=800, spacing=3))
    o.append(t(90, 170, 'One structure, wall to wall. The post in the middle, the frame rising round it in six terraces. Nothing else.',
               33, TEAL, weight=600, spacing=1))
    y = 300
    o.append(t(lx, y, 'WHAT CHANGES', 40, AMBER, weight=800, spacing=3))
    rows = [
        ('HALL', f'{TODAY["hall"][0]} x {TODAY["hall"][1]}', f'round, {WALL * 2} studs across'),
        ('ROOF', f'{TODAY["roof"]} studs', f'{ROOF} studs'),
        ('THE FRAME', f'{facts["frame_share_today"]}% of the floor', f'{facts["frame_share"]}% of the floor'),
        ('FLOORS', '3', f'2 at the court, {facts["top_floor"]} at the wall'),
        ('OTHER AREAS', 'nine', 'none'),
        ('HOW YOU ARRIVE', 'reception', 'a tunnel in the wall, then the PLAY ZONE gate'),
        ('WHAT SEES THE POST', 'the open hall', 'the front of every terrace'),
    ]
    y += 62
    for head, was, now in rows:
        o.append(t(lx, y, head, 24, CREAM, weight=800, spacing=2, opacity=0.6))
        o.append(t(lx, y + 38, was, 28, CREAM, weight=600, spacing=1, opacity=0.55))
        o.append(t(lx + 222, y + 38, '&#8594;', 28, CREAM, weight=600, opacity=0.55))
        o.append(t(lx + 262, y + 38, now, 30, CREAM, weight=800, spacing=0.6))
        y += 90
    y += 14
    o.append(t(lx, y, 'KEY', 40, AMBER, weight=800, spacing=3))
    y += 22
    key = [('ring', 'Ring of frame; the number is its floors. Its top is a terrace'),
           ('aisle', 'Stair aisle up the terraces, wide enough for the Counter'),
           ('slide', 'Tube slide down the steps, one colour each'),
           ('bridge', 'Net bridge over the court'),
           ('lane', 'The way in: the only straight line in the level')]
    for kind, text in key:
        y += 54
        if kind == 'ring':
            for i, c in enumerate((TINT[0], TINT[2], TINT[5])):
                o.append(f'<rect x="{lx + i * 22}" y="{y - 28}" width="22" height="36" fill="#0C1216"/><rect x="{lx + i * 22}" y="{y - 28}" width="22" height="36" fill="{c}" opacity="0.5"/>')
            o.append(f'<rect x="{lx}" y="{y - 28}" width="66" height="36" fill="none" stroke="{CREAM}" stroke-width="2"/>')
        elif kind == 'aisle':
            o.append(f'<rect x="{lx}" y="{y - 22}" width="66" height="24" rx="12" fill="#3A5D80"/>'
                     + ''.join(f'<path d="M{lx + 12 + i * 11} {y - 20} v20" stroke="{BG}" stroke-width="1.6" opacity="0.6"/>' for i in range(5)))
        elif kind == 'slide':
            o.append(f'<path d="M{lx + 4} {y - 2} q28 -34 58 -6" stroke="{BG}" stroke-width="20" fill="none" stroke-linecap="round"/>'
                     f'<path d="M{lx + 4} {y - 2} q28 -34 58 -6" stroke="{POSTS[1]}" stroke-width="15" fill="none" stroke-linecap="round"/>')
        elif kind == 'bridge':
            o.append(f'<rect x="{lx}" y="{y - 17}" width="66" height="13" fill="#E9A45A"/>'
                     f'<path d="M{lx} {y - 10} h66" stroke="{BG}" stroke-width="13" stroke-dasharray="3 8" opacity="0.7"/>')
        else:
            o.append(f'<rect x="{lx}" y="{y - 26}" width="66" height="32" fill="#1C3458" stroke="{CREAM}" stroke-width="2"/>'
                     f'<path d="M{lx + 8} {y - 10} h44" stroke="{CREAM}" stroke-width="3" stroke-dasharray="8 7" marker-end="url(#arrow)"/>')
        o.append(t(lx + 90, y, text, 26, CREAM, weight=600, spacing=0.5))
    y += 78
    o.append(t(lx, y, 'FOUR WAYS OUT AFTER THE THIRD TOUCH', 40, AMBER, weight=800, spacing=3))
    ways = [('A', 'THE BIG SLIDE', 'climb to the top; the slide carries you out through the wall'),
            ('B', 'BACK THE WAY YOU CAME', 'the gate opens again; the tunnel is too low for the Counter'),
            ('C', 'UNDER THE POST', 'the post sinks and leaves a chute, in the middle of everything'),
            ('D', 'A FIRE DOOR', 'one of four doors high in the wall unlocks, a different one each time')]
    y += 16
    for letter, name, text in ways:
        y += 70
        o.append(f'<circle cx="{lx + 24}" cy="{y - 12}" r="24" fill="{GREEN}"/>')
        o.append(f'<text x="{lx + 24}" y="{y - 12}" font-size="30" fill="{BG}" text-anchor="middle" font-weight="800" dominant-baseline="central">{letter}</text>')
        o.append(t(lx + 66, y - 16, name, 28, CREAM, weight=800, spacing=1.5))
        o.append(t(lx + 66, y + 14, text, 23, CREAM, weight=600, spacing=0.4, opacity=0.8))

    by = high - 62
    o.append(f'<path d="M90 {by} h{100 * S} M90 {by - 12} v24 M{90 + 100 * S} {by - 12} v24" stroke="{CREAM}" stroke-width="4"/>')
    o.append(t(90 + 100 * S + 24, by + 10, '100 studs: about 6 seconds at a walk, 4 at a sprint', 28, CREAM, weight=600, spacing=1))
    page('plan_arena', wide, high, ''.join(o))


# ====================================================================== the side view
def section(facts):
    E, wide, high = 3.4, 3040, 1940
    o = []

    def box(base, ground, x0, x1, h0, h1, **style):
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        o.append(f'<rect x="{base + x0 * E:.1f}" y="{ground - h1 * E:.1f}" width="{(x1 - x0) * E:.1f}" height="{(h1 - h0) * E:.1f}" {attrs}/>')

    def block(base, ground, x0, x1, n, tint, alpha=1.0, pitch=13):
        top = n * FLOOR
        o.append(f'<g opacity="{alpha}">')
        box(base, ground, x0, x1, 0, top, fill='#0C1216')
        box(base, ground, x0, x1, 0, top, fill=tint, opacity=0.34)
        box(base, ground, x0, x1, 0, top, fill='url(#enet)')
        mats = ['#D8342A', '#2A62D8', '#2FA04A', '#F2C21A']
        for k in range(1, n):
            x, i = x0, 0
            while x < x1 - 0.1:
                box(base, ground, x, min(x + pitch * 2, x1), k * FLOOR - 0.8, k * FLOOR + 0.8, fill=mats[(k + i) % 4])
                x += pitch * 2
                i += 1
        x, i = x0, 0
        while x <= x1 + 0.1:
            o.append(f'<path d="M{base + x * E:.1f} {ground:.1f} V{ground - top * E:.1f}" stroke="{POSTS[i % 4]}" stroke-width="3"/>')
            x += pitch
            i += 1
        o.append(f'<path d="M{base + x0 * E:.1f} {ground - top * E:.1f} H{base + x1 * E:.1f}" stroke="{CREAM}" stroke-width="2.6"/>')
        o.append('</g>')

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

    def figure(base, ground, x, h, tall, colour):
        head = tall * 0.24
        box(base, ground, x - tall * 0.16, x + tall * 0.16, h, h + tall - head, fill=colour)
        o.append(f'<circle cx="{base + x * E:.1f}" cy="{ground - (h + tall - head / 2) * E:.1f}" r="{head * E / 2:.1f}" fill="{colour}"/>')

    def rise(base, ground, x, h, label, side=1):
        px = base + x * E
        o.append(f'<path d="M{px:.1f} {ground:.1f} V{ground - h * E:.1f} M{px - 9:.1f} {ground:.1f} h18 M{px - 9:.1f} {ground - h * E:.1f} h18" '
                 f'stroke="{AMBER}" stroke-width="3"/>')
        o.append(t(px + side * 16, ground - h * E / 2 + 9, label, 27, AMBER, 'start' if side > 0 else 'end', 800, 1))

    def sight(base, ground, x, h, alpha=0.8):
        o.append(f'<path d="M{base + x * E:.1f} {ground - h * E:.1f} L{base:.1f} {ground - 5 * E:.1f}" stroke="{TEAL}" stroke-width="2.4" '
                 f'stroke-dasharray="12 9" opacity="{alpha}"/>')

    def middle(base, ground):
        box(base, ground, -COURT, COURT, 0, 0.9, fill=AMBER)
        box(base, ground, -1.6, 1.6, 0, 6, fill=CORAL)
        figure(base, ground, 9, 0, 8.2, '#E9DCC8')

    o.append(f'<defs><pattern id="enet" width="{2 * E}" height="{2 * E}" patternUnits="userSpaceOnUse">'
             f'<path d="M0 0 H{2 * E} M0 0 V{2 * E}" stroke="{CREAM}" stroke-width="0.6" opacity="0.26"/></pattern></defs>')
    o.append(t(90, 110, 'LEVEL 6  ·  THE ARENA FROM THE SIDE, SAME SCALE', 60, CREAM, weight=800, spacing=3))
    o.append(t(90, 170, 'Each ring is two floors taller than the one in front of it, so the front of every terrace looks down on the post.',
               33, TEAL, weight=600, spacing=1))

    # ---- row 1: today, and the bowl
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
    for n in range(RINGS, 0, -1):
        r0, r1 = COURT + RING * (n - 1), COURT + RING * n
        block(b, g1, -r1, -r0, floors(n), TINT[n - 1])
        block(b, g1, r0, r1, floors(n), TINT[n - 1])
    middle(b, g1)
    for n in range(1, RINGS + 1):
        sight(b, g1, -(COURT + RING * (n - 1)), floors(n) * FLOOR + 4)
    figure(b, g1, -(COURT + RING * (RINGS - 1)) - 3, floors(RINGS) * FLOOR, 5, '#F2C21A')
    figure(b, g1, -(COURT + RING * 2) - 3, floors(3) * FLOOR, 5, '#F2C21A')
    # the big slide leaves through the wall; an orange one comes down the steps into the court
    d = ' L'.join(f'{b + x * E:.1f} {g1 - h * E:.1f}' for x, h in
                  [(254, 124), (268, 116), (252, 106), (268, 96), (252, 86), (268, 78), (286, 74), (304, 73)])
    o.append(f'<path d="M{d}" stroke="{BG}" stroke-width="19" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
    o.append(f'<path d="M{d}" stroke="#D8342A" stroke-width="14" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
    d = ' L'.join(f'{b + x * E:.1f} {g1 - h * E:.1f}' for x, h in [(152, 62), (122, 46), (104, 40), (84, 26), (66, 20), (48, 3)])
    o.append(f'<path d="M{d}" stroke="{BG}" stroke-width="17" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
    o.append(f'<path d="M{d}" stroke="#E07B2A" stroke-width="12" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
    rise(b, g1, -WALL - 10, ROOF, str(ROOF), -1)
    o.append(t(b - (FRAME - RING / 2 + 6) * E, g1 - floors(RINGS) * FLOOR * E - 18, '120 studs', 25, AMBER, 'middle', 800, 1))
    o.append(t(b - WALL * E, g1 - ROOF * E - 46, 'NEW DRAFT: THE BOWL', 44, AMBER, weight=800, spacing=4))
    o.append(t(b - WALL * E + 640, g1 - ROOF * E - 46, 'cut through the middle of the hall, wall to wall', 28, CREAM, weight=600, spacing=1, opacity=0.7))
    for n in range(1, RINGS + 1):
        for side in (-1, 1):
            o.append(t(b + side * (COURT + RING * (n - 0.5)) * E, g1 + 52, str(floors(n)), 30, TINT[n - 1], 'middle', 800, 1))
    o.append(t(b, g1 + 52, 'THE POST', 26, CREAM, 'middle', 800, 2))
    o.append(t(b, g1 + 86, 'floors in each ring  ·  the Counter (8 studs) at the post  ·  players (5 studs) on two terraces  ·  dashed: what they see',
               23, CREAM, 'middle', 600, 0.6, 0.75))
    o.append(t(b + (WALL + 8) * E, g1 - 73 * E - 26, 'OUT', 26, GREEN, 'start', 800, 2))

    # ---- row 2: the other way to build it
    g2 = 1570
    hall(b, g2, -WALL, WALL, ROOF)
    block(b, g2, -FRAME, -COURT, floors(RINGS), TINT[5])
    block(b, g2, COURT, FRAME, floors(RINGS), TINT[5])
    middle(b, g2)
    for h in (34, 64, 94, 124):
        sight(b, g2, -COURT, h)
    figure(b, g2, -COURT - 3, 90, 5, '#F2C21A')
    figure(b, g2, -180, 120, 5, '#F2C21A')
    o.append(t(b - WALL * E, g2 - ROOF * E - 46, 'THE OTHER WAY TO BUILD IT: THE WELL', 44, CREAM, weight=800, spacing=4))
    lines = ['Twelve floors straight up from the edge of the court,',
             'like the picture of the court you liked, only twice as high.',
             '',
             'It looks taller from the court. But only the galleries on',
             'the inner face see the post; from anywhere behind them,',
             'or on the roof, you see nothing of it.',
             '',
             f'It is also about {facts["well_over_bowl_percent"]}% more structure to build and to run.']
    for i, line in enumerate(lines):
        o.append(t(90, g2 - 400 + i * 44, line, 31, CREAM, weight=600, spacing=0.6, opacity=0.9))
    o.append(t(b, g2 + 52, 'THE POST', 26, CREAM, 'middle', 800, 2))

    fy = high - 150
    cells = [(f'{TODAY["roof"]} &#8594; {ROOF}', 'studs up to the roof'), (f'3 &#8594; {facts["top_floor"]}', 'floors at the wall'),
             (f'{facts["frame_share_today"]}% &#8594; {facts["frame_share"]}%', 'of the floor is frame'),
             (f'{facts["cells_today"]} &#8594; {facts["cells_bowl"]:,}'.replace(',', ' '), 'cells of frame (12 x 12 studs, per floor)')]
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
