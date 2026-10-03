# UI research: popular Roblox backrooms games (2026-10-03)

Joined in the real Roblox client on the Mac (account LaverSneglen), screenshots in `screens/`.
Player counts are from Roblox search at about 18:40.

| Game | Link | Playing | Inspected | Not inspected |
|---|---|---:|---|---|
| Backrooms Company | https://www.roblox.com/games/109423220190564 | 5,517 | update log, lobby HUD, shop (Passes, Upgrades), inventory | Emotes/Donate tabs, an actual run (in-round HUD, prompts) |
| M.E.G. Endless Reality | https://www.roblox.com/games/98629859043211 | 5,183 | lobby HUD, shop, controls panel | badges, a run |
| Unseen Liminality | https://www.roblox.com/games/82797688803922 | 6,039 | main menu, store, in-game HUD (hotbar, stamina, key hints) | teleports, item use on a target, prompts |
| Backrooms (9273658706) | https://www.roblox.com/games/9273658706 | 3,048 | join screens, gameplay HUD, shop | titles, crates, rewards |

Not entered: Build Your Backrooms (4,191), Shrek in The Backrooms (2,006). No game was played on a phone;
mobile observations are inferences from layout. No purchase flow was taken past the first screen.

## What works
- **Backrooms Company**: the best shop of the four. Tabs on top, a grid of square item cards with a big icon
  and price, and a persistent detail pane on the right with one description, one price, one PURCHASE button.
  The inventory reuses the same frame (grid + detail + EQUIP), so players learn one layout. Upgrades are rows
  of five pips with a + button: progress is readable at a glance. The lobby HUD is one icon bar at the bottom.
- **Unseen Liminality**: the cleanest in-game HUD. Three item slots with names bottom-left, one stamina bar
  under them, key hints in small text bottom-right, nothing else. The world stays visible. Main menu is three
  words (PLAY / STORE / TELEPORTS).
- **M.E.G.**: a CONTROLS panel listing PC and Xbox bindings side by side; cheap and useful.

## What works poorly
- **Backrooms (9273658706)**: update log, instructions and a "do you want the tutorial" dialog all draw on top
  of each other at join; the shop is a grid of 16 near-identical gold circles with prices overlapping names.
- **M.E.G.**: the shop is a text list of Robux amounts, no item art, no descriptions; the pixel font is hard to
  read at small sizes; player billboards in the lobby pile up into unreadable text.
- **Backrooms Company**: overhead player stats in the lobby overlap into a wall of text; a group-join popup
  appears over the update log on entry (two modals deep before the player sees the game).
- **Unseen Liminality**: store cards mix photo thumbnails and renders, so the grid looks inconsistent.

## Our own UI (captured the same day in Studio)
- Shop (`own_03_shop.jpg`): coherent terminal look, but it is a single column of wide cards, two items per
  screen, and the left card repeats what the right detail pane says. Seven equal tabs with no icons. Item art
  is a small line icon in a circle; the price is not on the card at all (only OWNED or the detail pane).
- Lobby HUD (`own_01_lobby-hud.jpg`): left rail of five buttons is clear. **Roblox's chat window opens on top
  of the rail and blocks Shops/Upgrades** (`own_02_chat-covers-left-rail.jpg`); a scripted click there hit
  CoreGui. The briefing bar and the Friend Boost card are fine.
- Round HUD was not re-captured today (Level 6's objective card and TAGS counter were reviewed earlier).
