# Samlet fundliste

Alle poster har status **Ikke valgt**. Listen omfatter fejl, omskrivninger, pensionsvalg, data-bevaringskrav og beviser; overlappende fund er ikke separate nye bugs. Vælg IDer til en senere session; læs altid hele posten og dens regressionport først. CSV/JSON kan filtreres efter område/prioritet.

| ID | Område | Fund / valg | Detaljer |
|---|---|---|---|
| T01 | Repo/tools/storage | Afstem spejlet fra Studio før noget ryddes op | [repo-tools-storage-audit.md:30](repo-tools-storage-audit.md) |
| T02 | Repo/tools/storage | Manifestet er også internt inkonsistent | [repo-tools-storage-audit.md:37](repo-tools-storage-audit.md) |
| T03 | Repo/tools/storage | Full sync har en anden source-læser end de sikre push/pull-værktøjer | [repo-tools-storage-audit.md:44](repo-tools-storage-audit.md) |
| T04 | Repo/tools/storage | Pull-audit overser ReplicatedFirst | [repo-tools-storage-audit.md:51](repo-tools-storage-audit.md) |
| T05 | Repo/tools/storage | Full sync kan kassere queued repo-arbejde uden konfliktkontrol | [repo-tools-storage-audit.md:58](repo-tools-storage-audit.md) |
| T06 | Repo/tools/storage | Generic installer fejler på almindelig Unicode | [repo-tools-storage-audit.md:65](repo-tools-storage-audit.md) |
| T07 | Repo/tools/storage | To tests muterer autoritative filer som en del af deres test | [repo-tools-storage-audit.md:72](repo-tools-storage-audit.md) |
| T08 | Repo/tools/storage | De vigtige købs-/inventory-tests når ikke frem til deres assertions | [repo-tools-storage-audit.md:79](repo-tools-storage-audit.md) |
| T09 | Repo/tools/storage | Onboarding-testen tester en anden featureversion end Studio | [repo-tools-storage-audit.md:86](repo-tools-storage-audit.md) |
| T10 | Repo/tools/storage | Gamle branch-specifikke installercommands bør pensioneres eller gøres generiske | [repo-tools-storage-audit.md:93](repo-tools-storage-audit.md) |
| T11 | Repo/tools/storage | Deprecated animationseksport er stadig publisherens default sti | [repo-tools-storage-audit.md:100](repo-tools-storage-audit.md) |
| T12 | Repo/tools/storage | Hardcoded lokal connectorcredential ligger i tracked tools | [repo-tools-storage-audit.md:107](repo-tools-storage-audit.md) |
| T13 | Repo/tools/storage | Discord/Trello-bot kan skabe dubletter | [repo-tools-storage-audit.md:114](repo-tools-storage-audit.md) |
| T14 | Repo/tools/storage | Done-markeringen kan låse en halvfærdig botoperation | [repo-tools-storage-audit.md:121](repo-tools-storage-audit.md) |
| T15 | Repo/tools/storage | Store authoring-animationstræer er kandidater til at flyttes ud af release-stedet | [repo-tools-storage-audit.md:128](repo-tools-storage-audit.md) |
| T16 | Repo/tools/storage | Ældre kodebackups er inaktive, og flere er byte-identiske | [repo-tools-storage-audit.md:135](repo-tools-storage-audit.md) |
| T17 | Repo/tools/storage | Gamle authoring-/diagnostikobjekter og legacy-mapdata kan arkiveres betinget | [repo-tools-storage-audit.md:144](repo-tools-storage-audit.md) |
| T18 | Repo/tools/storage | Root-junk og tomme filer kan ryddes op uden at rive testhistorik væk | [repo-tools-storage-audit.md:151](repo-tools-storage-audit.md) |
| T19 | Repo/tools/storage | Kodegrafen giver for mange historiske svar til dead-code-bevis | [repo-tools-storage-audit.md:158](repo-tools-storage-audit.md) |
| T20 | Repo/tools/storage | Den aktive Arena-builder er ikke i repoet | [repo-tools-storage-audit.md:165](repo-tools-storage-audit.md) |
| C01 | Klient/shared | Repo og aktiv Studio har forskellige klientfunktioner | [clients-audit.md:21](clients-audit.md) |
| C02 | Klient/shared | To aktive scripts er bevidst inerte migration-markers | [clients-audit.md:37](clients-audit.md) |
| C03 | Klient/shared | Seks pensionerede L6-klienter og ét disabled animation-patch kan arkiveres | [clients-audit.md:46](clients-audit.md) |
| C04 | Klient/shared | Præcise ubrugte lokale konstanter og bindings i aktive filer | [clients-audit.md:56](clients-audit.md) |
| C05 | Klient/shared | UIRegression har ubrugte interne briefing-data og uncalled helpers | [clients-audit.md:76](clients-audit.md) |
| C06 | Klient/shared | Små native rester i den nye guide og preview-filteret | [clients-audit.md:94](clients-audit.md) |
| C07 | Klient/shared | Ubrugte returvariabler må ikke medføre fjernelse af GUI-kald | [clients-audit.md:103](clients-audit.md) |
| C08 | Klient/shared | JumpscareUI indeholder en pensioneret, kommenteret billedversion | [clients-audit.md:111](clients-audit.md) |
| C09 | Klient/shared | ShopDisplay scanner alle shop-descendants hver frame ved partiel streaming | [clients-audit.md:117](clients-audit.md) |
| C10 | Klient/shared | RoundHud renderer statisk objektiv/feed mindst 10 gange i sekundet | [clients-audit.md:125](clients-audit.md) |
| C11 | Klient/shared | Flashlight-profil læses to gange på hver normal renderframe | [clients-audit.md:133](clients-audit.md) |
| C12 | Klient/shared | Slukket egen flashlight udfører stadig aim-math og raycast hver frame | [clients-audit.md:139](clients-audit.md) |
| C13 | Klient/shared | Flashlight battery-widget skriver samme tilstand hver frame | [clients-audit.md:147](clients-audit.md) |
| C14 | Klient/shared | Teammate flashlight-shafts raycaster pr. tændt beam pr. frame | [clients-audit.md:153](clients-audit.md) |
| C15 | Klient/shared | Native DJ JSON-dekoder tracklisten ved 20 Hz, også når DJ er slukket | [clients-audit.md:161](clients-audit.md) |
| C16 | Klient/shared | Native DJ's lamp-cache ignorerer senere streamed lights | [clients-audit.md:167](clients-audit.md) |
| C17 | Klient/shared | Native DJ-musik fortsætter ind i det offentlige L6 Playground | [clients-audit.md:175](clients-audit.md) |
| C18 | Klient/shared | Native DJ har ubundet ventetid på Sound.Loaded | [clients-audit.md:183](clients-audit.md) |
| C19 | Klient/shared | Native L5 rolling-sounds springer cleanup over ved level-exit | [clients-audit.md:191](clients-audit.md) |
| C20 | Klient/shared | New-map flicker-episode kan fortsætte efter grade-release | [clients-audit.md:199](clients-audit.md) |
| C21 | Klient/shared | WELCOME avancerer sider på tastetryk i chat/TextBox | [clients-audit.md:207](clients-audit.md) |
| C22 | Klient/shared | WELCOME og DJ booth skalerer touch-targets under 44 px | [clients-audit.md:215](clients-audit.md) |
| C23 | Klient/shared | WELCOME device-copy bruger en gammel hybrid-device heuristik | [clients-audit.md:223](clients-audit.md) |
| C24 | Klient/shared | WELCOME og DJ registrerer modal-flags, som det fælles modal-system ikke kender | [clients-audit.md:231](clients-audit.md) |
| C25 | Klient/shared | Aktiv HELP beskriver de pensionerede L2-pumps | [clients-audit.md:239](clients-audit.md) |
| C26 | Klient/shared | Fire QA-navne er nu kompatibilitetsaliaser til samme RoundHud-test | [clients-audit.md:247](clients-audit.md) |
| C27 | Klient/shared | ShopData's fælles profile-push clearer alle action/product pending states | [clients-audit.md:255](clients-audit.md) |
| C28 | Klient/shared | Hazmat foretager body-capture over descendants fem gange i sekundet | [clients-audit.md:263](clients-audit.md) |
| C29 | Klient/shared | L3 crouch-pose og DJ-pose scanner playerlisten hvert physics/frame-step | [clients-audit.md:271](clients-audit.md) |
| C30 | Klient/shared | Tom fil og lokale agent-state JSON er ikke runtime Luau | [clients-audit.md:279](clients-audit.md) |
| C31 | Klient/shared | Den gamle L2 second-pump Dev ESP findes heller ikke i Studio | [clients-audit.md:285](clients-audit.md) |
| LE-01 | Levelsystemer | Stor, verificeret pensioneret procedural Level 2-builder | [levels-audit.md:24](levels-audit.md) |
| LE-02 | Levelsystemer | Gamle Level 2 Foam/Slide-encounterpakker startes ikke i native gameplay | [levels-audit.md:56](levels-audit.md) |
| LE-03 | Levelsystemer | Gammelt pump-devværktøj er stadig en caller, men kan ikke arbejde i den aktive map | [levels-audit.md:66](levels-audit.md) |
| LE-04 | Levelsystemer | Global tekstur-patch for gamle Level 2 props har ingen aktuelle native mål | [levels-audit.md:74](levels-audit.md) |
| LE-05 | Levelsystemer | Den gamle genererede Level 6-kopi kan pensioneres; to shared-filer skal blive | [levels-audit.md:82](levels-audit.md) |
| LE-06 | Levelsystemer | Playground Games gamle non-arena-map er en betinget, stor legacy-gren | [levels-audit.md:92](levels-audit.md) |
| LE-07 | Levelsystemer | Urefererede lokale Level 3 exit-guide- og intro-helpers | [levels-audit.md:102](levels-audit.md) |
| LE-08 | Levelsystemer | Retired furniture-suspension API i aktiv Level 3 Hiding | [levels-audit.md:112](levels-audit.md) |
| LE-09 | Levelsystemer | Gammel v1 Blender-bake er en conditional shared-library kandidat | [levels-audit.md:120](levels-audit.md) |
| LE-10 | Levelsystemer | Level 1 flicker kan gen-tænde lamper efter BLACKOUT/ESCAPE | [levels-audit.md:130](levels-audit.md) |
| LE-11 | Levelsystemer | Level 1 nav-prewarm kan cache permanent false før en tilladt langsom generation | [levels-audit.md:138](levels-audit.md) |
| LE-12 | Levelsystemer | Level 1 exit-touch mangler den servervalidering, Level 3 allerede bruger | [levels-audit.md:146](levels-audit.md) |
| LE-13 | Levelsystemer | Level 1 powerdown-delays refererer global session over yield | [levels-audit.md:154](levels-audit.md) |
| LE-14 | Levelsystemer | Native Level 3 loop-override 3 kan aldrig generere en map | [levels-audit.md:162](levels-audit.md) |
| LE-15 | Levelsystemer | Level 3 master-tuning kan ramme nye geometry asserts før retry | [levels-audit.md:170](levels-audit.md) |
| LE-16 | Levelsystemer | Exporteret Level 3 Tuning bliver stale efter Generate | [levels-audit.md:178](levels-audit.md) |
| LE-17 | Levelsystemer | Level 4 delayed Humanoid-bind kan installere connections efter Stop | [levels-audit.md:186](levels-audit.md) |
| LE-18 | Levelsystemer | Level 4 keypad har ingen roundLive gate | [levels-audit.md:194](levels-audit.md) |
| LE-19 | Levelsystemer | Playground Games annoncerede graph-fallback er ikke komplet | [levels-audit.md:202](levels-audit.md) |
| LE-20 | Levelsystemer | Playground EditableMesh-fejl kan lække engineresources under bake | [levels-audit.md:210](levels-audit.md) |
| LE-21 | Levelsystemer | Første doll-bake-fejl låser alle senere rounds til fallback-block | [levels-audit.md:218](levels-audit.md) |
| LE-22 | Levelsystemer | Party-spin connection har ingen cleanup ved exception inde i pcall | [levels-audit.md:226](levels-audit.md) |
| LE-23 | Levelsystemer | Level 1 LOS gennemsøger alle Decor-children for hver ray candidate | [levels-audit.md:236](levels-audit.md) |
| LE-24 | Levelsystemer | Level 1 drop-/placement-søgninger gentager world-scans, bounds og sort | [levels-audit.md:244](levels-audit.md) |
| LE-25 | Levelsystemer | Level 3 perception genopbygger ens filters for hvert target; navfilters hver frame | [levels-audit.md:252](levels-audit.md) |
| LE-26 | Levelsystemer | Level 3 hearing raycaster før billig distance-afvisning | [levels-audit.md:260](levels-audit.md) |
| LE-27 | Levelsystemer | Level 3 furniture-exclusions er fuld linear scan i hyppige navprobes | [levels-audit.md:268](levels-audit.md) |
| LE-28 | Levelsystemer | Native Balloon Dressing scanner hele world for hver af 30 rum | [levels-audit.md:276](levels-audit.md) |
| LE-29 | Levelsystemer | Level 4 Objective Heartbeat laver langsomt state-/promptarbejde 60 gange/sekund | [levels-audit.md:284](levels-audit.md) |
| LE-30 | Levelsystemer | Level 4 beholder alle færdige tweens indtil round Stop | [levels-audit.md:294](levels-audit.md) |
| LE-31 | Levelsystemer | Level 3 opbygger visual-only primitive pynt, som straks skjules af Blender | [levels-audit.md:302](levels-audit.md) |
| LE-32 | Levelsystemer | Lokale Level 4 state/helper-rester | [levels-audit.md:312](levels-audit.md) |
| LE-33 | Levelsystemer | Level 4 config knobs uden consumers | [levels-audit.md:321](levels-audit.md) |
| LE-34 | Levelsystemer | Små Level 1 / native Level 3 remnants | [levels-audit.md:332](levels-audit.md) |
| LE-35 | Levelsystemer | Stor Level 3/6 duplikation findes, men shared-refactor er ikke første oprydning | [levels-audit.md:346](levels-audit.md) |
| LE-36 | Levelsystemer | Adapters flytter alle characters til Level 3 arrival i Studio/direkte build | [levels-audit.md:352](levels-audit.md) |
| CORE-001 | Core/lobby | P1: Level4 tilbyder continuation til Level5, men access-check afviser den | [core-audit.md:35](core-audit.md) |
| CORE-002 | Core/lobby | P1: én spiller uden levende karakter kan fastholde hele live-level-partiet ubegrænset | [core-audit.md:41](core-audit.md) |
| CORE-003 | Core/lobby | P1: re-entry debit/refund har ikke holdbar operationsidentitet | [core-audit.md:47](core-audit.md) |
| CORE-004 | Core/lobby | P1: samme uklare commit-resultat kan bruge et inventory-item uden dets effekt | [core-audit.md:53](core-audit.md) |
| CORE-005 | Core/lobby | P2: RouteMarker kan publiceres efter round-cleanup | [core-audit.md:59](core-audit.md) |
| CORE-006 | Core/lobby | P2: fejlede accessibility saves bliver markeret færdige | [core-audit.md:65](core-audit.md) |
| CORE-007 | Core/lobby | P2: ukendte remote action-navne kan udvide rate-limit-tabellen uden grænse | [core-audit.md:71](core-audit.md) |
| CORE-008 | Core/lobby | P2: profile RemoteFunction mangler et bounded svarbudget pr. spiller | [core-audit.md:77](core-audit.md) |
| CORE-009 | Core/lobby | P2: Level4 analytics normaliseres til `other` | [core-audit.md:83](core-audit.md) |
| CORE-010 | Core/lobby | P2: glowstick readiness bruger et nyt ti-sekunders budget for hvert medlem | [core-audit.md:89](core-audit.md) |
| CORE-011 | Core/lobby | P2: assisterede Level5/6-tider har en anden leaderboard-policy end Level1–4 | [core-audit.md:95](core-audit.md) |
| CORE-012 | Core/lobby | P2: party-mode finder de samme lights 20 gange i sekundet | [core-audit.md:103](core-audit.md) |
| CORE-013 | Core/lobby | P2: kømotoren scanner spillerroster for hver station på hver Heartbeat | [core-audit.md:109](core-audit.md) |
| CORE-014 | Core/lobby | P2: FriendBoost-cachen beholder historiske spillerpar | [core-audit.md:115](core-audit.md) |
| CORE-015 | Core/lobby | P3: friend-only køer har en separat friendship-cache og queryvej | [core-audit.md:121](core-audit.md) |
| CORE-016 | Core/lobby | P3: Crouch State beholder character-connections indtil PlayerRemoving | [core-audit.md:127](core-audit.md) |
| CORE-017 | Core/lobby | P3: glowsticks har tidscap, men intet antalcap | [core-audit.md:133](core-audit.md) |
| CORE-018 | Core/lobby | P3: PurchaseAlerts har en ubounded RAM-dedupe | [core-audit.md:139](core-audit.md) |
| CORE-019 | Core/lobby | P3: PurchaseAlerts-rategrænsen tæller alerts, ikke HTTP-attempts | [core-audit.md:145](core-audit.md) |
| CORE-020 | Core/lobby | P3: Flashlight aim gentager uændret mount/profile-arbejde | [core-audit.md:151](core-audit.md) |
| CORE-021 | Core/lobby | P3: Luna udfører idle propertywrites hvert Heartbeat | [core-audit.md:157](core-audit.md) |
| CORE-022 | Core/lobby | P3: PushDoors arbejder 20 gange/sekund også uden relevante spillere | [core-audit.md:163](core-audit.md) |
| CORE-023 | Core/lobby | P3: runtime mesh-bake har store synkrone batches | [core-audit.md:169](core-audit.md) |
| CORE-024 | Core/lobby | P3, stærk fjernelseskandidat: 219 end-furniture instances bygges og slettes i samme build | [core-audit.md:177](core-audit.md) |
| CORE-025 | Core/lobby | P3, stærk lokal kandidat: ubrugte Builder-lokaler og kun-ubrugt require | [core-audit.md:183](core-audit.md) |
| CORE-026 | Core/lobby | P3, betinget kandidat: tre gamle Level5-authoring API'er uden runtime caller | [core-audit.md:189](core-audit.md) |
| CORE-027 | Core/lobby | P3, redesign-kandidat: gammel lobbygeometri bygges stadig bag den nye lobby | [core-audit.md:195](core-audit.md) |
| CORE-028 | Core/lobby | P3, dormant delsystem: gammel developer Level4 queue-choice | [core-audit.md:201](core-audit.md) |
| CORE-029 | Core/lobby | P3, betinget kandidat: Level2-preview flaggrene uden aktiv true-writer | [core-audit.md:207](core-audit.md) |
| CORE-030 | Core/lobby | P3, betinget kandidat: AvatarNormalize er et dokumenteret inaktivt sikkerhedsnet | [core-audit.md:213](core-audit.md) |
| CORE-031 | Core/lobby | P3, bevar-data/kandidat-code: pensionerede FieldNotes er stadig profilkompatibilitet | [core-audit.md:219](core-audit.md) |
| CORE-032 | Core/lobby | P3, ejerbeslutning: one-off compensation/backfill og entitlement-policy | [core-audit.md:225](core-audit.md) |
| CORE-033 | Core/lobby | P3, stærk repo-kandidat: Preview/V9 Workspace scripts findes ikke i Studio | [core-audit.md:231](core-audit.md) |
| CORE-034 | Core/lobby | P3: leaderboard UI kan vise en write som fejlede | [core-audit.md:239](core-audit.md) |
| CORE-035 | Core/lobby | P3: reserved-server guards er ikke alle migreret til ServerKind | [core-audit.md:245](core-audit.md) |
| CORE-036 | Core/lobby | P3: Level3 warmup beholder en terminal fejl resten af serverens liv | [core-audit.md:251](core-audit.md) |
| CORE-037 | Core/lobby | P3, tool hygiene: Completion Suite muterer delt attempt-counter | [core-audit.md:257](core-audit.md) |
| X01 | Tooling non-Python | P2: Level4 phased importer ændrer den eksisterende map før build er valideret færdigt | [tooling-nonpython-audit.md:9](tooling-nonpython-audit.md) |
| X02 | Tooling non-Python | P2/P3: EditableMesh cleanup springes over ved build/upload-exception | [tooling-nonpython-audit.md:17](tooling-nonpython-audit.md) |
| X03 | Tooling non-Python | P2/P3: upload-success kan være uregistreret og derfor blive uploaded igen | [tooling-nonpython-audit.md:23](tooling-nonpython-audit.md) |
| X04 | Tooling non-Python | P3: Level4 lighting authoring-template er ældre end den aktive controller | [tooling-nonpython-audit.md:29](tooling-nonpython-audit.md) |
| X05 | Tooling non-Python | P3: den dokumenterede rollback/source-path indeholder en kontrolkarakter | [tooling-nonpython-audit.md:35](tooling-nonpython-audit.md) |
