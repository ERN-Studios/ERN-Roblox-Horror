# Level 3: installeret og playtestet

?ndringen er installeret i **[UPDATE] BACKROOMS: STAY QUIET**
(place **131311258779917**). Alle fire scripts har status `synced`, og deres
faktiske Edit-source matcher de lokale filer ved en uafh?ngig fingerprintkontrol.
Play-sessionen er stoppet; Studio er tilbage i Edit.

Entity g?r med patruljehastighed til frie punkter omkring besatte borde og
opgiver sin direkte jagt, n?r spilleren gemmer sig. Den kr?ver h?jst 14 studs
og frit udsyn under bordet f?r en advarsel p? 2 sekunder. Serveren laver ?t
skill check med **25 % succesrate**. Succes skubber de ubeskyttede spillere ud,
genskaber kontroller og kollision samt giver 1,5 sekunders angrebsimmunitet.
Fejl lader spilleren blive og v?lger straks en rute til et andet besat bord.
Hvis intet andet bord er tilg?ngeligt, forts?tter entity sin patrulje.

Global cooldown er 18 sekunder og cooldown for samme bord er 25 sekunder.
Inspektionen ignorerer kun det unders?gte bords usynlige sight-occluder;
v?gge og fysisk inventar blokerer fortsat. Normal st?ende vision er bevaret.
Patruljen pr?ver 16 retninger og en 13,5-stud-ring for at n? inden for faktisk
inspektionsafstand. Dens faste tidsbudget tager h?jde for den planlagte rutes
omveje og bliver ikke forl?nget l?bende.

## Validering

- **443 lokale checks best?r:** 144 patrol/skill-check, 77 release/immunitet og 222 navigation.
- Alle fire produktionsscripts og begge playtest-prober kompilerer med Luau 0.737.
- Naturlig patrulje, seed 7331: skjult f?r spawn; bordtjek efter cirka 29 sekunder, fejlet roll, faktisk bev?gelse 2,25 studs efter fejl.
- Naturlig patrulje, seed 101: gemte sig under en aktiv jagt; 1152 studs navigeret gennem den lange rute, derefter vellykket skub uden at genoptage direkte jagt f?r spilleren var ude.
- Begge udfald verificeret med rigtige Roblox Random-seeds: succes restorede kontroller og 18 collision/touch/query-parts, immunitet udl?b; fejl valgte straks et patruljem?l og bev?gede entity v?k fra bordet.
- Spilleren bevarede 100 health i begge isolerede udfald.
- Uafh?ngig Edit-source-kontrol: alle fire scripts matcher pr?cist.

De naturlige rutepr?ver holder samme hunt ?ben med Studio-only timeline-seeks,
s? lange omveje kan f?rdigg?res. Udfaldspr?ven placerer den rigtige entity p?
et navigationsgodkendt punkt og bruger kendte RNG-seeds. Produktionschancen,
Heartbeat, udsyn og skublogik forbliver u?ndrede. Proberne rydder testverdenerne op.

## Filer og genk?rsel

`validation-summary.json` samler resultaterne; `engine-natural-seed*.json` og
`engine-outcomes.json` gemmer motorens readback. `studio-fingerprints.json`
gemmer den afsluttende source-kontrol. `studio-before/` er den oprindelige
Studio-baseline; `installed-candidate/`, `prepared-manifest.json` og
`level3-table-check.diff` indeholder den endelige installerede ?ndring.
Den oprindelige klarg?ringsmanifest er bevaret i `prepared-manifest-original.json`.

Nyere Studio-rettelser for finale, layout, slide og udgangslys er bevaret.
Installationen brugte `ScriptEditorService:UpdateSourceAsync`, konfliktkontrol,
readback og kompilering. Der blev ikke brugt konflikt-override.

Til genk?rsel: start en separat Studio-playtest med ?n spiller og k?r f?rst
`playtest-async.luau` i Server-datamodellen. Poll `_G.Level3TableCheckProbe`.
Efter afslutning kan `playtest-outcomes-async.luau` k?res; poll
`_G.Level3TableOutcomeProbe`. K?r proberne efter hinanden og stop Play bagefter.
`push-level3.ps1` foretager ingen ny push, n?r alle fire entries er synkroniseret.

Der er ikke publiceret til Roblox.
