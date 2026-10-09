# Priser, shopidéer og kampagneforslag — revideret 9. september 2026

**Anbefaling: Behold de 12 nuværende priser. Ret de konkrete spil- og shopfejl først, og mål derefter købsforløbet.** De observerede priser giver ikke belæg for en generel prisnedsættelse. De beviser heller ikke, at priserne er optimale, eller at pris ikke påvirker det lave salg. Det kræver data om eksponering, køb og spilleradfærd.

Dette dokument er det gældende, reviewede beslutningsgrundlag for Trello-kortene [pricing](https://trello.com/c/KBDJouxI), [nye shopidéer](https://trello.com/c/n7uSFoMX) og [rabatter/annoncer](https://trello.com/c/3wDozWJa). Det **erstatter anbefalingerne og det danske resumé i Claudes originalrapport**, som fik 6,5/10 i det første kritiske review. Originalens konkurrentkatalog kan bruges som historisk researchbilag med de begrænsninger, der står nedenfor. **Denne revision fik 9/10 af den uafhængige kritiker den 9. september; ingen yderligere nødvendige rapportrettelser.**

Claudes [originalrapport](G:/Roblox/pricing-research-2026-09-09/PRICING_REPORT.md) er bevaret uændret. Den blev udarbejdet med Fable 5.1 som manager og fire Opus 5-agenter ifølge rapportens modelproveniens. Revisionen er skrevet efter gennemgang af kritik, kode, primære Roblox-kilder og de dashboardtal, der blev aflæst i arbejdssessionen. Der er ikke ændret priser, oprettet produkter eller brugt annoncebudget som del af denne research. **5 tokens for 5 sekunders beskyttelse er ejerens beslutning; øvrige nye varer og kampagner her er forslag.**

## Hvad vi faktisk ved

Priser i tabellerne er standardpriser i Robux, ikke et løfte om alle spilleres checkoutpris. De tre egne passes er genverificeret 9. september via Roblox' offentlige produkt-API. Konfigurationen er genlæst samme dag. Developer product-priserne bygger på konfigurationen og originalrapportens MarketplaceService-kontrol fra 9. september; der er ikke gennemført nye rigtige køb i denne research.

Creator Dashboard for universe **10559217407** blev aflæst 9. september. Perioderne nedenfor holdes adskilt, fordi kortene viser forskellige vinduer og seneste datodækning. Kilde: [oplevelsens oversigt](https://create.roblox.com/dashboard/creations/experiences/10559217407/overview) og dens Monetization-side; adgang kræver ejertilladelse. Den lokale [kontrolrapport](G:/Roblox/MongoTV/artifacts/trello-20260909/dashboard-verification.md) fastholder aflæsningen.

| Visning og periode | Aflæste tal | Hvad de kan bruges til |
|---|---|---|
| Oversigt, 7-dages glidende gennemsnit, **2.–8. september** | DAU **180**; nye brugere **175**; D1-retention **1,45 %**; spilletid **12,5 min.**; daglig omsætning **9 Robux** | Aktuel størrelsesorden. Ingen årsagsforklaring og ingen isoleret organisk baseline. |
| Oversigt, ugentligt kort aflæst 9. september; præcise datogrænser ikke gemt | **888 plays fra annoncer** | Annoncer har allerede leveret trafik. Det viser ikke kampagnepris, unikke nye brugere, overskud eller om annoncer stadig kører. |
| Monetization, valgt **Last 7 days**, aflæst 9. september; præcise datogrænser ikke gemt | Net Daily Robux Spent: **63 i alt**, **9 dagligt**; Developer Products **63**; Standard DevEx Rate **63** | Der findes faktiske omsætningstal. Denne sum er ikke en målt 30-dages annoncekohorte. |
| Samme Monetization-visning | Gennemsnitlig daglig payer conversion **0,04 %**; betalere vist afrundet som **0**; Robux pr. betalende bruger **3,00**; Robux pr. daglig bruger **0,00761** | Lavt salg er et undersøgelsespunkt. Afrundet 0 betyder ikke, at ingen har betalt. Gennemsnit med forskellige nævnere må ikke kombineres til et beregnet antal køb. |
| Separat benchmarkkort, spilletid pr. **7. september** | **12,7 min.** | Blandes ikke med oversigtens 12,5 min. |
| Separat benchmarkkort, D1 pr. **6. september** | **1,77 %** | Blandes ikke med oversigtens 1,45 %. |
| Separat benchmarkkort, D7 pr. **31. august** | **0,00 %** | Ældre kohorte. Det beviser ikke effekten af rettelser udgivet i september. |
| Separat benchmarkkort, payer conversion pr. **7. september** | **0,04 %** | En anden periode end en fuld 30-dages konvertering. |
| Separat Hourly Robux Spent-graf | **120 i alt**: passes **69**, developer products **51** | Et andet tidsvindue end Last 7 days. Må ikke lægges oven i de 63 eller bruges som samme periodes produktsplit. |

Dashboardet oplyste to dages dataforsinkelse. Realtime viste 10 samtidige spillere omkring kl. 22.32 den 9. september; det er et øjebliksbillede, ikke DAU. Originalens 5.533 livstidsbesøg divideret med 47 dage giver cirka 118 besøg pr. dag over hele perioden. Det er **hverken aktuel DAU eller et mål for daglige købsprompter**.

Der findes også monetisering uden for de 12 shopvarer: [Access-indstillingerne](https://create.roblox.com/dashboard/creations/experiences/10559217407/access) viste betalte private servers med standardpris **20 Robux**, **2 aktive abonnementer** og regional pricing slået til. Behold denne indstilling indtil brug og indtjening er undersøgt særskilt. Roblox Plus kan give abonnenter adgang til betalte private servers uden direkte betaling; derfor kan abonnementstallet ikke oversættes til 40 Robux i månedlig indtjening. [Roblox Plus](https://create.roblox.com/docs/production/monetization/roblox-plus)

## Anbefaling for alle 12 eksisterende produkter

| Produkt | Type / ID | Pris | Faktisk værdi | Beslutning og begrundelse |
|---|---|---:|---|---|
| Zyntra Supporter | Pass `1941938256` | **99** | 10 Research Tokens én gang og permanent supporter-tag | **Behold 99 og nuværende ydelse.** Relevant engangsalternativ for en ikke-ejer, der ønsker mindst 10 tokens. Daglige bonusser er en separat designidé. |
| Advanced Equipment | Pass `1945402536` | **149** | Hazmat-farvevælger samt én fast +5 %-opgradering af både stamina- og batterikapacitet | **Behold 149.** Beskriv farvevælgeren tydeligt og de to faste opgraderinger præcist. Den aktuelle konfiguration beskriver allerede dette korrekt. Ingen frie tokens følger med. |
| Glowstick Customizer | Pass `1946086261` | **99** | Permanent glowstick-farvevælger, kun kosmetik | **Behold 99.** Prisen ligger inden for det observerede kosmetikfelt. Manglende salg kan skyldes eksponering eller præference såvel som pris. |
| 4 Research Tokens | Developer product `3707755089` | **49** | 4 tokens, kan købes gentagne gange | **Behold 49.** 12,25 Robux pr. token. En eventuel 5-pakke vurderes som et selvstændigt emballageforslag. |
| 20 Research Tokens | Developer product `3707755233` | **149** | 20 tokens, kan købes gentagne gange | **Behold 149.** 7,45 Robux pr. token, cirka **39,18 % lavere enhedspris** end 4-pakken. Permanente, gentagelige opgraderinger giver allerede anvendelse for flere pakker. |
| Emergency Re-entry | Developer product `3707755318` | **29** | Én lagret credit; højst én re-entry pr. spiller pr. runde. Køb i PARTY DOWN-vinduet på 15 sekunder kan bruges dér; et sent køb lagres | **Behold 29.** Forklar timing og lagring. Konkurrenters ubekræftede revivepriser bruges ikke som bevis for den rette pris. En 3-pakke er kun en idé. |
| Donate — Signal | Developer product `3710116814` | **10** | Frivillig støtte; tæller i donationsrangliste, ingen gameplayydelse | **Behold 10.** Lav indgang til frivillig støtte. |
| Donate — Supply | Developer product `3710116945` | **50** | Samme donationsfunktion | **Behold 50.** Intet datagrundlag for at flytte trinnet. |
| Donate — Field | Developer product `3710117017` | **100** | Samme donationsfunktion | **Behold 100.** Mål faktisk efterspørgsel pr. trin. |
| Donate — Research | Developer product `3710117070` | **250** | Samme donationsfunktion | **Behold 250.** Personlig anerkendelse kan undersøges uafhængigt af pris. |
| Donate — Command | Developer product `3710117099` | **500** | Samme donationsfunktion | **Behold 500.** Ingen dokumenteret grund til prisændring eller fjernelse. |
| Donate — Director | Developer product `3710117136` | **1.000** | Samme donationsfunktion | **Behold 1.000.** Et frivilligt højt støttetrin. Nul salg i en kort periode ville ikke alene begrunde sletning. |

Kilde til ydelser og ID'er: [ZyntraConfig](G:/Roblox/MongoTV/ReplicatedStorage/ZyntraConfig.ModuleScript.lua) og [ZyntraMonetization](G:/Roblox/MongoTV/ServerScriptService/ZyntraMonetization.Script.lua), genlæst 9. september. Ranglisten er aktuelt top 10. Tabellen beskriver donationsfunktionen før det separate Trello-arbejde om at tælle alle køb som støtte.

To 4-pakker koster 98 Robux for 8 tokens; en ikke-ejer kan for 99 få Supporter med 10 tokens og tag. Det er en nyttig sammenligning i shoppen, men kun mens Supporter ikke allerede ejes og med den pågældende spillers faktiske priser. Passet kan ikke genkøbes som en tokenpakke. Advanced Equipment kan heller ikke omregnes til to tokens, som spilleren frit kan bruge på beskyttelse eller på én valgt stat.

## Konkurrenter: prispejling med begrænsninger

Fire offentlige Roblox-endpoints blev genlæst ved revisionen. De viste varer til salg, tomme `PriceDiscountDetails` og samme standard- og svarpris:

| Sammenligning | Pris 9. september | Relevant observation |
|---|---:|---|
| Backrooms Company — Customizable Suit Colors | [149](https://apis.roblox.com/game-passes/v1/game-passes/1966287000/product-info) | Farvevælgeren er relevant for hazmat-delen af Advanced Equipment. Den er ikke identisk med hele vores ydelse. |
| The True Backrooms: Renovated — Upgraded Phone | [149](https://apis.roblox.com/game-passes/v1/game-passes/1963746253/product-info) | En permanent udstyrsopgradering; et andet spil med en anden nytteværdi. |
| Pressure — Chibi Keycharm Pack | [75](https://apis.roblox.com/game-passes/v1/game-passes/1576059128/product-info) | Et andet kosmetisk produkt. |
| Pressure — Rotten Coral Skin Pack | [149](https://apis.roblox.com/game-passes/v1/game-passes/1593392110/product-info) | Et kosmetisk sæt med anden mængde indhold. |

De egne passpriser blev kontrolleret på samme måde: [Supporter 99](https://apis.roblox.com/game-passes/v1/game-passes/1941938256/product-info), [Advanced Equipment 149](https://apis.roblox.com/game-passes/v1/game-passes/1945402536/product-info) og [Glowstick Customizer 99](https://apis.roblox.com/game-passes/v1/game-passes/1946086261/product-info). API-svarene dokumenterer udbudspriser, ikke salgstal, betalingsvillighed eller en kausal effekt af prisen.

Originalens større konkurrenttabel er et researchbilag, ikke en repræsentativ markedsundersøgelse. Dens DOORS- og Pressure-revives bygger på wiki-/guideoplysninger med modstridende alder og priser; de **udelades som aktuelle prissammenligninger** her. Et permanent ekstra liv eller en evne med gentagen brug kan ikke værdiansættes som én forbrugt revive ved at dividere passets pris med en nominel mængde liv. Formuleringer som “billigst på markedet” og “præcis samme værdi” er derfor ikke grundlag for anbefalingerne.

## Det besluttede produkt: 5 tokens for 5 sekunder

Ejeren har valgt **5 tokens pr. aktivering af 5 sekunders usynlighed/dødsbeskyttelse**. Den pris bevares. Der er ingen tilsvarende forbrugsvare med tilstrækkelig verificeret mekanik og pris i det gennemgåede materiale til at kalde den markedsvalideret.

Et token giver aktuelt én permanent opgradering på +5 % af basiskapaciteten, og serveren tillader gentagne opgraderinger uden et øvre loft. Hvert gennemført level giver ét token, også ved gentagelse. Derfor er beskyttelse **en yderligere anvendelse for tokens**; den er ikke den første gentagelige anvendelse og skaber ikke den første grund til at genkøbe 20-pakken.

| Vej til tokens | Regnet værdi af 5 tokens | Faktisk indkøb eller optjening |
|---|---:|---|
| 20-pakken | **37,25 Robux** ved pakkens enhedspris | 149 Robux køber 20 tokens, nok til fire aktiveringer. |
| Supporter | **49,50 Robux** ved simpel fordeling på tokens | 99 Robux giver 10 tokens samt tag én gang. Beløbet er ikke en separat pris for beskyttelse. |
| 4-pakken | **61,25 Robux** ved pakkens enhedspris | En spiller med nul tokens skal købe to pakker for 98 Robux og har tre tokens tilbage efter én brug. De resterende tokens kan fortsat bruges. |
| Spil | Ingen Robux nødvendig | Fem gennemførte levels giver fem tokens. Tid afhænger af level, nederlag og spillerens tempo. |

Én brug forbruger en saldo, som alternativt kunne købe fem permanente opgraderinger. Det kan gøre nogle spillere tilbageholdende, men der er endnu ingen data om hamstring eller efterspørgsel. Re-entry til 29 Robux er en anden ydelse med en anden timing og begrænsning; det er ikke en universel “fuld undo”, der gør beskyttelse værdiløs.

Før funktionen kan kaldes klar, skal den have en tydelig aktivering i runden, serverstyret betaling/tid, og samme beskyttelsesregel i alle relevante AI-angreb og direkte dødsforløb. Effekten må ikke blot skjule figuren, mens en allerede låst angriber stadig dræber. Test også udløb, gentagne tryk, for lav saldo, død/round-skift og genindtræden. Det er funktionskrav, ikke nye prisbeslutninger. En præcis 5-tokenpakke er **valgfri**; den eksisterende saldo og gratis optjening er tilstrækkelige betalingsveje. En delbar team-effekt, cooldown eller andre ekstra mekanikker er separate designvalg.

## Shopidéer, rangeret efter værdi og omfang

Alle priser nedenfor er hypoteser til senere afprøvning. Ingen af disse varer er oprettet eller godkendt til automatisk implementering af researchrapporten. “Omfang” er et relativt skøn, ikke et tidsestimat.

| Prioritet | Idé | Foreslået indhold/pris | Omfang | Hvorfor den er interessant, og hvad der skal afklares |
|---|---|---|---|---|
| 1 | Tydelig personlig støttehistorik og donormarkering | Vis egen samlede støtte og en diskret markering; ingen ny betaling | Lille–middel | Anerkendelse kan nå flere end top 10. Afstem først med Trello-ændringen om alle køb, så beløb ikke dobbelttælles, og tagget ikke forveksles med Supporter. |
| 2 | Valgfri pakke med 5 tokens | Eksempel **59 Robux**; 11,80 pr. token | Lille–middel | Kan gøre ét beskyttelseskøb lettere at forstå. Afklar om den erstatter 4-pakken eller gør shoppen mere uoverskuelig. Eksisterende køb skal fortsat give lovet indhold. |
| 3 | Emergency Re-entry ×3 | Eksempel **69 Robux**, 23 pr. credit | Middel | Giver credits på forhånd. Samme grænse på én brug pr. spiller pr. runde skal fremgå. Mål om købere forstår lagringen; forudsæt ikke højere indtjening. |
| 4 | Flashlight-housing eller hazmat-detaljer | Kosmetik uden styrkefordel; eksempel **99 Robux** | Middel | Passer til udstyr, som spilleren ser. Vis en forhåndsvisning; beskyt læsbarhed og lysstyrke. Vælg ét koncept ud fra spillerinteresse frem for at tilføje begge straks. |
| 5 | Samlet kosmetikpakke | Begge farvevælgere; eksempel **199 Robux** | Middel–stor | En fælles købsvej kan være nyttig. Kræver korrekt ejerskabshåndtering for spillere, der allerede ejer et eller begge passes; undgå betaling for samme adgang igen. |
| 6 | Team-forsyning | En begrænset fælles stamina-/batterigenopfyldning; pris ikke fastsat | Stor | Kan passe til co-op. Kræver balance og klarhed om hvem der får ydelsen; kan udhule spillets ressourcepres. |
| 7 | Løbende Supporter-bonus | Eksempel ét token pr. dag, ingen prisændring foreslået | Stor økonomisk usikkerhed | Kan give en ny grund til at vende tilbage. Kræver måling af tokenøkonomi og beslutning om nye, vedvarende forpligtelser; implementeres ikke som en simpel tekstrettelse. |

Abonnementer med daglige tokens, højere party-cap og nye permanente styrkepasses sættes bag disse idéer. Det er større designændringer, og betalte private servers findes allerede. Et loft over eksisterende permanente opgraderinger foreslås ikke som automatisk ændring; det ville ændre værdien af tidligere optjente og købte tokens.

## Priser vist til den enkelte spiller

Læs Managed Pricing-status pr. produkt i dashboardet, før en rabat vælges. Standardindstillinger i dokumentationen beviser ikke alle 12 konkrete varers aktuelle status. Managed Pricing kan ændre priser efter økonomisk region, og nye varer er som udgangspunkt tilmeldt. [Managed Pricing](https://create.roblox.com/docs/production/monetization/managed-pricing)

Shoppen skal vise den aktuelle spillerpris fra MarketplaceService. Dynamic Price Check kan kontrollere både en fast testpris og en simuleret region. En hårdkodet standardpris er ikke tilstrækkelig verifikation af checkout. [Regional pricing og Dynamic Price Check](https://create.roblox.com/docs/production/monetization/regional-pricing)

Roblox Plus giver 10 % rabat i de første to abonnementsmåneder og 20 % fra den tredje; Roblox finansierer rabatten. Vis eventuelle platformrabatter ud fra `PriceDiscountDetails`, `UserBasePriceInRobux` og `PriceInRobux`. Disse felter beskriver den aktuelle platformpris; de er ikke dokumentation for en historisk førpris i vores egen kampagne. [Roblox Plus](https://create.roblox.com/docs/production/monetization/roblox-plus)

## Et konkret, ægte rabatforslag

**Forslag til senere beslutning:** En tidsafgrænset kampagne på 20-tokenpakken med standardpris **149 → 119 Robux**, eksempelvis i syv dage. Det er en reduktion på **30/149 = 20,13 %** af standardprisen. Vælg præcise datoer og sluttidspunkt før annoncering, dokumentér den faktisk anvendte normalpris, og registrér prisens tilbageførsel. Ingen dato er lovet, og ingen pris er ændret nu.

Kampagnen kan beskrives som “Standardprisen på 20 tokens er sænket fra 149 til 119 Robux til [dato/tid]. Din aktuelle pris vises ved køb.” Den brede spillerkommunikation bør fokusere på den aktuelle API-pris. Skriv kun en personlig “før/nu”-pris eller præcis procentrabat, hvis netop den sammenligning er verificeret for spilleren. Regional pricing og Plus betyder, at **119 og 20,13 % ikke nødvendigvis beskriver hver spillers betaling**. Slå ikke Managed Pricing fra automatisk for at gøre et banner enklere.

Der blev ikke fundet tilstrækkelig officiel dokumentation for et generelt creator-styret værktøj, der planlægger og viser sådanne procentrabatter på alle passes og developer products. Det er en afgrænset researchkonklusion, ikke bevis for at funktionen ikke findes. Den konkrete dashboardmulighed skal kontrolleres ved en senere kampagne. [Managed Pricing](https://create.roblox.com/docs/production/monetization/managed-pricing) beskriver prisstyringen, men er ikke i sig selv dokumentation for en planlagt udsalgsvisning.

20-pakken er valgt, fordi det er ét gentageligt produkt med enkel før/efter-mængde. Den er ikke den “eneste sikre” vare at rabattere. Andre rabatter kan ændre relative værdier i kataloget; en lavere Advanced-pris beviser eksempelvis ikke, at Glowstick-salg stopper. Donationer holdes uden for dette forslag, fordi en rabat på frivillig støtte er vanskelig at formidle meningsfuldt.

En alternativ kampagneidé er **26 tokens for 149 Robux**. Det giver 30 % flere tokens og cirka 23,08 % lavere pris pr. token; det er ikke 30 % rabat. Den kræver en korrekt tidsafgrænset tildeling for alle berettigede køb. Ingen tokenbonus eller prisforskel skal annonceres, før leveringen er klar.

Vælg om en kampagne primært er en markering af en opdatering eller et forsøg på at måle prisens effekt. Ved en samtidig indholdsopdatering kan et højere salg ikke tilskrives rabatten alene. Der er ikke grundlag for løfter om positiv indtjening.

## Måling før større prisændringer

Den lave observerede payer conversion gør det relevant at undersøge forløbet: **kom ind i level → fandt Equipment/Shop → så varen → åbnede køb → fik ydelsen**. Registrér kilden til besøget og faktiske nævnere. Brug serverbekræftet tildeling til at tælle køb; et lukket prompt er ikke alene et leveret developer product-køb. Mål også tokens optjent, købt og brugt på hver funktion.

Et simpelt regneeksempel med 2 % mod 3 % købsrate kræver omtrent 7.650 uafhængige eksponerede brugere samlet ved en tosidet test, 5 % signifikans og 80 % styrke. Det er en illustrativ antagelse, ikke en prognose for dette spil. Originalens 12 daglige prompts var også en antagelse. Faktisk volumen, gentagne besøg, den valgte effektstørrelse og forsøgsdesign bestemmer, hvor længe en test skal køre. En generel regel om “altid seks måneder” er ikke begrundet.

Roblox skriver, at et spil **i de fleste tilfælde bør have** mindst 60.000 transaktioner de sidste 30 dage for en vellykket prisoptimeringstest. Det er en vejledning om datamængde; det skal ikke gengives som en universel hård adgangsgrænse. Den konkrete tilgængelighed afgøres i dashboardet. [Price optimization](https://create.roblox.com/docs/production/monetization/price-optimization)

Brug fejl som konkrete signaler: undersøg enhver bekræftet betaling uden levering straks. En reproducerbar startfejl prioriteres efter omfang og alvor. Originalens faste grænser på 2 % startfejl, 70 % hamstring eller nul salg på otte uger er ikke validerede standarder, og de begrunder ikke automatisk at stoppe al monetisering eller fjerne varer. Aftal grænser ud fra den faktiske baseline og konsekvensen for spilleren.

## Annoncer: gennemgå det eksisterende forbrug først

**Anbefaling: Udvid ikke annonceforbruget på grundlag af denne rapport.** Der er allerede observeret 888 ugentlige annonce-plays. Læs de eksisterende kampagners forbrug, datoer, mål, trafiktyper og resultater, før et nyt budget overvejes. Rapporten hverken opretter, pauser eller ændrer kampagner og giver ingen bemyndigelse til at bruge penge eller konvertere Robux til annoncekreditter.

En dårlig start kan spilde annoncebudget og give spillere en dårlig oplevelse. Det er ikke korrekt at hævde, at annoncehvervede spilleres bounce direkte sænker Home-rankingen: Roblox beskriver den som baseret på brugere, der kom organisk fra Recommended For You. Andre kilder kan hjælpe spillet til at blive overvejet til distribution, men deres engagement indgår ikke direkte i denne rankingkohorte. [Discovery](https://create.roblox.com/docs/discovery)

Før en eventuel udvidelse skal følgende være konkret belyst:

1. Lobby-start og relevante levels fungerer i publicerede servere, også med flere spillere og re-entry. En serie på eksempelvis 20 fejlfri starter er nyttig QA, men beviser ikke, at den sande fejlrate er under 2 %.
2. Nye spillere kan finde shoppen og forstå ydelser, priser og købsvinduer. Observer adfærden, ikke kun egen gennemgang.
3. Organiske og betalte besøgende analyseres hver for sig. En 14-dages baseline giver tidlige observationer; D7 bruges kun for brugere med syv fulde dages opfølgning. Den giver ikke modne 30-dages omsætnings- eller betalerkohorter. [Acquisition](https://create.roblox.com/docs/production/analytics/acquisition)
4. Varernes checkoutpriser og tildeling er kontrolleret. Oplevelsens aktuelle målgruppetilgængelighed og annonceringsmuligheder skal være verificeret. Dashboardet viste ved aflæsningen adgang for **16+ og trusted friends**, selv om indholdsmærkningen var **Mild**; de to størrelser må ikke sidestilles.

Hvis ejeren senere vælger en pilot, er forslaget én tydelig hypotese, ét godkendt budgetloft, et afgrænset publikum og en aftalt observationsperiode, eksempelvis syv kampagnedage. Vælg mål efter formålet: spilleranskaffelse og opfyldelse af en engagementstærskel er forskellige investeringer. Historiske budintervaller fra 2024 bruges ikke som et forventet 2026-CPP eller som budgetanbefaling. Brug den aktuelle kontos faktiske tal og den seneste prisvisning ved kampagneopsætningen.

Ads Managers attribution afhænger af brugergruppen: nye brugere får op til 30 dage efter første annoncejoin; nylige brugere kun sessioner startet fra annoncen; genaktiverede brugere får 7 eller 30 dage afhængigt af deres tidligere fravær. Rapporteringen kan være op til 48 timer forsinket. Hold disse grupper adskilt. [Ads Manager, reporting](https://create.roblox.com/docs/production/promotion/ads-manager)

For en fuld 30-dages vurdering af **alle nye brugere** i en syvdageskampagne skal aflæsningen ske tidligst **32 dage efter sidste relevante første join**, omtrent dag **39** fra kampagnestart. Senere joins flytter datoen. Dag 32 fra kampagnestart er for tidligt. Det er en tidsberegning ud fra attribution og forsinkelse, ikke en garanti for færdigafregnede tal. D1/D7 kan læses tidligere for modne kohorter.

### Sammenlign samme kohorte og samme valuta

Beregn en økonomisk sammenligning som:

**30-dages nettoindtægt i USD fra den afgrænsede annoncekohorte ÷ annonceudgift i USD.**

Nettoindtægten skal bygge på faktisk tilskrevne og leverede køb, korrigeret for Roblox' andel, relevante reguleringer og den gældende DevEx-sats. Er et eksporttal allerede netto/Earned Robux, skal Roblox' andel ikke trækkes fra igen. Undgå at tælle samme indtægt både i Ads Manager og egen kohorteopgørelse. En forskel mellem betalte og organiske brugere alene beviser heller ikke annoncernes kausale effekt.

Ved standardandelen på 70 % giver et køb til 149 Robux illustrativt **149 × 0,70 × 0,0038 = 0,39634 USD** før skat og eventuelle reguleringer. Et creator-udsalg til 119 giver under samme antagelser **0,31654 USD**; Roblox finansierer ikke vores egen prisnedsættelse. [Creator share](https://create.roblox.com/docs/monetize), [DevEx](https://create.roblox.com/docs/production/monetization/developer-exchange)

Satsen **0,0054 USD** gælder kun kvalificerede Earned Robux fra de relevante amerikanske, aldersverificerede 18+-køb i kvalificerede spil. Den er cirka **42,11 % højere** end 0,0038. Kravene vedrører spillerfigurer hele den aktive spilletid: R15 eller kvalificerede custom-figurer; mulighed for R6 under aktivt spil udelukker kvalifikation. NPC'er omfattes ikke. Den konkrete oplevelses kvalifikation er endnu ikke verificeret her, og dashboardets aflæste indtjening stod som **Standard DevEx Rate**. Brug derfor ikke den høje sats på al omsætning. [U.S. 18+ exchange rate](https://create.roblox.com/docs/production/monetization/18-plus-devex-rate)

CPP tæller plays, som kan omfatte genbesøg; indtægt pr. unik ny bruger har en anden nævner. Brug derfor helst kohortens samlede nettoindtægt mod dens samlede henførbare annonceudgift. Hvis udgiften ikke kan adskilles mellem nye og tilbagevendende brugere, skal resultatet mærkes som en blandet kampagneopgørelse og må ikke præsenteres som rent new-user-afkast. En positiv 30-dages ratio er ikke det samme som fortjeneste efter arbejdstid og øvrig drift, og få betalere giver stor usikkerhed.

## Beslutninger og udeståender

**Nu:** De 12 priser anbefales bevaret. Ejerens 5-tokenpris er fast. Spilrettelser og en forståelig shop prioriteres, og de observerede dashboardtal bruges frem for historiske trafikgæt.

**Før en senere pris- eller kampagnebeslutning:** Afklar Managed Pricing pr. vare, Dynamic Price Check, faktiske køb/tildeling, eksisterende annonceforbrug, kohorter pr. trafikkilde og den relevante nettoindtægt. Ingen generelle prisændringer, daglige Supporter-grants, nye shopvarer, statlofter eller annonceudgifter følger automatisk af denne rapport.

**Proveniens:** Originalrapportens SHA256 før og efter revision: `70A0E03C22F6359765F2FF46170CFFEE23513942CB67A52A2FECB75E1DCCFB81`. Kode og priser kan ændres af det parallelle Trello-arbejde; ovenstående er observationer fra 9. september 2026, ikke en garanti for en senere publiceret version. Kritikerens slutscore er **9/10** efter læsning af hele revisionen, kontrol af centrale beregninger, produkt-ID'er og grants mod aktuel konfiguration samt originalens hash. Reviewet godkender researchgrundlaget; det er ikke en bestilling af nye varer eller annonceforbrug.
