# Remaining real-device and published-server acceptance

This is a compact execution sheet for the open non-Level-4/5 Trello cards, not a substitute for test evidence. Use the latest **published** place version and record its Roblox publish receipt before starting. Use tester accounts, not a Studio-only simulation. Link screenshots/video, the place version, UTC time, device model/OS and observed result in each card.

On 24 September, the owner authorized a Roblox Player-only attempt. The Player opened the experience page, but its Play button did not start a session; no published-client flow was verified by that attempt. The owner's friend has an actionable checklist directly on [the physical phone/tablet card](https://trello.com/c/lUKD3R8G) and a separate checklist on [the controller card](https://trello.com/c/uI8hg2At). Those items remain unchecked until results are attached.

## Quick device checklist

- **Phone + tablet:** lobby guide absent; shop and all six standing suit previews/cards; equip a Token suit and rejoin; wheel/Daily tap targets, X and collect confirmation.
- **Phone + tablet, real Level 2:** record FPS, memory, load/pop-in and animation foot contact before spawn, at pump two, during a real pump-three chase and after exit; listen near/far for Pool Slide groans and cleanup.
- **Two accounts:** inspect False Sun particles from another player's view through equip, death and rejoin; verify Signal Architect on developer and ordinary accounts, including access removal in a safe test environment.
- **Physical controller:** kiosk → Settings → B, mission/mute, spectate, Level 2 disconnect/reconnect and switching between keyboard, controller and touch.
- Record the published version and each device/account result against the linked cards below. The multiplayer, persistence and purchase gates still need the separate published-server session.

## One phone + one tablet session

1. On both physical devices, open the lobby, shop, hazmat page, wheel, Daily Rewards and settings. Check tap targets, the standing 3D suit preview, six-sector wheel, prize dialog, close/X and collect confirmation. Equip a Token skin, leave and rejoin, and check the same suit appears on the player and in the shop. This covers [hazmat skins](https://trello.com/c/VSCGGIA9), [standing preview](https://trello.com/c/x4kKwPZx) and [wheel/Daily clarity](https://trello.com/c/25GLltY6).
   On one fresh and one returning account, confirm the lobby no longer shows `LEVEL 1 START HERE`, Field Notes or the lobby `TRY AGAIN` guide, including after death and return to lobby. This covers [guide removal](https://trello.com/c/PuuOYhmH).
2. Enter a real Level 2 round with the arch meshes active. Record device FPS and memory before entering, at the second pump/Pool Slide spawn, during the third-pump chase, and after the round ends. Check Pool Slide reach, animation/foot sliding and Pool Foam freeze when observed. Listen to the Pool Slide groans before spawn, at near/mid/far distance and through chase/reset; check direction, overlap and whether ambience resumes. This covers [render distance/arches](https://trello.com/c/Zpj0Gkbb), [Pool Slide](https://trello.com/c/rXhi1SZ8) and [Pool Slide sound](https://trello.com/c/LigItMHi). The arch card's server CPU and active chase already have evidence on the live card; do not repeat them merely to claim this mobile measurement.

   **Level 2 wall art is a separate gate:** published v2083 contains the removal of the two rejected decals ([receipt](../artifacts/publish-v2083-20260924/README.md)). Check visually that they are absent; do not judge or test replacement wall art yet, because no replacement has been selected. [Wall-depth card](https://trello.com/c/DDqjXkyU) stays open.

3. If the False Sun skin is available on a tester account, inspect its motes in the standing shop preview and on a character seen by another client; equip/unequip it, die and rejoin. Verify the particles remain cosmetic, visible but sparse, disappear when the visual is removed, and never leave native body parts hidden. Note FPS/memory before/after. This covers [skin VFX](https://trello.com/c/IRLeRBcN).
4. With one developer-allowed account and one ordinary account, verify Signal Architect appears/equips only for the developer, replicates cosmetically to the ordinary viewer, survives legitimate rejoin, and cannot be unlocked by Token, wheel, Robux or a forged equip request. Revoke developer access in a safe test environment and verify unequip/ownership cleanup. This covers [developer suit](https://trello.com/c/SYUaXHKQ).

## Controller session

With a physical controller, test kiosk → Settings → B, mission and mute buttons, multi-target spectate, controller disconnect/reconnect in Level 2, keyboard/controller switching and comparison with touch targets. Record every input/result, not just the final screenshot. This closes the device gate on [controller](https://trello.com/c/uI8hg2At).

## Published multiplayer and persistence session

1. Use 2–6 distinct tester accounts in a published server. Queue Level 2→3, include one late arrival and one rejoin, then die/retry. Record whether every client gets a loading cover and reaches the correct round; capture server/MemoryStore errors. This covers [loading/teleport](https://trello.com/c/DIktjy8U) and the multiplayer side of [Pool Slide](https://trello.com/c/rXhi1SZ8).
2. Complete a level, leave and rejoin on a new server. Confirm the clear, record, earned Tokens and badge are each granted **once**, including after a simulated uncertain DataStore write only in a safe test environment. This covers [completion-save](https://trello.com/c/EYpXKa9S) and [challenges/records](https://trello.com/c/FnF49TWk).
   Buy consecutive stamina and flashlight levels, checking each quoted price increases by one Token, unaffordable controls stay disabled, and owned levels persist after rejoin. This covers [upgrade costs](https://trello.com/c/KF7FDmP1) after the owner approves the ladder.
3. Use separate test accounts for each Token Earner direct tier and upgrade path. Buy only after the passes are enabled and the published server code checks prerequisites. Compare earned gameplay, Daily and wheel grants to the unboosted base; verify existing balance, purchased Token packs, admin grants and refunds are unchanged; leave/rejoin and repeat. This covers [Token Earner](https://trello.com/c/EtdsUM4e). Real Robux spending should use the smallest necessary tester matrix and retain transaction IDs.
4. Around a real UTC daily rollover, attempt a wheel/Daily claim before and after, plus a rejoin and a duplicate tap. Record exactly one payout per eligibility window and the displayed reward. This covers [wheel/Daily clarity](https://trello.com/c/25GLltY6). Do not time-warp production DataStores or infer rollover from one saved snapshot.

The [challenge/record card](https://trello.com/c/FnF49TWk) also awaits real player time data no earlier than **29 September 2026** for final time-goal tuning. The owner dropped the research-evidence challenge on 24 September; it is not an acceptance gate. A simulator, source review or unpublished Studio round cannot replace any physical or published-server acceptance above.
