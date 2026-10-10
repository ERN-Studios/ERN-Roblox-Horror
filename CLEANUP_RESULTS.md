# MongoTV oprydningsresultater — 2026-10-09

Studio er source of truth: place **131311258779917**, universe **10559217407**.
De gennemførte, testede batches er lokalt committed. Denne oprydningssession
har ikke publiceret eller pushet til GitHub. En anden session publicerede det
aktuelle sted som v2924 efter sit optimeringsarbejde; det er særskilt arbejde,
registreret i commit `9635a38c` og [ejerens receipt](tools/optimization_20261009/publication-receipt.json).
Ejeren har igen godkendt Studio-arbejde; to andre sessions
arbejder samtidig og skifter selv mellem Edit og Play. Deres sessioner bevares.
Historisk afsluttende Edit-parity00:42:34–00:42:44Z viste212 scripts,15 remotes og
52 ServerStorage-rødder; Source/editor/class/registrerede properties matcher
working-mirror og manifest med nul mismatch. Scopegrænser er angivet nedenfor.
Ny opfølgning S17 efter ejerens fortsæt-instruktion:213 scripts,15 remotes og
228 rows matcher Source/editor/class/registrerede properties i arbejdskopien
og manifestet ved07:41:08–07:41:18Z;52 ServerStorage-rødder.20 nye samtidige
Source-ændringer og ét nyt native script blev eksporteret nedstrøms; deres
gameplayimplementering tilskrives de andre udviklere. Tidligere dirty RoundUI
er bevaret byte-exact i privat checkpoint før den nye Studio-version blev
spejlet. Ingen native writes. Hele scopes og testgrænser er registreret nedenfor.
S18 har siden fjernet den private C06 no-op-blok, og S20 den private C04 Exit-konstant. Øvrige
afventende runtimeforslag står stadig uimplementeret; eksternt implementerede
ændringer beskrives særskilt uden oprydningskredit.

Alle **129** oprindelige fund var genkontrolleret og disponeret ved den foregående
afslutning. De nye samtidige Sources betyder, at berørte hypoteser skal
genbekræftes i hver kommende batch; gamle fixes gentages ikke. Grundlaget står i
[CLEANUP_PLAN.md](CLEANUP_PLAN.md) og de tre delrapporter:
[repo/tools](artifacts/cleanup-20261009/repo-tools-recheck.md),
[klienter](artifacts/cleanup-20261009/clients-recheck.md) og
[levels/core](artifacts/cleanup-20261009/levels-core-recheck.md).
De er hypoteser; eksisterende rettelser er ikke implementeret igen. Afgrænsede
dele af blandede fund har deres egen status og testport.

## Aktuel ServerStorage-oprydning

### S17 — frisk Studio→repo-baseline, gennemført

Før: stabilt native213/15/228 mod repo212/15/227,20 Source-afvigelser og nyt
`Level 1 Entity Motion`. Ingen Source/editor-konflikter. Dirty/diverged lokale
filer, alle20 eksisterende berørte spejle og manifest har recoverable privat
checkpoint; den nye fils fraværsbaseline er registreret. Frisk S13 getter læste
36 rows:21 Sources inklusive ny LocalScript
og15 remotes med manglende Archivable-metadata. Source/editor/instance/parent/
class/properties/attrs/tags blev kontrolleret omkring hver chunklæsning og
igen før landing. Alle øvrige spejle er byte-uændrede; historiske manifest-
operationstællere er bevaret. Eksporten implementerer ikke andres gameplayfixes.

Efter:42O0/O1 compile-porte for21 Sources PASS; source39/full-sync65-kontrakter
PASS før/efter. Faktisk ny komplet native hash/property-parity PASS213/15/228
med nul mismatch,missing,extra,Source/editor-conflict eller Enabled/Disabled/
RunContext-gaps. Catalog SHA25791b08093d08bb5048a6110744a90f2340848a2b2272d4179915687d225049
var stabilt før/capture/landing/efter. Console er identisk med eksisterende
fejl; ingen clean-console-,gameplay-,MP-,streaming-,asset- eller performancepass.

Et lokalt importpreflight havde forkert root-parent og fejlede før MCP-
initialisering eller Source/manifestwrites. Afvist toolcopy og årsag er bevaret;
rettet eksport bestod. [Capture/landing/tests/parity](artifacts/cleanup-20261010/resume-baseline-v1/export-result.json).
Ingen native Source-/objekt-/property-/modewrites, publicering eller GitHub-push.

S17 lokal commit: `fee5023fd5ce1e14e8c2205b7c8c008bc59ebc71`.

### S18 / C06 — privat Level4PreviewPrompt no-op, gennemført

Kun den215-byte gamle special-UserId-branch/kommentar og to nil→nil writes
er fjernet:1622→1407 LFbytes. Den private plain PROMPTS-literal har alene
to Level4-keys; der er ingen metatable, observers eller Level6-writers.
Alle øvrige bytes, DevAccess-require/fail-closed, aktive filtre, callbacks,
events, remotes og adgangspolitik er bevaret. Hele aktuelle script-, server-
entry-, DevAccess- og relevante authoring-closure er genkontrolleret.

Root-native før og installeret:455 checks/version,910 paired og910 reentry,
samme behavior hash, to aktive semantic mutants afvist. Fire friske
ModuleScripts skabt og fjernet pr. port; nul tilbage, lease frigivet og alle
213 originalers Source/editor/class/identity/properties/attrs/tags uændrede
under proberne. Faktiske test-ejede ProximityPrompts og Enabled/DescendantAdded
signaler er brugt; Players/DevAccess/delivery er kontrollerede boundaries.
Dette er no-op-kontraktbevis, ikke live gameplay, respawn, MP eller streaming.

Frisk native CAS kontrollerede213 originals før og inde i SES-callback;
kun præcis target Source blev skrevet. Native Source er eksporteret med
64-line/8k bounded chunks, metadata med20-row/20k pages. Manifestets eneste
ændring er target sha256/bytes. Alle øvrige212 Sources og manifestfields
blev genkontrolleret efter installeret port. Console før/efter er identisk
med eksisterende fejl; ingen rollback eller ny regression i native batch.
Uafhængig peer genkørte34 wrappercases/260 checks,15 actual Luau guardcases/
75 checks samt forward/inverse-anchor og receipt-integration. En fundet
post-replace rollbackfejl og den faktiske receipt-integration blev rettet
før native execution; timeout giver pending uden samtidig retry/rollback.

Source39/full-sync65 efter-kontrakter PASS. Separat faktisk parity ved
08:04:44–08:04:55Z:213 scripts,15 remotes,228 rows,52 ServerStorage-rødder,
nul mismatch/missing/extra/Source-editor-conflict eller propertycoveragegap.
Den separate parity dækker ikke attrs/tags eller fulde non-script assets;
S18's egne213-originalguards dækker scriptattrs/tags. Ingen målt performance-
gevinst, publicering, GitHub-push eller modeswitch.

Root havde præoprettet parity-readerens egen .gitattributes. Første lokale
opstart afviste derfor FileExistsError før MCP-initialisering; afvist forsøg
er bevaret. Ny destination bruger identisk frozen reader og bestod.
[Installation/rollback-receipt](artifacts/cleanup-20261010/clients-next-v1/preview-source-install-v1/result.json),
[native installeret port](artifacts/cleanup-20261010/clients-next-v1/preview-source-install-v1/native-installed-result.json),
[uafhængig peer](artifacts/cleanup-20261010/clients-next-v1/cas-v1/peer-review-v1.json),
[separat parity](artifacts/cleanup-20261010/clients-next-v1/final-parity-v2/result.json).

S18 lokal commit: `936dfd65ce6a1c988798f1d6c27ae571cd621e04`.

### S19 / T16,T17 — native recovery-opskrift fejlet; kandidater beholdes

Den rå S06 native genåbning er stadig FAIL for to af23 historiske træer.
Ny offline analyse fandt headeren og282 af283 native chunks byte-identiske.
Den eneste afvigelse var en Bone.CFrame-PROP-chunk med seks ændrede uncompressed bytes.
Lune-dekodning af14079 objekter/151983 properties lokaliserede fire historiske
R21-forskelle. Alle12 wanted-komponenter pr. Bone er bevaret fra de immutable
før-facts; ingen epsilon, normalisering eller ændring af arkivet blev godkendt.
Lune-constructor-port fejlede21/48 komponenter; rigtig readonly Studio ctor
bestod111 checks/48 komponenter, men dette er ingen setter-/recovery-pass.

Frosset V4 blev afprøvet i det korrekte Studio Edit uden modeswitch.
08:17:41Z baseline PASS2292 checks,213 Source/editor/identity/metadata-pins,
52 ServerStorage-rødder og416284 live descendants. 08:18:37Z actual native
V4 FAIL efter den første copy-only setter. Den kombinerede assertion var
`copy.CFrame == wanted AND after12 == spec12`; de to predicates og after-tal
blev ikke registreret hver for sig. Derfor er konkrete setter-deltas eller
normalisering som årsag ikke fastslået. De historiske DS-deltas er ikke dette
forsøgs after-setter-måling. Fire setters, anden reopening og native transfer
blev ikke gennemført; receiverens `recipePassed=false` er bevaret uændret.

Alle23 skabte/adopterede testkopier blev fjernet,0 tilbage, egen lease frigivet.
Afsluttende guards: original native archive uændret, alle213 friske scriptpins
uændrede;0 originale Source-/Parent-/modewrites. Ingen autoritativ regression
observeret; ingen original rollback nødvendig. Eksisterende console-output var
identisk før/efter. Root stoppede alene sin egen localhost-receiver efter den
færdige negative port; dens interrupt-exit1 var ikke testens fejlårsag.
Uafhængig peer fulgte hele actual-response/SHA-kæden med92 read-only checks.
Frosne V3/v4, faktiske preflight/fault-fejl og den negative native port bevares.
Ingen native retry, tolerance eller udvidet setterliste er implementeret.

Ny separat actual parity08:31:50–08:32:00Z PASS213 scripts/15 remotes/228 rows,
52 ServerStorage-rødder,416284 sceneobjekter; nul mismatch/missing/extra/
Source-editor-conflict/propertycoveragegap. Scope: source og registrerede
properties; attrs/tags/non-script assets sammenlignes ikke af paritylæseren.
S19’s egne scriptguards dækker attrs/tags. Sceneantallet var416284 allerede
før S19; den samtidige to-objektsændring fra416286 tilskrives ikke oprydningen.
Der er ingen målt gameplay-/performancegevinst, publicering eller GitHub-push.

Bevar held-originaler og fulde før-arkiver. S04’s fem native authoringpakker
beholdes også, indtil deres særskilte R4/V2/elevator/queue/gameplay/MP/streaming-
porte kan gennemføres. De23 allerede eksternt fjernede træer er fortsat
eksternt arbejde, ikke en fjernelse udført eller godkendt af denne batch.
[Frosset opskrift](artifacts/cleanup-20261010/storage-restoration-v1/REVIEW.md),
[actual native FAIL](artifacts/cleanup-20261010/storage-restoration-v1/native-v4-run-v1/port-verdict.json),
[uafhængig fejlreview](artifacts/cleanup-20261010/storage-restoration-v1/NATIVE_FAILURE_REVIEW.md),
[afsluttende parity](artifacts/cleanup-20261010/storage-restoration-v1/final-parity-v1/result.json).

S20/C04’s73-byte private tal-literal og den generiske authoringinstaller er
fortsat kun forberedte kandidater; ingen af deres produktionsændringer eller
native Sourcewrites er udført ved S19-afslutningen. Installerens offline
fejlfixture er ikke en native authoring-/transportcertificering.

S19 lokal commit: `51d3095afb3e6f62bb73c7fd0a8c6b491a205d82`.

### S23 / T01–T03 — tre samtidige Studio-Sources eksporteret

Lokal commit: `3d8e44df2e0fd1cb8be6c39faccf231281367d75`; ingen push/publicering.

GameManager, Level2PoolroomsPresentation og NoiseReporter er hentet friskt fra
native Source med editor-equality og eksakte identity/class/Enabled/Disabled/
RunContext/attributes/tags. NoiseReporter var ændret igen siden S21-afvisningen;
den seneste observerede kilde er bevaret. Private checkpoints gemmer alle tre
gamle raw mirrors, manifest og de eksisterende dirty plan/resultfiler.

Kun tre Sourcespejle og deres Source-bookkeeping i manifest er skrevet lokalt.
Ingen native Source/object/propertywrites eller mode-switch. Andre210 Sources,
alle øvrige manifestrows/felter og tidligere historiske operationcounts er
bevarede. Andre udvikleres ændringer krediteres ikke som oprydning.

V2/V3 blev aldrig anvendt: peer fandt en foreign-manifest rollback-afhængighed
og en manglende read-error/late-validation failure-receipt. De er bevaret og
rettet i V4 før faktisk eksport. [Peer](artifacts/cleanup-20261010/clients-export-peer-v1/REVIEW.json)
er statisk review; [actual export](artifacts/cleanup-20261010/concurrent-export-v2/export-result.json)
bestod separat. Ingen rollback blev nødvendig. Recovery er afgrænset CAS med
bevarelse/afventende frisk afstemning ved foreign/unreadable dependent files;
der hævdes ingen kontinuerlig cross-process-transaktion.

Tre kilder × O0/O1 compile PASS; Source39 og full-sync65 PASS.
Ny komplet native parity09:35:46–09:35:57Z:213 scripts,15 remotes,228 rows,
52 ServerStorage-rødder og417078 sceneobjekter; nul Source/editor conflicts,
mismatch, missing/extra mirrors eller property coveragegaps.
Catalog SHA `e0ec39a63fe5ecb9285245480d38523a7de00f900c88146ba9fc288522969630`.
Sceneantallet er ændret af samtidige Studio-edits og tilskrives ikke eksporten.
Ny readonly storage-census09:37:12Z har samme catalog og52 rødder.
Attributes/tags er præcist kontrolleret på tre targets; final census er Source/
editor/class/identity/registrerede properties, ikke fuld asset/reference-parity.
Dette er ingen gameplay-, MP-, streaming-, teleport- eller performancepass.

### S21 / C04 — faktisk førkontrol afvist, Hiding uændret

Det faktiske native førinventar fandt tre samtidige Sources, som afveg fra
repo/manifest. Installerens mirror-guard afviste forsøget FØR native parser
eller Source-CAS. Nul native Sourcewrites blev anmodet; target Hiding er
uændret. Dette er en baselineafvisning, ikke en runtime-regression.
[Read-only diagnose](artifacts/cleanup-20261010/clients-hiding-v1/baseline-refusal-v1.json)
og det fejlede forsøg beholdes. Den41-byte literal-kandidat står stadig afventende,
og gammel immutable installer-destination genbruges ikke. Ny closure/native/
installeret port kræves efter S23; ServerStorage/CORE-027 prioriteres nu.

### S25 / T11,T15 — fire gamle animationentrypoints pensioneret

Lokal commit: `b2c16a6d4352d1333a9b94973fb84b5975856f79`; ingen push/publicering.

Ejeren har pensioneret de gamle Studio-animationworkflows. Fire lokale værktøjer
afviser nu CLI/export/publish før Studio-, Blender- eller uploadoperationer.
`publish_code`, publisherens `main`, retargeted `studio_rest` og `main` afviser
også programmatisk brug. De to gamle bpy-exporteres import-initializer er
pensioneret; syv pure helpers i de to sikkert importérbare moduler er uændrede.
README beskriver den nye status. [Eksakte før-kilder og scope](artifacts/cleanup-20261010/animation-workflow-retirement-v1/proposal-v1/proposal.json)
er arkiveret, og private checkpoints bevarer de fire værktøjer og tre dokumenter.

Root genafspillede førporten og derefter porten mod de faktisk installerede
entrypoints:32 entrycases inklusive16 CLI-processer,13 helper-scenarier pr.
version og otte actual generated-Lua cached-ID-fixtures plus én missing-ID-negativ
PASS. Ingen upload, netværks- eller native writes under portene. Alle21 aktuelle
keyframe-/receipt-/builderfiler og runtime-ID-kilden er byte-identiske.
[Faktisk promotion](artifacts/cleanup-20261010/animation-workflow-retirement-v1/root-promotion-result-v1.json)
skrev kun fire lokale værktøjer; [installeret port](artifacts/cleanup-20261010/animation-workflow-retirement-v1/root-installed-port-v1.json)
bestod. Ingen rollback blev nødvendig. Den tidligere fixturefejl er bevaret.

Frisk native læsning10:04:32Z bekræftede Source/editor-equality og class/properties/
attributes/tags på seks aktuelle animationsconsumers. Alle otte gameplay-ID’er
bevares. `MongoTVEntityAnimations` har223367 objekter/117 topchildren;
`RBX_ANIMSAVES` har85712/27. Begge originalrødder og al native uploadcache
bevares. Den første readonly rapport fejlede ved JSON-encoding af en hashværdi;
separat V2 bruger eksplicit hashhex og bestod. Begge receipts bevares; ingen
native write eller mode-switch blev anmodet. En lokal receipt-skrivningsfejl
(`ReferenceError` før første filoperation) blev rettet uden productionwrites.

Portene bruger kontrollerede servicegrænser og dokumenterede cachefixtures;
de certificerer ikke alle aktuelle native versions/PublishedAssetId/AnimationId/
references eller playback. Fuld native archive/reopen, reference- og fraværsport
for de309079 animationobjekter afventer. Ingen FPS-, CPU- eller memorygevinst er
målt. Permanent native sletning er ikke gennemført af denne batch.

Den seneste fulde readonly før-parity09:56:06–09:56:16Z bestod med213 scripts/
15 remotes/228rows,52 ServerStorage-rødder og417075 sceneobjekter. Catalog
`81115530329fefcca83091e74379f63983ca0aa4b1da0b43bc64e653956623dd`.
En anden actors UIDevice/manifestarbejde og lokale commit `28f9c59a` er bevaret.
Proxyens sessions-ID er ændret; den gamle shared cleanup-ledger var ikke længere
tilgængelig. Historiske held-original references kan derfor ikke certificeres i
den aktuelle kontekst, selv om de genlæste native root-ID’er er uændrede.

### S26 / S04 — faktisk native V1 afvist før mappernes fravær

Lokal commit: `90a2ad15cbe824252d524d92dd217d38cc1371aa`; ingen push/publicering.

Den frosne V1-kilde blev faktisk udført én gang i det korrekte Edit-sted.
API-completion er kendt afsluttet efter89.234s; tiden er ikke en performancegevinst.
Actual R4 `RuntimeBake.GetManifest` afviste Edit-domænets `RunService.IsClient`
som «Preview bake is server-only». Ingen selectorfase blev godkendt og ingen
af de fem originals fik en Parentwrite. Dette er en testdomæneafvisning, ingen
observeret gameplay-regression eller gennemført fraværstest.

To friske tomme probes blev staged og fjernet,0 tilbage. Alle213 originals’
Source/editor/metadata og det præcise8050869-byte fem-root nativearkiv bestod
efterkontrol; scoped recovery og final/post-cleanup guards PASS. Ingen pending
originals, cleanupfejl eller efterladte forbindelser; begge egne namespaces
frigivet. Console før/efter er identisk med de eksisterende sound- og readonly
JSON-encoding-fejl; der hævdes ingen ren console. [Faktisk receipt/review](artifacts/cleanup-20261010/storage-authoring-port-v1/native-run-v1/ROOT_REVIEW.json).

Reflektionsscannen nåede181108 Instance-valued slots og24 unreadable kinds.
Compatible protected serialized endpoints/editor-/physics-references er endnu
ikke frikendt; permanent sletning er fortsat afventende. Under V1-execution fandt
review en composed setter-hook-kant før `entry.invoked`, som den oprindelige
offlinefixture ikke dækkede. Actual V1 udførte ingen Parentsetter. Eksakt kilde,
peer og fejlresultat er urørt; [separat kvalifikation](artifacts/cleanup-20261010/clients-storage-authoring-peer-v1/V1_QUALIFICATION.json)
bevares, og ny V2/actual negative/peer kræves før en ny scoped prøve. Ingen retry
af V1, cancellation, rollback af foreign arbejde eller Play-mode-switch.

Separat efter-parity10:16:00–10:16:10Z PASS:213 scripts,15 remotes,228rows,
52 ServerStorage-rødder,417075 sceneobjekter og uændret catalog811155…;
nul Source/editor conflicts, mirror/manifestmismatch eller coveragegaps.
[Fuld readonly parity](artifacts/cleanup-20261010/storage-authoring-port-v1/after-failed-v1-parity/result.json).
Ingen native runtime- eller packageændring tilskrives S26.

### S27 / T11 — døde exporterbodies fjernet efter pensionering

`export_entity_keyframes.py` og `export_entity_animations.py` er reduceret fra
4812/3389 til501 bytes hver:7199 døde Sourcebytes fjernet. Begge imports/CLI var
allerede pensioneret før bpy-initializers; nye små stubs giver samme tydelige
retirementbesked. Eksakte originaler og S25-guarded før-kilder er fuldt arkiveret.
Ingen aktive import-/subprocess-/safe_name-callers blev fundet. Syv pure helpers
i publisher/sampler,21 keyframe/receipt/builderfiler og alle otte gameplay-ID’er
bevares byte-exact. [Faktisk two-file promotion](artifacts/cleanup-20261010/animation-workflow-stubs-v1/root-promotion-result-v1.json).

Root før og faktisk installeret:16 CLI-processer,4 imports,4 semantic mutants
og13 retained helperbehaviors PASS. Ingen native/network/upload/manifest/index
writes fra portene, ingen rollback nødvendig. [Installeret port](artifacts/cleanup-20261010/animation-workflow-stubs-v1/root-installed-port-v1.json).
Dette er sourceoprydning, ingen målt gameplay-/FPS-/memorygevinst.

### S28 / S04 — faktisk fem-package fravær/restoration PASS

Immutable V2 retter den konkrete composed setter-ejerskabsgrænse og registrerer
Edit-domænet særskilt. Uafhængige actual-source porte51/3018 og38/2070 samt
hele fem compileunits bestod før Root native invocation. Native V2 er faktisk
afsluttet og valideret: alle fem samme originaler var midlertidigt fraværende,
R4/V2/elevator-selector/data-port bestod før/fravær/restored med21 kontrollerede
missing/incomplete/client-domain-fejlveje.10 Parentwrites med fem detach- og fem
restore-readbacks bestod; ingen original Sourcewrite eller permanent sletning.

Exact8050869-byte originalarkiv og2870333-byte aktive selected native-data,
deres readable facts/identities og alle213 Source/editor/class/properties/attrs/
tags er uændrede. Scoped recovery, final og post-cleanup guards PASS. To probes
skabt/fjernet,0 tilbage,0 pending originals/cleanupfejl/forbindelser og frigivne
egne namespaces. [Faktisk native review](artifacts/cleanup-20261010/storage-authoring-port-v2/native-run-v1/ROOT_REVIEW.json).

Actual Edit var IsClient=true/IsServer=false. Hele helperbodies bruger en eksplicit
kontrolleret server-datafacade; dette er ingen actual-server gameplaytest. Ingen
Ensure/Build/Begin/download/upload eller player/multiplayer/streaming/teleport
er certificeret.115.141s tooltid og1.679462s no-yield-trial er portvarigheder,
ingen performancegevinst. De24 unreadable referencekinds er fortsat selvstændigt
afventende. `deletionApproved=false`, `referenceAbsenceCertified=false`; de fem
mapper står igen i ServerStorage. Permanent sletning følger først selvstændig
referenceport. V1 og dets safe0-Parentwrite negative resultat er urørt.

Separat faktisk readonly efter-parity10:28:56–10:29:09Z PASS:213 scripts,
15 remotes,228rows,52 ServerStorage-rødder og417075 sceneobjekter. Catalog
`81115530329fefcca83091e74379f63983ca0aa4b1da0b43bc64e653956623dd`
er uændret; nul Source/editor conflicts, mirror/manifest/class/propertymismatch
eller coveragegaps. [Efterport](artifacts/cleanup-20261010/storage-authoring-port-v2/after-parity-v1/result.json).
Denne separate parity er Source/registrerede properties, ikke fuld asset/reference/
gameplay-parity. S28's egne213 originalguards dækker attributes/tags under prøven.

### ServerStorage og lobby — bevarede kandidater

Ejeren har pensioneret hele den gamle lobby som fallback: «Den kan altid bygges,
der skal ikke være et fallback.» Ved serverboot kalder GameManager stadig
TunnelLobbyBuilder før R4; samme-server return/reset genbruger lobbyen, mens en
ny lobbyserver bygger den igen. Builderen har fortsat aktive shop/support/spawn/
stationkontrakter; hele Build slettes derfor ikke blindt. Udskillelse og faktisk
regressionsport er afventende. Eksisterende shop-test fejler allerede før
cleanup fordi den forventer8texturekeys, mens aktuel kilde har10; dette negative
baselinefund skal bevares, og en aktuel featureport etableres først.

Fem gamle authoringpakker er fortsat beholdt. Arkiv/reopen og faktisk kontrolleret
absence/restoration/asset-selectorport er bestået i S28. Permanent fjernelse
afventer fortsat compatible protected Instance-references. Kun en komplet frisk
data-only closure kan afgrænse bredere gameplaykrav; de kontrollerede datafacader
certificerer ikke gameplay/MP/stream/teleport.

### S20 / C04 — privat Exit-konstant, gennemført

Kun den73-LFbyte ubrugte `HINT_HEIGHT = 36`-deklaration er fjernet fra
`Round Exit Client`:17956→17883 Sourcebytes. Hele closure er frisk kontrolleret;
ingen initializer, GUI-constructor, callbacks, remotes, attributes eller
leave-protokol fjernes. O1 whole-bytecode med37 funktioner og padded rawbinary
er identiske; O0 forskelle er registreret. Raw repo18399CRLF→17883LFbytes:
516 rawbytes inkluderer line endings og er ikke516 bytes fjernet kode.

Før og installeret: controlled whole-source Exit50/50 plus reentry50/50,
missing-import cleanup, to semantic mutants og hele aktuelle B6/B7 neighbor92/92
PASS. Native parser før09:03:26Z/installeret09:03:45Z: to friske tomme Modules
pr. port skabt og fjernet,0 tilbage, egen lease frigivet, ingen clientbody kørt.
213 originalers Source/editor/identity/class/properties/attrs/tags guards PASS.
Frisk Source-CAS09:03:28Z skrev kun target; efterfølgende bounded eksport og
manifest ændrede alene target sha256/bytes. Øvrige212 Sources og fields bevares.
Console før/efter eksakt identisk med eksisterende fejl; ingen rollback nødvendig.

Unexecuted V1 havde en reel mutating-transportgrænse: timeout kunne forveksles
med completed fejl og starte recovery mod et stadig kørende native kald.
Frosset V2 løser dette for apply/rollback/compile; unknown stopper senere native
kald og lokal recovery. Completed rollback-fejl kræver frisk exact before-export
og originalguards før lokal restore. Peer replay54cases/500checks,15guardcases/
75checks,31parserfaultcases/317checks samt helper/14compile PASS. Oversized
completed svar arkiveres ikke fuldt; deres error/checkpoint/known-state bevares.
Ingen V1 native write eller faktisk timeout-race blev udført.

Root after Source39/full-sync65 og installeret O0/O1 compile PASS. Separat actual
parity09:04:43–09:04:53Z:213 scripts/15 remotes/228rows,52 ServerStorage-rødder,
416286 sceneobjekter, nul mismatch/missing/extra/Source-editor-conflict/property-
coveragegap. Sceneændringen siden S19's416284 tilskrives ikke denne Source-batch.
Finalreader dækker Source/recordedproperties; egne213 guards dækkede scriptattrs/
tags. Ingen gameplay/hardware/respawn/MP/streaming/teleport/asset- eller målt
performancepass, native packagefjernelse, publicering eller GitHub-push.
[Actual installation](artifacts/cleanup-20261010/clients-exit-v1/exit-literal-install-v2/result.json),
[peer](artifacts/cleanup-20261010/storage-exit-peer-v1/V2_REVIEW.json),
[native provenance](artifacts/cleanup-20261010/clients-exit-v1/native-response-provenance-v1/root-provenance.json),
[parity](artifacts/cleanup-20261010/clients-exit-v1/final-parity-v1/result.json).

S20 lokal commit: `7fa4d2e13d64bb10732d62d35d8b219e0cf55583`.

### F01 / T06-extension — authoringinstaller, forberedt og afventer native test

Det aktuelle generic installer-workflow er genkontrolleret; fem actual-main
baselinecases reproducerede metadata-loss ved exact-source registration og
manglende frisk callback-CAS ved overwrite. T06’s historiske Unicodebug var
allerede rettet og er ikke implementeret igen. De15 remotes’ metadata-gap er
allerede løst i S17, ikke en ny afventende oprydning.

V6 er alene et forberedt forslag. Produktionstool, native Source og manifest
er uændrede. Kandidaten bevarer hele CLI- og Unicodecontract, bruger fresh S13
native metadata og kontrollerer overwrite inde i SES-callback; ny creation
sker på præcist egne tomme objekter med cleanup og Enabled-gendannelse.
Manifestregistration bevarer ukendte/unrelated fields og afviser drift; egne
temporære filer kræver eksakt descriptoridentity og kendte komplette bytes.
Der er ingen påstand om cross-process lock eller native-plus-local transaction.

Unchanged Unicode20,43 actual-main cases,711 generated Luau create/CAS-cases
med2241 checks og O0/O1 samt15 real filesystem/atomic faults91checks PASS.
Concrete candidate fejl i ID-guard, Parent commit-then-error cleanup og fremmed
temp-file-ejerskab blev fanget lokalt; immutable tidligere versioner/negative
receipts bevares. Disse porte bruger fakes ved native/SES/reflection boundaries.
En yderligere peer-reproduktion viste en sammensat V5 ownership-fejl: Parent
committede, fremmed reentry detached objektet, og setter kastede før attached-
flagget. V5’s combined gate er FAIL og uændret. V6 registrerer setterforsøget
før kaldet og bevarer ukendte nil-Parent outcomes;138 actual-generated cases/
432 checks bestod sammen med de ovenstående V6-porte. Det certificerer ikke
native engine-fejlveje. Rigtige native class/editor/authoring-porte og den enkelte store99.637-byte
overwrite-request er afventende; reads er målt bounded64lines/8k, hvilket ikke
certificerer write-transporten. Ingen Source- eller assetfjernelse er godkendt.
[Frosset V6 scope](artifacts/cleanup-20261010/foundation-next-v1/installer-v6/REVIEW.md),
[arvet native portdesign, kræver V6-binding](artifacts/cleanup-20261010/foundation-next-v1/installer-v5/NATIVE_AUTHORING_PLAN.md),
[præcis beviscuration](artifacts/cleanup-20261010/foundation-next-v1/CURATION-v2.json).

F01-kandidat/beviser er lokalt committed i `2dc4fa409a26b686c9ee0c0798f120bf20f0dcca`; produktion/native uændrede.

S08 har nu pensioneret Level1-legacybuildens standalone `main` og de offentlige
gamle import-/QA-/publish-/exporttargets i syv lokale filer. Aktive defaults
vælger V2; elevatorens delte INSTALL-template og alle 12 delte build-definitioner
og initializers er bevaret. Det installerede replay bestod seks byte-identiske
V2/elevator-payloads, installers, exporter og native-verification-record, syv
legacy-afvisninger før assetwrites/netværk og faktisk Blender V2/FBX-QA.
Alle 286 Level1-assetfiler, gamle teksturinput og receipt IDs er bevaret.
Scope reducerer de syv lokale filer fra 75.572 til 71.720 raw bytes.
Lokal commit: `9c6d713f4925ba8718bde0810797c333ab91fcbd`.
Tre bredere genereringsforsøg fejlede på frisk V2 wire/triangulering; en gentaget
uændret før-kilde viste også forskellen. Ingen tolerance eller ID-normalisering
blev brugt til at godkende den port, som stadig afventer. Det blokerer stadig
native pakke-fjernelse og enhver påstand om fuld ny V2-build-equivalence.
[Præcise scopes, før-kilder og installerede porte](artifacts/cleanup-serverstorage-20261009/S08-level1-local/REVIEW.md).

S06's read-only full-object arkiv indeholder alle 23 træer, som en anden session
tog ud af ServerStorage: 14.079 objekter, 12 scripts og 2.739.764 native bytes,
SHA `139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca`.
Lossless gzip bevarer alle 41.912.358 facts-bytes i 3.017.503 Git-bytes; det er
arkivstørrelse, ingen runtimegevinst. Native deserialize/reopen genskabte alle
objekter/scripts og ti interne referencer, men `TEMP_PipeEntityValidation` og
`TrelloPoolSlideReleaseBackup_20260910` havde property/subtreeforskelle.
Fuld restoration er ikke godkendt. Alle 23 testkopier blev destrueret, mens
originalernes Source/editor og native arkivhash forblev uændrede. Det separate
source-only downstream-scope har nu fjernet kun de 12 allerede fraværende
mirrors/rows efter sin egen friske før/efter-port. Alle 944.770 originale Source-
bytes er bevaret i off-mirror arkiv. Ingen native fjernelse tilskrives denne
oprydning; fuld object-restoration er fortsat afventende.

S04's første native capture afviste en uafklaret baselineændring. Det andet
afviste en tom SerializeInstancesAsync-liste fra testværktøjet; alle originale
guards bestod, nul kopier/writes. Testværktøjets tomme capability-kald er rettet
og den positive fem-root-kodevej testet, uden at svække originale guards.
Tredje capture bestod med 1.617 objekter og 8.050.869 native bytes, SHA
`e808f055403bd331b76e0831955b192abc8b4a914865c3936aa9b2d23ed2a8d7`.
Source/editor, properties og samtlige originale guards bestod; nul writes/kopier.
Den efterfølgende native reopen bestod også: original/canonical native bytes
matcher præcist og er stabile. Ti testkopier oprettet/destrueret, nul tilbage;
alle guards samt receipt-/lease-ejerskab består. Alle fem pakker er stadig
bevaret, da de aktive featureporte skal bestå, før de må fjernes.

S06's historiske lokale trials afviste først en for lille scenegrænse, dernæst samtidig
native ændring i den generelle `SoundController` og til sidst `GameManager`.
Alle tre blev afvist før nogen
filfjernelse eller manifestwrite; de er dokumenterede afvisninger, ingen
runtime-regression. Den målte 416.276-objektscene scannes nu med afgrænset fuld
strukturhash. S09's export er downstream af den aktuelle Studio-kilde, ingen
featureimplementering. S05's ældre Level2 Sound-export er siden overtaget af
en nyere samtidig ændring; den bevares som historisk receipt, mens den anden
sessions aktuelle filer/rows bevares uden staging i vores commit.

S06 v4's første kald afviste den anden sessions nye dokumentations-HEAD før
checkpoint, MCP-kald eller writes. Efter review af de ni dokumentationsstier
blev kun den forventede HEAD-literal afstemt; ingen Source eller guard ændret.
Den faktiske efterfølgende port bestod 23:25:29–23:25:58Z: 212 live Sources og
15 remotes; identisk Source/editor/class/metadata- og scene-struktursignatur
før/efter; alle 212 mirrors verificeret i begge faser og 424 O0/O1 compiles.
Kun de 12 lokale filer/rows blev fjernet, grundcounts 212/15/227. Source-
arkiver og originale held-instansreferencer er bevaret. Lokal commit
`38f1d041`; staged HEAD-manifest fjerner præcis de 12 rows og bevarer alle andre
HEAD-rows. Working RoundUI og dens særskilte manifestrow er fortsat ustaged.
Dette er ingen runtimefeature-fjernelse eller fuld asset-/gameplaygodkendelse.
[Faktisk før/efter-receipt](artifacts/cleanup-serverstorage-20261009/retired-external-repo-mirrors/execution-v4/removal-receipt.json)
og [commit-scope](artifacts/cleanup-serverstorage-20261009/retired-external-repo-mirrors/execution-v4/scoped-commit-review.json).

S03/S09 downstream-eksporter er committed i
`c49e5de0df711ac339598b93fb22b9ad49232f53`: Ambience 18.933 bytes og General
Sound 68.062 bytes med identisk native Source/editor, class/properties og
friske chunk-/slutguards. Fire compiles pr. export bestod. Kun de to Sources/
rows og afledte grundtællinger er inkluderet; arvet HEAD-count var én for lav.
S03/S09-committens scoped manifest havde222 scripts,15 remotes og237 rows. Den blandede working-
manifest og alle andre samtidige filer er bevaret. Det godkender ingen ny
audiofeature, gameplaytest eller fuld repo/Studio-parity.
[Scope og counted manifest](artifacts/cleanup-serverstorage-20261009/S03-S09-scoped-commit-v1/scope-receipt.json).

Frisk før-kontrol 23:07:26–23:07:37Z viste Edit, 212 native scripts, 15 remotes,
52 ServerStorage-rødder og 416.276 sceneobjekter. Ingen Source/editor-konflikter,
ingen mismatch mod aktuelle working-kilder/classes/registrerede properties og
ingen ekstra native scripts. Native cataloghash var identisk gennem ti sider
og slutcheck; repo/manifest var stabile. Working-manifest har 224 scripts/239
rows, præcis som dets deklarerede counts. De eneste fraværende native scripts
er de 12 gamle mirrors. Den tidligere GameManager-drift er afstemt af den anden
session; denne diagnose foretog ingen export eller runtimewrite. 96 manifest-
rækker mangler Enabled-feltet; faktisk Enabled er læst, og de registrerede
Disabled/RunContext/øvrige properties matcher. Tags/attributes/full assets er
uden for denne diagnose. Det er en frisk før-observation, ingen efterport.
[Parity-diagnose](artifacts/cleanup-serverstorage-20261009/final-parity-v1/retry-v2/result.json).

Native arkiver og testværktøjer er committed i
`2231f23babbe07876ddb5a86e5b55862ba7933b7`: 141 præcise stier, ingen runtime-
eller manifestændring. Staged bytes matcher de frosne hashes; gzip udpakker til
det fulde oprindelige facts-arkiv. Den fremtidige reopen-helper beskytter alle
game-/ledgeroriginals og adopterer/rydder senere testkopier uafhængigt af en
tidligere fejl. 16 actual-code offline cases/4.235 assertions og fire compiles
bestod; den fejlede native reopen er ikke omklassificeret eller gentaget.
[Arkiv-/værktøjsscope](artifacts/cleanup-serverstorage-20261009/archive-evidence-commit/final-scope.json).

S04-testens egen inaktive shared metadata blev frigivet efter friske præcise
ejerskabs-/lease-/nul-watcher-kontroller. De fem originale pakkeidentiteter/
parents og hele gamle ledger med 73 rootreferencer, 23 held-træer og 222
scriptreferencer bestod før/efter. Ingen objekter blev destrueret eller native
Source/editor/mode ændret. Historiske Sourceguards blev ikke genbrugt som
nutidig parity-godkendelse.
[Metadatafrigivelse](artifacts/cleanup-serverstorage-20261009/owned-state-release-v1/result.json).

S07 har pensioneret17 lokale Lobby R1/R2/R3/R3B-authoringfiler og bevaret alle
133.791 originalbytes i off-mirror arkiv. 162 andre authoringfiler er identiske.
Faktisk R4 package-validering og ny isoleret Blender R4-build/prop-QA bestod
før/efter:90 payloads matcher byte/hash; fuld manifest matcher bortset fra
hashen af den genererede private Blender-fil. En uændret gentagelse beviste
samme metadataforskel. Alle øvrige portrecords matcher;48 actual compiles og
otte Python AST-checks bestod. Første trial blev tilbagerullet med alle17
filer gendannet, før den præcise metadataforskel blev afklaret. Ingen Studio-
ændring eller gameplay-/performancepass udledes af denne lokale pensionering.
[Endeligt review og rollback](artifacts/cleanup-serverstorage-20261009/retired-lobby-authoring-v2/REVIEW.md).
Lokal commit: `9b0c046864d18789728e0ddcccade30606e6c651`.

S02 har fjernet ti stale Codex-mirrors fra runtime-mapperne og manifestet
(lokal commit `52be2b82`).
Studio havde allerede fjernet begge folders; batchen ændrede ingen native
instans. Alle10 gamle filer/entries er bevaret byte-identisk i
[historikarkivet](artifacts/cleanup-serverstorage-20261009/retired-repo-mirrors/removal-receipt.json).
Det rydder333.941 kildebytes/9.134 linjer fra runtime-spejlet. Før-O0/arkiv-O1
compile20/20, begge source/full-sync-kontrakter samt221 aktuelle resterende
mirrorhashes/compiles bestod; ingen samtidig filændring under den målte port.
Ejerens manifestentries og nye LevelWorldStorage-modul er bevaret.

S01's egen fjernelsesport blev aldrig kørt: de12 gamle TEMP-resultat-Folders har ingen
children/callers/tags, men deres store attributes er historiske testdata.
Komplet native archive148.531 bytes, SHA
`9613ba71dbe8255cf67b28ac4fa58e9d3e5e034a231dcf79cf72dff81f395098`,
typed facts/Lune reload/canonical roundtrip bestod. Joint native referencepack
med StarterPlayer bestod105 serialized Ref-kontroller uden inbound references;
den beskyttede PlaceAvatarRules-reference er serialiseret null. Den fulde
native-port skal stadig bestå efter sidste yield før en fjernelse.
Frisk v7 Edit-capture og unparented native rekonstruktion bestod2.472 checks,
12 kopier oprettet/fjernet,609.670 reference-property-reads og nul kendte refs/
selection/source-/rootdrift. Det er historisk v7-status. En anden Studio-session
har siden taget alle12 ud af ServerStorage sammen med11 øvrige gamle rødder.
V8-capture bestod, men rekonstruktionsproben afviste den eksternt ændrede
Parent-baseline ved check4, før nogen testkopi eller originalændring.
Ny referencepack dækker577 objekter/105 serialized refs og samme null-reference.
S01 bruger same-original Parent=nil med rollback/nativearkiv, aldrig Destroy;
opaque referenter bevarer identitet. Før remove mangler samme-original trial/
restore og frisk efter-sidste-yield reference-/authoring-port. Disse manglende
porte er ikke godkendt af den eksterne fjernelse; vi gentager den ikke.
De uafhængige offline porte bestod89 folderchecks (39 negative cases) og
39 referencechecks (28 negative cases); skjulte refs, forkerte bytes/typer og
Source/CDATA/comment-falske tags afvises. Seks Python AST og12 Luau O0/O1
tool-compiles bestod. Disse tal er arkiv-/værktøjskontroller, ikke gameplay.
[Plan, præcise targets og begrænsninger](artifacts/cleanup-serverstorage-20261009/PLAN.md).

Kontrollerne afviste først beskyttet SourceAssetId-read, manglende public
editor-reflection metadata, og senere samtidige sourceændringer. Ingen af
disse fejl ændrede eller fjernede authoritative originals, og ingen runtimebatch
skulle rulles tilbage. Metadata-scanningen blev udvidet med officielle
ReflectionService descriptors; serialized beskyttede refs dækkes separat af
native referencepack. Andre sessions ændrede syv scripts, tilføjede et modul
og parkerede tre maps i ServerStorage. Deres arbejde er bevaret og får ingen
oprydningskredit. Ingen FPS-/memorygevinst er målt eller påstået.

Peer-review før native removal lukkede capture-/probe-lease, catalog/property/
attribute-epoch og guard efter HTTP-yields. Protected nonserialized holders er
fortsat opaque for denne tråd; authoringbetydningen og et friskt joint-reference-
snapshot skal afklares ved den senere native port. Ingen capture/probe giver
automatisk sletningstilladelse. Ny Edit-capture blev afvist ved sourceændring,
og næste forsøg blev afvist ved et nyt Play-skift; originals var intakte ved
disse historiske gates. De23 senere unparented træer er stadig intakte via
sessionreferencer og bevares nu i separat S06-nativearkiv.

Frisk read-only observation21:54:29Z:50 ServerStorage-rødder/212 scripts;
23 held-originals med Parent=nil,12 gamle Source/editor-par identiske med v8.
[Præcise navne og kildehashes](artifacts/cleanup-serverstorage-20261009/external-storage-observation.json).
Ejeren har særskilt pensioneret animations-previewworkflowet i den eksternt
fjernede TEMP-pakke. Senere Source-/rootændringer fra andre sessions registreres
som samtidige arbejde; de historiske tal er ingen afsluttende paritypåstand.

Receiver- og repo-retirement-wrappers er desuden rettet for uafhængig resource-
cleanup, pinned metadata, atomisk manifestfil og rollback uden at overskrive
samtidige filer. De faktiske wrappers bestod37 offline scenarier/1.104 checks,
herunder20 actual Luau compiles i en midlertidig kopis succesflow. Historisk S02v1
og inputarkiver er uændrede; ingen live batch blev genkørt af disse tests.

## S10 / T16,T17 — lokale dublerede transportfiler

Præcis 92 ignorerede, utrackede chunks er fjernet fra diagnostic-v7/v8,
external-storage-archive-v1 og retired-authoring-archive-v3: **60.168.414 bytes**.
Hver chunk matchede bytepræcist sin bevarede fulde fil, offset og transferreceipt.
Fuld native/facts/referencefil, gzip, Source-arkiver og alle receipts er bevaret.
Fire roundtrip-chunks fra den fejlede S06-object-reopen står stadig; de er
afventende og indgår ikke i denne fjernelse.

Samme faktiske Lune folder-/referenceconsumers, S04 verify-constructor/context
og S06 input-preflight bestod før, i isoleret partless kopi og efter faktisk
fjernelse med identiske portrecords. Alle syv consumerkilder og beskyttede
arkivfiler er bytebevarede; private testkopier ryddet. Nul Studio-kald, Source-
eller manifestwrites. Tallet er fjernede lokale filbytes, ingen FPS-/CPU-/memorygevinst.

Første faktiske trial blev tilbagerullet: eftertesten ramte en dobbelt oprettelse
af sin egen `.gitattributes`, før consumerportene. Alle 92 chunks blev gendannet
bytepræcist; ingen samtidige filer eller rollbackfejl. V2 rettede kun versions-
mapperne og denne setup-rækkefølge. Samtlige pins, assertions, rollback og
consumerporte er uændrede. Den efterfølgende faktiske V2-port bestod.
[Før-closure](artifacts/cleanup-serverstorage-20261009/transport-parts-review-v1/REVIEW.md),
[rollback](artifacts/cleanup-serverstorage-20261009/transport-parts-after-v1/rollback.json)
og [faktisk efter-receipt](artifacts/cleanup-serverstorage-20261009/transport-parts-after-v2/removal-receipt.json).
Lokal commit `5a3a06e7` omfatter det præcise værktøj, før-/efter-/rollbackbeviser
og read-only parity/console-receipts. Ingen canonical Source eller manifest er
staged i denne batch; de ignorerede transportchunks indgår aldrig i Git.

## S12 / T01,T02 — native Enabled i downstream-manifest

Præcis 96 manglende `Enabled`-felter er registreret fra friske native værdier.
De to eksisterende aliases, Disabled/RunContext, øvrige properties, Sourcehashes,
counts, attributes og andre rækker er bevaret. Alle 212 lokale Sources er
byteidentiske før/efter. Der er ingen native Source-/property-/objectwrites,
modeændringer eller publication.

Faktisk native før-/efterport læste 212 scripts og 15 remotes gennem ti sider
og slutguard: nul Source/editor-konflikter, source/class/registrerede-property-
mismatches eller fraværende/ekstra mirrors. Manifestets Enabled-coveragegaps
gik fra 96 til nul; native catalog var identisk før/efter. Det er et verificeret
Source-/property-snapshot, ingen fuld asset-/gameplay-/multiplayer-/streamingport.
23 faktiske offline-wrapper-fixtures/2.191 checks og eksisterende Source-/
full-sync-kontrakter bestod. [Faktisk receipt](artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-v1/receipt.json).

Før-manifest og afgrænset HEAD-blob ligger privat til rollback/commit. Den
oprindelige dirty RoundUI og dens working Source-række bevares; kun vores
Enabled-tilføjelse på den række er med i den lokale scoped commit `e78cf597`.
Den anden sessions dokumentationscommit `9ca01fc0` er bevaret særskilt.
Et genfundet ældre problem,
hvor generic full-sync kasserer metadata, er rettet særskilt i S13 nedenfor.

## S11 / B11,LE-34 — privat PuzzleManager-felt

Kun det ulæste `latchMode = true` er fjernet fra den private sessioninitializer
på linje 1373: 18 bytes. Native før-source på 105.520 bytes er gemt til rollback;
installeret Source/editor og repo er 105.502 bytes, SHA
`40fce9298d29bfca01e20c0307591b545dfb125b2b66a9ab7e2d4092f6b85d8c`.
Fresh identity/parent/class/Enabled/Disabled/RunContext/attributes/tags og CAS
bestod. De øvrige 211 native Sources og metadata er bevaret; ingen autoritative
object-/Parent-/propertywrites eller modeskift. Repoeksporten kom fra den verificerede native kilde.

Samme faktiske initializer, tre fuse/box/lever-handlers, TeamObjectives.Announce
og clearPuzzle bestod før/kandidat/installeret: 47 checks pr. version, 94 ved
reentry, samme trace/adfærd. Duplicate distribution, stale callback, Disconnect-
fejl, Destroy-fejl/retry og cleanup var med. Tre friske tomme ModuleScripts er
oprettet og fjernet, nul tilbage; alle 212 autoritative originaler er uændrede
af teststaging. V2's lease/ownership-port bestod otte cases/20 checks.
Faktiske runtime-flowgrænser er kontrollerede fixtures; dette er ingen egentlig
round-, multiplayer-, streaming-, respawn- eller performancegodkendelse.

Installer-V1 fejlede på afkortet/ulæseligt JSON-resultat før nogen productionwrite;
parsefejlen er observeret, transportvolumen er den sandsynlige årsag. Den bevarede
V1-receipt er et afvist forsøg. V2 brugte bounded hash-/metadata-sider og separate
native Sourcechunks; actual CAS, export og installeret replay bestod. Console
før/efter indeholder samme eksisterende beskeder; ingen ren-console-påstand.
Lokal scoped commit `a7c7bac4` indeholder præcis target/row og testbeviser;
dirty RoundUI og andre rows er bevaret. RoomDressing er ikke del af S11.
[Faktisk receipt](artifacts/cleanup-20261009/pending-locals-native-v1/latch-source-install-v2/result.json).

## S13 / T01,T02,T03 — eksportens native metadata

Eksportværktøjet bevarer nu friske native class-properties, segments,
attributes, tags og Source/editor-enighed frem for at kassere dem ved full-sync.
Den eksisterende native chunk-reader er uændret. Per-row snapshots kræver Edit,
rigtigt place/universe, samme instance/parent, class, Source/editor og metadata;
unsupported typed attributes og drift afvises. Tomme attributes bevarer `[]`.

39 Source- og 65 full-sync-checks, 19 faktisk sync-loop-scenarier/128 assertions
og 30 faktisk genererede Luau-scenarier/103 assertions samt O0/O1 bestod.
Root læste otte native getters på fire classes før/efter med stabile IDs,
properties, attrs/tags og native/editor-hashes. Sourcefiler og manifest var
uændrede. Remote Archivable=True blev sammenlignet med S12's native record;
den nuværende remote-row har en eksisterende properties-coveragegap.

Første forberedelses-preflight afviste en remote-path med manglende `Remotes`
før nativekald. Næste wrapper læste fire korrekte getters, men dens comparator
fejlede på remote-rowens manglende properties. Korrigeret comparator bestod
otte læsninger; alle afvisninger er bevaret. Den sidste `[]`-kompatibilitetsrettelse
ændrede kun outputrepræsentation; de fire faktisk læste getterkilder er
byteidentiske med final tool. Ingen faktisk full-sync/chunk-loop i Studio,
runtimeinitializer, Source-/manifest-/modewrite eller objekter. Eksporten er
inkrementel, ingen atomisk hel-place- eller gameplayport. Ingen målt gevinst.
Lokal commit `8fb44faf` omfatter præcis værktøj/tests og read-only beviser.
[Review og reproduktion](artifacts/cleanup-serverstorage-20261009/S13-native-metadata-preparation-v1/REVIEW.md).

## S14 / B11,LE-34 — private RoomDressing-rester

Fem præcise substitutioner fjerner125 bytes: safeRect's altid-false
reservePerimeter-parameter/inaktive true-gren/to false-callargs og breakerens
overskrevne Vector3. Source18.304→18.179
bytes/SHA44249205…→89fc2abe…. Aktive Plan/Apply/Place/carrier/mesh/collider/
nav/prompt, Level6-kit/bake/metadata og alle synlige constructorcalls bevares.
Caller-/authoringclosure inkluderer den pensionerede forskellige Level3-
installpayload og særskilt aktiv Level6-dressing; begge bevares.

Faktisk native førport00:19:14Z og installeret replay efter CAS00:22:27Z bestod
752 checks/version,1504paired/reentry: seeded placements/servicevarianter,
protected rooms/missing assets, prompts, busy/stale callbacks/task/connection-
cleanup og fejlveje. To eksisterende cleanupthrows efter alive=false har stadig
no-op-retry og efterlader owner i fixture; de er bevaret og ikke løst. To aktive
placement-mutants blev afvist;18 probecompiles,8leasecases/20checks og16 faktisk
installer-scenarier/109checks plus5anchorcases/8checks bestod. Fire friske tomme
testmoduler oprettet/destrueret, nul tilbage; alle212 originaler beskyttet.
Øvrige211 Sources/metadata og console er identiske; ingen rollback. Kun frisk
native export af target og to manifest-Sourcefelter landede lokalt. Ingen rigtig
round/asset/gameplay/multiplayer/streaming/performancegodkendelse følger heraf.
Lokal commit `5ad5c03d`; én blank EOF-linje i en præcis historisk read-source-
proof er dokumenteret som immutable whitespaceundtagelse, alle andre staged
paths bestod whitespacecheck. [Actual receipt](artifacts/cleanup-20261009/remaining-private-locals-native-v1/room-source-install-v1/result.json).

## S15 / B12,C26 — aktuelle QA-kommentarer

Kun ti stale kommentarblokke er fjernet/omskrevet:7195 bytes, UIRegression
320.730→313.535/SHA605da83a…. Alle197 funktioners O0/O1 executable bytes,
instructions/constants/upvalues/types/struktur er identiske; alene definitionernes
linjemetadata normaliseres. Public QA-aliases, RunAll, helpers og workflows
bevares. Den aktuelle ObjectiveCorner-beskrivelse svarer til Levels1–4.
Actual currentUI authoring/error/borrow/restore/reentry består105 før/105 efter.

Actual native CAS00:33:56Z, bounded export og installeret compiler-/UI-replay
bestod; afsluttet00:34:24Z. Alle212 Source/editor/identiteter/classes/parents/
properties/attributes/tags er kontrolleret; kun targethash/bytes ændredes.
Øvrige211 Sources/metadata og console er identiske. Ingen native runtimeprobe,
rollback eller autoritative object-/property-/modewrites. Den første offline
testextractorfejl og den gamle stale v1-kommentar er bevaret som historik.
Lokal commit `920abdee`; target-only manifestblob udelader dirty RoundUI.
Ingen fuld native UI/font/gameplay/device/performancegodkendelse påstås.
[Actual receipt](artifacts/cleanup-20261009/c26-comments-native-v2/c26-comments-source-install-v1/result.json).

## S16 / B14,LE-32 — ulæst privat Usher-state

Fem substitutioner fjerner alene86 bytes: private targetReason/nextThinkAt/
stunUntil nil/nul/simple-copy-deklarationer/writes. Source34.745→34.659,
SHA9af1a745…→ec425242…. Aktiv reason, Heartbeat/ThinkSeconds, stunCooldownUntil,
beamers, targetvalg, navigation, capture og offentlige Start/Activate/Finale/
Stop/DebugPlace bevares; ingen initializer-sideeffects fjernes.

Native førport00:41:11Z, CAS00:41:37Z og installeret replay00:41:49Z bestod
68 checks/version,136paired og136reentry med identisk behaviorhash8dd7b422….
Faktisk chooseTarget/think/setState/setBeamers/Stop samt capture-boundary-,
Disconnect- og Destroy-throw/retry er med;2 aktive reason/cooldown-mutants
afvises. Perception/nav/finishCapture/proxy er kontrollerede fixturegrænser,
ingen real-capture-idempotencegodkendelse. 18probe-/12CAS-compiles,8leasecases/
20checks,16actual installer-scenarier/109checks og5anchorcases/8checks bestod.
Hver native probe oprettede/fjernede fire friske tomme moduler, nul tilbage,
ejet lease frigivet og212-original guard PASS. Øvrige211 Sources/metadata og
console er identiske; ingen rollback. Target-only native export/manifestlanding
bevarer samtidige filer og dirty RoundUI. Afslutning00:41:59Z; lokal commit
`dc1561d1`. Ingen full-initializer/nav/asset/capture/jumpscare/
respawn/multiplayer/streaming/gameplay/performancecertifikat.
[Actual receipt](artifacts/cleanup-20261009/usher-private-locals-native-v1/usher-source-install-v1/result.json).

## B17 / T12 — lokal værktøjsoprydning

De to vault-builders læser nu deres eksisterende lokale credential lazy gennem
`vault_auth.py` med et eksplicit miljøoverride. Hardkodede TOKEN-literals er
fjernet; endpoint, payload, IDs, retry, timeout, `fix_folders` og configfri import/
dry-run er bevaret. To ignorerede lokale værktøjsnoter fik kun deres sourcefence
udskiftet. Øvrige note-bytes/links/newlines er bytebevaret. Pluginconfig var
identisk ved testporten og blev aldrig skrevet af batchen; et senere eksternt
configskift er bevaret, og frisk peer-review bekræfter stadig samme auth/port.
Rollback-kopier med credentials ligger privat under `.git`, uden for commits.

Lokal commit `4c2aca10`.18 actual-module offline-tests og fem AST/compile-checks bestod, inklusive
refresh, override, retry, fejlhåndtering og ugyldige headertegn før HTTP med
neutrale fejlbeskeder. Ingen rigtig builder, vault-regeneration, netværks-/MCP-
kald eller Studioændring. Den eksisterende credential og Git-historik er
bevaret; testen godkender ingen live Obsidian-forbindelse.
[Review og reproducerbare receipts](artifacts/cleanup-serverstorage-20261009/vault-auth/REVIEW.md).

## Afklaret pensionering, afventer test

Ejeren har godkendt pensionering af de fire gamle lobby-sourcepakker
`LobbyReimaginedBlenderSource20261001`, R2, R3 og R3B samt deres manuelle
authoringworkflows, og af det gamle `Level1BlenderKit` legacy import/export/QA-
workflow. R4, Level1BlenderKitV2 og gameplay bevares. Fuld dependency-closure,
native arkiv/reopen og aktive R4/V2-porte skal bestå før fjernelse. Ingen af
disse fem pakker er endnu fjernet; afklaringen tilskrives ikke en gennemført batch.

## Gennemførte batches

| Batch / fund | Ændring og bevaring | Testresultat / grænse | Lokal commit |
|---|---|---|---|
| B01a / T03–T05 | Native Source chunk-reader, ReplicatedFirst-dækning og fail-closed ved pending/conflicting/ulæseligt manifest. Ingen bulk-sync eller native writes. | Source39/full-sync65 PASS; stale editor, stor Unicode-source, ødelagte chunks og ingen writes ved konflikt. | `e019a427` |
| B01b / T06,T08 | Luau Unicode-literals i installer; receipt/inventory-fixtures bruger aktuelle Skins/DevAccess. IDs, grants og runtimeøkonomi er bevaret. | Installer20, receipt299, inventory87 PASS; semantiske negative kontroller. Fake store er ikke levende økonomigodkendelse. | `e019a427` |
| B01b / T07 | Layout-mutant kører i memory/temp og skriver aldrig original MODULE. | Actual interrupted Luau-child, inputguards og uafhængig geometry-oracle PASS. Hele gamle layout-suite mangler pensionerede inputs og afventer test. | `e019a427` |
| B01 supplerende | Luau0.737 success-probe i fake-push-test; material-codegen kompatibel med Python3.11, samme output. | Push18 cases/82 assertions PASS; material golden/generated compile PASS. Python AST450/450 på daværende tooling. Ingen rigtig push/upload. | `e019a427` |
| B02 / C08 | Fjernet 14 linjer/461 bytes fra én inert jumpscare-kommentar. Alle aktive camera/cancel/overlay-kald bevares. | O0/O1 instructions/constants identiske; line-padded raw binary identisk. Native fresh Source/editor/property/attribute-CAS, landing og lobby-smoke PASS. | `6eb13e22` |
| B03 / X05,T18 | Rettet README-kontroltegn til verificeret rollbacksti; slettet kun tracked nul-byte `smoke_tmp.py`. | Assetsti/280.679 bytes/hash verificeret; ingen helperreferences/initializers. Øvrige tomme QA/packagefiler bevaret. | `e019a427` |
| B05 / X02 | EditableMesh-cleanup på build/upload-fejl i L4/L5 helpers og L1/L4 wrappers. Constructors, markers, extraction-signaturer og assetresultater bevares. | Samme93 actual-source scenarier: før leak; efter1775 assertions +12 generationchecks PASS; fem mutants afvist; otte payloadcompiles. Ingen faktiske uploads eller målt MB-gevinst. | `12947a34` |
| B06 / N01 | Native glyph TextScaled/TextWrapped=true; QA måler eksisterende16/24px HUD-margin; TouchTarget gendanner sin egen scenario-state mellem devices. | Baseline935/51. Slut native full0, shared730/0, queue719/0 og særskilt Touch261/0; borrowed-state/lock drift[]. Offline105 samt HUD387+stamina74. Live-round skips/hardware er ikke gameplay-pass. | `11faa990` |
| B07 / LE-34 kommentarer | Kun2x4→2x5 og one-box-per-player→ceil(n/2) i kommentarer; −6 sourcebytes. | Begge fulde kilder O0/O1 raw binary identiske; fire runtime-mutants afvist. Native exact CAS/metadata/manifest samt installeret compilerreplay PASS. | `0efce872` |
| B08 / C05 | Fjernet13 private unused QA-definitioner,73 linjer/2823 bytes;102 øvrige deklarationer og30 public exports bevares. | Native før→isoleret ny ModuleScript→installeret frisk Play: full0/Touch261/0; reports og30 API key/type/arity-rækker byte-identiske. Guards/restore/destroy PASS; offline105 PASS. | `1dd48870` |
| B09 / N02 | Bounded capturemetadata,40 records/60.000 bytes per svar; raw SHA/identity/initial-final checks. |291 actual offline Luau checks/11 negative fixtures PASS. Frisk post-B08 native230 scripts/15 remotes,0 drift/editorconflicts. Første afkortede svar blev kasseret uden snapshot eller writes. | `e3af7ab2` |
| B10 / LE-32,LE-34 | Fjernet privat uncalled isStar og unread lampShade-binding; aktive STAR_TAGS og synligt devicePart/shade/light bevares. −168 bytes. | Samme actual lifecycle/constructor/error/cleanup173 assertions,8 compiles,2 semantic mutants afvist; native fresh CAS, metadata/manifest og installeret replay PASS;230 hashes/editor0 drift. | `2ca92003` |
| B13 / T09 offline | Stale pathfinding-guide-fixture erstattet med hele aktuelle WELCOME/HELP+ZyntraConfig. Runtime uændret. |133 assertions/6 mutants/AST/generated compile/inputguards PASS. Native fonts/input/viewport/streaming afventer. C21/C22 diagnostik er separat fra passing contracts. | `bce98752` |
| B15 / N03 | Probe-tool's staging/allocation/require beskyttet; uafhængig Destroy og final original guard køres også ved fejl. AGENTS dokumenterer CORE024-hændelsen og nye probe-regler. |23 actual-generated offline Luau scenarios/275 assertions PASS; præcis gammel staging leak reproduceret;2 ownership-mutants afvist; AST/generated compile PASS. Ingen Studio-kald. | `0608a9f8` |
| B16 / N04 | Fem eksakte historiske N01 pair/touch-inputs arkiveret; loader pin hashes og beskytter historiske receipt-navne. Ingen ny native gate. |70 offline checks,6 input/index-negative kontroller,2 outputkontroller, AST2 og20 O0/O1 compiles PASS. Fire native receipt-sourcehashes matcher; touch-current har ingen præcis native receipt og er input-only. | `f21bfdf4` |

Rålogs og præcise scopes: [tooling](artifacts/cleanup-20261009/tooling-results.md),
[mesh-cleanup](artifacts/cleanup-20261009/mesh-upload-cleanup-results.md),
[N01](artifacts/cleanup-20261009/N01-results.md),
[C05](artifacts/cleanup-20261009/C05-results.md),
[LE-34 comments](artifacts/cleanup-20261009/le34-comments/REVIEW.md),
[B10](artifacts/cleanup-20261009/local-helpers/installed-contract-check.json) og
[T09](artifacts/cleanup-20261009/first-entry-guide-results.md).
Historiske før-kilder, baselinefejl, CORE009/CORE024/CORE037-prøver og de tre
repo-only snapshots er samlet committed i `f7507c95`; de manglende native porte
bliver ikke dermed godkendt. [N01-arkivets review](artifacts/cleanup-20261009/N01-pair-proof/README.md)
angiver særskilt, hvad de fem inputfiler og fire receipts dokumenterer.

## Afgrænsede forslag, som stadig står tilbage

| Batch/fund | Allerede gennemført lokal port | Manglende port / disposition |
|---|---|---|
| B11 / LE-34 | S11 Puzzle47/version94reentry og S14 Room752/version1504paired/reentry, native før/kandidat/installeret CAS/export/212-parity/console PASS. | Afgrænsede private kodefelter gennemført `a7c7bac4`/`5ad5c03d`; gamle L2-authoringguides beholdes. Historiske Play-afvisninger og eksisterende Room-cleanupfejl er bevaret. |
| B12 / C04,C06,C07,C26 | S15 C26-kommentarer gennemført `920abdee`:7195bytes,197O0/O1 funktioner/UI105/105/native212-parity. Øvrige historiske local-porte bevares. | Loading announced beholdes; samlet Loading-unit ugyldig, C07 ny afgrænsning. S18 C06 no-op gennemført med455/910/910 native checks,213 originalguards/CAS/installeret port/parity. Øvrige syv gyldige runtime-units afventer egne native full/Touch/lobby/loading-porte; ingen runtimefeature fjernet dér. RoundUI er ikke mål. |
| B14 / LE-32 Usher | S16 actual68/version136paired/reentry,2mutants,4probe-cleanup/212-original guards, CAS/export/installeret/console PASS. | De86bytes private rester er fjernet i `dc1561d1`; perception/nav/capture-boundaries er kontrollerede. Fuld AI/gameplay/asset/performance-verifikation er fortsat særskilt. |
| B04 / CORE-024 | Rettet native syntetisk Add/Emit-gate86 PASS, cleanup0 og originaler uændrede. Public default/PLAN,66 colliders/28 lenses bevares. | Faktisk R4-kit/full Builder/MaterialPolish/lobby/physical/multiplayer/streaming-port mangler. Historisk fixtures fulde failure-cleanup kræver hardening før genbrug. Proposal er uimplementeret. [Review](artifacts/cleanup-20261009/core024/REVIEW.md). |
| CORE-025 | Private rester/require-closure genkontrolleret. | Før/efter full-builder/kit/initializer/lobby-support/queue/shop-port mangler; require fjernes ikke alene fra tekstsøgning. |
| CORE-037 | Offline aktuelle Routing+Suite:399 checks/5 eksisterende fejl; no-reset-proposal bevarer samme report og viser0 genbrugte IDs. | Ikke implementeret. Native Suite/Host/real TeleportOptions/live counter/cache/claim-isolering kræves. Der nulstilles ikke et aktivt servercounter for at teste. |

B12's historiske samlede Loading-kandidat er siden blevet **ugyldig**: ejerens
nyere kode giver `announced()` en aktiv `levelWorlds()`-caller. Funktionen
beholdes. Rootens førhash-guard afviste den ændrede baseline; ingen installation
blev forsøgt. C07's bindings skal afgrænses på ny mod frisk Studio-source. De
gamle inputbytes og tests bevares som historisk bevis, ikke aktuel autorisation.
Bytepræcise proof-blobs har lokal `-text -whitespace` Git-attribut, så originale
line endings og historisk trailing whitespace ikke bliver omskrevet.
B11/B12/B14's historiske forslag, eksakte inputs, lokale porte og Loading-
preflight blev committed som **beviser** i `e55b2da0`; de senere gennemførte
S11/S14/S15/S16-scopes er særskilt installeret og testet som beskrevet ovenfor.

## Tilbageførte og afviste forsøg

CORE-024's første prøve brugte `live:Clone()` og ScriptEditorService staging.
Clone-guard fejlede efter4 checks. En efterfølgende native læsning viste original
EndBlockades-source lig proposalhash; Builder var uændret. Root gendannede
originalen med præcis candidate→baseline CAS til SHA256
`5c120357fad94d1274a7eb6e39c6ce0cbf996505246b3b6b5c68d3dfa5cff98a`.
Alle230 Source/editor-par matchede derefter manifestet. Årsagen er ikke bevist;
editor-identitet/ScriptGuid er kun en hypotese. Ingen publication.

Friske testmoduler bruger `Instance.new("ModuleScript")`, exact tom source,
guard under write og original-check efter success/failure, owned cleanup og
borrowed-state restore. Dette er dokumenteret i AGENTS.md. Receipts:
[incident](artifacts/cleanup-20261009/core024-trial-incident.json),
[rollback](artifacts/cleanup-20261009/core024-trial-rollback.json),
[230-source check](artifacts/cleanup-20261009/post-trial-rollback-native-hashes.json),
[rettet syntetisk gate](artifacts/cleanup-20261009/core024-native-gate.json).

B11's afviste Play-writes ændrede intet native. De lokale forslag blev trukket
tilbage til exact før-kilder. N01's første efterport havde2 scenariefejl og en
separat TouchTarget-port8 fixtureleak-fejl; de historiske receipts bevares. Parret
QA før/current og korrigeret reset→friske full/touch-slutporte bestod. Et tidligere
wrapperkald til manglende UI.LockState tabte sit resultat og tæller ikke som pass.
C05's senere egne isolerede og installerede porte bestod fuldt inden ejerens Play.

## Økonomi, performance og bevarede features

CORE-004 er reproduceret i fake store, **ikke rettet**: commit-debit efterfulgt
af tabt svar returnerer false, markers3→2; ny retry lykkes,2→1. Runtimeøkonomi
står, indtil operation-ID, duplicate requests, commit-then-error, refund retries,
disconnect, callback retries og round-epoch/settlement-porte er opfyldt. Fake
receipt299/inventory87 er ikke alene remediation-pass. CORE-009's oprindelige
fakehost111 checks består, men den nye L4-check fejler med analytics `other`.
Det uimplementerede in-memory allowlistproposal består127 checks. Ingen ekstern
analyticswrite er sendt.

Ingen gennemført batch har en målt faktisk FPS-, server CPU-, memory- eller
lobbyboot-gevinst. Sourcebytes og korrekt Destroy-lifecycle er dokumenteret.
CORE-024's **uimplementerede syntetiske** prøve:7 ens trials, median5,05→0,58ms,
transient furniture219→0. Det installerede R4-kit manglede; modellen var
syntetisk. Tallene gælder ikke det faktiske spil.

Bevaret: Level2 WorldBuilder's aktive tube/flume-helpers; Level6BlenderRuntimeBake
og Kit Metadata brugt af Level3; EndBlockades colliders/lenses; alle aktive
constructorcalls, usynlige collision/nav/hiding/prompt-parts, receipt IDs,
spillerdata, entitlements, migrations/grants og backupmapper. Preview/Legacy/
Disabled/navn eller ens script-source var aldrig alene slettebevis. Ingen
native non-script spilobjekter blev slettet som oprydning. Ejerens native
spilbackup bevares; et sourcespejl erstatter den ikke.

Aktive L2/pump/Foam/Slide/generated-L6/disabled/manual workflows, non-arena/
v1-kit-fallbacks og de nuværende gameplay-/ranking-/rate-/UI-/
økonomipolicies beholdes. Permanente entitlements/receipt/grant/migration-data
er obligatorisk bevaret. 27 tidligere beslutningsrækker er disponeret sådan
under bevaringsmandatet. En eventuel senere pensionering eller policyændring
kræver sit eget produktvalg og tests; den afventer ikke et svar i denne batch.
De allerede godkendte gamle Lobby-/Level1-/TEMPPreview-workflows kræver
derimod de beskrevne manglende native testporte, ingen ny tilladelse.
Den gamle fulde lobbyfallback og Studio-animationworkflows er senere også
pensioneret af ejeren. Deres konkrete runtime-/nativefjernelser følger egne porte.

Level2 living-participant safe spawn, anden distinct pump, tredje distinct
escalation, active-round navigation/retry/reset og server CPU/memory er ikke
godkendt. Multiplayer, streaming og rigtige reserved-server teleportforløb
kræver deres egne Roblox-clientporte. Studio kan ikke godkende ægte teleport.

## Parity og samtidigt arbejde

Start/fetched origin/main var `46073662`; seneste fetch i denne opgave viste
samme remote head. Ingen push, force-push eller history rewrite.
Baseline:230 scripts/15 RemoteEvents,0 source/editor/hash/class/properties/
attributes/manifest-afvigelser; repo230/native230 compile PASS.
Post-B08 fuld metadata/export har samme inventar og0 afvigelser/conflicts;
[receipt](artifacts/cleanup-20261009/post-B08-parity.json).
B10's native writeguards bevarede class/properties/attributes, manifest matcher,
og eftercheck havde230 scripts/0 Source/editor/hashdrift.

Historisk verificeret read-only repo-snapshot under daværende ejer-Play: **230/230** mirrorcompiles,
**230/230** manifesthash/byte-matches, **451/451** tooling Python AST;0 failures.
[Seneste receipt](artifacts/cleanup-20261009/owner-play-repo-checks-latest.json) angiver capturetid,
repo-only scope,0 Studio-kald og afventende native parity.

Den oprindelige dirty RoundUI og tilhørende manifestentry er bevaret og aldrig
committed af oprydningen. Mens ejeren brugte Play, opstod yderligere samtidige
ændringer i BlenderRoomRenderer, Lobby DJ Client, Shop Display Client, Lobby
Loading Screen, Round Entry Client og deres manifestentries. Seneste checkpoint
omfatter alle seks runtimefiler inklusive oprindelig RoundUI og manifestet:
`.git/mongotv-cleanup-20261009/concurrent-20261009T200540091097Z/`, bevaret og
ikke tilskrevet eller staged som vores arbejde. Den anden session har siden
afstemt og committed sine øvrige ændringer i `37f09c9c`; dens arbejde tilskrives
ikke oprydningen. Frisk Edit-kontrol efter S06 23:27:13–23:27:23Z viste 212
scripts og 15 remotes, 227 faktiske/deklarerede manifestrows, ingen fraværende/
ekstra native scripts, ingen ekstra mirrorfiler, Source/editor-konflikter eller
Source/class/registrerede property-mismatches. Catalog og repo var stabile
gennem alle ti sider og slutcheck. Dette er et point-in-time Source/klasse/
registreret-property-pass, ingen fuld assetparity. 96 Enabled-properties er læst
native, men var ved denne historiske kontrol ikke registreret i manifestet;
tags/attributes og full native assets er uden for denne diagnose.
[Efter-S06 parity](artifacts/cleanup-serverstorage-20261009/final-parity-v2/after-S06-v4/result.json).
Returnerede consolebytes før/efter S06 var identiske. Eksisterende unapproved-
sound-fejl for asset `134572728354839` og historiske probe-/StreamingMinRadius-
meddelelser står stadig; det er ingen clean-console- eller fuld gameplaypåstand.
[Console-sammenligning](artifacts/cleanup-serverstorage-20261009/final-parity-v2/after-S06-v4/console-before-after-comparison.json).
Senere S12-slutkontrol **2026-10-09 23:54:21Z** har samme 212 scripts/15 remotes/
227 manifestrows og stable catalog, nul Source/editor-konflikter eller mismatch,
og nu nul Enabled-coveragegaps. Alle 212 Sources er bytebevarede. Returneret
consoletekst er stadig byteidentisk, inklusive de eksisterende fejl.
[Senere parity](artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-v1/native-after/result.json),
[console](artifacts/cleanup-serverstorage-20261009/S12-enabled-metadata-v1/console-comparison.json).
Under den tidligere dokumentationskontrol ændredes Loading/manifest igen; stale checkpoint-
guard afviste prøven før artifactwrites. Ny checkpoint og repo-only port blev
taget, uden at overskrive tidligere receipts. Senere samtidige ændringer er
ikke godkendt af en tidligere snapshot.

Afsluttende frisk kontrol **2026-10-10 00:42:34–00:42:44Z**, efter S11/S14/S15/
S16, viser **212 scripts/15 remotes/227 rows**,52 ServerStorage-rødder og416.276
sceneobjekter. Nul Source/editor-conflicts, hash/class/registrerede-property-
mismatches, missing/extra native/mirrors, property-readfejl eller Enabled/
Disabled/RunContext-coveragegaps; faktiske og deklarerede counts matcher.
CatalogSHA `e931f551…` og lokale Sources/manifest er stabile gennem ti sider
og slutread. Særskilt Root-API-mode er Edit før/efter og console-resultatet er
eksakt identisk, inklusive de kendte eksisterende lyd-/Assistant-/radiusfejl.
Final reader/API foretager nul Source/manifest/native-object/modewrites.
Dette er Source/editor/class/registreret-property-parity ved observationen;
attrs/tags/fullassets/gameplay/continuous modeepoch indgår ikke i finalreader.
S14/S15/S16's separate originale212-guards dækkede attrs/tags under batches.
Remote Archivable er læst, men er fortsat en eksisterende uregistreret manifest-
property. Historiske sync created/updated/unchanged er ikke populationscounts.
[Actual finalparity](artifacts/cleanup-serverstorage-20261009/final-parity-v3/after-cleanup/result.json),
[mode/console-boundary](artifacts/cleanup-serverstorage-20261009/final-parity-v3/root-boundary-v1/proof.json).
Origin/main er fortsat `46073662c859eef421fc262177eb71be7c498ea6` ved frisk
ls-remote; ingen cleanup-push/publicering. Den oprindelige RoundUI og dens
working-only Sourcehash/bytes-row er stadig bevarende ustaged. Scoped commits
inkluderer kun hver batches egne target-/metadatafelter og reviewede beviser.

**Afventer:** S04's protected-reference-port før permanent pakkeændring;
S28 har siden bestået R4/V2/elevator-data/fravær/restoration-porten. Bredere
gameplaykrav afgrænses kun ved komplet data-only closure. Fuld 23-træers native restoration;
øvrige konkrete
runtime-/økonomi-/clientporte i planen. De afklarede workflows er pensioneret
lokalt. Manglende nødvendige testporte er årsagen til de bevarede kandidater,
ikke manglende pensioneringstilladelse. De dokumenterede sikre batches er
gennemført; de nødvendige udestående runtime-/assetporte erklæres ikke afsluttet.
De tidligere native UI-porte er reelle passing receipts med lobby-context/
live-round skips; de godkender ikke alle aktive gameplayflows.
