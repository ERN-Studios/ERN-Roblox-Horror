# MongoTV oprydningsplan — 2026-10-09

Studio er source of truth. PlaceId **131311258779917**, universe **10559217407**.
Denne opgave publicerer ikke det offentlige spil. Ingen GitHub-push er planlagt.

## Aktuel ServerStorage-batch efter ny tilladelse

Ejeren har igen godkendt Studio-arbejde og oplyst, at to andre sessions arbejder
samtidigt. Den tidligere pause nedenfor er historisk. Ingen anden sessions Play
stoppes. [Den præcise storage-plan](artifacts/cleanup-serverstorage-20261009/PLAN.md)
har aktuelle targets, closures, rollback og porte.

- **S02 / T01,T16 gennemført lokalt:** ti gamle Codex-spejlfiler, allerede fraværende
  i native, flyttet byte-identisk off-mirror (333.941 canonical bytes/9.134 linjer);
  kun deres manifestentries fjernet. Ingen native runtimefeature fjernet.
  20 arkiv-compiles, source/full-sync-kontrakter og221 resterende mirror-compiles/
  hashes bestod. Ejerens samtidige LevelWorldStorage-entry er bevaret;221 er
  231 aktuelle før-entries minus ti, ikke230 minus ti. Lokal commit `52be2b82`.
- **S01 / T17,N05 arkiveret; eksternt fjernet:**12 diagnostikrecord-Folders er komplet
  native-arkiveret, typed/Lune reload/canonical roundtrip og serialized inbound
  reference-scan bestået. En anden Studio-session har siden taget dem ud af
  ServerStorage sammen med11 andre gamle rødder. Oprydningen udførte ikke denne
  fjernelse. Frisk v7 Edit-capture og
  native unparented rekonstruktion bestod2.472 checks;12 testkopier er fjernet,
  originals intakte. V8-proben afviste den senere ændrede Parent-baseline før
  nogen testkopi eller originalændring. Vores Parent=nil→restore-port blev aldrig
  kørt og godkender ikke den eksterne fjernelse. De oprindelige træer er stadig
  intakte via de gemte sessionreferencer og arkiveres separat som S06.
  Permanent fjernelse bruger samme originals via Parent=nil med nativearkiv og
  sessionlokal rollback, så opaque pointers bevarer identitet. Ingen Destroy.
  Source-/mode-/referencekontroller bevarer andre sessioners samtidige arbejde.
  Aktive kits/caches/maps/authoring bevares.

Historisk v7-capture viste73 ServerStorage-rødder/222 scripts efter ejerens tre
parkede maps, nye LevelWorldStorage-modul og Level 2 Poolrooms Ambience-script.
Disse ændringer tilskrives ikke
oprydningen. Modulets generiske root-scan udvælger kun de tre præcise mapnavne;
det forbruger ingen af de12 records. Frisk afsluttende Edit-parity afventer
tilgængelig Edit og skal genlæses, fordi andre sessions fortsætter.

Frisk read-only observation21:54:29Z viste50 ServerStorage-rødder/212 scripts;
23 gamle rødder har Parent=nil, og12 tilhørende Source/editor-par er stadig
identiske med det tidligere arkiv. To nye scripts er samtidige ændringer.
[Observation og præcise navne](artifacts/cleanup-serverstorage-20261009/external-storage-observation.json).
S06 bevarer de23 komplette native træer og afstemmer kun allerede fraværende
downstream-mirrors efter arkiv-/compile-/caller-port. Ingen geninstallation.

**B17 / T12 gennemført lokalt:** `tools/vault/build_vault.py` og
`build_systems.py` har fået fjernet deres hardkodede credential. Den nye
`vault_auth.py:get_token` læser lazy ved faktisk `mcp()`-kald fra eksisterende
ignoreret pluginconfig eller eksplicit `MONGOTV_OBSIDIAN_MCP_TOKEN` override.
Configens bearer/port er verificeret uden værdiprint; config var byteidentisk
ved testporten og blev ikke skrevet af batchen. Et senere eksternt configskift
er bevaret; frisk peer-review bekræfter stadig samme bearer/port. Endpoint,
payload, IDs, retry, timeout, `fix_folders.py`-import/caller og configfri dry-run
er bevaret. To ignorerede lokale værktøjsnoter fik kun deres præcise sourcefence
opdateret; alle øvrige bytes/links/newlines er identiske. Før-kopier findes kun
privat under `.git`. Gevinst: ingen hardkodet credential i de aktuelle to
tracked builders eller deres to lokale noter; historik/config er bevaret.
Port:18 tests af faktiske moduler med fake HTTP og isoleret dry-branch bestået,
inklusive refresh, override, manglende/blank/defekt config, neutrale fejl før
Request/retry og afvisning af headerkontroltegn. Fem AST/compile-checks og
præcis AST-/note-/config-byteport ved den registrerede gate bestået. Lokal commit
`4c2aca10`. Ingen rigtig builder, regeneration,
Obsidian/network/MCP-kald, rotation eller Studioændring.
[Præcis closure og receipts](artifacts/cleanup-serverstorage-20261009/vault-auth/REVIEW.md).

**S03 / native-only mirror eksporteret; scoped commit afventer:** den anden sessions aktive
`StarterPlayer.StarterPlayerScripts.Level 2 Poolrooms Ambience` er LocalScript,
Enabled=true/Disabled=false/RunContext.Legacy og er nu i working mirror/manifest.
Frisk bounded Source/editor-read viste18.933 identiske bytes/SHA og nul attrs/tags.
Eksportér kun den verificerede kilde og dens nye manifestrow, med privat før-
checkpoint og friske CAS-/missing-file-guards. Bevar alle eksisterende dirty
actor-rows/topmetadata; scoped commit må kun tilføje den nye row til HEAD.
Port: frisk native/editor/props før/efter, compileO0/O1 og nøjagtig source/hash/
count/row-delta. Lav risiko ved downstream-export; paritygevinst uden native
ændring. Featuretilføjelsen krediteres ikke oprydningen.

**S07 / T16,T17 gennemført lokalt:**17 gamle lobby-authoringfiler er flyttet
byte-identisk til off-mirror arkiv (133.791 bytes). R4 package-validering,
isolated Blender prop-QA og faktisk ny R4-build bestod før/efter; alle meshes,
teksturer, placeringer, colliders og øvrige portrecords matcher. Kun den
verificerede private Blender-fils metadatahash varierer også i uændrede
gentagelser. 162 øvrige authoringfiler er bytebevarede. 48 actual compiles og
otte Python AST-checks bestod. Første strenge trial blev tilbagerullet med
alle17 originalbytes gendannet; årsag og gentaget baseline er dokumenteret.
Native fem-pakkers fjernelse er stadig S04, ikke godkendt af denne lokale port.
[Closure, rollback og endelige receipts](artifacts/cleanup-serverstorage-20261009/retired-lobby-authoring-v2/REVIEW.md).

**S04 / T16,T17 produktbeslutning afklaret af ejeren:** pensionér de manuelle
authoringworkflows for `ServerStorage.LobbyReimaginedBlenderSource20261001`,
`...R2`, `...R3`, `...R3B` og `ServerStorage.Level1BlenderKit`. Den aktuelle R4-
pakke, Level1BlenderKitV2 og alle aktive gameplayfeatures bevares.
Det er ikke i sig selv et slettebevis. Før ændringer kræves frisk fuld caller-/
dependency-closure, inklusive dynamiske native lookups, shared helpers og
authoring-/testværktøjer; præcise funktions-/fil-targets tilføjes efter review.
Port: komplette native objekt-/property-/attribute-/asset-/referencearkiver,
verificeret reopen/reconstruction, bytebevarede før-kilder, aktive R4/V2-
forbrugerchecks før/efter, guarded reversibel fjernelse i små grupper og præcis
repo/Studio/manifest-delta. Risiko: tab af kildeassets/shared dependencies;
gevinst: pensionerede revisioner og workflows ude af den aktive projektstruktur.
Status: afventer dependency- og arkiv-/authoringtest; ingen af de fem pakker er
endnu fjernet. Aktive fallbackcallers kræver særskilt bevaret/remedieret closure.

## Nye afgrænsede batches efter genkontrol

| Batch | Fund og præcis closure | Ændring og bevis | Risiko/gevinst | Før/efter-port | Status |
|---|---|---|---|---|---|
| B09 | N02: `artifacts/cleanup-20261009/capture_baseline.py`, metadata-read | Sideinddel native metadata i højst 40 records/60.000 bytes; den udvidede inventar-response blev afkortet af MCP. Ingen Source-writes. Kontrollér place/universe, sortering, fuld inventaridentitet og rå SHA før/efter chunks. | Lav; sikrere verificeret eksport uden ufuldstændigt snapshot. | 291 actual offline Luau checks, 11 negative fixtures, Python AST og frisk native post-B08 eksport med 230 scripts/15 remotes, nul drift/conflicts. | gennemført `e3af7ab2` |
| B10 | LE-32 `Light Director.isStar`; LE-34 `Worn Party Visual Adapter` lampShade-binding | Fjern kun privat uncalled closure og unread retur-binding; aktiv `STAR_TAGS`, `devicePart`-kald, shade, light, metadata og APIs bevares. Callers/dependencies/authoring closure i [review](artifacts/cleanup-20261009/local-helpers/REVIEW.md). Før-kilder/hash/property-rollback i candidate-manifest. | Lav; syv døde linjer/én closure og én binding; ingen målt performancegevinst. | Samme faktiske modul lifecycle/constructor/error/cleanup-graf før/efter: 173 assertions, otte O0/O1 compile-porte, to semantiske negative kontroller. Fresh native/editor/property/attribute CAS og manifestlanding; installeret replay PASS; 230 native hashes/editor uden drift. | gennemført `2ca92003` |
| B11 | LE-34 `Room Dressing.safeRect`, breaker-position; `PuzzleManager.session.latchMode` | To literal-false callers tillader konstant eksisterende inset. Breaker immutable Vector3 erstattes før læsning; brug endelig +2.15 direkte. Fjern kun unread boolean field. Aktive placements/carriers/nav/prompts/levers/data bevares. [Closure/rollback/testreview](artifacts/cleanup-20261009/additional-locals/REVIEW.md). | Lav; overflødige private beregninger/field; ingen native gameplay- eller performancepåstand. | Samme aktuelle RoomDressing Plan/Apply/interaction/error/reentry/cleanup 1.477 assertions; faktisk sessioninitializer og tre handlers 21 før/21 efter; otte O0/O1 compile-porte og tre negative kontroller. Afventer Edit/fresh CAS og installeret replay. | afventer test; originaler bevaret |
| B12 | C04/C06/C07/C26: historisk 11 private local/comment-scopes i ti script-instanser | Kun ulæste constants/functions/bindings, nil→nil assignments og dokumenteret stale QA-kommentarer. Constructors og public aliases beholdes. Præcise blokke, callbacks, flags, remotes, initializer/authoring-closure, risiko og rollback i [review](artifacts/cleanup-20261009/CLIENT_LOCALS_REVIEW.md) og [manifest](artifacts/cleanup-20261009/remaining-clients-proposals.json). RoundUI er ikke et ændringsmål. Den samlede Loading-unit er nu ugyldig; announced beholdes, C07 skal afgrænses på ny. | Lav ved scoped locals; historiske 8.736 kildebytes omfatter den tilbagetrukne Loading-unit på 173 bytes. Ingen målt runtimegevinst. | Parrede faktiske historiske sources: authoring287, HUD185/shared387+stamina74, exit/hiding92, UIRegression105, store777; relevante constructor/access/copy-mutants afvises. C26 O0/O1 executable binary identisk. Afventer Edit/fresh CAS, ny Loading-afgrænsning, installeret replay og native full/touch/loading-smoke. | afventer test; originaler bevaret; proposalbeviser committed `e55b2da0` |
| B13 | T09: `tools/tests/test_first_entry_guide.py` | Migrér den stale pathfinding/Beam-fixture til hele aktuelle WELCOME/HELP-source og faktisk ZyntraConfig. Aktuel guide har ikke UIStyle-dependency. Exact før-fixture checkpoint gemt; kun fake engine-grænser ændres. [Dependency/testreview](artifacts/cleanup-20261009/first-entry-guide-results.md). | Lav runtime-risiko; aktuelle assertions bliver tilgængelige. C21/C22 diagnosticeres separat og runtime bevares. | Baseline fejlede før assertions på manglende TweenService. Aktuel fixture: 133 assertions, seks uafhængige temporary source mutants afvist, AST/generated compile og input byte-guards. Native UX/input/streaming afventer egne porte. | gennemført offline `bce98752`; native UX afventer test |
| B14 | LE-32 `Level 4 Usher Controller`: targetReason, nextThinkAt, stunUntil private rester | Fjern kun unread declarations/assignments; faktisk reason/cooldown/scheduler/events/capture bevares. Før/kandidat/hash/closure og roller i [manifest](artifacts/cleanup-20261009/usher-locals/candidate-manifest.json). | Lav for locals; ingen faktisk AI/performancepåstand. | Faktiske chooseTarget/think/setBeamers/setState/Stop før/efter ved kontrollerede perception/navigation/capture-grænser: 59 assertions, fire O0/O1 compiles, to semantic negative controls. Afventer frisk native CAS og installeret replay. | afventer test; original bevaret |
| B15 | N03: `run_native_gate.py` N01 probe-allocation/staging/error-closure; AGENTS probe-rule | Staging/require omfattes af xpcall; uafhængig Destroy og final original identity/Source/editor guard kører også på fejl. Før-wrapperens staging leak er reproduceret. Alle inputs/objekter er test-owned; success-output uændret. [Review](artifacts/cleanup-20261009/native-gate-ownership-results.md). | Lav runtime-risiko, testværktøjs-lifecycle sikkerhed. Ingen current Play/Studio-kald. | 23 actual-generated offline Luau scenarier/275 assertions; staging/require/JSON/Destroy/original-drift, to ownership-mutants afvist, AST2/generated compile PASS. | gennemført offline `0608a9f8` |
| B16 | N04: `run_N01_pair_probe.py`, fem historiske pair/touch-inputs og proof-index | Arkivér eksakte inputs portabelt, pin raw/LF hashes og afvis ændrede inputs eller overskrivning af historiske receipts før MCP. `.git`-inputs og gamle resultater bevares. [Review](artifacts/cleanup-20261009/N01-pair-proof/README.md). | Lav runtime-risiko; verificerbare testinputs. Ingen native replay eller performancepåstand. |70 offline checks: fem inputhashes, fire receipt-sourcehashes, seks input/index-mutants og to outputkontroller; AST2 og20 proof/wrapper O0/O1 compiles. Touch-current mangler præcis native receipt og markeres input-only. | gennemført offline `f21bfdf4` |

B11-installation blev afvist af MCP, fordi Studio var skiftet til Play. Ingen
native writes blev eksekveret; begge lokale candidates blev straks gendannet til
de præcise gemte før-bytes, og manifestet blev ikke ændret. Ejeren har bekræftet,
at Play-sessionen skal bevares indtil tilbagemelding. B11 og yderligere
Studio-edits **afventer test/tilbagemelding**, mens lokale opgaver fortsætter.

Nyere concurrent Loading-source ændrer også B12's grundlag: `announced()` har
nu en aktiv caller i `levelWorlds()` og **beholdes**. Den historiske samlede
Loading-kandidat må ikke installeres. C07-bindinger kræver et nyt afgrænset
forslag mod frisk Studio-source efter ejerens Play. Beviser fra den ældre
baseline bevares som historiske receipts, ikke som aktuel fjernelsestilladelse.

## Baseline og samtidige ændringer

- Startcommit: `46073662`; `git fetch origin` bekræftede samme `origin/main`.
- Eksisterende dirty arbejde: `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`
  og `studio-sync-manifest.json`. Bytekopier og binær Git-diff bevares lokalt i
  `.git/mongotv-cleanup-20261009/preexisting/` og `preexisting.patch`.
- Nyere samtidigt arbejde under ejerens Play: BlenderRoomRenderer's Atomic-room
  streaming, Lobby DJ Client cache/round guards og Shop Display Client bounded
  retry/round guard samt Loading Screen og Round Entry Client's nye assetcensus,
  preload/retry/late-descendant-flow og deres manifestentries. Exact checkpoint
  af alle seks ejerændrede runtimefiler og manifestet i
  `.git/mongotv-cleanup-20261009/concurrent-20261009T200540091097Z/`.
  Filerne bevares ustaged, og rettelserne tilskrives ikke vores commits.
  Aktuel repo-only port:230/230 mirrorcompile,230/230 manifesthash/bytes og
  451/451 Python AST ved seneste verificerede snapshot;
  [receipt](artifacts/cleanup-20261009/owner-play-repo-checks-latest.json)
  har capturetid i JSON. Tidligere receipts bevares uændret. En yderligere
  Loading-/manifestændring blev afvist af stale checkpoint-guard, før artifacts
  blev skrevet; ny checkpoint og repo-port blev derefter taget. Samtidige
  senere edits kræver igen frisk kontrol.
  Native slutparity afventer ejerens tilbagemelding og frisk Edit-eksport.
- MCP valgte stedet efter navn **og** native PlaceId/GameId. Første inventar:
  230 scripts, alle native Source/editor-source ens; klasse, Enabled/Disabled,
  RunContext, attributes og manifest genkontrolleres i `baseline-parity.json`.
- Komplet spilbackup er allerede taget af ejeren. Ingen native objekter fjernes
  uden en særskilt komplet rollback for den konkrete closure.
- Auditbilag, der nu mangler lokalt, tæller ikke som aktuelle testbeviser.
- Offline klientbaseline: UIRegression 90; RoundHud 382; stamina 74; exit 92;
  controller 91; touch 86; POV 63 assertions bestod. De beviser fixturekontrakter,
  ikke alle gameplay-/multiplayer-/streamingflows.
- Source-kontrakt og full-sync-kontrakt består den friske offline baseline;
  T02 er allerede løst. Receipt/inventory/onboarding-fixtures fejler før deres
  relevante assertions og må repareres før de bruges som testport.
- Studio Play: én udviklerspiller, levende character, lobbyloading 12,9 s,
  68 assets, 0 preload-fejl. Eksisterende lydasset `134572728354839` afvises.
  RoundActive=false; level-/teleport-/økonomiflows er ikke godkendt af denne smoke.
- Første kildeeksport blev afbrudt af et for tidligt Play-skift og kasseret.
  Frisk Edit-eksport køres færdig inden kildeændringer.
- Frisk Edit-eksport er bestået: 230 scripts/15 remotes, 0 source-, hash-,
  klasse-, property- eller attributeafvigelser og 0 editor-konflikter.
  Luau compile 230/230 repo og 230/230 eksporterede native kilder bestod.
- Native `UIRegression.RunAllSummary`: 935 checks, 51 fejl i eksisterende
  HUD-layoutforventninger; harness lock clear. Det var før-baselinen. N01/B06
  og C05/B08 har siden bestået særskilte native før/isolering/efter-porte.
  Aktive round-scenarier, der blev skipped i lobbycontext, er fortsat unverified.

## Prioriterede batches

| Batch | Fund og præcis afgrænsning | Ændring / bevis | Dependencies og risiko | Testport før/efter | Status |
|---|---|---|---|---|---|
| B01a | T03/T04/T05: `tools/sync_from_studio.py`, `tools/pull_source_from_studio.py` | Native Source-læsning, ReplicatedFirst-dækning, fail-closed ved queued/conflicting lokale edits. Før-batchens full-sync læste editorbuffer og kunne overskrive pending arbejde; disse fejl er rettet. | Shared source contract, push/pull/full-sync og fake Studio; ingen live Studio-write. Lav runtime-risiko, stor mirror-sikkerhedsgevinst. | Offline integration med stale editor, stor Unicode-source, pending/conflict uden writes; eksisterende source/push/full-sync gates. | gennemført e019a427 |
| B01b | T06/T07/T08: generic installer, layout-mutantcheck og receipt/inventory fixtures | Korrekte Luau-literals, mutation i temp/in-memory kopi, aktuelle dependencies så økonomiassertions nås. | Præcise filer og fixtureclosures i repo-tools-recheck; receipt IDs/entitlements/økonomikode bevares. | Offline Unicode byte-roundtrip, mutant-afvisning uden original-write, eksisterende duplicate/failure fixtures og meningsfuld negativ kontrol. | delvist gennemført e019a427; gammel fuld layout-suite afventer test |
| B02 | C08: `StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua`, eneste `LEGACY IMAGE JUMPSCARE` kommentarblok | Fjern kommenteret gammel billedimplementation; ingen eksekverbar kode. | `Remotes.Jumpscare`, aktive camera/cancel/overlay-flows bevares fuldstændigt. Lav risiko, 14 døde linjer fjernes. | O0/O1 instruktioner+konstanter identiske; binær forskel kun dokumenterede linedefined-varints og proto-størrelser, line-padded trial binært identisk. Native fresh Source/editor compare-and-swap, compile og lobby-smoke. | gennemført 6eb13e22 |
| B03 | X05: `tools/level4_blender/README.md`; T18: `tools/level2_poolrooms/smoke_tmp.py` | Ret kontroltegn i verificeret rollbacksti; fjern kun nul-byte stray helper efter referencekontrol. | Rollbackobjekt på disk bekræftet; ingen initializer-sideeffects i tom fil. Lav risiko. | Sti findes og README uden kontroltegn; eksakt reference-/toolingcheck før/efter. | gennemført e019a427 |
| B04 | CORE-024: `ServerScriptService/LobbyReimaginedPreview/EndBlockades.ModuleScript.lua` Add/Emit placement-loop og sibling `Builder.ModuleScript.lua` | Skip kun furniture-clones, som samme build destruerer; public authoring Emit/PLAN bevares. | Colliders/lenses, tom folder, Ready/attrs og authoring-default skal bevares. Moderat risiko; mindre buildarbejde. | Isoleret before/after native build, fulde relevante objekt/propertykontrakter, authoring default, error/cleanup/rebuild samt samme-scenarie timing og frisk lobbyflow. | afventer test |

B02/C08 er **gennemført**: frisk Source/editor/property/attribute-guard inde i
UpdateSourceAsync-callback; native landing og manifest verificeret. Efter-smoke:
levende character, health100, LobbyLoadingDone=true, 68 assets/0 preload-fejl,
kun samme eksisterende lydafvisning. Kommentaroprydning fjerner 461 bytes og
14 linjer; den ændrer ingen aktive jumpscare-instruktioner eller konstanter.

B01a/T03–T06 og B01b/T08 er **gennemført** efter offline integration og
negative kontroller. T07's source-write er fjernet og interruption-porten
bestået; den komplette pensionerede layout-suite er fortsat **afventer test**
fordi dens aktuelle runtimeinputs ikke længere findes. B03/X05 og den ene
T18 nul-byte helper er **gennemført**; øvrige tomme QA-/packagefiler bevares.
Se [tooling-resultater](artifacts/cleanup-20261009/tooling-results.md).

## Supplerende testfund og batchporte

| ID / batch | Præcis kandidat og bevis | Dependencies / gevinst / risiko | Testport og status |
|---|---|---|---|
| N01 / B06 | `ReplicatedStorage/RoundHud.ModuleScript.lua` Chevron `TextScaled, TextWrapped = true, false`; native TextLabel-probe viser, at wrapped=false slår scaling fra. UIRegression shared anchor forventer kantplacering uden de allerede aktive 16/24 px margener. | RoundHud templates, Framewisp binding, UIDevice safe slots og shared UIRegression; små scoped rettelser, normal HUD skal bevares. | Native før-test 935/51; isolated propertyprobe; fake engine modellerer koblingen; eksisterende offline gates; native samme matrix/RunAll efter. **gennemført 11faa990**. |
| X02 / B05 | EditableMesh build/upload authoring-helpers og deres L1/L4 upload wrappers; exceptions forlader allocated meshes. | L1/L2 helper-extraction markers/signaturer og result/asset-ID-kontrakter bevares. Lav/moderat risiko; bounded resource cleanup uden målt MB-gevinst. | Actual offline Luau helpers med success/allocation/Add*/CreateAssetAsync error og nøjagtig Destroycount; alle importer-extraction paths. **gennemført 12947a34**. |
| LE-34 / B07 | To upræcise kommentarer: Level3 Layout Generator:26 (`2x4`→`2x5`) og Level1 PuzzleManager:1548 (one-box-per-player→ceil(n/2)). | Fulde aktive initializers, APIs, remotes og attributes bevares. Closure, caller- og authoringreferencer er gennemgået i [LE34 review](artifacts/cleanup-20261009/le34-comments/REVIEW.md). Meget lav risiko; retvisende kommentarer uden performancepåstand. | Begge fulde kilder O0/O1 rå bytecode identisk; fire runtimekonstant-mutants afvist. Fresh native Source/editor/class/properties/attrs-CAS og landing/manifest. **gennemført 0efce872**. |
| C05 / B08 | `ReplicatedStorage/UIRegression.ModuleScript.lua`: 13 private, ubrugte definitioner (3 functions og 10 constants/tables), præcise blokke i [C05 proof](artifacts/cleanup-20261009/C05-prepared.json). | Hele den fjernede referenceclosure er intern; initializers er literals/concat/immutable Vector2, uden Instance/require/event/attribute/remotes. Alle øvrige statements, 102 Fit/UIRegression-deklarationer og 30 eksporterede APIs bevares; ingen toolingreferencer. Lav risiko; 73 linjer/2.823 bytes mindre QA-kode. | Native actual før full/touch, isoleret ny ModuleScript-kandidat med samme full/touch, API key/type/arity, nil-aware borrowed-state restore og source/editor guards; exact native CAS og frisk Play efter. Offline failure/restore/anchor/reset-kontrakt105 PASS. **gennemført 1dd48870**. |

CORE-004 er nu **reproduceret i fake store**: commit efterfulgt af tabt svar
kan debitere et item uden anerkendt effekt, og en ny retry kan debitere igen.
Økonomikoden beholdes, indtil operation-ID/refund/disconnect-porten er opfyldt.

CORE-024's første isolerede stagingforsøg fejlede og ændrede uventet original
EndBlockades-source. Den præcise før-kilde er CAS-gendannet og hele native
spejlets 230 hashes/editor-kilder genverificeret uden drift. Ingen publication.
Batchen er **afventer test**. Nye isolerede scriptprobes bruger `Instance.new`
og tjekker originalerne på både success og failure; den præcise årsag til den
observerede klonadfærd er ikke bevist.

B05/X02 er **gennemført** for den konkrete authoring-resource-closure: begge
uploadhelpers samt L1/L4 wrappers. 93 faktiske offline Luau-scenarier, 1.775
assertions, 12 generationchecks, 5 afviste negative cleanupmutanter og 8/8
compilede payloads. Ingen uploads er udført. Bred historisk L2-importtest
afventer pensionerede inputs; X03 upload-resume/dataregistrering er uændret.

B06/N01 er installeret med præcis native CAS og 230/230 hash/editor-parity.
Den berørte native shared-HUD-matrix består 730 checks med 0 fejl (før 50).
Den første efterport havde to scenariefejl; parrede QA før/current og friske
slutporte gav full0 og særskilt TouchTarget261/0 med tomme borrowed-state drift-
lister. De historiske fejl beholdes i receipts. B06 er gennemført `11faa990`.
C05/B08 bestod derefter både isoleret og installeret frisk Play full0/touch261/0;
fulde reports og alle30 public API rows er identiske med før. B08 er gennemført
`1dd48870`; ingen public QA-lane blev pensioneret.

N01's supplerende TouchTarget-port reproducerede en eksisterende fixturelækage:
det sidste party-down-scenarie skjuler næste devices objective. Original QA gav
261/9 fejl; den korrigerede margin gav 261/8. En isoleret kandidat genbruger kun
`resetScenario(true)` før hver devices objective-staging og gav 261/0, med
uændrede assertions, fri lock og originale Source/editor bevaret. Det er en
ejet QA-reset, ingen runtimegameplayændring. Frisk native installation og
samme full/touch-efterporte er bestået; [N01-resultater](artifacts/cleanup-20261009/N01-results.md)
og [C05-resultater](artifacts/cleanup-20261009/C05-results.md) registrerer grænserne.

Batches gennemføres sekventielt med før-kilder, frisk baseline, scoped diff,
defineret testport og egen commit. En manglende nødvendig test medfører, at
runtimekandidaten bliver stående. En regression medfører rollback af batchen.

## Alle 129 hypoteser

Den aktuelle kandidatoversigt er opdelt i følgende **genkontroller**, som er del
af denne plan. Hver fundpost indeholder præcis lokation, handling, aktuelt bevis,
callers/dependencies/remotes/attributes/tooling, risiko/gevinst og før/efter-test.

- [T01–T20 og X01–X05](artifacts/cleanup-20261009/repo-tools-recheck.md).
- [C01–C31](artifacts/cleanup-20261009/clients-recheck.md).
- [LE-01–LE-36 og CORE-001–CORE-037](artifacts/cleanup-20261009/levels-core-recheck.md).

Statusord: **klar**, **kræver afklaring**, **afventer test**, **gennemført**, **beholdes**.
Allerede løste auditfund markeres gennemført med attribution til før-sessionens
arbejde, ikke som ny implementation. Delvist løste poster opdeles eksplicit.

## Bevaringsgrænser og åbne beslutninger

1. Grundlag/testfejl prioriteres før runtimefjernelser.
2. Kommentarer, tomme strayfiler og afgrænsede helpers kræver reference-,
   sideeffect-, compile-/authoringchecks. Ubrugte returbindings tillader ikke
   fjernelse af synlige buildkald.
3. Lifecycle/performancearbejde kræver konkret før-/efterflow og samme-scenarie
   måling; ingen FPS-/MB-gevinst udledes alene af kildekode.
4. L2 flume/tube-closure; L3's Level6 bake/metadata; EndBlockades colliders/lenses;
   receipt IDs, playerdata, migrations og entitlements er eksplicit KEEP.
5. Pensionering af L2/L6-pakker, fallback/authoringflows og flytning af native
   backups er samlet til ejerafklaring. Intet svar er pensioneringstilladelse.
6. Reserved-server continuation/reentry afhænger af rigtig Roblox-clienttest.
   Studio kan ikke godkende disse flows; de beholdes/afventer relevant test.
7. Skjulte collision/nav/hiding/promptdele og backupmapper vurderes som komplette
   objekter; ens source/navn/Disabled er ikke slettebevis.

Afslutningen skal registrere hver batch, rollback, måling, åbne testporte,
lokale commit-IDer og frisk repo/Studio-parity i `CLEANUP_RESULTS.md`.
