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

Status: offline arkivport89 checks og referenceport39 checks bestået;
native rekonstruktion/fresh-after-yield reference-CAS/after-port afventer Edit.
Beskyttede nonserialized editor-/engine-holders er stadig ulæselige; deres
authoringbetydning er en eksplicit begrænsning, ikke bevist irrelevant.
Hvis en nødvendig port fejler eller
Studio går i Play, beholdes kandidaterne; andre uafhængige opgaver fortsætter.

## Beholdte closures

Aktive L1/L2/L3/L6- og lobbykits, Hazmat-skins, flume/tube-templates,
MongoTVEntityAnimations PublishedAssetId-cache og TEMP-animationens PreviewControls
beholdes. Archive/Legacy/backup-revisions, RBX_ANIMSAVES og gamle sourcekits
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
