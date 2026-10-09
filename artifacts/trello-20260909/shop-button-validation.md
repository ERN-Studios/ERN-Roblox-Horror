# Direct lobby SHOP button

Trello: [7FXZy8ae](https://trello.com/c/7FXZy8ae/28-lobby-add-a-direct-shop-button-below-the-equipment-button). The card requests a button directly below Equipment that opens the shop.

## Initial implementation scope (before native clipping correction)

- `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`: creates `ZyntraShopButton`, positions it 8 pixels below Equipment, applies lobby/modal visibility and input guards, and connects `Activated` directly to the existing `openKioskShop` function. A subsequent native finding also corrected the shared lobby safe-area clamp described below.
- `ReplicatedStorage/UIRegression.ModuleScript.lua`: synthetic scenario reset treats both lobby buttons consistently; the existing store-modal scenario also forbids the new opener.

SHOP inherits the established Gotham Bold/teal/dark style and responsive Equipment width. Its height is 48 pixels, above the existing 44-pixel tap minimum. Desktop is 280×48 at y=92; phone/tablet share Equipment's safe horizontal position and are placed immediately below its actual height. Equipment's new label, dimensions and developer chip behavior are unchanged.

The existing kiosk route selects the Shop page, retains terminal navigation/focus and modal ownership, and rejects activation in a round or during the queue/briefing. The new button is hidden, inactive and unselectable when the terminal is visible, when either modal suppresses the store, and during every round, including for developers.

Exact backups: `shop-button-before.lua` and `shop-ui-regression-before.lua`. Exact feature delta: `shop-button.diff`.

## Verification completed by implementation agent

Both complete Luau files compile successfully with Luau 0.737: 11 KLOC, 345 KB bytecode. `git diff --check` reports no whitespace errors (only the existing Git line-ending conversion notice). The limited diff was inspected against byte-for-byte backups; no shop routing, purchasing, inventory, terminal page content or Equipment behavior was changed.

The initial implementation added no mirrored layout tests. After native QA found clipping, the focused actual-function regression described below was added. Independent critic review found no blocking code issues and independently compiled both complete files successfully. It confirmed the existing routing guards, visibility/input suppression, developer behavior and regression integration. The final numeric score is reserved for the root's native click/layout/suppression evidence. Native verification and publication belong to the root agent; this agent did not use Studio, push scripts or publish.

## Root-owned native pass

Use the actual desktop and Studio Device Simulator phone/tablet viewports. When the simulator still advertises both keyboard and mouse capability, the existing Studio-only `ForceTouchUI` override selects the touch branch; do not call these physical-device checks.

1. Measure both buttons on desktop, phone portrait/landscape and tablet portrait/landscape. Require an 8-pixel gap, shared left/right edges, SHOP height 48, readable labels, safe-area containment and no movement-control overlap.
2. Click SHOP through real input. Require visible Shop content, other pages hidden, both lobby openers hidden/inactive/unselectable, and normal terminal close behavior restoring both buttons.
3. Apply QueueModalOpen and DispatchBriefingOpen separately. Both buttons must become hidden/inactive/unselectable, remain unable to open the terminal, and restore once the suppressor clears.
4. Enter a round. SHOP must remain hidden/inactive/unselectable. Preserve the existing developer-only touch chip and desktop J path.
5. Use existing targeted UIRegression checks for actual touch rectangles/store-modal scenario as needed. Avoid broad unrelated matrices. Stop Play to clear temporary overrides, audit the scoped push, and publish using the mouse menu only after critic score is at least 8.


## Native clipping finding and correction

The first actual iPhone 13 landscape pass found a release blocker: both buttons had x=568 and width=220, extending to 788 while the ScreenGui safe width was 749. The native layout reported Safe={Left=0, Right=749}, Display={Left=-47, Right=796}, Controls.Left=796, Count=0, Measured=true, and ScreenGui.AbsolutePosition=(0,0). With no movement controls drawn, the empty control zone correctly sits at Display.Right. The inherited lobby placement incorrectly treated that display edge as the safe boundary. SHOP is not registered as a movement control and cannot feed back into the measured control union.

The lobby now takes the smaller of Safe.Right and Controls.Left before calculating width and position. With those exact native measurements the resulting x is 521 and the right edge is 741, leaving an 8-pixel safe margin. The developer chip retains its original control bound. No UIDevice change was needed. The exact pre-correction snapshot is `shop-button-pre-safe-area.lua`; the complete feature delta remains in `shop-button.diff`.

`test_shop_button_layout.py` extracts and executes the real complete updateVisibility function from both snapshots. It reproduces the original x=568/clipping, requires x=521/safe after the correction, and retains the earlier visible-controls x=371, vertical gap, touch target heights, modal/input restoration and unchanged DEV placement. All 19 pre-correction reproduction/retention checks and 19 post-correction checks pass. Both whole changed files compile again. The test intentionally does not claim native rendering coverage; root owns the landscape confirmation and critic rescore before publication.

## Completed native verification and release

The independent critic initially scored **6/10** for the actual phone clipping and rescored **9/10** after the correction and native evidence. Desktop and phone SHOP clicks opened the actual Shop page with Upgrades hidden; terminal close restored both lobby openers. Queue/briefing guards passed. The actual touch-enabled DEV check preserved its 136×44 chip and kept SHOP hidden. Desktop/tablet observations preceded the narrow safe-area correction; phone portrait/landscape and actual Shop open/close were repeated afterwards. These are Studio Device Simulator checks using the existing ForceTouchUI override, not physical-device certification.

The final `shop-button-phone-no-controls-fixed.jpg` now shows the **actual Controls.Count=0** state reproduced by native portrait→landscape rotation. The saved `exactNoControlsFixed` probe has safe right=749 and button right=741; the corresponding button x=521, width220 leaves an 8-pixel margin. Earlier manual attempts to hide controls were overridden by normal callbacks and did **not** reproduce Count=0; they were restored and are not counted as coverage. The final image and JSON supersede those attempts.

Evidence: `shop-button-native.json`, the exact `shop-button.diff`, six final native images (desktop; phone portrait, landscape and no-controls-fixed; tablet portrait and landscape), plus the separate before-fix phone image. Final Edit compilation was **122/122**, zero failures and no unstaged scripts. Audit was **122 matched, zero drift**, with one permitted trailing-newline difference. Play was stopped before release.

Root mouse-published through **File → Publish to Roblox**. Native Studio Output confirmed **v1823 on 10 September 2026 at 00:04:44.705 Europe/Copenhagen**. Trello 7FXZy8ae was updated with the original request preserved, moved to Done and marked complete.


Final independent review after the native correction: **9/10**, improved from 6/10 for the observed clipping. The critic independently inspected corrected images and repeated both full compiles plus the 19-before/19-after checks. Root verified the actual empty-control branch after physical simulator rotation, Shop click/close, modal guards and unchanged in-round DEV behavior. Root mouse-published v1823 on 10 September at 00:04:44.705 Danish time.
