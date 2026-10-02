# Level 4 cinema: owner layout edits on top of the Studio dump -> l4_layout.json.
# Both the Blender build and the Roblox collider/placement data read l4_layout.json, so the
# visual meshes and the invisible collision stay identical.
#
# 2026-09-30 owner requests:
#  1. Walls above openings must be flat. The facades carry a 0.22-stud plaster skin, but the header
#     blocks over every opening have none, so each header sat recessed ("hakker"). Every header gets a
#     flush skin matching the facing panels beside it, clipped around panels already on that plane.
#  2. The Concessions opening is taller: its top goes from Y 36 to Y 44 (12 -> 20 studs).
#
# 2026-10-01 facelift v3 owner requests (G:\Roblox\_local\l4facelift\v3\BRIEF.md), see V3 EDITS below:
#  3. Cinema 1 west side (points 12/13): C1, the passage north of the maintenance core and the passage west of it are
#     unreachable and removed; solid walls seal the lobby flush with the core's east face; A1's west entry is closed.
#  4. The projection booth front supports that cut through the last seat row are deleted (point 10).
#  5. The checker strip in front of the concession counter is deleted, so the carpet shows (point 6).
#  6. The arcade doorway moves to the middle of the room, X 23187-23197, Y 24-37 (point 8).
#  7. The service doorway narrows to one leaf, X 22860-22868, Y 24-36 (point 11).
#  8. The concession backsplash becomes theme wallpaper above matching lacquer wainscot (point 4).
#
# INDEX ALIGNMENT: export_l4.py and make_place.py pair layout part i with l4_dump.json part i (the original CFrame
# of carriers and flicker fixtures). So the edits never reorder or drop parts: they change parts in place, append
# new parts after the dump's, and turn deleted parts into tombstones (path "Removed/_", "was" = the old path,
# Transparency 1, CanCollide false, no tags / decals / attributes). Nothing in the pipeline matches "Removed/_".
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
        if not name.endswith("_Header") or h["t"] >= 0.95 or not axis_aligned(h) or h.get("noskin"):
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


# ======================================================================================== V3 EDITS (2026-10-01)
REMOVED = "Removed/_"
DROP_KEYS = ("tags", "dec", "at", "tex", "mesh", "sm")
LOG = {}


def tomb(p, why):
    """Delete a part without moving any other part's index (see INDEX ALIGNMENT)."""
    if p["p"] == REMOVED:
        return
    p["was"], p["p"], p["why"] = p["p"], REMOVED, why
    p["t"], p["cc"], p["c"], p["removed"] = 1, False, "Part", True
    for k in DROP_KEYS:
        p.pop(k, None)
    LOG.setdefault("removed: " + why, []).append(p["was"])


def set_box(p, lo=(None,) * 3, hi=(None,) * 3):
    """Move faces of an axis-aligned part to new world coordinates (None keeps that face)."""
    assert axis_aligned(p), p["p"]
    a, b = box(p)
    a = np.array([a[k] if lo[k] is None else lo[k] for k in range(3)], float)
    b = np.array([b[k] if hi[k] is None else hi[k] for k in range(3)], float)
    assert np.all(b - a > 0.01), (p["p"], a, b)
    R = np.array(p["cf"][3:]).reshape(3, 3)
    p["cf"][:3] = [round(float(v), 3) for v in (a + b) / 2]
    p["s"] = [round(float(v), 3) for v in np.abs(R).T @ (b - a)]
    p["edit"] = True
    LOG.setdefault("resized", []).append(p["p"])


def find(parts, path, lo=None, hi=None, tol=0.1):
    """The one part with this path whose world box has the given low / high corner values (None = any)."""
    hits = []
    for p in parts:
        if p["p"] != path:
            continue
        a, b = box(p)
        if lo is not None and any(v is not None and abs(a[k] - v) > tol for k, v in enumerate(lo)):
            continue
        if hi is not None and any(v is not None and abs(b[k] - v) > tol for k, v in enumerate(hi)):
            continue
        hits.append(p)
    assert len(hits) == 1, (path, lo, hi, len(hits))
    return hits[0]


def add_part(parts, path, lo, hi, like, cc):
    q = aa_part(path, np.array(lo, float), np.array(hi, float), like)
    q["cc"] = cc
    parts.append(q)
    LOG.setdefault("added", []).append(path)
    return q


def X(v):
    return (v, None, None)


# ---- 3. Cinema 1 west side ---------------------------------------------------------------------------------------
# Removed zones, tested on part centres at ground level (centre Y < 84; the gallery above stays):
C1_ZONES = [                             # (parts centred on the seal line itself, X 22676, are lobby trims: kept)
    ((22624, 22675.8), (-240, -20)),     # the C1 corridor itself (C1/* parts and e.g. Shell/C1_GroundJoint)
    ((22624, 22675.8), (-20, 0)),        # north passage (the C1 mouth, under the gallery)
    ((22624, 22647), (0, 100.5)),        # west passage beside the maintenance core
    ((22647, 22675.8), (97.8, 100.5)),   # 2-stud strip between the core's south wall and the concourse south wall:
]                                        # a second way round the core into the west passage
SEAL_X = 22676.0                         # lobby face of the new walls = the core's east face = A1's west wall line
# Structural shell / core walls that enclose the removed zones stay; so does the core stair room ("perfekt").
C1_KEEP = re.compile(r"^Shell/(BaseSlab|ShellSide|GallerySideFascia|C1BlockWall|C1BlockWallSouth)$"
                     r"|^HiddenService/Core(North|South|East|West|Roof)(_Sill|_Header)?$|^HiddenService/StaffGroundRunner$")


def in_c1_zone(c):
    return c[1] < 84 and any(x0 <= c[0] <= x1 and z0 <= c[2] <= z1 for (x0, x1), (z0, z1) in C1_ZONES)


def cinema1_west(parts):
    for p in parts:
        if p["p"].startswith("C1/"):
            tomb(p, "C1 corridor")
    for p in parts:
        if p["p"] == REMOVED or C1_KEEP.search(p["p"]):
            continue
        a, b = box(p)
        if in_c1_zone((a + b) / 2):
            tomb(p, "C1 passages")
        elif a[0] < SEAL_X - 0.01 and b[0] > SEAL_X + 0.5 and b[1] < 84 and any(
                min(SEAL_X, b[0], x1) - max(a[0], x0) > 0.5 and min(b[2], z1) - max(a[2], z0) > min(0.5, 0.9 * (b[2] - a[2]))
                for (x0, x1), (z0, z1) in C1_ZONES):        # reaches from the lobby into a removed zone:
            set_box(p, lo=X(SEAL_X))                       # lobby carpet, south facade strips, cove: clip at the seal
            LOG.setdefault("clipped at the seal", []).append(p["p"])
    like = find(parts, "HiddenService/CoreEast", lo=(22674, 24, 0))
    # North block wall: from A1's rear wall (its whole thickness, Z -22..-20) to the core's north-east corner (Z 0),
    # up to the gallery floor. Lobby plaster colour, so build_base gives it the theme wallpaper; solid, so the
    # exporter makes it a collider and a camera occluder.
    w = add_part(parts, "Shell/C1BlockWall", (SEAL_X - 2, 24, -22), (SEAL_X, 85, 0), like, True)
    w["col"] = [141, 54, 30]
    # South seal: closes the strip south of the core (Z 98..100) up to the lobby roof.
    w = add_part(parts, "Shell/C1BlockWallSouth", (SEAL_X - 2, 24, 98), (SEAL_X, 61, 100), like, True)
    w["col"] = [141, 54, 30]
    # A1 west entry (it opened onto C1's stair landing): one solid west wall over the full length and height.
    tomb(find(parts, "A1/A1_WallWest", lo=(22676, 24, -238)), "A1 west entry")
    set_box(find(parts, "A1/A1_WallWest", lo=(22676, 24, -124)), lo=(None, None, -238.0))
    for path in ("A1/A1_WallWest_Header", "A1/A1_WallWest_Sill", "A1/A1_EntryWest"):
        tomb(find(parts, path), "A1 west entry")
    for p in parts:                                          # frames + sign on both faces of the closed entry
        if re.match(r"^A1/A1_(EntryFrame_Head|EntryFrame_Jamb|EntrySign)$", p["p"]) and box(p)[1][0] < 22679:
            tomb(p, "A1 west entry")


# ---- 4. booth front supports -------------------------------------------------------------------------------------
def booth_supports(parts):
    for a in ("A1", "A2", "A3"):
        tomb(find(parts, "%s/%s_BoothFrontSupport" % (a, a)), "booth front support")


# ---- 5. concession checker strip ---------------------------------------------------------------------------------
def checker_strip(parts):
    for p in parts:
        if re.match(r"^Concession/Checker_(White|Red|Black)$", p["p"]):
            tomb(p, "concession checker strip")


def concession_back_wall(parts):
    """Replace every backsplash tile, including cream tiles, with the existing wallpaper finish."""
    for p in parts:
        if p["p"] == "Concession/CheckerBacksplash":
            tomb(p, "concession checker backsplash")
        elif p["p"] == "Concession/SpawnWeatheredBackWall":
            p["cf"][1], p["s"][1], p["edit"] = 40, 24, True  # paper meets the wainscot at Y28; keep the 0.01-stud skin
    like = find(parts, "Concourse/SouthFacadeWainscot", hi=X(23055))
    # Same four-stud lower band as the lobby; arch_detail's existing band builder adds its lacquer skirting/cap.
    for x0, x1 in ((22880, 23055), (23095, 23120)):
        add_part(parts, "Concession/BackWainscot", (x0, 24, 102.005), (x1, 28, 102.395), like, False)


# ---- 6 + 7. doorways in the concourse south wall (Z 100..102) ----------------------------------------------------
# The walls, the lobby-side facade strips (wainscot Y 24-28, plaster Y 28-55.5) and the service-side wall finish are
# re-segmented so the old opening is solid and the new one is cut exactly. The plaster over the new opening is an
# explicit piece, so these two headers get no flush skin (flush_headers skips "noskin").
DOORWAYS = {
    #           old x0, x1, top        new x0, x1, top
    "Arcade": ((23150, 23178, 36), (23187, 23197, 37)),
    "Service": ((22854, 22874, 36), (22860, 22868, 36)),
}


def remap_x(v, old, new):
    if v <= old[0] + 0.05:
        return v + new[0] - old[0]
    if v >= old[1] - 0.05:
        return v + new[1] - old[1]
    raise ValueError(v)


def move_doorway(parts, name):
    old, new = DOORWAYS[name]
    (ox0, ox1, otop), (nx0, nx1, ntop) = old, new
    for path in ("Shell/ConcourseSouthWall", "Concourse/SouthFacadeWainscot", "Concourse/SouthFacadePlaster"):
        set_box(find(parts, path, hi=X(ox0)), hi=X(nx0))
        set_box(find(parts, path, lo=X(ox1)), lo=X(nx1))
    hdr = find(parts, "Shell/ConcourseSouthWall_Header", lo=X(ox0), hi=X(ox1))
    set_box(hdr, lo=(nx0, ntop, None), hi=X(nx1))
    hdr["noskin"] = True
    set_box(find(parts, "Shell/%sDoorway" % name), lo=X(nx0), hi=(nx1, ntop, None))
    set_box(find(parts, "Shell/%sDoorwayThreshold" % name), lo=X(nx0), hi=X(nx1))
    like = find(parts, "Concourse/SouthFacadePlaster", lo=X(nx1))      # plaster over the new opening
    a, b = box(like)
    add_part(parts, "Concourse/SouthFacadePlaster", (nx0, ntop, a[2]), (nx1, b[1], b[2]), like, False)
    d = ntop - otop                      # the old opening's casing parts follow its edges (package A rebuilds the
    for p in parts:                      # casings from the markers; these keep the layout consistent)
        if re.match(r"^Concourse/%sDoorway(DeepJamb|DeepHeader|Frame_Head|Frame_Jamb)$" % name, p["p"]):
            a, b = box(p)
            set_box(p, lo=(remap_x(a[0], old, new), a[1] + d if a[1] >= otop - 0.05 else None, None),
                    hi=(remap_x(b[0], old, new), b[1] + d if b[1] >= otop - 0.05 else None, None))
    if name == "Service":
        set_box(find(parts, "Service/ServiceNorthWallFinish", hi=X(ox0)), hi=X(nx0))
        set_box(find(parts, "Service/ServiceNorthWallFinish", lo=X(ox1)), lo=X(nx1))
        set_box(find(parts, "Service/ServiceNorthWallFinish", lo=X(ox0), hi=X(ox1)), lo=X(nx0), hi=X(nx1))
    if name == "Arcade":
        for p in [p for p in parts if p["p"] == "Arcade/ArcadeSidelight"]:
            tomb(p, "old arcade opening")
        # ARCADE SurfaceGui sign: centred over the new door, as much higher as the door, 24 wide (was 28) so it
        # stays clear of the facade pilaster at X 23204.4
        sign = find(parts, "Concourse/ArcadeDoorwaySign")
        a, b = box(sign)
        cx = (nx0 + nx1) / 2
        set_box(sign, lo=(cx - 12, a[1] + d, None), hi=(cx + 12, b[1] + d, None))


# ---- self-check --------------------------------------------------------------------------------------------------
def self_check(parts, dump_parts):
    errs = []
    for i in range(len(dump_parts)):                        # index alignment with the dump
        if parts[i]["p"] not in (dump_parts[i]["p"], REMOVED):
            errs.append("index %d: %s != dump %s" % (i, parts[i]["p"], dump_parts[i]["p"]))
        if (dump_parts[i]["p"].startswith("C4/") or dump_parts[i]["cf"][1] >= 84) and parts[i] != dump_parts[i]:
            errs.append("changed protected C4/upstairs part: " + dump_parts[i]["p"])
    live = [p for p in parts if p["p"] != REMOVED]
    if any(p["p"].startswith("C1/") for p in live):
        errs.append("C1 parts left")
    for p in live:
        a, b = box(p)
        if in_c1_zone((a + b) / 2) and not C1_KEEP.search(p["p"]):
            errs.append("left in a removed zone: " + p["p"])
        if b[1] < 84 and a[0] < SEAL_X - 0.2 and b[0] > SEAL_X + 0.2 and a[2] < 100 and b[2] > -20 \
                and not C1_KEEP.search(p["p"]) and p["t"] < 0.95:
            errs.append("crosses the seal: " + p["p"])

    def check_wall(label, rx, z, y, x0, x1, holes):
        """Every 0.25-stud cell along X at (y, z) is covered by exactly one part matching rx (none in a hole)."""
        sel = [box(p) for p in live if re.search(rx, p["p"]) and p["t"] < 0.95]
        xs = np.arange(x0 + 0.125, x1, 0.25)
        cnt = sum(((xs > a[0]) & (xs < b[0]) & (a[1] < y < b[1]) & (a[2] < z < b[2])).astype(int) for a, b in sel)
        want = np.ones(len(xs), int)
        for h0, h1, top in holes:
            want[(xs > h0) & (xs < h1) & (y < top)] = 0
        bad = xs[cnt != want]
        if len(bad):
            errs.append("%s y=%.1f: coverage wrong at x %.2f..%.2f (counts %s)"
                        % (label, y, bad.min(), bad.max(), sorted(set(cnt[cnt != want].tolist()))))

    for name, (old, new) in DOORWAYS.items():
        x0, x1 = min(old[0], new[0]) - 15, max(old[1], new[1]) + 15
        for y in (24.5, 30.0, 36.5, 37.5, 45.0, 59.5):
            check_wall(name + " wall", r"^Shell/ConcourseSouthWall(_Header)?$", 101.0, y, x0, x1, [new])
        for y in (26.0, 30.0, 36.5, 37.5, 50.0):
            check_wall(name + " facade", r"^Concourse/SouthFacade(Wainscot|Plaster)$", 99.83, y, x0, x1, [new])
        a, b = box(find(live, "Shell/%sDoorway" % name))
        if not (np.allclose([a[0], a[1], b[0], b[1]], [new[0], 24, new[1], new[2]])):
            errs.append("%s marker at %s..%s" % (name, a, b))
        a, b = box(find(live, "Shell/%sDoorwayThreshold" % name))
        if not np.allclose([a[0], b[0]], new[:2]):
            errs.append(name + ": threshold does not match the opening")
        if any(p["p"].endswith("_Header_FlushSkin") and abs(box(p)[0][2] - 100) < 3 and box(p)[0][0] < x1
               and box(p)[1][0] > x0 for p in live):
            errs.append("%s: stale header skins" % name)
    check_wall("service finish", r"^Service/ServiceNorthWallFinish$", 102.03, 30.0, 22830, 22878,
               [DOORWAYS["Service"][1]])
    zs = np.arange(-237.875, -22, 0.25)                     # A1 west wall solid from Z -238 to -22
    walls = [box(p) for p in live if p["p"].startswith("A1/A1_WallWest")]
    for y in (24.5, 30, 47, 60, 83, 90, 103.5):
        cnt = sum(((zs > a[2]) & (zs < b[2]) & (a[1] < y < b[1])).astype(int) for a, b in walls)
        if not np.all(cnt == 1):
            errs.append("A1 west wall coverage y=%d: %s" % (y, sorted(set(cnt.tolist()))))
    if any(re.search(r"A1_Entry(West|Frame|Sign)", p["p"]) and box(p)[1][0] < 22679 for p in live):
        errs.append("A1 west entry parts left")
    for path, lo, hi in (
            ("Shell/C1BlockWall", (SEAL_X - 2, 24, -22), (SEAL_X, 85, 0)),
            ("Shell/C1BlockWallSouth", (SEAL_X - 2, 24, 98), (SEAL_X, 61, 100))):
        p = find(live, path)
        a, b = box(p)
        if not p["cc"] or p["t"] != 0 or not np.allclose(a, lo) or not np.allclose(b, hi):
            errs.append("incomplete solid passage seal: " + path)
    booth = [box(p) for p in live if re.match(r"^A\d/A\d_Booth", p["p"]) and p["t"] < 0.95]
    for p in live:                                           # no seat cut by what remains of the booths
        if re.match(r"^A\d/A\d_Chair(Seat|Back)$", p["p"]):
            a, b = box(p)
            if any(np.all(np.minimum(b, d) - np.maximum(a, c) > 0.01) for c, d in booth):
                errs.append("seat %s cut by a booth part" % p["p"])
    if any(re.match(r"^Concession/Checker_(White|Red|Black)$", p["p"]) for p in live):
        errs.append("checker strip left")
    if any(p["p"] == "Concession/CheckerBacksplash" for p in live):
        errs.append("checker backsplash left")
    check_wall("concession back wainscot", r"^Concession/BackWainscot$", 102.2, 26, 22880, 23120,
               [(23055, 23095, 44)])
    for y in (28.125, 30, 37.5, 45, 51.875):
        check_wall("concession back wallpaper", r"^Concession/(SpawnWeatheredBackWall|SpawnPassageHeaderFinish)$",
                   102.01, y, 22880, 23120, [(23055, 23095, 44)])
    # new / moved solid walls must not overlap another solid wall (duplicate walls); pre-existing overlaps of the
    # same pair in the dump are not counted
    # Compare the exact source indices: repeated wall paths are not interchangeable baselines.
    orig = {id(p): box(dump_parts[i]) for i, p in enumerate(parts[:len(dump_parts)])}

    def ov(a, b, c, d):
        return np.all(np.minimum(b, d) - np.maximum(a, c) > 0.05)

    edited = [p for p in live if p.get("edit") and p["cc"] and p["t"] < 0.95]
    others = [p for p in live if p["cc"] and p["t"] < 0.95 and p["m"] == "SmoothPlastic" and max(p["s"]) >= 6]
    for p in edited:
        a, b = box(p)
        for q in others:
            c, d = box(q)
            if q is p or not ov(a, b, c, d):
                continue
            if id(p) in orig and id(q) in orig and ov(*orig[id(p)], *orig[id(q)]):
                continue
            errs.append("overlap %s / %s" % (p["p"], q["p"]))
    return errs


def apply_v3(parts):
    cinema1_west(parts)
    booth_supports(parts)
    checker_strip(parts)
    concession_back_wall(parts)
    move_doorway(parts, "Arcade")
    move_doorway(parts, "Service")


if __name__ == "__main__":
    parts = copy.deepcopy(P)
    changed = taller_concessions(parts)
    apply_v3(parts)
    skins = flush_headers(parts)
    parts += skins
    errs = self_check(parts, P)
    for k, v in LOG.items():
        print("%-34s %4d  %s" % (k, len(v), ", ".join(sorted(set(v)))[:400]))
    print("concessions parts moved:", len(changed), sorted(set(changed)))
    print("flush skins:", len(skins))
    if errs:
        print("SELF-CHECK FAILED, l4_layout.json not written:")
        for e in errs:
            print("  ", e)
        raise SystemExit(1)
    dst = os.path.join(HERE, "l4_layout.json")
    with open(dst + ".tmp", "w") as fh:
        json.dump(dict(D, parts=parts), fh)
    json.load(open(dst + ".tmp"))
    os.replace(dst + ".tmp", dst)
    print("self-check ok; wrote", dst, len(parts), "parts,", sum(p["p"] == REMOVED for p in parts), "tombstones")
