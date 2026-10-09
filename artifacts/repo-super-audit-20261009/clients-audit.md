# Klienter, ReplicatedFirst og delte moduler — audit 2026-10-09

Dette dokument er en read-only handoff. Ingen eksisterende kode er ændret, ingen script er slettet eller deaktiveret, og der er ikke lavet removal-forsøg i Studio. Studio-inventaret er sandheden om det aktuelle spil. Repo bruges som læsbar kopi, når parity er `exact`; ved drift bruges snapshot under `studio-sources`.

Henvisninger med `native:` peger på `artifacts/repo-super-audit-20261009/studio-sources/`. Andre kildehenvisninger peger på repo-roden. Linjetal er tekstlinjer i de konkrete filer, ikke Studio-editorens tælling af en afsluttende tom linje.

Metode: komplet filinventar; gennemlæsning af kilde/hotspots; søgning på lokale symboler, krævede moduler, remotes, attributter og callers i hele træet; krydstjek med `parity.json`, `studio-inventory.json` og native snapshots. `D` i coverage betyder dyb læsning af filens centrale runtimeforløb; `S` betyder fuld strukturel scanning med udvalgte dybe hotspots. Store UI-filer og genererede tabeller er ikke alle gennemgået manuelt gren for gren. Coverage er derfor ikke en påstand om, at hver mulig runtimegren er afprøvet.

**Sikkerhed ved oprydning:** en fundet kandidat er ikke tilladelse til at slette nu. Selv de små, statisk sikre kandidater skal gennem den angivne regressionsport i en ny, isoleret session. Ingen anbefaling her er dokumenteret med et removal-playtest; root-sessionens compile-checks er baseline, ikke bevis for, at en fjernelse fungerer.

## Prioritet og anbefalede beslutninger

- Tag først den aktive Studio-kode tilbage i repo. Ellers kan en almindelig sync genindføre pensioneret Level 6, fjerne HELP/WELCOME eller lukke offentlig adgang til Level 5/6.
- Små, sikre oprydninger: to inerte marker-scripts, præcise ubrugte lokale konstanter/helpers og ubrugte interne QA-data. Bevar kald, der skaber GUI, selv når deres lokale returvariabel er ubrugt.
- Mest konkrete omskrivninger: ShopDisplay-rescan ved partiel streaming, RoundHud gentagen statisk rendering, native DJ-musikkens lobbyguard/cache, L5 rolling-sounds cleanup og WELCOME input/modal/touch-integration.
- Pensioneret L6-materiale: arkivér/udeluk fra sync efter dependency- og manifestgennemgang. Det er ikke tilstrækkeligt bare at slette de gamle klientfiler, hvis værktøjer fortsat forventer dem.
- Ingen hel delt ModuleScript blev dokumenteret som helt ubrugt. UIRegression bruges af værktøjer; animationstabeller, streaming-sikkerhed og client-side visuals har aktive callers.

## Konkrete fund

### C01 — Repo og aktiv Studio har forskellige klientfunktioner

**Kategori/prioritet:** correctness, høj. **Native:** dokumenteret drift, aktiv Studio har prioritet.

`First Entry Guide.LocalScript.lua` er en 7-linjers inert repo-marker, men en aktiv 566-linjers native WELCOME/HELP-klient. Native L1 Sound, L5 Lighting, Level4PreviewPrompt, Level6PreviewTransport og R4DevGate er også forskellige. Tre aktive klienter findes kun i Studio: Lobby DJ Client, Lobby Tunnel Reach Client og Level 6 Dev ESP.

Konkrete konsekvenser ved at pushe repo ukritisk:

- First Entry Guide: WELCOME, HELP, replay af tutorial og spawn-kameraretning forsvinder.
- Native L1 Sound: guard på `Level6PlaygroundPreview` mangler i repo; kontor-ambience kan spille i legepladsen, hvor SelectedLevel fortsat er 1.
- Native Level6PreviewTransport bruger `Level 6 Indoor Playground`, `Level6PlaygroundPreview` og offentlig `IsLevel6Allowed`. Repo refererer det pensionerede level/ældre adgangsgate.
- Native R4DevGate og Level4PreviewPrompt behandler Level 5/6 som offentlige. Repo kan skjule/blockere deres døre for almindelige spillere.
- Native L5 Lighting har under-ceiling-regler for debris, bodies og lyd, der ikke findes i repo.

**Mindste fix:** importer præcis native source, og bevar Disabled/enabled, før cleanup. Registrér de tre Studio-only klienter og deres server/remotes/assets i source control. **Risiko:** høj ved repo-overwrite, lav ved korrekt, reviewet source reconciliation. **Regressionsport:** ordinary account + developer account; lobby tutorial/help; offentlig L5/L6 entry/return; L6 stream acknowledgement; under-roof L5 audio/debris; DJ og tunnel-monster; native fingerprint efter reconciliation. **Fjern ikke First Entry Guide.**

### C02 — To aktive scripts er bevidst inerte migration-markers

**Kategori/prioritet:** removal, lav risiko. **Native:** `exact`, enabled=true, kun kommentarer.

- `StarterPlayer/StarterPlayerScripts/Team Objective Feed.LocalScript.lua:1`: 2 linjer. Kommentaren siger, at Round HUD nu ejer feedet. Aktiv successor: `Round HUD.LocalScript.lua:255` og `RoundHud.ModuleScript.lua:1040`.
- `StarterPlayer/StarterCharacterScripts/DisableDefaultWalkingSound.LocalScript.lua:1`: 5 linjer. Kommentaren siger, at SoundController dynamisk muter Running kun i runder. Det gamle script foretager ingen handling.

**Evidens:** ingen executable statements; native parity er exact. Hele træet er søgt efter navn og successor. **Mindste fix:** slet marker-instanser og fjern dem fra export/push-manifest; bevar successors. **Risiko:** gameplay lav; tooling kan have navnebaserede forventninger. **Regressionsport:** join/respawn, lobby Running-lyd, hver levels custom footsteps, team-objective push/feed og relevante sync-tests. Root gennemgår tooling-dependencies før fjernelse.

### C03 — Seks pensionerede L6-klienter og ét disabled animation-patch kan arkiveres

**Kategori/prioritet:** archive/removal-beslutning, mellem risiko for tooling, ingen nuværende native runtimeeffekt.

**Findes ikke i native Studio:** L6 Lighting Controller (1154 linjer), L6 Mall Manager Visual Smoother (211), L6 Table Hiding Client (515), L6 CD Dev ESP (188). **Findes, men disabled:** L6 Reader Client (1233), L6 Sound Controller (1215). Native DJ-kommentar `Lobby DJ Client:8` siger direkte, at DJ overtog det pensionerede Table Hiding-script; native Level6 Dev ESP:3 siger, at det erstatter CD ESP for den pensionerede genererede verden. Nu aktive L6: Playground Client + Playground Game + Dev ESP og public preview-access.

`StarterCharacterScripts/SetRunAnimation.LocalScript.lua` er også disabled i native inventory; 19 linjer patcher custom run-id `83054249237379`. Disabled er en designbeslutning, ikke automatisk bevis for, at animationsønsket er opgivet.

**Mindste fix:** saml de gamle L6-kilder i tydeligt arkiv uden for runtime-sync; dokumentér tidligere filenames og native status. Tag først stilling til disabled SetRunAnimation separat. **Afhængigheder:** gamle L6 servermoduler, migration/install-scripts, regression-fixtures og gamle preview-værktøjer; levels/tooling-audit er autoritativ for deres fjernelse. **Risiko:** høj hvis repo-filer ved en sync genskabes som enabled; mellem ved sletning af tests/tools; lav for at lade disabled instanser blive disabled. **Regressionsport:** fresh Studio sync fra den nye manifest, native L6 må kun køre Indoor Playground, public/developer adgang, doll/entity, reader/detector-UI, flashlights, easter egg, DJ/tunnel, return-to-lobby. **Ingen blind sletning af en hel Level 6 mappe.**

### C04 — Præcise ubrugte lokale konstanter og bindings i aktive filer

**Kategori/prioritet:** removal, lav. **Native:** exact for alle nævnte repo-filer.

Søgning med kommentarer fjernet fandt ingen læsning efter deklaration:

| Fil | Kandidat | Linje | Mindste ændring |
|---|---|---:|---|
| StarterCharacter/Animate | `origRoll` | 594 | fjern kun lokal deklaration |
| StarterCharacter/Animate | `climbFudge` | 863 | fjern kun lokal deklaration |
| Level 3 Reader Client | MAXIMUM_RANGE, ACCURACY_DEGREES, DISTANCE_NOISE | 25–27 | fjern de tre gamle calibration-values |
| Level 3 Reader Client | CD_SIGNAL_RANGE, ROOM_BLINK_RATE | 30,33 | fjern konstanterne |
| Level 3 Reader Client | MUTED, AMBER, DANGER | 44,45,48 | fjern ubrugte palette-bindings |
| Level 3 Table Hiding Client | HIDDEN_TEXT | 382 | fjern konstanten |
| Round Exit Client | HINT_HEIGHT | 55 | fjern konstanten |
| ReplicatedStorage/RoundHud | TOUCH_LANE_X | 1084 | behold TOUCH_LANE_Y=52, som bruges |
| ReplicatedFirst/Lobby Loading Screen | lokalt `announced()` | 638–640 | fjern uncalled helper |

**Afhængigheder:** disse er private locals, ikke modul-API. Deres værdier er literals/rene opslag; ingen synlig side effect fjernes. **Risiko:** lav; højere hvis man regex-sletter en hel multiple assignment eller nabokode. **Regressionsport:** compile, idle/run/climb animation, L3 reader + hide + upgraded detector, round-exit keyboard/touch/gamepad, touch detector-lane og lobby loading success/failure/ENTER ANYWAY. Bevar hele scripts og deres offentlige funktioner.

### C05 — UIRegression har ubrugte interne briefing-data og uncalled helpers

**Kategori/prioritet:** removal, lav. **Native:** exact. **Fil:** `ReplicatedStorage/UIRegression.ModuleScript.lua`.

Præcist afgrænsede kandidater:

- `setLongDispatchCue`:1253–1265, kun kommentarmæssig reference ved 2589, ingen caller.
- `BRIEFING_STRESS_CORPUS`:4152–4161.
- `BRIEFING_CONTROL_CAPTIONS`:4166–4171; `BRIEFING_CONTROL_ORDER`:4172.
- `briefingDevices`:4187–4196, ingen caller. `BRIEFING_LANDSCAPE_ROWS`:4178–4185 bruges kun af denne døde helper og er dermed transitivt død.
- `analyticalOverlap`:4210–4213, ingen caller.
- `BRIEFING_EXCLUSION_VIEWPORTS`:4262–4265.
- `DEV_CAPTION_KEYS`:4273–4283.
- `DEV_EYEBROW_BASE`:4284 og `DEV_EYEBROW_KEYBOARD`:4285; BASE bruges kun i den døde KEYBOARD assignment.
- `DEV_NOCLIP_KEYBOARD`:4286 og `DEV_NOCLIP_TOUCH`:4287.

**Mindste fix:** fjern kun disse private definitionsblokke og ret kommentaren, der siger, at setLongDispatchCue overskriver live cue. **Bevar** LONG_DISPATCH_CUE:1251, som har andre callers, og alle public Fit-metoder. **Risiko:** lav for runtime; QA-baseline kan have source-text-forventninger. **Regressionsport:** alle nuværende UIRegression-public tests og værktøjsentrypoints, compile, RunAll og bodyRoundHudMatrix. UIRegression som helhed er **ikke** død kode.

### C06 — Små native rester i den nye guide og preview-filteret

**Kategori/prioritet:** removal, lav. **Native:** source drift, brug native linjer.

- `native:First Entry Guide:247–248`: lokalt KEYS-table bygges, men læses aldrig; TOPICS bruger egne inline strings.
- `native:Level4PreviewPrompt:19–23`: special-case for user 11374988579 fjerner `Level6DeveloperPreviewPrompt` og `Level6DeveloperPreviewReturnPrompt` fra PROMPTS, men de to keys findes allerede ikke i tabellen:7–11. Branchens eneste effekt er at tildele nil til allerede nil keys.

**Mindste fix:** fjern KEYS og hele no-op special-case med dens forældede kommentar; behold public L5/L6-politikken og L4 developer-filteret. **Risiko:** lav, men repo-kopien er ældre og må ikke bruges som fix-base. **Regressionsport:** WELCOME/HELP alle topics; ordinary/dev/special-user door-visibility; L4 map-preview stadig developer-only; L5/L6 offentlig adgang.

### C07 — Ubrugte returvariabler må ikke medføre fjernelse af GUI-kald

**Kategori/prioritet:** cleanup guard, lav. **Native:** exact.

`Lobby Loading Screen:62` (`kicker`), :92 (`tip`) og `ZyntraStore:276` (`shopButtonRing`) er bindings, der ikke senere læses. Men `label(...)` skaber synlige labels, og `outline(...)` skaber en synlig UIStroke. **Kun bindingen er overflødig.**

**Mindste fix:** hvis ønsket, gør til standalone kald. Ingen performancegevinst forventes; UI skal stadig skabes. **Risiko:** høj for visuel regression ved at slette hele linjen. **Regressionsport:** loading kicker/tip samt store-knappens outline i keyboard/touch og hovered/disabled state. Ingen hel linjesletning anbefales.

### C08 — JumpscareUI indeholder en pensioneret, kommenteret billedversion

**Kategori/prioritet:** optional cleanup, lav. **Native:** exact. **Fil:** `JumpscareUI.LocalScript.lua:15–28`.

Den gamle image-jumpscare er en kommentarblok og kører ikke; den aktive head-camera-capture skal bevares. **Mindste fix:** fjern kommenteret gammel implementering, hvis git historik erstatter rollback-noten. **Risiko:** gameplay ingen; tab af lokal dokumentation. **Regressionsport:** ingen ny gameplaytest nødvendig alene for kommentarer; compile og diff bekræfter, at aktive statements er identiske. Dette er læsbarhed, ikke performance.

### C09 — ShopDisplay scanner alle shop-descendants hver frame ved partiel streaming

**Kategori/prioritet:** performance, mellem. **Native:** exact. **Fil:** `Shop Display Client.LocalScript.lua:688–705,723–739`.

`#boxes < ShopItemCount` kalder `collect(shopModel)` på hver Heartbeat. collect bruger model:GetDescendants. Serverens stamped count er totalen; med StreamingEnabled kan klienten have modellen og kun nogle af dens bokse i længere tid. Condition bliver da ved med at være sand. Det sker **før** `motionAllowed()` og derfor også, når round/accessibility guards slår bob-animationen fra. Kommentaren dokumenterer den oprindelige late-replication-bug; behovet for retry skal bevares.

**Mindste fix:** DescendantAdded/Removing dirty-flag + én coalesced collect, med en begrænset 0.5–1 s fallback til late replication. Pas på at bevare `Origin` og ikke recapture en midlertidigt bobbet CFrame. **Afhængigheder:** server ShopItemCount, streaming og serverens collision-envelope. **Risiko:** mellem; en for aggressiv cache kan give stillestående/forskudte bokse. **Regressionsport:** model før boxes, kun 1 af 8 boxes streamed, stream-out/in, lobby→round→lobby, ReduceFlashing/ReduceCameraShake. Instrumentér collect-count; efter initial load skal den ikke følge FPS. Bob og purchase-prompts skal fortsat fungere.

### C10 — RoundHud renderer statisk objektiv/feed mindst 10 gange i sekundet

**Kategori/prioritet:** performance, mellem. **Native:** exact. **Filer:** `RoundHud:716–790,955–1017,1331–1358`; `Level 2 Objective UI:24–34,46–53`.

RoundHud Heartbeat kalder refreshOwned hvert .1 s; den renderObjective'er samme State og renderFeed'er samme rækker, caption og layout. SetObjective cloner state og kalder renderObjective, selv når den semantiske nøgle er uændret. L2 sender yderligere samme exitObjective hvert .22 s, ud over attribut- og layoutlisteners. Det betyder op til ca.14.5 statiske refreshes/s på L2. Feed kalder også flowFeedWords for eksisterende rows; udløb har allerede task.delay:1047 og :1066.

**Mindste fix:** adskil statisk dirty-rendering fra compass geometry/timers/suppression. Cache semantic state/layout/actor text; behold live compass opdatering og nødvendige fallbacks. For L2: CharacterAdded/health + watched-target binding og dedup før SetObjective, eller reducer polling til readiness-fallback. **Afhængigheder:** late character/HUD readiness, spectate-target health, modal ownership, caption/feed expiry, detector attention, compass targetposition. **Risiko:** mellem; fjern ikke alle Heartbeats blindt. **Regressionsport:** bodyRoundHudMatrix, alle levels objective transitions, L2 late humanoid, target dead/escaped/disconnect, 4s feed expiry, 3.5s captions, alle modals/touch layouts, attention resume og moving compass. Mål propertywrites/render-count og frame-time før/efter; her er gentaget arbejde dokumenteret, men FPS-gevinst ikke målt.

### C11 — Flashlight-profil læses to gange på hver normal renderframe

**Kategori/prioritet:** lille performance/cleanup, lav. **Native:** exact. **Fil:** `FlashlightController:134–144`.

applyBeamProfile kaldes ved :135 og igen :144; ved mount-rebuild også :141. Dets key-cache dæmper writes, men opslag og key-bygning gentages. **Mindste fix:** én applyBeamProfile efter camera/mount er valideret og eventuel mount er bygget. **Risiko:** lav, hvis den beholdte call også kører ved ny mount/profilændring. **Regressionsport:** initial mount, character respawn, camera replacement, flashlight upgrade og L3-profile, on/off. Gameplayfunktionen skal bevares.

### C12 — Slukket egen flashlight udfører stadig aim-math og raycast hver frame

**Kategori/prioritet:** performance, mellem. **Native:** exact. **Fil:** `FlashlightController:134–199`.

Aim-lerp, hand placement, filter-allokering, wall raycast og mount.CFrame opdateres før `if on` ved :190. Det sker også i lobbyen/slukket tilstand. Den lokale suppression af serverens self-flashlight:177–188 er fortsat nødvendig, også hvis den lokale torch er slukket.

**Mindste fix:** behold mount/profil/suppression ownership; gate aim/raycast-positioneringsdelen bag on, og reinitialisér aimCF ved aktivering så der ikke kommer et stale-frame hop. **Risiko:** mellem, især dobbelte SpotLights eller første on-frame, hvis man blot early-returner for tidligt. **Regressionsport:** slukket lobby/round uden raycastarbejde, on toggles ved væg, L3 under-table camera, server mount arriving late, camera/character replace og net-sync. Visuals og server suppression skal være identiske.

### C13 — Flashlight battery-widget skriver samme tilstand hver frame

**Kategori/prioritet:** profilérbar effektivisering, lav/mellem. **Native:** exact. **Fil:** `FlashlightController:287–329,765–823`.

Battery state kan dræne smooth, men paintWidget opdaterer segments, caption og tone på alle frames, selv når segment-index/tone/text/visibility er identisk. **Mindste fix:** behold battery-drain/integrator; memoize widgetens synlige tuple og kun skriv ændrede properties. **Risiko:** lav ved korrekt cacheinvalidations; layout-/theme/profilskift skal invalidere. **Regressionsport:** fuld→tom batteri, recharge, mode changes, touch/keyboard rotation, modal hidden/resume og upgraded cell; sammenlign segment- og alert-tærskler før/efter.

### C14 — Teammate flashlight-shafts raycaster pr. tændt beam pr. frame

**Kategori/prioritet:** måle/valgfri omskrivning, mellem. **Native:** exact. **Fil:** `FlashlightController:706–742`.

Clienten opdaterer hver teammate beam og raycaster shaft endpoint hver Heartbeat. Det er en nødvendig visual-funktion; der er cleanup ved character ancestry:682. Det er **ikke** en dokumenteret leak. Antallet af rays skalerer med aktive teammate torches × klient-FPS.

**Mindste fix:** profilér først; hvis dyrt, cull/throttle kun shaft/lens decoration når langt væk/uden for synsfelt. Bevar SpotLight og server gameplay-state. **Risiko:** mellem ved synlige huller/popping. **Regressionsport:** 6 spillere med alle torches på, nær/fjern/stream-out, hurtige kameravendinger, endpoint mod væg samt on/off. Sammenlign MicroProfiler raycasttid og visuel parity. Fjern ikke teammate torch-feature.

### C15 — Native DJ JSON-dekoder tracklisten ved 20 Hz, også når DJ er slukket

**Kategori/prioritet:** performance, lav. **Native-only:** `Lobby DJ Client:24–27,137–145`.

Party-light Heartbeat kalder tracks() hvert .05 s; tracks JSONDecode'er workspace.LobbyDJTracks. Det sker før den afgør, om DJ er on. Tracklisten ændrer kun ved attributopdatering. **Mindste fix:** cache decoded list ved LobbyDJTracks-changed, brug cachen til lyd, lys og booth. Bevar invalid JSON→empty fallback. **Afhængigheder:** server publishes tracks/track index/start time. **Risiko:** lav. **Regressionsport:** initial missing/invalid tracks, server list replacement, track switch, STOP, non-team client, team panel, party lights og ReduceFlashing. Decode-count må følge list changes, ikke FPS/20 Hz.

### C16 — Native DJ's lamp-cache ignorerer senere streamed lights

**Kategori/prioritet:** visual correctness, mellem. **Native-only:** `Lobby DJ Client:114–135,147–164`.

collect() cacher kun de Light-instanser, der eksisterer ved første Ready-model scan. Hvis samme lobby-model bliver ved at eksistere, returneres cachen altid. Late/streamed-in lights tilføjes ikke; streamed-out entries bliver blot ignoreret. Nyindstreamede instanser kan derfor forblive normale, mens naboer er i party mode. Stop/start nulstiller cachen og kan midlertidigt reparere det.

**Mindste fix:** model DescendantAdded/Removing cache ved party-mode; snapshot base Color/Brightness for hver ny Light og restore præcis disse ved stop. **Risiko:** mellem, fordi andre lobby flicker-controlleres writes/ownership skal bevares. **Regressionsport:** DJ play mens kun en lobby-sektion er streamed; gå gennem hele lobbyen; stream-out/in; stop; normal ceiling/gate flicker og ReduceFlashing fortsat korrekt.

### C17 — Native DJ-musik fortsætter ind i det offentlige L6 Playground

**Kategori/prioritet:** correctness, mellem/høj. **Native-only:** `Lobby DJ Client:30–37,61–98`; aktiv `Level 6 Playground Client:1021–1022`.

DJ's eligible kræver ReservedRoundServer=false, InRound=false og LobbyMusicEnabled=true, men ikke Level6PlaygroundPreview=false. Preview bruger InRound=false. DJ-sound er direkte under SoundService uden ZyntraLobbyMusic SoundGroup; Playground duck'er kun denne SoundGroup. DJ lytter heller ikke på Level6PlaygroundPreview. En track, der spiller ved entry, følger derfor med ind i Playground, oven i level score.

**Mindste fix:** fælles lobby-eligibility med preview-guards og attr listeners; restore normal lobby music kun når alle aktive owners tillader det. **Risiko:** mellem, især race mellem Playground, LobbyMusic og DJ's Volume=0/1 writes. **Regressionsport:** DJ playing→L6→lobby, STOP inde i L6, track switch inde i L6, LobbyMusic setting on/off, ordinary account, DJ account, Level5/round entry. L6 må kun høre sin egen score; lobby skal få DJ/normal track korrekt tilbage.

### C18 — Native DJ har ubundet ventetid på Sound.Loaded

**Kategori/prioritet:** robusthedskandidat, lav/mellem; fejlsti er statisk, ikke live reproduceret. **Native-only:** `Lobby DJ Client:73–79`.

Hver applyTrack-on spawner en coroutine, der kan vente permanent på sound.Loaded hvis asset aldrig loader. SoundId kan skifte, mens tidligere waits stadig eksisterer. Flere attr changes kan skabe flere waits. Der findes ingen timeout/generation cancellation i dette forløb.

**Mindste fix:** generation token + bounded load-wait/poll; genbrug én pending resync per sound/id; stop, unsubscribe eller ignorér stale waits ved STOP/id-skift. **Risiko:** lav, hvis sync og stale-check bevares. **Regressionsport:** gyldig track sync på to klienter, forsinket load, asset load failure, play/stop/play hurtigt og tracks metadata update. Må ikke klassificeres som faktisk målt memory leak før dette reproduceres.

### C19 — Native L5 rolling-sounds springer cleanup over ved level-exit

**Kategori/prioritet:** correctness/lifecycle, mellem. **Native:** drift, snapshot L5 Lighting:822–889.

Rolling sounds oprettes looped på balls:863–868. Når `inLevel()` bliver false, rammer loopet continue:840–842, før `rolling` states opdateres eller destrueres. Kun fall stopper der. Roll cleanup:888 kræver, at loopet når balls-delen og near=false. Så længe ballinstanserne bliver i klientens world, ligger de looped/playing på tidligere volume; streaming/distance kan skjule lyden, men lifecycle-stop sker ikke. Den nye under-ceiling-kode ændrer ikke dette.

**Mindste fix:** stop/destroy alle rolling states på on→off, model change eller missing character; ryd tabel. Behold fades ved almindelig near→far bevægelse. **Risiko:** lav/mellem; return til level skal kunne genoprette lydene. **Regressionsport:** kick ball, public return to lobby før modellen unloades, death/respawn, teleport til andet level, reentry og ball removal. Ingen l5_ball_roll må være playing efter exit; der må ikke dannes dubletter ved reentry.

### C20 — New-map flicker-episode kan fortsætte efter grade-release

**Kategori/prioritet:** scoped lifecycle/effektivisering, lav/mellem. **Native:** exact. **Fil:** `Level2PoolroomsPresentation:216–242,257–260,264–272,313–328`.

Et grade-check findes kun ved episode-start:258. Inde i en episode ventes op til 15 s, og lys skrives igen efter wait uden kontrol af grade/epoch. releaseGrade/CharacterRemoving stopper ikke episoder; stopFlicker kaldes ved descendant removal. Hvis map ikke straks destrueres, kan lokale lys fortsat ændres efter klienten er ude. Det påvirker primært et efterladt map og er ikke dokumenteret som en round-blocker.

**Mindste fix:** grade generation/cancellation ved hvert yield eller stop/reset aktuelle episoder ved release og genstart ved entry. **Risiko:** mellem, hvis lights ender permanent slukkede eller fælles map gets forkert baselys ved resume. **Regressionsport:** exit/death mid-outage og ReduceFlashing-toggle under episode; return/new character; map stream-out. Lys skal restore og næste entry skal kunne flickre igen. Bevar accessibility fade/stutter-reglerne.

### C21 — WELCOME avancerer sider på tastetryk i chat/TextBox

**Kategori/prioritet:** input correctness, mellem. **Native-only drift:** `First Entry Guide:234–240`.

InputBegan callback bruger kun event og ignorerer gameProcessedEvent samt focused TextBox. Space, Return og arrow keys avancerer WELCOME, også når spilleren skriver/redigerer chat. Flere spaces kan dermed lukke onboarding uden hensigt.

**Mindste fix:** guard processed/focused TextBox for navigation, og afgør særskilt ESC/ButtonB policy. **Risiko:** lav/mellem; core UI gamepad-focus kan markere handled inputs og må ikke gøre NEXT ubrugelig. **Regressionsport:** WELCOME+chat typing med spaces/arrows/Enter, gamepad A/B, keyboard next/back, touch NEXT/SKIP og tutorial replay. Ingen gameplayfeature skal slettes.

### C22 — WELCOME og DJ booth skalerer touch-targets under 44 px

**Kategori/prioritet:** touch usability/correctness, mellem. **Native-only:** `First Entry Guide:122–135,149–170`; `Lobby DJ Client:249–255,276,291–304`.

WELCOME's 620×452 card skaleres efter rå Viewport. Ved 390 px bredde er scale=(390−28)/620≈.584; 50 px NEXT bliver ca.29 px, 40 px SKIP ca.23 px. Ved 568×320 bliver NEXT ca.32 px. Safe/modal viewport bruges ikke til dette card. DJ booth har 32 px PLAY før scale, 40 px close og 44 px footer; på lille landscape kan scale≈.688 reducere dem til ca.22/28/30 px. Dette er et konkret matematisk brud på projektets øvrige 44px touch-target-konvention.

**Mindste fix:** anvend UIDevice.ModalViewport/Safe-layout og reflow; mindst 44px **efter** UIScale, evt større uscaled button hitboxes. **Risiko:** mellem ved ændret card layout/tekstflow. **Regressionsport:** 390×844, 568×320, 844×390, 768×1024; notch/safe insets; touch+hård keyboard; alle fire welcome pages, lange track titles og scrolling; target bounds og touch hit-tests. Visuelle labels/instructions må ikke forsvinde.

### C23 — WELCOME device-copy bruger en gammel hybrid-device heuristik

**Kategori/prioritet:** input/device correctness, mellem. **Native-only:** `First Entry Guide:55,85–108,249–314`.

touch vælges én gang med TouchEnabled AND NOT KeyboardEnabled, eller ForceTouchUI. Det afviger fra UIDevice's fælles formfactor/hybrid policy. Tablet/telefon med keyboard kan få keyboard-only labels, og senere device/ForceTouchUI changes opdaterer ikke de allerede byggede PAGES/TOPICS strings.

**Mindste fix:** fælles UIDevice-layout/caption policy ved draw/topic selection; regenerér input-copy ved UIDevice.Changed. **Risiko:** lav/mellem; bevar både touch og keyboard/gamepad instruktioner. **Regressionsport:** phone/tablet med keyboard=true, laptop med touch, device change, ForceTouchUI, tutorial replay og HELP-controls. Compare med resten af HUD'ens inputglyphs.

### C24 — WELCOME og DJ registrerer modal-flags, som det fælles modal-system ikke kender

**Kategori/prioritet:** modal/input integration, mellem. **Native:** exact UIDevice + Studio-only/drift callers.

UIDevice.SCREEN_OWNING_MODALS:1656–1659 indeholder ni flags, inkl HelpPanelOpen, men ikke WelcomeCardOpen eller LobbyDJOpen. Native guide sætter WelcomeCardOpen:210 uden SuppressTouchMovement; native DJ show:327–330 sætter LobbyDJOpen uden tilsvarende suppression eller fælles close-on-other-modal. NoiseReporter, Flashlight, RoundHud, friend chips og store spørger den fælles predicate. De vil derfor ikke automatisk stå ned under disse to overlays. WELCOME shade er Active og fylder skærmen, men det er ikke samme som konsistent keyboard/touch movement/modal ownership.

**Mindste fix:** beslut om begge skal eje skærmen; hvis ja, registrér i samme liste/listeners og brug standard suppress/close lifecycle. DJ kan evt være et ikke-modalt developer panel, men så skal det dokumenteres og touch-UI placeres uden overlap. **Risiko:** mellem, fordi inklusion ændrer rail docking og modal interoperability. **Regressionsport:** WELCOME/DJ på touch med joystick/RUN/flashlight; store/help/badges/daily/wheel samtidig; close, InRound, death/capture og camera transitions. Bevægelse/rails skal genoprettes præcist. **Beslutning nødvendig:** DJ modal eller fri booth-panel; ikke en deletion.

### C25 — Aktiv HELP beskriver de pensionerede L2-pumps

**Kategori/prioritet:** stale feature-copy, lav/mellem. **Native-only drift:** `First Entry Guide:276`.

HELP siger "Start the pumps to open the exit". Levels-audit har krydset native Level2RoundAdapter:13,194 mod PoolroomsRuntime: aktiv public L2 er authored PoolroomsMap/exit, mens gamle WorldBuilder Build fejler som retired. L2 Objective UI:24–25 siger "Find the exit". En almindelig spiller får derfor vejledning til et pensioneret objective.

**Mindste fix:** ret HELP's L2-beskrivelse efter det aktive map/objective. **Risiko:** lav; ingen kodefjernelse. **Regressionsport:** ordinary L2 run + HELP læst før entry; teksten skal matche faktisk objective og exit-flow. Brug levels-audit til anden historisk copy, ikke blind string replacement.

### C26 — Fire QA-navne er nu kompatibilitetsaliaser til samme RoundHud-test

**Kategori/prioritet:** test coverage/documentation, mellem. **Native:** exact. **Fil:** `UIRegression:4215,4289,4828,4853`.

bodyBriefingFitMatrix, bodyBriefingExclusionMatrix, bodyObjectiveCornerMatrix og bodyDispatchCompactMatrix returnerer bodyRoundHudMatrix. Matrixen:4762–4821 tester objectives/feed/caption på stated devices og levels, men udfører ikke alle de historiske briefing-control/exclusion scenarios, der beskrives i de gamle blocks. RunAll kalder matrixen én gang; **der er ikke dokumenteret firefold duplicate runtime i RunAll**. Værktøjer kan stadig kalde aliasnavnene direkte.

**Mindste fix:** markér aliasernes konkrete coverage, ret gamle kommentarer/testnavne; fjern først aliases, når alle callers er migreret. Tilføj særskilt native WELCOME/HELP/DJ regression, hvis det ønskes, frem for at antage at bodyBriefingFit dækker dem. **Risiko:** mellem ved fjernelse af public QA-API. **Regressionsport:** alle tools/tests entrypoints, RunAll, samme pass/fail outcomes og dokumenteret testcase mapping. Dette er ikke grund til at slette UIRegression.

### C27 — ShopData's fælles profile-push clearer alle action/product pending states

**Kategori/prioritet:** protokol-review/valg, mellem; ikke dokumenteret token-loss/charge exploit. **Native:** exact. **Fil:** `ZyntraShopUI/ShopData:524–532`.

Kommentaren siger udtrykkeligt, at næste push slutter alle token requests og alle product receipts. Callback korrelerer ikke push med Action/key. Hvis handling B eller receipt B stadig er i gang, kan profile-push fra A eller en anden serverændring få B's UI til at fremstå ikke-pending. Det er en konkret scope-egenskab, men serverens autoritative/idempotente accounting skal vurderes af core-audit; man må ikke konkludere dobbeltbetaling ud fra klienten alene.

**Mindste fix, hvis designet ændres:** request/ack correlation eller field/revision-based completion per operation, med timeout fallback; bevar ProtectionClient's session_nonce/revision/idempotency. **Risiko:** mellem/høj for payment UI og protokol; ingen lokal quick-delete. **Regressionsport:** to forskellige queued token actions, unrelated profile push, delayed product receipt, failed request, retry, reconnect og pass-ownership callback. Et request skal først blive enabled igen ved eget ack eller timeout. **Beslutning nødvendig:** er globale pending-clears bevidst ønsket, eller skal UI vise per-action completion?

### C28 — Hazmat foretager body-capture over descendants fem gange i sekundet

**Kategori/prioritet:** profilérbar omskrivning, lav/mellem. **Native:** exact. **Fil:** `HazmatSkinDriver:13,226–237,508,532–540`.

RESCAN_INTERVAL=.2 medfører gentagen captureBody over karakter-descendants for aktive states. Det løser late accessory/rig replication og må ikke bare fjernes. PoseState per frame er også nødvendig for client-owned Motor6D/AnimationConstraint retargeting.

**Mindste fix:** DescendantAdded/Removing dirty capture plus lavere fallback, hvis profiler viser værdifuld gevinst. **Risiko:** mellem ved late rig/accessories, demo wardrobe og restore originals. **Regressionsport:** R6/R15/current constraint rigs, late accessory injection/replication, skin change, lobby demo, streaming teammate, respawn og restore. Mål GetDescendants-count/tid før beslutning. Ingen dokumenteret leak og ingen anbefaling om at fjerne skin-driver.

### C29 — L3 crouch-pose og DJ-pose scanner playerlisten hvert physics/frame-step

**Kategori/prioritet:** lav, valgfri profiling; bevar feature. **Native:** L3 exact, DJ native-only. **Filer:** `Level 3 Table Hiding Client:168–230`; `native:Lobby DJ Client:189–223`.

Begge callbacks skaber Players:GetPlayers-array hvert step og prøver eligibility for alle spillere; L3 bygger også et seen-table. Joint caches og poses er legitime, og all-client presentation er nødvendig, fordi server joint transforms ikke giver den ønskede animation. I store lobbies er det muligt at holde en eligibility-liste opdateret ved PlayerAdded/Removing/CharacterAdded/attr changes og kun steppe aktive/fading poses.

**Mindste fix:** profilér først; hvis nødvendigt, cache active subjects og behold fading/cleanup når crouch/DJ flag slukkes. **Risiko:** mellem for remote player animation/respawn. **Regressionsport:** 1/6/20 spillere, crouch/hide→unhide, DJ-mode toggle, disconnect, R6/R15/constraint rig og streaming. Fjern ikke PreSimulation/Stepped eller de nødvendige transform writes.

### C30 — Tom fil og lokale agent-state JSON er ikke runtime Luau

**Kategori/prioritet:** repo hygiene, lav. **Sti:** `StarterPlayer/StarterPlayerScripts/6430` er tom. `.claude-flow/neural/stats.json` og `.claude-flow/policy/state.json` under samme træ er agent/tool-state, ikke Roblox scripts.

**Mindste fix:** fjern den tomme fil og flyt/ignore tool-state efter root's tooling-audit; native spil har ingen tilsvarende Lua-kilder. **Risiko:** gameplay ingen; lokal agent/toolhistorik kan gå tabt. **Regressionsport:** runtime export indeholder kun intended classes/sources og tooling bootstrap behøver ikke disse statefiler. De er læst/klassificeret særskilt, ikke talt som kodebugs.

### C31 — Den gamle L2 second-pump Dev ESP findes heller ikke i Studio

**Kategori/prioritet:** archive/sync-kandidat, lav gameplayrisiko, mellem toolingrisiko. **Native:** missing_studio. **Fil:** `Level 2 Pool Slide Dev ESP.LocalScript.lua:1–221`.

Klienten er bundet til `Level 2 Generated World`, second-pump giant/tag og de gamle pump-attributter. Den aktive L2 bruger PoolroomsRuntime/PoolroomsMap uden det gamle pump-objective, bekræftet i levels-audit. Kilden er læst helt: gated developer-only, 4Hz polling, local labels/highlights og korrekt Destroying-cleanup; ingen serverrequest og ingen ekstra gameplayfunktion. Men `studio-sync-manifest.json:573–575` forventer fortsat instansen. Historiske pool-slide fixtures/docs peger også på den. En sync kan dermed genskabe et gammelt debug-vindue oven på det nye L2.

**Mindste fix:** tag filen ud af aktiv sync-manifest og arkivér den med gamle second-pump artifacts. Slet først, når tooling/fixtures er migreret. **Risiko:** lav for det aktuelle native spil, mellem for historiske tests/manifest. **Regressionsport:** fresh sync; L2 authored map + native dev-ESP/ordinary controls, ingen PoolSlideDevESPStatus; ingen obsolete client bliver genoprettet. Kørsels-/fmt-tests for historiske second-pump fixtures flyttes med arkivet. Det er en Studio-absence/retired-feature-kandidat, ikke en påstand om at scriptets oprindelige loop er ødelagt.

## Ting, som bevidst ikke anbefales fjernet

- **RoundHud, Round HUD, TeamObjectives remotes:** aktiv central objective/feed/compass/detector presentation. Marker-successor er dokumenteret.
- **UIDevice:** fælles safe-layout, formfactor, glyphs, touch controls og modal ownership; hundredevis af references.
- **UIRegression:** QA ModuleScript med værktøjscallers; kun private døde helpers/data er kandidater.
- **Level 4 Usher Animations:** genererede track-data, caller `Level 4 Round Client:853`; stor linje er ikke bevis på død kode.
- **SlideContinuationSafety:** collision count + ray checks beskytter streaming-containment; aktive L2-slide og world-builder callers.
- **Level 3 Visual Smoother:** bounded sample buffer (8), generation/spawn/sequence checks, .065 s interpolation og .3 s stale fallback; nødvendig client visual smoothing.
- **L3 Table Hiding:** under-table camera og client physics-step crouch/rig transforms; ikke redundant med server hide-state.
- **Level 1 Cable Current:** frame animation har aktiv/rescan guards og bounded bead progression.
- **Level 1 Hardware Client:** render jobs har disconnect/lifetime; et `while true` i animation catch-up er en finite lokal catch-up, ikke automatisk et runaway loop.
- **ReplicatedFirst loading:** seks workers/bounded work, visible callbacks og escape route ved asset/world failure er gameplaykritiske. Ubrugte bindings betyder ikke, at labels er døde.
- **ProtectionClient:** receipt retry/session_nonce/revision guarding er en sikkerhedsgrænse; bevar ved ShopData cleanup.
- **Flashlight teammate visuals:** character ancestry cleanup eksisterer; ingen dokumenteret stale-character leak.
- **L2/L3 sound/light controllers:** retry/polling håndterer streaming, attr races og server property overrides; ikke alle loops bør fjernes.
- **Native Lobby Tunnel Reach:** actively replicerede arm/state attrs, local BulkMoveTo/quantized shading, distance/awake culling, bounded capture/respawn og accessibility. Infinite Ready-wait på reserved round servers er eksplicit dokumenteret og skal ikke kaldes en bug uden at ændre owner-intent/server lifecycle.
- **DevCheats, MasterTuning, DevESP, ZyntraDev:** gating gør det developer-only, men det er aktive features med værktøjscallers; removal kræver produktbeslutning.

## Delte moduler — aktive dependency-hovedspor

| Modul | Aktive callers/funktion |
|---|---|
| DeathAdvice | server death flow, RoundUI, LoadingCardView; death/help hints |
| DevAccess | public/developer preview gates, cheat/tuning/ESP og server access |
| FlashlightProfiles | FlashlightController, ShopDisplay, Spectate, server FlashlightSync |
| Level 2 Entity Audio Bank | Entity Audio/Sound controller; entity voice assets |
| Level 4 Usher Animations | Level 4 Round Client animation presentation |
| LoadingCardView | RoundUI og ReplicatedFirst loading; shared loading-card API |
| MasterConfiguration | GameManager, levels1/3/6 configs, tuning UI/server; coercion/defaults |
| ProtectionClient | ProtectionHUD og ShopData; authoritative protection purchase state |
| RoundHud | objective receivers, reader/detector/level clients; central HUD owner |
| SlideContinuationSafety | L2 Slide Controller og builders; streaming-safe movement |
| UIDevice/UIStyle | shared layout/glyph/control/palette dependencies i de fleste GUI-klienter |
| UIRegression | tools/test entrypoints og Studio QA; public compatibility API |
| ZyntraChallenges | Shop L4 og server Monetization; challenge model/progression |
| ZyntraConfig | storefront, daily, skins, gameplay og server monetization config |
| ZyntraDailyResearch | server monetization profile/daily normalization; ikke runtime-ubrugt selv om klientcallers mangler |
| ZyntraDetectorVisual | ShopDisplay demo, detector client og RoundHud; scene/assets |
| ZyntraShopUI/ShopBinder | GUI mapping/cache for storefront/HUD source templates |
| ZyntraShopUI/ShopData | store/shop/daily; profile/action/receipt/price model |
| ZyntraSkins | wheel/shop/data/server cosmetic & monetization; skin catalog/normalization |

## Regressionsporte for næste session

En oprydningssession bør lave én reviewbar gruppe ad gangen. Først reconcile Studio source og manifest; derefter pure locals/markers; derefter hver runtime-omskrivning separat. En passing compile er ikke nok til en lifecycle/input/streaming-ændring.

1. Native source fingerprints og Disabled-status før/efter; fresh sync må ikke reaktivere retired L6 eller overskrive Studio-only features.
2. Ordinary account og developer; join→lobby→alle offentlige levels→exit/death→respawn; reserveret round server og public L5/L6 flows.
3. Keyboard, gamepad og touch, inkl telefon/tablet med keyboard; 390×844, 568×320, 844×390 og tablet; safe insets; alle shared modals.
4. Multiplayer 6 spillere, characters/teammates streamed sent, accessories/rig constraints sent, opt-in 20-player profile for player-loop ændringer.
5. Streaming model-before-parts, partial stream, stream-out/in; sound asset load failure/forsinkelse; GUI ready efter initial retries.
6. For hver removal: diff med kun intended symbol/block, compile + eksisterende berørte tests; konkret Studio feature-flow som angivet ved fundet.
7. For hver performance-ændring: tællere og MicroProfiler før/efter ved samme scenarie; bevar visuel/audio/state parity. Her er arbejdsfrekvenser statisk bevist, ikke en målt FPS-gevinst.

Root bekræftede baseline compile af 229 repo-sources og 230 native-sources uden compile errors. Studio blev eksternt ændret tilbage til Edit under den korte baseline; ingen removal-trials er udført. Runtimeforløb ovenfor er dermed testplaner for næste session, medmindre root-rapporten særskilt angiver udført bevis.

## Coverage pr. fil

Tabellen nedenfor genereres fra det aktuelle scope-inventar og parity, med læsedybde/feature og native-status. Metadata `.RemoteEvent.txt` er class/property-stubs; de er ikke Luau-implementeringer. Native driftsnapshots er reviewet særskilt efter tabellen.


| Fil | Linjer | Dybde | Native | Feature / review |
|---|---:|---|---|---|
| `ReplicatedFirst/Lobby Loading Screen.LocalScript.lua` | 784 | S | exact | preload workers/progress/cards/readiness/escape; C04,C07 |
| `ReplicatedStorage/DeathAdvice.ModuleScript.lua` | 186 | S | exact | death/hint/control context text |
| `ReplicatedStorage/DevAccess.ModuleScript.lua` | 72 | D | exact | public level/developer allowlist |
| `ReplicatedStorage/FlashlightProfiles.ModuleScript.lua` | 74 | D | exact | shared beam profile/upgrade/level |
| `ReplicatedStorage/Level 2 Entity Audio Bank.ModuleScript.lua` | 80 | S | exact | entity asset/audio tuning catalogue |
| `ReplicatedStorage/Level 2 Pool Foam Remotes/ClientEvent.RemoteEvent.txt` | 5 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 2 Pool Foam Remotes/ClientReport.RemoteEvent.txt` | 5 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 2 Remotes/Level 2 Alert Event.RemoteEvent.txt` | 4 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 2 Remotes/Level 2 Sound Event.RemoteEvent.txt` | 4 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 3 Remotes/ClientEvent.RemoteEvent.txt` | 5 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 3 Remotes/Level3HideRequest.RemoteEvent.txt` | 4 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Level 4 Usher Animations.ModuleScript.lua` | 53 | S | exact | generated track data; active caller traced |
| `ReplicatedStorage/LoadingCardView.ModuleScript.lua` | 196 | D | exact | shared loading-card view helpers |
| `ReplicatedStorage/MasterConfiguration.ModuleScript.lua` | 389 | D | exact | defaults/overrides/coercion/write guards |
| `ReplicatedStorage/ProtectionClient.ModuleScript.lua` | 164 | D | exact | nonce/revision/pending authority + retries |
| `ReplicatedStorage/Remotes/DevControl.RemoteEvent.txt` | 18 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/DevTuning.RemoteEvent.txt` | 18 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/DropGlowstick.RemoteEvent.txt` | 5 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/Jumpscare.RemoteEvent.txt` | 7 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/PuzzleStatus.RemoteEvent.txt` | 7 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/ReportNoise.RemoteEvent.txt` | 10 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/RoundStatus.RemoteEvent.txt` | 7 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/SetCrouching.RemoteEvent.txt` | 4 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/Remotes/ToggleFlashlight.RemoteEvent.txt` | 10 | M | ikke script source | RemoteEvent class/property stub; callers krydssøgt |
| `ReplicatedStorage/RoundHud.ModuleScript.lua` | 1361 | D | exact | objectives/feed/caption/detector/compass; C04,C10 |
| `ReplicatedStorage/SlideContinuationSafety.ModuleScript.lua` | 77 | D | exact | stream collision/readiness/raycast protection |
| `ReplicatedStorage/UIDevice.ModuleScript.lua` | 2040 | S | exact | safe/modal geometry, glyphs/formfactor/touch; C24 |
| `ReplicatedStorage/UIRegression.ModuleScript.lua` | 6608 | S | exact | QA harness/matrix/API; C05,C26 |
| `ReplicatedStorage/UIStyle.ModuleScript.lua` | 268 | S | exact | shared palette/control/text GUI helpers |
| `ReplicatedStorage/ZyntraChallenges.ModuleScript.lua` | 151 | S | exact | challenge reward/progress catalogue |
| `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` | 420 | S | exact | monetization/tasks/perks/constants/assets |
| `ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua` | 36 | D | exact | daily normalization; active server caller |
| `ReplicatedStorage/ZyntraDetectorVisual.ModuleScript.lua` | 265 | S | exact | detector scene/asset construction |
| `ReplicatedStorage/ZyntraShopUI/ShopBinder.ModuleScript.lua` | 839 | S | exact | source GUI mapping/name/path cache |
| `ReplicatedStorage/ZyntraShopUI/ShopData.ModuleScript.lua` | 566 | D | exact | profile/actions/receipts/prices/pending; C27 |
| `ReplicatedStorage/ZyntraSkins.ModuleScript.lua` | 153 | D | exact | skin catalogue/tier/normalize/ownership |
| `StarterPlayer/StarterCharacter/Animate.LocalScript.lua` | 971 | S | exact | default/character animation; C04 |
| `StarterPlayer/StarterCharacterScripts/DanceEmote.LocalScript.lua` | 54 | D | exact | lobby dance + stop lifecycle |
| `StarterPlayer/StarterCharacterScripts/DisableDefaultWalkingSound.LocalScript.lua` | 5 | D | exact | inert compatibility marker; C02 |
| `StarterPlayer/StarterCharacterScripts/SetRunAnimation.LocalScript.lua` | 19 | D | exact; disabled | disabled run-id patch; C03 |
| `StarterPlayer/StarterPlayerScripts/.claude-flow/neural/stats.json` | 6 | M | ikke script source | tom fil/tool-state, ikke runtime Luau; C30 |
| `StarterPlayer/StarterPlayerScripts/.claude-flow/policy/state.json` | 132 | M | ikke script source | tom fil/tool-state, ikke runtime Luau; C30 |
| `StarterPlayer/StarterPlayerScripts/6430` | 0 | M | ikke script source | tom fil/tool-state, ikke runtime Luau; C30 |
| `StarterPlayer/StarterPlayerScripts/Achievements Client.LocalScript.lua` | 296 | S | exact | badges/modal/lobby button/ownership |
| `StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua` | 693 | S | exact | dev fly/ESP/drop/cheats; gated |
| `StarterPlayer/StarterPlayerScripts/EntityShakeController.LocalScript.lua` | 214 | D | exact | entity proximity shake, bob/crouch, accessibility |
| `StarterPlayer/StarterPlayerScripts/First Entry Guide.LocalScript.lua` | 7 | D | drift | repo inert / native active WELCOME+HELP; C01,C06,C21–25 |
| `StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua` | 825 | D | exact | own/mate beam, battery, widget and net state; C11–14 |
| `StarterPlayer/StarterPlayerScripts/Found Footage HUD.LocalScript.lua` | 249 | S | exact | clock/telemetry + prompt pooling |
| `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua` | 329 | S | exact | friends/party boost chip + paging |
| `StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua` | 580 | S | exact | skin/body/rig overlay and restore; C28 |
| `StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua` | 182 | D | exact | head-camera capture, cover, controls/respawn; C08 |
| `StarterPlayer/StarterPlayerScripts/Level 1 Cable Current.LocalScript.lua` | 269 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 1 Hardware Client.LocalScript.lua` | 304 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 1 Sound Controller.LocalScript.lua` | 98 | D | drift | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 2 Entity Audio.LocalScript.lua` | 460 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 2 Lighting Controller.LocalScript.lua` | 156 | D | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 2 Objective UI.LocalScript.lua` | 54 | D | exact | exit objective + watched subject/retry; C10 |
| `StarterPlayer/StarterPlayerScripts/Level 2 Pool Foam Client.LocalScript.lua` | 493 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 2 Pool Slide Dev ESP.LocalScript.lua` | 221 | D | missing_studio | retired second-pump debug-client, manifest stadig aktiv; C31 |
| `StarterPlayer/StarterPlayerScripts/Level 2 Slide Controller.LocalScript.lua` | 825 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua` | 1043 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 3 Lighting Controller.LocalScript.lua` | 1185 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 3 Mall Manager Visual Smoother.LocalScript.lua` | 211 | D | exact | bounded samples/interpolation/reset checks |
| `StarterPlayer/StarterPlayerScripts/Level 3 Reader Client.LocalScript.lua` | 753 | D | exact | reader controls/upgrades/UI/audio; C04 |
| `StarterPlayer/StarterPlayerScripts/Level 3 Sound Controller.LocalScript.lua` | 1215 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 3 Table Hiding Client.LocalScript.lua` | 497 | D | exact | crouch rig/under-table camera/interaction; C04,C29 |
| `StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller.LocalScript.lua` | 331 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level 4 Round Client.LocalScript.lua` | 1165 | S | exact | Usher/note/code/keypad/objective visuals |
| `StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua` | 833 | D | drift | native roof/void/fall/rolling audio; C01,C19 |
| `StarterPlayer/StarterPlayerScripts/Level 6 CD Dev ESP.LocalScript.lua` | 188 | S | missing_studio | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level 6 Lighting Controller.LocalScript.lua` | 1154 | S | missing_studio | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level 6 Mall Manager Visual Smoother.LocalScript.lua` | 211 | S | missing_studio | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level 6 Playground Client.LocalScript.lua` | 1348 | S | exact | active doll/playground/score/death/preview |
| `StarterPlayer/StarterPlayerScripts/Level 6 Reader Client.LocalScript.lua` | 1233 | S | exact; disabled | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level 6 Sound Controller.LocalScript.lua` | 1215 | S | exact; disabled | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level 6 Table Hiding Client.LocalScript.lua` | 515 | S | missing_studio | pensioneret genereret L6, archival/dependency review; C03 |
| `StarterPlayer/StarterPlayerScripts/Level2AlertClient.LocalScript.lua` | 47 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/Level2PoolroomsPresentation.LocalScript.lua` | 329 | D | exact | authored grade/camera clamp/lamp flicker; C20 |
| `StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua` | 40 | D | drift | native public5/6 policy + L4 developer filter; C01,C06 |
| `StarterPlayer/StarterPlayerScripts/Level6PreviewTransport.LocalScript.lua` | 58 | D | drift | native public Playground stream+arrival ack; C01 |
| `StarterPlayer/StarterPlayerScripts/LobbyCeilingSweeps.LocalScript.lua` | 182 | S | exact | sweep light/accents |
| `StarterPlayer/StarterPlayerScripts/LobbyLevel3GateFlicker.LocalScript.lua` | 153 | S | exact | gate flicker/accessibility |
| `StarterPlayer/StarterPlayerScripts/LobbyMusicController.LocalScript.lua` | 310 | S | exact | normal lobby playlist/readiness/settings/SoundGroup |
| `StarterPlayer/StarterPlayerScripts/LobbyReimaginedQueueController.LocalScript.lua` | 97 | S | exact | queue prompts/signage |
| `StarterPlayer/StarterPlayerScripts/Lucky Wheel Client.LocalScript.lua` | 974 | S | exact | spin/reward modal + skins/receipts |
| `StarterPlayer/StarterPlayerScripts/MasterTuningClient.LocalScript.lua` | 308 | S | exact | developer tuning/config UI/remotes |
| `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua` | 1014 | S | exact | sprint/crouch/noise/touch/movement + server reports |
| `StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua` | 925 | S | exact | runtime feature efter filnavn; source/symbol/caller/loop scan |
| `StarterPlayer/StarterPlayerScripts/PuzzleUI.LocalScript.lua` | 113 | S | exact | puzzle status/minigame UI |
| `StarterPlayer/StarterPlayerScripts/R4DevGateController.LocalScript.lua` | 363 | D | drift | native public5/6 queue gates/signage; C01 |
| `StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua` | 149 | S | exact | arrival/loading/dispatch/teleport state |
| `StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua` | 443 | D | exact | exit/confirmation/prompts/input; C04 |
| `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua` | 305 | D | exact | status/event receiver and shared HUD driver |
| `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua` | 5339 | S | final exact; eksternt ændret under audit | party/queue/dispatch/ending/reentry/loading owner; se final source-note |
| `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` | 754 | D | exact | world demo/purchase prompts/bob; C09 |
| `StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua` | 1659 | S | exact | movement/alert/chase/UI/audio; Running mute |
| `StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua` | 413 | S | exact | camera/target/audio/late character state |
| `StarterPlayer/StarterPlayerScripts/Team Objective Feed.LocalScript.lua` | 2 | D | exact | inert compatibility marker; C02 |
| `StarterPlayer/StarterPlayerScripts/Zyntra Daily L4.LocalScript.lua` | 805 | S | exact | daily reward/streak/claim modal |
| `StarterPlayer/StarterPlayerScripts/Zyntra Dev L4.LocalScript.lua` | 1103 | S | exact | developer terminal/settings/preview |
| `StarterPlayer/StarterPlayerScripts/Zyntra Shop L4.LocalScript.lua` | 1899 | S | exact | terminal catalogue/action/profile/receipt UI |
| `StarterPlayer/StarterPlayerScripts/ZyntraDetectorClient.LocalScript.lua` | 59 | D | exact | mount visual/modal suppression |
| `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua` | 1350 | S | exact | rail/store/options/profile/purchases; C07 |

### Native snapshots reviewet separat

| Snapshot under studio-sources/StarterPlayer/StarterPlayerScripts | Linjer | Dybde | Review |
|---|---:|---|---|
| `First Entry Guide.LocalScript.lua` | 566 | D | WELCOME/HELP/replay/spawncamera; C01,C06,C21–25 |
| `Level 1 Sound Controller.LocalScript.lua` | 99 | D | preview guard; C01 |
| `Level 5 Lighting Controller.LocalScript.lua` | 902 | D | native diff+roof/fall/audio lifecycle; C01,C19 |
| `Level4PreviewPrompt.LocalScript.lua` | 38 | D | public5/6 policy + no-op; C01,C06 |
| `Level6PreviewTransport.LocalScript.lua` | 58 | D | public Playground stream/model/ack; C01 |
| `R4DevGateController.LocalScript.lua` | 363 | D | public5/6 access/signage; C01 |
| `Lobby DJ Client.LocalScript.lua` | 341 | D | hele source chunks: audio/lights/pose/access/booth; C15–18,C22,C24,C29 |
| `Lobby Tunnel Reach Client.LocalScript.lua` | 647 | D | alle centrale chunks: rig/capture/respawn/shading/sound/culling |
| `Level 6 Dev ESP.LocalScript.lua` | 104 | D | hele source: allowlist/kill-cover/mark cleanup/players+doll+button |

### Coverage-afgrænsning

Inventaret indeholder 86 Luau sourcefiler, 15 RemoteEvent-stubs og 3 øvrige filer. Alle er inventeret/læst/scannet med angivet dybde. Ingen kilde var nul/trunkeret bortset fra bevidst tomme `6430`; First Entry Guide-repo er en marker, ikke en komplet native kopi. Native snapshots er fetched/verified af root. Studio-inventory kan tælle +1 ved trailing newline.

Pensionerede L6-filer er primært vurderet for afhængigheder/sikker arkivering, ikke ny dyb correctness-audit af deres gamle gameplay. UIRegression/generated Usher-data er strukturelt gennemgået; API/callers og fundenes konkrete blokke er dybt krydset. RoundUI, UIDevice, NoiseReporter og store/daily/shop-terminalernes øvrige store branches er strukturelt scannet med hotspots, ikke alle manuelt valideret i runtime. Dette er en eksplicit begrænsning; ingen anbefaling om branch-sletning udledes af filstørrelse.

### Offline baseline fra root

15 udvalgte check-entrypoints: 12 pass, 3 fail. Passing: ControllerInput, RoundHudShared, UIRegressionShared, L4 queue-choice/clear-persistence, reentry-dismissal, speed-potion, friend boost, spectate audio, route markers, purchase relay og token grants. FirstEntryGuide-checks forventer en anden repo-profilguide og fejler mod den inerte marker; dette beviser ingen bug i den aktive native guide. Support-receipt harness mangler ZyntraSkins; item-inventory bootstrap fejler på nil content. Root/core-audit beskriver disse begrænsninger; se `selected-checks.json`/`test-logs`. C21–25 er begrundet direkte i native source/contracts, ikke i denne gamle testfejl.

### Final source-note — ekstern RoundUI-opdatering under audit

Root's afsluttende native recheck fandt to eksternt ændrede scripts: GameManager og RoundUI; øvrige 228 native scripts havde samme fingerprint. RoundUI ændrede LF-source fra 238388 til 238896 bytes. Den nyeste verificerede kilde er `studio-final-sources/StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua` (5339 tekstlinjer; SHA256 `98d2c871dd5cbd33e3a0d633e6afcc3a7a0012c777418bd57cc272c5f35eb5dc`). Aktuel repo-RoundUI matcher denne efter newline-normalisering. RoundUI-rækken ovenfor gælder dette final mirror.

Den før/efter-diff, der blev forsøgt skrevet, er tom, fordi repo også var eksternt opdateret. De tidligere bytes/fingerprints er bevaret i inventaret, men den oprindelige komplette RoundUI-kopi er ikke bevaret i snapshot-mappen. Derfor kan den præcise eksterne patch ikke rekonstrueres ud fra dette artifact alene, og der udledes ingen ny bug/removal-kandidat af dens størrelse.

Den aktuelle continuation/choice-state blev læst særskilt: `completion.applyChoices`:1508–1521 afviser forkert serial, ikke-stigende revision og skjult choice-window; Closed sætter pending. `completion.suspend`:1503–1507 deaktiverer begge knapper og afleverer controller-focus. Activate:1614–1630 validerer pending, visibility, serial, deadline, action, nextLevel og .15s click-rate, og sender serverSerial. Returnpending:4102–4107 kræver matching serial; continuefailed/returnfailed:4113–4137 re-armer kun matching serial før deadline; transitionfailed:4139–4144 suspenderer valget. Disse concurrency/lifecycle-guards skal bevares ved cleanup. Serverens tilsvarende final GameManager-flow vurderes i core-audit.

Dette er en statisk rådgivende recheck af den aktuelle kilde. Der er ingen ny removal-test eller runtimegaranti; C01–C31 i uændrede klient/shared-kilder beholder deres evidens og regressionsporte. Bevar final snapshots/changes-inventory i handoff, så næste session ikke bruger den tidligere source-identitet som aktuelle sandhed.
