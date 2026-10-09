# HANDOFF — Studio/repo-oprydning, 2026-10-09

**Opgaven i denne session var analyse og en valgliste. Ingen eksisterende kode er rettet, slettet, deaktiveret eller erstattet af auditten.** Alle vores nye filer ligger i artifacts/repo-super-audit-20261009/. Næste session skal kun gennemføre de fund, ejeren vælger.

**Studio er source of truth:** [UPDATE] BACKROOMS: STAY QUIET, placeId **131311258779917**, universe **10559217407**. Det åbne sted oplyste placeVersion **2859**; det dokumenterer ikke, hvilken version der er publiceret. Find den aktuelle Studio-session via MCP og placeId; manifestets gamle Studio-GUID må ikke bruges blindt.

## Sådan bruges materialet

1. Læs dette dokument og [den samlede fundliste](findings-index.md).
2. Vælg konkrete IDer. [CSV](findings-index.csv) og [JSON](findings-index.json) har alle poster med status **Ikke valgt**.
3. Læs hele posten i delrapporten: kilde, afhængigheder, mindste ændring, risiko og regressionsport.
4. Tag et nyt native inventar før ændringer. En kilde, der er ændret siden snapshot, skal vurderes igen.

| Delrapport | Indhold |
|---|---|
| [Repo/tools/storage](repo-tools-storage-audit.md) | T01–T20: source-sync, manifest, installer, tests, bot, credentials, arkiver |
| [Klient/shared](clients-audit.md) | C01–C31: UI, input, audio, flashlight, streaming, private helpers |
| [Levelsystemer](levels-audit.md) | LE-01–LE-36: L1/2/3/4/6, pensionerede pakker, AI, generatorer, lifecycle |
| [Core/lobby](core-audit.md) | CORE-001–CORE-037: routing, admission, økonomi, lobby, servere, Workspace/plugin |
| [Øvrige tool-scripts](tooling-nonpython-audit.md) | X01–X05: Lua/Luau/CMD/shell-authoring, importfejl, upload-resume og rollback |

Rapporterne indeholder **129 fund/valg**: 124 i de fire hovedrapporter og X01–X05 i tooling-tillægget. Flere beskriver samme problem fra forskellige sider; det er ikke 129 uafhængige gameplaybugs.

## Hvad der faktisk er undersøgt

| Grundlag | Resultat / dybde |
|---|---|
| Native Studio | 230 scripts, ca.223.837 linjer og 9.189.891 bytes ved første inventar |
| Repo/plugin | 229 Lua/Luau-kilder; runtime-roots, arkivkopier og plugin inventeret |
| Source-parity | 200 matcher indholdskontrakten; 18 drift; 10 repo-only; 12 Studio-only |
| Afvigende native kilder | 30 komplette snapshots; 30/30 byte-fingerprints verificeret |
| Level-kilder | 62 kilder, 90.516 linjer; individuel [coverage](levels-source-coverage.md) |
| Client/shared-kilder | 86 Luau-kilder +15 remote-stubs +3 øvrige filer; individuel coverage i klientrapporten |
| Core/lobby/Workspace/plugin | Filoversigt og dybde i core-rapporten |
| Tooling | 331 filer, 275 kodefiler; alle 258 Python-kilder AST-parset; [coverage](tooling-source-coverage.md) |
| Resten af workspace | 10.444 filer scopeindekseret; 2.109 historiske kodefiler og 305 tomme filer identificeret |

Dette er et komplet inventar af det beskrevne audit-scope og en bred feature-/dependencyanalyse. Store genererede tabeller, pensionerede controllerbodies, historiske snapshots og flere store UI-/authoringbranches er strukturelt scannet med dybe hotspots. **De er ikke alle manuelt valideret gren for gren.** En senere session skal fuldt gennemgå den konkrete deletion-closure, før den fjerner internals fra disse filer. Coverage-markeringerne må ikke bortforklares som “alt er runtime-testet”.

Eksterne Blender-workspaces, publicerede assetbodies, andre places, live spillerprofiler og ignorerede lokale vaults/downloads er ikke fuldt auditeret her. Den aktive Arena-model peger på en builder, som mangler i repoet, T20.

### Samtidige ændringer

En afsluttende native recheck fandt eksterne ændringer i **GameManager** og **RoundUI**; de øvrige **228 scripts** havde samme source/class/enabled/RunContext som det første inventar. De nyeste to kilder er fanget og verificeret under [studio-final-sources](studio-final-sources/), og relevante flows er genlæst. CORE-001 består fortsat.

Repoets to spejlfiler var også eksternt opdateret. Derfor findes der ikke en komplet gammel sourcekopi til at rekonstruere deres præcise eksterne patch; tomme diff-artifacts er ikke “ingen native ændring”. Før/efter-fingerprints står i [studio-final-changes.json](studio-final-changes.json).

Af **2.941** før-hashede originalfiler var kun GameManager, RoundUI og tools/tests/test_round_loading_notice.py ændret ved sidste diskcheck; ændringerne er fra samtidig arbejde. Auditten skrev kun nye artifacts. Se [original-source-recheck.json](original-source-recheck.json). Der kan være kommet senere ændringer: reread før implementering.

## Featurekort: aktive sammenhænge, der skal overleve

| Feature | Aktiv kode-/dataejerskab | Skal bevares ved oprydning |
|---|---|---|
| Loading og first join | ReplicatedFirst Lobby Loading Screen, LoadingCardView, native First Entry Guide | Preload/failure escape, WELCOME/HELP/replay, spawnkamera |
| Lobby og køer | GameManager, TunnelLobbyBuilder, LobbyReimaginedPreview, QueueBridge | Canonical spawn, shop/supportboard, capacity/host/friend gates, build-fallback |
| Servertyper/admission | Native ServerKind og Live Level Server, Round Loading Runtime | Party isolation, ready/deadline, cover-terminaler, reservation/local fallback |
| Campaign L1–4 | GameManager, Completion Routing, generatorwrappers og adaptere | Lineage, ownership, acknowledgement, retries, continue/return |
| Level1 | MazeGenerator, PuzzleManager, EntityAI/Animation/Kill, BlenderRoomRenderer | Collision/nav/pits, fuses/levers, powerdown, chase, escape |
| Level2 | Round Adapter → Poolrooms Runtime → authored PoolroomsMap | Entry/exit, flume fallback, slide/transition, ragdoll og presentation |
| Level3 | Native Layout/WorldBuilder/Visual/Dressing + objective/hiding/music/Mall Manager | CDs, tables, concealed exit, blackout/final hall, nav/collision, balloons/crayon |
| Shared L3-kit | Native Kit Warmup → Level6BlenderRuntimeBake + Level6 Kit Metadata | V2 source/revision/chunks; Level6-navnet gør det ikke pensioneret |
| Level4 | Configuration/Objectives/LightDirector/Usher + authored Cinema | Reels/projectors/keypad, hiding, bonus/battery, exit, nav og door motion |
| Level5 | Native Level5PreviewAccess, lighting/audio, live-server entry | Public Void-game, party/death/reentry/finale/return |
| Level6 | Native Level6PreviewAccess → Playground Game + Playground Client | Public Arena, doll/hide/seek/tags/party/finale, graph/art fallbackpolitik |
| Player lifecycle | PlayerProtection, ReentryPlacement, avatar/suit/crouch/spectate | Epoch/life/lease, safe placement, capture/respawn, lobby-avatar |
| Økonomi | Native ZyntraMonetization, inventory/reentry/protection contracts | Receipt IDs, durable migrations/grants, session/revision/idempotency |
| Store/rewards | Store/shop/daily/wheel, ZyntraSkins/Config/Challenges/FriendBoost | Entitlements, kosmetik, købs-UI, daily/wheel og serverberegnede rewards |
| HUD og controls | RoundHud/Round HUD, TeamObjectives, UIDevice/UIStyle, NoiseReporter | Objectives/feed/compass, touch/gamepad, modal ownership, glyphs og safe insets |
| Flashlight/detector/items | FlashlightController/Sync/Profiles, DetectorService/Sensing/Visual, RouteMarker | Authoritative battery/item consumption, teammate visuals, placement og noise |
| Audio/accessibility | SoundController, levelcontrollers, entity audio/shake | Round/lobby/spectate gating, ReduceFlashing/Shake, late streaming |
| Lobbyfeatures | Luna, native Lobby DJ og Lobby Tunnel Reach + clients | Interactions, rewards, audio/pose, servertypepolitik |
| Leaderboards/badges | Native Leaderboards + completion/time events, achievement clients | Run-policy, confirmed writes, badge/reward compatibility |
| QA/authoring | UIRegression, loading/completion/level suites, MasterTuning/plugin/tools | Public QA-API, fixtures, editable sourcepacks og rollback |

## Første prioritet: korrekt grundlag og konkrete fejl

| Prioritet | IDer | Anbefaling |
|---|---|---|
| 1 | T01–T06, C01 | Afstem Studio→repo og metadata; sikre source-læsning, pending conflicts og Unicode installer før cleanup |
| 2 | CORE-001 | Ret L4→L5 continuation-adgang uden at hæve campaign-generatorgrænsen globalt |
| 2 | CORE-002 | Gør live-party deadline uafhængig af, om alle characters er levende |
| 2 | CORE-003/004/005, T08 | Reproducer økonomi-/marker-scenarier med fake stores før redesign; fix fixture-fejl så assertions faktisk køres |
| 3 | LE-10/11/13/17/18/19/20/22, C19/20 | Session/yield/error cleanup og readiness; bevar hele gameplayfeatures |
| 3 | LE-14/15/16 | Afstem native L3 tuning med faktisk topologi/geometry og readback |
| 3 | C17/C21–25, CORE-006/007/008/009 | Audio-/input-/modal-/save-/remote-/analytics correctness |
| 4 | T12/T13/T14 | Credential-konfiguration og idempotent botarbejde; ingen eksterne beskeder sendt under audit |
| 4 | X01–X05 | Authoring-staging/rollback, EditableMesh cleanup, upload-resume og aktuelle templates før næste reimport |

CORE-003/004 er **statiske scenarier om commit efterfulgt af tabt/fejlet svar**, ikke en observeret dobbeltbetaling i production. Protection/mute revisions og Daily.FlushId løser andre paths; de udgør ikke item/reentry operation-IDer. Reproducer både failure-before-commit og commit-then-error, før økonomikoden ændres.

## Konkrete fjernelseskandidater

**A:** stærk, afgrænset statisk kandidat. **B:** kræver feature-/authoring-/fallbackvalg. Ingen er certificeret med en gennemført fjernelse.

| Type | IDer | Præcis anbefalet grænse | Bevar |
|---|---|---|---|
| A | C02 | To comment-only marker-scripts | Round HUD/RoundHud og SoundController successors |
| A | C04/05/06, CORE-025, LE-07/32/34 | Nævnte private helpers/locals/no-op assignments; følger symboltabeller i rapporterne | Aktive nabofunktioner, APIer, initializer-sideeffects |
| A | C07, LE-34 | Kun ubrugt retur-binding, hvis ønsket | GUI/devicePart-kaldet: det bygger synlige objekter |
| A | LE-04 | Ragdoll-service appendix til seks gamle texture-prefixes; native målcount=0 | Hele aktive ragdoll-/joint-/collision-/transition-servicen |
| A, afgrænset rewrite | CORE-024 | Skip 219 furniture-placement clones, der destrueres under samme build | 66 collision curtains, lenses, tom folder, attrs og Ready-kontrakt |
| A/B | C08/C30, T18 | Kommenteret kode og allowlist af tomme strayfiler | Daterede sourcepacks/kvitteringer, local paritybeviser og relevante dokumenter |
| B | LE-01 | Pensioneret procedural L2-closure efter extraction af aktivt flume-bibliotek | MakeEntryTub, MakeTubeFromPoints og deres transitive collision/assets/helpers |
| B | LE-02/03 | Gammel Foam/Slide/pump-feature med devkommando, clients, tools og fixtures som samlet pakke | Authored Poolrooms runtime, exit/slide og ragdoll |
| B | LE-05, C03 | Gammel genereret L6-kopi og tilknyttede gamle klienter | Ny public Playground + L3's shared Bake/Metadata/sourcekit |
| B | LE-06/09/21 | Non-arena L6, v1 bake-fallback eller permanent doll fallbackpolitik | Aktuel Arena og aftalte nav/art recovery-forløb |
| B | LE-08/33 | Public debug furniture-API / ubrugte configfelter | Hiding immunity/occupancy, battery event-counter og noise registry |
| B | CORE-026/028/029/033, C31 | Gamle authoring exports, preview-choice/flags og repo-only QA/ESP | Native public entrypoints, aktive authored worlds og developer workflows |
| B | CORE-027 | Legacy lobbygeometri efter udskilt bootstrap/shop/support/fallback | Fallbackpolitikken og alle aktive boot-/queuekontrakter |
| B | CORE-030 | AvatarNormalize kun efter character-regression | Scriptet er enabled med appearance-hooks; “inert” kommentar er ikke slettebevis |
| B | T15/16/17 | Off-place arkiv af authoringtrees, daterede backups og legacy-mapdata | Verificeret komplet rollbackpack, publicerede animation IDs og buildkilder |

**T16: identisk script-source er ikke bevis for identiske backupfoldere.** Objects, properties, attributes, revisionskobling og templates skal sammenlignes og eksporteres særskilt. De friske A2-reflector-backups fra 2026-10-09 bør bevares, indtil mapsessionen er godkendt.

**Databevaring:** CORE-031/032 er ikke et forslag om at slette spillernes FieldNotes, receipt IDs, migrationsmarkører eller entitlements. Gamle savefelter kan være nødvendige, selv når deres gameplay er pensioneret.

Den fulde source-valgliste findes i [source-selection.md](source-selection.md). Repo-only betyder fraværende i det aktuelle Studio, ikke automatisk værdiløs authoringkode. Den må heller ikke automatisk installeres tilbage.

## Omskrivninger med bedst begrundet arbejdsmængde

| IDer | Gentaget arbejde | Mindste retning |
|---|---|---|
| C09 | Shop-descendant scan hvert frame ved partial streaming | Dirty/coalesced collect + bounded fallback |
| C10 | Statisk objective/feed render ≥10 Hz | Semantic dirty rendering; behold compass/timers |
| C11/12/13, CORE-020 | Beam/profile/widget arbejde hver frame/pakke | Én apply, off-guard og unchanged-property cache |
| C15/16 | DJ JSON decode20 Hz og statiske lamp caches | Metadata dirty-cache + korrekt late-stream lifecycle |
| CORE-012/013 | Party light scans og roster/zone scans i mange køer | Owned caches og ét roster-snapshot pr. relevant tick |
| LE-23/24 | Decor/floor scans, bounds/sort ved LOS/placement/drop | Generation-owned index med præcis invalidation |
| LE-25/26/27 | AI rayparams/exclusion-scans og ray før afstandsgate | Del filters, billig range rejection, målt broadphase |
| LE-28/29/30 | World scan pr. room, promptwrites hvert frame, retained tweens | Build-index, state edges og kun active tween-set |
| CORE-014/016/018 | Historiske cache-/connection-/notification-ID referencer | Bounded lifecycle cleanup; receipt-dedupe bevares |
| C28/29, CORE-021/022/023 | Avatar/player/idle-door/bake arbejde | Profilér først; cache/chunk kun når målingen retfærdiggør det |

Der er operations-/frekvensbeviser, men **ingen målt FPS-, MB- eller bootgevinst efter en ændring**. Brug samme map, seed, playercount og streamingforløb før/efter. Fjern ikke nødvendige rendersteps, raycasts eller safety-fallbacks alene fordi et loop er hyppigt.

## Teststatus fra denne session

| Kontrol | Udført resultat | Hvad det ikke beviser |
|---|---|---|
| Luau0.737 compile | 229/229 repo/plugin +230/230 native baseline; begge nye native sources og13 tool-Luau også PASS | Runtime/API/feature-/removal-sikkerhed |
| Python syntax | Alle258 tooling Python AST OK | Korrekt Blender-/HTTP-/datastore-adfærd |
| Studio-source contract | PASS | Full sync og aktuelt manifest er korrekt |
| Full-sync contract | FAIL på counts og SoundController metadata | Spillets Luau fejler ikke af denne grund |
|15 offline feature-checks |12 PASS,3 FAIL | Native driftede branches er ikke fuldt integrationstestet |
| De3 fail | Receipt fixture mangler ZyntraSkins; inventory bootstrap nil.content; gammel guideforventning | Ingen dokumenteret receipt-/native welcome-gameplayfejl |
| Kort Studio Play | Lobby loading-log:11,8s,68 assets,0 failed | Alle levels, multiplayer, performance eller ændret build |
| Console | Audio134572728354839 “not approved”; ældre L3 kit-error før baseline | Ingen anbefaling om at fjerne audio/kit-feature |
| Removal-trials | Ikke udført | Ingen fjernelse er allerede godkendt |

Studio skiftede eksternt mellem Edit/Play under læsninger; flere runtime-probes blev afvist. Auditten har ikke publiceret, købt produkter, skrevet liveprofiler eller sendt bot-/webhookbeskeder. Rigtige reserved-server teleportforløb kræver Roblox-clienttest, som ikke er udført. [Roblox TeleportService](https://create.roblox.com/docs/reference/engine/classes/TeleportService)

To eksisterende tests, der midlertidigt skriver mutanter til originale sourcefiler, blev bevidst ikke kørt. T07 beskriver flytning til tempkopier. Completion-suite må også isoleres fra aktive runtime claims, CORE-037.

## Rækkefølge til næste session

1. **Baseline:** frisk MCP-session/inventar; eksportér autoritative kilder, Disabled/RunContext, manifests og komplet place/asset-rollback. Beskyt samtidig arbejde. Ingen blind git reset/full sync.
2. **Mirror og fixture-reparation:** T01–T09, før features pensioneres. Nyt parity-resultat og relevante tests skal passe.
3. **Små batches:** vælg A-kandidater; én afgrænset diff ad gangen. Native fingerprints/compile og berørte featureflows kontrolleres.
4. **Featurepensionering:** vælg B-pakker og manuel authoring/fallbackpolitik. Følg hele dependency-closure, inkl. tools/tests/remotes/data.
5. **Correctness og økonomi:** separate commits; fake failure fixtures og session/epoch-tests, derefter Studio/Roblox regression.
6. **Performance:** tag profiler før; implementér én cache/frekvensændring; mål efter med samme scenarie.

### Minimumsporte ved kodeændringer

- Fresh ordinary/developer join; lobby, shop, help, cosmetics, party/queues, return/reset.
- L1–L6 entry→objective→win og death→reentry/return; L2→L3 slide, L4→L5 og L5→L6 continue.
- To og seks spillere, én langsom/manglende character, leave/respawn midt i loading/transaction/round cleanup.
- Keyboard/gamepad/touch:390×844,568×320,844×390 og tablet; hybrid keyboard+touch, chatfocus, safe insets og fælles modals.
- Partial stream/model før children, stream-out/in, missing graph/mesh/audio og permanent versus transient failures.
- Økonomi: duplicate receipts, lost commit-response, refund retry, unrelated profile push og reconnect; ingen live køb som ukontrolleret test.
- Fysiske kontrakter: nav, invisible collision, hide/CD/prompt anchors, joints, ragdoll, slide containment og cleanup.
- Muterende suites i isoleret testkopi; rigtige teleportforløb i aftalt Roblox-teststed/client.

En batch er færdig, når dens angivne regressionport er bestået, diffen kun indeholder valgte ændringer, og rollback er verificeret. En compile-pass alene opfylder ikke dette.

## Valg, der mangler en ejerbeslutning

Bevar de aktive features som udgangspunkt. Ingen manglende svar er fortolket som tilladelse til pensionering.

- Skal gamle procedural L2 encounters/pumps og den genererede L6-kopi permanent pensioneres?
- Skal non-arena L6, v1-kit, arch-rib editor og den store oprindelige lobby-fallback stadig kunne bruges?
- Hvilke dated backups/sourcepacks skal ligge i release-stedet versus et verificeret off-place arkiv?
- Bruges public authoring/debug exports, AvatarNormalize og gamle preview-flags manuelt?
- Skal DJ eje skærmen som modal, og skal private live-level lobbyer have Luna/Reach?
- Hvilke assisterede/dev runs må rangeres? Er gifts/backfills permanent policy eller afsluttede migrationer?
- Hvor ligger den faktisk anvendte Arena-builder/source, T20?

## Kort starttekst til næste session

> Studio er source of truth. Læs artifacts/repo-super-audit-20261009/HANDOFF.md og hele fundposterne for de valgte IDer. Reread aktuelle native sources, beskyt samtidige ændringer og tag komplet rollback. Gennemfør kun de valgte batches. Bevar nav/collision, public APIer, playerdata og de eksplicitte KEEP-dependencies. Dokumentér compile, relevante offline checks, Studio/Roblox-regression og eventuelle målinger. Stop en batch ved uafklaret afhængighed og læg den tilbage på valglisten.

## Evidensfiler

[Repo-inventar](repo-inventory.csv), [Studio-inventar](studio-inventory.json), [parity](parity.json), [native snapshot-index](studio-source-index.json), [snapshot-verifikation](studio-snapshot-verification.json), [final inventory](studio-final-inventory.json), [final snapshot-verifikation](studio-final-snapshot-verification.json), [source-recheck](original-source-recheck.json), [compile](compile-results.json), [supplerende compile](supplemental-compile-results.json), [offline checks](selected-checks.json), [assetinventar](studio-assets.json), [storage-references](storage-references.json), [backup source-hashes](backup-sources.json), [level-probes](studio-level-probes.json), [texture-probe](studio-water-props.json), [tooling-index](tooling-source-index.json).

