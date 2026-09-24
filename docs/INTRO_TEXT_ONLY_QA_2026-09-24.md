# Intro briefings: text without voice — 24 September 2026

Trello: [xKozYUIo](https://trello.com/c/xKozYUIo). The owner asked to remove spoken voice from the lobby and Level 1–3 intro briefings, retain the text and sound IDs for possible restoration, and keep the rest of the UI usable while captions are shown. The radio-open cues remain; their audio content has not been independently listened to.

`dispatchAudio.voiceEnabled = false` prevents playback and preloading of the four speech Sounds (`LobbyCommandBriefing`, `LevelOneCommandBriefing`, `LevelTwoCommandBriefing`, `LevelThreeCommandBriefing`). Captions now use an independent clock that pauses when a screen-owning modal hides them. The old HUD-suppression attributes stay false; text activity has a separate `DispatchTextActive` attribute. SKIP remains available, while the MUTE control is hidden. A cue change refits the panel, so a long line cannot inherit a short line's dimensions after the viewport or reader moves.

The smallest landscape touch screens cannot fit a complete caption outside both the reader and the reserved thumbstick rectangle. There the caption body is passive/click-through, the 44px SKIP target sits outside the movement zones and reader, and the reader stays visible. This needs a physical touch check before release acceptance.

## Evidence

- Studio Edit scoped compare-and-swap push and compile of only `RoundUI` and `UIRegression`; after the push, 182/182 scripts match repo, both changed editor buffers equal Source, and the Luau 0.737 `-O0` wrapper compiles all 182 scripts.
- Studio Play full UI regression: **3,025 checks, 0 failures**, 22 scenarios, 0 failed, harness lock clear. `ObjectiveCornerMatrix`: **496/496** across desktop, phone and tablet fixtures. `BriefingFitMatrix`: **213/213**. These are emulated layout fixtures, not hardware measurements.
- Fresh Studio Play lobby intro: 25 seconds sampled at 0.5-second intervals; text visible/active in 50/50 samples with 9 distinct lines, zero speech-playing samples; `DispatchBriefingOpen=false`.
- Real Studio queue rounds through stations 1, 5 and 9: Level 1 had 10 distinct lines and 60/60 active caption samples over 30 seconds; Level 2 had 9 and 60/60; Level 3 had 8 and 52/60. The corresponding speech Sound had zero playing samples in all three runs. The Level 3 caption briefly yielded to other UI as intended. Studio test profiles are in memory, so these tests did not write the owner's live DataStore.
- The Level 3 reader/briefing case was asserted in the layout matrix. The separate click-through predicate requires the visible ScreenGui, passive caption body, visible 44×44 SKIP outside movement zones and reader, and no caption/reader overlap. A disabled-ScreenGui harness error found in the first run was corrected without weakening that predicate.

## Still open

The changed intro is **not published** as of this report; the last confirmed published release is v2083. After the owner publishes the current Studio place, capture its version/receipt and test the four intros in the published client. A physical phone landscape test should confirm that movement still works under the passive caption and SKIP is tappable. Directly listen to the four radio-open cues to confirm they contain no speech. Do not mark the Trello card Done until those checks pass.
