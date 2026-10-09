# Alle køb på støttetavlen — readiness, 9. september 2026

[Trello gTgtoztS](https://trello.com/c/gTgtoztS) kræver, at alle køb bidrager til spillerens total sammen med direkte donationer. Kortet har ingen yderligere præcisering. Dette er læsning og implementeringsplan; ingen købskode, Studio-tilstand, produktpriser eller produktionsdata er ændret.

**Konklusion:** De tre utility-produkter kan tilføjes sikkert gennem den eksisterende receipt-transaktion. Historiske køb og passes kræver et pålideligt beløbsgrundlag. Der findes en konkret officiel salgseksport, som bør undersøges, før man erklærer historikken tabt eller erstatter faktiske beløb med katalogpriser. Den fulde opgave kan ikke erklæres løst alene ved at fjerne et `Kind == "Donation"`-filter.

## Nuværende kode og data

| Område | Verificeret i repo |
| --- | --- |
| Katalog | `ReplicatedStorage/ZyntraConfig.ModuleScript.lua`: 3 passes, 3 utility Developer Products og 6 donationsprodukter. `DataStoreName=ZyntraPlayerData_v1`; ranking-store `ZyntraDonationLeaderboard_v2`, top 10, periodisk refresh 90 sekunder. |
| Kvitteringer | `ServerScriptService/ZyntraMonetization.Script.lua:2194`: én `ProcessReceipt`, kendt server-side produktkatalog, spiller/profil-kontrol, `PurchaseId`-validering. `mutate` bruger profilens `UpdateAsync` og gemmer grant + permanent `ReceiptIds` i samme transaktion. Kun donationsgrenen læser og summerer `CurrencySpent`. |
| Donationer | Profilens `DonationRobux`, publicProfile og attributten `ZyntraDonationRobux` er donationsspecifikke. Alle utility receipts kvitteres allerede, men deres produkt-ID og betalte beløb bevares ikke i `ReceiptIds` — kun ID-strengen. |
| Ranking | `syncSupportTotal` bruger monoton `max(current,total)`, ikke `IncrementAsync`. Det er en afledt cache. `queueSupportTotalSync` samler højeste afventende total pr. bruger, har én worker og forsøg efter 0/1/3/8/20 sekunder; beskidte totals genforsøges ved periodisk refresh og ved næste profil-load. Fejl på ranking må ikke forhindre anerkendelse af et korrekt gemt køb. |
| Passes | `PromptGamePassPurchaseFinished:2160` lytter på serveren, matcher et konfigureret pass og kræver `purchased=true`. Det session-latcher ejerskab og kalder `refreshPasses`. `Grants.Supporter/AdvancedEquipment` beskytter engangsfordele, men er hverken købskvitteringer eller beløbsdata. Cosmetic har ingen tilsvarende grant-flag. Studio giver alle passes gratis. |
| Visning | `TunnelLobbyBuilder:440` og `ZyntraStore` viser TOP DONORS / DONATIONS og en personlig `DonationRobux`-total. Disse tekster og RankingScope skal følge den nye betydning, f.eks. TOP SUPPORTERS / RECORDED SUPPORT. Kun ti spillere kan vises på tavlen ad gangen; nye købere skal indgå i rangeringen og deres personlige total, også når de ikke er top 10. |

## Faktisk betalt pris og bevis for køb

Developer Products: anvend serverens `receiptInfo.CurrencySpent`, ikke `Config.Price`, en efterfølgende produktpris eller et beløb indsendt af klienten. Bevar PurchaseId-deduplikering på tværs af servere. `PromptProductPurchaseFinished` er ikke betalingsbevis. [Roblox' primære API-kilde](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/MarketplaceService.yaml).

Passes: den server-side afslutningshændelse kan bekræfte resultatet, men dens signatur indeholder **intet betalt beløb eller PurchaseId**. Ejerskab ved join beviser ikke købspris eller tidspunkt. Den nye `BindReceiptHandler` understøtter DeveloperProduct og RobuxTransferSender/Receiver, ikke GamePass. Ingen dokumenteret server-side pass-transaktionspris blev fundet. [API-kilde](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/MarketplaceService.yaml), [ReceiptType](https://create.roblox.com/docs/reference/engine/enums/ReceiptType).

Regional-/personlig pris hentes til UI i klientkontekst. En serverpris eller brugerens prisniveau er ikke en efterprøvet transaktionspris, og klientrapporter kan manipuleres. Brug derfor ikke disse til den autoritative R$-rangering. [Regional pricing](https://create.roblox.com/docs/production/monetization/regional-pricing). Gratis/promoveret pass-ejerskab må heller ikke tilføje en fiktiv betaling. [Passes](https://create.roblox.com/docs/production/monetization/passes).

## Historik: noget findes, men dækningen er ukendt

Git viser en reel tidligere stream: commit `3e961ea` (27/8 kl. 19:00 dansk tid) oprettede `SupportRobux` og `ZyntraDonationLeaderboard_v1`; alle tre utilities havde `CountsTowardSupportLeaderboard=true`, og beløbene kom fra receipt `CurrencySpent` i live. Commit `a686ef3` (27/8 kl. 20:05) skiftede til en separat donationsstream. **Git-tiderne er ikke bevis for publicering eller reelle transaktioner.**

Den nuværende normalizer ignorerer bevidst det gamle `SupportRobux`, men returnerer samme profil-tabel og sletter ikke ukendte felter. Gamle beløb kan derfor stadig findes i profiler og/eller v1-rankingen. De er ikke læst fra live DataStore i dette audit. Koden viser heller ingen registrering af pass-beløb. Der er ingen fundne salgs-CSV/XLSX-filer under `G:\Roblox` ved den afgrænsede filgennemgang.

Roblox dokumenterer månedlige salgs-CSV'er for op til to år med **Buyer User ID, Sale Date and Time, Sale Location, Universe ID, Asset ID/Type, Hold Status, Revenue og Price**. `Price` beskrives som køberens betalte beløb; `Revenue` er creatorens indtægt og må ikke bruges som erstatning. Gruppens Revenue → Sales → Sales of Goods → Download Data er den dokumenterede adgang; linket leveres til verificeret email, og eksporten opdateres hver 48. time. De faktiske tilgængelige filer/kolonner er ikke inspiceret endnu. [Sales data](https://create.roblox.com/docs/production/analytics/analytics-dashboard#sales-data).

## Mindste sikre implementering

1. **Afklar datadækningen først:** læs relevante live profiler/v1/v2 uden at skrive og undersøg gruppens faktiske juli–september-eksport. Filtrér på spillets universe `10559217407` og det kendte katalog; håndtér annullerede handler særskilt. Afklar om ordlyden omfatter private servere, som findes i dashboardet men ikke købes gennem spillets nuværende shopkode. Vis dokumenterede huller, ikke beregnede historiske priser.
2. **Udvid den eksisterende atomiske Developer Product-transaktion.** Bevar `DonationRobux` som separat donationshistorik; tilføj en særskilt total for faktisk betalte utility-køb. På et nyt PurchaseId øges præcis én beløbsstream og det købte grant i samme `UpdateAsync`. På replay øges intet. Valider finitte, ikke-negative heltal/sikre summer; nulbetaling må ikke opfindes som katalogprisen. Studio-testværdier holdes uden for live DataStore.
3. **Beregn samlet support fra adskilte, dokumenterede streams.** Brug den eksisterende ranking-cache og samlet personlig total. Bevar den gamle v2-store og donationsdata ved en eventuel v3-skift; migrering må ikke midlertidigt tømme alle fraværende donorers placering uden en gennemført backfill. Undgå unødvendig omdøbning af alle Instance-navne; ret de synlige tekster og scope-metadata.
4. **Passes får en særskilt, varig bekræftelsesstatus.** Server-hændelsen kan idempotent registrere det kendte userId/passId som køb bekræftet med beløb afventende. Gratis Studio-ejerskab og allerede ejet pass må ikke udløse betaling. Selve R$-beløbet skal tilføjes fra verificeret transaktionsdata, eksempelvis salgseksport, med varig deduplikering og dokumenteret afstemning. Pass-grants skal fortsat fungere, selv om rankingens beløb afventer. Et aktuelle-pris-estimat er kun en anden produktregel, hvis ejeren udtrykkeligt vælger det; det må ikke kaldes faktisk betalt.
5. **Importer historik som en særskilt, reviderbar migrering.** Lav først et lokalt dry-run med per-bruger før/efter og kildeafgrænsning. En eksport må ikke blindt lægges oven i `DonationRobux`/legacy SupportRobux — donationer kan allerede være med. Den dokumenterede CSV-liste lover ikke `PurchaseId`; undersøg faktisk schema og kræv enten et fælles stabilt transaktions-ID eller dokumenteret ikke-overlappende perioder/streams. Sent leverede receipts og flere gamle serverversioner kan krydse en datoafgrænsning. Markér tvetydigheder til afstemning i stedet for at bruge `max()` eller sammenlægning som et opdigtet dedupe-bevis.
6. **Bevar driftsegenskaberne.** Én profiltransaktion pr. receipt, samling af ranking-writes, ingen global sorteringsforespørgsel for hver UI-render. Coalesce også de nuværende umiddelbare leaderboard-refresh ved samtidige købsbursts, da de ellers kan udløse mange `GetSortedAsync`-kald. Profilens ReceiptIds vokser allerede permanent; mål serialiseret profil-størrelse og købshastighed før en større ledgerændring. Fjern ikke gamle IDs for at spare plads. Separate receipt-keys plus separat saldo-write er ikke automatisk atomisk og må ikke indføres som en hurtig genvej.

Roblox' dokumenterede DataStore-grænse er 4.194.304 tegn pr. key; `UpdateAsync` bruger read- og write-budget. Begrænsninger gælder både server og experience. Det taler for at genbruge den eksisterende transaktion og kø, måle vækst og undgå et nyt fuldt metadata-ledger i hver profil uden behov. [Data store limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits).

## Nødvendige checks og åbne oplysninger

- Samme receipt samtidigt på to servere; replay efter gemt commit med tabt svar; ranking-nedbrud efter korrekt grant; nyere total under ældre cache-write; rejoin-genopretning.
- Donation, Tokens4, Tokens20 og Re-entry med faktiske testbeløb forskellige fra katalogprisen; tokens, credits og eksisterende donationstotal må stadig stemme. Tokenforbrug/gratis dev-gaver må ikke tælles igen som Robux-køb.
- Pass-success/cancel/ukendt ID/allerede ejet/gratis Studio-pass; beløb må kun tilføjes efter verificeret kilde. Historiske pass-grants er ikke beløbsbevis.
- Import kørt to gange, overlap med live/legacy og forsinkede receipts, annullerede rækker, manglende eller tvetydig pris; ingen dobbelttælling og ingen tavse gæt.
- Faktisk beløbs- og dedupe-dækning i gruppeeksporten, eventuel v1/SupportRobux-historik, eksisterende receipt-volumen/profilstørrelse, og om alle historiske/passtransaktioner kan afstemmes. Disse er undersøgelsesopgaver; de er endnu ikke dokumenteret uopnåelige.

Den fremadrettede utility-udvidelse er konkret og kan implementeres selvstændigt. Kortet skal blive åbent, hvis passes eller den krævede historik stadig ikke bidrager korrekt; en delvis utility-release er ikke den fulde leverance.
