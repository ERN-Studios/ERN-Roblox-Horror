# Wheel / Shop / Rewards / Friend Boost refresh — status (Claude, manager)

Clock: stamps are the Windows clock; local = UTC + 2.

## 20:55 UTC — round started
- Owner brief read (CLAUDE-PROMPT.md, REWARDS-ASSETS.md). Baseline git `86c675d`; Studio == repo
  (parity OK 20:20 UTC). The previous follow-up (#103/#104/#105) is in Studio and the repo but NOT
  published yet (public "updated" still 18:16 UTC); the owner publishes once after this round.
- Lobby measured in a Play session (Server datamodel): builder centre (0, 30, -760) abs; right
  wall face x 32.9; ledge top y 30.65 (rel 0.65), x 16.8..33.2; Level 2 gate posts abs z -849.8 /
  -830.2, Level 4 posts abs z -769.8 / -750.2 → usable wall rel z -69.45..-10.55 (58.9 studs).
  Kiosk `ZyntraSupplyKiosk` abs c (27,36,-795) 13.3x12.6x20 is what "the old shop/terminal" is.
- Wheel texture orientation checked on the PNG: Token1 centred at 12 o'clock, then clockwise
  Token3, Potion1, Potion2, Shield1; equal 72-degree fields.
- Contracts written: claude-contracts.md. Four Opus 5 agents launched in parallel with disjoint
  file ownership: A-WHEEL, A-DAILY, A-SHOP, A-FRIEND (see the contract's owner table).
- Asset preload probe in Studio (Edit datamodel, ContentProvider:PreloadAsync over ImageLabel
  instances): all five new ids AND the two rail icons report AssetFetchStatus.Success (a first
  attempt that passed bare id strings reported Failure for every id, including the two known-good
  ones, so that form of the probe is not authoritative). Runtime rendering is still checked in
  Play (ImageLabel.IsLoaded) before publishing.
- Owner does the native testing; Claude keeps computer control to the minimum (ideally none).

## 21:35 UTC — A-SHOP and A-WHEEL delivered; shop pushed to Studio
- A-SHOP: LobbyShopDisplay v4 (795 → 358 lines: eight 3.4-stud boxes at rel z -66 + 52/7*i, x 30.2,
  y 7.0, six decals each, invisible plates, no shopfront), Shop Display Client (client-side bob with
  server phase, "SHOP" title, kind tags TOKEN ITEM / ROBUX PRODUCT / PERMANENT PASS), and the whole
  ZyntraSupplyKiosk + shopkeeper deleted from TunnelLobbyBuilder (-537 lines). Tests:
  test_lobby_shop_display 2878, test_lobby_palette 828, neighbours green. Reviewed by Claude:
  accepted, including the bob standing down under ReduceFlashing/ReduceCameraShake. PUSHED to
  Studio (three files) at 21:33 UTC; native check in Play next.
- A-WHEEL: full-screen takeover wheel with the textured disc, rotating field labels + odds, fixed
  pointer, SPIN hub (tap while spinning = skip), 48 px X; 475 checks. Review found two things, sent
  back as a follow-up: size/centre on the Safe rect (Display let the pointer reach into the topbar
  band on landscape phones) and TextScaled field labels with an 11 px floor. Not pushed yet.
- A-DAILY and A-FRIEND still running. The two NEW Friend Boost scripts will be installed with
  tools/install_new_scripts.py once reviewed.

## 22:20 UTC — all four agents delivered, reviewed, pushed; desktop native pass green
- A-DAILY (480 + 488 checks) and A-FRIEND (318 + 243 checks; 16 neighbouring suites green)
  reviewed and accepted. A-WHEEL follow-up landed (520 checks: Safe-rect sizing, TextScaled
  labels). Claude fixed a real replication race in the shop client found in Play (the client
  collected the shop model before its boxes replicated and the row never bobbed): it now keeps
  collecting until it holds ShopItemCount boxes; test 2896 checks.
- New scripts installed in Studio with install_new_scripts.py (FriendBoost ModuleScript BEFORE
  GameManager was pushed, as GameManager WaitForChilds it). Pushed: ZyntraConfig,
  ZyntraMonetization, GameManager, ZyntraDailyRewardsPage, Daily Rewards Client, Shop Display
  Client, Lucky Wheel Client. pull --audit: 145/145, manifest 159 items all synced.
- Native desktop pass in Play (899x677, via the Studio MCP only — no desktop control):
  - Shop: 8 boxes at the contract centres, 6 decals each, 0 prompts, 0 collidable parts, kiosk /
    shopkeeper / plaque / access terminal gone, no SUPPLY/SHOP text in the lobby, worst corner
    r 32.900 at bob peak; bob moving after the fix; card auto-opens with "SHOP" + PERMANENT PASS.
  - Wheel: takeover disabled 22 ScreenGuis (StaminaGui re-enables itself and shows nothing in the
    lobby), disc loaded, 532 px on desktop, hub 138, X 48 at the safe corner, labels rotate with
    the disc; SPIN -> SPINNING -> landed at pointer 67.7 deg = field 2 (3 TOKENS) with the hub
    showing the prize then SPUN + countdown; X restored exactly the 16 guis it had disabled.
  - Daily Rewards: gift + three icons IsLoaded, header 64, X 48, cards 214x233 with 95 px icons,
    CLAIM row 44, no SUPPLY text. Console clean at boot.
  - Friend Boost: chip top-right "FRIEND BOOST +0% / INVITE FRIENDS TO EARN +10% PER FRIEND",
    invite button shown (CanSendGameInviteAsync answered true in Studio), attributes 0/0.
- Next: synthetic phone pass via the UIDevice Studio overrides (390x844 / 844x390), then the
  handoff to the owner for real desktop/mobile testing; publish after approval.

## 22:50 UTC — synthetic phone pass done; takeover hardened
- Synthetic phone pass in Play via the UIDevice Studio overrides (ForceTouchUI + UIRegressionViewport):
  wheel 390x844 → disc 335, hub 87, X 48, short labels at 13 px max; wheel 844x390 → disc 285
  inside the safe band, hub 74, labels 11 px; Daily portrait → horizontal 150-px cards with
  126-px icons and 44-px CLAIM; Daily landscape → cards start at y 206 of a 214-px scroll, so
  CLAIM needs a scroll on landscape phones → follow-up sent to A-DAILY (single-row strip, cards
  <= 160 tall on that tier only).
- Found in the synthetic pass: NoiseReporter's StaminaGui (home of the touch RUN button)
  re-enables itself on every layout pass, so RUN stayed on screen during the wheel takeover.
  Fix in the wheel client (Claude): while taken over, any other ScreenGui that switches itself on
  is switched off again and remembered as wanting to be on; restored on close. Test 524 checks.
  Pushed; native re-check with the touch layout next.

## 23:25 UTC — READY FOR THE OWNER'S TEST (not published)
- A-DAILY follow-up landed and pushed: on the compact landscape tier the countdown folds into the
  play strip (42 px, single row), cards 222x162, CLAIM bottom at 286 of a scroll ending at 294 →
  visible without scrolling; measured in Play at the 844x390 override. Tests 508 + 503.
- Studio == repo (pull --audit 145/145, manifest 159 items synced). Commits: a655130 (the round)
  + the follow-up commit below. Code knowledge graph rebuilt.
- Owner does the real desktop + iPhone-emulator/phone test and the two-account Friend Boost test
  (owner-test-checklist.md). Publish, Creator Dashboard verification, .rbxl backup, Trello
  #103/#104/#105 and the release commit follow the owner's approval.

## 2026-09-17 00:15 UTC — owner feedback round 1 applied and pushed
Owner's three notes after looking at the build:
1. A short caption over each hologram box → `ShopHologramCaption` BillboardGui (7 x 0.9 studs,
   2.45 studs above the box centre, rides the bob) with the product's own name in upper case in
   the box's accent colour + dark stroke. Verified in Play: eight captions, texts = upper(Name).
   test_lobby_shop_display 3432 (the "no drawn text" rule now exempts the caption).
2. Daily Rewards footer: the wheel pointer note removed; the playtime note is now only "Only time
   in an active round counts." (the "lobby and spectating do not ..." sentence is gone).
   test_daily_rewards_page 505, client 503.
3. Spectating counts toward daily playtime: ZyntraMonetization.playtimeCounts now counts a
   participant of an active round with no living body (dead, escaped-and-waiting, between bodies)
   — no AFK gate for them; RoundActive/loading flags still bound it. test_daily_rewards 337
   (gates updated + a 120 s spectating run).
Pushed: LobbyShopDisplay, ZyntraDailyRewardsPage, ZyntraMonetization. Audit 145/145, manifest
synced. Studio in Edit, Play stopped. Still NOT published.

## 2026-09-17 01:05 UTC — owner feedback round 2: Friend Boost chip lobby-only by construction
- Owner: the chip must never show inside a game. Reproduced the round flow natively (Level 1 via
  CREATE PARTY + DevFastQueue, instant win, auto-continue into Level 2): the chip stayed hidden
  throughout, so the old rule (InRound) held in that path — but "lobby" is now read off the
  world as well: visible only while the player's root is inside the ServerLobby model's bounding
  box (re-measured when the lobby is parked/moved) AND InRound/RoundActive are not true AND no
  round is loading; polled twice a second. A level server (no ServerLobby) can never show it.
- Verified in Play: visible on the lobby road, hidden within a poll after teleporting outside the
  lobby box with InRound still false, visible again back on the road. test_friend_boost 329.
- Pushed; audit 145/145. Still NOT published.

## 2026-09-17 06:40 UTC — PUBLISHED as v1933 (by the owner), verified
- Owner approved and published from Studio at 08:25 local (06:25:46 UTC). Verified by Claude in the
  Creator Dashboard version history (owner's Chrome, read-only): the "Published Version" tick is on
  1933 only; 1921-1932 are cloud saves. The public games API "updated" stamp matches.
- Trello #103, #104, #105 moved to Done and marked complete with the v1933 note. #106/#107/#69/#87
  untouched. release-receipt.json written.
- Backup .rbxl: pending the one Save-As (owner, or a single desktop action by Claude).
