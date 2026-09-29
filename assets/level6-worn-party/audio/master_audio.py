#!/usr/bin/env python3
"""Rebuild the five locally mastered Level 6 sounds from selected ElevenLabs takes."""

from __future__ import annotations

import array
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

RATE = 48000
CHANNELS = 2
ROOT = Path(__file__).resolve().parent
CANDIDATES = ROOT.parents[2] / "artifacts/level6-build-20260930/audio-candidates"

# Preserve the physical low/mid-frequency room tone; suppress broadband residue.
AMBIENCE_FILTER = "highpass=f=45,afftdn=nr=8:nf=-55:rf=-62:tn=1,lowpass=f=8500"
ARCADE_FILTER = (
    "[0:a]asplit=2[lo][hi];"
    "[lo]highpass=f=45,lowpass=f=600[bed];"
    "[hi]highpass=f=600,lowpass=f=6000,afftdn=nr=20:nf=-48:rf=-68:tn=1,"
    "agate=threshold=0.004:ratio=12:range=0.001:attack=4:release=160[events];"
    "[bed][events]amix=inputs=2:normalize=0[out]"
)
EVENT_FILTER = (
    "highpass=f=65,afftdn=nr=12:nf=-55:rf=-68:tn=1,lowpass=f=10000,"
    "agate=threshold=0.002:ratio=8:range=0.001:attack=3:release=100"
)
SOURCES = [
    ("party_hall_ambience", 4, True),
    ("budget_arcade_ambience", 2, True),
    ("maintenance_workshop_ambience", 3, True),
    ("arcade_credit_button", 2, False),
    ("breaker_switch", 3, False),
]


def run(args: list[str], data: bytes | None = None) -> bytes:
    result = subprocess.run(args, input=data, capture_output=True, check=True)
    return result.stdout


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(source: Path, filters: str, complex_filter: bool = False) -> array.array:
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-i", str(source)]
    cmd += ["-filter_complex", filters, "-map", "[out]"] if complex_filter else ["-af", filters]
    cmd += ["-f", "f32le", "-acodec", "pcm_f32le", "-ac", str(CHANNELS), "-ar", str(RATE), "-"]
    raw = run(cmd)
    samples = array.array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def rms(samples: array.array) -> float:
    return math.sqrt(sum(s * s for s in samples) / max(len(samples), 1))


def peak(samples: array.array) -> float:
    return max((abs(s) for s in samples), default=0)


def db(value: float) -> float:
    return round(20 * math.log10(max(value, 1e-12)), 2)


def circular_crossfade(samples: array.array, overlap_frames: int) -> array.array:
    frame_count = len(samples) // CHANNELS
    if frame_count <= overlap_frames * 2:
        raise ValueError("Loop source is too short for overlap")
    output = array.array("f", [0.0]) * ((frame_count - overlap_frames) * CHANNELS)
    tail_start = (frame_count - overlap_frames) * CHANNELS
    for frame in range(overlap_frames):
        incoming = (frame + 1) / (overlap_frames + 1)
        for channel in range(CHANNELS):
            index = frame * CHANNELS + channel
            output[index] = samples[tail_start + index] * (1 - incoming) + samples[index] * incoming
    output[overlap_frames * CHANNELS:] = samples[overlap_frames * CHANNELS:tail_start]
    return output


def endpoint_fades(samples: array.array, in_ms: int = 4, out_ms: int = 300) -> None:
    frames = len(samples) // CHANNELS
    fade_in = min(in_ms * RATE // 1000, frames // 2)
    fade_out = min(out_ms * RATE // 1000, frames // 2)
    for frame in range(fade_in):
        gain = frame / max(fade_in - 1, 1)
        for channel in range(CHANNELS):
            samples[frame * CHANNELS + channel] *= gain
    for frame in range(fade_out):
        gain = (fade_out - 1 - frame) / max(fade_out - 1, 1)
        index = (frames - fade_out + frame) * CHANNELS
        for channel in range(CHANNELS):
            samples[index + channel] *= gain


def write_wav(path: Path, samples: array.array) -> None:
    if sys.byteorder != "little":
        samples.byteswap()
    run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-nostdin", "-f", "f32le",
         "-ar", str(RATE), "-ac", str(CHANNELS), "-i", "-", "-c:a", "pcm_s24le", str(path)],
        samples.tobytes())
    if sys.byteorder != "little":
        samples.byteswap()


def main() -> None:
    raw_dir = ROOT / "raw"
    output_dir = ROOT / "mastered"
    raw_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for name, take, loop in SOURCES:
        candidate = CANDIDATES / f"{name}-take{take}.mp3"
        raw = raw_dir / f"{name}-elevenlabs-take{take}.mp3"
        # The selected untouched take is included in this package. The
        # exploratory candidates folder is optional after handoff.
        if not raw.is_file():
            raw.write_bytes(candidate.read_bytes())
        elif candidate.is_file() and sha(raw) != sha(candidate):
            raise RuntimeError(f"Existing raw master differs from selected candidate: {raw}")
        filters = ARCADE_FILTER if name == "budget_arcade_ambience" else (AMBIENCE_FILTER if loop else EVENT_FILTER)
        samples = decode(raw, filters, name == "budget_arcade_ambience")
        before_peak, before_rms = peak(samples), rms(samples)
        if loop:
            overlap_frames = RATE // 4  # 250 ms across original end/start.
            samples = circular_crossfade(samples, overlap_frames)
            desired = 10 ** (-36 / 20) / max(rms(samples), 1e-12)
            ceiling = 10 ** (-9 / 20) / max(peak(samples), 1e-12)
            gain = min(desired, ceiling)
        else:
            overlap_frames = 0
            endpoint_fades(samples)
            # Stereo-to-mono decoders can raise correlated events by ~3 dB.
            # Leave margin so both the PCM master and upload MP3 stay below -6 dBFS.
            gain = 10 ** (-10 / 20) / max(peak(samples), 1e-12)
        for index in range(len(samples)):
            samples[index] *= gain
        wav = output_dir / f"{name}.wav"
        mp3 = output_dir / f"{name}.mp3"
        write_wav(wav, samples)
        run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-nostdin", "-i", str(wav),
             "-c:a", "libmp3lame", "-b:a", "192k", "-ar", str(RATE), str(mp3)])
        records.append({
            "name": name,
            "selected_take": take,
            "loop": loop,
            "filters": filters,
            "overlap_ms": round(overlap_frames * 1000 / RATE),
            "fade_in_ms": 0 if loop else 4,
            "fade_out_ms": 0 if loop else 300,
            "pre_gain_peak_dbfs": db(before_peak),
            "pre_gain_rms_dbfs": db(before_rms),
            "gain_db": db(gain),
            "post_gain_peak_dbfs": db(peak(samples)),
            "post_gain_rms_dbfs": db(rms(samples)),
            "duration_seconds": round(len(samples) / (RATE * CHANNELS), 3),
            "raw": str(raw.relative_to(ROOT)),
            "raw_sha256": sha(raw),
            "wav": str(wav.relative_to(ROOT)),
            "wav_sha256": sha(wav),
            "mp3": str(mp3.relative_to(ROOT)),
            "mp3_sha256": sha(mp3),
        })
    (ROOT / "build-results.json").write_text(json.dumps(records, indent=2) + "\n")
    print(json.dumps([{key: record[key] for key in
                       ("name", "duration_seconds", "post_gain_peak_dbfs", "post_gain_rms_dbfs")}
                      for record in records], indent=2))


if __name__ == "__main__":
    main()
