# Level 6 entity, balloons and progressive crayon drawings

This revision changes only seven scripts under `ServerScriptService.Level 6
Systems`: five scoped updates and two new decoration modules. Studio was the
authoritative baseline; each installation compared both Source and editor Source
and rechecked the baseline inside the write. Exact paths and hashes are in
[scoped-script-manifest.json](scoped-script-manifest.json). Final comparison found
all 20 original Level 3 sources unchanged and all seven Level 3 native roots
byte-identical. Evidence is in [verification](verification/README.md).

Level 6 reuses the Level 3 Mall Manager's ordinary and blackout spawn profiles,
eligibility/group selection, safety/visibility rules, music timing, table checks,
navigation, attack/audio tuning and walk animation. Live Master tuning follows
the existing Level 3 overlay namespaces. The deliberate finale difference is a
strict **greater than 50%** trigger: the Manager spawns at 97% of the last corridor,
faces the players and approaches at 28 studs/second. Solo Play recorded no trigger
below or exactly at halfway, then a far-end spawn and actual approach after the
character crossed it. Ordinary spawn clearance was validated at 132.84 studs,
above the 90-stud minimum. These probes used a synthetic music seek or validated
CD setup; they do not establish a full natural round or multiplayer parity.
An active-AI counterplay probe physically reached the real escape sensor without
death or damage/health overrides; its navigation multiplier represented a
26-stud sprint. See the separate [normal spawn](normal-spawn-play-check.json),
[finale](finale-spawn-approach-play-check.json) and
[escape](counterplay-exit-play-check.json) records.

The existing Blender balloon mesh supplies seeded paired/triple bundles, with
ten sparse, ten medium and ten dense rooms per map. Additions target 1–2, 3–4 or
7–9 clusters per room, including floor tethers and ceiling floaters. They remain
noncolliding and outside the protected 14-stud door cross and furniture/objective
envelopes. The [128-seed planner check](balloon-plans-128-seeds.json) passed across
3,840 representative rooms. Two live seeds placed 134 and 130 clusters with no
skips; the final visual seed placed 130 clusters, adding 390 balloons in 650 mesh
chunks. The hard limit is 160 clusters/800 chunks.

There are 48 new transparent crayon motifs in three 16-cell atlases: ordinary,
unsettling and intense non-graphic drawings. District stage and graph distance
increase both density and the probability of disturbing imagery, continuing down
the final corridor. The final visual seed placed 331 drawings: 71 ordinary,
87 unsettling and 173 disturbing. All three images belong to ERN Roblox Studios,
stay Restricted and have access granted to experience `10559217407`. Roblox's
decoded 1024-pixel images were verified, so runtime atlas cells are 256 pixels.
Generation prompts, source hashes and upload/permission evidence are in
[drawings](drawings/README.md).

The final Visual Adapter SHA starts `57cdcd51`. It restores each ceiling
SurfaceLight's full original diffuser size and emission pose and widens the cone
to 175 degrees so the wall art receives lamp light. This task wrote no global
Lighting properties or Lighting Controller source; the preview remains nighttime. Final solo
visual checks found no invalid emitters or colliding decoration. Blackout disabled
all 159 observed fixture lights and restored all 159. Sixteen diffuser chunks
still reported Neon during the isolated check, so complete mesh blackout material
parity is **not** claimed.

The bounded Studio automation observer measured approximately 15 FPS and 6.65 GB
for the whole Studio process. The nearly exact frame rate appears consistent with
background throttling, but that explanation is unverified. Foreground/mobile
performance and multiplayer behavior remain unverified. Full details are in
[final visual QA](final-visual-blackout-play-check.json). The independent Claude
Opus 5.5/max review timed out without producing an audit.

Full native-before and native-after captures are preserved locally, including
jointly serialized raw models and service metadata; the recovery workflow also
reconstructs `.rbxl` places. Raw backups and transient payloads stay out of Git.
Unreadable Studio properties and unsupported Lune property assignments are
recorded; full reconstructed service-property parity is not claimed.

Native comparison and the seven-script verified Studio export passed. Concurrent
Level 4 cinema edits and the owner's HTTP/LightingStyle settings were preserved,
recorded with exact hashes and excluded from this task's write scope. Their
gameplay was not tested by this task. The [publication receipt](publish-receipt.json)
confirms Roblox published the existing place as version **2450**. A fresh
[post-publication check](post-publish-source-verification.json) compared 30 live
sources against the capture, including all task scripts, original Level 3 and the
preserved concurrent scripts. All had Source/editor parity; no temporary QA probe
remained. Task records, assets and the verified mirror are committed locally.
This checkout has no configured Git remote, so no GitHub push was performed.
