"""Floor plan of the lobby as a dead 1990s mall (proposal, round three), on the real lobby's measurements.

    /usr/local/bin/python3 tools/lobby_reach/mall_plan.py     # writes artifacts/lobby-mall-20261011/plan_v3.png and the Desktop copy
"""
import math, os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT = Path(__file__).resolve().parents[2]
S = 6
X0, X1, Z0, Z1 = 112, 328, -912, -540
W, H = (X1 - X0) * S, (Z1 - Z0) * S
TOP = 150
im = Image.new('RGB', (W, H + TOP + 200), (18, 20, 22))
d = ImageDraw.Draw(im)
B = lambda n: ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', n)
R = lambda n: ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', n)
def px(x, z): return ((x - X0) * S, TOP + (Z1 - z) * S)
def rect(x0, x1, z0, z1, fill, outline=None, width=2):
    a, b = px(x0, z1), px(x1, z0)
    d.rectangle([a[0], a[1], b[0], b[1]], fill=fill, outline=outline, width=width)
def label(x, z, text, f, fill=(235, 238, 230)):
    d.multiline_text(px(x, z), text, font=f, fill=fill, anchor='mm', align='center', spacing=4)
def disc(x, z, r, **kw):
    d.ellipse([px(x - r, 0)[0], px(0, z + r)[1], px(x + r, 0)[0], px(0, z - r)[1]], **kw)
def hexagon(x, z, r, **kw):
    d.polygon([px(x + r * math.cos(math.radians(a)), z + r * math.sin(math.radians(a))) for a in range(0, 360, 60)], **kw)
d.text((30, 26), 'LOBBY SOM FORLADT 90ER-INDKØBSCENTER  ·  PLANTEGNING v3', font=B(36), fill=(240, 244, 236))
d.text((30, 80), 'Åbne butikker med level-udstilling og kø-plader, sekskantet Shop & Supplies i midten, fare-bånd og mørk fløj. 1 tern = 10 studs.', font=R(20), fill=(170, 182, 174))
for x in range(120, 321, 10): d.line([px(x, Z0 + 6), px(x, Z1 - 6)], fill=(30, 33, 36), width=1)
for z in range(-900, Z1, 10): d.line([px(X0 + 6, z), px(X1 - 6, z)], fill=(30, 33, 36), width=1)
TERR, ACC = (92, 82, 52), (206, 170, 84)
rect(180, 260, -900, -621, TERR, (130, 116, 80), 3)
for i in range(16):
    z0 = -621 + i * 5
    c = max(8, 44 - i * 3)
    rect(180, 260, z0, z0 + 5, (c, c - 2, c - 6))
rect(180, 260, -621, Z1 + 1, None, (70, 66, 56), 2)
for z in (-606, -582):
    for (a, b) in ((160, 180), (260, 280)): rect(a, b, z - 10, z + 10, (22, 23, 24), (50, 50, 50), 1)
label(220, -596, 'DEN MØRKE FLØJ\nsamme gang, intet lys, tomme butikker', B(17), (150, 150, 150))
label(220, -572, 'går man herind, vågner lobby-væsnet:\nto øjne langt inde, lange arme kommer\nlangsomt nærmere og griber én', R(16), (190, 120, 120))
disc(212, -552, 2.2, fill=(255, 190, 110)); disc(228, -552, 2.2, fill=(255, 190, 110))
for x in (200, 214, 226, 240): d.line([px(x, -556), px(x + (x - 220) * 0.25, -566)], fill=(150, 140, 130), width=4)
for x in range(184, 260, 12): disc(x, -621, 1.4, fill=(230, 230, 230))
d.line([px(184, -621), px(256, -621)], fill=(250, 214, 40), width=7)
label(220, -627.5, 'BÅND PÅ PÆLE: "DANGER: DO NOT GO PAST THIS POINT"  ·  åbent', B(15), (250, 214, 40))
shops = [(1, True, -869, -811, 'OFFICE', (150, 130, 50)), (3, True, -789, -731, 'MALL PARTY', (170, 90, 50)), (5, True, -709, -651, 'THE VOID', (190, 130, 160)),
         (2, False, -869, -811, 'POOLROOMS', (70, 130, 140)), (4, False, -789, -731, 'CINEMA', (120, 40, 50)), (6, False, -709, -651, 'PLAY ZONE', (60, 90, 150))]
for n, west, z0, z1, name, col in shops:
    xa, xb = (127, 180) if west else (260, 313)
    rect(xa, xb, z0, z1, (48, 50, 50), (110, 116, 110), 2)
    rect(xa + (2 if west else 26), xb - (26 if west else 2), z0 + 3, z1 - 3, tuple(int(c * 0.55) for c in col), col, 2)
    label(xa + (14 if west else 39), (z0 + z1) / 2, 'LEVEL-\nUDSTILLING', B(13), (240, 240, 230))
    pad = 166 if west else 274
    for k in (-18, 0, 18): disc(pad, (z0 + z1) / 2 + k, 5, outline=(110, 220, 170), width=3)
    label(pad, (z0 + z1) / 2 + 26.5, 'kø-plader', R(13), (110, 220, 170))
    e = 180 if west else 260
    for zz in (z0 + 3, z1 - 3): disc(e, zz, 1.2, fill=(190, 184, 160))
    label(192 if west else 248, z1 - 6.5, f'LEVEL {n}', B(19))
    label(195 if west else 245, z1 - 13, name, R(14), (200, 204, 196))
rect(184, 256, -905, -894, (40, 44, 48), (140, 150, 160), 2)
label(220, -899.5, 'INDGANG  ·  døde glasdøre, mørkt udenfor', R(18), (200, 208, 214))
disc(220, -860, 6, fill=(110, 220, 170))
label(220, -872, 'ANKOMST (spawn)', R(17))
hexagon(220, -770, 15, fill=(110, 84, 46), outline=ACC, width=4)
hexagon(220, -770, 8, fill=(54, 44, 30), outline=(150, 124, 70), width=2)
label(220, -770, 'SHOP &\nSUPPLIES', B(15), (250, 220, 150))
label(220, -790, 'sekskantet 90er-stand (som en smykkekiosk): butikken', R(15), (230, 200, 130))
rect(180, 186, -806, -784, (52, 60, 70), (130, 150, 170), 2)
label(197, -795, 'center-\noversigt', R(13), (170, 186, 200))
for z in (-835, -700):
    rect(213, 227, z - 4, z + 4, (56, 66, 52), (120, 130, 100), 2); label(220, z, 'bænke', R(13), (190, 200, 180))
rect(205, 235, -655, -632, (70, 52, 60), (190, 120, 150), 3)
label(220, -643.5, 'EVENT-SCENE (DJ)', B(16))
for z in range(-890, -630, 20):
    for x in (200, 240):
        dead = (z, x) in ((-830, 240), (-750, 200), (-690, 240), (-650, 200), (-650, 240))
        rect(x - 5, x + 5, z - 1, z + 1, (60, 60, 50) if dead else (236, 222, 150))
y = TOP + H + 20
items = [((110, 220, 170), 'kø-plader og ankomst, som i dag'), (ACC, 'Shop & Supplies = butikken'), ((250, 214, 40), 'fare-bånd: her stopper lobbyen'),
         ((236, 222, 150), 'gullige lysstofrør (mørke = døde); ingen lys i den mørke fløj'), ((190, 120, 120), 'væsnet: øjne og arme, som det findes i dag')]
for i, (c, t) in enumerate(items):
    xx = 30 + (i % 2) * (W // 2); yy = y + (i // 2) * 44
    d.rectangle([xx, yy + 4, xx + 34, yy + 26], fill=c); d.text((xx + 48, yy + 2), t, font=R(21), fill=(210, 216, 208))
out = ROOT / 'artifacts' / 'lobby-mall-20261011' / 'plan_v3.png'
im.save(out)
desk = Path.home() / 'Desktop' / 'Lobby - forladt indkoebscenter (forslag)' / 'v3'
desk.mkdir(parents=True, exist_ok=True)
im.save(desk / '0 Plantegning v3.png')
print(out, im.size)
