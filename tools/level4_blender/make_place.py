# Level 4 cinema: manifest.json (export_l4.py) + l4_layout.json -> the compact placement file that
# place.luau reads (served as chunk 99999), plus the uploaded texture ids.
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT = r"G:\Roblox\_local\l4blender\export"
m = json.load(open(os.path.join(EXPORT, "manifest.json")))
LAYOUT = json.load(open(os.path.join(HERE, "l4_layout.json")))
DUMP = json.load(open(os.path.join(HERE, "l4_dump.json")))
TEX = json.load(open(os.path.join(HERE, "textures.json")))      # file name -> rbxassetid


def style(info):
    col = [c / 255 for c in info["color"]]
    sem, tex = info["sem"], info["tex"]
    st = {"m": info["roblox"], "c": [round(c, 4) for c in col], "t": 0}
    if sem == "glass" or info["alpha"] < 0.99:
        st["m"] = "Glass" if sem == "glass" else st["m"]
        st["t"] = round(min(0.75, 1 - info["alpha"]), 3) if sem == "glass" else round(1 - info["alpha"], 3)
    if sem == "neon":
        st["m"] = "Neon"
    if tex and sem not in ("neon", "glass"):
        st["sa"] = TEX[tex]
        st["tint"] = [round(min(1, c / 0.75), 4) for c in col] if tex.endswith("_n.png") else [1, 1, 1]
    return st


styles = {name: style(info) for name, info in m["materials"].items()}
chunks = [[c["id"], c["group"], c["material"], c["size"], c["center"]] for c in m["chunks"]]
placements = []
for p in m["placements"]:
    placements.append([p["group"], p["pos"], p["rot"], p["scale"], p["model"], p["name"],
                       p.get("attrs"), p.get("door")])

door_parts = re.compile(r"^AutomaticDoors/(?!.*_Post$)")
flicker = {p["p"] for p in LAYOUT["parts"] if (p.get("at") or {}).get("OccasionalFlicker") == "true"}
colliders, carriers, fixtures = [], [], []
for i, p in enumerate(LAYOUT["parts"]):
    orig = DUMP["parts"][i]["cf"][:3] if i < len(DUMP["parts"]) else None
    if p["cc"] and not door_parts.search(p["p"]):
        sh = p.get("sh") or "Block"
        colliders.append([p["cf"], p["s"], sh, p["m"], p.get("tags") or []])
    if orig and not p["p"].startswith("AutomaticDoors/") and any(d[0] in ("Decal", "SurfaceGui") for d in p.get("dec", [])):
        carriers.append([DUMP["parts"][i]["p"], orig, p["cf"], p["s"]])
    if orig and p["p"] in flicker:
        fixtures.append([p["p"], orig])
exit_part = next(p for p in LAYOUT["parts"] if p["p"] == "Level4V4Exit")
out = {"styles": styles, "chunks": chunks, "placements": placements, "colliders": colliders,
       "carriers": carriers, "fixtures": fixtures, "exitOrig": exit_part["cf"][:3]}
json.dump(out, open(os.path.join(EXPORT, "chunks", "c99999.b64"), "w"))
print(len(chunks), "chunks,", len(placements), "placements,", len(colliders), "colliders,",
      len(carriers), "carriers,", len(fixtures), "fixtures,", len(styles), "styles")
