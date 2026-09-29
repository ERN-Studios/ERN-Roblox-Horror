# Astra: Level 3 som modulært Blender-map

Analysen bygger på det friske, autoritative Studio-snapshot fra place `131311258779917`, universe `10559217407`, version **2403**. Manifestet registrerer 16 scripts og `editorMatches=true` for alle. Dette er en kildeanalyse og et byggeforslag; gameplay, assets, performance og publicering er ikke verificeret her. Ingen Studio-ændringer er foretaget.

**Anbefaling:** Byg et genbrugeligt Blender-kit, som Roblox sammensætter efter en seedet graf. Bevar de eksisterende gameplaykontrakter. Gør indretning, materialer og arkitektoniske profiler udskiftelige, så samme kit kan bruges til både Frutiger Aero og en videreudvikling af party/mall-temaet. Der indgår **intet vand, ingen fontæner og ingen akvarier**.

## Hvad den aktuelle kode faktisk gør

Level 3 har en brugbar opdeling mellem plan, world builder og gameplay. Layoutgeneratoren leverer rum, links, adjacency og roller. World Builder opretter verden og returnerer et manifest til objective, hiding, musik og Mall Manager. Det giver et klart sted at integrere Blender-moduler uden at omskrive hele runden. Se [Builder.Build](<studio-source/ServerScriptService__Level 3 Systems__Level 3 World Builder.ModuleScript.lua:2091>) og [manifestets felter](<studio-source/ServerScriptService__Level 3 Systems__Level 3 World Builder.ModuleScript.lua:2230>).

Med de forfattede standardindstillinger er der tre distrikter à otte rum samt Arrival og Exit: **26 rum, 31 links og seks grafcyklusser**. Rumstørrelserne er nu 65–85 × 57–74 studs, med 11–13 studs højde. Finalekorridoren er 560 studs. Faktiske runtime-overrides kan ændre dele af dette og skal aflæses særskilt. Se [Configuration](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Configuration.ModuleScript.lua:30>) og [Master.Overlay](<studio-source/ReplicatedStorage__MasterConfiguration.ModuleScript.lua:375>).

Ruterne varierer, men variationen er mindre end et hurtigt kig på den randomiserede DFS antyder. Et 2×4-gitter har ti mulige interne kanter. Livegeneratoren udelukker én kant, bygger et spanning tree og tilføjer to loops; dermed ender alle ni tilbageværende kanter i den færdige distriktsgraf. DFS-rækkefølgen giver ved disse standardindstillinger ikke yderligere topologisk variation. De synlige strukturelle valg giver højst **36 kombinationer**: entry-row × entry-cut × fælles gateway-column × exit-row = 2 × 3 × 3 × 2. Det er en afledning af kildekoden, ikke et målt antal gennemførte layouts; constraints/fallback kan reducere antallet. Størrelser, CD-placering og dekoration varierer yderligere. Se [gatewayvalg](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Layout Generator.ModuleScript.lua:337>) og [udeladte kanter og grafbygning](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Layout Generator.ModuleScript.lua:552>).

Et nyt seed vælges ved rundegenerering, medmindre `workspace.Level3Seed` er en gyldig manuel override. Nyt seed er ikke det samme som garanteret ny topologi. Et fremtidigt krav om forskellig rute hver gang bør bruge en særskilt topologihash og afvise gentagelsen fra den foregående runde; kosmetiske forskelle må ikke tælle som en ny rute. Se [seedvalg](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Round Adapter.ModuleScript.lua:580>).

## Forskelle fra det lokale mirror, der skal bevares

Sammenligning af de 16 snapshots med deres lokale modparter fandt forskelle i fem filer: Configuration, Layout Generator, Hiding Controller, Mall Manager AI Controller og Test Suite. De øvrige elleve matcher tekstmæssigt.

- Configuration er version 46 og har større rum samt grænser for lange lige synslinjer.
- Layoutgeneratoren beskytter nu mod lange ubrudte forbindelser og kræver et sving før Signal Hall langs finaleaksen. Bevar hensigten i det nye map. Se [valideringen](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Layout Generator.ModuleScript.lua:1047>).
- **Alle fem CD-borde** skal nu have hver sin hide anchor inden for tre studs i gulvplanet. CD'ens collect-prompt har prioritet, mens CD'en ligger på bordet; hiding vender tilbage efter opsamling. Se [koblingen](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Hiding Controller.ModuleScript.lua:471>).
- AI har fået en lokal aisle-repair, der søger efter en fysisk farbar rute mellem møbler. Kommentaren beskriver en konkret tidligere fastlåsning og en afgrænset søgning; det er ikke dokumentation for nye målinger udført i denne analyse. Nye moduler bør minimere behovet for denne fallback. Se [buildRoomAislePath](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Mall Manager AI Controller.ModuleScript.lua:1118>).
- Test Suite har nye kontroller for faktiske sightlines og CD/hide-prioritet. Se [MeasureCoreSightlines](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Test Suite.ModuleScript.lua:1046>) og [ValidateCDHidePromptPriority](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Test Suite.ModuleScript.lua:1264>).

## Konkret kontrakt mellem Blender og Roblox

Blender-modulet bør have fast pivot ved gulvet, kendt footprint, anvendte transforms og navngivne tilslutningspunkter. Første udgave bruger fire kardinale sider med ens gulvhøjde og kompatible åbninger. Vindues-/vægpaneler lukker ubenyttede sider. Møbler må ikke strækkes vilkårligt for at passe seedede rumstørrelser; brug aftalte størrelsesklasser, udskiftelige vægsegmenter og lokale dekorationszoner.

En foreslået Roblox-definition pr. modul indeholder `ModuleId`, `Revision`, `Footprint`, `Sockets`, `AllowedRotations`, `ThemeVariants`, `GameplayAnchors` og `ClearanceZones`. Et socket beskriver transform, fri bredde/højde og kompatibel type. Tillad kun rotationer, som både holder de eksisterende kardinale beregninger og modullets funktionelle zoner korrekte.

Importér den synlige geometri adskilt fra simple colliders og markører. Opret Roblox Attachments/attributes ud fra validerede metadata eller en kontrolleret Studio-authoringfase; antag ikke, at Blender-objectnavne automatisk bliver en komplet Roblox-gameplaykontrakt.

Generation bør følge denne rækkefølge:

1. Seed og graf med garanteret connectivity, loops, målrækkefølge og sving.
2. Modulvalg efter rolle, footprint og aktive sockets.
3. Placering, væglukninger og korridorforbindelser.
4. CD/hide-rigs, spawn-, lyd-, lys- og exitmarkører.
5. Dekoration fra en separat RNG-stream.
6. Validering af graf, fysisk passage og manifest før aktivering.

Opdel RNG i topologi, modulvalg og dekoration. Gem seed, generatorversion og kitversion, så en rute kan genskabes efter en fejl. En kosmetisk ændring bør ikke utilsigtet ændre hele grafen.

Bevar især manifestfelterne `Rooms`, `Corridors`, `BlackoutScreamOpenings`, `Modules`, `HideTables`, `DiscPlayer`, `ExitPortal`, `FinalHall`, `MallManagerSpawn`, `MallManagerRuntime`, `Elevator`, `ElevatorSpawn`, `MazeStart`, `EscapeTrigger`, `ExitSafeSpawn` og `ExitPosition`. Bevar også planens `Rooms`, `Links`, `RoomById`, `Adjacency` og `Roles`.

## Fem rum til den første prototype

Prototypen skal bevise kit, passage og visuel kvalitet, før hele Level 3 ombygges. Det er fem **modultyper**, som senere kan gentages/varieres i den fulde graf. Et isoleret femrums-showcase må ikke præsenteres som en komplet fungerende Level 3-runde: den aktuelle validator kræver 26 rum og alle gameplayroller.

| Modul | Rumlig funktion | Aero-udgave | Party/mall-udgave |
|---|---|---|---|
| Velkomstrum | Tydelig ankomstretning og ét introduktionsbord med CD/hide-rig | Hvide afrundede paneler, cyan skiltning, blanke farvefelter | Slidt velkomstskilt, beige paneler, efterladte festdetaljer |
| Lounge | To mulige udgange, kontrollerede sightlines og en tydelig fri passage | Rundede siddemøbler, grønne planter, matteret glas | Cafeteriastole, tæppe, festborde og afdæmpet farve |
| Medierum | Genkendeligt landmark og overskuelig CD-position | Perioderigtige computerskærme, grøn/blå grafik, hvide arbejdsborde | Musik-/arcadehjørne, plakater, gammelt AV-udstyr |
| Galleri/overgang | Ruten kræver et sving; modulet tester to/tre aktive sider | Buede loftsprofiler, farvede paneler og lysnicher | Partyrumsdeling, opslag og forladte dekorationer |
| Signalrum | Særskilt slut-landmark med plads til disc player og eksisterende finaletilslutning | Stor glødende grafisk flade og hvid/cyan arkitektur | Mørkere musikrum, røde accenter og eksisterende uhygge |

Kurverne er i første prototype primært arkitektur og interiør. Den logiske gennemgang forbliver kompatibel med den nuværende navigation. Ingen af varianterne bruger vandmotiver som fysiske installationer.

## Begrænsninger og acceptkriterier

**AI-geometrien er den største tekniske risiko.** Korridorcentrering antager lige kardinale forbindelser; rumlokalisering og lokale repairs bygger på rektangulære footprints. Arbitrært buede korridorer, forskudte sockets og flere etager kræver en ny navigationsoverflade-/centerlinjekontrakt. Det bør være en særskilt fase. Se [centerCorridorWaypoint](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Mall Manager AI Controller.ModuleScript.lua:620>).

Den aktuelle fysiske agent har radius 5, sweep-radius 5,25 og højde 10 studs; pathfinding bruger radius 4, og korridorer er 14 studs brede. Blender-moduler skal bestå den faktiske sweep-test med møbler på plads. Passage, som en spiller kan gå igennem, er ikke tilstrækkelig. Se [agentmål](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Configuration.ModuleScript.lua:166>).

Bevar hide-riggens collider, nav exclusion, sight occluder, anchor og prompt under den nye visuelle bordmodel. Bevar finaleaksen og dens målinger i første udgave. Se [makeTable](<studio-source/ServerScriptService__Level 3 Systems__Level 3 World Builder.ModuleScript.lua:325>) og [finaleprogression](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Objective Controller.ModuleScript.lua:131>).

Før implementering godkendes, bør prototypen demonstrere:

- Flere seeds med forskellige verificerede grafstrukturer, sammenhængende mål og ingen åbninger mod tomrummet.
- Matcher mellem aktive sockets, collision, fuld kropspassage og AI-ruter i møblerede rum.
- Alle fem CD'er, promptprioritet, hide occupancy, tabte CD'er og finale i en fuld integreret runde.
- Faktiske sightlines i normal belysning og blackout; glassets query-/sight-adfærd skal stemme med det, spilleren ser.
- Aktiv multiplayer med målt server CPU/hukommelse, path requests/retries, reset-cleanup og klientperformance. Mesh-/lysbudget fastlægges ud fra målinger, ikke et løfte om et bestemt universelt polygonantal.

Snapshots indeholder ikke en dokumenteret aflæsning af den aktuelle `LoadStage` eller `Level3_Error`. Adapteren kan skrive `WORLD_ERROR` og rydde den genererede verden ved fejl, så en tom verden alene er ikke bevis på et defekt modulkit. En aktuel fejl skal registreres separat og må ikke fejlagtigt tilskrives dette forslag. Se [fejlgrenen](<studio-source/ServerScriptService__Level 3 Systems__Level 3 Round Adapter.ModuleScript.lua:672>).

Arkitekturen anbefales derfor i to kontrollerbare skridt: først fem overbevisende modulprototyper med eksisterende gameplayrigs og navigation; derefter en udvidet grafgenerator, der giver mere topologisk variation og bevarer de nye live-sikkerhedsregler. Studio forbliver baseline ved enhver senere implementation.
