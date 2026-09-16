# Claude status — follow-up #103/#104/#105 (living document, lead = Fable 5.1)

Baseline: git `2c60cf3` (= published v1920), Studio == HEAD (141 scripts, 0 drift), Edit mode.
Claude only: code, integration, QA, publish. Codex: images (delivered, see assets-handoff.md).

## 11:10 UTC — scope read, contracts written, four Opus 5 agents DISPATCHED (running)

Contract: `claude-contracts.md` (names, modal rules, wheel construction, hologram rules).

| Agent | Card | Files (exclusive) | State |
|---|---|---|---|
| A-WHEEL | #103 | StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua (new), tools/tests/test_lucky_wheel_client.py (433 checks) | DONE + lead-reviewed 11:52 UTC after Fix 1 (spokes now rotate about the hub via full-diameter arm parents). Created in Studio via install_new_scripts.py. Needs Studio: does the 180-arm disc render cleanly, pointer legibility, tween feel |
| A-DAILY | #104 | StarterPlayerScripts/Daily Rewards Client.LocalScript.lua (new, 583 lines), ZyntraDailyRewardsPage (964 -> 599, wheel removed, header = countdown strip), test_daily_rewards_client.py 439, test_daily_rewards_page.py 280 | DONE + lead-reviewed 11:42 UTC (accepted as-is). Daily Rewards Client created in Studio via install_new_scripts.py; the page module push waits for A-RAIL so the terminal and the page land together |
| A-RAIL | rail + terminal | ZyntraStore (+180: 5-button rail, fit ladder 64/56 -> 52 -> two columns, railButtons list, lobbyModalOpener, Rewards tab removed, openKioskShop("Rewards") -> OpenDailyRewards, OnScreenOwningModalChanged -> updateVisibility), UIDevice (+2 modal names), UIRegression (rail rows, expectedTabs), test_zyntra_store_compact.py 520 | DONE + lead-reviewed 12:05 UTC (accepted); pushed to Studio with the page module |
| A-HOLO | #105 | LobbyShopDisplay (757 -> 795: projector disc + beam + ForceField hologram box + invisible pressure plate per item, pedestals/caps/INSPECT prompts/plate edges removed, walk-through, plaque copy DAILY REWARDS / PLAY TO EARN / PRESS E TO OPEN), Shop Display Client (pointer card 560 wide, 112 icon, close hint, no yaw), test_lobby_shop_display.py 802 | DONE + lead-reviewed 12:24 UTC (accepted); push next |

Untouched: ZyntraMonetization, ZyntraConfig, GameManager, RoundUI, every Level file, manifest,
Studio (until lead review). Publish only after native desktop + phone QA and the release checks.

## 11:58 UTC — Studio writes so far, QA method note

- Created in Studio (installer, byte-verified, manifest synced): `Daily Rewards Client`,
  `Lucky Wheel Client` (manifest 143 scripts / 157 items). Not yet pushed: the page module
  (waits for A-RAIL so the terminal loses its Rewards tab in the same push), A-RAIL's three
  files, A-HOLO's two files.
- The MCP assistant thread cannot Fire/Invoke Bindables in Play (capability sandbox), so the
  native modal QA must go through the real rail buttons with `user_mouse_input`
  (instance_path on `ZyntraWheelButton` / `ZyntraRewardsButton`) once A-RAIL's ZyntraStore is
  pushed, plus `screen_capture` and `get_console_output` for evidence.

## 12:15 UTC — native QA #103 (desktop 899x677 Studio Play)

- Rail: five 64x64 buttons at x 8 (y 134/206/278/350/422), all icons IsLoaded=true, captions
  Shops/Upgrades/Rewards/Wheel/Mute. Console clean.
- Wheel: rail click opened LuckyWheelGui (LuckyWheelOpen=true, rail stood down), panel 820x603,
  disc 331 px with 180 arms rendering a clean proportional pie (162/72/72/18/36 deg), sector
  labels, legend 45/20/20/5/10 %, pointer at 12 o'clock. SPIN -> server awarded 1 Speed Potion
  (potions 0 -> 1, tokens 35 unchanged); disc landed at rotation 1534.6 = pointer angle 265.4 deg
  inside the Potion1 sector (234..306); banner "YOU RECEIVED: 1 Speed Potion"; SPUN TODAY
  disabled; "Next spin in 12:21:31" counting. Captures: ScreenCapture_wheel_open/_landed.
- A-HOLO (#105) landed at 12:12 UTC (802 checks); review after this Play session.

## 12:24 UTC — native QA #104 + a lead fix

- Daily Rewards: rail click opened DailyRewardsGui (DailyRewardsOpen=true, wheel closed), panel
  720x603, content 680x467 scrolling (canvas 708), countdown "RESETS IN 12:20:54", readout
  "ACTIVE PLAY TODAY 0:00", three milestone cards locked ("5:00 TO GO" ...), wheel note, no
  SpinButton anywhere; terminal tabs now Upgrades/Shop/Notes/Donate/Colors/Settings/Dev.
  Capture: ScreenCapture_daily_open. Wheel reopened parked (same rotation, SPUN TODAY).
- FOUND + FIXED (lead, ZyntraStore): SHOPS and UPGRADES stayed Visible/Active beside an open
  wheel/rewards modal (one tap from a second modal). updateVisibility now hides both under any
  other screen-owning modal; toggleMain/openKioskShop refuse to OPEN over one. 520 checks +
  reentry 37 still green; compile OK. Push pending together with A-HOLO's files.

## 12:48 UTC — native QA #105 + modal exclusion (desktop Studio Play)

- Hologram shop built: ShopDisplayVersion 3, 8 items, 8 ShopHologramBox (ForceField 0.35, product
  decal on the road face at T=0), 8 projector discs + beams, 8 invisible pressure plates
  (T=1, CanQuery=false), 0 ShopInspectPrompt, 1 plaque prompt ("DAILY REWARDS"/"Daily Rewards").
  Capture ScreenCapture_holo_frontage: six floating boxes at alternating heights under the SHOP
  sign, no pedestals, rail with five buttons visible.
- Focus: stepping onto the Supporter plate -> ZyntraShopFocus=Supporter; onto the neighbour ->
  AdvancedEquipment; card auto-opened (560x277, icon 112, "Step off the plate or press CLOSE",
  OWNED disabled in Studio); CLOSE -> gui.Enabled=false and standing still 1.5 s did NOT reopen;
  step off -> focus nil; step back -> reopened. Token item: SpeedPotion plate -> card "FIELD
  SUPPLIES / 0 STORED / 3 TOKENS // BUY"; explicit BUY -> tokens 35 -> 32, potions 0 -> 1,
  state "1 STORED". Capture ScreenCapture_holo_card.
- Plaque prompt: E in front of the plaque (4.9 studs, in frustum) opened DailyRewardsGui
  (DailyRewardsOpen=true) -- the OpenDailyRewards route works from the world too.
- Modal exclusion after the lead fix (pushed): with the wheel open all five rail buttons are
  Visible=false/Active=false. Console clean throughout (no errors from any new script).

## 12:52 UTC — desktop-control grant denied

`request_access("Roblox Studio")` for the computer-use tools returned user_denied, so the Studio
Device Emulator and File -> Publish to Roblox are not reachable from this session right now
(the MCP tools only reach the in-game Client datamodel). Phone QA continues with UIDevice's
Studio-only viewport override + the UIRegression touch/terminal matrices in Play (synthetic
viewports, the project's documented fixture route). The grant will be requested again at the
publish step. Per Codex's 11:51 UTC relay, the owner has been asked to approve the grant in
Claude; Claude waits for it and does NOT bypass it with other UI automation. Native QA and the
publish stay with Claude (never handed to Codex); no card is marked Done/published before the
published version is verified.

## 13:05 UTC — synthetic phone pass (UIDevice viewport override + ForceTouchUI, Studio Play)

| Viewport | Rail | Wheel panel | Daily Rewards panel |
|---|---|---|---|
| 390x844 portrait | 5 x 56 px, one column y 241..545 | 366x620 inside; disc 260; SPIN 334x44 (below the fold, scroll); min text 11, min tap 44, no glyphs | 366x640 inside, compact; CLOSE 44x44; claims 286x44 |
| 844x390 landscape | 5 x 56 px, one column y 14..318 | 820x316 inside; body 202, disc 260 -> SPIN at canvas y 600 (scroll) | 720x316 inside; CLOSE 44; claim 640x44 (scroll) |
| 705x338 Galaxy A06 | 5 x 52 px in TWO columns (3+2) | 681x264 inside; body 150 (scroll) | 681x264 inside; CLOSE 44; claim 601x44 (scroll) |

Everything inside its viewport, every tap >= 44, every text >= 11, no keyboard glyphs; the
modal attributes and the rail stand-down behaved identically to desktop. Finding: on landscape
phones SPIN is under the fold -> Fix 2 requested from A-WHEEL (SPIN/SKIP pinned to the panel
footer on touch, disc sized to the body). The UIRegression lanes cannot be run from this
session (the assistant thread may not `require` place modules); the same command-bar run
(`require(game.ReplicatedStorage.UIRegression).RunAllSummary()`) is the owner's to trigger.

## 13:20 UTC — Fix 2 accepted and pushed

Lucky Wheel Client Fix 2 (SPIN/SKIP pinned as a panel footer on touch tiers, disc sized to the
body): test 530 checks, compile OK, pushed (39531 B, backup .studio-push-backups/20260916-115904).
Parity before the push: 141 exact + 1 permitted + the expected in-flight wheel drift; re-run
after this push follows. Native landscape re-measure follows in Play.

## 13:30 UTC — parity OK, landscape re-measure after Fix 2

- `tools/verify_studio_parity.py` on a fresh probe dump: exact 142, permitted 1, drift 0,
  missing 0, extra 0 -> PARITY OK (dump: studio-parity-dump.txt). `pull --audit`: 143/143.
- 844x390: wheel panel 820x316, body 796x156, disc holder 140x152 fully inside the body, SPIN
  796x44 in the panel footer at y 240 above the status line (y 294). 705x338: panel 681x264,
  body 104, SPIN footer y 188 (44 px), min tap 44; the 140-px disc floor makes the disc
  holder (152) scroll inside the 104-px body -- the pointer and landing sector at the top stay
  on screen, the lower half scrolls. Accepted as the Galaxy A06 compromise; noted for the owner.
- Console clean in every session. Studio is back in Edit.
