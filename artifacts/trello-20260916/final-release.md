# Publiceret — Roblox v1920, 16. september 2026

**Pc'en bliver tændt.** Ejerens seneste besked erstatter alle tidligere nedlukningsinstrukser. Claude-opfølgningen er pauset, og dens tekst er rettet til dette.

## Udgivelse

- Place: **131311258779917**, universe **10559217407**.
- Version **1920**, publiceret **10:04 dansk tid / 08:04 UTC** med titlen *Daily rewards, expanded shop and Level 3 hiding*.
- Verificeret i Roblox Creator Dashboard: Version History med **Show published only** markeret viste 1920 som nyeste version. Dashboard viste også en tidligere publiceret v1919 fra 09:51; denne sessions afsluttende publicering er v1920.
- Fuld lokal backup: `G:\Roblox\MongoTV\_local\trello-20260916\BACKROOMS-published-v1920.rbxl`, **9.308.399 bytes**, gemt 10:07:52 dansk tid.
- Backup SHA-256: `840FBCD7C4808C5570D12CA5CB1D3C8DAE4078FD1EB67080482DDD542541DF69`.

## Leveret

- Spilletidsbelønninger: 5/15/35 aktive minutter giver henholdsvis 1 token, 1 Speed Potion og 1 Entity Shield. Fremgang/claims er serverstyrede; retries og dagskifte er dækket.
- Gratis dagligt Lucky Wheel med fem præmier: 1 token, 3 tokens, 1 potion, 2 potions og 1 shield. Synlige odds 45/20/20/5/10 %. Samlet Daily Rewards-fane.
- Speed Potion og Route Marker Pack med tokenkøb, inventory og anvendelse. Field Notes-samling med gemt fremgang.
- Større fysisk shop, supply-kiosk og forbedret shop-UI. Firkantet shopikon. Fem nye genererede teksturer uploadet og indlæst i spillet.
- Hold L i 1,5 sek. / hold mobilknappen for at vende tilbage til lobby; slip annullerer. Mobilens Objectives, Mission Brief og Leave placeres uden overlap. Level 1-instruktionerne er kontrolleret i en rigtig Studio-runde.
- Donationstavle med separate kolonner og uden historik-footer; Entity Shield-HUD følger Objectives-stilen.
- Level 3-gemmeanimation til spillets faktiske hazmat-character: gruppeejet asset **119040885264927**, Blenderfil, fire sekunders hold-loop og tilsvarende fallback. Ingen entry/exit-filmsekvens.
- Allerede eksisterende Studio-ændringer til donationstrin 5.000/10.000 og et engangs-gamepass på 20.000 Robux er bevaret. De tre produkt-id'er og priser blev verificeret med MarketplaceService; ingen køb blev foretaget.

## Kontrol og grænser

- **22 relevante offline-testsuiter bestået** efter de sidste kodeændringer. `codex-related-tests.json` indeholder resultaterne.
- **141/141 scripts kompilerer i Studio**. Slutaudit: **141 matcher, 0 drift**. Uafhængig parity: 140 eksakte matches plus én tilladt afsluttende linjeskiftforskel, ingen ekstra/manglende scripts.
- Native desktop- og iPhone-emulatortest: shop, teksturer, Rewards-spin, tokenkøb, potionens faktiske fart/udløb/én-pr-runde, markør, noteindsamling, Level 1-guide og faktisk lobbyretur. Mobil-input blev registreret som Touch; både kort afbrudt hold og fuldt hold blev prøvet. Se `native-feature-qa.md`.
- Native serverkontrol: Round Completion 398 checks uden fejl, Level 3-konfiguration/layout/navigation og Level 2-exitgeometri på to friske seeds. Animation: 253 samples uden rootdrift, positiv gulv-/bordafstand, begge indgange, død, exit og fallback.
- Den brede ældre UI-harness var **ikke fuldt grøn**: 2799 checks, 21 fejl før den sidste mobilrettelse. Terminaldelen var 1657/0. Fixture-/forventningsproblemer samt eksisterende detector-copy-overflow på 568×320 og en intermittent control-zone-forventning er dokumenteret i `native-ui-isolated.txt`. Den reelle mobiloverlapfejl blev derefter rettet og verificeret i en frisk runde. Der hævdes ikke en ny fuld grøn harness-kørsel.
- Studio bruger in-memory profiler. Testene beviser ikke live DataStore-rejoin, betalte køb eller rigtig cross-server-teleport. #16 og separat flerklient-QA blev sprunget over efter ejerens instruktion.

## Trello og afgrænsning

Kort **#74, #83, #84, #85, #88, #89, #100, #101 og #102** er flyttet til Done og markeret færdige med v1920-status. **#99** er opdateret med animation v2. Genlæsning af hele boardet bekræftede alle ti i Done, ingen aktive In Progress-kort og ingen nye opgaver ud over #102. `release-receipt.json` gemmer status og resterende kort.

Fortsat udsat/fravalgt: #16, controller/console, Discord, nye Level 2-lyde, 50 % udsalg, Ideas og Before big adsspend. Flashlight Casings og Results Frame er udeladt. Historiske køb blev importeret i v1906 og privat input fjernet før v1907; importen er ikke kørt igen. Gaven var allerede leveret.

Claude med Opus-kodeagenter udførte hoveddelen af kodearbejdet. Ved limit overtog Codex, afsluttede integration/rettelser, assets, QA og publicering. Claude er stoppet; opfølgningen forbliver pauset.
