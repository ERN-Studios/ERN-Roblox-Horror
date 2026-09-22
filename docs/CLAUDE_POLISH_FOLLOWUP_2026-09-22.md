# Claude — implementér Codex' polish-review og de nye Trello-kort

Du skal lave **al kode og teknisk implementering**: Luau, integration, tests og eventuelle Blender-/asset-scripts. Codex har lavet review, konkrete visuelle beslutninger og en paintover. Implementér og verificér nedenstående; stop ikke efter en plan. Brug Studio MCP, Git, filer og API'er; så lidt almindelig computerstyring som muligt.

Projekt: `G:/Roblox/MongoTV`. Spillertekst på engelsk. Handoff på dansk.

## 0. Ny ejerinstruktion — fjern Field Notes og lobbyens Try again

Tilføjet 22/9/2026 efter det oprindelige prompt. Denne instruktion har forrang over ældre ønsker om Field Notes/notes-arkiv og retry-guide, inklusive A4 nedenfor. Fortsæt igangværende arbejde og bevar samtidige ændringer; start ikke de allerede færdige faser forfra.

**Fjern Field Notes som aktiv funktion i spillet:**

- Fjern Notes/Field Notes-fanen og alle indgange til den, læsevinduet, note-pickups og interaktionsprompts i levels, discovery-notifikationer, samlingsprogression og den tilhørende `FIELD ARCHIVIST`-titel.
- Afvikl de aktive spawn-/discovery-/UI-kald og de remotes, listeners, konfigurationsfelter og moduler, der kun bruges af funktionen. Fjern referencesammenhænge ordentligt, så der ikke opstår manglende requires, WaitForChild-timeouts, tomme navigationselementer eller efterladte pickups. Lad ikke blot UI'et være skjult, mens systemet fortsætter i baggrunden.
- Gamle FieldNotes-felter i spillerprofiler må gerne bevares som inert legacy-data for bagudkompatibilitet. Ingen destruktiv DataStore-oprydning, profilreset eller tab af tokens, udstyr og andre rewards. Gamle profiler skal stadig indlæses normalt; Field Notes-titlen skal ikke længere vises eller optjenes.
- Gennemgå især `ServerScriptService/FieldNotesService.Script.lua`, `StarterPlayer/StarterPlayerScripts/Field Notes Client.LocalScript.lua`, `ReplicatedStorage/ZyntraFieldNotes.ModuleScript.lua`, `ZyntraFieldNotesPage.ModuleScript.lua`, samt referencer i ZyntraStore, ZyntraConfig og ZyntraMonetization. Disse stier er navigationshjælp; læs den friske Studio-kilde før ændringer. ZyntraMonetization er samtidig berørt af reward-arbejdet og må ikke overskrives med en ældre fil.

**Fjern den automatiske Try again-guide efter død og retur til lobby:**

- Ingen `TRY AGAIN · LEVEL …`-tekst, lyssti, pil eller billboard mod en level-kø efter død, party wipe eller anden ikke-escaped retur. En gammel `RetryLevel` i en teleportpakke eller `RetryGuideLevel`-attribut må heller ikke genaktivere den.
- Fjern retry-delen i `First Entry Guide.LocalScript.lua` og de GameManager-/teleport-kald, som kun understøtter den. Bevar førstegangs-guiden `LEVEL 1 START HERE`, almindelige køer, dødskort, respawn/revive og completion/Continue/Return-flowet.
- Fjern også den automatiske Level 4-dev-erstatning `LEVEL 4 DEV ROUND ENDED ... TO RUN AGAIN` og den tilhørende banner/listener-logik. Den skal ikke være et nyt lobbyhint i stedet for den fjernede guide. Selve udvikleradgangen til Level 4 bevares.
- Afgræns efter funktion, ikke global tekstsøg/erstat: almindelige fejlbeskeder om at prøve igen ved netværks-/indlæsningsfejl er ikke denne lobbyguide.

Verificér, at en gammel profil med opdagede notes stadig kan indlæses, at ingen Field Notes-UI/titel/pickups eller aktive spawns er tilbage, og at Rewards/Wheel/shop virker efter oprydningen. Kør en faktisk lokal død → lobby og kontrollér fraværet af retry-tekst og guideobjekter. Kontrollér også, at en gammel returpakke ikke genskaber guiden, og at førstegangsintroduktion og manuel køstart stadig virker. Opdatér relevante regressionstests til den eksplicit ændrede produktadfærd; dokumentér uverificerede produktions-/multiplayer-scenarier ærligt.

Al implementeringskode udføres fortsat af Claude. Opdatér handoffet med fjernelser, scoped ændringer, checks og eventuel publiceringskvittering efter projektets eksisterende workflow.

## 1. Start fra den rigtige aktuelle version

Læs først:

1. `G:/Roblox/MongoTV/AGENTS.md` og `CLAUDE.md`; AGENTS' nyere Studio-regler har forrang over gamle sync-anvisninger.
2. `G:/Roblox/MongoTV/docs/CODEX_POLISH_REVIEW_2026-09-22.md`.
3. `G:/Roblox/MongoTV/docs/CODEX_POLISH_HANDOFF.md` og de relevante kontrakter i `docs/LEVEL4_CONTRACTS_2026-09-21.md`. Sidstnævntes indledning/installationsafsnit er historisk; scripts findes allerede.
4. `G:/Roblox/MongoTV/artifacts/codex-polish-20260922/README.md`, evidens-JSON og begge facadebilleder. Åbn billederne visuelt.

Ved reviewet stod Claude-branchen på `7e45852bdfa83cabc590de586d29365d082e627b`, 43 commits over PR #3, draft PR #4. Der kan nu ligge en efterfølgende Codex-commit med denne dokumentation og billeder. Fetch og undersøg selv den friske status.

Studio er autoritativt. Tag native backup samt Source/editor-baseline før ændringer. Recheck den præcise kilde inde i hver scoped skrivning; bevar samtidige ændringer. Ingen bulk-push fra Git eller restore af en gammel place. Mange uvedkommende untracked filer findes allerede; brug aldrig blind `git add -A`.

Seneste kontrol: 167/167 scripts matchede Studio, 0 Source/editor-konflikter. Åben editor viste PlaceVersion 1958, men der findes kvitteringer for v1973 og nyere **v1976**. Brug kvitteringer og aktuelle kilder, ikke editorens versionsfelt alene.

Bevar detector-polish. De tre runtime-filer i `e9bf35c` / PR #5 er allerede integreret via `d8edb14`; deres diff mod review-baselinen var tom. PR #5 har yderligere asset-/backupdokumentation, som skal bevares ved senere Git-reconciliation. Genimplementér ikke detektoren og overskriv ikke den anden sessions arbejde.

Der er nu **135 Trello-kort**. De tre nye åbne kort er med i fase B nedenfor; det fjerde nye kort er detectoren, som er Done. De øvrige tidligere opgaver skal ikke blindt implementeres igen.

## 2. Fase A — Level 4-rettelser og første facadepolish

Level 4 forbliver **dev-only**: flag plus DevAccess for alle deltagere, normal lobby “coming soon”, intet offentligt Level 3→4-tilbud. Denne opgave gør ikke hele C4 færdigt.

### A1. Ret de to bekræftede geometri-fejl

Fil: `ServerScriptService/Level 4 Systems/Level 4 World Builder.ModuleScript.lua`, `buildHouseShell` og `buildWindow`.

- **Tag:** De to wedges har høj kant ved yderenderne og lav kant ved midten. Codex målte på både House_Intro og House_A1: ved z±14 er overfladen 18,365 studs over floor-center; ved z±0,1 er den 12,641. Ret til sadeltag med højeste ryg midt i husets dybde og ryg parallel med facaden. Ret også den forkerte kommentar om wedge-retning. Bevar footprint 30×34, væghøjde 13 og taghøjde 7.
- **Vinduer:** På House_Intro er væggen z=36–37; ruderne er z=36,4–36,8 og dermed helt skjult inde i væggen. Flyt rude/ramme til den rigtige yderside for BEGGE FacingZ-retninger. Normalfacaden har fire synlige vinduer; ExtraWindow-varianten har ét ekstra. En billig opaque/farvet rudeflade er tilstrækkelig i første pass, hvis det ser overbevisende ud; fuldt gennemskårne facadehuller er ikke et krav.
- Kontrollér WrongNumber-/DrawnCurtains-sockets og deres SurfaceGui-/fladeorientering. De tynde dimensioner ser ikke ud til at være orienteret som facadevinduerne. Afvigelser skal være synlige og forståelige fra fortovet.

Verificér med native billede og målte tagoverflader, begge facaderetninger og mindst to seeds. En test, der kun gentager de valgte rotationskonstanter, er ikke et bevis på korrekt geometri.

### A2. Implementér den valgte facade-retning

Reference: `artifacts/codex-polish-20260922/level4-facade-polish-target.png`, sammenlignet med `level4-facade-before.jpg`.

- Falmet creme/støvet gul/blågrå facade, mørkt korrekt sadeltag, beskedne sternbrædder/udhæng, synlige ruder med enkle rammer og karme.
- Genkendelig mailbox med tydelig front/låg, så ReversedMailbox kan aflæses. Lavt hegn og ensartede, enkle hække. Ingen tilfældig clutter, som skjuler spor eller blokerer navigation.
- Verandasignal som en lille graphite-indfatning med en begrænset lysåbning. SAFE grøn, WARNED rav, DANGEROUS rød/slukket porch-light som i kontrakten. Mindre farvespil på græs/væg; farven skal stadig aflæses på afstand.
- En normal læsbar husidentifikation og et entydigt WrongNumber-eksempel. HUD'ens hus-id skal kunne kobles til et hus i verden. Bevar lot-id'et som teknisk identitet, selv hvis den synlige nummerplade har en separat referenceværdi.
- Udskift den synlige, høje, flade grønne væg med simple dekorative bakke-/horizont-silhuetter. Bevar de eksisterende gameplay-blockers og grænser. Lav ikke et nyt terræn-/streamingsystem.

Billedet er en reference, ikke en tekstur, blueprint eller et nyt asset-ID. Detaljer i græs/hække/baggrund er overdrevet i renderingen: implementér lav kompleksitet og fælles materialer. Brug eksisterende stock-materialer og få fælles meshes; der er ikke behov for nye raster-assets til dette pass.

Kontrakter har forrang over billedproportioner: fri dør **6×10,5**, gennemgange mindst **6**, uændrede InteriorVolumes, prompt-ankre, patrol-punkter, signal-/cabinet-index, escape trigger og Neighbour-envelope. Trim må ikke gøre åbninger mindre. Hold højst 12 dynamiske lys og 0 dynamiske lys med Shadows; dokumentér del-/mesh-/texture-/descendanttal og faktisk frame-cost efter passet. Loftet 12.000 descendants er ikke et mål om at fylde budgettet.

### A3. Giv levellet det aftalte rolige anløb

Filer: `Level 4 Objective Controller`, `Level 4 Configuration`, `StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller` og relevant objective-UI.

Codex reproducerede seed 101/CLOSE med 0/3 signaler, Neighbour PATROL og ét usikkert hus, mens klienten allerede stod på fareprofilen 17,6 / brightness 1,9 / fog 70–380. `dangerNow` reagerer på ethvert usikkert hus i hele levellet, og house-deadline starter før ankomsten er færdig.

- Lad scheduleren tage udgangspunkt i reel rundestart/kontrol efter ankomsten, ikke build-tid. Giv mindst cirka 20 sekunders roligt anløb uden tilfældige husvarsler. Reelle, bevidst fremprovokerede entity-møder må stadig følge tydelige varsler.
- Et fjernt usikkert hus må ikke alene fastholde hele klienten i farelys. Brug en tydeligt afgrænset relevant faretilstand, eksempelvis faktisk ALERT/CHASE mod spilleren eller spillerens eget varslede/farlige hus, og vend tilbage til calm når den ophører. Bevar fælles serverautoritativ gameplay-tilstand.
- Bevar brightness-floor 1,6, læsbar tåge og rolige transitions. ReduceFlashing skal virke, og server-/klientkonfigurationens spejlede værdier skal stemme.
- Vis `LEAVE WITHIN …` til spillere, som faktisk befinder sig i det truede hus. Udenfor: højst en relevant, kort lokal orientering; ikke en gentagen flugtordre til hele kvarteret. Tilstande skal kunne aflæses uden kun at skelne farver.
- Bevar mindst ét nåeligt sikkert alternativ i aktiv zone. Ingen skjult øjeblikkelig skade eller indelåsning fra hus-skift.

### A4. Luk de små, kendte prototypehuller

- Exit-position/readeren skal pege på en faktisk anvendelig indgang til EscapeTrigger, ikke stoppe 3,5 studs foran den uden at kunne fuldføre.
- Den tidligere opgave om et Level 4-retry-hint er erstattet af ejerinstruktionen i §0: fjern automatisk lobby-retry-guide og dev-erstatningsbanner. Bevar selve udvikleradgangen og almindelig manuel rundestart.
- Gem et billede af det faktiske Neighbour-dødsårsagskort efter et reelt kill. Det gamle `level4-death-neighbour-desktop.jpg` viser kun den generiske endskærm.
- Opdatér kontraktdokumentets status/installationsanvisninger, så næste udvikler ikke genopretter eksisterende scripts.

Minimumsbevis for fase A: seed 101 + seed 202, begge husretninger, synlige normale og anomale facader fra fortovet, rolig start → reel fare → ro igen, ReduceFlashing, solo tre signaler → tre kabinetkontroller → faktisk exit, samt ét reelt Neighbour-kill med korrekt kort. Verificér også uændrede passage-/shelter-regler og ingen nye consolefejl. Det er fortsat solo/Studio-evidens.

## 3. Fase B — tre nye Trello-kort og første CD-interaktion

### B1. Notifikationsprikker og kort reward-introduktion

[MsEn2mya](https://trello.com/c/MsEn2mya).

På Rewards- og Wheel-knapperne: en lille rød prik, kun når spilleren faktisk har noget tilgængeligt. Rewards følger claimable serverprofil/milestones; Wheel følger tilgængeligt gratis spin eller en uafhentet præmie. Prikken skal forsvinde efter gyldig indsamling og opdateres korrekt ved profilpush og dagskifte. Ingen evig reklameprik eller ekstra ticker/subscription pr. genåbning.

Efter spillerens første **reelle level-completion**: en meget kort, lukbar introduktion til, hvad Rewards og Wheel giver. Vis først på et roligt tidspunkt i lobbyen, efter win/Continue/Return-flowet, aldrig oven på briefing, queue eller en anden modal. Forklar få ting med eksisterende UI-stil; højst et par små trin. Persistér, at den er set. Afvisning må ikke blokere spillet, og genjoin må ikke spamme den. En død eller et round-start tæller ikke som completion. Normal spillertekst på engelsk.

Start med `ZyntraStore.LocalScript.lua` (rail-knapper), Daily Rewards Client, Lucky Wheel Client, DailyRewardsPage og eksisterende serverprofil/completion-vej. Genbrug etableret modal- og touch-suppression.

### B2. Et ærligt og sikkert collect-forløb

[25GLltY6](https://trello.com/c/25GLltY6).

Efter wheel-resultatet skal spilleren se en tydelig primærknap `COLLECT PRIZE` og derefter en kort bekræftelse, eksempelvis `1 token collected` / `25 tokens collected`, eller det rigtige item-navn og antal. Samme tydelige bekræftelse efter Daily-claims. Brug ikke skrivebordsteksten “click” som eneste forklaring på touch/controller.

**Vigtig eksisterende adfærd:** `ZyntraMonetization.spinDailyWheel` udbetaler allerede via `applyReward` i spin-mutationen før animationen. Sæt ikke en anden udbetaling på den nye knap. Implementér et reelt serverautoritativt pending→claimed-forløb for nye spins, hvor resultatet gemmes varigt ved spin, og den efterfølgende claim udbetaler præcis én gang atomisk. Eksisterende historiske WheelLast-resultater er allerede udbetalt og skal migreres/behandles som claimed, ikke genudbetales.

Uafhentet præmie skal overleve lukning, død, rundestart og rejoin. Et dagskifte må ikke slette den eller overskrive den med et nyt spin. Bevar odds, præmier og reset-semantik for gratis spins. Test dobbeltklik, tabt reply/retry, to claim-anmodninger, gemmefejl og gammel profil. Vis succes først efter serverbekræftelse; en animating/toast alene er ikke en claim. En receipt/serial skal forblive entydig gennem dagskifte og genjoin.

Bekræft Daily-claims med den samme principielle regel uden at omskrive den eksisterende sikre belønningsøkonomi unødigt. Undgå to konkurrerende toasts for samme claim.

### B3. 50 % flere Level 1-fuse-relays til små hold

[JYiwjBxw](https://trello.com/c/JYiwjBxw).

Fil: `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua`, `startPuzzle`, nuværende `fuseCount = fusesNeeded * SPAWN_MULT` og `pickWallSpots`.

Brug det allerede frosne antal aktive deltagere ved rundestart. For 1–3 deltagere: +50 % relay-spawns, rund op til et helt antal. For 4–6: eksisterende adfærd. Med reviewets standardmultiplier 2 er forventede spawn-mål **3, 3, 6, 4, 6, 6** for holdstørrelse 1–6, mod tidligere 2, 2, 4, 4, 6, 6. Bekræft den aktuelle MasterConfiguration før du bruger tallene som facit.

Ændr ikke hvor mange fuses/circuit boxes/levers der kræves for completion eller hastighedseskalering. Flere indsamlingssteder skal være fordelt og nåelige på rigtige vægspots med eksisterende decor-/pit-/spawn-clearance. Bekræft faktisk placerede modeller; det er utilstrækkeligt at øge et måltal, hvis placement falder tilbage til færre. Spectators og sent indkommende må ikke ændre den frosne puzzle.

Verificér holdstørrelse 1–6 i relevante plan-/spawn-checks, mindst to solo-layouts i Studio og en repræsentativ rigtig multiplayer-runde hvis den kan etableres. Markér sidste punkt uverificeret, hvis det kun simuleres.

### B4. Fjern prompt-konkurrencen ved første Level 3-CD

Handoffet beskriver HIDE og TAKE på samme første bord. `Level 3 Hiding Controller.refreshPrompt` tager ikke hensyn til CD-tilstand. Reproducer først med seed 1154781618 (`L3_S1_R05` i review-baselinen).

Når den første CD stadig ligger WORLD på sit introduktionsbord, skal TAKE være den entydige primære interaktion ved bordet. Gendan normal hiding efter pickup. Bevar alle øvrige borde, occupancy cap og eksisterende skjuleregler. Afvis også en ugyldig hide-anmodning på serveren; client-prompt-visibility alene er ikke nok. Håndtér cleanup/reset samt drop/rejoin efter de faktiske tilstande uden at låse hiding vilkårligt resten af runden.

Bekræft den almindelige prompt-oplevelse på desktop og simuleret touch, samt pickup→hiding og to spillere hvis tilgængeligt. Genbrug den eksisterende CD-reader og ReduceFlashing-adfærd.

## 4. Fase C — kontrolleret Level 2-arch-mesh-pilot

Dette er det valgte næste art/performance-forsøg; der behøves ikke en ny generel ejerafklaring for at lave en reversibel pilot. Store ændringer i rig, priser eller offentlig level-adgang er ikke del af forsøget.

Handoffets måling peger på 13.454 bue-/spandrel-dele og 32.224 Texture-instanser (77 % af de daværende textures). 71k→26k descendants er kun et overslag. Lav faktiske genanvendelige mesh-assets og en integration bag en reversibel kontakt; dokumentér før/efter med samme seed. Codex' screenshot/palette er art-reference, ikke en færdig mesh.

Udgangspunkt: `Level 2 World Builder.makeArchSpan`, `makeBarrelVault` og de tre kald til makeArchSpan. Profilen varierer: radius, floorDepth, verticalScale, axial/radial depth, kids-style og flisemål. Standardribben er 3,2×2,2 tværsnit, verticalScale 1,9 i korridoren; den slanke portalflade bruger axial depth 0,6 og andre radial-/segmentparametre. Bevar de eksisterende verdensmål, forlængelsen under gulv/vand og den faktiske tile-skala; udstrakt UV på en vilkårligt skaleret standardbue er ikke tilstrækkeligt.

**Collision-korrektion til handoffet:** `CanCollide=false` er eksplicit på portalens `.face`-buer. De normale korridorribber og fritstående ringe sender ikke flaget og bevarer collision. Klassificér hver familie fra frisk Studio/source. Bevar collision-envelope og `Vault Strip`-shell. Sæt ikke alle buer til non-colliding som en generel optimering. Spandrels er en særskilt profil, ikke automatisk dækket af en ring-mesh.

Start med én hyppig standardkorridor-familie og sammenlign den med den originale generator på samme placering. UV/tint: eksisterende `TILE_TEXTURE` (`113211706146395`), 7 studs hvor den relevante kaldesti bruger 7, og korrekt varm/kids-variant. Reuse materialer, ingen ny stor Texture-instans pr. flade. Hvis familieudvidelse bevarer kontrakterne, udvid til de verificerede varianter; ellers behold fungerende fallback for resten.

Returnér editable originalfil, eksport, mål/pivot/orientation, faktisk uploadede asset-ID'er hvis upload gennemført, kildehash og klart familiescope. Findes der ingen brugbar import/upload-vej, lever den faktiske lokale meshfil og den præcise tilbageværende blokering; opfind aldrig ID'er eller påstå live-integration.

Verificér native kameratur med identisk seed (start med 1182081016), silhouettes, tiling, streaming/fallback og collision for spiller, PoolSlide og Foams. Mål klient-frame-time med foreground-status og samplingvarighed, servercost, parts/meshes/textures/descendants; adskil cold build fra stabil aktiv runde. Et lavere instance-tal er ikke alene bevis for højere mobil-FPS. Aktiver kun den nye vej som standard, hvis de relevante checks består. Ingen fysiske-device-påstande ud fra Studio-emulering.

## 5. Verifikations- og statusgæld, som ikke må skjules

- De 78 UIRegression-fejl er **ikke bevist forældede**. Gruppér dem, sammenlign relevante kontrakter/baseline uden at restore gammel Studio, og reproducer de vigtigste konkrete fejl. Ret reelle UI-fejl; opdatér kun tests med begrundelse og bevis for ændret ønsket adfærd. Kør relevante matrices efter UI-ændringerne. Kalder du en fejl baseline, vedlæg sammenligningen.
- Analytics: test `Join→ProfileLoaded`, `ProfileLoaded→Join`, dobbelt kald og reserved-server-ankomst. `ProfileLoaded` kan oprette sessionen på step 2, og `onboard` dropper senere lavere trin. Produktions-latens er ikke en garanti. Ret deterministisk, hvis rækkefølgen bryder den aftalte funnel-kontrakt. Dashboard-ingestion må først erklæres efter faktisk modtagelse; Studio-ring er kun instrumentering.
- Token Earner D3 skal **ikke implementeres ud fra handoffets formel**. Fra en saldo på 100 giver køb af 2x→3x→5x i rækkefølge 1.200, mens direkte 5x giver 500. Priser, tokenkilder, køb/upgrade/spend-semantik og afrunding er fortsat uafklaret. Gør ikke et regnefejlsforslag til et salgssystem.
- PoolSlide-rig/animationer: originalkilden mangler stadig. Bevar eksisterende anim-ID'er og størrelse. Ingen placeholder-upload eller generisk animation må præsenteres som et løst A1-artpass.
- C1–C3 og D1–D3 er fortsat den særskilte backlog fra første prompt; denne opgave er polish/korrektion plus de tre nye konkrete kort. Ingen nye monetiseringspriser, udfordringsbelønninger eller publicering af Level 4 som tilgængeligt indhold.

## 6. Afslutning og håndoff

Arbejd i små, verificerbare commits. Afslut de uafhængige dele, selv hvis hardware/personer/PoolSlide-kildefil blokerer en anden del. Skriv præcist, hvilke checks der er kørt, og hvad der kun er kildeinspektion eller emulation.

Før en eventuel publicering: relevant kompilation/test, gennemgåede runtime-ændringer, native før/slut-backup, opdateret Studio-manifest og 0 Source/editor/repo-drift for taskens afsluttede baseline. Fjern Play-prober, gendan normale dev-flags og bevar alt samtidig arbejde. Følg AGENTS' eksisterende publiceringspræference for færdige, verificerede ændringer i samme experience; publicér ikke materiale med konstaterede blockers, og slå ikke Level 4-gaten fra. Gem Roblox' kvittering og det faktiske versionsnummer; genstart ikke aktive servere.

Bevar PR-stacken og detector-arbejdet. Tilpas PR-titel/beskrivelse til det reelle indhold. Ingen force-push eller automatisk merge. Commit taskens faktiske ændringer efter præcis staged-review, og adskil lokal commit, GitHub-push og Roblox-publicering i status.

Lever et opdateret `docs/CODEX_POLISH_HANDOFF.md` med:

1. Status pr. fase/kort: implementeret, verificeret, publiceret eller konkret blokeret.
2. Native før/efter-billeder fra de samme kameraer, første-CD-prompt, reward collect/badges og faktiske kill-kort.
3. Mål for geometri/performance og godkendte mesh-familier/fallbacks, uden projicerede tal forklædt som målinger.
4. Asset-/rig-kontrakter, originale filer, eksport/IDs og de få præcise art-/lydopgaver, Codex skal tage videre.
5. Commit-/PR-/publish-bevis og en kort liste over ægte resterende beslutninger.

Det vigtigste næste resultat er et Level 4, som visuelt ligner den valgte forstad og bevarer gameplay-kontrakterne, samt de tre nye spillerrettede forbedringer med korrekt serveradfærd. Ret de bekræftede fejl før du lægger flere detaljer på.
