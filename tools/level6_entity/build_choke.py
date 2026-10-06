"""The Counter's kill clip, `Choke`: 5 s, not looping, in the format the Level 6 Playground Client plays.

    python3 tools/level6_entity/build_choke.py              # writes export/choke_clip.json and installs it in Studio
    python3 tools/level6_entity/build_choke.py --no-install
    python3 tools/level6_entity/build_choke.py --dump 0.3,1.5,3,4.4 out.json     # poses for a test rig

CHOKE_20261006 (owner, with ten frames of the first version: "the choke effect with the hands looks awful ... fix
this so the entity is choking the player visually"). The first version held both arms straight out with the palms
down and the wrists touching, and the victim's camera sat just behind the fingertips: what you saw was two fans of
fingers in your face and forearms that crossed.

Now the clip is built round the victim's NECK. `neck(t)` is where that neck is, in the doll's own space, for the
whole five seconds, and each frame's arms are solved to it (rig_math.solve_arm): a hand on either side of the
neck, palms in, thumbs up, the rigid fingers lying round the back of it, elbows out. The same `neck(t)` is what the
server moves the victim's body along and what the victim's camera hangs above, so the three agree by construction:
    - Level 6 Playground Game, Session:catch: `chokeNeck(t)` (the numbers of NECK_KEYS below, in CONFIG.Choke)
    - Level 6 Playground Client, killCam: the eye is EYE_UP above the neck, and the neck is PALM_BELOW_NECK above
      the middle of the two palms (each PALM_ALONG along its hand from the wrist): its table CHOKE
Change the numbers here and the build prints what the two scripts must hold.

Timeline (seconds): 0-0.3 it bends down and takes the throat; 0.3-1.5 it straightens and lifts the victim off the
floor at arm's length, above its own head; 1.7-4.3 the elbows fold and it brings them down to its face; held to 5.
"""
import json, math, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import rig_math as rm

FPS, SECONDS = 30, 5.0
FEET_Y = rm.MESH['feetY']                       # the floor, in the doll's space (its origin is the mesh's centre)

# ---- the victim (the hazmat round body, measured in Studio 2026-10-06) --------------------------------------------
NECK_ABOVE_FEET = 4.66                          # the Head's NeckRigAttachment, standing
EYE_UP = 0.57                                   # the first-person eye above that attachment
NECK_RADIUS = 0.60                              # the suit's collar is 1.2 across
# ---- the doll's hand: 0.84 long from the wrist, 0.34 thick, the thumb on the edge that is "up" in this grip ---------
PALM_ALONG = 0.42                               # wrist to the middle of the palm
PALM_BELOW_NECK = 0.05                          # the palms sit this far under the neck attachment
HAND_THICK = 0.34
GRIP_YAW = 16.0                                 # how far the fingers turn in behind the neck
SINK = 0.24                                     # how far the palms press into the collar

# ---- where the victim's neck is: (time, height above the victim's own standing neck, distance in front of the doll) --
T_GRAB, T_LIFT, T_PULL0, T_PULL1 = 0.30, 1.50, 1.70, 4.30
NECK_KEYS = {'grab': (0.0, 2.30), 'lift': (1.85, 1.78), 'pull': (1.45, 1.62)}
LEAN = {'grab': 11.0, 'lift': -7.0, 'pull': 4.0}            # the spine: forward is positive


def ease(t, a, b):
    u = min(1.0, max(0.0, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def mix(t, table):
    lift, pull = ease(t, T_GRAB, T_LIFT), ease(t, T_PULL0, T_PULL1)
    g, l, p = table['grab'], table['lift'], table['pull']
    if isinstance(g, tuple):
        return tuple(g[i] + (l[i] - g[i]) * lift + (p[i] - l[i]) * pull for i in range(len(g)))
    return g + (l - g) * lift + (p - l) * pull


def neck(t):
    """The victim's neck in the doll's space (x across, y up from the mesh centre, -z in front of it)."""
    rise, away = mix(t, NECK_KEYS)
    return (0.0, FEET_Y + NECK_ABOVE_FEET + rise, -away)


def eye(t):
    n = neck(t)
    return (n[0], n[1] + EYE_UP, n[2])


def grip(t, side):
    """One hand on the neck: (wrist, finger axis, palm normal)."""
    n = neck(t)
    inward = 1.0 if side == 'Left' else -1.0                         # the left hand is at -x and presses toward +x
    b = math.radians(GRIP_YAW)
    # the hands follow the forearms up a little when the victim is held high: a wrist bent right back looks broken
    tilt = math.radians(14.0 * ease(t, T_GRAB, T_LIFT) - 8.0 * ease(t, T_PULL0, T_PULL1))
    axis = (inward * math.sin(b), math.sin(tilt), -math.cos(b) * math.cos(tilt))
    palm = (inward * math.cos(b), 0.0, math.sin(b))
    centre = (n[0] - inward * (NECK_RADIUS + HAND_THICK / 2 - SINK), n[1] - PALM_BELOW_NECK, n[2])
    wrist = rm.sub(centre, rm.mul(rm.unit(axis), PALM_ALONG))
    return wrist, axis, palm


def pose(t):
    reach = ease(t, 0.0, T_GRAB)
    lift, pull = ease(t, T_GRAB, T_LIFT), ease(t, T_PULL0, T_PULL1)
    shake = math.sin(t * 31) * 0.6 + math.sin(t * 47) * 0.4          # the tremble of a hard grip
    lean = mix(t, LEAN) * reach
    p = {
        'Hips': rm.R('x', -2.0 * reach),
        'Spine01': rm.R('x', -lean * 0.35), 'Spine': rm.R('x', -lean * 0.65),
    }
    # the head looks at the victim's eyes whatever the spine is doing, and rolls slowly from side to side
    head = rm.fk(p)['Head'][0]
    look = rm.sub(eye(t), rm.add(head, (0.0, 0.62, 0.0)))
    up = math.degrees(math.atan2(look[1], math.hypot(look[0], look[2])))
    nod = (up + lean) * reach
    roll = 7.0 * math.sin(t * 2.1) * (0.4 + 0.6 * pull) * reach
    p['neck'] = rm.R('x', nod * 0.4)
    p['Head'] = rm.chain(rm.R('z', roll), rm.R('x', nod * 0.6))
    # shrugged into it: the shoulders come up and forward as the arms take the weight
    p['LeftShoulder'] = rm.chain(rm.R('z', -8.0 * lift * reach), rm.R('y', -6.0 * reach))
    p['RightShoulder'] = rm.chain(rm.R('z', 8.0 * lift * reach), rm.R('y', 6.0 * reach))
    for side in ('Left', 'Right'):
        out = -1.0 if side == 'Left' else 1.0
        wrist, axis, palm = grip(t, side)
        wrist = rm.add(wrist, (0.0, shake * 0.012 * (0.4 + pull), shake * 0.008))
        # elbows out and down, further out as they fold
        pole = (out * (1.0 + 0.6 * pull), -0.75 + 0.35 * pull, 0.25)
        solved = dict(p)
        rm.solve_arm(side, solved, wrist, pole, palm, axis, palm)
        # from the arms it arrives with (hanging at its sides) into the grip, in the first three tenths of a second
        hang = {side + 'Arm': rm.R('z', -74.0 * out), side + 'ForeArm': rm.R('y', 14.0 * out), side + 'Hand': rm.IDENT}
        for bone in (side + 'Arm', side + 'ForeArm', side + 'Hand'):
            a, b = hang[bone], solved[bone]
            if sum(x * y for x, y in zip(a, b)) < 0:
                b = tuple(-v for v in b)
            q = tuple(x + (y - x) * reach for x, y in zip(a, b))
            n = math.sqrt(sum(v * v for v in q))
            p[bone] = tuple(v / n for v in q)
    return p


def check():
    """Every frame after the grab: the hands reach the neck, do not cross, and stay clear of the victim's eyes."""
    worst = 0.0
    for f in range(int(T_GRAB * FPS), int(FPS * SECONDS) + 1):
        t = f / FPS
        world = rm.fk(pose(t))
        for side in ('Left', 'Right'):
            want = grip(t, side)[0]
            got = world[side + 'Hand'][0]
            worst = max(worst, rm.length(rm.sub(want, got)))
        assert world['LeftHand'][0][0] < -0.5 < 0.5 < world['RightHand'][0][0], f'the hands close in at {t:.2f} s'
    assert worst < 0.06, f'a hand is {worst:.2f} studs off the neck: out of reach'
    return worst


if __name__ == '__main__':
    if '--dump' in sys.argv:
        i = sys.argv.index('--dump')
        out = {}
        for t in (float(v) for v in sys.argv[i + 1].split(',')):
            w = rm.fk(pose(t))
            out[str(t)] = {'pose': {k: [round(c, 5) for c in v] for k, v in pose(t).items()},
                           'expect': {k: [round(c, 3) for c in w[k][0]] for k in ('LeftHand', 'RightHand', 'Head', 'LeftForeArm')},
                           'neck': [round(c, 3) for c in neck(t)], 'eye': [round(c, 3) for c in eye(t)],
                           'face': [round(c, 3) for c in rm.add(w['Head'][0], rm.qrot(w['Head'][1], (0.0, 0.62, -0.45)))]}
        Path(sys.argv[i + 2]).write_text(json.dumps(out))
        print('reach error', round(check(), 3), 'studs;', len(out), 'poses written')
        sys.exit(0)

    worst = check()
    frames = int(FPS * SECONDS) + 1
    tracks = {name: [] for name in rm.BONES}
    for f in range(frames):
        full = pose(f / FPS)
        for name in rm.BONES:
            q = full.get(name, rm.IDENT)
            n = math.sqrt(sum(v * v for v in q)) or 1.0
            q = tuple(v / n for v in q)
            prev = tracks[name][-4:] if tracks[name] else None
            if prev and sum(a * b for a, b in zip(prev, q)) < 0:      # keep to one hemisphere: the client lerps
                q = tuple(-v for v in q)
            tracks[name].extend(q)
    CLIP = {'frames': frames, 'fps': FPS, 'loop': False,
            'bones': {name: [int(round(v * 10000)) for v in q] for name, q in tracks.items()}}
    out = rm.ROOT / 'artifacts' / 'level6-entity-20261003' / 'export' / 'choke_clip.json'
    out.write_text(json.dumps(CLIP))
    print('Choke', frames, 'frames', out.stat().st_size, 'bytes; the hands are within', round(worst, 3), 'studs of the neck throughout')
    print('game module, CONFIG.Choke: Grab', NECK_KEYS['grab'], 'Lift', NECK_KEYS['lift'], 'Pull', NECK_KEYS['pull'],
          'Times', (T_GRAB, T_LIFT, T_PULL0, T_PULL1), 'NeckAboveFeet', NECK_ABOVE_FEET, '; GrabDistance', NECK_KEYS['grab'][1])
    print('client, CHOKE: Grab', T_GRAB, 'Lift', T_LIFT, 'Pull0', T_PULL0, 'Pull1', T_PULL1, 'GrabDistance', NECK_KEYS['grab'][1],
          'NeckAboveFeet', NECK_ABOVE_FEET, 'EyeUp', EYE_UP, 'PalmAlong', PALM_ALONG, 'PalmBelowNeck', PALM_BELOW_NECK)

    if '--no-install' not in sys.argv:
        sys.path.insert(0, str(rm.ROOT / 'tools' / 'level6_playground'))
        import import_to_studio as studio_io
        s = studio_io.Studio()
        print(s.luau('''
local folder = game:GetService("ReplicatedStorage").Level6Counter.Clips
local old = folder:FindFirstChild("Choke")
if old then old:Destroy() end
local value = Instance.new("StringValue")
value.Name = "Choke"
value.Value = [==[%s]==]
value.Parent = folder
return value.Name .. " " .. #value.Value
''' % json.dumps(CLIP)))
