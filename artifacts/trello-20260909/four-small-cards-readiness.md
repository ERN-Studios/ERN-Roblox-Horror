# Four small cards — read-only implementation readiness

10 September 2026. Source inspection only; no runtime edits, Studio actions or publication. Each card remains a separate feature, with its own source baseline, native evidence, critic score and mouse publication before the next change.

## 18 — Remove the weird bar at level entrances

[mirOf8aF](https://trello.com/c/mirOf8aF): “Remove the weird bar.” The parent has seen its image and describes a black horizontal bar across the upper doorway. This agent has not independently viewed that image, so the final visible-object match remains a native step.

The strongest source candidate is **`WallConduit`**, built in `TunnelLobbyBuilder.ModuleScript.lua` around line 3020 inside `Builder.Build`. On each side it is a single dark Metal part at local X=±33.2, Y=10.5, with size 0.65×0.65×274. It extends along Z=-137..137 through all doorway centres (-80, 0, 80), rather than stopping at their openings. It is non-collidable. This is distinct from `LevelNDoorHeader`, whose lower edge is Y=13.95.

If native selection confirms WallConduit, replace each full-length piece with segments using the already authored `wallRanges` (-140..-90, -70..-10, 10..70, 90..140), clipped to the existing -137..137 end extent. Move the creation below that local range declaration or move the declaration earlier; do not duplicate another doorway coordinate list. Keep its current X/Y, thickness, material and non-collision state. Eight short pieces replace two full-length pieces, adding six parts while leaving the authored wall decoration elsewhere.

Verification: native selection confirms the named culprit first; camera from both lobby and bay sides across all six entrances, straight and oblique. All three active queues remain physically reachable and the three future doors remain blocked. A focused emitted-part check should require no conduit intersection with any doorway's Z=-10..10 span and unchanged coverage over closed wall sections. Compile the complete Builder. Do not remove DoorHeader, structural lintels, signs or unrelated reinforcing ribs on a name guess.

## 19 — Doorframe surface overlap

[xDmiuTCx](https://trello.com/c/xDmiuTCx): “Investigate and fix overlapping textures on the doorframe of the lobby level selector.”

**`addDoorway`**, around lines 1962–1987, contains a provable face overlap. Both `LevelNDoorPost` parts and `LevelNDoorHeader` have X-size 3.1 and identical X centre, so their front/back faces are coplanar. Posts span Y=-0.2..14.8; the header spans Y=13.95..16.05. Their faces overlap vertically by 0.85 studs near each upper corner and horizontally over 1.475 studs of each post. These are Metal material surfaces: `tagSurface(..., "Metal")` does not add a Texture because the material-spec table has no Metal entry. Calling this duplicate Texture instances would misdiagnose the source.

Native inspection must determine whether those upper corners match the reported flicker. The same area also contains `EntranceLintelWall` (bottom Y=14) and `DoorVestibuleCeiling` (bottom Y=15.5), so capture the actual opposing parts and face planes rather than adjusting all of them speculatively.

For the demonstrated post/header overlap, the clean candidate is to butt post tops against the header bottom: retain post bottom -0.2, set top 13.95, giving height 14.15 and centre Y=6.875. Keep header, horizontal placement and opening width unchanged. This removes the exact overlapping faces; it changes a very small trim collision volume at the outside corner, so validate real passage rather than claim every collider is byte-identical. If the native culprit is instead a vestibule or shell seam, fix only that measured pair and revise this proposal accordingly.

Verification: both sides and both top corners of all six frames at close/medium distance, with slow camera motion; no flicker, gap or sky sliver. The active doorway aperture and queue interactions must remain intact and future gates must remain sealed. A focused geometry check can compare visible face overlap area before/after and confirm the unchanged clear doorway. Compile the full Builder. Crossbar removal alone does not prove this separate card complete.

## 20 — Honest WIP percentages

[AzpxrZMR](https://trello.com/c/AzpxrZMR): simplify unfinished-level text to “Coming soon, work in progress.” and show a percentage bar. Current session values are Level 4=60%, Level 5=10%, Level 6=5%; no further percentage question is pending.

**`addComingSoonBoard(panel, face, level)`**, lines 263–436, already owns the world SurfaceGui and is called only from `addDoorway`'s `not active` branch around line 2036. It currently displays three filled segments for Level 4 and one for every later level, with route-calibration labels. `ProgressSegments` has no external consumer found.

Use one bounded percentage value from `{[4]=60, [5]=10, [6]=5}` for both displayed `%` text and a continuous track fill `UDim2.fromScale(percent/100, 1)`. Replace the decorative five-segment loop and its obsolete metadata with `ProgressPercent`. Keep “COMING SOON” and “WORK IN PROGRESS” as the meaningful status copy; remove the Route Pending / Route Calibration / extra planning copy rather than leaving contradictory status labels. The LEVEL N sign already identifies the gate. Preserve current dark screen, red status/accent, readable native fonts, brightness and depth-tested SurfaceGui; use enough track height for the 5% fill to be visible without visually exaggerating its width.

Keep the physical SealedDoor and `active` decision untouched. If updating `ComingSoonGateVersion`, update the GUI, blocker and panel together. No timed automatic progress or backend status system is needed.

Verification: native all three panels at near/typical lobby viewing distances and oblique angles; 60/10/5 labels match actual fill ratios, no clipping, Level 1–3 have no WIP board and Level 4–6 remain inaccessible. A small actual-function fixture can inspect generated labels/UDim2/attributes for levels 4/5/6; full Builder compile is required. This is world UI, so screen touch-target tests are not relevant to the noninteractive board.

## 21 — Developer overhead tag

[ZAlinXFV](https://trello.com/c/ZAlinXFV): add a developer name tag in the existing Zyntra Supporter style, with text “Developer”.

**`ZyntraMonetization.Script.lua:addSupporterTag`**, lines 416–447, creates the current server-owned `ZyntraSupporterTag` under Head: 180×28, offset Y=2.7, GothamBold, teal 90/235/215, dark text stroke, AlwaysOnTop, MaxDistance 65. It deliberately hides in rounds. Calls already exist after pass refresh (around 1438), CharacterAdded/Head readiness (1481) and InRound changes (1486).

Reuse that lifecycle as `refreshPlayerTags` and a small local tag-construction helper. Require the existing `ReplicatedStorage.DevAccess` on the server and use **`DevAccess.IsAllowed(player)`**, not username, a new whitelist, client attributes or Supporter ownership. Its three current allowed UserIds are 40920547, 9488575949 and 833029598. The existing DevAccess require inside the token-gift `do` block is scoped there and cannot be reused from the tag function without moving/adding the require intentionally.

Preserve Supporter ownership and benefits. Add `ZyntraDeveloperTag` with exact text “Developer” and the same styling. Keep both visible if a developer also owns Supporter, using separate vertical positions so they do not overlap. Match the existing lobby-only badge behavior unless root explicitly changes that scope; this avoids introducing overhead player tracking in gameplay. Remove/rebuild only the two owned tag names and keep updates idempotent. Never grant Supporter benefits merely because a player is a developer.

Developer identity must not depend on a successful paid-profile lookup. In `setupPlayer`, explicitly handle an already-present character as well as CharacterAdded; pass lookup failure should not suppress a valid Developer badge. Keep refresh confined to the current character if a deferred Head wait finishes after respawn.

Verification: native known developer, ordinary non-supporter and Supporter-only fixtures; developer+Supporter shows both without overlap. Test current character at setup, Head arriving after CharacterAdded, respawn, repeated refresh and lobby→round→lobby suppression/restore. A client-supplied fake developer attribute must have no effect. Offline exercise the real DevAccess and tag helper with generated UI nodes, including a profile lookup failure path; no live purchases or DataStore writes are needed. Compile the full Monetization file to catch scope/local-limit regressions. RoundUI's character-preview clone already removes all BillboardGui descendants, so no preview-specific change is expected.

## Execution order

Keep priorities 18→19→20→21. The first three touch the same Builder but require independent published checkpoints; take a fresh baseline after each preceding publication. This file is preparation only, and none of these cards has been marked complete or accepted by a critic.
