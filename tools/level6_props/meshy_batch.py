"""Level 6 hero props: one concept image and one textured mesh per prop, through Meshy's REST API.

    python3 tools/level6_props/meshy_batch.py [name ...]

The key is read from the Meshy MCP entry in ~/.codex/config.toml. Finished props are skipped, so the script
can be re-run; state is kept in artifacts/level6-props-20261003/state.json.
"""
import json, os, sys, time, tomllib, urllib.request, urllib.error
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'level6-props-20261003'
KEY = tomllib.load(open(os.path.expanduser('~/.codex/config.toml'), 'rb'))['mcp_servers']['meshy']['env']['MESHY_API_KEY']
API = 'https://api.meshy.ai/openapi/v1'
STYLE = ('Single game prop, whole object visible and centred, three-quarter front view, plain light grey background, '
         'soft even studio lighting, no floor shadow, no text. 1990s indoor soft-play centre, slightly dusty and worn, '
         'saturated primary colours. ')
# name: (prompt, target triangles)
PROPS = {
    'bouncy_castle': ('An inflatable bouncy castle: square bounce floor, four fat corner towers with red cone tops, low '
                      'inflated walls with arched windows, open front with a step; glossy PVC panels in red, yellow and blue.', 9000),
    'inflatable_slide': ('A tall inflatable slide: steep yellow slide lane between fat blue and red inflated side walls, '
                         'climbing steps on one side, two small towers with red cones at the top; glossy PVC.', 8000),
    'deflated_castle': ('A deflated bouncy castle collapsed into a low crumpled heap on the ground: heavy wrinkled folds of '
                        'glossy red, yellow and blue PVC, one sagging tower lying on its side.', 8000),
    'inflatable_dino': ('A large friendly green inflatable dinosaur, cartoon T-rex shape with yellow belly and spots, glossy '
                        'PVC with seams, slightly saggy.', 7000),
    'blower_fan': ('A black industrial inflatable blower fan: snail-shaped plastic housing with a round grille, carry handle '
                   'and a short yellow fabric air tube attached.', 4000),
    'arcade_cabinet_a': ('A 1990s upright arcade cabinet: dark blue body with purple and cyan abstract side art, lit marquee, '
                         'dark CRT screen, control panel with joystick and red buttons, coin door. Invented game, no real logos.', 5000),
    'arcade_cabinet_b': ('A 1990s upright arcade cabinet: red body with yellow lightning-bolt side art, marquee, dark CRT '
                         'screen, two joysticks and buttons, coin door. Invented game, no real logos.', 5000),
    'claw_machine': ('A claw crane prize machine: red base with a joystick, glass box above full of small plush toys, metal '
                     'claw hanging inside, yellow top sign.', 6000),
    'mascot_head_bear': ('A theme-park mascot costume head, removed and sitting on its neck opening: smiling brown cartoon '
                         'bear, big glossy round eyes, round ears, tan muzzle, plush fur, dusty.', 6000),
    'mascot_head_dog': ('A theme-park mascot costume head, removed and sitting on its neck opening: grinning golden-tan '
                        'cartoon lion cub with a small brown mane, big glossy eyes, plush fur, dusty.', 6000),
    'mascot_head_chicken': ('A theme-park mascot costume head, removed and sitting on its neck opening: white cartoon '
                            'chicken with a big orange beak, red comb, large blue eyes, feathery plush, dusty.', 6000),
    'slush_machine': ('A twin-tank slush drink machine: stainless steel base with two dispensing taps, two clear tanks, one '
                      'full of red slush and one of blue, black lids.', 5000),
    'ball_bag': ('A tall clear plastic sack tied at the top, stuffed full of colourful plastic play-pit balls in red, '
                 'yellow, blue and green.', 5000),
    'mop_bucket': ('A yellow janitor mop bucket on four wheels with a wringer and a wooden-handled string mop standing in it.', 4000),
    'playhouse': ('A chunky plastic toddler playhouse: pastel pink walls, blue pitched roof, yellow door frame with an open '
                  'doorway, round window with green shutters.', 5000),
    'toddler_castle': ('A small soft-play toddler castle: purple padded walls with yellow battlements, an arched doorway and '
                       'a short red slide coming off one side.', 6000),
    'fake_plant': ('A dusty artificial fern-like plant in a brown terracotta pot, as found in a 1990s mall.', 3000),
    'tube_window_panel': ('A square red soft-play wall panel with a clear plastic bubble dome window in the middle, yellow '
                          'padded frame around it.', 3000),
}


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            text = e.read().decode()[:400]
            if e.code in (429, 500, 502, 503) and attempt < 4:
                time.sleep(8 * (attempt + 1)); continue
            raise RuntimeError(f'{method} {path}: {e.code} {text}')
        except Exception as e:
            if attempt < 4:
                time.sleep(5); continue
            raise


def wait(kind, task_id, limit=900):
    t0 = time.time()
    while time.time() - t0 < limit:
        t = call('GET', f'/{kind}/{task_id}')
        if t.get('status') in ('SUCCEEDED', 'FAILED', 'CANCELED'):
            return t
        time.sleep(6)
    raise RuntimeError(f'{kind} {task_id} timed out')


def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, path)


STATE_FILE = OUT / 'state.json'
state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}


def save():
    STATE_FILE.write_text(json.dumps(state, indent=1))


def run(name):
    prompt, tris = PROPS[name]
    s = state.setdefault(name, {})
    try:
        if 'image_url' not in s:
            if 'image_task' not in s:
                s['image_task'] = call('POST', '/text-to-image', {'ai_model': 'nano-banana', 'prompt': (STYLE + prompt)[:600],
                                                                  'aspect_ratio': '1:1'})['result']
                save()
            t = wait('text-to-image', s['image_task'])
            if t['status'] != 'SUCCEEDED':
                raise RuntimeError(f'image {t["status"]}: {t.get("task_error")}')
            s['image_url'] = t['image_urls'][0]
            fetch(s['image_url'], OUT / 'images' / f'{name}.png')
            save()
        if not (OUT / 'glb' / f'{name}.glb').exists():
            if 'mesh_task' not in s:
                s['mesh_task'] = call('POST', '/image-to-3d', {
                    'image_url': s['image_url'], 'ai_model': 'latest', 'should_texture': True, 'enable_pbr': False,
                    'should_remesh': True, 'topology': 'triangle', 'target_polycount': tris, 'target_formats': ['glb']})['result']
                save()
            t = wait('image-to-3d', s['mesh_task'])
            if t['status'] != 'SUCCEEDED':
                raise RuntimeError(f'mesh {t["status"]}: {t.get("task_error")}')
            fetch(t['model_urls']['glb'], OUT / 'glb' / f'{name}.glb')
        s['done'] = True
        s.pop('error', None)
        print('OK', name, flush=True)
    except Exception as e:
        s['error'] = str(e)[:300]
        print('FAIL', name, s['error'], flush=True)
    save()


if __name__ == '__main__':
    names = sys.argv[1:] or list(PROPS)
    with ThreadPoolExecutor(6) as pool:
        list(pool.map(run, names))
    print('balance', call('GET', '/balance'))
