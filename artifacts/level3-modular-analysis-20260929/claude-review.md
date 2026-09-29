# Claude Opus 5.5: review af live-koden

Dette er Claude Codes faktiske sidste review, modtaget med model-ID `claude-opus-5-5`. Det oprindelige output er bevaret uændret i `claude-live-review-result.json`. Første lokale input var foreløbigt; dette live-input erstatter det. Rooten har efterfølgende krydstjekket konklusionerne i live-snapshot og med Astra.

## Rootens faktuelle præciseringer

1. Place-versionen er **2403**. `v2403.16` i den oprindelige overskrift var en modelfejl; 16 er antallet af eksporterede scripts. Overskriften nedenfor er korrigeret.
2. World Builder findes i det samlede Studio-snapshot, men blev ikke sendt igen i Claudes opdateringsinput. Rooten og Blender-/Astra-reviewet har læst den aktuelle version.
3. AI'ens overlap- og Blockcast-parametre bruger `RespectCanCollide=true` (AI linje 803/808). Derfor er Claudes generelle forklaring om `CanQuery=false` utilstrækkelig. Dekorationsmeshes med collision/query/touch slået fra er passende, men fysiske og visuelle hindringer skal have korrekte proxies. Eksisterende hide-occluders må ikke blot frakobles.
4. Rumloftets underside er **H−0,5**, så laveste standardrum har 10,5 studs fri højde. En 10,5-studs portal har ingen ekstra plads til en nedhængende dekorativ overligger. Eksisterende bjælker kan lokalt gå lavere; nye detaljer kræver faktisk clearance-test.
5. 3.705–6.290 er hele rumfootprintets areal, ikke en måling af besøgte eller farbare aisle-celler. Søgegrænsen på 2.000 skal vurderes gennem runtime-målinger.
6. Forslaget om tilfældige udeladte kanter og uafhængige gatewaykolonner er ikke alene et bevist større grafrum. Med ni interne kanter kan hvert distrikt kun mangle én kant; flere gatewaykolonner kan kræve to brud for at holde de lodrette run-grænser. Hovedforslaget er derfor et variabelt loopbudget og en eksplicit opdatering af validatoren. Se README.
7. Efter reviewet samplede rooten 1.000 aktuelle layoutplaner: præcis 36 strukturelle grafer og ingen registrerede fejl. Ét seed pr. grafklasse dækker stadig ikke alle mål, indretninger eller navigationstilfælde.

## Modelreview (bevar ovenstående præciseringer ved brug)

# Opdateret review, baseret på LIVE place 131311258779917 (v2403)

**Grundlag:** Jeg har læst live-versionen af Configuration og hele Layout Generator, Hiding Controller linje 469–515 og Manager AI linje 895–1270. World Builder var ikke med i snapshottet. Mine tidligere påstande om `makeRoomProps`, `fitRoomTableLayouts`, `TABLE_GROUP_FOOTPRINT`, scream-markører og ServerStorage-publicering er derfor ikke tjekket igen. Reviewet indeholder ingen performance-påstande.

## 1. Rettelser til det forrige review

- **Rummål:** `resolveTuning` lægger `Configuration.Layout` oven på `DEFAULTS`. DEFAULTS bruges kun, når en nøgle mangler. Uden L3Layout-overlay er værdierne derfor W 65–85, D 57–74, H 11–13, RowHalfSpacing 90 og 32 forsøg. Kun Arrival (64×54) og Exit (58×52) kommer fra DEFAULTS. Det giver disse korridorlængder:
  - interne nord–syd-korridorer: 106–123 studs (ikke 112–128),
  - gateways: 38–48,
  - interne øst–vest-korridorer: 24–54,
  - entry: 38–58.
- **Loops:** Jeg skrev forkert, at der vælges 2 af 3 ubrugte kanter. Når `ExtraLinksPerDistrict ≤ 2`, fjernes én kant pr. distrikt på forhånd. DFS (7 kanter) plus 2 loops bruger så alle 9 resterende kanter. Kantmængden er altså helt bestemt af, hvilken kant der er udeladt.
- **Straight-run:** De tre udeladte kanter gør, at grænserne altid holder med standardværdierne. Det er entry-rækken ved `entryCut`, distrikt 2's lodrette kant i gateway-kolonnen og SignalHalls vestkant. Vandrette løb er dermed højst 3 og lodrette højst 2. Reglen er garanteret af konstruktionen og virker ikke som et filter, så `Validate` afviser reelt ingen seeds på det punkt.
- **CD og hide:** Kravet er bekræftet og strengere, end jeg beskrev. Hiding Controller asserter, at pivoten på hver af de 5 CD-modeller ligger højst 3 studs (XZ) fra præcis ét hide-anchor. Et skin, der flytter anchor eller CD-socket, vælter hele sessionen, ikke kun én prompt.
- **AI:** Nu direkte observeret: perimeter-repair og aisle-repair antager rektangulære rum, kardinale links og *centrerede* døre (`point(sign*hx, 0)`) med inset 6,5. Aisle-søgningen bruger et gitter på 1 stud med et loft på 2000 celler. Rummene er nu på 3705–6290 celler, så søgningen kan stoppe, før den når den fjerne dør i store rum. Det skal testes, ikke antages.
- **Trukket tilbage:** Alle budgettal, 4-grid-footprints som nav-krav og "hæv korridoren til ≥12" som krav.

## 2. Den reelle variation i dag

Kerne-topologien er entryRow (2) × entryCut (3) × gatewayColumn (3) × exitRow (2) = **36**. Det gælder kun, når overlayet holder `ExtraLinksPerDistrict = 2`. DFS-rækkefølgen ændrer kun link-id'er og hash, ikke selve grafen.

Oven på topologien varierer:
- **CD-placering:** CD 1 ligger altid i entry-rummet. Tre vælges fra kolonne 2–3 med mindst 105 studs afstand. Den femte vælges i praksis deterministisk (max-min-afstand med minimal støj).
- **Decor:** permutation på 8! pr. distrikt.
- **Mål:** rummål, højder og gaps.

Den oplevede variation kommer altså mest fra decor og mål. Det er derfor skin-laget og ikke grafen, der giver mest nyt lige nu.

Alle draws deler én `Random`, og `entryCut` trækkes først efter decor-shuffle og højder. Ændrer man længden på en DecorPool, flytter topologien sig for alle seeds. Det gælder også regressions-seeds som 1428587057 fra AI-kommentaren.

## 3. Hjælper et 4-grid, der matcher nav-voxlerne?

Nej, ikke i sig selv:
- Rumcentrene er vilkårlige halve tal (`sharedWidths*.5` og `D*.5` i district-offset).
- Korridoren er 14 studs bred, altså 3,5 voxels.
- Koden håndterer allerede misforholdet med `PathAgentRadius 4`, `SweepRadius 5.25` og de lokale repair-stier.

Snapping af footprints hjælper først, hvis centre, vægge og korridorbredde også ændres. Selv da hjælper det kun, hvis navmeshets voxelgitter er alignet med verden, og det er ikke verificeret. Et 4-grid er fint som modulmål i Blender, men det er ikke begrundet som nav-krav.

## 4. Anbefalet Blender-arkitektur nu: parametrisk shell med faste skins

Hele, faste rum kræver diskrete footprints, og det er en generatorændring. Med 21×18×3 mulige rummål og altid centrerede åbninger passer denne model bedre:

- **Roblox beholder** shell, collision, åbninger, anchors og markører.
- **Skins** får `CanCollide`, `CanQuery` og `CanTouch` sat til false. `GetPartBoundsInBox` og `Blockcast` ignorerer parts med CanQuery=false, så Manageren ser ikke skins. Møbler med fysisk tilstedeværelse skal derfor have en proxy via den eksisterende `FurniturePathLabel`/NavExclusion-mekanik.
- **Kit pr. væg:**
  - et fast hjørne,
  - en fast portal-karm, centreret og uden at indsnævre 14×10,5,
  - vægspænd bygget af gentagne faste moduler plus én filler, der kun skaleres langs væggen og har en flad profil, så skaleringen ikke ses.
- **Højde 11–13 uden varianter:** Et bånd forankret i gulvet (sokkel eller butiksfacade) og et bånd forankret i loftet (cornice). Zonen imellem er shell-væggens tekstur. Ved H=11 er der kun 0,5 stud over åbningen, hvis H er den indvendige højde; det skal verificeres i Builder. Loftbåndet skal derfor afbrydes ved portalerne.
- **Hide-skin:** Skinnet forankres til Roblox' anchor, ikke omvendt. CD-socketen skal ligge højst 3 studs fra anchoret.
- **Stil-lag:** Skin-sæt og palet vælges ved build ud fra en stilparameter, og de eksisterende ThemeId- og Decor-navne mappes til skins. Så kan både Aero (hvid/cyan/lime) og den bevarede Level 3-fest/mall understøttes uden at røre `DISTRICT_DEFINITIONS`, `Validate` eller RNG. Der er ingen vand, springvand eller akvarier. Lysbokse med himmelgradient og kunstplanter er fine.

## 5. Fixture-test

Jeg er enig: en femrums-slice er umulig som runtime-level, men et separat modul-fixture er muligt.

- **Fixture:** Byg ekstremerne direkte med samme skin-kode, f.eks. 65×57×11, 85×74×13 og blandinger, med 1–4 åbninger og et CD-rum. Kør derefter clearance-sweep, hide/CD-assertionen og aisle-repair på dem.
- **Fuld generator:** Supplér med 36 seeds, ét pr. topologiklasse. Det giver deterministisk dækning i stedet for 200 tilfældige seeds.

## 6. Faset omskrivning af grafen (senere)

1. Metrikker i `Validate`: korteste sti, dead-end-dybde og CD-spredning. I første omgang kun som rapportering.
2. Separate RNG-strømme og `GeneratorVersion 3`. Det bryder bevidst de gamle seeds, én gang.
3. Tilfældig udeladt kant og uafhængige gateway-kolonner, så straight-run bliver et *reelt* afvisningsfilter. Antallet af gyldige topologier skal enumereres, ikke gættes.
4. Først derefter: flere gateways (loops der går uden om distrikter), døre uden for centrum eller ikke-rektangulære rum. Det kræver ændringer i Builder og i AI'ens repair-stier, som antager centrerede kardinale døre.
