# Zyntra monetization: analyse og opsætningsguide

Senest kontrolleret: 27. august 2026. Alle 12 Creator Dashboard Asset IDs er indsat og verificeret mod experience `10559217407`.

## Anbefalet launch-katalog

Zyntras nuværende opdeling er grundlæggende rigtig: permanente fordele er Game Passes, mens valuta og forbrug er Developer Products. Supporter bør ikke være en subscription ved første release.

| Intern nøgle | Dashboard-navn | Roblox-type | Basispris | Asset ID | Spillerens køb |
|---|---|---|---:|---:|---|
| `Supporter` | Zyntra Supporter | Pass | 99 R$ | `1941938256` | 10 Research Tokens én gang og permanent supporter-tag |
| `AdvancedEquipment` | Advanced Equipment | Pass | 149 R$ | `1945402536` | Én permanent +5% stamina-opgradering, én permanent +5% batteri-opgradering og hazmat color picker |
| `CosmeticEquipment` | Glowstick Customizer | Pass | 99 R$ | `1946086261` | Permanent glowstick color picker |
| `Tokens4` | 4 Research Tokens | Developer Product | 49 R$ | `3707755089` | 4 tokens; kan købes igen |
| `Tokens20` | 20 Research Tokens | Developer Product | 149 R$ | `3707755233` | 20 tokens; kan købes igen |
| `EmergencyReentry` | Emergency Re-entry | Developer Product | 29 R$ | `3707755318` | 1 gemt re-entry-credit; kan købes igen |
| `DonationSignal` | Donate Signal | Developer Product | 10 R$ | `3710116814` | Donation til spillets fortsatte udvikling |
| `DonationSupply` | Donate Supply | Developer Product | 50 R$ | `3710116945` | Donation til spillets fortsatte udvikling |
| `DonationField` | Donate Field | Developer Product | 100 R$ | `3710117017` | Donation til spillets fortsatte udvikling |
| `DonationResearch` | Donate Research | Developer Product | 250 R$ | `3710117070` | Donation til spillets fortsatte udvikling |
| `DonationCommand` | Donate Command | Developer Product | 500 R$ | `3710117099` | Donation til spillets fortsatte udvikling |
| `DonationDirector` | Donate Director | Developer Product | 1.000 R$ | `3710117136` | Donation til spillets fortsatte udvikling |

`Glowstick Customizer` er et anbefalet klarere kundenavn end det nuværende `Cosmetic Equipment Packs`, fordi passet kun indeholder glowstick-farven. Den interne nøgle kan fortsat hedde `CosmeticEquipment`.

## Færdig ikonpakke

De seks uploadklare filer ligger i `assets/monetization/icons-512`. De er præcis 512 x 512 PNG, uden pris eller tekst i motivet, og er visuelt kontrolleret med Roblox' cirkulære beskæring.

![Zyntra monetization icon preview](../assets/monetization/zyntra-icon-preview-sheet.png)

Filnavne, full-resolution masters og det anvendte prompt-set er dokumenteret i `assets/monetization/README.md`.

### Tekster til Creator Dashboard

**Zyntra Supporter**

> Receive 10 Research Tokens once and unlock a permanent ZYNTRA SUPPORTER tag.

**Advanced Equipment**

> Permanently unlock the hazmat color picker and receive one +5% upgrade to both Stamina Capacity and Battery Capacity.

**Glowstick Customizer**

> Permanently unlock the glowstick color picker for every glowstick you deploy. Cosmetic only.

**4 Zyntra Research Tokens**

> Adds 4 Research Tokens to your account. Spend each token on a permanent +5% upgrade to either Stamina Capacity or Battery Capacity.

**20 Zyntra Research Tokens**

> Adds 20 Research Tokens to your account. Spend each token on a permanent +5% upgrade to either Stamina Capacity or Battery Capacity.

**Emergency Re-entry**

> Adds 1 stored Emergency Re-entry credit. After dying during an active run, use it to rejoin once that round.

**Alle seks Donate-produkter**

> Donate toward the continued development of BACKROOMS: STAY QUIET [CO-OP HORROR].

## Nuværende status i spillet

- Alle 12 køb er implementeret i UI og serverscript.
- Alle 12 `Id`-felter er udfyldt og verificeret mod den aktive experience.
- Data gemmes i `ZyntraPlayerData_v1`.
- Én token giver permanent +5% til enten stamina- eller batterikapacitet uden maksimum.
- Hver gennemført level giver 1 gratis token, også ved gentagne clears.
- Supporterens 10 tokens og Advanced Equipments to +5%-grants gives kun én gang via gemte grant-flags.
- Developer Products behandles centralt gennem `MarketplaceService.ProcessReceipt`.
- En global Top Donors-tavle summerer kun den præcise `CurrencySpent` fra de seks dedikerede donationers receipts i `ZyntraDonationLeaderboard_v2`. Utility-produkter og passes tælles ikke med. Den nye v2-tavle migrerer bevidst ikke gamle utility-køb.
- Supporter giver ikke længere adgang til hazmat-styling; den ligger udelukkende i Advanced Equipment.
- Butikken henter aktuelle/personaliserede Roblox-priser og bruger Config-prisen som fallback.
- Studio giver automatisk alle passes og starter spilleren med 25 tokens; Studio kan derfor ikke bevise, at rigtige køb virker.
- Zyntra-butikken viser tekstkort. Ikonerne bruges straks på Roblox' købssider, men kræver en senere `ImageLabel`-udvidelse for også at blive vist i spillets terminal.

## Release-vurdering

### Klar til opsætning

- Zyntra Supporter
- Advanced Equipment
- Glowstick Customizer
- 4 Research Tokens
- 20 Research Tokens

### Emergency Re-entry — 15 sekunder valgt og Studio-test bestået

Kontrolleret 5. september 2026: produkt `3707755318` stod allerede **on-sale**
i Creator Dashboard med basispris **29 R$** og Managed pricing aktivt. Ingen
salgsindstilling eller pris blev ændret. Wipe-vinduet beholder **15 sekunder**,
som ejeren tidligere ønskede. De tre tests fra Trello samt en sen receipt
bestod i Studio; se [testbeviset](EMERGENCY_REENTRY_VALIDATION_2026-09-05.md).
Der blev ikke brugt rigtige Robux eller testet en rigtig betaling i en
publiceret server.

De tre oprindelige problemer, opdateret 4. september 2026:

1. **Besluttet 5. september: behold 15 sekunder.** `playRound` i
   `GameManager` sætter `wipeDeadline = os.clock() + 15`, og hele købet —
   prompt, betaling og `ProcessReceipt` — skal nå at ske inden for det, hvis
   købet skal redde netop den runde. 45-60 sekunder var den tidligere
   anbefaling; ejerens valg er 15 sekunder. Et køb efter udløbet gemmer en
   credit til senere brug. Begge timing-udfald blev observeret i Studio.
2. **Rettet.** Et køb, der lander mens spilleren stadig er død i en aktiv runde,
   bruger nu credit'en med det samme. `ProcessReceipt` kalder `useReentry` i en
   `task.spawn`, efter at credit'en er givet, og kun når spilleren opfylder
   præcis de samme betingelser som butikkens knap: `InRound`, `RoundActive`,
   ikke `ZyntraReentryUsed`, og ingen levende Humanoid. Der skal ikke trykkes to
   gange længere.
3. **Rettet.** Credit'en reserveres nu FØR respawnet. `useReentry` trækker
   credit'en i `mutate()`, kalder derefter `ZyntraReentry`-BindableFunction og
   lægger credit'en tilbage, hvis respawnet afvises. En fejlet save kan ikke
   længere give et gratis respawn; det værst tænkelige udfald er en credit brugt
   på et afvist respawn, og det tilfælde tilbagefører sig selv. Refunderingen er
   nøglet på et token pr. forsøg, så et forsøg, der bliver afløst, gentaget
   eller afbrudt af at spilleren forlader serveren, aldrig kan give credit to
   gange. Selve tilbageførslen prøves op til tre gange, fordi en enkelt
   DataStore-fejl ellers ville forvandle "respawn afvist" til "betalt credit
   væk"; lykkes ingen af dem, står der en `[Zyntra] Re-entry refund FAILED`
   i output med spillerens userId, så credit'en kan gives tilbage manuelt.

Samme vindue viser nu også et PARTY DOWN-kort: serveren sender `partydown` med
15 sekunder og navnet på den sidst døde, og `partydownclear`, når en re-entry
bringer nogen tilbage, eller runden rives ned. Kortet gør vinduet synligt, hvilket
er en forudsætning for, at produktet overhovedet kan sælges inden for det.

**Ikke dækket af Studio-testen:** en rigtig end-to-end-betaling i en
publiceret server. Ved en sådan test skal man købe midt i wipe-vinduet og
verificér, at respawnet sker uden et ekstra tryk, at credit'en trækkes præcis én
gang, og at et køb, der lander efter vinduet er lukket, giver credit'en tilbage
i stedet for at forsvinde.

## Økonomisk analyse

- 4-pakken koster 12,25 R$ pr. token.
- 20-pakken koster 7,45 R$ pr. token.
- 20-pakken er dermed cirka 39,2% billigere pr. token end fem 4-pakker. Det er en tydelig, men forståelig volumenrabat.
- Supporter giver 10 tokens for 9,9 R$ pr. token plus kosmetiske fordele. Det fungerer godt som en attraktiv engangs-startpakke uden at kunne genkøbes.
- Fordi spillere også får gratis tokens for clears, er modellen pay-to-progress og ikke en ren betalingsmur.
- Uendelige, lineære +5%-opgraderinger og uendelig farming af det letteste level kan på sigt fjerne survival-spændingen. Behold gerne designet til første telemetry-test, men mål clear-rate, gennemsnitligt upgrade-level og tokenkøb. Overvej derefter diminishing returns eller first-clear/daily rewards.

## Trin 1: publicér den rigtige experience

Spillet skal være publiceret og tilgængeligt på Roblox, før passes kan oprettes.

1. Åbn den korrekte Studio-version af `BACKROOMS: STAY QUIET [CO-OP HORROR]`.
2. Vælg `File -> Publish to Roblox`.
3. Kontrollér, at Creator/Group og experience er den samme, som monetization skal udgives under.
4. Åbn [Creator Dashboard](https://create.roblox.com/dashboard/creations) og vælg den nuværende experience `BACKROOMS: STAY QUIET [CO-OP HORROR]`.

Opret alle produkter under den samme experience. Roblox deaktiverede cross-game-salg af passes og Developer Products den 30. maj 2026.

## Trin 2: opret de tre passes

Gentag dette for `Zyntra Supporter`, `Advanced Equipment` og `Glowstick Customizer`:

1. Gå til `Creations -> BACKROOMS: STAY QUIET [CO-OP HORROR] -> Monetization -> Passes`.
2. Klik `Create pass`.
3. Upload det matchende 512 x 512 PNG-ikon fra `assets/monetization/icons-512`.
4. Indsæt navn og beskrivelse fra tabellen ovenfor.
5. Vælg en passende shop-kategori og klik `Create pass`.
6. Åbn passet og gå til `Sales`.
7. Slå `Item for Sale` til, angiv basisprisen og gem.
8. På passets tile: `... -> Copy Asset ID`.
9. Sammenlign det kopierede ID med tabellen øverst; de seks IDs er allerede indsat i koden.

Managed Pricing er automatisk aktivt for passes. Det kan give regionale priser helt ned til 30% af basisprisen. Anbefalingen er at beholde det aktivt, men kun når Zyntra-terminalen viser dynamiske priser.

## Trin 3: opret Developer Products

Gentag dette for de tre utility-produkter og de seks frivillige Donate-produkter:

1. Gå til `Creations -> BACKROOMS: STAY QUIET [CO-OP HORROR] -> Monetization -> Developer Products`.
2. Klik `Create developer product`.
3. Upload det matchende 512 x 512 PNG-ikon.
4. Indsæt navn, beskrivelse og basispris.
5. Klik `Save Changes`.
6. På produktets tile: `... -> Copy Asset ID`.

Managed Pricing er ikke automatisk aktivt for Developer Products. Lad det være slået fra under den første end-to-end-test. Når UI'et henter rigtige runtime-priser, kan det aktiveres; Zyntra har ingen token-gifting/trading, så den normale regional-price-arbitrage-risiko er lav.

## Trin 4: verificér de 12 Asset IDs

De 12 Asset IDs er allerede indsat i `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`; donationerne ligger i den separate `Donations`-tabel.

```lua
Passes = {
	Supporter = { Id = 1941938256, ... },
	AdvancedEquipment = { Id = 1945402536, ... },
	CosmeticEquipment = { Id = 1946086261, ... },
},

Products = {
	Tokens4 = { Id = 3707755089, ... },
	Tokens20 = { Id = 3707755233, ... },
	EmergencyReentry = { Id = 3707755318, ... },
},
```

Roblox opkræver altid Dashboard-prisen. `Price` i ZyntraConfig er i øjeblikket kun fallback-/displaytekst og kan ikke styre den virkelige pris.

## Trin 4b: opret de fire badges

De første fem badges pr. experience pr. GMT-døgn er gratis; derefter koster
hvert ekstra badge 100 Robux. Disse fire blev oprettet 5. september 2026 uden
Robux-betaling. De uddeles serverside af
`ZyntraMonetization` på `ZyntraLevelCompleted`-signalet, altså i samme øjeblik
spilleren får sit gratis token for et clear.

| Intern nøgle i `Config.Badges` | Oprettet badge-navn | Badge ID | Uddeles når |
|---|---|---|---|
| `FirstClearLevel1` | Level 1 Cleared | `2788462628933614` | Spilleren slipper ud af Level 1 første gang |
| `FirstClearLevel2` | Level 2 Cleared | `349186155479685` | Spilleren slipper ud af Level 2 første gang |
| `FirstClearLevel3` | Level 3 Cleared | `457908347698355` | Spilleren slipper ud af Level 3 første gang |
| `CampaignComplete` | Stay Quiet | `2318404539475574` | Alle tre levels er clearet mindst én gang — ikke det samme som at cleare Level 3 |

Alle fire står Active i Dashboardet. Uploadklare 512×512 PNG-ikoner og
originaler ligger i [assets/badges](../assets/badges/README.md). Mall-badget
bruger `level-3-cleared-map-v2.png`, skabt ud fra screenshots af det faktiske
Level 3; den forkastede rulletrappe-version må ikke uploades.

De fire id'er er indsat og kontrolleret i både repo og Studio. Den åbne
Studio-version blev publiceret som **v1755** med ejerens udtrykkelige tilladelse.
Roblox BadgeService bekræftede alle fire navne og `IsEnabled=true`; alle fire
uploadede ikoner var synlige i Dashboardet ved den afsluttende kontrol. Ingen test
uddeler badges til ejerens konto. Repoets øvrige ventende ændringer blev ikke
skubbet til Studio; Config-manifestet bevarer den separate pending-status.

1. Gå til `Creations -> BACKROOMS: STAY QUIET [CO-OP HORROR] -> Badges`.
2. Klik `Create badge`, upload et ikon, indsæt navn og beskrivelse.
3. På badgets tile: `... -> Copy Asset ID`.
4. Indsæt id'et i `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` under
   `Badges` på den matchende nøgle.

```lua
Badges = {
	FirstClearLevel1 = 2788462628933614,
	FirstClearLevel2 = 349186155479685,
	FirstClearLevel3 = 457908347698355,
	CampaignComplete = 2318404539475574,
},
```

`0` betyder "ikke oprettet endnu" og slår uddelingen helt fra: der kaldes ikke
`BadgeService`, og der gemmes ingenting. Der må ikke gættes et id — et id, der
ikke hører til denne experience, bliver afvist ved hver uddeling. `AwardBadge`
returnerer `false` i stedet for at fejle i den slags tilfælde (badge slået fra,
badge hører til en anden place, throttling, spilleren er gået), så koden læser
returværdien og ikke kun pcall'ens: den skriver kun i `AwardedBadges`, når
badget faktisk blev uddelt, og ellers logger den `[Zyntra] AwardBadge failed`
og prøver igen ved næste clear.

Profilen husker selv, hvad den har uddelt (`AwardedBadges`), og hvilke levels
kontoen har clearet (`LevelsCleared`). `UserHasBadgeAsync` kaldes kun, når vores
egen optegnelse siger "ikke uddelt endnu", så konti, der clearede et level før
badges fandtes, ikke får en ny notifikation ved hvert clear.

## Trin 5: verificér den dynamiske prisvisning før live launch

LocalScriptet henter den aktuelle pris på klienten og falder kun tilbage til Config-prisen, hvis Roblox-opslaget fejler. Det er nødvendigt på grund af Managed Pricing og personaliserede priser.

Den relevante implementering i `ZyntraStore.LocalScript.lua` svarer til:

```lua
local infoType = kind == "Pass" and Enum.InfoType.GamePass or Enum.InfoType.Product
local ok, info = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, item.Id, infoType)
if ok and info and info.PriceInRobux then
	buy.Text = tostring(info.PriceInRobux) .. " R$"
end
```

Kald det fra klienten, så prisen er personaliseret til den konkrete spiller. Brug fallbackteksten fra Config, hvis opslaget fejler.

Efter ændringen kan op til fem testkonti få simulerede priser gennem:

`Monetization -> Passes/Developer Products -> ... -> Dynamic Price Check`.

## Trin 6: sikkerheds- og købstest

### Passes

Brug en testkonto, der ikke ejer passet:

1. Køb passet i en publiceret testserver.
2. Kontrollér, at fordelen aktiveres uden rejoin.
3. Rejoin og kontrollér, at fordelen stadig er aktiv.
4. Kontrollér, at Supporter-tokenpakken og Advanced-grants ikke gives igen.
5. Test en Supporter-only spiller og kontrollér, at hazmat color pickeren er låst. Test derefter en Advanced-only spiller og kontrollér, at den kan åbnes og gemmes.

Punkt 2 er det, der plejede at kunne fejle uden spor: `UserOwnsGamePassAsync` cacher pr. server og svarer ofte stadig `false` lige efter købet. Serveren låser derfor købet fast, når `PromptGamePassPurchaseFinished` melder `purchased = true`, og lader det vinde over enhver senere ejerskabslæsning i den session. Et ejerskabsopslag der kaster, prøves igen (0/1/3 s) og ender som "ved ikke" i stedet for "ejer ikke", så et udfald ved join ikke længere kan fjerne et pass resten af sessionen. Svarer Roblox stadig ikke, spørger serveren af sig selv igen i baggrunden — op til tre gange med 20 sekunders mellemrum — og holder op, så snart et opslag svarer. Det kan ikke overlades til "den næste handling, der kræver passet": butikken låser sin farvevælger på netop den attribut og sender derfor slet ikke handlingen, og Supporter-passet har ingen handling overhovedet.

### Developer Products

Test med et billigt testprodukt og en testkonto. Rigtige testkøb bruger rigtige Robux.

1. Køb 4-tokenproduktet.
2. Kontrollér præcis +4, rejoin og kontrollér persistens.
3. Køb igen og kontrollér endnu +4.
4. Gentag for 20-tokenproduktet.
5. Afbryd/rejoin omkring købet og kontrollér, at samme `PurchaseId` aldrig giver dobbelt grant.
6. Test receipt-flowet gennem lobby, reserved server og tilbage til lobby.

Developer Product-grants må kun gives gennem `ProcessReceipt`, aldrig gennem `PromptProductPurchaseFinished`. Zyntra bruger allerede den korrekte centrale callback, men en publiceret end-to-end-test er nødvendig.

Hvis Developer Products også skal sælges på Roblox' eksterne Store-tab:

1. `Monetization -> Developer Products -> ... -> External Purchase Settings`.
2. Aktivér test mode.
3. Tillad external purchases på ét billigt testprodukt.
4. Køb det på Store-tabben, join spillet og verificér grant.
5. Kontrollér, at receipt-status bliver `Closed`, før eksternt salg aktiveres bredt.

## Trin 7: launch-checkliste

- [ ] Ikoner uploadet til de produkter, der skal have egne billeder.
- [ ] Tre passes oprettet under Zyntra-experiencen.
- [x] Ni Developer Products oprettet under Zyntra-experiencen.
- [ ] Dashboard-priser og beskrivelser dobbelttjekket.
- [x] 12 Asset IDs indsat og verificeret i `ZyntraConfig`.
- [x] Dynamisk prisvisning implementeret.
- [ ] Dynamic Price Check bestået med testkonti.
- [ ] Supporter-token-grant testet som one-time.
- [ ] Advanced-grants testet som one-time.
- [ ] Token receipts testet for gentagne køb, rejoin og duplicate receipt.
- [ ] Top Donors-tavlen testet med donation-receipts, genstart og OrderedDataStore-fejl.
- [ ] DataStore testet i publiceret version.
- [x] Emergency Re-entry: reserve-før-respawn og auto-use efter godkendt receipt implementeret.
- [x] Emergency Re-entry: 15 sekunder valgt; Trello-testene bestået i Studio; eksisterende on-sale/29 R$ verificeret.
- [ ] Emergency Re-entry: rigtig betaling og DataStore-forløb testet i en publiceret server.
- [x] Fire badges oprettet på Creator Dashboard og deres asset-ids indsat i `Config.Badges`; publiceret i v1755.
- [ ] Purchase-/receipt-fejl logges til analytics eller telemetri.
- [ ] Shop-copy forklarer tydeligt, at hvert token giver +5% til ét valgt system.

## Subscription-beslutning

Brug ikke en subscription ved første launch. Roblox-subscriptions er månedlige og auto-fornyende, mens den implementerede Supporter-fordel er permanent. Roblox har ingen indbygget ugentlig tokenudbetaling.

En senere `Zyntra Research Membership` kan give mening, hvis I vil tilbyde en reel løbende fordel, eksempelvis 10 tokens pr. betalingsmåned og et aktivt medlemsbadge. En ugentlig udbetaling kræver jeres egen periodisering, DataStore-felter, offline catch-up og serverkontrol af aktiv status. Subscription-fordele skal fjernes eller deaktiveres, når abonnementet ikke længere er aktivt.

## Tilgængelighedskontakter (server-kontrakten)

Profilen bærer nu de fire tilgængelighedskontakter, klienten allerede læste, men som intet kunne sætte. Listen står ordnet i `ZyntraConfig.AccessibilitySettings`, og den liste er hele kontrakten: hver `Key` er både feltet i `profile.Settings`, navnet på den player-attribut klienten læser, og den eneste nøgle serveren accepterer.

| Key | Label | Default | Læses af |
|---|---|---|---|
| `ReduceCameraShake` | Reduce camera shake | `false` | EntityShakeController, Level 2 Pool Foam Client |
| `ReduceFlashing` | Reduce flashing lights | `false` | Level 2 Pool Foam Client, Level 3 Lighting Controller |
| `CaptionsEnabled` | Show captions | `true` | Level 2 Pool Foam Client |
| `DisableCaptions` | Hide captions (`Hidden = true`) | `false` | Level 2 Pool Foam Client |

Hver post har desuden en `Description`, som kun er UI-tekst; serveren bruger kun `Key` og `Default`.

- `CaptionsEnabled` og `DisableCaptions` er to halvdele af den samme gamle kontakt (`DisableCaptions ~= true and CaptionsEnabled ~= false`). Begge gemmes og publiceres, så eksisterende saves stadig virker, men en UI må kun vise den ene: spring hver post over, der er markeret `Hidden`. Derfor er `CaptionsEnabled` også den eneste med `Default = true` — en default må aldrig vendes om til det modsatte af det, læserne antager.
- Attributterne sættes uden præfiks (`ReduceCameraShake`, ikke `ZyntraReduceCameraShake`), fordi det er de navne, de eksisterende klientlæsere spørger om. De publiceres ved profil-load og ved hver ændring, og de ligger også i `publicProfile`-payloaden.
- Klienten skriver dem via `ZyntraAction` med `"SetAccessibility"` og payload `{ Key = <string>, Enabled = <boolean> }`. Serveren validerer nøglen mod listen, ignorerer en uændret værdi helt, sætter attributten med det samme (optimistisk UI) og samler selve DataStore-skrivningen: første ændring skrives straks, følgende ændringer inden for 6 sekunder foldes ind i én skrivning. Forlader spilleren serveren inde i det vindue, skrives de ventende værdier alligevel, før sessionen lukkes.

## Skrivebudget for DataStore

Roblox' budget er 60 + 10 × spillere skrivninger i minuttet, og vejledningen for én nøgle er én skrivning pr. 6 sekunder. Tre ting holder klient-drevne handlinger inden for det:

- Et afvist `ZyntraAction` (ingen tokens, en farve der allerede er gemt, en receipt der allerede er indløst) åbner ikke længere en skrivning: `mutate`/`mutateIdempotent` annullerer `UpdateAsync` ved at returnere `nil`, når transformen melder "ingen ændring".
- Handlinger der kan skrive (`UpgradeStamina`, `UpgradeBattery`, `SetHazmatColor`, `SetGlowstickColor`, `SetAccessibility`) har et vindue på 1 sekund; resten beholder de responsive 120 ms. Vinduet er pr. handling — og for tilgængelighed pr. kontakt — så to forskellige knapper trykket lige efter hinanden begge bliver til noget. Ét fælles tidsstempel ville gøre det andet tryk til en død knap i et helt sekund.
- `SetMuteDispatch` er stadig undtaget fra vinduet, men køen eskalerer sit gulv 0,75 → 2 → 6 sekunder ved skrivninger i træk og nulstiller efter 30 sekunders ro, så vedvarende spam koster ~1 skrivning pr. 6 sekunder på spillerens egen nøgle.

## Kodepunkter

- Produktkatalog, ID-felter og tilgængelighedslisten: `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`
- Persistence, pass-grants og receipts: `ServerScriptService/ZyntraMonetization.Script.lua`
- Shop, prompts og nuværende prisdisplay: `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua`
- Level-belønning og re-entry: `ServerScriptService/GameManager.Script.lua`
- Batteri-multiplier: `StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua`
- Stamina-multiplier: `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`

## Officielle Roblox-kilder

- [Passes](https://create.roblox.com/docs/production/monetization/passes)
- [Developer Products](https://create.roblox.com/docs/production/monetization/developer-products)
- [Subscriptions](https://create.roblox.com/docs/production/monetization/subscriptions)
- [Regional Pricing](https://create.roblox.com/docs/production/monetization/regional-pricing)
- [Roblox Plus](https://create.roblox.com/docs/production/monetization/roblox-plus)
- [Player data and purchasing systems](https://create.roblox.com/docs/cloud-services/data-stores/player-data-purchasing)
- [MarketplaceService](https://create.roblox.com/docs/reference/engine/classes/MarketplaceService)
- [Publish games and places](https://create.roblox.com/docs/production/publishing/publish-games-and-places)
- [Badges](https://create.roblox.com/docs/production/publishing/badges)
