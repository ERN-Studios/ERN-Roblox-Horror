# Studio introduction — prepared, not installed

Trello card `kQ4GNLUU` asks for a short introduction explaining that the studio has two developers, is working on bugs and appreciates feedback. No description or checklist was supplied. This artifact changes only the existing lobby welcome sign in `ServerScriptService/TunnelLobbyBuilder.ModuleScript.lua`.

## Placement and copy

The existing double-sided `ServerLobby.TunnelDetails.ZyntraWelcomeBoard` sits at lobby center plus `(0, 18.1, -92.2)`, just beyond spawn at `(0, .4, -100)`. It already carries the arrival heading and directs players to the side gates. The proposal keeps this same panel, both faces, colors, enclosure, divider and gate instruction. The heading becomes one line, leaving room for:

> We're a team of 2 developers.
> We're fixing bugs and appreciate your feedback.

The message is passive lobby signage: no new modal, notification, button, gameplay overlay, profile flag, timer, audio or input binding. It remains available when someone chooses to look again. It adds two TextLabels and no physical parts. No feedback destination or new submission system is invented; the card requests appreciation, not a feedback collection flow.

The current RoundUI welcome is a voiced, persisted Command Center gameplay briefing. Changing its subtitle text would conflict with the recorded speech, and adding another forced introduction would interrupt arrival. ZyntraStore has equipment/store content and a developer-only tools introduction, but no public credits or feedback surface. Those are left unchanged. The existing code graph is stale (report commit e3904931, current HEAD 7f13f53), so the graph query was only a navigation hint; the current source determined this placement.

## Prepared change and review boundary

`before.lua` is an immutable byte snapshot of the current WIP/Crossbar/Doorframe-preserving Builder, SHA-256 `5de584ce892cd59f2fe5d6dc6ad1adcf866f717773f40eadb18cc4009d823b27`. `proposed.lua` and `studio-introduction.diff` replace only the two existing welcome-board `addBoard` calls. `prepare.py` refuses to regenerate if runtime differs from the saved baseline. If another Builder change ships first, apply this narrow transform to that checkpoint rather than copying an old full file over it.

The full proposed Builder compiled successfully with Luau 0.737 (`luau-compile.exe --null`), producing 95 KB bytecode. Preparation verified that the runtime bytes stayed unchanged. No Studio, Trello or runtime files were mutated, and no new test suite was added for this static display-only change. Prices and cards in Testing are outside this feature.

The existing 900×300 sign canvas is preserved. Heading occupies vertical fraction .06–.30; introduction .33–.69; divider starts .74; the unchanged instruction .76–.93. The new text uses Gotham and the existing subtitle color, with wrapping/scaling. These non-overlapping layout fractions and compilation are code evidence, not native readability or TextFits evidence.

Independent review has been requested. Root owns later integration, native acceptance and separate mouse publication. This preparation does not claim a completed or published card.

## Bounded native handoff

On the actual normal lobby, inspect the existing welcome board from both sides, including the spawn approach at ordinary camera pitch and a practical reading distance. Confirm both introductions and the gate instruction are readable and TextFits is true; include one narrow phone view in the same pass. The panel is overhead, so default arrival-camera discoverability is an explicit acceptance point, not assumed from the coordinates. If the message is too small or missed from that approach, adjust this sign's layout/placement narrowly before release.

Confirm there are still two Display SurfaceGuis on the same unchanged, non-colliding 32×7.2×.55 panel and one StudioIntroduction label per face. The entrance route remains clear because no physical geometry changed. No repeated popup or gameplay interruption is introduced by this code; no broad UI or round regression is claimed.
