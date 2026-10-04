"""The Counter's party clips (2026-10-04): toprock, windmill, headspin, a freeze and a finale, for the Level 6
easter egg. Written straight into ReplicatedStorage.Level6Counter.Clips in the format the Level 6 Playground
Client already plays (one quaternion per bone per frame x 10000, optional `hips` translation in studs x 1000).

    python3 tools/level6_entity/build_dance.py            # writes export/dance_clips.json and installs it in Studio

The rig is a T-pose with identity bone frames, so a bone's Transform is an absolute rotation in its parent's
frame, in model axes: X across (the Left limbs are at -X), Y up, the face toward -Z. Read off the recorded clips:
an arm hangs with +Z (left) / -Z (right), a leg swings forward with +X, a knee bends with -X, the spine leans
forward with -X, a left forearm bends forward with -Y. The tempo is the party track's, 142 bpm.
"""
import json, math, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FPS, BPM = 30, 142.0
BEAT = 60.0 / BPM * FPS            # frames per beat
BONES = ['Hips', 'Spine02', 'Spine01', 'Spine', 'neck', 'Head', 'LeftShoulder', 'LeftArm', 'LeftForeArm', 'LeftHand',
         'RightShoulder', 'RightArm', 'RightForeArm', 'RightHand', 'LeftUpLeg', 'LeftLeg', 'LeftFoot', 'LeftToeBase',
         'RightUpLeg', 'RightLeg', 'RightFoot', 'RightToeBase']


def R(axis, degrees):
    h = math.radians(degrees) / 2
    s = math.sin(h)
    return (s if axis == 'x' else 0.0, s if axis == 'y' else 0.0, s if axis == 'z' else 0.0, math.cos(h))


def mul(a, b):
    """a after b (both in the parent's frame)."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def chain(*parts):
    q = (0.0, 0.0, 0.0, 1.0)
    for part in reversed(parts):          # chain(a, b, c) = a after b after c
        q = mul(part, q)
    return q


def standing():
    return {'LeftArm': R('z', 74), 'RightArm': R('z', -74), 'LeftForeArm': R('y', -14), 'RightForeArm': R('y', 14)}


def clip(beats, frame):
    frames = int(round(beats * BEAT)) + 1
    tracks = {name: [] for name in BONES}
    hips = []
    last = None
    for f in range(frames):
        b = f / BEAT                                                   # time in beats
        pose, lift = frame(b, f / (frames - 1))
        full = standing()
        full.update(pose)
        for name in BONES:
            q = full.get(name, (0.0, 0.0, 0.0, 1.0))
            n = math.sqrt(sum(v * v for v in q)) or 1.0
            q = tuple(v / n for v in q)
            prev = tracks[name][-4:] if tracks[name] else None
            if prev and sum(p * v for p, v in zip(prev, q)) < 0:       # keep to one hemisphere: the client lerps
                q = tuple(-v for v in q)
            tracks[name].extend(q)
        hips.extend(lift)
    return {'frames': frames, 'fps': FPS, 'loop': True,
            'bones': {name: [int(round(v * 10000)) for v in q] for name, q in tracks.items()},
            'hips': [int(round(v * 1000)) for v in hips]}


def wave(b, per=1.0, phase=0.0):
    return math.sin(2 * math.pi * (b / per + phase))


def toprock(b, _):
    """Standing footwork: a step on every beat, the arms crossing, the whole body twisting on the two-beat."""
    left, right = max(0.0, wave(b, 2)), max(0.0, wave(b, 2, 0.5))
    return {
        'Hips': chain(R('y', 20 * wave(b, 2)), R('x', -6)),
        'Spine01': R('z', 7 * wave(b, 2)), 'Spine': chain(R('y', -16 * wave(b, 2)), R('x', -8)),
        'Head': R('x', -9 * wave(b, 1)), 'neck': R('y', 10 * wave(b, 2)),
        'LeftUpLeg': chain(R('x', 46 * left), R('z', -8)), 'LeftLeg': R('x', -70 * left),
        'RightUpLeg': chain(R('x', 46 * right), R('z', 8)), 'RightLeg': R('x', -70 * right),
        'LeftArm': chain(R('x', 55 * wave(b, 2)), R('z', 62)), 'LeftForeArm': R('y', -80),
        'RightArm': chain(R('x', -55 * wave(b, 2)), R('z', -62)), 'RightForeArm': R('y', 80),
    }, (0.0, -0.3 * abs(wave(b, 2)), 0.0)


def windmill(b, u):
    """On the back and shoulders, turning, the legs in a wide V that scissors as it goes round."""
    spin = 360.0 * 3 * u
    return {
        'Hips': chain(R('y', spin), R('z', 22 * wave(b, 1)), R('x', -84)),
        'Spine': R('x', 16), 'neck': R('x', 20), 'Head': R('x', 14),
        'LeftUpLeg': chain(R('x', 62 + 34 * wave(b, 1)), R('z', -56)), 'LeftLeg': R('x', -8),
        'RightUpLeg': chain(R('x', 62 - 34 * wave(b, 1)), R('z', 56)), 'RightLeg': R('x', -8),
        'LeftArm': chain(R('x', -30), R('z', 20)), 'LeftForeArm': R('y', -50),
        'RightArm': chain(R('x', -30), R('z', -20)), 'RightForeArm': R('y', 50),
    }, (0.0, -3.25 + 0.12 * abs(wave(b, 1)), 0.0)


def headspin(b, u):
    """Upside down on its head, turning fast, the legs split and the knees pumping."""
    spin = 360.0 * 5 * u
    pump = 0.5 + 0.5 * wave(b, 1)
    return {
        'Hips': chain(R('y', spin), R('z', 5 * wave(b, 2)), R('x', 180)),
        'Head': R('x', 6), 'Spine': R('x', -4),
        'LeftUpLeg': chain(R('x', 24 * wave(b, 2)), R('z', -48)), 'LeftLeg': R('x', -75 * pump),
        'RightUpLeg': chain(R('x', -24 * wave(b, 2)), R('z', 48)), 'RightLeg': R('x', -75 * (1 - pump)),
        'LeftArm': R('z', -58), 'LeftForeArm': R('y', -40), 'RightArm': R('z', 58), 'RightForeArm': R('y', 40),
    }, (0.0, -0.95, 0.0)


def freeze(b, _):
    """A one-handed freeze: upside down and tilted, one leg tucked, the other kicked out, pulsing on the beat."""
    pulse = wave(b, 1)
    return {
        'Hips': chain(R('y', 25 * wave(b, 8)), R('z', 24 + 3 * pulse), R('x', 172)),
        'Spine': R('z', -14), 'Head': R('z', -12),
        'LeftUpLeg': chain(R('x', 78), R('z', -18)), 'LeftLeg': R('x', -112),
        'RightUpLeg': chain(R('x', -18 + 6 * pulse), R('z', 44)), 'RightLeg': R('x', -14),
        'RightArm': R('z', 80), 'RightForeArm': R('y', 8),                      # the arm it stands on
        'LeftArm': chain(R('x', 30), R('z', 30)), 'LeftForeArm': R('y', -105),  # the other hand on its hip
    }, (0.0, -0.8 + 0.07 * pulse, 0.0)


def finale(b, u):
    """Back on its feet: a full turn every four beats, both arms up and waving, a jump on every beat."""
    jump = abs(wave(b, 2))
    return {
        'Hips': chain(R('y', 360.0 * 2 * u), R('x', -4)),
        'Spine': chain(R('z', 10 * wave(b, 2)), R('x', 6)), 'Head': R('x', 14),
        'LeftArm': chain(R('z', -66 + 18 * wave(b, 1)), R('x', 0)), 'LeftForeArm': R('y', -18),
        'RightArm': chain(R('z', 66 + 18 * wave(b, 1)), R('x', 0)), 'RightForeArm': R('y', 18),
        'LeftUpLeg': R('x', 30 * (1 - jump)), 'LeftLeg': R('x', -55 * (1 - jump)),
        'RightUpLeg': R('x', 30 * (1 - jump)), 'RightLeg': R('x', -55 * (1 - jump)),
    }, (0.0, 0.55 * jump - 0.35 * (1 - jump), 0.0)


CLIPS = {'Dance_Toprock': clip(8, toprock), 'Dance_Windmill': clip(8, windmill), 'Dance_Headspin': clip(8, headspin),
         'Dance_Freeze': clip(8, freeze), 'Dance_Finale': clip(8, finale)}
out = ROOT / 'artifacts' / 'level6-entity-20261003' / 'export' / 'dance_clips.json'
out.write_text(json.dumps(CLIPS))
print({name: data['frames'] for name, data in CLIPS.items()}, out.stat().st_size, 'bytes')

if '--no-install' not in sys.argv:
    sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
    import import_to_studio as studio_io
    s = studio_io.Studio()
    for name, data in CLIPS.items():
        print(s.luau('''
local folder = game:GetService("ReplicatedStorage").Level6Counter.Clips
local old = folder:FindFirstChild("%s")
if old then old:Destroy() end
local value = Instance.new("StringValue")
value.Name = "%s"
value.Value = [==[%s]==]
value.Parent = folder
return value.Name .. " " .. #value.Value
''' % (name, name, json.dumps(data))))
