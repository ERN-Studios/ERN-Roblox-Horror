# Turns manifest.json into the compact placement file Studio reads (served as chunk 99999).
import json, os, re

ROOT = os.path.dirname(os.path.abspath(__file__))
m = json.load(open(os.path.join(ROOT, "manifest.json")))
mats = m["materials"]

COLOR_FIX = {  # linked/procedural colours the exporter could not resolve to a constant
    "L4_Landscape_LeafSub": [0.0824, 0.1647, 0.0627],
    "L4_Landscape_LeafCoreSub": [0.0627, 0.1255, 0.0392],
    "L4_Landscape_PaintWhite": [0.88, 0.87, 0.82],
    "L4_Landscape_PaintYellow": [0.85, 0.68, 0.2],
}
RULES = [  # first match wins: (pattern, Roblox material)
    (r"Glass", "Glass"),
    (r"Leaf|Shrub|Thatch|Hedge|Landscape_Grass", "LeafyGrass"),
    (r"Lawn|WornHalo", "Grass"),
    (r"WornCore|Path", "Ground"),
    (r"Bark", "Wood"),
    (r"Asphalt", "Asphalt"),
    (r"Sidewalk|Drive|Paving", "Pavement"),
    (r"Curb|Concrete|Base|Barricade", "Concrete"),
    (r"Shingle|Roof", "Slate"),
    (r"Stone", "Slate"),
    (r"Siding|Clapboard", "WoodPlanks"),
    (r"Metal", "Metal"),
    (r"Wall|Cream|TowerShade|Soffit|Eave", "Plaster"),
]
NO_COLLIDE = re.compile(r"Landscape_Grass|Groove|Leaf|Shrub|Thatch|Hedge|Bark|Glow|LightPanel|Downlight|Ceiling|Bars|Balusters|Lattice|Blind|Curtain")


def style(name):
    info = mats.get(name, mats["None"])
    color = COLOR_FIX.get(name, info["color"])
    emit = info["emit"] if name not in COLOR_FIX else 0
    if emit >= 1:
        mat = "Neon"
    else:
        mat = next((r for p, r in RULES if re.search(p, name)), "SmoothPlastic")
    transparency = 0.25 if mat == "Glass" else 0
    return {"m": mat, "c": [round(x, 4) for x in color], "t": transparency, "cc": not NO_COLLIDE.search(name)}


styles = {}
chunks = []
for c in m["chunks"]:
    styles.setdefault(c["material"], style(c["material"]))
    chunks.append([c["id"], c["group"], c["material"], c["size"], c["center"]])
out = {"styles": styles, "chunks": chunks,
       "placements": [[p["group"], p["pos"], p["rot"], p["scale"]] for p in m["placements"]],
       "lights": m["lights"]}
json.dump(out, open(os.path.join(ROOT, "chunks", "c99999.b64"), "w"))
print(len(chunks), "chunks,", len(out["placements"]), "placements,", len(styles), "styles")
for k, v in sorted(styles.items()):
    print(f"  {k:36s} {v}")
