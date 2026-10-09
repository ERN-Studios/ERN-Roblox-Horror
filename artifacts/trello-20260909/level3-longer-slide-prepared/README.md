# Level 3 — longer slide and progressively higher party spawns

Trello `iuP2GkZL` (#59), direct read: **“Make the Level 3 slide longer and place successive player spawns progressively higher up the slide so players do not end up outside the map.”** The card is To Do, open/incomplete, with no checklist or comments; last activity 2026-09-10T10:16:48.193Z. This directory is a prepared proposal, with no runtime/Studio/UI/Trello mutation.

## Diagnosis and the bounded fix

GameManager, not the Level 3 adapter, selects the final slide resume position. Its previous candidate formula subtracts six studs from the path coordinate for each occupied slot. All six nominal v1849 positions are inside the current 230/66 bore, but later players start **lower**, contrary to the requested behavior. A normal six-player out-of-map failure has **not** been reproduced by this code-only investigation. Previously saved v1849 native math/rig-clone evidence also found those nominal positions inside. The user's reported physical/network outcome remains a native acceptance case, not a claimed prior reproduction.

Simply reversing that old formula would be unsafe: with the old first alpha .93, the sixth uphill point reaches alpha 1.0604, beyond the rear cap. The change therefore provides actual room for the requested uphill queue:

- World Builder: horizontal length **230 → 400**, rise **66 → 115**, first resume alpha **.93 → .80**.
- Only GameManager's `levelThreeSlideResume`: scan up the same published curve in **12-stud X increments**; refuse any candidate within 12 studs of/beyond the rear end. The six configured candidates actually retain at least **20 studs** before the rear cap.
- Keep the same radius8, 32 longitudinal sections and 20 panels per section. Panel count, collision count, materials, friction, runout, aperture construction, NO EXIT sign, rear cap, input/slide controls, exit and entity logic are unchanged. The maximum complete shell panel is14.50344 studs long, including its original overlap.

The six root positions, relative to the published mouth, are:

| Slot | X | Y above mouth | Alpha | X distance before cap |
|---|---:|---:|---:|---:|
| 1 | −320 | 73.6000 | .80 | 80 |
| 2 | −332 | 79.2235 | .83 | 68 |
| 3 | −344 | 85.0540 | .86 | 56 |
| 4 | −356 | 91.0915 | .89 | 44 |
| 5 | −368 | 97.3360 | .92 | 32 |
| 6 | −380 | 103.7875 | .95 | 20 |

Every point has its own downhill tangent and unchanged62-stud/s starting velocity. The existing actual-character occupancy check chooses the first vacant candidate. A missing body frees a slot; a full six-slot bore refuses a seventh and leaves the existing solid-floor fallback in control. The existing root-to-model-pivot correction still places the actual HRP at the selected point, without yielding between selection and PivotTo. The existing temporary adapter landing grid already fits the arrival room and needs no edit.

`beginVerifiedBoreStream`, its acknowledgement, the anchored preparation/release/fallback closure, input/joints/client drive, and the rest of GameManager remain byte-identical. No Testing-card loading/streaming behavior or other level is changed. The longer tube extends the rendered footprint another170 studs west; generator plan aspect ratios do not describe this mesh extension, and no new full render-bounds/streaming-performance result is claimed.

## Files and composition contract

| File | Baseline raw SHA-256 | Proposed canonical SHA-256 |
|---|---|---|
| `ServerScriptService/GameManager.Script.lua` | `3615b6a3ca5eb8dde3acdcc7c4f03ed674b5cc84641bce6ed07670e67c3e5d58` | `241d8ad4c2ccb70a7d3f62c7ef3a05b7909500723725019a52ac44a067df0219` |
| `ServerScriptService/Level 3 Systems/Level 3 World Builder.ModuleScript.lua` | `f1256558007826450fe5c86cc2a0f160d2274270ae345380135d4585bcb6f6b3` | `a3a41d76f6dc6d13d782cb5dab5595757a5cd9b1d1b440f6605f310c56bf983d` |

Complete before/proposed files, narrow diffs and `manifest.json` are included. `prepare.py` writes only this artifact directory and verifies exact baseline hashes. Its pure `manager(source)` transform changes only `levelThreeSlideResume`; root can compose it with the independently prepared lobby/ESP changes instead of replacing a newer whole GameManager. The selected region's canonical SHA changes from `f247f406696ac9eadaf5f857d844804edf03ce2832f556d4770b681060c2e7de` to `9dbb63c02adc69634a14c1802a738381da63a62e356ce9b815d6cddab4cfc0da`.

## Verification

```powershell
python artifacts/trello-20260909/level3-longer-slide-prepared/prepare.py
python artifacts/trello-20260909/level3-longer-slide-prepared/test_slide.py
# Optionally validate root's composed GameManager; no production write:
python artifacts/trello-20260909/level3-longer-slide-prepared/test_slide.py --gm-source <merged-GameManager.lua>
```

**433 actual GameManager checks**, **7,787 geometry checks**, and **61,269 existing aperture checks** pass. Both complete files compile. Two negative controls reject the original downward selector and the actual original short-bore geometry's insufficient uphill rear reserve.

The host runs the actual selector, placement and release functions across parties1–6, rotated/nonzero model-pivot offsets, occupancy/vacancy/refusal, stream-target/anchor/prepare/release/fallback, stale character, failed entry and missing world. A source override must contain the exact reviewed selector; the host then runs its actual adjacent placement/release helpers and compiles that entire override. It does not emulate the whole GameManager or change its shared services.

The real World Builder emits all640 shell panels,32 runout parts, the cap and aperture into a constructor/math host. A full separating-axis check places the previously native-measured authored collision bounds at all six root frames and finds no initial avatar/tube/cap or pairwise intersection. Minimum six-rider root separation is **13.25231 studs**. All **3,720 radial rays around actual segment joints and just either side** hit the generated shell/runout. The unchanged aperture assertions include240 front/oblique rays and minimum0.143256-stud clearance from the inner bore.

The farthest spawn from its nearest actually generated tagged collider is **8.10531 studs**, within the unchanged client's28-stud stream-readiness check. Each point also has an actual generated slide collider on its vertical support ray. Those are geometric checks, not proof of client replication. The constructor host reuses the established aperture test and v1849 math fixtures; it does not simulate Roblox physics, dynamic ragdoll limb extents, arbitrary avatar scaling, real networking or client ownership.

Independent critic reran the checks and gave **9/10 for this prepared code/geometric change**, without a remaining required correction. See `independent-review.md`. Native acceptance and publication remain pending.

## Native runbook for root

Current Switch composition and the exact normal L2→L3 route are specified in `native-acceptance-current.md`. In particular, use the actual Level 2 exit route for normal bore-resume acceptance; a direct Level 3 lobby queue uses the service elevator.

1. Stop Play, preserve the current checkpoint, and verify both current source baselines. Apply the narrow transforms to the intended current sources (compose GameManager if needed), compile the full files, push/read back and audit. This artifact has not performed those operations.
2. Launch Level2 from the normal lobby with the available real clients, physically complete its exit, and continue to Level3 through the campaign's bore route as detailed in `native-acceptance-current.md`. For the complete six-player requirement, use a real six-client local party or record the smaller player count honestly; cloned character placement is supplementary geometry evidence, not multiplayer acceptance. Capture each actual HRP while anchored and after release, its chosen path alpha/Y, stream acknowledgment and health.
3. Confirm the later actual players start successively higher/farther up the same tube, all within alpha .80–.95, and none crosses the rear cap or starts through the shell. Observe all riders travelling down into the mall with their actual client slide controller. Check no collision fling/void fall, actual health stays valid, and movement/joints/PlatformStand return to the normal state at the mouth.
4. Reuse the existing Level3-only `ValidateLevelThreeResume` / `ProbeLevelThreeSlideOut` methods from the Exit Transition Test Suite if helpful. The existing ride threshold (>80% of total length, downhill acceleration, physical mouth exit and released slide state) is preserved; do not weaken it. The probe repositions/restores one actual player and is therefore supplemental to the normal party entry, not its replacement.
5. Inspect the unchanged mouth/seal from the front and both oblique directions, plus the longer tube's joints and rear. Check normal arrival-room footing, the existing NO EXIT sign and input after the slide. The already accepted later run-in exit does not need recertification for this patch. No new entity behavior or new full-level aspect result should be inferred from this check.
6. Stop/restart while a rider is still in the bore and verify old world/slip-loop cleanup, no leftover anchored current body or PlatformStand. Observe the unchanged stream-failure fallback only if naturally/test-safely available; this card does not reopen the excluded Testing loading fixes.

Root owns native evidence, final critical score≥8 and the separate mouse publication before moving to another feature.
