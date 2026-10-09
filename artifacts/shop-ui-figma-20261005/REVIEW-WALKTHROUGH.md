# Zyntra Shop: gennemgang af de 4 layoutforslag (2026-10-05)

Figma-fil: <https://www.figma.com/design/7FXycGKH6OT6Lme6FV3VBc> (Pro, Full seat).
Alt er bygget som native Figma: komponenter fra Design System-siden, Zyntra Flat-variabler og -tekststile, og
klikbare prototyper med Proto State-variabler. Eksporterne ligger i `exports/` ved siden af denne fil; forsiden er
`exports/Cover.png`.

Roblox Studio er ikke rørt i denne runde, og der er ingen .lua-ændringer. Integrationen i spillet er et senere
og separat skridt. Kontrakten for den ligger i `INTEGRATION-CONTRACT.md`.

## Sådan åbner du prototyperne

1. Åbn filen og vælg en layoutside i venstre panel:
   - `L1 · Field Catalogue`
   - `L2 · Storefront Shelves`
   - `L3 · Terminal Split`
   - `L4 · Bento Home`
   - `Lobby & Flows` for de fælles demoer.
2. Tryk **Present** (play-knappen øverst til højre, eller Ctrl+Alt+Enter).
   - Vælg et flow i flow-listen i præsentationsvinduet. Det svarer til sidens *flow starting points*; tabellen nedenfor viser dem.
   - Du kan også vælge flowet på forhånd under fanen Prototype i højre panel.
3. Alle skærme er 1920x1080. Sæt visningen til "Fit" (Options > Fit), så hele terminalen er synlig.
4. Startstanden kommer fra kollektionen **Proto State** på Design System-siden:
   - 37 tokens.
   - Advanced Equipment er ejet.
   - Daily Reward kan hentes.
   - Hjulet har 1 gratis spin.
   - 0 Re-entry-kreditter.
   - Genstart flowet (R) for at begynde forfra. Ellers fortsætter variablerne fra, hvor du slap.
5. Lobby-demoerne har knapper nederst (`DemoControls_ignore`):
   - TOGGLE REWARDS DOT og TOGGLE WHEEL DOT slår prikkerne til og fra.
   - TOKENS 37 / 2 skifter saldoen, så du kan prøve "ikke nok tokens".

| Side | Flow starting points |
|---|---|
| L1 · Field Catalogue | L1 · Lobby, L1 · Shop, L1 · Upgrades, L1 · Skins, L1 · Donate, L1 · Colors, L1 · Wall card (Robux buy) |
| L2 · Storefront Shelves | L2 · Lobby, L2 · Shop, L2 · Upgrades, L2 · Skins |
| L3 · Terminal Split | L3 · Lobby, L3 · Shop, L3 · Upgrades, L3 · Skins |
| L4 · Bento Home | L4 · Lobby, L4 · Shop, L4 · Upgrades, L4 · Skins |
| Lobby & Flows | Lobby demo, Rewards & Wheel demo, Re-entry demo |

**Vigtigt: ingen af prototyperne er afspillet i Present mode.** MCP kan ikke klikke. Alle forbindelser er kun
tjekket i koden: ingen mål mangler, og ingen peger på en anden side. Tjek disse tre ting først, når du afspiller:

- Token-saldoen tæller ned i pillen. Det er udtrykket `tokensText = tokens + ''`.
- Timerne (AFTER_TIMEOUT) inde i komponentvarianterne skifter videre, fx Spinning til Result og Waiting til
  Re-entering.
- Toasts, der henter deres tekst fra variablen `toastText`, viser en tekst. Det gælder L4 · Toast · Success og
  L4 · Toast · Not enough tokens, som er tomme i den statiske eksport.

## Fælles for alle fire

Alle fire layouts deler disse dele:

- **Lobbyen** (Screen/Lobby HUD) med rail: SHOP, UPGRADES, REWARDS, WHEEL og MUSIC.
- **Token-pillen** med +.
- **Friend Boost-chippen** med INVITE FRIENDS.
- **Hologramvæggen.**
- **Væg-kortet** (World/Shop Wall Card) med en Robux-vej og en token-vej:
  - Robux-vejen (Advanced Equipment, R$ 149): BUY, så Waiting (en stand-in for Robloxs egen prompt) og derefter Success og Owned. Vælger man Cancel, får man Cancelled og ryger tilbage til kortet.
  - Token-vejen (Speed Potion, 3 tokens) tjekker `tokens >= 3`. Er der nok, trækkes 3 fra og man får Success. Ellers vises Not enough tokens.
- **Daily Rewards** (Modal/Daily Rewards):
  - CLAIM giver +1 token og skifter til Claimed.
  - Linket LUCKY WHEEL åbner hjulet.
- **Lucky Wheel** (Takeover/Lucky Wheel): SPIN, så Spinning (tryk på navet for at springe over), så Result med COLLECT +3 og til sidst Used today.

I hvert layout fører railens REWARDS og WHEEL til den rigtige tilstand via conditionals:

- REWARDS åbner Claimed, hvis `dailyClaimed` er sand.
- WHEEL åbner Used today, hvis `wheelSpinAvailable` er falsk.

Luk-knappen (X) i terminalen fører tilbage til layoutets Lobby.

Frames som "Lucky Wheel · Spinning" og "Lucky Wheel · Result" er tavler til gennemsyn. I prototypen kører hele
hjul-forløbet inde i én overlay, via komponentens interaktive varianter.

Retningen er den samme i alle fire layouts:

- Robux er altid amber og står som teksten "R$".
- Tokens er altid teal med det native token-chip.
- OWNED, EQUIPPED og ACTIVE vises med rail-teal kant.

Kunst og billeder:

- Alt kunst er de nye in-game-billeder: product-*, supply-*, rail-*, daily-*, wheel-disc og skin-sample-1..7.
- Ingen af de pensionerede 09-16-billeder er med.
- Shop-fanen bruger højst 13 af de 15 billeder, som Framewisp-gratisplanen tillader per frame.

## L1 · Field Catalogue

Side `33:2`, sektion `38:2`. Venstre kategori-rail, et bredt Expedition Pack-banner og et kortgitter med 4
kolonner. Review: **6 → 7,5**.

**Det kan du klikke på**

- **Lobby:**
  - Railen: SHOP, UPGRADES, REWARDS (conditional) og WHEEL (conditional).
  - MUSIC og INVITE FRIENDS viser en info-toast.
  - Token-pillens + fører til Shop.
  - Holo_AdvancedEquipment åbner Owned-kortet, når `ownAdvancedEquipment` er sand, og ellers BUY-kortet. Holo_SpeedPotion åbner token-kortet.
- **Terminalen:**
  - Alle fem faner kan klikkes.
  - RECORDS og SETTINGS (20 knapper) viser en info-toast.
  - Robux-køb: Waiting for Roblox, så Purchased.
  - Token-køb trækker fra 37 eller viser Not Enough Tokens.
- **Skins:** EQUIP skifter mellem Baseline Yellow og Pool Service.
- **Colors:**
  - 15 farveprøver opdaterer preview og hex-kode via `colorHazmat`/`colorHazmatHex` og `colorGlowstick`/`colorGlowstickHex`.
  - Glowstick-passets BUY går over Waiting til Colors · Unlocked.
- **Døde, med vilje:** aktiv fane og knapperne OWNED, EQUIPPED, LOCKED, WAITING og "n TO GO". Holo_Tokens20, Holo_ExpeditionPack og Holo_EntityDetector har intet kort endnu.

**Gennemgang (fra review)**

> Du starter i lobbyen. Rail-knapperne SHOP, UPGRADES, REWARDS, WHEEL og MUSIC kan klikkes, og det samme gælder væg-hologrammerne og Friend Boost-chippen. SHOP åbner Zyntra-terminalen med kategori-rail til venstre, et Expedition Pack-banner og et kortgitter med 4 kolonner.
>
> Alle fem faner kan klikkes. Et Robux-køb viser 'Waiting for Roblox' og ender som OWNED. Et token-køb trækker fra saldoen på 37 og viser 'Not enough tokens', når der ikke er nok.
>
> I SKINS skifter EQUIP nu mellem Baseline Yellow og Pool Service. I COLORS skifter preview og hex-kode, når du trykker på en farve. Daily Rewards kører CLAIM til CLAIMED, og Lucky Wheel kører SPIN til resultat og videre til 'brugt i dag'.
>
> RECORDS, SETTINGS, MUSIC og INVITE FRIENDS svarer nu med en kort info-toast i stedet for at være døde knapper.
>
> Stærkest: det ligner præcis spillets ikoner. Fladerne er mørke, teal er systemfarven, og de ravgule Robux-knapper er det tydeligste på skærmen.
>
> Svagest: kortene er smalle (ca. 118 pt på en telefon), så ikonerne virker små. Første kortrække lå lige på kanten af scroll-området; den sidste rettelse af det er endnu ikke set på et screenshot.

**Det mangler stadig**

- Shop-folden: den første PERMANENT PASSES-række er nu læsbar. Den skarpe eksport `L1-16-shop.png` viser dog, at prisknappernes underkant stadig skæres ca. 8 px af scroll-kanten.
- Earner- og Tokens-rækkerne under folden er ikke set i et screenshot. `EarnerStatus` og `GoUpgrades_button` blev gjort mindre, så tjek dem for klippet indhold.
- Benefit-teksterne i L1 er nu forkortet til 2 linjer og afviger derfor fra SHARED-SPEC. Ejeren skal vælge: skriv dem ind i den fælles spec, eller rul dem tilbage.
- RECORDS og SETTINGS står i terminalens header, men SHARED-SPEC udelader dem. Behold eller fjern.
- Colors: den valgte ring bliver på den oprindelige prøve efter et tryk.
- Colors: de 4 nye variabler mangler i `DESIGN-SYSTEM.json`.
- Framewisp: mange auto-layout-frames mangler `_list`.
- Framewisp: Expedition-banneret er en løsrevet frame, ikke en komponentvariant.
- Kortene er smalle, ca. 118 pt på en telefon, så ikonerne virker små. Det er layoutets indbyggede pris.

## L2 · Storefront Shelves

Side `42:2`, sektion `42:3`. Fem store topfaner, en Expedition Pack-hero med en stor amber R$ 69-knap og
vandrette hylder. Review: **7,3 → 8,4**.

**Det kan du klikke på**

- **Lobby:**
  - Railen og token-pillens + virker.
  - MUSIC og INVITE viser en info-toast.
  - Alle fem hologrammer kan klikkes: Advanced Equipment og Speed Potion åbner væg-kort, de tre andre åbner Shop.
- **Terminalen:**
  - Alle faner kan klikkes.
  - RECORDS og SETTINGS (22 knapper) viser en info-toast.
  - Token-pillens + på Shop-fanen scroller ned til TOKENS-hylden (SCROLL_TO).
  - Robux-køb: Waiting for Roblox, så efter 1,2 s Purchase complete.
- **Upgrades:** conditional token-køb. Bought giver Saved, mangel giver Not enough tokens. GET TOKENS fører til Shop.
- **Skins:**
  - EQUIP virker.
  - UNLOCK koster 25/75 tokens.
  - Clears needed vises for Blacksite Director.
  - Robux-dragter går over Waiting.
  - Signal Architect EQUIP sætter `equippedSkin`.
- **Colors:** Glowstick-pass BUY, så Waiting, så Colors · Unlocked. Farveprøverne skifter mellem Default og Selected via Swatch/Color-komponenten.
- **Donate:** alle 9 trin kan klikkes.

**Gennemgang (fra review)**

> Ejeren starter i lobbyen: venstre rail (SHOP, UPGRADES, REWARDS, WHEEL, MUSIC), et Friend Boost-chip med INVITE FRIENDS og en hologramvæg, hvor alle fem bokse nu kan klikkes.
>
> SHOP åbner terminalen med fem store topfaner. Øverst står en Expedition Pack-hero med en kæmpe ravgul R$ 69-knap. Under den ligger vandrette hylder: permanente passes med et kigge-kort, Token Earner-stigen 2x → 3x → 5x med opgraderingspriserne R$ 150/250 og Tokens & Supplies.
>
> Man kan købe med Robux (venter på Roblox og bekræftes), bruge tokens på Upgrades med "ikke nok tokens"-gren, låse op og udstyre skins, købe Glowstick-passet og vælge farver. Man kan også donere, hente daglige belønninger og dreje Lucky Wheel.
>
> Records- og Settings-ikonerne, plus-knappen på tokens (scroller til token-hylden) og alle farveprøver reagerer nu også.
>
> Stærkeste træk: prisknapperne er det højeste på skærmen. Robux er ravgul og tokens er teal, så de kan ikke forveksles, og OWNED/ACTIVE/EQUIPPED er tydelige.
>
> Svageste: Upgrades-fanen har ingen ikoner på Stamina, Battery og Entity Shield og ligner en indstillingsside. FIELD SUPPLIES ligger helt under folden.

**Det mangler stadig**

- Upgrades-kortene for Stamina, Battery og Entity Shield har ingen ikoner.
  - Der findes intet fladt ikon i 10-01-stilen.
  - daily-entity-shield er forbeholdt Daily Rewards og hjulet.
  - Det er en kunst-beslutning.
- Upgrades:
  - FIELD SUPPLIES ligger helt under folden, og dens hjælpelinje skæres af kanten.
  - Hjælpelinjen er stadig udviklerformuleringen "+5% PER LEVEL · LEVEL N COSTS N+1 TOKENS". L1 har rettet sin.
- Emergency Re-entry-kortet viser et statisk "1 STORED", men `reentryCredits` starter på 0.
- Shop · Purchased viser statisk 37 ved siden af "+10".
- Hylderne bruger en lokal "L2/Shelf Card" i stedet for Card/Product Horizontal. Hero-kortet er en løsrevet frame.
- Records- og Settings-toasts er stand-ins: i spillet åbner knapperne de gamle sider.
- Ejer-beslutning: hooks og hero-chips bruger Roboto Condensed Black 30, hvor guiden siger mono 30.

## L3 · Terminal Split

Side `8:2`, sektion `42:4297`. Produktliste til venstre og et stort detaljepanel til højre med én stor
købsknap. Review: **7 → 8**.

**Det kan du klikke på**

- **Lobby:**
  - Railen, token-pillens + og hologrammerne Advanced Equipment og Speed Potion.
  - MUSIC og INVITE viser en info-toast.
- **Terminalen:**
  - Alle faner kan klikkes.
  - RECORDS og SETTINGS (24 knapper) viser en info-toast.
  - Ejede rækker (Advanced Equipment, Token Earner 2x, Supporter efter køb) viser toasten "You already own this pass".
  - Robux-køb går over SET own* og Waiting, så Complete. Supporter går via Shop · Pending.
  - Token-køb er conditional.
- **Upgrades · Short:** NEED 2 MORE åbner Not Enough Tokens.
- **Skins:** preview-panelet har nu en EQUIP-knap i fuld bredde, der fører til Skins · Equipped.
- **Colors:** Pending og Unlocked via glowstick-passet.
- **Døde, med vilje:** rækker under et igangværende køb, EQUIPPED/LOCKED/DEV ONLY-dragter og den aktive fane.

**Gennemgang (fra review)**

> Ejeren starter i lobbyen: venstre rail (SHOP, UPGRADES, REWARDS, WHEEL, MUSIC), hologram-væggen med produktkort og Friend Boost-chippen. Alt kan klikkes, også MUSIC og INVITE, som nu viser en toast.
>
> Shoppen er en terminal med en liste til venstre og et stort detaljepanel til højre. Faner: UPGRADES, SHOP, SKINS, DONATE og COLORS. Prototypen kører hele vejen for Robux-køb (venter på Roblox, så købt), token-køb med saldo 37 (købt eller 'ikke nok tokens'), udrustning af skins, farver låst op via pass, Daily Rewards og Lucky Wheel.
>
> Det stærkeste er SHOP-fanen: amber R$-knapper, teal token-knapper, OWNED-tilstande der er lette at skelne, og Expedition Packs WHAT YOU GET med én stor KØB-knap. Skins har nu også en EQUIP-knap i preview-panelet.
>
> Det svageste er at et tryk på en række i SHOP køber med det samme i stedet for at vise varen i detaljepanelet. Kun Expedition Pack og Supporter har en detaljevisning. Upgrades, Donate og Colors bruger heller ikke split-idéen, og under Upgrades skjuler skærmkanten Field Supplies.

**Det mangler stadig**

- **Den største brist:** et tryk på en Shop-række køber med det samme i stedet for at vise varen i detaljepanelet.
  - Kun Expedition Pack og Supporter har en detaljevisning.
  - En rigtig L3-prototype kræver 9 "Shop · <produkt> selected"-frames, eller et detaljepanel bundet til variabler.
- Upgrades, Donate og Colors bruger ikke liste-og-detalje-idéen.
- Upgrades: FIELD SUPPLIES-hjælpelinjen skæres midt i linjen, og begge supply-kort ligger under folden.
- Blacksite Director-rækken viser ikke prisen på 300 tokens. Den kan ikke være i 370 px ved 30 px-gulvet. Ejeren vælger: en højere række, eller prisen i preview-panelet.
- Fanerne og deres ikonfelter er løsrevne frames, ikke Nav/Item-instanser.
- Token-pillens + uden for Shop lander øverst i Shop, ikke ved TOKENS & SUPPLIES.
- Farveprøver kan vise to ringe på én gang.
- Lucky Wheel: tjek efter Framewisp-importen, at den roterede Disc/Pointer ikke afhænger af clipping.

## L4 · Bento Home

Side `35:2`, sektion `35:3`. En mosaik af store, mellemstore og små fliser med en dock nederst. Review:
**6,5 → 8**.

**Det kan du klikke på**

- **Lobby:**
  - Railen og token-pillens +.
  - MUSIC og INVITE FRIENDS viser en info-toast.
  - Holo_AdvancedEquipment åbner væg-kortet. BUY sætter `ownAdvancedEquipment` og `toastText`, viser Toast · Waiting for Roblox og derefter Success.
- **Terminalen:**
  - Docken skifter mellem UPGRADES, SHOP, SKINS, DONATE og COLORS.
  - RECORDS og SETTINGS (22 knapper) viser en info-toast.
  - Robux-køb: Pending (Roblox-prompt) og derefter Purchased med toast og +10 på pillen.
- **Upgrades:** alle fem knapper trækker tokens via variabler, også i "Not enough tokens"-tilstanden (3 tokens).
- **Skins:** EQUIP virker, også på Signal Architect, som giver en toast.
- **Colors:** farveprøverne skifter mellem Default og Selected.
- **Døde, med vilje:** aktiv fane, OWNED/EQUIPPED/CLAIMED/TO GO/SPUN og den låste glowstick-SAVE.
- **Ikke wired:** de fire andre hologrammer, også Speed Potion.

**Gennemgang (fra review)**

> Ejeren starter i lobbyen. Railen (SHOP, UPGRADES, REWARDS, WHEEL, MUSIC) og hologram-væggen åbner Zyntra-terminalen, Daily Rewards og Lucky Wheel, og alle knapper i dem kan nu klikkes.
>
> I Shop ligger Expedition Pack som stor hero-flise med en stor amber "BUY · R$ 69". Ved siden af ligger Token Earner-panelet (2x OWNED, 3x og 5x med UPGRADE-priser) og små fliser til 20 tokens og Re-entry. Rul ned for passes, der nu også har en hook-linje.
>
> Køb kører hele vejen: Pending (Roblox-prompt), så Purchased med toast og +10 på token-pillen. Upgrades, Skins, Donate og Colors skifter fra docken i bunden. RECORDS og SETTINGS viser nu en info-toast i stedet for at være døde klik.
>
> Upgrades trækker tokens via variabler, og "Not enough tokens"-tilstanden svarer nu korrekt på alle fem knapper. Skins viser alle 7 dragter med de rigtige renders, og Suburb Survey siger nu "NEED 38 MORE". Blacksite viser prisen 300 tokens og 23/100 clears.
>
> Stærkeste træk: bento-hierarkiet er det tydeligste af de fire forslag. Robux i amber og tokens i teal kan ikke forveksles, og prisknappen er altid det mest larmende element.
>
> Svageste træk: Entity Shield-ikonet ligner en token-chip. Token Earner-tallene er små i forhold til referencen. Hero og Supporter-kortet er stadig løse frames i stedet for komponenter.

**Det mangler stadig**

- Entity Shield-ikonet ligner en token-chip og kan forveksles med valutaen. Det kræver et fladt product-entity-shield-ikon (kunst- eller ejer-beslutning).
- Token Earner-fliserne:
  - Tierkunsten er lille.
  - SAVE R$ 149 brydes over 2 linjer.
  - Meta-linjen WAS R$ 299/399 mangler.
- Medium-fliserne: OwnedBadge sidder med inset 0 og dækker ikonets hjørne.
- Baseline Yellow viser EQUIPPED to gange.
- Card_ExpeditionPack, Card_Supporter og SectionHeader er løsrevne frames.
- Reaktionerne sidder på *Slot-instanserne, ikke på *_button.
- "NEED 38 MORE" er statisk tekst.
- Toast · Success og Toast · Not enough tokens har ingen brødtekst i den statiske eksport. `ToastText_txt` er bundet til `toastText`, der som standard er tom. Tjek i Present mode, at hver vej, der åbner dem, sætter `toastText`.

## Fælles flows (side Lobby & Flows `38:451`)

Siden er nu delt i to sektioner. Placeringer, forbindelser og flow-starter er uændrede.

- `69:2` **Shared · Lobby HUD, wall card & toasts**: Screen/Lobby HUD, World/Shop Wall Card, Toast/Purchase og flowet **Lobby demo** med dets 8 væg-kort-overlays.
- `69:3` **Shared · Daily Rewards, Lucky Wheel, Re-entry**: komponentsættene Modal/Daily Rewards, Takeover/Lucky Wheel, Modal/Emergency Re-entry og Card/Party Down, plus flowene **Rewards & Wheel demo** og **Re-entry demo**.

**Lobby demo** (`41:80`)

- Advanced Equipment-hologrammet kører Robux-vejen: Robux-kort, Pending, så Buy (Success, Owned) eller Cancel (Cancelled, tilbage).
- Speed Potion-hologrammet køber med en rigtig conditional. Pillen tæller ned fra 37 med 3 ad gangen.

**Rewards & Wheel demo** (`46:6309`)

- CLAIM (5 MIN) sætter `dailyClaimed` og giver +1 token.
- LUCKY WHEEL åbner hjulet: SPIN, Spinning, Result, COLLECT +3 og Used today. Luk fører tilbage til Rewards, hvor hjul-linket nu er skjult.

**Re-entry demo** (`46:6850`)

1. Død med 1 kredit: USE CREDIT, så Re-entering.
2. Næste runde: PARTY DOWN uden kredit. BUY R$ 29 fører til Waiting for Roblox, så kreditten købt og brugt.
3. NO THANKS fører tilbage til start.

Data og bevidste valg (ejeren kan ændre dem):

- **Hjulet har seks lige store felter i config-rækkefølge:** Token1, Token3, Potion1, Potion2, Shield1, Skin5.
  - Odds: 40/20/20/5/10/5 %.
  - Skin-feltet siger "SKIN OR 3 TOKENS".
- **Milestones:** 5 min giver 1 token, 15 min 1 Speed Potion og 35 min 1 Entity Shield. Daily Research udbetales automatisk.
- **Re-entry:** R$ 29, 10 s usynlig, én gang per runde.
- **CREAM (Equip-fladen)** bruges til "tag det, der er dit": CLAIM og USE CREDIT. Amber er kun Robux.
- **Daily Rewards har en "LUCKY WHEEL · FREE SPIN READY"-række.** Den findes ikke i spillet i dag.
- **Hjul-takeoveren har et "PRIZES & ODDS"-panel og en token-pille.** Dagens takeover viser odds på felterne.
- **Proto State-variablen `rewardsClaimable` (spejl af NOT `dailyClaimed`)** mangler i `DESIGN-SYSTEM.json`. Alt, der sætter `dailyClaimed`, skal også sætte den.

## Framewisp-import (kort)

- Vælg én 1920x1080-frame, ikke en sektion, og konverter den.
- Disse tags bruges:
  - `_button`, `_close`, `_panel`, `_scroll`, `_list`, `_grid`, `_tabgroup`, `_tab:Name`, `_txt` og `_shadow`.
  - `_ignore` er kun mockup og springes over: `Backdrop_ignore`, `DemoControls_ignore` og `RobloxPrompt_ignore`.
- Billedbudget: Shop-fanen bruger 13 af gratisplanens 15 billeder per frame. Upgrades bruger 4-6, Skins 9-10, Daily 5, og hjulet 1.
- Kendte bage-risici, alle lave:
  - Hjulets Disc og Pointer er roterede frames. Roblox kan rotere native, men roterede GuiObjects clipper ikke deres børn.
  - Colors' HUE/SAT/VAL-spor bruger LINEAR-gradienter uden for vinduet. De er native, men bryder én-gradient-reglen.
- Løsrevne frames (hero-kort, nogle faner og SectionHeader-indpakninger) bliver importeret fint, men er ikke instanser. Se listerne under hvert layout.

## Ændringer i Figma i dette eksport-trin

- **Cover-siden** (`0:1`):
  - De gamle skeletsektioner 9:117 og 9:331 var allerede væk.
  - Ny forside-frame `Cover` (`69:12622`) i Zyntra Flat med titel, dato, de fire layouts med miniaturer, hvordan man åbner prototyperne, Framewisp-note og sideliste.
- **Lobby & Flows:** indholdet er lagt i de to sektioner `69:2` og `69:3`. Kun for overblik og eksport; intet er flyttet visuelt.
- **L4:** de fire info-toasts (Records, Settings, Lobby music, Invite friends: `60:2800/2806/2812/2818`) var 126 px høje og klippede deres tolinjers tekst. De er nu 164 px.
- **L1:** de tre info-toasts (Music Off, Invite Friends, Records & Settings: `61:3062/3072/3082`) lå uden for sektionen og viste alle den kopierede tekst "Tokens spent. Saved to your profile.". De ligger nu i sektion `38:2` og har deres egen tekst:
  - "Tap MUSIC again to turn it back on."
  - "+10% tokens per friend in your round."
  - "Unchanged pages, not in this design."

## Eksporter

Alle filer ligger i `exports/`.

**Sektions- og frame-billeder**

- **Opløsning:** hvert layout er fotograferet som én sektion (maks. 6000 px) og beskåret lokalt.
  - L1 er 0,36x, dvs. 682x384 per frame. `L1-16-shop.png` og `L1-21-skins.png` er taget separat i fuld 1920x1080.
  - L2 er 0,46x, L3 0,57x og L4 0,67x.
  - Shared er 0,59x og 0,49x. Design System er 0,46x.
- **De rettede toasts** (L1-32..34 og L4-24..27) er taget efter rettelsen i fuld størrelse.
- **`_section-L1.png` og `_section-L4.png`** er fra før rettelsen: L1-toasts mangler, og L4-toasts er klippede.

**Øvrige filer**

- `Cover.png`: forsiden i 1920x1080.
- `_overview-L1.jpg` .. `_overview-L4.jpg` og `_overview-shared.jpg`: kontaktark med frame-navne.
- `_section-*.png`: hele sektioner.
- `DS-00-board.png` og `DS-01..09-*.png`: Design System-tavlen og dens rækker (farver, typer, token, knapper, chrome, navigation, feedback, kort).
- Beskæringsskriptet ligger i `_local/shop-ui-figma/export/crop_exports.py` (rå skud i `_raw/`).

## Bilag: alle frames

### L1

| # | Frame | Node | Fil |
|---|---|---|---|
| 01 | L1 / Lobby | `49:13469` | `L1-01-lobby.png` |
| 02 | L1 / Daily Rewards | `49:13929` | `L1-02-daily-rewards.png` |
| 03 | L1 / Daily Rewards · Claimed | `49:14071` | `L1-03-daily-rewards-claimed.png` |
| 04 | L1 / Lucky Wheel | `49:14219` | `L1-04-lucky-wheel.png` |
| 05 | L1 / Lucky Wheel · Spinning | `49:14278` | `L1-05-lucky-wheel-spinning.png` |
| 06 | L1 / Lucky Wheel · Result | `49:14337` | `L1-06-lucky-wheel-result.png` |
| 07 | L1 / Lucky Wheel · Used today | `49:14396` | `L1-07-lucky-wheel-used-today.png` |
| 08 | L1 / Shop Wall Card | `49:13477` | `L1-08-shop-wall-card.png` |
| 09 | L1 / Shop Wall Card · Pending | `49:13479` | `L1-09-shop-wall-card-pending.png` |
| 10 | L1 / Shop Wall Card · Success | `49:13491` | `L1-10-shop-wall-card-success.png` |
| 11 | L1 / Shop Wall Card · Cancelled | `49:13494` | `L1-11-shop-wall-card-cancelled.png` |
| 12 | L1 / Shop Wall Card · Owned | `49:13497` | `L1-12-shop-wall-card-owned.png` |
| 13 | L1 / Shop Wall Card · Speed Potion | `49:13499` | `L1-13-shop-wall-card-speed-potion.png` |
| 14 | L1 / Shop Wall Card · Speed Potion Success | `49:13501` | `L1-14-shop-wall-card-speed-potion-success.png` |
| 15 | L1 / Shop Wall Card · Not Enough Tokens | `49:13504` | `L1-15-shop-wall-card-not-enough-tokens.png` |
| 16 | L1 / Shop | `38:7` | `L1-16-shop.png` |
| 17 | L1 / Shop · Pending | `39:338` | `L1-17-shop-pending.png` |
| 18 | L1 / Shop · Purchased | `39:738` | `L1-18-shop-purchased.png` |
| 19 | L1 / Upgrades | `42:1330` | `L1-19-upgrades.png` |
| 20 | L1 / Upgrades · Bought | `42:1911` | `L1-20-upgrades-bought.png` |
| 21 | L1 / Skins | `42:5682` | `L1-21-skins.png` |
| 22 | L1 / Skins · Equipped | `42:6320` | `L1-22-skins-equipped.png` |
| 23 | L1 / Donate | `44:5771` | `L1-23-donate.png` |
| 24 | L1 / Colors | `44:6398` | `L1-24-colors.png` |
| 25 | L1 / Colors · Unlocked | `44:6938` | `L1-25-colors-unlocked.png` |
| 26 | L1 / Toast · Waiting for Roblox | `46:1960` | `L1-26-toast-waiting-for-roblox.png` |
| 27 | L1 / Toast · Purchase Complete | `46:1966` | `L1-27-toast-purchase-complete.png` |
| 28 | L1 / Toast · Glowstick Pending | `46:1972` | `L1-28-toast-glowstick-pending.png` |
| 29 | L1 / Toast · Not Enough Tokens | `46:1978` | `L1-29-toast-not-enough-tokens.png` |
| 30 | L1 / Toast · Saved | `46:1984` | `L1-30-toast-saved.png` |
| 31 | L1 / Toast · Color Saved | `46:1990` | `L1-31-toast-color-saved.png` |
| 32 | L1 / Toast · Music Off | `61:3062` | `L1-32-toast-music-off.png` |
| 33 | L1 / Toast · Invite Friends | `61:3072` | `L1-33-toast-invite-friends.png` |
| 34 | L1 / Toast · Records & Settings | `61:3082` | `L1-34-toast-records-settings.png` |

### L2

| # | Frame | Node | Fil |
|---|---|---|---|
| 01 | L2 / Lobby | `50:5265` | `L2-01-lobby.png` |
| 02 | L2 / Daily Rewards | `50:5273` | `L2-02-daily-rewards.png` |
| 03 | L2 / Daily Rewards · Claimed | `50:5409` | `L2-03-daily-rewards-claimed.png` |
| 04 | L2 / Lucky Wheel | `50:5546` | `L2-04-lucky-wheel.png` |
| 05 | L2 / Lucky Wheel · Spinning | `50:5605` | `L2-05-lucky-wheel-spinning.png` |
| 06 | L2 / Lucky Wheel · Result | `50:5664` | `L2-06-lucky-wheel-result.png` |
| 07 | L2 / Lucky Wheel · Used today | `50:5723` | `L2-07-lucky-wheel-used-today.png` |
| 08 | L2 / Shop Wall Card | `50:5782` | `L2-08-shop-wall-card.png` |
| 09 | L2 / Shop Wall Card · Pending | `50:5784` | `L2-09-shop-wall-card-pending.png` |
| 10 | L2 / Shop Wall Card · Success | `50:5796` | `L2-10-shop-wall-card-success.png` |
| 11 | L2 / Shop Wall Card · Cancelled | `50:5799` | `L2-11-shop-wall-card-cancelled.png` |
| 12 | L2 / Shop Wall Card · Owned | `50:5802` | `L2-12-shop-wall-card-owned.png` |
| 13 | L2 / Shop Wall Card · Speed Potion | `50:5804` | `L2-13-shop-wall-card-speed-potion.png` |
| 14 | L2 / Shop Wall Card · Speed Potion Success | `50:5806` | `L2-14-shop-wall-card-speed-potion-success.png` |
| 15 | L2 / Shop Wall Card · Speed Potion Short | `50:5809` | `L2-15-shop-wall-card-speed-potion-short.png` |
| 16 | L2 / Shop | `42:35` | `L2-16-shop.png` |
| 17 | L2 / Shop · Pending | `42:2577` | `L2-17-shop-pending.png` |
| 18 | L2 / Shop · Purchased | `42:3007` | `L2-18-shop-purchased.png` |
| 19 | L2 / Upgrades | `44:960` | `L2-19-upgrades.png` |
| 20 | L2 / Upgrades · Bought | `44:1544` | `L2-20-upgrades-bought.png` |
| 21 | L2 / Upgrades · Short | `44:2099` | `L2-21-upgrades-short.png` |
| 22 | L2 / Skins | `45:6259` | `L2-22-skins.png` |
| 23 | L2 / Skins · Equipped | `45:6870` | `L2-23-skins-equipped.png` |
| 24 | L2 / Donate | `48:11032` | `L2-24-donate.png` |
| 25 | L2 / Colors | `46:10475` | `L2-25-colors.png` |
| 26 | L2 / Colors · Unlocked | `46:11046` | `L2-26-colors-unlocked.png` |
| 27 | L2 / Overlay · Waiting for Roblox | `48:11664` | `L2-27-overlay-waiting-for-roblox.png` |
| 28 | L2 / Overlay · Purchase complete | `48:11670` | `L2-28-overlay-purchase-complete.png` |
| 29 | L2 / Overlay · Not enough tokens | `48:11676` | `L2-29-overlay-not-enough-tokens.png` |
| 30 | L2 / Overlay · Saved | `48:11682` | `L2-30-overlay-saved.png` |
| 31 | L2 / Overlay · Glowstick waiting | `48:11688` | `L2-31-overlay-glowstick-waiting.png` |
| 32 | L2 / Overlay · Clears needed | `48:11694` | `L2-32-overlay-clears-needed.png` |
| 33 | L2 / Overlay · Records | `57:3247` | `L2-33-overlay-records.png` |
| 34 | L2 / Overlay · Settings | `57:3257` | `L2-34-overlay-settings.png` |
| 35 | L2 / Overlay · Music off | `57:3267` | `L2-35-overlay-music-off.png` |
| 36 | L2 / Overlay · Invite | `57:3277` | `L2-36-overlay-invite.png` |

### L3

| # | Frame | Node | Fil |
|---|---|---|---|
| 01 | L3 / Lobby | `50:1873` | `L3-01-lobby.png` |
| 02 | L3 / Daily Rewards | `50:2424` | `L3-02-daily-rewards.png` |
| 03 | L3 / Daily Rewards · Claimed | `50:2628` | `L3-03-daily-rewards-claimed.png` |
| 04 | L3 / Lucky Wheel | `50:2830` | `L3-04-lucky-wheel.png` |
| 05 | L3 / Lucky Wheel · Spinning | `50:2903` | `L3-05-lucky-wheel-spinning.png` |
| 06 | L3 / Lucky Wheel · Result | `50:2976` | `L3-06-lucky-wheel-result.png` |
| 07 | L3 / Lucky Wheel · Used today | `50:3049` | `L3-07-lucky-wheel-used-today.png` |
| 08 | L3 / Shop Wall Card | `50:1881` | `L3-08-shop-wall-card.png` |
| 09 | L3 / Shop Wall Card · Pending | `50:1883` | `L3-09-shop-wall-card-pending.png` |
| 10 | L3 / Shop Wall Card · Success | `50:1895` | `L3-10-shop-wall-card-success.png` |
| 11 | L3 / Shop Wall Card · Cancelled | `50:1898` | `L3-11-shop-wall-card-cancelled.png` |
| 12 | L3 / Shop Wall Card · Owned | `50:1901` | `L3-12-shop-wall-card-owned.png` |
| 13 | L3 / Wall Card · Speed Potion | `50:1903` | `L3-13-wall-card-speed-potion.png` |
| 14 | L3 / Wall Card · Speed Potion · Success | `50:1905` | `L3-14-wall-card-speed-potion-success.png` |
| 15 | L3 / Wall Card · Speed Potion · Not Enough Tokens | `50:1908` | `L3-15-wall-card-speed-potion-not-enough-tokens.png` |
| 16 | L3 / Shop | `8:3` | `L3-16-shop.png` |
| 17 | L3 / Shop · Pending | `42:4710` | `L3-17-shop-pending.png` |
| 18 | L3 / Shop · Purchased | `42:5202` | `L3-18-shop-purchased.png` |
| 19 | L3 / Upgrades | `45:953` | `L3-19-upgrades.png` |
| 20 | L3 / Upgrades · Bought | `45:1532` | `L3-20-upgrades-bought.png` |
| 21 | L3 / Upgrades · Short | `45:1757` | `L3-21-upgrades-short.png` |
| 22 | L3 / Skins | `46:7300` | `L3-22-skins.png` |
| 23 | L3 / Skins · Equipped | `46:7961` | `L3-23-skins-equipped.png` |
| 24 | L3 / Donate | `48:1752` | `L3-24-donate.png` |
| 25 | L3 / Colors | `48:2393` | `L3-25-colors.png` |
| 26 | L3 / Colors · Pending | `48:2934` | `L3-26-colors-pending.png` |
| 27 | L3 / Colors · Unlocked | `48:3160` | `L3-27-colors-unlocked.png` |
| 28 | L3 / Overlay · Waiting | `49:11848` | `L3-28-overlay-waiting.png` |
| 29 | L3 / Overlay · Complete | `49:11854` | `L3-29-overlay-complete.png` |
| 30 | L3 / Overlay · Not Enough Tokens | `49:11860` | `L3-30-overlay-not-enough-tokens.png` |
| 31 | L3 / Overlay · Records & Settings | `58:6430` | `L3-31-overlay-records-settings.png` |
| 32 | L3 / Overlay · Music Off | `58:6442` | `L3-32-overlay-music-off.png` |
| 33 | L3 / Overlay · Invite | `58:6454` | `L3-33-overlay-invite.png` |
| 34 | L3 / Overlay · Owned | `58:6466` | `L3-34-overlay-owned.png` |

### L4

| # | Frame | Node | Fil |
|---|---|---|---|
| 01 | L4 / Lobby | `52:1965` | `L4-01-lobby.png` |
| 02 | L4 / Shop Wall Card | `52:2115` | `L4-02-shop-wall-card.png` |
| 03 | L4 / Daily Rewards | `52:2164` | `L4-03-daily-rewards.png` |
| 04 | L4 / Daily Rewards · Claimed | `52:2367` | `L4-04-daily-rewards-claimed.png` |
| 05 | L4 / Lucky Wheel | `52:2568` | `L4-05-lucky-wheel.png` |
| 06 | L4 / Lucky Wheel · Spinning | `52:2641` | `L4-06-lucky-wheel-spinning.png` |
| 07 | L4 / Lucky Wheel · Result | `52:2714` | `L4-07-lucky-wheel-result.png` |
| 08 | L4 / Lucky Wheel · Used today | `52:2787` | `L4-08-lucky-wheel-used-today.png` |
| 09 | L4 / Shop | `44:2943` | `L4-09-shop.png` |
| 10 | L4 / Shop · Pending | `46:11679` | `L4-10-shop-pending.png` |
| 11 | L4 / Shop · Purchased | `46:12067` | `L4-11-shop-purchased.png` |
| 12 | L4 / Upgrades | `46:12520` | `L4-12-upgrades.png` |
| 13 | L4 / Upgrades · Bought | `46:13054` | `L4-13-upgrades-bought.png` |
| 14 | L4 / Upgrades · Not enough tokens | `46:13293` | `L4-14-upgrades-not-enough-tokens.png` |
| 15 | L4 / Skins | `48:11913` | `L4-15-skins.png` |
| 16 | L4 / Skins · Equipped | `48:12495` | `L4-16-skins-equipped.png` |
| 17 | L4 / Donate | `48:12797` | `L4-17-donate.png` |
| 18 | L4 / Colors | `49:7400` | `L4-18-colors.png` |
| 19 | L4 / Colors · Unlocked | `49:7912` | `L4-19-colors-unlocked.png` |
| 20 | L4 / Toast · Waiting for Roblox | `49:14489` | `L4-20-toast-waiting-for-roblox.png` |
| 21 | L4 / Toast · Success | `49:14495` | `L4-21-toast-success.png` |
| 22 | L4 / Toast · Not enough tokens | `49:14501` | `L4-22-toast-not-enough-tokens.png` |
| 23 | L4 / Toast · Glowstick pending | `49:14507` | `L4-23-toast-glowstick-pending.png` |
| 24 | L4 / Toast · Records | `60:2800` | `L4-24-toast-records.png` |
| 25 | L4 / Toast · Settings | `60:2806` | `L4-25-toast-settings.png` |
| 26 | L4 / Toast · Lobby music | `60:2812` | `L4-26-toast-lobby-music.png` |
| 27 | L4 / Toast · Invite friends | `60:2818` | `L4-27-toast-invite-friends.png` |

### Shared

| # | Skærm | Node | Fil |
|---|---|---|---|
| 01 | Screen/Lobby HUD | `38:453` | `Shared-01-screen-lobby-hud.png` |
| 02 | World/Shop Wall Card (set) | `39:1245` | `Shared-02-world-shop-wall-card-set.png` |
| 03 | Toast/Purchase (set) | `39:1270` | `Shared-03-toast-purchase-set.png` |
| 04 | Lobby demo | `41:80` | `Shared-04-lobby-demo.png` |
| 05 | Overlay · Wall card · Robux | `41:81` | `Shared-05-overlay-wall-card-robux.png` |
| 06 | Overlay · Wall card · Pending | `41:82` | `Shared-06-overlay-wall-card-pending.png` |
| 07 | Overlay · Wall card · Success | `41:83` | `Shared-07-overlay-wall-card-success.png` |
| 08 | Overlay · Wall card · Cancelled | `41:84` | `Shared-08-overlay-wall-card-cancelled.png` |
| 09 | Overlay · Wall card · Owned | `41:85` | `Shared-09-overlay-wall-card-owned.png` |
| 10 | Overlay · Speed Potion · Tokens | `41:86` | `Shared-10-overlay-speed-potion-tokens.png` |
| 11 | Overlay · Speed Potion · Success | `41:87` | `Shared-11-overlay-speed-potion-success.png` |
| 12 | Overlay · Speed Potion · Not enough tokens | `41:88` | `Shared-12-overlay-speed-potion-not-enough-tokens.png` |
| 13 | Modal/Daily Rewards (set) | `42:4209` | `Shared-13-modal-daily-rewards-set.png` |
| 14 | Takeover/Lucky Wheel (set) | `44:4167` | `Shared-14-takeover-lucky-wheel-set.png` |
| 15 | Modal/Emergency Re-entry (set) | `45:7652` | `Shared-15-modal-emergency-re-entry-set.png` |
| 16 | Card/Party Down (set) | `45:7783` | `Shared-16-card-party-down-set.png` |
| 17 | Demo · Rewards 1 · Claimable | `46:6309` | `Shared-17-demo-rewards-1-claimable.png` |
| 18 | Demo · Rewards 2 · Claimed | `46:6460` | `Shared-18-demo-rewards-2-claimed.png` |
| 19 | Demo · Wheel 1 · Ready | `46:6610` | `Shared-19-demo-wheel-1-ready.png` |
| 20 | Demo · Wheel 2 · Spinning | `46:6670` | `Shared-20-demo-wheel-2-spinning.png` |
| 21 | Demo · Wheel 3 · Result | `46:6730` | `Shared-21-demo-wheel-3-result.png` |
| 22 | Demo · Wheel 4 · Used today | `46:6790` | `Shared-22-demo-wheel-4-used-today.png` |
| 23 | Demo · Re-entry 1 · Death, 1 credit stored | `46:6850` | `Shared-23-demo-re-entry-1-death-1-credit-stored.png` |
| 24 | Demo · Re-entry 2 · Re-entering | `46:6895` | `Shared-24-demo-re-entry-2-re-entering.png` |
| 25 | Demo · Re-entry 3 · Next round, PARTY DOWN, no credit | `46:6940` | `Shared-25-demo-re-entry-3-next-round-party-down-no-credit.png` |
| 26 | Demo · Re-entry 4 · Waiting for Roblox | `46:6981` | `Shared-26-demo-re-entry-4-waiting-for-roblox.png` |
| 27 | Demo · Re-entry 5 · Credit bought and used | `46:7024` | `Shared-27-demo-re-entry-5-credit-bought-and-used.png` |
