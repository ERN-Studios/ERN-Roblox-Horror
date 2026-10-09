# blender -b luna_norm.blend -P landmarks.py   -> prints silhouette profile + paw clusters (studs, nose +Y)
import bpy, json
import numpy as np

ob = bpy.data.objects["LunaMesh"]
v = np.array([vv.co[:] for vv in ob.data.vertices])
out = {}
# side profile: per 0.2-stud Y slice, z min/max of the central body band and x extent
rows = []
for y0 in np.arange(v[:, 1].min(), v[:, 1].max(), 0.2):
    s = v[(v[:, 1] >= y0) & (v[:, 1] < y0 + 0.2)]
    if len(s) == 0:
        continue
    c = s[np.abs(s[:, 0]) < 0.2]
    rows.append([round(y0 + 0.1, 2), round(float(s[:, 2].min()), 2), round(float(s[:, 2].max()), 2),
                 round(float(c[:, 2].min()), 2) if len(c) else None, round(float(s[:, 0].min()), 2), round(float(s[:, 0].max()), 2), len(s)])
out["profile_y_zmin_zmax_centralzmin_xmin_xmax_n"] = rows
# paws: low vertices, split by side and front/back
low = v[v[:, 2] < 0.25]
paws = {}
for side, sx in (("L", -1), ("R", 1)):   # Blender -X is the dog's left when nose is +Y? (+Y fwd, +Z up -> +X is the dog's right)
    for end, sy in (("Front", 1), ("Hind", -1)):
        m = low[(np.sign(low[:, 0]) == sx) & (np.sign(low[:, 1]) == sy)]
        paws[end + side] = [round(float(a), 3) for a in m.mean(0)] if len(m) else None
out["paws"] = paws
# leg columns: for each paw, the x/y centre of the leg at several heights
legs = {}
for k, p in paws.items():
    if not p:
        continue
    col = []
    for z0 in np.arange(0.0, 2.2, 0.2):
        s = v[(v[:, 2] >= z0) & (v[:, 2] < z0 + 0.2) & (np.abs(v[:, 1] - p[1]) < 0.6) & (np.sign(v[:, 0]) == np.sign(p[0]))]
        if len(s):
            col.append([round(z0 + 0.1, 1), round(float(s[:, 0].mean()), 2), round(float(s[:, 1].mean()), 2), round(float(np.ptp(s[:, 1])), 2), len(s)])
    legs[k] = col
out["leg_columns_z_x_y_yspan_n"] = legs
out["nose"] = [round(float(a), 3) for a in v[np.argmax(v[:, 1])]]
out["tail_tip"] = [round(float(a), 3) for a in v[np.argmin(v[:, 1])]]
top = v[v[:, 2] > 3.0]
out["ear_tips"] = {"L": [round(float(a), 3) for a in top[top[:, 0] < 0].mean(0)] if (top[:, 0] < 0).any() else None,
                   "R": [round(float(a), 3) for a in top[top[:, 0] > 0].mean(0)] if (top[:, 0] > 0).any() else None}
print("LANDMARKS", json.dumps(out))
