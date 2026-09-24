"""Create a compact diagnostic plot from offline Pool Slide gait JSON files."""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("v1", type=Path)
    ap.add_argument("v2", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    v1 = json.loads(args.v1.read_text(encoding="utf-8-sig"))
    v2 = json.loads(args.v2.read_text(encoding="utf-8-sig"))
    plt.style.use("dark_background")
    fig, axs = plt.subplots(2, 2, figsize=(12, 7), dpi=150)
    fig.patch.set_facecolor("#111820")
    colors = {"left": "#ffb253", "right": "#77c9ff"}
    for row, clip in enumerate(("Walk", "Run")):
        floor = v2[clip]["rest_floor_y"]
        for col, attr in enumerate(("min_y", "bone_z")):
            ax = axs[row, col]
            ax.set_facecolor("#1c2630")
            for side in ("left", "right"):
                for version, data, style in (("v1", v1, "--"), ("v2", v2, "-")):
                    samples = data[clip]["feet"][side]["sampled"]
                    ax.plot([r["time"] for r in samples], [r[attr] for r in samples],
                            style, color=colors[side], linewidth=1.2 if version == "v1" else 2,
                            alpha=0.42 if version == "v1" else 0.95,
                            label=f"{side.title()} {version}")
            if col == 0:
                ax.axhline(floor, color="#f5f5f5", lw=1, alpha=0.75, label="Rest sole floor")
                ax.set_ylabel("Lowest foot mesh (studs)")
            else:
                ax.set_ylabel("Foot bone forward position (studs)")
            ax.set_title(f"{clip} · {'sole height' if col == 0 else 'bone travel'}")
            ax.set_xlabel("Clip time (seconds)")
            ax.grid(color="white", alpha=0.12)
            ax.legend(fontsize=7, ncol=2, loc="best")
    fig.suptitle("Pool Slide: interleaved rest-pose dropout removal (offline v2 candidate)",
                 fontsize=14, color="#f5f5f5")
    fig.tight_layout(rect=(0, 0, 1, 0.95))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, facecolor=fig.get_facecolor())
    plt.close(fig)


if __name__ == "__main__":
    main()
