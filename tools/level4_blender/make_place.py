# Level 4 cinema: manifest.json (export_l4.py) + textures.json -> the compact placement file place.luau reads
# (served as chunk 99999).
#   python make_place.py [export_dir] [out_file]      (defaults: the export dir, <export_dir>/chunks/c99999.b64)
#   python make_place.py --tex-requests [export_dir]  every map the exported chunks use that textures.json lacks is
#       copied to TEX_OUT (G:\Roblox\_local\l4blender\tex, served at http://127.0.0.1:8766/tex/<file> by e.g.
#       `python -m http.server 8766 -d G:\Roblox\_local\l4blender`), and TEX_OUT\..\tex_requests.json gets the
#       Studio MCP upload_image requests: {"batches": [{"imagePaths": [url, ...]}, ...], "files": {url: file}}
#   python make_place.py --tex-merge <result.json> ...   merges upload_image answers ({url: "rbxassetid://n"}) into
#       textures.json, keyed by file name
#   python make_place.py --selftest                    asserts the occluder inset, zone filter, carrier moves
# Reads version 2 manifests (PBR fields, collider kinds, lights, propColliders, occluder flags, tags).
# Texture ids come from textures.json, keyed by file name; a map that is not uploaded yet is left out (listed).
# On top of the manifest (v3, 2026-10-01):
#   * camera occluders: a collider flagged "occ" is inset OCC_INSET studs on every axis (place.luau shows it black,
#     Transparency 0, so Poppercam stops at it). Axes that would drop below OCC_FLOOR keep their original size;
#     such thin colliders stay invisible. Eligible occluders use SmoothPlastic with their tags preserved;
#   * Signage carriers whose original part stood in the removed Cinema 1 west zone (REMOVED_ZONES) are left out,
#     and CARRIER_MOVE re-seats a carrier (path regex + original centre -> new CFrame, layout frame);
#   * the original preview's ceiling lights (LEGACY_CEILING) are never cloned, whatever "L4 Lights" still holds.
import json, os, re, shutil, sys, urllib.parse, itertools, collections

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = r"G:\Roblox\_local\l4blender\export"
MAPS = (("c", "tex"), ("n", "normal"), ("r", "rough"), ("m", "metal"))   # SurfaceAppearance map <- manifest field
TEX_DIRS = (r"G:\Blender\Level4_Cinema\textures\pbr", r"G:\Blender\Level4_Cinema\textures")   # where maps live
TEX_OUT = r"G:\Roblox\_local\l4blender\tex"
TEX_URL = "http://127.0.0.1:8766/tex/"
BATCH = 20
# Tuned in a Studio play test (2026-10-01, LightingStyle Realistic + the Level 4 Lighting Controller grade): the
# Blender light values came out far too dim in Roblox, and the lightbox / marquee board faces (EMIT_WARM
# 255,240,214) bloomed so hard that the poster decals laid over them vanished.
# v3 play test 2026-10-02 (owner: "you must be able to see everything", neon + star ceiling light it): the v3 lights
# need 3x the v2 gain, the star fill 5x and longer reach; tall auditoria hang their star fills at Y 80 so they reach
# the front rows within Roblox's 60-stud range.
LIGHT_GAIN, RANGE_GAIN, RANGE_MAX = 2.7, 1.56, 60.0
AUD_BOX = ((22677, 23323), (-232, -20))     # the three auditoria (Studio x, z)
# v2 lit the auditoria with too few fixtures and needed 4.6 / 1.25 here; v3 lights them to the brief (star fill +
# coves), so they start neutral. Retune live.
AUD_GAIN, AUD_RANGE_GAIN = 1.0, 1.0
KIND_GAIN = {"star": 5 / 3}                 # light l4_kind -> brightness factor (live tuning)
KIND_RANGE = {"star": 1.5 / 1.3}            # light l4_kind -> range factor
AUD_STAR_Y = 80.0                           # auditorium star fills above this height come down to it
STYLE_OVERRIDES = {"L4S_EMIT_WARM_fff0d6": {"m": "SmoothPlastic"},    # lit-looking white backing, not Neon
                   # the puddle water read as a black hole in the floor: a translucent dark film instead
                   "L4S_F_Water": {"m": "SmoothPlastic", "t": 0.7, "c": [0.078, 0.086, 0.118]}}

OCC_INSET, OCC_FLOOR = 0.1, 0.3             # studs
# Owner 2026-10-01 (v3 points 12/13): the Cinema 1 west side is walled off and removed. Boxes (x0, x1, y0, y1, z0, z1)
# in original Studio studs; a carrier whose original centre is inside one is left out.
REMOVED_ZONES = [
    (22624, 22676, -1e9, 1e9, -239, -20),   # C1: corridor, stair, return, roof (every height)
    (22624, 22676, -1e9, 84.999, -20, 0),   # north passage under the gallery (the gallery above stays)
    (22624, 22647, -1e9, 84.999, 0, 98),    # west passage beside the core
    (22674, 22684, 40, 60, -140, -120),     # A1's closed west entry, both faces
]
LEGACY_CEILING = re.compile(r"(Downlight|CeilingLight|CeilingLens|CeilingNeon|ReturnLight|_StairA\d(East|West)_Light"
                            r"|GalleryLamp|CagedServiceLamp|CounterWarmLight|Fluorescent|FlickerTube|MarqueeGlow)/")
# {"path": regex on the original path, "at": original centre [x, y, z] (None: any), "cf": 12 numbers (layout frame,
#  the carrier's decal face keeps its original Face), "s": new size (optional)}
CARRIER_MOVE = []


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin2srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def style(info, tex, missing):
    col = [c / 255 for c in info["color"]]
    sem, alpha = info["sem"], info.get("alpha", 1.0)
    st = {"m": info["roblox"], "c": [round(c, 4) for c in col], "t": 0}
    if info.get("tags"):
        st["tags"] = list(info["tags"])
    if sem == "glass" or alpha < 0.99:
        st["m"] = "Glass" if sem == "glass" else st["m"]
        st["t"] = round(min(0.75, 1 - alpha), 3) if sem == "glass" else round(1 - alpha, 3)
    if sem == "neon" or (info.get("emit", 0) >= 2 and not info.get("tex")):
        st["m"] = "Neon"
    if st["m"] in ("Neon", "Glass"):
        return st                                   # no SurfaceAppearance: it would replace the Neon/Glass look
    sa = {}
    for k, field in MAPS:
        fn = info.get(field)
        if fn and fn in tex:
            sa[k] = tex[fn]
        elif fn:
            missing.add(fn)
    if sa and sem == "decal":                       # alpha-cut decals: smooth blending needs Transparency >= 0.02
        sa["alpha"] = "Transparency"
        st["t"] = 0.02
    if sa:
        if "c" not in sa:
            sa["tint"] = st["c"]                    # no albedo: the tint carries the slot colour
        elif info.get("tinted", info.get("tex", "").endswith("_n.png")):
            # Blender multiplies the linear albedo by min(1, linear colour / 0.75) (slots.py); SA.Color is sRGB
            sa["tint"] = [round(lin2srgb(min(1.0, srgb2lin(c) / 0.75)), 4) for c in col]
        else:
            sa["tint"] = [1, 1, 1]
        st["sa"] = sa
    return st


def occluder_size(s):
    """Inset both faces of each eligible axis; retain the original size of an axis that would be too thin."""
    return [round(v - 2 * OCC_INSET, 4) if v - 2 * OCC_INSET >= OCC_FLOOR - 1e-9 else v for v in s]


def collider(c):
    """-> [cf, size, shape, material, tags, kind, occluder, attributes or None] (place.luau makeCollider)."""
    size, occ = c["s"], False
    if c.get("occ") and c.get("kind", "Part") == "Part":
        occ = all(v - 2 * OCC_INSET >= OCC_FLOOR - 1e-9 for v in size)
        size = occluder_size(size)
    return [c["cf"], size, c.get("sh") or "Block", "SmoothPlastic" if occ else c.get("m") or "SmoothPlastic", c.get("tags") or [],
            c.get("kind") or "Part", occ, c.get("at") or None, c.get("name")]


def gameplay_prop(p):
    return bool(p.get("door") or p.get("attrs") or p.get("tags") or p.get("gameplay") or p.get("modelGroup")
                or p.get("modelTags") or p.get("partName") or p.get("pivot") or p.get("partAttrs")
                or re.search(r"door|frame|seat|arcade|Level4V4", p.get("model", "") + " " + p.get("name", ""), re.I))


def plain_box(c):
    return (c.get("kind", "Part") == "Part" and c.get("sh", "Block") == "Block"
            and not c.get("occ") and not c.get("tags") and not c.get("at"))


def box_points(c):
    cf, size = collider(c)[:2]                     # actual placed bounds, including the camera inset
    R = [cf[3 + i * 3:6 + i * 3] for i in range(3)]
    return [[cf[i] + sum(R[i][j] * size[j] * q[j] / 2 for j in range(3)) for i in range(3)]
            for q in itertools.product((-1, 1), repeat=3)]


def box_contains(outer, points):
    cf, size = collider(outer)[:2]
    return all(abs(sum((p[i] - cf[i]) * cf[3 + i * 3 + j] for i in range(3))) <= size[j] / 2 + 1e-6
               for p in points for j in range(3))


def merge_boxes(a, b):
    """Union only exactly adjacent rectangular boxes in one frame, with identical physical semantics."""
    if (a.get("placement") != b.get("placement") or not plain_box(a) or not plain_box(b)
            or a.get("m") != b.get("m") or a["cf"][3:] != b["cf"][3:]):
        return None
    delta = [sum((b["cf"][i] - a["cf"][i]) * a["cf"][3 + i * 3 + j] for i in range(3)) for j in range(3)]
    for axis in range(3):
        if (all(abs(delta[j]) < 1e-7 and abs(a["s"][j] - b["s"][j]) < 1e-7 for j in range(3) if j != axis)
                and abs(abs(delta[axis]) - (a["s"][axis] + b["s"][axis]) / 2) < 1e-7):
            lo = min(-a["s"][axis] / 2, delta[axis] - b["s"][axis] / 2)
            hi = max(a["s"][axis] / 2, delta[axis] + b["s"][axis] / 2)
            merged = dict(a, cf=list(a["cf"]), s=list(a["s"]))
            for i in range(3):
                merged["cf"][i] = a["cf"][i] + a["cf"][3 + i * 3 + axis] * (lo + hi) / 2
            merged["s"][axis] = hi - lo
            return merged
    return None


def optimise_prop_colliders(m):
    """Preserve gameplay/occluder boxes; remove only redundant invisible ordinary prop boxes."""
    original = m.get("propColliders", [])
    placements = m.get("placements", [])
    candidates = {i for i, c in enumerate(original) if plain_box(c)
                  and c["placement"] < len(placements) and not gameplay_prop(placements[c["placement"]])}
    containers = [c for c in m.get("colliders", []) + original
                  if c.get("kind", "Part") == "Part" and c.get("sh", "Block") == "Block"]
    bounds = []
    for c in containers:
        pts = box_points(c)
        bounds.append((c, [min(p[j] for p in pts) for j in range(3)], [max(p[j] for p in pts) for j in range(3)]))
    kept, removed, report = [], set(), []
    # ponytail: bounded level export scans boxes quadratically; use a spatial index if export profiling needs it.
    for i, c in enumerate(original):
        if i not in candidates:
            kept.append(dict(c))
            continue
        points = box_points(c)
        lo, hi = [min(p[j] for p in points) for j in range(3)], [max(p[j] for p in points) for j in range(3)]
        outer = next((b for b, blo, bhi in bounds if b is not c and id(b) not in removed
                      and all(blo[j] <= lo[j] + 1e-6 and bhi[j] >= hi[j] - 1e-6 for j in range(3))
                      and box_contains(b, points)), None)
        if outer is None:
            kept.append(dict(c))
        else:
            removed.add(id(c))
            report.append({"src": c.get("src"), "placement": c["placement"], "reason": "contained", "by": outer.get("src")})
    contained = len(report)
    by_prop = collections.defaultdict(list)
    for c in kept:
        by_prop[c["placement"]].append(c)
    kept = []
    for pi, boxes in by_prop.items():
        changed = True
        while changed and pi < len(placements) and not gameplay_prop(placements[pi]):
            changed = False
            for i in range(len(boxes)):
                for j in range(i + 1, len(boxes)):
                    merged = merge_boxes(boxes[i], boxes[j])
                    if merged:
                        report.append({"src": boxes[i].get("src"), "placement": pi, "reason": "adjacent"})
                        boxes[i] = merged
                        boxes.pop(j)
                        changed = True
                        break
                if changed:
                    break
        kept.extend(boxes)
    return kept, {"before": len(original), "after": len(kept), "contained": contained,
                  "merged": len(report) - contained, "removed": report}


def bare_props(m):
    chunks = collections.defaultdict(list)
    for c in m["chunks"]:
        if c["group"] >= 0:
            chunks[c["group"]].append(c)
    hosted = {c["placement"] for c in m.get("propColliders", [])} | {l["prop"] for l in m.get("lights", []) if "prop" in l}
    out = []
    for i, p in enumerate(m["placements"]):
        group = chunks[p["group"]]
        tagged = any(c.get("tags") or m["materials"].get(c["material"], {}).get("tags") for c in group)
        out.append(len(group) == 1 and i not in hosted and not p.get("hadColliders") and not gameplay_prop(p) and not tagged)
    return out


def in_removed_zone(pos):
    return any(x0 <= pos[0] <= x1 and y0 <= pos[1] <= y1 and z0 <= pos[2] <= z1
               for x0, x1, y0, y1, z0, z1 in REMOVED_ZONES)


def carriers_of(m, moves=None):
    """Manifest carriers -> [[path, orig, cf, size]] minus the removed zone, with CARRIER_MOVE applied."""
    moves = CARRIER_MOVE if moves is None else moves
    out = []
    for c in m["carriers"]:
        if c.get("culled") or in_removed_zone(c["orig"]):
            continue
        cf, s = c["cf"], c["s"]
        for mv in moves:
            at = mv.get("at")
            if re.search(mv["path"], c["path"]) and (at is None or max(abs(a - b) for a, b in zip(at, c["orig"])) <= 0.1):
                cf, s = mv["cf"], mv.get("s", s)
                break
        out.append([c["path"], c["orig"], cf, s])
    return out


def build(m, tex):
    assert m.get("version", 1) >= 2, "manifest from before export v2: re-export"
    missing = set()
    styles = {name: style(info, tex, missing) for name, info in m["materials"].items()}
    for name, over in STYLE_OVERRIDES.items():
        if name in styles:
            styles[name].update(over)
    chunks = [[c["id"], c["group"], c["material"], c["size"], c["center"], c.get("tags") or [], c.get("zone")] for c in m["chunks"]]
    placements = [[p["group"], p["pos"], p["rot"], p["scale"], p["model"], p["name"], p.get("attrs"), p.get("door")]
                  for p in m["placements"]]
    bare = bare_props(m)
    for p, source, compact in zip(placements, m["placements"], bare):
        # Object tags on collider-bearing props already belong to their collision boxes (Seat/gameplay tags).
        p.extend([compact, (source.get("tags") or []) if not source.get("hadColliders") else [], source.get("asset", source["model"])])
        p.extend([source.get("partName"), source.get("pivot"), source.get("partAttrs"), source.get("modelGroup"),
                  source.get("modelParent"), source.get("modelTags"), source.get("zone")])
    colliders = [collider(c) for c in m["colliders"]]
    # Luau is 1-based: placement indices + 1
    prop_colliders = [[c["placement"] + 1] + collider(c) for c in m.get("propColliders", [])]
    lights = []
    for l in m.get("lights", []):
        l = {k: v for k, v in l.items() if k != "propName"}
        if "prop" in l:
            l["prop"] += 1
        aud = AUD_BOX[0][0] <= l["pos"][0] <= AUD_BOX[0][1] and AUD_BOX[1][0] <= l["pos"][2] <= AUD_BOX[1][1]
        gain = LIGHT_GAIN * (AUD_GAIN if aud else 1) * KIND_GAIN.get(l.get("kind"), 1)
        l["brightness"] = round(l.get("brightness", 1.0) * gain, 3)
        l["range"] = round(min(RANGE_MAX, l.get("range", 16) * RANGE_GAIN * (AUD_RANGE_GAIN if aud else 1)
                               * KIND_RANGE.get(l.get("kind"), 1)), 3)
        if aud and l.get("kind") == "star" and l["pos"][1] > AUD_STAR_Y + 2:
            l["pos"] = [l["pos"][0], AUD_STAR_Y, l["pos"][2]]
            l["range"] = RANGE_MAX
        lights.append(l)
    out = {"styles": styles, "chunks": chunks, "placements": placements, "colliders": colliders,
           "propColliders": prop_colliders, "lights": lights, "carriers": carriers_of(m),
           "legacyLights": [e for e in m.get("legacyLights", []) if not LEGACY_CEILING.search(e[0])]}
    return out, missing


def tex_requests(m, tex, out_dir=TEX_OUT, dirs=TEX_DIRS, base=TEX_URL):
    """Maps used by the exported chunks and absent from textures.json -> copied to out_dir; returns the
    upload_image request file content and the file names that exist nowhere."""
    used = {c["material"] for c in m["chunks"]}
    files = sorted({m["materials"][n][f] for n in used if n in m["materials"] for _, f in MAPS
                    if m["materials"][n].get(f)} - set(tex))
    os.makedirs(out_dir, exist_ok=True)
    urls, lost = {}, []
    for fn in files:
        src = next((os.path.join(d, fn) for d in dirs if os.path.exists(os.path.join(d, fn))), None)
        if src is None:
            lost.append(fn)
            continue
        dst = os.path.join(out_dir, fn)
        if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src) or os.path.getmtime(dst) < os.path.getmtime(src):
            shutil.copy2(src, dst)
        urls[base + urllib.parse.quote(fn)] = fn
    paths = list(urls)
    return {"batches": [{"imagePaths": paths[i:i + BATCH]} for i in range(0, len(paths), BATCH)], "files": urls,
            "missing": lost}, lost


def tex_merge(results, tex):
    """upload_image answers {url: "rbxassetid://n"} -> textures.json entries keyed by file name."""
    n = 0
    for url, asset in results.items():
        if isinstance(asset, str) and asset.startswith("rbxassetid://"):
            tex[urllib.parse.unquote(url.rsplit("/", 1)[-1])] = asset
            n += 1
    return n


def _selftest():
    I = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    assert occluder_size([10, 1, 4]) == [9.8, 0.8, 3.8]
    assert occluder_size([0.5, 6, 6]) == [0.3, 5.8, 5.8]                 # the floor itself is allowed
    assert occluder_size([10, 0.45, 4]) == [9.8, 0.45, 3.8] and occluder_size([0.2, 9, 9]) == [0.2, 8.8, 8.8]
    wall = {"cf": [0, 30, 0] + I, "s": [40, 12, 1], "m": "Fabric", "tags": ["Level4V4Floor"], "occ": True}
    c = collider(wall)
    assert c[1] == [39.8, 11.8, 0.8] and c[6] is True and c[3] == "SmoothPlastic" and c[4] == ["Level4V4Floor"], c
    assert collider(dict(wall, occ=False))[1:7:5] == [[40, 12, 1], False]       # not flagged: untouched
    assert collider(dict(wall, s=[40, 12, 0.3]))[1:7:5] == [[39.8, 11.8, 0.3], False]  # thin axis unchanged, invisible
    assert collider(dict(wall, kind="Seat"))[1:7:5] == [[40, 12, 1], False]    # seats keep their physical bounds
    assert collider({"cf": wall["cf"], "s": [2, 2, 2]}) == [wall["cf"], [2, 2, 2], "Block", "SmoothPlastic", [],
                                                              "Part", False, None, None]
    # removed Cinema 1 west zone: the real carriers there, and neighbours that must stay
    gone = [(22624.27, 37.5, -180), (22660.83, 37.5, -69), (22669, 49.5, -143.8), (22675.85, 54, -130),
            (22650, 30, -10), (22635, 30, 50), (22679, 52, -130)]
    kept = [(22690, 39.65, 99.07), (22650, 92, -10), (22660, 40, 50), (22700, 30, -10), (22700, 50, -130),
            (22766, 47.5, -17.6), (22678, 37, -208), (22640, 30, 99.5), (22676.1, 37, -208), (22650, 85, -10),
            (23350, 37, -180)]                  # exact boundary, gallery, C4 must stay
    assert all(in_removed_zone(p) for p in gone), [p for p in gone if not in_removed_zone(p)]
    assert not any(in_removed_zone(p) for p in kept), [p for p in kept if in_removed_zone(p)]
    sign = {"path": "Concourse/A2_Marquee", "orig": [23000, 47.5, -17.6], "cf": [23000, 47.5, -17.6] + I, "s": [60, 7, 0.3]}
    poster = {"path": "C1/C1_PosterArt", "orig": [22624.27, 37.5, -180], "cf": [22624.4, 37.5, -180] + I, "s": [0.1, 13.6, 8.8]}
    m = {"carriers": [sign, poster]}
    mv = [{"path": r"^Concourse/A2_Marquee$", "at": [23000, 47.5, -17.6], "cf": [23000, 50, 41.5] + I, "s": [40, 6, 0.3]}]
    out = carriers_of(m, mv)
    assert len(out) == 1 and out[0][2] == [23000, 50, 41.5] + I and out[0][3] == [40, 6, 0.3], out
    assert carriers_of(m, [dict(mv[0], at=[1, 2, 3])])[0][2] == sign["cf"]          # wrong centre: not moved
    assert LEGACY_CEILING.search("Concourse/Downlight/PointLight") and LEGACY_CEILING.search("C1/C1_StairA1West_Light/PointLight")
    assert LEGACY_CEILING.search("Restrooms/Men_Fluorescent/PointLight") and LEGACY_CEILING.search("A2/A2_CeilingLight/PointLight")
    assert not LEGACY_CEILING.search("HiddenService/EastStairLamp/PointLight")
    assert not LEGACY_CEILING.search("HiddenService/GallerySconce/PointLight")
    man = {"version": 2, "materials": {"L4S_EMIT_STAR": {"sem": "neon", "color": [255, 244, 225], "roblox": "Neon",
                                                         "tags": ["L4StarTwinkleA"]}},
           "chunks": [{"id": 0, "group": -1, "material": "L4S_EMIT_STAR", "size": [1, 1, 1], "center": [0, 0, 0],
                       "tags": ["L4StarTwinkleB"]}],
           "placements": [], "colliders": [wall], "propColliders": [dict(wall, placement=0, occ=False)],
           "carriers": [sign, poster],
           "lights": [{"type": "PointLight", "pos": [22700, 40, -100], "rot": I, "color": [1, 1, 1], "range": 20,
                       "brightness": 1, "kind": "star", "prop": 0, "propName": "x"}],
           "legacyLights": [["Concourse/Downlight/PointLight", [0, 0, 0]], ["HiddenService/EastStairLamp/PointLight", [1, 1, 1]]]}
    out, _ = build(man, {})
    assert out["styles"]["L4S_EMIT_STAR"]["tags"] == ["L4StarTwinkleA"] and out["chunks"][0][5] == ["L4StarTwinkleB"]
    assert out["colliders"][0][6] is True and out["propColliders"][0][0] == 1 and out["propColliders"][0][7] is False
    assert len(out["carriers"]) == 1 and out["legacyLights"] == [["HiddenService/EastStairLamp/PointLight", [1, 1, 1]]]
    assert out["lights"][0]["prop"] == 1 and "propName" not in out["lights"][0]
    assert abs(out["lights"][0]["brightness"] - LIGHT_GAIN * AUD_GAIN * KIND_GAIN.get("star", 1)) < 1e-3
    # Round contracts survive the compact packet: invisible volume, grouped moving part, hinge and zones.
    man["chunks"][0]["zone"] = 4
    man["chunks"].append(dict(man["chunks"][0], id=1, group=1))
    pivot = [0, -.5, 0] + I
    man["placements"] = [{"group": 1, "pos": [0, 1, 2], "rot": I, "scale": [1, 1, 1],
                           "model": "BreakerA1", "name": "Handle", "modelGroup": "BreakerA1",
                           "modelParent": "PowerA", "modelTags": ["L4Breaker"],
                           "attrs": {"CabinetId": "A", "SwitchIndex": 1}, "partName": "Handle", "pivot": pivot}]
    man["colliders"].append(dict(wall, kind="Marker", occ=False, tags=["L4EntrySpawn"], at={"Slot": 1}, name="Spawn1"))
    man["lights"][0]["zone"] = 4
    out, _ = build(man, {})
    assert out["chunks"][0][6] == 4 and out["lights"][0]["zone"] == 4
    assert out["colliders"][-1][5:] == ["Marker", False, {"Slot": 1}, "Spawn1"]
    p = out["placements"][0]
    assert p[8] is False and p[11:17] == ["Handle", pivot, None, "BreakerA1", "PowerA", ["L4Breaker"]]
    print("make_place self-test ok")


if __name__ == "__main__" and sys.argv[1:2] == ["--selftest"]:
    _selftest()
elif __name__ == "__main__" and sys.argv[1:2] == ["--tex-requests"]:
    export = sys.argv[2] if len(sys.argv) > 2 else EXPORT
    m = json.load(open(os.path.join(export, "manifest.json")))
    req, lost = tex_requests(m, json.load(open(os.path.join(HERE, "textures.json"))))
    dest = os.path.join(os.path.dirname(TEX_OUT), "tex_requests.json")
    json.dump(req, open(dest, "w"), indent=1)
    print(len(req["files"]), "maps to upload in", len(req["batches"]), "batches ->", dest)
    if lost:
        print("NOT FOUND in", TEX_DIRS, ":", ", ".join(lost))
elif __name__ == "__main__" and sys.argv[1:2] == ["--tex-merge"]:
    path = os.path.join(HERE, "textures.json")
    tex = json.load(open(path))
    n = sum(tex_merge(json.load(open(f)), tex) for f in sys.argv[2:])
    json.dump(tex, open(path, "w"), indent=1)
    print(n, "texture ids merged into", path)
elif __name__ == "__main__":
    export = sys.argv[1] if len(sys.argv) > 1 else EXPORT
    dest = sys.argv[2] if len(sys.argv) > 2 else os.path.join(export, "chunks", "c99999.b64")
    m = json.load(open(os.path.join(export, "manifest.json")))
    tex = json.load(open(os.path.join(HERE, "textures.json")))      # file name -> rbxassetid
    out, missing = build(m, tex)
    json.dump(out, open(dest, "w"))
    print(len(out["chunks"]), "chunks,", len(out["placements"]), "placements,", len(out["colliders"]), "colliders (",
          sum(c[6] for c in out["colliders"]), "occluders ),", len(out["propColliders"]), "prop colliders,",
          len(out["lights"]), "lights,", len(out["carriers"]), "carriers (", len(m["carriers"]) - len(out["carriers"]),
          "in the removed zone ),", len(out["styles"]), "styles,", len(out["legacyLights"]), "legacy lights")
    if missing:
        print("NOT UPLOADED (left out of the SurfaceAppearances):", ", ".join(sorted(missing)))
