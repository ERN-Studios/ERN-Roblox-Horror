# Poolrooms audio plan v3 — 2026-10-10

`ReplicatedStorage.Level2Poolrooms.Plan` is a `StringValue` containing JSON. Its sibling `Sounds` folder holds one `Sound` template for every referenced sound key: `Name` equals the key and `SoundId` is `rbxassetid://` followed by digits. The client reads the JSON once at startup. `revision`, the bank's `AudioRevision`, and template provenance attributes are labels; they do not select a code path or reload a running client.

All new fields are optional. Omitting them retains the v2 mix and timing defaults. Supply finite numbers, ordered ranges (`lo <= hi`), complete three-number coordinates, and correctly typed tables. Arrays must be dense JSON arrays without holes or named entries; each required coordinate has exactly three numbers, each range has exactly two, and `fade` is a two-element duration pair rather than an ordered range. A malformed schema or exceeded declared limit retains the legacy ambience. A missing or invalid Sound template skips its rows, warns once for its key, and publishes that key; it does not invalidate healthy rows. A template that appears later does not restore a row skipped at startup. At least one usable bed row is required.

## Coordinates and section membership

Coordinates are `[x, y, z]` arrays in **studs relative to the generated world's origin**, not absolute world positions. The world's `Origin` Vector3 attribute takes precedence over `plan.origin`. The client adds the selected origin to loop positions, shot authored positions, section boxes, and route endpoints.

Every sound row has a `sections` array of section IDs. `"*"` applies in every known current section. A bed or loop row is a separate persistent voice even when another row uses the same key. Multiple applying beds are mixed as layers; their volumes are not normalized.

`order` defines route neighbours: only the immediately preceding and following IDs in that array count. For `S, P0, A1, P1`, A1's neighbours are P0 and P1. Adjacency does not wrap at the ends, and geographic proximity does not make a neighbour. A current section absent from `order` still plays its own rows and has no route neighbours. Include each section ID once in the intended route order.

## Top-level fields

| Field | Type and default | Meaning |
| --- | --- | --- |
| `revision` | Optional string, ignored by playback | Human-readable pack revision. |
| `origin` | Required three-number coordinate array | Fallback world origin when the world has no `Origin` Vector3 attribute. |
| `order` | Optional array of section IDs, default `[]` | Route adjacency, persistent preload order, and box-detection order. Use the full walking route. |
| `sections` | Required object keyed by section ID | Detector boxes and optional section shot timing. |
| `beds` | Required array, may contain layered rows | Non-positional looping beds. There must be at least one row with a valid template after missing rows are skipped. |
| `loops` | Required array, may be empty | Positioned looping emitters. |
| `shots` | Required array, may be empty | Positioned non-looping environmental one-shots. |
| `route` | Optional array, default `[]` | Streaming fallback segments; see below. |
| `limits` | Optional object | Lower authored budgets or opt into a recent-history depth; see below. |

Budgets count authored rows/keys, including keys whose templates are missing. A plan may use several rows for one key; that key counts once against the distinct-key budget, while every bed and loop row counts against the persistent-row budget.

### `limits`

| Field | Allowed values and default | Meaning |
| --- | --- | --- |
| `persistent` | Integer `1..64`, default `64` | Maximum total `#beds + #loops` rows accepted. |
| `keys` | Integer `1..160`, default `160` | Maximum distinct keys referenced by beds, loops, and shots. |
| `shots` | Integer `0..4`, default `2` | Maximum live one-shot voices, including pending loads and cancellation tails. `0` disables one-shots. |
| `recent` | Integer `0..4`, default legacy depth `2` | Explicit depth is capped to the eligible candidate count minus one, after section, failed-key, and cooldown filtering. The last keys are avoided when another eligible key exists; history never permanently blocks the remaining eligible clip. Omit this field to retain v2's exact two-key rule. |

## `sections[id]`

| Field | Type and default | Meaning |
| --- | --- | --- |
| `min` | Three-number coordinate array | Minimum origin-relative box corner, in studs. |
| `max` | Three-number coordinate array, componentwise at least `min` | Maximum origin-relative box corner, in studs. |
| `passage` | Optional boolean, absent by default | `true` boxes are tested before `false` boxes, with a two-stud margin. It does not alter volume or timing. Omission is accepted but that section's box is not tested; author an explicit boolean to use box fallback. |
| `gap` | Optional ordered range `[lo, hi]` in seconds, each at least `0.001`, default `[18, 45]` | Delay drawn after a due shot attempt while this section is current. A draw with no eligible candidate retries after a random `2..4` seconds only when this section explicitly supplies `gap`. Without `gap`, unsuccessful draws retain the legacy full-gap schedule. |
| `first` | Optional ordered nonnegative range `[lo, hi]` in seconds, absent by default | On an accepted change into this section, schedule `min(existingDeadline, now + random(lo, hi))`. It pulls an upcoming shot earlier and never postpones one. Without `first`, a section change leaves the schedule untouched. |

The session's initial shot deadline is always drawn from `18..30` seconds after session creation; `first` is not applied to the initial section selection. Later accepted section changes use the existing detector debounce (two consecutive polls at about 0.25 seconds each) and can pull that deadline earlier. A later change from an unknown section to a known section also counts. Shots also require an active round and a ready section; the schedule belongs to the session, not a separate timer per room.

Section detection is unchanged: collision `Area` attributes first, passage/area boxes second, the nearest route segment within 55 studs third, and EXIT during the player's exit transition last. Raycast hits named Barrier, Guard, Veil, or Hazard are ignored. When no section can be found, the new mix yields to the legacy ambience.

## Bed rows: `beds[]`

| Field | Type and default | Meaning |
| --- | --- | --- |
| `key` | Required nonempty string | Template key; conventionally starts with `bed_`. |
| `sections` | Required array of section IDs or `"*"` | Sections in which the bed plays. |
| `volume` | Required nonnegative number | Target Roblox Sound volume, a unitless linear gain. |
| `fade` | Optional nonnegative two-number array `[in, out]` in seconds, default `[3, 2]` | Smoothstep fade durations for section transitions. The whole session still fades and cleans up in the existing two seconds when eligibility, world, or generation is lost. |

Beds are non-positional looping Sounds under `SoundService.Level2PoolroomsBeds`; stereo templates remain stereo. A start/restart begins at a random offset in the loaded loop. A row shared across consecutive sections continues without a target-volume dip.

## Loop rows: `loops[]`

| Field | Type and default | Meaning |
| --- | --- | --- |
| `key` | Required nonempty string | Template key; conventionally starts with `loop_`, although v2 also reuses `bed_service`. |
| `sections` | Required array of section IDs or `"*"` | Sections in which the 3D loop is allowed to play. A neighbour's loop is created ahead of time but remains silent until its section applies. |
| `volume` | Required nonnegative number | Target unitless linear gain. |
| `position` | Required three-number coordinate array | Fixed emitter position in origin-relative studs. |
| `name` | Optional string, default `key` | Emitter name for inspection. |
| `min` | Optional nonnegative number, default `8` studs | `RollOffMinDistance`. |
| `max` | Optional number at least `min`, default `90` studs | `RollOffMaxDistance`. |
| `replaces` | Optional string | `"Cascade Water"` proportionally ducks the server's Cascade Water Sound while this loaded loop fades up, and restores its original volume on cleanup. Other strings do not replace an existing sound. |

Loop rolloff uses Roblox `Enum.RollOffMode.InverseTapered`. The effective `max` must be at least the effective `min`, including their defaults; a custom `min` above 90 requires an explicit suitable loop `max`. Loop fades retain the existing three-second entry and two-second exit defaults; `fade` is a bed option.

## Shot rows: `shots[]`

| Field | Type and default | Meaning |
| --- | --- | --- |
| `key` | Required nonempty string | Template key; conventionally starts with `shot_`. |
| `sections` | Required array of section IDs or `"*"` | Sections eligible for this shot. Usually one section, or two route neighbours. |
| `volume` | Required nonnegative number | Base unitless gain; each voice multiplies it by a random `0.9..1.05`. |
| `weight` | Optional number at least `0.001`, default `1` | Relative weighted-draw likelihood among eligible rows. |
| `dist` | Optional two-number array, default `[18, 65]` studs | Inclusive full 3D distance range for authored `positions`; horizontal radius range for random fallback placement. |
| `position` | Optional three-number coordinate array | Legacy fixed origin-relative emitter spot. Used without a distance check when `positions` is absent. |
| `positions` | Optional array of three-number coordinate arrays | Choose uniformly among authored origin-relative spots whose full 3D distance from the listener lies inclusively in `dist`. If none qualify, use random placement. This field takes precedence over `position`, including when its list is empty or none of its spots are in range. |
| `pitch` | Optional ordered range `[lo, hi]`, each at least `0.001`, default `[0.98, 1.02]` | Random Roblox `PlaybackSpeed` ratio, not semitones. A value below one slows and lowers the sound. |
| `cooldown` | Optional nonnegative number, default `70` seconds | Minimum time since this key last **started** playing. It is shared by all shot rows using that key and persists across section changes within the session. |
| `min` | Optional nonnegative number, default `10` studs | `RollOffMinDistance`. |
| `max` | Optional number at least `min`, default `110` studs | `RollOffMaxDistance`. |

Random fallback placement picks a horizontal angle, a radius within `dist`, and a vertical offset of `-1..4` studs relative to the current listener. No geometry/occlusion check is added. Spectators use their eligible spectated player's root as the listener for section selection and shot placement.

The effective shot `max` must be at least the effective `min`, including defaults; a custom `min` above 110 requires an explicit suitable shot `max`. Shots use InverseTapered rolloff, open at silence, retain the existing 0.25-second sine-squared attack and 1.5-second tail driven by actual audio position, and retain the one-second cancellation fade. Engine delay/stall detection and emitter ownership are unchanged. History/cooldown are recorded on actual Sound playback start, not when a pending emitter is created. A shot clone that remains unloaded or has no positive TimeLength after 12 seconds is removed, its key is marked failed for the session, and that key is included in the skipped diagnostic; the rest of the pool can continue.

## Route fallback rows: `route[]`

Each row has `section` (a valid section ID), `a` and `b` (origin-relative three-number endpoints in studs). The closest point on each segment is tested; the nearest qualifying segment under 55 studs supplies the section while collision floors are unavailable. This list does not define neighbours; `order` does.

## Loading, voices, and fallback

Persistent clones are created only when their row applies to the current section or either immediate route neighbour. Unwanted clones fade to silence and remain cached until they have been both silent and unwanted continuously for 30 seconds; this prevents recreation around boundaries. Recently visited rows may therefore remain live outside the three-section window. The absolute persistent clone ceiling is 64, plus up to four shot clones.

Readiness requires a known current section, every usable persistent row of that section loaded, and at least one loaded bed of that section. A persistent clone still unloaded 12 seconds after creation fails for that session and is removed from readiness; another loaded bed can then supply the section. A failure applies to that row, while warnings and the skipped-key list deduplicate by key. If no bed of the current section loads, Ready and Active stay false and the legacy mix keeps ownership. A new session can try a previously timed-out row again.

Preloading runs asynchronously in batches of at most three template Sounds, with a separate 12-second deadline per batch. Beds and loops for the first three route sections are queued first, then the remaining persistent templates in route order, including rows not represented in `order`. A section's shot templates are queued only when that section or a route neighbour is current. Duplicate template keys are queued once. Timeout/cancellation never blocks the frame callback or holds a healthy section behind an unrelated row.

## Client-local diagnostics

Attributes are set on the LocalPlayer only when their values change.

| Attribute | Value |
| --- | --- |
| `Level2PoolroomsAudioReady` | Existing loaded-current-section readiness; false preserves legacy fallback. |
| `Level2PoolroomsAudioActive` | Existing ownership flag, true with readiness and false during exit/cleanup. |
| `Level2PoolroomsAudioSection` | Accepted current section ID, or nil. |
| `Level2PoolroomsAudioLastShot` | Most recently started shot key. |
| `Level2PoolroomsAudioBeds` | Sorted `key=targetVolume` comma list for bed voices currently playing above `0.01`, with two decimal places; multiple audible bed rows sharing a key sum their targets. An outgoing bed can appear as `key=0.00` until it fades below the threshold. |
| `Level2PoolroomsAudioShots` | Number of actual one-shot starts in this session; resets to zero on session cleanup and at the start of a new session. |
| `Level2PoolroomsAudioSkipped` | Sorted comma list of missing/failed keys observed during this client lifetime. |
| `Level2PoolroomsAudioVoices` | Number of live persistent Sound clones, including silent cached neighbours; excludes one-shots/templates. |

Bed/skipped strings are rebuilt only when membership or target values change, not every frame.

## Worked example: A1 cistern

This is a complete small plan illustrating one section, with P0 and P1 as its neighbours. Template assets for these keys must already exist in the bank. Coordinates illustrate the v2 map's origin-relative layout; they are not absolute positions.

```json
{
  "revision": "poolrooms-audio-20261010-v3",
  "origin": [70000, 300, 0],
  "limits": {"persistent": 64, "keys": 160, "shots": 2, "recent": 4},
  "order": ["P0", "A1", "P1"],
  "sections": {
    "P0": {"min": [-762.2, -68.6, 640.5], "max": [-725, 13.2, 741.9], "passage": true},
    "A1": {
      "min": [-929.5, -70.4, -5.7],
      "max": [-557.7, -10.7, 640.6],
      "passage": false,
      "gap": [7, 16],
      "first": [3, 7]
    },
    "P1": {"min": [-757.1, -130.1, 266.8], "max": [-530.4, -65.8, 276.6], "passage": true}
  },
  "beds": [
    {"key": "bed_a1_cistern", "sections": ["A1"], "volume": 0.50, "fade": [1.2, 2]},
    {"key": "bed_water", "sections": ["A1"], "volume": 0.06},
    {"key": "bed_service", "sections": ["P0", "P1"], "volume": 0.45, "fade": [1.2, 1.5]}
  ],
  "loops": [
    {"key": "loop_pumphouse", "name": "Pump House Resonance", "position": [-743.5, -55, 288],
      "sections": ["A1", "P1"], "volume": 0.60, "min": 6, "max": 65}
  ],
  "shots": [
    {"key": "shot_a1_column_drip", "sections": ["A1"], "volume": 0.65, "weight": 3,
      "dist": [16, 42], "cooldown": 24, "pitch": [0.97, 1.03],
      "positions": [[-760, -55, 300], [-735, -55, 320], [-710, -55, 300]]},
    {"key": "shot_a1_pump_tick", "sections": ["A1", "P1"], "volume": 0.45,
      "dist": [20, 48], "cooldown": 30, "pitch": [0.98, 1.02]}
  ],
  "route": [{"section": "A1", "a": [-742, -55, 320], "b": [-742, -55, 288]}]
}
```

At origin `[70000, 300, 0]`, the pump loop's absolute position is `[69256.5, 245, 288]`. While A1 is current, its two bed layers target `0.50` and `0.06`, the A1/P1 pump loop may play, and the P0/P1 bed is created silently for nearby route sections. Entering A1 from another section during an existing session pulls its shot deadline in to at most `3..7` seconds from the accepted entry, and subsequent attempts use `7..16` seconds. If the session starts in A1, its first deadline remains `18..30` seconds. When both example shot rows are eligible, explicit recent depth four is capped to one; with one eligible row it becomes zero.
