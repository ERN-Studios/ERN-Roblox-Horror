# Level 4 material sources — 23 September 2026

These five original PNGs were made with Codex's built-in imagegen tool for **The Quiet Suburbs** art pass. They are source images in the repo and now have group-owned Roblox `Image` IDs. They are **not yet active game materials**. Keep the current live Studio baseline authoritative; Claude owns the runtime integration.

| File | Intended use | Roblox group image ID |
|---|---|---|
| `siding-cream-v1.png` | Faded-cream near facades | `rbxassetid://77541865358370` |
| `siding-dusty-yellow-v1.png` | Dusty-yellow alternate facades | `rbxassetid://120074734376273` |
| `siding-blue-grey-v1.png` | Blue-grey alternate facades | `rbxassetid://122418696615381` |
| `ceiling-panel-lit-v1.png` | Repeating fluorescent-face ceiling panel | `rbxassetid://79500496492388` |
| `ceiling-panel-dark-v1.png` | Dark companion ceiling panel | `rbxassetid://78521295543756` |

All images are 1,254 × 1,254 px RGB albedo sources. The three siding variants share the same board layout and graining. The two ceiling variants share the same boundary design. An 8-pixel border comparison gave mean absolute RGB differences of **2.1–2.5/255 left-to-right** and **2.6–3.6/255 top-to-bottom** across the set; this is a source-image seam check, not a Studio visual acceptance test.

The images should be reused as tiled surfaces, not copied into each decorative floor as unique assets. A first placement could map one siding image across a 10 × 13-stud facade bay and one ceiling image across a 20 × 20-stud panel; Claude must set the final face axes and tile scale from the actual arrival-slice geometry. Keep upper/far facade detail simpler than the near houses, and preserve the task-facing house anomalies, `Level4_Placeholder` audit, named objective sockets, doors, safe-house signals and collision. The bright ceiling image **does not emit light**. Any real lights must stay within the existing maximum of 12 dynamic lights; the giant ceiling can be mostly visual.

These IDs were verified on 23 September 2026 as group-owned `Image` assets in ERN Roblox Studios' inventory (group `1039373905`), and all five loaded as `EditableImage` in Studio. The Roblox copies are 1,024 × 1,024 px; keep the 1,254 × 1,254 source PNGs in GitHub. Claude should A/B the tiles at normal player height and on a narrow/low-graphics viewport before switching the art pass on. Check line density, repeated seams, texture memory and whether the anomaly clues still read from the street. No game code or Studio instances were changed for this pack, and no publish was performed.

Generation prompt set, summarized: a flat orthographic, edge-to-edge, seamless cream clapboard albedo with straight horizontal board seams, subtle paint/grain and no lighting or props; two precise recolors of that source to muted dusty yellow and blue-grey while preserving every seam; a flat orthographic olive-grey ceiling tile with one recessed warm-white rectangular fluorescent face and no painted bloom; a precise edit removing only that fixture to create the dark companion tile. Each prompt excluded text, logos, perspective and watermarks. Tool: built-in `imagegen`, not Higgsfield.

Visual direction and constraints: `docs/LEVEL4_VIDEO_DIRECTION_2026-09-22.md`, `docs/LEVEL4_CONTRACTS_2026-09-21.md` §§5–8 and `assets/concepts/level4-indoor-suburbs-v1.png`.
