# Claude-only Trello follow-up — 16 September 2026

## New direct owner instructions — override older handoffs

The owner requests the new Trello work to be completed ONLY by Claude. Codex MUST NOT take over code, implementation, integration or fixes if Claude hits a usage limit. Wait for the limit reset and then resume Claude. Codex may generate, validate and upload required images, provide asset IDs/handoff documentation, coordinate through the native Claude UI, and check status no more often than every ten minutes. Claude remains manager and quality reviewer, using Opus 5 coding agents as previously requested. Do not spend usage credits or upgrade the subscription.

LEAVE THE PC ON. Do not shut down, suspend or schedule shutdown. Ignore historical shutdown/takeover instructions in earlier artifacts. They have been superseded.

## Baseline and ownership

Repository: G:\Roblox\MongoTV. Main commit 2c60cf3, published place version 1920, place 131311258779917 / universe 10559217407. The previous batch is COMPLETE; do not resume its unfinished-looking agent logs. Read artifacts/trello-20260916/final-release.md for what Codex finished after the previous limit. Tracked tree was clean when this follow-up began. Other tasks may edit Studio: inspect live drift before writing and preserve unrelated changes.

Claude owns all game source, Studio implementation, testing, final publication and focused local commit. Codex owns only new image files/asset receipts and this coordination directory. Asset upload alone does not transfer Studio source ownership. Do not overwrite or rerun the historical CSV import (completed v1906, removed before v1907). Gift already delivered.

## Authorized new cards

### #103 — real Lucky Wheel and dedicated side button

https://trello.com/c/rZC8cJHy

Make the Lucky Wheel an actual visible spinning wheel with its own side button. Codex supplies a generated button image through assets-handoff.md. Keep the existing daily spin and all reward/persistence semantics. Five existing rewards and displayed true odds remain: 1 token 45%, 3 tokens 20%, 1 Speed Potion 20%, 2 Speed Potions 5%, 1 Entity Shield 10%. The server-selected persisted result must determine the wheel's final sector. Never choose a separate client result. No paid spins or rerolls. Any equal-sized sectors must not imply equal odds: keep actual odds clearly visible. Square side-button container matches the surrounding HUD; a round wheel symbol inside it is appropriate.

### #104 — standalone Daily Rewards UI and separate side button

https://trello.com/c/EnbSc9ak

Give Daily Rewards its own standalone UI and side button, separate from Lucky Wheel. Preserve saved daily active playtime, claims and milestones (5 min -> 1 token, 15 min -> 1 Speed Potion, 35 min -> 1 Entity Shield). Existing progression and claim behavior must continue to work. Avoid duplicate reward pages, modal overlap, stale listeners or double requests. Codex is providing a matching generated icon.

### #105 — much larger floating hologram shop

https://trello.com/c/IA6VOViX

Replace the old shop presentation with a much larger shop of floating hologram product boxes. Walking onto an invisible pressure-plate trigger automatically opens that product's purchase UI. Remove the visible Inspect interaction. Opening a product panel never purchases anything: the player explicitly chooses Buy. Preserve product IDs, prices, inventories, ownership and purchase flow. Handle trigger debounce, product switching and exiting the area without reopening loops. Keep navigation/queue access clear. Reuse the existing uploaded product art; hologram styling and geometry are Claude's work. Request additional specific images in asset-requests.md only if existing art is insufficient.

## Execution and QA

Start from the current post-v1920 code, with separate agent file ownership. Read CLAUDE.md, README release requirements and source-sync tools. Use UpdateSourceAsync for Studio source writes, targeted pushes only after review, audit and parity checks. Do not pull over pending local work. Adapt rather than rebuilding reward server logic unnecessarily.

Manager performs final code review and native desktop/phone portrait/landscape QA: independent buttons, wheel spin/landing/result/disabled-day state, claim availability/state, close/reopen, hidden/modals, input hit areas, loading/in-round transitions, auto-shop trigger/Buy distinction, clipping and world clearance. Run meaningful relevant suites, whole-place compile, final source audit/parity. The old broad UI harness has documented fixture issues; investigate actual regressions without claiming it was previously all green.

The owner already authorized publishing validated completed Trello work to the same experience. Claude must finish implementation, QA, publish, verify actual published version through an authoritative result, save full .rbxl backup, document results/limits and update the three Trello cards only when actually complete. Preserve the owner's exclusions: #16 skipped; no console/controller QA, no 50% sale, no Discord, no new Level2 sounds, no Ideas or Before big adsspend work. No new incentive scope without an owner proposal/approval.

Persist claude-status.md and claude-handoff.md in THIS follow-up directory at meaningful checkpoints with agent ownership, changed files, tests, exact next step and published state. At a limit stop and retain the checkpoint. Codex waits for reset and resumes you; it must not implement. Resume automatically at reset only under this current scope. Never resume obsolete v1907 instructions.
