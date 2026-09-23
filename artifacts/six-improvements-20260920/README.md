# Six improvements — published 2026-09-20

Published to place 131311258779917 / universe 10559217407 as **v1937** at 13:29:52 UTC.
Studio log explicitly reports `Place published` and `PublishSuccessful`; the open Edit model still reports its original loaded PlaceVersion 1933. No active servers were restarted.

## Shipped behavior

- Speed Potion: 1.30 multiplier (+30%), same six-second duration, one-per-round rule and price.
- Lobby: teal/gold SUPPLIES & UPGRADES sign above the existing wall shop.
- Level 1: exit navigation uses the safe upper-right corner. Owner feedback reduced phones to 190×72 and tablets to 220×80, with EXIT / FOLLOW ARROW copy. Desktop retains 310×116.
- Team progress: server-owned actor usernames and actions for Level 1 fuse/box/lever steps, Level 2 pumps and Level 3 CD collection/recovery/insertion. Only InRound recipients; client also checks level and monotonic serial. Up to three recent desktop messages, latest message on touch.
- Advanced Equipment: existing pass 1945402536 includes switchable focused light (+45% range, narrower cone, unchanged battery drain). Keyboard Y, gamepad R3, touch hold; F/RB/short tap remains on/off. Existing benefits/grants remain unchanged. Local six-second wide/focused demo on its existing shop card; step off the plate to close.
- Expedition Pack: developer product **3713829859**, **69 Robux**, on sale, managed pricing disabled. One stored re-entry credit, one Entity Shield charge, three Route Markers. Added to existing terminal and hologram shop. Atomic receipt transaction; no auto re-entry, no permanent pass.

## Validation and exact limits

- All 147 Studio scripts match local UTF-8 bytes, byte length/djb2 and ScriptEditorService editor source. Inventory includes disabled/run-context properties. 149 repository Lua files compiled successfully, including retained files outside the active Studio inventory.
- 299 receipt checks passed against production receipt code with mocked persistence: bundle grants, receipt replay, rejoin, atomic overflow refusal, concurrent inventory changes, and write failures before/after commit.
- 249 flashlight input/lifecycle checks passed against production control sections/server code with mocked Roblox services, including owner/non-owner checks, keyboard/gamepad/touch hold/tap, round exit, death, hiding, battery, and replicated beam state.
- Native Studio Play: sign and bundle display present; six-second demo measured wide core/spill 38/45 studs then focused 55.1/65.25, then removed. Non-owner focus request rejected. Focused own lights measured 55.1/65.25 with narrower angles. Native emulated short touch switched the light on.
- Device Simulator: iPhone 17 Pro landscape/portrait, iPad Pro M5 13-inch landscape. Compact exit positions/sizes and TextFits measured; native iPhone screenshot inspected. Long-username team message fitted without colliding with the compact exit panel. Final short-copy heartbeat change was compiled and source-readback checked.
- Device simulation was stopped and Studio returned to default viewport.
- Creator Dashboard save and live MarketplaceService:GetProductInfoAsync confirmed product name, IsForSale=true and PriceInRobux=69.
- This was focused Studio UI/input QA, **not** full multiplayer rounds, a physical phone/gamepad run, a live paid purchase or live persistent-inventory rejoin. Touch long-hold behavior was covered by the input harness; the simulator automation did not reliably deliver a held touch to the target.
- One discarded QA fixture set RoundActive without generating a maze, causing the existing PuzzleManager to report missing fuse-box positions. The fixture was stopped; a clean subsequent Play session and UI-only fixture had no such error. No fixture attributes or temporary listeners were written to Edit.

## Preservation

Started from the audited Studio v1933 mirror in f3b892386e6927e0eefaa9a22f1c895f98feffa7 (audit PR #2). Each write checked live Source/editor and used UpdateSourceAsync with an exact expected-source comparison. Thirteen scripts changed and two new scripts were added; no bulk deployment occurred.

The complete native `six-improvements.rbxl` is the verified Edit model immediately before publication. The previous v1933 native backup remains in `artifacts/studio-audit-20260920/`. See `source-inventory.json`, `validation.json` and `publish-log.txt` for evidence. No unrelated developer changes were overwritten.
