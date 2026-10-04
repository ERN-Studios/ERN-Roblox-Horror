# Remaining approved Trello work — 2026-09-20

Published to place 131311258779917 (universe 10559217407) as **v1947**, confirmed by Studio at 17:07:56 UTC. The owner's preceding re-entry publication was v1942. No live servers were restarted.

## Delivered behavior

- [Slide transition](https://trello.com/c/xIjizflN): Level 2 exit flume walls grow from 0.60 to 0.90 studs and legacy exit panels from 0.72 to 1.08, outward to preserve the bore. Level 3 continuation shell grows from 0.30 to 0.45; runout from 0.60 to 0.90. Segment overlap is one stud. Atomic streaming plus all 672 collidable panels and three floor probes gate readiness. A shared geometry guard rescues fast ragdolls inside the bore while leaving the mouth open. The owning client corrects its own character; the server fallback handles server-owned assemblies, avoiding opposing network corrections.
- [Mall Manager](https://trello.com/c/DYnBEZHk): Level **3**, despite the original card title. Inspection previously called FlushAnchor and moved hidden occupants outside. Inspection now preserves hidden occupants and respects its cooldown; voluntary exit, death and teardown still restore character state.
- [Product preview](https://trello.com/c/UNRk7Qy8): existing normal/focused torch demo followed by hazmat color preview, glowstick color preview on a sanitized avatar clone, and a clearly simulated detector demo. Descriptions state contents, consumption/duration and permanent access. Scrollable details and an above-controls portrait layout prevent clipping. Camera preview remains deferred until that product exists; the broad preview card remains partially complete.
- [Daily research](https://trello.com/c/wEFTmguQ): three personal, solo-capable, purchase-free goals: insert a Level 1 fuse (1 Research Token), activate a powered lever (1), and escape any level alive (2). Three UI cards show progression. Completion and token grant share the existing serialized profile UpdateAsync transaction; duplicate events/retries cannot award twice. The completion ledger persists under Daily.Research and resets with the existing daily system at 00:00 UTC. This is the approved first selection, not the later collectible/photo missions from the larger idea list.
- [Entity Detector](https://trello.com/c/Zyrtgu79): permanent game pass **1982715834**, verified on sale for **149 Robux**. Icon **134413710349950**. Server-authorized LOW/MEDIUM/HIGH snapshot, 60-stud range, HIGH within 22 studs, 20-second cooldown and four-second reading. Z, D-pad Left and a mobile SCAN button activate the handheld display and quiet local ping. It samples live Level 1/2/3 entities, excludes dead/despawned/inactive targets, and exposes a Level 4 tag adapter. No exact positions, continuous tracking or guaranteed safety. Free shop demo changes no inventory, balance or ownership.

## Verification

- All 20 changed/new runtime sources compile. All **154** live Source/editor buffers match repository UTF-8 bytes, verified by fresh byte lengths and djb2; SHA-256 hashes are recorded in studio-sync-manifest.json.
- Native geometry probe confirmed 672 panels, atomic model, new thicknesses, full readiness, rejection of a partial shell, inside-bore rescue and free mouth exit. Real generated Level 2 exit geometry has 0.90-stud walls; other slides remain 0.60.
- Final native player ride traversed the continuation and exited beyond the mouth alive (100 health), unanchored, out of PlatformStand. An earlier network correction conflict was found and corrected before that passing ride.
- Normal server Script reproduced table ejection: one occupant ejected, no longer hidden, moved 5.8856 studs. After the fix: zero ejected, still hidden, zero movement, normal exit restoration true.
- 15 research checks execute the actual pure module and extracted production daily normalization/reset logic: duplicate/retry safety, loaded-profile normalization, day boundary, reset once, invalid schema/keys and bounded rewards. Native server events (including duplicates) completed all three goals and increased the Studio profile from 35 to 41 tokens: four research plus two ordinary clear rewards.
- Detector sensing checked HIGH/MEDIUM/LOW, dead/despawned exclusion and the future-level adapter. Actual Z input produced a HIGH reading and local model; a second scan did not reset cooldown, and an unowned request was rejected. Mobile SCAN measured 56×56.
- Runtime preview checks verified LOW/MEDIUM/HIGH demo sequence, cleanup and unchanged balance; cosmetic clone had 18 parts and did not change the real avatar; advanced demo showed normal, focused and hazmat stages. A native click activated the actual mobile preview button.
- Visually inspected desktop, iPhone 17 Pro landscape/portrait and iPad Pro M5 simulations. ForceTouchUI was enabled only in Play to work around startup device-cache timing. Simulator returned to default after checks; no test fixtures or forced touch setting were saved in Edit. Final game console had no game-script errors.

## Limits

No real paid transaction, production DataStore outage/rejoin, physical-device session, multi-client Level 2→3 transition or three-player table scenario was run. Existing stateful modules were validated from ordinary temporary Scripts because MCP require has a separate cache. Native Play uses Studio profile fallback; persistence checks use actual normalization/transaction paths rather than claiming a production rejoin. Full Level 2 pump-two/pump-three spawn-distance, AI navigation/CPU/memory checks were not run in this change; those entity systems were not modified. The slide and hiding probes do not establish full multiplayer/performance coverage.

## Records

- remaining-trello-20260920.rbxl: complete native Edit backup of the final source and non-script state; 9,337,807 bytes; SHA-256 d2dbfed1b1d6c2c00b6b04caffe53ccada2bc02a65a14acf9c6e72fb6b370f1b.
- source-inventory.json: all 154 source/editor comparisons.
- studio-results.json and Luau probe files: actual scoped validation outputs and test inputs.
- research-tests.luau: repeatable 15-check suite.
- publish-log.txt: publication evidence. Its earlier 17:07:18 PublishSuccessful belongs to DownloadCopy; the publishType=1 request at 17:07:50 and success at 17:07:56 identify the real v1947 publication.
- All Studio source writes used exact complete Source/editor baseline comparisons and final readbacks. Other developers' unrelated source was preserved.

## Detector icon provenance

Generated with the built-in imagegen tool (new image, no reference input); visually inspected, copied to assets/shop/box-entity-detector.png and uploaded as the game-pass icon. In-game configuration uses its verified Roblox icon asset ID.

Final prompt:

> Use case: product-mockup. Square Roblox horror game shop product icon, 1024x1024. A chunky handheld industrial entity detector for the fictional Zyntra research brand: dark graphite rectangular body, small recessed black rectangular display with three bright horizontal signal bars in mint cyan, amber and red, short antenna on top left, single circular scan button below screen, subtle brass screw details. Three-quarter product view, strong silhouette, mint rim lighting, dark olive industrial background and worn yellow hazard-stripe border matching a Backrooms game supply crate. The device fills 75% of the frame, no person, no monster, no weapon, no map radar. Polished stylized 3D game art. Only text: small 'ZYNTRA' on device and large 'ENTITY DETECTOR' along bottom, clearly legible, no other text. Return saved local image path for project use.
