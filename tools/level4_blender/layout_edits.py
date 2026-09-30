# Level 4 cinema: owner layout edits on top of the Studio dump -> l4_layout.json.
# Both the Blender build and the Roblox collider/placement data read l4_layout.json, so the
# visual meshes and the invisible collision stay identical.
#
# 2026-09-30 owner requests:
#  1. Walls above openings must be flat. The facades carry a 0.22-stud plaster skin, but the header
#     blocks over every opening have none, so each header sat recessed ("hakker"). Every header gets a
#     flush skin matching the facing panels beside it, clipped around panels already on that plane.
#  2. The Concessions opening is taller: its top goes from Y 36 to Y 44 (12 -> 20 studs).
import copy, json, os, re
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
D = json.load(open(os.path.join(HERE, "l4_dump.json")))
P = D["parts"]
FACING_MATS = {"SmoothPlastic", "CeramicTiles", "Plastic", "Concrete", "Fabric"}


def box(p):
    R = np.array(p["cf"][3:]).reshape(3, 3)
    ext = np.abs(R) @ (np.array(p["s"]) / 2)
    c = np.array(p["cf"][:3])
    return c - ext, c + ext


def axis_aligned(p):
    R = np.array(p["cf"][3:]).reshape(3, 3)
    return np.allclose(np.abs(R), np.round(np.abs(R)), atol=1e-3)


def aa_part(name, lo, hi, like):
    q = copy.deepcopy(like)
    c = (lo + hi) / 2
    q["p"] = name
    q["cf"] = [round(float(c[0]), 3), round(float(c[1]), 3), round(float(c[2]), 3), 1, 0, 0, 0, 1, 0, 0, 0, 1]
    q["s"] = [round(float(v), 3) for v in hi - lo]
    q["cc"] = False
    q.pop("dec", None); q.pop("tags", None); q.pop("at", None)
    q["edit"] = True
    return q


def subtract(iv, cuts):
    out = [iv]
    for a, b in cuts:
        nxt = []
        for x, y in out:
            if b <= x or a >= y:
                nxt.append((x, y))
                continue
            if a > x:
                nxt.append((x, a))
            if b < y:
                nxt.append((b, y))
        out = nxt
    return [(x, y) for x, y in out if y - x > 0.05]


def flush_headers(parts):
    boxes = [box(p) for p in parts]
    added = []
    for hi_idx, h in enumerate(parts):
        name = h["p"].rsplit("/", 1)[-1]
        if not name.endswith("_Header") or h["t"] >= 0.95 or not axis_aligned(h):
            continue
        lo, hi = boxes[hi_idx]
        th = int(np.argmin(hi - lo))
        if th == 1:
            continue
        ax = 2 if th == 0 else 0            # horizontal axis along the wall
        for sgn, plane in ((-1, lo[th]), (1, hi[th])):
            facing, coplanar = [], []
            for j, p in enumerate(parts):
                if j == hi_idx or p["t"] >= 0.95 or not axis_aligned(p):
                    continue
                a, b = boxes[j]
                t = int(np.argmin(b - a))
                if t != th or (b - a)[t] > 0.6:
                    continue
                back = a[t] if sgn > 0 else b[t]
                if abs(back - plane) > 0.15:
                    continue
                if b[1] < lo[1] - 0.1 or a[1] > hi[1] + 0.1:
                    continue
                if b[ax] < lo[ax] - 0.05 or a[ax] > hi[ax] + 0.05:
                    continue
                inside = a[ax] >= lo[ax] - 0.05 and b[ax] <= hi[ax] + 0.05
                if p["m"] not in FACING_MATS:
                    continue
                if inside:
                    if b[ax] - a[ax] >= (hi[ax] - lo[ax]) * 0.9:
                        coplanar.append((a[1], b[1], a[th], b[th]))
                elif (b - a)[1] > 3:
                    facing.append((float((b - a)[ax] * (b - a)[1]), j))
            if not facing:
                continue
            _, fj = max(facing)
            f = parts[fj]
            fa, fb = boxes[fj]
            # only skins on the very same plane (same front face) cut the new skin
            front = fa[th] if sgn < 0 else fb[th]
            cuts = [(y0, y1) for y0, y1, a0, b0 in coplanar if abs((a0 if sgn < 0 else b0) - front) < 0.03]
            for y0, y1 in subtract((lo[1], hi[1]), cuts):
                nlo, nhi = lo.copy(), hi.copy()
                nlo[1], nhi[1] = y0, y1
                if sgn > 0:
                    nlo[th], nhi[th] = hi[th] + (fa[th] - hi[th]), hi[th] + (fb[th] - hi[th])
                else:
                    nlo[th], nhi[th] = lo[th] - (lo[th] - fa[th]), lo[th] - (lo[th] - fb[th])
                added.append(aa_part(h["p"] + "_FlushSkin", nlo, nhi, f))
    return added


def taller_concessions(parts):
    """Concessions opening: top Y 36 -> 44. Only parts spanning that opening (x 23053..23097, z 99..103)."""
    RAISE = 8.0
    changed = []
    for p in parts:
        x, y, z = p["cf"][:3]
        n = p["p"].rsplit("/", 1)[-1]
        if not (23050 <= x <= 23100 and 98.5 <= z <= 103.5):
            continue
        if n == "ConcourseSouthWall_Header":            # y 36..60 -> 44..60
            p["cf"][1] = 52.0; p["s"][1] = 16.0
        elif n == "ConcessionsDoorway":                  # invisible marker, y 24..36 -> 24..44
            p["cf"][1] = 34.0; p["s"][1] = 20.0
        elif n in ("ConcessionsDoorwayDeepHeader", "ConcessionsDoorwayFrame_Head", "ConcessionsDoorwaySign"):
            p["cf"][1] += RAISE
        elif n in ("ConcessionsDoorwayDeepJamb", "ConcessionsDoorwayFrame_Jamb"):
            p["cf"][1] += RAISE / 2; p["s"][1] += RAISE
        elif n == "SpawnPassageHeaderFinish":            # y 36..52 -> 44..52
            p["cf"][1] = 48.0; p["s"][1] = 8.0
        else:
            continue
        p["edit"] = True
        changed.append(n)
    return changed


if __name__ == "__main__":
    parts = copy.deepcopy(P)
    changed = taller_concessions(parts)
    skins = flush_headers(parts)
    parts += skins
    out = dict(D, parts=parts)
    json.dump(out, open(os.path.join(HERE, "l4_layout.json"), "w"))
    print("concessions parts moved:", len(changed), sorted(set(changed)))
    print("flush skins:", len(skins))
    for s in skins:
        print("  ", s["p"], s["cf"][:3], s["s"], s["m"], s["col"])
