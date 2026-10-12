"""Finish the picture set of 2026-10-13 (artifacts/promo-20261013-ingame/raw): crop, a light edit, lettering, Desktop.

    /usr/local/bin/python3 tools/promo/finish_ingame2.py

The owner asked for in-game pictures "with some slight edit that makes them pop". The edit is the same small one on
every picture (`pop`): a little contrast about the mid-tones, a little saturation, a mild sharpen and a gentle
darkening toward the corners. Nothing is painted in. Thumbnails get the one small BACKROOMS / STAY QUIET lock-up in
the bottom-left corner (finish_ingame.lockup) and also go out without it; gallery pictures go out clean; covers get
the title large in the upper third; icons are 1024 and 512 square, no lettering. Pictures that are missing from
`raw` are skipped and listed.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
sys.path.insert(0, str(Path(__file__).resolve().parent))
import finish as f
import finish_ingame as before

JOB = f.ROOT / 'artifacts' / 'promo-20261013-ingame'
DESK = Path.home() / 'Desktop' / 'Backrooms Stay Quiet - Nye billeder 2026-10-13'
NAMES = {
    'T01_l1_pov_torch_finds_it': '01 Level 1 - lygten finder den', 'T02_l1_pov_it_runs': '02 Level 1 - den loeber mod dig',
    'T03_l1_dim_round_the_corner': '03 Level 1 - rundt om hjoernet (daempet lys)', 'T04_l1_dim_eyes_in_the_dark': '04 Level 1 - oejne i moerket',
    'T05_l1_two_torches': '05 Level 1 - to lygter', 'T06_l3_the_manager': '06 Level 3 - Mall Manager', 'T07_l3_pov_torch_balloon': '07 Level 3 - lygten paa ballonhovedet',
    'T08_l3_under_the_table': '08 Level 3 - under bordet', 'T09_l6_it_counts': '09 Level 6 - den taeller', 'T10_l6_found_you': '10 Level 6 - fundet',
    'T11_l6_behind_you': '11 Level 6 - bag dig', 'T12_lobby_mall': '12 Lobbyen - det doede indkoebscenter',
    'I01_icon_torch_and_eyes': 'ikon A - lygte og oejne', 'I02_icon_entity_in_beam': 'ikon B - entity i lyskeglen', 'I03_icon_balloon_head': 'ikon C - ballonhovedet',
    'I04_icon_counter_peek': 'ikon D - dukken kigger', 'I05_icon_mask_dim': 'ikon E - masken', 'I06_icon_red_eyes': 'ikon F - roede oejne',
    'G01_l1_dim_empty': 'galleri 1 - Level 1 daempet', 'G02_l1_off_torch': 'galleri 2 - Level 1 slukket med lygte', 'G03_l3_party_room': 'galleri 3 - Level 3 festlokalet',
    'G04_l6_court': 'galleri 4 - Level 6 banen', 'G05_lobby_mall_hall': 'galleri 5 - lobbyen', 'G06_l2_hall': 'galleri 6 - Level 2 soejlehallen',
    'C01_cover_three_entities': 'cover 1 - tre entities i lyskeglerne', 'C02_cover_one_torch': 'cover 2 - en lygte',
}
FOLDERS = {'T': '1 Thumbnails med logo (1920x1080)', 'Tplain': '2 Thumbnails uden logo (1920x1080)', 'I': '3 Ikoner (1024x1024 og 512x512)',
           'G': '4 Galleri (1920x1080)', 'C': '5 Covers med titel (1920x1080)', 'Cplain': '6 Covers uden titel (1920x1080)'}


def pop(im):
    a = np.asarray(im).astype(np.float32) / 255
    a = np.clip(0.5 + (a - 0.5) * 1.09 - 0.012, 0, 1)                      # contrast about the middle, blacks a touch deeper
    h, w = a.shape[:2]
    yy, xx = np.mgrid[:h, :w]
    r = np.hypot((xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2))
    a *= (1 - 0.16 * np.clip(r - 0.55, 0, 1) ** 1.6)[..., None]           # corners only
    out = Image.fromarray(np.uint8(a * 255 + 0.5))
    out = ImageEnhance.Color(out).enhance(1.10)
    return out.filter(ImageFilter.UnsharpMask(radius=1.6, percent=55, threshold=2))


def cover_title(im):
    w, h = im.size
    s = h / 1080
    im = f.shade(im, (w * 0.18, -60, w * 0.82, 330 * s), 0.5, 0.6)
    d = ImageDraw.Draw(im, 'RGBA')
    f1, f2 = f.font(58 * s), f.font(168 * s)
    y = int(70 * s)
    w1 = f.tracked_width(d, 'BACKROOMS', f1, 20 * s)
    f.tracked(d, (w - w1) / 2, y, 'BACKROOMS', f1, f.CREAM, 20 * s, shadow=3)
    y2 = y + f.cap(f1) + 26 * s
    w2 = f.tracked_width(d, 'STAY QUIET', f2, 4 * s)
    end = f.tracked(d, (w - w2) / 2, y2, 'STAY QUIET', f2, f.CREAM, 4 * s, shadow=4)
    d.rectangle(((w - w2) / 2, y2 + f.cap(f2) + 22 * s, end, y2 + f.cap(f2) + 28 * s), fill=f.AMBER + (255,))
    return im


def main():
    for sub in FOLDERS.values():
        (DESK / sub).mkdir(parents=True, exist_ok=True)
    (JOB / 'final').mkdir(exist_ok=True)
    made, missing = {}, []
    for key, name in NAMES.items():
        path = JOB / 'raw' / f'{key}_raw.png'
        if not path.exists():
            missing.append(key)
            continue
        raw = Image.open(path).convert('RGB')
        kind = key[0]
        if kind == 'I':
            out = pop(before.crop_to(raw, 1024, 1024))
            out.save(DESK / FOLDERS['I'] / f'{name}.png')
            out.resize((512, 512), Image.LANCZOS).save(DESK / FOLDERS['I'] / f'{name} (512).png')
        else:
            plain = pop(before.crop_to(raw, 1920, 1080))
            if kind == 'T':
                plain.save(DESK / FOLDERS['Tplain'] / f'{name}.jpg', quality=94)
                out = before.lockup(plain.copy())
                out.save(DESK / FOLDERS['T'] / f'{name}.jpg', quality=94)
            elif kind == 'G':
                out = plain
                out.save(DESK / FOLDERS['G'] / f'{name}.jpg', quality=94)
            else:
                plain.save(DESK / FOLDERS['Cplain'] / f'{name}.jpg', quality=94)
                out = cover_title(plain.copy())
                out.save(DESK / FOLDERS['C'] / f'{name}.jpg', quality=94)
        out.save(JOB / 'final' / f'{key}.jpg', quality=92)
        made[key] = out
    wide = [im for k, im in made.items() if k[0] != 'I']
    if wide:
        rows = -(-len(wide) // 3)
        sheet = Image.new('RGB', (640 * 3, 360 * rows), (12, 12, 12))
        for i, im in enumerate(wide):
            sheet.paste(im.resize((640, 360), Image.LANCZOS), ((i % 3) * 640, (i // 3) * 360))
        sheet.save(DESK / '0 Oversigt - brede billeder.jpg', quality=90)
        sheet.save(JOB / 'final' / 'sheet_wide.jpg', quality=88)
    icons = [im for k, im in made.items() if k[0] == 'I']
    if icons:
        sheet = Image.new('RGB', (384 * len(icons), 384 + 150), (12, 12, 12))
        for i, im in enumerate(icons):
            sheet.paste(im.resize((384, 384), Image.LANCZOS), (i * 384, 0))
            sheet.paste(im.resize((150, 150), Image.LANCZOS), (i * 384 + 117, 384))       # the size the store shows them at
        sheet.save(DESK / '0 Oversigt - ikoner.jpg', quality=90)
        sheet.save(JOB / 'final' / 'sheet_icons.jpg', quality=88)
    print('made', len(made), 'in', DESK, '| missing:', ', '.join(missing) or 'none')


if __name__ == '__main__':
    main()
