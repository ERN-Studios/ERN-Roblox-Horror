"""Level 6 concept v3: the floor plan of the proposed layout, drawn to scale.

Writes SVG and PNG (headless Chrome) to artifacts/level6-concept-20261005/plan:
  plan_new.png        the proposed hall, 864 x 576 studs
  before_after.png    today's hall and the proposed one at the same scale
  height_before_after.png   the same two from the side

Nothing here builds the level. The numbers in NEW are the proposal the Blender
build would start from once the owner has approved the draft.

    python3 tools/level6_playground/concept_v3/draw_plan.py
"""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'artifacts' / 'level6-concept-20261005' / 'plan'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"

BG, CREAM, TEAL, AMBER, CORAL = '#161D20', '#F3ECDA', '#4FADAA', '#EDA827', '#F2725D'
POSTS = ['#F2C21A', '#D8342A', '#2A62D8', '#2FA04A']

# ------------------------------------------------------------------ today's map (build_playground.py)
OLD = {
    'size': (600, 400),
    'zones': [
        ('RECEPTION', (0, 0, 150, 108), '#B8587C'),
        ('SNACK SHACK', (0, 132, 150, 288), '#D98A34'),
        ('PARTY ROOMS', (0, 312, 174, 400), '#7E5AC2'),
        ('ARCADE', (186, 330, 330, 400), '#4B58CC'),
        ('PRIZES', (330, 330, 432, 400), '#C2568F'),
        ('STAFF ONLY', (444, 304, 600, 400), '#B99A2E'),
        ('TODDLER TOWN', (168, 12, 312, 120), '#D46F9B'),
        ('INFLATABLES', (504, 12, 600, 288), '#3A8FCC'),
    ],
    'frame': [[(336, 128), (480, 128), (480, 296), (336, 296)]],
    'pit': (330, 12, 486, 120),
    'home': (236, 214, 26),
    'entrance': (54, 78),
    'exit': (576, 588),
    'removed': [(186, 330, 432, 400)],
}

# ------------------------------------------------------------------ the proposal
NEW = {
    'size': (864, 576),
    'roof': 120,          # was 46; the frame's floors stay 10 studs apart, there are just far more of them
    'zones': [
        ('RECEPTION', (0, 0, 180, 120), '#B8587C'),
        ('SNACK SHACK', (0, 144, 156, 348), '#D98A34'),
        ('PARTY ROOMS', (0, 444, 204, 576), '#7E5AC2'),
        ('STAFF ONLY', (672, 444, 864, 576), '#B99A2E'),
        ('TODDLER TOWN', (216, 0, 432, 96), '#D46F9B'),
        ('INFLATABLES', (768, 0, 864, 420), '#3A8FCC'),
        ('INFLATABLES', (612, 0, 768, 96), '#3A8FCC'),
    ],
    # one outline: the main block and the north wing that takes the arcade's wall
    'frame': [[(192, 120), (744, 120), (744, 456), (648, 456), (648, 576), (228, 576), (228, 456), (192, 456)]],
    'wings': [    # name, rect, tint, storeys, where the label sits
        ('NET MAZE', (192, 120, 396, 456), '#F2C21A', '6 FLOORS', (300, 196)),
        ('TUBE TOWN', (228, 456, 648, 576), '#D8342A', '7 FLOORS', (438, 530)),
        ('TUBE TOWN', (396, 384, 648, 456), '#D8342A', '', None),
        ('FOAM FOREST', (564, 216, 744, 384), '#2FA04A', '6 FLOORS', (668, 352)),
        ('THE TOWER', (648, 384, 744, 456), '#E07B2A', '10 FLOORS', (690, 404)),
        ('BALL OCEAN', (396, 120, 744, 216), '#2A62D8', 'SUNK PIT + BRIDGES', (640, 150)),
        ('COUNTING COURT', (396, 216, 564, 384), '#8A8F96', '', None),
    ],
    'pit': (492, 134, 708, 204),
    'home': (468, 290, 44),
    # the lanes wide and tall enough for the Counter; every one turns before it gets long
    'streets': [
        [(192, 252), (288, 252), (288, 304), (372, 304), (372, 290), (426, 290)],
        [(444, 120), (444, 178), (410, 178), (410, 232), (454, 232), (454, 250)],
        [(744, 316), (668, 316), (668, 262), (590, 262), (590, 290), (510, 290)],
        [(468, 332), (468, 366), (524, 366), (524, 430), (482, 430), (482, 500), (566, 500), (566, 548)],
        [(288, 304), (288, 410), (398, 410), (398, 366), (468, 366)],
        [(668, 316), (668, 392)],
        [(482, 500), (330, 500), (330, 456)],
    ],
    'gates': [('WEST GATE', (192, 252), 'w'), ('SOUTH GATE', (444, 120), 's'), ('EAST GATE', (744, 316), 'e')],
    'slides': [   # colour, path points (drawn as a smooth curve)
        ('#D8342A', [(712, 446), (728, 454), (742, 446), (740, 432), (726, 430), (722, 442), (738, 450), (756, 440), (758, 414), (756, 392)]),
        ('#F2C21A', [(604, 252), (612, 232), (600, 214), (604, 196)]),
        ('#2A62D8', [(300, 532), (262, 540), (224, 522), (214, 488)]),
        ('#2FA04A', [(232, 172), (222, 150), (230, 124), (224, 106)]),
        ('#E07B2A', [(520, 480), (506, 452), (486, 410), (480, 340)]),
    ],
    'bridges': [[(330, 346), (430, 346)], [(520, 150), (520, 204)], [(660, 140), (660, 204)], [(560, 420), (640, 420)]],
    'entrance': (60, 96),
    'exit': (822, 846),
}


def area(poly):
    return abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(poly, poly[1:] + poly[:1]))) / 2


def numbers(m):
    w, d = m['size']
    frame = sum(area(p) for p in m['frame'])
    return {'hall': (w, d), 'floor': w * d, 'frame': frame, 'share': frame / (w * d)}


class Sheet:
    """One layout at a scale, with y pointing north."""

    def __init__(self, m, scale, ox, oy):
        self.m, self.s, self.ox, self.oy = m, scale, ox, oy
        self.w, self.d = m['size']
        self.out = []

    def p(self, x, y):
        return self.ox + x * self.s, self.oy + (self.d - y) * self.s

    def rect(self, r, **style):
        x0, y0 = self.p(r[0], r[3])
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        self.out.append(f'<rect x="{x0:.1f}" y="{y0:.1f}" width="{(r[2] - r[0]) * self.s:.1f}" '
                        f'height="{(r[3] - r[1]) * self.s:.1f}" {attrs}/>')

    def path(self, pts, close=False, **style):
        d = 'M' + ' L'.join(f'{x:.1f} {y:.1f}' for x, y in (self.p(*q) for q in pts)) + (' Z' if close else '')
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        self.out.append(f'<path d="{d}" {attrs}/>')

    def curve(self, pts, **style):
        q = [self.p(*a) for a in pts]
        d = f'M{q[0][0]:.1f} {q[0][1]:.1f}'
        for i in range(len(q) - 1):      # Catmull-Rom through the points
            p0, p1, p2, p3 = q[max(i - 1, 0)], q[i], q[i + 1], q[min(i + 2, len(q) - 1)]
            c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
            c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
            d += f' C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}'
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        self.out.append(f'<path d="{d}" fill="none" {attrs}/>')

    def text(self, x, y, s, size, fill=CREAM, anchor='middle', weight=700, spacing=1.5, opacity=1.0):
        px, py = self.p(x, y)
        self.out.append(f'<text x="{px:.1f}" y="{py:.1f}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" '
                        f'font-weight="{weight}" letter-spacing="{spacing}" opacity="{opacity}" '
                        f'dominant-baseline="middle">{s}</text>')

    def tag(self, x, y, s, size, fill, ink=BG, sub=None):
        px, py = self.p(x, y)
        w = max(len(s), len(sub or '') * 0.62) * size * 0.60 + size * 1.1
        h = size * (2.55 if sub else 1.7)
        self.out.append(f'<rect x="{px - w / 2:.1f}" y="{py - h / 2:.1f}" width="{w:.1f}" height="{h:.1f}" '
                        f'rx="{size * 0.45:.1f}" fill="{fill}" stroke="{BG}" stroke-width="2"/>')
        self.out.append(f'<text x="{px:.1f}" y="{py - (size * 0.38 if sub else 0):.1f}" font-size="{size}" fill="{ink}" '
                        f'text-anchor="middle" font-weight="800" letter-spacing="1.5" dominant-baseline="middle">{s}</text>')
        if sub:
            self.out.append(f'<text x="{px:.1f}" y="{py + size * 0.72:.1f}" font-size="{size * 0.62:.1f}" fill="{ink}" '
                            f'text-anchor="middle" font-weight="700" letter-spacing="1.2" opacity="0.8" '
                            f'dominant-baseline="middle">{sub}</text>')

    # --------------------------------------------------------------
    def draw(self, uid, detail=True, label=14):
        m, s = self.m, self.s
        tile = 12 * s
        x0, y0 = self.p(0, self.d)
        self.out.append(
            f'<defs><pattern id="floor{uid}" x="{x0:.1f}" y="{y0:.1f}" width="{tile * 2:.2f}" height="{tile * 2:.2f}" '
            f'patternUnits="userSpaceOnUse"><rect width="{tile * 2:.2f}" height="{tile * 2:.2f}" fill="#1C3458"/>'
            f'<rect width="{tile:.2f}" height="{tile:.2f}" fill="#1D5238"/>'
            f'<rect x="{tile:.2f}" y="{tile:.2f}" width="{tile:.2f}" height="{tile:.2f}" fill="#1D5238"/></pattern>'
            f'<pattern id="net{uid}" x="{x0:.1f}" y="{y0:.1f}" width="{tile:.2f}" height="{tile:.2f}" '
            f'patternUnits="userSpaceOnUse"><path d="M0 0 H{tile:.2f} M0 0 V{tile:.2f}" stroke="{CREAM}" '
            f'stroke-width="{max(0.6, s * 0.35):.2f}" opacity="0.30"/></pattern>'
            f'<pattern id="hatch{uid}" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
            f'<rect width="14" height="14" fill="#000" opacity="0.55"/><rect width="5" height="14" fill="{CORAL}"/></pattern>'
            f'<clipPath id="clip{uid}">'
            + ''.join('<path d="M' + ' L'.join(f'{a:.1f} {b:.1f}' for a, b in (self.p(*q) for q in poly)) + ' Z"/>'
                      for poly in m['frame']) + '</clipPath></defs>')
        self.rect((0, 0, self.w, self.d), fill=f'url(#floor{uid})')

        for name, r, colour in m['zones']:
            self.rect(r, fill=colour, opacity=0.88, rx=6)

        # the frame: dark decks, wing tints, net lines and a padded post on every corner
        for poly in m['frame']:
            self.path(poly, close=True, fill='#0C1216')
        self.out.append(f'<g clip-path="url(#clip{uid})">')
        for name, r, colour, storeys, at in m.get('wings', []):
            self.rect(r, fill=colour, opacity=0.30)
        if not m.get('wings'):
            for poly in m['frame']:
                self.path(poly, close=True, fill='#F2C21A', opacity=0.30)
        self.rect((0, 0, self.w, self.d), fill=f'url(#net{uid})')
        if detail:
            xs = sorted({q[0] for poly in m['frame'] for q in poly})
            ys = sorted({q[1] for poly in m['frame'] for q in poly})
            n = 0
            for gx in range(int(xs[0]), int(xs[-1]) + 1, 12):
                for gy in range(int(ys[0]), int(ys[-1]) + 1, 12):
                    px, py = self.p(gx, gy)
                    self.out.append(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{max(1.2, s * 0.9):.1f}" '
                                    f'fill="{POSTS[(gx // 12 * 3 + gy // 12) % 4]}" opacity="0.9"/>')
                    n += 1
        self.out.append('</g>')

        if m.get('pit'):
            self.rect(m['pit'], fill='#17408F', stroke='#2A62D8', stroke_width=max(2, s * 2.2), rx=10 * s)
            px0, py0, px1, py1 = m['pit']
            for k in range(46 if detail else 20):
                bx = px0 + 8 + (k * 37.7) % (px1 - px0 - 16)
                by = py0 + 8 + (k * 23.3 + (k % 5) * 9) % (py1 - py0 - 16)
                cx, cy = self.p(bx, by)
                self.out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{max(1.5, s * 1.3):.1f}" '
                                f'fill="{[POSTS[0], POSTS[1], "#3F9BD8", POSTS[3], "#E07B2A"][k % 5]}"/>')

        for line in m.get('streets', []):
            self.path(line, fill='none', stroke='#27425F', stroke_width=14 * s, stroke_linejoin='round',
                      stroke_linecap='round')
        for line in m.get('streets', []):
            self.path(line, fill='none', stroke=CREAM, stroke_width=max(1.2, s * 0.7), stroke_dasharray=f'{s * 4:.1f} {s * 4:.1f}',
                      stroke_linejoin='round', opacity=0.55)

        hx, hy, hr = m['home']
        cx, cy = self.p(hx, hy)
        self.out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{hr * s:.1f}" fill="{AMBER}" stroke="{BG}" stroke-width="3"/>')
        self.out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{hr * s * 0.62:.1f}" fill="none" stroke="{BG}" '
                        f'stroke-width="2" stroke-dasharray="8 7" opacity="0.6"/>')
        self.out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{max(4, s * 3):.1f}" fill="{CORAL}" stroke="{BG}" stroke-width="2"/>')

        for line in m.get('bridges', []):
            self.path(line, fill='none', stroke='#E9A45A', stroke_width=5 * s, stroke_linecap='butt', opacity=0.95)
            self.path(line, fill='none', stroke=BG, stroke_width=5 * s, stroke_dasharray=f'{s * 1.2:.1f} {s * 3.2:.1f}', opacity=0.75)
        for colour, pts in m.get('slides', []):
            self.curve(pts, stroke=BG, stroke_width=9.5 * s, stroke_linecap='round')
            self.curve(pts, stroke=colour, stroke_width=7 * s, stroke_linecap='round')
            self.curve(pts, stroke='#FFFFFF', stroke_width=1.4 * s, stroke_linecap='round', opacity=0.35)

        for poly in m['frame']:
            self.path(poly, close=True, fill='none', stroke=CREAM, stroke_width=max(2.5, s * 1.6), stroke_linejoin='round')

        for r in m.get('removed', []):
            self.rect(r, fill=f'url(#hatch{uid})', stroke=CORAL, stroke_width=4, rx=6)

        self.rect((0, 0, self.w, self.d), fill='none', stroke=CREAM, stroke_width=max(5, s * 3.4))

        # labels
        seen = set()
        for name, r, colour in m['zones']:
            if name in seen or any(c[0] <= r[0] and r[2] <= c[2] and c[1] <= r[1] and r[3] <= c[3] for c in m.get('removed', [])):
                continue
            seen.add(name)
            self.tag((r[0] + r[2]) / 2, (r[1] + r[3]) / 2, name, label, CREAM)
        for name, r, colour, storeys, at in m.get('wings', []):
            if at:
                self.tag(at[0], at[1], name, label * 1.12, colour, BG, storeys)
        if m.get('wings'):
            self.tag(hx, hy + 20, 'HOME BASE', label * 1.05, BG, AMBER, 'THE COUNTING COURT')
        else:
            (fx0, fy0), (fx1, fy1) = m['frame'][0][0], m['frame'][0][2]
            self.tag((fx0 + fx1) / 2, (fy0 + fy1) / 2, 'THE BIG FRAME', label, POSTS[0])
            self.tag((m['pit'][0] + m['pit'][2]) / 2, (m['pit'][1] + m['pit'][3]) / 2, 'BALL OCEAN', label, '#2A62D8', CREAM)
            self.tag(hx, hy - hr - 16, 'HOME BASE', label, BG, AMBER)

        for name, (gx, gy), side in m.get('gates', []):
            dx, dy = {'w': (-1, 0), 'e': (1, 0), 's': (0, -1)}[side]
            ax, ay = self.p(gx + dx * 20, gy + dy * 20)
            bx, by = self.p(gx + dx * 3, gy + dy * 3)
            self.out.append(f'<path d="M{ax:.1f} {ay:.1f} L{bx:.1f} {by:.1f}" stroke="{CREAM}" stroke-width="{s * 2.4:.1f}" '
                            f'marker-end="url(#arrow)"/>')
            off = {'w': (-30, 24), 'e': (34, 24), 's': (56, -15)}[side]
            self.tag(gx + off[0], gy + off[1], name, label * 0.8, BG, CREAM)

        e0, e1 = m['entrance']
        self.rect((e0, -5, e1, 5), fill=TEAL, stroke=BG, stroke_width=2)
        self.text((e0 + e1) / 2, -18, 'ENTRANCE', label, TEAL, weight=800)
        x0, x1 = m['exit']
        self.rect((x0, self.d - 5, x1, self.d + 5), fill=CORAL, stroke=BG, stroke_width=2)
        self.text((x0 + x1) / 2, self.d + 18, 'EXIT', label, CORAL, weight=800)
        return '\n'.join(self.out)


DEFS = (f'<defs><marker id="arrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="5" markerHeight="5" '
        f'orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="{CREAM}"/></marker></defs>')


def page(name, width, height, body):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" '
           f'font-family="{FONT}"><rect width="{width}" height="{height}" fill="{BG}"/>{DEFS}{body}</svg>')
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f'{name}.svg').write_text(svg)
    html = OUT / f'{name}.html'
    html.write_text(f'<html><body style="margin:0;background:{BG}">{svg}</body></html>')
    target = OUT / f'{name}.png'
    target.unlink(missing_ok=True)
    subprocess.run([CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    f'--window-size={width},{height}', f'--screenshot={target}', f'file://{html}'], capture_output=True)
    html.unlink()
    print(target, target.exists())


def t(x, y, s, size, fill=CREAM, anchor='start', weight=700, spacing=1.5, opacity=1.0):
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}" '
            f'letter-spacing="{spacing}" opacity="{opacity}">{s}</text>')


def main():
    old, new = numbers(OLD), numbers(NEW)
    facts = {
        'hall_old': OLD['size'], 'hall_new': NEW['size'], 'floor_factor': round(new['floor'] / old['floor'], 2),
        'frame_old_sq': old['frame'], 'frame_new_sq': new['frame'], 'frame_factor': round(new['frame'] / old['frame'], 1),
        'frame_share_old': round(old['share'] * 100, 1), 'frame_share_new': round(new['share'] * 100, 1),
        'roof_old': 46, 'roof_new': NEW['roof'],
    }
    (OUT / 'numbers.json').parent.mkdir(parents=True, exist_ok=True)
    (OUT / 'numbers.json').write_text(json.dumps(facts, indent=1))
    print(facts)

    # ---------------------------------------------------------- the proposal on its own
    S, OX, OY = 2.5, 90, 250
    width, height = 3040, 1830
    plan = Sheet(NEW, S, OX, OY).draw('n', True, 30)
    lx = OX + 864 * S + 70
    side = [
        t(OX, 110, 'LEVEL 6  ·  INDOOR PLAYGROUND  ·  NEW LAYOUT, DRAFT', 62, CREAM, weight=800, spacing=3),
        t(OX, 172, f'The Big Frame is the map now: {facts["frame_share_new"]:.0f}% of the floor and up to ten floors high, '
                   f'with Home Base in the middle of it. The arcade is gone.', 34, TEAL, weight=600, spacing=1),
        t(lx, 300, 'WHAT CHANGES', 40, AMBER, weight=800, spacing=3),
    ]
    rows = [
        ('HALL', f'{OLD["size"][0]} x {OLD["size"][1]}', f'{NEW["size"][0]} x {NEW["size"][1]} studs'),
        ('FLOOR', '', f'{facts["floor_factor"]:.1f}x bigger'),
        ('THE BIG FRAME', f'{facts["frame_share_old"]:.0f}% of the floor', f'{facts["frame_share_new"]:.0f}% of the floor'),
        ('FRAME FOOTPRINT', '', f'{facts["frame_factor"]:.1f}x bigger'),
        ('FLOORS IN THE FRAME', '3', '6 to 10'),
        ('ROOF', '46 studs', f'{NEW["roof"]} studs'),
        ('LONGEST SLIDE DROP', '20 studs', '100 studs'),
        ('ARCADE + PRIZES', 'north wall', 'removed'),
        ('BALL OCEAN', 'beside the frame', 'sunk inside it'),
        ('HOME BASE', 'open hall', 'court inside the frame'),
    ]
    y = 366
    for head, was, now in rows:
        side.append(t(lx, y, head, 25, CREAM, weight=800, spacing=2, opacity=0.62))
        if was:
            side.append(t(lx, y + 40, was, 30, CREAM, weight=600, spacing=1, opacity=0.55))
            side.append(t(lx + 232, y + 40, '&#8594;', 30, CREAM, weight=600, opacity=0.55))
            side.append(t(lx + 276, y + 40, now, 32, CREAM, weight=800, spacing=1))
        else:
            side.append(t(lx, y + 40, now, 32, CREAM, weight=800, spacing=1))
        y += 96
    y += 14
    side.append(t(lx, y, 'KEY', 40, AMBER, weight=800, spacing=3))
    y += 30
    key = [
        ('net', 'Net fences and padded posts: the frame'),
        ('street', 'Lane the Counter can walk; none runs straight'),
        ('bridge', 'Net bridge on an upper floor'),
        ('slide', 'Tube or open slide, one colour each'),
        ('pit', 'Ball Ocean: almost empty, a few loose balls'),
        ('home', 'Home Base and the post'),
    ]
    for kind, text in key:
        y += 58
        if kind == 'net':
            side.append(f'<rect x="{lx}" y="{y - 30}" width="64" height="40" fill="#0C1216" stroke="{CREAM}" stroke-width="2.5"/>'
                        f'<path d="M{lx + 21} {y - 30} v40 M{lx + 43} {y - 30} v40 M{lx} {y - 10} h64" stroke="{CREAM}" opacity="0.4"/>'
                        f'<circle cx="{lx + 21}" cy="{y - 10}" r="4" fill="{POSTS[0]}"/><circle cx="{lx + 43}" cy="{y - 10}" r="4" fill="{POSTS[1]}"/>')
        elif kind == 'street':
            side.append(f'<rect x="{lx}" y="{y - 24}" width="64" height="28" rx="14" fill="#27425F"/>'
                        f'<path d="M{lx + 8} {y - 10} h48" stroke="{CREAM}" stroke-width="2" stroke-dasharray="8 8" opacity="0.6"/>')
        elif kind == 'bridge':
            side.append(f'<rect x="{lx}" y="{y - 17}" width="64" height="13" fill="#E9A45A"/>'
                        f'<path d="M{lx} {y - 10} h64" stroke="{BG}" stroke-width="13" stroke-dasharray="3 8" opacity="0.75"/>')
        elif kind == 'slide':
            side.append(f'<path d="M{lx + 4} {y - 2} q28 -34 56 -6" stroke="{BG}" stroke-width="20" fill="none" stroke-linecap="round"/>'
                        f'<path d="M{lx + 4} {y - 2} q28 -34 56 -6" stroke="{POSTS[1]}" stroke-width="15" fill="none" stroke-linecap="round"/>')
        elif kind == 'pit':
            side.append(f'<rect x="{lx}" y="{y - 30}" width="64" height="40" rx="12" fill="#17408F" stroke="#2A62D8" stroke-width="5"/>'
                        f'<circle cx="{lx + 20}" cy="{y - 6}" r="4" fill="{POSTS[0]}"/><circle cx="{lx + 42}" cy="{y - 16}" r="4" fill="{POSTS[1]}"/>')
        else:
            side.append(f'<circle cx="{lx + 32}" cy="{y - 10}" r="21" fill="{AMBER}"/><circle cx="{lx + 32}" cy="{y - 10}" r="7" fill="{CORAL}"/>')
        side.append(t(lx + 88, y, text, 27, CREAM, weight=600, spacing=0.6))

    # scale bar under the plan
    by = OY + 576 * S + 92
    side.append(f'<path d="M{OX} {by} h{100 * S} M{OX} {by - 12} v24 M{OX + 100 * S} {by - 12} v24" stroke="{CREAM}" stroke-width="4"/>')
    side.append(t(OX + 100 * S + 24, by + 10, '100 studs: about 6 seconds at a walk, 4 at a sprint', 28, CREAM, weight=600, spacing=1))
    side.append(t(OX + 864 * S, by + 10, 'north is up  ·  one net square = 12 studs', 28, CREAM, 'end', 600, 1, 0.7))
    page('plan_new', width, height, plan + ''.join(side))

    # ---------------------------------------------------------- before and after, same scale
    S = 1.78
    gap, OX, OY = 130, 90, 300
    width = int(OX * 2 + (600 + 864) * S + gap)
    height = int(OY + 576 * S + 290)
    a = Sheet(OLD, S, OX, OY + (576 - 400) * S).draw('a', True, 21)
    bx = OX + 600 * S + gap
    b = Sheet(NEW, S, bx, OY).draw('b', True, 21)
    extra = [
        t(OX, 110, 'LEVEL 6  ·  TODAY AND THE NEW DRAFT, SAME SCALE', 60, CREAM, weight=800, spacing=3),
        t(OX, 170, 'The hall grows to twice the floor. The arcade goes, and the frame takes its wall and the middle of the hall.',
          33, TEAL, weight=600, spacing=1),
        t(OX, OY + (576 - 400) * S - 34, 'TODAY', 44, CREAM, weight=800, spacing=4),
        t(OX + 172, OY + (576 - 400) * S - 34, f'{OLD["size"][0]} x {OLD["size"][1]} studs  ·  the frame is {facts["frame_share_old"]:.0f}% of the floor',
          30, CREAM, weight=600, spacing=1, opacity=0.7),
        t(bx, OY - 34, 'NEW DRAFT', 44, AMBER, weight=800, spacing=4),
        t(bx + 268, OY - 34, f'{NEW["size"][0]} x {NEW["size"][1]} studs  ·  the frame is {facts["frame_share_new"]:.0f}% of the floor',
          30, CREAM, weight=600, spacing=1, opacity=0.7),
    ]
    ax, ay = OX + 309 * S, OY + (576 - 400) * S + (400 - 365) * S
    extra.append(f'<rect x="{ax - 196}" y="{ay - 27}" width="392" height="54" rx="10" fill="{CORAL}" stroke="{BG}" stroke-width="2"/>')
    extra.append(t(ax, ay + 11, 'ARCADE + PRIZES: REMOVED', 28, BG, 'middle', 800, 2))
    fy = OY + 576 * S + 176
    cells = [
        (f'{facts["floor_factor"]:.1f}x', 'the floor'),
        (f'{facts["frame_factor"]:.1f}x', "the frame's footprint"),
        (f'{facts["frame_share_old"]:.0f}% &#8594; {facts["frame_share_new"]:.0f}%', 'of the floor is frame'),
        ('3 &#8594; 10', 'floors at the highest point'),
        ('46 &#8594; 120', 'studs up to the roof'),
    ]
    step = (width - OX * 2) / len(cells)
    for i, (big, small) in enumerate(cells):
        extra.append(t(OX + step * i, fy, big, 76, AMBER, weight=800, spacing=1))
        extra.append(t(OX + step * i, fy + 52, small, 30, CREAM, weight=600, spacing=1, opacity=0.8))
    page('before_after', width, height, a + b + ''.join(extra))


def elevation():
    """Today's frame and the proposed one from the side, at one scale."""
    E, width, height = 3.2, 3040, 1120
    ground = 800
    o = []

    def X(base, x):
        return base + x * E

    def Y(h):
        return ground - h * E

    def box(base, x0, x1, h0, h1, **style):
        attrs = ' '.join(f'{k.replace("_", "-")}="{v}"' for k, v in style.items())
        o.append(f'<rect x="{X(base, x0):.1f}" y="{Y(h1):.1f}" width="{(x1 - x0) * E:.1f}" height="{(h1 - h0) * E:.1f}" {attrs}/>')

    def frame(base, x0, x1, floors, tint, alpha=1.0):
        top = floors * 10
        o.append(f'<g opacity="{alpha}">')
        box(base, x0, x1, 0, top, fill='#0C1216')
        box(base, x0, x1, 0, top, fill=tint, opacity=0.22)
        box(base, x0, x1, 0, top, fill='url(#enet)')
        mats = ['#D8342A', '#2A62D8', '#2FA04A', '#F2C21A']
        for k in range(1, floors):
            n = 0
            x = x0
            while x < x1 - 0.1:
                box(base, x, min(x + 24, x1), k * 10 - 0.9, k * 10 + 0.9, fill=mats[(k + n) % 4])
                x += 24
                n += 1
        n = 0
        x = x0
        while x <= x1 + 0.1:
            o.append(f'<path d="M{X(base, x):.1f} {Y(0):.1f} V{Y(top):.1f}" stroke="{POSTS[n % 4]}" stroke-width="3.2"/>')
            x += 12
            n += 1
        o.append(f'<path d="M{X(base, x0):.1f} {Y(top):.1f} H{X(base, x1):.1f}" stroke="{CREAM}" stroke-width="2.5"/>')
        o.append('</g>')

    def hall(base, x0, x1, roof):
        box(base, x0, x1, 0, roof, fill='#1B2328')
        box(base, x0, x1, roof, roof + 3, fill='#5C666C')
        x = x0 + 14
        while x < x1 - 8:
            o.append(f'<path d="M{X(base, x):.1f} {Y(roof):.1f} l{6 * E:.1f} {3.4 * E:.1f} l{6 * E:.1f} {-3.4 * E:.1f}" '
                     f'stroke="#5C666C" stroke-width="2" fill="none"/>')
            x += 12
        x = x0 + 30
        while x < x1 - 20:
            box(base, x, x + 9, roof - 6.2, roof - 5.2, fill='#FFF6D8')
            o.append(f'<path d="M{X(base, x + 4.5):.1f} {Y(roof):.1f} V{Y(roof - 5.2):.1f}" stroke="#5C666C" stroke-width="1.5"/>')
            x += 62
        box(base, x0, x1, -4, 0, fill='#1D5238')
        x = x0
        while x < x1 - 0.1:
            box(base, x, min(x + 12, x1), -4, 0, fill='#1C3458')
            x += 24

    def person(base, x, tall, colour):
        head = tall * 0.24
        box(base, x - tall * 0.16, x + tall * 0.16, 0, tall - head, fill=colour)
        o.append(f'<circle cx="{X(base, x):.1f}" cy="{Y(tall - head / 2):.1f}" r="{head * E / 2:.1f}" fill="{colour}"/>')

    def rise(base, x, h, label, side=1):
        px = X(base, x)
        o.append(f'<path d="M{px:.1f} {Y(0):.1f} V{Y(h):.1f} M{px - 9:.1f} {Y(0):.1f} h18 M{px - 9:.1f} {Y(h):.1f} h18" '
                 f'stroke="{AMBER}" stroke-width="3"/>')
        o.append(t(px + side * 16, Y(h / 2) + 9, label, 27, AMBER, 'start' if side > 0 else 'end', 800, 1))

    o.append(f'<defs><pattern id="enet" width="{2 * E:.2f}" height="{2 * E:.2f}" patternUnits="userSpaceOnUse">'
             f'<path d="M0 0 H{2 * E:.2f} M0 0 V{2 * E:.2f}" stroke="{CREAM}" stroke-width="0.6" opacity="0.28"/></pattern></defs>')
    o.append(t(90, 110, 'LEVEL 6  ·  HOW HIGH IT GOES, SAME SCALE', 60, CREAM, weight=800, spacing=3))
    o.append(t(90, 170, 'The roof is more than twice as far away, and the frame climbs with it: six floors everywhere, seven in Tube Town, ten in the Tower.',
               33, TEAL, weight=600, spacing=1))

    # today
    a = 236
    hall(a, 0, 200, 46)
    frame(a, 28, 172, 3, '#F2C21A')
    person(a, 14, 5, '#F2C21A')
    rise(a, -8, 46, '46', -1)
    rise(a, 180, 30, '30')
    o.append(t(X(a, 0), Y(46) - 46, 'TODAY', 44, CREAM, weight=800, spacing=4))
    o.append(t(X(a, 0) + 170, Y(46) - 46, '3 floors under a 46-stud roof', 30, CREAM, weight=600, spacing=1, opacity=0.7))

    # the proposal: a cut west to east through Home Base, with Tube Town and the Tower standing behind it
    b = 236 + 200 * E + 178
    hall(b, -44, 600, 120)
    frame(b, 36, 456, 7, '#D8342A', 0.45)
    frame(b, 456, 552, 10, '#E07B2A', 0.62)
    frame(b, 0, 204, 6, '#F2C21A')
    frame(b, 372, 552, 6, '#2FA04A')
    # the court between the wings: the post, the Counter and a player
    box(b, 204, 372, 0, 0.9, fill=AMBER)
    box(b, 286, 290, 0, 13, fill=CORAL)
    person(b, 268, 8.2, '#E9DCC8')
    person(b, 310, 5, '#F2C21A')
    # slides: the Tower's spiral to the floor, Tube Town's long tube into the court, a wave slide off the Net Maze
    def slide(points, colour, wide):
        d = 'M' + ' L'.join(f'{X(b, x):.1f} {Y(h):.1f}' for x, h in points)
        o.append(f'<path d="{d}" stroke="{BG}" stroke-width="{wide + 5}" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
        o.append(f'<path d="{d}" stroke="{colour}" stroke-width="{wide}" fill="none" stroke-linejoin="round" stroke-linecap="round"/>')
    spiral = []
    for k in range(0, 9):
        spiral += [(556 + (22 if k % 2 == 0 else 0), 100 - k * 11.5)]
    spiral += [(590, 2)]
    slide(spiral, '#D8342A', 15)
    slide([(350, 70), (336, 52), (346, 36), (330, 20), (338, 8), (322, 2)], '#E07B2A', 13)
    slide([(204, 40), (218, 24), (214, 12), (230, 2)], '#2A62D8', 13)
    rise(b, -36, 120, '120', -1)
    rise(b, 574, 100, '100')
    rise(b, -10, 60, '60', -1)
    o.append(t(X(b, -44), Y(120) - 46, 'NEW DRAFT', 44, AMBER, weight=800, spacing=4))
    o.append(t(X(b, -44) + 262, Y(120) - 46, 'cut west to east through Home Base; Tube Town and the Tower stand behind', 30, CREAM,
               weight=600, spacing=1, opacity=0.7))
    for x, text in ((102, 'NET MAZE  ·  6'), (462, 'FOAM FOREST  ·  6'), (288, 'HOME BASE')):
        o.append(t(X(b, x), Y(-4) + 44, text, 27, CREAM, 'middle', 800, 2))
    o.append(t(X(b, 288), Y(-4) + 80, 'the post, the Counter (8 studs, pale) and a player (5 studs, yellow)', 23, CREAM, 'middle', 600, 0.8, 0.75))
    o.append(t(X(b, 300), Y(74), 'TUBE TOWN  ·  7', 26, CREAM, 'middle', 800, 2, 0.8))
    o.append(t(X(b, 504), Y(104), 'THE TOWER  ·  10', 26, CREAM, 'middle', 800, 2, 0.9))

    fy = ground + 190
    cells = [('46 &#8594; 120', 'studs up to the roof'), ('30 &#8594; 60 to 100', 'studs of frame'),
             ('3 &#8594; 6 to 10', 'floors to climb'), ('20 &#8594; 100', 'studs down the longest slide')]
    step = (width - 180) / len(cells)
    for i, (big, small) in enumerate(cells):
        o.append(t(90 + step * i, fy, big, 72, AMBER, weight=800, spacing=1))
        o.append(t(90 + step * i, fy + 50, small, 30, CREAM, weight=600, spacing=1, opacity=0.8))
    page('height_before_after', width, height, ''.join(o))


if __name__ == '__main__':
    main()
    elevation()
