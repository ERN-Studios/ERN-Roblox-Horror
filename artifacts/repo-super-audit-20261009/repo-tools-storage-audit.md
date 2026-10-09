# Repo, Studio, tooling og arkiv — audit 2026-10-09

Studio er source of truth. Denne rapport foreslår ændringer; ingen eksisterende spil-, tool- eller konfigurationskilder er ændret. Alle nye filer ligger i denne audit-mappe.

## Grundlag og evidens

- Sted: **131311258779917**, universe **10559217407**, snapshot af placeVersion **2859**. Versionen er metadata om det åbne sted, ikke bevis for hvad der er publiceret.
- Direkte `.Source`-inventar: **230 scripts**, ca. **223.837 linjer**, **9.189.891 bytes**. Det omfatter 42 ServerStorage-kilder; lagerkopier er ikke automatisk runtime.
- Manifestets faktiske scriptposter: **228**. **200** matcher Studio, **18** har indholdsdrift, **10** findes ikke i Studio, **12** Studio-scripts mangler i manifest/repo.
- De 30 Studio-kilder med drift eller manglende spejling er hentet i chunks og verificeret **30/30 byte-identiske** med inventarets længde + FNV-1a + djb2-fingerprints.
- Repo/plugin: **229** Lua/Luau-filer med ca. 219.000 linjer. **229/229** repo/plugin og **230/230** indfangede Studio-scripts kompilerer med den eksisterende Luau **0.737** CLI. Kodekroppe blev ikke kørt.
- Filinventar: **10.444** filer, heraf **2.109** historiske kodefiler i artifacts/drafts og **331** tooling-filer. **305** filer er tomme. Ignorerede lokale vaults, downloads, git-database og agenttelemetri er ikke et komplet assetinventar.
- Alle Python-kilder i tools/plugin er strukturelt indlæst og AST-parset; **0 syntaksfejl**. Importindeks er i `tool-imports.json`. Dette er ikke en dyb semantisk review af hver Blender- og testgren.

Fil-for-fil og verificerbare tal findes i `repo-inventory.csv`, `studio-inventory.json`, `parity.json`, `studio-source-index.json`, `compile-results.json`, `backup-sources.json`, `studio-assets.json` og `storage-references.json`.

## Prioritet og sikkerhed

**P0:** tab af data, forkert releasegrundlag eller brudt spilflow. **P1:** væsentlig runtimefejl eller dokumenteret dyrt arbejde. **P2:** sikker oprydning/testvedligehold. **P3:** valgfri konsolidering.

**A — stærk statisk kandidat:** konkret inaktiv blok eller identisk kopi, native status kontrolleret. Skal stadig bestå sin regressionport.
**B — betinget kandidat:** afhænger af feature-, authoring- eller rollbackbeslutning.
**R — rewrite:** bevar feature og offentlig kontrakt; ændr implementeringen.
**K — behold:** dokumenteret aktiv afhængighed.

Ingen kandidat er prøvet fjernet eller deaktiveret. Handoffen påstår derfor ikke, at en ændret build allerede er godkendt. Lav små batches i en isoleret kopi af det aktuelle Studio-sted.

## Fund

### T01 — Afstem spejlet fra Studio før noget ryddes op
**P0 · R · sikkerhed: verificeret.** `studio-sync-manifest.json`, `parity.json`.

Eksempel: repoets First Entry Guide er en 430-byte pensioneringsmarkør, mens Studio har en aktiv 31.986-byte welcome/onboarding-klient. ServerKind, Live Level Server, Level Leaderboards, Level 3 Kit Warmup, ny Playground Game og lobbyens DJ/Tunnel Reach findes kun i Studio. En oprydning ud fra repo alene ville miste aktiv kode.

**Mindste handling:** pull de identificerede Studio-kilder ind i spejlet og afstem fjernede/omdøbte poster; behold Studio-indholdet som udgangspunkt. Opdatér manifestets counts/hashes efter native reread. **Port:** nul indholdsdrift/missing/extra ved ny direkte Source-parity. Der skal være en særskilt beslutning om de 10 repo-only filer; de må ikke installeres tilbage blot fordi de er på disk.

### T02 — Manifestet er også internt inkonsistent
**P0/P1 · R · verificeret testfejl.** `studio-sync-manifest.json:11`, `tools/tests/test_full_sync_contract.py`.

Counts siger 226 scripts + 19 remotes = 245; items indeholder 247 poster (228 scripts + 19 remotes). SoundController-postens canonical hash/bytes svarer ikke til dens repo-fil. Full sync-kontrakttesten fejler på begge forhold, selv om kontrakthjælperens tests består.

**Handling:** genberegn metadata fra afstemte kilder, ikke ved at godkende drift blindt. **Port:** begge eksisterende sync-kontrakttests passer, og native parity passer. Testens nuværende fejl er ikke en Luau-kompileringsfejl.

### T03 — Full sync har en anden source-læser end de sikre push/pull-værktøjer
**P1 · R · konkret fejlscenario, ikke reproduceret mod en stale editor i denne session.** `tools/sync_from_studio.py:583`, `tools/push_repo_to_studio.py:409`, `tools/pull_source_from_studio.py:3`.

Full sync læser hele scripts med `script_read` og verificerer kun den lokalt skrevne tekst mod samme svar. Push/pull og projektets egne noter beskriver, at denne editorlæsning kan være stale efter programmatisk opdatering. Et stale svar kan derfor blive spejlet og registreret som korrekt uden kontrol mod den aktuelle Source. Hele response kan også ramme transportgrænsen på de store filer.

**Handling:** genbrug chunk-læsning af direkte Source med længde/fingerprint-verifikation. Bevar newline-kontrakten. **Port:** fake Studio, der giver gammel editorbuffer men ny Source, plus >200 KB source og Unicode. Værktøjet skal læse og verificere den aktuelle Source eller afvise; aldrig registrere editorbufferen som native sandhed.

### T04 — Pull-audit overser ReplicatedFirst
**P1 · R · verificeret kode/inventar.** `tools/pull_source_from_studio.py:56`, `tools/sync_from_studio.py:506`.

SERVICES udelader ReplicatedFirst. Lobby Loading Screen er et aktivt script dér. `mirrored_candidates` udelader også servicen. En fremtidig ændring eller en ny fil i loading-flowet kan undgå disse værktøjers opdagelse.

**Handling:** anvend én services-definition, der inkluderer ReplicatedFirst og de relevante native scriptcontainere. **Port:** en fake ReplicatedFirst-loader opdages som drift/new/orphan; normal round-loading fungerer stadig.

### T05 — Full sync kan kassere queued repo-arbejde uden konfliktkontrol
**P1 · R · konkret næste-session-scenario.** `tools/sync_from_studio.py:547`, `tools/sync_from_studio.py:593`; sammenlign `tools/pull_source_from_studio.py:200`.

Full sync bevarer newlineflags, men har ikke pull-værktøjets beskyttelse af pending-studio-push/studio-push-conflict. Hvis oprydningssessionen først køer en repoændring og derefter kører full sync, bliver den gamle Studio-version skrevet over den queued fil, og den nye manifestpost mister pending-baseline.

**Handling:** afvis/skip pending/conflict i full sync, indtil brugeren eksplicit vælger at kassere dem. Studio forbliver source of truth for release. **Port:** fake pending fil forbliver byte-identisk og pending efter sync, eller hele sync nægter før første write.

### T06 — Generic installer fejler på almindelig Unicode
**P1 · R · reproduceret offline.** `tools/install_new_scripts.py:56` og `:62`.

`lua_update` bruger JSON-stringescaping som Luau-literal. JSONs `\\u00e9` er ikke gyldig Luau escaping. En source med “é” fejler parsing af installationskommandoen, før UpdateSourceAsync. ASCII-proben består; Unicode-proben fejler med malformed escape sequence. Se `installer-probe.json`.

**Handling:** genbrug eksisterende `push_repo_to_studio.luau_string` eller samme sikre encodingkontrakt. **Port:** accents, danske bogstaver, quotes, backslash, control chars og emoji lander byte-identisk. Ingen ny encodingframework er nødvendig.

### T07 — To tests muterer autoritative filer som en del af deres test
**P1 · R · verificeret kilde.** `tools/tests/test_level2_kit_layout.py:850`–881; `tools/tests/test_level2_kit_import.py:677`–685.

Layout-testen skriver et mutant direkte til MODULE og gendanner i finally. Import-testen skriver mutanter til et source/export-manifest. Ved proceskill eller samtidig sync kan mutanten blive læst/publiceret, og gendannelsen kan overskrive en anden sessions arbejde. Disse tests blev **ikke** kørt i auditten.

**Handling:** kør mutanter på tempkopier/in-memory source; behold mutationens uafhængige oracle. **Port:** dræb mutantprocessen og verificér, at originalkilden aldrig ændrede bytes; kør samtidig med read-only sync-audit.

### T08 — De vigtige købs-/inventory-tests når ikke frem til deres assertions
**P1 · R · reproduceret offline.** `tools/tests/test_support_product_receipts.py`, `tools/tests/test_item_inventory.py`.

Support-receipts stopper ved “harness has no module ZyntraSkins”; inventory stopper ved require/nil.content. Det er fixturefejl, ikke dokumentation for fejl i receipt-grants. Den eksisterende suite dækker derfor ikke de lovede kritiske scenarier på nuværende kode.

**Handling:** opdatér module-fixtures til Studio-versionens afhængigheder og test de reelle receipt/idempotency-/inventory-scenarier. **Port:** tests skal nå grant/refund/duplicate assertions, og en tilsigtet dobbelt-grant-mutant skal fejle.

### T09 — Onboarding-testen tester en anden featureversion end Studio
**P2 · R · reproduceret offline.** `tools/tests/test_first_entry_guide.py:17`; T01.

Testen forventer den gamle guide i repoets inerte markør. Native er en stor aktiv welcome-klient. Fejlen “a brand-new profile gets the guide” beviser ikke, at den aktuelle Studio-welcome er forkert.

**Handling:** afstem kilden og omskriv testens forventninger til den aktuelle feature; bevar nye/gamle-profil-adfærd, input og modal ownership. **Port:** native onboarding med tastatur/touch/gamepad, chatfocus og respawn.

### T10 — Gamle branch-specifikke installercommands bør pensioneres eller gøres generiske
**P2/P3 · B.** `tools/apply_to_studio.cmd:28`, `:39`; `tools/install_trello_new_scripts.py`.

CMD-filen fetcher/checker ud på en fast gammel auditbranch før push. Den lille Trello-installer er en firefils kopi af den nu generiske installer. Ingen af dem er gameplay-runtime. Gamle genkørsler kan dog skifte arbejdsbranch eller fejle på dagens kilder.

**Handling:** vælg en aktuelt dokumenteret generic installation; arkivér daterede one-shot commands, eller gør branch eksplicit parameter. **Port:** dry-run fra en dirty checkout ændrer hverken branch, repo eller Studio. Ingen massedeletion af manuelle CLI-værktøjer ud fra manglende Python-import alene.

### T11 — Deprecated animationseksport er stadig publisherens default sti
**P2 · B/R.** `tools/export_entity_keyframes.py:1`; `tools/publish_entity_animations.py:29`–54.

Den gamle 120-linjers exporter er eksplicit deprecated, fordi den gav vendt armbevægelse. Publisher uden versionsflag kan stadig vælge gamle `keyframes`, mens nuværende runtime bruger v10 asset IDs. Den gamle publisher/exportpath er authoringhistorik, ikke aktiv animation runtime.

**Handling:** gør den aktuelle eksport/publishingrute eksplicit; arkivér gamle commands sammen med deres source/receipts. Behold uploadede animation IDs i gameplay. **Port:** v10-rebuild bruger retargeted source, og entity watch/walk/run/actions/kill spiller efter samme IDs.

### T12 — Hardcoded lokal connectorcredential ligger i tracked tools
**P1 · R · verificeret placering; aktuel gyldighed ukendt.** `tools/vault/build_vault.py:25`, `tools/vault/build_systems.py:7`.

Begge tracked filer indeholder en bearercredential som stringliteral til lokal Obsidian MCP. Værdien er ikke gengivet i rapporten. Test-relayens TOKEN er en testfixture og skal ikke blandes sammen med denne.

**Handling:** læs credential fra eksisterende lokal/env-konfiguration; rotér den hvis stadig aktiv. Ændr ikke vaultbyggernes outputkontrakt. **Port:** source indeholder ingen aktiv credential; connector virker fra lokal konfiguration. Sletning af scripts eller git-historik er en særskilt beslutning.

### T13 — Discord/Trello-bot kan skabe dubletter
**P1 · R · konkret race/crash-case.** `tools/discord_trello_bot/bot.py:99`–126.

Startup catchup og on_message kan håndtere samme starter samtidig. handle har ingen in-flight guard og POSTer en card før øjenreaktionen gemmes. Crash eller add_reaction-fejl efter POST giver en ny card ved næste catchup.

**Handling:** per-thread in-flight guard + verificér eksisterende card via threadlink før retry. Bevar feature. **Port:** samtidig startup/on_message og simuleret failure efter POST giver én card, med mulighed for at afslutte marking. Auditten har ikke sendt Discord/Trello-beskeder.

### T14 — Done-markeringen kan låse en halvfærdig botoperation
**P2 · R · konkret fejlcase.** `tools/discord_trello_bot/bot.py:144`–162.

announce_done skriver tick før reply og forumtag. Hvis reply/tag fejler, returnerer næste retry tidligt på tick, og resten fuldføres aldrig. caught_up sættes også før startup-scan er fuldført, så en delvis fejlet catchup genkøres ikke på reconnect.

**Handling:** udfør/efterprøv deltrin idempotent, og registrér completion/catchup efter succes. **Port:** failures ved reply/tag og midt i catchup bliver færdiggjort efter retry uden dobbelte beskeder.

### T15 — Store authoring-animationstræer er kandidater til at flyttes ud af release-stedet
**P2 · B · native objekter og runtime-referencer undersøgt.** `ServerStorage.RBX_ANIMSAVES` (**85.711** descendants), `ServerStorage.MongoTVEntityAnimations` (**223.366** descendants).

Der er ingen literal references til disse rødder i de aktuelle native kilder udenfor ServerStorage. EntityAnimation bruger publicerede asset IDs. Publisheren bruger dog MongoTVEntityAnimations som cache for authoring/publishing; det er derfor **ikke værdiløse data**. Descendanttal er ikke målt MB- eller FPS-besparelse.

**Handling:** eksportér verificeret authoring/sourcepack og kvitteringer, og vælg derefter om træerne skal ud af release-stedet. Bevar originalkilder udenfor release. **Port:** originalpack kan genindlæses; animationerne spiller i Roblox-client med samme IDs; publishing/reuse følger dokumenteret cacheprocedure. ServerStorage repliceres ikke til klienterne, så dette er især place/server/Studio-belastning. [Roblox ServerStorage](https://create.roblox.com/docs/reference/engine/classes/ServerStorage)

### T16 — Ældre kodebackups er inaktive, og flere er byte-identiske
**P2 · A/B.** Alle **42** kilder står i `backup-sources.json` med hash/linjer og native Enabled/RunContext i `studio-inventory.json`.

Fem Controller-backups i PoolSlideContextDiagnosticBackup_0710/MP6/MP7/MP8/MP9 er identiske. Fire Navigator-kopier deler en hash; MP8/MP9s anden Navigator-version deler også en hash. De ligger i ServerStorage og har ingen native eksterne folder-callers. Aktiveret Legacy Script i Project Mirror udføres ikke blot fordi Enabled=true under ServerStorage.

**Grænse:** identisk source-hash gælder kun scriptkilden. Hele backupfoldere kan have forskellige objekter, properties, attributes og revisionstilknytning; de må ikke deduplikeres ud fra source-hash alene. Eksportér og verificér den komplette rollbackpack først.

**Handling:** behold én verificeret off-place rollbackkopi pr. hash/revision; vælg derefter at fjerne daterede duplikater fra release-stedet. Field Notes/Slidemouth/ældgamle maprevisioner er historik og skal ikke “optimeres” som om deres loops kørte. **Port:** ingen runtime require/clone til folderen og rollbackpack verificeret. Nye A2-reflector-backups fra **2026-10-09** bør blive liggende indtil den aktuelle mapsession er godkendt.

### T17 — Gamle authoring-/diagnostikobjekter og legacy-mapdata kan arkiveres betinget
**P2 · B.** `studio-assets.json`, `storage-references.json`.

Native kandidater uden literal produktionsreferences: TEMP_PipeEntityAnimations superseded (**3.821** descendants), TEMP_PipeEntityAnimations (**4.642**), PoolSlideContactAnimations (**5.373**), Level2LegacyArchive_20261009 (**7.505**) samt daterede MP-resultatfoldere. Sidstnævnte kan bære attributes selv med 0 descendants; de er ikke automatisk tomme.

**Handling:** review hvert navn mod værktøjer og authoringbehov; eksportér før removal. Bevar Level2PoolroomsMap, Level1BlenderKitV2/elevator-kit, R4 lobby source og L6 bake/source afhængigheder. **Port:** aktuelt L2 entrytube/slide og L3 kitwarmup/visuals virker; old maprestore kan ske fra pack. Dynamisk templateopslag er en grund til at holde kandidaten betinget, selv uden literal fuldnavn.

### T18 — Root-junk og tomme filer kan ryddes op uden at rive testhistorik væk
**P3 · A/B.** `repo-summary.json`, `repo-inventory.csv`.

305 filer er tomme; mange untracked rootfiler hedder tal, enkelttegn eller tidligere shellfragmenter. AGENTS.md er 0 bytes og README begynder midt i en sætning og ender midt i en anden; tidligere projektnoter beskriver langt større indhold. Disse dokumenter er allerede ændrede før auditten.

**Handling:** læg en konkret allowlist for tomme stray-filer og gendan/skriv README fra verificeret nuværende Studio-arkitektur. Tom AGENTS skal afklares som tilsigtet vs. beskadiget. **Port:** ingen autoritativ manifest-/buildreference peger på et slettet navn. Bevar `_local`-paritybeviser og assets/source-packs; deres rollbackværdi er dokumenteret.

### T19 — Kodegrafen giver for mange historiske svar til dead-code-bevis
**P2 · R.** `graphify-out/graph.json`, `.graphifyignore`, `CLAUDE.md`.

Den eksisterende graphify-query har 22.867 nodes og returnerede primært gamle artifact-kilder. .graphifyignore ekskluderer Archive, men ikke de 2.109 daterede kodefiler. Projektets noter dokumenterer også Luau-parserens undercoverage i bl.a. GameManager.

**Handling:** generér et nyt runtime-scoped graph fra afstemt Studio-spejl; hold historik i en særskilt graf. Bekræft hvert unused-fund med fuld source/reference-søgning og native hierarki. **Port:** queries for GameManager/WorldBuilder leder til aktuelle filer, og manglende graph-edge bruges aldrig som eneste sletteevidens.

### T20 — Den aktive Arena-builder er ikke i repoet
**P2 · R · verificeret metadata/gap, runtime virker ikke nødvendigvis forkert.** `Workspace.Level 6 Indoor Playground` har `Source="tools/level6_playground/build_arena.py"`, Arena=true, Ready=true og NavGraph. Repoet har ikke den toolsmappe eller builderfil.

**Handling:** find og versionér den faktisk brugte authoringkode fra den ansvarlige session; bevar eksisterende Studio-map og public Playground Game. En model-Source attribute kan være gammel metadata, så ændr den først efter afklaring. **Port:** dokumenteret rebuild af Arena med samme exported collision/nav/objectivekontrakt i en kopi. Kilde i G:/Blender og scripts udenfor workspace er ikke semantisk auditeret her.

## Teststatus og begrænsninger

`test_studio_source_contract.py`: PASS. `test_full_sync_contract.py`: FAIL på to metadataforhold (T02).
15 valgte offline featurekontroller: **12 PASS, 3 FAIL** (T08/T09); logs og exitcodes er gemt. Passede bl.a. controllerinput, RoundHud shared, UIRegression shared, L4 queue/clear-persistence, token grants, reentry dismissal, speed potion, FriendBoost, spectate audio, purchase relay og route markers. De køres mod repo; for driftede filer er det ikke en fuld native integrationstest.

En kort Play-start nåede lobbyen på **11,8 sekunder**, med loading-loggens **68 assets / 0 failed**. Sound asset **134572728354839** gav “Asset is not approved for the requester”. Det er et permission/assetfund, ikke en opfordring til at slette audiofeature. Tidligere consolelinjer fra før vores Play indeholdt en L3 kit-not-ready assert; de beviser ikke et nyt selvudløst round-failure.

Studio skiftede mellem Edit og Play under efterfølgende læsninger uden stop/start fra auditten. Flere Server-/Edit-probes blev derfor afvist. Ingen state-/FPS-/multiplayer-/economy-/removal-test påstås bestået. Der blev ikke publiceret, foretaget køb eller skrevet liveprofiler. TeleportService kræver test i Roblox-applikationen; Studio alene kan ikke godkende reserved-server transitions. [Roblox TeleportService](https://create.roblox.com/docs/reference/engine/classes/TeleportService)

Store navtabeller, retired backupbodies og historiske snapshots er strukturelt/hash-/referencegennemgået, ikke fuldt semantisk revideret linje for linje. De aktive subsystemrapporter beskriver deres egen coverage. Dette er en fuld inventory og bred featureaudit med konkrete, verificerede fund; det er ikke et bevis for, at hver mulig gren i 223.000 linjer er fejlfri.

