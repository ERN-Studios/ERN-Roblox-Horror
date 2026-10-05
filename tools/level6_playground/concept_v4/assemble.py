"""Level 6 concept v4, "the Arena": put the drawn sheets and the generated views into one numbered folder on the Desktop.

    python3 tools/level6_playground/concept_v4/assemble.py

Reads artifacts/level6-concept-20261006/{plan,final}; REPLACES ~/Desktop/"Level 6 nyt koncept" (the owner asked for
the first concept's folder to go; its pictures are still in artifacts/level6-concept-20261005).
A view that has not been generated yet is reported and skipped.
"""
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / 'artifacts' / 'level6-concept-20261006'
DEST = Path.home() / 'Desktop' / 'Level 6 nyt koncept'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
BG, CREAM = '#161D20', '#F3ECDA'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"

ORDER = [   # name on the Desktop, source
    ('01_map_of_the_arena', 'final/01_map_of_the_arena.png'),
    ('02_plan_to_scale', 'plan/plan_arena.png'),
    ('03_side_view_the_bowl_and_the_well', 'plan/section_arena.png'),
    ('04_the_whole_arena_from_above', 'final/04_the_whole_arena_from_above.png'),
    ('05_you_arrive_in_the_tunnel', 'final/05_the_spawn_tunnel.png'),
    ('06_the_way_in', 'final/06_the_way_in.png'),
    ('07_the_court_and_the_bowl', 'final/07_the_court_the_bowl.png'),
    ('08_looking_down_from_the_top', 'final/08_looking_down_from_the_top.png'),
    ('09_inside_the_rings', 'final/09_inside_the_rings.png'),
    ('10_on_the_net_bridge_over_the_post', 'final/10_the_net_bridge_over_the_post.png'),
    ('11_the_court_in_the_games_look', 'final/11_the_court_in_game_look.png'),
    ('12_way_out_A_the_big_slide', 'final/12b_escape_A_the_big_slide.png'),
    ('13_way_out_B_back_the_way_you_came', 'final/13_escape_B_back_the_way_you_came.png'),
    ('14_way_out_C_under_the_post', 'final/14_escape_C_under_the_post.png'),
    ('15_way_out_D_a_fire_door', 'final/15_escape_D_the_emergency_door.png'),
    ('16_the_other_way_to_build_it_the_well', 'final/16_the_other_way_the_well.png'),
]


def contact_sheet(files, target):
    cells = ''.join(f'<div style="width:620px"><img src="file://{f}" style="width:620px;height:349px;object-fit:contain;'
                    f'background:#0C1216;display:block"><div style="font-size:19px;font-weight:700;letter-spacing:1px;'
                    f'padding:8px 2px 0">{f.stem}</div></div>' for f in files)
    rows = (len(files) + 3) // 4
    page = SRC / '_page.html'
    page.write_text(f'<html><body style="margin:0;background:{BG};font-family:{FONT};color:{CREAM}">'
                    f'<div style="padding:34px 40px 8px;font-size:46px;font-weight:800;letter-spacing:3px">'
                    f'LEVEL 6  ·  THE ARENA  ·  ALL PICTURES</div>'
                    f'<div style="display:flex;flex-wrap:wrap;gap:26px 24px;padding:20px 40px">{cells}</div></body></html>')
    target.unlink(missing_ok=True)
    subprocess.run([CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    f'--window-size=2632,{120 + rows * 412}', f'--screenshot={target}', f'file://{page}'], capture_output=True)
    page.unlink()


def main():
    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True)
    done, missing = [], []
    for name, source in ORDER:
        if (SRC / source).exists():
            shutil.copyfile(SRC / source, DEST / f'{name}.png')
            done.append(name)
        else:
            missing.append(name)
    contact_sheet([DEST / f'{n}.png' for n in done], DEST / '00_all_pictures.png')
    notes = SRC / 'README.txt'
    if notes.exists():
        shutil.copyfile(notes, DEST / '00_READ_ME.txt')
    print('copied', len(done), 'missing', missing)


if __name__ == '__main__':
    main()
