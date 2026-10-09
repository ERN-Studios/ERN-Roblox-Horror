# Native feature QA — 16 September 2026

Fresh Studio Play, persistent DataStores disabled by the production IsStudio branch. These are in-memory tests, not live purchases or proof of production rejoin persistence.

## Verified

- All five new image assets returned ContentProvider AssetFetchStatus.Success. Both supply icons additionally reported ImageLabel.IsLoaded=true and rendered in the actual UI.
- New terminal viewed at ~899x679: spacious list/detail Shop, separate Rewards and Notes tabs. Square HUD shop button matches neighbours (64x64, radius7).
- Real Rewards button free spin: initial35 tokens ->36; server recorded Token1, WheelDay2026-09-16, Serial1. Animation finished with YOU RECEIVED:1 Research Token and disabled SPUN TODAY. All five prize rows/actual odds and 5/15/35-minute milestones rendered. Premature claims visibly disabled.
- Real Upgrades buy buttons: 3 tokens ->1 SpeedPotion (36->33); 2 tokens ->3 RouteMarkers (33->31).
- Standing on the physical SpeedPotion plate opened its correctly named art/description/stock/token-price card. Actual purchase button spent3 tokens and increased potions1->2 (31->28). No Robux prompt. New physical shop seen with six animated product displays, rewards stand and adjacent supply kiosk.
- Full isolated UIRegression: terminal1657checks/0failures after Notes low-screen fix. Entire harness2799checks/21failures; no claim of a fully green old harness. Seven briefing expectations conflict with unchanged lobby behavior; objectives fixture forces an overlapping MissionBrief toggle; eleven L1 rows measure hidden counters from an inactive lobby fixture; existing568x320 detector copy overflow and intermittent control-zone Changed expectation remain. Need actual-round L1/mobile inspection before final assessment.

## Actual Level 1 round and input

- A fresh real station-1 queue reached READY and RoundActive=true. Power Restoration objectives and Mission Brief rendered correctly. H opened all four Level 1 steps plus threat protocol. This verifies the production path behind the inactive-lobby fixture's eleven hidden-counter failures.
- T consumed exactly one SpeedPotion (2->1), published multiplier1.1 and a six-second expiry, and changed actual Humanoid.WalkSpeed16->17.6. Speed returned to16; another T left inventory1 and UsedThisRound=true.
- X consumed one marker (3->2), created an owned visible RouteMarker and reported1/3 active. Movement changed Daily.Accruing totrue; profile showed90 earned seconds. Offline fault tests separately cover persistence/retry accounting.
- A naturally placed, path-tested Field Note at(-180,1.6,-228) rendered its E prompt. Real E hold discovered L1-01, collectionCount1/12.
- L held0.45seconds left InRound=true and immediately reset progress0. L held1.9seconds returned the player to the lobby through the real server handler. RoundActive=false; all markers/notes cleared; potion round latch reset.
- Donation board's ten rows expose separate rank/name/Robux columns atx12/72/408, widths44/324/140, with16px/12px gaps. No historical-purchase footer. Runtime empty-data text fits its name column. Offline tests additionally exercise long names and nonempty amounts.

RoundCompletion398/0, Level3 configuration/layout/navigation checks, fresh Level2 worlds101 and303 passed five exit geometry suites each. native-server-release.json contains full evidence. Final native compile141/141, audit141matched/0drift and parity140exact+1permitted passed after the last mobile fix and preservation of existing Studio donation changes.

## Input test API

Roblox's supported test input API is documented at https://create.roblox.com/docs/reference/engine/classes/VirtualInput . CreateVirtualInput succeeded in Client MCP. No Windows input helper or security settings are changed.

## Mobile emulator and final correction

- Actual iPhone13 Studio emulator, TouchEnabled=true: rendered viewport749x368 landscape and389x762 portrait. Shop, Rewards and Notes fit their safe areas; real touch dragging scrolls Rewards to its FREE SPIN. Touch spin awarded3tokens (35->38), Token3/Serial1, then SPUN TODAY. Portrait showed all five odds and the outcome.
- Real portrait round exposed an overlap between the Level1 objective, Mission Brief and Leave chip. Corrected RoundUI to place Mission Brief below the measured objective when they cannot fit beside each other. Leave now reserves actual visible objective/brief rectangles for all three levels, updates when their size/visibility changes, and keeps its desktop placement. Added five geometry/resize checks to the existing full-script hold suite;299 checks passed.
- Fresh real portrait round after correction: objective(81,8,300,106), brief(24,122,168,44), leave(24,174,164,44), exact8px gaps. Native screenshot confirms readable separate controls. Brief opened and closed normally.
- Emulator test input was captured on LeaveChip.InputBegan as Touch (not guessed from device mode). A0.45second touch released without leaving and resetfill0; a1.9second touch completed the real server return.
- MCP instance-targeted mouse coordinates omit the58px inset on this emulator; corrected test coordinates explicitly added GuiService.GetGuiInset. The first attempted short hold opened Mission Brief and is NOT counted as a Leave test.

Leave the PC ON when finished. No shutdown.
