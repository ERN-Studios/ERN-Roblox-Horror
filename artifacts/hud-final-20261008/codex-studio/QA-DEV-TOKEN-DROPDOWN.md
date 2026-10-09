# Actual DEV token recipient dropdown QA

Source audit only, 2026-10-09. No Studio calls or product changes.

The product has a scrolling dropdown with five visible rows, rather than the old three-player chip row. Native opening: invoke PlayerGui.ZyntraDevL4.UIRegressionZyntraDevL4Probe with `open`, then click the Economy tab: `Root.WindowHolder.WindowFit.DevWindow.Canvas.Categories.Items.Tab_Economy`. Menu still requires real DevAccess; grants/selector are desktop-only by the existing policy.

The mounted grant row is `Root.WindowHolder.WindowFit.DevWindow.Canvas.Pages.Page_Economy.Economy.Economy.Dev_grantTokens`. Find its `PlayerSelect` descendant; it lives inside `Items.PlayerRow.PlayerPicker.PlayerPicker.Items`. The floating `PlayerList` ScrollingFrame is a DIRECT child of ZyntraDevL4, outside Root so the page does not clip it. Rows are direct PlayerList.Player_1 through Player_N, sorted by lowercase player Name. Giving is the separate Action_grantTokens button: do not press it.

Existing probe operations are only open, close, state, press:<id>. There is NO roster injection. Internal rebuild takes actual Players:GetPlayers() only. A single-client native playtest cannot produce eight genuinely wired player rows through an existing seam without eight real test clients. Do not parent fake Players into the service. Cloned display rows would only prove appearance, not production row-eight selection.

Offline evidence: `artifacts/shop-ui-figma-20261005/roblox-draft/dev-menu/tests/test_zyntra_dev_l4.py` PASS 6965 checks across seven template variants; draft source is byte-identical to product (SHA2564a0c96c62010ba65d3a6953f4888e3714754f0a17e6d0df72deb62adb58fe476). Its harness lines474-499 builds eight fake-service users, checks Player_8 exists, canvas exceeds viewport, successfully selects row6, and checks gamepad focus/close. It does not claim native row8 reach. `tools/tests/test_token_grants.py` PASS243 checks with fake store/remote only.

For a native eight-client lobby or an explicitly added Studio-only presentation roster seam, first read actual list CanvasSize, AbsoluteCanvasSize, AbsoluteWindowSize, and row8 geometry. The product computes rowHeight=max(24,selector.AbsoluteSize.Y), fullCanvas=4+N*(rowHeight+4), viewport=min(fullCanvas,4+5*(rowHeight+4)).

Client readback/scroll recipe (requires actual eight wired rows; grants are never pressed):

```lua
local p=game.Players.LocalPlayer
local gui=p.PlayerGui.ZyntraDevL4
local list=gui.PlayerList
local row8=assert(list:FindFirstChild("Player_8"), "eight actual wired rows required")
local row=gui:FindFirstChild("Dev_grantTokens",true)
print("canvas",list.CanvasSize,"nativeCanvas",list.AbsoluteCanvasSize,"window",list.AbsoluteWindowSize)
list.CanvasPosition=Vector2.new(0,math.max(0,list.AbsoluteCanvasSize.Y-list.AbsoluteWindowSize.Y))
-- Allow one engine frame, then reacquire/read:
print("row8",row8.AbsolutePosition,row8.AbsoluteSize,"list",list.AbsolutePosition,list.AbsoluteSize)
assert(row8.AbsolutePosition.Y>=list.AbsolutePosition.Y-1)
assert(row8.AbsolutePosition.Y+row8.AbsoluteSize.Y<=list.AbsolutePosition.Y+list.AbsoluteSize.Y+1)
-- Native click row8. Only selection changes locally; do not click GIVE.
-- Then inspect row:GetAttribute("SelectedUserId") and PlayerSelect caption.
```

No new seam was added by this read-only audit. A safe future Studio-only presentation seam should create plain roster records privately in the owning DEV LocalScript (no Players parenting), rebuild using the real picker path, and explicitly refuse grants while the presentation roster is active. That is additional product work, not a capability the current probe already has.
