# Level 4 "The Quiet Suburbs" — handoff

**Til:** den udvikler, der overtager Level 4.
**Fra:** Claude, for ejeren (mikkelczar), 23. september 2026.
**Trello:** [Y2xXThBN — Level 4](https://trello.com/c/Y2xXThBN).

Level 4 er en spilbar, **dev-only prototype**. Et helt forløb virker fra start til slut, men alt visuelt er pladsholdere, og der er
ingen lyd eller animationer. Du overtager hele Level 4: kode, kort, The Neighbour og art-integration. Resten af spillet
(Level 1–3, lobby, butik) bliver ved med at blive vedligeholdt af ejeren, Claude og Codex. Derfor skal du holde dig til
Level 4-filerne og koordinere med ejeren, hvis du skal ind i fælles scripts.

Dette dokument er indgangen. Detaljerne står i:

| Dokument | Hvad det er |
|---|---|
| [LEVEL4_CONTRACTS_2026-09-21.md](LEVEL4_CONTRACTS_2026-09-21.md) | **Kontrakten.** Instansnavne, attributter, mål, rig, animations- og lydslots, smoke test og kendte huller (§13) |
| [LEVEL4_VIDEO_DIRECTION_2026-09-22.md](LEVEL4_VIDEO_DIRECTION_2026-09-22.md) | Den visuelle retning: en lille forstad under enorme indendørs boligfacader, broer og et kunstigt loft |
| [../assets/concepts/level4-indoor-suburbs-v1.png](../assets/concepts/level4-indoor-suburbs-v1.png) | Konceptbillede (kun reference, ikke et asset) |
| [../assets/level4/neighbour/MODEL_HANDOFF.md](../assets/level4/neighbour/MODEL_HANDOFF.md) | Brief til modellen af The Neighbour, med T-pose-referencer i samme mappe |
| [../assets/level4/materials/README.md](../assets/level4/materials/README.md) | Fem teksturer (siding og loftpaneler) med gruppeejede image-id'er, endnu ikke brugt i spillet |
| [CODEX_ASSET_ORDER_2026-09-23.md](CODEX_ASSET_ORDER_2026-09-23.md) §3 | Hvad der er bestilt hos Codex til Level 4 (model, animationer, facademoduler, lyd) |

---

## 0. Før du starter — adgang

- [ ] **GitHub.** Repoet [ERN-Studios/ERN-Roblox-Horror](https://github.com/ERN-Studios/ERN-Roblox-Horror) er offentligt, så du
  kan læse det uden adgang. For at pushe skal ejeren gøre dig til collaborator. Arbejd på din egen branch, fx `level4/<emne>`,
  og lav pull requests. Push aldrig direkte til `main`, og force-push aldrig.
  Den nyeste Level 4-kode ligger på branchen `claude/trello-20260921`. `main` har en ældre udgave, indtil ejeren merger
  branchens pull request. Tag din branch fra `claude/trello-20260921`, eller fra `main` efter merge.
- [ ] **Roblox Studio.** Du skal have redigeringsadgang til place `131311258779917` (universe `10559217407`), som ejes af
  gruppen **ERN Roblox Studios (1039373905)**. Ejeren giver den via en grupperolle eller som collaborator i Team Create.
- [ ] **DevAccess.** Level 4 åbner kun for spillere, hvis UserId står i `ALLOWED_USER_IDS` i
  [`ReplicatedStorage/DevAccess.ModuleScript.lua`](../ReplicatedStorage/DevAccess.ModuleScript.lua). Send dit UserId til ejeren.
  Listen giver også adgang til alle andre dev-kommandoer, så den ændres kun efter ejerens beslutning.
- [ ] **Værktøjer.** Du skal bruge Windows, Python 3.11+ og en officiel `luau`-binær fra
  [luau-lang/luau releases](https://github.com/luau-lang/luau/releases). Peg miljøvariablen `LUAU_BIN` på den binære.
  Synk-værktøjerne (§2.3) kræver Studio åbent på samme PC med Studios MCP-server (`%LOCALAPPDATA%\Roblox\mcp.bat`).

## 1. Regler, der ikke kan forhandles

1. **Studio er sandheden. Repoet er et spejl.** Mapperne svarer 1:1 til Explorer, og filerne hedder `Navn.ClassName.lua`.
   [`studio-sync-manifest.json`](../studio-sync-manifest.json) holder en sha256 og en status pr. script. Tjek altid, om
   Studio har ændret sig, før du redigerer (§2.3). Andre sessioner (ejeren, Claude, Codex) arbejder i samme place samtidig.
2. **Level 4 forbliver dev-only**, indtil hele kortets accept er opfyldt (§6). Ejerens regler:
   - `Routing.MaxLevel` forbliver 3 i
     [`Round Completion Routing`](../ServerScriptService/Round%20Completion%20Routing.ModuleScript.lua).
   - **Level 3 fortsætter aldrig ind i Level 4.** Det gælder også for udviklere (ejerens beslutning 23/9, markør
     `NO_LEVEL3_CONTINUE_20260923` i `GameManager`). Testen `tools/tests/test_no_level3_continue.py` fejler, hvis det kommer tilbage.
   - Lobbyen viser "coming soon" ved Level 4-porten for alle, også udviklere. Kun udviklere kan gå gennem den forseglede dør
     og bruge Level 4-stationerne. Level 4 må hverken annonceres eller slås til offentligt.
3. **Publicér ikke uden ejerens OK.** Når placen publiceres, går alt ud, også andres uafsluttede arbejde. `AGENTS.md` siger,
   at agenter skal publicere efter verificerede ændringer. Det gælder ikke Level 4-arbejde: aftal det med ejeren.
4. **Rør ikke fælles scripts uden aftale.** Det gælder især `GameManager`, `RoundUI`, `ZyntraMonetization`, `NoiseReporter` og
   `Round Completion Routing`. `RoundUI` er tæt på Luaus grænse på 200 lokale variable i main chunk. Kommentarerne i
   scriptet og `CLAUDE.md` siger "præcis på grænsen"; en optælling 23/9 fandt cirka 188. Læg ny tilstand i en
   `do ... end`-blok, og kør kompileringstjekket (`tools/studio_compile_probe.luau`) efter hver ændring.
5. **Navne og attributter er kontrakter** ([kontrakten](LEVEL4_CONTRACTS_2026-09-21.md) §5–6). GameManager, controllerne og
   testene finder ting ved navn. Ændr `Configuration.Body` og lad dørbredder og passager blive afledt af den. Hardcode
   aldrig en dørbredde; adapteren asserter den.
6. **Budgetterne er hårde asserts.** Højst 12 dynamiske lys, alle uden skygge, og højst 12.000 descendants i verdenen.
   Overskrides de, afbryder Round Adapter bygningen. Alle lys skal gennem `light()` i World Builder, som tæller dem.
   Loftpanelerne er Neon-flader, ikke lys.
7. **Kun gruppeejede assets.** Alle id'er skal ejes af ERN Roblox Studios, ellers virker de ikke i spillet. Alt, der skal
   erstattes af art, har attributten `Level4_Placeholder = true`. En søgning på den er hele listen.

## 2. Kom i gang

### 2.1 Start en Level 4-runde i Studio

Start Play. Kør dette i **Server**-konteksten (kommandolinjen i serverens datamodel):

```lua
workspace:SetAttribute("Level4DevEnabled", true)   -- er true som standard; false er nødstop
workspace:SetAttribute("Level4Seed", 101)          -- valgfrit: >= 1 låser kortet, 0/negativ = tilfældig
print(game:GetService("ServerStorage").Level4DevStart:Invoke())
```

`Invoke()` returnerer `true`, eller `false` med en af årsagerne `RESERVED_SERVER`, `DISABLED`, `BUSY`, `NOT_DEVELOPER`
(nogen i sessionen er ikke på DevAccess) eller `NO_PLAYERS`. I lobbyen findes også Level 4-stationer, der kun lukker
udviklere ind. Seeds `101` giver varianten CLOSE og `202` giver TERRACE. Begge er spillet igennem.

### 2.2 Kør testene

I Studio, mens en Level 4-runde står:

```lua
local Suite = require(game:GetService("ServerScriptService")["Level 4 Systems"]["Level 4 Test Suite"])
local result = Suite.RunAll()
print(result.Text) print("PASSED:", result.Passed)   -- RunAll returnerer en tabel, så print den ikke direkte
```

Offline, uden Studio (PowerShell):

```powershell
$env:LUAU_BIN = "C:\sti\til\luau.exe"
python tools/tests/test_level4_plan.py            # den rigtige plangenerator over 68 seeds + lys-spejlet + megastruktur-afstande
python tools/tests/test_level4_neighbour_brain.py # Neighbourens tilstandsmaskine
python tools/tests/test_no_level3_continue.py     # Level 3 fortsætter aldrig til 4
```

Offline-grøn er ikke det samme som Studio-grøn. Testene bruger en falsk motor, så kør altid en rigtig runde og læs
konsollen, før du kalder noget verificeret.

### 2.3 Synk mellem Studio og repo

```powershell
python tools/pull_source_from_studio.py --audit   # Studio -> repo: hvad har ændret sig? Kør det FØR du redigerer
python tools/pull_source_from_studio.py           # hent ændringerne; springer KUN filer over, som record_pending_push.py har sat i kø

python tools/record_pending_push.py               # repo -> Studio: sæt dine ændrede filer i kø
python tools/push_repo_to_studio.py --audit       # sammenlign med live Studio uden at skrive
python tools/push_repo_to_studio.py               # skriv (compare-and-swap + kompilering)
```

- **Pas på med `pull`:** en lokal ændring, du ikke har registreret med `record_pending_push.py`, bliver overskrevet uden
  advarsel, hvis samme script også er ændret i Studio. Kør `record_pending_push.py`, før du puller.
- Skrivning til Studio sker med `ScriptEditorService:UpdateSourceAsync`. Rå `.Source`-skrivning efterlader LocalScripts med
  forældet bytecode.
- En **KONFLIKT** betyder, at en anden har ændret scriptet i Studio. Flet deres ændring ind. Brug aldrig
  `--overwrite-conflicts` i blinde, og brug heller aldrig `pull --force` på filer, der venter på push.
- **Nye scripts** kan ikke pushes af værktøjerne. Brug `python tools/install_new_scripts.py --dry-run "<spejlsti>"` og
  derefter uden `--dry-run`. Opret afhængigheder først (kontrakten §1).
- Arbejder du hellere direkte i Studio, så gør det, men spejl til repoet bagefter (`pull`) og commit afgrænset.
- **Team Create:** hvis Collaborative Editing er slået til, ligger dine script-ændringer som kladder, indtil du committer dem
  i Studio. Værktøjerne læser `.Source` og ser dem ikke før da.

## 3. Hvor koden ligger

| Script | Rolle |
|---|---|
| [`Level 4 Systems/Level 4 Configuration`](../ServerScriptService/Level%204%20Systems/Level%204%20Configuration.ModuleScript.lua) | Tal, navne og farver til tuning: `Body` (hvoraf døre, trapper og agent afledes), gader, grunde, mål, husstater, Neighbour-tuning, budgetter, `Megastructure` og `Lighting`. Ingen adfærd. Klientscriptene hardcoder dog verdens- og mappenavnene (`Level 4 Generated World`, `Level 4 State`, `Level 4 Remotes`), og World Builder og Neighbour Controller har stadig enkelte egne tal og farver |
| [`Level 4 Plan Generator`](../ServerScriptService/Level%204%20Systems/Level%204%20Plan%20Generator.ModuleScript.lua) | **Ren funktion** fra seed til plan. 3 håndlavede varianter (TERRACE / CRESCENT / CLOSE), 11 grunde, gadenet med løkke og genvej, validering og en `PlanHash`. Den bruger sin egen Park-Miller-strøm: tilføjer du et træk før variant-trækket, skifter alle seeds variant |
| [`Level 4 World Builder`](../ServerScriptService/Level%204%20Systems/Level%204%20World%20Builder.ModuleScript.lua) | Bygger verdenen af Parts ud fra planen: huse, interiører, signaler, anomalier, finale, grænse, patruljepunkter og ankomstslicen (§5). Returnerer det manifest, adapteren validerer |
| [`Level 4 Round Adapter`](../ServerScriptService/Level%204%20Systems/Level%204%20Round%20Adapter.ModuleScript.lua) | Rundens livscyklus: dev-assert, seed, isolering af Level 1-entity, bygning, validering, budgetter, start af controllerne og oprydning. Ved fejl: `Level4_Phase = ERROR` og `Level4_Error` |
| [`Level 4 Objective Controller`](../ServerScriptService/Level%204%20Systems/Level%204%20Objective%20Controller.ModuleScript.lua) | 3 signaler i fri rækkefølge, derefter 3 kontroller i rækkefølge ved busstoppets skab, 6 s advarsel og udgang. Husstaterne SAFE / WARNED / DANGEROUS og `IsSheltered` |
| [`Level 4 Neighbour Brain`](../ServerScriptService/Level%204%20Systems/Level%204%20Neighbour%20Brain.ModuleScript.lua) | **Ren** tilstandsmaskine: PATROL / INVESTIGATE / SEARCH / ALERT / CHASE / RETURN (testet offline) |
| [`Level 4 Neighbour Controller`](../ServerScriptService/Level%204%20Systems/Level%204%20Neighbour%20Controller.ModuleScript.lua) | Rig af Parts flyttet med CFrame, PathfindingService, sigte med raycast, hørelse via `NoiseRegistry` og angreb der dræber med ét slag |
| [`Level 4 Test Suite`](../ServerScriptService/Level%204%20Systems/Level%204%20Test%20Suite.ModuleScript.lua) | `RunPlanChecks` / `RunBrainChecks` / `RunWorldChecks` / `RunAll` |
| [`Level4Generator`](../ServerScriptService/Level4Generator.ModuleScript.lua) | Tynd bro, som GameManager kalder (`LEVEL_GENERATORS[4]`) |
| [`Level4GateAccess`](../ServerScriptService/Level4GateAccess.Script.lua) | Lader DevAccess-avatarer gå gennem den forseglede Level 4-dør i lobbyen |
| [`Level 4 Objective UI`](../StarterPlayer/StarterPlayerScripts/Level%204%20Objective%20UI.LocalScript.lua) | HUD: signaler, beacon, husadvarsler og trusselslinjen |
| [`Level 4 Lighting Controller`](../StarterPlayer/StarterPlayerScripts/Level%204%20Lighting%20Controller.LocalScript.lua) | Rolig og farlig lysgradering, inkl. placens `Atmosphere`. Gendanner alt ved exit. Talværdierne er **kopieret** fra `Configuration.Lighting`, fordi en LocalScript ikke kan require et servermodul: ret begge, ellers fejler spejltesten |

Tilstand til klienten: `ReplicatedStorage."Level 4 State"` (attributter) og `ReplicatedStorage."Level 4 Remotes".ClientEvent`.
`applyBaselineReplicatedState` i Round Adapter er listen over attributterne på state-mappen. Husene bærer deres egne
(`Level4_HouseState`, `Level4_HouseStateEndsAt`, `Level4_LotId`, `Level4_Zone`), og Workspace har `Level4SignalProgress`,
`Level4BeaconUnlocked`, `Level4ExitOpen` m.fl. Verdenen
hedder `Workspace."Level 4 Generated World"`, bygges ved `WorldOrigin (12400, 24, 0)` og rives helt ned mellem runder. Du
kan derfor ikke placere ting i den med hånden: alt skal bygges af World Builder.

## 4. Sådan spilles en runde i dag

1. **Ankomst.** Partyet placeres på `ElevatorSpawn` i servicepassagen med front mod øst og ryggen til en rulleport 24 studs
   mod vest. Loading-coveret løftes ved første tick af en nedtælling på 7 s. Derefter glider portens `DoorL`/`DoorR` til side
   bag partyet; ingen går gennem porten. GameManager kræver kompatibilitetsmarkørerne `Elevator` (med `DoorL`/`DoorR`),
   `ElevatorSpawn` og `MazeStart`. Omdøb dem ikke.
2. **Briefing:** *"Investigate three residential signals. Restore the extraction beacon. Stay quiet."*
3. **Tre signaler, ét pr. zone, i valgfri rækkefølge.** Signaltyperne er FacadeCompare (en referencetavle på verandaen),
   Broadcast (en indendørs CRT) og Sample (en målepæl i forhaven). Zone 1 er tilgivende: intet hold, 16 studs rækkevidde og
   ingen støj. De andre har 1,2 s hold og 10 studs rækkevidde, og **de larmer** (`relay` i NoiseRegistry). Hver signal-husstand
   har en visuel anomali (ExtraWindow, WrongNumber, ReversedMailbox eller DrawnCurtains), og der er lokkeanomalier på
   pyntehuse. Ingen kode kræver, at spilleren finder anomalien.
4. **Beacon.** Ved 3/3 låses tre kontroller op ved busstoppets skab. De skal bruges i rækkefølge, med 1,5 s hold, og
   hver af dem larmer. Derefter kommer 6 s advarsel, udgangsporten glider op, og spilleren undslipper ved at gå ind i
   `EscapeTrigger`.
5. **Husstater.** Efter 24 s ro kan planlæggeren advare et hus (WARNED, 12 s) og gøre det farligt (DANGEROUS, 35 s). Højst
   2 huse kan være usikre ad gangen, og hver zone har altid mindst ét sikkert hus. Introhuset er altid sikkert. Et
   **SAFE** hus skjuler dig: Neighbouren kan hverken se eller slå dig der. En jagt, der allerede er i gang, fortsætter dog
   mod din faktiske position inde i huset i op til 3,5 s (1,19 s hvis du smyger dig), før den går over i SEARCH.
6. **The Neighbour** patruljerer gader, postkasser og verandaer med 7 studs/s. Hører den støj (inden for 110 studs × lydstyrke,
   hvor `relay` ≈ 148), går den til **støjens** position, ikke spillerens. Ser den en spiller tæt på (højst 42 studs, synsvinkel
   110°, fri sigtelinje), telegraferer den ALERT i 1,1 s og jager derefter med 24 studs/s. Spillerens sprint er 26 studs/s.
   Taber den kontakten i 3,5 s (1,19 s hvis spilleren smyger sig), søger den og vender så hjem. Et slag dræber
   (0,5 s windup), og nyligt genoplivede spillere har 1,5 s grace.

## 5. Nyt 23/9: ankomstslicen (første udgave af den nye retning)

Commit `5fe0503`. Den er bygget omkring ankomsten og langs vestkanten, så skala og stemning kan vurderes, før den bredes
ud. `SouthTerrace` står bag husene på sydsiden fra x = -24 til 340 (Main Street går til 420), `NorthCanyon` dækker hele
West Avenue, og loftet og lysgraderingen gælder hele kvarteret. Østkanten og nordsiden af Back Lane har endnu ingen facader.

- **To høje facadegrupper** (`Configuration.Megastructure.Groups`) gør servicepassagen til en kløft:
  - Syd: `SouthCanyon` plus `SouthTerrace`, som ligger bag husene på sydsiden.
  - Nord: `NorthCanyon` langs West Avenue plus `ArrivalWall` bag ankomstporten.
  - Højden er 23 etager, op til et loft i 300 studs. Hver blok har én **solid kerne**, der kolliderer og stopper stråler.
    Alt på facaderne er ren pynt (`CanQuery = false`).
- **Facademodulet** på 24 × 13 studs gentages op ad facaden. De nederste etager har altan, rækværk, dør, vinduer og
  karnapper med gavl. Mellemetagerne har færre dele, og de øverste etager er ét vinduesbånd pr. modul. Hvert 7. vindue er tændt.
- **Én overdækket bro** over kløften (`Megastructure.Bridge`) på etage 3. Den er dekorativ og kan ikke nås.
- **Kunstigt loft:** en plade på 2048 × 2048 med 70 Neon-lyspaneler og fire fjerne vægge, så horisonten er dis og ikke himmel.
- **Lys:** en indendørs gulgrøn dis. Placen har et `Atmosphere`, der tilsidesætter alle `Fog*`-værdier og slørede loftet ud i
  himlen. Derfor graderer Lighting Controller nu også `Atmosphere` og gendanner den ved exit.
- **Vagt:** `test_level4_plan.py` §6 fejler, hvis en blok står på en gade, en grund med have, et landmærke eller ankomsten.
- **Målt i Studio** (seeds 101 og 202): world checks 66/66, 3.234 descendants, 10 dynamiske lys og 0,83 ms server-heartbeat.
  Klient-FPS er **ikke målt**, fordi Studio låser et ufokuseret vindue til 15 FPS. Mål i forgrunden og på lav grafik.

## 6. Hvad mangler før Level 4 kan åbnes

Fra Trello-kortets punkt 8 og kontraktens §13. Alle 10 punkter på kortets tjekliste er åbne.

**Gameplay og tests**
- [ ] En hel runde solo og i fuldt hold, uden betalt udstyr, på alle tre varianter.
- [ ] På PC og touch skal man kunne læse advarsler, undersøge, gemme sig, bruge udstyr og nå i mål.
- [ ] Død, genoplivning (Emergency Re-entry), spectate, exit til lobbyen og belønninger i Level 4 specifikt, uden dobbelte
  belønninger. Belønningssystemet tæller i dag kun Level 1–3 som "cleared", så Level 4 giver tokens, men ingen badge
  og ingen `LevelsCleared`.
- [ ] Navmesh med `AgentRadius 2.7` er ikke verificeret. Står `Level4_NeighbourPathStatus` på `FAILED`, så sænk radius
  **kun til pathfinding** og behold kropsmålene.
- [ ] Spilletid (målet er 8–12 min, ikke et krav), jagttempo, funnel-målinger og performance på mobil.
- [ ] Beslut sammen med ejeren, hvordan Level 4 skal nås, når det åbner. Level 3 fortsætter ikke dertil i dag.

**Art og lyd**
- [ ] **The Neighbour:** model, rig og fem animationer (Idle/ALERT, Walk, Search, Chase og Attack med markøren `Contact`),
  se kontrakten §6 og [MODEL_HANDOFF.md](../assets/level4/neighbour/MODEL_HANDOFF.md). Riggen i dag er Parts, der poseres
  med CFrame. Et skinned mesh kan ikke bare sættes ind: controllerens posering skal tilpasses den leverede hierarki.
  `Level4_NeighbourAnimation` og `AttackSerial` publiceres allerede, men intet læser dem.
- [ ] **Facade-, bro- og loftmoduler:** `Level4FacadeBalcony`, `Level4FacadeBay`, `Level4FacadeFlat`, `Level4BridgeSpan` og
  `Level4CeilingPanel`, se [asset-bestillingen](CODEX_ASSET_ORDER_2026-09-23.md) §3.2. Udvid facaderne ud over ankomsten,
  når slicen er godkendt, og giv husene mere dybde (gavle, verandaer, karnapper).
- [ ] **Teksturer:** de fem id'er i [materials/README.md](../assets/level4/materials/README.md) er klar, men ikke i brug.
  A/B-test dem i spillerhøjde og på lav grafik.
- [ ] **Lyd:** alle slots i kontrakten §8 er tomme. Koden sender kun cue-navne, som `HouseWarned` og `HouseDangerous`.
  Alle kritiske advarsler skal også have en visuel side.
- [ ] Loading-coveret bruger Level 1's grønne palet, fordi `RoundUI.LOADING_PALETTES` mangler en `[4]`-post. Tilføj den i
  den eksisterende tabel (det er ingen ny top-level local), og kør kompileringstjekket bagefter.

Aftal med ejeren, om Codex stadig leverer model, animationer, moduler og lyd fra bestillingen, eller om du selv laver dem.

## 7. Kendte fejl og faldgruber (kontrolleret mod koden 23/9)

- **Fodtrin høres aldrig i Level 4.** `NoiseReporter` rapporterer kun på level 1 og 2
  (`NoiseReporter.LocalScript.lua` ved `level ~= 1 and level ~= 2`), og intet i Level 4 dræner `Remotes.ReportNoise`. Den eneste
  støj kommer fra signaler og skabskontroller. Kontraktens testopskrift ("sprint i det åbne" udløser INVESTIGATE) virker derfor ikke.
- **Et WARNED hus skjuler dig ikke længere.** `IsSheltered` kræver `HouseState == "SAFE"`, men UI'et siger "LEAVE WITHIN 12s".
  Beslut, hvad der er meningen, og få kode og tekst til at stemme overens.
- **Neighbouren kan gå gennem vægge**, når pathfinding fejler. Rigget har `CanCollide = false`, og uden waypoints går den lige
  mod målet (`if not target then target = session.Goal end` i Neighbour Controller).
- **Riggets højde er fast.** Kun X og Z ændres. Regnet på papir, ikke målt: fødderne svæver cirka 3 studs over vejen, og
  fordi `AttackRange 5.2` er en 3D-afstand, bliver den vandrette rækkevidde kun cirka 2,3 studs. Mål begge dele i en runde.
- **SEARCH efter INVESTIGATE sigter mod `LastSeenPosition`**, ikke mod støjen. Hvis ingen er set endnu, er det spawn-punktet.
- **Planlæggeren kan advare det hus, der har et uafsluttet signal.** Prompten virker stadig, men huset er ikke længere ly.
- **Spillere, der joiner sent, får ikke respawn-grace.** `CharacterAdded`-hooks forbindes kun for spillere, der er med ved start.
- **Timere bruger `os.clock()`**, som er CPU-tid i Studios serverdatamodel, mens UI-nedtællingen bruger servertid. I Studio kan
  de to være uenige.
- **Debug-hjælpere virker ikke fra kommandolinjen.** `require` fra kommandolinjen eller `execute_luau` giver en separat
  modulinstans, så `DebugCompleteSignal` og lignende ser ingen session. Læs instanser og attributter i stedet.
- **Forældede kommentarer.** `QuietContactMultiplier` påvirker kun jagtens kontakt, ikke hørelsen. `DoorWaitSeconds` åbner
  ingen døre (husene har ingen dørplader), den omdirigerer kun. `Level4DevEnabled` beskrives som opt-in, men GameManager
  sætter den til `true` ved boot. Den reelle lås er DevAccess for alle i partyet.
- **`Configuration.Megastructure` mangler i `table.freeze`-listen** nederst i Configuration, som de andre tabeller står i.
- **README.md siger stadig "There is no Level 4".** Kontrakten og dette dokument er de gyldige kilder.
- **Kodegrafen (`graphify-out/`) er fra før Level 4** og kender det ikke. Brug grep.

## 8. Hvor du kan starte

1. Få adgang (§0). Start en runde på seed 101 og 202 og kør `RunAll()`, så du ser udgangspunktet med egne øjne.
2. Gå ankomstslicen igennem i spillerhøjde, og aftal med ejeren, om retningen holder, før den bredes ud over kvarteret.
3. Ret de gameplay-fejl i §7, der ændrer, hvordan level'et spilles (fodtrin, WARNED-ly, væg-gang), før art lægges på.
4. Integrér The Neighbour-modellen og animationerne, når de findes, og derefter moduler, teksturer og lyd.
5. Gennemgå §6's accept, og flyt først kortet til Done, når alt er opfyldt.

Skriv resultater, mål og beslutninger på [Trello-kortet](https://trello.com/c/Y2xXThBN), så ejeren og de andre kan følge med.
