# Level-systemer: read-only cleanup-handoff, 2026-10-09

**Studio er source of truth. Ingen eksisterende runtimekode er ændret eller slettet.** Rapporten omfatter Level 1/2/3/4/6 Systems, de tre aktive generator-wrappers og native Studio-kilder inden for samme område. Den er en anbefalingsliste til en senere session, ikke en godkendelse til at slette hele mapper.

## Evidens og begrænsninger

- Alle 62 scoped kilder er indekseret fra ende til ende: 90.516 linjer / 3.248.617 bytes. Ingen tomme kilder. `Level 6 Kit Metadata` har tre meget lange datalinjer; `Level 4 Usher Nav` har 26.200 linjer genereret navdata. Begge indeholder væsentlige data og er ikke tomme eller defekte alene på grund af formatet.
- [levels-source-coverage.md](levels-source-coverage.md) angiver fuld semantisk, dyb delvis eller strukturel gennemgang pr. fil. [levels-source-index.json](levels-source-index.json) indeholder SHA256, alle funktioner, requires, events og loop/task-steder. Det ville være forkert at kalde 90.516 linjer fuldt semantisk dyblæst: store pensionerede controllerpakker, geometry-builders og den store Level 3 Test Suite er gennemgået strukturelt og målrettet, ikke alle internals linje for linje.
- `parity.json` og `studio-source-index.json` bruges til at vælge den autoritative native kilde, hvor repo og Studio afviger. Native Level 3 Layout/World Builder/Round Adapter/Worn Party-kilder afviger; native Level 3 Balloon/Crayon og Level 6 Playground Game findes kun som snapshots. Linjehenvisninger til disse er derfor **snapshotlinjer**, ikke repoets gamle linjer. Native snapshots er verificeret af root-sessionen: 30/30 identiske fingerprints ved eksport.
- Exact-kilder i repoet bruges som læsbare referencer til den samme native kode. Windows CRLF/LF kan give forskellige byteantal uden source-drift; anvend parity-status og fingerprints, ikke et byteantal alene.
- Caller-søgning er kørt i de aktive runtime-roots `ServerScriptService`, `ReplicatedStorage`, `StarterPlayer`, `Workspace` og i de aktuelle native snapshots. Tools/tests er fulgt, når de er direkte afhængigheder. En tekstsøgning alene er ikke bevis for unused; nedenfor kombineres den med runtime-entrypoints, eksporter og konkrete native erstatninger.
- Der er ingen delete-and-play test: brugerens instruktion forbyder kodeændringer nu. De beskrevne regressionstests er den nødvendige port for den næste session. Root-sessionens Studio-baseline og inventar skal læses sammen med rapporten; denne delrapport påstår ikke at have afprøvet de foreslåede ændringer.

## Aktive kæder, som oprydningen skal bevare

1. Level 1 genereres af MazeGenerator og kører PuzzleManager + EntityAI/Animation/Kill. BlenderRoomRenderer er en aktiv visualisering af autoritative primitive collision-/navdele.
2. `Level2Generator → Level 2 Round Adapter → Level 2 Poolrooms Runtime` bruger den authored Poolrooms-map. Den gamle WorldBuilder bruges stadig som bibliotek for flume/tub-generering. Slide Ragdoll Service er et aktivt server-script og dækker også slides fra Level 2 til Level 3.
3. Native `Level3Generator → Level 3 Round Adapter → Layout → WorldBuilder → Worn Party Visual Adapter → Room Dressing/Balloons/Crayon`. Objective/Hiding/Music/Mall Manager er aktive. Native Level 3 Kit Warmup kræver **Level6BlenderRuntimeBake**, og Layout/Visual kræver **Level 6 Kit Metadata**.
4. `Level4RoundGenerator → Configuration/Objectives/LightDirector/Usher` og den genererede `Level 4 Usher Nav` er aktive. Preview-værktøjerne betyder ikke, at selve gameplayet er dødt.
5. Native `Level6PreviewAccess → Level 6 Playground Game` kører den authored Indoor Playground/Arena. Navnet “Preview” er historisk: den nye kæde er en offentlig admission-/roundsti. Den gamle genererede Level 3-kopi i Level 6 Systems startes ikke længere af den native entrypoint.

## Pensionerings- og sletningskandidater

### LE-01 — Stor, verificeret pensioneret procedural Level 2-builder

**Kilde:** `ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua:5890`.

**Evidens:** `WorldBuilder.Build()` fejler nu altid med “procedural Level 2 is retired; Level2Generator uses the authored Poolrooms map”. Der er ingen build-gren, som kan nå den gamle hall/pump/kids/arrival-generation. Følgende lokale rødder har kun deres egen definition som kode-reference; de er ikke eksporteret og udføres ikke ved require:

| Lokal rod | Linje | Hvad den tilhører |
| --- | ---: | --- |
| `makeWallWithGaps` | 228 | Pensioneret hall-arkitektur |
| `makeHallFloor` | 358 | Pensioneret hall-gulv |
| `makeHallCeiling` | 927 | Pensioneret hall-loft/skylights |
| `makeColonnade` | 1552 | Pensioneret colonnade |
| `spiralStairPlacement` | 2028 | Pensioneret spiral-stair plan |
| `makeSlideHall` | 3002 | Pensioneret slide-hall |
| `makeExitFlume` | 3228 | Gammel procedural exit-root |
| `makeKidsHall` | 3943 | Pensioneret kids-hall |
| `shuffledLeverHandleColors` | 4254 | Gammelt pump-puzzle |
| `makePumpStation` | 4312 | Gammelt pump-puzzle |
| `makeCorridor` | 4653 | Gammelt hall-net |
| `dressHall` | 5015 | Gammel hall-dressing |
| `decoratePumpHall` | 5242 | Gammel pump-dressing |
| `makeHallEdgeWalkway` | 5355 | Gammel large-hall walkway |
| `decorateLargeHall` | 5447 | Gammel large-hall dressing |
| `makeArrivalConcourse` | 5705 | Gammel arrival |
| `makeCompatibilityArrival` | 5824 | Gammel arrival-marker root |

**Mindste sikre ændring:** isolér først den aktive `MakeEntryTub`/`MakeTubeFromPoints`-closure i et lille bibliotek og skift PoolroomsRuntime til dette. Fjern derpå kun den pensionerede closure, constants og imports, som ikke indgår i det aktive bibliotek. De 17 rødder er ikke alene hele det transitive slettesæt; næste session skal følge deres helpers og kontrollere overlap.

**Vigtige afhængigheder:** PoolroomsRuntime:19-25 kræver WorldBuilder, og :47-48 kalder begge flume-eksporter, når det authored exit-slide mangler. Bevar `part`/folder/assets/config, collision-friction, endcaps, collision strips, one-way attributes og template-fallbacks fra :2178-2649 og :2708-2919. `makeLegacyTubeFromPoints` er en **aktiv asset-delivery fallback**, ikke død kode. `ArchRibMeshMissingKeys`, `EnsureArchRibMeshTemplates`, `ArchRibMeshKeyFor` :5894-5932 er editor-API; pensionér dem kun sammen med det tilhørende arch-rib tooling.

**Risiko:** medium ved extraction; høj ved at slette hele WorldBuilder. **Regression:** authored map med eksisterende slide; map med slide bevidst fraværende i isoleret testkopi; manglende mesh-template; open/closed collision og bore; one-way exit, ragdoll og overgang til Level 3. Sammenlign collision-attributes, start/end-position og fysisk gennemkørsel før/efter.

### LE-02 — Gamle Level 2 Foam/Slide-encounterpakker startes ikke i native gameplay

**Kilder:** `Level 2 Pool Foam Controller`, `Pool Foam Configuration`, `Pool Foam Proxy Factory`, `Pool Foam Animation Adapter`, `Pool Foam Navigator`, `Pool Foam Observer`; `Level 2 Pool Slide Controller`, `Pool Slide Configuration`, `Pool Slide Navigator`, `Pool Slide Rig Adapter` i Level 2 Systems.

**Evidens:** native RoundAdapter kræver PoolroomsRuntime og kalder dens Start :194. Den starter hverken FoamController, SlideController eller den gamle ObjectiveController. Søgning efter controller-navne/Start-kald finder egen pakke, historisk dokumentation og diagnostiske tools/tests, ikke et aktivt server-entrypoint. Navigatorernes store loops udføres derfor ikke på den native offentlige map nu; deres linjeantal er vedligeholdelsesvægt, ikke en påvist aktuel frame-time udgift.

**Forslag:** markér som samlet pensioneringspakke, hvis den authored map permanent har erstattet disse enemies. Flyt/arkivér eller fjern den samlede feature med klienter, tilhørende tests og READMEs efter ejerens valg. **Ikke** en automatisk selvstændig sletning af hver enkelt dependency: den gamle ObjectiveController indlæser bl.a. FoamConfiguration, og dev-caller findes, jf. LE-03.

**Risiko:** lav for native gameplay efter dependency-port; medium for tests/editor-værktøjer og fremtidig restaurering. **Regression:** Level 2 entry, exit, exploration, slide/ragdoll; ingen require-time fejl fra devpanel; native remote-/folder-inventar; de diagnostiske tools skal enten opdateres eller tydeligt pensioneres. Slet ikke en navfil, som en bevaret diagnostik stadig loader uden at justere den diagnostik.

### LE-03 — Gammelt pump-devværktøj er stadig en caller, men kan ikke arbejde i den aktive map

**Kilder:** `GameManager.Script.lua:347-360`; `Level 2 Objective Controller.ModuleScript.lua:971-984`.

**Evidens:** `level2PumpPair` lazily kræver den gamle ObjectiveController og kalder `DevActivatePumpPair`. Der findes ingen aktiv `.Start()` for controlleren, så `activeSession` er nil, og værktøjet returnerer `LEVEL_2_ONLY` selv i den nye Level 2. Controlleren må derfor ikke kaldes “ingen callers”.

**Forslag:** vælg mellem at pensionere devkommando + dens UI/README/tests sammen, eller implementere en ny devhandling, der passer til authored Poolrooms. Fjern først ObjectiveController bagefter. **Risiko:** lav for gameplay, medium for eksisterende dev-workflow. **Regression:** faktisk Level 2 devpanel-click skal enten være fjernet eller give det nye tilsigtede resultat; ingen 5/10-sekunders require-waits efter dependency-sletning.

### LE-04 — Global tekstur-patch for gamle Level 2 props har ingen aktuelle native mål

**Kilde:** `Level 2 Slide Ragdoll Service.Script.lua:506-574`.

**Evidens:** appendix-scanneren læser alle Workspace-descendants ved startup og ejer en permanent `Workspace.DescendantAdded`-callback for seks gamle prop-prefixes. `studio-water-props.json` viser **0 af alle seks** i Workspace, ServerStorage og ReplicatedStorage. De gamle procedural producers ligger i den pensionerede WorldBuilder, LE-01.

**Forslag:** fjern kun appendix `WATER_TEXTURE_RULES` og dets callbacks/helpers. Bevar selve ragdoll-servicen, remote-validation, collision-baselines og de gamle avatar-joint adapters. **Risiko:** lav for den aktuelle map; medium hvis arkiverede gamle props genindføres. **Regression:** ingen teksturændringer på den authored map; samtlige slides/ragdoll for native AJU og en understøttet Motor6D-avatar; re-entry/leave/respawn genopretter joints og collision.

### LE-05 — Den gamle genererede Level 6-kopi kan pensioneres; to shared-filer skal blive

**Evidens:** native `Level6PreviewAccess.Script.lua:8-17` siger eksplicit, at den genererede Level 3-kopi ikke længere startes og kræver i stedet `Level 6 Playground Game`. Repoets Preview Runtime findes ikke i Studio. Native Level 6 Controllers/Layout/WorldBuilder/Visual/Dressing bliver kun refereret af den gamle genererede kæde, ikke den nye Playground Game.

**Kandidater:** Level 6 Hiding Controller, Layout Generator, Mall Manager AI Controller, Music Sequence Controller, Objective Controller, World Builder, Room Dressing, Visual Adapter, Balloon Dressing, Crayon Wall Art samt deres Configuration, **når alle efterfølgende old-client/tool-referencer er håndteret**. Repo-only Preview Runtime er en spejl-/arkivkandidat, ikke native aktive runtime.

**SKAL BEVARES:** `Level6BlenderRuntimeBake` kræves af native Level 3 Kit Warmup:35-38. `Level 6 Kit Metadata` kræves af native Level 3 Layout:12 og Worn Party Visual Adapter:6. `ServerStorage.Level6BlenderKit`/revision-source er aktive Level 3-assets. Hele “Level 6 Systems” må ikke slettes.

**Mindste ændring:** sync først de native entrypoints og Studio-only Playground/Level 3 dressing-kilder ind i et kontrolleret mirror. Fjern derefter den gamle generated-feature som en lukket dependency-gruppe. Flyt evt. de to shared moduler og omret deres callers i en separat ændring. **Risiko:** medium; høj ved blanket-folder delete. **Regression:** public Level 6 queue, campaign continue fra Level 5, party-lock, suit, hide/seek/count, tags, party easter egg, catch/death/re-entry/finale/win/return; derefter et fuldt public Level 3 cold-start inklusive 279 kit-chunks.

### LE-06 — Playground Games gamle non-arena-map er en betinget, stor legacy-gren

**Kilde:** native snapshot `Level 6 Playground Game.ModuleScript.lua:129-151, 1169-1200, 1277-1296, 1613-1692, 1709-1735`.

**Evidens:** `studio-level-probes.json` viser den aktuelle authored model `Arena=true`, `Ready=true`, build-source `tools/level6_playground/build_arena.py` og NavGraph. De ovennævnte non-arena seek/exit/party-room-varianter er ikke valgt af den aktuelle model. De er dog stadig eksplicit understøttede runtime-grene, ikke urefererede funktioner.

**Valg for ejer:** bekræft, om den gamle free-roam/party-room map skal kunne genbruges. Hvis nej, kan non-arena branches og deres specifikke config fjernes. **Bevar path/follow og art-fallbacks**, så længe de også er tiltænkt graph-/mesh-fallbacks. `chooseSpot()` :1190 recurses uden stop, når `info.spots` er tom; dette er en latent fejl i den gamle non-arena-sti, ikke en observeret fejl på den aktuelle Arena.

**Risiko:** medium, fordi fallback-kontrakten ændres. **Regression:** verificér entydig Arena-admission; gamle map-afvisning skal være forklarlig; graph-missing og mesh-missing scenarier; ingen ændring i aktuel tag/finale/party-opførsel. Det nuværende authored build-tool mangler i repoet ifølge root-sessionen: arkivér ikke de native kilder/assets før reproducerbarheden er håndteret.

### LE-07 — Urefererede lokale Level 3 exit-guide- og intro-helpers

**Kilde:** `Level 3 Objective Controller.ModuleScript.lua:1067-1184, 1412-1438`.

**Evidens:** `prepareExitGuide` har ingen callers og indeholder et permanent `if false then` :1104. `markNearestGuideFixture`/`markGuideLight` bruges kun i den døde helper-closure. `scheduleIntro` har ingen caller; `IntroScheduled` er kun denne gamle helper plus init-state. RoundUI ejer nu briefing. Level 6-kopien har samme rester (:1044ff, :1075, :1362); prioritet er at pensionere hele gammel L6-kæde, LE-05.

**Forslag:** fjern de fire lokale helpers, den permanent false-gren og `IntroScheduled`-feltet. **Bevar** active `unlockExit` fra :1186, `Level3_ExitWay`-lyset, final-hall progression og cleanup af persistente legacy-markers. Kommentarens henvisning til gammel cleanup er ikke en caller til disse helpers.

**Risiko:** lav, så længe generiske fireAlert/fireSound/fixture helpers med aktive callers bliver. **Regression:** normal briefing én gang; fem CDs unlocker concealed wall, blåt exit-frame/way lights, final-hall chase og win; cleanup af et saved legacy marker-state. Tests med tekstbaserede section-delimiters skal justeres, hvor helper-navne bruges som boundaries.

### LE-08 — Retired furniture-suspension API i aktiv Level 3 Hiding

**Kilde:** `Level 3 Hiding Controller.ModuleScript.lua:41-46, 396-403, 448`.

**Evidens:** ingen runtime-caller af `SetFurnitureSuspended`; permanent furniture er den aktuelle kontrakt. Feltet startes false, og kun den ubrugte API kan ændre det. `tools/tests/test_level3_hidden_chase.py:537` bruger funktionsnavnet som tekst-section boundary; det er en testafhængighed, ikke gameplay-caller.

**Forslag:** fjern API, felt og gating-condition samlet, og flyt testens section-boundary. Bevar flush/hide immunity, occupant tracking, `Stop()` og gamle persistente attribute-clears i Adapter. **Risiko:** lav/medium pga. public debug-API/manual Studio-calls. **Regression:** enter/exit/flush på alle table anchors, 2+ occupants, immunity, død/re-entry/cleanup; start med gammel furniture attribute uden at afvikle den pensionerede suspension feature.

### LE-09 — Gammel v1 Blender-bake er en conditional shared-library kandidat

**Kilde:** `Level6BlenderRuntimeBake.ModuleScript.lua:137-154, 176-187`.

**Evidens:** aktiv public Level 3 kræver revision SHA `d2ed...cc6b` og v2-kit med 61 families/279 chunks/74.092 triangles. Warmup afviser et rent v1-resultat. V1 bruges kun, hvis revision-source mangler; den gamle generated L6 Preview Runtime er ikke længere native caller.

**Forslag:** behold hele shared bake-motoren. Vælg særskilt, om en 49-kit restaurerings-/editor-workflow stadig skal understøttes. Hvis nej, kan v1 atlas/image-closure og schema-fallback pensioneres med eksplicit v2 fail-fast. **Risiko:** medium for legacy restauration, lav for current public v2. **Regression:** cold public Level 3 v2-bake, cached kit reuse, concurrent warmup, bounded memory/failure cleanup og en klar fejl ved manglende revision-source.

## Konkrete korrektheds- og lifecycleproblemer

### LE-10 — Level 1 flicker kan gen-tænde lamper efter BLACKOUT/ESCAPE

**Kilde:** `MazeGenerator.Script.lua:2012-2030, 2033ff, 2152-2160`.

**Evidens:** NORMAL kontrolleres kun før det lange blink-loop. Flere yields efterfølges af `setLight(..., true)` uden ny mode-check. BLACKOUT/ESCAPE appliceres kun ved mode-edge. Et blink startet før edge kan derfor gen-tænde lampen bagefter, og den mørke fase retter den ikke igen.

**Mindste fix:** fang mode/generation-token og recheck efter hvert yield før en relight; mode-controlleren skal fortsat være autoritet for terminal darkness. Abortér gamle world-arbejdere ved teardown. **Risiko:** lav/medium; timing ændres ved modeswitch, almindelig NORMAL flicker skal bevares. **Regression:** tving NORMAL→POWERDOWN/BLACKOUT/ESCAPE midt i begge slags blink; efter endt wave skal alle tilsigtede lamper være slukket, også efter mindst to blinkperioder. NORMAL skal kunne genoptages korrekt.

### LE-11 — Level 1 nav-prewarm kan cache permanent false før en tilladt langsom generation

**Kilde:** `EntityAI.Script.lua:468-479, 840-860, 892-904`; `GameManager.Script.lua:1741-1744`.

**Evidens:** PitZones-wait stopper efter 30 sekunder. Maze-wait 60 sekunder bliver ikke tjekket, og `edgeOpen` memoiserer false, hvis Maze mangler. GameManager aktiverer Level 1 entity-scripts inden generationen og accepterer op til 180 sekunders world-build. En 70-sekunders build er derfor tilladt, men kan give fejl i AI nav/pit sensing resten af runden. Maze parentes først til Workspace ved :1933, så normal tidlig navigation bruger ikke staged geometry; fejlen er timeout/ready-synkronisering, ikke et påvist almindeligt lobbyproblem.

**Mindste fix:** bind prewarm til samme world/generation-ready kontrakt som generatoren; cache aldrig et resultat begrundet i “world ikke klar”; bind PitZones når den reelt dukker op, eller afbryd ved generation cancellation. **Risiko:** medium for startup flow. **Regression:** kontrolleret world-delay >30 og >60, men <180; navcache har valide ruter, AI krydser ikke pits; cancel/build/retry giver ikke gamle zoner eller callbacks.

### LE-12 — Level 1 exit-touch mangler den servervalidering, Level 3 allerede bruger

**Kilde:** `PuzzleManager.Script.lua:2388-2402`; sammenlign `Level 3 Objective Controller:1270-1283`.

**Evidens:** Level 1 accepterer participant + et touch-hit med character-parent og HRP. Den checker ikke levende Humanoid eller serverens root inde i triggeren. Level 3 behandler touch som wake-up og rechecker root mod triggerens lokale box. Oprydningen bør bevare den stærkere autoritet, ikke reducere den til en shared raw-touch handler.

**Mindste fix:** valider live character, `RoundActive`/Level 1, aktuelle session og HRP mod den owned exit-box før escape. **Risiko:** lav; en passende lille fysisk tolerance skal vælges. **Regression:** almindeligt indløb, hurtig løber gennem doorway, to samtidige escapees; touch fra død character/et fjernt root/out-of-round body må ikke markere escaped.

### LE-13 — Level 1 powerdown-delays refererer global session over yield

**Kilde:** `PuzzleManager.Script.lua:2462-2502`.

**Evidens:** første task.delay, yielding `ContentProvider:PreloadAsync`, og anden duration-delay checker kun den aktuelle globale sessions active/stage. De fanger ikke den session, som trak leverne. En gammel callback kan derfor ændre origin/mode/exit i en senere session med samme stage. Check før PreloadAsync er heller ikke et check efter yield. `ExitPowerDown` er placeret i SoundService og er ikke med i clearPuzzle-folderen; Ended er eneste destroy-sti.

**Mindste fix:** fang owningSession og recheck identitet efter hvert yield og i begge delays; knyt sound til session cleanup eller bounded destruction, også ved load-/play-failure. **Risiko:** lav/medium. **Regression:** stop under 1-sekund-delay, stop under langsom preload og stop under powerdown; start nyt run og færdiggør det; ingen gammel callback må unlocke/give gammel mode/origin i den nye world, og ingen sound skal være tilbage efter cleanup.

### LE-14 — Native Level 3 loop-override 3 kan aldrig generere en map

**Kilde:** native `Level 3 Layout Generator:113, 562-584, 655-658, 1221-1258`; `MasterConfiguration:173-174`.

**Evidens:** 2×5-grid har 13 mulige interne kanter; den nye planner skærer altid 2 væk, altså 11 tilbage. Et spanning tree af 10 rooms bruger 9, så der findes højst **2** ekstra kanter. Tuning tillader 3, og masterpanel annoncerer 0..6. Værdier ≥3 clamped til 3 giver “not enough unused grid edges” for alle forsøg/fallback-seeds. Dette er logisk deterministisk, ikke afhængigt af et særligt tilfældigt seed.

**Mindste fix:** hold den nye two-cut topologi og clamp/annoncér max 2 i både Master og runtime. Alternativt understøt flere loops bevidst og revalidér dead ends/sightlines; dette er større scope. **Risiko:** lav for max-2 fix. **Regression:** master values 0,1,2,3,6; 0..2 bygger korrekt connectivity/module placement; 3/6 skal være afvist eller normaliseret uden at blokere admission. Test flere pinned seeds og current default.

### LE-15 — Level 3 master-tuning kan ramme nye geometry asserts før retry

**Kilde:** native Layout:100-109, :860-881, :1228; Master room-size controls :155-165.

**Evidens:** samme planner tillader room sizes under den nye current map-størrelse, men assert kræver `RoomFloorArea >= 160072`. Gateway-gap resolution tillader ned til 24, mens authored inserted room kræver mindst 36 studs. Disse asserts er inde i `generateAttempt`, men `Generate()` kalder den uden pcall, så en infeasible konfiguration kan afbryde før det eksisterende retry/fallback-system kan håndtere fejlen. Nuværende default er ikke påvist fejlagtig.

**Mindste fix:** valider samlet konfiguration før seed-loop; UI/runtime bounds skal svare til mapens invariants. Returnér en kendt generationError for seed-specifik infeasibility, så retry faktisk virker. **Risiko:** medium, da eksisterende dev-tuning ændrer kontrakt. **Regression:** mindste/største accepterede master-rum, swapped min/max, current minimum area, ændrede gateway gaps og eksisterende seeds; ingen uventet admission timeout eller silent reset til gamle værdier.

### LE-16 — Exporteret Level 3 Tuning bliver stale efter Generate

**Kilde:** native Layout:142, :1222, :1261.

**Evidens:** `LayoutGenerator.Tuning = Tuning` eksporteres én gang. Hver Generate erstatter den lokale Tuning-table; exporten peger fortsat på den oprindelige table. Runtime bruger de nye værdier, diagnostik/tests, som læser exporten, kan vise gamle værdier.

**Mindste fix:** opdatér exporten efter resolveTuning, eller eksponér en readonly snapshot/getter. **Risiko:** lav; ændringen er primært diagnostic correctness. **Regression:** ændr ét tilladt Master override, kald Generate, og sammenlign generated geometry, Tuning-readback og configuration summary.

### LE-17 — Level 4 delayed Humanoid-bind kan installere connections efter Stop

**Kilde:** `Level 4 Objective Controller:1057-1069, 1210ff`.

**Evidens:** hookCharacter venter op til 10 sekunder, og forbinder derefter globalt uden session-/character-token. Stop kan i mellemtiden have disconnected og cleared listen. Den gamle worker kan tilføje en ny Died-callback bagefter; ved et efterfølgende Start bruger den callback globale reels/holder og kan droppe den nye sessions inventory. Level 3 Objective gør allerede liveSession-check efter wait.

**Mindste fix:** fang sessionSerial ved bind og recheck serial, character-identitet og aktiv manifest efter wait før Connect. **Risiko:** lav. **Regression:** delayed Humanoid, Stop/Start i wait-vinduet, død på gammel body; nye reels må ikke droppes, gamle callbacks skal være væk efter Stop, normal respawn/re-entry skal stadig få en watcher.

### LE-18 — Level 4 keypad har ingen roundLive gate

**Kilde:** `Level 4 Objective Controller:1174-1188`.

**Evidens:** serverhandleren checker code, participant, alive root, distance og attempt cooldown, men ikke `roundLive()`. Controlleren lever gennem resultat-/intermission-delay, og participant-flag er en separat tilstand. Gamle keypad requests kan dermed accepteres efter RoundActive=false, hvis body/flag stadig er til stede. De øvrige prompts bruger canUse→roundLive.

**Mindste fix:** kræv roundLive og aktuelt keypad ownership/prompt state, før forsøget behandles. **Risiko:** lav. **Regression:** korrekt/forkert kode i active round virker; samme request i result/intermission/cleanup/anden level virker ikke; en anden aktiv spillers bonus ændres ikke.

### LE-19 — Playground Games annoncerede graph-fallback er ikke komplet

**Kilde:** native Playground:528-535, :637-641, :1251-1265, :1494-1509.

**Evidens:** en Arena uden læsbar NavGraph får nil `s.nav` og en warning om PathfindingService-fallback. Non-chase Arena hunt kalder alligevel `self:routeTo` uden nav-check; routeTo→navNodeAt derefererer nav.origin. Den spawned seekBrain fejler. Finale hunt undgår nil route men står idle, i stedet for at bruge den annoncerede fallback. Aktuel native map har graph, så normal path er ikke påvist ødelagt.

**Mindste fix:** implementér graph-missing path/follow for Arena nearest-target-hunt og finale, eller afvis mapen tidligt med en konkret readiness-fejl. Fjern ikke PFS helpers som døde, før denne kontrakt er valgt. **Risiko:** medium. **Regression:** manglende Part_XX, corrupt graph JSON, manglende NavGraph, valid graph; hunt/finale skal enten bevæge sig korrekt eller afvise entry kontrolleret, aldrig efterlade en halvaktiv session med død brain.

### LE-20 — Playground EditableMesh-fejl kan lække engineresources under bake

**Kilde:** native Playground:375-403, :2188-2211; sammenlign RuntimeBake:31-53.

**Evidens:** editable mesh oprettes før vertex/triangle/bone-processing; `Destroy()` ligger kun efter den succesfulde processing. En fejl under AddTriangle/face UV/bone/weights exits outer pcall uden at destruere mesh. Slide-jobbet kan forsøge igen op til 40 gange. Den shared RuntimeBake har allerede pcall + Destroy på build-fejl og er en lokal model for fixet.

**Mindste fix:** garanter Destroy på både succes og fejl omkring hver allocation. Bevar fallback collision-tubes og simple doll, så art-problemer ikke fjerner fysisk gameplay. **Risiko:** lav/medium for art startup. **Regression:** kontrolleret triangle-/bone-datafejl og bake-service-fejl efter allocation; editable memory må ikke vokse pr. retry; valid assets ser uændrede ud og catch/finale virker også med fallback art.

### LE-21 — Første doll-bake-fejl låser alle senere rounds til fallback-block

**Kilde:** native Playground:443-462.

**Evidens:** én failed pcall sætter `dollTemplate=false` for resten af serverens levetid. Dette er et tydeligt designvalg og en recoverability-begrænsning, ikke død fallbackkode. En transient budget/service-fejl kan derfor permanent erstatte Counter med en block.

**Valg:** behold den stabile fallback, eller prøv et enkelt bounded/cooldown retry ved senere admission, uden parallel bakes. **Risiko:** medium for memory/latency, derfor ikke ubetinget anbefaling. **Regression:** første bake fejler, næste lykkes; intet retry-storm, ingen dobbelt child, samme round logic/kill camera hvis template fortsat fejler.

### LE-22 — Party-spin connection har ingen cleanup ved exception inde i pcall

**Kilde:** native Playground:1746-1833.

**Evidens:** spin oprettes inde i pcall :1815 og disconnectes først :1828. Hvis en senere handling i routine/music-delen kaster, springes Disconnect over; efter pcall destrueres made-parts, men callbacken kan fortsat holde dem og kaste på Heartbeat. Normal successful party disconnecter korrekt.

**Mindste fix:** gem connection uden for pcall og disconnect den ubetinget i fælles cleanup efter pcall. **Risiko:** lav. **Regression:** normal 30-sekunders party samt kontrolleret exception efter spin-installation; ingen tilbageværende callback/heartbeat errors, lys/player frames/doll pose/paused clock genoprettes.

## Effektiviseringer uden featuresletning

### LE-23 — Level 1 LOS gennemsøger alle Decor-children for hver ray candidate

**Kilde:** `EntityAI:720-752, 784-802, 1219ff`.

**Evidens:** `blockedByPlazaPile` laver Decor.GetChildren/full scan hver gang; clearLoS bruger op til tre bodypoints pr. target, perception hvert 0,1 sekund. Omkostning er op til ca. `30 × P` fulde Decor-scans/sekund før yderligere attack checks, selv om kun få children har BlocksEntitySight. Det er et operations-count estimat, ikke en profiler-måling.

**Mindste fix:** indexér kun sight-block volumes ved DecorReady og ved faktisk child/tag-change. Genbrug den aktuelle segment-vs-OBB-test. **Risiko:** medium, hvis dynamiske props/blocks ikke invalidates. **Regression:** plaza pile skjuler hoved/torso/fødder korrekt; almindelige CanQuery=false møbler ændrer ikke syn; tilføjet/fjernet blocker og ny world giver samme authority. Profiler den største map før/efter.

### LE-24 — Level 1 drop-/placement-søgninger gentager world-scans, bounds og sort

**Kilde:** `PuzzleManager:219-230, 257-280, 373-401, 547-585`.

**Evidens:** station-placement kan prøve op til 600 kandidater; nearestWall opretter fire ens RaycastParams pr. kandidat, og decorClear henter GetBoundingBox på alle models igen. fuseDropPosition henter alle Maze descendants, bygger alle floor records og sorterer dem efter afstand ved hver inventory-drop. Dette er byggestid/death-spikes, ikke et konstant frame-loop.

**Mindste fix:** genbrug params, og tag generation-owned snapshot af statiske Decor bounding boxes/floor candidates. Cache invalidates ved ny world og faktiske geometry-ændringer. Bevar fallback-søgningen efter en fysisk verificeret fri floor. **Risiko:** medium. **Regression:** mange seeds, crowded decor, fuses over pit/out-of-bounds/på møbel; samtlige krævede box/lever/relay counts opretholdes, drops kan stadig hentes; nye rounds bruger aldrig gamle floors. Mål generation og samtidige death/drop-spikes.

### LE-25 — Level 3 perception genopbygger ens filters for hvert target; navfilters hver frame

**Kilde:** `Mall Manager AI:778-792, 1741-1757, 1759ff, 1799ff, 1851ff, 4016ff`.

**Evidens:** sightParams skaber ny RaycastParams og enumererer alle players/avatars + furniture exclusions for hver LOS/hearing-candidate. Med P targets og P characters bliver filter-arbejdet kvadratisk i P pr. think. Navigation refresh skaber desuden nye ray/overlap params med samme playerliste på Heartbeat, selv om characters kun ændres ved joins/leaves/respawns.

**Mindste fix:** en fælles filterliste pr. sense-tick eller dirty cache på avatar/exclusion changes; genbrug params. Undgå at cache resultater for playerpositions eller visibility på tværs af frames. **Risiko:** medium. **Regression:** player join/leave/re-entry/corpse, table-hide, furniture exclusion, collision layers; samme target selection og wall occlusion, færre allocation/filter scans i MicroProfiler.

### LE-26 — Level 3 hearing raycaster før billig distance-afvisning

**Kilde:** `Mall Manager AI:1875-1879`.

**Evidens:** soundOccluded køres før distance og range compare, også for targets langt uden for hearing-range. Aktuelle normal/blackout occlusion multipliers reducerer range.

**Mindste fix:** beregn distance først og skip occlusion uden for den maksimalt mulige range. Hvis multipliers fortsat kan overskrides via tuning, brug `range * max(1,multiplier)` som conservative outer bound. **Risiko:** lav. **Regression:** normal/sprint/crouch, wall attenuation og blackout; grænsetargets med samme resultat, far-away targets uden raycasts; bevar measured-speed anti-spoof check.

### LE-27 — Level 3 furniture-exclusions er fuld linear scan i hyppige navprobes

**Kilde:** `Mall Manager AI:859ff, 874ff` og volume-clear/waypoint projection callers.

**Evidens:** point/segment checks scanner alle FurnitureNavExclusions; flere avoidance/lookahead/projection checks bruger dette pr. movement frame. Listen er round-static efter dressing.

**Forslag:** start med en billig AABB broadphase/spatial bucket index ved world build, der stadig udfører den præcise existing volume-test på candidates. Dette er en optimeringskandidat, ikke begrundelse for at slette de usynlige volumes. **Risiko:** medium/høj ved forkert narrowphase coverage. **Regression:** samtlige furniture corners, diagonale segmenter, gateways, table-hide/CD envelopes og avoidance; sammenlign offline/Studio probes mod gammel fuld scan på tusindvis af positions.

### LE-28 — Native Balloon Dressing scanner hele world for hver af 30 rum

**Kilde:** native `Level 3 Balloon Dressing:144-170, 188-205`.

**Evidens:** GetDescendants tages én gang, men collectBlocked løber over hele listen for hvert rum og regner footprint på mange irrelevante objekter igen. Eksisterende Room Dressing collectBlocked :111 bruger room-model descendants; balloons skal også se dressing/neighbor envelopes, så skift ikke blindt kun til room descendants.

**Mindste fix:** indexér block records én gang og fordel efter room bounds/spatial overlap, eller gruppér både authoritative room-parts og dressing-owned objects efter Level3_RoomId. Bevar cross-boundary collision og protected CD/table lanes. **Risiko:** medium. **Regression:** samme seed skal give samme plan/report/balloon placeringer og MAX_CLUSTERS-budget, ingen overlap med hide/table/CD/service envelopes; mål visual-generation time på native 32-room map.

### LE-29 — Level 4 Objective Heartbeat laver langsomt state-/promptarbejde 60 gange/sekund

**Kilde:** `Level 4 Objective Controller:1072-1127`.

**Evidens:** hvert frame enumereres players, hidezones/reel count og solo-participants; prompt Enabled/ActionText/Fuse state og mirror state sættes igen. Exit-detektion og holder-distance er blandet med dette arbejde.

**Mindste fix:** begræns hide/noise/state-refresh til fx 10–20 Hz og flyt prompt changes til state edges; behold hurtig exit-/holder-check eller brug sweeps, så en hurtig løber ikke overspringer exit-volume. Undgå en global blind 10 Hz-throttle af hele funktionen.

**Risiko:** medium for hiding/capture-timing. **Regression:** maksimum faktisk party, snelle hiding enter/exit, holder går væk/dør, solo/co-op overgang, fuse expiry og sprint gennem exit. Sammenlign detection latency og server frame budget; støj fortsat maksimalt hver 0,5 sekund pr. runner.

### LE-30 — Level 4 beholder alle færdige tweens indtil round Stop

**Kilde:** `Level 4 Objective Controller:208-213, 1221ff`.

**Evidens:** tweenTo append'er enhver tween til arrayet; completed tweens fjernes ikke før Stop. Gentagne wrong-order switch/reset/lever-forløb øger de retained referencer i et langt run. Level 3 playTween :82-96 har allerede et set + Completed cleanup.

**Mindste fix:** track kun aktive tweens i et set og fjern ved Completed; Stop skal stadig cancel'e aktive. Skab ikke et stort generisk cleanup-framework. **Risiko:** lav. **Regression:** 100+ wrong-sequence/reset-cycles, retained active tween-count bounded; Stop mid-animation restoring authored handles/doors; funktionelt og visuelt uændret normal puzzle.

### LE-31 — Level 3 opbygger visual-only primitive pynt, som straks skjules af Blender

**Kilde:** native `WorldBuilder` decorative roots, native Visual Adapter:44, :173-190, :320ff.

**Evidens:** builder bygger legacy primitives/Textures/SurfaceGuis og adapter sætter mange af dem invisible/disabled. Kolliders, nav/hide/CD/prompt/fixture anchors forbliver reelt autoritative og må ikke fjernes. Den redundante opbygning kan koste generation, instances og vedligehold, men hver skjult del er ikke automatisk død.

**Forslag:** lav først et maskinelt before/after instance-budget og en eksplicit liste over **rent kosmetiske** gamle Texture/Decal/Particle/UI/parts uden collision/nav/prompt/manifest refs. Skip deres konstruktion, når Blender er obligatorisk, efter at de tilsvarende meshes er garanteret. Bevar arrival tube, waiting room, ExitWay signs/glow, legacy collision wall og reactive anchor parts. **Risiko:** høj; endnu ikke et færdigt sikkert slettesæt. **Regression:** native multi-seed Level 3 suites + physical traversal, hide, carry/drop, final hall; hvert manifestfelt/invisible collision volume skal stadig være identisk. Denne kandidat må ikke implementeres via `Transparency==1 → Destroy()`.

## Små præcise rester og dokumentationsgæld

### LE-32 — Lokale Level 4 state/helper-rester

| Kilde | Kandidat | Evidens / mindste ændring | Risiko og test |
| --- | --- | --- | --- |
| Light Director:60-65 | `isStar` | Ingen caller; fjern funktionen. Bevar STAR_TAGS, som setStars bruger. | Lav; all cinema stars/blackout/restore virker. |
| Usher:41, :676 | `targetReason` | Skrives, læses aldrig; fjern binding/assignment, bevar chooseTarget reason hvis anden local logik bruger den. | Lav; alle target modes/diagnostic snapshots ens. |
| Usher:43 | `nextThinkAt` | Kun declaration; fjern binding. | Lav; ThinkSeconds scheduler uændret. |
| Usher:44, :927 | `stunUntil` | Kun init/reset; aktiv stun bruger andet state. | Lav; stun/cooldown/retreat tests. |

### LE-33 — Level 4 config knobs uden consumers

| Felt / linje | Nuværende evidens | Valg |
| --- | --- | --- |
| Projectors.RunNoiseSeconds :76 | Ingen runtime read | Fjern felt/kommentar eller implementér den tilsigtede post-threading lydvarighed. |
| Bonus.BatteryRefill :92 | Ingen read; client refiller fra Level4_BatteryRefill event-counter | Fjern field, **bevar counter**; eller før den tilsigtede fraction gennem server/client. |
| Usher.LitRetreat :121 | Ingen read; lit retreat styres direkte i think | Fjern misleading knob eller gør det til en virkelig toggle. |
| Noise.Door :130 | Ingen runtime configuration read | Fjern field alene, eller wire de relevante dørsounds; slet ikke registry “door”, som andre levels bruger. |

**Risiko:** lav ved fjernelse af ubrugte felter, medium ved implementering af nye semantics. **Regression:** projector noise, battery pickup/flashlight, Usher lit-retreat og door sounds; opdatér dokumentation så felt ikke længere fremstår tunable.

### LE-34 — Små Level 1 / native Level 3 remnants

| Kilde | Kandidat | Evidens / anbefaling |
| --- | --- | --- |
| PuzzleManager:1373 | `session.latchMode=true` | Ingen consumer. Fjern field; `test_level1_team_prompts.py:139` har også en gammel stub-field. Bevar persistent lever logic/remote flag. |
| Native Room Dressing:61-62 | `reservePerimeter` → 11.5-inset | Alle interne calls sender false; public Plan bruger også false. Fjern private argument/ternary, behold WALL_INSET. |
| Native Room Dressing:252-255 | Første breaker-specific `localPosition=...6.70...` | Straks overskrevet til 2.15 for samme kind. Brug korrekte 2.15 direkte i første expression. |
| Native Visual Adapter:425 | `local lampShade = devicePart(...)` | Bindingen læses ikke; **kaldet skaber synlig lamp shade**. Kun fjern `local lampShade =`, ikke devicePart-kaldet. |
| Native Layout:26 | “2x4” kommentar | Aktuel grid er 2x5/10 per district; ret beskrivelsen. |
| PuzzleManager:1548 | “one-box-per-player” kommentar | Aktuel boxCount er ceil(party/2), capped6; ret kommentaren. |
| Gamle L2 READMEs | Procedural pumps/Foam/Slide guides | Pensionér sammen med LE-01/02 eller marker historical; nuværende map har find-exit gameplay. |

**Risiko:** lav; kontrollér identiske seeded plans/interaction positions/lever remote payloads og lamp appearance. At en lokal variabel er unused gør dens initializer ikke automatisk død.

### LE-35 — Stor Level 3/6 duplikation findes, men shared-refactor er ikke første oprydning

**Evidens:** repoets Level 3/6-par deler efter normalisering af levelnavne ca. 90–96% linjer i Configuration/Hiding/Layout/MallAI/Music/Objectives/WorldBuilder/Dressing; Visual Adapter deler kun ca. 52%. Dette er målt repo-lighed, ikke native reachability. Den gamle L6 generated-feature er nu pensioneret af native entrypoint, mens native Level 3 er udvidet.

**Forslag:** foretræk LE-05's feature-pensionering frem for at bygge én kompleks generisk L3/L6 motor. Kun hvis ejer vil genoplive begge, er små fælles hiding/music helpers relevante. **Risiko:** høj ved at dele global attributes/session ownership blindt. **Regression:** to levels skal være isolerede i deltagere, attributes, cleanup, audio og callbacks; ingen regression ved senere native sync.

### LE-36 — Adapters flytter alle characters til Level 3 arrival i Studio/direkte build

**Kilde:** native RoundAdapter:393-412, :665-666; tilsvarende gammel Level 2 adapter-behavior.

**Evidens:** movePlayersToArrival enumererer alle Players med levende root, ikke kun den admitted party. Core-audit bekræfter, at public campaign L1-4 normalt reserverer separat roundserver, så det er **ikke** dokumenteret som almindelig production cross-party-fejl. I Studio deles Workspace med native L5/L6, og direkte adaptercalls kan derfor flytte en anden aktiv live-level spiller.

**Mindste fix:** hvis Studio multiplayer tests skal understøtte samtidige live levels, send faktisk cohort til adapter eller filtrér den konkrete roundbody/participant kontrakt; check også L2. **Risiko:** medium for world/lobby overgang. **Regression:** én spiller aktiv i L6, en anden launcher L3 i Studio; L6-spilleren bliver på egen map, campaign arrival/lobby teardown er stadig korrekt. Production reserved roundserver smoke test må fortsat bestå.

## Forhold, som bevidst IKKE anbefales slettet

- Level2Generator, Level3Generator og Level4RoundGenerator er tynde men aktive GameManager bridges; små wrappers er ikke død kode.
- Level 4 Usher Nav: fuld maskinel datavalidering finder 5.611 nodes, 20.585 edges, 0 invalid node references, 0 duplicate edges/nodes og én connected component med alle 5.611 nodes. Den store fil er runtime path data, ikke “dum loop”. Fallback marker-graphens O(n²) og hop-node scan har eksisterende begrundede ponytail-kommentarer og bruges ved begrænsede størrelser/frekvens; der er ikke påvist en bottleneck, som retfærdiggør rewrite nu.
- Level 3 Test Suite og Level 2 Exit Transition Test Suite er ikke automatiske gameplay-entrypoints, men bruges til deterministiske lifecycle/nav/death regressions og tools. Det er testkode, ikke unødvendig gameplaykode. Kør kun muterende tests i isoleret testkopi; flere debug helpers kræver levende round-setup.
- Invisible primitive collision/hiding/CD/prompt parts, Level 3 furniture nav exclusions og Level 1 Blender fallback anchors er aktive autoriteter. “Legacy” i navn, `Transparency=1` og `CanQuery=false` er ikke unused-evidens.
- Ragdoll legacy Motor6D-adapteren understøtter en anden avatar-rigklasse; selve texture appendix kan fjernes, men adapteren kan ikke fjernes af samme grund.
- Level 3 persisted legacy attribute-clears/cleanup er billige og beskytter saved/crashed place states. Urefererede generator-helpers kan fjernes, men det gør ikke cleanup-reglerne automatisk døde.
- Den nye native Level6PreviewAccess og Studio-only Playground Game/Level 3 Balloon/Crayon/Kit Warmup er aktive, selv om repoets gamle mirror ikke viser dem.

## Port til næste session og åbne valg

1. Sync/arkivér native source of truth uden at overskrive nye native features med repoets gamle mirror. Tag before-fingerprints og native inventory for præcis den place/session, der ændres.
2. Vælg LE-01/02/05 feature-pensioneringer og LE-06/09/21's fallback-politik. Afklar om arch-rib editor-workflow og gammel non-arena L6-map/v1 Blender-kit stadig skal kunne restaureres.
3. Lav separate små ændringer: lokale urefererede helpers/state/config; texture scanner; hver lukket legacy featurepakke; derefter correctness og målte performance-forbedringer. Ingen blanket-delete af mapper/transparent parts.
4. Kør de relevante eksisterende Python/Luau tests med opdaterede native snapshots, men brug Studio fysisk gennemspilning for collision/ragdoll/nav/camera/catch/escape. Samtlige compile/load/start/stop/error-paths er en del af definitionen på færdig oprydning.
5. Read-only/depth-begrænsningerne i coverage-filen skal ikke forsvinde i en sammenfatning. En senere session, som fjerner internals fra en stor delvist semantisk læst controller, skal først gennemgå netop den deletion-closure fuldt. Ingen anbefaling her garanterer safe removal uden de angivne regressioner.
