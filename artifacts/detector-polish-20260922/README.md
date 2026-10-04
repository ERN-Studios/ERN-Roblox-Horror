# Detector polish — 22 September 2026

Trello: https://trello.com/c/bn2zeKKO
Baseline: origin/claude/trello-20260921 at 7587b58, all 156 Studio scripts matching. Only three runtime scripts changed. Other developer work preserved. Studio place 131311258779917 / universe 10559217407.

## Delivered

- Shared 3D detector housing, raised rubber grip ribs, cylindrical antenna and brass collar. Generated graphite/brass face artwork matches the existing box illustration. Uploaded image 94042368093581. Source image and exact built-in imagegen prompt are in assets/detector/.
- Live display with blue SAFE DISTANCE, yellow ENTITY NEARBY and red ENTITY VERY CLOSE. Active band is highlighted; compact screens show a two-line meaning, with an additional readable scan caption/countdown.
- Detector renders in a dedicated local ViewportFrame above ordinary game HUDs, with a projected live screen overlay. Important modals suppress the live readout. No physical replicated tool or entitlement changes.
- Free shop demo has its own clear stage, automatically visits all three readings, and provides explicit selectable colour buttons. Clearly labelled simulation, never a live scan or purchase. Closing restores the product card; leaving the shop, starting a round, another modal, character replacement or script destruction cleans it up.
- Existing server sensing, 120/50 distance thresholds, four-second reading, twenty-second cooldown, purchase flow and analytics entry point preserved.

## Verification

- All three changed scripts compile; git diff --check passes. Final exact byte/hash comparison: 156/156 Studio and repository sources; all editor/source pairs identical.
- Native Play + UI activation: TRY DEMO opens; BLUE and YELLOW selection update display; automatic HIGH reached; X removes demo and restores shop.
- Desktop, iPhone 7 landscape, iPhone 17 Pro portrait, iPad 10th generation landscape inspected. Final phone/tablet/portrait readouts have zero TextFits failures; buttons are at least 44px high. Portrait footer was enlarged after finding a real overflow. These are Studio simulations, not physical-device tests.
- Controlled server fixture through the real detector RemoteEvent: target at 80 studs => MEDIUM; target at 35 => HIGH. Four-second expiry removes readout and sound. Repeated scan during cooldown leaves deadline unchanged. See validation.json. A separate 90-second presentation-only payload was used for the screenshot; production timing was not changed.
- Demo leaves ownership, live reading and cooldown untouched. Round-start and other-modal cleanup passed. Final console showed no new errors. No real purchase, production rejoin or full multiplayer round performed.
- Play stopped, temporary fixture removed, simulator read back as default / LandscapeLeft.

## Backup and release

Native before and final rbxl files retained here. Source-before.json preserves the exact three edited baseline scripts. Full native final backup recorded with hash in studio-sync-manifest.json.
Published successfully at 2026-09-22 07:51:26 UTC as v1976; receipt in publish-log.txt. No running servers restarted. The publication includes the existing Studio state from the other developer; this task's diff is limited to the detector presentation.
