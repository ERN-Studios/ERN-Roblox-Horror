# FULD HANDOVER — Game DEV / Backrooms: Stay Quiet / Level 5

**Skrevet 27. september 2026, Europe/Copenhagen. Læs denne fil først i en ny chat.**

Dette er en samlet, operationel overdragelse af denne chats krav, beslutninger, leverancer, kendte fejl og næste arbejde. Det er ikke en ordret chateksport. Den erstatter ikke en ny aflæsning af live Roblox Studio. Alle statusangivelser nedenfor er senest verificerede observationer, ikke en garanti for, at andre udviklere ikke har ændret noget siden.

## 0. Det vigtigste på ét minut

- Spillet er **Backrooms: Stay Quiet**, repo **ERN-Studios/ERN-Roblox-Horror**. Arbejdet i denne chat handler primært om **Level 5 — The Indoor Suburbs**.
- **Roblox Studio er den autoritative kilde.** GitHub og Trello er dokumentation/spejl. Upload aldrig en gammel repo-version eller backup over aktuelle Studio-ændringer.
- Senest verificerede publicerede version: **v2143**, place **131311258779917**, universe **10559217407**, publiceret **2026-09-26T21:09:18.148Z**.
- Level 5 har otte sektioner **A–H**, syv rigtige puzzles/sliding gates, en passiv **Window Watcher / Vindueskiggeren**, et stort boligatrium i F og 48 par loftsøjne i H.
- **Kun A–G** får blackout. Gate 1–6 starter/forlænger det; gate 7 ind i H gør ikke. Fem sekunders gradvis flimren/slukning efterfølges af 60 fulde sekunders mørke. H og den sidste nedgang beholder lys.
- **Ingen huslamper, ingen HOUSE CLUE-skilte, ingen mørk full-screen baggrund bag padlock-UI.** PC-markøren skal straks frigives, når padlock åbnes. Disse rettelser var publiceret før den seneste lydopgave.
- **Seneste uafsluttede brugeropgave:** gennemgå alle sektioner og puzzles for spilbarhed, brug ElevenLabs til nødvendige lyde, og importer dem, inklusive Window Watcher.
- **12 færdige WAV-lyde er genereret og teknisk valideret. 48 original-takes er bevaret. 0 nye lyde er uploadet til Roblox. Lydkoden er kun et testet udkast; den er ikke installeret eller publiceret.** Generér ikke lydene igen uden grund.
- Frisk, komplet gennemspilning blev blokeret af indlæsnings-/UI-timeouts. Kodekontrol af alle syv puzzles passer. **H mangler stadig completion/sliding-gameplay**, og performance/multiplayer/fysiske mobilenheder er ikke godkendt.
- Seneste arbejdscommit før denne handover: **e4bd203cd0e6a543731aa442d98839431f6512c5**, pushet til **codex/level5-window-watcher**, **PR #10 åben**. Den commit tilføjer lydfiler, udkast og QA-dokumentation, ikke produktionsændringer.
- Sidste komplette friske script-export: **197 scripts**, Source/editor ens; **193 eksisterende matchede v2143**, **4 samtidige Level 6-scripts blev bevaret**. Sidste native place-backup er ældre og omfatter ikke nødvendigvis disse nye ændringer.

## 1. Hvad den nye chat skal gøre først

1. Læs denne fil færdig. Giv brugeren en kort dansk kvittering med den faktiske status; hævd ikke, at lydene allerede er i spillet.
2. Find projektmappen og repoet ud fra stierne nedenfor. Læs repoets **AGENTS.md** før ændringer. `sources/` under projektroden er read-only referencefiler.
3. Kontrollér `git status`, branche, seneste lokale/remote historie og PR #10. Bevar alle samtidige ændringer. Ingen hard reset, force-push eller blind checkout/pull over beskidt arbejde.
4. Find den aktuelle Studio-session med de tilgængelige Roblox Studio-værktøjer. Kontrollér place/universe og om den er Edit/Play. Session-ID'er fra den gamle chat må ikke antages stadig gyldige.
5. Læs relevant **live Source og editor-tekst**. Sammenlign med sidste checkpoint; forskelle fra andre udviklere er ikke fejl, der må rulles tilbage.
6. Kontrollér om Studio og den autoriserede Creator Dashboard-browser nu reagerer. Tidligere blev brugeren spurgt, om Mac'en var låst/i dvale; der kom ikke et bekræftet svar. **Antag ikke, at den var låst**, eller at åbning alene løser problemet.
7. Fortsæt den uafsluttede lyd-/QA-opgave i rækkefølgen i afsnit 10. Brugerens nye beskeder kan justere scope. Denne handover er ikke en ordre om at genbygge alt eller straks implementere en ny hovedentity.

### Læserækkefølge, så den nye chat ikke bliver langsom igen

Læs kun disse kompakte dokumenter først, relativt til repoet:

1. `AGENTS.md`
2. `docs/LEVEL5_AUDIO_QA_2026-09-27.md`
3. `artifacts/level5-audio-qa-20260927/qa/puzzle-source-audit.md`
4. `artifacts/level5-audio-qa-20260927/qa/audio-draft-integration.md`
5. `artifacts/level5-audio-qa-20260927/qa/startup-failure-readonly-analysis.md`
6. `docs/LEVEL5_EXIT_CEILING_EYES_2026-09-26.md`
7. `docs/LEVEL5_SURFACE_UI_FIXES_2026-09-26.md`
8. `docs/LEVEL5_RESIDENTIAL_ATRIUM_2026-09-26.md`

Læs derefter de konkrete live scripts og de fire nye lydudkast. Åbn store JSON-exports, historiske logs, billedsamlinger og ældre handovers **målrettet efter behov**, ikke alle på én gang. Gamle underagenters hukommelse, tool-celler og browserhandles overlever ikke nødvendigvis en ny chat.

## 2. Identitet, stier og eksterne links

### Absolutte lokale stier på denne Mac

```text
PROJECT_ROOT = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e
REPO         = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-window-watcher-repository
AUDIO_TASK   = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-audio-qa-20260927
HANDOVER_DIR = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-full-handover-20260927
LUAU         = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-build/tools/luau/luau
LUAU_COMPILE = /Users/zeanjuul4/.codex/.chatgpt-projects/g-p-6a72501f4e648191a4bd04f306d6606e/output/level5-build/tools/luau/luau-compile
BLENDER      = /Applications/Blender.app/Contents/MacOS/Blender
```

Navnene PROJECT_ROOT/REPO/AUDIO_TASK er dokumentforkortelser, ikke nødvendigvis eksisterende shellvariabler. Brug korrekte quotes omkring stier med mellemrum. Hvis en ny lokal opgave får en anden cwd, kan ovenstående stadig læses via absolutte stier. Hvis filsystemet er et andet, brug recovery-pakken eller en ny separat clone; overskriv ikke en eksisterende checkout.

### Roblox / GitHub / Trello / ElevenLabs

| Emne | Værdi |
|---|---|
| Place | `131311258779917` |
| Universe / experience | `10559217407` |
| Kendt asset-ejer | ERN Roblox Studios, gruppe `1039373905`; verificér den aktuelle ejer i upload-UI |
| Udvikler-preview | `Mikkelczar` og `LaverSneglen`, via eksisterende allowlist/queue |
| Repo | https://github.com/ERN-Studios/ERN-Roblox-Horror |
| Aktiv review-branche | `codex/level5-window-watcher` |
| PR | https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/10 |
| PR-base | `codex/level5-qa-exit-polish` (stacked PR; ikke antag main) |
| PR-titel | Build Level 5 neighbourhoods, residential atrium, puzzles and Window Watcher |
| Level 5 Trello-kort | https://trello.com/c/Y2xXThBN |
| Trello-board | BACKROOMS: STAY QUIET – Development |
| Trello-status | In Progress, `complete=false` |
| Trello card ARI | `ari:cloud:trello::card/workspace/6a9807517a71aa833c5dedb8/6aa288c6f9cfb6b3f705051e` |
| ElevenLabs-lydflow | https://elevenlabs.io/app/flows/jjheL5GNVJdYYNrfs1E8 |
| Flow-ID / model | `jjheL5GNVJdYYNrfs1E8` / `eleven_text_to_sound_v2` |
| Creator Dashboard lydside | https://create.roblox.com/dashboard/creations?activeTab=Audio |

Trello blev sidst opdateret 27/09 med den blokerede QA-/lydstatus og commit e4bd203. Det er ikke en kvittering for lydimport. Seneste browser havde et upload-handoff på denne lydside, men en ny chat skal selv finde den aktuelle fane. LaverSneglen i topbaren er login-navnet, ikke nødvendigvis asset-ejer; kontrollér den valgte gruppe.

## 3. Brugerens krav og vedtagne beslutninger

### Arbejdsform

- Brugeren ønsker, at agenten **gør arbejdet og tester det**, ikke blot foreslår eller erklærer sig klar. Undgå at spørge om rutinevalg, der allerede er autoriseret.
- Kommunikér kort, konkret og primært på dansk. Skeln mellem genereret, importeret, installeret, testet, committed, pushet og publiceret.
- Vær kritisk som Roblox-udvikler og QA. Ingen opdigtede passes, ingen mock-tests præsenteret som native spiltest, ingen udokumenteret multiplayer-/mobilgodkendelse.
- Brugeren tester også selv. Afklar kun samtidige tests, hvis de faktisk konflikter; gamle stop var tidligere brugerens egen test, men er ikke bevis for nyere timeouts.
- Følg den stående publiceringspræference efter verificerede ændringer. Publicér ikke en kendt materiel blocker, og genstart ikke aktive servers uden særskilt grund/autorisation.

### Visuelt mål for Level 5

- Backrooms/liminal **indendørs boligkvarterer**: almindelige hjemmeelementer i umulig skala, tætte høje husstakke, varierende højder, forskudte altaner, broer, trapper, mørke vinduer og enorme fælles lofter.
- Større sektioner skal også være **tættere og mere detaljerede**. Ikke kæmpetomme rum med få spredte huse. Nogle åbne områder er okay, når det giver rumlig mening.
- Ruten skal skifte side og højde mellem sektioner. Man må ikke bare gå ligeud til næste dør hele vejen.
- Tykke overlappende ydervægge/lofter/kanter: intet udelys gennem hjørner eller sprækker.
- Rigtige genererede teksturer frem for flade Roblox-standardfarver. Bevar plaster, blomstertapet, træbeklædning, finer, tagsten, tæpper og **græs**. Grønne udendørs-lignende flader skal være græs, ikke grønt tæppe.
- Nogle huse skal opleves som komplette boliger. Sparsom, men gennemført indretning: sofa, stole, bord, TV/CRT, skabe. Subtilt forkerte/sammenvoksede stole og borde er ønsket; overfyldte rum er ikke.
- **Ingen individuelle små huslys**, hverken inde eller ude. Husvinduer skal være mørke/tintede. Fælles loftslys må variere i varme/lysstyrke, og nogle må være slukket.
- Høje uhyggelige vægtegninger blev senere **udtrykkeligt erstattet af mørk mycelium/skimmel**, som spreder sig højt og bredt fra gulv, hjørner og forskellige sømme. Flere forskellige former; ægte transparent baggrund uden rektangler. Genindfør ikke de gamle tegninger.
- Exit-retning skal vises med imagegen-pile malet på fladerne. Ingen ny skilt-skov.
- **NO HOUSE CLUES / HOUSE CLUE-skilte uden på husene.** Indendørs selve puzzle-sporene skal blive.
- Flimrende teksturer ved små kameravinkelskift var en konkret klage. Det blev behandlet som konkurrerende/overlappende flader; bevar de publicerede surface-fixes, og kontrollér visuelt igen ved nye geometriændringer.

### Referencerne og F

- Brugeren var først begejstret for miljøet i Window Watcher-konceptbilledet. Det førte til en tidligere F-version med 33 nested houses og flere carpet courts.
- Derefter sendte brugeren **Foto 1 og Foto 2**: creme/hvide boligfacader omkring en smal, dyb indendørs skakt; meget høje vægge, hvide gelændere, tæppeafsatser, forskudte små altaner, broer og trapper mellem mange etager; ét fælles fluorescerende loft.
- **Den nyere F-boligatriumversion er gældende.** Genskab ikke de gamle brede courts, det gamle 156-stud-loft eller gammel F-rute fra ældre dokumenter.
- Fotos viste huslamper, men brugerens udtrykkelige krav om ingen huslys har forrang. Konceptbilleder er inspiration, ikke tilladelse til at genindføre lamper.
- Lore: Backrooms' oprindelse er ukendt. **Zyntra er forskerne, ikke skaberen af stedet.**

### Gameplay og entities

- Window Watcher er en **passiv sekundær entity**, ikke den fremtidige hovedentity. Ingen jagt, skade eller combat var del af dens nuværende levering.
- Hun skal kunne vise sig bag rigtige vinduer i alle sektioner, i mindst én spillers omtrentlige synsfelt og gerne flere grupperede spilleres.
- Hun har lysende hvide øjne. Når blikket nærmer sig hende, kommer en subtil pulserende POV/FOV-effekt. Tilfældig forsvindingstærskel afhænger af afstand og samlet kiggetid.
- Hver sektion før næste gate har en nem puzzle, omtrent som første farvepuzzle, ikke eskalerende urimelig sværhedsgrad. Forkerte svar giver gratis nye forsøg.
- Sliding gates blokerer sektionerne. Serveren afgør progression og åbner fælles for spillerne.
- Den sidste outage-ændring begrænser blackout til A–G; H er den oplyste exit-sektion med **mange par loftsøjne**, forskellige højder, afstande, størrelser og vinkler, som følger spillerne.
- Seneste brugeropgave kræver **ElevenLabs-lyde og faktisk import**, også for Window Watcher. Den er stadig uafsluttet.

## 4. Versionshistorik og hvad der er overhalet

| Checkpoint | Indhold | Status / reference |
|---|---|---|
| v2036 | Udvidelser, møbler, huslys fjernet, skimmel erstatter tegninger | `LEVEL5_FURNISHING_2026-09-24.md`, `LEVEL5_MOLD_2026-09-24.md` |
| v2104 | Tidligere QA og exit-pile/polish | `LEVEL5_QA_2026-09-25.md`; ejeren publicerede, verificeret i Studio-log |
| v2121 / v2123 | Meshy/Blender-rig, publicerede animationer, white-eye mask; derefter gaze/FOV | `LEVEL5_WINDOW_WATCHER_2026-09-25.md` |
| v2128 | Større A–H, første puzzle, syv fysiske gates, Watcher i alle sektioner | `LEVEL5_EXPANSION_2026-09-26.md` |
| v2129 | Gradvis 5 s strømfejl + 60 s blackout | `LEVEL5_OUTAGE_2026-09-26.md` |
| v2133 / b583d0c | Tættere kvarterer, offset-ruter, syv materialer, alle syv puzzles | `LEVEL5_DENSE_ROUTES_2026-09-26.md` |
| v2136 / 0563191 | F erstattet med smalt dybt boligatrium efter de to fotos | `LEVEL5_RESIDENTIAL_ATRIUM_2026-09-26.md` |
| v2139 / feb0b96 | Overfladeflimmer, PC-markør, gennemsigtig UI-backdrop, HOUSE CLUE fjernet | `LEVEL5_SURFACE_UI_FIXES_2026-09-26.md` |
| v2143 / cd2485d | 48 par exit-loftsøjne; H/chute undtaget fra blackout; gate 7 starter ikke outage | `LEVEL5_EXIT_CEILING_EYES_2026-09-26.md` |
| e4bd203, ingen ny place-version | QA-vurdering og 12 nye ElevenLabs-lyde med offline integrationsudkast | `LEVEL5_AUDIO_QA_2026-09-27.md` |

**Læs gamle dokumenter med dato/scope:**

- “Only first gate has a puzzle” er overhalet: alle syv har nu puzzles.
- “Only F has Window Watcher” er overhalet: 18 anchors dækker A–H.
- “No outage system” og “every gate starts outage” er begge historiske: nu A–G/gate 1–6, H exempt.
- “HOUSE CLUE paper beside the door” i dense-routes-dokumentet er overhalet og forbudt.
- F's 33-house courts / gamle canyon-udformning er overhalet af v2136.
- “Heartbeat” i v2123 betyder **kamerapuls**, ikke færdigimporteret lyd.
- Gamle `patches/`, `pending-studio-push`-flag og handoff drafts er ikke en deployment-kø.
- Nogle første runtime-observerrapporter er `INCOMPLETE`, selv om deres observerede del havde nul fejl. De må ikke omdøbes til PASS.
- `AUDIO_TASK/qa/elevenlabs-flow.json` og `audio-pipeline-notes.md` indeholder tidlige “not started” discovery-statusser; de er overhalet af generation-receipt og ready-manifest.

## 5. Aktuel map-/puzzleoversigt

Level 5-origin i adapteren er **Vector3(17000,24,0)**. Tabellen bruger **lokale** koordinater; tilføj origin ved Studio-positionering. Brug helst den aktuelle build-manifests world-space waypoints, ikke manuelt gættede punkter.

| Sektion | Rumtype og væsentlige kontroller | Gatecenter, lokal |
|---|---|---|
| A | Balcony Atrium, asymmetriske høje boligstakke, fire ground-level clue-huse; optional altaner | `(0,0,196)` |
| B | Low Eaves Arcade, lave overdækninger, skiftende sidegange og through-houses | `(88,0,456)` |
| C | Pastel Village, fire boligcourts og græs, tre spredte adressesporshuse; bredeste område | `(-120,0,936)` |
| D | Floral Terraces, street ved -12 samt promenader og trapper | `(120,0,1296)` |
| E | Domestic Labyrinth, gennemgående og nested hjem med lavere lofter og sving | `(-120,0,1596)` |
| F | Dybt boligatrium, etager -42..+28, boliger op til +70, fælles loft +84; main/clue/recovery-ruter | `(178,0,2076)` |
| G | Tilted Subdivision, 8/16-terrasser, skæve lukkede dekorationshuse, vestligt ground-level clue-hus | `(-65,0,2456)` |
| H | Quiet last-house court, loftsøjne, forskudt vestibule, pile og lukket nedgang | Ingen ottende puzzle |

F alene: **167 boliger, 62 enterable, 344 tintede ruder**. Hele seneste genererede verden: **29.928 descendants** mod en guard på **30.000**. Det er en instancegrænse, ikke en performancegodkendelse. Lydudkastet bruger lokale emitters uden for generated world.

### Puzzles — QA-facit, ikke spiller-UI

| Gate | Spillerens rigtige svar | Serverens indeks-array | Clue-hjem/read-position, lokal |
|---|---|---|---|
| 1 / A | RED, YELLOW, BLUE, GREEN | `1,2,3,4` | Fire hjem ved read-punkter `(-128,3,42)`, `(-128,3,156)`, `(128,3,42)`, `(128,3,156)` |
| 2 / B | LAMP, CUP, KEY | `2,4,1` | `ArcadeCrossLaneHome_1_0`, `(0,3,288)` |
| 3 / C | RED **2**, BLUE **6**, YELLOW **4** | `3,7,5` | `(-229,3,545)`, `(-140,3,715)`, `(145,3,909)` |
| 4 / D | UP, DOWN, UP | `2,1,2` | `FloralTowerHome_1_1_0`, `(125,3,994)` |
| 5 / E | 3:00, 9:00, 6:00 | `2,4,3` | `EastCrossLaneRoom`, `(100,3,1390)` |
| 6 / F | CH04, CH07, CH02 | `4,7,2` | `WestContinuousDwellings.TelevisionClueResidence`, `(-66,3,1743)` |
| 7 / G | RIGHT, DOWN, UP | `2,3,1` | `OuterGardenResidence_-1_2_0`, `(-232,3,2290)` |

**C's printed digits are 2/6/4, not 3/7/5.** Options begin with 0; the array values are indices. Read-positions are historical supported QA locations, not a new traversal pass.

Puzzle contracts: previous gate must be FullyOpen; valid alive Level 5 participant; server distance <=14 studs, unobstructed LOS, nonce, correct shape/range, session/rate checks. UI ~0.7 s submit debounce vs server ~0.65 s; session 120 s. Wrong answer does not consume resources. Physical door tween is **1.6 seconds**, leaves lose collision when both complete. Gate has `Unlocked`, `OpenReason`, `FullyOpen`; **server writes Unlocked before OpenReason**.

Normal use is real E/ButtonX prompt and real UI controls. Holding F is an allowlisted **developer bypass**, not evidence of puzzle playability. Holding L uses the normal lobby-return flow. Never count forced attributes, teleports through boundaries or bypassed gates as ordinary completion.

H: last-house entrance `(0,0,2584)`, descent `(0,0,2615)`, enclosed arrival around `(0,-29,2674.5)`. Architecture currently describes geometry-only/no-slide-or-completion. Do not give rewards or claim Escaped without implementing/reviewing the real completion contract.

**Preserved finale intention, not implemented:** the earlier owner brief describes an easy puzzle in a strangely assembled house opening a steep narrow downward passage, painted arrows at its entrance, walking through roughly the first 70%, then player-steerable sliding through the final ~30%, and completion on reaching the pitch-black end. The 70/30 split was an earlier working interpretation, not a tested contract. Keyboard/controller/touch steering and camera control were intended. This is separate from the seven installed gate puzzles. The old suggested house-light puzzle and exact slide speeds are historical proposals, not current approved implementation; later no-house-lights and H outage-exemption requirements take precedence. Preserve the vision for future completion work without claiming an eighth puzzle, slide controller, finale audio or reward trigger exists.

## 6. Assets and exact appearance contracts

### Seven current MaterialVariants

| Variant | Base / tile | ColorMap ID |
|---|---|---|
| Level5AgedPlaster | Plaster / 12 | `108985650994325` |
| Level5FloralWallpaper | Plaster / 8 | `102299936573476` |
| Level5PaintedSiding | WoodPlanks / 12 | `115748401620318` |
| Level5LawnGrass | Grass / 6 | `126776492995543` |
| Level5VeneerWood | Wood / 4 | `118880038763227` |
| Level5RoofShingles | Slate / 8 | `118077370167392` |
| Level5LoopCarpet | Fabric / 6 | `113909496202267` |

These are scoped MaterialVariants, not global material overrides. MaterialService objects are **non-script state**: source export alone cannot fully restore them. Source/provenance: `assets/level5/dense-materials-20260926/`.

Mold: eight colonies using `111130507669211` rising, `84997095468417` corner, `119550867817499` seam; sources in `assets/level5/mold20260924/`. Original 96-stud growth dimensions in old canyon docs are historical; F-carrier dimensions changed with later architecture. Preserve current live placement and backing-ray checks.

First colour clue images: red `129034114315469`, yellow `82053429341504`, blue `98028147005436`, green `73277763916471`. Sources in `assets/level5/colour-lock-20260926/`. Exit arrow assets/provenance: `assets/level5/qa20260925/`. Furniture assets: `assets/level5/furnishing20260924/`; successfully loaded replacement upholstery `132119936960491` supersedes its failed initial upload.

### Window Watcher / Vindueskiggeren

| Asset | ID / fact |
|---|---|
| Skinned Mesh | `138178192370575` |
| Base-color | `91091934459636` |
| White-eye emission mask v5 | `91743869995723` |
| WatchingIdle | `123386867650430`, 6 s |
| SlowWindowLean | `85635358459792`, 5 s |
| GlassTap | `85948818863545`, 4 s |
| Frozen GLB SHA256 | `cbf260ff36b8c7226f27271456eae6bf4db7fd266bdce82dda8b0eae7cbc051e` |
| Eye-mask SHA256 | `99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738` |
| Meshy image-to-3D task | `01a0d8e3-3fdd-752a-b810-ea9cace0266e` |
| Meshy rigging task | `01a0d8ec-0c4f-71fc-b513-af1e1d1e59b4` |

Permanent template: `ServerStorage.Level5WindowWatcher.WindowWatcherRig`, with sibling `Animations`. Source files: `assets/level5/window-watcher/` includes model.blend, model.glb/model.fbx, three animation FBXs, packed texture, compact 30 fps pose JSON, Meshy originals, provenance and Blender scripts.

Mesh has 11,862 triangles, 25 bones; no finger bones; normalized 1–4 influences. Authored 2.4 m high, installed **8 studs**, floor-origin pivot, faces local **-Z**. Root is stationary and feet planted. Preserve real serialized GLB joint bases. **Do not scale only MeshPart.Size or invent bone-axis conversion.** A-pose is bind pose, not intended visible gameplay pose.

White eyes are skin-following SurfaceAppearance emission, white strength 200, not billboard eyes or actual PointLights. Billboard solution was rejected because tinted glass occluded it. Preserve dark body and mask's brow-UV guard.

Blender connection was solved using official installed Blender 5.2 and background **bpy**; no Blender MCP/add-on is needed to resume. Recipe: executable above with `--background --factory-startup --disable-autoexec --python-exit-code 23 --python SCRIPT -- ARGUMENTS`. Authoring scripts write files; run in a recoverable asset copy, not blindly on frozen published outputs. See `assets/level5/window-watcher/blender-tools/README.md`.

Current encounter behavior: one passive actor, 18 curated real windows across A–H; valid living audience outside pane at 3–145 studs, generally facing it; pane first-hit ray and pane-to-face clearance; recheck after warm-up; prefer groups and avoid immediate repeat. Server head/root direction approximates view; it is not exact client camera. First eligible appearance delay 2–4 s, visible 8–14 s, hidden interval 18–35 s. All current clips use at least **1.90 studs inward depth**; known tap bound leaves about 0.085 stud behind actual pane. Older per-clip .95-depth notes are superseded.

Client visual guard hides her until official track loads, advances and evaluates a non-bind pose. It uses local transparency, not competing manual bone animation. Gaze effects: full within 8 degrees, zero by 30; fades 100–145 studs. Random stare threshold ~2.5–4.5 s at 12 studs, rising to 5–8 s at 100. Exposure decays .20/s when looking away. Local disappearance lasts until new server appearance; other clients/server can still see her. POV pulse 60–105 BPM, <=1.5-degree inward FOV shift, smaller rebound; accessibility/modal/camera guards apply.

### Other concept ideas are not implemented mechanics

Eight imagegen concept boards exist in `assets/level5/entity-concepts-20260925/`: Wrong Neighbor, Window Watcher, Folded One, Noisy Shortcuts, Reactive Mold, Shifting House, Local Blackout, Last House. Most are concepts only. Do not assume there is a chasing Neighbor, reactive mold, moving houses or an 8-3-6 finale puzzle in production. Boards 02/07/08 contained unwanted lamps; attempted 07/08 corrected images were interrupted. Use the current requirements over concept artifacts.

## 7. Runtime script map

Paths below are exact mirror paths under REPO and correspond to Studio instances without file suffixes.

| Owner | Files / responsibility |
|---|---|
| Map build | `ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua`; `Level 5 Architecture.ModuleScript.lua`; `Level 5 Neighbourhood Districts.ModuleScript.lua`; `Level 5 Landmark Districts.ModuleScript.lua`; `Level 5 Furniture.ModuleScript.lua` |
| Puzzle authority | `ServerScriptService/Level 5 Systems/Level 5 Section Progression.ModuleScript.lua`; `Level 5 Puzzle Catalog.ModuleScript.lua`; `Level 5 Colour Lock Logic.ModuleScript.lua` |
| Puzzle client | `StarterPlayer/StarterPlayerScripts/Level5ColourLockClient.LocalScript.lua`; existing `RoundUI.LocalScript.lua` owns cursor; `ReplicatedStorage/UIDevice.ModuleScript.lua` owns modal policy |
| Power | `ServerScriptService/Level 5 Systems/Level 5 Power Outage.ModuleScript.lua`; `ReplicatedStorage/Level5OutageLogic.ModuleScript.lua`; `StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua` |
| Watcher | `ServerScriptService/Level 5 Systems/Level 5 Window Watcher Encounters.ModuleScript.lua`; `ReplicatedStorage/WindowWatcherGazeLogic.ModuleScript.lua`; `StarterPlayer/StarterPlayerScripts/WindowWatcherVisualClient.LocalScript.lua`; `WindowWatcherGazeClient.LocalScript.lua` |
| H eyes | `StarterPlayer/StarterPlayerScripts/Level5CeilingEyesClient.LocalScript.lua` plus authored Landmark geometry |
| Existing sound | `StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua` (footsteps/flashlight; do not double-play them) |
| Entry flow | `ServerScriptService/GameManager.Script.lua`; `Round Loading Runtime.ModuleScript.lua`; `StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua`; NoiseReporter controls-ready and RoundUI UI-ready |
| Dev access | `ServerScriptService/Level5GateAccess.Script.lua`, `Level5Generator.ModuleScript.lua`, existing allowlist/queue; `ServerStorage.Level5DevStartInvoke` schedules normal load |

World model: `workspace["Level 5 Generated World"]`. Key flags `Level5_MapOnly`, `Level5_Generation`; root SpawnCFrame; generated Architecture manifest `RouteWaypoints`, `SectionGates`, `FRescueRouteWaypoints`, `FClueRouteWaypoints`. Normal route after F revision is not the old 120-point route verbatim.

Progression owner: `world.Level5SectionProgression`, gates `SectionGate1..7`, lock `ColourPadlock`, owned attributes `Level5ProgressionOwned`. Client GUI `Level5ColourLockGui`, `ModalInputBlocker` transparency 1, `LockPanel`, `Wheel1..4`, `Unlock`, `Close`. Modal attribute `Level5ColourLockOpen`. Remote folder `ReplicatedStorage.Level5Progression` carries State/Submit; preserve the token/nonce contract.

Watcher owner: `world.Level5WindowWatcherEncounters.WindowWatcher`; `AppearanceCount`, `Visible`, `WindowWatcherVisualReady`, `WindowWatcherGazeHidden`, matching SourceGlbSha256. Gaze diagnostics at 10 Hz: GazeIntensity, GazeExposure, GazeThresholdSeconds, GazeDistance, GazeAngle, GazeLineOfSight, GazeAppearance, GazeHidden, GazeError.

Power metadata: `Level5OutageSchedule` JSON and bounds `Level5OutageExemptMin/Max`, `Level5OutageExitMin/Max`. Read current source for exact state/serial contract before modifying. Local audio must match lighting owner's conservative exemption behavior when metadata is missing.

## 8. ElevenLabs audio — prepared but not installed

### Exact deliverables

Canonical local files: `AUDIO_TASK/audio/ready/`. Versioned duplicate: `REPO/artifacts/level5-audio-qa-20260927/audio/ready/`.

| File | Duration | Purpose |
|---|---:|---|
| L5_room_hum.wav | 11.94 s loop | Normal fluorescent room ambience |
| L5_blackout_roomtone.wav | 11.94 s loop | Quiet outage room tone |
| L5_watcher_heartbeat.wav | 3.94 s loop | Local gaze pulse |
| L5_puzzle_click.wav | ~0.55 s | Wheel/button feedback |
| L5_puzzle_reject.wav | ~0.9 s | Wrong answer |
| L5_puzzle_unlock.wav | ~1.5 s | Solved padlock |
| L5_sliding_gate.wav | 4 s | Gate motion/settling |
| L5_power_fall.wav | 5 s | Staggered power failure |
| L5_power_restart.wav | 3 s | Power restoration |
| L5_watcher_glass.wav | 2 s | Glass presence/tap cue |
| L5_watcher_breath.wav | 4 s | Close apparition breath |
| L5_watcher_recede.wav | ~2.5 s | Gaze-triggered disappearance |

All final files: mono, 44.1 kHz, signed 16-bit PCM WAV; total **4,515,012 bytes**. Exact decoded durations/hashes are in the manifest; the short table uses configured/rounded effect durations for some one-shots. Selected source takes: hum4, blackout1, heartbeat2, click2, reject4, unlock3, gate3, fall4, restart4, glass4, breath2, recede1.

Generation: one batch, 12 prompts × 4 variations = 48 completed MP3 takes, zero generation failures. Objective technical selection/mastering only; **no subjective listening or native mix pass**. Constant gain, peak ceiling -2.3 dBTP, 5/35 ms fades on one-shots, explicit 60 ms float cyclic blend on loops. An intermediate loop-render duration error was caught and replaced; use current manifest hashes.

Authoritative records under task/repo artifact `qa/`:

- `ready-audio-manifest.json` SHA256 **573b00f463da7dd0dec35d544973be0f6f1fc47eb188899e0c7891d55b8a238b**
- `ready-audio-validation.json`, `raw-audio-manifest.json` (all 48 take IDs/hashes)
- `elevenlabs-generation-receipt.json`, `level5-audio-cue-palette.json`
- `audio-delivery.md`, `audio-draft-integration.md`, `master_level5_audio.py`
- `packaged-validation.json` in repo artifact; `session-status.json`

Returned generation pricing total was about **685.9314 credits / USD 0.1247148**; this is tool pricing metadata, not an independently verified billing statement. Generation has already been performed; reuse files and original flow rather than generating again.

All 48 generations completed and downloaded; no pending session polling is necessary. Remote node IDs, if source recovery is needed:

```text
room_hum           ZRuikFLC0XlQdCLKfKrB
blackout_roomtone   RKye4wkZ3TcpvMvU8V4e
watcher_heartbeat   YF50dVQIk4RT4w5T46sS
puzzle_click       yRaxKvktieFInIkiD3N4
puzzle_reject      9cfJu0IGSzxvTicfMeR1
puzzle_unlock      6UmEbASSE9m0wNB0AuXI
sliding_gate       Wmoz9aoidh0ncVeuJfLh
power_fall         9TVxWlSfRjvCB0n4c2tF
power_restart      DTepRwimLqd5NgSez6Z1
watcher_glass      tZQySYJ5v0HOtL5GYjLY
watcher_breath     YQpCExhgXN1Xjve6trWE
watcher_recede     JUqvaPvKzZMKv8TBGreR
```

Early local `elevenlabs-flow.json` and `audio-pipeline-notes.md` predate generation and are superseded by the receipt and final manifests. Raw connector responses may contain temporary signed URLs and are unnecessary for recovery.

### Draft code, all AssetId values currently zero

| Draft under artifact `patches/` | Intended Studio destination |
|---|---|
| Level5AudioCatalog.ModuleScript.lua | new `ReplicatedStorage.Level5AudioCatalog` |
| Level5AudioLogic.ModuleScript.lua | new `ReplicatedStorage.Level5AudioLogic` |
| Level5SoundController.LocalScript.lua | new `StarterPlayer.StarterPlayerScripts.Level5SoundController` |
| Level5ColourLockClient.LocalScript.lua | scoped **3-line** addition to existing client |
| Level5ColourLockClient.audio.diff | exact three-line diff; zero-context archival patch |

Do not install the complete older client file over a changed live client. Reconcile/apply the three scoped lines against fresh Source/editor. Create modules before enabling their consumer. IDs=0 intentionally produce silence; zero-ID deployment is not “audio implemented.”

Controller: 12 reusable Sound voices (3 loops, 9 one-shots), 5 invisible local positional emitter Parts under CurrentCamera, nonspatial sounds under SoundService. 10 Hz update, hard budget <=16 (currently12); zero audio descendants added to generated world. Active only for alive participating Level 5 player with ready controls, not spectating/escaped. Death/lobby/world replacement/script destruction removes owned sounds. Camera replacement recreates pool while preserving event history.

Outage hum follows A–G schedule and leaves H/chute normal; no entry replay of old power transitions. Gate sounds trigger on an observed locked→unlocked edge; existing unlocked/streamed replacement gates form silent baselines. Normal solved unlock has a bounded one-second pending reason because `Unlocked` can arrive before `OpenReason`. Developer bypass plays door only.

Watcher cues require current appearance, real visibility/LOS, healthy enabled gaze LocalScript, no modal/menu/text focus/non-Custom camera. Glass/breath/recede only consume their once-per-appearance state when actual loaded emitter can be heard at its range. Heartbeat follows intensity, stops on LOS/permission/hide loss. GazeError/disabled/destroyed owner stops all Watcher voices despite stale prior diagnostics. Natural timeout does not pretend to be stare disappearance.

Three independently found bugs above were fixed in the draft. **218 pure logic assertions + 125 actual-controller mock assertions pass; all four scripts compile.** Mocks inject valid loaded IDs and are not proof of Roblox asset permission or sound quality. Diagnostics: AudioActive, AudioVoiceCount, AudioLoadedCount, AudioPhase, AudioExempt, AudioWatcherIntensity, AudioCueCount, AudioLastCue, AudioError.

Run from artifact root with available Luau:

```sh
luau tests/test_audio_logic.luau
python3 tests/run_controller_mock.py /absolute/path/to/luau
luau-compile --null patches/*.lua
```

The runner also supports LUAU_BIN or Luau on PATH. Generated concatenated test harness is ignored. Do not broadly rerun every historical game test without a relevant change/failure.

## 9. Current blockers and exact last runtime state

### Native loading failure

Two normal developer-preview starts failed in the audio session. First run timed out game code and Roblox CoreGui/StarterScript under Studio's default 10 s script limit. A diagnostic second attempt temporarily used 60 s, then reached the shared **entry-readiness** deadline. **ScriptTimeoutLength was restored to 10 and verified. Studio returned to Edit.** No production source mutation, no restart/kill, no fake acknowledgement and no new publication happened.

Second failure at **2026-09-27 04:36:20 UTC** reached `Round Loading Runtime.AwaitReady` from GameManager after world build, character load, placement and Prepare. The world was subsequently cleaned up. Generic `LoadStage=WORLD_ERROR` is used for multiple failures; absence of world after cleanup does **not** show it failed to build. `L5QAStartResult=true` only showed hook scheduling, not successful entry.

Host had 8 GB RAM, approximately **17,882.75 MB swap** used of 18,432 allocated and MainThreadHangs warnings. This supports an environment problem but is not proof of the exact cause. Previous poor FPS cannot establish the map alone is responsible.

Concrete but unproven loading fragility: `Round Entry Client` latches AssetsReady=false for a token if any avatar mesh/decal/texture preload fails; repeated same-token Prepare only updates deadline, without retry. Wrap-deformer warnings did not identify the missing asset/latch state. **Do not speculatively change shared loading or bypass its readiness barrier to make this test green.**

Read `qa/startup-failure-readonly-analysis.md`. Use `qa/client-entry-readiness-snapshot.lua` in **Client context during loading, before cleanup**. Server cannot reliably see client-local readiness state; after cleanup evidence is lost. Snapshot is read-only and does not reveal all private LocalScript locals.

Old session info, only for finding logs, not for blind reuse:

```text
Studio MCP session: 4c4f4e63-ad77-456e-8b99-b06b5a864bc8
Studio PID then: 70324
Log: /Users/zeanjuul4/Library/Logs/Roblox/0.740.19.7400931_20260926T113832Z_Studio_a1f69_last.log
```

### Upload/UI blocker

Authenticated Creator Dashboard listed existing Level 2 audio, but Upload assets interactions repeatedly timed out. Read-only AX sometimes worked while browser CDP clicks/snapshots and native Studio UI hung. A fresh same-browser tab and keyboard method did not resolve it. No files selected/uploaded, no new Roblox IDs, no asset-permission or moderation pass.

No configured Roblox audio-upload Open Cloud credential was available in the checked task environment. Do not scrape browser cookies or hunt private credentials. Use the authorised Creator Dashboard/Studio importer or a properly configured supported upload tool if available in the new session. Image-upload MCP is not an audio uploader.

Old pending browser tab ID was `1021424206` (Chrome); marked as a handoff. The duplicate was closed. Treat all tab/runtime handles as ephemeral. The local export bridge at **127.0.0.1:8769** was explicitly stopped at the end of the audio task. Its script is `AUDIO_TASK/bridge.py`; do not assume it is still running.

## 10. Exact next-work plan and acceptance checklist

### A. Recover a usable test environment without losing work

1. Establish correct current Studio place and live sources; preserve concurrent edits and unsaved non-script work. Obtain a new full native backup if UI allows before any restart or installation.
2. If host/UI still blocked, explain the specific failing action. User may need to unlock Mac, foreground responsive Studio/Chrome, save before reopening, or reconnect the existing Studio MCP plugin. Do not hard-kill unsaved Studio or delete random files to gain memory.
3. Make one ordinary Level 5 developer start once environment has meaningfully changed. If loading fails, capture the client readiness diagnostic before deadline/cleanup, pair with server state and current log excerpt. Fix only an evidenced fault; preserve normal access/readiness.

### B. Finish audio import and integration

1. Verify ready WAV hashes. Audition all12 and choose/correct only clearly unsuitable cues; prompts/metrics cannot prove no speech or aesthetically good sound. Use existing four takes before new generation.
2. Upload under correct ERN owner context and confirm usage permission for universe10559217407. Record asset ID, file hash, owner and moderation/load state per cue in a new import manifest. A website upload success alone does not prove runtime access.
3. Time the four-second sliding_gate asset against the **1.6-second** actual tween; movement must align, with a plausible settling tail. Do not slow gameplay merely to fit the sound. Likewise recovery sound may tail past lighting restoration.
4. Fill catalog with real verified IDs. Fresh-compare live Source/editor, then apply only new modules/controller and the three existing-client event lines. Recheck current source inside write; abort/reconcile if someone edited meanwhile.
5. Native confirm all12 assets load, AudioLoadedCount=12, AudioError absent, <=12 voices, no new generated-world descendants. Check intended gains near/far and normal max player volume. Avoid excessive clipping/overlap/jumpscare loudness.

### C. Real puzzle / route playthrough

- Fresh locked round; use real prompts/buttons, not bypass or setting solved flags.
- A: visit all four actual clue rooms, try wrong answer then correct; verify instant PC pointer and transparent background.
- B: traverse offset lanes and room entrance/interior/exit; symbols correct and retry.
- C: find all three separate address houses; enter printed 2/6/4; assess discovery distance without signs.
- D: walk both heights and connecting stairs without forced jumps; switches; no unnecessary rails blocking route.
- E: navigate through furniture/partitions/door frames; clocks agree with written labels.
- F: current **28-point main route**, clue-house detour and **12-point recovery path** from pit, door5/6 thresholds, TV puzzle. Stage separate recovery tests honestly; don't call teleport staging one continuous walk.
- G: climb/descend terraces, visit western ground house, arrows; decorative inaccessible tilted houses remain closed.
- H: last gate creates no new/extended outage; court/chute remain lit even while A–G outage active. Check eye tracking, painted arrows, dogleg, descent support/enclosure. Record completion as missing until implemented.
- Close/reopen UI; invalid/late nonce, range/LOS loss and another player's solve must not leave modal/cursor stuck. Wrong answers free; gates ordered and shared, no bypass underneath or through corners.
- Fresh-round gates reset locked. Normal L-return cleans world/remotes/owned tracks/audio after actual existing delay; do not call a one-second retained object a leak without settled observation.

### D. Regression checks for the user's explicit complaints

- Slow walk and small camera-angle changes across plaster/grass/carpet, houses, thresholds and F ledges; inspect z-fighting. Structural rays alone do not prove pixel-level stability.
- No exterior HOUSE CLUE signs; actual indoor clues present/readable, including non-colour-only labels.
- No individual house Light/Neon fixtures; shared ceiling variation retained; no external corner light leaks.
- A–G: 5 s sequenced flicker/fall, 60 s full blackout, restoration of originally-lit/off state; overlapping triggers follow current schedule correctly. Gate7 never starts/extends; H/chute exempt.
- H: all48 eye pairs track living appropriate targets, preserve mounts and rest on leaving; no real Light instances added. Actual multiplayer selection requires multiple real players.
- Watcher: loaded animated pose behind actual pane; white eyes/no floating brow artifacts; real supported rooms across A–H; approach from >85studs into audible range; blocked LOS and modal stop heartbeat; random accumulated gaze hide; natural timeout; no local sound leakage after hide/lobby/death.
- Audio cleanup: death, respawn, spectating, lobby, new world/streamed replacement, camera replacement and disabled/errored gaze owner. No duplicate footsteps/flashlight.

### E. Reporting, backup, Git and publication

Record native passes separately from pure/mock tests and prior history. Save screenshots plus compact evidence; no repeated enormous dumps. Fresh Source/editor/repo parity for changed work, preserve unrelated developers. Full native place backup for non-script state. Review exact staged diff, commit all relevant task changes, push existing branch without force, update PR10 and keep it attached, update existing Trello card truthfully. Publish only verified completed changes to the existing place and verify actual success/version receipt. Never infer publication from git push or Save to Roblox.

If H completion/performance remains a blocker, keep the developer-preview limits and report it. The task to add a main hostile entity is future work, not permission to improvise one while importing audio.

## 11. QA evidence already available — do not overclaim it

| Evidence | What it established | What it did not establish |
|---|---|---|
| Latest source puzzle audit | 6,910 assertions /2,185 combinations, consistent7 answers and clue construction | Fresh native full playthrough |
| Layout arithmetic | 2,737 checks;7 puzzles×9 viewports | Every real device/font/gamepad;244px usable-height limit remains |
| Latest audio draft |218 logic+125 actual-controller mock;4 scripts compile; independent review of3 fixes | Actual uploaded assets, audio listening, spatial playback |
| v2139 native surface/UI |18,168 rays,18 anchors, actual gate1 clicks,1,134 cursor frames,B/F room walks | Every open gate, every reset path, physical mobile, all possible pixel flicker |
| v2136 native F |Closed/open5,651 rays each, main/recovery/clue routes and real TV input | Clean current-device performance or every home traversal |
| v2143 native eyes |48 rigs east/west aim and rest, mount error<=.00274studs | Human multiplayer target allocation |
| v2143 outage |Complete71.17s cycle,402 samples,379 streamed fixtures of421 server originals,zero observed mismatches | Simultaneous client observation of every fixture |
| v2143 gates |Real held developer bypasses1–7;gate7 preserved serial/deadline | Normal seven-puzzle solve run |
| Older Watcher assets |300 published bone/time comparisons;three clips;cleanup/reentry separately observed | Global pass for earlier INCOMPLETE observers or published-server permissions on all devices |

Earlier F averaged11.85FPS and unchanged A6.56FPS on the heavily swapping8GBMac. Older pre-atrium samples reached45–60FPS. These are different versions/conditions; neither proves current controlled performance. Keep performance unapproved until retested on a responsive host and target devices.

A potential prompt UX issue remains a **candidate**, not confirmed softlock: prompt RequiresLineOfSight=false can display E from a wall's wrong side while server correctly rejects obstructed use. If changing it, test legitimate padlock geometry doesn't occlude the prompt.

Other known historical whole-game issue: completion-save failures can lose rewards/progression while a badge is attempted; Trello https://trello.com/c/EYpXKa9S. This was outside visual Level5 changes. Don't claim it fixed or redesign it without reviewing current code/scope.

## 12. Concurrent developers, baseline and recovery

The fresh audio-session export is `AUDIO_TASK/baseline/full-1.json` through `full-40.json`, parsed into `baseline/sources/` plus `baseline/source-index.json`. **Use this complete set.** Earlier `studio-before-*` were a failed partial oversized export and are not a full snapshot. This snapshot is historical at handover; re-read live before edits.

Four additional scripts present in that authoritative export, absent from the193-script v2143 mirror:

| Path under baseline/sources | SHA256 |
|---|---|
| ServerScriptService/Level6Expansion.ModuleScript.lua | `2baa24025cb90442bbd1af3c328e5c1e2a3f2afad2763c2a20a64adf58f913cb` |
| ServerScriptService/Level6Generator.ModuleScript.lua | `880a8912e3c4b97227ce012ab826bd4fa3bc98ed18d93e3e7989f81bd6335f7f` |
| ServerScriptService/Level6PreviewAccess.Script.lua | `14a9b9063931d395e0813d3d152d2007d522b2734e61689c70ce799dc5ba73aa` |
| StarterPlayer/StarterPlayerScripts/Level6PreviewPrompt.LocalScript.lua | `050beec93e5dee8d7721a83d6b61290a74d43884e979d4bdfa4753b31398fc4d` |

These were preserved, not authored/QA-approved by this task. Do not remove because a Git mirror lacks them. Current global Studio instance count includes editor internals; don't blame these scripts for a large global instance statistic without scope measurement.

Earlier concurrent work also included TunnelLobbyBuilder's Level4/5/6 estimates90/70/30, Records/ZyntraStore/UIRegression and Signal Architect Ascendant. Their history is documented in the relevant older docs; always compare current authoritative sources instead of replaying old developer merges. All12 Level4 scripts were preserved by the latest Level5 production edits.

### Latest verified native backup

```text
REPO/artifacts/level5-exit-eyes-20260926/after.rbxl
9,821,563 bytes
SHA256 0a1bab9bc1510b952ef85c335e8df4f2bf953edbb447fa107da3da29bc59b7f1
Published scope: v2143, 26 September2026, before the new audio task/concurrent Level6 checkpoint.
```

This contains rig/material/non-script state at that older checkpoint. **It is not a complete backup of the current unsaved Studio place.** The new197-script export preserves sources but cannot prove preservation of any concurrent non-script edits. Never restore this file over live Studio by default. If original current place is lost, open it as a **separate recovery copy**, compare current published/cloud/team state, then reconcile newer known sources/assets after review.

Older backups are in the chronological artifact folders for surface/UI, atrium, dense routes, expansion, outage and Watcher; see their receipts. Old backups should not be preferred merely because a filename says “final.”

## 13. What the user may need to provide manually — worst case

Ask only for the minimum missing item, after checking tools/files. Do not send the user through all steps if the new session already has access.

| Failure scenario | What the new agent can do first | Minimal manual information/action if still blocked |
|---|---|---|
| New local chat has no history | Read this handover and listed artifacts using absolute paths | Paste START_HER text or attach this MD |
| New chat runs in cloud/another Mac | Use attached recovery ZIP; extract in a new directory | Attach ZIP or give access to correct repo/branch; local `/Users/...` is not cloud-accessible |
| Repo missing | Clone authorised repo to a new separate folder;checkout named branch after verifying remote | Sign in to GitHub normally if access is absent; do not paste tokens into chat |
| Studio connection missing | Discover enabled Roblox Studio MCP and list sessions; verify correct place | Open the existing correct experience in Studio and enable/reconnect the installed MCP plugin; exact UI depends on installed version |
| Mac asleep/locked or UI hanging | Stop retry loops; retain files and read-only evidence | Unlock Mac; check Studio/Chrome respond. Save current place/unsaved work before restarting Studio |
| User is playing simultaneously | Inspect current Play state/ask only if actions conflict | Tell agent whether it may own the test session; avoid stopping its test mid-run |
| Upload account/group unavailable | Inspect visible Creator Dashboard owner; existing authenticated session | Log in as authorised developer and select ERN Roblox Studios. Never send password/cookies/API key in chat |
| New audio IDs exist from user/manual upload | Look for exact12 names, compare asset metadata and test permission | Give12 name→asset-ID mapping and owner if agent cannot read them; no need to regenerate files |
| Uploaded audio fails moderation/access | Check asset status and experience usage permission | Authorised owner may need to grant universe10559217407 access or resolve a flagged upload |
| ElevenLabs unavailable | Reuse ready WAVs/raw alternatives; existing generation already completed | Reconnect plugin only if another take must genuinely be generated or source recovered |
| Meshy/Blender unavailable | Existing published rig/clips and source files suffice for audio task | Reconnect/install official app only if later editing is necessary; no rerig or paid regeneration by default |
| Exact original photo comparison needed | Search preserved assets/reference files first | Reattach **Foto1 and Foto2**, and only relevant current gameplay screenshots/video if originals remain missing |
| Visual bug persists only for user | Check live version,location/material,camera and current native repro | Section/location,device/resolution/graphics,new vs old server,and short clip showing angle change |
| Physical mobile/multiplayer validation | Distinguish simulation from real hardware; prepare test route | A real device/account session or user test observations; do not claim native coverage from mocks |
| Publish UI still blocked after completed verified work | Save backup and exact source parity; leave reviewable result | User may click File→Publish to Roblox; agent must then verify version receipt. Do not ask to publish currently unverified audio |
| Only old backup survives | Work in separate recovery copy; reconcile newer checkpoint sources | User must identify any unsaved/new developer changes not captured in source export; no guarantee these can be reconstructed |

### Original attachments that were not found during this handover

The **eight earlier design screenshots do survive** as copied `Level-4-Reference-01…08-*.png` files in `PROJECT_ROOT/output/level4-design-20260923-v2/`. The historical “Level 4” names refer to the design later assigned to **Level 5**. The same directory preserves the brief, build checklist, image prompts and chute-arrow images. Later user decisions in this handover override obsolete gameplay/lore instructions in those historical files. Extracted video frames at 15/27/33/46 seconds and a contact sheet survive in `PROJECT_ROOT/output/level4-video-reference-20260923/`. These are included in the recovery ZIP.

The old transient paths for the two atrium photos are absent:

```text
/tmp/codex-remote-attachments/01a0a070-b708-7232-9329-1b8fa741047d/4525787A-39A7-4B88-95CB-3AEF7F52A2FE/1-Foto-1.jpg
/tmp/codex-remote-attachments/01a0a070-b708-7232-9329-1b8fa741047d/4525787A-39A7-4B88-95CB-3AEF7F52A2FE/2-Foto-2.jpg
```

Sample Desktop paths `/Users/zeanjuul4/Desktop/Screenshot 2026-09-26 at 21.05.21.png` and `...21.05.49.png` are also absent. The earlier message included many near-identical gameplay views and some unrelated Shopify/security settings captures. **Do not request or bundle unrelated account screenshots.** Current implementation screenshots and concept sources survive in the repo. Missing originals do not block audio import or code QA; request them only when an exact visual comparison is needed.

## 14. Tool/skill notes for the next agent

- Discover actual available tools rather than declaring a missing capability from memory. Roblox tools previously included list_roblox_studios, get_studio_state, execute_luau with Edit/Server/Client contexts, start_stop_play, character_navigation, native input/screen capture and console output.
- Keep short read-only diagnostics separate from mutations. Studio execute source writes require fresh Source/editor compare-and-swap; do not launch old `push_repo_to_studio.py` wholesale.
- Export scripts in small batches. Previous13-script payload exceeded1MB;5-script batches succeeded. Use complete batch count/index/hashes before calling export complete.
- Use installed ElevenLabs sound-effects/creative-studio skill when working on audio. Prior paths were under `/Users/zeanjuul4/.codex/plugins/cache/openai-curated-remote/app-6a8d784b60cc81919aeafbfaeda5fbcf/1.0.0/skills/`; discover the current catalog if path/version changed.
- Imagegen is required for new image assets the user requests. Existing materials/mold/arrows already generated; don't replace them just to demonstrate tool usage.
- Browser/native UI must use the supported current CUA API. Read its documentation on first use. Preserve the user's tabs, don't reuse stale element indices, verify actual upload result/owner and permissions. If browser cannot interact, don't scrape credentials or unofficial private endpoints.
- Authentication/permissions are account state, not stored in this handover. No credentials, cookies, API keys or temporary signed asset URLs should be copied into future docs/commits.
- A source file, GLB export, mocked test or Git commit does not establish Roblox publication. Verify each boundary.

## 15. Recovery package contents and limits

Alongside this handover there is a local recovery ZIP, a START_HER message and a machine-readable inventory with SHA256 values. The package preserves this handover, latest audio assets/udkast/tests,197-source checkpoint, relevant history/QA documents, Level5 authored assets (including Blender/Meshy sources), selected implementation/reference images and the v2143 native backup. Relative paths inside ZIP permit use outside this Mac. Read its manifest before restoration.

Local delivery files are under `HANDOVER_DIR`:

- `START_HER_NY_CHAT.md`: copy/paste this into the next chat.
- `GAME_DEV_LEVEL5_RECOVERY_2026-09-27.zip`: portable recovery bundle.
- `RECOVERY_MANIFEST.json`: per-file hashes and original locations, also inside ZIP.
- `RECOVERY_VERIFICATION.json`: archive verification result and ZIP hash, outside ZIP.

After extracting, `FULL_HANDOVER_GAME_DEV_LEVEL5_2026-09-27.md` is at the bundle root. `repository/` preserves selected repo-relative paths, `studio-checkpoint/` contains the complete newer 197-source export and index, and `references/` contains the historical visual reference copies. Use `repository/artifacts/level5-audio-qa-20260927/` as the portable audio-task root. Do not run its old absolute paths unchanged on another machine. The manifest identifies each original path and SHA; originals need not remain reachable to use the bundled files. `VERIFY_BUNDLE.py` checks the extracted files without installing or changing the game.

**Limits:** no claim of full raw chat transcript, no credentials/login sessions, no entire Git history, no missing temporary original photos, no full newer native backup of concurrent unsaved non-script work. GitHub branch and current live Studio remain necessary for the latest state when reachable. Recovery files are reference/recovery inputs, not permission for bulk deployment.

## 16. Definition of done for the unfinished task

The current task is only finished when the agent can truthfully report:

1. All A–H sections assessed with current evidence and clear playable/unverified/incomplete status; normal A–G puzzle inputs and required paths actually tested on the working current build.
2. All necessary selected Level5/Watcher cues uploaded, permitted, installed and audibly verified; all twelve loaded or any replacement/removal explicitly justified.
3. Outage timing and H exemption, Watcher gaze/LOS lifecycle, modal/cursor behavior and surface/sign/light constraints still pass.
4. Cleanup and performance checked appropriately; multiplayer/mobile limitations explicit.
5. Fresh sources and non-script state backed up, reviewable commit/push, truthful Trello, and verified publication **if there is no remaining material release blocker**.

Until then say exactly what is ready and what remains blocked. Do not mark the overall Level5 card done while completion/main entity/release QA remain open.
