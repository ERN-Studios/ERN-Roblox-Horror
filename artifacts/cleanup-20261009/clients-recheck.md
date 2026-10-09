# Klient/shared recheck – 2026-10-09

Denne rapport genkontrollerer C01–C31 mod de aktuelle kanoniske projektfiler. Analysen og de fire offline baseline-gates blev udført før klientændringer. Den senere godkendte C08 repo-kandidat er registreret nedenfor. Ingen Studio-kald eller start/stop er udført af denne delopgave; root ejer native compare-and-swap, manifest og Studio-tests. Eksisterende dirty `RoundUI` og manifest er bevaret.

Læst grundlag: projektets `AGENTS.md`, audit `HANDOFF.md`, `findings-index.md` og `clients-audit.md`. `graphify query` blev brugt som orientering i det eksisterende graph; grafen indeholder historiske kilder og er ikke autoritativ for dagens callers. Alle nedenstående konklusioner er genkontrolleret i aktuelle filer og relevante references. Historiske artifacts/sourcepacks er ikke behandlet som aktive runtime-callers.

## Baseline og allerede løste punkter

- Aktuelt manifest: 230 scripts (129 ModuleScript, 72 LocalScript, 29 Script) og 15 RemoteEvent-stubs. Alle 245 filer findes og matcher deres SHA256 efter CRLF→LF-normalisering. Rå diskbytes varierer på 20 filer alene på grund af CRLF. Dette beviser manifest/repo-konsistens, ikke i sig selv native parity.
- Root har oplyst korrekt PlaceId og 230 native scripts med Source/editor-enighed. Native source-sammenligningen registreres af root separat.
- C01: de tidligere driftede guide/preview/L5-kilder og DJ/Tunnel/DevESP er nu spejlet. Genimplementér ikke gammel source-sync.
- C03: de fire Studio-fraværende gamle L6-klienter er allerede ude af kanoniske roots/manifest. Disabled L6 Reader, L6 Sound og SetRunAnimation består.
- C31: den gamle L2 Pool Slide Dev ESP er allerede ude af kanoniske roots/manifest.
- C30: tom `6430` er allerede fjernet. De to lokale `.claude-flow` JSON-filer findes, men er utrackede og ignorerede af `.gitignore:220`.
- C22: auditens udsagn om direkte camera-viewport er delvist forældet: WELCOME bruger nu `UIDevice.Layout().Viewport` og `UIDevice.Changed`. Den utilstrækkelige hit-targetstørrelse efter UIScale består.

## Udførte offline baseline-checks

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
- **Handling/bevis:** behold de aktuelle native spejle; ingen genskrivning fra auditens gamle repo. Aktuel guide har WELCOME/HELP og aktiv spawn-view; public L5/L6, DJ/Tunnel/ESP står i manifest. Alle aktuelle manifesthashes passer.
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

## C03 – gamle L6-klienter og animation-patch

- **Steder:** de tidligere kanoniske `Level 6 Lighting Controller`, `Level 6 Mall Manager Visual Smoother`, `Level 6 Table Hiding Client`, `Level 6 CD Dev ESP` er allerede fraværende i roots/manifest. `StarterPlayer/StarterPlayerScripts/Level 6 Reader Client.LocalScript.lua`, `Level 6 Sound Controller.LocalScript.lua` og `StarterPlayer/StarterCharacterScripts/SetRunAnimation.LocalScript.lua` har stadig manifest `Disabled=true`, `RunContext=Legacy`.
- **Handling/bevis:** markér de fire tidligere sync-kandidater allerede løst; behold tre disabled instanser indtil konkrete retirementvalg. Disabled/navn er ikke slettebevis. SetRunAnimation ændrer run-asset til `83054249237379`, hvis genaktiveret.
- **Dependencies:** gamle Level6 server/sourcepacks/tests; aktive Playground Game/Client/DevESP/DJ skal bevares. L3's Level6BlenderRuntimeBake/Kit Metadata må ikke følge med i retirement.
- **Risiko/gevinst:** nul runtimegevinst ved disabled deletion; rollback/authoring kan brydes. Kanonisk sync genskaber allerede ikke de fire gamle klienter.
- **Før/efter-port:** migration/sourcepack-callers og full native object/property backup; ny manifest må ikke reaktivere gammel L6; public/dev L6 entry, doll, hide, detector/reader, flashlight, DJ/tunnel, return. Reelle reserved teleports kræver Roblox-clienttest.
- **Status:** fire fraværende klienter **gennemført tidligere**; tre disabled instanser **kræver afklaring**.

## C04 – private literals og lokal helper

- **Præcise steder:** `StarterPlayer/StarterCharacter/Animate.LocalScript.lua:594 origRoll, :863 climbFudge`; `StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua:25–27 MAXIMUM_RANGE/ACCURACY_DEGREES/DISTANCE_NOISE, :30 CD_SIGNAL_RANGE, :33 ROOM_BLINK_RATE, :44–45 MUTED/AMBER, :48 DANGER`; `Level 3 Table Hiding Client:382 HIDDEN_TEXT`; `Round Exit Client:55 HINT_HEIGHT`; `ReplicatedStorage/RoundHud.ModuleScript.lua:1084 TOUCH_LANE_X`; `ReplicatedFirst/Lobby Loading Screen.LocalScript.lua:638–640 announced()`.
- **Handling/bevis:** fjern kun de identificerede lokale deklarationer/helper. Alle symboler har ingen aktuelle læsninger uden for definition. `announced` er uncalled. Initializers er literals/rene eksisterende opslag; ingen synlig objektkonstruktion eller require. Ved `TOUCH_LANE_X, TOUCH_LANE_Y` bevares Y=52 og dets callers.
- **Dependencies:** private lexical bindings, ingen remotes/attributes/API fjernes; reader, hiding, exit, detector-lane, animation og loading-successors bliver stående. Historiske tools/sourcepacks er ikke ændringsmål.
- **Risiko/gevinst:** lav; mindre støj og små ubrugte tabeller; ingen målt runtimegevinst. Multiple-assignment og nabokode kræver præcis diff.
- **Før/efter-port:** symbol/initializer-review af hele definitionens lexical closure; compile alle berørte sources; eksisterende RoundHud/UIRegression/controller/B6-B7-kontrakter før/efter. Hvis ændringen udvides til et runtimeflow, kræves idle/run/climb, L3 reader/hide/upgrade, exit keyboard/touch/gamepad, touch lane og loading failure/ENTER ANYWAY i isoleret Studio-test.
- **Status:** **klar** som rent lokal cleanup efter fresh native baseline og afgrænset kontraktport; ingen ændring udført.

## C05 – UIRegression private dead definitions

- **Steder:** `ReplicatedStorage/UIRegression.ModuleScript.lua`: `setLongDispatchCue:1253–1265`; `BRIEFING_STRESS_CORPUS:4152–4161`; `BRIEFING_CONTROL_CAPTIONS:4166–4171`; `BRIEFING_CONTROL_ORDER:4172`; `BRIEFING_LANDSCAPE_ROWS:4178–4185`; `briefingDevices:4187–4196`; `analyticalOverlap:4210–4213`; `BRIEFING_EXCLUSION_VIEWPORTS:4262–4265`; `DEV_CAPTION_KEYS:4273–4283`; `DEV_EYEBROW_BASE/KEYBOARD:4284–4285`; `DEV_NOCLIP_KEYBOARD/TOUCH:4286–4287`; stale caller-comment `:2589`.
- **Handling/bevis:** fjern kun disse private definitionsblokke og ret den ene stale kommentar. Aktuel repositorysøgning finder kun definitions/transitive dead uses og historisk dokumentation; ingen public/tools-caller. `briefingDevices` er eneste bruger af LANDSCAPE_ROWS; BASE bruges kun af dead KEYBOARD. Initializers er literal tables/strings; uncalled bodies har ingen initializer-sideeffects.
- **Dependencies:** **bevar** `LONG_DISPATCH_CUE:1251` (aktive borrow/residue-callers), `MODAL_DEVICES`, alle offentlige UIRegression/Fit-metoder, aliases og RunAll. Relevante tools: `test_ui_regression_shared`, `test_round_hud_shared` og manuelle UIRegression-lanes.
- **Risiko/gevinst:** lav; QA-script bliver kortere og allokerer færre ubrugte datatabeller. Ingen performancepåstand. Source-section extraction i tools kræver kontrol.
- **Før/efter-port:** compile hele modul; eksisterende UIRegression shared og RoundHud-checks (baseline ovenfor PASS); sammenlign public-method names/lane-binding og aktive sections. Native RoundHudMatrix/RunAll kræves for en eventuel større authoringomskrivning; de er ikke kørt her.
- **Yderligere native baseline fra root:** RunAllSummary udførte 935 checks/21 scenarios med 51 eksisterende failures (50 shared matrix, én shared-objective scenario). UIRegression/C05 er ikke ændret. Isoleret C05-kandidat i `.git/mongotv-cleanup-20261009/client-before/UIRegression.C05.candidate.lua` fjerner 13 private definitions/73 linjer/2.823 bytes, bevarer 102 public Fit/UIRegression signatures og alle øvrige statements, compiler PASS og samme shared90 PASS. Kandidaten er ikke installeret. Foundation-recheck af native anchor/glyph assertions undersøges særskilt; baselinefailures må ikke blot bortforklares eller assertions tilpasses til observationer.
- **Status:** **afventer test**; cleanup pauset indtil native testgrundlaget er afklaret. Ingen production sourceændring.

## C06 – KEYS og no-op preview-special-case

- **Steder:** `StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua:247–248 KEYS`; `Level4PreviewPrompt.LocalScript.lua:19–23` special-user branch.
- **Handling/bevis:** fjern KEYS-table (ingen læsninger; TOPICS har inline strings) og kun nil→nil-tildelingerne med stale ZenMeister-kommentar. PROMPTS indeholder kun Level4DeveloperPreviewPrompt/ReturnPrompt fra starten; ingen kode kan tilføje L6-keys før branchen.
- **Dependencies:** bevar HELP/TOPICS/touch-copy, DevAccess public L5/L6-politik, L4 cosmetic filter og workspace DescendantAdded watcher. Ingen active remote/attribute fjernes.
- **Risiko/gevinst:** lav; mindre dead/no-op-kode og én ubrugt table per klient. Ingen measured performancegevinst.
- **Før/efter-port:** native CAS; compile begge; statisk PROMPTS/top-level initialization-kontrakt. Brug aktuelt guideflow; `test_first_entry_guide.py` er stale (forventer tidligere guidefeature) og må ikke omfortolkes som ny guidebug. WELCOME/HELP-topic og ordinary/dev/special-user preview-door checks hvis flowet ændres ud over no-op removal.
- **Status:** **klar** efter fresh source/afgrænset closure; ingen ændring udført.

## C07 – GUI-returbindinger

- **Steder:** `ReplicatedFirst/Lobby Loading Screen.LocalScript.lua:62 kicker, :92 tip`; `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua:276 shopButtonRing`.
- **Handling/bevis:** ændr kun `local name = call(...)` til samme `call(...)`. `label:46–59` bygger/parent'er TextLabel; `ZyntraStore.outline:72` bygger UIStroke. Ingen binding læses senere, men kaldet har nødvendig synlig sideeffect.
- **Dependencies:** Kicker/Tip labels, shop-knappens stroke, layout/hover/visibility og store UI. Ingen API/remote fjernes.
- **Risiko/gevinst:** lav ved binding-only; høj ved linje-/kaldsletning. Ren læsbarhedsgevinst.
- **Før/efter-port:** compile; kald og argumenter token-identiske; loading Kicker/Tip samt shop outline visible-tree/authoring checks før/efter i keyboard/touch state.
- **Status:** **klar** som binding-only cleanup; kald skal blive stående.

## C08 – gammel kommenteret jumpscare

- **Sted:** `StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua:15–28`.
- **Handling/bevis:** fjern kun `--[[ LEGACY IMAGE JUMPSCARE ... ]]`; alle executable statements efter kommentarstripping skal være identiske. Hele filens aktive camera/capture/fade/controls/remote/respawn-lifecycle bliver stående. Git og saved before-source opretholder rollback.
- **Dependencies:** aktive Remotes.Jumpscare, EntityKillCamera renderstep, PlayerModule controls, fade/capture records; legacyImageScare er kun kommentartekst og ingen initializer. Referencer er audit/historik.
- **Risiko/gevinst:** runtime ingen; mindre støj, ingen FPS/memorypåstand.
- **Før/efter-port:** hash før-source; exact comment-only patch/CAS; compile; executable token/statement parity. Ingen gameplaytest kræves alene for denne kommentarændring.
- **Udført repo-trial:** den første fjernelse blev straks rullet tilbage, da en absolut `--binary -g0` byteidentitetsport fejlede. Aktuel Luau serialiserer `Proto.linedefined` også med debug=0. Ved genprøven er O0/O1 text-dumps med constants byte-identiske; fuld bytecode14/type3 parser bevarer alle bytes undtagen de 13 function-definition line-varints og deres enclosing proto-size, og de kanoniserede binaries er byte-identiske. 14 function protos, top-level line0 uændret, de øvrige definitioner rykkes præcis 14 linjer. En særskilt kandidat, som udskifter kommentarindholdet med 14 blanke linjer, giver fuld rå binaryidentitet ved både O0/O1. Officielt [serializer-layout](https://github.com/luau-lang/luau/blob/0.737/Bytecode/src/BytecodeBuilder.cpp#L912) og [loader-layout](https://github.com/luau-lang/luau/blob/0.737/VM/src/lvmload.cpp#L635) blev kontrolleret for det konkrete metadatafelt.
- **Resultat:** B02 fjerner 461 bytes/14 kommentarlinjer; exact aktive prefix/suffix bevaret. Før SHA256 `07baa4a3ae035615dacb67da55ec197cfd4a09f6bf7071280f3685b653f97f88`; efter `7e5cedc84631a6af3f7edc126cb6775c9c498f42e851484c4980c3a3a6846a88`. `git diff --check` PASS, ingen aktive references til de kommenterede symboler/assets. Root har rapporteret native Source/editor CAS install og opdateret manifest; efter-smoke: 68 preload assets, 0 failed, levende karakter med Health100 og kun tidligere observeret audio-approval rejection. Root's B02-native-install/smoke indeholder de konkrete native receipts.
- **Rollback/evidens:** `.git/mongotv-cleanup-20261009/client-before/JumpscareUI.LocalScript.lua` og `verify-c08.py` med rå bytecode/text-dumps; detaljer i `artifacts/cleanup-20261009/C08-candidate.json`. Første trial var en testportafvisning pga forventet debuglinjemetadata, ikke en gameplayregression.
- **Status:** **gennemført**; root håndterer scoped commit/evidence. Ingen publicering.

## C09 – partial-stream shop collect

- **Sted:** `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua:688–705 collect, :723–739 Heartbeat`.
- **Handling/bevis:** kandidat til model-owned dirty/coalesced collect og bounded fallback. Aktuel kode kalder GetDescendants hver frame så længe #boxes<ShopItemCount, før motionAllowed. Behovet for late replication er dokumenteret og aktivt.
- **Dependencies:** server LobbyShopDisplay stamped ShopItemCount/ShopBobOrigin/ShopBobPhase, ServerLobby.ZyntraShopDisplay, prompts/purchase, accessibility, model/part stream lifecycle. Origin må ikke recaptures fra bobbet CFrame.
- **Risiko/gevinst:** mellem; mulig reduktion af scans, kræver måling. Forkert invalidation kan flytte/stivne bokse.
- **Før/efter-port:** samme scene med model-before-parts, 1/8 streamed boxes, stream-out/in, lobby→round→lobby og begge accessibility flags; mål collect-count/CPU ved samme FPS/playercount; bob og purchase-prompts. Ingen perfmåling foretaget her.
- **Status:** **afventer test**; runtime-rewrite holdes.

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

- **Sted:** `StarterPlayer/StarterPlayerScripts/Lobby DJ Client.LocalScript.lua:24–27 tracks`, `:137–145 lights Heartbeat`.
- **Handling/bevis:** JSONDecode ved hvert 20Hz light-step og andre calls består, også før off-guard. Candidate cache keyed by exact LobbyDJTracks attribute, invalid JSON→empty.
- **Dependencies:** Lobby DJ server, LobbyDJTracks/LobbyDJTrack/LobbyDJStartedAt/LobbyDJBy, booth/UI/party palette og sound tracks().
- **Risiko/gevinst:** lav; decode-count kan blive attr-change afhængig, measured CPU ukendt.
- **Før/efter-port:** missing/invalid list, replacement, track switch/STOP, ordinary/team panels, lights/ReduceFlashing; decode counter og same-scene CPU før/efter.
- **Status:** **afventer test**.

## C16 – DJ streamed lights

- **Sted:** `Lobby DJ Client:114–135 collect/restore`, `:147–164 party update`.
- **Handling/bevis:** samme-model lampsFor-cache returnerer uden late-descendant capture. Kandidat til model-owned add/remove observers og exact base restoration.
- **Dependencies:** LobbyReimaginedPreview.Ready, Light.Enabled/Brightness/Color, Lamp parenting/position, ceiling/gate flicker controllers og accessibility ownership.
- **Risiko/gevinst:** mellem; correctness af late stream samt nødvendigt restore. Ingen målt performancegevinst.
- **Før/efter-port:** partial lobby loaded ved PLAY, traverse/stream-out/in, STOP, normal flicker og ReduceFlashing; kontrollér base light values før/efter.
- **Status:** **afventer test**.

## C17 – DJ audio følger Playground

- **Sted:** `Lobby DJ Client:35–37 eligible`, `:61–98 applyTrack/listeners`; `Level 6 Playground Client.LocalScript.lua:1021–1022`.
- **Handling/bevis:** eligible mangler Level6PlaygroundPreview-guard og listener; direkte SoundService sound bliver ikke ducked gennem ZyntraLobbyMusic. restore har previewguard, men on-stien har ikke. Problemhypotese består, ikke live reproduceret her.
- **Dependencies:** LobbyDJ sound/normal lobby SoundGroup, LobbyMusicEnabled/InRound/Level6PlaygroundPreview, Playground score/music lifecycle.
- **Risiko/gevinst:** mellem; lydcorrectness, race med gruppevolumen. Ingen feature removal.
- **Før/efter-port:** DJ→public L6→lobby, STOP/track change inde i L6, settings toggle, ordinary/team accounts, L5/round entry; kontroller begge sound owners og restoration.
- **Status:** **afventer test**.

## C18 – DJ Loaded wait

- **Sted:** `Lobby DJ Client:73–79`.
- **Handling/bevis:** task.spawn+Sound.Loaded:Wait uden timeout/generation består; gentagne applyTrack kan skabe waits ved failed asset. Bounded cancellable single-owner resync er kandidat.
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
- **Handling/bevis:** TouchEnabled and not KeyboardEnabled/ForceTouchUI vælges én gang. UIDevice-fit changes ændrer ikke allerede byggede copy-tables. Kandidat fælles caption-policy ved draw/topic og Changed.
- **Dependencies:** UIDevice layout/glyph/input heuristics, phone/tablet keyboard, ForceTouchUI og tutorial/help replay.
- **Risiko/gevinst:** lav/mellem; korrekt instructions på hybrid, men bevar keyboard/gamepad tips.
- **Før/efter-port:** phone/tablet keyboard=true, touch laptop, device switch, ForceTouchUI, replay/HELP; sammenlign fælles HUD captions.
- **Status:** **afventer test**.

## C24 – WELCOME/DJ modal policy

- **Steder:** `ReplicatedStorage/UIDevice.ModuleScript.lua:1656–1659 SCREEN_OWNING_MODALS`; `First Entry Guide:210 WelcomeCardOpen`; `Lobby DJ Client:327–330 LobbyDJOpen`.
- **Handling/bevis:** flags mangler stadig i fælles modal-list; ingen fælles suppression. Screen-filling shade er ikke predicate integration. Eventuel registrering og standard close/suppress lifecycle kræver DJ panel-policy.
- **Dependencies:** NoiseReporter movement, flashlight, RoundHud suppression/detector, store rail/chips, help/badges/daily/wheel, death/camera/round cleanup og flags/listeners.
- **Risiko/gevinst:** mellem; påvirker docking/input interoperability på tværs af UI.
- **Før/efter-port:** touch joystick/run/light, parallel modal opens, close/InRound/death/capture, camera transition; exact movement/rail restoration.
- **Status:** **kræver afklaring**: DJ booth screen-owning modal eller frit developerpanel? WELCOME ownership kan behandles separat med egne tests.

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
- **Status:** **klar** for kommentar-only dokumentation; public aliases **beholdes**.

## C27 – ShopData global pending-clear

- **Sted:** `ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua:524–532 profileChanged callback`.
- **Handling/bevis:** næste profile-push clearer fortsat alle action/product-receipt pending entries uden operation-korrelation. Bevidst dokumenteret eksisterende policy; ikke bevis for server-double-charge. Candidate per-operation ack kræver protokol/design review.
- **Dependencies:** ShopData.start/pending/robux, ProfileChanged server, purchase/product/pass callbacks, ProtectionClient session/revision, receipt/item/reentry operation semantics og timeout.
- **Risiko/gevinst:** mellem/høj; payment UI/protocol kan låses eller reenable forkert. Autoritative entitlements/receipts må bevares.
- **Før/efter-port:** to token actions, unrelated push, delayed receipt, failed/duplicate request, commit-then-error, refund retries, disconnect/reconnect og pass ownership; core fake-store fixtures før redesign plus native UI.
- **Status:** **kræver afklaring** om global clear er tilsigtet; ingen quick-delete.

## C28 – Hazmat body rescans

- **Sted:** `StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua:13 RESCAN_INTERVAL=.2`, `:226–237 captureBody`, `:508 reconcile`, `:532–540 renderstep`.
- **Handling/bevis:** 5Hz body capture består og løser late accessories/rig replication. Candidate dirty descendants/cache kun efter profilering. Client pose transfer for Motor6D/AnimationConstraint er aktiv.
- **Dependencies:** originals/transparency attributes, ZyntraSkins/visual templates, demo wardrobes, late accessories, blocked/pending states, respawn/restore og camera culling.
- **Risiko/gevinst:** mellem; restore/late rig kan ødelægges. Ukendt gevinst, ingen leak bevist.
- **Før/efter-port:** R6/R15/current constraint rigs, late accessory, skins/demo, streamed teammate, respawn/restore; samme population scan-count/CPU før/efter.
- **Status:** **beholdes** indtil profiling/test.

## C29 – per-step subject scans

- **Steder:** `StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua:168–230 PreSimulation`; `Lobby DJ Client:189–223 Stepped`.
- **Handling/bevis:** Players:GetPlayers arrays per step består; L3 seen-table/eligibility/fading pose er aktiv. Cache kun active/fading subjects efter måling; nødvendige joint writes beholdes.
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

Kun C08's kommentarblok er fjernet som repo-kandidat; ingen klientfeature/runtimeomskrivning, performancegevinst eller offentlig Roblox-publication er påstået udført i denne recheck.
