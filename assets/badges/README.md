# BACKROOMS: STAY QUIET badges

Four badge illustrations were generated with the built-in image generator for the Trello badge task. The original 1254 x 1254 PNGs are preserved in `source/`. Upload-ready files in `icons-512/` are exactly 512 x 512 PNGs, reduced with high-quality bicubic resampling and no artistic edits. Alpha is preserved where present in the original.

| Roblox badge name | Roblox description | Config key | Upload file |
| --- | --- | --- | --- |
| Level 1 Cleared | Escaped Level 1 of the Backrooms. | `FirstClearLevel1` | `icons-512/level-1-cleared.png` |
| Level 2 Cleared | Survived the Sunken Leisure Complex and found the exit. | `FirstClearLevel2` | `icons-512/level-2-cleared.png` |
| Level 3 Cleared | Got out of the mall before the Mall Manager found you. | `FirstClearLevel3` | `icons-512/level-3-cleared-map-v2.png` |
| Stay Quiet | Cleared every level of the campaign. | `CampaignComplete` | `icons-512/stay-quiet.png` |

Source task: <https://trello.com/c/sHKVULaS>

`prompts.json` contains the initial image-generation prompts; `level-3-map-v2-prompt.txt` contains the final corrected mall prompt. All images used the built-in image generator, not an API/CLI fallback. `prepare-icons.ps1` records the source-image mapping and export settings. It refuses to overwrite existing assets.

All four selected icons are uploaded and visible on Roblox. The matching badge IDs are in `ReplicatedStorage/ZyntraConfig` and were published in place version **1755** on 2026-09-05. See `docs/EMERGENCY_REENTRY_VALIDATION_2026-09-05.md` for ID and publication evidence.

## Level 3 correction

The original escalator design is **REJECTED — NEVER UPLOAD**. These files are preserved only as a rejected source variant:

- `source/level-3-cleared-source.png`
- `icons-512/level-3-cleared.png`

The approved replacement is `source/level-3-cleared-map-v2-source.png`, exported to `icons-512/level-3-cleared-map-v2.png`. It represents the actual Level 3 party-room map rather than a generic shopping-mall escalator.

Actual Roblox Studio screenshots used for the corrected design are preserved in `references/`:

- `references/level3-actual-red-party-20260905.jpg`
- `references/level3-actual-signal-hall-20260905.jpg`

To export only the replacement into missing destinations, run `prepare-icons.ps1 -BadgeNames level-3-cleared-map-v2`.
