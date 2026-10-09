#!/usr/bin/env python3
"""Select and master a bounded set of Poolrooms ElevenLabs sound-effect takes.

Run with Blender's Python (NumPy) and ffmpeg on PATH. No network, Studio,
credentials, uploads, or listening claims. Only selected raw WAVs, OGG masters,
and compact provenance/recipe/QC records survive; work files are temporary.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import tempfile

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
RECIPES = {
    "bed_hall": {"kind": "bed", "seconds": 24, "target_lufs": -27, "lowpass": 3800, "highpass": 45, "cross": 2.0, "physical_water": False, "comb_from": 800},
    "bed_water": {"kind": "bed", "seconds": 24, "target_lufs": -27, "lowpass": 4800, "highpass": 45, "cross": 2.0, "physical_water": True, "comb_from": 900},
    "bed_service": {"kind": "bed", "seconds": 24, "target_lufs": -27, "lowpass": 3500, "highpass": 50, "cross": 2.0, "physical_water": False, "comb_from": 1400, "machinery": True},
    "loop_weir": {"kind": "loop", "seconds": 20, "target_lufs": -24, "lowpass": 5800, "highpass": 60, "cross": 2.0, "physical_water": True, "comb_from": 900},
    "loop_lion": {"kind": "loop", "seconds": 20, "target_lufs": -24, "lowpass": 6000, "highpass": 60, "cross": 2.0, "physical_water": True, "comb_from": 900},
    "shot_drip": {"kind": "shot", "seconds": 8, "target_lufs": -25, "lowpass": 5500, "highpass": 60, "attack": .15, "tail": 1.5, "physical_water": True, "comb_from": 1200},
    "shot_pipe": {"kind": "shot", "seconds": 10, "target_lufs": -25, "lowpass": 4500, "highpass": 50, "attack": .25, "tail": 2.0, "physical_water": False, "comb_from": 1400, "machinery": True},
    "shot_splash": {"kind": "shot", "seconds": 9, "target_lufs": -25, "lowpass": 5800, "highpass": 60, "attack": .18, "tail": 1.8, "physical_water": True, "comb_from": 1200},
    "shot_creak": {"kind": "shot", "seconds": 9, "target_lufs": -25, "lowpass": 4800, "highpass": 60, "attack": .25, "tail": 2.0, "physical_water": False, "comb_from": 1600},
}


def command(args, *, input=None):
    return subprocess.run(args, input=input, check=True, capture_output=True)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def decode(path):
    probe = json.loads(command(["ffprobe", "-v", "error", "-show_entries", "stream=channels", "-of", "json", str(path)]).stdout)
    channels = int(probe["streams"][0]["channels"])
    data = command(["ffmpeg", "-v", "error", "-i", str(path), "-ar", str(SR), "-f", "f32le", "-"]).stdout
    return np.frombuffer(data, dtype="<f4").reshape(-1, channels).astype(np.float64)


def write_wav(path, signal):
    channels = 1 if signal.ndim == 1 else signal.shape[1]
    # ffmpeg emits to stdout; Python owns the explicitly scoped output file.
    data = command(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", str(channels), "-i", "-", "-c:a", "pcm_s24le", "-f", "wav", "-"], input=signal.astype("<f4").tobytes()).stdout
    Path(path).write_bytes(data)


def encode_ogg(wav, output):
    data = command(["ffmpeg", "-v", "error", "-i", str(wav), "-c:a", "libvorbis", "-q:a", "6", "-ar", str(SR), "-f", "ogg", "-"]).stdout
    Path(output).write_bytes(data)


def loudness(path):
    result = command(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true:dualmono=true", "-f", "null", "-"])
    text = result.stderr.decode(errors="replace")
    tail = text[text.rfind("Summary:"):]
    def value(pattern):
        match = re.search(pattern, tail)
        return float(match.group(1)) if match else None
    return {"lufs": value(r"I:\s*(-?[\d.]+) LUFS"), "true_peak_dbfs": value(r"Peak:\s*(-?[\d.]+) dBFS")}


def db(power):
    return 10 * np.log10(np.maximum(power, 1e-20))


def amp_db(value):
    return float(20 * np.log10(max(float(value), 1e-12)))


def frames(x, n, hop):
    if len(x) < n:
        x = np.pad(x, (0, n - len(x)))
    return np.lib.stride_tricks.sliding_window_view(x, n)[::hop]


def power_spectrum(x, n=8192, hop=4096):
    window = np.hanning(n)
    spec = np.fft.rfft(frames(x, n, hop) * window, axis=1)
    power = abs(spec) ** 2 * 2 / (n * np.sum(window ** 2))
    return power, np.fft.rfftfreq(n, 1 / SR)


def band(power, freq, low, high):
    return np.sum(power[..., (freq >= low) & (freq < high)], axis=-1)


def smooth(array, size, axis):
    if size <= 1:
        return array
    pad = [(0, 0)] * array.ndim
    pad[axis] = (size // 2, size // 2)
    padded = np.pad(array, pad, mode="edge")
    return np.mean(np.lib.stride_tricks.sliding_window_view(padded, size, axis=axis), axis=-1)


def tonal_peaks(x, lowest=800):
    power, freq = power_spectrum(x, 16384, 8192)
    level = db(power.mean(axis=0))
    base = np.empty_like(level)
    for k in range(len(level)):
        half = max(15, int(k * .122))
        base[k] = np.median(level[max(0, k - half): min(len(level), k + half + 1)])
    prominence = level - base
    peaks = []
    frame_levels = db(power)
    for k in range(8, len(level) - 8):
        if freq[k] < lowest or freq[k] > 11000:
            continue
        if prominence[k] < 8 or level[k] != np.max(level[k - 6:k + 7]):
            continue
        bin_power = float(db(np.sum(power.mean(axis=0)[k - 2:k + 3])))
        if bin_power < -95:
            continue
        neighbours = np.concatenate([frame_levels[:, k - 12:k - 4], frame_levels[:, k + 5:k + 13]], axis=1)
        persistence = float(np.mean(frame_levels[:, k] - np.median(neighbours, axis=1) > 8))
        hz = float(freq[k])
        peaks.append({"hz": round(hz, 2), "prominence_db": round(float(prominence[k]), 2), "power_dbfs": round(bin_power, 2), "persistence": round(persistence, 3), "on_50hz_grid": abs(hz - round(hz / 50) * 50) <= 7.5})
    return peaks


def signal_metrics(signal, cutoff=5000, *, loop=False, detailed_channels=False):
    if signal.ndim == 1:
        signal = signal[:, None]
    mid = signal.mean(axis=1)
    power, freq = power_spectrum(mid)
    long = power.mean(axis=0)
    qpower, qfreq = power_spectrum(mid, 2048, 2048)
    energy = qpower.sum(axis=1)
    quiet_rows = np.argsort(energy)[:max(1, len(energy) // 10)]
    quiet = qpower[quiet_rows].mean(axis=0)
    frame_level = db(energy)
    hf = long[(freq >= 2500) & (freq < 8000)]
    flatness = float(np.exp(np.mean(np.log(hf + 1e-30))) / max(float(np.mean(hf)), 1e-30))
    tones = tonal_peaks(mid)
    record = {
        "seconds": round(len(mid) / SR, 4), "sample_peak_dbfs": round(amp_db(np.max(abs(signal))), 2),
        "rms_dbfs": round(float(db(np.mean(mid ** 2))), 2),
        "quiet10_rms_dbfs": round(float(db(quiet.sum())), 2),
        "quiet10_2p5k_8k_dbfs": round(float(db(band(quiet, qfreq, 2500, 8000))), 2),
        "quiet_to_median_db": round(float(np.median(frame_level) - db(quiet.sum())), 2),
        "envelope_p95_minus_p5_db": round(float(np.percentile(frame_level, 95) - np.percentile(frame_level, 5)), 2),
        "above_1p3_cutoff_dbfs": round(float(db(band(long, freq, cutoff * 1.3, 22050))), 2),
        "above_cutoff_relative_db": round(float(db(band(long, freq, cutoff * 1.3, 22050)) - db(long.sum())), 2),
        "high_band_flatness": round(flatness, 4),
        "bands_dbfs": {name: round(float(db(band(long, freq, lo, hi))), 2) for name, lo, hi in [("under150", 0, 150), ("150_1k", 150, 1000), ("1k_4k", 1000, 4000), ("4k_8k", 4000, 8000), ("over8k", 8000, 22050)]},
        "all_tonal_peaks": tones,
        "audible_steady_tones_over800": sum(p["power_dbfs"] > -70 and p["persistence"] > .7 for p in tones),
        "audible_steady_grid_tones_over800": sum(p["power_dbfs"] > -70 and p["persistence"] > .7 and p["on_50hz_grid"] for p in tones),
    }
    if signal.shape[1] == 2:
        record["stereo_correlation"] = round(float(np.corrcoef(signal[:, 0], signal[:, 1])[0, 1]), 4)
    if detailed_channels:
        channel_records = []
        for channel in signal.T:
            p, f = power_spectrum(channel)
            q, qf = power_spectrum(channel, 2048, 2048)
            quiet_channel = q[np.argsort(q.sum(axis=1))[:max(1, len(q) // 10)]].mean(axis=0)
            channel_records.append({
                "all_tonal_peaks": tones if signal.shape[1] == 1 else tonal_peaks(channel),
                "above_1p3_cutoff_dbfs": round(float(db(band(p.mean(axis=0), f, cutoff * 1.3, 22050))), 2),
                "above_cutoff_relative_db": round(float(db(band(p.mean(axis=0), f, cutoff * 1.3, 22050)) - db(p.mean(axis=0).sum())), 2),
                "quiet10_2p5k_8k_dbfs": round(float(db(band(quiet_channel, qf, 2500, 8000))), 2),
            })
        record["individual_channel_noise_and_tones"] = channel_records
    if loop:
        seam = []
        for channel in signal.T:
            difference = np.diff(channel)
            step = abs(channel[0] - channel[-1])
            n, hop = 512, 256
            p, f = power_spectrum(channel, n, hop)
            ordinary = band(p, f, 2000, 16000)
            joined = np.concatenate([channel[-n // 2:], channel[:n // 2]])
            jp, jf = power_spectrum(joined, n, n)
            je = float(band(jp, jf, 2000, 16000)[0])
            window = int(.25 * SR)
            seam.append({
                "step_dbfs": round(amp_db(step), 2),
                "step_vs_diff_rms_db": round(amp_db(step / max(float(np.sqrt(np.mean(difference ** 2))), 1e-12)), 2),
                "hf_vs_median_db": round(float(db(je) - db(np.median(ordinary))), 2),
                "hf_vs_p99_db": round(float(db(je) - db(np.percentile(ordinary, 99))), 2),
                "end_vs_start_250ms_db": round(float(db(np.mean(channel[-window:] ** 2)) - db(np.mean(channel[:window] ** 2))), 2),
            })
        record["loop_seam_channels"] = seam
    else:
        n = int(.02 * SR)
        record["first20ms_peak_dbfs"] = round(amp_db(np.max(abs(signal[:n]))), 2)
        record["last20ms_peak_dbfs"] = round(amp_db(np.max(abs(signal[-n:]))), 2)
        record["first_sample_peak"] = float(np.max(abs(signal[0])))
        record["last_sample_peak"] = float(np.max(abs(signal[-1])))
    return record


def raw_assessment(path, recipe):
    signal = decode(path)
    metric = signal_metrics(signal, recipe["lowpass"])
    metric.update(loudness(path))
    body = metric["rms_dbfs"]
    high_relative = metric["bands_dbfs"]["over8k"] - body
    steady_grid = metric["audible_steady_grid_tones_over800"]
    steady_other = metric["audible_steady_tones_over800"] - steady_grid
    silence_fraction = float(np.mean(db(np.mean(frames(signal.mean(axis=1), 2048, 2048) ** 2, axis=1)) < body - 25))
    # We score technical suitability only. Water's broad noise is legitimate:
    # never call spectral flatness or noisy flowing water an artistic defect.
    score_terms = {
        "steady_grid_tones": min(steady_grid, 100) * .7,
        "steady_other_tones": min(steady_other, 100) * (.08 if recipe.get("machinery") else .18),
        "out_of_band_energy": max(0, high_relative + 18) * (.15 if recipe["physical_water"] else .3),
        "clipped_peak": max(0, metric["sample_peak_dbfs"] + .5) * 10,
        "unexpected_length": abs(metric["seconds"] - recipe["seconds"]) * 3,
        "loop_silence": silence_fraction * 20 if recipe["kind"] != "shot" else 0,
        "excess_gain_needed": max(0, recipe["target_lufs"] - (metric["lufs"] or -99) - 6),
        "excessive_loop_crest": max(0, metric["sample_peak_dbfs"] - body - 24) * 1.5 if recipe["kind"] != "shot" else 0,
        "loop_envelope_instability": max(0, metric["envelope_p95_minus_p5_db"] - 15) * .35 if recipe["kind"] != "shot" else 0,
    }
    metric["silence_fraction_below_body_minus25"] = round(silence_fraction, 4)
    return {"file": path.name, "sha256": sha256(path), "score": round(sum(score_terms.values()), 3), "score_terms": {k: round(v, 3) for k, v in score_terms.items()}, "metrics": metric}


def stft(signal, *, circular, n=8192, hop=2048):
    window = np.hanning(n + 1)[:-1]
    pad = n
    padded = np.pad(signal, (pad, pad), mode="wrap" if circular else "constant")
    blocks = frames(padded, n, hop)
    return np.fft.rfft(blocks * window, axis=1), len(signal), window, hop, pad


def istft(spec, info):
    length, window, hop, pad = info
    n = len(window)
    padded_length = length + pad * 2
    out = np.zeros(padded_length)
    norm = np.zeros(padded_length)
    blocks = np.fft.irfft(spec, n=n, axis=1) * window
    for i, block in enumerate(blocks):
        start = i * hop
        out[start:start + n] += block
        norm[start:start + n] += window ** 2
    return (out / np.maximum(norm, 1e-12))[pad:pad + length]


def shave_comb(x, recipe, loop):
    peaks = tonal_peaks(x, recipe["comb_from"])
    selected = [p for p in peaks if p["persistence"] >= .7 and p["on_50hz_grid"] and p["prominence_db"] >= 9 and p["power_dbfs"] > -75]
    if not selected:
        return x.copy(), []
    n = 16384
    spec, length, window, hop, pad = stft(x, circular=loop, n=n, hop=4096)
    freq = np.fft.rfftfreq(n, 1 / SR)
    gain = np.ones(len(freq))
    for peak in selected:
        index = int(round(peak["hz"] / (SR / n)))
        depth = min(24, peak["prominence_db"] - 2)
        for j in range(index - 3, index + 4):
            taper = .5 + .5 * np.cos((j - index) / 4 * np.pi)
            gain[j] = min(gain[j], 10 ** (-depth * taper / 20))
    return istft(spec * gain, (length, window, hop, pad)), selected


def gentle_static_reduction(x, recipe, loop):
    decision = {"applied": False, "depth_db": 0, "reason": "Physical water retains its natural broadband texture; no spectral gate."}
    if recipe["physical_water"]:
        return x, decision
    spec, length, window, hop, pad = stft(x, circular=loop)
    mag2 = abs(spec) ** 2
    freq = np.fft.rfftfreq(len(window), 1 / SR)
    energy = mag2.sum(axis=1)
    # Ignore the zero-padding itself when learning the noise print.
    valid = np.arange(len(spec)) * hop
    valid = (valid >= pad) & (valid + len(window) <= pad + length)
    rows = np.where(valid)[0]
    quiet = rows[np.argsort(energy[rows])[:max(3, len(rows) // 10)]]
    gap = float(db(np.median(energy[rows])) - db(np.mean(energy[quiet])))
    high = (freq >= 2500) & (freq < 8000)
    profile = smooth(mag2[quiet].mean(axis=0)[None, :], 9, 1)[0]
    flatness = float(np.exp(np.mean(np.log(profile[high] + 1e-30))) / max(float(profile[high].mean()), 1e-30))
    decision.update({"quiet_to_median_db": round(gap, 2), "profile_high_flatness": round(flatness, 4)})
    if gap < 10 or flatness < .12:
        decision["reason"] = "No isolated stationary broadband floor identified; retain intended ambience and use band limiting/comb removal only."
        return x, decision
    # At most 6 dB attenuation, only above 1.8 kHz; smooth modulation rather than
    # a hard noise gate or full spectral subtraction that damages reverb tails.
    ratio = profile[None, :] / np.maximum(smooth(mag2, 3, 0), 1e-20)
    gain = np.sqrt(np.clip(1 - .65 * ratio, .25, 1))
    weight = np.clip((freq - 1800) / 1700, 0, 1)
    gain = 1 - (1 - gain) * weight
    gain = smooth(smooth(gain, 5, 1), 3, 0)
    decision.update({"applied": True, "depth_db": 6, "reason": "Quiet source frames contain a stationary broadband residual with at least 10 dB separation from the active signal; apply a restrained high-band profile reduction."})
    return istft(spec * gain, (length, window, hop, pad)), decision


def band_limit(x, recipe, loop):
    pad = 0 if loop else int(.75 * SR)
    y = np.pad(x, (pad, pad))
    freq = np.maximum(np.fft.rfftfreq(len(y), 1 / SR), 1e-9)
    shape = 1 / np.sqrt(1 + (freq / recipe["lowpass"]) ** 32)
    shape /= np.sqrt(1 + (recipe["highpass"] / freq) ** 8)
    out = np.fft.irfft(np.fft.rfft(y) * shape, n=len(y))
    return out[pad:len(out) - pad] if pad else out


def cyclic_crossfade(x, seconds):
    n = min(int(seconds * SR), len(x) // 4)
    head, tail = x[:n].copy(), x[-n:].copy()
    theta = np.linspace(0, np.pi / 2, n)
    a, b = np.sin(theta), np.cos(theta)
    # Equal-power preserves the level of uncorrelated water. Correct positive
    # head/tail correlation to avoid a periodic gain swell on tonal room beds.
    correlation = np.clip(np.corrcoef(head, tail)[0, 1], 0, 1)
    norm = np.sqrt(a * a + b * b + 2 * correlation * a * b)
    joined = (head * a + tail * b) / norm
    return np.concatenate([joined, x[n:-n]])


def shot_envelope(x, recipe):
    attack = min(int(recipe["attack"] * SR), len(x) // 3)
    tail = min(int(recipe["tail"] * SR), len(x) // 3)
    x = x.copy()
    x[:attack] *= np.sin(np.linspace(0, np.pi / 2, attack)) ** 2
    x[-tail:] *= np.cos(np.linspace(0, np.pi / 2, tail)) ** 2
    x[0] = x[-1] = 0
    return np.pad(x, (int(.05 * SR), int(.2 * SR)))


def rotate_stable_seam(signal):
    """Move the file boundary onto a stable region without silencing a cycle."""
    window = int(.25 * SR)
    hop = int(.25 * SR)
    candidates = np.arange(window, len(signal) - window, hop)
    power = signal ** 2
    sums = np.concatenate([np.zeros((1, signal.shape[1])), np.cumsum(power, axis=0)], axis=0)
    before = (sums[candidates] - sums[candidates - window]) / window
    after = (sums[candidates + window] - sums[candidates]) / window
    mismatch = np.max(abs(db(before) - db(after)), axis=1)
    ordinary_difference = np.sqrt(np.mean(np.diff(signal, axis=0) ** 2, axis=0))
    candidate_steps = np.max(20 * np.log10(np.maximum(abs(signal[candidates] - signal[candidates - 1]) / np.maximum(ordinary_difference, 1e-12), 1e-12)), axis=1)
    # Reject long silent seams: quiet guards must not create a periodic dip.
    overall = np.mean(power, axis=0)
    quiet_penalty = np.maximum(0, np.max(db(overall) - db((before + after) / 2) - 8, axis=1))
    score = mismatch + quiet_penalty + np.maximum(0, candidate_steps - 4) * 2
    chosen = int(np.argmin(score))
    index = int(candidates[chosen])
    return np.roll(signal, -index, axis=0), {"rotation_seconds": round(index / SR, 4), "worst_channel_250ms_level_mismatch_db": round(float(mismatch[chosen]), 3), "worst_channel_step_vs_diff_rms_db": round(float(candidate_steps[chosen]), 3)}


def gentle_peak_limiter(signal, ceiling_db=-3.5, block=32, lookahead_ms=8, release_ms=100, *, loop=False):
    """Linked lookahead gain control, not waveform clipping.

    A linked stereo envelope prevents image shifts. A nearby-peak maximum gives
    gentle advance ducking; the release follows slowly. Reduction over 8 dB is
    a source-selection failure rather than a license to squash the ambience.
    """
    ceiling = 10 ** (ceiling_db / 20)
    pad = (-len(signal)) % block
    padded = np.pad(signal, ((0, pad), (0, 0)), mode="wrap" if loop else "constant")
    peaks = np.max(abs(padded).reshape(-1, block, signal.shape[1]), axis=(1, 2))
    if peaks.max() <= ceiling:
        return signal, {"maximum_reduction_db": 0, "fraction_reduced_more_than_1db": 0}
    reach = max(1, int(lookahead_ms * .001 * SR / block))
    nearby = np.max(np.lib.stride_tricks.sliding_window_view(np.pad(peaks, (reach, reach), mode="wrap" if loop else "edge"), 2 * reach + 1), axis=1)
    wanted = np.minimum(1, ceiling / np.maximum(nearby, 1e-12))
    # Smooth descending edges in advance; never relax protection at a peak.
    eased = smooth(wanted[None, :], 9, 1)[0]
    wanted = np.minimum(wanted, eased)
    release = math.exp(-block / (SR * release_ms * .001))
    envelope = np.empty_like(wanted)
    hold = 1.0
    for _ in range(2 if loop else 1):
        for i, gain in enumerate(wanted):
            hold = min(gain, release * hold + (1 - release))
            envelope[i] = hold
    positions = np.arange(len(peaks) + (1 if loop else 0)) * block
    gains = np.concatenate([envelope, envelope[:1]]) if loop else envelope
    samples = np.interp(np.arange(len(signal)), positions, gains)
    out = signal * samples[:, None]
    reduction = -20 * np.log10(np.maximum(envelope, 1e-12))
    return out, {"maximum_reduction_db": round(float(reduction.max()), 3), "fraction_reduced_more_than_1db": round(float(np.mean(reduction > 1)), 5), "lookahead_ms": lookahead_ms, "release_ms": release_ms}


def faults(metrics, recipe):
    out = []
    if metrics["sample_peak_dbfs"] > -3 or (metrics.get("true_peak_dbfs") is not None and metrics["true_peak_dbfs"] > -3):
        out.append("Final decoded/true peak exceeds -3 dBFS")
    if metrics["above_1p3_cutoff_dbfs"] > -68 or metrics["above_cutoff_relative_db"] > -34:
        out.append("Residual above 1.3 times low-pass cutoff exceeds the bounded hiss limits")
    if any(c["above_1p3_cutoff_dbfs"] > -68 or c["above_cutoff_relative_db"] > -34 for c in metrics.get("individual_channel_noise_and_tones", [])):
        out.append("An individual final channel exceeds the bounded high-band hiss limits")
    if metrics["lufs"] is None or abs(metrics["lufs"] - recipe["target_lufs"]) > 3:
        out.append("Integrated loudness lies more than 3 LU from the restrained target")
    if recipe["kind"] != "shot":
        for seam in metrics["loop_seam_channels"]:
            if seam["step_vs_diff_rms_db"] > 12 or seam["hf_vs_p99_db"] > 3 or abs(seam["end_vs_start_250ms_db"]) > 6:
                out.append("Final encoded loop seam is anomalous against ordinary waveform differences, HF transients, or local level")
                break
    elif metrics["last20ms_peak_dbfs"] > -75 or metrics["first20ms_peak_dbfs"] > -75:
        out.append("Encoded shot guard windows are not sufficiently silent")
    # All peaks, not a top-N list. Intentional machinery partials are preserved
    # below recipe.comb_from; only sustained grid residues are a comb defect.
    grid = [p for p in metrics["all_tonal_peaks"] if p["hz"] >= recipe["comb_from"] and p["power_dbfs"] > -70 and p["persistence"] > .7 and p["on_50hz_grid"]]
    if len(grid) > 3:
        out.append(f"{len(grid)} potentially audible sustained grid residues remain")
    for c in metrics.get("individual_channel_noise_and_tones", []):
        grid = [p for p in c["all_tonal_peaks"] if p["hz"] >= recipe["comb_from"] and p["power_dbfs"] > -70 and p["persistence"] > .7 and p["on_50hz_grid"]]
        if len(grid) > 3:
            out.append(f"An individual channel retains {len(grid)} potentially audible sustained grid residues")
            break
    return out


def seam_fault(metrics):
    return any(s["step_vs_diff_rms_db"] > 12 or s["hf_vs_p99_db"] > 3 or abs(s["end_vs_start_250ms_db"]) > 6 for s in metrics.get("loop_seam_channels", []))


def process_key(key, rawdir, output, work):
    recipe = RECIPES[key]
    paths = sorted(rawdir.glob(key + "__take*.mp3"))
    if len(paths) < 4:
        raise RuntimeError(f"{key}: expected at least four raw takes, found {len(paths)}")
    choices = [raw_assessment(path, recipe) for path in paths]
    choices.sort(key=lambda row: (row["score"], row["file"]))
    winner = choices[0]
    chosen = rawdir / winner["file"]
    raw = decode(chosen)
    rawwav = output / "selected_raw" / (key + ".wav")
    write_wav(rawwav, raw)
    loop = recipe["kind"] != "shot"
    channels = raw.T if recipe["kind"] == "bed" else [raw.mean(axis=1)]
    done, process_reports = [], []
    for channel in channels:
        x, shaved = shave_comb(channel, recipe, loop)
        x, denoise = gentle_static_reduction(x, recipe, loop)
        if loop:
            x = cyclic_crossfade(x, recipe["cross"])
        x = band_limit(x, recipe, loop)
        if not loop:
            x = shot_envelope(x, recipe)
        done.append(x)
        process_reports.append({"removed_comb_candidates": shaved, "broadband_reduction": denoise})
    master = np.stack(done, axis=1)
    seam_rotation = None
    if loop:
        master, seam_rotation = rotate_stable_seam(master)
    temp = work / (key + ".wav")
    write_wav(temp, master)
    cleaned_loud = loudness(temp)
    gain_db = min(9, recipe["target_lufs"] - (cleaned_loud["lufs"] or -99))
    master *= 10 ** (gain_db / 20)
    master, limiting = gentle_peak_limiter(master, loop=loop)
    write_wav(temp, master)
    final = output / "masters" / (key + ".ogg")
    encode_ogg(temp, final)
    decoded = decode(final)
    metric = signal_metrics(decoded, recipe["lowpass"], loop=loop, detailed_channels=True)
    metric.update(loudness(final))
    # Lossy encoding can create overshoot; use a bounded re-encode attenuation,
    # measured from the actual final decoder, rather than trusting a PCM peak.
    overshoot = max(metric["sample_peak_dbfs"], metric.get("true_peak_dbfs") or -99) + 3.2
    if overshoot > 0:
        master *= 10 ** (-overshoot / 20)
        write_wav(temp, master)
        encode_ogg(temp, final)
        decoded = decode(final)
        metric = signal_metrics(decoded, recipe["lowpass"], loop=loop, detailed_channels=True)
        metric.update(loudness(final))
    if loop and seam_fault(metric) and seam_rotation:
        # Vorbis's first/last transform blocks can make a particular cut less
        # faithful even when the PCM cut was smooth. Verify an alternate real
        # phase point: the original cyclic crossfade boundary. This neither
        # inserts silence nor conceals a bad decoded seam behind a looser rule.
        rotated_metric = metric
        offset = int(round(seam_rotation["rotation_seconds"] * SR))
        candidate = np.roll(master, offset, axis=0)
        write_wav(temp, candidate)
        encode_ogg(temp, final)
        alternate = signal_metrics(decode(final), recipe["lowpass"], loop=True, detailed_channels=True)
        alternate.update(loudness(final))
        if not seam_fault(alternate):
            master, metric = candidate, alternate
            seam_rotation["encoded_fallback"] = "Original cyclic crossfade phase has the stronger final decoded seam"
            seam_rotation["final_rotation_seconds"] = 0
            seam_rotation["rejected_encoded_seam_channels"] = rotated_metric["loop_seam_channels"]
        else:
            write_wav(temp, master)
            encode_ogg(temp, final)
            seam_rotation["alternate_original_phase_also_failed"] = alternate["loop_seam_channels"]
    issues = faults(metric, recipe)
    if limiting["maximum_reduction_db"] > 8:
        issues.append("Selected take requires more than 8 dB peak limiting; source is unsuitable for restrained ambience")
    row = {
        "selected_take": winner["file"], "selected_raw_sha256": winner["sha256"],
        "selected_raw_wav_sha256": sha256(rawwav), "master_sha256": sha256(final),
        "selection_rationale": "Lowest bounded technical-artifact score across available takes: stationary grid tones, out-of-band residue, clipping, duration, unintended loop silence, excessive transient crests/envelope instability, and excessive normalization. This does not establish artistic or auditory superiority.",
        "selection_candidates": choices,
        "recipe": recipe, "processing": process_reports,
        "normalization_gain_db": round(gain_db, 3), "linked_peak_limiter": limiting, "seam_rotation": seam_rotation, "encoder_overshoot_reduction_db": round(max(overshoot, 0), 3),
        "pre_gain_clean_loudness": cleaned_loud,
        "final_decoded_metrics": metric, "faults": issues, "numeric_pass": not issues,
        "listening_verified": False,
    }
    print(f"{key}: {winner['file']} score {winner['score']:.2f}, {metric['seconds']:.2f}s, {metric['lufs']:.1f} LUFS, peak {metric['sample_peak_dbfs']:.1f}, {'PASS' if not issues else 'FAULT: ' + '; '.join(issues)}", flush=True)
    return key, row


def negative_controls():
    t = np.arange(int(5.123 * SR)) / SR
    bad = .05 * np.sin(2 * np.pi * 137 * t + np.pi / 4)
    seam = signal_metrics(bad, 4500, loop=True)["loop_seam_channels"][0]
    assert seam["step_vs_diff_rms_db"] > 25
    rng = np.random.default_rng(20261009)
    x = rng.normal(0, .001, len(t)) + .035 * np.sin(2 * np.pi * 1850 * t)
    peaks = tonal_peaks(x)
    detected = [p for p in peaks if abs(p["hz"] - 1850) < 10 and p["persistence"] > .7 and p["on_50hz_grid"]]
    assert detected
    clean, removed = shave_comb(x, {"comb_from": 800}, False)
    after = tonal_peaks(clean)
    remaining = [p for p in after if abs(p["hz"] - 1850) < 10]
    reduction = detected[0]["power_dbfs"] - (max(p["power_dbfs"] for p in remaining) if remaining else -95)
    assert reduction > 10
    return {"bad_loop_seam_detected": seam, "artificial_1850hz_tone_reduction_db": round(reduction, 2), "removed_candidates": len(removed), "listening_verified": False}


def make_audition(output, report):
    """A short, labeled review reel; only numerically passing masters enter it."""
    levels = {"bed_hall": .5, "bed_water": .55, "bed_service": .45, "loop_weir": .7, "loop_lion": .6,
              "shot_drip": .6, "shot_pipe": .6, "shot_splash": .6, "shot_creak": .6}
    snippets, timeline, cursor = [], [], 0
    gap = np.zeros((int(.75 * SR), 2))
    for key in RECIPES:
        if key not in report["sounds"] or not report["sounds"][key]["numeric_pass"]:
            continue
        signal = decode(output / "masters" / (key + ".ogg"))
        if signal.shape[1] == 1:
            signal = np.repeat(signal, 2, axis=1)
        if RECIPES[key]["kind"] != "shot":
            n = int(4 * SR)
            signal = np.concatenate([signal[-n:], signal[:n]])
            guard = int(.5 * SR)
            signal[:guard] *= (np.sin(np.linspace(0, np.pi / 2, guard)) ** 2)[:, None]
            signal[-guard:] *= (np.cos(np.linspace(0, np.pi / 2, guard)) ** 2)[:, None]
        if snippets:
            snippets.append(gap)
            cursor += len(gap) / SR
        length = len(signal) / SR
        timeline.append({"key": key, "start_seconds": round(cursor, 3), "end_seconds": round(cursor + length, 3),
                         "gain": levels[key], "loop_file_seam_seconds": round(cursor + 4, 3) if RECIPES[key]["kind"] != "shot" else None})
        cursor += length
        snippets.append(signal * levels[key])
    if not snippets:
        return
    combined = np.concatenate(snippets)
    assert len(combined) / SR < 90
    audit = ROOT / "artifacts/poolrooms-audio-20261009/audit"
    audit.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="audition-", dir=audit) as temp:
        wav = Path(temp) / "audition.wav"
        write_wav(wav, combined)
        encode_ogg(wav, audit / "technical-audition.ogg")
    (audit / "technical-audition-timeline.json").write_text(json.dumps({
        "auditioned": False, "seconds": round(cursor, 3), "timeline": timeline,
        "purpose": "Review reel at proposed gains. Loops present their last four then first four seconds so the encoded file seam is in the middle. Mono files duplicate into both headphone channels. Spatial mix and gameplay are not represented.",
    }, indent=2) + "\n")
    print(f"Review reel: {cursor:.2f} seconds, {len(timeline)} passing masters, no listening claim.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path, default=Path("/tmp/poolrooms-audio-raw"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "assets/poolrooms-audio-20261009")
    parser.add_argument("--generation-manifest", type=Path)
    parser.add_argument("--keys", nargs="+", choices=sorted(RECIPES), default=list(RECIPES))
    parser.add_argument("--controls-only", action="store_true")
    parser.add_argument("--audition-only", action="store_true")
    args = parser.parse_args()
    if args.audition_only:
        report = json.loads((args.output_dir / "qc.json").read_text())
        make_audition(args.output_dir, report)
        return
    controls = negative_controls()
    if args.controls_only:
        print(json.dumps(controls, indent=2))
        return
    output = args.output_dir.resolve()
    if ROOT not in output.parents:
        raise SystemExit("Output must be inside this isolated worktree")
    for child in (output / "masters", output / "selected_raw"):
        child.mkdir(parents=True, exist_ok=True)
    rawdir = args.raw_dir.resolve()
    for key in args.keys:
        if len(list(rawdir.glob(key + "__take*.mp3"))) < 4:
            raise SystemExit(f"Raw download is incomplete for {key}; do not start mastering until all four takes are ready")
    report = {"schema": 1, "date": "2026-10-09", "sample_rate": SR, "auditioned": False,
              "scope": "Technical master assessment only. No claim that AI static is inaudible or that gameplay audio transitions passed.",
              "negative_controls": controls, "sounds": {}}
    previous = output / "qc.json"
    if previous.exists():
        report["sounds"].update(json.loads(previous.read_text()).get("sounds", {}))
    with tempfile.TemporaryDirectory(prefix="audio-work-", dir=output) as temporary:
        work = Path(temporary)
        with ThreadPoolExecutor(max_workers=3) as workers:
            futures = [workers.submit(process_key, key, rawdir, output, work) for key in args.keys]
            for future in futures:
                key, row = future.result()
                report["sounds"][key] = row
                previous.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    provenance = {"date": "2026-10-09", "provider": "ElevenLabs", "model_id": "eleven_text_to_sound_v2",
                  "take_counts_per_sound": {key: len(row["selection_candidates"]) for key, row in report["sounds"].items()}, "provenance_source": str(args.generation_manifest) if args.generation_manifest else "Generation metadata must be attached by the coordinating agent", "generator_parameters": None,
                  "script_sha256": sha256(__file__), "sound_count": len(report["sounds"]), "auditioned": False}
    if args.generation_manifest:
        # No signed download URLs or credentials are copied into the repository.
        metadata = json.loads(args.generation_manifest.read_text())
        provenance["generation_manifest_sha256"] = sha256(args.generation_manifest)
        provenance["generation_metadata"] = metadata
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
    (output / "recipes.json").write_text(json.dumps(RECIPES, indent=2, sort_keys=True) + "\n")
    make_audition(output, report)
    failed = [key for key, row in report["sounds"].items() if not row["numeric_pass"]]
    print(f"Completed {len(report['sounds'])} sounds; faults: {failed}; no auditory listening performed.")
    if failed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
