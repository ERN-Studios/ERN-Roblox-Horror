# B3 narrow PC + B4/B5 shared HUD: implementation handoff

2026-10-09. Shared source owner: Codex dev_tokens_audit. Offline implementation and verification complete; ownership released to root for its fresh CAS audit/push/Studio QA. No Studio, lock, git, commit, publish, image upload or Figma edit was performed by this worker. The earlier `INDEPENDENT-VERIFY.md` remains the immutable history of the original B3 hashes and preexisting failures.

## Product hashes at handoff

| File | SHA-256 |
|---|---|
| `ReplicatedStorage/RoundHud.ModuleScript.lua` | `9cde6c90fa17c38b7e61b8f8f3e5e204f78cf9ae167eeade5e39810bf88d5ad0` |
| `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua` | `cea582f7c3256aca21883e16c0849977f14798d6656e41cac9f6c07da19ea20b` |
| `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua` | `6fbda00100ba7c0f5f810706cc537c09dad3050ba4577f3e1927ed728c509cc5` |

`NoiseReporter` changes are limited to the narrow-PC bar placement and its adjacent explanation. Other caller/server/UIRegression files belong to their respective workers. Root must re-read candidates and use its live baseline before pushing; these hashes are not an assertion of live Studio equality.

## Implemented behavior and contracts

- B3: when Safe width is less than872, the320x26 PC bar uses Safe centre at bottom distance228. Full GRACE marker uses258, preserving the4px bar gap. The bar bottom clears the maximum kit/refusal/detector top by8px. Wider PC and all existing D9 touch bar geometry stay as before. Truly impossible width/height hides rather than drawing outside Safe. Spectated bar keeps its92px lift.
- `Stack(bundle,path,parent,opts)` returns `root,parts,attention?`. Each direct imported part is mounted through `Mount`; current direct GuiObject children flow by LayoutOrder, visibility/height/reparenting close gaps, and `HudStackHeight` publishes bounds. Actual ResultsTouch six imported rows can move into a bounded ScrollingFrame without losing Head/Party/Footer geometry. No Figma geometry is redrawn.
- `Paint` touches only documented Objective/Loading/Results accent paths. Loading paints the current track slot and resets other slots to Sage. `Soften` and two-half-mask `Ring(slot)->set(fraction,color)` are exported.
- `SetObjective` accepts the exact BUILD-PLAN table plus optional `OnOrderActivate`. Wrong-level, inactive, invalid watched subject and nil publishers do not erase active state. `LastObjective` returns the latest valid snapshot with `Counter={Label=Tag,Current=Count,Max=Goal}`, retained through `Clear`. Bearing uses camera X/Z and clamps at±60; distance includes full3D watched-root separation, metres=studs/3.571. Only GET OUT can say AT THE EXIT below8m. inRoom is static Coral; calibrating is stable triple-chevron. Target updates and numeric countdown changes do not reset attention. Danger remains bright and retains its touch status row after6s.
- Touch uses the already-sized240px import. The visual collapsed Bar stays40px; the transparent Attention container reserves44px for its44px hit. This is necessary because [CanvasGroup always clips descendants](https://create.roblox.com/docs/reference/engine/classes/CanvasGroup). Full imported parts are not scaled again. Tap/semantic changes expand6s; Order-line activation calls the supplied callback.
- `Feed({Kind,Actor?,Detail,Key?})` resolves Player/name/id to DisplayName, uses complete UTF8 initials, pools2 PC/1 touch rows, expires at4s and merges same Key within2s. Later actorless LEVEL duplicates preserve the validated team actor/copy. Root-added TeamObjectives keys match L1/L2/L3 caller keys.
- `Caption(speaker,text,seconds?)` is gated and lasts at most3.5s; seconds0 clears regardless of a later gate change. COMMAND CENTER preserves source-gated lobby dispatch only while DispatchTextActive is true. Touch captions replace the feed lane. PC captions clear marker; while spectating they clear the raised watched bar instead.
- Feed measures the visible, enabled B7 HiddenStatus/LeaveHiding/TableCheck union, including the actual44px leave hit. Small/portrait touch lanes yield below an overlapping ObjectiveCard and the door before stepping left; their358px art stays unchanged. Touch detector follows the moved feed/caption lane. RoundGui results/loading and modal gates suppress stale surfaces.
- `Clear` tears down only owned Objective/Detector/Feed/Caption roots; caller marker/stamina survive. Studio-only `CaptureTestState` recursively freezes snapshots; `RestoreTestState` restores nil loss data, entries/deadlines, caption, detector and attention/expansion deadlines while invalidating staged timers.
- Actual `Round HUD` owns `RoundStatus` objective/death gates. Own death belongs to the death card; teammate death reads appended aliveCount after cause. RoundUI alone delivers escape feed. The real client's Studio-only `RoundHud.UIRegressionRoundHudProbe` supports lowercase `capture`, `restore`, `setobjective`, `feed`, `caption`, `snapshot` (LastObjective), and `expandobjective`. QA must invoke this probe, not require RoundHud from execute_luau's separate cache. Restore original player/workspace/device attributes before restoring captured state.

## Offline verification

Official Luau0.737, `python -B`, compiler `-O0 --null` for all3 owned product files: PASS. Real fixtures are `tools/tests/fixtures/hud/framewisp-dump.HUD_PC.json`, `HUD_Touch.json`, `HUD_Screens.json`; no synthetic screen fixture was used.

| Suite | Result |
|---|---|
| `test_round_hud_shared.py` |227 shared checks PASS; isolated real B3 stamina fixture74 PASS |
| `test_round_hud_local.py` |490 PASS, real Round HUD + real RoundHud + real UIDevice layouts |
| `test_round_hud.py` |185 existing module checks PASS |
| `test_equipment_hud.py` |750 PASS |
| `test_flashlight_player_control.py` |730 control +226 PC widget +249 touch LIGHT checks PASS |
| `test_controller_input.py` |91 current controller +86 B2 +74 B3 checks PASS after sibling's retired-objectives port |

Unique checked totals across these suites:3108 (the isolated74 B3 checks are the same fixture as the aggregate, not counted twice). Tests include800/640 PC full10s GRACE+active detector, original≥880 PC and D9 touch lanes, narrow/spectated caption gaps, real authored stack gap closure and bounded roster, all6 loading accents,3D watched compass/no invalid-target fallback, semantic countdown/no wake, touch danger,44 hit bounds, device remount, keyed merges both event orders, UTF8 DisplayName, caption preferences/expiry/lobby dispatch, B7 full warning union, small667 and portrait375 placement, exact held/resting deadline restoration and nil-snapshot cleanup. Driver tests use the actual LocalScript probe handler and actual shared module cache.

## Remaining real engine QA

Offline checks do not prove real fonts, CanvasGroup pixel/clipping, UIGradient half-mask sweep, physical gamepad/touch routing or live control rectangles. Root must inspect320px bar/full GRACE on800/640 with active detector;40px visual/44px hit and Order activation; small-phone/portrait feed+caption+detector alongside Objective, B7 warning and open KIT; real prompt/leave ring sweep; watched-player and device-remount paths; and scoped/full UIRegression with cleanup through the real-player probe. Existing B1/B2 live QA gaps recorded by root remain. No product-source work is pending for this owner; new engine findings should be routed back with the measured rectangles.
