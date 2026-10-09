# Independent final review — left buttons and dispatch mute

**Overall release score: 9/10. Revised button design: 10/10. No blocking finding.**

This reviews the user's latest revision: substantially smaller buttons at the left edge, Shop above Upgrades, complete outlines, and a copy of the existing dispatch-mute control below them. The previous right-side square approval is historical and is not the basis for this decision.

## Exact reviewed sources

| Source | SHA-256 |
|---|---|
| Store | `5638699125280c0980128946efb1c20018da219c3c263d9e9c21bc402843ee6b` |
| RoundUI | `59c29543b0e4d24eb733be2a096c36a684d8d6d285234984ed24ce9df44a519f` |

Both installed filesystem sources matched these proposals during this review. Their baselines were Store `b031c3ab5b27edb484b5a62c40fcb380434df1c664d6cb51811e27c7b688a3cb` and RoundUI `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3`. I read the complete deltas and checked that reversing their changed regions restores the exact baseline bytes. Store preparation reproduces the exact proposal from the preserved baseline.

## Code and focused verification

I independently reran Store's **147 actual-source checks**, the wrong-right-edge and missing-inset negative controls, and both whole-file compiles. I also independently ran RoundUI's **38 actual-source checks**, the original active-only negative control, and its whole-file compile before installation. These are controlled-host checks, not additional native gameplay trials.

The Store change keeps existing assets, purchase handlers and tab behavior, reserves transparent mute geometry, and fits each complete bitmap inside a three-pixel inset above its caption. Its fallback remains on the left and rejects collision with visible movement controls. Full modals and round state hide the lobby controls; active Dispatch hides the two openers while retaining the mute copy.

RoundUI owns the copied control. It shares the original private preference, pending/acknowledgement state, timeout and `SetMuteDispatch` action. Only the explicit copy can request a toggle during idle lobby time. The original button, M and LB retain their active-transmission requirement. The copy uses an explicit Border stroke and refreshes its font when the slot resizes. No new economy or persistence mechanism is introduced.

## Native evidence independently read and viewed

The screenshots and JSON were produced by root in actual Studio; this reviewer operated no Studio/UI tools.

- **Desktop idle:** [native-desktop-idle.jpg](native-desktop-idle.jpg) and [JSON](native-desktop-idle.json) show 64-pixel squares at x=8, y=8/80 and a 64×44 mute control at y=152. Both images are loaded, both captions fit, and all outlines are complete. The icons and captions have distinct space and the narrow column leaves the scene visible.
- **Phone emulator:** [native-phone-idle.jpg](native-phone-idle.jpg) and [JSON](native-phone-idle.json) show actual iPhone 13 emulation, no synthetic override, with 749×368 camera viewport and 749×310 safe area. The squares are 56×56 at x=8, y=8/70; mute is 56×44 at y=134. The 50×16 caption boxes contain actual text bounds 49×11 and 30×11. Both image loads and TextFits are true. The mute target ends at y=178, leaving 39 pixels before the measured visible thumbstick glyph at y=217.
- **Touch input:** [native-phone-tap-evidence.json](native-phone-tap-evidence.json) records consumed rail taps with `processed=true`, maximum MoveDirection 0 and displacement 0. [native-phone-joystick.json](native-phone-joystick.json) then records a joystick gesture with `processed=false`, maximum MoveDirection 1 and displacement about 0.261 studs. This supports the deliberate choice to place active GUI controls within the stick's broader invisible activation area while keeping its visible glyph clear. It is evidence for these actual gestures, not every possible simultaneous-touch combination.
- **Copied mute on phone:** [native-phone-briefing.json](native-phone-briefing.json), [native-phone-mute.json](native-phone-mute.json) and [image](native-phone-mute.jpg) show the copy remains available during an actual briefing. Both labels change to UNMUTE, `ZyntraMuteDispatch=true`, and `ZyntraDispatchAudio.Volume=0`. Idle restoration is false/Volume1. Lobby music remains enabled; its pre-existing briefing ducking is distinct from dispatch muting.
- **Both desktop controls:** [native-desktop-original-mute.json](native-desktop-original-mute.json) and its [image](native-desktop-original-mute.jpg) show the original control produces true/Volume0 with both labels UNMUTE. [native-desktop-copy-unmute.json](native-desktop-copy-unmute.json) and its [image](native-desktop-copy-unmute.jpg) show the copy restores false/Volume1 and both labels MUTE while the briefing remains active. This confirms the two controls share the same setting.
- Root also saved native Shop/Upgrades opener captures. Upgrades retains the existing last-tab behavior; this change does not promise to force the Upgrades tab when the last tab was Shop.

## Boundaries and release disposition

The phone evidence is Studio device emulation, not a physical-phone certification. Native evidence covers the shown desktop/landscape layouts and ordinary taps; portrait, 52-pixel fallback, modal/round guards and pending recovery have focused source coverage rather than exhaustive physical-device trials. The earlier phone attempt to press the original mute after the briefing expired is not counted as a successful click. No purchase, new live DataStore/rejoin guarantee, gameplay completion or new DEV/ESP release is claimed.

Root reports temporary input observers disconnected and the mute preference restored to false. Root owns the final stopped-Edit compile/source audit and publication. This review authorizes the exact reviewed scope once that ordinary final verification is clean; it does not claim publication already occurred.

Review method: independent source/inverse/host verification plus direct inspection of saved native images and measurements. Impeccable's layout, legibility and task-fit criteria informed the bounded visual pass; no broad web audit, new UI harness, or production mutation was performed. Questions skipped: the latest user requirements and the bounded release criteria were already explicit.
