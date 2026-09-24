"""Assemble the Blender-rendered v1/v2 gait comparison into one QA figure."""
from pathlib import Path
import argparse

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("renders", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    samples = (("walk_03250", "Walk · 0.325 s"),
               ("walk_08250", "Walk · 0.825 s"),
               ("run_02833", "Run · 0.283 s"),
               ("run_05500", "Run · 0.550 s"))
    fig, axs = plt.subplots(2, 4, figsize=(12, 6.7), dpi=150)
    fig.patch.set_facecolor("#111820")
    for col, (stem, label) in enumerate(samples):
        for row, version in enumerate(("v1", "v2")):
            ax = axs[row, col]
            ax.imshow(plt.imread(args.renders / f"{version}_{stem}.png"))
            ax.axis("off")
            if row == 0:
                ax.set_title(label, color="#eee", fontsize=11)
            if col == 0:
                ax.text(-0.05, 0.5, "Current v1" if row == 0 else "Candidate v2",
                        transform=ax.transAxes, rotation=90, va="center", ha="right",
                        color="#ffb253" if row == 0 else "#77c9ff", fontsize=11)
    fig.suptitle("Pool Slide: rest-pose flashes removed between authored gait frames",
                 color="#eee", fontsize=14)
    fig.tight_layout(rect=(0.03, 0, 1, 0.94), pad=0.45)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, facecolor=fig.get_facecolor())
    plt.close(fig)


if __name__ == "__main__":
    main()
