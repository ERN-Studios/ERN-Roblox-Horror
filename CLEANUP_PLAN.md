# MongoTV oprydningsplan — 2026-10-09

Studio er source of truth. PlaceId **131311258779917**, universe **10559217407**.
Denne opgave publicerer ikke det offentlige spil. Ingen GitHub-push er planlagt.

## Baseline og samtidige ændringer

- Startcommit: `46073662`; `git fetch origin` bekræftede samme `origin/main`.
- Eksisterende dirty arbejde: `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`
  og `studio-sync-manifest.json`. Bytekopier og binær Git-diff bevares lokalt i
  `.git/mongotv-cleanup-20261009/preexisting/` og `preexisting.patch`.
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
  HUD-layoutforventninger; harness lock clear. C05 og relateret HUD-oprydning
  afventer afklaring/test. Fejlene er ikke introduceret af oprydningen.

## Prioriterede batches

| Batch | Fund og præcis afgrænsning | Ændring / bevis | Dependencies og risiko | Testport før/efter | Status |
|---|---|---|---|---|---|
| B01a | T03/T04/T05: `tools/sync_from_studio.py`, `tools/pull_source_from_studio.py` | Native Source-læsning, ReplicatedFirst-dækning, fail-closed ved queued/conflicting lokale edits. Nuværende full-sync læser editorbuffer og kan overskrive pending arbejde. | Shared source contract, push/pull/full-sync og fake Studio; ingen live Studio-write. Lav runtime-risiko, stor mirror-sikkerhedsgevinst. | Offline integration med stale editor, stor Unicode-source, pending/conflict uden writes; eksisterende source/push/full-sync gates. | afventer test |
| B01b | T06/T07/T08: generic installer, layout-mutantcheck og receipt/inventory fixtures | Korrekte Luau-literals, mutation i temp/in-memory kopi, aktuelle dependencies så økonomiassertions nås. | Præcise filer og fixtureclosures i repo-tools-recheck; receipt IDs/entitlements/økonomikode bevares. | Offline Unicode byte-roundtrip, mutant-afvisning uden original-write, eksisterende duplicate/failure fixtures og meningsfuld negativ kontrol. | afventer test |
| B02 | C08: `StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua`, eneste `LEGACY IMAGE JUMPSCARE` kommentarblok | Fjern kommenteret gammel billedimplementation; ingen eksekverbar kode. | `Remotes.Jumpscare`, aktive camera/cancel/overlay-flows bevares fuldstændigt. Lav risiko, 14 døde linjer fjernes. | O0/O1 instruktioner+konstanter identiske; binær forskel kun dokumenterede linedefined-varints og proto-størrelser, line-padded trial binært identisk. Native fresh Source/editor compare-and-swap, compile og lobby-smoke. | afventer native test |
| B03 | X05: `tools/level4_blender/README.md`; T18: `tools/level2_poolrooms/smoke_tmp.py` | Ret kontroltegn i verificeret rollbacksti; fjern kun nul-byte stray helper efter referencekontrol. | Rollbackobjekt på disk bekræftet; ingen initializer-sideeffects i tom fil. Lav risiko. | Sti findes og README uden kontroltegn; eksakt reference-/toolingcheck før/efter. | afventer test |
| B04 | CORE-024: `TunnelLobbyEndBlockades.ModuleScript.lua` Add/Emit placement-loop og caller `TunnelLobbyBuilder` | Skip kun furniture-clones, som samme build destruerer; public authoring Emit/PLAN bevares. | Colliders/lenses, tom folder, Ready/attrs og authoring-default skal bevares. Moderat risiko; mindre buildarbejde. | Isoleret before/after native build, fulde relevante objekt/propertykontrakter, authoring default, error/cleanup/rebuild samt samme-scenarie timing og frisk lobbyflow. | afventer test |

B02/C08 er **gennemført**: frisk Source/editor/property/attribute-guard inde i
UpdateSourceAsync-callback; native landing og manifest verificeret. Efter-smoke:
levende character, health100, LobbyLoadingDone=true, 68 assets/0 preload-fejl,
kun samme eksisterende lydafvisning. Kommentaroprydning fjerner 461 bytes og
14 linjer; den ændrer ingen aktive jumpscare-instruktioner eller konstanter.

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
