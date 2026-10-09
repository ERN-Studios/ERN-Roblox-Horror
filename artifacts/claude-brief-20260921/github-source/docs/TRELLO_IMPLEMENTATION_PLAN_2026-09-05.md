# Plan for de tre åbne Trello-opgaver — 5. september 2026

Status: kode implementeret og integreret i Studio. 13 scripts er ændret/tilføjet, herunder de nye `Round Loading Runtime`, `Round Loading Test Suite` og `Round Entry Client`. Den afsluttende compile-kontrol består for alle 104 scripts; repo/Studio-audit viser 0 drift. Loading og controller står i **Testing**; lydkortet står i **In Progress**, indtil de tre faktiske lyde er leveret. Ændringerne er ikke publiceret.

**Aktuel implementerings- og teststatus**

- Fælles loading-flow, klientens readiness-kvittering, controllerrettelser og Pool Foam-lydinfrastruktur er implementeret. De endelige tre Pool Foam-lyd-ID'er mangler stadig; ingen færdig lydoplevelse er leveret.
- Direkte start gennem køen til Level 1, 2 og 3 samt den lokale Level 2→3-rørovergang via sejr/Continue er prøvet i Studio. Rørtesten fandt en for kort gulv-ray, som nu er rettet og genprøvet. Tastaturets H-panel åbner/lukker. Det er ikke en fysisk controllertest eller bevis for netværksteleport mellem publicerede servere.
- Tvungen manglende klient-readiness gav timeout ved deadline+0,24s, ingen rundestart, synlig fejl og lobbykarakter. Et nyt Level 2-forsøg i samme session bestod. Destination-disconnect-rettelsen er integreret og dækket af runtime- og host-tests. Detaljer: [valideringsrapport](TRELLO_IMPLEMENTATION_VALIDATION_2026-09-05.md).

| Kontrol | Bestået hidtil |
|---|---:|
| Round Completion-regression | 398 |
| Round Loading | 51 |
| Faktiske GameManager-hostblokke, offline | 83 |
| Controller-input, offline | 120 |
| Pool Foam-audio, offline | 24 |
| Hele Round Entry Client-scriptet, offline | 57 |

De afgrænsede offline-tests bruger den faktiske produktionslogik med kontrollerede engine-grænser. De beviser ikke fysisk input, hørbart lydmix, publiceret teleport eller MemoryStore-adfærd. Den gennemførte Studio-timeouttest er registreret særskilt ovenfor; en virkelig disconnect mellem publicerede servere mangler.

Resterende validering og afhængigheder: test fysisk controller og publicerede sessioner med flere klienter, herunder continuation/røret, langsom streaming, MemoryStore/admission, disconnects og teleport. Modtag de tre licenserede lydfiler/ID'er, integrer dem og verificér lydadgang og mix. Lydprøver kan muligvis laves af ejerens ven i ElevenLabs. Kortene skal forblive åbne, indtil deres respektive acceptkriterier er dokumenteret.

Board: [BACKROOMS: STAY QUIET – Development](https://trello.com/b/6FHYrsMR/backrooms-stay-quiet-development).

**Grundlag ved researchstart — historisk baseline**

Dette afsnit og kodehenvisningerne i den oprindelige analyse nedenfor beskriver tilstanden før implementeringen. Linjetallene er baseline-henvisninger og kan have flyttet sig. Den aktuelle status står ovenfor; historiske fejlbeskrivelser er ikke en påstand om, at de samme fejl stadig findes i den integrerede kode.

- Ved researchstart: præcis tre kort i To Do; In Progress og Testing var tomme.
- Gennemgået den aktuelle kildekode, CLAUDE.md, HANDOVER-2026-09-05.md og den oprindelige audit.
- Kodegrundlag: commit `c5ffa2dcfd628f7cd92fb1d2de72225fc44643a3`.
- Read-only Studio-audit: 101 scripts sammenlignet, 101 matcher, 0 manglende/afvigende. To tilladte ekstra slutlinjer i uvedkommende scripts er registreret i manifestet.
- Graphify-grafen er fra `e3904931`, og GameManager er delvist indekseret. Grafen blev derfor kun brugt til at finde rundt; konklusionerne er kontrolleret mod scripts.
- Live metadata: place `131311258779917`, universe `10559217407`, ejergruppe `1039373905`, StreamingEnabled=true. Studio-sessionens PlaceVersion er ikke brugt som bevis på seneste publicerede version.
- Ved researchstart var ingen playtests kørt som del af opgaven. Handoverens 398 beståede Round Completion-checks var dengang en tidligere baseline; nye delresultater fra implementeringen registreres særskilt i statusafsnittet ovenfor.

**Accepteret plan, rækkefølge og ansvar**

Planen nedenfor bevares som grundlag for implementeringen og den resterende accepttest. Trin 2A/2B og lydinfrastrukturen i 2C er nu implementeret; integration og validering er fortsat i gang. Produktion/valg af de endelige lyde og den publicerede test mangler.

| Trin | Arbejde | Færdigt når |
|---|---|---|
| 1 | Produktvalg | Besluttet: alle skal være klar før start; fælles 60 s frist; tre aktive lyde; mulig ElevenLabs-produktion hos en ven |
| 2A | Codex retter loading/admission med målrettede fejltests | Alle forventede tilsluttede spillere er klar før start; fælles 60 s frist afbryder og sender hele holdet hjem; sene callbacks kan ikke genåbne en afbrudt start |
| 2B | Controllerrettelser laves sideløbende i separate filer | Input, fokus, hints og sprint virker gennem de beskrevne scenarier |
| 2C | Lydprøver produceres/udvælges; kode til afspilning kan forberedes med tomme ID'er | Lydkarakter valgt, og brugbare filer/IDs findes |
| 3 | Saml ændringer, gennemgå loading-fixet uafhængigt, integrer lyde | Compile, relevante regressionstests og Studio-spiltest passerer |
| 4 | Publiceret test med flere Roblox-klienter | Teleport, lydadgang, streaming og controlleroplevelse verificeret |
| 5 | Udgivelse og Trello-afslutning efter samlet gennemgang | Godkendt build publiceret; hvert kort har faktisk testbevis |

Controller er en lille rettelse. Loading er en mellemstor rettelse af startforløbet. Lydarbejdet afhænger især af kvaliteten af prøverne, brugerens valg og Roblox-moderation. Et præcist samlet tidsestimat før de valg ville være misvisende.

Én session ejer Studio-skrivninger og integration. Parallelle kodearbejdere får særskilt filansvar eller worktrees. Både loading og controller berører RoundUI: én integrator ejer ændringerne dér, og de landes i rækkefølge. Lydproduktion, controllerens øvrige filer og uafhængig review kan fortsætte parallelt. Ingen bred pull over pending ændringer; audit før push. Brug projektets UpdateSourceAsync- og manifestflow.

**1. Loading og robusthed**

[Trello-kort](https://trello.com/c/DIktjy8U).

Aktuel status: den fælles runtime, klientkvittering og serverintegration er implementeret i Studio. Timeout-test og disconnect-review er endnu ikke afsluttet. Følgende fejlfund og linjetal er den oprindelige baseline; planens scenarier er stadig acceptkriterier.

Kortets foreslåede hurtige rettelse er utilstrækkelig. I GameManager venter `loadGameplayCharacter` først på en global lås og derefter på `LoadCharacterAsync`. De seks sekunders polling kommer bagefter. Fire forsøg er derfor ikke en reel 24-sekunders grænse. Et fejlet load kan også efterlade en gammel Character, som fejlagtigt tæller som succes. Se GameManager:369–457.

De tre entry-loops er ved GameManager:1950, :2410 og :2746. Fejl ved karakter eller placering håndteres ikke samlet. Et simpelt `spectating`-signal starter ikke tilskuerkameraet: RoundUI:4053 skjuler kun overlayet og viser ventetekst, mens SpectateController starter via død/escape. Den oprindelige påstand om sort skærm hele runden er for kategorisk; det sikre fund er spillere uden korrekt karakter/tilskuerforløb, og at et hængende engine-kald kan blokere gruppen.

Ejerens valgte adfærd: Runden starter først, når alle forventede, stadig tilsluttede spillere er helt indlæst. Hvis det ikke lykkes inden én fælles frist på 60 sekunder, afbrydes holdets start, alle får en tydelig fejl og sendes tilbage til lobbyen. Det er 60 sekunder for holdets loading-forløb, ikke 60 sekunder per spiller eller retry. En ubesvaret engine-operation må ikke udskyde fejlen. Det tæller ikke som nederlag og kræver ikke Emergency Re-entry.

Planens startpunkt for fristen er destinationsserverens begyndelse på holdets loading-forløb, så admission, world build, karakterindlæsning og klient-readiness deler samme budget. Almindelig køtid før afgang er udenfor. Den frosne continuation-cohort og dens transportaftale skal bevares; en tidlig ankomst må ikke få lov at starte alene. "Helt indlæst" kræver også klientens relevante verden/gulv klar, ikke alene at serveren har et Character-objekt. Brug eksisterende entry/elevator/streaming-kvitteringer, hvor de findes, og tilføj afgrænset readiness for manglende niveauer. Klientkvitteringer skal tilhøre den konkrete startgeneration og supplere serverens readiness-check.

I et spil med StreamingEnabled betyder helt indlæst et spilbart startområde, karakter, nødvendige controls/UI og kritiske startassets; hele den fjerne bane forventes ikke indlæst på alle klienter. En forventet continuer, der endnu ikke er ankommet, må ikke tælles som en legitim frakobling alene fordi vedkommende forlod kildeserveren. Den nuværende mulighed for at starte med en mindre cohort ved admission-frist skal ændres til fejl, hvis forventede ankomster stadig mangler. Gyldige lobbyvalg/opt-outs bevares.

Readiness ved researchstart havde følgende konkrete huller, som den fælles barriere skal dække:

| Indgang | Hul ved researchstart |
|---|---|
| Level 1 | Elevator-timer uden klientkvittering, GameManager:2205 |
| Level 2 | waitForGroupEntry-resultat ignoreres, GameManager:2170; RoundUI kan sende entryready efter mislykket ground-check/15 s timeout (:4123) og fra en 35 s fallback (:4102) |
| Level 3 direkte | Syv sekunders elevator-timer uden klientkvittering, GameManager:2190 |
| Level 2→3 rør | Gode tokens/geometry-checks findes, men prepareSlideResume tæller afslutninger frem for succes, og resultatet ignoreres; fallback-placering kan ske efter RoundActive, GameManager:793 og :2183 |

Genbrug tokenmønstret fra rørets stream-kvittering, kræv korrekt niveau/startområde, current Character og kolliderbart gulv. En fallback til elevator skal selv være verificeret før readiness. Timeout må aldrig omfortolkes til ready. Eksisterende lokale fail-open-timere skal samordnes, så de hverken starter spillet eller skjuler den nye fejl. Et returneret RequestStreamAroundAsync-kald garanterer ikke i sig selv den faktiske klientgeometri. [Roblox streaming request](https://create.roblox.com/docs/reference/engine/classes/Player#RequestStreamAroundAsync), [kritiske startassets](https://create.roblox.com/docs/performance-optimization/improve#load-times).

Implementering:

1. Saml karakterindlæsning og placering for de tre entry-loops i ét afgrænset flow. Kræv en frisk, aktuel karakter med levende Humanoid, root og vellykket placering. Afbrydelse af forbindelsen behandles særskilt.
2. Lad én uafhængig 60-sekunders deadline omfatte admission/bygning, låseventetid, engine-load, readiness og placering. Et token knytter resultater til det konkrete startforsøg; alle sene resultater kontrollerer ejerskab. Rundeur, fjender og aktiv gameplay frigives først efter hele holdets readiness-barriere.
3. Bevar global serialisering af StarterCharacter. Lobby-load flytter midlertidigt gameplay-riggen. Timeout må ikke frigive låsen eller starte konkurrerende engine-loads, mens den gamle operation stadig ejer den. Gennemfør oprydning, når operationen faktisk slutter.
4. Ved afbrudt start: ugyldiggør token, ryd kun det pågældende forsøgs placement/slide/stream-tilstand, og brug det eksisterende lobby-return-flow. Bevar den oprindelige holdliste; fjern ikke elementer under iteration.
5. Vis korrekt fejltekst før forsøg på lobby-avatar-load. Et aldrig afsluttet engine-kald må ikke blokere brugerens fejlvisning. Hvis avataren ikke kan genskabes, skal der være en tydelig genindtrædelses-/genstartsvej.
6. Kontroller fælles loader-kald i Emergency Re-entry og Level 2-overgangen, så ændringen ikke giver sene genoplivninger eller bryder refundering.
7. Reserved-server boot får én idempotent fejlrute for både afvist admission og tom resterende gruppe. Registrer terminal fejlstatus, send tydelig fejl, og genbrug eksisterende lobby-teleport, claims, retries og watchdog. Senere PlayerAdded-spillere skal følge fejlruten i stedet for ny loadinggame. De bare returns står ved GameManager:2709 og :2718; setupPlayer ved :889.

Test: almindelig start i alle niveauer; begge fortsættelser; én langsom klient holder runden tilbage; alle klar lige inden 60 s starter præcis én gang; manglende readiness ved 60 s sender hele holdet hjem; en kvittering efter timeout eller fra forkert generation starter ingenting. Desuden én/all failed; alle disconnecter; manglende root/død Humanoid/gammel Character; lås eller load hænger; placering fejler; load afsluttes efter abort eller ny start; manglende/fejlagtig teleportpakke; sen ankomst efter afvist boot; teleport kaster fejl, sender dubleret/sent fejl-event eller aldrig svarer. Fejlen ved 60 s starter recovery; Roblox-transporten kan naturligvis afsluttes senere. Test selve produktionslogikken med kontrollerede fejl, ikke kun kodeform eller nye kopier af implementationen. Udvid relevante eksisterende suites.

Test også at 45 sekunders admission/bygning efterlader 15 sekunder i samme budget; en manglende continuer må ikke udløse start med reduceret hold; valid opt-out må ikke blokere; et sent world-build-resultat efter timeout må ikke aktivere den afbrudte verden. Fejlbeskeden skal overleve returtransporten, så den også kan ses i lobbyen.

Roblox dokumenterer, at karakterload yielder, og at CharacterAdded kommer før hele karakterforløbet er afsluttet. Rigtige teleports kræver test i den publicerede Roblox-klient. [Player](https://create.roblox.com/docs/reference/engine/classes/Player#LoadCharacterAsync), [teleport](https://create.roblox.com/docs/projects/teleport).

**2. Controller**

[Trello-kort](https://trello.com/c/uI8hg2At).

Aktuel status: rettelserne er integreret i Studio; 120 offline-inputchecks og live åbning/lukning med H er bestået. Fysisk controller og den fulde fokus-/hardwarematrix nedenfor mangler fortsat. Tabellen og punkterne fastholder det accepterede omfang.

| Handling | Foreslået binding |
|---|---|
| Level 1 mission brief / eksisterende H-panel | D-pad op |
| Mute dispatch | LB/L1 |
| Skift tilskuerkamera | D-pad venstre/højre |
| Luk synlig Zyntra-terminal | B/cirkel |

ButtonSelect kolliderer med Roblox GUI-navigation. Y er optaget af Level 3-reader-panelet. D-pad op er ledig i projektkoden, men skal stadig prøves mod Roblox-menu/CoreScript-input. H-panelet er aktuelt Level 1-only; dette kort udvider ikke dets funktion til andre niveauer. [Roblox GUI-fokus](https://create.roblox.com/docs/reference/engine/classes/GuiService/SelectedObject).

Berørte filer er RoundUI, SpectateController, NoiseReporter og ZyntraStore i StarterPlayer/StarterPlayerScripts. Genbrug UIDevice. RoundUI ligger ifølge projektnoter ved Luau-registergrænsen, så undgå flere top-level locals og compile efter ændring.

- Tilføj bindings og enhedstilpassede hints, herunder den hardcodede H-keycap i RoundUI:1965. Bevar tastatur og touch.
- Skærm-ejende paneler, tekstinput og Roblox-menuen skal have prioritet. Spectate-navigation må ikke samtidig flytte GUI-markering.
- Flyt fysisk genlæsning af Shift/L2 over lobby/round-forgreningen i NoiseReporter:676. Opdater sprint-state og hastighed ved ændring. Bevar touch-RUN og skjul/slide-værn.
- Bind terminalens B-luk kontekstuelt, kun mens den er åben. Den skal ikke falde ud på et generelt processed-return eller samtidig udføre STOP DISPATCH. Sæt fokus på den aktuelle synlige fane, og gendan kun stadig gyldigt tidligere fokus ved lukning. Opdater også automatisk luk/genåbning.

Test controller-only kiosk→Settings→B; åbning/lukning af mission brief; mute; spectate med flere levende mål og efter et mål forlader; controller afbrydes med L2 holdt; Shift slippes under fokustab; flere tilsluttede controllere; tastatur/controller-skift; touch-RUN og hints. Bevar R1-lygte, L3-crouch, X-glowstick/prompts, Y-reader og B-bord-exit. Kør emulator og slut med fysisk controller. [Gamepad-test](https://create.roblox.com/docs/input/gamepad), [UserInputService](https://create.roblox.com/docs/reference/engine/classes/UserInputService), [kontekstuelle handlinger](https://create.roblox.com/docs/reference/engine/classes/ContextActionService).

**3. Pool Foam-lyd**

[Trello-kort](https://trello.com/c/24sCzSO6).

Aktuel status: den genbrugte server-emitter, state-/pausehåndtering, oprydning og det offerbegrænsede AttackHit er implementeret i Studio; 24 offline-checks er bestået. Alle lyd-ID'er er fortsat tomme. Kortet leverer først de tre aktive lyde, når faktiske filer/ID'er er integreret og aflyttet; de tolv konfigurationsfelter må ikke beskrives som færdiggjorte.

De tolv tomme felter findes i Configuration:221, men alle runtime-kloner bruger Primary (Controller:1421). Secondary spawnes ikke. Caught-grenen er deaktiveret med FreezeWhileObserved=false, og Collapse bruges ikke. Ejeren har valgt at færdiggøre tre aktive cues og udvide senere ved ny adfærd. Det ændrede kortomfang skal fremgå, når Trello opdateres; alle tolv må ikke efterfølgende beskrives som leveret.

| Aktiv lyd | Retning | Længde |
|---|---|---|
| Walk | Tung våd skum/gummi, der slæber over fliser; dæmpet og urolig | 6–8 s loop |
| Hunt | Samme materiale, hurtigere og mere presset; tydelig jagtforskel | 6–8 s loop |
| Attack | Kort vådt slag/gummisnap; uden ekstra skrig eller lang rumklang | 0,5–1 s |

Idle er stille i denne version. Caught/Collapse/Secondary er reserverede felter, indtil tilsvarende gameplay findes.

Ejerens ven har ElevenLabs og kan muligvis lave prøverne. Det konkrete brief med tre kopierbare prompts ligger i POOL_FOAM_SFX_BRIEF_2026-09-05.md. Vennens medvirken og kontotype er endnu ikke bekræftet. Alternativer er egnede gratis Creator Store-assets eller original Foley. Vi har ikke fundet/verificeret konkrete Creator Store-lyde, og denne session har intet tilkoblet lydgenereringsværktøj. ElevenLabs har loop-generering; deres gratisplan dækker ikke kommerciel brug. [Roblox lydkatalog/import](https://create.roblox.com/docs/audio/assets), [ElevenLabs SFX](https://elevenlabs.io/docs/eleven-creative/playground/sound-effects), [ElevenLabs licens](https://help.elevenlabs.io/hc/en-us/articles/13313564601361-Can-I-publish-the-content-I-generate-on-the-platform).

Lav få prøver til aflytning, vælg karakteren, kontrollér loops og mix, og behold originalfil samt kilde/licens. Eksportér helst mono 44,1/48 kHz. Upload via ejergruppen 1039373905, afvent moderation, og verificér brugsadgang til universe 10559217407. ID alene beviser ikke, at en anden spiller kan høre filen. De aktuelle importkrav omfatter MP3/OGG/WAV/FLAC, under 20 MB/7 minutter og højst 48 kHz; kontrollér resterende kvote i dashboardet. [Importkrav](https://create.roblox.com/docs/audio/assets), [asset permissions](https://create.roblox.com/docs/projects/assets/privacy).

Implementering kan forberedes før endelige IDs:

1. Én genbrugt serveroprettet bevægelses-Sound under en Attachment i hver models PrimaryPart. Start med InverseTapered 12/110 studs; mix og afstand er foreløbige værdier.
2. Skift efter faktisk bevægelses-/paused-tilstand, uafhængigt af om animationen kan loades. Gentagne samme-state-opdateringer genstarter aldrig loopet. Brug enkelt fade ned/skift/op, hvis nødvendigt.
3. Bevar AttackHit som én offerlyd. Kill-koden vælger paused Walk og øger ActionSerial før angrebet; kopier derfor ikke animationens restart-logik blindt. Kontroller rækkefølgen mellem remote og dødsreplikering, så liveLevel2-filteret ikke sluger lyden.
4. Stop og fjern lyd ved modeludskiftning, pause, Stop, genstart og rundeslut. Tomme eller afviste IDs må ikke blokere AI-loop eller lave uendelige gentagelser.

Roblox anbefaler nye AudioPlayer/AudioEmitter-objekter til nye audiosystemer. Her er eksisterende Sound en bevidst lille integration i projektets nuværende lydsystem; en samlet migration er ikke nødvendig for kortet. [Audio objects](https://create.roblox.com/docs/audio/objects), [Sound-objekter](https://create.roblox.com/docs/sound/objects).

Test retning og afstand, fem samtidige fjender uden overhøjt/synkront mix, Walk↔Hunt, kill, pause, modeludskiftning, ny runde og manglende assets. Test mindst to klienter, streaming ud/ind og spectate af fjern medspiller; 110 studs rolloff garanterer ikke, at modellen er streamet ind. Aflyt med headset og telefonhøjttaler sammen med pumper, miljø og spillerlyde. Afslut med publiceret klient under en anden konto. [Streaming](https://create.roblox.com/docs/workspace/streaming).

**Claude Fable 5.1 / Ultracode**

Den anbefalede rolle er en uafhængig kritisk gennemgang af loading-planen og senere implementationen/tests. Det er den del, hvor anden gennemlæsning mest sandsynligt finder dyre timingfejl. Der er ikke grundlag for at hævde, at en bestemt model er bedre til disse konkrete rettelser.

Anthropic beskriver Ultracode som xhigh-effort med dynamiske parallelle workflows og fremhæver uafhængig verifikation. Hold opgaven afgrænset, og lad Codex eje integrationen. Et kopierbart prompt ligger i CLAUDE_LOADING_REVIEW_PROMPT_2026-09-05.md. [Anthropic workflows](https://claude.com/blog/introducing-dynamic-workflows-in-claude-code).

**Ejerens svar og resterende praktiske aftaler**

1. Alle skal være helt indlæst før rundestart. Ved 60 sekunder uden fuld readiness: fejlbesked og hele holdet tilbage til lobbyen.
2. Tre aktive Pool Foam-lyde; udvidelse først ved ny adfærd.
3. En ven med ElevenLabs kan muligvis producere lydene. Brief er klar; ingen besked er sendt til vennen.

Fysisk controller/platform aftales før den sidste hardwaretest. Lydsmag vurderes på faktiske prøver. Publicering sker først efter en konkret gennemgang af den samlede testede ændring.
