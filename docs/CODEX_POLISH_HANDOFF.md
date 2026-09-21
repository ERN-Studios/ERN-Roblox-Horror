# Codex polish-handoff — BACKROOMS: STAY QUIET

Skrevet løbende af Claude (al kode). Opgavegrundlag: `docs/CLAUDE_PROMPT_2026-09-21.md`.
Status-ord: **kodefærdig** · **verificeret i Studio** · **verificeret publiceret** · **mangler art** · **afventer data/hardware**.
Intet i dette dokument er publiceret endnu, medmindre der står det.

## 0. Baseline og versionsstyring

| Punkt | Værdi |
|---|---|
| Studio ved start | place `131311258779917`, PlaceVersion **1958**, Edit, 154 scripts, Source == editor-source for alle 154 |
| Repo-audit ved start | `pull_source_from_studio.py --audit`: 154/154 matcher `origin/codex/six-improvements-20260920` (`736f417`) |
| Native backup | `artifacts/claude-20260921/baseline-v1958.rbxl` (File → Download a Copy), 9.337.868 B, sha256 `bdb10cbf513eb08e7c265ed2b7a9e77d3e54142c2bcb0de3f8238ffc71fe7276`. Ligger kun lokalt (untracked) |
| Checkpoint af gammel lokal main | branch `backup/local-main-20260921` → `11b3502` |
| Arbejdsbranch | `claude/trello-20260921`, bygget på `origin/codex/six-improvements-20260920` + merge `06a0642` af lokal mains upushede docs/assets/tests. Runtime-mirror og manifest blev taget uændret fra six-branchen |
| PR-stack | PR #2 (audit → main) og PR #3 (six → audit) er urørte. Ingen merge, ingen force-push |
| Studio-skrivninger | kun pr. fil gennem `tools/push_repo_to_studio.py` (compare-and-swap mod frisk Studio-baseline inde i `UpdateSourceAsync`, kompileret efter landing). Før-kilder: `.studio-push-backups/<tidsstempel>/`. Efter hver runde: `pull_source_from_studio.py --audit` = 0 drift |

Én hændelse undervejs: et sammensat git-kald blev afviklet to gange af værktøjslaget, så to filer kortvarigt lå i Studio med konfliktmarkører (kompilerede ikke, ingen play-session kørte). Opdaget af push-værktøjets compile-check, rettet og re-pushet inden for to minutter; audit bagefter 154/154.

## 1. Status pr. milepæl

### Fase A

| Kort | Status | Kort fortalt |
|---|---|---|
| A1 PoolSlide chase-lag ([rXhi1SZ8](https://trello.com/c/rXhi1SZ8)) | kode: **verificeret i Studio** (solo). Animationer/større model: **mangler art** | Årsag fundet og målt; planlægning med 96-studs horisont. Se §3.1 |
| A2 PoolSlide-lyd ([LigItMHi](https://trello.com/c/LigItMHi)) | **kodefærdig**, tilstandsmaskine **verificeret i Studio** på attributniveau. Lyttetest: **afventer** (jeg kan ikke høre) | Én ejer pr. lydforløb; mund-emitter følger det animerede `Head`-bone. §3.2 |
| A3 PoolFoam overlap ([jecT8s86](https://trello.com/c/jecT8s86)) | **delvist**: steady state holder afstand i Studio; korte overlap under "back-out" i en klynge er fundet og er ved at blive rettet | §3.3 |
| A4 Lag/render ([Zpj0Gkbb](https://trello.com/c/Zpj0Gkbb)) | målt på PC; mobil **afventer hardware**. Texture-instans-reduktion under arbejde | §3.4 |
| A5 Level 3 første CD + CD-reader ([6BVH4WmN](https://trello.com/c/6BVH4WmN)) | **verificeret i Studio** (solo, PC). To spillere, fem afleveringer og touch-layout: ikke kørt | §3.5 |

### Fase B

| Kort | Status |
|---|---|
| B1 Shoptekster ([xQWVkwhw](https://trello.com/c/xQWVkwhw), [UNRk7Qy8](https://trello.com/c/UNRk7Qy8)) | tekst **kodefærdig og i Studio**; event-måling under B2 |
| B2 Analytics ([bIFdNWUf](https://trello.com/c/bIFdNWUf)) | under arbejde |
| B3 Dødsårsag, råd og retry ([PR0ersiy](https://trello.com/c/PR0ersiy), [us5TWr9O](https://trello.com/c/us5TWr9O)) | under arbejde |
| B4 QA/marketing | **afventer personer/hardware**; se §6 |

### Fase C/D

Level 4 blokmodel + prototype er under arbejde (dev-only adgang; live-gates uændrede). Øvrige: se §7.

## 2. Ændrede Studio-paths og commits (lokale commits på `claude/trello-20260921`)

| Commit | Indhold | Studio-paths |
|---|---|---|
| `7509fb9` | PoolSlide horisont-planlægning + request-tracing | `ServerScriptService.Level 2 Systems.Level 2 Pool Slide Controller`, `…Navigator` |
| `e4bc4a7` | L3 første CD i entry-rummet + CD-reader | `…Level 3 Systems.Level 3 Layout Generator`, `…Objective Controller`, `StarterPlayerScripts.Level 3 Reader Client`; test `tools/tests/test_level3_first_cd.py` |
| `390f5aa`, `f58e493` | PoolSlide-lyd: ejerskab + mund følger animeret bone | `ReplicatedStorage.Level 2 Entity Audio Bank`, `StarterPlayerScripts.Level 2 Entity Audio`, `…Level 2 Sound Controller`; tests `test_pool_slide_audio_states.py`, `test_spectate_audio_gates.py` |
| `0790135` | PoolFoam separation | `…Level 2 Pool Foam Controller`, `…Navigator` (ny `Sidestep`), `…Configuration` (blok `Separation`); test `test_pool_foam_separation.py` |
| `a1248c8` | L3 rumopslag i plan-koordinater; SlideContinuationSafety kaster ikke længere på forankret rod; UIRegression-række | `…Level 3 Objective Controller`, `ReplicatedStorage.SlideContinuationSafety`, `ReplicatedStorage.UIRegression` |
| `0a83253` | Load-tids-readbacks + måleartefakter | `…Level 2 Round Adapter`, `…Level 3 Round Adapter` |
| `8e97018` | Shoptekster | `ReplicatedStorage.ZyntraConfig`, `StarterPlayerScripts.Shop Display Client`, `ServerScriptService.ZyntraMonetization` |

Ikke pushet til GitHub endnu, ikke publiceret til Roblox endnu (se §9).

## 3. Før/efter, seeds og målinger

Alle målinger: ejerens PC, Roblox Studio play-session (server + én klient), udviklerkonto med entitlements/ESP — **ikke** en nyspiller-, mobil- eller produktionsmåling.

### 3.1 PoolSlide (A1) — fuld record i `artifacts/claude-20260921/poolslide/RESULTS.md`

- Reproduktion: seed `1182081016` (pinned via `workspace.Level2Seed`), 1 spiller, spawn efter pumpe 2 i 194,75 studs afstand, scriptet mål der går 16 studs/s rundt mellem fire hall-noder (`harness-server.luau`, `harness-ab-server.luau`).
- Før: hele ruten (110–220 studs) blev body-certificeret ved hver plan med 2 ms/frame. Når en detour-søgning var nødvendig et sted på ruten, løb 3 s-deadlinen ud 3–4 gange i træk, den gamle rute blev aldrig erstattet, og kæmpen gik (og løb) hen hvor spilleren havde været for 10–15 s siden. `os.clock()` er wall-clock i denne session (ratio 0,99999) — det er ikke en CPU-ur-fejl.
- Rettelse: stabile ruter certificerer kun de første `PlanHorizon = 96` studs og forlænger når der er `PlanHorizonExtend = 48` tilbage. Selve beviset (centrering, detour, smoothing, join, per-skridt-validering) er uændret.
- A/B i samme runde (75 s pr. fase, horisont 0 = gammel):

| Fase | Goal age p50 / p95 / max (s) | Goal error p50 / p95 / max (studs) | Planner aktiv |
|---|---|---|---:|
| gammel | 3,2 / 13,9 / 16,1 | 39 / 183 / 191 | 95 % |
| ny | 0,9 / 2,8 / 5,2 | 15 / 53 / 99 | 63 % |
| gammel | 1,8 / 10,6 / 14,2 | 27 / 158 / 179 | 84 % |
| ny | 1,0 / 2,7 / 4,7 | 17 / 42 / 70 | 69 % |

  Latency-mål brugt: typisk ≤ 1,5 s, p95 ≤ 3 s mens målet bevæger sig (ét repath-interval + én kort plan). Server-Heartbeat uændret (p50 16,6 ms i sammenlignelige faser); ingen nye spikes.
- Accept kørt: sikker spawnafstand (194,75 ≥ 100) fra eneste levende deltager; spawn efter 2. forskellige pumpe; 3. pumpe (rigtig ProximityPrompt) → `ENRAGED`, fart 32, **samme Model-instans**, `SpawnCount` stadig 1; tre runder i træk spawner én gang hver og nulstiller alle attributter; 265 samples med kroppen i bevægelse: 0 overlap med kolliderbar geometri (krops-bbox krympet 1×3×1).
- Ikke verificeret: flere levende deltagere, publiceret server, enraged på lang afstand.
- Diagnostik (slået fra som standard): `workspace.Level2_PoolSlideDiagnostics = true` → `Level 2 State`-attributterne `Level2_PoolSlideGoalAge/GoalError/TargetDistance/Trace` (JSON pr. request: kø, compute, centre, join, outcome, goal drift) og A/B-håndtaget `workspace.Level2_PoolSlidePlanHorizon`.

### 3.2 PoolSlide-lyd (A2)

Ejerskab: `Level 2 Sound Controller` ejer fjerne pipe-groans; `Level 2 Entity Audio` ejer alt der kommer fra en krop. Eneste håndtryk er serverflaget `Level2_PoolSlideActive` (på `workspace` og i `Level 2 State`), som ikke streames ud — et lokalt stream-out kan derfor ikke forveksles med despawn.
Observeret i Studio-runde (klient-probe, attributter/instanser — ikke lyttetest): fjern groan 10 s inde i runden før nogen pumpe (én emitter, ~8 s, fjernet); ved spawn præcis én `Level 2 Slide Alert` fra mund-emitteren, fjerne emittere = 0 mens aktiv; emitteren sidder ~11 studs over sålerne og vipper med gangen (følger `Head`-bonens `TransformedWorldCFrame`); ved listener-død fader kanaler ud på 70 ms; ved rundeslut 0 emittere, 0 lyde, 0 efterladte instanser.
Ikke verificeret: faktisk despawn → genoptaget ambience, stream ud/ind, andet spawn, chase-frekvens for øret, spectator-mix. Lyttetjekliste: se agentens rapport gengivet i §5 (lydkontrakt).

### 3.3 PoolFoam (A3)

Studio, seed `1182081016`, én pumpe (fase Foreshadow: fem aktive, ingen angreb), stillestående spiller: alle fem konvergerede på spilleren inden for et minut. Live-modellen er final art, bbox 5,17 × 11,05 × 4,0 → målt radius 2,59, kontakt 5,17, med padding 6,67. Uafhængig sampling (0,5 Hz): par-afstande 6,48–6,7 = præcis den polstrede kontaktafstand. Men controllerens egne readbacks viste korte reelle overlap: `MinSeparation` 3,2, `OverlapFrames` +1/s, `YieldCount` +2–3/s uden loft — "back-out"-reglen (til korridor-møder) fyrer kontinuerligt i en stillestående klynge og bakker gennem naboer. Rettelse bestilt: en ring om et fælles mål er en stabil sluttilstand; aldrig retreat/release ind i en anden krop. Passets pris: 0,006–0,2 ms.
Før-tilstand: ingen separation overhovedet (alle dele forankrede, `CanCollide = false`, navigatoren ekskluderer hele runtime-mappen).

### 3.4 Lag (A4) — `artifacts/claude-20260921/level2-perf/MEASUREMENTS.md`

PC, Studio i forgrunden: klient 16,7 ms p50 / 18,4 p95 / 22,1 max (60 Hz-loft, 0 frames > 33 ms); server Heartbeat 0,98 ms i ro. Auditens "ca. 15 FPS" var baggrunds-throttling. Strukturel afviger: **44.923 af 74.654 verdens-descendants er `Texture`-instanser** (én pr. flade, seks som standard); 138–154 lys, alle med skygger; 21.261 dele med CastShadow. Streaming-radius/-mode kan ikke læses fra MCP-tråden (capability). Nye readbacks: `Level2_/Level3_LayoutSeconds`, `BuildSeconds`, `WorldDescendants`. Under arbejde: fjern Texture på beviseligt skjulte flader (kontakt `Performance.CullHiddenTileFaces`), verificeres med fast kameratur + billed-diff (`level2-perf/shots-client.luau`).

### 3.5 Level 3 (A5)

Seed `1154781618` (pinned), solo: `Level3_EntryRoomId == Level3_FirstCDRoomId == L3_S1_R05`; præcis fem CD'er i fem forskellige rum; CD 1 ligger på bordet i første rum efter ankomstkorridoren. `Level3_Room` på spilleren: `Arrival` → `""` i korridoren (21 studs fra CD'en, én væg imellem → ingen tekst) → `L3_S1_R05` inde i rummet → readeren viser præcis `IN THIS ROOM` i `UIStyle.Color.Danger`, pulserende 0–0,40 transparens (stabil med `ReduceFlashing`). Pickup → `CARRIED`, position nil, readeren skifter straks til næste CD (`CD // ▮□□□□ 61m`). Død med CD i hånden → `DROPPED` på sidste sikre gulvposition med rum-id. Reader-panel: øverst til højre, 248 × 101 px ved 1539 × 809.
Fundet og rettet undervejs: rumopslaget sammenlignede verdenskoordinater med planens lokale rektangler (`WorldOrigin` 6200,24,0) — ingen spiller var nogensinde "i et rum". Offline-testen kunne ikke se det; første Studio-kørsel gjorde.
Observation til polish: alle fem CD'er ligger på rummets **skjulebord**, og både `COLLECT CD` og `HIDE UNDER TABLE` bruger E. Roblox viser den prompt man sigter på (verificeret: sigt på CD'en → COLLECT, sigt under bordet → HIDE). Det er eksisterende adfærd for alle CD'er, men for den garanterede første CD kan en ny spiller komme til at gemme sig i stedet for at samle op. Forslag: slå bordets hide-prompt fra mens dets CD er `WORLD` (kræver ændring i Hiding Controller; ikke lavet).
Ikke verificeret: to spilleres pickups, fem afleveringer + exit, touch/tablet-layout, spectator-visning.

## 4. Screenshots

Native Studio-captures ligger uden for git i session-scratchpad (`shots-before/shot01–12.png`, fast kameratur i Level 2). Level 3-readeren (desktop, `IN THIS ROOM`) er set og beskrevet ovenfor; gemte HUD-screenshots til Codex følger når touch-tiers er kørt.

## 5. Assetliste til Codex

### PoolSlide — nye walk/run-animationer og større model (**mangler art**; ingen kilde fundet)

- Rig-kilden findes ikke på denne PC: templaten bærer `SourceSHA256 = 7446213563c55d9688fb6b756220a0101f4d10675ceed7646c4c30cf9fa1a2a0` og `TaskCreated = 2026-09-09-new-pipe-entity`; ingen `.glb/.fbx/.blend` i `G:\Roblox`, Downloads, Documents eller Desktop matcher den hash. Den eneste Meshy-fil i repoet (`assets/models/Meshy_AI_Dustwalker_…fbx`) er Level 1-entityen og må ikke forveksles.
- Live template: `ServerStorage.Level2Assets."Level 2 Pool Slide Template"` — Model, PrimaryPart `RootPart` (0,6³ Part), MeshParts `Mesh_0` (11,53 × 12,00 × 3,96, mesh `108970159979893`) og `Mesh_02` (3,82 × 3,79 × 2,79, mesh `91916953208682`), to statiske Motor6D-bindlinks RootPart→mesh, `AnimationController/Animator`, mappe `Animations` med `Animation`-instanserne **Idle** `116085684636171`, **Walk** `140239794149902`, **Run** `101625402038627`, **Attack** `121778490512649`. Pivot (0,4,0), bbox-center (0,4,0).
- 20 bones: `Root, Hips, LeftUpperLeg, LeftLowerLeg, LeftFoot, RightUpperLeg, RightLowerLeg, RightFoot, Spine, Chest, LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand, Neck, Head, RightShoulder, RightUpperArm, RightLowerArm, RightHand`. Nye clips skal bruge præcis disse navne og samme hvilepose/orientering (pivot skal stå lodret: `UpVector·Y ≥ 0,999`).
- Attributter controlleren asserter på: `AgentRadius 7,5`, `AgentHeight 16,7`, `AnimatedEnvelopeRadius 7,3`, `AnimatedEnvelopeHeight 16,1`, `GroundOffset 6` (pivot→sål, skal matche målt ±0,12), `Level2_PoolSlideRigVerified`, `Level2_PoolSlideCorridorFitVerified`. Loft i navigatoren: radius ≤ 12, højde ≤ 24.
- Integrationspunkt: `Level 2 Pool Slide Rig Adapter.Attach` loader de fire `Animation`-instanser fra templatens `Animations`-mappe (skift kun `AnimationId`); afspilningsrate = faktisk fart / `WalkAnimationReferenceSpeed` (10,82) hhv. `RunAnimationReferenceSpeed` (27,6) i `Level 2 Pool Slide Configuration`, clamp 0,05–2,5, blend 0,16 s. Spilfart: walk 10, run 20, enraged 32 studs/s. Nye clips: mål den fart i studs/s hvor fødderne ikke glider ved rate 1 og skriv den i de to konstanter. Attack-clippet er 1,2 s med kontaktmarkør ved 0,5 s (`AttackWindup`), må ikke ændres uden at ændre de to tal.
- Større model: `Model:ScaleTo` er ikke lavet, fordi (a) envelope-attributterne og korridor-fit skal genverificeres samlet, (b) translation-tracks i skinned clips skalerer ikke automatisk. Regnestykke: +20 % giver bbox 13,8 × 14,4 × 4,8, `AgentRadius ≥ 8,9`, `AgentHeight ≈ 20,0` (under loftet 24) — korridorfit skal måles på tre layouts før flagene sættes. Leveringsformat: FBX/GLB med skelet + fire clips, 30 fps, Y-up, én root; upload som ejet animation til gruppen.

### PoolSlide-lyd (kalibrering for øret)

`ReplicatedStorage."Level 2 Entity Audio Bank"`: `Slide.MouthBoneOffset = Vector3.new(0, -0.3, -0.8)` (bone-space fra `Head`-leddet mod mundåbningen, skaleres med modelhøjde / `MouthReferenceHeight = 12`); `Mix.Slide.Mouth = {Volume 0.42, Min 24, Max 240}`; mund-interval idle 16–28 s, chase 7–14 s; spawn-groan = eksisterende `Slide.Alert`; periodiske groans = de fire `Level 2 Distant Monster-Like Pipe Groan 1..4`-slots i `Level 2 Sound Library`. Valgfrit for art: en Attachment `Level2_PoolSlideMouth` på kæben i templaten vinder over alt andet. Bemærk: også walk/run-loopet spiller fra mund-emitteren (12 studs høj krop; ikke hørbart forkert på afstand, men en fod-emitter er en mulig polish).

### Level 3 CD-reader

Ingen nye assets. Tekster: `> CD READER`, `CD // ▮▮▮□□ 30m`, `IN THIS ROOM`. Farver fra `UIStyle` (`Danger` til rumteksten).

## 6. Hvad der reelt må vente

- Fysisk telefon/tablet/svag enhed (A4, B4): ingen hardware i denne session. Studio-emulator er ikke device-QA.
- To venner / nye spillere uden hjælp (B3, B4): kræver personer.
- Dashboard-modtagelse af analytics (B2): først efter en publiceret release.
- En uges sammenlignelige data, D1/D7-kohorter, CPP (B2): kan ikke fremstilles.
- Lyttetest af A2.

## 7. Ejerafklaringer (kun de reelle)

1. **Token Earner 2x/3x/5x (D3)**: priser, stacking, hvilke tokenkilder der ganges, upgrade-semantik. Forslag: højeste ejede tier gælder (ingen multiplikation af tiers), upgrade koster differencen, multiplikatoren gælder kun *optjente* tokens (ikke købte/gave), og engangseffekten ved køb er `floor(balance × (tier − forrige tier))` bogført i en grant-ledger. Konsekvens: ingen selvforstærkende grants ved login, og 2→3→5 giver samme slutresultat som 5 direkte.
2. **Hazmat-skins (C2)** og **Advanced Camera (D1)**: priser/produkt-ID'er findes ikke; kode kan laves testbar uden aktivt salg.
3. **Alle 138–154 Level 2-lys kaster skygger**: art/ejer-valg om fjerne dekorationslys må miste `Shadows` på svage enheder.
4. **PoolSlide-størrelse**: hvor meget større (tal), før korridor-fit genverificeres.

## 8. Instruktion til Codex

Lav polish, art og asset-feedback ud fra kontrakterne ovenfor. Har du brug for en kodeændring (nye attributnavne, en ekstra attachment-opslagssti, andre intervaller end dem der er knapper til), så skriv den som en konkret anmodning til Claude med fil/funktion og ønsket adfærd — ret ikke runtime-scripts direkte, så rollefordelingen og Studio-pariteten (154/154, 0 drift) bevares. Rene værdier i `Level 2 Entity Audio Bank`, `Level 2 Pool Slide Configuration` (de to reference-hastigheder) og `AnimationId`'er i templaten er dine at dreje på; sig til bagefter, så de bliver mirroret.

## 9. Release

Ikke publiceret. Publicering følger repoets præference (AGENTS.md) når en milepæl er færdig **og** verificeret uden materiel blocker. Aktuelle blockere for en samlet publicering: A3-rettelsen (overlap i klynge) er ikke landet/verificeret; B2/B3 er ikke integreret; Level 4 er en dev-only prototype og må ikke erstatte live-gates.
