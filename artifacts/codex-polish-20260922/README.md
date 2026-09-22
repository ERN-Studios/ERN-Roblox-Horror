# Codex polish-pakke — 22. september 2026

Denne pakke er review og visuel specifikation til Claude. Ingen kode eller native spilassets er ændret, og intet er publiceret fra denne opgave.

## Filer

| Fil | Betydning |
|---|---|
| `level4-start.jpg` | Native Studio Play-capture, seed 101 / CLOSE, kamera ved servicepassagen. Faktisk gameplaybillede, 1539 × 809. |
| `level4-facade-before.jpg` | Native capture af `House_Intro`; midlertidig capture-kamera-position (12420,33,13), kig mod (12438,32,44). Faktisk blokmodel, 1539 × 809. |
| `level4-review-evidence.json` | Samme rundes tilstand, klientlys, geometri-målinger og positionsinventar. Målingerne er forskellige samples i samme runde, ikke atomisk taget sammen med billederne. |
| `level4-facade-polish-target.png` | Genereret paintover, **designreference, ikke implementeret spilindhold**, 1730 × 909. |
| `imagegen-prompt.txt` | Hele prompten til billedgeneratoren. |
| `trello-board-snapshot.json` | Frisk læsning af alle 135 kort, inklusive arkiverede. Ingen resterende sider. |
| `trello-refreshed-checklists.json` | De fire nye kort plus Level 4; alle forespørgsler lykkedes, ingen resterende sider. De nye kort havde ingen checklists. |
| `detector-v1976-publish-log.txt` | Uændret tekstindhold hentet fra `e9bf35c` på detector-branchen; dokumenterer en anden sessions publicering. |
| `studio-sync-audit-after.txt` | Afsluttende audit: 167 scripts, 167 match, 0 drift. |

## Imagegen-proveniens og kvalitetstjek

- Værktøj: indbygget imagegen i edit-mode. Ingen Higgsfield-job eller credits brugt i denne opgave.
- Edit target: `level4-facade-before.jpg`, produceret gennem Roblox Studio MCP i denne opgave.
- Mood-reference: `../claude-brief-20260921/level4-quiet-suburbs-concept.png`, tidligere intern konceptreference.
- Original output: `C:/Users/mikke/.codex/generated_images/01a0c4c2-bfe7-75e2-a033-361c41c2869f/exec-11c21e71-3a3b-4646-b6f6-14593378873f.png`. Projektkopi er bevaret her; originalen er ikke slettet.
- SHA256 for projektkopien: `9a6cd0c74761aac080c4aaf8218842900c75d1d9615fd21a20b1ff61683d325d`.
- Visuelt kontrolleret: fire facadevinduer, ét åbent centralt dørhul, korrekt sadeltag, lille grønt signal, genkendelig mailbox, samme overordnede kameravinkel/lot og klar reference-label.
- Billedgeneratoren har fortolket bevoksning og overfladedetaljer mere detaljeret end målplatformen kræver. Implementér simple fælles materialer og lave, få mesh-silhuetter; undlad individuelle græsstrå/blade og tæt baggrundsskov.
- Billedet er ikke målfast. Den eksisterende kontrakt har forrang: hus 30 × 34 studs, væg 13, taghøjde 7, dør mindst 6 × 10,5, passagebredde mindst 6, uændret InteriorVolume/ankerplacering.
- Brug ikke PNG'en som en færdig hus-/UI-tekstur, og markedsfør den ikke som nuværende gameplay.

Det samlede review og Claude-promptet ligger under `../../docs/` med datoen 2026-09-22.
