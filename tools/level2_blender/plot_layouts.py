"""Draw Level 2 kit layouts (from the real generator under luau) as 2D plans for owner review.
  LUAU_BIN=... python tools/level2_blender/plot_layouts.py <out_dir> seed [seed ...]"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tests"))
import test_level2_kit_layout as T
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

ROLE = {"Arrival": "#7bd389", "Slide Hall": "#f2a65a", "Pump Station": "#e15554", "Kids Area": "#f7d154",
        "Small": "#a6a6a6", "Entity Den": "#6c4f8c", "Entity Den B": "#6c4f8c"}


def draw(layout, path):
    fig, ax = plt.subplots(figsize=(13, 13))
    halls = layout["Halls"]
    for c in layout["Corridors"]:
        a, w = c["Axis"], c.get("Width", 34)
        x0, x1 = (c["From"], c["To"]) if a == "X" else (c["Cross"] - w / 2, c["Cross"] + w / 2)
        z0, z1 = (c["Cross"] - w / 2, c["Cross"] + w / 2) if a == "X" else (c["From"], c["To"])
        col = {"Narrow": "#3d5a80", "PressureDoor": "#b23a48"}.get(c["Kind"], "#7fc8c4")
        if str(c.get("Variant", "")).startswith("Stair"):
            col = "#c9a227"
        ax.add_patch(Rectangle((x0, z0), x1 - x0, z1 - z0, color=col, zorder=1))
    for h in halls:
        col = ROLE.get(h.get("Role"), "#cfe8ef")
        if h.get("IsGrand"):
            col = "#ff7f11"
        ax.add_patch(Rectangle((h["MinX"], h["MinZ"]), h["MaxX"] - h["MinX"], h["MaxZ"] - h["MinZ"],
                               facecolor=col, edgecolor="#333", lw=.8, zorder=2))
        label = h["Type"] if h["Role"] != "Small" else h["Prefab"]
        ax.text((h["MinX"] + h["MaxX"]) / 2, (h["MinZ"] + h["MaxZ"]) / 2,
                f"{label}\nY{h.get('FloorY', 0):+d} H{h.get('CeilingClass', '')}", ha="center", va="center",
                fontsize=5.5 if h.get("Role") == "Small" else 7, zorder=3)
    b = layout["Bounds"]
    ax.set_xlim(b["MinX"] - 20, b["MaxX"] + 20); ax.set_ylim(b["MaxZ"] + 20, b["MinZ"] - 20)
    ax.set_aspect("equal"); ax.set_facecolor("#20262e")
    small = sum(1 for h in halls if h.get("Role") == "Small")
    narrow = sum(1 for c in layout["Corridors"] if c["Kind"] == "Narrow")
    ax.set_title(f"Level 2 Poolrooms requested seed {layout['RequestedSeed']} (resolved {layout['Seed']}): "
                 f"{len(halls) - small} halls, {small} chambers, "
                 f"{len(layout['Corridors']) - narrow} tunnels, {narrow} narrow passages "
                 f"(gold = stair tunnel, dark blue = narrow, red = pressure door)", fontsize=9)
    fig.savefig(path, dpi=110, bbox_inches="tight"); plt.close(fig)


if __name__ == "__main__":
    out, seeds = sys.argv[1], [int(s) for s in sys.argv[2:]]
    binary = os.environ["LUAU_BIN"]
    os.makedirs(out, exist_ok=True)
    for label, layout in T.run_layouts(binary, seeds):
        draw(layout, os.path.join(out, f"layout_{layout['RequestedSeed']}.png"))
        print("drawn", layout["RequestedSeed"], "resolved", layout["Seed"])
