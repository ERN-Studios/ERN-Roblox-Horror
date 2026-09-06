# Validering af Trello-implementering — 5. september 2026

Arbejdsmappe: G:\Roblox\MongoTV. Studio-place 131311258779917, universe 10559217407. Ændringerne er integreret i Studio og endnu ikke publiceret. Ingen endelige Pool Foam-lydfiler eller lyd-ID'er er leveret.

## Implementeret

- Én fælles 60-sekunders deadline fra destinationens loading-start gennem admission, world build, karakterindlæsning, placering og klientkvittering. Runde/fjender frigives efter hele den tilsluttede gruppes barriere.
- Token- og karakterkontrol afviser gamle kvitteringer/resultater. Motorens karakter-load beholder den fælles lås, til operationen faktisk slutter.
- Timeout viser fejl og bruger eksisterende lobby-recovery. En igangværende world builder holdes adskilt fra nye startforsøg indtil sikker oprydning.
- Continue afgår fortsat straks. Et endeligt cohort-snapshot i MemoryStore afklarer senere legitime opt-outs; endnu ikke ankomne spillere må ikke blot falde ud af forventningen.
- Controller: DPadUp missionshjælp, LB mute, DPadLeft/Right spectate, kontekstuel terminal-B, fokusgendannelse og genlæsning af fysisk sprint-input under runden.
- Pool Foam: genbrugt positionel Walk/Hunt-emitter med pause/cleanup samt target-only Attack med beskyttelse mod gamle/dobbelte events. De tre aktive IDs er bevidst tomme.

## Gennemførte Studio-scenarier

Test gennem faktiske launch-zoner og ConfigureQueue; ingen direkte tvungen RoundActive. Én lokal klient med StreamingEnabled.

1. **Level 1:** normal kø → loading → ready → RoundActive=true, InRound=true, loading-cover skjult. H åbnede og lukkede missionshjælpen.
2. **Manglende klient-readiness:** Studio-only DevHoldEntryReady=true før Level 1-kø. Runden forblev inaktiv, og cover blev stående. Serverens annoncerede deadline var 1788622657.518; klienten modtog første LOADING_TIMEOUT ved 1788622657.761 (ca. 0,24 s efter deadline). Intet start-event kom.
3. **Lobby-recovery:** efter timeout: InRound=false, RoundActive=false, cover skjult, RoundGui enabled, synlig tekst “LOADING TIMED OUT (60s) — RETURNING YOUR PARTY TO LOBBY”, RoundLoadingError=timeout. Ny lobbykarakter var unanchored med Classic-kamera.
4. **Nyt forsøg efter fejl:** DevHoldEntryReady fjernet, samme session → Level 2-kø. Token steg fra entry:1 til entry:2. loadinggame ved 1788622714.774, entryreleased ved 1788622719.403, start ved 1788622719.404. Fejlattribut ryddet; RoundActive=true, InRound=true, cover skjult.
5. **Level 3 direkte:** ny Studio-session → LaunchZone9. loadinggame ved 1788622999.004, entryreleased ved 1788623000.771, start efter elevatorforløbet ved 1788623008.058. RoundActive=true, InRound=true og cover skjult. Konsollen havde ingen scriptfejl.
6. **Level 2→3-røret, efter gulvrettelsen:** normal Level 2-start, eksisterende dev-control aktiverede to pumper, tredje pumpe aktiveret med faktisk E-hold på prompten. Efter tre pumper og powered exit blev karakteren flyttet ind i den faktiske completion-sensor; Objective-controlleren udløste sejr og rørmarkør. Den aktuelle win-serial blev sendt med Continuenow. Ingen direkte tvungen RoundActive eller syntetisk escape-event. Win ved 1788624064.547; loadinggame ved 1788624065.598; entryreleased og start ved 1788624066.868. Level 3 var aktiv, cover skjult, karakter unanchored og flyttet fra rørets bagende til udløbsområdet. Testen dækker den lokale continuation, ikke netværksteleporten mellem publicerede servere.

L2-testkonsollen viste terrain-cleanupens kendte recovery-log og `AwardBadge failed ... FirstClearLevel2 false`. Badge-tildeling er ikke verificeret eller ændret i denne opgave. Ingen runtime-scriptfejl blev observeret i den beståede rørtest.

Virtuel DPadUp blev afvist af Roblox: “key is permanently bound to a CoreGUI core action”. Det tæller ikke som en bestået fysisk controller-test. De automatiske handler-tests verificerer bindingernes logik; CoreGUI/hardware-rutningen kræver den særskilte test nedenfor.

## Automatiske checks

Luau 0.737, officiel Windows-release med kontrolleret checksum. Offline-tests kører faktisk produktionskode med kontrollerede engine-grænser.

| Suite | Resultat |
|---|---|
| Round Completion Test Suite, Studio | 398 checks, 0 fejl |
| Round Loading Test Suite, Studio | 51 checks, 0 fejl; med sidste disconnect-rettelse |
| tools/tests/test_round_loading_host.py | 83 bestået; faktiske GameManager-blokke med fake engine-grænser |
| tools/tests/test_controller_input.py | 120 bestået |
| tools/tests/test_pool_foam_audio.py | 24 bestået |
| tools/tests/test_round_entry_client.py | 57 bestået; hele LocalScriptet eksekveres, inkl. rør-gulvets faktiske afstand |

Alle 13 implementerede scripts blev pushed med projektets UpdateSourceAsync-flow og compiled uden fejl. Den efterfølgende destination-disconnect-rettelse blev pushed i tre serverfiler uden konflikter. Sidste Studio-kørsel bestod både 398 Completion- og 51 Loading-checks, og konsollen viste ingen scriptfejl. Studio er afsluttet i Edit.

Slutkontrol: compile-proben kompilerede 104/104 scripts, ingen fejl eller staging-fejl. Read-only parity-audit: 104 matchede, 0 drift/manglende; de to tidligere dokumenterede tilladte slutlinjeforskelle er uændrede. Ingen publicering eller git-commit/push udført.

Host-testen eksekverer de faktiske blokke for setup-evidens, arrivalEntries/stageArrivingParty, recoverFailedEntry, beginGroupLoading og prepareGroupLoading med de fulde Loading/Routing-moduler. Den dækker én deadline gennem admission→builder→ack, hængende workers/læsninger, recovery, destination-disconnect, final-bærerens afgang, genjoin og et besøg mellem polls. Den udgiver sig ikke for en virkelig server-til-server-test.

Den ekstra lokale L2→3-prøve fandt, at den holdte karakters ray-origin ligger ca. 14,923 studs over rørets gulv. Den oprindelige 14-stud ray fandt derfor ikke den allerede indlæste kolliderbare shell. Level 3 bruger nu en 20-stud ray; øvrige levels beholder 14. Whitelist, position, normal og kollisionskrav er bevaret. Tre nye checks dækker den faktiske afstand, afvisning af fjernt gulv og uændret kortere grænse i Level 2.

## Resterende accepttest

- Publiceret session med 2–6 klienter: tidlig Continue, sidste spiller vælger lobby, alle Continues forlader kilden tidligt, faktisk destination-disconnect, sent join, MemoryStore-fejl, teleportfejl/retry og afbrudt boot. Studio kan ikke bevise TeleportService/MemoryStore-kontrakten mellem rigtige servere.
- Publiceret Level 2→3 gennem exit-røret og continuation, inkl. langsom streaming og verificeret fallback. Den normale lokale rør-overgang er prøvet ovenfor; den erstatter ikke netværks- og fejltesten.
- Fysisk controller: kiosk→Settings→B, DPadUp, LB, spectate med flere mål, controller frakobles med L2 holdt, Shift slippes under fokustab, flere gamepads, touch-RUN og inputskift.
- Modtag og vælg Walk/Hunt/Attack, kontrollér brugsret, gruppeupload, moderation og experience-adgang; indsæt IDs, aflyt loops og afstandsmix med mindst to klienter. Ingen hørbar lydvalidering påstås med tomme IDs.
- Readiness betyder spilbart startområde, korrekt karakter, lokale controls/UI og karakterens kritiske mesh/tekstur-preload. Fjerne world-assets og sent tilføjede karakterassets preloads ikke som en komplet bane; test langsom streaming på målenhederne.

Se docs/CLAUDE_LOADING_REVIEW_PROMPT_2026-09-05.md til uafhængigt read-only review og docs/POOL_FOAM_SFX_BRIEF_2026-09-05.md til lydproduktion.
