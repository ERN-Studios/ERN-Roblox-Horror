# A-DAILY — Trello #104, standalone Daily Rewards modal

Agent: A-DAILY. Baseline: `2c60cf3`. Nothing committed, nothing pushed to Studio,
manifest untouched.

## Files

| File | State | Lines |
|---|---|---|
| `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` | **NEW** | 583 |
| `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua` | edited (wheel removed) | 964 → 599 |
| `tools/tests/test_daily_rewards_client.py` | **NEW** | 1136 |
| `tools/tests/test_daily_rewards_page.py` | edited (wheel assertions removed) | 1050 → 874 |

Nothing else was touched. `ZyntraStore`, `UIDevice` and `UIRegression` are
A-RAIL's; the wheel is A-WHEEL's; the server side is unchanged by this batch.

## Verified offline, and how

Both suites run the REAL shipped Lua under the real luau interpreter
(`LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`). No
static string matching is used as proof anywhere.

```
python tools/tests/test_daily_rewards_page.py     -> 280 checks passed
python tools/tests/test_daily_rewards_client.py   -> 439 checks passed
luau-compile.exe --binary ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua  -> OK
luau-compile.exe --binary "StarterPlayer/.../Daily Rewards Client.LocalScript.lua"   -> OK
```

`test_daily_rewards_client.py` executes the ENTIRE LocalScript inside a fake
DataModel and then drives it. Real modules loaded and run under the same fake:
`UIStyle`, `ZyntraConfig` and `ZyntraDailyRewardsPage` (the page is re-executed
per fixture, which is what `require`'s cache gives it in the engine). `UIDevice`
is faked only where its published contract is: `Layout().ModalViewport`,
`LocalPosition`/`LocalOffset`, `SetEnabled`, `SetInteractive`,
`SuppressesKeyboardGlyphs`, `LastInput`, `ScreenOwningModalOpen` (reading the
five attributes) and `SuppressTouchMovement` (recording every request). `Color3`
has no arithmetic in the fake; `TweenService.Create` throws, so a tween anywhere
in the modal fails the run.

What it proves by running the code:

- **The shell.** `DailyRewardsGui`, DisplayOrder 117, `ResetOnSpawn = false`,
  `ScreenInsets = CoreUISafeInsets`, an Active full-safe-area shade, the panel,
  the title bar, CLOSE, the content frame and the status line. Boot sends
  exactly one `ZyntraGetProfile` and zero actions, publishes no attribute and
  makes no suppression request.
- **One mount, at build time.** The real `Page.mount` is wrapped so the call is
  counted. Three open/close cycles leave `MountCalls == 1`, one page tree and a
  scroll that was never destroyed. Every field the page contract names is
  asserted present and of the right type on the ctx that was actually passed.
- **Open.** The bindable is created when absent and ADOPTED when another script
  made it first (never duplicated); firing it draws the modal, publishes
  `DailyRewardsOpen = true`, makes exactly one `SuppressTouchMovement(true)`
  request, re-reads the profile, binds ButtonB, and hands a gamepad the CLOSE
  control. A second fire while open changes nothing.
- **Refusals**, one case each for `InRound`, `ZyntraStoreOpen`, `DevPhoneOpen`,
  `ZyntraReentryOpen`, `QueueModalOpen`: not drawn, no attribute, no suppression
  request, no extra read, no bound action — and it opens once the reason clears,
  so the refusal is the attribute and not something latched at build time.
- **Seven close paths** (CLOSE, Escape, ButtonB, `InRound` → true, `RoundActive`
  → true, `QueueModalOpen` → true, Roblox menu): each clears the attribute,
  tells the page it is off screen, unbinds ButtonB, makes exactly ONE further
  suppression request, and does not remount or destroy the page. The
  `QueueModalOpen` row asserts the request is `true` — the movement cluster
  stays down because the queue still owns the screen — and a dedicated case
  opens re-entry on top, closes this modal and asserts the cluster is still
  suppressed, then frees it when nothing is left.
- **Profile pushes re-render**: 0 → `5:00 TO GO`, 299 → `0:01 TO GO`, 300 →
  `CLAIM` enabled, claimed → `CLAIMED` disabled, a yesterday-dated profile →
  locked again; a push that arrives while the modal is CLOSED still lands, so
  reopening is correct on the first frame.
- **CLAIM** fires `ClaimPlaytimeReward {Minutes = 5}` exactly once, locks to
  `CLAIMING...`, swallows the second and third press, and unlocks on the push.
- **The 6 s recovery**: still waiting at 5 s with no re-read, then at 6 s the
  status line reads "No answer yet. Try again." in the error colour, the page
  RE-READS (`ZyntraGetProfile` count +1), the control comes back and a retry is
  a genuine second request.
- **The wheel is gone and unreachable**: every `TextButton` in the whole modal
  is Activated with an unspent spin on the profile, and no `SpinDailyWheel` is
  ever sent; a recorded `WheelLast` draws nothing.
- **Fit at four viewports** (1280x720 pointer, 390x844, 844x390, 1024x768): the
  panel lands inside `ModalViewport` on all four edges; content, status, CLOSE
  and title all inside the panel; the title stops short of CLOSE; the content
  stops short of the status line; CLOSE ≥ 44 px on touch; every milestone CLAIM
  inside the content frame and ≥ 44 px on touch; smallest face ≥ 11 px; the fit
  table carries all seven contracted keys and its `ContentWidth`/`ContentHeight`
  equal the content frame's own rectangle.
- **A 320x260 modal viewport** (below every device in the matrix) still yields a
  panel inside the viewport, a content box, and a CLOSE that is ≥ 44 px, inside
  the panel on both axes, and still closes the modal.
- **Degraded hosts**: a `ZyntraGetProfile` that throws leaves the modal openable
  with every milestone locked and the failure stated; a place with no
  `ZyntraDailyRewardsPage` draws `DAILY REWARDS UNAVAILABLE`, warns once, and
  still opens, publishes and closes so nobody is trapped.
- **The Studio probe** drives the production paths: `open`/`close`/`state`,
  `cards` returns the three authored milestone rows, `scrolls` returns
  `Rewards|DailyRewards`, an unknown action answers nil — and `open` is REFUSED
  in a round exactly as a player is, so a matrix cannot measure a modal a player
  could never have opened.

`test_daily_rewards_page.py` keeps everything that was not the wheel (states,
day roll, 1 Hz countdown and its re-anchor, one-press-one-action, the 6 s
recovery, refresh/destroy, the four-viewport fit, the degraded-host cases) and
gains a `wheelRemnant()` walk of the whole built tree: a hidden `SpinButton`
would still be wired to the action, so "not drawn" is not accepted as proof.

## NOT verified — needs Studio

- Real touch, a real finger, and whether `SuppressTouchMovement` actually stands
  Roblox's dynamic thumbstick down under this modal.
- Font metrics / `TextBounds`: every width here is a stated offset. The title
  bar copy is short and the title is clamped to `closeLeft - 10`, but whether
  "DAILY REWARDS" ellipsizes at 24 px on a 358-wide phone panel is a capture.
- `UICorner`/`UIStroke` rendering, and whether the panel reads well against the
  shade at DisplayOrder 117 with the Lucky Wheel at 118.
- The kiosk plaque prompt → `OpenDailyRewards` path (A-RAIL's binding).
- **The script is not in Studio.** New scripts cannot be pushed by the sync
  tools: it must be created in Studio via `execute_luau` + `UpdateSourceAsync`
  first, then given a `studio-sync-manifest.json` item with `sha256_of` /
  `canonical_bytes` from `tools/studio_source_contract.py`. I ran no Studio or
  sync tool and did not edit the manifest.

## Decisions

1. **The page's eyebrow and title were REMOVED; the shell owns them.** The task
   brief asked for both the shell title bar and the page header to carry
   "ZYNTRA // DAILY SUPPLY" / "DAILY REWARDS" — that is the same two words
   twice, ~40 px apart, in the only host that now exists.
   `claude-contracts.md` (binding) is the tiebreak and is unambiguous: the page
   "keeps its milestones section and header (countdown, UTC note, active-play
   readout, progress track, three claim cards)" and the client builds "the modal
   shell (title bar "DAILY REWARDS", CLOSE, status line)". So the page's header
   is now a countdown strip (accent bar + `ResetCountdown` + `ResetNote`) and
   the title lives once, in the shell. This is also correct in the terminal, if
   it ever mounts the page again: the tab is the title there, exactly as the
   Upgrades and Shop pages already work.
2. **Panel design size 720x640**, not the terminal's 1180x760. The page is one
   column now; a milestone card across a 1140 px content box is a 1100 px CLAIM
   button. Clamped to `ModalViewport` with the terminal's own margins and
   give-way ladder (eyebrow first, then the status band, then grow into the
   viewport).
3. **`RoundActive` closes but does not refuse**, per the contract's two lists. A
   lobby player on a server where someone else's round is running is not in that
   round, and `InRound` is the fact that says so — that one both refuses and
   closes.
4. **The shade does not close the modal** when tapped. A mis-tap on a phone
   would throw away a card the player is reading; it is Active only so the tap
   cannot reach the movement controls or a world prompt behind it.
5. **The mount is in a `task.spawn`** so a place without the module still gets a
   working shell and a working CLOSE instead of a rail button whose modal never
   appears. A layout hook that registers after the shell's first layout pass is
   handed the fit immediately, otherwise the page would hold its build-time
   rectangles until the first device rotation.
6. **The contract cards are recorded but NOT CollectionService-tagged.** The
   terminal's `ZyntraTerminalAction` tag drives UIRegression's fit matrix, which
   measures every tagged control on screen; these sit behind a modal that is
   closed almost all of the time. They carry `ZyntraPage` / `ZyntraCardKey`
   attributes and are reported by the probe's `cards` action instead.
7. **`COLORS` is copied by value** from ZyntraStore. The page takes its two
   accents from `ctx.COLORS`, and ZyntraStore is a LocalScript with nothing to
   require; a divergent palette would draw a differently coloured DAILY REWARDS
   depending on which host opened it.
8. **The layout collapses to one column at every tier.** `TWO_COLUMN_MIN` became
   `WIDE_HEADER_MIN` (same 620) and now only decides whether "Resets 00:00 UTC"
   sits beside the countdown or under it.

## Instance names and captions

| Instance | Path | Caption |
|---|---|---|
| `DailyRewardsGui` | `PlayerGui` | — (DisplayOrder 117, CoreUISafeInsets) |
| `DailyRewardsShade` | `DailyRewardsGui` | — (Active, 50% black) |
| `DailyRewardsPanel` | `DailyRewardsShade` | — |
| `HeaderAccent` | panel | — |
| `Eyebrow` | panel | `ZYNTRA // DAILY SUPPLY` |
| `Title` | panel | `DAILY REWARDS` |
| `CloseButton` | panel | `X` |
| `PageContent` | panel | — (the page mounts here) |
| `StatusLine` | panel | server notices; `No answer yet. Try again.` |
| `PageUnavailable` | `PageContent` | `DAILY REWARDS UNAVAILABLE` (module missing only) |
| `UIRegressionDailyRewardsProbe` | `DailyRewardsGui` | Studio only |
| `OpenDailyRewards` | `PlayerScripts` | BindableEvent, create-if-absent |
| `WheelNote` | page `PlaytimeSection` | `Spin the Lucky Wheel from its own button on the left rail.` |

Published attributes: `DailyRewardsOpen` on the LocalPlayer (true while drawn,
nil otherwise); `DailyRewardsCompact` / `DailyRewardsTapFloor` /
`DailyRewardsContentHeight` / `DailyRewardsModalWidth` /
`DailyRewardsModalHeight` on `DailyRewardsPanel`, for regressions that want the
CHOICES rather than the pixels.

Unchanged page copy: `ACTIVE PLAY TODAY  m:ss` (+ `  //  COUNTING`),
`RESETS IN HH:MM:SS`, `Resets 00:00 UTC`, `PLAYTIME REWARDS`,
`5/15/35 MINUTES`, `CLAIM` / `CLAIMING...` / `CLAIMED` / `m:ss TO GO`,
`Every milestone reached today.`, and the "only time in an active round counts"
note.

## Cross-agent notes

- A-RAIL has already landed `"DailyRewardsOpen"` in `SCREEN_OWNING_MODALS` and
  `lobbyModalOpener("OpenDailyRewards")` in ZyntraStore; their guards
  (`InRound`, `modalBlocksStore`, `ScreenOwningModalOpen`) match this client's
  own refusals, and both sides create the bindable if absent. Verified by
  reading their working copy, not by running it.
- `tools/tests/test_zyntra_store_compact.py` broke mid-batch on A-RAIL's rail
  edit (its literal marker `for _, entry in ipairs({openButton, shopButton,
  musicButton}) do` is present at HEAD and renamed by the 3 → 5 button rail),
  and A-RAIL has since fixed it: re-run at the end of this batch it reports
  **501 checks / 5-button rail**, green. Neither the break nor the fix is mine;
  recorded because it was red for part of the batch.
- `UIRegression` line ~5045 still allowlists `SPUN TODAY` / `SPINNING` in
  `Fit.ZyntraDisabledCaptions`. Harmless — A-WHEEL's client needs those same
  captions — but worth a glance when A-RAIL reconciles that table.

## Trello draft — card #104

> **Daily Rewards now has its own UI and its own side button.**
>
> Daily Rewards has left the Zyntra terminal. It is a modal of its own, opened
> by the new REWARDS button on the lobby rail (and by the kiosk plaque prompt),
> with its own title bar, CLOSE and status line. The terminal's Rewards tab is
> removed, so there is exactly one Daily Rewards surface in the game — not two
> CLAIM buttons for the same milestone.
>
> Everything saved is untouched: the server side (`ClaimPlaytimeReward`, the
> `Daily` payload, `SecondsToReset`) was not changed at all. Daily active
> playtime, the three milestones (5 min → 1 token, 15 min → 1 Speed Potion,
> 35 min → 1 Entity Shield) and every claim still come out of the profile the
> server already committed; the modal asks and then re-reads, and never grants
> anything client-side. One request in flight per milestone, and a request
> nobody answers for 6 seconds re-reads instead of guessing.
>
> The Lucky Wheel is no longer part of this page — it is card #103's own modal,
> on its own rail button. The rewards page carries one line saying so.
>
> No modal overlap: it refuses to open in a round, under the terminal, under the
> dev phone, under the re-entry modal or while the queue host panel is up, and
> it closes on CLOSE, Escape, gamepad B, entering a round, a round starting and
> the queue panel opening. It publishes `DailyRewardsOpen` and hands the
> movement-control suppression back only when nothing else still owns the
> screen. One mount for the whole session — reopening never builds a second copy
> or a second listener.
>
> Offline proof: 439 checks driving the whole LocalScript (plus the real page
> module, UIStyle and ZyntraConfig) under the real Luau interpreter, and 280 on
> the page module — including four viewports with every touch target measured at
> or above 44 px, and a check that no control anywhere in the modal can send
> `SpinDailyWheel`.
>
> Still to do on a real client: phone portrait/landscape, tablet and desktop
> captures, and the thumbstick standing down under the modal on touch.
