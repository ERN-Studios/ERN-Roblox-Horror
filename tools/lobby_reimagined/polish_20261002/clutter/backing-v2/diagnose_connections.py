from pathlib import Path
import json
path = Path(__file__).with_name("verify_backing_v2.py")
source = path.read_text()
scope = {"__file__":str(path)}
exec(compile(source.split("# Each moved")[0],str(path),"exec"),scope)
results = []
for index in scope["changed"]:
    item = scope["b"]["placements"][index]
    row = {"name":item["name"]}
    for label,key in (("before","old_boxes"),("after","new_boxes")):
        box = scope[key][item["name"]]
        candidates = []
        for other in scope["b"]["placements"][:179]:
            if other["name"] == item["name"] or " Embedded " not in other["name"] or other["name"].split()[0] != item["name"].split()[0]:
                continue
            neighbor = scope[key][other["name"]]
            candidates.append({"name":other["name"],"overlap":scope["sat_overlap"](box,neighbor),"lower":neighbor["center"][1]<box["center"][1]})
        row[label] = {"bestAll":sorted(candidates,key=lambda p:-p["overlap"])[:3],"bestLower":sorted((p for p in candidates if p["lower"]),key=lambda p:-p["overlap"])[:3]}
    results.append(row)
print(json.dumps(results,indent=2))
