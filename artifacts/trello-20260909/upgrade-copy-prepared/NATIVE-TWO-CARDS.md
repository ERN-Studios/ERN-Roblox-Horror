# Two exact upgrade descriptions — native check

Prepared instructions only. No UI, Studio, source, purchase or profile action was performed. Current Store readback on disk is `749afb8362e159940ab1f719fe74f8f1bc9ce84a495d41bd08f6306b79768151`; the current two-string proposal is `083c53b7639a578c64398f1da077745c07f1d99d03fd8421c660ef9619d87c71`. Apply the existing narrow transform to the immediate input if other Store work lands first.

1. In normal lobby, after the existing profile is loaded and blocking modals are closed, click **UPGRADES & GEAR** (`PlayerGui.ZyntraStore.ZyntraOpenButton`). Select **UPGRADES** explicitly if another tab was retained: `PlayerGui.ZyntraStore.Terminal.TerminalTabs.UpgradesTab`.
2. The page is `PlayerGui.ZyntraStore.Terminal.TerminalContent.Upgrades`; its scroll is `UpgradeCards`. The cards are uppercase **`STAMINA`** and **`BATTERY`**, not their complete displayed titles. Their named labels are:

| Actual relative path under `UpgradeCards` | Exact new text |
|---|---|
| `STAMINA.Description` | `Run for longer before exhaustion.` |
| `BATTERY.Description` | `Keep the flashlight active for longer.` |

3. With actual content width at least 520 px, the cards occupy two columns. Below 520 they are sequential rows, each 330 px high with 12 px spacing. Use the normal scroll to reach BATTERY; the Entity Shield card follows, so do not assume the bottommost card is Battery. Capture each shortened description visibly, with its title and readout. A scroll-clipped offscreen card is not a text-fit failure, but it is not a visual screenshot of that card either.
4. Read `Description.Text`, `TextFits`, `TextBounds`, `AbsoluteSize`; require exact text, `TextFits=true`, and actual on-screen rendering when its screenshot is taken. Confirm both former second sentences are absent, and the title, percent/level and existing Spend button still appear normally. No purchase, token spend, gameplay replay or new broad regression suite is needed for two literal removals.

Optional one-shot **read-only Play Client** extraction after opening the real Upgrades page (no selection/scroll mutation):

```lua
local p=game:GetService("Players").LocalPlayer
local terminal=assert(p.PlayerGui:FindFirstChild("ZyntraStore")).Terminal
local page=terminal.TerminalContent.Upgrades
assert(terminal.Visible and page.Visible,"Open the actual Upgrades page first")
local scroll=page.UpgradeCards
local rows={}
for _,name in ipairs({"STAMINA","BATTERY"}) do
 local d=scroll[name].Description
 table.insert(rows,{Name=name,Text=d.Text,TextFits=d.TextFits,
  TextBounds={d.TextBounds.X,d.TextBounds.Y},Size={d.AbsoluteSize.X,d.AbsoluteSize.Y},
  Position={d.AbsolutePosition.X,d.AbsolutePosition.Y}})
end
return game:GetService("HttpService"):JSONEncode({Rows=rows,
 ScrollPosition={scroll.CanvasPosition.X,scroll.CanvasPosition.Y},
 ScrollSize={scroll.AbsoluteSize.X,scroll.AbsoluteSize.Y}})
```

The script reports rectangles, not a claimed effective visibility test. Root's actual screenshots provide that evidence. Close through the normal `Terminal.CloseTerminal` button, then use the existing exact-source audit/publication workflow. This card's native check is separate from the remaining ESP/respawn/square-button features.
