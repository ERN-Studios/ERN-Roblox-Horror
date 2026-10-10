# S16 / LE-32 — Usher ulæste private felter

Status: **afventer frisk native førport, Root-installation og efterport**. Offline-parrede kontrakter og installerens negative porte passer. Ingen produktionskilde, manifest, Studio-instans, Play-tilstand, spillerdata eller authoringkilde er ændret af denne forberedelse. Root alene udfører native prober, CAS-installation, eksport og commit.

## Præcis kandidat og bevis

`ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua`; native `ServerScriptService.Level 4 Systems.Level 4 Usher Controller`, ModuleScript `1_42775`, parent `1_15624`. Før 34745 bytes / SHA `9af1a745968b95928355707aeaf81bf36b2e9495bdc589918b72bca10d6ba7e3`; efter 34659 bytes / SHA `ec4252424a0a513ca370851a5ff45b212bab4c2bfcbe20cba58c0a740a2b2a2f`. Fem substitutioner fjerner præcis 86 bytes:

- `targetReason`: privat nil-deklaration og skrivning fra det stadig aktive `reason`; ingen læsning. `reason` bruges stadig til holder/sight/finale-valget af Chase eller Stalk.
- `nextThinkAt`: privat nul-deklaration; ingen skrivning eller læsning. Den aktive Heartbeat-akkumulator og `C.ThinkSeconds` bevares.
- `stunUntil`: privat nul-deklaration og Stop-nulstilling; ingen læsning. `beamTime`, `stunCooldownUntil`, cooldown, retreat og beamer-attributter bevares.

Deklarationernes højresider er alene nil/nul; den fjernede skrivning kopierer alene en lokal værdi. Der er ingen initializer-sideeffects, krævede moduler, objektkald, forbindelser, remote-kald eller gameplay-returnværdier i fjernelserne. Ingen af felterne eksporteres eller læses af resten af modulet. Gevinsten er mindre ulæst privat tilstand og færre overflødige skrivninger; der er ikke målt CPU/FPS/hukommelsesgevinst.

## Hele konkrete dependency-closure

`closure.json` registrerer præcise aktuelle kildehashes og manifestmetadata for modulet, callers, afhængigheder, klient, tests og relevante authoringværktøjer. Ingen kildetekst er duplikeret i denne hashinventarfil.

- Usher kræver Level 4 Configuration (`Configuration.Usher`), NoiseRegistry, PlayerProtection og DeathAdvice. Dynamisk nav-loader beholder `Level 4 Usher Nav` eller `L4UsherNode`-markerfallback. Nav, darkness, raycasts, huntability, pathing, hop, proxy/motion, battery, hide, leased capture, death-markering og protection/disconnect-hooks er uændrede.
- `Level4RoundGenerator` kræver modulet, kalder `Usher.Start(manifest, generation, LightDirector, Objectives)` ved Build og `pcall(Usher.Stop)` som første del af Cleanup. Generatorens LevelWorldStorage-forbindelse, world/template/visual-publicering og øvrige Stop-kald bevares.
- `Level 4 Objective Controller` modtager Usher fra Start og kalder Activate efter PowerUp samt Finale ved exit-unlock. LightDirector leverer zone-hooken. Usher.Start kalder også Stop ved reentry og forbinder Heartbeat/PlayerProtection/PlayerRemoving. Activate-sessionguard, Finale, Position, `_nodeDark` og det manuelle Play-testhook DebugPlace bevares ordret.
- Output til state-folder: `Level4_UsherActive`, `Level4_UsherState`, `Level4_UsherTarget`; proxy `State`; spiller `Level4_BeamingUsher`. Den aktive `Level 4 Round Client` tegner Usher fra Level 4 Usher Visual/Animations og UsherMotion, modtager ClientEvent/UsherCapture og rydder lokale round-objekter. `Remotes.ReportNoise`, Jumpscare, Level4 Remotes.ClientEvent og UsherMotion/protokoller bevares. NoiseRegistry input og DeathAdvice `L4Usher` bevares.
- Modul-initializeren opretter captureGeneration GUID og module-scope ReportNoise/PlayerRemoving intake-forbindelser. **Disse uændrede sideeffects eksekveres ikke i kontraktproben**; hele before/candidate-modulerne kompilieres, og de berørte private state/function-blokke testes som eksakt Source-udtræk. Der fjernes ingen initializer.
- `Level 4 Test Suite` har fortsat statiske/nav/live-round checks. `tools/level4_blender/usher_nav.py` authorer det separate nav-modul og markers; upload/serve bygger assets. README beskriver aktiv kinematisk Usher. `tools/performance_research/capture_sources.py` læser Usher til måling. Søgning i aktive source/services og disse tools finder ingen callers til de tre private navne uden for selve modulet og ingen separat controller-source payload, som skal omskrives. Nav-authoring, performance research, testhook og eksisterende owner-optimizationarbejde bevares.

Native forventet metadata for seks relevante originaler (target, RoundGenerator og fire require-afhængigheder) kommer fra Roots faktisk beståede S14-finalsnapshot. Proben revaliderer dem friskt og beskytter **alle 212** aktuelle LuaSourceContainers med Source/editor/class/identity/parent/properties/attributes/tags/census. Nav, LightDirector, Objectives og klient er således også omfattet af originalbeskyttelsen, selv om de ikke er en del af de seks særskilt pinnede fixtures.

## Meningsfuld før/efter-testport

`prepare_usher_private_locals_probe.py` indlæser det hashpinnede tidligere `verify_usher_locals.py` og udtrækker de faktiske state-deklarationer, setState, setBeamers, chooseTarget, think og Usher.Stop ordret. Hosts/perception/navigation/capture er tydelige kontrollerede grænser. Der evalueres ingen fuld live initializer, aktuel spiller, remote, map, nav-asset eller borrowed runtime-state.

- **68 assertions pr. version / 136 parrede og 136 ved runner-reentry**; fuld observerbar targeting/stun/state/attributes/capture-boundary/cleanup/failure-trace-signatur skal være identisk.
- Holder/sight/noise/finale, anonym Search, Shush/capture-boundary, beamer Stunned-threshold, aktiv stun cooldown, retreat, cooldown-suppression/udløb, invalid round og Stop/repeated Stop afprøves.
- Tre faktiske Stop-failure/retry-scenarier: den kontrollerede finishCapture-boundary kaster efter registrering; første Disconnect kaster; proxy Destroy kaster. Før og kandidat har samme throw, sessionsinvalidering, delvis cleanup, rækkefølge, retry og gentaget Stop. Faults sættes alene på test-owned fake objekter og fjernes før retry. Den kontrollerede capture-boundary kan registrere to cancellations ved retry; dette er **ikke** en real-capture-idempotencegodkendelse. Eksisterende behavior bevares.
- To ændringer i stadig aktive reason/cooldown-semantikker skal fejle kontrakten. **18 O0/O1 compilechecks** dækker whole Source før/efter, fire payloads, begge native runners og leasefixture. **8 faktiske udtrukne leasecases / 20 checks** beskytter late no-yield claim, fremmed state/token, cleanup og release.
- Native runner bruger fire friske unparented ModuleScripts, exact empty Source/editor CAS via ScriptEditorService, aldrig LuaSourceContainer-clones; originalguards før/efter alle success/failure-staginger og uafhængig owned cleanup. Eksakt egen shared state/token/emptyconnections/phase kontrolleres efter yield og ved no-yield claim/release. Ingen original Parents/properties, gameplay-state eller mode ændres.

Dette er tilstrækkelig lokalhjælper-/ulæst-state-port til det foreslåede snævre scope, når Root også har bestået den native førport og installerede replay. Det er **ikke** et fuldt gameplay-, virkelig capture/jumpscare-, respawn-, multiplayer-, streaming-, faktisk asset/nav- eller performancebevis. Større Usher-featurefjernelser kræver fortsat deres egne reelle flows og kan ikke udledes af denne kandidat.

## Scoped installation og reversibel fejlport

`apply_usher_private_locals_cleanup.py` bruger den gennemgåede S14-bounded installerstruktur. Default udfører alene offline proposal/compilechecks; kun Root må vælge `--apply`. Før apply kræves den faktiske native-before receipt med det præcise runnerhash, 68/136/136 checks, fire created/destroyed/zero remaining, original212 uændret og ejet lease frigivet.

Friske native Source/editor/hash/metadata læses i højst 20-record pages med 20KB reply-cap og samme katalog/signatur gennem alle pages. Source læses gennem det faktiske chunk-reader med 64-line chunks og 8KB cap, bracketed af targetidentity/hash/editor-checks og fuld 212-original/census-guard efter sidste yield. Before Source/editor/properties samt repo/working/HEAD-manifester gemmes privat før ændringen. Callback rechecks alle 212 originaler samt exact target Source/editor i et no-yield scoped CAS og foretager kun de fem unikke nonempty anchors; fjernet targetReason-skrivning har en bevaret attributlinje som reverse-anchor. Den native body skal hashmatche præcis kandidaten.

Efter apply eksporteres den verificerede native Source; præcis target-mirror og kun row.sha256/bytes i working-manifest opdateres. En privat HEAD-projektion ændrer kun Usher-rækken; ejerens RoundUI/working-only row og alle andre rækker bevares. Installeret samme native kontrakt, frisk global 212 parity og identisk console-baseline er obligatoriske. Eksisterende console-fejl kan eksistere; "identisk" betyder ikke tom console.

Ved callback/MCP-throw observeres faktisk target-status før rollback: kun kendt egen kandidat kan scoped-reverseres; allerede-before kræver ingen Sourcewrite; fremmed/ukendt Source bevares med eksplicit manual reconciliation. Lokale filer og manifestfelter rollbackes kun med egne aktuelle bytes/sha/size; andre aktørers metadata/rækker bevares. File-CAS er et kontrolpunkt umiddelbart før atomic replacement, ikke en kontinuerlig lås mod eksterne processer.

Offline installerporten har **16 scenarier / 109 assertions**, inkl. Play, før-write fejl, commit-then-error, fremmed/ukendt native, replay/console-fejl, actor Source/manifest/target-row, malformed/truncated/oversized pages, catalog/shortpage drift og chunk failure. Faktisk native-template transform afprøves forward/reverse/duplicate/missing/SHA: **5 scenarier / 8 checks / 2 compiles**; alle seks genererede operationer kompilieres O0/O1 (**12**). Kun MCP/native/console/git grænserne er fake; wrapperen og den faktiske filesystem/CAS/rollback udføres i temp directories. Produktionsfiler kontrolleres uændrede.

## Root-gate og udestående leverance

1. Uafhængig peer-review af de fem frosne tools/proof; repo/remote/current native er friske, eller kandidaten genafklares ved CAS-drift.
2. Root k?rte `python -B tools/cleanup_20261009/prepare_usher_private_locals_probe.py --execute before --receipt artifacts/cleanup-20261009/usher-private-locals-native-v1/usher-native-before-result.json`: **actual PASS 68/136/136**, fire probes created/destroyed, zero remaining, alle 212 originaler u?ndrede og owned lease frigivet.
3. Kun ved actual PASS: Root gennemgår og udfører den scoped installer `python -B tools/cleanup_20261009/apply_usher_private_locals_cleanup.py --apply`; installer udfører installed replay/afterparity/console.
4. Før/efterresultater, eventuel rollback og safe metadata-only public receipts kurateres særskilt. Root opdaterer plan/resultater, inspicerer præcis Source+HEAD-row diff og committer. Ingen GitHub-push eller cleanup-publicering.

Hvis en nødvendig native før/efterport ikke kan fuldføres, eller en regression/concurrent drift opstår, beholdes kandidaten og status forbliver afventende. De foreløbige offline PASS-felter må ikke omtales som actual native PASS.


## Actual resultater og kuraterede beviser

`usher-native-before-result.json` og `usher-source-install-v1/native-installed-result.json` viser samme behavior SHA `8dd7b422c11106477bf58191b04d4143616446687240163a5bcb0c402c1f89de` for f?r/kandidat og for det installerede replay. Begge prober har ingen cleanupErrors, zero probes tilbage og frigivet egen lease; de ?ndrer ingen authoritative Source/Parent/attributes. Installerens `result.json` viser pr?cis ?n original Sourcewrite, zero andre original Sourcewrites/propertywrites/Parentwrites/mode switches og u?ndret HEAD `920abdeeb07dbf6729c48f980765b96ec82b06eb` gennem batchen. De ?vrige 211 Source-r?kker og alle andre working-manifest-r?kker er bevaret; kun Usher-row.sha256/bytes er ?ndret. Ejerens RoundUI/working-only row bevares separat ved Roots scoped HEAD-commit.

`native-before.json`, `native-after.json` og `native-final.json` indeholder metadata/hash, ingen Source/editor-bodies. Final-kataloget er afledt fra de faktisk eksekverede sidste 11 pages med ens target/katalog; alle 212 identiteter er unikke. Kun Usher sha256/bytes ?ndres; samtlige identities/classes/parents/properties/attributes/tags er ens, og after/final er byte?kvivalente. `apply.luau`, begge faktiske chunk-slutguards og ?n metadata-readercode er eksakte private-checkpoint-eksporter. 33 r? page checkpoints og fulde native rollback-Source/editor/working/HEAD-manifester bliver private; Source-before/candidate findes allerede som de tidligere immutable forslag og kopieres ikke igen som r? blobs.

`curate-installed-proof.py` udf?rer ingen Studio-/Source-/manifest-/Git-kald; den l?ser og hashbeskytter aktuelle kanoniske filer og frosne tools, revaliderer actual PASS og private f?rinput, og skriver alene eksklusive egne public evidencefiler. Den afledte bounded proof skelner de eksekverede 20KB metadata/8KB Source-responsecaps fra statiske 64-line Source-chunks: **15 chunks pr. version, st?rste 3363 UTF-8 bytes**. Gemte pretty JSON pages er ikke m?lte wire-sizes. Console er pr?cis u?ndret og indeholder fortsat de eksisterende sound-afvisninger og gamle Assistant-diagnosticfejl; der h?vdes ikke en tom console.

Default installer og fake-boundary wrapper-test er f?rinstallationens replayport og kr?ver den kanoniske before-baseline; de historiske receipter skal ikke overskrives efter installation. Samme installerede native Source-kontrakt kan genk?res af Root med `prepare_usher_private_locals_probe.py --execute installed --receipt <ny immutable sti>`; den revaliderer aktuelt target og alle originaler og ?ndrer alene nye owned probeobjekter. Native kontrakt-runners indeholder n?dvendige faktiske Source-udtr?k og testhosts; de er ikke raw rollback-kopier og m? ikke kaldes et full-capture/gameplaycertifikat.

Der er ingen m?lt performancegevinst og ingen certificering af real initializer/nav/capture/jumpscare/round/multiplayer/streaming/respawn/teleport/assetflow. Aktive features og workflows er bevaret inden for den dokumenterede scoped kilde?ndring og de best?ede kontrakter. St?rre kandidater kr?ver deres egne manglende integrationsporte.
