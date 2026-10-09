# Codex polish-review — 22. september 2026

Claude-handoffet er kontrolleret mod GitHub, et frisk Trello-snapshot og en lokal Studio-runde. Denne levering indeholder **review, art direction, billedreference og et nyt Claude-prompt**. Der er ikke ændret runtime-kode, native spilassets eller publiceret fra denne gennemgang. Alle implementeringer forbliver hos Claude.

## Aktuel baseline og nyere arbejde

- Lokal branch og origin: `claude/trello-20260921`, `7e45852bdfa83cabc590de586d29365d082e627b`, 43 commits oven på PR #3. [PR #4](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/4) er åben og draft; ingen CI-checks blev returneret ved opslaget.
- Frisk Studio-audit før og efter prøverunden: **167/167 scripts matcher repo, 0 drift**. Afsluttende separat læsning: **0 Source/editor-konflikter, 0 editor-læsefejl**. Studio efterladt i Edit, `SelectedLevel=1`, `EntityPaused=false`, uden et vedvarende `Level4DevEnabled`-flag fra testen.
- v1973 er dokumenteret af Claudes publiceringslog fra 21/9 kl. 22:47 UTC. Der findes nu også en **nyere kvittering for v1976**, 22/9 kl. 07:51:26 UTC, på detector-branchen. Det er den seneste publiceringskvittering fundet i dette review; ikke en påstand om en efterfølgende produktionstest.
- [Detector-PR #5](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/5), branch `codex/detector-polish-20260922`, commit `e9bf35c4fdb1b7c7a1911822952f9e49359c38dc`, indeholder også native backups, assetfil og verifikation. Dens tre runtime-filer har **ingen diff mod den aktuelle Claude-branch**; de er allerede mirroret gennem `d8edb14`. Undgå at genimplementere eller overskrive dem. PR'ens øvrige dokumentation/assets er ikke dermed automatisk flettet ind.
- v1976-kvitteringen dokumenterer detector-sessionens publicering. Den fastslår ikke alene, at den nuværende Level 4-prototype indgår i den publicerede place. Level 4 er stadig dev-only i den kontrollerede Studio-version.
- `game.PlaceVersion` i den åbne editor stod fortsat på 1958. Brug ikke denne sessionsværdi til at tilsidesætte nyere publiceringskvitteringer.

## Trello-delta

Boardet er læst igen inklusive arkiverede kort: **135 kort**, mod 131 den 21/9. Fire nye kort; ingen andre kort havde ændret `lastActivityAt` eller arkivstatus i sammenligningen. De nye korts checklists er forespurgt særskilt (ingen); Level 4's ti designpunkter er genlæst.

| Kort | Næste arbejde |
|---|---|
| [Rewards/Wheel-badges og kort introduktion efter første gennemførte level](https://trello.com/c/MsEn2mya) | Lille rød indikator ved noget, som faktisk kan hentes; kort, lukbar forklaring efter første succes. |
| [Tydelig indsamling af Wheel- og Daily-præmier](https://trello.com/c/25GLltY6) | Klar collect-handling og bekræftelse med det rigtige beløb. Serverens eksisterende grant-tidspunkt skal håndteres korrekt. |
| [50 % flere Level 1-fuse-relays for 1–3 spillere](https://trello.com/c/JYiwjBxw) | Flere indsamlingssteder; uændret antal nødvendige fuses, bokse og levers. |
| [Detector-polish](https://trello.com/c/bn2zeKKO) | Done; v1976, PR #5. Bevar arbejdet. |

Rådata: `artifacts/codex-polish-20260922/trello-board-snapshot.json` og `trello-refreshed-checklists.json`. Den tidligere komplette kortoversigt er fortsat grundlaget for de øvrige kort; den skal ikke præsenteres som et aktuelt 131-korts board.

## Bekræftede Level 4-fund

Prøve: lokal Studio Play, eksisterende `Level4DevStart`, seed **101**, variant **CLOSE**, planhash `4f3eec7f`. Ingen kildefiler ændret. Målingerne er diagnostik i den lokale runde; ikke en ny end-to-end-, multiplayer- eller mobiltest.

### 1. Tagene er vendt forkert

`ServerScriptService/Level 4 Systems/Level 4 World Builder.ModuleScript.lua`, `buildHouseShell`, omkring linje 339–348.

Native screenshots viser et tag med en dal i midten. Lodrette raycasts mod de to `HouseRoof`-dele i både `House_Intro` og `House_A1` bekræfter det:

| z-offset fra husets midte | Taghøjde over HouseFloor-center |
|---:|---:|
| −14 | 18,365 studs |
| −0,1 | 12,641 studs |
| +0,1 | 12,641 studs |
| +14 | 18,365 studs |

Midten er ca. 5,72 studs **lavere** end målepunkterne nær udhænget. Et almindeligt sadeltag skal have sin højeste ryg i midten. Ret wedge-orientering og den misvisende kildekommentar. Bevar tagets akse, husets footprint og passagekontrakter. Godkend med geometri og billede, ikke kun en assertions-test af de samme rotationskonstanter.

### 2. De fire normale facadevinduer er inde i væggen

Samme fil, `buildWindow` og `buildHouseShell`, omkring linje 278 og 351–357.

På `House_Intro` er facadevæggens z-interval **36,0–37,0**. De fire roterede vinduer har center z **36,6** og tykkelse 0,4, altså interval **36,4–36,8**. Hele ruden er indlejret i den opaque væg. Det samme blev målt på `House_A1`; screenshot viser den blanke facade.

Placér ruden synligt på facadens yderside med korrekt fortegn for begge `FacingZ`-retninger. Art-valget er en billig, synlig facadeflade med ramme og karm; der er ikke behov for at udhule alle vægge i denne første polishrunde. Normalt hus: fire vinduer. `ExtraWindow`: ét ekstra, som reelt kan sammenlignes med de normale.

Kontrollér også `buildAnomaly`: `WrongNumber` og `DrawnCurtains` bruger tynd x-dimension uden vinduets rotation; det er en kildebaseret mistanke om dårlig læsbarhed, ikke en særskilt gennemført runtime-test. Postkassen er en næsten symmetrisk klods; et låg/frontmarkør skal gøre 180°-vendingen synlig.

### 3. Den rolige start bliver til farelys uden spillerens progression

`StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller.LocalScript.lua`, `dangerNow`, linje ca. 135–140; house-scheduler i `Level 4 Objective Controller`.

Første opsamlede runtime-sample: `RoundActive=true`, **SIGNALS 0/3**, Neighbour **PATROL**, `Level4_UnsafeHouses=1`. Klienten var allerede på hele fareprofilen: **ClockTime 17,6, Brightness 1,9, FogStart 70, FogEnd 380**. Dette er ikke et løfte om et sample præcis ved sekund nul, men det reproducerer problemet før nogen undersøgelse eller jagt.

`dangerNow` behandler ethvert usikkert hus i hele kvarteret som global fare. Scheduleren starter sin deadline ved controller-start, før elevatorforløbet er færdigt. Ret dette som oplevelseslogik hos Claude: et faktisk roligt anløb, og en fareprofil, som kan vende tilbage til ro. Skjulte hændelser i et fjernt hus må ikke permanent farve hele himlen kold.

### 4. Husvarsler skal kunne bruges af spilleren

Screenshot fra servicepassagen viser `HOUSE B2 IS GOING DARK -- LEAVE WITHIN 12s`, selv om spilleren står udenfor alle huse. Adskil en relevant besked til en beboer fra information om et andet hus. Gør husets id genkendeligt i verden. Den farvede porch-lampe skal også kunne forstås på form/tekst og i reduceret flashing; den skal ikke være en stor grøn projektør på hele græsplænen.

## Konkret art direction

Ny reference: `artifacts/codex-polish-20260922/level4-facade-polish-target.png`. Den er en imagegen-paintover af det **faktiske** facade-screenshot, tydeligt mærket `DESIGN REFERENCE — NOT IN-GAME`.

- Én etage, korrekt mørkt sadeltag, diskrete sternbrædder/udhæng, creme/gul/blågrå puds. Fire synlige vinduer på normalfacaden; trim giver dybde uden mange nye draw calls.
- Åben dør med mindst **6 × 10,5 studs** fri passage. Bevar `DoorFrame`, `InteriorVolume`, collision, prompt-ankre og entityens ruter. Billedets proportioner er vejledende; de målte kontrakter bestemmer geometri.
- Genkendelig postkassefront, læsbare husnumre, diskret graphite-hus om porch-signalet. SAFE/WARNED/DANGEROUS skal bevare de samme gameplay-betydninger.
- Rolig varm eftermiddag og simple bakke-silhuetter bag uændrede grænsekollisioner. Billedets tætte græs/hække og baggrundsbevoksning er en illustration af farve og masse; de er **ikke** et krav om individuelle blade, græsstrå eller en skov.
- Genbrug stock-materialer, få fælles meshes/materialer og eksisterende tile-assets. Første facadepass behøver ingen nye rastertextures eller asset-ID'er. PNG'en skal ikke uploades som en hel hustekstur.
- Bevar grænsen på højst 12 dynamiske Level 4-lys og 0 shadow-casting dynamiske lys. Mål samlet omkostning efter ændringer; det eksisterende loft på 12.000 descendants er et loft, ikke et mål.

Den tekniske implementering af dette udseende ligger i den procedurale World Builder og skal derfor udføres af Claude. Der er ikke foretaget engangsændringer i et genereret Play-hus, som alligevel ville forsvinde ved næste runde.

## Andre rettelser og afgrænsninger

| Fund | Evidens og næste handling |
|---|---|
| Første Level 3-CD konkurrerer med bordets HIDE-prompt | Claude-handoff + kildeinspektion af `Level 3 Hiding Controller.refreshPrompt`: ingen CD-tilstandsafhængighed. Frisk runtime-reproduktion er ikke lavet her. Claude skal prioritere TAKE ved netop første CD-bord, genaktivere normal hiding efter pickup og validere på serveren. |
| Level 2-arch-mesh-forslaget kræver kollisionsopdeling | `makeArchSpan` slår kun collision fra, når `options.CanCollide == false`. Korridorribber og fritstående ringe sender ikke dette flag; `.face`-buer gør. **Alle ribber kan derfor ikke generelt erstattes af ikke-kolliderende pynt.** Bevar de kolliderende profiler og Vault Strip. 71k→26k descendants er en prognose, ikke målt gevinst. |
| Wheel belønner allerede ved SPIN | `ZyntraMonetization.spinDailyWheel` kalder `applyReward` inde i den atomiske mutation før klientanimationen. En ny COLLECT-knap må ikke give præmien igen. Et reelt collect-trin kræver en vedvarende pending/claimed-tilstand med idempotent server-claim og migration af allerede udbetalte resultater. |
| 50 % flere småhold-relays | `PuzzleManager.startPuzzle` fryser allerede aktive deltagere. Med standard-multiplier 2 er nuværende relay-mål for 1–6 spillere: **2,2,4,4,6,6**. Nyt mål: **3,3,6,4,6,6**. Bevar nødvendige fuses og puzzle-progression. Bekræft live konfiguration og faktisk antal placerede relays. |
| Token Earner-forslagets matematik er forkert | Med handoffets additive `floor(balance × (tier − previousTier))` giver 100 → 2x → 3x → 5x saldi **200 → 400 → 1.200**. Direkte 1x→5x giver **500**. En grant-ledger løser ikke dette. Ingen D3-implementering, før semantik/priser er besluttet; en ratiosats alene løser heller ikke alle rounding-/spend-scenarier. |
| Analytics join/profil-rækkefølge | Kildebaseret risiko: `ProfileLoaded` kan oprette sessionen på trin 2 før `GameManager.setupPlayer` kalder Join. `onboard` undertrykker lavere trin, så trin 1 ikke sendes særskilt i den rækkefølge. At produktions-DataStore typisk er langsommere er ikke en rækkefølgegaranti. Test begge rækkefølger, dobbelt kald og reserved-server-ankomst; skeln mellem log/ingestion/dashboard. |
| 78 UI-regressionsfejl | Handoffet siger udtrykkeligt, at de ikke er bevist forældede mod baseline. Uændrede filer beviser ikke, at fejlen er irrelevant. Gruppér unikke fejl, reproducer, og korrigér kun tests med dokumenteret kontraktændring. |
| Level 4 exit/retry og dokumentation | Handoffets 3,5-studs exit-pointer-afvigelse og manglende Level 4-retry-bay er åbne. Bevar dev-gaten. Contract-dokumentets starttekst om “nothing has been run” og “create these scripts” er historisk; geninstallér ikke eksisterende scripts. |
| Dødsskærm-evidens | `level4-death-neighbour-desktop.jpg` viser den generiske endskærm “NO ONE FOUND A WAY OUT”; det billede dokumenterer ikke alene Neighbour-dødsårsagskortet. Bevar eventbeviser og tag et egnet billede ved næste reelle kill-test. |

## Hvad denne runde ikke har verificeret

Ingen rigtig mobilhardware, nye testpersoner, multiplayer, ny A2-lyttetest, produktionsteleport, køb eller analytics-dashboard. Ingen nye påstande om disse checks. Claudes tidligere solo-/suite-beviser er fortsat historik, ikke genkørt fuldt her.

PoolSlides originale rig-/animationskilde er fortsat ikke til rådighed; der er ikke produceret eller uploadet erstatningsanimationer. C1–C3 og D1–D3 er fortsat separat backlog, bortset fra den dokumenterede delmængde af C3 i Level 4. Et facadepass gør ikke C4 færdigt eller klar til at blive åbnet for normale spillere.

Næste implementering: `docs/CLAUDE_POLISH_FOLLOWUP_2026-09-22.md`. Filen indeholder rækkefølge, konkrete kontrakter og beviser, Claude skal returnere.
