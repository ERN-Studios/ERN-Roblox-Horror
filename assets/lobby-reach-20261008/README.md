# Sounds of the creature behind the lobby's fence (2026-10-08)

Owner: "give the lobby monster sounds behind the fence. Use ElevenLabs and remember to sound engineer the AI
static out." Fourteen sounds, made for this creature only. What plays when is in `tools/lobby_reach/README.md`
("The sounds"); this folder is how they were made.

| here | what |
|---|---|
| `brief.md`, `brief2.md`, `brief3.md` | the three jobs given to Codex (ElevenLabs text to sound effects, `eleven_text_to_sound_v2`, prompt influence 0.6) |
| `raw/` | all 23 takes as ElevenLabs gave them, and `prompts.json` (every prompt and parameter) |
| `jobs.json` | which take became which sound, and the numbers it was cleaned with |
| `clean_reach.py` | measures the takes, cleans and levels them, writes the files beside it and `levels.json` |
| `reach_*.mp3`, `reach_*.ogg` | what was uploaded (the loops are OGG: an MP3 leaves a gap at the join) |
| `levels.json` | per sound: loudness before and after, the floor in its quietest frames and the energy above its cutoff, before and after |

    /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 clean_reach.py measure
    /Applications/Blender.app/Contents/Resources/5.2/python/bin/python3.13 clean_reach.py
    python3 tools/lobby_reach/upload_sounds.py        # then: status
    python3 tools/lobby_reach/install_sounds.py       # writes the ids into the client script

## What the static was, and what took it out

Measured per take in nine bands, once in the loudest quarter of its frames and once in the quietest eighth (the
generator's own floor), and looked at as spectrograms. Three different things, three tools (`clean_reach.py`):

1. **A hiss that is there whether the creature makes a sound or not** (and in two takes a low hum). Every bin is
   gated against the print of the file's own quietest frames: under 6 dB over the print it goes down 12 to 14 dB,
   over 15 dB it is kept whole. Floor between 2 and 16 kHz afterwards: 4 to 26 dB lower (`levels.json`; the drag
   loop cannot be compared, its silences were cut out).
2. **A haze between the partials of a voiced sound**, which rises and falls with it. Only the two groans
   (`retreat`) got this gate (8 dB): on a breath the noise IS the sound, and gating it makes it ring.
3. **A band of hiss above where the sound itself ends.** A steep low-pass per sound: 4.5 to 5.5 kHz for what
   comes from deep in the tunnel (breath, wake, groans), 6.5 to 8.5 kHz for the slaps and cracks, whose click is
   real treble. Energy above the cutoff afterwards: 26 to 45 dB lower.

Then mono, a loudness target and a limiter that turns the gain down round a peak. The first version clipped
peaks softly instead, and on the knuckle cracks that put back the treble the low-pass had just taken (energy above
the cutoff fell 7 dB instead of 34): a clipper is the wrong tool for a sound that is all peak.

## The takes

| sound | take used | why, and what was not used |
|---|---|---|
| `reach_wake_1`, `_2` | `wake_b`, `wake_a` | both good; `a` was nearly all under 200 Hz and got a shelf (+8 dB above 220 Hz) so a phone's speaker has something to play |
| `reach_presence` (loop) | `presence_b` | two long hoarse breaths with their energy at 500 Hz to 2 kHz; 1.2 s of silence added after the second, the join lies in that silence. `presence_loop` was almost all under 150 Hz (nothing on a phone); `presence_c` is a 2-second snore: asleep, and this thing is awake |
| `reach_creep` (loop) | `creep_c` | ten heavy wet slaps, one a second, clean silence between. The generator's loop was seamless with a slap across the join: it is rolled 0.68 s so the join lies in a silence. The thud under 150 Hz carried nearly all the level: everything above 180 Hz is lifted 10 dB. `creep_loop` was thin and 43 LUFS quiet (amplifying it would have amplified its hiss); `creep_d` is a dense wash from 1 to 12 kHz in which texture and hiss cannot be told apart |
| `reach_windup_1`, `_2` | `windup_b`, `windup_c` | knuckle cracks. `windup_a` was one broadband hiss, not cracks |
| `reach_slam_1`, `_2` | `slam_a`, `slam_c` | `a` has the deep boom, `c` the wet slap; `c` is cut at 0.7 s (a stray click at 0.8 s). `slam_b` came back silent (-61 LUFS) |
| `reach_grab_1` | `grab_a` | `grab_b` is three slow snaps, not one closing hand |
| `reach_drag` (loop) | `drag_loop` | came as four bursts with a quarter second of nothing between: the silences are cut out and the level is held even |
| `reach_kill_1`, `_2` | `kill_b`, `kill_a` | |
| `reach_retreat_1`, `_2` | `retreat_a`, `retreat_b` | |

## Limits

- **Nobody has listened to these.** A session cannot hear. They were chosen and checked by band measurements,
  spectrograms before and after, and two play tests that logged which sound played when, at what volume and
  distance. Whether they sound like a creature and not like a generator is the owner's ears' call.
- ElevenLabs refuses a prompt over 450 characters (two of the second job's five failed on that).
- Codex's sandbox has no network: it prints each take's signed URL and the session fetches it with curl.
