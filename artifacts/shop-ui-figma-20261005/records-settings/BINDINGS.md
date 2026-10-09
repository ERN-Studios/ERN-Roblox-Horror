# L4 RECORDS and SETTINGS pages: binding contract (2026-10-07)

Figma file `7FXycGKH6OT6Lme6FV3VBc`, export frame `ZyntraShop_L4` (91:3) on page "L4 · Roblox export" (91:2).
Both pages sit in `Pages` (91:83), 1680x656, stacked on top of the five shop pages, all VISIBLE.
They are native frames and text only: no new images, no new fonts.

Review frames on "L4 · Bento Home" (35:2), in section 35:3, in a new row under the Colors frames (y 8160):

| Frame | Id | Shows |
|---|---|---|
| L4 / Records | 159:2548 | Records page at the top of the scroll, CLEAN view, a realistic state mix |
| L4 / Records · Scrolled | 160:2548 | The same page at its real maximum scroll (Content_list y -358 = 466 - 824): Level 3 and Level 4 |
| L4 / Settings | 159:3304 | Settings page v2 (its Page_Settings clone is 172:47), every switch at its config Default, `Settings_active` shown |

Screenshots: `records.png`, `records-scrolled.png`, `settings-v2.png` in this folder. `settings.png` is the superseded
v1 (four tall cards with a 280x136 toggle box) and is kept for comparison only.

Review fixes (2026-10-07, after the build):
- The Level 2 sample was impossible. A CLEAN solo best of 9:58 is under the 10:00 goal, so `Challenges.Apply` would have
  set `TimeGoal["2"]` in the same write, but the card showed NOT YET. Level 2 SoloTime now reads 10:42 in the export frame
  (157:53) and in both review frames (159:3152, 160:3152). Keep sample times consistent with the challenge chips:
  a clean time at or under the goal means that goal is DONE.
- The scrolled review frame used to sit 62 px past the end of the list. It now shows the real maximum scroll.
- `records.png` and `records-scrolled.png` were re-taken. `settings.png` is unchanged.

## Naming rules the controller relies on

- `Binder.base` strips the tags `_button _scroll _list _txt ...`. Layer `Desc_txt` binds as `Desc`; `ShowAssisted_button` binds as `ShowAssisted`.
- **The scrolls are `RecordsList_scroll` and `SettingsList_scroll`, NOT `Records_scroll` / `Settings_scroll`.**
  `Records_scroll` has the base `Records`, the same as the header's `Records_button`. `Binder.find(window, "Records")` (Zyntra Shop L4, header wiring) would then depend on child order.
- **The setting rows use the exact `ZyntraConfig.AccessibilitySettings[i].Key`:**
  - `Setting_LobbyMusicEnabled`, not `Setting_LobbyMusic`.
  - So `need(page, "Setting_" .. entry.Key)` works for all four rows with no mapping table.
  - Skip entries with `Hidden = true` (`DisableCaptions`). They have no row.
- Every bindable node is VISIBLE in the export frame, because Framewisp imports only visible layers. That includes both EQUIPPED badges on every card. The controller hides what does not apply. The review frames show the hidden states.
- Search a card's children by name inside that card. `Title`, `Name`, `Reward`, `State` and `Label` repeat on purpose.

## Page_Records (157:6)

Data: `profile = ctx.profile()`, `rows = ZyntraChallenges.Rows(profile.Records, profile.Challenges, Config.Challenges)`, one row per `Config.Challenges.Levels` = {1, 2, 3, 4}. `Challenges.FormatTime` gives `m:ss` (whole seconds, no tenths).

### Intro: RecordsIntro (157:7)

| Binding | Id | Driven by |
|---|---|---|
| `RecordsIntro/TitleCol/Eyebrow` | 157:9 | View mode: "CLEAN RUNS" or "ASSISTED RUNS". The export sample is the longer one. |
| `RecordsIntro/TitleCol/Title` | 157:10 | Static "RECORDS". |
| `RecordsIntro/Desc_txt` (base `Desc`) | 157:12 | Static, the legacy NOTE text. |
| `ShowAssisted_button` (base `ShowAssisted`) | 157:13 | Tap flips client-local `showAssisted` and re-renders. It sends nothing to the server. |
| `ShowAssisted_button/Track` | 157:14 | OFF: INK #05090B fill, 3px SAGE stroke. ON: RAIL TEAL #44DDC4 fill, no stroke. |
| `ShowAssisted_button/Track/Knob` | 157:15 | OFF: x 6, SAGE. ON: x 38, INK. |
| `ShowAssisted_button/ShowAssistedLabel` | 157:16 | Static "SHOW ASSISTED", CREAM. The track carries the state. |

Button face: OFF is TILE_HI #1D262A with a 3px LINE #263134 stroke. ON is OWNED_FILL #10292A with a 4px RAIL TEAL stroke. This is the dev menu toggle.

### List

| Binding | Id | Driven by |
|---|---|---|
| `RecordsList_scroll` | 157:17 | Vertical scroll, 1680x466 at y 190. |
| `RecordsList_scroll/Content_list` | 157:18 | Vertical list, gap 16, 4 cards of 194. Canvas height = 824. |

### Cards: Record_Level1..4

Ids: Record_Level1 157:19, Record_Level2 157:46, Record_Level3 157:73, Record_Level4 157:100. Children, with the Level 1 ids and what drives each:

| Child | L1 id | Driven by |
|---|---|---|
| `TitleCol/Title` | 157:21 | "LEVEL " .. row.Level |
| `Times/SoloRow/SoloLabel` | 157:25 | Static "SOLO" |
| `Times/SoloRow/SoloTime` | 157:26 | `row.Records["solo:" .. view]`. Present: `FormatTime(record.Best)` in CREAM. Absent: "—" (em dash) in SAGE. |
| `Times/SoloRow/SoloBadge` | 157:27 | `.Visible = record ~= nil and record.Equipped == true` |
| `Times/SoloRow/SoloBadge/Label` | 157:28 | Static "EQUIPPED" |
| `Times/PartyRow/PartyLabel` | 157:30 | Static "PARTY" |
| `Times/PartyRow/PartyTime` | 157:31 | Same as SoloTime, key `"party:" .. view` |
| `Times/PartyRow/PartyBadge` | 157:32 | Same as SoloBadge, for the party record |
| `Challenges/Challenge1/Name` | 157:37 | Static "NO DEATHS" |
| `Challenges/Challenge1/Reward` | 157:38 | `tokens(Config.Challenges.RewardTokens.NoDeath)`, giving "+3 TOKENS". Not done: ICON TEAL. Done (paid): SAGE. |
| `Challenges/Challenge1/State` | 157:39 | `row.NoDeath`. Done: RAIL TEAL fill. Not done: TILE_HI fill. |
| `Challenges/Challenge1/State/Label` | 157:40 | Done: "DONE" in TILE #161D20. Not done: "NOT YET" in SAGE. |
| `Challenges/Challenge2/Name` | 157:42 | `"UNDER " .. FormatTime(row.TimeGoal)`: UNDER 8:00, 10:00, 10:00, 12:00. Hide `Challenge2` when `row.TimeGoal == nil`. |
| `Challenges/Challenge2/Reward` | 157:43 | `RewardTokens.TimeGoal`, coloured as Challenge1 |
| `Challenges/Challenge2/State` (+ `/Label`) | 157:44 / 157:45 | `row.TimeGoalDone`, styled as Challenge1 |

Level 2, 3 and 4 use the same shape. Their ids run in the same order from the card id: L2 157:46..72, L3 157:73..99, L4 157:100..126. The full path-to-id list is at the end of this file.

`view` = `showAssisted and "assisted" or "clean"`. Challenges are clean-only by definition, so they do not change with the view.

Card visibility: `Config.Challenges.HiddenUntilPlayed` is `{}` today, so all four cards always show. If a level is ever listed there again, hide its card until `played(profile, row)` is true, the way the legacy page does.

The `Times` column is a fixed 529 px. Hiding a badge must not move the Divider or the challenge column.

## Page_Settings (158:2) — v2, 2026-10-07

Owner feedback on v1 (four tall cards, each with a 280x136 ON/OFF box, list scrolled and cut the 4th row in half):
"make it look more like normal game settings". v2 is a grouped settings list that fits the 1680x656 page with no
scroll: two section headers, compact 136 px rows in a panel per section, thin separators, a classic pill switch.

Data: `Config.AccessibilitySettings`, minus `Hidden` entries. The state is the player attribute of the same name (`player:GetAttribute(Key)`, falling back to `Default`). A tap sends the existing `ZyntraAction "SetAccessibility" {Key, Enabled}`, which ZyntraStore already validates and floor-limits. LobbyMusicEnabled keeps ZyntraStore's own special-case path (lines 840-881).

**What changed for the controller (v1 -> v2):**
- `SettingsList_scroll` (158:3) is kept, but it no longer scrolls (`overflowDirection` NONE). Its content is exactly 656 tall. If Framewisp still imports it as a ScrollingFrame, the canvas equals the frame and nothing moves.
- `Content_list` is a new node (172:2, was 158:4): vertical, gap 20, holding two sections instead of four rows.
- The sections are static design: `Section_Audio` holds `Setting_LobbyMusicEnabled`, and `Section_Accessibility` holds the other three. Each has a `SectionHeader` (`SectionLabel` + `Rule`) and a `Group` panel. Nothing binds to them. The grouping is not in `ZyntraConfig`. If a fifth setting is ever added, place its row in Figma (`need` still finds it, see below).
- **`Toggle_<Key>_button` is now the whole row.** `Setting_<Key>` wraps exactly one child, the button, which fills it. `Info` moved inside the button: v1 `Setting_<Key>/Info/Title` is v2 `Setting_<Key>/Toggle_<Key>_button/Info/Title`. `Binder.find` is a preorder descendant search, so `need(row, "Title")`, `need(row, "Desc")`, `need(row, "Track")`, `need(row, "Knob")` and `need(row, "State")` keep working unchanged.
- The button no longer changes its face with the state. It has no fill (the `Group` panel gives the TILE background), so do NOT recolour it ON/OFF. Only `Track`, `Knob` and `State` carry the state.
- `Track` is 112x60 (was 72x40). `Knob` is 48x48 and its x is 58 when ON, 6 when OFF (was 38 / 6). OFF colours changed: see below.
- `State` is a FIXED 84x36 label, right-aligned and Montserrat Black 30 (was hug-width, Black 40). A swap between ON and OFF moves nothing, so it needs no `fitLine` widening.

| Binding | Id | Driven by |
|---|---|---|
| `SettingsList_scroll` | 158:3 | Plain container now, 1680x656, clips |
| `SettingsList_scroll/Content_list` | 172:2 | Vertical list, gap 20: Section_Audio (180) + Section_Accessibility (456) = 656 |
| `Section_Audio` | 172:3 | Static. SectionHeader 172:4 (SectionLabel "AUDIO" 172:5, Rule 172:6), Group 172:7 |
| `Section_Accessibility` | 172:16 | Static. SectionHeader 172:17 (SectionLabel "ACCESSIBILITY" 172:18, Rule 172:19), Group 172:20, Separators 172:29 / 172:38 |
| `Setting_LobbyMusicEnabled` | 172:8 | Toggle_..._button 172:9, Info 172:10 (Title 172:11, Desc_txt 172:12), State 172:13, Track 172:14, Knob 172:15 |
| `Setting_ReduceCameraShake` | 172:21 | Toggle_..._button 172:22, Info 172:23 (Title 172:24, Desc_txt 172:25), State 172:26, Track 172:27, Knob 172:28 |
| `Setting_ReduceFlashing` | 172:30 | Toggle_..._button 172:31, Info 172:32 (Title 172:33, Desc_txt 172:34), State 172:35, Track 172:36, Knob 172:37 |
| `Setting_CaptionsEnabled` | 172:39 | Toggle_..._button 172:40, Info 172:41 (Title 172:42, Desc_txt 172:43), State 172:44, Track 172:45, Knob 172:46 |

Static look:
- `SectionLabel`: Roboto Mono Bold 30/36, ICON TEAL #4BB4B0 (the header Eyebrow style). `Rule`: 2 px LINE #263134, fills the rest of the header line.
- `Group`: TILE #161D20, a 3px LINE stroke (not counted in layout), radius 24, clips. `Separator`: 2 px LINE between rows.

Per row (`Toggle_<Key>_button`, 1680x136, padding 32 left/right, gap 24, centred vertically):

- `Info/Title`: `entry.Label`. Montserrat ExtraBold 34/40, CREAM.
- `Info/Desc_txt` (base `Desc`): `entry.Description`. Montserrat SemiBold 30/36, SAGE, fill width (1372 = 1680 - 2x32 padding - 84 State - 112 Track - 2x24 gap). It wraps to 1 or 2 lines: Lobby music and Reduce camera shake take 2, the other two take 1. A row's content is at most 116 of its 136 px.
- `Toggle_<Key>_button` (base `Toggle_<Key>`): the tap target, the whole row. It is 136 design px tall, which is 44 px on a phone.
- `State`: "ON" in RAIL TEAL #44DDC4 or "OFF" in SAGE, left of the switch.
- `Track` (112x60, radius 30): ON is RAIL TEAL. OFF is #303C40, a dark grey one step above LINE so the pill still reads on the TILE panel. It has no stroke in either state.
- `Track/Knob` (48x48, radius 24, y 6): ON is CREAM at x 58. OFF is SAGE at x 6.
- While a write is in flight, a pending look (State and Knob in SAGE, Track at #303C40, at the old position) is the obvious choice. It is not drawn here.

## Header: active state

| Binding | Id | Note |
|---|---|---|
| `Header/Records_button` | 91:25 | Opens Page_Records |
| `Header/Settings_button` | 91:29 | Opens Page_Settings |
| `Header/Records_active` | 158:37 | **Hidden, so Framewisp does not import it.** Design reference only. |
| `Header/Settings_active` | 158:43 | **Hidden, so Framewisp does not import it.** Design reference only. |

Draw the active look at runtime on the button itself. It is the dock-tab look that `ui.selectTab` already applies:
- BackgroundColor3 = TILE, BackgroundTransparency = 0.
- UIStroke = RAIL TEAL, Thickness 4, Enabled.
- An `ActiveBar` = RAIL TEAL 8 px bar, inset 16 px each side and 4 px from the bottom (112x8 at 16,132 on the 144 button), radius 4. Clone `ui.tabs.Shop.Bar` for it.

When Records or Settings is up, every dock tab shows inactive: no fill, no ring, no bar and a SAGE label. The header button that is not up keeps its resting look, INK fill with a 3px LINE stroke.

## Controller notes (not done here)

- **Re-import hazard.**
  - Today `TAB_ORDER = {"Upgrades","Shop","Skins","Donate","Colors"}` and `ui.selectTab` only toggles `ui.pages` from that list.
  - Re-importing this frame before the controller learns `Records` / `Settings` leaves both new pages Visible on top of every tab.
  - So ship the controller change with the import, or hide every `Page_*` not in `ui.pages` at bind.
- The header buttons currently call `ui.handoff(tab)` (the legacy terminal). Switch them to `ui.selectTab` once the pages bind.
- Window-level `Binder.find(window, "Title")` (the DEV button borrows its FontFace) now has 12 candidates, not 3. The new
  pages add `Title` nodes. That is harmless while the header title comes first in preorder, but scope the lookup to
  `Header` when you touch that code.
- The Records chip labels are hug-width (`DONE` 73 px). A runtime swap to `NOT YET` relies on `Binder.scaleText` →
  `fitLine` widening into the chip's horizontal list, the same as the dev menu's ON/OFF. Run `scaleText` over both
  pages after the bind. The Settings `State` labels are fixed 84 px and right-aligned (v2), so ON/OFF needs no widening.

## All binding paths and ids (export frame)

```
Page_Records                                      157:6
  RecordsIntro                                    157:7
    TitleCol/Eyebrow                              157:9
    TitleCol/Title                                157:10
    Desc_txt                                      157:12
    ShowAssisted_button                           157:13
      Track 157:14 / Knob 157:15 / ShowAssistedLabel 157:16
  RecordsList_scroll                              157:17
    Content_list                                  157:18
      Record_Level1 157:19   Title 157:21  SoloLabel 157:25 SoloTime 157:26 SoloBadge 157:27(Label 157:28)
                             PartyLabel 157:30 PartyTime 157:31 PartyBadge 157:32(Label 157:33)
                             Challenge1 157:36 Name 157:37 Reward 157:38 State 157:39(Label 157:40)
                             Challenge2 157:41 Name 157:42 Reward 157:43 State 157:44(Label 157:45)
      Record_Level2 157:46   Title 157:48  SoloLabel 157:52 SoloTime 157:53 SoloBadge 157:54(Label 157:55)
                             PartyLabel 157:57 PartyTime 157:58 PartyBadge 157:59(Label 157:60)
                             Challenge1 157:63 Name 157:64 Reward 157:65 State 157:66(Label 157:67)
                             Challenge2 157:68 Name 157:69 Reward 157:70 State 157:71(Label 157:72)
      Record_Level3 157:73   Title 157:75  SoloLabel 157:79 SoloTime 157:80 SoloBadge 157:81(Label 157:82)
                             PartyLabel 157:84 PartyTime 157:85 PartyBadge 157:86(Label 157:87)
                             Challenge1 157:90 Name 157:91 Reward 157:92 State 157:93(Label 157:94)
                             Challenge2 157:95 Name 157:96 Reward 157:97 State 157:98(Label 157:99)
      Record_Level4 157:100  Title 157:102 SoloLabel 157:106 SoloTime 157:107 SoloBadge 157:108(Label 157:109)
                             PartyLabel 157:111 PartyTime 157:112 PartyBadge 157:113(Label 157:114)
                             Challenge1 157:117 Name 157:118 Reward 157:119 State 157:120(Label 157:121)
                             Challenge2 157:122 Name 157:123 Reward 157:124 State 157:125(Label 157:126)
Page_Settings                                     158:2   (v2, 2026-10-07)
  SettingsList_scroll 158:3 / Content_list 172:2
    Section_Audio 172:3          SectionHeader 172:4 (SectionLabel 172:5, Rule 172:6)   Group 172:7
      Setting_LobbyMusicEnabled 172:8   Toggle_LobbyMusicEnabled_button 172:9   Info 172:10 Title 172:11 Desc_txt 172:12  State 172:13 Track 172:14 Knob 172:15
    Section_Accessibility 172:16 SectionHeader 172:17 (SectionLabel 172:18, Rule 172:19) Group 172:20
      Setting_ReduceCameraShake 172:21  Toggle_ReduceCameraShake_button 172:22  Info 172:23 Title 172:24 Desc_txt 172:25  State 172:26 Track 172:27 Knob 172:28
      Separator 172:29
      Setting_ReduceFlashing    172:30  Toggle_ReduceFlashing_button 172:31     Info 172:32 Title 172:33 Desc_txt 172:34  State 172:35 Track 172:36 Knob 172:37
      Separator 172:38
      Setting_CaptionsEnabled   172:39  Toggle_CaptionsEnabled_button 172:40    Info 172:41 Title 172:42 Desc_txt 172:43  State 172:44 Track 172:45 Knob 172:46
Header/Records_button 91:25   Header/Settings_button 91:29   Records_active 158:37 (hidden)   Settings_active 158:43 (hidden)
```
