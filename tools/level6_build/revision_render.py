"""Render actual revised Blender room studies for visual review."""
import bpy
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/level6-blender-revision-20260930'
PREVIEWS = OUT / 'previews'
PREVIEWS.mkdir(exist_ok=True)
requested = set(sys.argv[sys.argv.index('--') + 1:]) if '--' in sys.argv else set()
record = []
for scene in sorted(bpy.data.scenes, key=lambda s: s.name):
    if not scene.name.startswith('Revision study '):
        continue
    index = scene.name.split()[2]
    if requested and index not in requested:
        continue
    bpy.context.window.scene = scene
    scene.render.resolution_x, scene.render.resolution_y = 960, 640
    scene.render.resolution_percentage = 100
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.filepath = str(PREVIEWS / (index + '.png'))
    bpy.ops.render.render(write_still=True)
    file = Path(scene.render.filepath)
    record.append({'scene': scene.name, 'file': str(file.relative_to(OUT)),
                   'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
                   'scope': 'Actual offline Blender render; no Roblox gameplay or performance test'})
existing = PREVIEWS / 'render-records.json'
prior = json.loads(existing.read_text()) if existing.exists() else []
final = {r['scene']: r for r in prior + record}
existing.write_text(json.dumps(list(final.values()), indent=2) + '\n')
print('LEVEL6_REVISION_RENDERS', json.dumps(record), flush=True)
