# Claude handoff — follow-up #103/#104/#105 (living document)

> Clock note: the section times below after "11:10 UTC" were written from memory and run ahead of
> the wall clock (the desktop-grant retry, the commit and this note happened at 12:06 UTC by
> `date -u`). The ORDER of events is exact; treat the later stamps as approximate.

Resume point for a new Claude session (Codex does not implement). `claude-status.md` = live
agent table; `claude-contracts.md` = the interface every agent builds against.

## Milestone 0 (11:12 UTC) — batch launched
- Baseline verified: git 2c60cf3 clean, Studio 141/141 match, v1920 published.
- Codex icons ready: wheel 111918608092047, rewards 85423575361057 (assets-handoff.md).
- Four Opus 5 agents with exclusive file ownership; reports land at agent-<id>-report.md.

## Milestone 1 (12:08 UTC) — three of four agents landed, Studio holds the rail + both modals
- Reviewed + accepted: A-WHEEL (433 checks, after the arm-pivot fix), A-DAILY (439 + 280),
  A-RAIL (520). A-HOLO (#105) still running.
- In Studio: `Lucky Wheel Client` and `Daily Rewards Client` created (installer, byte-verified);
  ZyntraStore, UIDevice, UIRegression, ZyntraDailyRewardsPage pushed (backup
  `.studio-push-backups/20260916-113630`). Manifest 143 scripts / 157 items; the only pending
  entries are A-HOLO's LobbyShopDisplay + Shop Display Client (in flight, do NOT push yet).
- Native QA of #103/#104 is being run in a Play session through the rail buttons
  (`user_mouse_input` instance_path) with `screen_capture` + console evidence.

## Milestone 2 (12:30 UTC) — all four agents landed and pushed; Studio == working copy
- Accepted: A-HOLO (#105, 802 checks). Lead fix in ZyntraStore: SHOPS/UPGRADES openers stand
  down under any other screen-owning modal; toggleMain/openKioskShop refuse to open over one.
- Pushed: ZyntraStore (patched), LobbyShopDisplay, Shop Display Client (backup
  `.studio-push-backups/20260916-114126`). Manifest 143 scripts / 157 items, 0 pending.
- Offline compile 143/143; 24-suite sweep green (numbers in claude-status.md).
- Native QA done: #103 wheel (spin -> 1 Speed Potion, landed in its sector, SPUN TODAY, parked on
  reopen), #104 modal (locked milestones, countdown, no spin button, tabs without Rewards).
- Remaining: native #105 walk-through (auto-open on plate, switch, close, BUY explicit, plaque
  prompt -> Daily Rewards), phone emulator pass for all three, parity probe + audit, Trello,
  publish, backup, commit.

## Milestone 3 (13:08 UTC) — native + synthetic phone QA done; waiting on Fix 2 and the desktop grant
- Native desktop QA (Studio Play, 899x677) passed for #103, #104, #105 and the modal exclusion;
  synthetic phone pass (UIRegressionViewport + ForceTouchUI at 390x844 / 844x390 / 705x338)
  passed the fit rules. Evidence and numbers: claude-status.md 12:15-13:05 sections and the
  Studio captures ScreenCapture_wheel_open/_landed/_daily_open/_holo_frontage/_holo_card.
- Open: A-WHEEL Fix 2 (SPIN/SKIP pinned to the panel footer on touch) -> re-review, push,
  re-measure at 844x390. Then parity probe + audit, focused commit, Trello, publish, backup.
- Desktop control (device emulator, File -> Publish, Save As) needs the owner's approval of
  the computer-use grant; Codex has asked the owner. Claude does not bypass it and keeps the
  native QA/publish itself.

## Milestone 4 (12:06 UTC by the wall clock) — code complete, Studio == repo, committed; BLOCKED on the desktop grant
- Fix 2 accepted (530 checks) and pushed; landscape re-measured; parity OK (142 exact + 1
  permitted); audit 143/143; console clean in every Play session.
- Focused local commit made on main (see `git log -1`); NOT pushed to origin; nothing published.
- What is left and why it is blocked: the Studio Device Emulator pass (real iPhone rendering of
  the two modals, the rail and the shop card), File -> Publish to Roblox, the published-version
  verification and the .rbxl backup all need the Studio window, i.e. the computer-use grant
  for "Roblox Studio". `request_access` was denied twice (12:52 and 13:32 UTC). The owner has
  been asked (via Codex) to approve it in Claude; Claude waits and does not bypass it.
- When the grant arrives, in this order: (1) Studio Test tab -> Device -> iPhone (portrait +
  landscape): Play, open Wheel/Rewards from the rail, walk onto a hologram plate, screenshot;
  (2) stop Play, File -> Publish to Roblox (same experience), read the new version from the
  Output/Creator Dashboard; (3) File -> Save to File As -> _local/trello-20260916-followup/
  BACKROOMS-published-v<N>.rbxl; (4) update Trello #103/#104/#105 with the verified version
  (trelloWriteCard, ARIs in trello-scope.json); (5) a second small commit with the release
  receipt; (6) leave the PC on.

## Exact next steps
1. As agents land: read report, `git diff` their files, run their tests + the suites that load
   the same files, `luau-compile.exe --binary` every touched .lua.
2. Reconcile names against claude-contracts.md (bindables, attributes, button names).
3. Studio: `pull --audit` (expect 0 drift), create the two NEW LocalScripts with
   `python tools/install_new_scripts.py <mirror path>`, then `record_pending_push.py` and
   `push_repo_to_studio.py --file <path>` per reviewed file; offline compile loop over the
   mirror (the MCP compile probe is sandbox-blocked; Codex/owner can run
   tools/studio_compile_probe.luau from the command bar); `pull --audit` = 0 drift;
   `verify_studio_parity.py`.
4. Native QA in Play: desktop + phone portrait/landscape (device emulator): five rail buttons,
   wheel open/spin/land/result/spun-today, rewards open/claim states/close/reopen, modal
   exclusivity (terminal vs wheel vs rewards vs queue), in-round transition closes modals,
   hologram shop auto-open/switch/close/BUY-only, world clearance, no INSPECT prompts.
5. Release checks (README "Before the next publish") + publish to the same experience, verify
   the published version (Creator Dashboard / PlaceVersion), save the .rbxl backup under
   _local/, update the three Trello cards, commit the focused change.

## If this session dies
Working copy is the truth (`git status`); nothing committed; Studio untouched until step 3.
