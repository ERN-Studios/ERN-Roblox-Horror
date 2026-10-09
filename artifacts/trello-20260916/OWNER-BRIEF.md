# Owner-authorized continuation — 16 September 2026

LATEST OWNER OVERRIDE: Leave the PC ON when finished. Do not shut down, suspend or schedule shutdown. Work is now complete and published as v1920; see final-release.md. The assignments below are historical context; do not restart Claude.
Working repo G:\Roblox\MongoTV, main HEAD aa40f70 (prior baseline1b33c03). Published v1907. Read CLAUDE.md and prior artifacts/trello-20260915/FINAL-STATUS.md as history. The owner's newest direct message supersedes yesterday's proposal-only scope.

## Manager / work arrangement
You are Fable5.1 manager and QA reviewer in Claude desktop. Use Opus5 coding agents as explicitly requested, separate file ownership and evidence-based QA. Heavy lifting is yours. Codex handles native Level3 character animation authoring/import, needed generated textures and final oversight. Your code agents may work alongside Codex's Studio animation tests but DO NOT operate Studio until coordination grants it. No git commits/push by you: Codex consolidates after release. Persist claude-status.md and claude-handoff.md in artifacts/trello-20260916 at meaningful milestones; record exact files/tests/model/Studio ownership. Codex only checks your status every10minutes. At limit persist checkpoint and stop; Codex takes over. Do not depend on frequent replies.
Maintain a clear shared-coordination.md listing ownership and completion. Initially Studio owned by Codex. Codex owns tools/assets for table animation and Level3 hiding/config integration; avoid those files unless assigned. You own all other authorized feature code, including ZyntraMonetization/ZyntraConfig/Sprint/UI/Builder, and tests.

## Direct owner decisions
- Reject Flashlight Casings. Results Frame explained as cosmetic results border and excluded from this implementation.
- Lucky wheel can award Speed Potion and Entity Shield as well as tokens.
- Rest of proposals approved: Daily Rewards tab and progressive playtime, free daily wheel, Route Marker Pack, Speed Potion, Field Notes collection, hold-key PC/hold-button mobile for Back to Lobby.
- Shop HUD button must return to square like adjacent buttons. Prior circular treatment came from #88; owner's newest correction wins.
- #16 skip. Do not perform cross-server2–6-player QA or use it to block completion.
- New active Trello #100 and #101 included; snapshot beside this file.
- Level3 hide animation must match the game's actual character, only the tucked hiding pose/hold. Codex is rebuilding/verifying it visually using real character; no entry/exit cinematic.
- Continue existing exclusions: NO 50% sale/pricing changes, NO Discord, NO new Level2 sounds, NO console/controller QA, NO Ideas/Before big adsspend work.
- CSV import is COMPLETE. Never reapply, regenerate or publish private source; no changes to historical support totals or receipt semantics.
- On finished validated work publish to same game, then Codex saves backup/reports. LEAVE THE PC ON, per the latest direct owner instruction.

## Concrete scope
### #83/#84/#89: rewards
One polished DAILY REWARDS tab matching Objectives/Mission Brief (shared UIStyle); same content reachable at physical shop terminal. FREE one spin/calendar day, no Robux/token spins/rerolls/tickets, visible honest reward odds, UTC day boundary with local countdown, skip/reduced-flashing animation, server commits outcome BEFORE animation. Loss/rejoin/retry/midnight/concurrency/replay cannot grant twice. Reuse existing durable profile transactions, do not add a competing datastore/session writer. UI must show actual saved availability/claim, recover request failure, fit phone portrait/landscape and desktop.
Daily active-round playtime persists across sessions. No lobby or spectate credit; legitimate hiding and brief inactivity count, long AFK pauses without losing earned time. Milestones5/15/35minutes, one each/day.
Codex asked owner optional balancing clarification at05:56UTC: proposal5min1token,15min1speedpotion,35min1shield; wheel70%1token,20%1potion,10%1shield. Numbers are a conservative working assumption under approved feature scope, not a claim of an explicit numeric answer. Check owner-answers.md for reply before finalizing, and make these constants easy to tune. Do not implement rejected cosmetic stamp/casing/frame reward branches.
Shield rewards add one existing stored shield charge, never autoactivate or spend tokens. Potion rewards add one stored consumable.

### #85/#88: actual usable items
Route Marker Pack2tokens gives3 direction markers, max3active/player, visible to team in their current round, removed at round end. Direction is player-chosen, not automatic solution. Server authorizes placement/round/distance/rate, no remote arbitrary parenting/CFrame exploit. Durable spend/grant, consume uses correctly; death/leave semantics documented. Native touch/PC usable.
Speed Potion3tokens each, stored consumable, +10% movement speed6seconds, maxone per round, no stacking, no extra stamina. Integrate with existing sprint/crouch/hiding/stun/server controls rather than competing WalkSpeed loops. Must not restore stale WalkSpeed on death/respawn/level change or defeat restricted movement. Test all3levels' movement constraints and entity chase balance; no invulnerability/teleport effects. Wheel/playtime reward uses same item.
Do not add new Robux products or new sale/pricing. Existing shop transaction mechanisms remain intact.
Field Notes: one optional new discovery per round adds illustration/text to a persistent collection; use reachable existing routes in supported L1–3, never gate exit. Clear discover/collection UI; completion gives a cosmetic title (not casing/frame), no stat effect. Modest finite initial collection, transparent progress; choose readable Zyntra facility notes. Author original short fictional text, no unsupported lore claims about real people. No need for external research or monetization service. Ask Codex for any required artwork with concrete asset dimensions/use, otherwise use coherent clean in-game typography/icons.

### #74 Back to Lobby
1.5s hold PC key and touch button, visible progress + release cancels, no mouse unlock workaround. Inspect bindings and choose truly unused key, show it in UI. Block/reset on typing/chat/modal, focus loss, death/respawn/round transitions; at most one request. Reuse authoritative RoundExit/lobby transport/error flow. Explain leaving current round, no fake pausing. QA click/tap alone doesnotleave, successfulhold, canceledhold, UI interactions, failure/retry and mobile safeareas.

### #100 board columns
Remove INCLUDES VERIFIED HISTORICAL PURCHASES footer. Separate consistently aligned rank, player name, Robux columns with spacing, truncate long names safely, stable right alignment of amounts. Preserve value bindings/history/refresh, actual native text bounds and visual inspection.

### #101 Shield HUD
Match Objective UI type/spacing/colors/panel, clear name/remainingcharges/key. Avoid clutter/overlap, mobile accessible activation, shared style. Coordinate with potion UI so inventory actions feel consistent and do not crowd touch controls.

## Evidence / release
### NEW #102 (owner added at06:00UTC)
Research and redesign current in-game shop to be MUCH larger and higher quality.
Card https://trello.com/c/32xgCdtM : "Make the current in-game shop significantly
larger and improve its overall quality. Research good shop designs and layouts
first, then use the findings to redesign and implement a polished, easy-to-use
shop." Include the physical wall shop and make browsing details more spacious
on desktop while preserving readable, reachable mobile layout. Inspect actual
lobby wall/gate clearance before resizing; preserve all queues and paths.
Do actual focused external research, cite primary sources in shop-research.md,
then implement under this explicit card authorization. No new unapproved items
or monetization beyond scope. Give Codex concrete texture requests promptly if
new artwork is needed. Coordinate Builder ownership with #100.

Use meaningful tests for atomic claims, replay/concurrency/save failure, inventory spend/consume, dayroll/AFK, movement restore and regression; do not count static string-matching as runtime proof. Native Studio real rendered UI and gameplay tests required after Codex releases ownership. Required texture references cannot remain placeholders or invented asset IDs. Compile/source parity, no temporary dev grants or test scripts in Edit. Publish only after shared release checklist is fulfilled; report exact version and verification. Existing secrets/private CSV remain ignored. Persist enough that Codex can take over immediately.
