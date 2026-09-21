# Trello, GitHub og Studio — grundlag for Claude

Gennemgået 21. september 2026. Spil: BACKROOMS: STAY QUIET [CO-OP HORROR].

## Konklusion

De nyeste funktioner fra GitHub findes allerede i den åbne Studio-version. Den næste kodeindsats bør starte med PoolSlides forsinkede chase, PoolFoams overlap, målt Level 2-performance og den nye Level 3-CD-opgave. Shoptekster og måling af onboarding/køb skal følge tæt efter. Arkiv, kosmetik, variation og Level 4 er næste indholdsfase; kamera, udfordringer og token-multipliers har flere afhængigheder.

Dette er en gennemgang og et arbejdsgrundlag. Codex har ikke ændret spilkode, flyttet Trello-kort, købt noget eller publiceret spillet. Claude skal skrive al implementeringskode. Codex overtager derefter visuel polish og asset-feedback.

## Kontrolleret baseline

| Kilde | Observeret tilstand |
|---|---|
| Projekt | `G:/Roblox/MongoTV` |
| GitHub | [ERN-Studios/ERN-Roblox-Horror](https://github.com/ERN-Studios/ERN-Roblox-Horror) |
| Lokal checkout | `main` på `cd8d5bf9c4b1a234066cacac801e848d4b549033`, 12 commits foran origin/main; mange eksisterende untracked filer |
| origin/main efter fetch | `d17fa28f6d19b3c7c060a9fc607c2171588232e3` |
| Nyeste udviklingsbranch | `origin/codex/six-improvements-20260920`, `736f417a738c922cd8db7143c13f7cd3085ac038` |
| PR-stack | [PR #2](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/2): audit → main; [PR #3](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/3): improvements → audit. Begge åbne ved gennemgangen; ingen CI-checks registreret |
| Åben Studio | Place `131311258779917`, universe `10559217407`, observeret PlaceVersion **1958** |
| Git-manifest | Nyeste manifest beskriver publiceret v1949; tidligere native backup v1947. README/audittekst om v1933 er historisk |
| Source-sammenligning | 154/154 scripts matcher nyeste branch på normaliseret byteantal og djb2-fingeraftryk; ingen afvigelser eller ekstra Studio-scripts fundet |
| Editor-kontrol efter test | Source og `ScriptEditorService:GetEditorSource` var identiske for alle 154. Source-fingeraftryk var uændrede gennem gennemgangen |
| Fordeling | 44 scripts i StarterPlayer, 15 i ReplicatedStorage, 57 i ServerScriptService og 38 historiske scripts/arkiver i ServerStorage |

Source-match dokumenterer ikke fuld lighed mellem geometri, assets, streaming-properties eller native place-filer. Den åbne v1958 må aldrig erstattes af en ældre Git/native kopi. Studio er autoritativ; Claude skal tage et nyt checkpoint og læse det aktuelle editor-indhold før hver ændring.

Otte commits på den nyeste branch ligger uden for den lokale HEAD:

| Commit | Ændring |
|---|---|
| f3b8923 | Studio v1933-snapshot og Trello-prioritering |
| 41fc4de | Lobby, objectives, lygte og supplies |
| a86b2dd | Expedition Pack-grafik |
| 34ccfa7 | Advanced Equipment, Level 1-puzzle, lyd og team-UI |
| 2eb7ed4 | Re-entry ved dødssted og 10 sekunders beskyttelse |
| bd72376 | Daily Research, detector, demoer, hiding og sikrere overgange |
| 19abe41 | Detector-grafik og ændret rækkevidde |
| 736f417 | Firkantet detector-grafik og tilpassede shoptekster |

Sammenligning af runtime-mapperne mellem lokal HEAD og nyeste branch: 38 filer, 1.240 tilføjede og 398 fjernede linjer. Hele ændringssættet, manifests, nyere PR-dokumentation og relevante live-scripts er gennemgået. Graphify-grafen var ældre og blev kun brugt til navigation.

## Trello-dækning

[Udviklingsboardet](https://trello.com/b/6FHYrsMR/backrooms-stay-quiet-development) indeholder 131 kort. Alle kort, deres beskrivelser og tilgængelige kommentar-/labeldata er hentet; checklists er desuden forespurgt særskilt for samtlige 131 kort uden fejl eller resterende sider. Fem kort har checklists, herunder Level 4's ti detaljerede designpunkter. Et andet tilgængeligt board indeholdt kun Trellos startguide.

| Liste | Alle kort | Ikke arkiverede |
|---|---:|---:|
| To Do | 23 | 17 |
| In Progress | 0 | 0 |
| Testing | 2 | 2 |
| Done | 99 | 95 |
| Ideas | 0 | 0 |
| Before big adsspend | 7 | 7 |

Der er dermed 26 ikke-arkiverede kort uden for Done. To To Do-kort er udskudt, og begge Testing-kort har en udtrykkelig tidligere ejerbeslutning om udsættelse/skip. Det efterlader 15 aktuelle To Do-kort plus syv før-ads-opgaver. Flere kort er delvist leveret eller afhænger af rigtige spillere/data. Trellos `complete`-flag må ikke erstatte listestatus; 12 kort i Done har flaget false.

Den fulde kortoversigt og alle rå snapshots ligger i `artifacts/claude-brief-20260921/`. `TRELLO_INDEX.md` dækker alle 131 kort. `LEVEL4_DESIGN.md` gengiver hele Level 4-tjeklisten.

## Funktioner Claude skal bevare

- Hologramshop med autoåbning, eksplicit BUY, skiltet SUPPLIES & UPGRADES og produktspecifik grafik. Normal/fokuseret lygte, hazmat/glowstick-avatar og simuleret detector-demo findes allerede. Resterende shoparbejde er især tekst, måling og senere kamera-demo.
- Daily Rewards, Lucky Wheel, Field Notes, Route Markers og verificeret Friend Boost. Daily Research har allerede tre personlige, gratis mål med reset kl. 00 UTC: fuse +1 token, lever +1, escape +2.
- Speed Potion: +30% bevægelsesfart i seks sekunder, tre tokens, én brug pr. runde, uden staminaændring.
- Advanced Equipment: +45% fokuseret lysrækkevidde, samme batteridræn, +50% base-stamina oven i eksisterende opgraderinger, hazmatfarver og den eksisterende engangsgrant. LaverSneglens specifikke entitlement skal bevares; eksisterende ejere må ikke få grant igen.
- Expedition Pack: én lagret re-entry, én femsekunders shield-charge og tre markers. Receipt og hele grant ligger i samme transaktion.
- Re-entry: dødsposition eller sikker fallback, ti sekunders beskyttelse fra frigivelsen. Et almindeligt shield varer stadig fem sekunder.
- Level 1: `ceil(players/2)` fusebox/lever-par; 1–2 spillere får ét, 3–4 to, 5–6 tre. Levers forbliver tændt uden ti-sekunderskrav. Den gamle spoken sætning om tidskravet er mutet med korrigeret caption; en senere ny voice-take er polish.
- Team-objective-feed med aktørnavn og servervalideret fremdrift i levels 1–3; lokalt spotted-scream til målet i Level 1.
- Level 3: Mall Manager-inspektion flytter ikke længere skjulte spillere; frivilligt exit, død og teardown frigiver dem. Opgaven hører til Level 3, selv om et gammelt kort siger Level 2.
- L2→L3: tykkere vægge, atomic continuation-model, kontrol af hele collision-sættet og floor-readiness samt korrektion hos netværksejeren. Det er eksisterende kode, som streamingarbejde ikke må ødelægge.
- Entity Detector: nuværende config er 120/50 studs, fire sekunders aflæsning og 20 sekunders cooldown. Gamle Done-noter om 60/22 er forældede. Den korrekte firkantede lobby-grafik er `90757067349588`.

## Konkrete fund og implementeringsspor

| Opgave | Underlag og betydning |
|---|---|
| PoolSlide chase | Trello beskriver cirka ti sekunders gammelt mål. Controlleren har allerede target refresh 0,25 s, goal refresh 0,15 s, path-timeout 3 s og planning-wall-timeout 4 s; blot at sænke en refresh-værdi er ikke en dokumenteret løsning. Mål køtid, beregning, route-certification, goal-alder, cancellation og fysisk bevægelse på samme spor. Historiske tests har også rapporteret langsom indledende route-planlægning |
| PoolSlide rig/animation | Live template: `ServerStorage.Level2Assets.Level 2 Pool Slide Template`, RootPart, ca. 11,53 × 12,00 × 3,96 bounding size. Walk-ID 140239794149902 og Run-ID 101625402038627. En gammel backup er kun otte units høj; det nye størrelsesønske skal vurderes mod den nuværende rig. Art-kilden til nye clips er ikke identificeret, og Level 1-FBX'er må ikke forveksles med denne rig |
| PoolSlide lyd | `Level 2 Sound Controller` har allerede fjern pipe-groan-scheduler og et root-attachment. En nyere `Level 2 Entity Audio` kan deaktivere dette forløb og ejer også entity-lyd. Kravet er en koordineret state machine, mund/bone-attachment, chase-frekvens og genoptagelse efter faktisk despawn — ikke to overlappende schedulere |
| PoolFoam | Fem modeller var aktive i test. Kildesøgning fandt ikke en tydelig lokal crowd-separation. Overlap blev ikke reproduceret i denne korte prøve; konkret multi-entity-reproduktion er stadig nødvendig |
| Streaming/performance | StreamingEnabled er allerede true. De øvrige streaming-properties kunne ikke læses med den anvendte Luau-adgang. Level 2 havde 71.596 genererede descendants på serveren og ca. 53.989 streamede hos klienten; profiler objektgrupper, navigation og lys før tuning |
| Level 3 CD | Layoutgeneratoren vælger aktuelt fem spredte module rooms, ikke et garanteret bord i første rum. Brug reel entry-room-relation og eksisterende CD-state/room-attributter. Runtime viste præcis fem WORLD-CD'er i fem rum |
| Level 3 reader | Native screenshot bekræfter “EXIT DOOR READER” nederst til højre på desktop. Desktop- og touch-layout har forskellige grene. Den ønskede CD-reader skal bruge Level 1's øverste højre safe-area-layout på alle enheder |
| Shopcopy | `ZyntraConfig` indeholder “120-stud snapshot for 4s”; `Shop Display Client` viser “Step off the plate to close”, men triggeren er usynlig. Nogle CLOSE-knapper er nu TRY DEMO, så vejledningen skal svare til den konkrete vares faktiske handlinger |
| Advanced Equipment-copy | `ZyntraMonetization` har stadig en gammel engangsgrant-toast med kun +5% stamina/battery. Opdatér forklaringen, hvis den eksponeres, uden at ændre grant/idempotens eller den nye +50%-bonus |
| Måling | Ingen `AnalyticsService`, `LogFunnel…` eller `LogCustom…`-instrumentering blev fundet i de aktive runtime-mapper. Servervaliderede funnels/custom events er et konkret kodegab; aktuelle retention-resultater kan ikke udledes af kildekode |

De præcise filnavne og acceptkrav står i Claude-promptet. Linjenumre skal genfindes mod den friske Studio-baseline; de må ikke bruges som faste patch-positioner.

## Faktisk runtime-gennemgang

Testmiljø: Roblox Studio, én spiller på udviklerkontoen, almindeligt lobby/queue-flow via Roblox Studio MCP. Ingen generel browser-/desktopstyring. Kontoen havde eksisterende entitlement og developer ESP; dette var ikke en ren førstegangsoplevelse.

- Lobby og Rewards blev åbnet og fotograferet. Den nye shop og Daily Research var til stede.
- Level 1 blev startet fra lobbyens queue. `LoadStage=READY`, `RoundActive=true`, HP 100, ét aktivt circuit og HUD `RESTORE FUSE BOXES 0/1` blev observeret. Ingen fuld Level 1-completion gennemført.
- Level 2 blev startet fra almindelig queue. `READY`, HP 100, 40 halls og 66 corridors. Requested seed 737430837; resolved seed 738163940 efter generation attempt 8. Fem PoolFoam-modeller blev registreret.
- Det eksisterende whitelisted developer-værktøj trak to forskellige pumper med fem sekunders mellemrum. To pumper og én PoolSlide-spawn blev registreret. Senere samples viste ingen levende chase-target, derefter DORMANT/cleanup og retur til lobby. Selve angrebøjeblikket og ti-sekundersforsinkelsen blev ikke dokumenteret, så dette tæller ikke som en bestået chase-/deathflow-test.
- Level 3 blev startet normalt. `READY`, HP 100, 26 rooms, 31 corridors, 24 hide-tables og fem WORLD-CD'er. Seed 1154781618; layout-hash `L3-2-abe3c038`. Readerens gamle tekst/placering blev dokumenteret med et native screenshot.
- Forsøg med syntetisk L-hold/klik gav ikke en verificeret lobbyretur fra Level 3. Der blev ikke konstateret en isoleret produktfejl; inputmetoden/modal-state kan spille ind. Test derfor det rigtige hold-input og retry-flow særskilt, uden at genåbne et Done-kort alene på dette grundlag.
- Den afsluttende konsolprøve indeholdt normale Level 1-opstartslogs. Det er ikke en fuld fejlfrihedserklæring for alle sessioner.
- Play blev stoppet. Studio står i Edit; alle 154 sources er uændrede, og editor/source stemmer overens.

En kort Level 2-prøve på 120 renderframes viste gennemsnit 66,65 ms, p95 68,88 ms og max 71,69 ms, omtrent 15 FPS. Studio kørte i baggrunden, så throttle er en sandsynlig forklaring; målingen kan ikke bruges som normal gameplay-FPS eller før/efter-benchmark. Stats-memory var ca. 4.970 MB mod ca. 4.098 MB i lobby; dette er Studio-processens prøve, ikke isoleret produktionsklient/server-memory.

Ikke verificeret: fuld solo-gennemspilning, friske nye brugere, to venner/2–6 klienter, publicerede Teleport/MemoryStore-forløb, fysiske telefoner/tablets, live purchase/receipt eller server-CPU under produktion. Kildeinspektion og historiske testnoter er holdt adskilt fra nye runtime-beviser.

## API-detaljer verificeret i officielle kilder

Roblox funnel-events sendes fra serveren i publicerede spil; Studio kan kun validere den lokale instrumentering. Springes et funnel-step over, tæller Roblox tidligere trin som fuldført. Derfor bør death/retry og valgfrie demoer ikke presses ind i en obligatorisk lineær objective-/purchase-funnel. Brug passende separate funnels eller custom events. [Roblox: Funnel events](https://create.roblox.com/docs/production/analytics/funnel-events).

Instance streaming kan reducere klientens memory og loadtid. Ændringer i radius/persistence kræver fortsat sikker arrival/readiness og målt effekt; de dokumenterer ikke automatisk lavere server-CPU. [Roblox: Improve performance](https://create.roblox.com/docs/performance-optimization/improve), [Instance streaming](https://create.roblox.com/docs/workspace/streaming), [Workspace-properties](https://create.roblox.com/docs/reference/engine/classes/Workspace).

## Afgrænsning og næste handoff

Purchase alerts/Discord er udskudt. Udsalg skal fortsat ignoreres frem til 20. oktober; der er ikke oprettet en automation eller ændret priser. Console/controller-QA er udskudt; loading-kort #16 er skipped efter ejerbesked. Dette fjerner ikke kravet om at regressionsteste berørte overgange ved nye ændringer.

Trellos foreslåede priser på nye skins og Advanced Camera er ikke godkendte produktpriser. Token-multipliers mangler pris-, stacking- og upgrade-regler. Claude kan lave kode og sikre testtilstande, men må ikke opfinde produkt-ID'er eller aktivere uafklarede salg.

Level 4-konceptet ligger i `artifacts/claude-brief-20260921/level4-quiet-suburbs-concept.png`. Det er intern art direction, ikke en færdig bane, animation eller annonce. Higgsfield viste 10 credits; ingen blev brugt. Prompt/proveniens står i `IMAGE_REFERENCE.md`.

Brug `CLAUDE_PROMPT_2026-09-21.md` til implementeringsopgaven. Claude skal levere et præcist `CODEX_POLISH_HANDOFF.md` med gennemførte ændringer, reelle testresultater, åbne afklaringer, asset-kontrakter og screenshots, så Codex kan polere uden at overtage kodearbejdet.
