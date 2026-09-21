# A-EXIT — Trello #74 "Back to Lobby", hold-to-leave

Baseline `aa40f70`. Nothing committed, nothing pushed, Studio never touched.

## Files

| Path | What |
|---|---|
| `G:\Roblox\MongoTV\StarterPlayer\StarterPlayerScripts\Round Exit Client.LocalScript.lua` | rewritten alive-player path: hold-to-leave. 497 lines. |
| `G:\Roblox\MongoTV\tools\tests\test_round_exit_hold.py` | new. Whole LocalScript under a fake DataModel, 294 checks. |

Nothing else was edited. `git status` shows ten other modified files in this
checkout; they belong to the other agents in this batch, not to me.

## What it does now

**Alive player.** The `LeaveChip` at the top-left of the safe area is no longer
clickable — there is no `Activated` path at all. It reads `HOLD L • LOBBY` on a
keyboard and `HOLD • LOBBY` on a touchscreen, and it is *held*: the `L` key, or a
finger/mouse/gamepad-A press on the chip itself. A translucent accent wash
(`HoldFill`, a Frame inside the chip) grows from 0 to full width over
`HOLD_SECONDS = 1.5`, and a caption band (`HoldHint`) appears directly under the
chip for the duration: *"Leaving ends your run. The others keep playing."*
Release before 1.5 s and the bar snaps to 0 with nothing sent. At 1.5 s it fires
`Remotes.RoundStatus:FireServer("leaveround")` **once**, the chip reads
`RETURNING...`, and the key/finger must physically lift before another hold can
begin.

**Dead or escaped player.** Unchanged: `PlayerScripts.RoundExitPrompt` (fired by
SpectateController's band button) still opens the STAY / BACK TO LOBBY card,
because the cursor is already free there. Both paths now share one
`requestPending` latch and one `sendLeave()`, so only one request can ever be in
flight regardless of which path the player used.

**Server contract untouched.** `"leaveround"` out; `"leaveack"`,
`"leavefailed"`, `"lobby"/"loadinggame"/"lose"/"win"` back. GameManager's
`handleLeaveRoundRequest` is the authority and was not opened.

Answers on the chip: `leaveack` → `RETURNING TO LOBBY...` (stays);
`leavefailed` → `NOT AVAILABLE IN THIS TEST ROUND` for 3 s, then back to the
prompt and a new hold is allowed; no answer at all within 8 s → unlatch and
`NO ANSWER — HOLD AGAIN` for 3 s.

**Cancel list** (all reset the bar to 0 immediately): typing in a TextBox, the
Roblox menu, any screen-owning modal (`ZyntraStoreOpen`, `DevPhoneOpen`,
`ZyntraReentryOpen`, `QueueModalOpen` via `UIDevice.ScreenOwningModalOpen`), the
dispatch briefing, the Level 1 guide, the PARTY DOWN card, `WindowFocusReleased`,
death, `CharacterAdded`/`CharacterRemoving`, `InRound` false, `RoundActive`
false, `Spectating`, `Escaped`, `Level2_ExitTransition`,
`RoundEntryControlsReady` false, and the confirm card being open. The authority
is a **per-frame re-read** of `holdBlocked()` inside the RenderStepped step; the
signals only make the same cancel happen sooner. A state nothing signals (another
script setting an attribute, a humanoid dying silently) is still caught within
one frame — there is a test for exactly that.

## Decisions I made rather than asking

1. **The hold clock is RenderStepped's own delta, not `os.clock()`.** The brief
   said `os.clock()` deltas; in this project `os.clock` is process CPU time (the
   Studio note in CLAUDE.md), which is not what a player holds a key for. The
   frame delta is wall time by construction and is what makes the bar identical
   at 15 and 240 FPS. Consequence to be aware of: a single 2 s frame hitch
   contributes its full 2 s. I did **not** clamp per-frame delta, because a clamp
   would make the stated "three 0.5 s frames complete the hold" contract false.
2. **Separator is `•` (U+2022), not `·`.** The brief wrote `HOLD L · LOBBY`. The
   game already uses `•` in 34 places (`PUBLIC • EVERYONE`, `FUSES CARRIED 3 •
   FILL A FUSE BOX`), so the chip matches house copy. Exact strings:
   `HOLD L • LOBBY`, `HOLD • LOBBY`.
3. **`UIDevice.Binding("L", "")` alone decides the glyph**; I did not also call
   `SuppressesKeyboardGlyphs()` in the script. Binding already returns `""` for
   every touchscreen *and* for a gamepad-only device (where there is no L key),
   which is exactly the wanted behaviour and one call instead of two. The test
   fake drives Binding *through* SuppressesKeyboardGlyphs so both are exercised.
4. **`chip.TextWrapped = true`.** `NOT AVAILABLE IN THIS TEST ROUND` is 32
   characters and does not fit one line in a 156 px chip; it wraps to two lines
   inside the 30 px pointer chip rather than clipping. If the owner would rather
   keep one line, shorten the copy — it is a one-string change.
5. **The chip's `Activated` handler is gone entirely.** A click on the chip does
   nothing, which is the point ("click/tap alone does not leave").
6. **Gamepad A on a selected chip also holds.** `chip.InputBegan` accepts Touch,
   MouseButton1 and Gamepad1. This adds no new binding to document and is the
   only mid-round exit a controller player has; nothing selects the chip
   automatically, so it is inert unless something does. Not QA'd (owner excluded
   controller QA).
7. **`holdInput` survives `stopHold()` and is cleared only by `releaseHold()`.**
   Clearing it on stop looked tidier and silently broke the touch latch: after a
   completed touch hold there would be no handle left to match the finger's
   release against, so the latch could never clear. The test caught it.
8. **`sendLeave()` is the single one-request authority.** I removed the duplicate
   `requestPending` test from the confirm button; a mutation probe proved the
   duplicate made the real guard untestable dead code.
9. **The confirm card renders the shared latch instead of clearing it.** Old
   `openCard()` did `requestPending = false`; a player who completed a hold and
   then died would have been handed a fresh button over an in-flight request.

## Verified offline, and how

`python tools/tests/test_round_exit_hold.py` → **294 checks passed**.
`python tools/tests/test_ui_style.py` → **83 checks passed** (unchanged; the
markers it slices — `local function makeButton` … `local title = Instance.new` —
are intact, and the new `HoldFill` lives inside that slice and runs under it).
`luau-compile.exe --binary "…/Round Exit Client.LocalScript.lua"` → OK.

The test runs the **entire real LocalScript** under a fake DataModel — fake
`UserInputService` (InputBegan/InputEnded/WindowFocusReleased/TextBoxFocused/
TextBoxFocusReleased/GetFocusedTextBox), `RunService.RenderStepped` stepped with a
stated delta, `GuiService` (MenuIsOpen/SelectedObject with real property-changed
signals), attributes with change signals on both the player and workspace,
Humanoid Died/HealthChanged, CharacterAdded/Removing, a `RoundStatus` remote that
captures `FireServer` and can push `OnClientEvent`, the `RoundExitPrompt`
bindable, a fake `UIDevice`, and the **real UIStyle module** loaded under the same
fake. No string matching anywhere: every assertion is made by driving the script
and reading back its instances and the captured remote traffic.

Covered: tap/click/short-press sends nothing and leaves no progress; a full hold
sends exactly one `leaveround`; release at 1.0 s resets the bar to 0; each of 17
cancel conditions kills a running hold; three of them re-checked with the signal
suppressed, to prove the per-frame re-read is what actually does the work; a
silent `Health = 0`; typing L into chat; a `processed` key event; four wrong keys;
`UserInputState.Change`; releasing a different key; a finger sliding off the chip;
three wrong input types on the chip; the latch after completion for both keyboard
and touch, and its release by key-up, finger-up and `WindowFocusReleased`; the 8 s
no-answer unlatch and the 3 s refusal message, including that an answered request
never trips the timer and that a layout change does not wipe an unread message;
the card path (STAY closes, confirm sends once, hammering it cannot send twice,
refusal re-enables, retry works, card timeout); the card refusing to open outside
a round; a card opened over an in-flight hold request; frame-rate independence at
0.5 / 0.25 / 0.03 / 1⁄60 / 1⁄144 s frames (each completing within one frame of
1.5 s); device rotation repainting the glyph; and the layout at 390×844, 844×390,
705×338 with a GUI inset, and 1280×720 — chip and caption both inside the safe
rect, caption left-aligned with the chip, strictly below it, 12 px off the safe
right edge.

**Mutation-probed** (each mutation applied to the real file, test run, file
restored): `HOLD_SECONDS 1.5 → 0.1` fails; removing the completion latch fails;
removing the per-frame `holdBlocked()` re-read fails; removing the one-request
guard in `sendLeave` fails. The suite is not vacuous.

## NOT verified — needs Studio / a device

- **The real mouse lock.** The whole reason for this card. Nothing offline proves
  the hold is reachable while the first-person camera owns the cursor.
- **Real touch.** A finger that slides off the chip before lifting: I rely on
  `GuiObject.InputEnded` *and* `UserInputService.InputEnded` matched on the input
  object. Both are faked here; the engine's exact behaviour for a dragged-off
  touch is the one thing I could not check.
- **Font metrics / TextBounds.** Chip widths are *stated* (156 pointer / 164
  touch, TextSize 12/13, `TextScaled = false`), not measured — TextService does
  not exist offline. `HOLD L • LOBBY` should sit comfortably; the 3 s refusal
  copy is expected to wrap to two lines.
- **Whether the engine clips `HoldFill` to the chip's rounded corner.**
  `ClipsDescendants = true` plus a matching `UICorner` on the fill is belt and
  braces; only a capture shows which one is doing the work.
- **The wash reading as progress.** `UIStyle.Color.Accent` at
  `BackgroundTransparency = 0.62`, under the chip's own label (descendants draw
  over an ancestor's text under `ZIndexBehavior.Sibling`, so an opaque fill would
  hide the words it is counting). Legibility is a capture question.
- **The `HoldHint` band not colliding with the Level 1 objectives column.** It is
  drawn only while a hold runs and is clamped to the safe rect, but the top-left
  column below the objectives button was not measured against it.
- **Gamepad.** Excluded from QA by the owner; the chip accepts Gamepad1 but
  nothing selects it.

## QA checklist for the native pass

Run a real round on each of desktop and a phone.

1. **Click/tap alone does not leave.** Alive, mid-round: click the chip (desktop,
   cursor freed however you like) and tap it (phone). Nothing must happen — no
   card, no request, no progress.
2. **Successful hold.** Hold `L` (desktop) / press and hold the chip (phone) for
   1.5 s without moving the camera off the action. The wash must fill smoothly,
   the caption must appear under the chip, and at the end the chip must read
   `RETURNING...` and then `RETURNING TO LOBBY...`; the player lands in the lobby
   and **the round continues for the others** (check a second client).
3. **Cancelled hold.** Hold for ~1 s and release. Bar must snap to empty, caption
   must vanish, nothing sent. Repeat three or four times in a row — no creep, no
   partial progress carried over.
4. **UI interactions.** While holding, in turn: open the Roblox menu; focus chat
   and type; open the Zyntra terminal/store; trigger the dispatch briefing; get a
   PARTY DOWN card; alt-tab away. Each must reset the bar. Then, specifically
   with chat focused, confirm the chip is **still visible** (it should not vanish)
   and that typing the letter `L` does nothing.
5. **Failure and retry.** In Studio Level 2 or 3 (where the lobby is parked) a
   hold must produce `NOT AVAILABLE IN THIS TEST ROUND` for 3 s and then return to
   `HOLD L • LOBBY`; release and hold again and it must retry. Also confirm that
   *keeping* the key down after a refusal does **not** re-fire.
6. **Mobile safe areas.** Phone portrait and landscape, and a notched device if
   there is one: the chip must clear the objectives button above it, the caption
   must sit fully on screen under the chip while holding, and neither may overlap
   the movement stick, the objectives/briefing band or the sprint/jump buttons.
7. **Dead path unchanged.** Die, use the spectate band's button: the STAY /
   BACK TO LOBBY card must still open, STAY must close it, BACK TO LOBBY must
   leave. Then: complete a *hold*, die before the teleport lands, open the card —
   it must show `RETURNING...` disabled, not a fresh button.
8. **Round transitions.** Hold while a round ends (win/lose/lobby) — the bar must
   reset and the chip go back to its resting prompt.

## Open questions for the owner

- The refusal copy `NOT AVAILABLE IN THIS TEST ROUND` wraps to two lines in the
  pointer chip. Keep it, or shorten (e.g. `NOT IN THIS TEST ROUND`)?
- `L` is confirmed free per the contract sweep. If anything in the batch claims
  `L` later, this is the one string to change (`HOLD_KEY`).
- After `leaveack` the chip stays latched on `RETURNING TO LOBBY...` until the
  round events arrive. If a published teleport ever *surrenders*, the player sits
  on that message until `InRound` flips. GameManager owns that path; I did not
  open it. Worth a look by whoever owns the transport.

## Texture / artwork needs

None. The chip, wash and caption are all UIStyle tokens and typography.

## Trello card #74 — text draft

> **Back to Lobby is now hold-to-leave (no mouse unlock).**
>
> The old chip needed a click, and in a live round the first-person camera owns
> the mouse — so it was unusable exactly when a player wanted it. It is now a
> hold: **L** on keyboard, **press and hold the chip** on touch, 1.5 seconds,
> with the bar filling inside the chip and a line under it saying *"Leaving ends
> your run. The others keep playing."* Releasing early cancels and the bar resets
> to zero — a click or a tap on its own now does nothing at all.
>
> The hold stops and resets on anything that should stop it: typing in chat, the
> Roblox menu, the shop/terminal/queue/re-entry panels, the mission briefing, the
> Level 1 guide, the PARTY DOWN card, losing window focus, dying, respawning,
> escaping, the Level 2 exit and the round ending. At most one leave request can
> ever be in flight, and after a completed hold the key or finger has to come up
> before another one can start.
>
> Dead and escaped players keep the existing STAY / BACK TO LOBBY card from the
> spectate band — the cursor is free there — and both paths now share the same
> single request. The server side is untouched: same `leaveround` request, same
> lobby transfer, same `Not available in this test round` answer in Studio, same
> retry after 8 s of silence.
>
> Verified offline: 294 checks running the whole client script under a fake
> DataModel (tap-does-not-leave, successful hold, cancelled hold, every cancel
> condition, the one-request rule, retry and timeout, and the layout on four
> viewports), plus the shared UI-style suite. Still to check on device: the real
> mouse lock, real touch, and the text fitting in the chip.
