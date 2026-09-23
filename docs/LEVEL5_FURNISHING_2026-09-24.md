# Level 5 — domestic furniture, unlit houses and tall wall drawings

The Indoor Suburbs now has 20 sparsely furnished rooms, four tall transparent wall drawings, and no small house lights or glowing house fixtures. The eight-district layout, developer access and tinted windows are preserved. This remains a map preview: no entity, puzzle, slide controller or completion rewards were added.

## Appearance

- Five restrained room arrangements: sofa/TV lounge, reading corner, dining room, joined chairs, and sparse sitting room. Most rooms contain only three or four domestic pieces.
- Furniture is actual anchored 3D geometry with cushions, arms, backs, wooden legs, veneer cabinets, chairs and CRT bodies. Generated images provide woven upholstery and the switched-off CRT front. One dining table has misaligned supported halves; paired armchairs share an uncanny junction and different back heights.
- Removed individual house interior lights, exterior sconces, the final house's decorative lamps, and two suspended subdivision fixtures. Shared overhead fluorescent panels and canyon circulation lighting remain. All 356 window panes remain dark tinted Glass.
- Four architectural charcoal/graphite drawings show impossible stacked houses and stairs. Their carriers are 42, 54 and 87 studs tall. Both generated PNGs have real partial/zero alpha; the wall shows through, with no backing rectangle or emitted light. Carriers do not collide, cast shadows or participate in ray queries.

Artwork, complete prompt records where available, asset IDs, file hashes and alpha measurements are in `assets/level5/furnishing20260924/`. The first upholstery upload timed out during Roblox content delivery; its replacement, `132119936960491`, successfully loaded in Play. The original is retained only as superseded provenance.

## Verification performed

The final fresh Play build passed the read-only runtime inspection:

| Check | Result |
| --- | ---: |
| Furnished rooms / furniture parts | 20 / 891 |
| Checked furniture corners | 7,128, zero failures |
| Reserved central passage | 7 studs per furnished room |
| House models inspected | 114 |
| Light instances / Neon inside house models | 0 / 0 |
| Consistent tinted windows | 356 |
| Transparent mural carriers / decals | 4 / 4 |
| Map BaseParts / architecture descendants | 11,900 / 12,820 |
| Shared circulation/ceiling lights | 58 |

Visual Play screenshots cover the house-tower mural, the 87-stud stair drawing, the off CRT, woven sofa, joined chairs and split dining table. All four active uploaded images loaded successfully. The stair artwork intentionally has lighter graphite strokes than the house-tower artwork.

The actual Humanoid walked through CourtCottage_01, DetachedWaitingRoom_1, CourtCottage_03, WestLoungeFurniture, CutawayReadingRoom and SecretThroughHouse: 17 target arrivals passed. Server repositioning was used only to set up each independent room check; this is not a claim of one uninterrupted whole-map traversal. The existing expansion report records the earlier traversal across all eight districts. Holding L returned the character to the lobby. The world still existed at the one-second snapshot; delayed cleanup was not reasserted by this test.

The broad game review is in `WHOLE_GAME_QA_2026-09-24.md`. Additional actual Studio checks passed Level 2 layout generation for seeds 1/101/7331, Level 3's official nine layout seeds and twenty navigation seeds, and Level 4's 163 plan plus 18 brain assertions. An initial three-seed Level 3 probe was too small for that suite's diversity contract; it was corrected to the official defaults. These are bounded checks, not full multiplayer playthroughs or physical phone/tablet performance measurements.

## Small confirmed bug corrected

Level 1's entry briefing previously counted circuits directly from player count while the actual puzzle uses half the party rounded up. The briefing now uses the same clamped `ceil(players / 2)` rule. The focused test extracts the actual GameManager and PuzzleManager source assignments, including the old two-player mismatch.

A separate confirmed completion-save failure can lose a player's reward/progression while still attempting a badge. It remains open at [Trello EYpXKa9S](https://trello.com/c/EYpXKa9S); safe recovery needs an idempotent completion transaction and is not folded into this visual change.

## Studio and concurrent developer work

The initial 176-script baseline matched the repository. The final 178-script export has zero editor/source conflicts. This task changed Architecture, Landmark Districts and the one GameManager briefing expression, and added Furniture. The other developer added ZyntraRecordsPage and changed UIRegression/ZyntraStore while this task was running; those three scripts match remote `2e5cfd8` exactly and are preserved. Their focused checks passed 2,465 Records-page, 42 Challenges and 544 compact-store assertions. All twelve Level 4 sources are byte-identical to the baseline.

The remote Records UI and repaired test harnesses were merged from `claude/trello-20260921`. Manifest conflicts were resolved from the fresh authoritative Studio export, preserving the earlier native backup and publication history. All 178 runtime mirrors match that export exactly. The fifteen historical RemoteEvent records were retained, not reverified by this script export.

## Delivery status

Save to Roblox succeeded at `2026-09-23T22:31:25Z`. A full local native post-change copy was verified (16,715,956 bytes, SHA-256 `4c849ff7e68576fd0092408c93779c988708db7d0b3f3be10357c06fe01d3a4a`), despite a delayed UI response. Existing v2026 backup is also preserved. Publication confirmation remains pending. Do not treat the earlier v2026 publish receipt as publication of this update. The final publication receipt, when available, belongs in `artifacts/level5-furnishing-20260924/` and `studio-sync-manifest.json`.

The [Level 5 Trello card](https://trello.com/c/Y2xXThBN) remains In Progress for its future gameplay work. Completed furnishing/visual/traversal items can be checked independently; delivery remains unchecked until verified.
