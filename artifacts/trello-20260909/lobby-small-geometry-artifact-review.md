# Lobby crossbar and doorframe — independent artifact review

10 September 2026. Review only; no runtime or Studio edits, application or publish.
Both proposals compile as complete Builder modules (192 KB combined bytecode).
Runtime SHA remains `ec3593a320bcda26b7f1cf0d7f3ff3e71312f27e3aac40e09b58260eed9f7ae0`.

| Proposal | Independent reviewer | Score | Repeated evidence |
| --- | --- | --- | --- |
| Crossbar, mirOf8aF | `/root/critic` — original author did not score their own work | **9/10** | Exact diff, native-before image, 4,464 actual emitted-geometry checks; all 474 sampled baseline aperture hits removed; full compile |
| Doorframe, xDmiuTCx | `/root/spawn_diagnosis` | **9/10** | Exact two-line diff, native-before image/geometry, 12 measured post/header pairs; 216 additional actual-source checks over 12 doorway/translated-center fixtures; full compile |

**Crossbar:** existing wallRanges place eight non-collidable conduit segments in
the closed wall spans instead of two continuous bars. Height, thickness, material,
end setbacks and neighboring emitted geometry are preserved; part count rises by
six. Root already identified the reported bar as WallConduit with a native ray.
The older README ending and `nativeVisibleObjectMatchRequired` field predate that
identification. After-fix acceptance still needs all six openings from the lobby
and bay sides, straight/oblique cameras, active queue approach/interaction and
future gates remaining sealed. No after-fix rendering is claimed here.

**Doorframe:** shortening the posts to 14.15 studs at local Y=6.875 preserves
their bottom and horizontal opening while meeting the unchanged header bottom.
The actual old/new source removes the measured 0.85×1.475-stud coplanar face area
per upper corner. Both pieces are Metal without Texture instances; this is a
surface overlap fix, not removal of duplicate Texture objects. All other Builder
source is unchanged. The outermost 0.075 stud of each post extends beyond the
header horizontally, so the shortened trim changes a small exterior corner
volume; collider identity and a perfectly seamless rendered corner are not
claimed. Native slow camera movement must confirm no flicker, gap or sky sliver
at both upper corners and both sides of every frame, plus unchanged passage and
queue/future-gate behavior. Static before images cannot prove temporal flicker.

**Apply separately:** both saved full proposals use the same original Builder
baseline. After publishing Crossbar, apply the precise Doorframe transform to
that new checkpoint (or regenerate from it); copying the old full Doorframe
proposal would restore the crossbars. The two scoped transforms were verified
to compose without changing each other's result. Preserve each checkpoint's
before copy and inspect its scoped diff, native-test and mouse-publish it before
the next card. `doorframe-prepared/prepare.py` rewrites its before copy from the
current runtime when run, so archive that copy before deliberate regeneration.

Existing checks repeated:

```text
LUAU_BIN=<luau.exe> python artifacts/trello-20260909/crossbar-prepared/prepare_and_test.py
python artifacts/trello-20260909/doorframe-prepared/prepare.py
luau-compile.exe --null <crossbar-proposed.lua> <doorframe-proposed.lua>
```

The Doorframe command was wrapped with before/runtime byte-equality guards and
after-run checks; it left existing before/proposed and runtime bytes unchanged.
The additional temporary Luau fixture executed the actual frame-creation source
for six entrances at two centers; it did not duplicate placement formulas.
