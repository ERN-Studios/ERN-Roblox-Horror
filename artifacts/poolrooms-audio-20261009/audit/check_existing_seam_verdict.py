"""Synthetic negative control for the pre-existing cleaner's seam verdict.

This is an audit artifact, not a production sound or game change.
"""
import importlib.util
from pathlib import Path
import sys

import numpy as np

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("poolrooms_clean_audit", ROOT / "tools/audio/clean.py")
clean = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clean)

sr = clean.SR
t = np.arange(int(5.123 * sr)) / sr
x = .05 * np.sin(2 * np.pi * 137 * t + np.pi / 4)
step = abs(x[0] - x[-1])
join_step_vs_diff_rms_db = float(20 * np.log10(step / np.sqrt(np.mean(np.diff(x) ** 2))))
# These plausible non-seam fields isolate the verdict function; this does not
# represent an ffmpeg measurement or an audition of any production clip.
numbers = {
    "above_cutoff_db": -100,
    "tones_over_1k": 0,
    "peak": -26,
    "lufs": -29,
    "join_step_vs_diff_rms_db": join_step_vs_diff_rms_db,
}
print("Synthetic 137 Hz waveform seam step vs ordinary adjacent-sample RMS: %.2f dB" % join_step_vs_diff_rms_db)
print("Existing verdict faults with this seam measurement:", clean.verdict(numbers, True))
assert join_step_vs_diff_rms_db > 25
assert clean.verdict(numbers, True) == []
