"""Measure, clean and level the sounds of the creature behind the lobby's fence (raw/ is what ElevenLabs gave).

    <a python with numpy> clean_reach.py measure     # what is in each raw file, band by band
    <a python with numpy> clean_reach.py             # write the cleaned files next to this script, and levels.json
    (Blender's python has numpy: /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13)

What "the AI static" is in these files, and what takes it out (the owner has heard it in raw generator output twice):

  1. A HISS that is there whether the creature makes a sound or not. It is measured where the file is quietest (the
     generator's own floor: the 12% of frames with the least energy) and every bin is gated against that print: a
     bin that does not stand clear of the print is turned down, one that does is kept whole. This is what a fixed
     noise print can do, and a breath or a growl with silence round it needs exactly that.
  2. A HAZE between the partials of a voiced sound (growls, groans) that rises and falls with it, which no fixed
     print can touch. `clean_screams.clean` gates each bin against the local floor of its own frame.
  3. A BAND of hiss above where the sound itself ends. A steep low-pass at a cutoff chosen per file from the
     measurement: low for the breath and the growls, higher for the slaps and nails, whose click is real treble.

Then mono (they are 3D emitters), a guard fade at both ends, a loudness target and a limiter (a gain that ducks
round a peak, not a clipper: clipping a knuckle crack puts back the very treble the low-pass took). Loops are written
as OGG, which loops without the gap an MP3 leaves. A loop the generator already made seamless is ROLLED so that its
ends lie in a silence and joined with a 30 ms fade; one it did not is cross-faded tail into head over 0.6 s.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'level5-void-20261005' / 'audio-engineering'))
import clean_screams as cs                                    # noqa: E402

RAW = HERE / 'raw'
CEILING_DB = -1.5
BANDS = [(0, 150), (150, 500), (500, 1000), (1000, 2000), (2000, 4000), (4000, 6000), (6000, 8000), (8000, 12000), (12000, 16000)]

# jobs.json: name -> {take, lufs, lowpass (Hz), haze (dB, 0 = none), gate (dB, 0 = none), and optionally loop,
# steady (level a loop), gaps (cut the silences out of a loop), shelf ([Hz, dB]: lift everything above Hz),
# roll (s: start a seamless loop this far in), cross (s: the loop's join, 0.6 unless given), pad (s of silence put
# at a loop's end), end (s: a one-shot stops here)}.
# Filled in from `measure` and from each take's spectrogram; why each take was used or not is in README.md.
JOBS = {}
JOBS_FILE = HERE / 'jobs.json'
if JOBS_FILE.exists():
    JOBS = json.loads(JOBS_FILE.read_text())


def band_db(mag2, freq, lo, hi):
    """Mean power of the bins between lo and hi, in dB (per frame when mag2 is frames x bins)."""
    sel = (freq >= lo) & (freq < hi)
    return 10 * np.log10(np.maximum(mag2[..., sel].mean(axis=-1), 1e-20))


def measure():
    freq = np.fft.rfftfreq(cs.N, 1 / cs.SR)
    print(f'{"file":26s} {"sec":>5s} {"LUFS":>6s} {"peak":>6s} {"L/R":>5s} | loud frames, dB per band' + ' ' * 28 + '| quiet frames (the floor)')
    print(' ' * 53 + '  '.join(f'{lo // 1000 if lo >= 1000 else lo}{"k" if lo >= 1000 else ""}'.rjust(4) for lo, _ in BANDS))
    for path in sorted(RAW.glob('*.mp3')):
        stereo = cs.load(path)
        mono = stereo.mean(axis=1)
        loud, peak = cs.lufs(path)
        side = stereo[:, 0] - stereo[:, 1]
        width = 10 * np.log10((side ** 2).mean() / max((mono ** 2).mean(), 1e-20) + 1e-20)
        spec, _ = cs.stft(mono)
        power = np.abs(spec) ** 2
        energy = power.sum(axis=1)
        order = np.argsort(energy)
        quiet, hot = order[: max(4, len(order) // 8)], order[-max(4, len(order) // 4):]
        top = ' '.join(f'{band_db(power[hot].mean(axis=0), freq, lo, hi):5.0f}' for lo, hi in BANDS)
        low = ' '.join(f'{band_db(power[quiet].mean(axis=0), freq, lo, hi):5.0f}' for lo, hi in BANDS)
        print(f'{path.name:26s} {len(mono) / cs.SR:5.2f} {loud:6.1f} {peak:6.1f} {width:5.0f} | {top} | {low}')


def print_gate(x, depth_db):
    """Gate every bin against the file's own floor: the mean spectrum of its quietest frames (the generator's hiss
    with nothing of the creature in it). A bin less than 6 dB over the print goes down by `depth_db`, one more than
    15 dB over it stays whole, a smooth step between, smoothed over time and frequency so nothing chirps."""
    if depth_db >= 0:
        return x
    spec, length = cs.stft(x)
    mag = np.abs(spec)
    energy = (mag ** 2).sum(axis=1)
    quiet = np.argsort(energy)[: max(6, len(energy) // 8)]
    floor = cs.smooth(mag[quiet].mean(axis=0)[None, :], 9, 1)[0]
    over = 20 * np.log10(np.maximum(cs.smooth(mag, 5, 0), 1e-12) / np.maximum(floor[None, :], 1e-12))
    keep = np.clip((over - 6.0) / 9.0, 0.0, 1.0)
    keep = keep * keep * (3 - 2 * keep)
    least = 10 ** (depth_db / 20)
    gain = cs.smooth(cs.smooth(least + (1 - least) * keep, 5, 0), 3, 1)
    return cs.istft(spec * gain, length)


def close_gaps(x, floor_db=-34.0, least=0.12, fade=0.045):
    """Cut the silences out of a loop that has to be continuous: the generator's "dragged very fast" came as four
    bursts with a quarter second of nothing between them. A stretch whose 30 ms level stays `floor_db` under the
    loud part's for at least `least` seconds is removed and the two sides are cross-faded."""
    n = int(0.03 * cs.SR)
    level = np.sqrt(np.convolve(x ** 2, np.ones(n) / n, mode='same'))
    loud = np.percentile(level, 80)
    silent = level < loud * 10 ** (floor_db / 20)
    keep, start, i = [], 0, 0
    while i < len(x):
        if silent[i]:
            j = i
            while j < len(x) and silent[j]:
                j += 1
            if (j - i) / cs.SR >= least:
                keep.append((start, i))
                start = j
            i = j
        else:
            i += 1
    keep.append((start, len(x)))
    keep = [(a, b) for a, b in keep if b - a > int(0.2 * cs.SR)]
    f = int(fade * cs.SR)
    out = x[keep[0][0]:keep[0][1]].copy()
    for a, b in keep[1:]:
        piece = x[a:b].copy()
        ramp = np.sin(np.linspace(0, np.pi / 2, f)) ** 2
        out[-f:] = out[-f:] * (1 - ramp) + piece[:f] * ramp
        out = np.concatenate([out, piece[f:]])
    return out, len(keep) - 1


def shelf(x, corner, gain_db):
    """Lift everything above `corner` by `gain_db` (a smooth step an octave wide): a breath that came out almost all
    under 150 Hz is a rumble on headphones and nothing at all on a phone's speaker."""
    spec, length = cs.stft(x)
    freq = np.fft.rfftfreq(cs.N, 1 / cs.SR)
    step = np.clip(np.log2(np.maximum(freq, 1.0) / corner) + 0.5, 0.0, 1.0)
    return cs.istft(spec * (10 ** (gain_db * step * step * (3 - 2 * step) / 20))[None, :], length)


def steady(x, window=0.8, most_db=12.0):
    """Hold a loop at one level (clean_finale's): the gain follows the inverse of a slow envelope, gently."""
    n = int(window * cs.SR)
    power = np.concatenate([x[-n:], x, x[:n]]) ** 2
    kernel = np.hanning(n * 2 + 1)
    env = np.sqrt(np.convolve(power, kernel / kernel.sum(), mode='same')[n:-n])
    gain = (np.median(env) / np.maximum(env, 1e-6)) ** 0.6
    return x * np.clip(gain, 10 ** (-6 / 20), 10 ** (most_db / 20))


def limit(x, ceiling_db=CEILING_DB, block=32, reach=6):
    """Keep every sample under the ceiling by turning the gain down ROUND a peak (about 4 ms either side, eased),
    which leaves the waveform's shape alone."""
    ceiling = 10 ** (ceiling_db / 20)
    if np.abs(x).max() <= ceiling:
        return x
    pad = (-len(x)) % block
    peaks = np.abs(np.concatenate([x, np.zeros(pad)])).reshape(-1, block).max(axis=1)
    wide = np.pad(peaks, reach, mode='edge')
    held = np.max([wide[i:i + len(peaks)] for i in range(2 * reach + 1)], axis=0)       # the largest peak nearby
    gain = np.minimum(1.0, ceiling / np.maximum(held, 1e-9))
    kernel = np.hanning(2 * reach + 1)
    eased = np.convolve(np.pad(gain, reach, mode='edge'), kernel / kernel.sum(), mode='valid')
    eased = np.minimum(eased, gain)                                                     # easing may never let more through
    out = x * np.interp(np.arange(len(x)), np.arange(len(peaks)) * block + block / 2, eased)
    return np.clip(out, -ceiling, ceiling)


def main():
    if not JOBS:
        raise SystemExit('jobs.json is missing: run `measure`, choose the takes and their numbers first')
    work = Path(tempfile.mkdtemp(prefix='reach-'))
    freq = np.fft.rfftfreq(cs.N, 1 / cs.SR)
    report = {}
    for name, job in JOBS.items():
        take, target, cutoff, haze_db, gate_db = job['take'], job['lufs'], job['lowpass'], job.get('haze', 0), job.get('gate', 0)
        loop = job.get('loop', False)
        source = RAW / take
        mono = cs.load(source).mean(axis=1)
        if job.get('roll'):
            mono = np.roll(mono, -int(job['roll'] * cs.SR))
        if job.get('end'):
            mono = mono[: int(job['end'] * cs.SR)]
        before, _ = cs.lufs(source)
        out = print_gate(mono, gate_db)
        out, _ = cs.clean(out, cutoff, haze_db)
        if job.get('shelf'):
            out = shelf(out, *job['shelf'])
        cut = 0
        if job.get('gaps'):
            out, cut = close_gaps(out)
        if loop:
            if job.get('steady'):
                out = steady(out)
            if job.get('pad'):
                out = np.concatenate([out, np.zeros(int(job['pad'] * cs.SR))])
            n = int(job.get('cross', 0.6) * cs.SR)                 # tail fades out over the head fading in
            fade = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
            out = np.concatenate([out[:n] * fade + out[-n:] * (1 - fade), out[n:-n]])
        else:
            guard = int(0.008 * cs.SR)
            out[:guard] *= np.linspace(0, 1, guard)
            tail = int(0.06 * cs.SR)
            out[-tail:] *= np.linspace(1, 0, tail)
        wav = work / f'{name}.wav'

        def write(signal):
            wav.unlink(missing_ok=True)                            # ffmpeg may not replace a file in place here
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(cs.SR), '-ac', '1', '-i', '-',
                            '-c:a', 'pcm_s24le', str(wav)], input=np.clip(signal, -1, 1).astype('<f4').tobytes(), check=True)
        write(out)
        now, _ = cs.lufs(wav)
        out = out * 10 ** ((target - now) / 20)
        out = limit(out)                                          # one sample of an impact may not set the rest
        write(out)
        final = HERE / f"{name}.{'ogg' if loop else 'mp3'}"
        final.unlink(missing_ok=True)
        codec = ['-c:a', 'libvorbis', '-q:a', '6'] if loop else ['-c:a', 'libmp3lame', '-b:a', '192k']
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), *codec, '-ac', '1', '-ar', str(cs.SR), str(final)], check=True)
        after, after_peak = cs.lufs(final)
        # what the cleaning took: energy above the cutoff, and in the quietest frames, before and after
        def floor_of(signal):
            if loop:                                               # as it is played: round and round, the join inside
                signal = np.roll(signal, len(signal) // 2)         # (a loop's cut ends read as a click that is not there)
            power = np.abs(cs.stft(signal)[0]) ** 2
            power = power[6:-6] if loop else power
            quiet = np.argsort(power.sum(axis=1))[: max(6, len(power) // 8)]
            return band_db(power[quiet].mean(axis=0), freq, 2000, 16000), band_db(power.mean(axis=0), freq, cutoff * 1.3, 16000)
        # compared at the SAME loudness (the cleaned file's), or a quiet take made louder would read as noisier
        quiet_before, hiss_before = floor_of(mono * 10 ** ((after - before) / 20))
        quiet_after, hiss_after = floor_of(out)
        report[name] = {'take': take, 'before_lufs': before, 'after_lufs': after, 'after_peak': after_peak,
                        'seconds': round(len(out) / cs.SR, 2), 'file': final.name, 'lowpass_hz': cutoff, 'haze_cut_db': haze_db,
                        'print_gate_db': gate_db, 'silences_cut': cut, 'floor_2k_16k_db': [round(float(quiet_before), 1), round(float(quiet_after), 1)],
                        'above_cutoff_db': [round(float(hiss_before), 1), round(float(hiss_after), 1)]}
        print(f'{name:22s} {before:6.1f} -> {after:6.1f} LUFS, peak {after_peak:5.1f}, {len(out) / cs.SR:5.2f} s | quiet floor 2-16k '
              f'{quiet_before:6.1f} -> {quiet_after:6.1f} dB | above the cutoff {hiss_before:6.1f} -> {hiss_after:6.1f} dB  ({final.name})')
    levels = HERE / 'levels.json'
    levels.unlink(missing_ok=True)
    levels.write_text(json.dumps(report, indent=1) + '\n')


if __name__ == '__main__':
    measure() if sys.argv[1:] == ['measure'] else main()
