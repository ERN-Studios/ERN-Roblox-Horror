# Level 2 lobby-spawn — releasejournal 9. september 2026

Kort: https://trello.com/c/DOIafNTw. Rapporten samler hovedagentens målte testresultater, kritikerens vurdering og den native publiceringsbekræftelse. Den ændrer ikke det oprindelige Trello-snapshot.

## Rettelse og afgrænsning

`ServerScriptService/Level 2 Systems/Level 2 Pool Slide Configuration.ModuleScript.lua` har nu `Enabled=false` og `StudioValidationMode=false`.

Den aktive Pool Slide-template havde `RigVerified=false` og `CorridorFitVerified=false`. Studio-overridet skjulte den manglende accept lokalt; en publiceret server afviste riggen, hvorefter Level 2-build kunne afbrydes. Hotfixet holder denne ufærdige entity ude af frigivne runder, indtil rig og korridorpasform er godkendt. Pool Foam er fortsat aktiv. Templates, controller og acceptkontroller er bevaret. Tunnel-/rigarbejdet ligger fortsat på kort https://trello.com/c/KcUdv690.

## Verifikation

- To normale lobby-starter via LaunchZone5 og CreateParty, med deltagerantal valgt til én gennem UI og normal nedtælling, bestod på ufastlåste seeds **1149227209** og **1700670544**.
- Server: SelectedLevel 2, RoundActive true, RoundLoadingState ready, InRound true, Health 100, root ikke anchored og WalkSpeed 16. En kollisions-raycast uden karakteren ramte Workspace.ElevatorSpawn. Pool Foam aktiv; Pool Slide deaktiveret som tilsigtet.
- Klient: loading-cover og queue-modal skjult; RoundEntryUIReady og ControlsReady true.
- Normal død og party-down-forløb returnerede spilleren til lobby med Health 100, root ikke anchored og InRound false. Den genererede level-verden var fjernet, og Pool Foam var inaktiv.
- Luau-kompilering: **122/122**. Studio-audit: **122 matchede, 0 drift**. Uafhængig paritet: **120 eksakte og 2 kun med forskelle i linjeskift**, ingen manglende eller ekstra scripts.
- Round Loading Suite: **73/73**. Completion Suite: **398/398**. Fokuseret offline Pool Slide-release-test: **78/78**; kritikeren genkørte denne uafhængigt.
- Level 3 ValidateConfiguration og ValidateGeneratedLayouts bestod på ni seeds med 26 rum.

Runtime- og kompileringsevidens: [spawn-validation.json](spawn-validation.json). Paritetsdump: [spawn-parity.json](spawn-parity.json). Fokuseret test: `tools/tests/test_level2_pool_slide_release.py`. Før-ændring-backup: `.studio-push-backups/20260909-195110/`.

## Uafklarede fund fra bred UIRegression

Den brede UIRegression-kørsel under aktiv Level 2 omfattede **2549 checks og 16 fejl**:

| Fundgruppe | Antal | Observeret |
|---|---:|---|
| Level 2 objectives/scenario | 2 | objectives-panel og level2-alert-and-objective fejlede. |
| Device-matrix | 13 | CreateParty var synlig, men `Active=false`. |
| Genetablering af ydre UI-tilstand | 1 | L3Reader synlig, L2Objective skjult og Zyntra Toggle inaktiv efter suite. |

De øvrige testspor havde ingen rapporterede fejl, og testlåsen blev ryddet. **Der er ingen sammenlignelig før-baseline, så fejlene er ikke dokumenteret som eksisterende før hotfixet.** Frisk genstart og normal lobby-entry bestod. Kritikeren vurderede, at fundene ikke blokerede den afgrænsede config-rettelse, men de skal undersøges målrettet og må ikke forsvinde i en påstand om, at alle tests er grønne. Denne tabel er hovedagentens opsummering af suite-output, ikke en gemt fuld rå log.

## Kritik og publicering

Den uafhængige kritiker gav hotfixet **9/10** og prioriteringen **9/10**, uden blocker for denne rettelse.

Hovedagenten brugte computerstyring til **Alt+P**. Et afbrudt værktøjskald betød ikke, at selve publiceringen blev afbrudt. Efterfølgende observation af native Studio-output viste:

```text
22:01:41.106 Sent message to server to publish.
22:03:09.329 Place published. Eligible players can now play this place in Roblox.
22:03:09.329 Add publish notes to v1813
22:03:09.364 Published new changes in "BACKROOMS: STAY QUIET [CO-OP HORROR]" to Roblox.
```

Tidspunkterne er dansk lokaltid den **9. september 2026**. Publiceret version er **v1813**. Edit-sessionens indlæste `game.PlaceVersion` var fortsat 1809 og blev derfor ikke brugt som publiceringskvittering.

Hovedagenten har opdateret kortets beskrivelse og flyttet det til **Testing**. Rettelsen er implementeret, lokalt verificeret og publiceret; spil med rigtige publicerede klienter er endnu ikke afprøvet. Det separate transportkort https://trello.com/c/DIktjy8U kræver fortsat 2–6 klienter.
