"""Level 6 concept v5: put the drawn sheets and the generated views into one numbered folder on the Desktop.

    python3 tools/level6_playground/concept_v5/assemble.py

Reads artifacts/level6-concept-20261006b/{plan,final} and four views kept from the draft before it
(artifacts/level6-concept-20261006/final); REPLACES ~/Desktop/"Level 6 nyt koncept".
A view that has not been generated yet is reported and skipped.
"""
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / 'artifacts' / 'level6-concept-20261006b'
OLD = ROOT / 'artifacts' / 'level6-concept-20261006' / 'final'
DEST = Path.home() / 'Desktop' / 'Level 6 nyt koncept'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
BG, CREAM = '#161D20', '#F3ECDA'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"

ORDER = [   # name on the Desktop, source
    ('01_map_of_the_arena', SRC / 'final/01_map_of_the_arena.png'),
    ('02_plan_to_scale', SRC / 'plan/plan_arena.png'),
    ('03_side_view_and_the_way_out', SRC / 'plan/section_arena.png'),
    ('04_the_whole_arena_from_above', SRC / 'final/04b_the_whole_arena_from_above.png'),
    ('05_you_arrive_in_the_tunnel', OLD / '05_the_spawn_tunnel.png'),
    ('06_the_way_in', OLD / '06_the_way_in.png'),
    ('07_the_court', SRC / 'final/07_the_court.png'),
    ('08_inside_the_galleries_the_picture_you_picked', OLD / '09_inside_the_rings.png'),
    ('09_looking_down_from_a_high_gallery', SRC / 'final/09_looking_down_from_a_high_gallery.png'),
    ('10_on_the_net_bridge_over_the_post', OLD / '10_the_net_bridge_over_the_post.png'),
    ('11_the_court_in_the_games_look', SRC / 'final/11_the_court_in_game_look.png'),
    ('12_the_third_touch_the_countdown', SRC / 'final/12_the_third_touch_the_countdown.png'),
    ('13_zero_the_post_goes_down', SRC / 'final/13_the_post_goes_down.png'),
    ('14_run_for_it', SRC / 'final/14_run_for_it.png'),
    ('15_down_the_hole', SRC / 'final/15_down_the_hole.png'),
    ('16_the_exit_under_the_floor', SRC / 'final/16_the_exit_under_the_floor.png'),
]


def contact_sheet(files, target):
    cells = ''.join(f'<div style="width:620px"><img src="file://{f}" style="width:620px;height:349px;object-fit:contain;'
                    f'background:#0C1216;display:block"><div style="font-size:18px;font-weight:700;letter-spacing:0.6px;'
                    f'padding:8px 2px 0">{f.stem}</div></div>' for f in files)
    rows = (len(files) + 3) // 4
    page = SRC / '_page.html'
    page.write_text(f'<html><body style="margin:0;background:{BG};font-family:{FONT};color:{CREAM}">'
                    f'<div style="padding:34px 40px 8px;font-size:46px;font-weight:800;letter-spacing:3px">'
                    f'LEVEL 6  ·  THE ARENA  ·  DRAFT 3  ·  ALL PICTURES</div>'
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
        if source.exists():
            shutil.copyfile(source, DEST / f'{name}.png')
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
