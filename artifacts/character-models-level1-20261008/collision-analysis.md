# Offline-analyse af karakterkontakt — 2026-10-08

Ingen Studio-/bridgekald. Ingen fælles scripts, manifest eller lås ændret. Grundlaget er den frosne `offline-baseline/`, ikke de samtidige sessions' arbejdsfiler.

Der er to konkrete fejl, som tilsammen passer tæt på ejerens observation:

- `offline-baseline/HazmatSkinDriver.LocalScript.lua:491-495` gør hele den nye mesh usynlig, når kameraet er mindre end 3 studs fra **enhver** spillers hoved. Kontakten med en holdkammerat kan derfor skjule holdkammeratens nye krop på den anden spillers klient. Den skjulte R15-krop bliver fortsat skjult.
- Samme scripts `BODY_PARTS` (`:33-41`) og `captureBody` (`:223-238`) skjuler kun navngivne direkte børn. Det historiske, faktiske StarterCharacter-eksport har præcis tre ekstra dele, som ikke står på listen: `LeftShoulderSeamLiner`, `RightShoulderSeamLiner`, `NeckSeamLiner` (`artifacts/trello-20260916/character-export-rig.json:41,63,85`). Når resten af kroppen er usynlig, kan netop disse tre gamle seamfillers blive synlige alene. `tools/fit_actual_hide_pose.py:31-32` og `tools/build_actual_table_hide.py:56-60` bekræfter, at de er dekoration omkring UpperTorso, ikke R15-segmenter.

Det er bevist offline, at koden har begge fejl. Det er endnu ikke bevist, at den aktuelle live StarterCharacter stadig har de tre seamfillers, eller at de aktuelle dele er løse/collidable. Det kræver readback og en kontaktprøve i rigtig Play, når root-sessionen har Studio-turen. Der er ikke lavet spekulative ændringer til karakterernes fysik.

Den isolerede kandidat er i `collision-candidate/`:

- `HazmatSkinVisuals.Script.lua`: fjern server-side kun de tre gamle seamfillers efter alle eksisterende mesh/root/floor/topper-checks er bestået i `buildVisual`. Ved forkert asset eller dødt rig bevares den gamle fallback. De 15 R15-segmenter, Humanoid, root, joints og udstyr bevares til bevægelse, kamera og animation.
- `HazmatSkinDriver.LocalScript.lua`: lad 3-stud-skjulningen gælde LocalPlayer og den præcise `SpectateTargetUserId`. En tæt holdkammerat skjules aldrig alene på afstand. Tilføj også de tre seamfillers til `BODY_PARTS`, så en sent replikeret rest skjules. `SpectateController` skriver mål-attributten på linje 187 og rydder den på linje 363; tilskuernes førstepersonsadfærd bevares.
- `prepare.py` genskaber de to kandidater fra den frosne baseline med tre præcise erstatninger. Den ændrer ikke delte kilder.
- `test_collision.py` eksekverer de faktiske `buildVisual`, `captureBody`, `setVisible`, `clearState`, `reconcile` og render-callbacks i et offline Luau-host. Testen kan køres med `--source-dir <kombineret-kandidatmappe>` og `--only server|client`.

Validering: 39 serverchecks og 39 klientchecks bestået. Begge kandidater kompilerer med Luau 0.737 `luau-compile -O0 --null`. Checks dækker bevaret R15/udstyr, ugyldigt mesh/bones/ekstra parts/topper og dødt rig, fjernelse af alle tre gamle dele ved gyldigt visual, skjult egen krop, synlig holdkammerat på kameraets position, spectate ind/ud, tredjeperson, gentagen nærkontakt, sent seamfiller-barn, oprindelig transparency/Decal-metadata ved cleanup, idempotent cleanup og fallback ved posefejl.

De frosne gamle scripts fejler de samme regressionschecks som forventet: servercheck 18 (`LeftShoulderSeamLiner removed server-side`) og klientcheck 2 (`teammate touching the camera stays visible`). Dermed passerer testen ikke bare af sig selv.

Eksisterende harness: `tools/tests/test_level2_newmap_feedback.py:615-688` tester server `refresh`/`addPlayer` og klient `reconcile` ved Level 2-previewflagget. Den dækker ikke render-callbacken, kameraets kontaktafstand, `captureBody`, seamfillers eller cleanup. Der findes ingen aktuel kildefil til en dedikeret skin-/collisiontest under `tools/tests/`; kun et gammelt `__pycache__/test_zyntra_skins` blev fundet. Projektets graphify-graph er fra commit `a6551306`, mens checkout er `1be05fc9`; den kunne ikke bruges som nutidigt bevis.

Den selvstændige loadingfejl (`RoundActive` kommer først efter briefen) håndteres af root-sessionen. Den er ikke ændret i denne afgrænsede kandidat.

Efter sammenlægning: harnessets falske gameplayrig har nu `ZyntraGameplayCharacter=true`, svarende til den nye autoritative karaktermarkering. Det ændrer kun fake-engine opsætningen; ingen forventninger er svækket. Den kombinerede kandidat i `combined-candidate/` består stadig 39 serverchecks + 39 klientchecks. Frossen baseline fejler fortsat servercheck 18 og klientcheck 2.

2026-10-09: collision-harnesset understøtter nu også `combined-tint-candidate/` ved at eksekvere den faktiske `advancedHazmatColor`-helper, når den findes. Fake-spilleren har ingen Advanced Equipment-ejerskab, så denne suite tester standardkollision/visibilitet; særskilte tint-tests køres af en anden agent. Både `combined-candidate/` og `combined-tint-candidate/` består alle 78 collisionchecks. Frossen baseline fejler fortsat servercheck 18 og klientcheck 2. Ingen forventninger er svækket; ingen kilde-, Studio- eller køændringer.
