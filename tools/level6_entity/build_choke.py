"""The Counter's kill clip (2026-10-04, owner: "it grabs the person, chokes them and brings them closer to the
face until it goes black"). One clip, `Choke`, 5 s, not looping, in the same format as build_dance.py's clips.

    python3 tools/level6_entity/build_choke.py            # writes export/choke_clip.json and installs it in Studio

Timeline (seconds): 0-0.3 both arms shoot out to the throat; 0.3-1.6 it holds and lifts (arms rise, the grip
trembles); 1.6-4.4 the elbows fold and the body leans in, so the hands - and whoever is in them - come up to its
face; 4.4-5 held. The Level 6 Playground Client hangs the victim's camera on the two hand bones, so whatever
this clip does with the hands is what the victim's view does.
"""
import json, math, sys
from pathlib import Path

sys.argv.append('--no-install')            # build_dance builds and installs at import; only its helpers are wanted
sys.path.insert(0, str(Path(__file__).parent))
import build_dance as d
sys.argv.remove('--no-install')

FPS, SECONDS = 30, 5.0
R, chain = d.R, d.chain


def ease(t, a, b):
    u = min(1.0, max(0.0, (t - a) / (b - a)))
    return u * u * (3 - 2 * u)


def pose(t):
    out_, lift, pull = ease(t, 0.0, 0.3), ease(t, 0.3, 1.6), ease(t, 1.6, 4.4)
    grip = math.sin(t * 31) * 0.6 + math.sin(t * 47) * 0.4          # the tremble of a hard grip
    lean = 4 + 24 * pull                                            # the body bends in over its arms
    raise_ = lean + 4 + 14 * lift - 6 * pull + grip * 1.2           # arms: forward, up to the throat
    # The shoulders are 1.4 studs apart, the upper arm is 1.04 and the forearm 0.96: turned in 12.5 degrees with the
    # elbows almost straight the two hands meet in front of the chest, and as the elbows fold the upper arms have to
    # open again (to -14) or the hands would cross.
    spread = 90 + 12.5 - 26.5 * pull
    fold = 8 + 68 * pull + grip * 1.5                               # elbows
    hang = 1 - out_                                                 # from the hanging arms it arrives with
    return {
        'Hips': R('x', -2 * pull),
        'Spine01': R('x', -lean * 0.35), 'Spine': R('x', -lean * 0.65),
        'neck': R('x', -6 - 8 * pull), 'Head': chain(R('z', 7 * math.sin(t * 5.3) * (0.4 + 0.6 * pull)), R('x', 8 * pull)),
        'LeftArm': chain(R('x', raise_ * out_), R('y', -spread * out_), R('z', 74 * hang)),
        'RightArm': chain(R('x', raise_ * out_), R('y', spread * out_), R('z', -74 * hang)),
        'LeftForeArm': R('y', -(14 * hang + fold * out_)), 'RightForeArm': R('y', 14 * hang + fold * out_),
        'LeftHand': R('y', -25 * out_), 'RightHand': R('y', 25 * out_),
    }


frames = int(FPS * SECONDS) + 1
tracks = {name: [] for name in d.BONES}
for f in range(frames):
    full = pose(f / FPS)
    for name in d.BONES:
        q = full.get(name, (0.0, 0.0, 0.0, 1.0))
        n = math.sqrt(sum(v * v for v in q)) or 1.0
        q = tuple(v / n for v in q)
        prev = tracks[name][-4:] if tracks[name] else None
        if prev and sum(p * v for p, v in zip(prev, q)) < 0:
            q = tuple(-v for v in q)
        tracks[name].extend(q)
CLIP = {'frames': frames, 'fps': FPS, 'loop': False,
        'bones': {name: [int(round(v * 10000)) for v in q] for name, q in tracks.items()}}
out = d.ROOT / 'artifacts' / 'level6-entity-20261003' / 'export' / 'choke_clip.json'
out.write_text(json.dumps(CLIP))
print('Choke', frames, 'frames', out.stat().st_size, 'bytes')

if '--no-install' not in sys.argv:
    sys.path.insert(0, str(d.ROOT / 'tools' / 'level6_playground'))
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
