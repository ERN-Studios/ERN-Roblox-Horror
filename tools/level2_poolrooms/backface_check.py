"""Find kit mesh faces that the interior sees from BEHIND (Roblox culls them: you see through).

Blender renders and BVH ray tests treat faces as double-sided; Roblox MeshParts are not.
A ray from an interior sample whose first mesh hit has dot(ray, normal) > 0 is looking at
a back face. Reported per (component, material chunk); exit 1 if any.

Run: D:/Blender/blender.exe -b --factory-startup --python-exit-code 1 \
    -P tools/level2_poolrooms/backface_check.py -- 837834
"""
from collections import Counter
from pathlib import Path
import sys

import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import world_check as wc  # noqa: E402
from render_world import fixture_chunk, load_kit_chunks, mesh_triangles_world  # noqa: E402


def main():
    seed = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "837834"
    import json
    world = json.loads((wc.WORLDS / f"world_{seed}.json").read_text(encoding="utf-8"))
    chunks = load_kit_chunks(world)
    tris, owner = [], []
    for part in world["parts"]:
        if part["transparency"] >= 0.98:
            continue
        if part["fixtureKind"] == "mesh":
            t = mesh_triangles_world(part, fixture_chunk(part, chunks))
            label = f"{part['fixtureComponent']}/{part['name'].rsplit('_', 1)[-1]}"
        elif part["class"] != "MeshPart":
            t = wc.part_triangles(part)
            label = None  # closed Roblox primitive: visible from outside, never culled wrongly
        else:
            continue
        tris.append(np.asarray(t, dtype=np.float32))
        owner.extend([label] * len(t))
    triangles = np.concatenate(tris)
    bvh = wc.make_bvh(triangles)
    rays = wc.directions(128)
    back, front = Counter(), Counter()
    where = {}
    for origin, label in wc.sample_points(world["layout"]):
        o = Vector(origin)
        for ray in rays:
            d = Vector(ray)
            loc, normal, index, _ = bvh.ray_cast(o, d, 2500)
            if loc is None or owner[index] is None:
                continue
            if normal.dot(d) > 0:
                back[owner[index]] += 1
                where.setdefault(owner[index], (label, [round(v, 1) for v in loc]))
            else:
                front[owner[index]] += 1
    for key, n in back.most_common():
        print(f"BACKFACE {key}: {n} back hits vs {front[key]} front  e.g. from {where[key][0]} at {where[key][1]}")
    print(f"BACKFACE_TOTAL {sum(back.values())} hits in {len(back)} chunks; front hits {sum(front.values())}")
    sys.exit(1 if back else 0)


main()
