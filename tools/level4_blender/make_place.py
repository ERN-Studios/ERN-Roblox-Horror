# Level 4 cinema: manifest.json (export_l4.py) + textures.json -> the compact placement file place.luau reads
# (served as chunk 99999).
#   python make_place.py [export_dir] [out_file]      (defaults: the export dir, <export_dir>/chunks/c99999.b64)
#   python make_place.py --tex-requests [export_dir]  every map the exported chunks use that textures.json lacks is
#       copied to TEX_OUT (G:\Roblox\_local\l4blender\tex, served at http://127.0.0.1:8766/tex/<file> by e.g.
#       `python -m http.server 8766 -d G:\Roblox\_local\l4blender`), and TEX_OUT\..\tex_requests.json gets the
#       Studio MCP upload_image requests: {"batches": [{"imagePaths": [url, ...]}, ...], "files": {url: file}}
#   python make_place.py --tex-merge <result.json> ...   merges upload_image answers ({url: "rbxassetid://n"}) into
#       textures.json, keyed by file name
# Reads both manifest shapes: version 2 (PBR fields, collider kinds, lights, propColliders) and the original one.
# Texture ids come from textures.json, keyed by file name; a map that is not uploaded yet is left out (listed).
import json, os, re, shutil, sys, urllib.parse

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
LIGHT_GAIN, RANGE_GAIN, RANGE_MAX = 0.9, 1.2, 60.0
AUD_BOX = ((22677, 23323), (-232, -20))     # the three auditoria (Studio x, z): too few fixtures for their size
AUD_GAIN, AUD_RANGE_GAIN = 4.6, 1.25
STYLE_OVERRIDES = {"L4S_EMIT_WARM_fff0d6": {"m": "SmoothPlastic"}}    # lit-looking white backing, not Neon


def srgb2lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin2srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def style(info, tex, missing):
    col = [c / 255 for c in info["color"]]
    sem, alpha = info["sem"], info.get("alpha", 1.0)
    st = {"m": info["roblox"], "c": [round(c, 4) for c in col], "t": 0}
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


def collider(c):
    return [c["cf"], c["s"], c.get("sh") or "Block", c.get("m") or "SmoothPlastic", c.get("tags") or [],
            c.get("kind") or "Part", c.get("at") or None]


def build(m, layout, tex):
    missing = set()
    styles = {name: style(info, tex, missing) for name, info in m["materials"].items()}
    for name, over in STYLE_OVERRIDES.items():
        if name in styles:
            styles[name].update(over)
    chunks = [[c["id"], c["group"], c["material"], c["size"], c["center"]] for c in m["chunks"]]
    placements = [[p["group"], p["pos"], p["rot"], p["scale"], p["model"], p["name"], p.get("attrs"), p.get("door")]
                  for p in m["placements"]]
    if m.get("version", 1) >= 2:
        colliders = [collider(c) for c in m["colliders"]]
        carriers = [[c["path"], c["orig"], c["cf"], c["s"]] for c in m["carriers"]]
        fixtures = [[f["path"], f["orig"]] for f in m["flicker"]]
    else:                                           # original manifest (colliders without material/tags): layout
        dump = json.load(open(os.path.join(HERE, "l4_dump.json")))
        door_parts = re.compile(r"^AutomaticDoors/(?!.*_Post$)")
        flicker = {p["p"] for p in layout["parts"] if (p.get("at") or {}).get("OccasionalFlicker") == "true"}
        colliders, carriers, fixtures = [], [], []
        for i, p in enumerate(layout["parts"]):
            orig = dump["parts"][i]["cf"][:3] if i < len(dump["parts"]) else None
            if p["cc"] and not door_parts.search(p["p"]):
                colliders.append([p["cf"], p["s"], p.get("sh") or "Block", p["m"], p.get("tags") or [], "Part"])
            if orig and not p["p"].startswith("AutomaticDoors/") and any(d[0] in ("Decal", "SurfaceGui") for d in p.get("dec", [])):
                carriers.append([dump["parts"][i]["p"], orig, p["cf"], p["s"]])
            if orig and p["p"] in flicker:
                fixtures.append([p["p"], orig])
    # Luau is 1-based: placement indices + 1
    prop_colliders = [[c["placement"] + 1] + collider(c) for c in m.get("propColliders", [])]
    lights = []
    for l in m.get("lights", []):
        l = {k: v for k, v in l.items() if k != "propName"}
        if "prop" in l:
            l["prop"] += 1
        aud = AUD_BOX[0][0] <= l["pos"][0] <= AUD_BOX[0][1] and AUD_BOX[1][0] <= l["pos"][2] <= AUD_BOX[1][1]
        l["brightness"] = round(l.get("brightness", 1.0) * LIGHT_GAIN * (AUD_GAIN if aud else 1), 3)
        l["range"] = round(min(RANGE_MAX, l.get("range", 16) * RANGE_GAIN * (AUD_RANGE_GAIN if aud else 1)), 3)
        lights.append(l)
    exit_part = next(p for p in layout["parts"] if p["p"] == "Level4V4Exit")
    out = {"styles": styles, "chunks": chunks, "placements": placements, "colliders": colliders,
           "propColliders": prop_colliders, "lights": lights, "carriers": carriers, "fixtures": fixtures,
           "exitOrig": exit_part["cf"][:3]}
    if "legacyLights" in m:                         # absent: place.luau clones every original light (old manifests)
        out["legacyLights"] = m["legacyLights"]
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


if __name__ == "__main__" and sys.argv[1:2] == ["--tex-requests"]:
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
    layout = json.load(open(os.path.join(HERE, "l4_layout.json")))
    tex = json.load(open(os.path.join(HERE, "textures.json")))      # file name -> rbxassetid
    out, missing = build(m, layout, tex)
    json.dump(out, open(dest, "w"))
    print(len(out["chunks"]), "chunks,", len(out["placements"]), "placements,", len(out["colliders"]), "colliders,",
          len(out["propColliders"]), "prop colliders,", len(out["lights"]), "lights,", len(out["carriers"]),
          "carriers,", len(out["fixtures"]), "fixtures,", len(out["styles"]), "styles,",
          len(out.get("legacyLights", [])), "legacy lights")
    if missing:
        print("NOT UPLOADED (left out of the SurfaceAppearances):", ", ".join(sorted(missing)))
