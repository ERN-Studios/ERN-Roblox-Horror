# Arbejdsprompt til Claude — BACKROOMS: STAY QUIET

Du er ansvarlig for **al kode** i denne opgave: Roblox/Luau, integrationer, testkode og eventuelle asset-/Blender-scripts. Codex har gennemgået Trello, GitHub og den aktuelle Studio-version og lavet en Level 4-konceptreference. Codex overtager efterfølgende visuel polish, art direction og asset-feedback. Lever implementering og dokumenteret handoff; stop ikke efter en plan.

Arbejd i projektet `G:/Roblox/MongoTV`, GitHub `https://github.com/ERN-Studios/ERN-Roblox-Horror`. Brug Roblox Studio MCP, Git, filer og relevante API'er. Brug almindelig computerstyring så lidt som muligt.

Spillerrettet tekst forbliver på engelsk og følger den eksisterende Zyntra-stil. Rapportering og handoff kan være på dansk.

## 1. Læs grundlaget og beskyt den aktuelle version

Læs disse filer først:

1. `G:/Roblox/MongoTV/docs/REVIEW_FOR_CLAUDE_2026-09-21.md`.
2. `G:/Roblox/MongoTV/artifacts/claude-brief-20260921/TRELLO_INDEX.md`.
3. `G:/Roblox/MongoTV/artifacts/claude-brief-20260921/LEVEL4_DESIGN.md` ved Level 4-arbejdet.
4. Aktuel `AGENTS.md` og `CLAUDE.md`. Nyeste remote har AGENTS; en læsekopi findes også i `artifacts/claude-brief-20260921/github-source/AGENTS.md`.

Rå Trello-data findes i `trello-board-snapshot.json` og `trello-checklists.json` i samme artifact-mappe. Alle 131 kort og checklists er allerede hentet. Brug beskrivelsernes seneste status og ejerbeslutninger; historiske afsnit kan være forældede. Gencheck ændringer siden snapshot, ikke en blind genimplementering af hele boardet.

Baseline ved gennemgangen:

- Lokal main var `cd8d5bf9c4b1a234066cacac801e848d4b549033`, mens origin/main var `d17fa28f6d19b3c7c060a9fc607c2171588232e3`. Der findes mange uvedkommende untracked filer.
- Nyeste udviklingsbranch var `origin/codex/six-improvements-20260920` på `736f417a738c922cd8db7143c13f7cd3085ac038`.
- PR #2 er audit → main, PR #3 er improvements → audit. Bevar stacken; undgå at miste eller duplikere ændringer ved at arbejde ud fra den gamle main. Ingen automatisk merge eller force-push.
- Den åbne Studio-place var v1958, place `131311258779917`, universe `10559217407`. 154 scripts matchede nyeste branch på byteantal/fingeraftryk; 154/154 Source og editor-source stemte overens. Geometri/properties/native assets er ikke bevist identiske med Git-manifestets v1949.
- `github-source/` er en læsekopi til denne audit, **ikke** en deploymentmappe eller en ny repository-root.

**Studio er autoritativ.** Fetch og læs status, bevar et recoverable checkpoint før checkout-reconciliation, og arbejd isoleret hvor det er nødvendigt. Tag en frisk native backup og source/editor-baseline. Læs præcis den aktuelle instance før en scoped ændring, og recheck baseline inde i skrivningen. Ved samtidige ændringer: læs igen og foren den aktuelle ændring. Bulk-push aldrig en Git-/Trello-kopi ind over Studio, og restore aldrig en gammel place for at gøre filerne ens.

Eksportér verificerede ændringer fra Studio tilbage med korrekte paths, classes, hashes og relevante assets/properties. Commit kun opgavens filer efter kontrol af staged diff; ingen blind `git add -A`. Opfind ikke model-, animations- eller produkt-ID'er.

## 2. Arbejdsrækkefølge og definition af færdig

Gennemfør arbejdet i afgrænsede, testbare milepæle. Start med fase A, derefter B, C og D, når deres afhængigheder findes. Fortsæt med uafhængige opgaver, hvis et enkelt asset, en konkret ejerbeslutning eller ekstern test mangler. Lav ikke en stor ny framework-arkitektur omkring eksisterende systemer.

Skeln mellem kodefærdig, verificeret i Studio, verificeret publiceret, manglende art og afventende data/hardware. Ingen Trello-opgave må kaldes færdig på baggrund af kun source-søgning, en compiler eller gamle testnoter. Dokumentér også det arbejde, der reelt må vente; lav ikke falske resultater for en uges analytics eller ikke-tilgængelige spillere.

## 3. Fase A — Level 2-fejl og Level 3-navigation

### A1. PoolSlide skal reagere på det aktuelle mål

Kort: https://trello.com/c/rXhi1SZ8

Reproducer den rapporterede langsomme opstart og chase mod cirka ti sekunder gamle spillerpositioner. Instrumentér målvalg, goal-timestamp/alder, request/queue/start/slut, path-compute, route-certification/postprocess, cancellation/retry og faktisk bevægelse. Skeln mellem langsom shared navigation-preparation før spawn og gammelt mål under chase. Spor det samme request hele vejen.

Kig især i `ServerScriptService/Level 2 Systems/Level 2 Pool Slide Controller.ModuleScript.lua`, `Level 2 Pool Slide Navigator.ModuleScript.lua`, `Level 2 Pool Slide Rig Adapter.ModuleScript.lua` og deres configuration. Der findes allerede .25 s target refresh, .15 s goal refresh, 3 s path-request-timeout og 4 s planning-wall-timeout i controlleren. En gammel navigator-default er ikke nødvendigvis den effektive værdi. Async request-guards findes allerede; find den reelle forsinkelse frem for blot at sænke konstanter.

Gamle eller annullerede beregninger må ikke overtage nyere mål. Hold dyrt arbejde og retries begrænset; undgå nye planner-tasks hver frame, lange server-spikes og permanente fastlåsninger. Genbrug eksisterende navigation/collision-sikkerhed og håndtér tabt LOS, død, beskyttet spiller, skiftende mål og round teardown.

Kortet inkluderer **nye walk- og run-animationer lavet i Blender samt en synligt større model**. Ingen bestemt procent er bestilt. Aktuel template er `ServerStorage.Level2Assets.Level 2 Pool Slide Template`, PrimaryPart `RootPart`; observeret bounding size ca. 11.53 × 12.00 × 3.96. Den er allerede større end en historisk backup; brug den aktuelle model som udgangspunkt. Aktuelle Walk/Run-ID'er var 140239794149902 og 101625402038627, kun som baseline. Idle/Attack skal bevares medmindre tilpasning er nødvendig.

Find de faktiske rig-/Blender-kilder; forveksl ikke Level 1-entityens FBX'er med PoolSlide. Lav de nye walk/run-clips, integration og hastigheds-/transitionstilpasning, hvis de nødvendige kilder/værktøjer findes. Tilpas model/rig, clearance, collision og agentmål samlet. Test fodkontakt, fodglidning, drejninger og relevante korridorer i begge bevægelsestilstande. Hvis selve art-asset kræver Codex, lever præcis rig-/bone-kontrakt, referencehastigheder, source/export-format og integrationspunkt; markér animationsdelen som manglende. Et justeret gammelt clip tæller ikke som de bestilte nye Blender-animationer.

Accept: registreret før/efter med bevægende spiller, aktuelle chase-mål, begrundet latency-mål og målte typiske/værste tilfælde. Verificér sikker spawnafstand fra alle levende deltagere, spawn efter anden forskellige pumpe og escalation af **samme** entity efter tredje. Vis ingen wall-hits, utilgængelige ruter eller nye CPU-spikes. Verificér også gentagne runder.

### A2. PoolSlide-lyd skal skifte mellem fjern ambience og mund

Kort: https://trello.com/c/LigItMHi

Genbrug eksisterende pipe-groan-assets. Uden en aktiv PoolSlide: tilfældige klip, pauser og fjerne positioner i Level 2, også før første spawn. Ved spawn: én groan fra munden, derefter periodiske groans, hyppigere under chase. Den fjerne ambience skal være pauset, mens entityen er aktiv. Ved faktisk despawn: stop mouth-emitter/timere og genoptag fjern ambience, hvis Level 2 stadig kører. Ved round end/level exit: stop begge forløb fuldt.

Koordinér `StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua`, `Level 2 Entity Audio.LocalScript.lua` og `ReplicatedStorage/Level 2 Entity Audio Bank.ModuleScript.lua`. Der er allerede to lydveje, og den gamle scheduler kan blive slået fra af den nye bank. Sørg for tydeligt ejerskab og ingen dobbelte spawn-/chase-/attacklyde. Et lokalt stream-out er ikke et server-despawn; brug autoritativ aktiv-state/generation til dette skel.

Mundens attachment skal følge korrekt bone/åbning gennem animation og skalering, ikke ligge på root ved gulvet. Brug retning/afstand, naturlig dæmpning, variation og rene fades. Test før spawn, spawn, chase, despawn, streaming væk/tilbage, nyt spawn og round exit fra flere positioner. Kildelæsning dokumenterer ikke en lyttetest.

### A3. PoolFoam må ikke overlappe

Kort: https://trello.com/c/jecT8s86

Reproducer med mindst to aktive entities ved spawn, krydsende ruter, smal passage og fælles chase-mål. Brug lokal undvigelse/separation eller tilsvarende begrænset styring baseret på modellernes reelle størrelse. At slå CanCollide fra er ikke løsningen, hvis modellerne stadig går igennem hinanden. Undgå fysisk skub, jitter, permanent deadlock og køophobning. Bevar world-collision og spiller-/skadesregler. Mål ekstra serverarbejde og dokumentér før/efter.

Byg videre på Pool Foam Controller/Navigator/Proxy Factory i `ServerScriptService/Level 2 Systems`; lav ikke en parallel AI.

### A4. Reducér lag ud fra målinger

Kort: https://trello.com/c/Zpj0Gkbb

StreamingEnabled er allerede true. Profilér client frame time/spikes, memory, synlige/renderede objekter/lys, netværk og server CPU/navigation/world-generation hver for sig. I en kort audit-runde havde Level 2 71.596 genererede descendants og ca. 53.989 hos klienten. En baggrunds-Studio-måling var ca. 15 FPS; den er ikke et gyldigt normal-performance-benchmark.

Brug samme seed, rute, antal spillere og kendte enheder før/efter. Undersøg generation-retries, dyre loops, unødvendig persistence, modelgruppering, lys/skygger og dekorationskompleksitet. Justér streaming/renderafstand først ud fra målinger. Bevar solide gulve, objektiver, entity-state og sikre ankomster; fjern ikke loading-cover før readiness. Bevar især eksisterende atomic L2→L3-slide og hele collision-/floor-checken. Reduceret renderafstand er ikke i sig selv dokumentation for reduceret server-CPU.

### A5. Level 3: garanteret første CD og ny CD-reader

Kort: https://trello.com/c/6BVH4WmN

Placér altid én synlig CD på et bord i **første rum efter spawn**, bestemt ud fra den faktiske indgangsrelation. `Level 3 Layout Generator` har blandt andet `Roles.EntryDistrictRoomId`; valider relationen mod den byggede bane. Det er ikke nok at kalde en tilfældig CD for nr. 1. De øvrige fire placeres tilfældigt, tilgængeligt og uden dubletter. Der skal stadig være præcis fem.

Erstat den gamle exit-door-reader med en reader mod nærmeste tilbageværende CD. Brug Level 1-exit-vectorens faktiske øverste højre placering, safe insets og overlapshåndtering på PC, telefon og tablet. Opdatér efter bevægelse, andres pickup, death-drop, respawn og round reset. Brug den eksisterende server-state og små nødvendige opdateringer, også når en CD-model er streamet ud; klienten må ikke afgøre progression eller rewards.

Vis præcis `IN THIS ROOM` i blinkende Zyntra-rød, når spilleren er i samme **faktiske rum** som mindst én resterende CD. En CD gennem en væg må ikke give signal. Respektér ReduceFlashing med en stabil, tydelig variant. Fjern/reberegn signalet straks ved room-exit og pickup for alle berørte spillere.

Bevar WORLD/HELD/DROPPED/INSERTED-flowet, death-drops, disc-relay og eksisterende exitprogression. Guid kun mod CD'er, der faktisk kan samles op. Når alle fem er samlet, fjernes CD-pejling og rumtekst; spilleren skal stadig forstå afleveringen og den efterfølgende udgang. Bevar de fem samlede discs, også når flere spillere bærer dem.

Primære filer: `Level 3 Layout Generator`, `Level 3 World Builder`, `Level 3 Objective Controller`, `StarterPlayerScripts/Level 3 Reader Client`, `PuzzleUI` og `UIDevice`. Eksisterende `Level3_ModuleRoom`, CD-index/state og collection-attributter er relevante; inventér den friske runtime før ændring.

Accept: flere seeds, bordet i det rigtige første rum, fire øvrige gyldige spawns, korrekt nærmeste mål ved to spilleres pickups, samme-rum kontra nabovæg, drop/recovery, fem afleveringer, exit og HUD på alle relevante viewporttyper.

## 4. Fase B — forståelighed, måling og første runde

### B1. Shoptekster og resterende demoarbejde

Kort: https://trello.com/c/xQWVkwhw og https://trello.com/c/UNRk7Qy8

Ret “120-stud snapshot for 4s” og anden uforståelig afstandsjargon i de spillerrettede tekster. En egnet retning er “Scan nearby threats”, “LOW / MEDIUM / HIGH for 4 seconds”, “Ready again after 20 seconds” og en kort forklaring om, at den ikke giver præcise positioner eller garanterer sikkerhed. Bevar den faktiske 120/50-range; copy-opgaven ændrer ikke balancen.

Ret “Step off the plate to close”, fordi triggeren er usynlig. “Walk away to close” passer til den eksisterende afstandsbaserede handling; vis kun instruktioner for knapper, der faktisk findes. Nogle tidligere CLOSE-knapper er nu TRY DEMO. Bevar explicit BUY, autoåbning og demo-cleanup. Opdatér også eventuel gammel Advanced Equipment-toast uden at ændre engangsgrant.

Lygte-, hazmat/glowstick- og simuleret detector-demo er allerede leveret. Test/bevar dem; byg dem ikke igen. Tilføj eventmåling for product view, demo, bekræftet køb og faktisk brug. Kamera-demo kommer først, når kameraet findes. Demoer må ikke starte betaling, give ejerskab, bruge tokens eller efterlade udstyr i runden.

### B2. Måling før større adspend

Kort: https://trello.com/c/bIFdNWUf

Implementér en lille, servervalideret analytics-integration i de eksisterende flows. Mål join → sikkert loading-ready → round start → første objective samt første death og næste almindelige forsøg, med relevante tidsafstande og exits <60 s / 1–3 min. Skeln mellem session, runde og genforsøg; håndtér teleport/rejoin uden falske dubletter. Opdel PC/mobil og ny/returnerende. Brug kun dokumenteret acquisition-attribution; ellers Unknown.

Undgå en falsk funnel: død kan ske før objective, completion kan ske uden death, og køb kan ske uden demo. Separate funnels/custom events skal repræsentere disse grene. Roblox tæller tidligere funnel-trin som opfyldt, hvis et senere trin logges først. Log efter den faktiske autoritative handling; køb måles efter bekræftet grant/ejerskab, ikke efter åbning af betalingsprompt.

Officielle kilder: https://create.roblox.com/docs/production/analytics/funnel-events og https://create.roblox.com/docs/reference/engine/classes/AnalyticsService. Events kræver server og publiceret spil; Studio-tests er ikke bevis på modtagne dashboard-events. Brug begrænsede eventnavne/custom fields, ratebegrænsning og fejl, der ikke kan blokere gameplay. Verificér modtagelse efter den relevante færdige release.

Lever event-schema, dedup-regler og en læsbar plan for funnel med antal, konvertering, tider og de tre største tab. Før større ads kræves reelle sammenlignelige data, mindst en uge, modne D1/D7-kohorter, CPP og kildefordeling. Historiske tal fra 15/9 var 7,6 min., D1 3,76%, D7 0,02%; de er ikke nutidige resultater. 10–12 min. og D1 6–8% er interne arbejdsmål. Opret ikke en ny adudgift eller automatisk budgetforhøjelse.

### B3. Tidlig succes, entity-regler og retry

Kort: https://trello.com/c/us5TWr9O, https://trello.com/c/EYIT99eM, https://trello.com/c/2fiHi4q4 og https://trello.com/c/PR0ersiy

Genbrug eksisterende First Entry Guide, Mission Brief, objectives, team-feed, Back to Lobby og Continue/Return. Mål queue-/briefing-/loadtid og ret observeret unødig ventetid. Der skal være en tydelig solo-start og en tidlig, forståelig succes. Fjern aldrig en nødvendig sikkerhedsgate for at få et lavere tidsmål.

Lær hver entitys centrale regel i en tilgivende situation med læsbart billed- og lydsignal. Ingen påkrævet mikrofon eller lange nye popups. Efter død: kort korrekt årsag og konkret overlevelsesråd fra den faktiske dødsårsag; opfind ikke en forklaring. Et almindeligt nyt forsøg skal være let at finde. Dette kræver ikke gratis revive midt i en aktiv runde.

Test solo, tidlig gruppedød, party wipe, spectate, lobbyretur og ny kø. Kontrollér det reelle L-hold/touch-input; auditens syntetiske input gav ikke verificeret lobbyretur, men etablerede heller ikke en isoleret fejl. Brug nye spillere uden mundtlig hjælp til forståelsestest, når de er tilgængelige. Udviklerkonto/ESP er ikke en nyspiller-test.

### B4. QA og marketing-handoff

Kort: https://trello.com/c/lUKD3R8G, https://trello.com/c/V7m3zDSa og https://trello.com/c/kydyBl7u

Test almindelig solo-runde og to venner, som finder hinanden, starter sammen og spiller igen. Test telefon, tablet og svagere fysisk enhed i rigtig runtime: primære handlinger, læsbarhed, loading, shop, død og retry. Studio-touch/viewport-test er nyttig, men må ikke kaldes fysisk device-QA. Registrér konkret enhed, seed, spillerantal, måling og begrænsninger. Manglende hardware/personer stopper ikke uafhængigt kodearbejde.

Lever native gameplay-screenshots og en kort liste over faktiske løfter i første minutter til Codex' annonce-/thumbnail-polish. Level 4-konceptet må ikke markedsføres som eksisterende gameplay. Testdesign skal adskille annonce-CTR, play-through, CPP, spilletid og D1; ingen kampagnestart eller budgetændring er en del af denne kodeopgave.

## 5. Fase C — arkiv, kosmetik, variation og Level 4

### C1. Entity-/research-arkiv

Kort: https://trello.com/c/nWCCdowB

Udbyg eksisterende Field Notes: én side pr. entity, fundne/manglende spor, locked states og næste opnåelige mål uden at afsløre alt. Bevar gamle noter, progression og FIELD ARCHIVIST. Knyt eksisterende Daily Research og senere kamera/Level 4-fund til arkivet, når de relevante systemer findes. Lav once-only milestone-titler/kosmetiske rewards og robust migration. Ingen dubletgrant ved rejoin/retry. Mobilnavigation følger den eksisterende UI-stil.

### C2. Hazmat-skins med preview

Kort: https://trello.com/c/VSCGGIA9

Start med få tydeligt forskellige hazmat-mønstre/materialer. Genbrug eksisterende farvevalg og avatarpreview. Implementér owned/equipped/unowned, persistence, replikering og korrekt produkt-preview. Kosmetik må ikke ændre stats, støj, entity-detektion eller hitbox. Tidligere afviste Flashlight Casings/Results Frame skal ikke genindføres. 79–149 Robux er kun et designforslag; adskil færdig, testbar kode fra nye salg, der mangler besluttede priser/produkter. Lever asset-skabeloner og præcise overflade-/teksturkrav til Codex.

### C3. Kontrolleret variation

Kort: https://trello.com/c/OBjSW30k

Genbrug generator/objective-flow. Serveren vælger gyldige, fælles kombinationer pr. runde. Variér frivillige spor først. Bevar solo-reachability, tydelige ruter, spawn/exit og stabile entity-regler. Ingen nødvendig genstand bag sin egen lås. Test forskellige seeds og reset; Level 3's garanterede første CD må ikke randomiseres væk. Level 4 starter med to–tre kontrollerede opgavesæt.

### C4. Level 4 — The Quiet Suburbs

Kort: https://trello.com/c/Y2xXThBN

Læs hele `artifacts/claude-brief-20260921/LEVEL4_DESIGN.md`; det er kravgrundlaget med alle ti tjeklistepunkter. Åbn `level4-quiet-suburbs-concept.png` og `IMAGE_REFERENCE.md` som intern visuel reference. Billedet er ikke en færdig assetpakke eller dokumenteret in-game-indhold.

Byg først en gennemførbar blokmodel, derefter én fungerende prototype af hus/opgave/entity, dernæst fuldt gameplay og til sidst art-/audio-integration:

- 8–12 synlige huse i falmet creme, støvet gul og blågrå, mørke tage, præcise hække, få aflæselige facadeanomalier; loop med genvej og tre undersøgelseszoner. Tårn som landmærke, busstoppested/signalskab som exit. To–tre genbrugelige interiører.
- Tre signalundersøgelser i valgfri rækkefølge, tilgivende første succes og visuelle alternativer til lydspor. Finalens tre korte kontroller kan klares sekventielt solo. Bevar completion/reward/Continue/Return; kun spillere, der faktisk når ud, får escape.
- Original entity The Neighbour: høj, smal, lange underarme, stift arbejdstøj, mat glasmaske og unaturlig hovedhældning. Serverstyret patrol → investigate gameplay-støj → search → varslet LOS-chase → return. Ingen teleports oven på spilleren, wall-damage eller omniscient støjmål.
- Huse har sikkert/varslet/farligt med tydelige forvarsler og mindst ét nåeligt sikkert alternativ. Ingen skjult instant-kill eller låst spiller ved state-skift. Stille bevægelse og brudt LOS skal have værdi; dørene må ikke skabe permanent AI-deadlock.
- Varm eftermiddag skifter til koldere lys/dis ved fare, stadig læsbart på mobil. Begrænset dynamisk lys, modulære assets, ordentlig unload. Stilhed, retningsbestemt entity-lyd, rene fades og visuelle varsler. Dette skal ikke være endnu en Level 3 musikstop/bordmekanik.
- Gratis interact kan bruges i første version; gratis basiskamera kobles på senere. Betalt kamera/detector må aldrig være påkrævet. Detectorens eksisterende tag/level-extension kan bruges til den nye entity.
- Integrér korrekt L3→L4, solo/hold, død, re-entry, spectate, lobbyretur, reward-idempotens og reset. Alle opgavekombinationer skal være løselige efter død/disconnect.

8–12 minutter er designmål, ikke et opdigtet testresultat. Lav egne assets/layout/rig; Motion/Level 94 er tematisk inspiration. En blokmodel/prototype må ikke kaldes et færdigt level eller erstatte live-gates før det er klart. Lever fuld kode og præcise model-, animation-, tekstur-, lyd- og UI-kontrakter til Codex' polish.

## 6. Fase D — senere afhængigheder og økonomi

### D1. Research Camera

Kort: https://trello.com/c/cqvNQIIc

Byg efter research/arkiv. Gratis basiskamera kan registrere alle obligatoriske motiver; serveren validerer motiv, afstand, LOS og én reward pr. fund. Gem motivregistreringer i første version; en ekstern billedtjeneste er ikke nødvendig. Vis resultat/progression/næste mål, og lav kamera-demo i shop uden ownership/charge-bivirkninger. Senere Advanced Camera får begrænset night vision og kosmetik, som ikke ophæver entity-/lysreglerne. Foreslået 199 Robux er ikke en besluttet pris eller eksisterende product-ID.

### D2. Udfordringer efter completion

Kort: https://trello.com/c/FnF49TWk

Frivillige personlige rekorder: ingen dødsfald, alle research-fund og tid. Ingen global leaderboard i første version. Gem korrekt level, regelsæt, målvariation, relevante assists/re-entry og completion. Sammenlign kun sammenlignelige forløb; skill betalte gameplayhjælpemidler og revives tydeligt ud. Bevar normal progression og giv milestones én gang, også ved rejoin/receipt-/save-retry.

### D3. Token Earner 2x/3x/5x

Kort: https://trello.com/c/EtdsUM4e

Kravet er tre prisniveauer og en tydeligt forklaret engangseffekt på den eksisterende tokenbalance ved køb. **Priser, stacking, hvilke tokenkilder der multipliceres, og upgrade-semantik er ikke besluttet.** Afklar disse samlet, når implementeringen når økonomidelen; arbejd videre på øvrige opgaver imens. En mulig model er højeste ejede tier frem for multiplicering af tiers og en eksplicit upgrade-delta, men den må ikke behandles som en ejerbeslutning.

Implementér efter beslutningen serverautoritet, purchase/ownership-verifikation, atomisk balance+grant-ledger, once-only migration for tidligere ejere, samtidige køb, retry/rejoin, downgrade/duplicate protection og finite-safe bounds. Adskil earn-multiplier fra grant af købte tokens og balancesnapshot, så der ikke opstår selvforstærkende eller gentagne grants ved login. Test matematikken med konkrete balancer og 2→3→5-forløb. Vis det præcise før/efter-beløb og fremtidige regler inden explicit BUY. Ingen opfundne priser/IDs eller aktivering af uafklarede salg.

## 7. Bevar de nye færdige funktioner

Brug auditrapporten til detaljer. Disse er allerede bygget og skal regressionstestes, når de berøres:

- Daily Rewards, Lucky Wheel, tre Daily Research-mål med UTC-reset, Field Notes, markers og verificeret friend boost.
- Speed Potion +30% i seks sekunder, én pr. runde; Advanced Equipment focus +45% range/samme drain og +50% base-stamina; eksisterende engangsbonus og LaverSneglens entitlement.
- Expedition Packs atomiske 1 re-entry + 1 shield + 3 markers; re-entry ved dødssted med ti sekunders grace; almindeligt shield fem sekunder.
- Level 1's `ceil(players/2)` circuits og permanent tændte levers; korrekt guide/caption; actor-aware objective-feed på alle tre levels.
- Level 3-hiding uden tvungen udskubning; L2→L3's forbedrede collision, streaming-readiness og netværksejer-korrektion.
- Detectorens nuværende 120/50-range, fire sekunders reading, 20 sekunders cooldown, square art og responsive demoer. Den må ikke rulles tilbage til gamle 60/22-Trello-noter.

Lav fokuserede tests af ændrede kontrakter og kritiske regressioner. Genbrug eksisterende suites, men opfind ikke beståede multiplayer-, receipt- eller hardwaretests. Hold syntetiske data og testprofiler adskilt fra rigtige spillerdata; nulstil ikke eksisterende progression for at skabe en test.

## 8. Udtrykkeligt udskudt eller uden for denne implementering

- https://trello.com/c/XuxYAtTA: Discord/købsnotifikationer er udskudt. Ingen webhook, kanal eller besked.
- https://trello.com/c/GxhsmCC5: 14 dages 50%-udsalg skal ignoreres frem til 20. oktober. Ingen prisændring eller scheduling nu.
- https://trello.com/c/uI8hg2At: console/controller-hardware-QA er udskudt. Bevar eksisterende kode.
- https://trello.com/c/DIktjy8U: loading-kort #16 er skipped efter direkte ejerbesked. Genåbn det ikke som en gammel releaseblokering. Nye fejl og regressioner i berørte overgange skal stadig håndteres ærligt.
- Arkiverede kort og Done er historik, ikke en ordre om at genimplementere deres oprindelige tekst.
- Ingen ændring af adbudget, adgangsindstillinger, aktive servere eller andre oplevelser.

## 9. Handoff til Codex, versionsstyring og release

Skriv løbende `G:/Roblox/MongoTV/docs/CODEX_POLISH_HANDOFF.md`, så arbejdet kan fortsætte efter et kontekstskifte. Medtag:

1. Implementerede Trello-kort/delkrav og status pr. milepæl; konkret restarbejde med afhængighed.
2. Ændrede Studio-paths og repo-filer, baseline, native backup, source/editor-parity samt commit/branch/PR. Skeln mellem lokalt commit, push og publish.
3. Før/efter-reproduktioner, seeds, spillerantal, device, navigation/CPU/memory/frame-målinger og faktisk afviklede tests. Skriv tydeligt hvad der ikke er verificeret.
4. Native screenshots af berørte HUD/shop/levels, gerne ens kamera før/efter; mobil-layout og synlige fejl. Marker placeholder-art.
5. En assetliste til Codex med præcise fil-/instance-paths, teksturmål/aspect/alpha/UV eller materialekrav, rig/bone/attachment-navne, animation-referencehastigheder og lydvarighed/loop/rolloff. Skeln mellem manglende originalfiler, upload og integration.
6. De få reelle ejerafklaringer, herunder tokenøkonomi/nye priser, og et konkret forslag med konsekvens. Undgå at gøre almindelige reversible kodevalg til spørgsmål.
7. En kort instruktion til Codex om at lave polish og sende nødvendige kodeændringer tilbage til Claude, så rollefordelingen bevares.

Følg repoets eksisterende publishing-præference for **færdige og verificerede** spilændringer til den eksisterende place. En prototype eller milepæl med en materiel blocker er ikke en færdig release. Aflever visual/asset-afhængige dele til Codex før de erklæres færdige. Verificér Roblox' faktiske publish-resultat; genstart ikke aktive servere. Lad aldrig denne opgave glide over i at publicere en gammel snapshot eller halvfærdig Level 4.

Start nu med en kort baseline-kontrol og den første reproduktion i fase A. Lever kode og beviser i sammenhængende milepæle; fortsæt uden at vente på godkendelse af en almindelig arbejdsplan.
