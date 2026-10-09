# Level 3 run-in exit — implementation and release verification

The user's clarified requirement is automatic escape when running into the
unlocked freight exit. The previous final ProximityPrompt is removed.

## Change

- World Builder creates a hidden, anchored `EscapeTrigger` at the freight
  doorway. Its size is 3 × 10 × 9.5 studs. It fits between the existing jambs;
  the solid leaf stops a normal running character with its root inside the
  detector. All visible door geometry remains.
- Objective Controller accepts a player only when the current Level 3 session
  is active, the CD exit is unlocked, the player is present and in the round,
  the character is alive, and its root is inside the detector's oriented bounds.
  Root comparisons also reject non-finite positions.
- Touch and the existing 10 Hz heartbeat invoke the same check. The heartbeat
  covers an early limb touch, absent touch events, or unlock with a runner
  already at the door. The escape flag is latched before the existing safe-room
  placement, sound and party notification, preventing duplicates.
- Touch detection is enabled before connecting its listener. `Stop` disconnects
  both handlers through existing session cleanup and disables the detector.
- Adapter and Test Suite manifest assertions now use `EscapeTrigger`; the
  suite rejects a leftover final EscapePrompt. CD and VCR interaction are unchanged.

## Validation completed offline

- `tools/tests/test_level3_run_in_exit.py`: **94 checks passed** using the actual
  exit builder, current production player/session guards, escape function,
  unlock function, touch/heartbeat registration and complete Stop function.
  Roblox instances/physics and unrelated CD/audio/lighting operations are fakes.
- Covers touch and occupancy success, locked rejection, waiting during unlock,
  root outside on every side, non-finite root, rotated volume, stale session,
  replaced generation, removed/foreign/disabled detector, absent/dead character,
  non-participant/departed/already escaped player, one-shot effects, two players
  and distinct safe-room slots, and handler cleanup.
- All four changed production Luau files compile using Luau 0.737.
- `git diff --check` passes. Source newline conventions and final-newline state
  are preserved. The pre-existing Test Suite changes are retained.

Before snapshots: `artifacts/trello-20260909/exit-before/`.
Focused production diff: `artifacts/trello-20260909/level3-run-in-exit.diff`.

## Actual-play requirements recorded at implementation handoff

Start Level 3 through the real queue. No final exit prompt should appear. Before
CD unlock, running against the final door must not escape. After genuine CD
insertion, run at the door without E and verify one escape plus safe-room/party
result. Check sprint and a second player, since offline geometry arithmetic
does not prove the real character's collisions or client streaming.

No Studio push, UI operation or publication was performed by this subagent.
The root owns synchronization, critique review and per-feature publication.

## Root verification and publication update — 9 September 2026

The root subsequently synchronized the scoped change to Studio, verified
**122/122 scripts compiled** and **0 source drift**, and received an independent
critic score of **9/10**.

The locked-exit control left the living player unescaped at the door with 100 HP.
The first positive attempt was interrupted by an AI kill and is not counted as a
passing escape test. In a fresh Level 3 generation (**generation 2**), AI was
isolated for a focused physics test. Test setup collected/inserted five CDs
through the objective paths, and physical `MoveTo` into the unlocked door
produced **one escape event**, `Escaped=true`, **100 HP at escape**, and the
normal round-completion path (`RoundActive=false`). This proves the run-in
detector with one actual Studio client under AI isolation; it does not claim an
unassisted full gameplay run or a published multiplayer test. Evidence:
[level3-exit-playtest.json](level3-exit-playtest.json).

A fresh native Studio screenshot confirmed **v1814 published at 22:23:09,
9 September 2026, Danish local time**. An earlier Alt+P tool call was interrupted,
and the user reported that the app closed. The user's subsequent instruction
requires **mouse publication through Studio menus, not the keyboard shortcut**.
The root's attempted menu action was disrupted by focus/user input, and the
following screenshot already showed the v1814 publication confirmation. The
published result is confirmed; the evidence does **not** establish whether the
prior request or the user's input triggered it. Do not describe this as a
confirmed mouse publication performed by the root. Future releases must use the
new menu/mouse instruction.
