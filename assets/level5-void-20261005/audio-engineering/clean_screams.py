"""Take the generator's static out of the Level 5 fall sounds and set their level.

The six ElevenLabs screams (and the level's older fall rush) carry two kinds of noise that a real recording of a
voice does not: a hiss band from about 5 kHz up to the MP3's 16 kHz edge, where the voice has nothing, and a haze
BETWEEN the voice's harmonics that rises and falls with the voice. A fixed noise print cannot remove the second
kind (there is no noise when the voice is silent), so this works per frame:

  1. mono (the sounds are 3D emitters; the two channels differ only in noise),
  2. per STFT frame, the floor under the harmonics is the 25th percentile of the magnitudes in a 540 Hz window;
     a bin is kept in full when it stands well clear of that floor and turned down by the job's depth when it
     does not (a smooth step between, smoothed again over time and frequency so nothing chirps),
  3. a steep low-pass at the job's cutoff (nothing of the voice is up there, only hiss),
  4. the original fades are kept, and the result is set to a target loudness and a peak ceiling.

Run with any Python that has numpy (Blender's):  python3.13 clean_screams.py
It needs ffmpeg on PATH. Output: <name>_clean.mp3 next to each source, and levels.json here. The ids of the
uploaded results go into tools/level5_void/sound_ids.json under the ORIGINAL keys."""
import subprocess, sys, json, tempfile
from pathlib import Path
import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent.parent
SR, N, HOP = 44100, 2048, 256
# name -> (source, target LUFS, low-pass cutoff Hz, deepest cut of the floor in dB)
JOBS = {
    'l5_fall_scream_1': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_1.mp3', -18.0, 4800, -12),
    'l5_fall_scream_2': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_2.mp3', -18.0, 4800, -12),
    'l5_fall_scream_3': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_3.mp3', -18.0, 4800, -12),
    'l5_fall_scream_4': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_4.mp3', -18.0, 4800, -12),
    'l5_fall_scream_5': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_5.mp3', -18.0, 4800, -12),
    'l5_fall_scream_6': (ASSETS / 'level5-void-20261005' / 'l5_fall_scream_6.mp3', -18.0, 4800, -12),
    # the level's own fall rush is noise by nature: only the hiss band goes, and its loudness stays where it was
    'l5_player_fall': (ASSETS / 'level5-void-20261004' / 'l5_player_fall.mp3', None, 4800, 0),
}
PEAK_CEILING_DB = -3.0
GATE_DB, KEEP_DB, GLIDE_DB = 9.0, 17.0, 4.0                     # over the local floor (its 25th percentile)

def load(path):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)

def lufs(path):
    text = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(path), '-af', 'ebur128=peak=true:dualmono=true', '-f', 'null', '-'],
                          capture_output=True, text=True).stderr
    tail = text[text.rfind('Summary:'):]
    loud = float(tail.split('I:')[1].split('LUFS')[0])
    peak = float(tail.split('Peak:')[1].split('dBFS')[0])
    return loud, peak

def stft(x):
    window = np.hanning(N + 1)[:-1]
    padded = np.concatenate([np.zeros(N), x, np.zeros(N)])
    frames = 1 + (len(padded) - N) // HOP
    index = np.arange(N)[None, :] + HOP * np.arange(frames)[:, None]
    return np.fft.rfft(padded[index] * window, axis=1), len(padded)

def istft(spec, length):
    window = np.hanning(N + 1)[:-1]
    out, norm = np.zeros(length), np.zeros(length)
    frames = np.fft.irfft(spec, n=N, axis=1) * window
    for i, frame in enumerate(frames):
        out[i * HOP:i * HOP + N] += frame
        norm[i * HOP:i * HOP + N] += window ** 2
    return (out / np.maximum(norm, 1e-9))[N:length - N]

def smooth(a, size, axis):
    if size <= 1: return a
    kernel = np.hanning(size + 2)[1:-1]
    kernel /= kernel.sum()
    return np.apply_along_axis(lambda v: np.convolve(np.pad(v, size // 2, mode='edge'), kernel, mode='valid'), axis, a)

def clean(x, cutoff, floor_db):
    spec, length = stft(x)
    mag = np.abs(spec)
    freq = np.fft.rfftfreq(N, 1 / SR)
    gain = np.ones_like(mag)
    if floor_db < 0:
        # a partial of the voice holds still for longer than a grain of noise does: judge on a 40 ms average
        steady = smooth(mag, 7, 0)
        width = 25                                                  # bins: 540 Hz, wider than one harmonic's lobe
        padded = np.pad(steady, ((0, 0), (width // 2, width // 2)), mode='reflect')
        floor = np.percentile(sliding_window_view(padded, width, axis=1), 25, axis=2)
        floor = smooth(smooth(floor, 9, 0), 9, 1)                   # the floor is a smooth surface
        over = 20 * np.log10(np.maximum(steady, 1e-12) / np.maximum(floor, 1e-12))
        # kept in full from KEEP_DB over the floor, at the limit from GATE_DB down, a smooth step between: noise
        # reaches KEEP_DB about once in ten thousand bins, so nothing is left twinkling in the gaps
        keep = np.clip((over - GATE_DB) / (KEEP_DB - GATE_DB), 0.0, 1.0)
        # a partial that is sliding fast is smeared by that average: the frame itself may vouch for it too, but
        # it has to stand GLIDE_DB higher, which noise never does
        now = 20 * np.log10(np.maximum(mag, 1e-12) / np.maximum(floor, 1e-12))
        keep = np.maximum(keep, np.clip((now - GATE_DB - GLIDE_DB) / (KEEP_DB - GATE_DB), 0.0, 1.0))
        keep = keep * keep * (3 - 2 * keep)
        # the cut is shallow under 700 Hz (the body of the voice, few bins per harmonic) and full from 2 kHz
        depth = np.interp(freq, [0, 700, 2000, 22050], [floor_db * 0.35, floor_db * 0.6, floor_db, floor_db])
        least = 10 ** (depth / 20)
        gain = least[None, :] + (1 - least[None, :]) * keep
        gain = smooth(smooth(gain, 3, 1), 3, 0)
    # low-pass: flat to 0.85 x cutoff, -3 dB at the cutoff, -23 dB a quarter above it, -50 dB at 1.6 x
    ratio = np.maximum(freq, 1.0) / cutoff
    lowpass = 1.0 / np.sqrt(1.0 + ratio ** 24)                      # 12th-order Butterworth magnitude, zero phase
    highpass = 1.0 / np.sqrt(1.0 + (70.0 / np.maximum(freq, 1.0)) ** 8)
    return istft(spec * gain * (lowpass * highpass)[None, :], length), gain

def main():
    work = Path(tempfile.mkdtemp(prefix='l5scream-'))
    report = {}
    for name, (source, target, cutoff, floor_db) in JOBS.items():
        stereo = load(source)
        mono = stereo.mean(axis=1)
        before_lufs, before_peak = lufs(source)
        out, _ = clean(mono, cutoff, floor_db)
        # the generator's clips start and stop on a fade already; a 10 ms guard at each end rules out a click
        guard = int(0.010 * SR)
        out[:guard] *= np.linspace(0, 1, guard)
        out[-guard:] *= np.linspace(1, 0, guard)
        wav = work / f'{name}_clean.wav'
        def write(signal):
            pcm = np.clip(signal, -1, 1).astype('<f4').tobytes()
            wav.unlink(missing_ok=True)                             # ffmpeg may not replace a file in place here
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'f32le', '-ar', str(SR), '-ac', '1', '-i', '-',
                            '-c:a', 'pcm_s24le', str(wav)], input=pcm, check=True)
        write(out)
        now, _ = lufs(wav)
        want = before_lufs if target is None else target
        out *= 10 ** ((want - now) / 20)
        peak = 20 * np.log10(np.abs(out).max() + 1e-12)
        if peak > PEAK_CEILING_DB:                                  # a soft knee over the ceiling, not a hard clip
            limit = 10 ** (PEAK_CEILING_DB / 20)
            knee = limit * 0.7
            big = np.abs(out) > knee
            out[big] = np.sign(out[big]) * (knee + (limit - knee) * np.tanh((np.abs(out[big]) - knee) / (limit - knee)))
        write(out)
        mp3 = source.with_name(f'{name}_clean.mp3')
        mp3.unlink(missing_ok=True)
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(wav), '-c:a', 'libmp3lame', '-b:a', '192k', '-ac', '1',
                        '-ar', str(SR), str(mp3)], check=True)
        after_lufs, after_peak = lufs(mp3)
        report[name] = {'before_lufs': before_lufs, 'before_peak': before_peak, 'after_lufs': after_lufs,
                        'after_peak': after_peak, 'seconds': round(len(out) / SR, 2)}
        print(f'{name}: {before_lufs:6.1f} LUFS / {before_peak:5.1f} dBFS  ->  {after_lufs:6.1f} LUFS / {after_peak:5.1f} dBFS')
    levels = HERE / 'levels.json'
    levels.unlink(missing_ok=True)
    levels.write_text(json.dumps(report, indent=1) + '\n')

if __name__ == '__main__':
    main()
