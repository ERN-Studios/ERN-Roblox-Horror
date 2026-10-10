# Klient/shared recheck – 2026-10-09

Denne rapport genkontrollerer C01–C31 mod de aktuelle kanoniske projektfiler. Analysen og de fire offline baseline-gates blev udført før klientændringer. Den senere godkendte C08 repo-kandidat er registreret nedenfor. Ingen Studio-kald eller start/stop er udført af denne delopgave; root ejer native compare-and-swap, manifest og Studio-tests. Eksisterende dirty `RoundUI` og manifest er bevaret.

Læst grundlag: projektets `AGENTS.md`, audit `HANDOFF.md`, `findings-index.md` og `clients-audit.md`. `graphify query` blev brugt som orientering i det eksisterende graph; grafen indeholder historiske kilder og er ikke autoritativ for dagens callers. Alle nedenstående konklusioner er genkontrolleret i aktuelle filer og relevante references. Historiske artifacts/sourcepacks er ikke behandlet som aktive runtime-callers.

## Baseline og allerede løste punkter

- Oprindelig baseline-manifest: 230 scripts (129 ModuleScript, 72 LocalScript, 29 Script) og 15 RemoteEvent-stubs. Alle245 filer fandtes og matchede deres SHA256 efter CRLF→LF-normalisering. Rå diskbytes varierede på20 filer alene på grund af CRLF. Dette beviste manifest/repo-konsistens ved baseline, ikke i sig selv native parity. De senere samtidige DJ/Shop Display-ændringer nedenfor kræver ny root-parity.
- Root har oplyst korrekt PlaceId og 230 native scripts med Source/editor-enighed. Native source-sammenligningen registreres af root separat.
- C01: de tidligere driftede guide/preview/L5-kilder og DJ/Tunnel/DevESP er nu spejlet. Genimplementér ikke gammel source-sync.
- C03: de fire Studio-fraværende gamle L6-klienter er allerede ude af kanoniske roots/manifest. Disabled L6 Reader, L6 Sound og SetRunAnimation består.
- C31: den gamle L2 Pool Slide Dev ESP er allerede ude af kanoniske roots/manifest.
- C30: tom `6430` er allerede fjernet. De to lokale `.claude-flow` JSON-filer findes, men er utrackede og ignorerede af `.gitignore:220`.
- C22: auditens udsagn om direkte camera-viewport er delvist forældet: WELCOME bruger nu `UIDevice.Layout().Viewport` og `UIDevice.Changed`. Den utilstrækkelige hit-targetstørrelse efter UIScale består.
- Senere samtidig ejer-/developerændring, checkpoint `concurrent-20261009T193459220110Z`: DJ har nu raw-attribute JSON-cache og tidlig round-guard; Shop Display har bounded0.5s retry og tidlig round-guard. De er ikke cleanupændringer/commits. C09/C15 er genkontrolleret mod disse aktuelle repo-kilder; native installation, workflowtests og målt gevinst påstås ikke her. Ingen af de samtidige kilder er skrevet af denne delopgave.
- C04/C06/C07/C26 har portable byte-identiske før-/kandidat-inputs i [proof index](client-local-proofs/index.json). Alle lokale paired gates er reproduceret med portable inputs alene i [separat receipt](client-local-portability-gates.json); oprindelige raw receipts/checkpoints uændrede. Det kollektive Play-stop var historisk. C26 er nu gennemført som S15 `920abdee` med faktisk scoped native CAS/eksport/installeret efterport; de øvrige otte aktuelt forberedte kildekandidater og Loading-reconcile afventer fortsat deres egne nødvendige full/Touch/lobby/nativeporte. Samtidige ejersessioner og deres mode bevares; ingen ejer-stop antydes.
- Nyere samtidige Loading/Round Entry-ændringer gør den gamle Loading-unit **ugyldig**: `announced():724–726` er nu aktiv via `levelWorlds():728`→round-prefetch`:752` og skal beholdes. Root's exact-before guard afviste den gamle9483…baseline uden native installation. LF-hashes observeret ved denne genkontrol: Loading `df0b347a37e096503c2cfd5fd04991f4be4f3167049711dccbd22b9106e69491`; Round Entry `b2c27975ef4c836881e294068d17df4d3b6034984b0120d1f87877057742f0d1`. De ændringer er ejer-/developerarbejde, ikke cleanup. Gamle proof-inputs/receipts er uændrede historiske testresultater, ikke godkendelse af de nye kilder.
- Ny Loading/Round Entry-closure: supported content-/carrier-census og pending/failed bookkeeping, request-owned busy/generation guards, bounded retry-attempts og DescendantAdded watchers er aktive. Round Entry overvåger character og nær entry-worldens synlige art, sætter AssetsReady=false ved nye arrivals og kræver0.35s quiet+existing UI/controls/ground gate før entryready; cancel/deadline/respawn afbryder request-owned connections. Loading bevarer roundcover ved RoundUI, mens live5/6 cover har bounded prefetch og særskilt incomplete status. Ingen af disse nye helpers/workers/watchers er fjernet eller behandlet som redundant kode.
- Manglende nye flowporte: initial+late mesh/image/URI/opaque content, success/failed/no-callback/hanging PreloadAsync, retries/ENTER ANYWAY, obsolete generation under nyt entry, cancel/deadline/respawn/disconnect/reentry, ground/UI/controls stability samt multiplayer/streaming. Round5/6 reserved arrival kræver relevant Roblox-clienttest; native preload-return eller tom RequestQueue er ikke i sig selv renderer/PBR/mip-readiness. Den eksisterende offline `test_round_entry_client.py`-fixture skal genkontrolleres for nye DescendantAdded/nearby/content-boundaries, før den bruges til en ny pass-påstand. Ingen sådan pass er påstået her; root udfører fresh native før/efter efter ejerens Play.

## Udførte offline baseline-checks

Seneste yderligere repo-snapshot kl20:06UTC flytter Loading's `announced()` til
`:743`, caller til`:747` og round-prefetch til`:771`; kilden er36701 LF-bytes,
SHA `872b9ed13fdc0e21332a844a6931b5ba2796a1ffd659a45f6cf0d5d945049583`.
De tidligere hashes/linjer ovenfor er historiske. Funktionens aktive dependency
består; ingen gammel Loading-kandidat må installeres. Det er stadig ejerarbejde,
og den friske native Source/editor- og featureport er afventende.

Kørt med eksisterende Luau 0.737 fra `C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737`, `PYTHONDONTWRITEBYTECODE=1`, uændret kode og midlertidige fixtures uden projektmutationer.

| Entry point | Resultat | Dækning/begrænsning |
|---|---|---|
| `tools/tests/test_ui_regression_shared.py` | PASS, 90 checks | Aktuel UIRegression compile; shared borrow/restore/residue/error cleanup og TouchTargetMatrix-sektion. Ingen fuld native RunAll/font/input. |
| `tools/tests/test_round_hud_shared.py` | PASS, 382 shared + 74 stamina checks | Aktuelle RoundHud/Round HUD/NoiseReporter compile og virkelige importerede Framewisp-trees. Ingen native render/hardware. |
| `tools/tests/test_round_exit_hold.py` | PASS, 92 B6/B7 checks | Produktionskilder, importerede controls, hold/cancel/pending/retry/stale-timers. Native platformrouting kræver Studio. |
| `tools/tests/test_controller_input.py` | PASS, 91 controller + 86 touch-cell + 74 stamina + 63 POV checks | Produktionslogik ved offline engine-boundary. Ingen fysisk controller, kamera eller native input-routing. |

Checkene er baseline, ikke gennemførte runtime-fjernelsesporte. Performance er ikke målt. Ingen af rapportens operationstællinger er en påstået FPS/MB-gevinst.

## C01 – tidligere source drift

- **Præcis closure:** `StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua`; `Level 1 Sound Controller.LocalScript.lua`; `Level 5 Lighting Controller.LocalScript.lua`; `Level4PreviewPrompt.LocalScript.lua`; `Level6PreviewTransport.LocalScript.lua`; `R4DevGateController.LocalScript.lua`; nu spejlede `Lobby DJ Client.LocalScript.lua`, `Lobby Tunnel Reach Client.LocalScript.lua`, `Level 6 Dev ESP.LocalScript.lua`.
- **Handling/bevis:** behold de verificerede native spejle; ingen genskrivning fra auditens gamle repo. Aktuel guide har WELCOME/HELP og aktiv spawn-view; public L5/L6, DJ/Tunnel/ESP står i manifest. Baseline-manifesthashes passede; nyere samtidige DJ/Shop-kilder må genafstemmes fra Studio af root.
- **Dependencies:** DevAccess, UIDevice, ZyntraConfig, public PreviewAccess, Loading/RoundUI, LobbyDJ remote/attributes og authored maps. Source-sync/installer-tests er relevante authoring-callers.
- **Risiko/gevinst:** lav ved at registrere allerede løst; høj ved at overskrive nyere Studio. Gevinst er korrekt grundlag.
- **Før/efter-port:** root sammenligner fresh native Source/editor/class/Disabled/RunContext og manifest. Hvis ingen kodeændring, ingen ny gameplaytest til at genimplementere reconciliation.
- **Status:** **gennemført tidligere**, betinget af root's friske native parity-resultat.

## C02 – to kommentar-only migration-markers

- **Steder:** `StarterPlayer/StarterPlayerScripts/Team Objective Feed.LocalScript.lua:1–2`; `StarterPlayer/StarterCharacterScripts/DisableDefaultWalkingSound.LocalScript.lua:1–5`.
- **Handling/bevis:** eventuel fjernelse af kun disse to instanser og manifestfiler. Begge består kun af kommentarer og har ingen initializer/hook/require. Projektreference er manifest plus successor-kommentar i `Round HUD:255`.
- **Dependencies:** aktive successors `Round HUD`, `ReplicatedStorage/RoundHud` og `SoundController`. TeamObjectives/RoundStatus-kontrakten og dynamisk HumanoidRootPart.Running.Volume skal bevares. Tooling må ikke antage marker-navne/count.
- **Risiko/gevinst:** lav runtime-risiko, lille reduktion af no-op scriptinventar; mulig navne/count-kontrakt i sync.
- **Før/efter-port:** kontroller references og native kommentar-only source; Studio join/respawn, lobby Running, custom footsteps og objective-feed; sync/manifest-contract efter scoped deletion. Object/property rollback gemmes først.
- **Status:** **afventer test**; ingen object-removal udført.
- **Senere owner-entry-recheck:** begge marker-kilder er fortsat rene kommentarer; de nye Loading/Round Entry-diffs tilføjer ingen caller til dem. Den aktive RoundStatus entryprepare/entryready-kæde og gate-attributter er bevidst bevaret. Dette er fortsat ikke en successor-join/respawn/feed/footstep-før/eftertest; eventuel marker-removal skal vente på ny owner-flow baseline og exact native objektbackup/parity.

## C03 – gamle L6-klienter og animation-patch

- **Steder:** de tidligere kanoniske `Level 6 Lighting Controller`, `Level 6 Mall Manager Visual Smoother`, `Level 6 Table Hiding Client`, `Level 6 CD Dev ESP` er allerede fraværende i roots/manifest. `StarterPlayer/StarterPlayerScripts/Level 6 Reader Client.LocalScript.lua`, `Level 6 Sound Controller.LocalScript.lua` og `StarterPlayer/StarterCharacterScripts/SetRunAnimation.LocalScript.lua` har stadig manifest `Disabled=true`, `RunContext=Legacy`.
- **Handling/bevis:** markér de fire tidligere sync-kandidater allerede løst; behold tre disabled instanser indtil konkrete retirementvalg. Disabled/navn er ikke slettebevis. SetRunAnimation ændrer run-asset til `83054249237379`, hvis genaktiveret.
- **Dependencies:** gamle Level6 server/sourcepacks/tests; aktive Playground Game/Client/DevESP/DJ skal bevares. L3's Level6BlenderRuntimeBake/Kit Metadata må ikke følge med i retirement.
- **Risiko/gevinst:** nul runtimegevinst ved disabled deletion; rollback/authoring kan brydes. Kanonisk sync genskaber allerede ikke de fire gamle klienter.
- **Før/efter-port:** migration/sourcepack-callers og full native object/property backup; ny manifest må ikke reaktivere gammel L6; public/dev L6 entry, doll, hide, detector/reader, flashlight, DJ/tunnel, return. Reelle reserved teleports kræver Roblox-clienttest.
- **Status:** fire fraværende klienter **gennemført tidligere**; tre disabled instanser **beholdes** — understøttet eller endnu uverificeret authoring/migration under bevaringsmandatet; Disabled alene er ikke slettebevis; eventuel pensionering kræver særskilt workflowvalg og de angivne porte.

## C04 – private literals og lokal helper

- **Præcise steder:** `StarterPlayer/StarterCharacter/Animate.LocalScript.lua:594 origRoll, :863 climbFudge`; `StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua:25–27 MAXIMUM_RANGE/ACCURACY_DEGREES/DISTANCE_NOISE, :30 CD_SIGNAL_RANGE, :33 ROOM_BLINK_RATE, :44–45 MUTED/AMBER, :48 DANGER`; `Level 3 Table Hiding Client:382 HIDDEN_TEXT`; `Round Exit Client:55 HINT_HEIGHT`; `ReplicatedStorage/RoundHud.ModuleScript.lua:1085 TOUCH_LANE_X/TOUCH_LANE_Y`. Loading's tidligere`:638–640 announced()` er nu`:724–726` og **beholdes**.
- **Handling/bevis:** fjern kun de øvrige identificerede private deklarationer. `announced` er blevet aktiv i samtidig owner-kode: `levelWorlds():728` kalder den og `coverRound():752` bruger resultatet til aktiv round-prefetch. Den gamle helper-removal og sammensatte Loading install-unit er ugyldige; ingen rebase/fjernelse udføres. Øvrige symboler har ingen læsninger uden for definition; initializers er literals/rene eksisterende opslag, uden synlig objektkonstruktion eller require. Begge `TOUCH_LANE_X` og `TOUCH_LANE_Y` er ulæste; tidligere Y-caller-antagelse er afkræftet. Aktive `touchLane`/`placeDetector` statements bevares præcist. UIStyle.Color er en plain table uden metatable/mutation i den fulde aktuelle moduleclosure.
- **Dependencies:** private lexical bindings, ingen remotes/attributes/API fjernes; reader, hiding, exit, detector-lane, animation og loading-successors bliver stående. Historiske tools/sourcepacks er ikke ændringsmål.
- **Risiko/gevinst:** lav; mindre støj og små ubrugte tabeller; ingen målt runtimegevinst. Multiple-assignment og nabokode kræver præcis diff.
- **Før/efter-port:** symbol/initializer-review af hele definitionens lexical closure; compile alle berørte sources; eksisterende RoundHud/UIRegression/controller/B6-B7-kontrakter før/efter. Hvis ændringen udvides til et runtimeflow, kræves idle/run/climb, L3 reader/hide/upgrade, exit keyboard/touch/gamepad, touch lane og loading failure/ENTER ANYWAY i isoleret Studio-test.
- **Faktiske forberedte porte:** alle seks filer O0/O1 compile; actual Animate weighted/step/tool cleanup, current cover tree og helper closure; RoundHud185/shared387+74 og B6/B7 exit+hiding92 før/efter PASS. Hiding/exit/RoundHud har også O1 canonical binary identity; der påstås ikke compileridentity for de øvrige helperændringer.
- **Status:** Loading `announced` **beholdes**; gamle Loading-kandidater er ugyldige. Øvrige private kandidater **afventer test/Studio**: den tidligere ejer-Play-afvisning er historisk; nu mangler kandidaternes egne friske native reconcile/CAS/manifest og installerede full/TouchTarget/lobby-porte ved root. Samtidige ejersessioner og deres mode bevares. [Review med stale-baseline warning](CLIENT_LOCALS_REVIEW.md) og [manifest med ugyldig Loading-status](remaining-clients-proposals.json) bevarer den historiske proof. Ingen productionændring udført.
- **Fail-closed authoringport:** `prepare_client_locals.py` afviser nu aktiv/referenceændret `announced` før enhver prepared artifact/manifestskrivning. Actual CLI afvist ved caller`:728`;59 prepared filer, inventory, raw receipts og begge owner-kilder byte-uændrede. Historisk uncalled helper accepteres; ny call/alias/dublet/ændret definition afvises i [preflight receipt](client-loading-preflight-gate.json). Proof-blobs er ikke rettet eller regenereret.

## C05 – UIRegression private dead definitions

- **Steder:** `ReplicatedStorage/UIRegression.ModuleScript.lua`: `setLongDispatchCue:1253–1265`; `BRIEFING_STRESS_CORPUS:4152–4161`; `BRIEFING_CONTROL_CAPTIONS:4166–4171`; `BRIEFING_CONTROL_ORDER:4172`; `BRIEFING_LANDSCAPE_ROWS:4178–4185`; `briefingDevices:4187–4196`; `analyticalOverlap:4210–4213`; `BRIEFING_EXCLUSION_VIEWPORTS:4262–4265`; `DEV_CAPTION_KEYS:4273–4283`; `DEV_EYEBROW_BASE/KEYBOARD:4284–4285`; `DEV_NOCLIP_KEYBOARD/TOUCH:4286–4287`; stale caller-comment `:2589`.
- **Handling/bevis:** fjern kun disse private definitionsblokke og ret den ene stale kommentar. Aktuel repositorysøgning finder kun definitions/transitive dead uses og historisk dokumentation; ingen public/tools-caller. `briefingDevices` er eneste bruger af LANDSCAPE_ROWS; BASE bruges kun af dead KEYBOARD. Initializers er literal tables/strings; uncalled bodies har ingen initializer-sideeffects.
- **Dependencies:** **bevar** `LONG_DISPATCH_CUE:1251` (aktive borrow/residue-callers), `MODAL_DEVICES`, alle offentlige UIRegression/Fit-metoder, aliases og RunAll. Relevante tools: `test_ui_regression_shared`, `test_round_hud_shared` og manuelle UIRegression-lanes.
- **Risiko/gevinst:** lav; QA-script bliver kortere og allokerer færre ubrugte datatabeller. Ingen performancepåstand. Source-section extraction i tools kræver kontrol.
- **Før/efter-port:** compile hele modul; eksisterende UIRegression shared og RoundHud-checks (baseline ovenfor PASS); sammenlign public-method names/lane-binding og aktive sections. Native RoundHudMatrix/RunAll kræves for en eventuel større authoringomskrivning; de er ikke kørt her.
- **Historisk native baseline og forberedt kandidat:** Den oprindelige RunAllSummary havde935 checks/21 scenarios med51 failures (50 shared matrix, én shared-objective). N01 retter dokumenteret native glyph-coupling og QA-fixturekontrakter; afsluttende authoritative full har0 failures/all21 scenarios og separat TouchTarget261/0 med exact source/editor og attr/lock restoration. Ved dette forberedelsestrin var C05's definitions endnu ikke fjernet; de efterfølgende isolation-/install-porte står nedenfor. Temp-kandidaten fra installeret SHA419a7e3e… fjerner13 private definitions/73 linjer/2.823 bytes, bevarer102 named Fit/internal/UIRegression-declaration signatures, alle30 UIRegression-exports og alle øvrige statements. Den bevarer begge shared margin-callers og owned per-device reset; O0 compiler og shared105 PASS. `C05-prepared.json` og `.git/mongotv-cleanup-20261009/client-before/N01/UIRegression.C05.candidate.lua` bevarer beviset.
- **Isolerede native porte:** `B07-C05-full.json` har0/all21/shared730; `B07-C05-touch.json` har261/0. Begge entire compact-reports er byte-identiske med N01's authoritative før-reports. Alle30 native public exports har identiske keys/type/arity/variadic flags; originale Source/editor uændrede, workspace/player/lock drift[] og probes destrueret. `C05-results.md` bevarer receipt-navnenes historiske B07-prefix; cleanup-batchen er B08.
- **Installeret efter-port:** `B08-C05-native-install.json` beviser exact419→b57/editorSource-parity; manifest opdateret. Frisk Play `B08-after-full.json` har0/all21/shared730 og `B08-after-touch.json` har261/0. Entire compact-reports og alle30 public API rows er identiske med før; attr/lock drift[] og Source/editor uændrede under begge tests. Rollback-original `.git/mongotv-cleanup-20261009/client-before/N01/UIRegression.C05.before.lua`.
- **Status:** **gennemført**, lokal commit `1dd48870`; alle13 private definitions og stale kommentar er ryddet med før/isolated/installeret-efter porte. Ingen aktiv public authoringmetode eller gameplayfeature fjernet.

## C06 – KEYS og no-op preview-special-case

- **Steder:** `StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua:247–248 KEYS`; `Level4PreviewPrompt.LocalScript.lua:19–23` special-user branch.
- **Handling/bevis:** fjern KEYS-table (ingen læsninger; TOPICS har inline strings) og kun nil→nil-tildelingerne med stale ZenMeister-kommentar. PROMPTS indeholder kun Level4DeveloperPreviewPrompt/ReturnPrompt fra starten; ingen kode kan tilføje L6-keys før branchen.
- **Dependencies:** bevar HELP/TOPICS/touch-copy, DevAccess public L5/L6-politik, L4 cosmetic filter og workspace DescendantAdded watcher. Ingen active remote/attribute fjernes.
- **Risiko/gevinst:** lav; mindre dead/no-op-kode og én ubrugt table per klient. Ingen measured performancegevinst.
- **Før/efter-port:** compile begge O0/O1; private initializer/PROMPTS closure. Actual whole preview script testes ordinary/special/dev/missing/error/truthy, initial/late/re-enabled L4 og publicL5/L6. Actual current whole guide kører PC/touch10 topics og4 replay pages/skip/reentry/modal cleanup. Den tidligere stale guide-suite er nu erstattet af T09; den nye133-check suite og6 negative fixtures passer på begge immutable C06 inputs. C21 input-focus bug og C22 lille Skip-target reproduceres ens før/efter og forbliver urørte; de er ikke skjult af cleanup-porten.
- **Status:** **afventer test/Studio**: temp-only lokale porte bestået; den tidligere ejer-Play-afvisning er historisk. Root skal stadig udføre kandidatens egne friske native CAS/manifest/installerede efter-porte; samtidige ejersessioner og deres mode bevares. [Review/closure](CLIENT_LOCALS_REVIEW.md), [exact manifest](remaining-clients-proposals.json), [T09 paired receipt](client-local-T09-paired.json). Ingen produktion ændret.

## C07 – GUI-returbindinger

- **Steder:** `ReplicatedFirst/Lobby Loading Screen.LocalScript.lua:59 kicker, :89 tip` (tidligere`:62/:92`); `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua:276 shopButtonRing`.
- **Handling/bevis:** ændr kun `local name = call(...)` til samme `call(...)`. `label:46–59` bygger/parent'er TextLabel; `ZyntraStore.outline:72` bygger UIStroke. Ingen binding læses senere, men kaldet har nødvendig synlig sideeffect.
- **Dependencies:** Kicker/Tip labels, shop-knappens stroke, layout/hover/visibility og store UI. Ingen API/remote fjernes.
- **Risiko/gevinst:** lav ved binding-only; høj ved linje-/kaldsletning. Ren læsbarhedsgevinst.
- **Før/efter-port:** compile; kald og argumenter token-identiske; loading Kicker/Tip samt shop outline visible-tree/authoring checks før/efter i keyboard/touch state.
- **Faktiske porte:** O0/O1 compile; actual before/candidate loading og store tree snapshots er identiske PC/touch; Kicker/Tip constructors og alle tre shop strokes beholdes. Actual store777 kontrakt PASS før/efter. Negative controls, der sletter Kicker-call eller accent outline-call, fejler som forventet.
- **Status:** **afventer test/Studio/reconcile**: Kicker/Tip-bindinger og deres eksakte constructorcalls består i owner-koden, men gammelt Loading førhash/helkildekandidat matcher ikke længere. Den gamle C04/C07-unit må ikke installeres; ny C07-only kandidat fra frisk native baseline og egne before/after gates er stadig nødvendig; Play-stoppet er historisk, og samtidige ejersessioner/deres mode bevares. Store-kandidaten er separat og uændret. Ingen constructor slettes; [Review](CLIENT_LOCALS_REVIEW.md) og [manifest](remaining-clients-proposals.json) markerer stale Loading.

## C08 – gammel kommenteret jumpscare

- **Sted:** `StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua:15–28`.
- **Handling/bevis:** fjern kun `--[[ LEGACY IMAGE JUMPSCARE ... ]]`; alle executable statements efter kommentarstripping skal være identiske. Hele filens aktive camera/capture/fade/controls/remote/respawn-lifecycle bliver stående. Git og saved before-source opretholder rollback.
- **Dependencies:** aktive Remotes.Jumpscare, EntityKillCamera renderstep, PlayerModule controls, fade/capture records; legacyImageScare er kun kommentartekst og ingen initializer. Referencer er audit/historik.
- **Risiko/gevinst:** runtime ingen; mindre støj, ingen FPS/memorypåstand.
- **Før/efter-port:** hash før-source; exact comment-only patch/CAS; compile; executable token/statement parity. Ingen gameplaytest kræves alene for denne kommentarændring.
- **Udført repo-trial:** den første fjernelse blev straks rullet tilbage, da en absolut `--binary -g0` byteidentitetsport fejlede. Aktuel Luau serialiserer `Proto.linedefined` også med debug=0. Ved genprøven er O0/O1 text-dumps med constants byte-identiske; fuld bytecode14/type3 parser bevarer alle bytes undtagen de 13 function-definition line-varints og deres enclosing proto-size, og de kanoniserede binaries er byte-identiske. 14 function protos, top-level line1 uændret, de øvrige definitioner rykkes præcis 14 linjer. En særskilt kandidat, som udskifter kommentarindholdet med 14 blanke linjer, giver fuld rå binaryidentitet ved både O0/O1. Officielt [serializer-layout](https://github.com/luau-lang/luau/blob/0.737/Bytecode/src/BytecodeBuilder.cpp#L912) og [loader-layout](https://github.com/luau-lang/luau/blob/0.737/VM/src/lvmload.cpp#L635) blev kontrolleret for det konkrete metadatafelt.
- **Resultat:** B02 fjerner 461 bytes/14 kommentarlinjer; exact aktive prefix/suffix bevaret. Før SHA256 `07baa4a3ae035615dacb67da55ec197cfd4a09f6bf7071280f3685b653f97f88`; efter `7e5cedc84631a6af3f7edc126cb6775c9c498f42e851484c4980c3a3a6846a88`. `git diff --check` PASS, ingen aktive references til de kommenterede symboler/assets. Root har rapporteret native Source/editor CAS install og opdateret manifest; efter-smoke: 68 preload assets, 0 failed, levende karakter med Health100 og kun tidligere observeret audio-approval rejection. Root's B02-native-install/smoke indeholder de konkrete native receipts.
- **Rollback/evidens:** `.git/mongotv-cleanup-20261009/client-before/JumpscareUI.LocalScript.lua` og `verify-c08.py` med rå bytecode/text-dumps; detaljer i `artifacts/cleanup-20261009/C08-candidate.json`. Første trial var en testportafvisning pga forventet debuglinjemetadata, ikke en gameplayregression.
- **Reproducerbar check:** `python artifacts/cleanup-20261009/verify_C08.py --compiler C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe` PASS. Verifier læser native-originalens lokale checkpoint uden at kopiere fuld before-source ind i tracked artifacts; `--before` kan pege på en anden gendannet original. Kun automatisk opryddede temporary compiler-inputs skrives; ingen projekt-/manifest-/Studio-mutation. `--json` skriver fuld struktureret evidens til stdout.
- **Status:** **gennemført**; root håndterer scoped commit/evidence. Ingen publicering.

## C09 – partial-stream shop collect

- **Sted:** `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua:688–703 collect`, `:722–747 Heartbeat scan/round guards`, `:756–758 bob loop`.
- **Handling/bevis:** samtidig ejer-/developerændring har allerede erstattet incomplete-model scans per frame med mindst0.5s mellem retries. Første/ny model collect sker stadig straks; InRound/RoundActive returnerer før modelopslag/scan og restore'er aktiv bob, med scanElapsed=.5 til hurtig incomplete-retry efter return. Genimplementér ikke denne rettelse. Behovet for late replication består. En separat stream-lifecycle-hypotese består: #boxes tæller stale parentless records; når den gamle count er ShopItemCount, er der ingen descendant-invalidation til at opfange replacement-parts. Den aktive bob-loop har ingen Parent-guard, mens restore har.
- **Dependencies:** server LobbyShopDisplay stamped ShopItemCount/ShopBobOrigin/ShopBobPhase, ServerLobby.ZyntraShopDisplay, prompts/purchase, accessibility, model/part stream lifecycle. Origin må ikke recaptures fra bobbet CFrame.
- **Risiko/gevinst:** mellem for yderligere cache-invalidation; origin må fortsat komme fra serverens ShopBobOrigin, ikke aktuel bobbet CFrame. Server amplitude.35/period3.4, demo/purchase/events er uændrede i ejerens diff. Færre potentielle scans følger source-guard, men ingen målt FPS/CPU/MB-gevinst påstås.
- **Før/efter-port:** native model-before-parts→late8, prolonged1/8 med scan-count højst2 retries/s, full8→stream-out1→newInstance tilbage, modeldestroy/rebuild, roundentry/return og begge accessibility flags. Kontroller authored origins/restoration, ingen stale-part CFrame-fejl, demo/purchase-prompts; mål collect-count/CPU ved samme scene/FPS/playercount. Ny guarded native parity for ejerens ændring mangler i denne delrapport.
- **Status:** **beholdes**: bounded retry og round-guard er allerede implementeret samtidigt, uden cleanup-kredit. Native/streaming/performanceverifikation og separat invalidation-kandidat **afventer test**; ingen runtime-rewrite udført her.

## C10 – statisk RoundHud rendering

- **Steder:** `ReplicatedStorage/RoundHud.ModuleScript.lua:716–790 objective, :955–1017 feed, :1331–1358 refresh/Heartbeat`; `StarterPlayer/StarterPlayerScripts/Level 2 Objective UI.LocalScript.lua:24–34,46–53`.
- **Handling/bevis:** semantic dirty-render kandidat; aktuelle .1s og .22s polls genrender samme state. Bevar compass/timers/suppression/readiness og watched target binding.
- **Dependencies:** all-level objective senders, L2 InRound/SelectedLevel/Spectating/Health/Escaped, RoundStatus/TeamObjectives, UIDevice modal/layout, 4s feed expiry, 3.5s caption, detector attention og live compass.
- **Risiko/gevinst:** mellem; potentielt færre propertywrites/layouts, ingen målt gevinst.
- **Før/efter-port:** eksisterende shared baseline PASS; native bodyRoundHudMatrix, alle level transitions, late humanoid, spectate-target dead/escaped/disconnect, expiries, modal/touch rotations, attention resume og moving compass. Mål renders/propertywrites/frame CPU ved samme scene.
- **Status:** **afventer test**.

## C11 – redundant flashlight profile apply

- **Sted:** `StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua:134–144`.
- **Handling/bevis:** tre mulige apply-calls ved rebuild/to normale framecalls består. Reducér til én efter valide camera/mount og rebuild, uden at springe profile/upgradechange over. Profile-keycache reducerer writes allerede.
- **Dependencies:** FlashlightProfiles, buildMount/lastBeamProfile, camera replace, character lifecycle, server FlashlightSync og own/mate visual state.
- **Risiko/gevinst:** lav men runtimeændring; færre opslag/key-builds, ingen målt gevinst.
- **Før/efter-port:** initial mount, respawn, camera replacement, upgrade/L3-profile og on/off; mål callcount ved samme scenario; eksisterende flashlight contracts plus kontrolleret native trial.
- **Status:** **afventer test**.

## C12 – off-flashlight aim/raycast

- **Sted:** samme flashlight renderstep `:134–199`.
- **Handling/bevis:** aim/math/filter/ray/mount CFrame sker også off. Kandidat: gate kun positionering, behold mount/profile/replicated-self suppression; reset aimCF ved aktivering.
- **Dependencies:** self server-mount arriving late, replicated Lights disable loop `:177–188`, camera/character and under-table final camera, aim remote 15Hz.
- **Risiko/gevinst:** mellem; potentielt færre rays off, men double lights/stale first-frame kan introduceres.
- **Før/efter-port:** off lobby/round ray counter, toggle ved væg, L3 hide, late self mount, replace camera/character, network aim; visuel parity og measured CPU ved samme scene.
- **Status:** **afventer test**.

## C13 – flashlight widget unchanged writes

- **Steder:** `FlashlightController:287–329 paintWidget`, `:765–823 heartbeat/widget caller`.
- **Handling/bevis:** Visible/text/color/segments skrives igen ved uændret tuple. Spectating-keycap har allerede én cache. Memoize kun synlig widgettuple, ikke drain/integrator.
- **Dependencies:** battery/upgrade/mode, Framewisp template roots, ShopBinder/RoundHud/UIDevice, touch light-cell og modal/spectate state.
- **Risiko/gevinst:** lav/mellem; potentiale færre propertywrites, theme/layout invalidation skal overleve.
- **Før/efter-port:** full→empty/recharge, modes/thresholds, upgrade, touch/keyboard rotate, hidden/resume/spectate; samme scenario propertywrite/CPU måling.
- **Status:** **afventer test**.

## C14 – teammate shaft rays

- **Sted:** `FlashlightController:706–742 mateBeams Heartbeat`.
- **Handling/bevis:** ray per visible lit teammate shaft per frame består; ingen leak påvist, ancestry cleanup eksisterer. Behold feature; profilér før eventuel distance/FOV culling af decoration.
- **Dependencies:** replicated FlashlightOn/FlashlightFocused/Health, teammate character lifecycle, SpectateTargetUserId, SpotLight, shaft/lens/endpoints.
- **Risiko/gevinst:** mellem; popping/visuelle huller. Gevinst ukendt uden profile.
- **Før/efter-port:** seks spillere alle lights, nær/fjern, stream-out, hurtig camera-turn, vægendpoint, toggles; ray/CPU før/efter og visual parity.
- **Status:** **beholdes** indtil profiling/test viser grundlag.

## C15 – DJ JSON decode-cache

- **Sted:** `StarterPlayer/StarterPlayerScripts/Lobby DJ Client.LocalScript.lua:24–33 tracks`, `:143–156 party Heartbeat`.
- **Handling/bevis:** source-hypotesen er løst i samtidig ejer-/developerarbejde: tracks() lazy-cacher den eksakte LobbyDJTracks raw attribute og decoder kun ved ændring. Manglende initialnil returnerer empty uden decode; malformed/non-table JSON cacher empty indtil raw ændres. Alle tre aktuelle consumers (audio, lights, booth) læser alene returtable; GUI's senere local trackList shadow ændrer ikke cache-binding. Party-lights kontrollerer nu ReservedRoundServer/InRound før tracks() og restore'er aktive lamper én gang før return. Genimplementér ikke cache/roundguard.
- **Dependencies:** Lobby DJ server, LobbyDJTracks/LobbyDJTrack/LobbyDJStartedAt/LobbyDJBy, booth/UI/party palette og sound tracks().
- **Risiko/gevinst:** lav for bevaret cache; consumers må fortsat ikke mutere den delte returtable. Source viser ændringsafhængig decode; målt CPU/FPS/hukommelse og faktisk native flow er ikke undersøgt her.
- **Før/efter-port:** native missing/invalid→valid replacement, repeated identical invalidraw, valid JSON primitive→empty, track switch/STOP, ordinary/team panels, lights/ReduceFlashing; round/reserved entry restore af exact authored Color/Brightness og lobby return. Instrumentér decode-count i samme20Hz scenario og mål same-scene CPU. Ny Source/editor/manifest-parity for ejerens ændring mangler i denne delrapport.
- **Status:** **beholdes**: cache og tidlig round-guard er allerede implementeret samtidigt, uden cleanup-kredit. Verifikation **afventer test**; ingen runtimeændring udført her.

## C16 – DJ streamed lights

- **Sted:** `Lobby DJ Client:120–140 collect/restore`, `:157–175 party update`.
- **Handling/bevis:** samme-model lampsFor-cache returnerer stadig uden late-descendant capture. Den samtidige C15 roundguard løser ikke dette. Kandidat til model-owned add/remove observers og exact base restoration.
- **Dependencies:** LobbyReimaginedPreview.Ready, Light.Enabled/Brightness/Color, Lamp parenting/position, ceiling/gate flicker controllers og accessibility ownership.
- **Risiko/gevinst:** mellem; correctness af late stream samt nødvendigt restore. Ingen målt performancegevinst.
- **Før/efter-port:** partial lobby loaded ved PLAY, traverse/stream-out/in, STOP, normal flicker og ReduceFlashing; kontrollér base light values før/efter.
- **Status:** **afventer test**.

## C17 – DJ audio følger Playground

- **Sted:** `Lobby DJ Client:41–44 eligible`, `:67–104 applyTrack/listeners`; `Level 6 Playground Client.LocalScript.lua:1021–1022`.
- **Handling/bevis:** eligible mangler stadig Level6PlaygroundPreview-guard og listener efter den samtidige C15 ændring; direkte SoundService sound bliver ikke ducked gennem ZyntraLobbyMusic. restore har previewguard, men on-stien har ikke. Problemhypotese består, ikke live reproduceret her.
- **Dependencies:** LobbyDJ sound/normal lobby SoundGroup, LobbyMusicEnabled/InRound/Level6PlaygroundPreview, Playground score/music lifecycle.
- **Risiko/gevinst:** mellem; lydcorrectness, race med gruppevolumen. Ingen feature removal.
- **Før/efter-port:** DJ→public L6→lobby, STOP/track change inde i L6, settings toggle, ordinary/team accounts, L5/round entry; kontroller begge sound owners og restoration.
- **Status:** **afventer test**.

## C18 – DJ Loaded wait

- **Sted:** `Lobby DJ Client:79–85`.
- **Handling/bevis:** task.spawn+Sound.Loaded:Wait uden timeout/generation består efter den samtidige C15 ændring; gentagne applyTrack kan skabe waits ved failed asset. Bounded cancellable single-owner resync er kandidat.
- **Dependencies:** SoundId/IsLoaded/TimeLength/started server clock; STOP/track replacement, Sound.Loaded listeners og sound lifetime.
- **Risiko/gevinst:** lav/mellem; forebygger stalled tasks, men sync må ikke brydes. Faktisk leak/memory er ikke målt.
- **Før/efter-port:** valid track synced på to clients, delayed/failing asset, rapid play-stop-play/metadata changes; task/wait ownership og TimePosition parity.
- **Status:** **afventer test**.

## C19 – L5 roll-sound cleanup

- **Sted:** `StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua:822–889`.
- **Handling/bevis:** rolling weak-key table og looped ball sound består; `:840–842` off/missing model/root/humanoid continue før roll cleanup. Ny ceiling-code løser ikke dette. Kandidat: explicit stop/destroy/clear ved exit/model change/missing char, genopret ved reentry.
- **Dependencies:** Level5VoidRound, Level5 authored MODEL_NAME/Balls, l5_ball_roll/hit clips, root velocity/distance, server audio event/death, roll fade ved near→far.
- **Risiko/gevinst:** lav/mellem; correctness/lifecycle, ikke målbar gevinst uden test.
- **Før/efter-port:** kick ball før exit while map retained, death/respawn, other-level/reentry, ball removal; ingen playing roll efter exit, ingen duplicate sounds ved reentry.
- **Status:** **afventer test**.

## C20 – L2 flicker cancellation

- **Sted:** `StarterPlayer/StarterPlayerScripts/Level2PoolroomsPresentation.LocalScript.lua:142–158 releaseGrade`, `:216–242 flickerEpisode`, `:257–272 thread/stop`, `:313–328 listeners`.
- **Handling/bevis:** grade-check kun ved episode-start; post-yield skriver lys efter exit. releaseGrade/CharacterRemoving cancellerer ikke eksisterende episode. Candidate epoch/owned cancellation plus precise base restore/restart.
- **Dependencies:** L2 map Lights holder.L2NFlicker/BaseBrightness, grade effects ownership, ReduceFlashing (nil treated reduced), tween/thread table og stream removal.
- **Risiko/gevinst:** mellem; et halvfærdigt fix kan efterlade lys slukket eller restore forkert base.
- **Før/efter-port:** exit/death mid-outage, ReduceFlashing mid-episode, reentry/new character, model/holder stream-out; verify brightness restore, tween/task cancellation og ny entry flicker.
- **Status:** **afventer test**.

## C21 – WELCOME chat/text input

- **Sted:** `First Entry Guide:234–240 InputBegan`.
- **Handling/bevis:** callback ignorerer processed og focused TextBox; Space/Return/arrows stepper WELCOME. Add scoped navigation guards while retaining A/B and Next/Skip.
- **Dependencies:** welcome `open/page/connections/close`, UserInputService, chat/core GUI processed routing, gamepad focus og gui.Page test seam.
- **Risiko/gevinst:** lav/mellem correctness; processed guard må ikke sluge selected gamepad button.
- **Før/efter-port:** chat/TextBox spaces/arrows/Enter, keyboard nav/back, gamepad A/B, touch Next/Skip og replay i kontrolleret client.
- **Status:** **afventer test**.

## C22 – WELCOME/DJ touch targets

- **Steder:** `First Entry Guide:122–135 fit`, `:149–170 buttons`; `Lobby DJ Client:249–255,276,291–304`.
- **Handling/bevis:** WELCOME bruger allerede UIDevice.Layout og Changed; kun denne auditdetalje er stale. 620px card skalerer 50px Next til ~29px og 40px Skip til ~23px ved 390 bredde. DJ 32px Play og andre knapper bliver ligeledes små. Reflow/minimum final hitbox kandidat.
- **Dependencies:** UIDevice safe/modal space, UIScale, every welcome page, long DJ titles/scroll, hybrid input og notch/topbar insets.
- **Risiko/gevinst:** mellem; usabilityforbedring, layout/text må ikke croppes. Ingen feature removal.
- **Før/efter-port:** actual final bounds+tap-tests ved 390×844,568×320,844×390,768×1024, safe inset/hybrid; alle pages/long titles.
- **Status:** **afventer test**; delvist stale årsagsbeskrivelse registreret.

## C23 – WELCOME hybrid copy

- **Sted:** `First Entry Guide:55 touch`, `:85–108 PAGES`, `:249–314 TOPICS`.
- **Handling/bevis:** TouchEnabled and not KeyboardEnabled/ForceTouchUI vælges stadig én gang; nyere Loading/Round Entry-diffs ændrer ikke denne guide-kode. UIDevice-fit changes ændrer ikke allerede byggede copy-tables. Guide venter fortsat LobbyLoadingDone før WELCOME; den nye preload/handoff ændrer derfor baseline-timing, ikke hybrid-caption-policy. Kandidat fælles caption-policy ved draw/topic og Changed.
- **Dependencies:** UIDevice layout/glyph/input heuristics, phone/tablet keyboard, ForceTouchUI og tutorial/help replay.
- **Risiko/gevinst:** lav/mellem; korrekt instructions på hybrid, men bevar keyboard/gamepad tips.
- **Før/efter-port:** phone/tablet keyboard=true, touch laptop, device switch, ForceTouchUI, replay/HELP; sammenlign fælles HUD captions. Efter owner-ændringer kræves frisk lobby loadingDone→WELCOME/HELP baseline og reserved/round suppression før eventuel guideændring; historisk T09 må ikke udlægges som test af nyt asset-preload/entryflow.
- **Status:** **afventer test**.

## C24 – WELCOME/DJ modal policy

- **Steder:** `ReplicatedStorage/UIDevice.ModuleScript.lua:1656–1659 SCREEN_OWNING_MODALS`; `First Entry Guide:210 WelcomeCardOpen`; `Lobby DJ Client:327–330 LobbyDJOpen`.
- **Handling/bevis:** flags mangler stadig i fælles modal-list, også efter de samtidige Loading/Round Entry-diffs; ingen fælles suppression. Screen-filling shade er ikke predicate integration. Eventuel registrering og standard close/suppress lifecycle kræver DJ panel-policy. Nye asset/preload-workers er aktive, ikke no-op UI-integration eller slettebevis.
- **Dependencies:** NoiseReporter movement, flashlight, RoundHud suppression/detector, store rail/chips, help/badges/daily/wheel, death/camera/round cleanup og flags/listeners.
- **Risiko/gevinst:** mellem; påvirker docking/input interoperability på tværs af UI.
- **Før/efter-port:** touch joystick/run/light, parallel modal opens, close/InRound/death/capture, camera transition; exact movement/rail restoration.
- **Status:** **beholdes** — aktuel UI/modalpolicy; ændring af DJ eller WELCOME ownership kræver særskilt produktvalg og de angivne native input/restore-porte.

## C25 – stale HELP L2 objective copy

- **Sted:** `First Entry Guide:276` TOPICS THE LEVELS Poolrooms line.
- **Handling/bevis:** siger stadig Start the pumps to open the exit; aktuelle `Level 2 Objective UI:24–25` siger Find the exit, og aktiv authored runtime har samme objective. Ret kun den verificerede spillervejledning efter mapflowet.
- **Dependencies:** Level2RoundAdapter/PoolroomsRuntime, authored exit/slide, HELP topic rendering. Ingen pump-feature/API/data fjernes.
- **Risiko/gevinst:** lav; korrekt instruktion, ingen performanceeffekt.
- **Før/efter-port:** ordinary L2 run og HELP før entry; source/touch/keyboard HELP render; active exit matching. Ingen blind massestrengreplacement.
- **Status:** **afventer test** af faktisk objective/exit-flow.

## C26 – QA aliases og stale coverage claims

- **Steder:** `UIRegression:4215 bodyBriefingFitMatrix`, `:4289 bodyBriefingExclusionMatrix`, `:4828 bodyObjectiveCornerMatrix`, `:4853 bodyDispatchCompactMatrix`.
- **Handling/bevis:** alle delegerer stadig til `Fit.bodyRoundHudMatrix`; RunAll udfører shared lane én gang. Public aliases har authoring-callers og må bevares. Ret kommentarer til den coverage der faktisk udføres; fjern ikke aliases.
- **Dependencies:** public BriefingFit/BriefingExclusion/ObjectiveCorner/DispatchCompact methods, Fit.lane token/borrow contracts, manual QA/tools, same pass/fail outputs. Native Welcome/DJ er ikke testet af disse aliaser.
- **Risiko/gevinst:** lav som comment-only, mellem ved API-removal. Klarere QA-dækning.
- **Før/efter-port:** public alias/function bodies token-identiske; compile og UIRegression shared baseline/after; samme lane maps/pass-fail. Ingen ny gameplaytest for kommentar-only correction.
- **Faktiske porte:** historisk temp proposal og S15 installeret comment-only port har197 compiler functions med identisk O0/O1 canonical binary og instruction/constant dumps; kun Proto.linedefined-varints og enclosing Proto-size metadata ændres. S15 fjernede7195 kommentarbytes gennem ti reversible exact anchors med frisk native Source/editor/identity/property/attribute/tag-CAS, verificeret eksport,212 originalguards og current UIRegression105 PASS før/kandidat samt installeret local contract. Alle executable bytes, aliases/public bodies, lane maps og DispatchReference metadata er bevaret. Ingen legacy briefing/Welcome/DJ eller ny real-UI/gameplay/performancecoverage opfindes.
- **Status:** **gennemført** — S15 lokal commit `920abdeeb07dbf6729c48f980765b96ec82b06eb`; faktisk scoped native CAS/eksport/manifest/installeret contract og efterparity PASS. Public aliases **beholdes**. Linjepositionerne ovenfor er historiske før-positioner; de samme funktioner/entrypoints er bevaret. Historiske [review](CLIENT_LOCALS_REVIEW.md), [compiler-manifest](remaining-clients-proposals.json) og readonly runner bevares; [faktisk S15 receipt](c26-comments-native-v2/c26-comments-source-install-v1/result.json) og [snævert scope/reproduktion](c26-comments-native-v2/REVIEW.md) registrerer afslutningen.

## C27 – ShopData global pending-clear

- **Sted:** `ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua:524–532 profileChanged callback`.
- **Handling/bevis:** næste profile-push clearer fortsat alle action/product-receipt pending entries uden operation-korrelation. Bevidst dokumenteret eksisterende policy; ikke bevis for server-double-charge. Candidate per-operation ack kræver protokol/design review.
- **Dependencies:** ShopData.start/pending/robux, ProfileChanged server, purchase/product/pass callbacks, ProtectionClient session/revision, receipt/item/reentry operation semantics og timeout.
- **Risiko/gevinst:** mellem/høj; payment UI/protocol kan låses eller reenable forkert. Autoritative entitlements/receipts må bevares.
- **Før/efter-port:** to token actions, unrelated push, delayed receipt, failed/duplicate request, commit-then-error, refund retries, disconnect/reconnect og pass ownership; core fake-store fixtures før redesign plus native UI.
- **Status:** **beholdes** — aktuel global pending-clear-policy; ændring kræver særskilt produkt-/protokolvalg og de angivne økonomi-/native UI-porte; ingen quick-delete.

## C28 – Hazmat body rescans

- **Sted:** `StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua:13 RESCAN_INTERVAL=.2`, `:226–237 captureBody`, `:508 reconcile`, `:532–540 renderstep`.
- **Handling/bevis:** 5Hz body capture består og løser late accessories/rig replication. Candidate dirty descendants/cache kun efter profilering. Client pose transfer for Motor6D/AnimationConstraint er aktiv.
- **Dependencies:** originals/transparency attributes, ZyntraSkins/visual templates, demo wardrobes, late accessories, blocked/pending states, respawn/restore og camera culling.
- **Risiko/gevinst:** mellem; restore/late rig kan ødelægges. Ukendt gevinst, ingen leak bevist.
- **Før/efter-port:** R6/R15/current constraint rigs, late accessory, skins/demo, streamed teammate, respawn/restore; samme population scan-count/CPU før/efter.
- **Status:** **beholdes** indtil profiling/test.

## C29 – per-step subject scans

- **Steder:** `StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua:168–230 PreSimulation`; `Lobby DJ Client:199–233 Stepped`.
- **Handling/bevis:** Players:GetPlayers arrays per step består; L3 seen-table/eligibility/fading pose er aktiv. Den samtidige C15 guard gælder party Heartbeat, ikke Stepped pose-loop. Cache kun active/fading subjects efter måling; nødvendige joint writes beholdes.
- **Dependencies:** player/character lifecycle, L3 hiding/crouch/track readiness, DJMode, Motor6D/AnimationConstraint/Animator, fade/cleanup og streaming.
- **Risiko/gevinst:** mellem; remote-player poses og restore kan regrediere. Ukendt CPUgevinst.
- **Før/efter-port:** 1/6/20 players, hide→unhide, DJ toggle, disconnect, respawn, rigs og streaming; pose parity og same-scene CPU.
- **Status:** **beholdes** indtil profiling/test.

## C30 – stray/local agent state

- **Steder:** tidligere `StarterPlayer/StarterPlayerScripts/6430` er fraværende; `.claude-flow/neural/stats.json` og `.claude-flow/policy/state.json` under samme root eksisterer kun lokalt.
- **Handling/bevis:** markér tomfilfjernelse allerede løst; ingen native/script/manifest entries for JSON. Git ls-files har ingen statefiler; .gitignore:220 ignorerer hele .claude-flow. Stats/policy har lokal agenthistorik og audit receipts, ikke spillersave/Roblox receipts.
- **Dependencies:** lokal Ruflo/agenttoolstate; ingen konkrete projektreferences fundet. Tool bootstrap/root tooling vurderer retirement/relocation.
- **Risiko/gevinst:** runtime ingen, lokal historik kan gå tabt. Ingen tracked repo-støj tilbage.
- **Før/efter-port:** preserve recoverable local checkpoint; runtime manifest/export class allowlist; tool bootstrap hvis relocation/sletning vælges. Slet ikke ignoreret lokal historik alene pga navn.
- **Status:** tomfil **gennemført tidligere**; ignored agentstate **beholdes** indtil tooling-/workflowvalg.

## C31 – gammel L2 Dev ESP

- **Sted:** tidligere `StarterPlayer/StarterPlayerScripts/Level 2 Pool Slide Dev ESP.LocalScript.lua` og manifest entry er fraværende.
- **Handling/bevis:** markér canonical sync removal allerede løst; genindfør ikke ESP. Historiske pool-slide fixtures/sourcepacks kan fortsat nævne det og er ikke aktive canonical importkrav.
- **Dependencies:** pensioneret Level2GeneratedWorld/second-pump attrs; aktive authored Poolrooms/slide controls og øvrige developerflows bevares.
- **Risiko/gevinst:** den tidligere sync-reintroduktionsrisiko er løst. Arkiv-/fixture-cleanup kræver værktøjsejerskab.
- **Før/efter-port:** root fresh inventory/manifest confirms absence; sync contract må ikke genskabe script. Ingen ekstra gameplayændring gennemføres for et allerede fraværende script.
- **Status:** **gennemført tidligere** i canonical repo/manifest; native absence bekræftes af root.

## Åbne beslutninger og anbefalet batchrækkefølge

1. C08 og C26 kommentar-only ændringer: exact aktive statements, compile/kontrakt; lavest risiko.
2. C04/C05/C06 samt C07 binding-only: hele private closure, initializers/callers og eksisterende meningsfulde authoring/kontraktporte; bevar alle aktive featureflows/APIer.
3. C02 object-deletion først når successor-footsteps/feed og object/manifest rollback er afprøvet.
4. C19/C20 og C17/C18 correctness/lifecycle i hver sin kontrollerede clientbatch med før/efter flow, cleanup og reentry.
5. Performance C09–C16/C28–C29 måles først ved samme scenario; manglende tests efterlader kandidaten stående.

Saml produktspørgsmål: pensionér disabled L6 Reader/Sound? Pensionér SetRunAnimation eller gem som authoringmulighed? Skal DJ booth eje skærmen? Er ShopData global pending-clear bevidst ønsket? Bevar de nu ignorerede lokale agentstatefiler med mindre værktøjsworkflowet afklares.

C08's kommentarblok og C05's13 private authoring-definitioner er fjernet i C-fundene. N01 nedenfor retter dokumenterede baselinefejl og fixturekontrakter før C05's isolerede og installerede native porte. Ingen gameplayfeature er pensioneret, og ingen performancegevinst eller offentlig Roblox-publication er påstået udført.

## N01 – native baselineport og bearing-glyph

- **Præcise steder:** `ReplicatedStorage/RoundHud.ModuleScript.lua:704 paintCompass`; `ReplicatedStorage/UIRegression.ModuleScript.lua:4387 Fit.anchorProblems`, `:4782 Fit.bodyRoundHudMatrix` og `:3351 Fit.bodyTouchTargetMatrix` shared objective-kald/setup; `tools/tests/hud_harness.luau:147/252` native text-property model og de to eksisterende shared suites. Linjer identificerer før-blokke; senere edits forskyder dem.
- **Bevis før:** root's `baseline-native-ui.json` registrerer RunAllSummary med 935 checks, 21 scenarios og 51 failures. `N01-native-gate.json` måler 11 Level1-devicecases: den aktuelle shared card har ekstra right margin 16 touch/24 PC, som `RoundHud.placeObjective` allerede reserverer; generisk legacy anchor forventede ingen ekstra margin. Safe containment og movement-zone-tests gælder stadig.
- **Runtimefejl bekræftet:** `N01-textlabel-property-probe.json` fra isolerede native TextLabels viser, at `TextScaled=true` efterfulgt af `TextWrapped=false` ender false/false, også efter wait. Omvendt rækkefølge og scaled-only ender true/true. Luau O0-dump viser, at production-multiassignment udfører scaled før wrapped. [Roblox TextLabel-dokumentation](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/TextLabel.yaml) beskriver, at TextScaled automatisk aktiverer TextWrapped. Binder er ikke årsagen: glyph-clonen har allerede fjernet FigmaFontSize, så den deferred solve guard returnerer.
- **Mindste ændring:** glyphens eksisterende TextScaled og TextWrapped sættes begge true; én glyph kan ikke danne ekstra tekstlinjer. Source template, imported slot, position, anchor, font-size constraint, readable copy floor og compass states beholdes. QA-anchor tager et optional rightInset med default0; begge shared-HUD callers angiver den nuværende16/24-reservation. TouchTargetMatrix bruger eksisterende `resetScenario(true)` før hvert devices objective-staging, så forrige fixtures PartyDownCard/modal ikke suppresses næste objective. Legacy anchor, AnchorSlack, safe containment, movement collision, hit44, text-bound assertions og native-frame resolver ændres ikke.
- **Dependencies:** Level1/3 compass state/publisher, local og spectated character origin, current camera, Binder.scaleText clone attributes, UIDevice safe frame, HUD_PC/HUD_Touch imports, objective attention/remount/resize, test borrow/restore og offentlige UIRegression-APIer. Ingen remotes, persistent attributes, spillerdata eller entitlements ændres.
- **Rollback:** alle fem før-filer med raw/LF hashes gemt i `.git/mongotv-cleanup-20261009/client-before/N01`; kilder rechecked byte-identiske umiddelbart før edit. Root alene ejer native fresh Source/editor CAS, manifest og rollback.
- **Meningsfuld testport:** den korrigerede native coupling-fixture med original runtime reproducerer fejl ved wide/tall fallback glyph `locating`; den nye anchor-contract-fixture med original UIRegression reproducerer exact-slot failure. Begge prøver bruger før-kilder i isolerede offline programs, ingen midlertidig nedskrivning af canonical production. Efter candidate: shared HUD 387 + stamina 74; UIRegression 101 (11 nye tests inkluderer forkert margin, 5px drift, safe escape, movement hit og legacy-anchor); exit 92; controller 91/touch 86/stamina 74/POV 63; basic HUD 185; compiler O0 og scoped diff-check pass. Den eksisterende borrow/error-suites anchor stub bevares for dens egen fixture; den rigtige production anchor-body måles separat. Offline placement læser production position/size-writes, mens native gate stadig skal måle faktisk engine geometry.
- **Risiko/gevinst:** lav/afgrænset correctness-fix og troværdigere QA baseline; ingen målt eller påstået performancegevinst. Hardware/input, multiplayer/streaming og ægte fonts må ikke påstås dækket af offline fixtures.
- **Native efter-resultat:** root's B06 Source/editor CAS og manifest er installeret. `B06-native-ui-after.json` viser 935 checks/21 scenarios med 2 failures; shared matrix er nu 730/0 mod baseline 730/50, lock clear og levende Health100/loadingDone. De to scenariofailures `hiding-plus-reader` og `round-win-fullscreen` skal undersøges som mulige regressioner, før batchen kan godkendes. Summary udelader rå Contract/Offscreen-detaljer; den er derfor ikke tilstrækkelig til årsagsbestemmelse.
- **Parret undersøgelse:** `run_N01_pair_probe.py pair-before` og `pair-current` stager hver sin helt ny ModuleScript (ingen clone) og bevarer eksakt live UIRegression/RoundHud instance, Source/editor og LF hash med guards før, i staging callback og efter også fejl. Temporary probe destrueres på alle paths. `CleanupScenarioPair` bruger de uændrede Scenarios setup og byte-identiske RunAll contract evaluators, original .3s settle samt egen lane/borrow/reset/restore/residue. Rå failures, rectangles, glyph flags og viewport/attribute context returneres. Begge QA-prober bruger current gameplay owner; fuld runtime-før/efter kræver frisk kontrolleret Play-fase eller isoleret place. Glyph-fix ændrer kun Chevron-ink; hiding forbids objektivet, og result-setup resetter shared HUD, men asynkron synlighed eller ændret gameplaycontext må først udelukkes ved måling.
- **Afsluttende native bevis:** Parrede scenario-probes begge0 med samme rectangles/context og intet residue; efterfølgende frisk full-suite0/all21. Separat TouchTarget fandt8 eksisterende fixture-lifecyclefailures efter første device; exact før/reset probes målte261/9 (én gammel anchor + otte missing) mod261/0, originals uændrede og flags/lock restored. Offline reset reentry før reproducerer missing, efter105 checks PASS. Efter guarded reset419-installation målte authoritative `RunAllCompact`0/all21/shared730 og separat `Compact("TouchTargetMatrix")`261/0. Begge afsluttende reports har workspace/player/lock drift[], exact Source/editor unchanged og ingen temporary probe.
- **Resultatfil/status:** `N01-candidate.json`, `N01-results.md` og `B06-final-full.json`/`B06-final-touch.json` indeholder før/efter hashes, forventede før-fejl og de fulde afsluttende reports. **Status: gennemført**, lokal commit `11faa990`; de historiske2 scenario- og8 Touch-fixturefejl er undersøgt/lukket med friske grønne native slutporte. C05 har siden bestået egne isolerede og installerede efter-porte. Ingen hardware/multiplayer/performancecheck påstås udført.
