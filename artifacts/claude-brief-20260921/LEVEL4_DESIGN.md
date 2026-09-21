# Level 4 — fuld Trello-tjekliste

Snapshot 21. september 2026. Alle ti punkter stod som INCOMPLETE. [Originalt kort](https://trello.com/c/Y2xXThBN).

**1. Oplevelsen og den visuelle retning**

Spillerne forlader level 3 og kommer ud i et alt for perfekt parcelhuskvarter. Sol, klar blå himmel, ens huse og velplejet græs giver et kort øjeblik følelsen af at være sluppet ud. Stilheden, gentagelserne og forkerte detaljer afslører gradvist, at kvarteret er en Zyntra-testzone.

Stilen skal være liminal og troværdig med let kunstige proportioner: enkle pudsede/træbeklædte facader i falmet creme, støvet gul og blågrå; mørke tage; præcise hække; postkasser og lave hegn. Græsset må gerne være unaturligt ensartet grønt. Få diskrete Zyntra-neonmarkeringer på testudstyr — ikke neon på hele kvarteret. Silhuetten af et vand-/signaltårn fungerer som landmærke.

Brug næsten identiske huse med små men aflæselige afvigelser: et ekstra vindue, forkert husnummer, en postkasse vendt mod huset, gardiner som er trukket for på én side. Interiører har almindelige møbler, som gentages lidt for præcist, tomme billedrammer, et CRT-TV og ingen beboere. Undgå tilfældig rod, som skjuler gameplay-spor.

Lyset begynder som varm, stille eftermiddag. Under fareperioder bliver himlen koldere, disen tættere og enkelte verandaer slukker i en tydelig sekvens. Bevar læsbarhed på mobil; spændingen må ikke kræve næsten sort skærm. Intet påkrævet gore; design til spillets eksisterende milde frygtprofil uden at love en bestemt platformsvurdering.

---

**2. Kortets opbygning**

Første version: 8–12 synlige huse, ca. 8–12 minutters målspilletid og én entity. Byg en sammenhængende rundstrækning med en tværgående genvej, så en forfølgelse kan brydes uden blindgyder.

- Indgang: en kort servicepassage fra level 3 åbner mod kvarterets centrale gade. Spillere spawner adskilt på stabilt underlag.
- Første hus: et trygt introduktionsområde med Zyntra-briefing, et synligt eksempel på en anomali og den første enkle succes.
- Tre undersøgelsesområder: hver har flere mulige opgavehuse, tydelige landmærker og mindst to forbindelser tilbage til hovedruten.
- Midte: et lille grønt område med bænk, slukket legeplads eller telefonboks; landmærke og sigtelinje til tårnet.
- Finale: et Zyntra-signalskab ved et busstoppested nær tårnet. Det kan ses tidligere, men aktiveres først efter tre undersøgelser.
- Udkant: gentagne facader og bakker skaber illusionen af et enormt kvarter. Dekorationshuse behøver ikke interiør; gameplaygrænsen skal fremstå naturlig.

Brug 2–3 interiørmoduler til de tilgængelige huse. Placér døre, trapper og passagebredder efter vores faktiske karakter og entity-rig. De første spilbare huse skal have tydelige ind-/udgange og nok plads til at passere en holdkammerat. Undgå fysisk labyrint af mange ens rum.

---

**3. Rundens forløb**

1. Ankomst: kort, roligt blik ud over kvarteret. Spilleren får selv kontrollen og ser, hvor de kan gå hen.
2. Briefing: “Investigate three residential signals. Restore the extraction beacon. Stay quiet.” Vis 0/3 fælles mål i eksisterende Objectives-stil.
3. Første undersøgelse: en tilgivende opgave viser, hvordan man genkender et ændret hus og aflæser et signal. Første entity-cue kan observeres fra sikker afstand.
4. Fri undersøgelse: holdet vælger rækkefølge mellem de tre zoner. Eksempler på opgavetyper: sammenlign facade med et referencefoto, find den forkerte udsendelse på et TV, og registrér en prøve ved et unormalt målepunkt. Giv også visuelle spor, så ingen opgave kræver hørelse eller mikrofon.
5. Fare og rutevalg: The Neighbour undersøger støj. Holdet vælger stille omveje, bruger et aflæseligt sikkert hus eller lokker entityen væk fra en holdkammerat.
6. Finale: de tre undersøgelser låser signalskabet op. Holdet aktiverer tre korte kontroller omkring busstoppestedet. Én spiller skal kunne udføre dem efter hinanden; flere kan samarbejde.
7. Udgang: et kort, tydeligt varsel efterfølges af transport/udgang i levelgrænsen. Genbrug completion-, reward- og Continue/Return-flow. Ingen automatisk succes for spillere, der aldrig nåede ud.

Første prototype kan bruge almindelig interact til dokumentation. Når research-kameraet er klar, integreres det gratis basiskamera. Betalt kamera eller detector må ikke blive en adgangsbillet til completion.

---

**4. The Neighbour — entityens udseende og regler**

Bevar retningen fra den eksisterende note om en høj, Slender-lignende skabning, men lav en selvstændig Zyntra-entity. Arbejdsnavn: The Neighbour.

Udseende: meget høj og smal, for lange underarme, stift arbejdstøj og et ansigt skjult af mat glas/maske. En unaturlig hældning i hovedet og langsomme, målrettede skridt gør den genkendelig på afstand. Lav egen silhuet, rig og animationer.

Adfærd:
- Patrol: bevæger sig mellem gader, postkasser og verandaer.
- Investigate: reagerer på løb, hårdt smækkede døre og relevante opgavelyde. Undersøger lydens position frem for at kende spillerens placering uden spor.
- Search: stopper ved huse, lytter og kontrollerer indgange. Spilleren kan aflæse søgningen gennem skridt, silhouette og vindues-/verandasignaler.
- Chase: udløses ved faktisk afsløring tæt på/med fri sigtelinje. Der skal være varsling og mulighed for at bryde kontakten.
- Return: når sporene mistes, søger den kort og vender tilbage til patrulje.

Stille gang og et afbrudt synsfelt skal have værdi. Døre må forsinke entityen kort, men kan ikke holde den fast for evigt. Ingen teleport direkte oven på spilleren, skade gennem vægge eller hits på en korrekt skjult spiller. Brug gameplay-støj; voice chat kan være en ekstra oplevelse, men er aldrig nødvendig.

---

**5. Sikre huse, varsler og variation**

Huse kan have en af tre tydelige tilstande: sikkert, varslet og farligt. Et stabilt verandasignal samt fravær af en bestemt facadeanomali viser et brugbart skjul. Før status skifter, vis et tydeligt forvarsel med lys og en lav tone; spilleren får tid til at forlade huset.

Sørg for mindst ét nåeligt sikkert alternativ i den aktive zone. En spiller må ikke låses inde eller dræbes øjeblikkeligt af et skjult tilstandsskift. Faren er en beslutning om rute og observation; den skal ikke gentage level 3's musikstop-og-gem-dig-under-bordet.

Lav 2–3 kontrollerede kombinationer af opgaveplaceringer og facadeanomalier. Alle spillere ser samme runde. Entity-reglerne og betydningen af varsler skifter ikke vilkårligt.

---

**6. Lyd og stemning**

Udendørs: svag vind, fjern elektrisk summen og unaturligt få naturlyde. Indendørs: dæmpet køleskab/TV, træknirk og entity-skridt udenfor. The Neighbour får tydeligt forskellige patrol-, search-, chase- og attack-signaler med afstand og retning.

Undgå konstant musik, så stilheden kan bære spændingen. Lydhaler fades rent til nul; ingen hørbar statisk støj i stille passager. Brug naturlig udendørs dæmpning og korte husrefleksioner frem for pool-/korridor-ekko overalt. Kritiske varsler har også en visuel komponent.

---

**7. Assets og byggefaser**

- Blokmodel: gader, 8–12 husvolumener, tre zoner, genvej, spawn og exit. Gennemfør først hele ruten med simple interaktioner.
- Spilbar prototype: ét færdigt hus, første research-opgave, entity med patrol/investigate/search/chase og ét sæt læsbare faresignaler.
- Udvidelse: tre objektivtyper, 2–3 placeringsvarianter, sikre huse, finale, solo-/holdskalering og reset.
- Art pass: modulære facader, 2–3 interiører, postkasser/hegn/lygter, signalskab, busstoppested, baggrundsbakker, sky/lys, entitymodel og animationer.
- Audio/UI: rumlyd, entity-SFX, Mission Brief, fælles opgavebeskeder, completion og arkivindgange.
- Færdiggørelse: mobilperformance, pathfinding, collision, respawn, progression og publiceret level-overgang. Bevis gennemført arbejde før kortet flyttes til Done.

Stream/genbrug husmoduler, hold baggrundsdekoration enkel og undgå hundredvis af unødvendige dynamiske lyskilder. Serveren afgør opgaver, skade, spawns og rewards; klienten viser effekter/UI. Entity-navigation skal fungere ved åbne/lukkede døre, traps og skiftende spillerantal. Fjern rundeobjekter og lyd ved unload.

---

**8. Kriterier for færdig level**

- Hele runden kan gennemføres solo og med spillets understøttede holdstørrelse uden betalt udstyr.
- PC og touch kan aflæse varsler, undersøge, gemme sig, bruge udstyr og afslutte.
- Alle opgavekombinationer er løselige; ingen nødvendige spor forsvinder permanent ved død/disconnect.
- Spawn, level 3→4, re-entry, død, spectate og lobbyretur fungerer uden clipping eller dobbelte belønninger.
- Nye spillere forstår den vigtigste entity-regel efter første møde.
- Mål: start→første undersøgelse, completion pr. zone, dødssteder, exit undervejs, genforsøg og antal spillere der overhovedet når level 4.
- Registrér observeret spilletid og performance på relevante mobilenheder; 8–12 minutter er et designmål, ikke et fast krav.

---

**9. Sammenhæng med de øvrige nye opgaver**

Research-opgaver: https://trello.com/c/wEFTmguQ
Entity-arkiv: https://trello.com/c/nWCCdowB
Entity Detector: https://trello.com/c/Zyrtgu79
Research Camera: https://trello.com/c/cqvNQIIc
Level-variation: https://trello.com/c/OBjSW30k
Fælles objective-beskeder: https://trello.com/c/FAgRQho1

---

**10. Inspiration og afgrænsning**

Motion/Level 94 er tematisk reference til falsk tryghed og et forvrænget boligkvarter. Byg egne rum, opgaver, assets, historie og entity. Konkurrenternes besøg/badges dokumenterer eksponering, ikke at netop dette level har bedst retention eller salg. Run for Your Life kan overvejes som senere kort ekstrasekvens; Funrooms fravælges som level 4-retning, fordi level 3 allerede har party/mall-tema.

https://www.rolimons.com/game/9534337535
https://escapethebackrooms.fandom.com/wiki/Level_94_Guide
