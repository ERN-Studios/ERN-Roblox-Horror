"""Level 6 concept v3: put the plan sheets and the generated views into one numbered folder on the Desktop.

    python3 tools/level6_playground/concept_v3/assemble.py

Reads artifacts/level6-concept-20261005/{plan,final,refs}; writes ~/Desktop/"Level 6 nyt koncept".
A view that has not been generated yet is reported and skipped.
"""
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / 'artifacts' / 'level6-concept-20261005'
DEST = Path.home() / 'Desktop' / 'Level 6 nyt koncept'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
BG, CREAM, AMBER, TEAL = '#161D20', '#F3ECDA', '#EDA827', '#4FADAA'
FONT = "'Avenir Next Condensed','Helvetica Neue',Helvetica,Arial,sans-serif"

ORDER = [   # name on the Desktop, source
    ('01_map_of_the_new_layout', 'final/01_map_overview.png'),
    ('02_floor_plan_to_scale', 'plan/plan_new.png'),
    ('03_today_and_new_same_scale', 'plan/before_after.png'),
    ('04_height_today_and_new', 'plan/height_before_after.png'),
    ('05_your_screenshot_today_and_new', None),             # built below
    ('06_whole_hall_from_above', 'final/02_whole_hall_cutaway.png'),
    ('07_from_the_entrance', 'final/03_from_the_entrance.png'),
    ('08_the_gate_between_the_nets', 'final/04_the_gate_between_the_nets.png'),
    ('09_inside_the_net_maze', 'final/05_inside_the_net_maze.png'),
    ('10_home_base_inside_the_frame', 'final/06_home_base_court.png'),
    ('11_looking_up_the_tower', 'final/07_looking_up_the_tower.png'),
    ('12_tube_town', 'final/08_tube_town.png'),
    ('13_ball_ocean_inside_the_frame', 'final/09_ball_ocean_inside_the_frame.png'),
    ('14_hiding_in_a_tube', 'final/10_hiding_in_a_tube.png'),
    ('15_view_from_the_top_deck', 'final/11_top_deck_view.png'),
    ('16_same_view_as_your_screenshot_concept', 'final/13_same_view_new_height_concept.png'),
]


def render(html, target, width, height):
    page = SRC / '_page.html'
    page.write_text(html)
    target.unlink(missing_ok=True)
    subprocess.run([CHROME, '--headless', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                    f'--window-size={width},{height}', f'--screenshot={target}', f'file://{page}'], capture_output=True)
    page.unlink()
    return target.exists()


def screenshot_pair(target):
    """The owner's screenshot of the frame today above the same view at the new height."""
    today, new = SRC / 'refs' / 'owner_frame_ingame.png', SRC / 'final' / '12b_same_view_new_height_ingame.png'
    if not (today.exists() and new.exists()):
        return False
    width = 1920
    top = round(width * 534 / 2094)
    html = (f'<html><body style="margin:0;background:{BG};font-family:{FONT};color:{CREAM}">'
            f'<div style="padding:34px 40px 18px;font-size:44px;font-weight:800;letter-spacing:3px">TODAY '
            f'<span style="font-size:26px;font-weight:600;letter-spacing:1px;opacity:.7">your screenshot: three floors, the roof just above</span></div>'
            f'<img src="file://{today}" style="display:block;width:{width}px;height:{top}px">'
            f'<div style="padding:34px 40px 18px;font-size:44px;font-weight:800;letter-spacing:3px;color:{AMBER}">NEW DRAFT '
            f'<span style="font-size:26px;font-weight:600;letter-spacing:1px;opacity:.8;color:{CREAM}">the same frame from the same spot: six floors here, '
            f'the roof at 120 studs (generated picture, not the game)</span></div>'
            f'<img src="file://{new}" style="display:block;width:{width}px;height:1080px"></body></html>')
    return render(html, target, width, top + 1080 + 2 * 104)


def contact_sheet(files, target):
    cells = ''.join(f'<div style="width:620px"><img src="file://{f}" style="width:620px;height:349px;object-fit:contain;background:#0C1216;display:block">'
                    f'<div style="font-size:19px;font-weight:700;letter-spacing:1px;padding:8px 2px 0">{f.stem}</div></div>' for f in files)
    rows = (len(files) + 3) // 4
    html = (f'<html><body style="margin:0;background:{BG};font-family:{FONT};color:{CREAM}">'
            f'<div style="padding:34px 40px 8px;font-size:46px;font-weight:800;letter-spacing:3px">LEVEL 6  ·  NEW CONCEPT  ·  ALL PICTURES</div>'
            f'<div style="display:flex;flex-wrap:wrap;gap:26px 24px;padding:20px 40px">{cells}</div></body></html>')
    return render(html, target, 2632, 120 + rows * 412)


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.glob('*.png'):
        old.unlink()
    done, missing = [], []
    for name, source in ORDER:
        target = DEST / f'{name}.png'
        if source is None:
            ok = screenshot_pair(target)
        else:
            ok = (SRC / source).exists()
            if ok:
                shutil.copyfile(SRC / source, target)
        (done if ok else missing).append(name)
    contact_sheet([DEST / f'{n}.png' for n in done], DEST / '00_all_pictures.png')
    notes = SRC / 'README.txt'
    if notes.exists():
        shutil.copyfile(notes, DEST / '00_READ_ME.txt')
    print('copied', len(done), 'missing', missing)


if __name__ == '__main__':
    main()
