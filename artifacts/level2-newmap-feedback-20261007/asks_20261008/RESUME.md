# Owner asks 2026-10-08 evening: PAUSED 20:5x (owner needed the PC)

Live: v2850 (arrival at Level 1's door, a touch lighter, P2 water stair). Nothing of these asks is in Studio yet.

Asks: (1) A2 lion-room skylight onto the gold disc, (2) a bit more light out of the open exit door,
(3) a whole exit slide that ends in RoundUI's LEVEL 2 CLEARED card, then the lobby.

Done offline:
- Designs: G:/Blender/Level2_Poolrooms_New_20261006/work/fb/lead/asks_20261008/designs.md
- make_asks.py (patch for 4 scripts: preview server, preview client, Level 2 Slide Controller, RoundUI) - compiles.
  Run: python make_asks.py PLACE_LAT A2_LAT after measuring the sun in Play (GeographicLatitude sweep at ClockTime 12,
  best GetSunDirection().Y; the place's own latitude was 0 on 2026-10-07).
- make_tests_asks.py: access test passes; feedback test still fails ONE check ("the ride only runs on and down ...").
  The Z-tolerance fix did not apply (its anchor in make_tests_asks.py has different escaping) - fix that anchor
  first, then find which of monotone / lowest / steepest fails (python says: steepest 19.05 deg, monotone, lowest
  312.9, Z drift 1.7e-13).
- Exit lamp: exporter SHAFT_DIM x1.6 (uncommitted in the Blender repo) + re-exported packet (only lights.json changed,
  0.631 -> 1.009); Studio step: roblox/work/exit_lamp_brightness.py (lock-gated, Edit).

Next: fix the test, adversarial review (workflow), take the lock in queue order, measure the sun, apply the patch
(apply_scoped_patch.py), exit lamp script, compile probe, Play QA (skylight, lamp, the ride + card + lobby), publish.

## Resumed 22:43 - status 23:26
- Test fixed; adversarial review (review.md in the Blender asks_20261008 folder) applied: card retry + latch per body,
  Level 3 branch guard in the Slide Controller, beam ends over the disc, 7 soft layers, A2 zone up to Y 391, A2GradeX
  knobs, BaseBrightness synced, one patch file per script (asks_patch_1..4.json), new offline checks (gate, card title,
  barrier decoys, finish probes, curvature, retry/latch, reach refusal). Both preview tests green; mutation checked.
- Exit lamp committed in Blender (da44a57). Play QA: G:/Blender/.../roblox/work/asks_qa.py (sun skylight lamp ride console).
- PUBLISH NEEDS THE OWNER'S OK (lock managerNote 22:55) and ships other sessions' unpublished Studio work (queue gate,
  HUD B1): do Studio + QA, release the lock, then ask.
- Studio order: lock (queue order) -> studios -> Play: asks_qa.py sun -> stop -> make_asks.py PLACE A2 + make_tests_asks.py
  PLACE A2 + tests -> apply asks_patch_1..4 one by one (+ manifest sha each) -> exit_lamp_brightness.py -> verify ->
  compile probe -> Play: asks_qa.py skylight lamp ride console (+ tweak_qa cascade/arrive) -> stop -> release.
