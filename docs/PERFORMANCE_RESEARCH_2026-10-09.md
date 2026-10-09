# Optimeringsanalyse — Backrooms: Stay Quiet, 9. oktober 2026

**De stærkeste kandidater er mere præcis indlæsning, mindre permanent klientindhold og enklere geometri.** Streaming er allerede aktiveret. Et generelt system, der skjuler fjerne vægge, er derfor ikke automatisk den største forbedring. Min anbefaling er at prioritere UI-importkopier og lobbyens assetprioritering, verificere streamingbudgettet og derefter måle Poolrooms-collision samt Level 6-geometri og lokale lys.

Analysen kombinerer aktuelle officielle Roblox-kilder med read-only inspektion af Studio-place `131311258779917`, universe `10559217407`, i Edit. Der er indsamlet 42 relevante scripts med eksakte paths, klasser og SHA-256, kontrolleret mod Source og editor source. En separat tekstsøgning gennemgik alle 220 LuaSourceContainers fundet på det tidspunkt. Tal nedenfor beskriver Edit-modeller og templates, ikke en samtidig aktiv klientverden. Der er ikke kørt gameplay, multiplayer, enhedstests af performance eller A/B-ændringer.

Kildegrundlaget ligger i [research-evidensen](../artifacts/performance-research-20261009/). [Source-manifestet](../artifacts/performance-research-20261009/source-manifest.json), [instansinventaret](../artifacts/performance-research-20261009/live-instance-inventory.json), [collision/UI-detaljerne](../artifacts/performance-research-20261009/live-collision-ui-details.json) og [UI-referencesøgningen](../artifacts/performance-research-20261009/live-ui-reference-scan.json) gør fundene efterprøvelige. Kildekopierne er analyseevidens; de er ikke en deploymentbaseline eller et fuldt native place-backup.

**“Ikke indlæse alt” består af flere forskellige problemer.** Denne opdeling afgør, hvor en ændring kan have effekt:

| Mekanisme | Hvad den reducerer | Hvad den ikke i sig selv reducerer |
| --- | --- | --- |
| Render-culling | Arbejdet med at tegne usynligt indhold | Antal indlæste instanser, serverens AI og collision |
| Workspace-streaming | Klientens lokale verdensinstanser og relevante opdateringer | Hele serverens verden og fast ReplicatedStorage-indhold |
| Prioriteret assetindlæsning | Ventetid før nødvendige billeder, meshes og lyd er klar | Antal replikerede UI-/verdensinstanser |
| LOD/færre detaljer | Kompleksiteten af indhold, som stadig vises | Al øvrig gameplaylogik |
| Serveraktivering pr. level/område | Unødvendige aktive systemer og eventuelt serverindhold | Klientens allerede indlæste UI og fælles assets |

Roblox udfører allerede frustum-culling og occlusion-culling. Motoren forsøger således at undlade at tegne indhold uden for kameraets synsfelt og bag dækkende geometri. Et stort map i serverens Explorer er ikke bevis for, at klienten tegner hele mappet. Supplerende rumstyring kan stadig være nyttig, især for effekter og lys. [Roblox: Improve performance](https://create.roblox.com/docs/performance-optimization/improve)

**De konkrete Studio-fund giver en mere præcis prioritering.**

| Undersøgt indhold | Bekræftet størrelse/egenskab | Betydning |
| --- | --- | --- |
| Workspace | `StreamingEnabled = true` | Den grundlæggende mekanisme findes allerede |
| ReplicatedStorage.ZyntraShopUI | 13.383 descendants; Imports alene 10.396 | Stor fast klientreplikering, selv når shoppen ikke vises |
| ReplicatedStorage.ZyntraHUD | 3.321 descendants; Imports alene 1.661 | HUD-importarkiv og produktions-templates eksisterer samtidigt |
| ServerStorage.Level2PoolroomsMap | 30.869 descendants, 27.535 BaseParts, 23.885 helt transparente colliders | Meget collision-/instansindhold; ligger aktuelt uden for klientreplikering |
| Samme Poolrooms-model | Root Nonatomic, 2.936 MeshParts, 513 lights, 274 enabled, 3 shadow-enabled | Ingen konstateret whole-map Atomic-fejl; lysbudget må vurderes under aktiv runde |
| Workspace.Level 6 Indoor Playground | 14.300 BaseParts, 6.605 UnionOperations; alle unions RenderFidelity.Precise og CollisionFidelity.Hull | Konkret kandidat til geometri- og instansforenkling |
| Samme Level 6-model | 5.688 Textures, 281 lights, 277 enabled; ingen light shadows | Stor struktur, men “sluk alle light shadows” rammer ikke denne model |
| Samme Level 6-model | 1.828 helt transparente parts har CastShadow=true | Kandidat til selektiv oprydning i shadow-casters |
| Workspace.Level 4 Cinema Blender | 8.909 BaseParts, 4.051 MeshParts; 254 enabled lights, 3 med shadows | Lys-/rumstyring er mere relevant end blanket shadow-off |
| Workspace.Level 5 Void | 1.947 BaseParts, 661 enabled lights; ingen light shadows | Undersøg lysenes overlap og synlige nærområde |
| ServerStorage.RBX_ANIMSAVES + MongoTVEntityAnimations | 309.077 descendants tilsammen | Stor authoring-/serverinstansmængde, men ikke direkte klientrendering |

StreamingMinRadius, StreamingTargetRadius, StreamOutBehavior, ModelStreamingBehavior, StreamingIntegrityMode og de nye streamingflags kunne ikke læses gennem denne Studios MCP-execution-kontekst: de blev rapporteret som ikke tilgængelige medlemmer. Det er registreret i inventaret. Jeg antager derfor hverken 1.024 studs eller nogen anden aktuel indstilling. Deres værdier skal registreres i Studio Properties før radiusforsøg.

De authored L4/L5/L6-modeller ligger ved meget forskellige verdenspositioner. Streaming kan derfor allerede holde store dele væk fra en klient, der befinder sig i lobbyen eller en anden bane. Ovenstående lys- og parttal kan ikke lægges sammen og bruges som klientens aktuelle renderbelastning.

**Flere af de oplagte optimeringer er allerede implementeret.** Level 1 genereres først ved launch, jf. MazeGenerator linje 19–24 og GameManager linje 1753–1757. Poolrooms-adapteren flytter den samme map fra ServerStorage til Workspace ved entry og tilbage ved cleanup; den kloner ikke to permanente maps. Det fremgår af Level 2 Round Adapter linje 81–88 og 174–184.

Den aktuelle Level 2 Poolrooms Runtime bruger cached hazard-/exit-zoner og en 0,1-sekunders loop. Den starter ikke den gamle Pool Foam AI. Det gamle World Builder-modul bruges kun til en exit-slide-helper. Ældre AI-kode er derfor ikke belæg for at udpege L2-pathfinding som en aktuel flaskehals.

L3 bygger først i ServerStorage med batch-yields, og AI-controlleren serialiserer pathfinding, sammenlægger nye mål og begrænser retry-frekvensen. L6-entry bruger Playground Game, ikke de ældre Mall Manager/World Builder-moduler; Counter starter først ved AddPlayer, og den anvender normalt sin egen NavGraph. RoundHud monterer allerede udvalgte widgets efter behov. Shop-controlleren bygger den store shop ved åbning eller en tilsvarende brugerhandling, jf. Zyntra Shop L4 linje 1353–1358 og 1426; den komplette shopklon er derfor ikke dokumenteret som en automatisk first-join-omkostning. Disse forhold gør det mindre sandsynligt, at en generisk omskrivning af alle loops eller al lazy loading er den bedste første investering.

**Den forventede impact er kvalitativ, ikke en påstået benchmark.** “Høj” betyder, at en relevant stor omkostning kan fjernes, hvis den profileres som væsentlig. Det siger ikke, at hele spillet bliver et bestemt antal procent hurtigere.

| Tiltag | Forventet hovedgevinst | Potentiale i vores spil | Arbejde/risiko | Prioritet |
| --- | --- | --- | --- | --- |
| Flyt bekræftet authoring-only UI Imports uden for klientreplikering | Join, instanshukommelse, replikering | Højt og meget konkret | Lav–middel; fuld reference-/UI-kontrol | 1 |
| Kritisk assetliste og senere valgfri lobby/shop-assets | Cold join og oplevet ventetid | Højt, hvis ikke-kritiske assets ligger foran kontrol | Middel; readiness og pop-in | 1 |
| Tilpas eksisterende streamingradius og stream-out | Klienthukommelse, streaming-/netværksarbejde | Højt hvis nuværende radius dækker unødvendigt meget | Middel; sprint, teleport og manglende gulv | 1 |
| Forenkling af L2-collision proxies | Instances, physics/navigation memory, queryarbejde | Højt strukturelt potentiale | Middel–høj; trapper/slides/geometri | 2 |
| Level 6 unions fra Precise til Automatic, derefter modulære assets | GPU/geometry memory, eventuelt draw calls | Middel–højt, profilafhængigt | Lille A/B-forsøg; større assetarbejde senere | 2 |
| Rum-/sektorstyrede lokale lights og effekter | Render CPU/GPU og spikes | Middel–højt i aktive områder | Middel; lyslæk/pop-in/gameplay-state | 2 |
| Selektiv fjernelse af unødvendige CastShadow-flags | Shadow-pass arbejde | Middel; afhænger af aktive lys | Lav–middel; visuel kontrol | 2 |
| Rolleafhængig L3-kit warmup | Serverstartup, CPU/memory | Potentielt højt på irrelevante serverroller | Middel; bevare launch-readiness | 2 |
| Mesh-/teksturgenbrug og passende opløsning | Graphics memory, download, draw calls | Middel; aktiv assetmængde ukendt | Middel; visuel kvalitet | 3 |
| SLIM for egnede statiske modeller | Distant rendering og repræsentationer | Betinget; runtimekompatibilitet | Middel–høj | 3 |
| Custom hiding af alle fjerne opaque vægge | Ekstra renderarbejde | Ofte lavere ekstra gevinst | Middel; egen CPU og pop-in | 4 |
| FrustumStreaming | Fjern synlighed | Lav prioritet til lukkede rum; kan koste mere | Middel | 4 |
| Tåge alene | Skjuler visuelle overgange | Begrænset som selvstændig performanceændring | Lav | 4 |

**UI-importkopierne er det mest konkrete første indlæsningsspor.** Shop og HUD indeholder tilsammen 16.704 descendants. De to Imports-foldere indeholder alene 12.057: omtrent 72,2% af disse to træers underobjekter. Det er en strukturandel, ikke 72,2% af spillets RAM eller loadtid. De indeholder også forskellige instanstyper, som har forskellig pris.

Den fulde live-søgning fandt ingen bogstavelige `Imports`-referencer i de 220 scripts. RoundHud bruger `ZyntraHUD.Templates`, linje 111–113, og kloner konkrete widgets. Det taler for at holde importoriginaler som authoring-data uden for klientreplikering, mens nødvendige templates bliver tilgængelige. Søgningen beviser ikke fravær af dynamiske opslag, ObjectValues eller plugins. En ændring kræver derfor en referencekontrol og afprøvning af shop, daily rewards, devmenu og HUD. ReplicatedStorage-indhold indlæses hos klienten uanset verdensstreaming. [Roblox: Design for performance](https://create.roblox.com/docs/performance-optimization/design)

**Loading-koden er allerede afgrænset, men prioriteten kan forbedres.** Den har deduplication, fire workers, yields og arbejde, der deles over frames. Lobbyens preload vælger dog både ServerLobby og LobbyReimaginedPreview og tilføjer hele PlayerGui: Lobby Loading Screen linje 377–381 og 466–480. Det kan medtage indhold, spilleren først behøver senere. De faktisk tilstedeværende PlayerGui-kloner ved join skal måles; skjult shop er ikke automatisk bevist at være der.

Et praktisk forslag er tre indlæsningsniveauer: nødvendigt for kontrol og sikkert spawn; nødvendigt for den næste korte bevægelsesrute; valgfrit indhold, som hentes senere eller ved åbning af en menu. Shop-build ved åbning findes allerede; forbedringen skal målrettes de assets, der faktisk indsamles ved join. Meshes, teksturer og lyd hentes allerede efter behov uden Workspace-streaming. PreloadAsync bør reserveres til nødvendige assets frem for at gøre hele banen til en adgangsbetingelse. En vellykket content-callback er heller ikke en garanti om skarp GPU-tekstur ved det næste frame. [Roblox: ContentProvider](https://create.roblox.com/docs/reference/engine/classes/ContentProvider)

**Streamingafstand skal vælges ud fra bane og forbindelse.** Jeg foreslår at sammenligne den aktuelle værdi med TargetRadius 384, 256 og 128 studs, hvis de giver mening i forhold til den aktuelle MinRadius og synslinjerne. Min 64 er Roblox' generelle udgangspunkt; deres generelle Target-anbefaling er 1.024, ikke en dokumenteret optimal værdi for vores korridorer. Start med de større forsøgsradier og reducer gradvist.

Target skal være større end Min, så der findes en buffer. Tænk praktisk i længste synslinje, løbehastighed og tiden til at få nyt gulv/geometri ind: en spiller, der bevæger sig hurtigt på en dårlig forbindelse, behøver mere margin. Target er ikke en hård RAM-grænse; indhold kan blive liggende uden for den. Opportunistic er relevant, når man ønsker stream-out før egentlig memory pressure. [Roblox: Instance streaming](https://create.roblox.com/docs/workspace/streaming)

Små Atomic-modeller kan sikre komplette døre, objekter eller kompakte rum. Hele maps bør ikke blive Atomic for at fikse manglende dele, og Persistent skal begrænses til ting, der faktisk skal være tilgængelige konstant. Atomic-garantien gælder den oprindelige replikering, ikke alle senere tilføjede descendants. [Roblox: ModelStreamingMode](https://create.roblox.com/docs/reference/engine/enums/ModelStreamingMode)

Readiness ved teleport skal fortsat kontrollere destinationen; RequestStreamAroundAsync er en forberedelse med timeout, ikke et bevis på, at alle ønskede assets er tilgængelige. Midlertidige ekstra foci må ikke ende som permanente dobbelte streamingområder. [Roblox: Player API](https://create.roblox.com/docs/reference/engine/classes/Player)

**Room-culling bør begynde med lys og lokale effekter.** En passende model er aktivt rum plus relevante nabosektorer, med margin ved døre og forskellig ind-/udkoblingsgrænse, så grænsebevægelse ikke får lys til at blinke. Rumskift eller en billig periodisk opdatering er mere oplagt end at scanne hele mappets descendants hvert frame. Sektorkortet kan bygges sammen med mappet; instanslister opdateres, når indhold streamer ind/ud.

På hver klient bestemmes dekorative effekters aktivitet ud fra dens behov. Monster-, objective-, blacklist-/blackout- og skade-state bliver serverautoritative. En klient må ikke deaktivere globale hazards eller fjernspilleres collision, fordi de er uden for dens kamera. Serveraktivering skal tage højde for alle levende deltagere og nødvendige NPC-ruter. Klientpathfinding kan mangle outstreamede vægge; serveren har fortsat hele verden. [Roblox: Pathfinding](https://create.roblox.com/docs/characters/pathfinding)

I L5/L6 findes mange lys, men ingen light shadows i de undersøgte modeller. En blanket `Light.Shadows=false` giver derfor ikke en ny gevinst dér. Undersøg i stedet antallet af lys, der påvirker samme synlige område, deres Range og faktisk render-/lightingtid. L6's transparente shadow-casters kan testes separat under de lysforhold, der faktisk er aktive.

**Poolrooms-collision har en usædvanligt stor strukturandel.** 23.885 af 27.535 BaseParts er helt transparente colliders, omtrent 86,7%. Kun to synlige dele har CanCollide=true. Mappet ser dermed ud til at bruge separat fysisk proxygeometri i stor skala. Det er ikke 23.885 transparente skærmflader med overdraw, og antal colliders alene måler ikke physics-tid.

Undersøg, om tilstødende coplanare gulve/vægge kan repræsenteres med færre enkle lokale proxies. Et hypotetisk fald fra 24.000 til 6.000 proxies er 75% færre proxies; det siger intet direkte om FPS. Bevar døråbninger, trapper, skrå slides, rækværk, hazards og query-kontrakter. At sætte Box/Hull på én stor rum-mesh kan udfylde åbninger. CanQuery kan være nødvendigt, selv hvis CanCollide er false. [Roblox: CollisionFidelity](https://create.roblox.com/docs/reference/engine/enums/CollisionFidelity)

**Level 6 bør have sit eget geometriforsøg.** Alle 6.605 unions står på Precise. Test Automatic på en afgrænset, repræsentativ gruppe og sammenlign billedkvalitet, triangles, draw calls og frame time. UnionOperation er en PartOperation; API-valg skal kontrolleres for den klasse, og MeshPart.Performance er ikke et universelt valg til unions. [Roblox: PartOperation](https://create.roblox.com/docs/reference/engine/classes/PartOperation)

Senere kan gentagne væg-/net-/legeelementer blive modulære meshes med fælles IDs, eventuelt færre Texture-instanser via passende materialer eller UV'er. Undgå én kæmpemesh for hele banen: det kan forringe spatial streaming/culling og collision. L6-inventaret viser allerede kun syv unikke MeshIds blandt de 73 MeshParts; det er ikke i sig selv bevis for, at meshgenbrug generelt er dårligt. Unions er den særskilte kandidat.

MeshPart.Automatic tillader afstandsbaserede enklere repræsentationer. I korte synlige korridorer er synlige meshes ofte så tæt på, at et afstands-LOD kan få lille effekt; assetforenkling kan være vigtigere. [Roblox: MeshPart](https://create.roblox.com/docs/reference/engine/classes/MeshPart)

SLIM er værd at undersøge til egnede statiske, kompakte modeller. Den nuværende dokumentation udelukker runtime-modificerede modeller og modeller med Humanoid og angiver krav om streaming og cloud-/Team Create-workflow. Procedural construction, flytning, animation og dynamiske ændringer kræver en kompatibilitetsprøve; det er ikke en blanket indstilling til alle vores levels/NPC'er. [Roblox: SLIM](https://create.roblox.com/docs/workspace/streaming/slim)

**Serveren har andre omkostninger end render distance.** GameManager starter L3 Kit Warmup ved linje 34, før serverrollen afklares ved 132. Warmup kan lave sessionens Blender-kit via EditableMesh/Image-bake, selv på serverroller, som ikke skal bruge L3. Den er allerede asynkron og cached; det flytter arbejdet, men gør det ikke gratis. Rolleafhængig warmup eller verificerede publicerede prefabs bør sammenlignes med eksisterende readiness og `Level3KitWarmSeconds`/`BakeSeconds`.

De 309.077 authoring-animation-descendants ligger i ServerStorage, så de skal ikke bruges som argument for klient-FPS. De er en kandidat til serverinstans-/startmemory og produktionsindhold. Enhver fremtidig ændring skal bevare de native authoring-data og verificere alle runtime-animationreferencer; der er ikke autoriseret eller foretaget sletning i denne research.

Partyservere bruger samme place. Det adskiller spillere og aktive runder, men betyder ikke, at place-indholdet automatisk er opdelt pr. level. Et særskilt place pr. level kan senere give stærkere isolering, men koster routing, versionering, return/rejoin-håndtering og flere overgange. Roblox beskriver også ekstra join-tid ved place-teleports. Det er en arkitekturmulighed, ikke første skridt. [Roblox: Design for performance](https://create.roblox.com/docs/performance-optimization/design)

FrustumStreaming er ligeledes en senere synlighedsbeslutning: det udvider normal streaming med kameraets synsvolumen og kan øge indlæst indhold. Det ignorerer vægges occlusion og reducerer ikke den normale streamingmængde. Det er derfor svagt begrundet som løsning på “ikke alt på én gang” i lukkede Backrooms-korridorer. [Roblox: Frustum streaming](https://create.roblox.com/docs/workspace/streaming/frustum)

Tåge kan gøre streamingovergange mindre synlige, men FogEnd beskriver, hvor tågen er helt opaque; det er ikke en dokumenteret unload-grænse. Den bør vælges sammen med et faktisk streaming-/geometribudget. [Roblox: Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting)

**Impact i procent kræver en baseline.** Det er muligt at beregne ændringen i en bestemt komponent uden at kende hele spillets performance, men de to resultater skal holdes adskilt:

| Regneeksempel — ikke måling af vores spil | Komponenteffekt | Begrænsning |
| --- | --- | --- |
| Radius 512 → 256 i en stor, omtrent plan verden med ensartet tæthed | Nominel cirkelflade falder 75% | Ikke 75% mindre RAM; fælles assets, retention, geometri og fixed overhead består |
| 12.057 import-descendants ud af 16.704 UI-descendants | Omtrent 72,2% af de to UI-træer | Ikke 72,2% mindre samlet klientmemory |
| Frame time 33,3 → 25 ms | Omtrent 30 → 40 FPS uden cap | 25% lavere frame time bliver 33% højere FPS |
| 40% af arbejdet halveres, hvis det ligger serielt på den kritiske vej | Total tid bliver 80%; teoretisk speedup 1,25× | CPU/GPU-pipelining og andre flaskehalse kan begrænse gevinsten |

Det relevante spørgsmål er derfor både “hvor meget arbejde fjernes?” og “ligger det arbejde på den kritiske vej?”. En CPU-optimering kan give bedre frame time på én telefon og næsten ingen FPS-ændring på en GPU-begrænset enhed. En hurtig PC med FPS-cap kan skjule forbedringen. [Roblox: MicroProfiler](https://create.roblox.com/docs/performance-optimization/microprofiler)

**En afgrænset benchmarkserie kan omsætte prioriteringen til sikre tal.** Først registreres Studio Properties, aktuel serverrolle, place-version, graphics quality, netværk og testdevice. Brug mindst en faktisk svag/mellemklasse mobil og en PC. Studio-emulatoren er egnet til layout og controls, men er ikke en nøjagtig telefonmemorytest. [Roblox: Test on hardware](https://create.roblox.com/docs/performance-optimization/test-on-hardware)

Forsøg udføres én variabel ad gangen og med identisk rute/seed/kamera. Alternér baseline og variant, så temperatur og cache ikke følger den samme rækkefølge. Skeln mellem første join uden relevante cached assets og gentagne warm joins. Gem rå profiler og noter antallet af gentagelser; en enkelt hurtig join er ikke et resultat.

| Situation | Målinger | Hvilket spørgsmål den besvarer |
| --- | --- | --- |
| Cold join til public lobby | Klik→kontrol, downloadbytes, peak RAM, replikerede instances | Hjælper UI-slimning og assetprioritering? |
| Samme 2–3-minutters aktive rute pr. level | p50/p95/p99 frame time, CPU/GPU, triangles/draw calls, RAM | Hjælper radius, geometri eller lokale lys? |
| Sprint, teleport, døre, elevator/slides | Stream-pauser, gulv-readiness, pop-in og synlige fejl | Er mindre radius sikker og visuelt acceptabel? |
| Flere deltagere tæt sammen og spredt i banen | Server frame time, netværk, memory, relevante klienttal | Gælder gevinsten også multiplayer? |
| Gentagne round reset/rejoin | Instances/LuaHeap/connections over tid | Ophobes indhold, eller genbruges/ryddes det? |

Foreløbige målsætninger kan være stabilt 30 FPS på valgt minimumsmobil og 60 på PC; de er produktbeslutninger, ikke verificerede nuværende resultater. Prioritér også lange frame-spikes. P95/p99 bør rapporteres som millisekunder frem for at skjules i et gennemsnitligt FPS-tal. [Roblox: Identify performance issues](https://create.roblox.com/docs/performance-optimization/identify)

Scene Analysis kan adskille instance composition og render-pass triangles/draw calls. Følg opaque/shadows/transparent/particles særskilt. MicroProfiler-tags såsom queryFrustumOrdered, computeLightingPerform, ShadowMapSystem, updateParticles og ProcessPackets hjælper med at koble et fund til faktisk arbejde; et højt objektantal alene er ikke en CPU-/GPU-diagnose. [Roblox: Scene Analysis](https://create.roblox.com/docs/performance-optimization/scene-analysis), [MicroProfiler tag reference](https://create.roblox.com/docs/performance-optimization/microprofiler/tag-table)

Hukommelse måles som både peak og stabil usage: Instances, GraphicsTexture, GraphicsMeshParts, PhysicsCollision, LuaHeap, Sounds og HttpCache. Et outstreamet objekt betyder ikke, at alle cached assets straks forsvinder fra RAM. [Roblox: Memory usage](https://create.roblox.com/docs/studio/optimization/memory-usage)

Ved enhver fremtidig Level 2-ændring, der berører den historiske entity/pump-kontrakt, skal aktive scenarier også verificere spawnafstand fra alle levende deltagere, anden distinct pump og tredje eskalering samt CPU/memory/navigation/retry/reset. Den aktuelle authored Poolrooms-runtime starter ikke den gamle pump/entity-controller; en syntetisk probe på den gamle kode er derfor ikke et performancepass for den nuværende bane.

**Min foreslåede rækkefølge er:** dokumentér baseline og de utilgængelige streamingindstillinger; kontroller UI-importreferencer og lobbyens kritiske assetliste; mål radier/stream-out; prøv derefter L2-proxies og L6-geometri/lys hver for sig; vurder serverwarmup og større arkitektur, når de første profiler viser størrelsen af omkostningen. Den anbefalede rækkefølge er en begrundet vurdering. Faktiske FPS-, MB- og sekundgevinster er fortsat uverificerede.

Studio og gameplaykode er ikke ændret, Play er ikke startet, og der er ikke publiceret et nyt spil. Repositoryets eksisterende ændringer i RoundUI og studio-sync-manifest er bevaret uden at blive en del af researchens staged changes. Remote history er inspiceret efter fetch; analysen bygger på Studio frem for Git/Trello. Researchens dokumentation og task-owned evidence committes lokalt; en lokal commit er ikke et GitHub-push.
