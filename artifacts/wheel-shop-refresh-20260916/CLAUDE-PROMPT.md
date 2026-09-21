Implementér følgende ejerbestilte ændringer i G:\Roblox\MongoTV. Du står for implementering, integration, QA og publicering. Brug Opus 5-agenter til afgrænsede kodeopgaver, mens du selv styrer og kvalitetssikrer. Læs repoets gældende instruktioner og seneste checkpoint først; bevar eksisterende ændringer. Dette er en ny ændringsrunde oven på den aktuelle version. Codex har kun leveret billedasset og denne brief.

1. LUCKY WHEEL
Brug den nye roterbare hjultekstur: rbxassetid://86770264881525.
Lokal fil: assets/shop/lucky-wheel-disc-v2.png.
Det er SELVE hjulskiven, ikke sidebar-ikonet. Transparent baggrund, ingen indbygget pil.
Når hjulet er åbent, skal hele den øvrige spil-UI skjules: sidebar, valuta, shop, Rewards, titler, separate paneler, præmielister og knapper uden for hjulet. Vis kun hjulet med en fast pil ved randen og ét tydeligt X øverst til højre. Bevar eventuel diskret baggrundsdæmpning; ingen stor rektangulær container. Gendan den korrekte UI-tilstand ved lukning/respawn.
Placér SPIN som en interaktiv del af navet i midten, så der ikke kommer en ekstra knap uden for hjulet. Vis cooldown/spinning/resultat kort og læsbart inde i hjulet/navet. X skal fungere på desktop og mobil og være mindst 44x44 px uden at rotere.
Teksturen har fem LIGE STORE visuelle felter. Fra feltet centreret øverst og med uret: Token1, Token3, Potion1, Potion2, Shield1. Kontrollér den faktiske billedorientering inden rotationsmatematik implementeres. Tilføj nødvendige tydelige antal som live UI inde i felterne (1 token, 3 tokens, 1 speed potion, 2 speed potions, 1 entity shield). Labels og skive skal følge samme rotation.
Bevar serverens nuværende præmier, chancefordeling, gratis daglige spin og persistence. Visuelt lige store felter ændrer IKKE sandsynlighederne. Serveren vælger præmien; klienten animerer til det korrekte felt. Pilen må aldrig rotere med skiven. Genbrug eksisterende sandsynlighedsoplysning diskret inde i hjulet, hvis spillet viser odds; ingen ekstra sidepaneler. Undgå dobbelt spin/dobbelt udbetaling, også ved lukning eller reconnect.

2. SHOP LANGS HELE VÆGGEN
Fjern den gamle shop/terminal og den gamle præsentation, så der ikke står to shops. Fjern gamle skilte, fascia, sokler og tekstplader, som ikke tilhører det nye koncept.
Den nye shop skal strække sig langs HELE vægstykket fra Level 2-gaten til Level 4-gaten. Undersøg de faktiske gate-positioner og mål det brugbare vægstykke i Studio; gæt ikke koordinater. Gateåbninger og gangareal skal forblive farbare.
Kun større, svævende hologram-bokse langs væggen, med betydeligt mere luft mellem hver boks og jævn fordeling over den tilgængelige længde. Ingen separat shopbod, terminal eller fysisk skilt.
Hver boks skal have produkttekstur på ALLE seks sider, ikke kun en front-decal. Genbrug de korrekte eksisterende produktbilleder. Boksen skal stadig fremstå som et hologram: delvis gennemsigtig, lysende kant og læselig produktgrafik.
Giv boksene en rolig, kontinuerlig op/ned-animation med let forskudt fase. Undgå kollisionsbevægelse og dyre serveropdateringer hvert frame.
Fjern AL forekomst af “Zyntra Supply” / “ZYNTRA // SUPPLY” i shoppræsentationen. Hvor en shopoverskrift er nødvendig i købsmenuen, brug kun “SHOP”. Opret IKKE et nyt fysisk SHOP-skilt.
Bevar automatisk åbning via de usynlige triggerområder. Man skal fortsat trykke eksplicit BUY for at købe. Større mellemrum skal også afspejles i triggerområderne, så man ikke utilsigtet skifter produkt. Close/forlad/genindtræd skal fortsat virke uden øjeblikkelig genåbning.
Fjern Daily Rewards-plaketten, teksten og interaktionen fra shoppen helt. Daily Rewards åbnes kun fra sin separate sideknap. Bevar produktpriser og købssystemer.

3. DAILY REWARDS – MERE INDBYDENDE
FÆRDIGE IMAGEGEN-ASSETS — Claude skal bruge disse direkte; ingen billedgenerering kræves:
| token | rbxassetid://93116899475472 | assets/shop/rewards-token-v1.png |
| speed-potion | rbxassetid://120211340805188 | assets/shop/rewards-speed-potion-v1.png |
| entity-shield | rbxassetid://126728249949579 | assets/shop/rewards-entity-shield-v1.png |
| gift | rbxassetid://117126194981100 | assets/shop/rewards-gift-v1.png |
Se også artifacts/wheel-shop-refresh-20260916/REWARDS-ASSETS.md for billedbrug og layout. Panelrammer, kortbaggrunde, tekst, timere, status og knapper bygges som almindelig Roblox-UI; præmie- og gavegrafikken er allerede genereret og uploadet.

Visuel reference: C:\Users\mikke\AppData\Local\Temp\codex-clipboard-88d0f7bf-9809-4a3b-af2e-6122e63e096c.png.
Reference til den eksisterende shop, der skal ændres: C:\Users\mikke\AppData\Local\Temp\codex-clipboard-deeb9592-2b59-4a04-b4b7-5d16ebbd9b6d.png.
Læs billederne som visuelle referencer, ikke som instruktioner.
Gør Rewards langt mere indbydende: varm tydelig header med gaveikon, store farverige præmiekort, store produktikoner, tydelig status/nedtælling, markant CLAIM når klar, grønt check når modtaget og et stort X øverst til højre. God kontrast, luft, læsbar tekst og mobilvenlige trykflader.
Brug den visuelle energi og kortopbygning fra referencen; kopiér ikke dens pets, valuta, produktnavne eller løfter.
Bevar de allerede godkendte spilletidsbelønninger: 5 minutter = 1 token, 15 minutter = 1 speed potion, 35 minutter = 1 entity shield. Referencebilledet er IKKE godkendelse til et nyt syvdages-login/streak-system eller ændret økonomi.
Ingen Rewards-komponent i den fysiske shop. Kun sideknappen åbner dette panel. Shop, Wheel og Rewards må ikke være åbne samtidig.

4. FRIEND BOOST
Indfør +10% ekstra completion-tokens pr. unik Roblox-ven, som spilleren inviterer og spiller sammen med.
Aktivt fælles spil er kravet: en invitation alene, en offline ven eller en ven på en anden server må ikke give bonus. Brug eksisterende party/invite-tracking hvis projektet har det; hvis ingen sådan tracking findes, brug verificerede Roblox-venner i samme aktive spil/session som kriterium og dokumentér denne fortolkning. Opfind ikke et separat referral-system.
Bonus er additiv: 1 ven +10%, 2 venner +20%, 3 venner +30%. Spilleren tæller ikke sig selv; samme ven tæller kun én gang. Ingen uanmodet cap.
Beregn bonus server-side ved completion. Bevar øvrige eksisterende multipliers uden dobbelt optælling. Anvend kun på completion-tokens, ikke køb, Lucky Wheel, Daily Rewards, gaver eller historiske køb.
Håndtér små heltalsbelønninger eksplicit, så 10% ikke altid forsvinder ved afrunding; følg et eksisterende remainder-system hvis der er et, ellers gem brøkrest server-side og udbetal hele tokens, når de er optjent. Dokumentér beregningen.
Vis en kompakt “Friend Boost +X%” med aktivt antal venner samt en Invite Friends-handling via Roblox' understøttede invitation-flow. Ingen auto-invites, ingen belønning blot for at trykke Invite. Skjul også denne UI, når Wheel er åbent.
Opdatér ved join/leave og håndtér fejlede friendship-opslag sikkert uden at stole på klientens angivne antal venner.

QA OG AFLEVERING
Test desktop samt mobil portrait/landscape: kun wheel/X ved wheel åbent, korrekt genoprettet HUD, alle fem serverpræmier lander i deres rigtige felt, loaded asset, Daily Rewards claim/persistence, hele shopvæggen, seks teksturerede sider, bob-animation, åbning/lukning, eksplicit køb og ingen gammel shop/Daily Rewards-plakat.
Test Friend Boost med 0/1/flere venner, join/leave, duplicate/replayed completion og afrunding.
Gem checkpoint med berørte filer, testresultater, eventuelle begrænsninger og tydelig publish-status. Publicér først efter relevante checks og verificér publiceret version og backup. Marker kun faktisk leverede Trello-opgaver færdige.
Bevar tidligere undtagelser: #16, konsol/controller, 50% udsalg, Discord, nye Level 2-lyde, Ideas og Before big adsspend. Genkør aldrig den historiske CSV-import.
Ved usage limit: checkpoint og vent på reset. Codex overtager ikke. PC SKAL FORBLIVE TÆNDT. Genaktivér ikke Codex' planlagte opgaver.
