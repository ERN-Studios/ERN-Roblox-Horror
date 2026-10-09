# UIRegression: the `ZyntraShopL4FitMatrix` lane (spec, SHOP_UI_L4_20261005)

A later edit to the mirrored `ReplicatedStorage/UIRegression.ModuleScript.lua`
(Studio first, then mirrored), **before** the owner sets `ShopUIVersion = "L4"`.
Nothing here is applied yet. UIRegression is 9.4k lines; every change below is
an addition except item 1, which is a two-line guard in two existing places.

## 0. What the L4 window publishes for this lane (already in the draft)

| Seam | Where | Shape |
|---|---|---|
| `UIRegressionZyntraShopL4Probe` (BindableFunction, Studio only) | `PlayerGui.ZyntraShopL4` | `open` / `open:<Tab>` -> bool, `close`, `tab:<Name>` -> current tab, `cards` -> `page\|key\|action` lines, `state` -> `page\|key\|action\|<caption>` lines |
| `ZyntraShopL4Card` attribute | every bound action's input target (the Buy GuiButton, or the `Hit` laid over a Frame) | `page\|key\|action`, one-to-one with `cards` |
| `ZyntraStoreOpen` | player attribute | `true` while open, `nil` closed (same name as legacy) |
| Root / fit | `ZyntraShopL4 > Root > WindowHolder > WindowFit > ShopWindow` | `WindowHolder` = `UIDevice.Layout().ModalViewport` exactly on a pointer layout; on touch (`Layout().IsTouch`) its Left/Width with `Safe`'s Top/Bottom (the 8 px vertical margins go to the window); `WindowFit` aspect-locked to the authored window |

`cards` today lists 26 actions: Shop 6 (`Buy`), Upgrades 5 (`Buy`), Skins 6
(`Buy`), Donate 5 (`Buy`), Colors 4 (`Save` and `GetPass` per picker).

## 1. Keep the LEGACY lanes legacy (required, or they fail with the flag on)

With the routing hunk in, `openKioskShop` asks the L4 bridge first. The legacy
rows call `UIRegressionZyntraStoreProbe:Invoke("kiosk")` (lines ~4967, ~5005 and
the terminal matrix), so with `ShopUIVersion = "L4-dev"` on a developer account
the kiosk path would open **L4** and the legacy assertions would fail.

- Add `"ShopUIVersion"` to `BORROWED_WORKSPACE_ATTRIBUTES` (line ~2206), so
  `Fit.borrow` / `Fit.restore` / `Fit.residue` cover it.
- In `Fit.bodyZyntraTerminalFitMatrix` and the store-modal rows (the block around
  line ~4920 that calls `storeProbe:Invoke("kiosk")`), right after
  `local saved = Fit.borrow()`: `workspace:SetAttribute("ShopUIVersion", nil)`.
  `Fit.restore(saved)` puts the owner's value back.

## 2. Captions: `Fit.ZyntraDisabledCaptions` (line ~5279)

Append four Lua patterns (no literal `...`, per the comment above the list):

```lua
	-- SHOP_UI_L4_20261005: the L4 window's stated reasons.
	"LOADING", "CHECKING", "NEED %d+ MORE", "%d+/%d+ CLEARS",
```

`CHECKING` (unanchored `string.find`) covers both `CHECKING PRICE` (a verified
price in flight) and bare `CHECKING` (a pass whose `ZyntraOwns*` attribute, or
the Token Earner's `ZyntraTokenEarnerMultiplier`, the server has not published
yet -- the first seconds after `ZyntraProfileLoaded`).

Already present and also used by L4: `OWNED`, `COMING SOON`, `WAITING`,
`UNAVAILABLE`, `CONFIRMING`, `SAVING`, `EQUIPPED`, `LOCKED` (L4's locked colour
Save reads `LOCKED`; a Robux suit whose pass flipped before its profile grant
reads `SAVING...`). Enabled L4 captions (`R$ n`, `BUY \u{B7} R$ n`, a bare token
cost, `EQUIP`, `RETRY REQUEST`, `SAVE COLOR`) need no entry.

No `Fit.ZyntraExpectedActive` row for L4: unlike legacy, L4 stands short
Upgrades/Supplies down (`NEED n MORE`), so every L4 page is account-dependent and
held to the complete-accounting rule (section 3, check 4) instead.

## 3. The lane

```lua
function Fit.bodyZyntraShopL4FitMatrix(): (string, number)
function UIRegression.ZyntraShopL4FitMatrix(token: string?): (string, number)
	return Fit.lane("ZyntraShopL4FitMatrix", token, Fit.bodyZyntraShopL4FitMatrix)
end
```

Run it from the aggregate run directly **after** `ZyntraTerminalFitMatrix`
(line ~9305), with the same `lease.Token`.

Body, in the shape of `Fit.bodyZyntraTerminalFitMatrix`:

1. `Fit.awaitQuietDispatch()`, then `local saved = Fit.borrow()`.
2. `workspace:SetAttribute("ShopUIVersion", "L4-dev")` (restored by `Fit.restore`).
   Find `PlayerGui.ZyntraShopL4` and its probe. **Absent probe:** a SKIP line
   ("L4 shop not installed") while the saved place's flag is not `"L4"`, and a
   FAIL when it is (the release must never ship without its lane).
3. `local cards = probe:Invoke("cards")` -> the authored set, split into pages.
4. For each `device in Fit.Devices` (same forced-viewport mechanism as the
   terminal matrix) and each tab in `Upgrades, Shop, Skins, Donate, Colors`:
   `probe:Invoke("open:" .. tab)`, `task.wait(0.15)`, then record:
   1. **Opened.** The invoke returned `true`; `ZyntraStoreOpen == true`.
   2. **Fit.** `WindowHolder`'s absolute rect equals `ModalViewport` (on a
      touch row: `ModalViewport`'s columns, `Safe`'s rows); `WindowFit` lies inside it; `ShopWindow` fills `WindowFit`.
   3. **Tap floor.** Every descendant of the visible `Page_<tab>` carrying
      `ZyntraShopL4Card`, if `Active`, has `AbsoluteSize.X` and `.Y` >=
      `Fit.ZyntraFloorFallback` (44). Measured on the input target (the Hit), which
      is the face's full size. The same floor applies to the window chrome the
      cards list does not carry: the `Close` hit and the five `Tab_*` hits (find
      them by base name under `ShopWindow`; `Hit` child first, else the node).
      `Close` is the only way out on a touch device without a gamepad.
   4. **Accounting.** For the page: reachable (Active, Visible chain, >= floor)
      plus stood-down-with-caption (not Active and `Fit.zyntraDisabledReason`
      matches its caption, read from `probe:Invoke("state")` by the attribute
      id) equals the page's `cards` lines exactly. An inactive action with no
      recognised caption is the "died silently" failure, as in legacy.
   5. **Text floor.** Every visible TextLabel/TextButton under `ShopWindow` with
      non-empty text renders >= 11 px (the same measurement the terminal lane
      uses for TextScaled text; record the node's full name on failure).
   6. **Forbids.** The five rail buttons (`ZyntraShopButton`, `ZyntraOpenButton`,
      `ZyntraRewardsButton`, `ZyntraWheelButton`, `ZyntraMusicButton`) are not
      Visible+Active while the window is open; `ZyntraLobbyPillL4.TokenPill` is
      not Visible.
   7. `probe:Invoke("close")` -> `ZyntraStoreOpen == nil` and the rail is back.
5. `pcall` the whole sweep; always `probe:Invoke("close")`, `Fit.restore(saved)`,
   and record `Fit.residue(saved)` empty, exactly like the terminal matrix.

## 4. Rail rows with the skin on

The existing rail rows (`ZyntraStore:FindFirstChild("ZyntraShopButton")` ...)
keep passing with the flag unset. Run the aggregate once more with
`ShopUIVersion = "L4-dev"` to measure the grafted labels: they carry a
`UITextSizeConstraint` with `MinTextSize = 11`, which is what holds the text
floor at the 52 px rail size. The skin never renames or reparents a legacy node.

## 5. Owner-visible numbers to report from the first run

- Any action under 44 px at 705x338 with the 58 px inset (plan section 6 Q1).
- The `Fit.Devices` rows where the wheel's odds panel is shown vs the field odds.
