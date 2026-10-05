"""Clean and level the six sounds of the Level 5 finale (raw/ is what ElevenLabs gave).

They are noise by nature (stone, impact), so there is no voice to protect and nothing between harmonics to gate:
each is summed to mono (they are 3D emitters), loses the generator's hiss band above its cutoff, and is set to a
loudness. The grind is a LOOP: its tail is cross-faded into its head and it is written as OGG, which Roblox loops
without the gap an MP3's padding leaves.

    <a python with numpy> clean_finale.py        (Blender's: .../Blender.app/Contents/Resources/5.2/python/bin/python3.13)
"""
import subprocess, sys, json, tempfile
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'level5-void-20261005' / 'audio-engineering'))
import clean_screams as cs

# name -> (target LUFS, low-pass cutoff Hz, loop)
# (raw/l5_body_hit_2 is not used: its scrape came out louder than its thud and a second and a half late)
JOBS = {
    'l5_body_hit_1': (-17.0, 6000, False),
    'l5_crusher_slam': (-15.0, 7000, False),
    'l5_crusher_shut': (-15.0, 7000, False),
    'l5_crusher_groan': (-18.0, 6000, False),
    'l5_crusher_grind': (-20.0, 5500, True),
}
CEILING_DB = -1.5

def steady(x, window=0.6, most_db=20.0):
    """Hold a loop at one level: the generator's grind came in surges with two seconds of near silence between
    them, and walls that move at one speed do not pause. The gain follows the inverse of a slow envelope."""
    n = int(window * cs.SR)
    power = np.concatenate([x[-n:], x, x[:n]]) ** 2                # the loop wraps
    kernel = np.hanning(n * 2 + 1)
    env = np.sqrt(np.convolve(power, kernel / kernel.sum(), mode='same')[n:-n])
    gain = (np.median(env) / np.maximum(env, 1e-6)) ** 0.9
    return x * np.clip(gain, 10 ** (-6 / 20), 10 ** (most_db / 20))


def main():
    work = Path(tempfile.mkdtemp(prefix='l5finale-'))
    report = {}
    for name, (target, cutoff, loop) in JOBS.items():
        source = HERE / 'raw' / f'{name}.mp3'
        mono = cs.load(source).mean(axis=1)
        before, before_peak = cs.lufs(source)
        out, _ = cs.clean(mono, cutoff, 0)
        if loop:
            out = steady(out)
            # the last half second fades out over the first half second fading in: the join is the middle of both
            n = int(0.5 * cs.SR)
            fade = np.sin(np.linspace(0, np.pi / 2, n)) ** 2
            head = out[:n] * fade + out[-n:] * (1 - fade)
            out = np.concatenate([head, out[n:-n]])
        else:
            guard = int(0.008 * cs.SR)
            out[:guard] *= np.linspace(0, 1, guard)
            tail = int(0.05 * cs.SR)
            out[-tail:] *= np.linspace(1, 0, tail)
        wav = work / f'{name}.wav'
        def write(signal):
            wav.unlink(missing_ok=True)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(cs.SR), '-ac', '1', '-i', '-',
                            '-c:a', 'pcm_s24le', str(wav)], input=np.clip(signal, -1, 1).astype('<f4').tobytes(), check=True)
        write(out)
        now, _ = cs.lufs(wav)
        out *= 10 ** ((target - now) / 20)
        peak = 20 * np.log10(np.abs(out).max() + 1e-12)
        if peak > CEILING_DB:                                       # an impact's one sample may not set the level of the rest
            limit = 10 ** (CEILING_DB / 20)
            knee = limit * 0.6
            big = np.abs(out) > knee
            out[big] = np.sign(out[big]) * (knee + (limit - knee) * np.tanh((np.abs(out[big]) - knee) / (limit - knee)))
        write(out)
        final = HERE / f"{name}.{'ogg' if loop else 'mp3'}"
        final.unlink(missing_ok=True)
        codec = ['-c:a', 'libvorbis', '-q:a', '6'] if loop else ['-c:a', 'libmp3lame', '-b:a', '192k']
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), *codec, '-ac', '1', '-ar', str(cs.SR), str(final)], check=True)
        after, after_peak = cs.lufs(final)
        report[name] = {'before_lufs': before, 'after_lufs': after, 'after_peak': after_peak, 'seconds': round(len(out) / cs.SR, 2), 'file': final.name}
        print(f'{name}: {before:6.1f} LUFS -> {after:6.1f} LUFS, peak {after_peak:5.1f} dBFS, {len(out) / cs.SR:.2f} s  ({final.name})')
    levels = HERE / 'levels.json'
    levels.unlink(missing_ok=True)
    levels.write_text(json.dumps(report, indent=1) + '\n')

if __name__ == '__main__':
    main()
