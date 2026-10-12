"""Finish picture set 3 of 2026-10-13 (artifacts/promo-20261013-set3/raw) and ADD it to the Desktop folder of set 2.

    /usr/local/bin/python3 tools/promo/finish_ingame3.py

The owner looked at the 26 pictures of set 2 and wrote "Du må lige lave nogle flere der er bedre og tilføj dem til
samme mappe": seventeen more (bigger subjects, a lit area in every one, the Halloween lobby). Same finishing as set 2
(finish_ingame2: crop, the small `pop` edit, the lock-up on thumbnails, the title on covers, icons at 1024 and 512),
written into the SAME folders with numbers that continue set 2's, so nothing of set 2 is overwritten. Its own two
overview sheets go beside set 2's. Pictures missing from `raw` are skipped and listed.
"""
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
import finish as f
import finish_ingame as before
import finish_ingame2 as two

JOB = f.ROOT / 'artifacts' / 'promo-20261013-set3'
DESK, FOLDERS = two.DESK, two.FOLDERS
NAMES = {
    'T13_halloween_lobby': '13 Halloween - lobbyen', 'T14_halloween_lanterns': '14 Halloween - graeskar ved tapen',
    'T15_l1_lunge': '15 Level 1 - springet', 'T16_l1_the_fuse': '16 Level 1 - sikringen',
    'T17_l3_manager_close': '17 Level 3 - Mall Manager helt taet paa', 'T18_l6_counter_runs': '18 Level 6 - den loeber mod dig',
    'T19_l2_wading': '19 Level 2 - i vandet', 'T20_l1_back_to_back': '20 Level 1 - ryg mod ryg',
    'I07_icon_entity_face': 'ikon G - entity taet paa', 'I08_icon_manager_grin': 'ikon H - ballonhovedet i lyset',
    'I09_icon_counter_corner': 'ikon I - dukken om hjoernet', 'I10_icon_mask_and_eyes': 'ikon J - oejne i masken',
    'I11_icon_halloween': 'ikon K - Halloween',
    'G07_halloween_shop': 'galleri 7 - Halloween-butikken', 'G08_l4_cinema': 'galleri 8 - Level 4 biografen', 'G09_l5_void': 'galleri 9 - Level 5 The Void',
    'C03_cover_halloween': 'cover 3 - Halloween',
}


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
            out = two.pop(before.crop_to(raw, 1024, 1024))
            out.save(DESK / FOLDERS['I'] / f'{name}.png')
            out.resize((512, 512), Image.LANCZOS).save(DESK / FOLDERS['I'] / f'{name} (512).png')
        else:
            plain = two.pop(before.crop_to(raw, 1920, 1080))
            if kind == 'T':
                plain.save(DESK / FOLDERS['Tplain'] / f'{name}.jpg', quality=94)
                out = before.lockup(plain.copy())
                out.save(DESK / FOLDERS['T'] / f'{name}.jpg', quality=94)
            elif kind == 'G':
                out = plain
                out.save(DESK / FOLDERS['G'] / f'{name}.jpg', quality=94)
            else:
                plain.save(DESK / FOLDERS['Cplain'] / f'{name}.jpg', quality=94)
                out = two.cover_title(plain.copy())
                out.save(DESK / FOLDERS['C'] / f'{name}.jpg', quality=94)
        out.save(JOB / 'final' / f'{key}.jpg', quality=92)
        made[key] = out
    wide = [im for k, im in made.items() if k[0] != 'I']
    if wide:
        rows = -(-len(wide) // 3)
        sheet = Image.new('RGB', (640 * 3, 360 * rows), (12, 12, 12))
        for i, im in enumerate(wide):
            sheet.paste(im.resize((640, 360), Image.LANCZOS), ((i % 3) * 640, (i // 3) * 360))
        sheet.save(DESK / '0 Oversigt - NYE brede billeder (runde 2).jpg', quality=90)
        sheet.save(JOB / 'final' / 'sheet_wide.jpg', quality=88)
    icons = [im for k, im in made.items() if k[0] == 'I']
    if icons:
        sheet = Image.new('RGB', (384 * len(icons), 384 + 150), (12, 12, 12))
        for i, im in enumerate(icons):
            sheet.paste(im.resize((384, 384), Image.LANCZOS), (i * 384, 0))
            sheet.paste(im.resize((150, 150), Image.LANCZOS), (i * 384 + 117, 384))       # the size the store shows them at
        sheet.save(DESK / '0 Oversigt - NYE ikoner (runde 2).jpg', quality=90)
        sheet.save(JOB / 'final' / 'sheet_icons.jpg', quality=88)
    print('made', len(made), 'in', DESK, '| missing:', ', '.join(missing) or 'none')


if __name__ == '__main__':
    main()
