# A-RAIL — the five-button lobby rail, the modal set, the terminal's Rewards tab

Scope: ZyntraStore's left rail grows from 3 to 5 buttons, the two new ones open
the #103 / #104 modals, the terminal loses its REWARDS tab, and the UIDevice /
UIRegression contracts follow. Nothing here touches ZyntraMonetization,
ZyntraConfig, GameManager, RoundUI, any Level file, or the three files owned by
A-WHEEL / A-DAILY / A-HOLO.

## Files changed

| File | What |
|---|---|
| `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | rail 3 -> 5, caption table, fit ladder, routing, Rewards tab removed |
| `ReplicatedStorage/UIDevice.ModuleScript.lua` | `SCREEN_OWNING_MODALS` + `LuckyWheelOpen`, `DailyRewardsOpen` (list and its comment only) |
| `ReplicatedStorage/UIRegression.ModuleScript.lua` | `expectedTabs` drops Rewards; three rail enumerations grow to five |
| `tools/tests/test_zyntra_store_compact.py` | +261 checks (259 -> 520), three new runnable lanes |

No manifest edit, no Studio call, no git write. All four files are LF/CRLF
exactly as they were (ZyntraStore LF, the two ReplicatedStorage modules CRLF).

## What shipped, in detail

### Rail

`SECTION_IMAGES` gains `Rewards = rbxassetid://85423575361057` and
`Wheel = rbxassetid://111918608092047`.

The captions were a nested conditional — `kinds[1] == "Shop" and "Shops" or
(kinds[1] == "Music" and "Music" or "Upgrades")`. Its final `or` is a DEFAULT, so
both new buttons would have silently captioned themselves "Upgrades". It is now
`SECTION_CAPTIONS`, a table with one entry per kind, and the test asserts its key
set equals `SECTION_IMAGES`'s.

`ZyntraRewardsButton` and `ZyntraWheelButton` are built by the same `button(...)`
call as the other three, with `COLORS.bg` / `COLORS.accent`, their own
`sectionButtonContent`, and the shared `SquareSectionButton` + `SquareSectionBorder`
loop. They are modelled on **musicButton**, not on openButton/shopButton: those two
carry an extra named `UIStroke` (`openButtonOutline`, `shopButtonRing`) because the
in-round DEV chip mutates the first one and the second is a leftover of the retired
card-88 ring. Copying either would have added a second stroke writer per button.

`local railButtons = {shopButton, openButton, rewardsButton, wheelButton,
musicButton}` is declared once, in drawn order, and **all three loops that used to
restate `{openButton, shopButton, musicButton}` now read it**. The test asserts that
no three-button literal survives anywhere in the file.

### The fit ladder

`layoutSquareSections(layout, shopButton, openButton, rewardsButton, wheelButton,
musicButton)` — arguments in drawn order, so the old "three arguments in one order,
re-ordered in a literal inside the loop" second source of truth is gone.

Ladder, in order: full side (64 pointer / 56 touch) -> the 52px floor -> **two
columns**, 3 at `left` and 2 at `left + side + gap`, both starting at the same
(centred) `top`. There is no fourth rung and no clipping: a control that has run off
the bottom of the screen is not a smaller control, it is one the player cannot reach.

The thumbstick-glyph dodge now tests against `width = side * columns + gap *
(columns - 1)` instead of one button's `side`. This is a real fix, not bookkeeping:
on the 705x338 reference phone the rail is two 52px columns spanning x 8..118, and a
glyph resting at x 114 sits **outside** a single column and **inside** the real rail.
The old predicate could not see it.

Measured (by the test, running the production function):

| Case | side | columns | top | notes |
|---|---|---|---|---|
| 1920x1080 pointer | 64 | 1 | 364 | 5x64 + 4x8 = 352, centred |
| 1024x768 touch | 56 | 1 | 232 | 6px touch gap |
| safe height 300 touch | 52 | 1 | 8 | 284 = exactly the available height |
| safe height 260 pointer | 52 | 2 | 44 | the brief's short screen |
| 705x338 touch (safe 0,58–705,338) | 52 | 2 | 114 | col 2 at x 66 |

### Activation and guards

`lobbyModalOpener(name)` is one helper used for both bindables: create-if-absent in
PlayerScripts (the `RoundExitPrompt` pattern), a `warn` + no-op when something else
already owns the name with the wrong class, and one guard closure —
**never in a round, never while `modalBlocksStore()`, never while
`UIDevice.ScreenOwningModalOpen()`**.

`openKioskShop(tab)` answers `tab == "Rewards"` by firing `OpenDailyRewards` and
returning. **Decision:** routed inside `openKioskShop` rather than at each caller, so
`PlayerScripts.ZyntraOpenTerminal "Rewards"` and `bindShopPrompt`'s
`ShopRewardsPrompt` branch share one answer. Routing at each caller is how one of
them silently ends up opening the Shop tab, which is a defect with no symptom.

### One root-cause fix beyond the brief

`UIDevice.OnScreenOwningModalChanged(updateVisibility)` was added. The rail's
predicate reads `ScreenOwningModalOpen()`, but until this line **nothing re-evaluated
it** — only `QueueModalOpen` and the dispatch briefing re-ran `updateVisibility`. So
MUSIC was already being left drawn and Active underneath a re-entry modal, and
REWARDS and WHEEL would have joined it: exactly the C5 defect ("an Active TextButton
keeps taking taps through its own transparent background"). One line, in the shared
place, rather than a hand-rolled subscription per new button.

It terminates by construction: `setMainVisible`'s own write to `ZyntraStoreOpen`
lands back in `updateVisibility`, which finds the terminal already closed and writes
nothing further; `updateReentry`'s `ZyntraReentryOpen` is a pure function of inputs
`updateVisibility` does not change, and Roblox does not fire an attribute signal for
an unchanged value.

### Terminal

`TERMINAL_PAGE_MODULES` keeps only `Notes`; the authored tab list is
`Upgrades, Shop, Notes, Donate, Colors, Settings` (+ `Dev`). `ZyntraDailyRewardsPage`
is still in ReplicatedStorage — A-DAILY's client mounts it — which is exactly why
UIRegression's `expectedTabs` no longer derives a Rewards tab from the module's
presence. Mounting it in both places would mean two profile subscriptions and two
claim buttons for one server-side claim. The probe's `"tabs"` action reflects the new
list automatically; nothing there needed editing.

## Verified offline, and how

`luau-compile.exe --binary` after every edit: all three .lua files compile.

`LUAU_BIN=.../luau.exe python tools/tests/test_zyntra_store_compact.py` ->
**520 checks** (baseline 259, so **+261**), lanes:
`tabs 10, supplies 42, supplies-absent 4, shop 102, rail 123, layout 101,
routing 39, modals 19`. The last three lanes are new, `rail` grew from 39 to 123.
Every lane runs the **production Lua extracted by marker** under the real luau
interpreter against honest fakes; a lane that asserts nothing now fails rather
than passing.

* **layout (101)** — the real `layoutSquareSections` against a fake `layout` and
  the real `PlayerGui.TouchGui...ThumbstickStart` chain. The five table rows above,
  plus a sweep of 509 safe heights x both form factors asserting, as one check per
  invariant: five buttons always placed, never under the 44px tap floor, never two
  sizes in one rail, always square, never overlapping, never past the safe height.
  Plus the 705x338 dodge and the documented "neither side fits" fallback.
* **routing (39)** — the real `lobbyModalOpener`, `openKioskShop`, the
  `ZyntraOpenTerminal` block, `bindShopPrompt` and the real `.Activated` connects.
  Covers: each button fires only its own bindable and never opens the terminal;
  refusal under each of the three guards, on both buttons AND on the plaque prompt
  AND on the terminal opener; `"Rewards"` reaches the modal while `"Notes"`, no tab
  and an unknown name still reach the terminal; the plaque with and without
  `ShopRewardsPrompt`; another player's trigger reaching nobody; adoption of a
  pre-existing `OpenLuckyWheel` (same instance, still exactly one); and the
  wrong-class refusal warning once and then being a no-op.
* **modals (19)** — the REAL `SCREEN_OWNING_MODALS` literal and
  `ScreenOwningModalOpen` / `OnScreenOwningModalChanged` from UIDevice, run against a
  fake player. Each of the six attributes opens and releases the answer; `false` and
  a truthy non-boolean both read as closed; the change hook subscribes to all six.
* **rail (123)** — order, names, captions, icon asset ids, `ScaleType Fit`, the
  authored 64px square, the shared corner/border/hover rule on all five, and that
  MUSIC ships inactive while REWARDS and WHEEL ship pressable.

**Mutation-tested** (each mutation applied to the real source, run, reverted):

| Mutation | Caught by |
|---|---|
| `left + width` -> `left + side` in the glyph dodge | layout |
| two-column rung disabled | layout |
| rail order swapped (openButton first) | rail/static |
| the `tab == "Rewards"` branch deleted | routing |
| wheel button wired to `openDailyRewards` | routing |
| `ScreenOwningModalOpen()` dropped from the guard | routing |
| `"LuckyWheelOpen"` removed from `SCREEN_OWNING_MODALS` | modals |

Whole-repo sweep: all 52 `tools/tests/test_*.py` run. 46 pass, including every
suite that loads my four files (`test_controller_input`, `test_daily_rewards_page`,
`test_dev_free_respawn_offer`, `test_equipment_hud`, `test_field_notes`,
`test_lobby_shop_display`, `test_reentry_dismissal`, `test_round_exit_hold`,
`test_ui_style`). Six fail:

* `test_full_sync_contract` — **expected and mine to declare, not to fix.** It
  compares the manifest's sha256 against the working copy, so it fails for every
  file this batch edited (mine plus `LobbyShopDisplay`) and for A-WHEEL's untracked
  `Lucky Wheel Client`. `record_pending_push.py` is the manager's step; I am
  forbidden to touch the manifest.
* `test_level3_run_in_exit`, `test_level3_hidden_chase`, `test_level3_slide_aperture`
  — already failing at HEAD, documented in CLAUDE.md.
* `test_pool_slide_navigation` — Pool Slide content, which lives only in Studio;
  reads none of my files.
* `test_push_repo_to_studio` — "CANNOT EXECUTE": this luau build rejects
  `--version`, so the fixture never runs. Environment, not code.

## NOT verified — needs Studio

* **Real thumbstick geometry.** The dodge is tested against a fake
  `ThumbstickStart` at stated rectangles. Roblox's own resting glyph position and
  size on a real handheld is not modelled, and neither is `UIDevice.LocalOffset`'s
  real answer (the fixture returns 0,0). The 705x338 numbers above come from
  `layout.Safe = (0,58)-(705,338)`, which is the documented inset for that device,
  not a live `UIDevice.Layout()` read.
* **That the two new icons render.** The asset ids are wired and preloadable per
  `assets-handoff.md`, but nothing offline proves the PNGs draw inside a 64px square
  with the caption legible. `assets-handoff.md` explicitly asks the manager to
  confirm both visible buttons before publishing.
* **UIRegression itself.** It only runs inside Studio. My three edits to it compile
  and are consistent with the source they mirror, but no lane of it has been
  executed. In particular the new per-device rail assertion in
  `ZyntraTerminalFitMatrix` and the five-name `Forbids` on the `store-modal` row are
  unexercised.
* **The two-column rail as a picture.** Whether a 3+2 grid at the left edge of a
  landscape phone actually looks like a rail, and whether it collides with anything
  A-HOLO or the queue HUD draws there, is a QA judgement.
* **`UIDevice.OnScreenOwningModalChanged(updateVisibility)` under load.** The
  termination argument above is from reading the code; it has not been run against
  Roblox's real deferred attribute signals.

## Decisions taken (not asked)

1. **`layoutSquareSections` takes five positional arguments in drawn order**, not a
   table, and builds its own `rail` list from them. The brief allowed either; this
   removes the internal re-ordering literal, which was the shape of the bug.
2. **Two columns are 3 + 2, both starting at the same `top`** (the centred top of a
   3-row stack), column-major so the reading order still runs downward.
3. **The new buttons are modelled on musicButton**, i.e. no extra named `UIStroke`.
   See "Rail" above.
4. **`"Rewards"` is routed inside `openKioskShop`**, not at each of the two callers.
5. **`UIDevice.OnScreenOwningModalChanged(updateVisibility)` was added** although the
   brief did not ask for it. Without it the whole "leaves the input stack while a
   modal is up" requirement is unreachable, because nothing re-evaluated the
   predicate. It also fixes the same latent defect on MUSIC.
6. **UIRegression's dispatch/queue lane at ~4506 was deliberately left alone.** It
   enumerates one button (`ZyntraOpenButton`), not three, and its `STATES` table
   asserts `Opener = false` during a *lobby* briefing — which `modalBlocksStore()`
   (`queueModalOpen() or (InRound and briefingOpen())`) does not appear to produce.
   That table may already be stale against ZyntraStore's "the rail remains usable
   during Dispatch" rule. Extending a lane I cannot run, on a predicate I cannot
   reconcile offline, would have been guessing. **Flagged for the manager**: worth
   one Studio run of `BriefingExclusionMatrix` to see whether that row still passes.
7. **The height sweep records one check per invariant, not one per button pair.**
   It was 8378 checks at first; 300 passing copies of one rule say nothing the first
   one does not and they bury the lanes that matter.

## Contract notes for the other agents

`Daily Rewards Client` and `Lucky Wheel Client` were read (not edited) to confirm
both sides agree: both do create-if-absent on their bindable, both publish
`DailyRewardsOpen` / `LuckyWheelOpen`, both call
`UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())` on open and after
close, and both refuse on `ScreenOwningModalOpen()`. Because ZyntraStore now refuses
first, a rail press can never reach them while another modal is up; their own refusal
stays as the backstop for any other caller.

## Trello draft — the rail parts

**#103 (Lucky Wheel), rail portion**

> The wheel has its own square side button in the lobby rail: WHEEL, fourth from the
> top, wearing the generated wheel symbol. It sits in the same treatment as SHOPS,
> UPGRADES and MUSIC — same size, same border, same hover — and the icon is a button
> symbol only: the spinning disc and its stationary pointer are built by the wheel
> client, so nothing rotates the baked-in pointer. Pressing it fires
> PlayerScripts.OpenLuckyWheel. It refuses in a round, while a queue modal is up, and
> while any other screen-owning modal is up, and it leaves the input stack entirely
> whenever one is — including the wheel's own modal, so it cannot be pressed through
> the panel it opened.

**#104 (Daily Rewards), rail portion**

> Daily Rewards has its own square side button, REWARDS, third from the top of the
> lobby rail, and the terminal's REWARDS TAB IS REMOVED — the page now exists in
> exactly one place, so there is no second set of claim buttons and no second profile
> subscription. Everything that used to ask for the Rewards tab now opens the
> standalone modal instead: the kiosk plaque's E prompt and
> PlayerScripts.ZyntraOpenTerminal "Rewards". The remaining tabs are UPGRADES, SHOP,
> NOTES, DONATE, COLORS, SETTINGS (and DEV on a whitelisted account).

**Both cards, shared line**

> The rail grew from three buttons to five, so it now fits itself to the screen: 64px
> squares on a pointer, 56 on touch, 52 when the safe area is short, and two columns
> of 3 + 2 when even that does not fit. It is never clipped and it still steps aside
> for the on-screen thumbstick — measured against the whole rail now, not one button's
> width, which a two-column rail made necessary.

## Open for the manager

* Run `record_pending_push.py` before any push; `test_full_sync_contract` fails
  until then, by design.
* Confirm both new icons render legibly inside the 64px square (and at 52px, which
  is what a landscape phone gets) before publishing — `assets-handoff.md` asks for
  this explicitly.
* One Studio run of the briefing/queue lane, per decision 6.
