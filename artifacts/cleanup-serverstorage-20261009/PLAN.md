# ServerStorage — afgrænset oprydning 2026-10-09

Studio Edit er igen godkendt af ejeren. Andre sessioners Play og edits bevares;
ingen modeswitch, publicering eller GitHub-push. Frisk baseline: HEAD 68e2d839,
70 ServerStorage-rødder, 220 native scripts/15 remotes, ingen editor-konflikter.
De ti gamle Codex-mirrors mangler allerede native; de installeres ikke igen.

## S01 — historiske diagnostikrecords (T15–T17 / ny N05)

Præcise targets under ServerStorage:

- TEMP_PipeEntityLobbyRigResult_0748Z
- TEMP_PipeEntityMPResult_0457Z
- TEMP_PipeEntityMPResult_0503Z
- TEMP_PipeEntityMPResult_0508Z
- TEMP_PipeEntityMPResult_0638Z
- TEMP_PipeEntityMPResult_0706Z
- TEMP_PipeEntityMPResult_1609Z
- TEMP_PipeEntityMPResult_1624Z
- TEMP_PipeEntityMPResult_1633Z
- TEMP_PipeEntityMPResult_1640Z
- TEMP_PipeEntityMPResult_1648Z
- TEMP_PipeEntityMultiplayerLaunch

Alle er Folder med nul children. De indeholder stadig Result-/Complete-/Bytes-/
Token-/tidsattributes, som skal bevares nøjagtigt off-place. 2.807 tracked tekstfiler
er genkontrolleret: ingen aktuelle callers, writers, remotes eller attribute-
consumers. Det senere LevelWorldStorage-modul traverserer nu rødderne, men
udvælger kun de tre præcise aktive mapnavne og læser ingen andre attributes.
Ingen af de12 resultatrecords matcher. Importerens
root-scan matcher kun egne __L2KMeshWire_/Installing_-prefixes; sync-, compiler-
og backupværktøjer inventerer data uden at forbruge resultatrecords.

Ændring: arkivér komplette native objekter og typed attributes; fjern kun disse
records fra native ServerStorage. Risiko: tab af historiske testbeviser, hvis
arkivet ikke kan genskabes. Gevinst: færre gamle testrecords i Explorer;
ingen FPS-/memorygevinst hævdes.

Port: før-archive med SerializationService, bytes/SHA, præcise facts og native
references; offline native reopen/typed facts/roundtrip; unparented native
Folder-rekonstruktion og oprydning; inbound-reference-scan; frisk objekt-/
property-/attribute-/source/editor-guard; reversibel Parent=nil-test med
rollback ved fejl; samme after-guards, originals intakte indtil porten består.
Start med MultiplayerLaunch og fortsæt i højst fire records pr. batch.
Gem receipts for hver batch. Ingen runtimefeature fjernes og ingen gameplay,
multiplayer, streaming eller performancepass udledes af denne arkivport.

Status ved v7: frisk Edit-capture73 roots/222 scripts og native rekonstruktion
bestået med2.472 checks,12 test-owned unparented kopier oprettet/fjernet og
609.670 property-reads uden kendte inbound refs/source-/rootdrift. Native
archive er stadig148.531 bytes med samme SHA. Frisk referencepack har13 roots/
577 objekter/105 serialized refs uden inbound og PlaceAvatarRules=null;
pack-SHA `74a893a614cc2ffb738e4a7ea4498101c23971074961af310583fe7390a0c821`.
Frisk efter-sidste-yield reference-CAS og samme-original reversibel port mangler.
Det var status ved v7. En anden Studio-session har siden taget alle12 originals
ud af ServerStorage. V8-proben afviste den ændrede Parent-baseline før oprettelse
af testkopier; denne oprydnings egen fjernelsesport blev aldrig kørt.
De23 eksternt fjernede træer er stadig intakte i de gemte sessionreferencer.
Se `external-storage-observation.json`; egen arkivering af dem er S06.

S01 anvender permanent `Parent=nil`, aldrig `Destroy`. Samme originale Folder
og alle data beholdes i en afgrænset, sessionlokal rollbackliste og i det
verificerede off-place nativearkiv. Place-træet udelader dem, mens eventuelle
opaque pointers beholder deres nøjagtige referent. Dette er en afgrænset
data-/authoring-oprydning, ikke et bevis for at alle beskyttede pointers er null.
Read-only peer-review accepterer denne port; ingen ny ejertilladelse kræves.
Beskyttede nonserialized editor-/engine-holders forbliver dokumenteret ulæselige.
Den valgte handling ødelægger ikke deres referent eller forbindelser.

Før enhver remove skal samme gruppe have bestået Parent=nil→ServerStorage
med de samme originaler. Porten fryser Source/editor/properties/attributes,
remotes, selection, præcise aktive mapidentiteter/parents, importerens eget
scratch-udvalg og foreign-root-inventory. Efter sidste yield genkontrolleres
verificeret joint referencehash, højst10.000 Folder-kompatible slots og child0
før no-yield write/after-guards. Ingen require, mapactivation eller importer køres.
Testrollback må ikke overskrive fremmed reparenting eller navnekollisioner.
Efter fravær/restoration skal kun den forventede root-/descendant-delta ses;
data/identitet/maps/scripts/remotes/scratch/selection er uændrede. Deferred
events kontrolleres efter sikker trial-restoration; mode-/foreign-edit-fejl
afviser gruppen og bevarer andre sessions arbejde. Consolekontrol registreres
uden at tilskrive andre sessions eksisterende fejl til denne batch.
Hvis en nødvendig port fejler eller
Studio går i Play, beholdes kandidaterne; andre uafhængige opgaver fortsætter.

## Beholdte closures

Aktive L1/L2/L3/L6- og lobbykits, Hazmat-skins, flume/tube-templates,
MongoTVEntityAnimations PublishedAssetId-cache beholdes. Ejeren har nu også
pensioneret TEMP-animationens PreviewControls-workflow; dets eksternt fjernede
træ bevares i S06-arkivet. Archive/Legacy/backup-revisions, RBX_ANIMSAVES og øvrige sourcekits
kræver komplette objekt- og authoringporte; identisk source eller navn er ikke
slettebevis. Project Mirror og den bare Column Flare Template er separate,
endnu ikke certificerede kandidater. Playerdata, receipt IDs, migrationsmarkører
og entitlements berøres ikke.

## S02 — downstream-mirrors af allerede fraværende native Codex-backups (T01/T16)

Præcise ti `studioPath`/filnavne findes i
`native-script-metadata.json:manifestOnlyPaths` og det scoped før-manifest i
`retired-repo-mirrors/manifest-before.json`. Det gælder kun mapperne
`ServerStorage/CodexBackup_20260902_ComingSoonGates` (én kilde) og
`ServerStorage/CodexBackup_20260902_FiveFixes` (ni kilder).

Ændring: flyt de nøjagtige gamle mirror-bytes og entries til et off-mirror
historikarkiv; fjern kun disse ti stale manifestentries/mirrorfiler. Frisk native
Edit læste alle scripts: begge folders og alle ti scripts er allerede fraværende.
De må ikke installeres igen. Dette er downstream-afstemning, ingen native
runtimefjernelse. Ingen aktuelle callers/importer reads; gamle README/CLAUDE-
noter beskriver historisk state og opdateres afgrænset. Risiko: tab af kildehistorik;
SHA- og restore-byte-port bevarer den. Gevinst: et spejl uden ti fiktive instanser.

Port: exact før-fil/manifest-checkpoint, native absens-bevis, hele caller-/tool-
closure, byte-identisk arkiv/reload og Luau compile af alle ti arkiver; frisk
manifestbaseline med scoped removal og ingen andre fieldændringer; resterende
mirrorhash/class/count/sourcekontrakt/compile; diff og ejerfiler bytebevares.
Studio Play bevares. Full Edit-parity tages, når Edit er tilgængelig; andre
sessioners nye maps/scripts/migrations tilskrives ikke denne batch.

Status: gennemført, lokal commit `52be2b82`. Alle10 arkivfiler er byteidentiske og compile20/20 bestået;
221 resterende mirrors har nul hash-/compile-/count-fejl. Source- og full-sync-
kontrakter bestået. Kun ti rows/filer fjernet; native er uændret.

## N05-værktøjsreview efter S02 (offline)

Frisk peer-review fandt lifecycle-/capturehuller før nogen native fjernelse.
Live capture/probe har nu eksklusiv sessionlease, owned tree-watchers, en fuld
catalog-/property-/attribute-guard samt guard efter HTTP-yields. Probe-baselinen
er lokalt scoped; gammel referencepack godkender ingen senere fjernelse.
`deletionApproved=false` er eksplicit; reference/CAS- og authoringporte er stadig
separate. Native syntaks består, men ændret wrapper er ikke en native removalpass.

Receiver-cleanup er uafhængig ved constructor/close-fejl. S02-wrapper pin'er
metadata før læsning/mutation, skriver manifest via ejet tempfile/atomisk replace
og bevarer samtidige reintroducerede filer ved rollback. Faktiske wrappers i
midlertidige fixtures:37 scenarier/1.104 checks og20 actual Luau compiles bestået.
Den oprindeligt gennemførte S02v1 og dens receipts er ikke kørt igen eller ændret.
En yderligere frisk capture afviste samtidige sourceændringer; endnu en blev
afvist, fordi en anden session igen havde startet Play. Ingen originals ændret.

## S07 — pensionerede lokale Lobby R1/R2/R3/R3B-authoringindgange (T16/T17)

Status: gennemført lokalt; native S04 afventer særskilte porte. Produktbeslutningen
er afklaret. Præcis allowlist, kun
under `tools/lobby_reimagined/`: `build.py`, `serve.py`, `install.py`,
`revision_install.py`, `revision_install_r3.py`, `revision_install_r3b.py`,
`source_module_manifest.json`, `source_module_manifest_r3.json`,
`runtime_bake.ModuleScript.luau`, `preview_builder.ModuleScript.luau`,
`preview_bootstrap.Script.luau`, `queue_controller.LocalScript.luau`,
`queue_bridge.ModuleScript.luau`, `compile_candidates.luau`,
`verify_import_helpers.py`, `verify_r3_geometry.py`, `verify_r3_native_scope.luau`.

Ændring: byte-identisk off-mirror arkiv af disse17 filer; pensionér deres lokale
CLI/import/export/QA-indgange og korrigér aktuel IMPORT-dokumentation. Historiske
receipts og modeller bevares. Den fulde gamle closure er serve→install→revision
generators/manifests/old runtimecandidates→QA; R3B læser R2-generatorens AST.
Native Source-closure bruger præcis R4, ingen af de fire gamle source-navne.
De17 filer har ingen aktive R4 imports. Remotes og attributes i deres gamle
candidates bevares i arkivet; aktuelle native scripts berøres ikke.

Bevar R4 `build_r4.py`, `serve_r4.py`, `install_r4.py`, `props.py`, `r4_bays.py`,
`r4_pbr_export.py`, `r4_materials.py`, shared `export_prefabs.py`, `verify_props.py`
og argumentstyret FBX-export/QA. Bevar old Level1-assets/shared helpers, som V2 og
elevator bruger. Risiko: skjult manuelt R4-import; gevinst:17 pensionerede
indgange/candidates væk fra aktive tools. Ingen runtime/performancegevinst hævdes.

Port før/efter: fuld tracked reference-/initializer-closure; bytearkiv/reload;
Python AST og alle arkiverede Luau-kilder O0/O1; faktisk R4 package-loader med
manifest/hash/mesh/PBR checks og samme generated installer bytes/gating; isoleret
Blender prop-library QA med gentaget-build-refusal og atlas/material-bevarelse.
Delte aktive kilder/output skal forblive identiske. Den eksisterende R4
`serve_r4 --verify-only` fejler allerede på historisk catalog sourceCount8 mod
værktøjets7; dette registreres som baselineblokering, og ingen installation køres.
Native fem-pakkers arkiv/fjernelse og aktive gameplayflows er separate S04-porte.
