# MongoTV oprydningsplan — 2026-10-09

Studio er source of truth. PlaceId **131311258779917**, universe **10559217407**.
Seneste opfølgning S17, 2026-10-10 07:41Z: **213 scripts,15 remotes,228 rows**.
20 samtidige native Source-ændringer og ét nyt script er eksporteret nedstrøms
efter friske Source/editor/identity/property/attribute/tag-læsninger. Den
oprindelige dirty RoundUI og de øvrige tidligere spejle er bevaret i privat
checkpoint. Tidligere inventarer og funddispositioner nedenfor er historiske;
nye ændringer skal genkontrolleres i den konkrete kommende dependency-closure.

| Ny batch / fund | Præcis kandidat og ændring | Bevis / dependency-closure | Risiko og gevinst | Før/efter-port | Status |
|---|---|---|---|---|---|
| S17 / T01,T02,T03 | 20 Source-afvigelser samt nyt `StarterPlayer/StarterPlayerScripts/Level 1 Entity Motion.LocalScript.lua`; præcis allowlist i [export-scope](artifacts/cleanup-20261010/resume-baseline-v1/export-scope.json);15 RemoteEvent-row-properties | Stabil native213/15 mod212/15 i repo; S13 brackets Source/editor/class/identity/props/attrs/tags. Ingen native writes. Alle tidligere berørte spejle/dirty RoundUI checkpoints; disk-/index-drift afvises. | Lav downstream-risiko; korrekt grundlag. Ingen feature/performanceændring tilskrives eksporten. | Source39/full-sync65 før/efter;21 Sources×O0/O1 compile; ny stabil213/15/228 parity med nul mismatch/conflicts/missing/extra/gaps, console identisk. | gennemført — lokal eksport og verificeret parity; commit registreres i efterfølgende rapport |
| S18 / C06 | Kun215-byte special-Userid-kommentar/branch med to nil→nil writes i `Level4PreviewPrompt.LocalScript.lua`;1622→1407 LFbytes. Alle aktive promptfiltre/callbacks beholdes. | Privat frisk PROMPTS-literal har alene to L4-keys, ingen metatable/udlevering/Level6-writers. Hele script/DevAccess/server-entry/authoring-closure genlæses. Ingen initializer/Instance/require/eventkald fjernes. [Scope](artifacts/cleanup-20261010/clients-next-v1/REVIEW.md). | Lav;215 færre Sourcebytes, ingen målt framegevinst. LocalPlayer/UserId-read bortfalder i normalt Legacy LocalScript-clientdomæne; ugyldige server/fake-player-domæner certificeres ikke. | Whole-source12 access/failure/initial/late/re-enable/detach/reparent cases455/version, to semantic mutants, authoring/lease-guards. Root fresh-ModuleScript native før/kandidat, scoped CAS/eksport og installeret port med213 originalguards. Native test-ejede prompts/signals; Players/access/service/late-delivery er kontrollerede boundaries, ikke gameplay/MP/streaming-certifikat. | afventer test — ingen runtimeændring endnu |

Oprydningssessionen udfører ingen publicering eller GitHub-push. En anden
session har særskilt registreret publicering v2924 i commit `9635a38c`;
dens optimeringsarbejde og publicering tilskrives ikke oprydningen.

Tidligere afgrænsede fremdrift, 2026-10-10: S07 er lokalt committed i `9b0c0468`.
S08 er lokalt committed i `9c6d713f`.
S08 har pensioneret Level1-legacyværktøjernes standalone-entry og offentlige
gamle targets i syv filer. Installeret replay bestod seks præcise V2/elevator-
outputs, syv negative legacy-porte og faktisk Blender V2/FBX-QA; alle 286
Level1-assetfiler og øvrige delte Python-helpers er bevaret. Fuld frisk V2-
triangulering varierer også ved uændrede før-kilder og er fortsat afventende.
Ingen af de fem native S04-pakker er fjernet af denne oprydning.
[S08 closure og porte](artifacts/cleanup-serverstorage-20261009/S08-level1-local/REVIEW.md).

S04's tredje friske native capture bestod: 1.617 objekter, 8.050.869 bytes,
SHA `e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7`.
Alle original-/Source-/editor-/property-/leaseguards bestod. Nul originalwrites
eller testkopier. Den separate native reopen bestod også: original/canonical
bytes er identiske og stabile, ti testkopier oprettet og fjernet, nul tilbage,
Source/editor og originale guards bestået. Aktive featureporte er stadig
afventende; pakken er bevaret.

S06 har komplet native arkiv af de 23 eksternt fjernede træer: 14.079 objekter,
12 scripts og 2.739.764 native bytes. Den separate native reopen-port genskabte
alle objekter/scripts og ti interne referencer, men to gamle modeltræers
properties afveg. Fuld gendannelse er derfor **afventende**, og alle 23
testkopier blev ryddet væk med originalerne uændrede. S06's separate lokale
12-mirror/manifest-oprydning er gennemført i `38f1d041` efter sin friske
før/efter-port; 944.770 Source-bytes er bevaret i off-mirror arkiv. Den ændrer
ingen runtimefeature eller native objekt.

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
det forbruger ingen af de12 records. Ved dette historiske snapshot afventede
slutparity tilgængelig Edit; senere frisk kontrol er registreret i slutafsnittet.

Frisk read-only observation21:54:29Z viste50 ServerStorage-rødder/212 scripts;
23 gamle rødder har Parent=nil, og12 tilhørende Source/editor-par er stadig
identiske med det tidligere arkiv. To nye scripts er samtidige ændringer.
[Observation og præcise navne](artifacts/cleanup-serverstorage-20261009/external-storage-observation.json).
S06 bevarer de23 komplette native træer og afstemmer kun allerede fraværende
downstream-mirrors efter arkiv-/compile-/caller-port. Ingen geninstallation.

S06's første lokale trial afviste scannerens 100.000-objektgrænse før writes.
Frisk census viste 416.276 objekter; scanneren har nu en konfigureret/testet cap på 500.000,
1.000-row checkpoints og 256 afgrænsede hash-buckets med præcis row/multiplicity.
Andet trial afviste samtidig native drift i den generelle `SoundController`;
tredje trial afviste `ServerScriptService.GameManager`. Alle tre stoppede før
filfjernelse eller manifestwrite. V4 afviste dernæst en ny dokumentations-HEAD
før checkpoint/MCP/writes. Kun HEAD-literal blev afstemt efter præcist review.
Den faktiske V4-port bestod siden: 212 mirrors verificeret mod live native
Source/editor/metadata før/efter, identisk fuld scene-strukturhash og 424
compiles. Præcis 12 filer/rows fjernet, counts 212/15/227; status **gennemført**,
lokal commit `38f1d041`. Arkiver og gamle held-originals er bevaret. Den
uafhængige 23-træers fulde restoration er fortsat afventende. S09 afstemmer kun den friske
Studio-kilde og dens manifestrow. Den anden sessions nyere
Level2 Sound-source/row bevares og udelades fra vores scoped commit; S05's
tidligere export er historisk og må ikke bruges som nutidig landing.

S03/S09 er lokalt committed i `c49e5de0`: to verificerede downstream Sources,
deres to præcise rows og grundtællinger afledt af de 237 rows. Den arvede
HEAD-tællefejl er rettet; øvrige rows og metadata er bevaret. Det er ingen
featureimplementering eller samlet parity-godkendelse. Native arkiver,
rollbackreceipts og testede guards er committed i `2231f23b` med præcis
allowlist; rå 41 MB facts bevares bytepræcist i gzip og lokalt, ikke duplikeret
i Git. S04-testens inaktive egne metadata er frigivet med ejerskabskontrol;
de 73 originale rootreferencer, 23 held-træer og 222 scriptreferencer er intakte.
De fem S04-pakker bevares, indtil aktive R4/V2/elevator-porte består.

**S10 / T16,T17 gennemført lokalt:** fjern præcis de 92 dublerede transport-
chunks i [allowlist](artifacts/cleanup-serverstorage-20261009/transport-parts-review-v1/candidate.json),
under diagnostic-archive-before-v7/v8, external-storage-archive-v1 og retired-
authoring-archive-v3. De komplette native/facts/referencefiler, receipts og
Source-arkiver er bevaret. Bevis: samtlige part-bytes matcher fuld fil, offset,
hash og transferreceipt; immutable completed capture-consumers læser fulde
filer. Ingen initializer, remote, attribute eller runtimecaller fjernes.
Risiko: miste en redundant transportrepræsentation; hver chunk kan genskabes
bytepræcist med eksklusiv write fra bevaret fuld fil. Gevinst: 92 lokale filer/
60.168.414 bytes fjernet. Før/isolated partless/efter faktisk fjernelse: samme
Lune folder/ref-consumers, S04 verify-constructor/context og S06 inputpreflight
bestod med identiske portrecords; hele beskyttede inventory og syv consumer-
kilder er bytebevarede. Første trial blev fuldt tilbagerullet efter en dobbelt
`.gitattributes`-oprettelse i testsetup; kun setup/versionmapper blev rettet.
Faktisk V2 efterport bestod. Fire S06 roundtrip-chunks beholdes som **afventer
test**, fordi deres fulde native restoration fejlede. Ingen runtime-/FPS-gevinst.
[Faktisk receipt](artifacts/cleanup-serverstorage-20261009/transport-parts-after-v2/removal-receipt.json).
Lokal commit `5a3a06e7` bevarer præcis tool-/før-/efter-/rollback-/parityevidens.

**S12 / T01,T02 gennemført lokalt:** `studio-sync-manifest.json` har fået
præcis 96 manglende native `Enabled`-aliases på Script/LocalScript-rækker.
Aktuelle native Source/editor/class/Disabled/RunContext og eksisterende
registrerede properties matcher; Enabled er Boolean og modsvarer Disabled.
De to allerede registrerede Enabled-værdier, alle Sourcebytes, øvrige rækker,
properties og counts bevares. Ingen runtimecaller, remote, attribute eller
authoring-entry fjernes. Risiko: registrere stale metadata; friske native
før-/efterlæsninger, HEAD-/filguards og afgrænset rollback beskytter batchen.
Gevinst: fuldstændig Enabled-registrering for de 98 aktive/inaktive BaseScripts.
23 faktiske wrapper-fixtures/2.191 checks bestod; native før/efter: 212 scripts,
15 remotes, nul Source/editor-konflikter/mismatches og coveragegaps 96→0.
212 lokale Sources er bytebevarede; ingen native/Source-/modewrites.
[Faktisk receipt](artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-v1/receipt.json).
Lokal scoped commit `e78cf597`; den samtidige sessions `9ca01fc0` bevares.
Generic full-syncs ældre metadata-tab er rettet særskilt som S13 nedenfor; ingen
bulk-sync er kørt. RoundUI's allerede ændrede Source-række bevares særskilt.

**S11 / B11,LE-34 gennemført for PuzzleManager:** fjern kun det private,
ulæste `latchMode = true` på sessioninitializerens linje 1373 (18 bytes).
`fuseSession` har kun privat bind/drop-brug; ingen hel-session-reflection,
dynamisk feltlæsning, export eller remotepayload bruger feltet. Box-/fuse-/
lever-handlers, TeamObjectives, cleanup, data og entitlements bevares.
Native før-/kandidat-/installeret port kører de samme faktiske initializer,
tre handlers, Announce og clearPuzzle ved kontrollerede enginegrænser:
47 checks pr. version, 94 ved reentry, identisk adfærd inklusive duplicate/
stale requests, Disconnect-/Destroy-fejl og cleanup/retry. Tre friske tomme
ModuleScripts er fjernet; alle 212 originaler og øvrige metadata er bevaret.
Dette er en privat felt-/kontraktport, ikke faktisk round, multiplayer,
streaming, respawn eller performance. Fresh native Source/editor/class/
properties/identity CAS og bounded før-/efter-export bestod; kun target og
dets sha/bytes-row ændret. Risiko: en overset feltcaller; hele closure og
semantisk negativ kontrol beskytter porten. Ingen målt performancegevinst.
Native/kilde er 105.502 bytes, SHA `40fce9298d29bfca01e20c0307591b545dfb125b2b66a9ab7e2d4092f6b85d8c`.
Lokal scoped commit `a7c7bac4`. Første installer-V1 blev afvist af JSON-parse
før nogen write; det historiske forsøg bevares. RoomDressing-delen af B11
er siden gennemført separat som S14 i `5ad5c03d`.
[Faktisk efterport](artifacts/cleanup-20261009/pending-locals-native-v1/latch-source-install-v2/result.json).

**S13 / T01,T02,T03 gennemført for eksportværktøjet:**
`tools/sync_from_studio.py:read_native_record/sync` læser nu friske native
segments, class-properties, attributes, tags og Source/editor-enighed rundt
om den eksisterende chunk-reader. Før genopbyggede full-sync minimale rows
og tabte metadata. Engine-/class-/place-/mode-/identity-/metadata-drift og
unsupported attribute-typer afvises før den berørte rækkes write. Tomme
attributes bevarer manifestets `[]`-konvention. MCP-client, shared Source-
reader, pushværktøj og initializer-workflows er bevaret. Risiko: forkert
metadata-eksport; faktiske reader/loop-fixtures og native getters dækker
kontrakten. Gevinst: fremtidige exports bevarer verificeret native metadata.
39 Source- og 65 full-sync-checks, 19 Python-scenarier/128 assertions og
30 faktisk genererede Luau-scenarier/103 assertions samt O0/O1 bestod.
Otte native getters for fire classes bestod før/efter med nul writes eller
objekter. Remote Archivable er sammenlignet med S12's native record, fordi
dens nuværende manifestrow mangler properties. Ingen faktisk full-sync er
kørt; eksporten er fortsat inkrementel og ingen atomisk hel-place-port.
Lokal commit `8fb44faf`; ingen runtime- eller performanceændring.
[Closure, historiske afvisninger og porte](artifacts/cleanup-serverstorage-20261009/S13-native-metadata-preparation-v1/REVIEW.md).

**S14 / B11,LE-34 — RoomDressing, gennemført i `5ad5c03d`:** præcis native
`ServerScriptService.Level 3 Systems.Level 3 Worn Party Room Dressing`,
mirror `ServerScriptService/Level 3 Systems/Level 3 Worn Party Room Dressing.ModuleScript.lua`,
linjer 61–62,89,252–255,404. Kun privat `safeRect`-parameter/konstantvej,
to literal-false argumenter og den før første læsning erstattede Vector3
fjernes. Aktiv VisualAdapter-caller, Place/carrier/mesh/collider/nav/prompt,
Level6-kit/bake/metadata, playerdata og remotes bevares. Source 18.304 bytes/
SHA `44249205…` bliver 18.179/`89fc2abe…` (125 bytes); ingen målt gevinst.
Historisk pensioneret Level3-installpayload og separat aktiv Level6-dressing
har andre kilder/workflows og bevares; de er ikke dubletter af dette target.
Risiko: ændret placering eller interaction; samme fulde aktuelle Plan/Apply-
kontrakt kører før/kandidat/installeret med seeded placements, servicevarianter,
beskyttet rum, manglende assets, prompts, busy/stale callbacks, task/connection-
cleanup og reentry. De to reproducerede eksisterende cleanup-fejl er uændrede;
retry er dér en no-op, ingen remediation-pass. Offline18 compiles/to semantiske
negative kontroller og ownership8/20 bestod. Faktisk native førport 00:19:14Z
bestod752 pr. version/1.504 paired/reentry; fire friske tomme moduler fjernet,
alle212 originaler bevaret. Før-source/editor/properties/objektidentitet gemmes
privat; fresh CAS, native export/manifestlanding, installeret replay, samme
212-source/metadata closure og console før/efter bestod ved actual CAS
00:22:27Z og installeret replay752/1504; fire testmoduler fjernet, nul tilbage.
De øvrige211 Sources/metadata er uændrede, console identisk; ingen rollback.
Ingen faktisk kit-/round-/multiplayer-/streaming-/performancegodkendelse.
[Closure og porte](artifacts/cleanup-20261009/remaining-private-locals-native-v1/REVIEW.md).

**S15 / B12,C26 — UIRegression-kommentarer, gennemført i `920abdee`:**
præcis `ReplicatedStorage.UIRegression` / `ReplicatedStorage/UIRegression.ModuleScript.lua`.
Ti reversible kommentarblokke på før-linjer23,1897,4087–4254,4772,6378 erstattes
med beskrivelser af de aktuelle shared-matrix-aliases og Levels1–4. 7.195 stale
kommentarbytes fjernes; alle197 executable funktioner/protos, constants, types,
upvalues, statements og public aliases/QA-workflows bevares. Risiko: misvisende
QA-dokumentation eller fejl i kommentargrænser; hele O0/O1 binary-kontrakten
bevarer samtlige bytes undtagen definitionernes linjemetadata, og faktiske
current UI authoring/error/borrow/restore/reentry-porte bestod105 før/105 efter.
Ti unique anchors plus forward/reverse/missing/duplicate/hash-negativer bestod.
Fresh native getter bekræfter ModuleScript-ID1_42698/parent1_408323, Source/editor
`b57a2b84…`, Archivable/LinkedSource og tomme attributes/tags; ingen writes.
Før-source/editor/metadata gemmes privat; native fresh CAS og bounded export til
313.535 bytes/`605da83a…`, scoped manifestlanding, samme installerede offline
kontrakt, 212-source/metadata parity og identisk console bestod ved actual
CAS00:33:56Z og afslutning00:34:24Z. De øvrige211 Sources/metadata er
uændrede; ingen rollback. Ingen native
runtimeprobe er nødvendig for en ren kommentarændring; ingen faktisk UI/device/
gameplay-/multiplayer-/streaming- eller performancegodkendelse følger heraf.
Loading-announced, RoundUI, remotes, data og øvrige runtime-local-kandidater
bevares. [Præcis closure og porte](artifacts/cleanup-20261009/c26-comments-native-v2/REVIEW.md).


**S16 / B14,LE-32 — Usher, gennemført i `dc1561d1`:**
`ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua`,
native ModuleScript `1_42775`, parent `1_15624`. Fem præcise substitutioner
fjerner alene de ulæste private nil/nul-værdier `targetReason`, `nextThinkAt`
og `stunUntil` samt deres overflødige simple writes: 34.745→34.659 bytes,
SHA `9af1a745…`→`ec425242…`, 86 bytes. Der fjernes ingen initializer-sideeffects.
Aktiv reason, ThinkSeconds/Heartbeat-akkumulator, stunCooldownUntil, beamers,
nav/capture/Start/Activate/Finale/Stop og offentlige testhooks bevares.

Hele konkrete closure, remotes/attributes/callers, authoringværktøjer og
testgrænser er registreret i [review](artifacts/cleanup-20261009/usher-private-locals-native-v1/REVIEW.md)
og [closure](artifacts/cleanup-20261009/usher-private-locals-native-v1/closure.json).
RoundGenerator/Objectives/LightDirector, Configuration/NoiseRegistry/
PlayerProtection/DeathAdvice, Usher Nav/klient/Test Suite og aktiv nav-/asset-
authoring bevares. Risikoen er lav for dette private scope; gevinsten er mindre
ulæst state, uden påstand om målt performance.

Før og efter skal den samme actual-source kontrakt bestå 68 checks pr. version,
136 parrede og 136 reentry; targeting/stun/state/attributes og faktisk Stop med
capture-boundary-/Disconnect-/Destroy-throw og retry afprøves. To aktive
reason/cooldown-mutants skal afvises. Native prober bruger fire friske tomme
ModuleScripts, destroyes uafhængigt, og skal efterlade nul prober samt frigivet
ejet lease. Alle 212 originalers Source/editor/identitet/metadata beskyttes.
Offline 16 installer-scenarier/109 checks, fem actual-anchor-scenarier/otte
checks, 18 probecompiles, 12 genererede CAS-compiles og otte leasecases/20
checks passerer med uafhængig review. Før actual PASS foretages ingen install.

Før-kilder, editor, properties og working/HEAD-manifest gemmes privat;
CAS rechecks den friske baseline inde i callback og kan kun reverse egen
eksakte kandidat. Derefter eksporteres kun verificeret native target-Source
og to Sourcefelter i manifest; installeret replay, særskilt frisk 212-parity
og console-diff er obligatoriske. Play bevares, hvis andre starter den.
Kontrollerede perception/nav/capture-grænser er ikke en rigtig gameplay-,
capture/jumpscare-, respawn-, multiplayer-, streaming- eller performanceport.
Faktisk native førport00:41:11Z, CAS00:41:37Z og installeret replay00:41:49Z
bestod68/136/136 med identisk behaviorhash. Hver probe fjernede alle fire
moduler og frigav ejet lease; 212-original guard bestod. Øvrige211 Sources/
metadata og console er identiske; ingen rollback. Afsluttet00:41:59Z.

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

**S03 / native-only mirror eksporteret og committed i `c49e5de0`:** den anden sessions aktive
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
Status: caller-closure, lokale authoringporte og native før-arkiv bestået;
native reopen bestået; afventer nødvendige featureporte. Ingen af de fem pakker er
endnu fjernet. Aktive fallbackcallers kræver særskilt bevaret/remedieret closure.

## Nye afgrænsede batches efter genkontrol

| Batch | Fund og præcis closure | Ændring og bevis | Risiko/gevinst | Før/efter-port | Status |
|---|---|---|---|---|---|
| B09 | N02: `artifacts/cleanup-20261009/capture_baseline.py`, metadata-read | Sideinddel native metadata i højst 40 records/60.000 bytes; den udvidede inventar-response blev afkortet af MCP. Ingen Source-writes. Kontrollér place/universe, sortering, fuld inventaridentitet og rå SHA før/efter chunks. | Lav; sikrere verificeret eksport uden ufuldstændigt snapshot. | 291 actual offline Luau checks, 11 negative fixtures, Python AST og frisk native post-B08 eksport med 230 scripts/15 remotes, nul drift/conflicts. | gennemført `e3af7ab2` |
| B10 | LE-32 `Light Director.isStar`; LE-34 `Worn Party Visual Adapter` lampShade-binding | Fjern kun privat uncalled closure og unread retur-binding; aktiv `STAR_TAGS`, `devicePart`-kald, shade, light, metadata og APIs bevares. Callers/dependencies/authoring closure i [review](artifacts/cleanup-20261009/local-helpers/REVIEW.md). Før-kilder/hash/property-rollback i candidate-manifest. | Lav; syv døde linjer/én closure og én binding; ingen målt performancegevinst. | Samme faktiske modul lifecycle/constructor/error/cleanup-graf før/efter: 173 assertions, otte O0/O1 compile-porte, to semantiske negative kontroller. Fresh native/editor/property/attribute CAS og manifestlanding; installeret replay PASS; 230 native hashes/editor uden drift. | gennemført `2ca92003` |
| B11 | LE-34 private Puzzle-session.latchMode og RoomDressing safeRect/breaker | Ulæst privat felt, to literal-false parameterveje og overskrevet immutable Vector3 fjernet; aktive constructors/Place/carrier/prompts/nav bevares. Closure og præcise blokke findes i S11/S14 ovenfor. | Lav; mindre privat restkode, ingen målt performancegevinst. | S11 native47/version94reentry; S14 native752/version1504paired/reentry; fresh CAS/export,212-source/metadata guard og installeret replay/console PASS. Historiske Play-afvisninger bevares. | gennemført — S11 `a7c7bac4`, S14 `5ad5c03d`; L2 authoringguides beholdes |
| B12 | C04/C06/C07/C26 historiske11 scopes/ti instanser | S15 fjerner alene7195 stale UIRegression-kommentarbytes; public aliases/QA-workflows bevares. Øvrige runtime-local-scopes beholdes indtil egne porte. Loading announced har aktiv caller; gammel samlet Loading-unit er ugyldig, C07 skal afgrænses på ny. RoundUI er ikke mål. | Lav for kommentarer; ingen målt gevinst. | S15:197O0/O1 funktioner executable-identiske, currentUI105/105, actual fresh CAS/export og212-parity/console PASS. Øvrige otte gyldige units afventer native full/Touch/lobby/loading-port; alle originale runtime-sources bevares. | gennemført — C26-kommentarer `920abdee`; øvrige scopes afventer test; historiske proposals `e55b2da0` |
| B13 | T09: `tools/tests/test_first_entry_guide.py` | Migrér den stale pathfinding/Beam-fixture til hele aktuelle WELCOME/HELP-source og faktisk ZyntraConfig. Aktuel guide har ikke UIStyle-dependency. Exact før-fixture checkpoint gemt; kun fake engine-grænser ændres. [Dependency/testreview](artifacts/cleanup-20261009/first-entry-guide-results.md). | Lav runtime-risiko; aktuelle assertions bliver tilgængelige. C21/C22 diagnosticeres separat og runtime bevares. | Baseline fejlede før assertions på manglende TweenService. Aktuel fixture: 133 assertions, seks uafhængige temporary source mutants afvist, AST/generated compile og input byte-guards. Native UX/input/streaming afventer egne porte. | gennemført offline `bce98752`; native UX afventer test |
| B14 | LE-32 Usher private targetReason/nextThinkAt/stunUntil | Kun fem unread nil/nul/simple-copy substitutioner86bytes; reason/cooldown/scheduler/events/capture bevares. Præcis Source/closure/attributes/remotes/authoring i S16-review. | Lav; ingen faktisk AI/performancepåstand. | S16 native før/kandidat/installeret68/version136paired136reentry med faktisk Stop throw/retry mod kontrollerede boundaries;2mutants,4prober destroyed,212-original guards, fresh CAS/export/console PASS. | gennemført — S16 `dc1561d1`; reel AI/gameplay/asset/performance-verifikation er særskilt |
| B15 | N03: `run_native_gate.py` N01 probe-allocation/staging/error-closure; AGENTS probe-rule | Staging/require omfattes af xpcall; uafhængig Destroy og final original identity/Source/editor guard kører også på fejl. Før-wrapperens staging leak er reproduceret. Alle inputs/objekter er test-owned; success-output uændret. [Review](artifacts/cleanup-20261009/native-gate-ownership-results.md). | Lav runtime-risiko, testværktøjs-lifecycle sikkerhed. Ingen current Play/Studio-kald. | 23 actual-generated offline Luau scenarier/275 assertions; staging/require/JSON/Destroy/original-drift, to ownership-mutants afvist, AST2/generated compile PASS. | gennemført offline `0608a9f8` |
| B16 | N04: `run_N01_pair_probe.py`, fem historiske pair/touch-inputs og proof-index | Arkivér eksakte inputs portabelt, pin raw/LF hashes og afvis ændrede inputs eller overskrivning af historiske receipts før MCP. `.git`-inputs og gamle resultater bevares. [Review](artifacts/cleanup-20261009/N01-pair-proof/README.md). | Lav runtime-risiko; verificerbare testinputs. Ingen native replay eller performancepåstand. |70 offline checks: fem inputhashes, fire receipt-sourcehashes, seks input/index-mutants og to outputkontroller; AST2 og20 proof/wrapper O0/O1 compiles. Touch-current mangler præcis native receipt og markeres input-only. | gennemført offline `f21bfdf4` |

Den historiske B11-installation blev afvist af MCP, fordi Studio var skiftet til Play. Ingen
native writes blev eksekveret; begge lokale candidates blev straks gendannet til
de præcise gemte før-bytes, og manifestet blev ikke ændret. Ejeren har bekræftet,
at Play-sessionen skal bevares indtil tilbagemelding. Denne pause er historisk; ejeren har siden godkendt Studio-arbejde uden at
stoppe andres Play. S11 Puzzle og den senere særskilte S14 Room-port er gennemført.

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
  Ved dette historiske checkpoint blev filerne bevaret ustaged. Den anden
  session har siden committed sine øvrige ændringer i `37f09c9c`; kun den
  oprindelige dirty RoundUI/Source-række står tilbage. Ingen cleanup-kredit.
  Historisk repo-only port under daværende ejer-Play:230/230 mirrorcompile,230/230 manifesthash/bytes og
  451/451 Python AST ved seneste verificerede snapshot;
  [receipt](artifacts/cleanup-20261009/owner-play-repo-checks-latest.json)
  har capturetid i JSON. Tidligere receipts bevares uændret. En yderligere
  Loading-/manifestændring blev afvist af stale checkpoint-guard, før artifacts
  blev skrevet; ny checkpoint og repo-port blev derefter taget. Samtidige
  senere edits kræver igen frisk kontrol.
  Ved dette historiske snapshot afventede native slutparity Edit. Senere
  afgrænsede batches og afsluttende frisk parity er registreret særskilt.
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

## Afsluttende verificeret snapshot — 2026-10-10

Frisk native Edit-read00:42:34–00:42:44Z efter S11/S14/S15/S16: **212 scripts,
15 remotes,227 faktiske/deklarerede rows,52 ServerStorage-rødder** og416.276
sceneobjekter. Source/editor/class/registrerede properties matcher working-
mirror og manifest; nul konflikter/missing/extra/Enabled-coveragegaps.
Catalog og lokale Sources/manifest er stabile gennem ti sider og slutread.
Root's særskilte API-mode før/efter er Edit og consolebytes identiske; ingen
modeændring eller nye native writes fra finalkontrollen. Dette er point-in-time
parity, ikke komplet assets/attributes/tags/gameplay eller en kontinuerlig lås.
Remote Archivable er læst, men den eksisterende manifestcoverage for feltet er
ufuldstændig. S14/S15/S16 har separat beskyttet alle212 Sourceattrs/tags.
[Actual parity](artifacts/cleanup-serverstorage-20261009/final-parity-v3/after-cleanup/result.json),
[mode/console](artifacts/cleanup-serverstorage-20261009/final-parity-v3/root-boundary-v1/proof.json).
Oprindelig dirty RoundUI og dens Sourcefelter i working-manifest er bevaret
og udeladt af vores scoped commits. Origin/main er fortsat `46073662`.

De godkendte gamle Lobby-/Level1-/TEMPPreview-workflows er pensioneret i de
angivne lokale delscopes. Fem native S04-pakker afventer faktisk R4/V2/elevator-
fejl/cleanup/respawn/reentry/asset/multiplayer/streaming-port;23-træers fulde
restoration fejlede2/23 og er fortsat afventende. Ingen manglende test omdøbes
til PASS, og ingen yderligere pensionsbeslutning efterspørges for disse scopes.

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
5. Aktive L2/L6-/fallback-/authoring-/policykontrakter og native backups
   beholdes under bevaringsmandatet. En eventuel fremtidig pensionering eller
   policyændring kræver særskilt produktvalg og egne porte; det er ikke en
   uafklaret forudsætning for de gennemførte batches.
6. Reserved-server continuation/reentry afhænger af rigtig Roblox-clienttest.
   Studio kan ikke godkende disse flows; de beholdes/afventer relevant test.
7. Skjulte collision/nav/hiding/promptdele og backupmapper vurderes som komplette
   objekter; ens source/navn/Disabled er ikke slettebevis.

Afslutningen skal registrere hver batch, rollback, måling, åbne testporte,
lokale commit-IDer og frisk repo/Studio-parity i `CLEANUP_RESULTS.md`.
