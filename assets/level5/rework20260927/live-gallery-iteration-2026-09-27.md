# Level 5 DEV gallery iteration — 2026-09-27

## Authority and installed source

Roblox Studio place 131311258779917 (universe 10559217407) was in Edit mode. Before each scoped write, the exact live ModuleScript Source and ScriptEditorService editor source matched the committed baseline; each UpdateSourceAsync callback checked that baseline again. The three resulting live sources matched the exported repository files byte for byte in both Source and editor after Play. No other live script was edited in this pass.

| Studio instance | Baseline SHA-256 | Installed/source mirror SHA-256 | Bytes |
| --- | --- | --- | ---: |
| ServerScriptService.Level 5 Systems.Level 5 Reference Facades (ModuleScript) | fda2d85dd2e784b8e52410cc91c75304682f7aac95bd820bc81c02a678e8a395 | cb5ab04b66c95d37b21b9065d0823ea5a79c4b5ece88746c4a47e3380a3683a0 | 54,009 |
| ServerScriptService.Level 5 Systems.Level 5 Reference Anomalies (ModuleScript) | 4b0a6e7fd6ded49498b81d3e111c95db4e5d6b907096bbc6659df3df24793408 | 54e1d028929e559911dcd56c818cc39b945bc1caf275a0cb4aea63bf1d89a0e2 | 88,154 |
| ServerScriptService.Level 5 Systems.Level 5 Rework Gallery (ModuleScript) | f02f346dbaa24a54557db8d36dfb87af03d1affe874b766a17ea68399b3be565 | fff66028ca95b14a51497e635d37883fdccb7235d07060a8a0a4bed01a9df518 | 16,402 |

The gallery still labels every cell FidelityStatus=unverified-draft, uses GalleryContentVersion=reference-gallery-2026-09-27-v1, and is created only by the existing Level5PreviewAccess server script when an allowed developer uses the Level 5 sealed door. That script, ReplicatedStorage.DevAccess, the playable Level 5 Architecture, and the public round flags were not changed. The three ChatGPT imagegen candidate textures remain scoped to this gallery: clapboard rbxassetid://107441812561821, carpet rbxassetid://136282007145831, lawn rbxassetid://108216315862080. The gallery source adjusts carpet repeats to 6 studs and its tint to RGB (174, 165, 147). A prior full native place backup remains at [pre-rework-place.rbxl](pre-rework-place.rbxl).

## Isolated build and visual checks

The local proposal was first built from cloned modules in a tagged temporary model in Studio Edit. The build succeeded at **9,937 descendants**, and the QA model and cloned modules were removed afterward. Per-cell descendant counts:

| Section | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Count | 1,791 | 359 | 1,095 | 1,195 | 1,440 | 955 | 340 | 1,279 | 1,282 | 139 |

The revised Edit captures are [01](gallery-proposal-ref01-gapfix.jpg), [02](gallery-proposal-ref02-recessfix.jpg), [08](gallery-proposal-ref08-revised.jpg), and [09](gallery-proposal-ref09-revised.jpg); [05](gallery-proposal-ref05-handfix.jpg) shows the preceding, locally verified inclination change. Section 01's upper-left opening closed and its path is smoother; section 02's near dark doorway and five recesses received backing down to Y=-6; section 08 no longer puts balcony rails on the top walkway and now has a visible stair/far facade; section 09 has more lower rail posts and matte dark window strips. Section 05 has round towers and corrected screen-right arches.

These are landscape Studio captures at 1920×1076. The original portrait screenshots remain attached in the conversation rather than available locally as files for a pixel overlay. Visual acceptance is **still failed**: section 01's distant tower/facades and landscaping are too regular; section 02's right wall is still plain; section 05's tilted houses and towers are too symmetric; section 08's fronts and floor are simplified; section 09's canyon remains too blue/regular in Edit. Sections 03, 04, 06, 07 and 10 also still need a focused rework against their separate references. The model should not be called 1:1.

## Play check

After live installation, a fresh Play session as whitelisted user 9488575949 used actual prompts: sealed Level 5 door → hub → section 01 → hub → section 08 → hub → section 09 → hub → lobby. QA moved the avatar beside the door and hub stands by script to save walking time, but no script moved it into a section cell. The server preview had PreviewReady=true, the expected content version, and exactly **9,937 descendants**, below its 30,000 cap. The client had the collidable landing pads for sections 01, 08 and 09 after streaming; at three seconds after each arrival, the avatar remained above its pad. Reference camera heading dots were approximately 1.0; the section 01 camera FOV was 70°. The gallery status UI hid on lobby return. One authorized client was exercised; non-DEV multiplayer, active-round interaction, seven-gate gameplay, and the playable Level 5 route remain unverified for this iteration.

The Studio Save shortcut was issued after the Play check; no cloud publish confirmation was reported. No Roblox publish or GitHub push was made because the ten visual references and integrated gameplay checks still have material gaps.
