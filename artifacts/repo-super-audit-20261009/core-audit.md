# Core runtime, lobby, Studio-only serverfunktioner og Workspace — read-only audit

Dato: 2026-10-09. Der er ikke rettet, slettet, deaktiveret eller erstattet eksisterende kode i denne del af analysen. Denne fil er en handoff, ikke et gennemført oprydningsforsøg.

**Studio er source of truth.** Når Studio og repo afviger, henviser fund til den eksporterede Studio-kilde. `N/` nedenfor betyder `artifacts/repo-super-audit-20261009/studio-sources/ServerScriptService/`. Andre serverstier er under `ServerScriptService/`. Et filnavn uden `N/` er sammenlignet som identisk med Studio, medmindre andet udtrykkeligt står. Repoets gamle Level5/6PreviewAccess beskriver ikke længere hele det aktive spil. GameManager blev ændret af en anden session under analysen; alle GameManager-henvisninger gælder den afsluttende native kilde `studio-final-sources/ServerScriptService/GameManager.Script.lua`, som også er identisk med den senest læste repo-fil. Den eksterne rettelse af Studio `failPendingTeleport` → `releaseUndispatchedClaims` er allerede med og er ikke et åbent audit-fund.

Denne del omfatter alle top-level serverfiler uden levelgeneratorerne, hele LobbyReimaginedPreview, seks Studio-only serverfiler, Workspace-scripts og pluginet. Level1–6-systemerne, klientkode, arkiver og værktøjer har separate delrapporter. Kald og eventkontrakter er sporet på tværs af disse områder, hvor de er nødvendige for et fund.

## Beslutningsregel til næste session

- **Ret fejl:** aktiv kode med et konkret svigtforløb. Dette er normalt en lille rettelse eller et afgrænset redesign, ikke sletning af funktionen.
- **Fjern afgrænset kode:** lokalt ubrugt kode eller arbejde, hvis resultat destrueres før publicering. Behold de nævnte kontrakter og regressionstest.
- **Kandidat, kræver beslutning/test:** historiske sikkerhedsnet, admin-API'er og fallbackverdener. Manglende interne callers alene beviser ikke, at en ejer aldrig anvender dem i Command Bar.
- **Bevar:** funktioner, der er aktive eller beskytter økonomi, routing, multiplayer, collision eller world lifecycle.

P1 betyder risiko for fastlåst spilflow eller tab/dobbeltkreditering af købte credits/items. P2 er en konkret robustheds-, informations- eller belastningsfejl. P3 er oprydning, betinget pensionering eller en optimering, hvor gevinsten skal måles. Ingen kandidat nedenfor er certificeret med en faktisk kodefjernelse i Studio.

## Aktive featurekontrakter

| Område | Aktiv sammenhæng | Konsekvens for oprydning |
|---|---|---|
| Lobby | GameManager → TunnelLobbyBuilder → færdig shop → LobbyReimaginedPreview.Builder → flyttet canonical spawn | Den gamle builder er stadig boot-afhængighed og fallback. |
| R4-lobbykøer | QueueBridge bygger ID 101–124; GameManager registrerer dem og ejer admission/countdown | `preview` i navnet betyder ikke ubrugt. Level5/6 har aktive launchers. |
| Level1–4 | GameManager, Round Loading Runtime, Round Completion Routing, adaptere og lifecycle | Routing og bounded loading må ikke erstattes med en simpel teleport-loop. |
| Level5/6 | Native PreviewAccess, ServerKind, Live Level Server og QueueBridge | Public gameplay med egne reserverede lobbyservers og lokal fallback. |
| Økonomi | ZyntraMonetization, server-Bindables, entitlement/receipt/session leases, client profile | Gamle profilfelter og receipts kan være nødvendige, selv om en feature er pensioneret. |
| Re-entry/items | Monetization → ZyntraReentry/ZyntraInventory → runtime | Købt credit/item skal håndteres korrekt på tværs af yields, disconnect og uklart commit-resultat. |
| Leaderboards | ZyntraLevelCompleted for 1–4; LevelTimeReported for 5/6 | Begge eventveje er aktive; deres regler er forskellige. |
| Shop/skins | LobbyShopDisplay → HazmatSkinVisuals/Skins og monetization | Renderkode, previews og spillernes gameplay-suit har forskellige livscyklusser. |
| Støj/AI | NoiseRegistry → Level1 AI og Level4 usher | Et legacy Level2-flag gør ikke hele registry-modulet dødt. |
| Level3 warmup | Studio-only Level 3 Kit Warmup → Level6BlenderRuntimeBake/kit metadata | En Level6-oprydning kan også ødelægge Level3. |

## Konkrete fejl: ret aktiv kode

### CORE-001 — P1: Level4 tilbyder continuation til Level5, men access-check afviser den

**Kode/evidens:** final native `GameManager.Script.lua:159–190`, `:2122–2125`, `:2181–2187`, `:2588–2602`; `Round Completion Routing.ModuleScript.lua:47–49`; native `N/ServerKind.ModuleScript.lua:124–144`. Ved Level4-clear reserverer intermission en live Level5-server og sætter nextLevel=5. `teleportPlayersToNextLevel` kalder imidlertid `canAccessLevel` før live-server-descriptoren. MaxLevel og DevMaxLevel er begge 4; med LEVEL4_PUBLIC=true returnerer devCeiling altid 4. Gruppen afvises, inden den registrerede Level5-overgang nås. Access-checket er genlæst efter den eksterne ændring og fundet består.

**Mindste fix:** adskil adgang til en verificeret live-level continuation fra adgang til campaign-generators. Kontroller descriptor, level, eksisterende reservation og relevant adgangspolitik; behold campaigngrænsen på 4. **Risiko:** høj ved at hæve MaxLevel globalt, fordi den almindelige generator-rute ikke har en Level5-generator. **Test:** production-lignende reserveret Level4 med to finishers; Continue, automatisk countdown og Return; reservation-fejl skal fortsat give sikker lobby/eksisterende policy. Statisk fund; denne overgang er ikke live-testet.

### CORE-002 — P1: én spiller uden levende karakter kan fastholde hele live-level-partiet ubegrænset

**Kode/evidens:** native `N/Live Level Server.Script.lua:181–204`. `ready` kræver `standing(player)` samt client-ready eller alder >35 sekunder. Den 45-sekunders launch-grænse kontrolleres kun inde i `#waiting > 0 and allReady`. En ankommet spiller uden karakter, humanoid/root eller liv gør allReady=false og forhindrer også timeout-launch for de raske medlemmer. `LiveLevelPending` sættes ved admission og ryddes ved launch, som aldrig nås i dette forløb.

**Mindste fix:** en absolut cohort-deadline og et individuelt terminalt load-resultat. Afvis/ryd den fejlede spiller og launch den gyldige rest efter den vedtagne party-policy. **Risiko:** middel; må ikke splitte et gyldigt parti under normal streaming. **Test:** to spillere, én permanent manglende/dead karakter; efter deadline er alle covers terminale og den raske spiller kan komme ind. Test også alle fejler og sen CharacterAdded.

### CORE-003 — P1: re-entry debit/refund har ikke holdbar operationsidentitet

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:3065–3127`, `:1335–1405`, `:4572`. Reservationen trækker én credit med almindelig `mutate`; tokenet findes kun i `reentryAttempts` i RAM. `mutate` anvender en local lock og UpdateAsync, men tilføjer ingen durable operations-ID eller expected revision til denne delta. Hvis store-write bliver committet, men kaldet melder fejl, returneres false uden re-entry eller holdbar recovery. Refund er en ubetinget `+=1`, genforsøgt op til tre gange. Et refund-commit med tabt svar efterfulgt af retry kan derfor give ekstra credit. Kommentar `:3111–3115` beskriver replay-risikoen, men bounded retry giver ikke dedupe. Hvis player-finalizeren rydder tokenet mens reentry.Invoke yield'er, springer det senere negative svar refund-blokken over. Dette er statisk identificerede failure-scenarier; tab eller dobbeltgrant er ikke reproduceret mod production.

**Mindste fix:** persistér en operations-ID og reservation/settlement-status, og gør debit, refund og recovery idempotente. Brug den eksisterende holdbare transaction-tankegang fra protection/andre idempotente grants, ikke blind retry af en delta. **Risiko:** høj; økonomi skal ændres med fixture/migration-review. **Test:** fake store, der *committer og derefter kaster fejl*, for debit og refund; Invoke=false/exception; disconnect midt i Invoke; gentaget recovery ved næste load. Præcis én credit netto og én terminal operation. Den eksisterende happy-path re-entry-test beviser ikke disse forløb.

### CORE-004 — P1: samme uklare commit-resultat kan bruge et inventory-item uden dets effekt

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:3580–3620`, `:3894–3916`, `:3354–3406`. SpeedPotion og inventory `Consume` bruger `dailyMutate` til en item-delta og anvender først effekt/returnerer success efter et positivt resultat. Daily.FlushId deduper kun playtime-deltaen ved `:3371–3376`; body køres altid ved `:3378`, og item-operationen har ingen egen holdbar ID/revision. Protection-/mute-revisioner findes i andre kontrakter og beskytter ikke denne item-path. Ved commit efterfulgt af fejl er itemet brugt i save, men caller får failure og kan ikke anvende effekten. `useSpeedPotion` forbruger også bevidst potionen, hvis runden slutter under write, men undlader effekten efter epoch-check. Committed-lost-response er et statisk failure-scenarie, ikke et demonstreret production-tab.

**Mindste fix:** durable operation-ID og idempotent settlement. Beslut eksplicit policy for round-end mens en potiontransaktion er i gang; undgå utilsigtet lobby-speed. **Risiko:** høj ved generisk inventory-rewrite. **Test:** committed-lost-response for potion/marker og delayed commit over RoundEpoch-skift; én item-delta, én effekt eller én verificeret refund. Bevar eksisterende per-round potion-grænse.

### CORE-005 — P2: RouteMarker kan publiceres efter round-cleanup

**Kode/evidens:** `RouteMarkerService.Script.lua:236–263`, `:295–296`. Geometrien gemmes før inventory.Invoke, som kan yield'e. RoundActive=false rydder eksisterende markers. Et forsinket success-svar opretter bagefter en ny marker ved den gamle position, selv om cleanuppen allerede er gennemført og næste runde kan være startet.

**Mindste fix:** gem round/epoch, og revalider denne efter consume-yield før publicering. En afvist placering efter et gennemført debit kræver idempotent refund/settlement fra CORE-004. **Risiko:** middel; death i samme runde er bevidst understøttet og må ikke utilsigtet afvises. **Test:** suspendér inventory-success; slut runden/start ny; ingen gammel marker og præcis én korrekt item-afregning. Test normal death i samme epoch særskilt.

### CORE-006 — P2: fejlede accessibility saves bliver markeret færdige

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:3251–3298`, `:4492–4495`. Worker sætter dirty=false før `writeAccessibilityTargets`, ignorerer returnværdien og stopper efter dens retries. Local preference/UI kan være accepteret, men den ønskede state er ikke saved. Finalizeren skriver kun hvis dirty=true, så en tidligere fejlet write genforsøges heller ikke ved leave.

**Mindste fix:** versionér den ønskede state og ryd kun dirty for en version, hvis write faktisk lykkes. Bounded retry og afsluttende snapshot skal håndtere in-flight job sikkert. **Risiko:** middel; bevare coalescing og write floor. **Test:** tre save-fejl, derefter recovery/leave; ønsket state survives reload; samtidig nyt toggle skal vinde over gammel worker.

### CORE-007 — P2: ukendte remote action-navne kan udvide rate-limit-tabellen uden grænse

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:3951–3996`. Der kontrolleres string-type, men ingen whitelist før `windowKey=action` og `times[windowKey]=now`. Payload-nøgler er korrekt begrænset af kataloger, men en klient kan sende stadig nye action-strenge og skabe en permanent entry for hver, indtil den forlader serveren. Tidsvinduet begrænser hver streng, ikke antallet af strenge.

**Mindste fix:** reject ukendt action før allocation; behold eksisterende per-action/per-catalog-buckets. **Risiko:** lav med en komplet actionliste. **Test:** mange unikke ukendte action-navne giver nul vækst; alle legitime actions, hurtige forskellige køb/toggles og protection/mute særveje virker fortsat.

### CORE-008 — P2: profile RemoteFunction mangler et bounded svarbudget pr. spiller

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:2699–2702`. Hvert Invoke venter op til ti sekunder, hvis profile ikke er loaded, og genererer derefter et enriched profile-svar. Ingen local in-flight gate/rate-limit. En klient med mange samtidige Invokes opretter mange ventende workers under et slow/failed load.

**Mindste fix:** ét delt readiness-resultat/cached snapshot, kort fejl/loading-svar og en lille per-player gate. **Risiko:** lav/middel; klientens første profile-load/retry skal fortsat være responsivt. **Test:** 100 parallelle Invokes under slow load og efter disconnect; bounded ventende arbejde og korrekt profile efter recovery.

### CORE-009 — P2: Level4 analytics normaliseres til `other`

**Kode/evidens:** `ZyntraAnalytics.ModuleScript.lua:59–60`, `:125–136`. levelTag producerer L4, men ALLOWED indeholder kun L0–L3. fields anvender value(), som ændrer L4 til other. Aktiv public Level4 mistes dermed som separat attribution i disse events.

**Mindste fix:** optag L4; udvid kun til L5/6, når deres eventintegration er defineret. **Risiko:** lav. **Test:** inject analytics service og kontroller L1–L4 custom fields uden at sende live analytics.

### CORE-010 — P2: glowstick readiness bruger et nyt ti-sekunders budget for hvert medlem

**Kode/evidens:** `GameManager.Script.lua:442–447`, `:3518–3525`, `:4184`. Party entry har ét samlet 60-sekunders loading-budget, men `assignGlowstickSlots` venter serielt med et separat ti-sekunders deadline pr. spiller. Seks uløste profile/entitlement-readiness checks kan bruge hele budgettet, inden resten af load-preparation starter.

**Mindste fix:** fælles readiness-deadline eller parallel readiness med deterministisk fallback-slot. **Risiko:** middel; cosmetic ownership/color må ikke blandes mellem medlemmer. **Test:** seks profile-loads uden svar; alle får bounded fallback og load forsøges inden entry-deadline. Test blandet rækkefølge og leave under ventetiden.

### CORE-011 — P2: assisterede Level5/6-tider har en anden leaderboard-policy end Level1–4

**Kode/evidens:** native `N/Level Leaderboards.Script.lua:77–89` filtrerer `run.DevTouched` på ZyntraLevelCompleted, men LevelTimeReported tager kun player, level, seconds. Native Level5 finale rapporterer direkte ved `N/Level5PreviewAccess.Script.lua:1177`; Level6 finale ved `N/Level 6 Systems/Level 6 Playground Game.ModuleScript.lua:1601–1602`. Developer free-reentry er adgangsbeskyttet, men rapporteringen har ingen aided/dev flag.

**Mindste fix:** definér samme godkendte run-metadata-kontrakt for 5/6 og filtrér de tilsigtede debug/assisted runs på serveren. Dette er policy, ikke bevis for, at almindelige spillere kan kalde serverens Bindable. **Risiko:** middel; ejer skal vælge, om normale købte hjælpemidler diskvalificerer. **Test:** developer free-revive/debug assisteret run vises ikke, hvis policy siger det; almindeligt rent run gemmes; ingen klient kan vælge aided=false.

## Loops, hukommelse og unødvendigt arbejde

### CORE-012 — P2: party-mode finder de samme lights 20 gange i sekundet

**Kode/evidens:** `LobbyPartyModeController.Script.lua:21–41`, `:103–104`, `:127–156`. En cirka ti-sekunders party-loop samler/sorterer ceiling lights hvert .05 sekund, selv om palette skifter langt sjældnere. Promptopdatering scanner desuden hele Workspace ved state/paletteskift. Cirka 200 light-discovery scans pr. aktivering; dette er en statisk arbejdsmængde, ikke en målt FPS-regression.

**Mindste fix:** cache ejede lights og allerede bundne prompts; invalidér ved de faktiske lobby/descendant lifecycle-events. **Risiko:** lav/middel; rebuild og gamle lights må ikke hænge i cache. **Test:** aktivering, spam, lobby-rebuild og fjernet prompt; samme farver/cooldown, ingen property writes til destruerede instanser. Mål profiler før/efter.

### CORE-013 — P2: kømotoren scanner spillerroster for hver station på hver Heartbeat

**Kode/evidens:** `GameManager.Script.lua:3659–3815`, `:3818–3955`, `:4010`, `:4194`; `TunnelLobbyBuilder.ModuleScript.lua` bygger de oprindelige 16 Level1–4-stationer, native QueueBridge bygger yderligere 24. GameManager bevarer begge samlinger. Capacity enforcement kører per station på Heartbeat; hver station har også en .25-sekunders state-loop. Afhængigt af station-state gentages roster/root, zone, ordering og afvisningsarbejde. Den gamle verden er fortsat fallback, ikke inaktiv kode.

**Mindste fix:** ét snapshot af players/current roots pr. enforcement-tick, del genbrugelige zoneberegninger og behold admission-epoch checks. Lavere frekvens kræver særskilt reach/kapacitets-test; må ikke bare fjerne Heartbeat-barrieren. **Risiko:** middel/høj; multiplayer fairness, host cleanup og reset er følsomt. **Test:** seks samtidige køer, overlap, private friends, syvende indtrænger, respawn/leave og R4 model replacement; mål calls/tick og server-profiler med 20+ spillere.

### CORE-014 — P2: FriendBoost-cachen beholder historiske spillerpar

**Kode/evidens:** `FriendBoost.ModuleScript.lua:45–62`, `:174–175`. Kun unresolved pairs bliver queried, hvilket er nyttigt, men positive/negative par bliver i friendships for serverens levetid. PlayerRemoving republisher, men rydder ikke par med den afgående UserId. Hukommelsen vokser med par, som har mødt hinanden gennem serverens samlede roster-churn; den er ikke begrænset af aktuel MaxPlayers.

**Mindste fix:** ryd par når et medlem forlader, eller brug en bounded TTL/cache med safe in-flight resolution. **Risiko:** lav/middel; race under async friendship-resultat. **Test:** mange join/leave-cyklusser; cache bounded og samtidig roster-revision bevarer korrekt multiplier. Den eksisterende friendboost-test skal fortsat passere.

### CORE-015 — P3: friend-only køer har en separat friendship-cache og queryvej

**Kode/evidens:** `GameManager.Script.lua:1402`, station.friendCache og reset ved `:3592`; `FriendBoost.ModuleScript.lua:53–62`. To funktioner udfører samme friendship-relation med hver sin cache; køen bruger IsFriendsWith, FriendBoost den async variant. Der er ikke grundlag for at slette FriendBoost, som bestemmer den serverberegnede token-multiplier.

**Mindste fix:** genbrug en fælles relation-resolver med readiness/failure-contract og recheck host/epoch efter yield. **Risiko:** middel; private køer må aldrig åbne på failed lookup. **Test:** host skifter/forlader midt i lookup, true/false/error og to stationer med samme par.

### CORE-016 — P3: Crouch State beholder character-connections indtil PlayerRemoving

**Kode/evidens:** `Crouch State Server.Script.lua:18`, `:72–113`. Hver ny karakter tilføjer state/death/attribute/Anchored-forbindelser til spillerens connections-liste. Disconnect af hele listen sker først ved leave. Destruerede instansers signaler kører ikke videre, men Lua-listen beholder connection-objekter pr. respawn.

**Mindste fix:** separat character-bag, som disconnectes/ryddes ved CharacterRemoving eller før bind af ny karakter. **Risiko:** lav; player-level remote/CharacterAdded forbindelser skal leve videre. **Test:** 50 respawns; listeantal stabilt, crouch og round transitions virker på den nyeste karakter alene.

### CORE-017 — P3: glowsticks har tidscap, men intet antalcap

**Kode/evidens:** `GameManager.Script.lua:457–516`. Der kan droppes hver femte sekund, Debris-levetid er 1.200 sekunder, og hver stick omfatter serverejet fysisk Part samt lys/trail/attachments. Seks aktive medlemmer kan teoretisk skabe cirka 1.440 sticks over den levetid. Breadcrumbs er en bevidst gameplay-feature.

**Mindste fix:** ejer-/party-FIFO med aftalt antal, eventuelt fade af de ældste; behold runde/leave-cleanup. **Risiko:** middel og gameplay-valg; et aggressivt cap reducerer orienteringshjælpen. **Test:** maksimumrunde med seks spillere, spam/cooldown og cleanup; mål aktive physics/light count. Ingen measured latency-fordel hævdes her.

### CORE-018 — P3: PurchaseAlerts har en ubounded RAM-dedupe

**Kode/evidens:** `PurchaseAlerts.ModuleScript.lua:150–151`. Notifications-køen er bounded, men seen[purchaseId] sættes permanent i serverens levetid. Et langlivet serverjob med mange køb beholder alle IDs.

**Mindste fix:** bounded TTL/size for *notification*-dedupe. **Risiko:** lav; må ikke anvendes på den permanente økonomiske receipt-dedupe i profilen. **Test:** flere alerts end cap og gentaget nylig ID; ingen ekstra penge/credits og kun tilsigtet notifications-adfærd.

### CORE-019 — P3: PurchaseAlerts-rategrænsen tæller alerts, ikke HTTP-attempts

**Kode/evidens:** `PurchaseAlerts.ModuleScript.lua:23–24`, `:107–126`. rateGate kaldes før retry-loop; tre retry-attempts for hvert tilladt alert kan derfor blive op til tre gange det nominelle 20/minut HTTP-workload. Dette er kun en fejl, hvis RATE_LIMIT er ment som request-limit.

**Mindste fix:** ejer vælger alert- eller requestgrænse; ved requestgrænse placeres gate pr. attempt. **Risiko:** lav/middel; shutdown-drain skal forblive bounded. **Test:** HTTP fejler tre gange per alert; total requests pr. vindue følger vedtaget policy. Ingen webhook sendt i denne audit.

### CORE-020 — P3: Flashlight aim gentager uændret mount/profile-arbejde

**Kode/evidens:** `FlashlightSync.Script.lua:125–141`, især `:139–140`. Aim opdateres løbende; samme handler laver igen mount-name/profile-opslag og sætter lysproperties, der normalt er uændrede mellem aim-pakker. Rotation/retning skal fortsat opdateres; profile/mount kan cachees ved ændringer.

**Mindste fix:** opdatér statiske mount/light-properties ved character/profile/attribute ændring, og behold kun aim-geometri i den hurtige vej. **Risiko:** middel; skift af skin, equipment og accessibility skal invalidere cache. **Test:** normal flashlight, alt skin/mount, color/intensity-setting, death/reentry og reconnect; mål writes/sekund.

### CORE-021 — P3: Luna udfører idle propertywrites hvert Heartbeat

**Kode/evidens:** native `N/LunaTribute.Script.lua:263`, `:287–326`; native-versionen har desuden aktiv achievement/reward-integration. AlignPosition/AlignOrientation targets skrives hver frame også under stationære sleepperioder. Når ingen action-animation kører, kalder den stationære idle-vej desuden setLoco/AdjustSpeed igen, selv om idle-track og speed er uændrede. Sleep-action undertrykker netop locomotion-blokken; dens animation er derfor ikke et AdjustSpeed-spamfund.

**Mindste fix:** sammenlign target før propertywrite, og kør state-transitionarbejde ved faktisk ændring; behold physics constraints. **Risiko:** lav/middel; følgeadfærd, sleep/wake, tribute og reward er aktive. **Test:** lange idleperioder, ny spiller, pet/follow, sleep/wake og tribute-grant én gang. Hele Luna-scriptet skal bevares.

### CORE-022 — P3: PushDoors arbejder 20 gange/sekund også uden relevante spillere

**Kode/evidens:** `Workspace/Level 4 Cinema Blender/Doors/PushDoors.Script.lua:107–159`, .05-sekunders loop og nærmeste-spiller-søgning. Scriptet følger den aktive authored map og er ikke blot en testfil. Det tager spiller/character-roster igen og beregner door proximity under perioder, hvor ingen er nær biografen.

**Mindste fix:** delt character-snapshot, grov map-proximity/empty-roster pause, mens døre under closing stadig får deres updates. **Risiko:** middel; ingen ændring af collision/hinge/network ownership uden særskilt behov. **Test:** to spillere på hver side, døren åbner/lukker igen, spiller forlader, public Level4 og developer entry; profiler uden biografspillere.

### CORE-023 — P3: runtime mesh-bake har store synkrone batches

**Kode/evidens:** `LobbyReimaginedPreview/RuntimeBake.ModuleScript.lua`, vertex/normal-loops og chunked triangle-loop. De nødvendige mesh-data behandles ved first build; vertex/normal-faser kan have store batches uden yield. Dette er en startup/load-optimering, ikke bevis for løbende dead loop.

**Mindste fix:** bounded chunking med bevaret shared job/cancellation/budget. Permanent installerede assets er en større deploymentbeslutning og kræver autorisation i næste session. **Risiko:** middel/høj ved asset-formatændring. **Test:** fresh server first build, concurrent Ensure, fejl, invalid asset og retry; mål maksimal enkeltframe-tid. Mesh-runtime og caches kan ikke slettes, før deres assets er gjort uafhængige af dem.

## Død/overflødig kode og betingede pensionskandidater

### CORE-024 — P3, stærk fjernelseskandidat: 219 end-furniture instances bygges og slettes i samme build

**Kode/evidens:** `LobbyReimaginedPreview/Builder.ModuleScript.lua:224`, `:253`, `:271–277`; `EndBlockades.ModuleScript.lua:16–22`, `:52–54`, PLAN på `:57`. PLAN indeholder 219 placements: Desk70, FilingCabinet44, VinylBench37, Sofa34, StackChair16, CRTMonitor12, Photocopier3, WireTrolley3; 220.612 instanced triangles. Alle placement-children destrueres før Ready/publicering. Før destruktion bliver de også materialpolished og sat solid. De overlevende collision curtains og luminous lenses er separate loops og er aktive.

**Mindste fix:** skip placering/clone/material/collision-arbejdet for denne pensionerede visual-pile. Behold `Reference End Furniture Piles` som tom folder, relevante attrs/Ready-statistik, colliders i `:23–31` og lenses i `:34–49`. Den store placements-data kan først fjernes, når helper/API er opdelt og ingen authoring caller bruger Module.Emit. **Risiko:** lav/middel med dette scope; høj ved at slette hele EndBlockades. **Test:** samme Ready, zero end-furniture, samme end-collision/raycast, DJ/stage/speakers beholdes, ingen nye missing mesh-assets. Sammenlign instance/clone-count og boot time. Dette er den tydeligste udførlige oprydningskandidat i core.

### CORE-025 — P3, stærk lokal kandidat: ubrugte Builder-lokaler og kun-ubrugt require

**Kode/evidens:** `LobbyReimaginedPreview/Builder.ModuleScript.lua:4`, `:10–12` (`allowed`), `:387` (`plaster`), `:494` (`thick`). allowed er aldrig kaldt; det er denne fils eneste anvendelse af DevAccess-requiren. plaster/thick læses ikke. Native Builder er identisk med repo.

**Mindste fix:** fjern disse lokale definitioner/require alene. **Risiko:** lav; fjern ikke DevAccess-modulet eller andre callers. **Test:** compile og fresh lobby build/Ready; public/developer entry skal stadig styres af de aktive guards.

### CORE-026 — P3, betinget kandidat: tre gamle Level5-authoring API'er uden runtime caller

**Kode/evidens:** `TunnelLobbyBuilder.ModuleScript.lua:2013` RefreshLevelFiveRoom, `:2041` ActivateLevelFiveStations, `:2090` RestoreLevelFiveStationActivation. Søgning i aktiv repo- og eksporteret native server/client-kode finder definitionerne, men ingen caller. Det gamle repo PreviewAccess brugte en anden feature; den native controller er nu public Void-game. `styleLevelFiveRoom` er derimod stadig kaldt fra builderens normale room-build ved `:2281`.

**Mindste fix:** pensionér disse exports separat eller flyt dem til et tydeligt authoring-værktøj efter ejerbeslutning. **Risiko:** lav for runtime, ukendt for Command Bar/admin-workflow. **Test:** fresh lobby, queue5, egen live-level server og reservation-fallback; bekræft owner ikke bruger exports manuelt. Fjern ikke styleLevelFiveRoom eller hele builderen.

### CORE-027 — P3, redesign-kandidat: gammel lobbygeometri bygges stadig bag den nye lobby

**Kode/evidens:** `GameManager.Script.lua:651–706`; `TunnelLobbyBuilder.ModuleScript.lua` hele Build. Den oprindelige verden bygges før R4-lobbyen, bl.a. tunneller, ribs, barricader og seks circular rooms. Canonical spawn flyttes; den oprindelige shop skal færdiggøres før clone til den nye lobby; support board overføres og bevarer sine aktive connections. De oprindelige stationer returneres og køres videre. Ved revised build-fejl bliver originalSpawn genbrugt som sikker fallback.

**Mindste fix:** udskil først canonical spawn, shop, support/queue-kontrakter og eventuelt en lille fallback fra legacy dekorationsbuild. Derefter kan overflødig fjern geometri fjernes i små grupper. **Risiko:** høj ved helfilsletning, middel ved bevidst migration. **Test:** normal boot og forced R4 asset/build failure, canonical join/reset/return, shops/leaderboard/supportboard, alle gamle/new køzoner. Ejer skal vælge, om stor original-lobby-fallback skal bevares. Ingen safe-delete anbefaling til hele TunnelLobbyBuilder.

### CORE-028 — P3, dormant delsystem: gammel developer Level4 queue-choice

**Kode/evidens:** `GameManager.Script.lua:1306–1311` og choice-dependent branches. Predicate kræver previewOnly=true og level=4. Native QueueBridge `:45` sætter previewOnly til level>4. Oprindelige Level4-stationer er normale campaign-stationer. Den tidligere Level4 developer/normal mode-picker har dermed ingen normal native R4-queue at aktivere på. Relateret `LEVEL4_PUBLIC=true` gør developer ceiling-grenen ved `:160–173` konstant til 4.

**Mindste fix:** fjern uopnåelig Level4-choice state/branches i server og tilhørende klientkontrakt samlet, efter at alle eventnavne/payloads er mappet. Behold normal public Level4-route og Level5/6 launcher-guards. **Risiko:** middel; client fixture/remote contract kan være historisk. **Test:** public/nondev Level4, queueconfig, reset/hostleave og normal launch; offline choice-test bruger en kunstig gammel station og beviser ikke nutidig reachability.

### CORE-029 — P3, betinget kandidat: Level2-preview flaggrene uden aktiv true-writer

**Kode/evidens:** final native GameManager skriver `Level2BlenderPreviewActive=false` ved `:125`, `:1788`, `:1854`; aktiv Level2-adapter skriver også false. Branches læser det ved character/death/postwin/clear flows. `Level2NewMapPreview` er en beslægtet gammel attribute-contract. Aktiv-kode-søgning fandt ikke en tilsvarende normal writer til true; archived preview er separat fra den native Level2 gameplay-map.

**Mindste fix:** fjern gamle preview-only branches/attributes tværgående efter native attribute- og authoring-workflow-check. **Risiko:** middel; mulig manuel Studio-attribute-toggle og flere klientconsumers. **Test:** Level2 entry/death/reentry/escape, flashlight/noise/skin; fresh Studio ingen preview attributes; ejer bekræfter gamle preview-workflow pensioneret. Behold NoiseRegistry, som er aktiv i Level1 og Level4.

### CORE-030 — P3, betinget kandidat: AvatarNormalize er et dokumenteret inaktivt sikkerhedsnet

**Kode/evidens:** `AvatarNormalize.Script.lua:13–17`, normalize/hook. Kommentar og traced spawn-flow er enige om, at gameplay bruger den fælles hazmat StarterCharacter; normalisering er kun InRound. Personal lobby-avatar skal bevares. Scriptet er stadig aktivt og kan blive relevant ved andre spawnveje/late appearance, så den interne statuskommentar er ikke alene et slettebevis.

**Mindste fix:** kun pensionering efter karakter-regression i en isoleret kopi. **Risiko:** lav/middel med nuværende spawnflow; høj hvis fremtidige HumanoidDescription-baserede gameplay-avatars forventes. **Test:** alle seks levels, paid/developer reentry, extreme Roblox scales, premium skins og late appearance; præcis rig/hitbox-parity og uændret lobbyavatar.

### CORE-031 — P3, bevar-data/kandidat-code: pensionerede FieldNotes er stadig profilkompatibilitet

**Kode/evidens:** native `N/ZyntraMonetization.Script.lua:344`, `:629–630`, `:698`, `:799`. Den aktive feature/title er pensioneret, men FieldNotes oprettes og normaliseres eksplicit som inert legacy-save data. Det er ikke en aktiv gameplay-loop.

**Mindste fix:** eventuel isoleret kompatibilitetsadapter eller bevar-opaque migrering efter databeslutning. **Risiko:** høj ved at droppe save-feltet; lav ved at lade denne lille adapter blive. **Test:** historiske profiler med notes/serial loader uden datatab; nye profiler og save-roundtrip. Jeg anbefaler ikke at slette eksisterende spillerdata for at spare få linjer.

### CORE-032 — P3, ejerbeslutning: one-off compensation/backfill og entitlement-policy

**Kode/evidens:** native ZyntraMonetization `:2390` indeholder et hardcoded AdvancedEquipment-entitlement for UserId9488575949, `:2409–2422` feedback-thanks20260914 for UserId10152463945 og sales-backfill startup med Studio-skip ved `:4652`. Gifts er eksplicit engangs-/entitlement-policy; backfill er en administrativ migration. De er ikke ukendte public remotes.

**Mindste fix:** spørg ejer om permanent gift og om backfill er afsluttet; flyt afsluttet administration ud af normal boot med bevarede durable migration/receipt markers. **Risiko:** høj hvis grants eller migration-markers fjernes blindt. **Test:** gamle/migrerede/nye profiler, allerede-granted gift, manglende backfill asset og tilbagevenden til ældre save. Behold permanente ReceiptIds; et antalcap kan give genudbetaling.

### CORE-033 — P3, stærk repo-kandidat: Preview/V9 Workspace scripts findes ikke i Studio

**Kode/evidens:** native inventory indeholder kun Level 4 Cinema Blender-scriptparret. Repoets `Workspace/Level 4 Cinema Preview/{OccasionalFixtureFlicker.Script.lua,AutomaticDoors/AutomaticDoorMotion.Script.lua}` og tilsvarende `Workspace/Level 4 Cinema V9 QA/` er repo-only. De to preview/flicker-kopier har samme SHA256 `542f9c2bf3fc212332e4ade3ec33aa1db198bd58fda1540e9807e8f56b0fc247`; automatic-door-kopier samme `75d4935b65b2f26c0ee4e4b7d22960acbd9c4b4e92e33391aa4d90eb7ea7f4d1`.

**Mindste fix:** arkivér/fjern fra aktiv mirror/install-manifest efter check af tooling-referencer. **Risiko:** lav for nuværende Studio-runtime; ukendt for ownerens QA-workflow. **Test:** parity og sync må ikke genindføre Preview/V9-worlds; aktive Blender-flicker og PushDoors beholdes. Dette er repo-oprydning, ikke fire aktive Studio-scripts der skal slås fra.

## Yderligere robusthedsfund

### CORE-034 — P3: leaderboard UI kan vise en write som fejlede

**Kode/evidens:** native `N/Level Leaderboards.Script.lua:48–70`. better=true sættes inde i UpdateAsync-transformen. Hvis alle write-attempts fejler efter at transformen har kørt, forbliver better=true, og local shown/redraw præsenterer en tid, der ikke er bekræftet saved. Senere refresh kan fjerne den igen.

**Mindste fix:** track confirmed successful write separat fra transformens candidate-resultat; håndter callback retries. **Risiko:** lav. **Test:** callback udføres, store kaster fejl alle tre gange; ingen local saved-ranking; derefter successful write opdaterer korrekt.

### CORE-035 — P3: reserved-server guards er ikke alle migreret til ServerKind

**Kode/evidens:** native LunaTribute tidlig guard ved `:5` og native Lobby Tunnel Reach ved `:27` bruger stadig `PrivateServerId ~= '' and PrivateServerOwnerId == 0`. ServerKind definerer nu registrerede Level5/6-reserverede servere som live-level *lobby*, og GameManager/Bootstrap har ny guard. De to features udebliver derfor også i disse private party-lobbyservers.

**Mindste fix:** hvis features ønskes i alle lobbyer, anvend `ServerKind.IsRoundServer()` som de migrerede lobby-systemer. Hvis private party-lobbyen bevidst skal være uden dem, dokumentér denne policy. **Risiko:** lav/middel; ingen grund til helfilsletning. **Test:** public lobby, Level1–4 reserved round og Level5/6 reserved live-lobby. En Studio-attribute simulation kan teste klassifikationen, men ikke rigtig reservation/teleport.

### CORE-036 — P3: Level3 warmup beholder en terminal fejl resten af serverens liv

**Kode/evidens:** native `N/Level 3 Kit Warmup.ModuleScript.lua:24–28`, `:41–44`, `:63–64`. Started sættes før jobbet; efter failed job er finished=true og Await returnerer failure. Senere transient recovery starter ikke et nyt job. Den underliggende Level6 bake er en aktiv delt dependency, ikke en pensioneret Level6-feature.

**Mindste fix:** én bounded retry/cooldown for recovery-egnede fejl med ny jobgeneration; behold fælles in-flight job, SHA/metadata-validation og Await-budget. **Risiko:** middel; må ikke starte parallelle massive bakes eller uendelige retries. **Test:** første warmup fejler transient, andet lykkes; permanent invalid kit forbliver bounded; samtidige callers deler ét job.

### CORE-037 — P3, tool hygiene: Completion Suite muterer delt attempt-counter

**Kode/evidens:** `Round Completion Test Suite.ModuleScript.lua:2617` kalder Routing.ResetAttemptIds() på samme krævede ModuleScript-table, som runtime bruger; `Round Completion Routing.ModuleScript.lua:774–776`. Suite er nyttig og ikke død kode. At køre den i et aktivt serverjob ændrer imidlertid runtime-counter state. Der er ikke i denne analyse demonstreret en faktisk claim-collision.

**Mindste fix:** isolér Routing-testinstansen eller fjern behovet for counter-reset; dokumentér suite som offline/isolated-host test. **Risiko:** lav for selve oprydningen, ukendt ved kørsel i live Play med claims. **Test:** RunAll i isoleret fixture plus host-probe, ingen mutation af en parallel runtime Routing-instans.

## Bevar-liste og positive kontroller

Der er ikke fundet grundlag for at slette disse hele systemer:

- **Native Level5PreviewAccess og Level6PreviewAccess:** aktive public Level5/6, party isolation, local fallback, death/reentry, returning og afslutning. Repoets gamle preview-implementeringer må ikke bruges som retirement-evidens.
- **ServerKind og Live Level Server:** aktive Studio-only serverejerskabs-/admissionkontrakter. Manglende mirrorfiler er et repo-sync-problem, ikke bevis for, at Studio mangler dem.
- **Round Loading Runtime:** cancellation og bounded deadlines med delt worker-ownership. Simple timeout/cancel-rewrites kan frigive andre jobs eller efterlade halv world-load.
- **Round Completion Routing og de to test suites:** retry policy, acknowledgements, ownership, lineage, watchdog og failure fixtures beskytter de forskellige continuation-/return-forløb. Ingen aktive callers er ikke et kriterium for at fjerne en test API.
- **PlayerProtection:** life/lease/transaction-reservation og epoch checks er aktive sikkerhedsregler. **ReentryPlacement:** bounded ground/collision-check er nødvendig spawn-sikkerhed.
- **NoiseRegistry, TeamObjectives, ZyntraDetectorSensing/ZyntraDetectorService:** aktiv AI/objective/consumable gameplay. Detectorens tidsbegrænsede scan er ikke en ubegrænset læk alene fordi det anvender en loop.
- **HazmatSkinVisuals, LobbyShopDisplay, FriendBoost:** cosmetics/shop previews og serverberegnet reward-adfærd. Fjernelseskandidater er deres specifikke dublerede arbejde/cache, ikke systemerne.
- **LunaTribute, Lobby DJ, Lobby Tunnel Reach:** aktive lobbyfeatures; owner-policy og ServerKind-guards afgør, hvilke lobbytyper de skal findes i.
- **EndBlockades collision/lens loops, MaterialPolish, LobbyPolishBays/Scene:** synlige/physical kontrakter eksisterer stadig, selv om én furniture-pile efterfølgende destrueres.
- **MasterTuningPlugin:** aktiv authoring/plugin-API; plugin code er ikke dead server-runtime bare fordi spillet ikke require'r den.

## Verifikation og grænser

Alle runtime-kilder i nedenstående coverage er læst. Repo/native drift er læst som både fuld gammel kilde og fuld relevant native ændring; native Level5 er læst som selvstændig ny controller. Native exports er parentens verificerede byte-/fingerprint snapshots. Fil- og linjehenvisninger gælder disse snapshotversioner.

Denne del lavede ingen Play-mutation, economy call, HTTP-post, deletion trial eller performance benchmark. Parentens samlede kørsel har separat dokumentation: alle 229 repo-kilder og 230 native kilder kompilerer; en kort Studio lobby-baseline indlæste 68 assets uden failed assets, men ingen komplet Level1–6/regression/removal-test blev gennemført. Udvalgte offline-checks er ikke et bevis for sikker retirement; især stale fixtures skal holdes adskilt fra aktiv native featureadfærd. Datastore lost-commit-forløbene er statisk udledte adversarial cases og skal bekræftes med fake stores, som faktisk committer før de melder failure.

Studio økonomi bruger in-memory profile/session-path under IsStudio og skip'er live backfill/support-ledger/leaderboard writes; dette blev kontrolleret i native Monetization og Leaderboards som hjælp til parentens baseline. Det giver ikke automatisk en garanti for alle eksterne effekter i vilkårlige senere ændrede tests.

## Coverage: fuldt læste kilder

### Top-level ServerScriptService

AvatarNormalize.Script.lua; Crouch State Server.Script.lua; FlashlightSync.Script.lua; FriendBoost.ModuleScript.lua; GameManager.Script.lua; HazmatSkinVisuals.Script.lua; Level5PreviewAccess.Script.lua (repo og fuld native); Level6PreviewAccess.Script.lua (repo og fuld native ændring); LobbyPartyModeController.Script.lua; LobbyShopDisplay.ModuleScript.lua; LunaTribute.Script.lua (repo og native drift); NoiseRegistry.ModuleScript.lua; PlayerProtection.ModuleScript.lua; PurchaseAlerts.ModuleScript.lua; ReentryPlacement.ModuleScript.lua; Round Completion Routing.ModuleScript.lua; Round Completion Test Suite.ModuleScript.lua; Round Loading Runtime.ModuleScript.lua; Round Loading Test Suite.ModuleScript.lua; RouteMarkerService.Script.lua; TeamObjectives.ModuleScript.lua; TunnelLobbyBuilder.ModuleScript.lua; ZyntraAnalytics.ModuleScript.lua; ZyntraDetectorSensing.ModuleScript.lua; ZyntraDetectorService.Script.lua; ZyntraMonetization.Script.lua (hele repo og alle native ændringer).

Top-level Level2Generator, Level3Generator og Level4RoundGenerator dækkes af levels-rapporten. Andre level scripts ligger i deres respektive systems-folders og dækkes af den samme separate rapport.

### LobbyReimaginedPreview

Bootstrap.Script.lua (repo/native guard-drift); Builder.ModuleScript.lua; DevBayAccessGuard.ModuleScript.lua (repo/native public5/6-drift); EndBlockades.ModuleScript.lua; LobbyPolishBays.ModuleScript.lua; LobbyPolishScene.ModuleScript.lua; MaterialPolish.ModuleScript.lua; QueueBridge.ModuleScript.lua (repo/native landing-drift); RuntimeBake.ModuleScript.lua.

EndBlockades' store data-literal er gennemgået strukturelt og via familie/count/statistics: 219 placements, otte familier, 66 collision curtains, deklareret schema/hash/center/revision og de separate emit-kontrakter. Det er data, ikke tusinder af ekstra featuregrene. MaterialPolishs indlejrede JSON er parsed: tre materials + sidewalkAtlas, KNOWN 67 mesh-hashes/family/material entries, SINGLE_SIDED 46 entries, alle sidstnævnte findes i KNOWN. Numeriske mesh-positioner er ikke individuelt visuelt godkendt.

### Studio-only serverkilder

N/ServerKind.ModuleScript.lua; N/Live Level Server.Script.lua; N/Level Leaderboards.Script.lua; N/Level 3 Kit Warmup.ModuleScript.lua; N/Lobby DJ.Script.lua; N/Lobby Tunnel Reach.Script.lua. Alle seks er fuldt læst; ikke klassificeret som ubrugte på baggrund af deres fravær fra normal mirror.

### Workspace og plugin

Workspace/Level 4 Cinema Blender/OccasionalFixtureFlicker.Script.lua; Workspace/Level 4 Cinema Blender/Doors/PushDoors.Script.lua; Workspace/Level 4 Cinema Preview/OccasionalFixtureFlicker.Script.lua; Workspace/Level 4 Cinema Preview/AutomaticDoors/AutomaticDoorMotion.Script.lua; Workspace/Level 4 Cinema V9 QA/OccasionalFixtureFlicker.Script.lua; Workspace/Level 4 Cinema V9 QA/AutomaticDoors/AutomaticDoorMotion.Script.lua. De to V9QA-filer er fuldt identiske med de læste Preview-filer og er fingerprint-kontrolleret.

plugin/MasterTuningPlugin.server.lua og plugin/build_plugin.py er fuldt læst. Parentens tooling-delrapport håndterer install/sync/test scripts. ServerStorage backups og øvrige archives håndteres af parentens archive-delrapport.

## Handoff og nødvendige ejerbeslutninger

Start med Studio→repo reconciliation, så næste session har de aktive native core-filer. Løs CORE-001/002 og afprøv CORE-003/004 med fake datastore failure-before/after-commit, før en større oprydning. Gennemfør CORE-024/025 som første lille reversible cleanup i en kopi med visual/collision diff. Gem performanceprofiler, før frekvenser/caches ændres.

Ejeren bør vælge: skal original-lobby-fallback beholdes; anvendes de tre Level5-authoring exports stadig manuelt; skal extreme-avatar-normalisering bevares som sikkerhedsnet; er gamle Level2/Level4-preview-workflows helt pensioneret; må private party-lobbyer have Luna/Reach; hvilke assisterede runs må rangeres; er gifts/backfills permanent policy eller afsluttet migration. Ingen af de beslutninger kræver, at aktiv kode slettes nu.
