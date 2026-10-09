# MongoTV oprydningsresultater — 2026-10-09

Studio er source of truth: place **131311258779917**, universe **10559217407**.
De tidligere gennemførte, testede batches er lokalt committed. Intet er publiceret eller
pushet til GitHub. Ejeren har igen godkendt Studio-arbejde; to andre sessions
arbejder samtidig og har igen startet Play. Deres session bevares. Yderligere
native porte og afsluttende Edit-parity afventer tilgængelig Edit.
Vores valgte afventende runtimeforslag står stadig uimplementeret; eksternt
implementerede ændringer beskrives særskilt uden oprydningskredit.

Alle **129** oprindelige fund er genkontrolleret og disponeret i
[CLEANUP_PLAN.md](CLEANUP_PLAN.md) og de tre delrapporter:
[repo/tools](artifacts/cleanup-20261009/repo-tools-recheck.md),
[klienter](artifacts/cleanup-20261009/clients-recheck.md) og
[levels/core](artifacts/cleanup-20261009/levels-core-recheck.md).
De er hypoteser; eksisterende rettelser er ikke implementeret igen. Afgrænsede
dele af blandede fund har deres egen status og testport.

## Aktuel ServerStorage-oprydning

S02 har fjernet ti stale Codex-mirrors fra runtime-mapperne og manifestet.
Studio havde allerede fjernet begge folders; batchen ændrede ingen native
instans. Alle10 gamle filer/entries er bevaret byte-identisk i
[historikarkivet](artifacts/cleanup-serverstorage-20261009/retired-repo-mirrors/removal-receipt.json).
Det rydder333.941 kildebytes/9.134 linjer fra runtime-spejlet. Før-O0/arkiv-O1
compile20/20, begge source/full-sync-kontrakter samt221 aktuelle resterende
mirrorhashes/compiles bestod; ingen samtidig filændring under den målte port.
Ejerens manifestentries og nye LevelWorldStorage-modul er bevaret.

S01 er endnu ikke installeret: de12 gamle TEMP-resultat-Folders har ingen
children/callers/tags, men deres store attributes er historiske testdata.
Komplet native archive148.531 bytes, SHA
`9613ba71dbe8255cf67b28ac4fa58e9d3e5e034a231dcf79cf72dff81f395098`,
typed facts/Lune reload/canonical roundtrip bestod. Joint native referencepack
med StarterPlayer bestod105 serialized Ref-kontroller uden inbound references;
den beskyttede PlaceAvatarRules-reference er serialiseret null. Den fulde
native-port skal stadig bestå efter sidste yield før en fjernelse.
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
og næste forsøg blev afvist ved et nyt Play-skift; originals står stadig.

Receiver- og repo-retirement-wrappers er desuden rettet for uafhængig resource-
cleanup, pinned metadata, atomisk manifestfil og rollback uden at overskrive
samtidige filer. De faktiske wrappers bestod37 offline scenarier/1.104 checks,
herunder20 actual Luau compiles i en midlertidig kopis succesflow. Historisk S02v1
og inputarkiver er uændrede; ingen live batch blev genkørt af disse tests.

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
| B11 / LE-34 | RoomDressing safeRect/breaker og PuzzleManager unread latchMode:1477 actual authoring/interaction/error/cleanup assertions; faktisk sessioninitializer+tre handlers21 før/21 efter;8 compiles/3 mutants. | MCP afviste Edit-write før execution i ejerens Play. Begge lokale candidates blev gendannet til præcise før-bytes; manifest uændret. Afventer Edit/fresh native CAS/installeret replay. [Review](artifacts/cleanup-20261009/additional-locals/REVIEW.md). |
| B12 / C04,C06,C07,C26 |Historisk11 local/comment-scopes,10 install-units; constructorcalls/public aliases uændrede. Actual authoring287, HUD185/shared387+74, exit/hiding92, UIRegression105, store777; negative controls. C26 executable O0/O1 binary identisk. | Ingen native writes. Loading-unit ugyldig; announced beholdes, C07 kræver ny afgrænsning. Øvrige ni units afventer ejerens Edit, fresh CAS, installeret replay samt native full/touch/loading-smoke. RoundUI er ikke mål. [Review](artifacts/cleanup-20261009/CLIENT_LOCALS_REVIEW.md). |
| B14 / LE-32 Usher |59 actual targeting/think/stun/Stop assertions;4 compiles/2 mutants. Perception/nav/capture er kontrollerede grænser. | Private targetReason/nextThinkAt/stunUntil står endnu. Afventer fresh native CAS/installeret replay; ingen fuld AI/gameplaymåling. [Manifest](artifacts/cleanup-20261009/usher-locals/candidate-manifest.json). |
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
B11/B12/B14's forslag, eksakte inputs, lokale porte og den nye Loading-preflight
er committed som **beviser**, ikke runtimeinstallationer, i `e55b2da0`.

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

Åbne valg og nødvendige porte er detaljeret i planen/delrapporter: pensionering
af L2/pump/Foam/Slide/generated-L6/disabled/manual workflows; non-arena/v1-kit/
original-lobby-fallbacks; assistance/leaderboard, breadcrumb, alert-rate-limit,
Luna/Reach-policy, gifts/backfill og DJ-screen ownership. Intet manglende svar
tæller som godkendelse af pensionering.

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

Seneste verificerede read-only repo-snapshot under ejerens Play: **230/230** mirrorcompiles,
**230/230** manifesthash/byte-matches, **451/451** tooling Python AST;0 failures.
[Seneste receipt](artifacts/cleanup-20261009/owner-play-repo-checks-latest.json) angiver capturetid,
repo-only scope,0 Studio-kald og afventende native parity.

Den oprindelige dirty RoundUI og tilhørende manifestentry er bevaret og aldrig
committed af oprydningen. Mens ejeren brugte Play, opstod yderligere samtidige
ændringer i BlenderRoomRenderer, Lobby DJ Client, Shop Display Client, Lobby
Loading Screen, Round Entry Client og deres manifestentries. Seneste checkpoint
omfatter alle seks runtimefiler inklusive oprindelig RoundUI og manifestet:
`.git/mongotv-cleanup-20261009/concurrent-20261009T200540091097Z/`, bevaret og
ikke tilskrevet eller staged som vores arbejde. Frisk endelig Edit-export skal
afstemme dette nyere arbejde før en afsluttende parity-påstand.
Under dokumentationskontrollen ændredes Loading/manifest igen; stale checkpoint-
guard afviste prøven før artifactwrites. Ny checkpoint og repo-only port blev
taget, uden at overskrive tidligere receipts. Senere samtidige ændringer er
ikke godkendt af en tidligere snapshot.

**Afventer:** ejerens tilbagemelding, resterende valgte native batches/tests,
frisk samlet Edit-source/editor/property/manifest-parity, aktuelle native
sourcecompiles og console/residue-review. Denne rapport registrerer pausepunktet;
den erklærer ikke hele oprydningen afsluttet.
De tidligere native UI-porte er reelle passing receipts med lobby-context/
live-round skips; de godkender ikke alle aktive gameplayflows.
