# Level 1 hardware polish (2026-10-04, evening): ceiling seams, lamp glow, lever, fuse extraction

The owner's feedback after the elevator revision:

- soften the black lines between the ceiling panels;
- let the lamp grille glow a little;
- centre the lever rod, make it go from up to down, and give it a good animation;
- improve the fuse-extraction animation.

Everything is installed in the authoritative Studio and mirrored. **Not published.**

## What changed

| Change | Where | Applies to |
|---|---|---|
| Ceiling T-bar grid: matte warm grey (186,178,158) instead of fully metallic PBR (metal got no light and rendered black) | `BlenderRoomRenderer` `matte()` in `Rooms()` and the exit vestibule | preview |
| Fixture louvre glows with its own fixture (lit: Neon at 0.42 x the fixture colour; off, dead, POWERDOWN or BLACKOUT: matte grey) | `BlenderRoomRenderer` Skin / updateColour | preview |
| Relay label plate rides the door | `BlenderRoomRenderer` dynamic list (`RelayLabel`) | preview |
| Relay door opens into the room (was -86 deg into the wall). Hinge published as attributes. Prompt moved off the moving door onto the body (same world spot). Door has CanQuery false. Server tweens removed; server sets the final open pose; fires `relayextract` / `relayrestore` | `PuzzleManager` | public + preview |
| Lever rod pivots on the hub (`LEVER_HINGE` 0, .015, -.72), rests UP (-25 deg), latches DOWN (-155 deg). Handle no longer collides. Server sets the final pose and fires `leverpull` | `PuzzleManager` | public + preview |
| New LocalScript `Level 1 Hardware Client` | `StarterPlayerScripts` | public + preview |

What `Level 1 Hardware Client` animates:

- **Relay hold:** the door unlatches and stands ajar, and the fuse wobbles loose. Releasing early eases everything back.
- **Extraction:** the door swings fully open. The fuse is pulled out and arcs into the extractor's hands, shrinking and fading.
- **Lever:** lift 0.10 s, throw 0.24 s, rebound 0.08 s, settle 0.12 s.
- **Door fade:** the door fades locally where its sweep crosses the first-person camera.

SurfaceAppearance emissive (`EmissiveStrength`/`Tint`/`MaskContent`) exists in this engine, but it rendered **nothing**: strength 20 with a white mask left the pixels unchanged. Comparison: `claude-qa/baseline-hw/grille-emis-compare.jpg`. Neon was used instead (`grille-neon-compare.jpg`, `seams-compare.jpg`).

## Studio writes

All writes were made with fresh-baseline scoped CAS, with Source checked equal to the editor Source.

- **Renderer:** `923217ca` → `b31724bc` (claude-hw-install) → `f7c99569` (claude-hw-install2, BLACKOUT threshold).
- **PuzzleManager:** `8ad034d9` → `9901cea1`.
- **Level 1 Hardware Client:** created via `multi_edit`. Then two verified `multi_edit` passes changed `HOLD_DOOR` from .62 to .3 and added the door fade plus the settle reset. Current sha `252c7b86`.

`studio-sync-manifest.json` records all three. The new item increments counts.scripts and counts.total.

## QA (owner account, real preview prompts, native E holds, Entity paused with the developer P key)

| Check | Result |
|---|---|
| `claude-hw/hw-qa.luau`, new probe, three generations | 6/6 every time. 1600 matte grids. 399 louvres in phase (287-291 lit). 3 relays with hinge/prompt/door/label OK. Lever rests up (+2.24) and latches down (-2.24). Rod base on the hub (0.000). Exit vestibule louvre glows. |
| `claude-hw/qa-runtime-hw.luau` (v2646 structural probe; only the two deliberately changed expectations are scoped) | 121/123. The same two known elevator-revision provenance/PBR items as before. |
| Cancelled hold, full extraction, lever throw | Burst captures in `claude-hw/evidence/` (`relay-cancel-contact`, `relay2-zoom`, `relay2-extract-contact`, `relay-fp-contact`, `lever-throw-contact`) |
| Full loop on the new code | Relays C→B→A, fuse box, lever, ALERT, escape through the exit, reset 8/8 + client reset 3/3. No ghost fuses left on the client. |
| Console | No errors from the changed scripts. One foreign error, `ZyntraMonetization:2260: attempt to call a nil value`, was not touched. |

Adversarial review (workflow `wf_2e608b77-982`) confirmed four findings, all fixed:

- the playtest tool's prompt lookup;
- the settle after relayrestore kept a shrunk ghost;
- the BLACKOUT beacon blink turned the louvre black;
- the full extract swing crossed a centred first-person camera (the door fade).

The old QA labels are scoped in the probe copy. Offline tests `test_level1_team_prompts` and `test_level1_blender_preview` already fail at HEAD f4313a5 and are unrelated.

Not done or open:

- No multiplayer run. Teammates see the extraction and throw, but not another player's hold.
- The relay cluster flicker (5.5 Hz, server-side) is unchanged.
- No publish.

## Later the same night: red ALERT and pit fields, published in v2698

Both changes were installed at the owner's request with no Play QA ("bare lav det"). The owner tests in game.

| Change | Studio write | Commit |
|---|---|---|
| Slightly brighter red ALERT phase: pulse 0.12-0.67 → 0.25-0.85, a dim red ambient (48,14,10), fog 85-450 instead of 30-220 | MazeGenerator 5eb47972 → 170f2de3, RoundUI 3f450edf → 1950ff37 (`claude-alert-receipt.json`, `alert-patch.json`) | 4bc0b38 |
| Pit fields: the kit carpet tiled at 6 studs on the beams (no stretched FloorPanel). One wallpapered slab per beam, 0.05 stud proud of the walkway, from the carpet edge to the bottom (no stretched WallHalf bands, ledges or gaps). A PitFade SurfaceGui gradient reaches black two thirds down. The pit floor is black. | MazeGenerator 170f2de3 → f3bf0447 (`claude-pit-receipt.json`, `pit-patch.json`, `build_pit_patch.py`) | b2b0be7 |

The pit patch had an adversarial review (workflow `wf_be5b58a8-a8f`). It confirmed one finding: the wallpaper phase restarted 1 stud under the lip, because the walkway strip and the wall each tiled from their own face. Making the slab cover the strip fixed it without guessing the texture anchor.

**Published:** the owner had the whole Studio place published as **v2698** at 2026-10-05 06:04:48 UTC. Receipt: `C:/Users/mikke/Documents/Codex/2026-10-02/kan-du-tjekke-hvad-status-for/output/owner-publish-20261005-receipt.json`.

A read-only export afterwards found Studio's MazeGenerator = f3bf0447, matching b2b0be7 and the manifest. Studio's RoundUI is 8df388bb. It still carries the ALERT hunk, plus five lines from another session (`BRIEFINGS_OFF_20261004` early returns, `LoadingLevel`). Those lines are not mirrored here; that session owns them.
