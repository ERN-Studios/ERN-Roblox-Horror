"""Crop, size and letter the in-game-look store pictures of 2026-10-11 (artifacts/promo-20261011-ingame/raw).

    /usr/local/bin/python3 tools/promo/finish_ingame.py

Thumbnails: centre crop to 16:9, 1920 x 1080, and ONE small lock-up in the bottom-left corner of every picture, the
way the big backrooms games do it (BACKROOMS over STAY QUIET; the public name no longer says CO-OP HORROR). Icons:
1024 x 1024, no lettering. Everything also goes out without lettering.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parent))
import finish as f

JOB = f.ROOT / 'artifacts' / 'promo-20261011-ingame'
DESK = Path.home() / 'Desktop' / 'Backrooms Stay Quiet - Store-billeder 2026-10-11'
NAMES = {'T01_l1_round_the_corner': '01 Level 1 - rundt om hjoernet', 'T02_l1_it_sees_you': '02 Level 1 - den har set dig', 'T03_l1_caught': '03 Level 1 - fanget (roed)',
         'T04_l2_the_hall': '04 Level 2 - soejlehallen', 'T05_l3_under_the_table': '05 Level 3 - under bordet', 'T06_l4_the_aisle': '06 Level 4 - biografen',
         'T07_l5_the_ledge': '07 Level 5 - kanten', 'T08_l6_it_counts': '08 Level 6 - den taeller', 'I01_icon_mask': 'ikon A - masken', 'I02_icon_eyes': 'ikon B - oejnene'}


def crop_to(im, w, h):
    target = w / h
    if im.width / im.height > target:
        nw = round(im.height * target); x = (im.width - nw) // 2
        im = im.crop((x, 0, x + nw, im.height))
    else:
        nh = round(im.width / target); y = (im.height - nh) // 2
        im = im.crop((0, y, im.width, y + nh))
    return im.resize((w, h), Image.LANCZOS)


def lockup(im):
    w, h = im.size
    s = h / 1080
    x, y = int(58 * s), int(h - 58 * s - 118 * s)
    im = f.shade(im, (-80, y - 60 * s, 560 * s, h + 80), 0.55, 0.5)
    d = ImageDraw.Draw(im, 'RGBA')
    f1, f2 = f.font(30 * s), f.font(84 * s)
    f.tracked(d, x + 2 * s, y, 'BACKROOMS', f1, f.CREAM, 9 * s, shadow=2)
    y2 = y + f.cap(f1) + 12 * s
    end = f.tracked(d, x, y2, 'STAY QUIET', f2, f.CREAM, 1.5 * s, shadow=2)
    d.rectangle((x, y2 + f.cap(f2) + 12 * s, end, y2 + f.cap(f2) + 15 * s), fill=f.AMBER + (255,))
    return im


def main():
    for sub in ('1 Thumbnails med logo (1920x1080)', '2 Thumbnails uden logo (1920x1080)', '3 Ikoner (1024x1024)'):
        (DESK / sub).mkdir(parents=True, exist_ok=True)
    (JOB / 'final').mkdir(exist_ok=True)
    made = []
    for key, name in NAMES.items():
        raw = Image.open(JOB / 'raw' / f'{key}_raw.png').convert('RGB')
        if key.startswith('I'):
            out = crop_to(raw, 1024, 1024)
            out.save(DESK / '3 Ikoner (1024x1024)' / f'{name}.png')
            out.save(JOB / 'final' / f'{key}.jpg', quality=92)
        else:
            plain = crop_to(raw, 1920, 1080)
            plain.save(DESK / '2 Thumbnails uden logo (1920x1080)' / f'{name}.jpg', quality=93)
            out = lockup(plain.copy())
            out.save(DESK / '1 Thumbnails med logo (1920x1080)' / f'{name}.jpg', quality=93)
            out.save(JOB / 'final' / f'{key}.jpg', quality=92)
        made.append((name, out))
    thumbs = [im for n, im in made if not n.startswith('ikon')]
    sheet = Image.new('RGB', (960 * 2, 540 * 4), (12, 12, 12))
    for i, im in enumerate(thumbs):
        sheet.paste(im.resize((960, 540), Image.LANCZOS), ((i % 2) * 960, (i // 2) * 540))
    sheet.save(DESK / '0 Oversigt.jpg', quality=90)
    small = Image.new('RGB', (320 * 4, 180 * 2), (12, 12, 12))        # the size the store shows them at
    for i, im in enumerate(thumbs):
        small.paste(im.resize((320, 180), Image.LANCZOS), ((i % 4) * 320, (i // 4) * 180))
    small.save(JOB / 'final' / 'at_store_size.jpg', quality=92)
    print('made', len(made), 'in', DESK)


if __name__ == '__main__':
    main()
