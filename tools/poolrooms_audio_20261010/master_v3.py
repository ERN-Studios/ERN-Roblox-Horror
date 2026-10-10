#!/usr/bin/env python3
"""Sequential, manifest-driven Poolrooms mastering with measured static QC.

Run with Blender's NumPy Python and local ffmpeg. Selected original MP3s,
decoded-QC Vorbis masters, recipes, provenance, matrices and PNGs are retained.
The preserved 2026-10-09 DSP core has a frozen compatibility regression mode.
No network, synthesis of deliverables, uploads, Studio or listening claims.
"""
from __future__ import annotations

import argparse
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
LEGACY_RECIPES = {
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


def process_legacy(key, rawdir, output, work):
    recipe = LEGACY_RECIPES[key]
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



# Generalized v3 interface. The frozen functions above preserve the complete
# 2026-10-09 numerical chain; no thread pool is used anywhere in this tool.
import shutil
import time
from datetime import datetime, timezone

BANDS6 = [('under150',0,150),('150_300',150,300),('300_1k',300,1000),
          ('1k_3k',1000,3000),('3k_6k',3000,6000),('over6k',6000,22050)]


def json_write(path, value):
    path = Path(path)
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')
    tmp.replace(path)


def scoped(path):
    path = Path(path).resolve()
    if path != ROOT and ROOT not in path.parents:
        raise ValueError('All paths must remain inside the audio workspace: ' + str(path))
    return path


def manifest_rows(path):
    data = json.loads(Path(path).read_text())
    if isinstance(data, list):
        return data
    if 'sounds' in data:
        return list(data['sounds'].values()) if isinstance(data['sounds'], dict) else data['sounds']
    return [r for group in ('beds','loops','shots') for r in data.get(group, [])]


def derive_recipe(row, overrides):
    key = row['key']
    kind = key.split('_', 1)[0]
    if kind not in ('bed','loop','shot') or not re.fullmatch(r'[a-zA-Z0-9_]+', key):
        raise ValueError('Invalid sound key: ' + key)
    text = (row.get('prompt','') + ' ' + row.get('place','')).lower()
    text = re.sub(r'no water(?: sounds| splashing)?', '', text)
    water = bool(re.search(r'water|trickl|fountain|wet|glug|gurg|churn|overflow', text))
    air = bool(re.search(r'\bwind\b|whoosh|exhale|air rushing|air moving|moving air|hush|desert|roof fabric|fabric.*flap', text))
    tonal = bool(re.search(r'tonal|\bhum\b|humming|drone|buzz|whine|bearing|\bring\b|ringing|moan|gong|glassy|resonan|creak', text))
    texture = water or air
    seconds = 24 if kind == 'bed' else 20 if kind == 'loop' else row.get('seconds')
    r = {'kind':kind, 'seconds':seconds, 'target_lufs':-27 if kind=='bed' else -24 if kind=='loop' else -25,
         'lowpass':4800 if texture else 4500, 'highpass':45 if kind=='bed' else 60,
         'cross':2.0, 'attack':.008, 'tail':min(1.5, max(.2, float(seconds or 6)*.2)),
         'physical_water':texture, 'natural_noise_texture':texture,
         'source_class':'water/air texture' if texture else 'tonal/mechanical' if tonal else 'impact/other',
         'machinery':bool(re.search(r'motor|pump|boiler|fan|vent|bearing|electri|pipe',text)),
         'comb_from':1400 if tonal else 1200, 'tonal_haze_candidate':tonal and not texture,
         'haze_depth_db':3, 'phone_min_relative_db':-14, 'phone_shelf_max_db':6,
         'bed_envelope_limit_db':8, 'treatment_envelope_p95_limit_db':2,
         'treatment_modulation_increase_limit_db':3, 'loop_envelope_change_limit_db':4,
         'selection_min_takes':2, 'trim_shot_onset':True,
         'recipe_reason':'Kind defaults, with prompt-derived natural noise protection and tonal treatment eligibility.'}
    r.update(overrides.get('defaults',{}).get(kind,{}))
    r.update(overrides.get('keys',overrides).get(key,{}))
    if not 0 <= r['phone_shelf_max_db'] <= 6:
        raise ValueError('Phone shelf must stay in 0..6 dB')
    if r['natural_noise_texture'] and r.get('haze_depth_db',0) != 0:
        r['haze_depth_db'] = 0
    return r


def envelope(signal):
    if signal.ndim == 1:
        signal = signal[:,None]
    # Channel-mean power avoids false quiet frames from stereo phase cancellation.
    n = int(.05*SR)
    use = signal[:len(signal)//n*n]
    if len(use) < n:
        return np.array([-120.])
    p = np.mean(use.reshape(-1,n,signal.shape[1])**2, axis=(1,2))
    return db(smooth(p[None,:],5,1)[0])


def envelope_stats(signal):
    e = envelope(signal)
    centered = e - np.median(e)
    # Swells require >=6dB rise AND fall to troughs within1.5s, with peaks
    # separated by1.5s. This avoids counting roughness inside a single lap;
    # the recorded old water bed yields its known9 swells. Counts diagnose,
    # while the independent8dB spread threshold rejects unstable beds.
    candidates = [i for i in range(6,len(e)-6) if e[i]==np.max(e[i-6:i+7]) and
                  e[i]-max(float(np.min(e[max(0,i-30):i+1])),float(np.min(e[i:min(len(e),i+31)])))>=6]
    kept=[]
    for i in sorted(candidates,key=lambda k:e[k],reverse=True):
        if all(abs(i-j)>=30 for j in kept): kept.append(i)
    v = centered - centered.mean()
    spec = abs(np.fft.rfft(v*np.hanning(len(v))))**2
    freq = np.fft.rfftfreq(len(v),.05)
    areas = [float(spec[(freq>=a)&(freq<b)].sum()) for a,b in [(.05,.2),(.2,.5),(.5,2),(2,5)]]
    denom=max(sum(areas),1e-20)
    return {'p95_minus_p5_db':round(float(np.percentile(e,95)-np.percentile(e,5)),3),
            'modulation_rms_db':round(float(np.std(e)),3), 'swells_per_file':len(kept),
            'swells_seconds':[round(i*.05,2) for i in sorted(kept)],
            'modulation_band_power_fractions':[round(a/denom,6) for a in areas],
            'analysis_window_seconds':.25,'analysis_hop_seconds':.05,
            'swell_definition':'>=6dB rise and fall within1.5s each side, local max over0.6s, peaks separated>=1.5s; calibrated on recorded9-swell water bed.'}


def highband_envelope(signal):
    power=None
    for ch in signal.T:
        p,f=power_spectrum(ch,2048,1024)
        q=band(p,f,2500,8000)
        power=q if power is None else power+q
    return db(smooth((power/signal.shape[1])[None,:],11,1)[0])


def haze_measure_or_clean(x, recipe, loop, clean=False):
    """clean_screams' local 25th-percentile/540 Hz floor, evaluated in chunks.

    Only harmonic-bearing frames can authorize a shallow haze treatment.
    Natural air/water never receives it. No hard gate or spectral subtraction.
    """
    n,hop = 2048,256
    spec,length,window,hop,pad=stft(x,circular=loop,n=n,hop=hop)
    mag=abs(spec)
    steady=smooth(mag,7,0)
    floor=np.empty_like(steady)
    padded=np.pad(steady,((0,0),(12,12)),mode='reflect')
    for start in range(0,len(steady),64):
        floor[start:start+64]=np.percentile(np.lib.stride_tricks.sliding_window_view(padded[start:start+64],25,axis=1),25,axis=-1)
    floor=smooth(smooth(floor,9,0),9,1)
    freq=np.fft.rfftfreq(n,1/SR)
    valid=(np.arange(len(spec))*hop>=pad)&(np.arange(len(spec))*hop+n<=pad+length)
    energy=(mag**2).sum(axis=1)
    active=valid & (energy>=np.max(energy[valid])*10**(-25/10)) if np.any(valid) else valid
    over=20*np.log10(np.maximum(steady,1e-12)/np.maximum(floor,1e-12))
    region=(freq>=700)&(freq<min(recipe['lowpass'],8000))
    # Count local separated maxima >17dB over floor in the low/mid band.
    partial=(over>17)&(mag>=np.roll(mag,1,axis=1))&(mag>np.roll(mag,-1,axis=1))&(freq[None,:]>=150)&(freq[None,:]<4500)
    harmonic_frames=active&(partial.sum(axis=1)>=3)
    use=harmonic_frames if np.any(harmonic_frames) else active
    scale=2/(n*np.sum(window**2))
    mask=(over<9)&region[None,:]
    q=(mag**2)*scale
    haze=float(np.mean(np.sum(q[use]*mask[use],axis=1))) if np.any(use) else 1e-20
    harmonic=float(np.mean(np.sum(q[use]*((over[use]>17)&region[None,:]),axis=1))) if np.any(use) else 1e-20
    record={'between_harmonics_haze_dbfs':round(float(db(haze)),3),
            'harmonic_to_haze_db':round(float(db(harmonic)-db(haze)),3),
            'harmonic_frame_fraction':round(float(np.mean(harmonic_frames[valid])) if np.any(valid) else 0,5),
            'definition':'25th-percentile magnitude floor in 25 bins (~540Hz), 7-frame magnitude smoothing, 9x9 floor smoothing; haze bins <9dB above floor, 700Hz..lowpass; active source frames only.',
            'applied':False,'depth_db':0}
    if not clean or not recipe.get('tonal_haze_candidate') or recipe.get('natural_noise_texture') or record['harmonic_frame_fraction']<.15:
        record['reason']='Measure only; natural noise protection or insufficient harmonic-bearing frames.'
        return x,record
    depth=min(6,max(0,recipe.get('haze_depth_db',3)))
    keep=np.clip((over-9)/8,0,1)
    now=20*np.log10(np.maximum(mag,1e-12)/np.maximum(floor,1e-12))
    keep=np.maximum(keep,np.clip((now-13)/8,0,1))
    keep=keep*keep*(3-2*keep)
    d=np.interp(freq,[0,700,2000,22050],[-depth*.35,-depth*.6,-depth,-depth])
    least=10**(d/20)
    gain=smooth(smooth(least[None,:]+(1-least[None,:])*keep,3,1),3,0)
    record.update(applied=depth>0,depth_db=depth,reason='Harmonic-bearing frames identified; shallow smooth local-floor attenuation, no natural noise gate.')
    return istft(spec*gain,(length,window,hop,pad)),record


def extended_metrics(signal,recipe,with_haze=True):
    if signal.ndim==1: signal=signal[:,None]
    mean_power=None
    quiet_levels=[]
    high_flat=[]
    all_tones=[]
    for channel in signal.T:
        power,freq=power_spectrum(channel)
        p=power.mean(axis=0)
        mean_power=p if mean_power is None else mean_power+p
        q,qf=power_spectrum(channel,2048,2048)
        order=np.argsort(q.sum(axis=1))[:max(1,len(q)//10)]
        quiet=q[order].mean(axis=0)
        quiet_levels.append(float(band(quiet,qf,2500,8000)))
        high=quiet[(qf>=2500)&(qf<8000)]
        high_flat.append(float(np.exp(np.mean(np.log(high+1e-30)))/max(float(np.mean(high)),1e-30)))
        all_tones.append(sorted(tonal_peaks(channel)+low_tonal_peaks(channel),key=lambda p:p['hz']))
    mean_power/=signal.shape[1]
    bands={name:round(float(db(band(mean_power,freq,lo,hi))),3) for name,lo,hi in BANDS6}
    total=float(db(mean_power.sum()))
    haze=None
    if with_haze and recipe.get('tonal_haze_candidate'):
        channel_haze=[haze_measure_or_clean(ch,recipe,recipe['kind']!='shot')[1] for ch in signal.T]
        haze=dict(max(channel_haze,key=lambda h:h['between_harmonics_haze_dbfs']))
        haze['individual_channels']=channel_haze
    return {'bands_dbfs':bands,'total_spectral_dbfs':round(total,3),
            'phone_300_3k_relative_db':round(float(db(band(mean_power,freq,300,3000)))-total,3),
            'quiet10_2p5k_8k_dbfs':round(float(db(np.mean(quiet_levels))),3),
            'quiet10_high_band_flatness':round(float(np.mean(high_flat)),5),
            'above_lowpass_dbfs':round(float(db(band(mean_power,freq,recipe['lowpass'],22050))),3),
            'above_lowpass_relative_db':round(float(db(band(mean_power,freq,recipe['lowpass'],22050)))-total,3),
            'steady_narrow_tones':max(sum(p['persistence']>.7 and p['power_dbfs']>-70 for p in tones) for tones in all_tones),
            'steady_narrow_tones_over800':max(sum(p['hz']>=800 and p['persistence']>.7 and p['power_dbfs']>-70 for p in tones) for tones in all_tones),
            'steady_tone_definition':'60Hz..11kHz, >8dB local prominence, persistence>70%, integrated five-bin power>-70dBFS; intentional low motor/body tones are counted, not automatically removed.',
            'steady_tones_by_channel':all_tones,'envelope':envelope_stats(signal),'haze':haze}


def low_tonal_peaks(x):
    """Extend the old >800Hz artifact counter to60..800Hz for diagnostics.

    Same long FFT, local-median prominence and persistence criteria as the
    original detector, but only evaluate the low bins to keep this cheap.
    """
    p,f=power_spectrum(x,16384,8192)
    long=p.mean(axis=0); level=db(long)
    end=int(np.searchsorted(f,850)); frame_level=db(p[:,:end+20]); result=[]
    for k in range(max(8,int(np.searchsorted(f,60))),int(np.searchsorted(f,800))):
        half=max(15,int(k*.122))
        prominence=level[k]-np.median(level[max(0,k-half):k+half+1])
        if prominence<8 or level[k]!=np.max(level[k-6:k+7]): continue
        power=float(db(long[k-2:k+3].sum()))
        if power<-95: continue
        neighbours=np.concatenate([frame_level[:,k-12:k-4],frame_level[:,k+5:k+13]],axis=1)
        persistence=float(np.mean(frame_level[:,k]-np.median(neighbours,axis=1)>8))
        hz=float(f[k])
        result.append({'hz':round(hz,2),'prominence_db':round(float(prominence),2),'power_dbfs':round(power,2),
                       'persistence':round(persistence,3),'on_50hz_grid':abs(hz-round(hz/50)*50)<=7.5})
    return result


def spectral_picture(signal,width=520,height=155):
    # Mean channel power, not mono fold-down, displays stereo contents honestly.
    acc=None
    for ch in signal.T:
        p,f=power_spectrum(ch,4096,1024)
        acc=p if acc is None else acc+p
    p=acc/signal.shape[1]
    # dBFS/bin on a common grid; normalize to 1Hz for FFT-independent density.
    level=db(p/(SR/4096))
    logfreq=np.geomspace(60,12000,height)
    times=np.linspace(0,len(level)-1,width)
    cols=np.clip(np.round(times).astype(int),0,len(level)-1)
    return np.stack([np.interp(logfreq,f,level[i]) for i in cols],axis=1).astype(np.float32)


def shelf(x,gain_db,loop):
    pad=0 if loop else int(.75*SR)
    y=np.pad(x,(pad,pad))
    freq=np.fft.rfftfreq(len(y),1/SR)
    step=np.clip(np.log2(np.maximum(freq,1)/300)+.5,0,1)
    shape=10**(gain_db*step*step*(3-2*step)/20)
    out=np.fft.irfft(np.fft.rfft(y)*shape,n=len(y))
    return out[pad:-pad] if pad else out


def trim_shot(signal):
    n=int(.005*SR)
    p=np.mean(signal[:len(signal)//n*n].reshape(-1,n,signal.shape[1])**2,axis=(1,2))
    floor=float(np.percentile(p,10))
    threshold=max(float(p.max())*10**(-35/10),floor*10**(12/10),1e-12)
    # Never let a loud background floor put the threshold above the event.
    threshold=min(threshold,float(p.max())*10**(-12/10))
    onset=np.flatnonzero(p>=threshold)
    index=int(onset[0]*n) if len(onset) else 0
    # shot_envelope adds precisely 50ms pre-roll; onset receives a short fade.
    return signal[index:],{'removed_leading_seconds':round(index/SR,5),'onset_threshold_dbfs':round(float(db(threshold)),3),
                           'pre_onset_guard_seconds':.05,'onset_definition':'First 5ms RMS frame above max(peak-35dB, quiet-floor+12dB), bounded at peak-12dB.'}


def assess_v3(path,recipe):
    base=raw_assessment(path,recipe)
    def finite_tree(v):
        if isinstance(v,dict): return all(finite_tree(x) for x in v.values())
        if isinstance(v,list): return all(finite_tree(x) for x in v)
        return not isinstance(v,(float,int)) or math.isfinite(v)
    if not finite_tree(base) or base['metrics']['rms_dbfs']<-100 or base['metrics']['seconds']<.3:
        raise ValueError('Silent, too-short or nonfinite source measurement')
    if recipe['kind']!='shot' and base['metrics']['seconds']<recipe['seconds']-.05:
        raise ValueError('Loop source shorter than required raw duration; no padding/synthesis allowed')
    x=decode(path)
    ext=extended_metrics(x,recipe,with_haze=False)
    gates=[]
    if recipe['kind']=='bed' and ext['envelope']['p95_minus_p5_db']>recipe['bed_envelope_limit_db']:
        gates.append('Lapping/unstable bed: 250ms-smoothed p95-p5 exceeds 8dB')
    phone=recipe['kind']!='shot' and ext['phone_300_3k_relative_db']<recipe['phone_min_relative_db']
    if phone: gates.append('Phone band below -14dB relative; alternate take preferred before <=6dB shelf')
    if base['metrics']['sample_peak_dbfs']>1:
        gates.append('Source reconstructed peak >+1dBFS; possible source clipping')
    base.update(extended_metrics=ext,raw_gates=gates,phone_needs_tilt=phone,
                hard_source_fail=any('Lapping/' in s for s in gates))
    return base


def process_v3(key,row,recipe,rawdir,output,work):
    paths=sorted(rawdir.glob(key+'__take*.mp3'))
    choices=[]
    rejected=[]
    for p in paths:
        try: choices.append(assess_v3(p,recipe))
        except (subprocess.CalledProcessError,ValueError,IndexError) as e:
            rejected.append({'file':p.name,'why':'Decode/measurement failed: '+str(e)[:200]})
    if not choices:
        (output/'masters'/(key+'.ogg')).unlink(missing_ok=True)
        (output/'selected_raw'/(key+'.mp3')).unlink(missing_ok=True)
        return {'recipe':recipe,'numeric_pass':False,'listening_verified':False,'faults':['No usable raw take'],
                'weak':[],'selection_candidates':rejected,'selected_take':None,'mastered':False,'gates':{'usable_source':False}}
    # Hard lap gate takes priority. Then take substitution avoids an EQ rescue.
    choices.sort(key=lambda c:(c['hard_source_fail'],c['phone_needs_tilt'],c['score'],c['file']))
    attempts=[]
    # First test all phone-ready steady sources, then only bounded shelf rescue.
    for choice in choices:
        chosen=rawdir/choice['file']
        raw=decode(chosen)
        source=raw if recipe['kind']=='bed' else raw.mean(axis=1)[:,None]
        if recipe['kind']=='bed' and source.shape[1]==1:
            source=np.repeat(source,2,axis=1)  # source mono is disclosed as weak below
        source=source[:int(recipe['seconds']*SR)] if recipe['kind']!='shot' else source
        before=extended_metrics(source,recipe)
        trimmed=None
        if recipe['kind']=='shot' and recipe.get('trim_shot_onset'):
            source,trimmed=trim_shot(source)
        loop=recipe['kind']!='shot'
        done=[]; reports=[]; treatment_before=[]; treatment_after=[]
        for ch in source.T:
            x,shaved=shave_comb(ch,recipe,loop)
            x,denoise=gentle_static_reduction(x,recipe,loop)
            if recipe.get('natural_noise_texture'):
                denoise['reason']='Intended water/air noise: no broadband spectral gate; retain texture, band-limit and shave grid defects only.'
            x,haze=haze_measure_or_clean(x,recipe,loop,clean=True) if recipe.get('tonal_haze_candidate') else (x,{'applied':False,'depth_db':0,'reason':'Non-tonal or intended water/air texture; no haze gate.'})
            treatment_before.append(ch); treatment_after.append(x)
            if loop: x=cyclic_crossfade(x,recipe['cross'])
            x=band_limit(x,recipe,loop)
            if not loop: x=shot_envelope(x,recipe)
            done.append(x)
            reports.append({'removed_comb_candidates':shaved,'broadband_reduction':denoise,'haze_reduction':haze})
        eb=envelope(np.stack(treatment_before,axis=1)); ea=envelope(np.stack(treatment_after,axis=1))
        active=eb>np.max(eb)-35
        residual=(ea-np.median(ea[active]))-(eb-np.median(eb[active]))
        treatment={'active_envelope_centered_change_p95_db':round(float(np.percentile(abs(residual[active]),95)),3),
                   'modulation_rms_before_db':round(float(np.std(eb[active])),3),
                   'modulation_rms_after_db':round(float(np.std(ea[active])),3),
                   'modulation_increase_db':round(float(20*np.log10(max(float(np.std(ea[active])),1e-9)/max(float(np.std(eb[active])),1e-9))),3),
                   'justification':'Same-length source versus spectral-treatment stage, before intended fades/crossfade/EQ; centered levels remove normalization. <=2dB p95 and <=3dB modulation increase.'}
        hb=highband_envelope(np.stack(treatment_before,axis=1)); ha=highband_envelope(np.stack(treatment_after,axis=1))
        hv=hb>float(np.max(hb))-25
        hr=(ha-np.median(ha[hv]))-(hb-np.median(hb[hv]))
        treatment['highband_centered_change_p95_db']=round(float(np.percentile(abs(hr[hv]),95)),3)
        treatment['highband_modulation_sd_before_db']=round(float(np.std(hb[hv])),3)
        treatment['highband_modulation_sd_after_db']=round(float(np.std(ha[hv])),3)
        treatment['highband_modulation_increase_db']=round(float(20*np.log10(max(float(np.std(ha[hv])),1e-9)/max(float(np.std(hb[hv])),1e-9))),3)
        treatment['highband_justification']='2.5–8kHz envelope at same source positions, 250ms smoothing; source-active HF frames (>peak-25dB), centered p95 change <=3dB. Gate-induced HF pumping checked separately from broadband movement.'
        master=np.stack(done,axis=1)
        tilt=0.0
        epre=extended_metrics(master,recipe,with_haze=False)
        if loop and epre['phone_300_3k_relative_db']<recipe['phone_min_relative_db']:
            for gain in (2,4,6):
                if gain>recipe['phone_shelf_max_db']: break
                candidate=np.stack([shelf(ch,gain,loop) for ch in master.T],axis=1)
                ce=extended_metrics(candidate,recipe,with_haze=False)
                tilt=gain
                if ce['phone_300_3k_relative_db']>=recipe['phone_min_relative_db']: break
            if tilt: master=candidate
        rotation=None
        if loop: master,rotation=rotate_stable_seam(master)
        temp=work/(key+'.wav')
        write_wav(temp,master)
        clean_loud=loudness(temp)
        gain=min(9,recipe['target_lufs']-(clean_loud['lufs'] or -99))
        master*=10**(gain/20)
        master,limiting=gentle_peak_limiter(master,loop=loop)
        final=output/'masters'/(key+'.ogg')
        write_wav(temp,master); encode_ogg(temp,final)
        decoded=decode(final)
        metric=signal_metrics(decoded,recipe['lowpass'],loop=loop,detailed_channels=True)
        metric.update(loudness(final))
        overshoot=max(metric['sample_peak_dbfs'],metric.get('true_peak_dbfs') or -99)+3.2
        if overshoot>0:
            master*=10**(-overshoot/20)
            write_wav(temp,master); encode_ogg(temp,final)
            decoded=decode(final)
            metric=signal_metrics(decoded,recipe['lowpass'],loop=loop,detailed_channels=True); metric.update(loudness(final))
        if loop and seam_fault(metric) and rotation:
            old_metric=metric
            offset=int(round(rotation['rotation_seconds']*SR))
            candidate=np.roll(master,offset,axis=0)
            write_wav(temp,candidate); encode_ogg(temp,final)
            alternate=signal_metrics(decode(final),recipe['lowpass'],loop=True,detailed_channels=True); alternate.update(loudness(final))
            if not seam_fault(alternate):
                master,metric=candidate,alternate
                rotation.update(encoded_fallback='Original crossfade phase has stronger decoded seam',final_rotation_seconds=0,rejected_encoded_seam_channels=old_metric['loop_seam_channels'])
            else:
                write_wav(temp,master); encode_ogg(temp,final)
                rotation['alternate_original_phase_also_failed']=alternate['loop_seam_channels']
            decoded=decode(final)
        after=extended_metrics(decoded,recipe)
        issues=faults(metric,recipe)
        if loop and choice['metrics']['seconds']<recipe['seconds']-.05:
            issues.append('Raw loop source shorter than required '+str(recipe['seconds'])+'s; no padding or synthesis allowed')
        if loop and abs(metric['seconds']-(recipe['seconds']-recipe['cross']))>.05:
            issues.append('Decoded loop duration differs from required '+str(recipe['seconds']-recipe['cross'])+'s')
        if limiting['maximum_reduction_db']>8: issues.append('More than 8dB peak limiting')
        if choice['hard_source_fail']: issues.append('Selected raw bed laps/has >8dB slow envelope spread; all alternatives exhausted')
        if loop and after['phone_300_3k_relative_db']<recipe['phone_min_relative_db']: issues.append('Phone gate failed after alternate takes and bounded shelf')
        if recipe['kind']=='bed' and after['envelope']['p95_minus_p5_db']>recipe['bed_envelope_limit_db']: issues.append('Final bed envelope p95-p5 >8dB: lapping/unstable bed')
        if treatment['active_envelope_centered_change_p95_db']>recipe['treatment_envelope_p95_limit_db']: issues.append('Spectral treatment changes active envelope by >2dB p95')
        if treatment['highband_centered_change_p95_db']>3:
            issues.append('Spectral treatment changes high-band envelope by >3dB p95')
        if treatment['highband_modulation_increase_db']>3 and treatment['highband_modulation_sd_after_db']-treatment['highband_modulation_sd_before_db']>.5:
            issues.append('Spectral treatment adds high-band pumping: >3dB modulation and >0.5dB SD')
        # Tiny pre-treatment variance makes ratio unstable; require real added movement.
        if treatment['modulation_increase_db']>recipe['treatment_modulation_increase_limit_db'] and treatment['modulation_rms_after_db']-treatment['modulation_rms_before_db']>.5:
            issues.append('Spectral treatment adds >3dB modulation and >0.5dB envelope SD')
        loop_delta=after['envelope']['p95_minus_p5_db']-before['envelope']['p95_minus_p5_db']
        if loop and abs(loop_delta)>recipe['loop_envelope_change_limit_db']: issues.append('Final loop slow envelope spread changes >4dB; filtering/crossfade cannot justify it')
        full_chain_residual=None
        if loop:
            baseline=np.stack([band_limit(cyclic_crossfade(ch,recipe['cross']),recipe,True) for ch in source.T],axis=1)
            # Known crossfade and band limit form the reference. Shelf, static
            # treatment, limiting and encoding remain inside this complete check.
            offset=0 if rotation.get('final_rotation_seconds')==0 else int(round(rotation['rotation_seconds']*SR))
            baseline=np.roll(baseline,-offset,axis=0)
            be=envelope(baseline); de=envelope(decoded)
            count=min(len(be),len(de)); be=be[:count]; de=de[:count]
            full_chain_residual=round(float(np.percentile(abs((be-np.median(be))-(de-np.median(de))),95)),3)
            if full_chain_residual>4:
                issues.append('Complete loop chain changes aligned centered envelope >4dB p95')
        gainmatch=metric['lufs']-(choice['metrics']['lufs'] or metric['lufs'])
        static_delta=after['quiet10_2p5k_8k_dbfs']-(before['quiet10_2p5k_8k_dbfs']+gainmatch)
        if static_delta>3 and recipe['kind']!='shot': issues.append('Quiet high-band floor increased >3dB at equal integrated loudness')
        # Detect added line ENERGY on any grid. A gate revealing an existing
        # harmonic by lowering its neighbours is not a newly generated tone.
        newlines=[]
        for ci,ts in enumerate(after['steady_tones_by_channel']):
            p,f=power_spectrum(source[:,min(ci,source.shape[1]-1)],16384,8192)
            long=p.mean(axis=0)
            for tone in ts:
                if tone['hz']<recipe['comb_from'] or tone['persistence']<=.7 or tone['power_dbfs']<=-70: continue
                k=int(round(tone['hz']/(SR/16384)))
                original=float(db(long[max(0,k-2):k+3].sum()))+gainmatch+tilt
                if tone['power_dbfs']>original+3: newlines.append(tone['hz'])
        if newlines: issues.append('New sustained narrow-line energy introduced: '+','.join(str(k) for k in newlines)+'Hz')
        haze_delta=None
        if before['haze'] and after['haze']:
            bh=before['haze']; ah=after['haze']
            haze_delta=round(ah['between_harmonics_haze_dbfs']-(bh['between_harmonics_haze_dbfs']+gainmatch),3)
            comparable=min(bh['harmonic_frame_fraction'],ah['harmonic_frame_fraction'])>=.05 and abs(bh['harmonic_frame_fraction']-ah['harmonic_frame_fraction'])<=.5
            if comparable and haze_delta>3+tilt: issues.append('Between-harmonics haze increased >3dB at matched loudness beyond documented shelf')
        attempt={'file':choice['file'],'phone_shelf_db':tilt,'faults':issues,'numeric_pass':not issues}
        attempts.append(attempt)
        result={'selected_take':choice['file'],'selected_raw_sha256':choice['sha256'],'master_sha256':sha256(final),
                'recipe':recipe,'processing':reports,'normalization_gain_db':round(gain,3),'linked_peak_limiter':limiting,
                'seam_rotation':rotation,'encoder_overshoot_reduction_db':round(max(overshoot,0),3),
                'pre_gain_clean_loudness':clean_loud,'final_decoded_metrics':metric,
                'static_before':before,'static_after':after,'static_equal_loudness_gain_db':round(gainmatch,3),
                'quiet_floor_equal_loudness_change_db':round(static_delta,3),'treatment_envelope_integrity':treatment,
                'haze_equal_loudness_change_db':haze_delta,'introduced_narrow_lines_hz':newlines,
                'final_loop_envelope_spread_change_db':round(loop_delta,3),'phone_shelf_db':tilt,
                'full_chain_loop_envelope_residual_p95_db':full_chain_residual,
                'phone_shelf_reason':'Other takes considered before smooth 300Hz shelf, <=6dB; retains spectral shape beyond bounded tilt.' if tilt else 'None needed',
                'shot_trim':trimmed,'faults':issues,'numeric_pass':not issues,'listening_verified':False,'mastered':True,
                'selection_rationale':'Prefer raw bed envelope <=8dB and phone band >=-14dB, then original bounded technical score; try alternatives after final decoded QC failures. No subjective superiority claim.'}
        if not issues: break
    # If no attempt passes, preserve the least-faulted attempt, reproducibly.
    # Reprocess the preferred failed candidate if the last attempt was worse.
    best=min(attempts,key=lambda a:(len(a['faults']),next(i for i,c in enumerate(choices) if c['file']==a['file'])))
    if best['file']!=result['selected_take']:
        # Cache failed PCM? Avoid RAM/cache burden: run only that source in a
        # bounded recursive call, retaining complete original candidate evidence.
        isolated=work/'retry_raw'; isolated.mkdir(exist_ok=True)
        link=isolated/best['file']; link.unlink(missing_ok=True); link.symlink_to(rawdir/best['file'])
        result=process_v3(key,row,recipe,isolated,output,work)
        link.unlink(); isolated.rmdir()
    selected=next(c for c in choices if c['file']==result['selected_take'])
    shutil.copyfile(rawdir/selected['file'],output/'selected_raw'/(key+'.mp3'))
    for c in choices:
        c['why_lost']='Selected' if c['file']==result['selected_take'] else '; '.join(c['raw_gates']) or ('Higher original technical score / tie-break order, or final decoded QC failed')
        att=next((a for a in attempts if a['file']==c['file']),None)
        if att and c['file']!=result['selected_take']: c['why_lost']+='; '+('; '.join(att['faults']) or 'alternative already passed')
    weak=[]
    if len(choices)<2: weak.append('Only one usable take; selection comparison unavailable')
    if len(choices)<(2 if recipe['kind']=='shot' else 3): weak.append('Fewer usable takes than requested by generation job')
    if result['phone_shelf_db']: weak.append('Needed '+str(result['phone_shelf_db'])+'dB phone shelf')
    if recipe['kind']=='bed' and 6<result['static_after']['envelope']['p95_minus_p5_db']<=8: weak.append('Bed approaches 8dB envelope limit')
    if recipe['kind']=='bed' and decode(rawdir/selected['file']).shape[1]==1: weak.append('Raw bed is mono; duplicated to stereo, no invented width')
    if result['normalization_gain_db']>=9: weak.append('Reached +9dB normalization cap')
    result.update(selection_candidates=choices+rejected,mastering_attempts=attempts,weak=weak,
                  gates={'old_chain':not faults(result['final_decoded_metrics'],recipe),
                         'phone':recipe['kind']=='shot' or result['static_after']['phone_300_3k_relative_db']>=recipe['phone_min_relative_db'],
                         'raw_lapping':not selected['hard_source_fail'],
                         'final_bed_steady':recipe['kind']!='bed' or result['static_after']['envelope']['p95_minus_p5_db']<=8,
                         'treatment_envelope':not any('Spectral treatment' in s for s in result['faults']),
                         'final_envelope_change':not any('spread changes' in s for s in result['faults']),
                         'no_added_haze_or_lines':not any('floor increased' in s or 'introduced' in s or 'haze increased' in s for s in result['faults']),
                         'take_comparison':len(choices)>=2})
    print(f"{key}: {result['selected_take']}, {result['final_decoded_metrics']['lufs']} LUFS, {'PASS' if result['numeric_pass'] else 'FAIL'}; {'; '.join(result['faults'])}",flush=True)
    return result


def regenerate_prompt(row, reasons):
    kind=row['key'].split('_')[0]
    original=row.get('prompt','')
    corrected=ROOT/'out/prompt_overrides.json'
    if corrected.exists():
        prompt=json.loads(corrected.read_text()).get(row['key'])
        if prompt and len(prompt)<=440: return prompt
    if kind=='bed':
        original=original.replace('with a slow beating wobble','at a stable even level').replace('slow low flutters','constant gentle pressure').replace('slow heavy air moving','steady heavy air circulating').replace('drifting between','held steadily between')
    # Preserve the event/place and append only requirements supported by QC.
    suffix=' Normal recording level. Clean source, no electronic static or added hiss.'
    if kind=='bed': suffix+=' Continuous even level, no swells, lapping, pulses or fade cycles. Audible 300Hz-3kHz body, not sub-bass alone.'
    elif kind=='loop': suffix+=' Continuous even flow with audible midrange body; no pauses or added hiss.'
    else: suffix+=' One clear event with natural decay and silence before/after; no background noise.'
    if any('alike' in r.lower() for r in reasons): suffix+=' Emphasize this room material and resonance distinctly.'
    maxprefix=440-len(suffix)
    prefix=original[:maxprefix]
    if len(original)>maxprefix: prefix=prefix.rsplit(' ',1)[0].rstrip(' ,;')+'.'
    return (prefix+suffix)[:440]


def generation_provenance(rows,report,rawdir):
    logs=[]
    for name in ('beds_log.json','shots_log.json'):
        p=rawdir/name
        if p.exists():
            try: logs.append((name,json.loads(p.read_text())))
            except json.JSONDecodeError: logs.append((name,{'read_error':'Generation log incomplete at read time'}))
    sounds={}
    for r in rows:
        key=r['key']; q=report['sounds'].get(key,{})
        selected=q.get('selected_take')
        take=int(re.search(r'__take(\d+)',selected).group(1)) if selected else None
        info={'prompt':r.get('prompt'),'section':r.get('section'),'place':r.get('place'),
              'selected_take':selected,'take_number':take,'raw_sha256':q.get('selected_raw_sha256'),
              'generation_ids':[],'generation_log_matches':[]}
        for name,log in logs:
            for t in log.get('takes',[]):
                match=Path(t.get('file','')).name==selected or (t.get('key')==key and str(t.get('take'))==str(take))
                if selected and match:
                    safe={k:v for k,v in t.items() if k in ('key','take','file','generation_id','node_id','session_id','status','seconds','prompt','model_id','prompt_influence','loop')}
                    info['generation_log_matches'].append({'log':name,**safe})
                    if t.get('generation_id'): info['generation_ids'].append(t['generation_id'])
            info.setdefault('job_ids',{})[name]={k:log.get(k) for k in ('provider','model','flow_id','prompt_influence','loop') if log.get(k) is not None}
        sounds[key]=info
    return {'date':datetime.now(timezone.utc).isoformat(),'provider':'ElevenLabs','sounds':sounds,
            'script_sha256':sha256(__file__),'sample_rate':SR,'codec':'OGG Vorbis q6',
            'listening_verified':False,'network_used':False,'synthetic_audio_outputs':False}


def create_visuals_and_distinctness(rows,report,output):
    from report_v3 import write_sheet,compute_distinctness
    pictures=output.parent/'spectrograms'; pictures.mkdir(parents=True,exist_ok=True)
    sheetpaths=[]; profiles={}; audit_rows=[]; audit_number=1; audit_paths=[]
    for q in report['sounds'].values():
        q['weak']=[w for w in q.get('weak',[]) if not w.startswith('Bed too alike in measured')]
    for kind in ('bed','loop','shot'):
        sheets=[]; number=1
        for r in rows:
            key=r['key']; q=report['sounds'].get(key,{})
            if not key.startswith(kind+'_') or not q.get('mastered'): continue
            raw=decode(output/'selected_raw'/(key+'.mp3'))
            master=decode(output/'masters'/(key+'.ogg'))
            if kind!='shot' and (q.get('phone_shelf_db',0)>0 or (q.get('quiet_floor_equal_loudness_change_db') or 0)>3):
                match=raw.copy() if kind=='bed' else raw.mean(axis=1)[:,None]
                if q.get('phone_shelf_db'):
                    match=np.stack([shelf(ch,q['phone_shelf_db'],True) for ch in match.T],axis=1)
                scalar=q['normalization_gain_db']-q.get('encoder_overshoot_reduction_db',0)
                match*=10**(scalar/20)
                audit_rows.append({'key':key,'raw':spectral_picture(match),'master':spectral_picture(master),
                                   'raw_seconds':len(match)/SR,'master_seconds':len(master)/SR,
                                   'gates':f"RAW GAIN {scalar:+.1f}DB SHELF {q.get('phone_shelf_db',0):+.1f}DB"})
                if len(audit_rows)==8:
                    p=pictures/f'gain_audit_{audit_number}.png'; write_sheet(audit_rows,p,raw_label='GAIN/EQ-MATCHED RAW')
                    audit_paths.append(str(p.relative_to(ROOT))); audit_rows=[]; audit_number+=1
            sheets.append({'key':key,'kind':kind,'raw':spectral_picture(raw),'master':spectral_picture(master),
                           'raw_seconds':len(raw)/SR,'master_seconds':len(master)/SR})
            if kind=='bed':
                ext=q['static_after']; e=ext['envelope']
                profiles[key]={'band_db':[ext['bands_dbfs'][name] for name,_,_ in BANDS6],
                               'envelope_features':{'p95_minus_p5_db':e['p95_minus_p5_db'],'modulation_rms_db':e['modulation_rms_db'],
                                                    **{'modulation_band_'+str(i):v for i,v in enumerate(e['modulation_band_power_fractions'])}},
                               'reference':False}
            if len(sheets)==8:
                p=pictures/f'{kind}_{number}.png'; write_sheet(sheets,p,db_min=-120,db_max=-35)
                sheetpaths.append(str(p.relative_to(ROOT))); sheets=[]; number+=1
        if sheets:
            p=pictures/f'{kind}_{number}.png'; write_sheet(sheets,p,db_min=-120,db_max=-35)
            sheetpaths.append(str(p.relative_to(ROOT)))
    if audit_rows:
        p=pictures/f'gain_audit_{audit_number}.png'; write_sheet(audit_rows,p,raw_label='GAIN/EQ-MATCHED RAW')
        audit_paths.append(str(p.relative_to(ROOT)))
    references={}
    for key in ('bed_hall','bed_service','bed_water'):
        path=ROOT/'input/assets/masters'/(key+'.ogg')
        if not path.exists(): continue
        r={**LEGACY_RECIPES[key],'tonal_haze_candidate':False}
        ext=extended_metrics(decode(path),r,with_haze=False)
        references[key]=ext
        if key!='bed_water':
            e=ext['envelope']
            profiles['old_'+key]={'band_db':[ext['bands_dbfs'][name] for name,_,_ in BANDS6],
                'envelope_features':{'p95_minus_p5_db':e['p95_minus_p5_db'],'modulation_rms_db':e['modulation_rms_db'],
                                    **{'modulation_band_'+str(i):v for i,v in enumerate(e['modulation_band_power_fractions'])}},'reference':True}
    distinct=compute_distinctness(profiles)
    distinct['reference_measurements']=references
    historical=json.loads((ROOT/'input/assets/qc.json').read_text())['sounds']
    for key,ref in references.items():
        ref['legacy_46ms_envelope_p95_minus_p5_db']=historical[key]['final_decoded_metrics']['envelope_p95_minus_p5_db']
        ref['legacy_46ms_note']='Historical short-frame spread; new slow-swell test uses 250ms smoothing, so its spread may be smaller.'
    if 'bed_water' in references:
        assert references['bed_water']['envelope']['p95_minus_p5_db']>8
        report['negative_controls']['recorded_old_lapping_bed_rejected']={'key':'bed_water','envelope':references['bed_water']['envelope'],'v3_gate_pass':False}
    distinct['missing_new_beds']=[r['key'] for r in rows if r['key'].startswith('bed_') and r['key'] not in profiles]
    json_write(output/'distinctness.json',distinct)
    report['distinctness']=distinct
    report['spectrogram_sheets']=sheetpaths
    report['gain_matched_diagnostic_sheets']=audit_paths
    # Similarity is a review/regeneration weakness, not a claim of auditory identity.
    for pair in distinct.get('too_alike',[]):
        for key in pair.get('keys',[]):
            if key in report['sounds']:
                weak=report['sounds'][key].setdefault('weak',[])
                message='Bed too alike in measured band/modulation profile; see distinctness matrix'
                if message not in weak: weak.append(message)
    return sheetpaths


def write_report(rows,report,output):
    from report_v3 import distinctness_markdown
    lines=['# Poolrooms v3 measured mastering report','',
           'All audio processed sequentially at 44.1 kHz. No listening, game playback, phone playback or subjective static verification performed. `listening_verified: false` for every sound. Passing numbers do not prove absence of audible AI static. Failed masters are retained for review and must not be treated as approved.', '',
           'Floor comparisons can change because quiet-frame populations change after crossfade/trim and because EBU gated active content changes. A stronger equal-LUFS floor does not prove newly generated hiss. QC also records applied-scalar floor change, harmonic haze, narrow-line energy and envelope integrity. Equal-LUFS values are null where the meter reaches its -70LUFS absolute floor.', '',
           'Six bands are channel-mean spectral power in dBFS: <150 / 150–300 / 300–1k / 1k–3k / 3k–6k / >6k Hz. Floor is the quietest 10% of full-energy frames in 2.5–8kHz. Before/after values below are absolute dBFS; equal-LUFS floor deltas and per-channel tone lists are in qc.json. High-band flatness is quiet-frame flatness. Above LP is energy above the exact low-pass; the inherited gate evaluates above 1.3×LP. Tones count60Hz..11kHz with >8dB prominence, >70% persistence and >−70dBFS five-bin power; intended low motor tones are counted separately from the inherited >800Hz/grid defect gate. Haze uses the clean_screams local floor only for eligible tonal sounds.', '',
           'A bed fails at >8dB p95–p5 in a 250ms-smoothed envelope. This deliberately rejects unstable room beds; it does not flatten them. Phone gate requires 300Hz–3kHz >=−14dB relative to total for both beds and spatial loops. Alternate takes precede a smooth <=6dB shelf. Spectral-treatment envelope p95 change <=2dB; added modulation <=3dB with >0.5dB SD change; final loop spread change <=4dB. Source replacement is preferred to stronger processing.', '',
           '| Key | Kind | Section | s | LUFS | True peak dBFS | Bands dBFS (six) | Floor raw → master | Flatness raw → master | Above LP raw → master | Tones raw → master | Haze raw → master | Swell raw → master / swells | Gates |',
           '|---|---|---|---:|---:|---:|---|---|---|---|---|---|---|---|']
    for r in rows:
        key=r['key']; q=report['sounds'].get(key,{})
        if not q.get('mastered'):
            lines.append(f"| {key} | {key.split('_')[0]} | {r.get('section','')} | — | — | — | — | — | — | — | — | — | — | FAIL: {'; '.join(q.get('faults',['not processed']))} |")
            continue
        m=q['final_decoded_metrics']; b=q['static_before']; a=q['static_after']
        hz='n/a (natural noise/non-tonal)'
        if b['haze'] and a['haze']: hz=f"{b['haze']['between_harmonics_haze_dbfs']:.1f} → {a['haze']['between_harmonics_haze_dbfs']:.1f}"
        gate='PASS' if q['numeric_pass'] else 'FAIL: '+'; '.join(q['faults'])
        if q.get('weak'): gate+='; WEAK: '+'; '.join(q['weak'])
        lines.append(f"| {key} | {key.split('_')[0]} | {r.get('section','')} | {m['seconds']:.2f} | {m['lufs']:.1f} | {m['true_peak_dbfs']:.1f} | {' / '.join(f'{a['bands_dbfs'][n]:.1f}' for n,_,_ in BANDS6)} | {b['quiet10_2p5k_8k_dbfs']:.1f} → {a['quiet10_2p5k_8k_dbfs']:.1f} | {b['quiet10_high_band_flatness']:.3f} → {a['quiet10_high_band_flatness']:.3f} | {b['above_lowpass_dbfs']:.1f} → {a['above_lowpass_dbfs']:.1f} | {b['steady_narrow_tones']} → {a['steady_narrow_tones']} | {hz} | {b['envelope']['p95_minus_p5_db']:.1f} → {a['envelope']['p95_minus_p5_db']:.1f} / {a['envelope']['swells_per_file']} | {gate} |")
    lines+=['','## Bed distinctness','',distinctness_markdown(report.get('distinctness',{})),'',
            '## Failed and weak sources: regenerate rather than process harder','']
    for r in rows:
        q=report['sounds'].get(r['key'],{})
        reasons=q.get('faults',[])+q.get('weak',[])
        if reasons:
            prompt=regenerate_prompt(r,reasons)
            q['regenerate_prompt']=prompt
            lines += [f"- **{r['key']}**: {'; '.join(reasons)}",f'  - Regenerate ({len(prompt)} characters): {prompt}']
    lines+=['','## Regression against 2026-10-09','']
    val=ROOT/'out/validation/comparison.json'
    if val.exists():
        v=json.loads(val.read_text())
        lines.append(f"Same takes: {v['same_takes']}/{v['count']}; tolerance matches: {v['within_tolerance']}/{v['count']}. Full per-field deltas: validation/comparison.json.")
        lines.append(v['fan_exception'])
        for k,q in v['keys'].items():
            if q.get('differences'): lines.append(f"- {k}: "+'; '.join(q['differences']))
    lines+=['','## Pictures and unverified work','',
            'Spectrograms are absolute channel-mean power density dBFS/Hz, log frequency 60Hz–12kHz, common −120..−35dB scale; raw left / decoded Vorbis master right. No arbitrary row normalization. Look for added haze/lines/holes. Visual review findings are in out/visual_review.json.',
            '','Not verified: auditory static absence; aesthetic distinction; semantic prompt compliance; phone-speaker audibility in playback; spatial/gameplay mix; Roblox import/playback. No network, synthesis, upload or Studio actions performed. Negative-control arrays are internal tests only and produce no media.', '',
            'Generation wait: '+json.dumps(report.get('generation_wait',{})), '',
            'Gain-matched diagnostic views apply the recorded scalar and phone shelf to raw data for pictures only, with the same absolute scale; these are not audio deliverables. They distinguish raised pre-existing floor from added structure. Crossfade/seam rotation changes time location.', '',
            'Sheets: '+', '.join(report.get('spectrogram_sheets',[])+report.get('gain_matched_diagnostic_sheets',[]))]
    (output.parent/'REPORT.md').write_text('\n'.join(lines)+'\n')


def refresh_numeric_evidence(report):
    """Expand each inherited threshold into an explicit reproducible gate.

    EBU R128's -70LUFS absolute floor is not a valid gated integrated value.
    Such sources retain absolute noise metrics, but equal-LUFS claims are null.
    """
    for q in report['sounds'].values():
        for c in q.get('selection_candidates',[]):
            if 'metrics' in c:
                c['metrics']['lufs_valid']=c['metrics'].get('lufs') is not None and c['metrics']['lufs']>-69.9
        if not q.get('mastered'): continue
        if q['recipe']['kind']=='bed' and q['static_after']['envelope']['p95_minus_p5_db']>8:
            q['weak']=[w for w in q.get('weak',[]) if w!='Bed approaches 8dB envelope limit']
        r=q['recipe']; m=q['final_decoded_metrics']; g=q.setdefault('gates',{})
        selected=next(c for c in q['selection_candidates'] if c['file']==q['selected_take'])
        q['static_comparison_method']='Equal integrated loudness, raw and decoded output; source/output both within gated meter range.'
        if not selected['metrics']['lufs_valid'] or m['lufs']<=-69.9:
            q['static_comparison_method']='Equal-LUFS unavailable: source or output reaches the -70LUFS absolute meter floor. Absolute band/floor metrics and applied gain remain measured.'
            q['static_equal_loudness_gain_db']=None
            q['quiet_floor_equal_loudness_change_db']=None
            q['haze_equal_loudness_change_db']=None
            q['weak']=[w for w in q.get('weak',[]) if not w.startswith('Equal-LUFS unavailable')]
            q['weak'].append('Equal-LUFS unavailable at -70LUFS meter floor; source level unsuitable')
            q['faults']=[s for s in q['faults'] if not ('at equal integrated loudness' in s or 'at matched loudness' in s)]
        q['pre_gain_clean_loudness']['lufs_valid']=q['pre_gain_clean_loudness'].get('lufs') is not None and q['pre_gain_clean_loudness']['lufs']>-69.9
        scalar=q['normalization_gain_db']-q.get('encoder_overshoot_reduction_db',0)
        q['quiet_floor_after_applied_scalar_change_db']=round(q['static_after']['quiet10_2p5k_8k_dbfs']-q['static_before']['quiet10_2p5k_8k_dbfs']-scalar,3)
        q['floor_comparison_caveat']='Different quiet-frame populations after onset trim/crossfade and spectral shaping; an equal-LUFS increase means stronger floor relative to gated active content, not proof of newly generated hiss. Compare applied gain, band profiles, modulation, local haze and pictures.'
        if q.get('static_equal_loudness_gain_db') is not None and abs(q['static_equal_loudness_gain_db']-scalar)>3:
            q['static_comparison_method']+=' Gated loudness change differs from applied scalar by >3dB; artifact attribution is ambiguous.'
        def grid_count(tones):
            return sum(p['hz']>=r['comb_from'] and p['power_dbfs']>-70 and p['persistence']>.7 and p['on_50hz_grid'] for p in tones)
        g.update(decoded_peak=m['sample_peak_dbfs']<=-3 and m.get('true_peak_dbfs') is not None and m['true_peak_dbfs']<=-3,
                 out_of_band_mid=m['above_1p3_cutoff_dbfs']<=-68 and m['above_cutoff_relative_db']<=-34,
                 out_of_band_each_channel=all(c['above_1p3_cutoff_dbfs']<=-68 and c['above_cutoff_relative_db']<=-34 for c in m['individual_channel_noise_and_tones']),
                 loudness_target=m.get('lufs') is not None and m['lufs']>-69.9 and abs(m['lufs']-r['target_lufs'])<=3,
                 loop_seam_or_shot_guards=not seam_fault(m) if r['kind']!='shot' else m['first20ms_peak_dbfs']<=-75 and m['last20ms_peak_dbfs']<=-75,
                 residual_grid_mid=grid_count(m['all_tonal_peaks'])<=3,
                 residual_grid_each_channel=all(grid_count(c['all_tonal_peaks'])<=3 for c in m['individual_channel_noise_and_tones']),
                 limiter_max_8db=q['linked_peak_limiter']['maximum_reduction_db']<=8,
                 duration=r['kind']=='shot' or abs(m['seconds']-(r['seconds']-r['cross']))<=.05,
                 channel_layout=len(m['individual_channel_noise_and_tones'])==(2 if r['kind']=='bed' else 1),
                 full_chain_envelope=r['kind']=='shot' or q.get('full_chain_loop_envelope_residual_p95_db',0)<=4,
                 static_comparison_valid=q.get('static_equal_loudness_gain_db') is not None)
        g['no_added_haze_or_lines']=not any('floor increased' in s or 'introduced' in s or 'haze increased' in s for s in q['faults'])
        q['gate_limits']={'decoded_peak_max_dbfs':-3,'out_of_band_above_1p3_lp_max_dbfs':-68,'out_of_band_relative_max_db':-34,
                          'loudness_target_lufs':r['target_lufs'],'loudness_tolerance_lu':3,'encoded_shot_guard_peak_max_dbfs':-75,
                          'grid_residues_max_count':3,'limiter_max_db':8,'phone_min_relative_db':-14,'bed_slow_envelope_max_db':8,
                          'loop_duration_tolerance_seconds':.05,'treatment_envelope_p95_max_db':2,'treatment_hf_envelope_p95_max_db':3,
                          'loop_full_chain_envelope_p95_max_db':4,'loop_spread_change_max_db':4}
        q['numeric_pass']=not q['faults']


def refresh_envelope_definition(report,rawdir,output):
    if report.get('envelope_definition_version')==2: return
    for q in report['sounds'].values():
        for c in q.get('selection_candidates',[]):
            if 'extended_metrics' in c and (rawdir/c['file']).exists():
                c['extended_metrics']['envelope']=envelope_stats(decode(rawdir/c['file']))
    for key,q in report['sounds'].items():
        if not q.get('mastered'): continue
        x=decode(output/'selected_raw'/(key+'.mp3'))
        r=q['recipe']
        if r['kind']!='bed': x=x.mean(axis=1)[:,None]
        if r['kind']!='shot': x=x[:int(r['seconds']*SR)]
        q['static_before']['envelope']=envelope_stats(x)
        q['static_after']['envelope']=envelope_stats(decode(output/'masters'/(key+'.ogg')))
    report['envelope_definition_version']=2


def refresh_tone_definition(report,rawdir,output):
    if report.get('tone_definition_version')==2: return
    def update(ext,x):
        tones=[]
        for ci,ch in enumerate(x.T):
            upper=[p for p in ext['steady_tones_by_channel'][min(ci,len(ext['steady_tones_by_channel'])-1)] if p['hz']>=800]
            tones.append(sorted(upper+low_tonal_peaks(ch),key=lambda p:p['hz']))
        ext['steady_tones_by_channel']=tones
        ext['steady_narrow_tones']=max(sum(p['persistence']>.7 and p['power_dbfs']>-70 for p in ts) for ts in tones)
        ext['steady_narrow_tones_over800']=max(sum(p['hz']>=800 and p['persistence']>.7 and p['power_dbfs']>-70 for p in ts) for ts in tones)
        ext['steady_tone_definition']='60Hz..11kHz, >8dB prominence, >70% persistence, >-70dBFS five-bin power; low source/body tones counted without automatic removal.'
    for key,q in report['sounds'].items():
        for c in q.get('selection_candidates',[]):
            if 'extended_metrics' in c and (rawdir/c['file']).exists(): update(c['extended_metrics'],decode(rawdir/c['file']))
        if not q.get('mastered'): continue
        x=decode(output/'selected_raw'/(key+'.mp3')); r=q['recipe']
        if r['kind']!='bed': x=x.mean(axis=1)[:,None]
        if r['kind']!='shot': x=x[:int(r['seconds']*SR)]
        update(q['static_before'],x)
        update(q['static_after'],decode(output/'masters'/(key+'.ogg')))
    report['tone_definition_version']=2


def validate_legacy(rawdir,output):
    output.mkdir(parents=True,exist_ok=True)
    for name in ('masters','selected_raw'): (output/name).mkdir(exist_ok=True)
    report={'sounds':{},'negative_controls':negative_controls(),'listening_verified':False}
    with tempfile.TemporaryDirectory(prefix='legacy-work-',dir=output) as temp:
        for key in LEGACY_RECIPES:
            _,q=process_legacy(key,rawdir,output,Path(temp))
            report['sounds'][key]=q
            json_write(output/'qc.json',report)
    old=json.loads((ROOT/'input/assets/qc.json').read_text())['sounds']
    comparison={'count':len(LEGACY_RECIPES),'same_takes':0,'within_tolerance':0,'keys':{},
                'tolerance_db_or_lu':.5,'legacy_new_gates_bypassed':True,
                'fan_exception':'bed_hall uses recorded fan-body replacement take10 (takes9–12 changed prompt, same recipe); no unrecorded exception to numerical matching. New phone/lapping gates are bypassed only in historical regression.',
                'listening_verified':False}
    def numeric_fields(value,prefix=''):
        result={}
        if isinstance(value,dict):
            for k,v in value.items(): result.update(numeric_fields(v,prefix+'.'+k if prefix else k))
        elif isinstance(value,list):
            for i,v in enumerate(value): result.update(numeric_fields(v,prefix+'.'+str(i)))
        elif isinstance(value,(int,float)) and not isinstance(value,bool): result[prefix]=value
        return result
    for key,q in report['sounds'].items():
        expect=old[key]; same=q['selected_take']==expect['selected_take']
        comparison['same_takes']+=int(same)
        a=numeric_fields(q['final_decoded_metrics']); b=numeric_fields(expect['final_decoded_metrics'])
        deltas={name:round(a[name]-v,6) for name,v in b.items() if name in a}
        # Compare every comparable db/flatness/time metric, not tone frequencies
        # that represent a changed candidate list. Peak/LU/band/noise/seam gates included.
        bounded={k:v for k,v in deltas.items() if ('db' in k or k.endswith('lufs')) and 'all_tonal_peaks' not in k}
        failed={k:v for k,v in bounded.items() if abs(v)>.5}
        differences=[]
        if not same: differences.append('Take differs: '+q['selected_take']+' vs '+expect['selected_take'])
        for k,v in failed.items(): differences.append(f'{k} delta {v:+.3f} dB/LU (current decoder/encoder arithmetic; see actual values)')
        ok=same and not failed
        comparison['within_tolerance']+=int(ok)
        comparison['keys'][key]={'selected_take':q['selected_take'],'expected_take':expect['selected_take'],'same_take':same,
                                 'within_tolerance':ok,'metric_deltas':deltas,'differences':differences,
                                 'lufs':q['final_decoded_metrics']['lufs'],'true_peak_dbfs':q['final_decoded_metrics']['true_peak_dbfs']}
    json_write(output/'comparison.json',comparison)
    print(json.dumps({k:comparison[k] for k in ('count','same_takes','within_tolerance')},indent=2),flush=True)
    return comparison


def main():
    parser=argparse.ArgumentParser(description='Sequential, conservative Poolrooms v3 mastering; no listening claims.')
    parser.add_argument('--sounds',type=Path,default=ROOT/'sounds_v3.json')
    parser.add_argument('--rawdir',type=Path,default=ROOT/'raw')
    parser.add_argument('--outdir',type=Path,default=ROOT/'out/pack')
    parser.add_argument('--keys',nargs='+')
    parser.add_argument('--overrides',type=Path,help='JSON {defaults:{kind:{...}}, keys:{key:{...}}}, or direct per-key map')
    parser.add_argument('--validate-legacy',action='store_true')
    parser.add_argument('--controls-only',action='store_true')
    parser.add_argument('--reports-only',action='store_true')
    parser.add_argument('--wait-generation',action='store_true',help='Poll both last_*.txt every 60 seconds, max75 minutes')
    args=parser.parse_args()
    rawdir=scoped(args.rawdir); output=scoped(args.outdir)
    if args.validate_legacy:
        validate_legacy(rawdir,output)
        return
    if args.controls_only:
        print(json.dumps(negative_controls(),indent=2)); return
    rows=manifest_rows(scoped(args.sounds))
    overrides=json.loads(scoped(args.overrides).read_text()) if args.overrides else {}
    recipes={r['key']:derive_recipe(r,overrides) for r in rows}
    keys=args.keys or list(recipes)
    if set(keys)-set(recipes): raise ValueError('Unknown keys: '+str(set(keys)-set(recipes)))
    output.mkdir(parents=True,exist_ok=True)
    for name in ('masters','selected_raw'): (output/name).mkdir(exist_ok=True)
    previous=output/'qc.json'
    report=json.loads(previous.read_text()) if previous.exists() else {'sounds':{}}
    report.update(schema=3,date=datetime.now(timezone.utc).isoformat(),sample_rate=SR,listening_verified=False,
                  processing_workers=1,negative_controls=negative_controls(),
                  scope='Numerical and visual QC only. No verified listening or subjective static absence.')
    if args.wait_generation and not args.reports_only:
        start=time.monotonic(); polls=0
        while True:
            flags={name:(ROOT/name).exists() for name in ('last_beds.txt','last_shots.txt')}
            print('Generation completion '+json.dumps(flags)+f'; elapsed {(time.monotonic()-start)/60:.1f}min',flush=True)
            if all(flags.values()) or time.monotonic()-start>=75*60: break
            # 60-second polling, synchronous single process; output is flushed.
            time.sleep(60); polls+=1
        report['generation_wait']={'flags':flags,'poll_interval_seconds':60,'polls':polls,
                                   'elapsed_seconds':round(time.monotonic()-start,1),'timeout_minutes':75,
                                   'timed_out':not all(flags.values())}
    if not args.reports_only:
        with tempfile.TemporaryDirectory(prefix='audio-work-',dir=output) as temp:
            for key in keys:
                row=next(r for r in rows if r['key']==key)
                report['sounds'][key]=process_v3(key,row,recipes[key],rawdir,output,Path(temp))
                report['sounds'][key]['section']=row.get('section')
                json_write(previous,report)
    for r in rows:
        if r['key'] not in report['sounds']:
            report['sounds'][r['key']]={'recipe':recipes[r['key']],'mastered':False,'numeric_pass':False,'listening_verified':False,
                                       'selected_take':None,'faults':['No take / key not processed'],'weak':[]}
    # Resolve provenance at completion because producers update logs atomically.
    json_write(output/'recipes.json',recipes)
    json_write(output/'provenance.json',generation_provenance(rows,report,rawdir))
    refresh_envelope_definition(report,rawdir,output)
    refresh_tone_definition(report,rawdir,output)
    refresh_numeric_evidence(report)
    create_visuals_and_distinctness(rows,report,output)
    write_report(rows,report,output)
    json_write(previous,report)
    summary={'tool':str(Path(__file__).relative_to(ROOT)),'mastered':sum(bool(q.get('mastered')) for q in report['sounds'].values()),
             'passed':sum(q.get('numeric_pass',False) for q in report['sounds'].values()),
             'failed':[{'key':r['key'],'why':'; '.join(report['sounds'][r['key']]['faults']),
                        'regenerate_prompt':report['sounds'][r['key']].get('regenerate_prompt',regenerate_prompt(r,[]))}
                       for r in rows if not report['sounds'][r['key']].get('numeric_pass')],
             'weak':[{'key':r['key'],'why':report['sounds'][r['key']].get('weak',[]),
                      'regenerate_prompt':report['sounds'][r['key']].get('regenerate_prompt',regenerate_prompt(r,[]))}
                     for r in rows if report['sounds'][r['key']].get('weak')],
             'beds_too_alike':report['distinctness'].get('too_alike',[]),
             'not_verified':['listening','audible AI-static absence','semantic content','phone playback','game/Roblox spatial mix'],
             'files':[str((output/x).relative_to(ROOT)) for x in ('masters','selected_raw','recipes.json','qc.json','provenance.json','distinctness.json')]+[str((output.parent/'REPORT.md').relative_to(ROOT))]+report['spectrogram_sheets']+report.get('gain_matched_diagnostic_sheets',[])}
    val=ROOT/'out/validation/comparison.json'
    summary['validated_against_20261009']=json.loads(val.read_text()) if val.exists() else {'performed':False}
    deltas=[q['quiet_floor_equal_loudness_change_db'] for q in report['sounds'].values() if q.get('mastered') and q.get('quiet_floor_equal_loudness_change_db') is not None]
    summary['static_summary']=f'Quiet 2.5–8kHz floor at matched integrated loudness: median change {float(np.median(deltas)):.1f}dB, range {min(deltas):.1f}..{max(deltas):.1f}dB; natural air/water protected from gates. Numeric QC does not establish audible static absence.' if deltas else 'No available takes mastered; static absence unverified.'
    json_write(output.parent/'summary.json',summary)
    print(json.dumps({k:summary[k] for k in ('mastered','passed','static_summary')},indent=2),flush=True)


if __name__=='__main__':
    main()
