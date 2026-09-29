#!/usr/bin/env python3
"""Measure Level 6 audio masters with ffmpeg; no third-party Python packages."""

from __future__ import annotations

import argparse
import array
import json
import math
import subprocess
import sys
from pathlib import Path

RATE = 48000
FRAME = RATE // 50  # 20 ms


def db(value: float) -> float:
    return round(20 * math.log10(max(value, 1e-12)), 2)


def percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    pos = q * (len(ordered) - 1)
    lo = int(pos)
    hi = min(lo + 1, len(ordered) - 1)
    return ordered[lo] * (hi - pos) + ordered[hi] * (pos - lo)


def decode(path: Path, filter_expr: str | None = None) -> array.array:
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(path)]
    if filter_expr:
        cmd += ["-af", filter_expr]
    cmd += ["-f", "f32le", "-acodec", "pcm_f32le", "-ac", "1", "-ar", str(RATE), "-"]
    result = subprocess.run(cmd, capture_output=True, check=True)
    samples = array.array("f")
    samples.frombytes(result.stdout)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def frame_levels(samples: array.array) -> list[float]:
    return [math.sqrt(sum(s * s for s in samples[i:i + FRAME]) / len(samples[i:i + FRAME]))
            for i in range(0, len(samples), FRAME) if len(samples[i:i + FRAME]) >= FRAME // 2]


def rms(samples: array.array) -> float:
    return math.sqrt(sum(s * s for s in samples) / max(len(samples), 1))


def analyze(path: Path) -> dict:
    samples = decode(path)
    high = decode(path, "highpass=f=4500")
    levels = frame_levels(samples)
    high_levels = frame_levels(high)
    half_second = RATE // 2
    quiet_frames = min(25, len(levels))
    quiet_start = min(range(max(1, len(levels) - quiet_frames + 1)),
                      key=lambda i: sum(levels[i:i + quiet_frames]))
    diffs = [abs(samples[i] - samples[i - 1]) for i in range(1, len(samples))]
    seam = abs(samples[0] - samples[-1]) if samples else 0
    return {
        "path": str(path),
        "duration_seconds": round(len(samples) / RATE, 3),
        "peak_dbfs": db(max((abs(s) for s in samples), default=0)),
        "rms_dbfs": db(rms(samples)),
        "frame_rms_dbfs": {key: db(percentile(levels, q)) for key, q in
                            (("p10", .1), ("p50", .5), ("p90", .9), ("p99", .99))},
        "head_0_2s_rms_dbfs": db(rms(samples[:RATE // 5])),
        "tail_0_5s_rms_dbfs": db(rms(samples[-half_second:])),
        "tail_0_5s_highpass_4k5_rms_dbfs": db(rms(high[-half_second:])),
        "quietest_0_5s_start_seconds": round(quiet_start / 50, 2),
        "quietest_0_5s_rms_dbfs": db(rms(samples[quiet_start * FRAME:(quiet_start + quiet_frames) * FRAME])),
        "quietest_0_5s_highpass_4k5_rms_dbfs": db(rms(high[quiet_start * FRAME:(quiet_start + quiet_frames) * FRAME])),
        "loop_boundary_sample_step_dbfs": db(seam),
        "natural_adjacent_step_p99_9_dbfs": db(percentile(diffs, .999)),
        "loop_boundary_exceeds_natural_p99_9": seam > percentile(diffs, .999),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    results = [analyze(path) for path in args.paths]
    output = json.dumps(results, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    main()
