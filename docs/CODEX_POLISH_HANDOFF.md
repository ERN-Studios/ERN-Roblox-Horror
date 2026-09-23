# Codex polish-handoff — BACKROOMS: STAY QUIET

Skrevet af Claude (al kode). Opgavegrundlag: `docs/CLAUDE_PROMPT_2026-09-21.md` (21/9) og
`docs/CLAUDE_POLISH_FOLLOWUP_2026-09-22.md` inkl. ejerinstruktionen i §0 (22/9). Del I nedenfor
er 22.–23/9-arbejdet; del II er 21/9-handoffet uændret, som reference.

Status-ord: **kodefærdig** · **verificeret i Studio** · **verificeret publiceret** · **mangler art** · **afventer data/hardware/ejer**.

---

# Del I — 22.–23. september 2026

## I.0 Baseline, versionsstyring og samtidige sessioner

| Punkt | Værdi |
|---|---|
| Studio ved start | place `131311258779917`, Edit, 167 scripts, `pull_source_from_studio.py --audit` 167/167, 0 drift, editor == Source |
| Native backup før ændringer | `artifacts/claude-20260922/baseline-before-polish.rbxl` (File → Download a Copy), 9.420.617 B, sha256 `66903fbba4487187240271e715041928b110babb3b326c5b394f4d03a0ebc3a0`. Kun lokalt (untracked) |
| Arbejdsbranch | `claude/trello-20260921` (lokal `2596df8` fra Codex ved start; Codex committede `55d42a8`, `bc1a1db`, `437d10f` undervejs — bevaret, ikke rørt) |
| Anden session i Studio | `Level4GateAccess` (ny Script) + GameManager/Routing/TunnelLobbyBuilder-ændringer fra `55d42a8` lå i Studio, men uden manifest-post. Verificeret Studio == HEAD med 73/73 blok-hashes (50-linjers djb2 over `execute_luau`) før baselinen blev re-registreret; manifest-post for `Level4GateAccess` tilføjet. Push-værktøjets CONFLICT var altså et forældet baseline-sha, ikke en reel afvigelse |
| Studio-skrivninger | kun pr. fil gennem `tools/push_repo_to_studio.py` (CAS + compile). Slettede scripts: destrueret i Edit-mode med **deaktiveret** kopi i `ServerStorage.Archive.FieldNotesRetired_20260922` (spejlet i repo). Efter hver runde `pull --audit` = 0 drift; ved afslutning 168/168 |
| Studio genstartet undervejs | `studio_id` skiftede to gange (`a476e358…` → `60f26cb1…` → `7b9759ba…`, sidste gang natten 22.→23.); audit bagefter 168/168, ingen ændringer tabt |
| Luau-værktøjet | `%TEMP%\codex-luau-0.737` (luau.exe + luau-compile.exe) blev slettet af en Temp-oprydning natten til 23/9. Ændringer efter det tidspunkt er compile-tjekket af `push_repo_to_studio.py` i Studio og kørt live i Studio; de Python-baserede offline-suiter kan først køres igen, når værktøjet er hentet ned igen (kræver ejerens ja til download) |
| Publicering | se I.9 |

## I.1 Status pr. opgave

| Opgave | Status | Commit |
|---|---|---|
| §0 Field Notes fjernet | **verificeret i Studio**: ingen NOTES-fane, ingen remotes/folders/pickups, ingen `ZyntraFieldNotesTitle`/tag-række, gammel profil loader (in-memory `FieldNotes` bevares inert), Rewards/Wheel/shop virker | `080a946` |
| §0 Try again-guide fjernet | **verificeret i Studio**: Level 1-død → lobby uden `TRY AGAIN`-tekst, beam, billboard eller `RetryGuideLevel`; gammel pakke med `RetryLevel` læses af ingen (offline `test_death_advice` §4); Level 4-dev-banner fjernet; førstegangsguiden `LEVEL 1 START HERE` **verificeret i Studio** 23/9 (en frisk kopi af det rigtige script med `ZyntraFirstLogin=true` — serverens eget input for en ny profil — tegnede billboard + 16 beams ind i Level 1-bayen; billede `lobby-first-entry-guide-still-works.jpg`) | `080a946` |
| A1 Level 4 tage/vinduer/facade | **verificeret i Studio** seed 101 (CLOSE) + 202 (TERRACE), begge husretninger: kip 19,5 over pladen ved z ±0,1, 14,2 ved udhæng (før: omvendt 12,6/18,4); ruder 0,4 studs **foran** ydermuren (før: 0,2–0,6 inde i den). Facade efter Codex' reference: udhæng + fascia, 3,0×4,4-vinduer m. ramme/sålbænk i bånd, dørkarm, porchsignal (venstre bånd) + husnummer (højre bånd), postkasse m. stolpe/låge/flag, trim-hegn, cylinderbakker; anomalier i samme akser (ekstra vindue over døren, forkert nummer `D0`, vendt postkasse, halvt gardin) — alle synlige fra fortovet (billeder I.5) | `ed5a3d8` |
| A3 Level 4 rolig start / fare | **verificeret i Studio**: `CalmLeadSeconds 24` → første usikre hus 25,4 s efter `RoundActive`; klientens lys følger kun trusler mod DENNE spiller (Neighbour ALERT/CHASE på én, eller huset man står i) og vender tilbage til ro; `ReduceFlashing` forlænger rampen (5,25 s mod 3,32 s målt); nedtælling `LEAVE HOUSE A2 -- 12s LEFT` inde i huset, ellers 3 s note inden for 70 studs | `ed5a3d8` |
| A4 Level 4 exit/retry | **verificeret i Studio**: `Level4_ExitPosition` = triggerens centrum; server fejer levende rødder i den åbne trigger (0,25 s); solo 3 signaler → 3 kontroller i rækkefølge (forkert rækkefølge afvist) → transitdør → `Escaped` på seed 101 og 202. Dev-retry-hintet blev bygget og derefter **fjernet igen** efter §0 | `ed5a3d8`, `080a946` |
| Level 4 Neighbour-kill | **verificeret i Studio** seed 202: PATROL → ALERT (0,1 s) → CHASE (1,4 s) → drab 2,7 s; kort `THE NEIGHBOUR GOT YOU` / `It saw you in the open and closed the distance.` / `NEXT TIME Break its line of sight; a house with a steady porch light hides you.` (billede) | — |
| B1 Rewards/Wheel-prikker + intro ([MsEn2mya](https://trello.com/c/MsEn2mya)) | **verificeret i Studio**: prik på WHEEL ved ubrugt gratis spin, væk efter collect; ingen prik på REWARDS ved 0 min spilletid; intro-kort efter første rigtige completion (Level 1-win → lobby), GOT IT → `RewardsIntroSeen` true, vises ikke igen. Prikker genberegnes ved hvert profil-push + én forsinket genlæsning ved UTC-reset (ingen ticker) | `9e4e6f8` |
| B2 COLLECT PRIZE ([25GLltY6](https://trello.com/c/25GLltY6)) | **verificeret i Studio** (in-memory profil): spin → `COLLECT PRIZE` → dobbeltklik → **én** udbetaling (Tokens 35→36, `WheelLast.Claimed=false→true`, Serial 1); Daily-claims bekræfter `<reward> collected -- N minutes of play today.`. Offline 370+557 checks: pending overlever dagskifte (spin afvises `Collect your prize first: …` og det gratis spin venter), tabt reply/retry, to claims, gemmefejl før/efter commit, gammel profil (historisk `WheelLast` normaliseres til claimed, betales aldrig igen) | `080a946` |
| B3 +50 % relays ([JYiwjBxw](https://trello.com/c/JYiwjBxw)) | **verificeret i Studio**: to solo-layouts placerede 3/3 relæer (mål 3, `Level1RelaySpawnTarget`/`Level1RelaysPlaced`), min. parvis afstand 226/369 studs; mål 1–6 spillere = 3,3,6,4,6,6 (`SPAWN_MULT` effektivt 2 i MasterConfiguration). Multiplayer-runde: **ikke kørt** (kun solo + offline 43 checks) | `080a946` |
| B4 Første CD-prompt | **verificeret i Studio** seed 1154781618 (`L3_S1_R05`): kun `COLLECT CD` vises ved introbordet på desktop og simuleret touch (`ForceTouchUI`); HIDE-prompten er slået fra mens CD'en er WORLD (23/24 borde åbne, kun introbordet), server afviser `CD_ON_TABLE`; efter pickup vender HIDE tilbage øjeblikkeligt og man kan gemme sig under samme bord (`Level3_Hiding=true`, bord 3). Kun første-CD-rummets bord; øvrige borde/cap/regler uændrede | `080a946` |
| C Level 2 bue-mesh-pilot | **kodefærdig, målt i Studio, kontakt OFF som standard.** Tal I.4. Visuel A/B **blokeret**: mesh bygget som EditableMesh renderer på klienten som sin bounding box (bevist med magenta-probe); kun et **uploadet** mesh-asset renderer. Levering: to `.obj` + integration bag kontakt + loader der kun tager asset-baserede meshes ved runtime | `3e533e7`, `2d24ac8` |
| §5 Analytics-rækkefølge | **verificeret i Studio + offline** (111 checks): `ProfileLoaded` før `Join` logger nu 1 så 2; dobbelt `Join` åbner én retry-loop; reserved arrival åbner ingen. Studio-ringen viser nu `onboard 1 Joined` → `onboard 2 ProfileLoaded` (21/9 manglede trin 1 i Studio, fordi profilen vandt kapløbet). Dashboard: **afventer publiceret trafik** | `c6cbad3` |
| §5 UIRegression 78 fejl | **verificeret i Studio 23/9: 78 → 0.** Fuld `RunAllCompact` (203 s): sikkert område 126, kø-modal 719, briefing-tekst 243, eksklusion 107, objektiv-hjørner 450, dispatch 210, terminal 1449, kontrolzone 22, same-frame 24, harness-lås 16, completion + fit 0 fejl, 22/22 scenarier, alt lånt state genoprettet. Grupperet og reproduceret i Studio 23/9 (samme 78 som 21/9; kørsel 188 s):<br>(1) **Kø-modal-banen, 44** — 11 var en reel kontraktfejl: Friend Boost-chippen skjulte sig med `Visible` alene og efterlod `InviteButton` Active under kø-skyggen → rettet i produktkoden (`UIDevice.SetInteractive` sammen med chippen). 33 var testens autoriserede nøgleliste, som var ældre end to autoriserede registreringer: `EntityDetectorScan` (ProtectionHUD-rækken, `bd72376` 20/9, samme `makeRow` som listens `SpeedPotionUse`/`RouteMarkerPlace`) og `FriendBoost` (chippen, 16/9) → listen opdateret med henvisning. Banen: 0 fejl.<br>(2) **Briefing-eksklusion, 7** — ejerens egen `d0ff99e` (10/9) ændrede `modalBlocksStore` fra `queueModal or briefing` til `queueModal or (InRound and briefing)`: lobby-railen er brugbar under Dispatch. Matrixen hævdede den gamle regel → rækkerne genformuleret til den nye regel + et NYT værn for reglens forudsætning (en nåbar opener deler ingen pixel med briefing-panelet — C4A-fejlen). In-round-halvdelen (DEV-telefonen) kan lobby-banen ikke nå; **verificeret manuelt i en Level 1-runde**: med briefing-panelet oppe afviser både toggle og kiosk telefonen; en allerede åben telefon får briefingen til at vige (samme vige-regel som i lobbyen). 107 checks, 0 fejl.<br>(3) **Terminal-fit, 11** — `Donation20K` er en engangs-GamePass; en konto der ejer den ser `OWNED` pr. design (`ZyntraStore.refreshDonationOwnership`). Forventet antal fratrækker nu ejede pass-tiers med butikkens egen test. 1449 checks, 0 fejl.<br>(4) **Level 1-objektivhjørnet, 14** — ingen produktfejl: siden `f3b8923` (20/9) gen-afleder PuzzleUI panel+toggle fra rundens tællere ved hvert layout-pass (by design, kommentar PuzzleUI:1046), så testens `Visible = true`-skrivninger i lobbyen blev overskrevet (11× "not visible"); detektor-rækkerne målte et kort der kun vises i NAV-mode, klemt af rækker lækket fra forrige enhed; 375×667 målte 5 lækkede rækker (titel + 3 rækker + besked), som serveren ikke længere kan producere. Bevis: den samme bane kørt INDE i en rigtig Level 1-runde gav 14 → 3, og de 3 var netop lækage-rækkerne. Rettet: ny Studio-only `UIRegressionPuzzleProbe` i PuzzleUI driver den RIGTIGE status-handler (serverens egne events og tekst), banen stager de to stakke en runde faktisk tegner (fuse-fase + afvisningsbesked `You have no fuses`; lever-fase med 3 rækker), nulstiller med den rigtige runde-slut-reset, og måler detektoren i NAV-mode efter `escape`.<br>(5) **To basisscenarier** — `objectives-panel`: scenariet viste footer-knappen OG det fulde brief, som RoundUI siden `9812b87` (2/9) aldrig viser samtidig på nogen formfaktor → scenariet viser nu kun panelet. `level3-reader-open`: lobby-only Friend Boost-chippen deler nu `TopRightPanel` med readeren (min egen `e4bc4a7`, 21/9); i spillet kan de aldrig ses samtidig → `resetScenario` slår lobby-only flader fra i in-round-rækker (chip via `Enabled`, rewards-introkort), ligesom railen.<br>(6) **Kontrolzonen, fundet under slutverifikationen** — rækken "hiding a registered control invalidates the zone" skjulte `drawn[1]`, altså den kontrol `GetTagged` tilfældigvis nævnte først. Var det `FlashlightPower`, tegner FlashlightController den igen hvert frame før den udskudte refresh, og zonen flytter sig med rette ikke (målt: `TouchRunHold`/`TouchPOV` 2 fires, `FlashlightPower` 0). Produktet er korrekt; rækken bruger nu harnessens egen registrerede probe, som banens header i forvejen foreskriver.<br>Plus: `Level4ObjectiveGui` i harnessens optional-liste. | `69ab222`, `2430e54` |
| §5 Token Earner | **ikke implementeret** (ejerinstruktion; formlen er fejlbehæftet — se 21/9 §7.1) | — |

## I.2 Ændrede Studio-paths

| Commit | Studio-paths |
|---|---|
| `ed5a3d8` | `ServerScriptService.Level 4 Systems.Level 4 Configuration / World Builder / Objective Controller`, `StarterPlayerScripts.Level 4 Lighting Controller / Level 4 Objective UI`, `GameManager` |
| `080a946` | SLETTET: `ServerScriptService.FieldNotesService`, `StarterPlayerScripts.Field Notes Client`, `ReplicatedStorage.ZyntraFieldNotes`, `ReplicatedStorage.ZyntraFieldNotesPage` (arkiv: `ServerStorage.Archive.FieldNotesRetired_20260922`). Ændret: `ZyntraMonetization` (Field Notes ud, `WheelLast.Claimed`, `ClaimWheelPrize`, `MarkRewardsIntroSeen`, `RewardsIntroSeen`), `ZyntraConfig`, `UIRegression`, `ZyntraStore` (NOTES-fane ud), `GameManager` (retry ud), `First Entry Guide` (retry ud), `Level 4 Objective UI` (dev-banner ud), `Lucky Wheel Client` (COLLECT), `Level 1 Systems.PuzzleManager`, `Level 3 Systems.Level 3 Hiding Controller`, `Level 3 Test Suite` |
| `9e4e6f8` | `ZyntraStore` (prikker + intro) |
| `3e533e7`, `2d24ac8` | `Level 2 Systems.Level 2 World Builder`, `Level 2 Configuration` (`Performance.ArchMeshRibs`, `ArchMeshRibAssets`) |
| `c6cbad3` | `ServerScriptService.ZyntraAnalytics` |
| `69ab222` | `StarterPlayerScripts.Friend Boost Client` (Invite står ned sammen med chippen), `UIRegression` |
| `2430e54` | `StarterPlayerScripts.PuzzleUI` (navngivet status-handler + Studio-only `UIRegressionPuzzleProbe`; ingen adfærdsændring live), `UIRegression` |

Nye/ændrede tests: `test_level1_relay_spawns.py`, `test_level3_first_cd_prompt.py`, `test_rail_dots_intro.py`, `test_daily_rewards.py` (wheel-flow + harness), `test_lucky_wheel_client.py`, `test_item_inventory.py`, `test_zyntra_store_compact.py`, `test_death_advice.py`, `test_daily_rewards_client.py`, `test_daily_rewards_page.py`, `test_level2_tunnel_height.py`, `test_zyntra_analytics.py`; slettet `test_field_notes.py`, `test_retry_guide.py`. Fem harnesses var forældede mod den levende kode (manglende `ZyntraDailyResearch`, `BindableEvent.Event`, `advancedStaminaBonus`, +30 %-potion, `Vector2`) og blev repareret — assertions kun ændret for bevidst ændret produktadfærd.

## I.3 Level 4 — målinger

- Seed 101 CLOSE / 202 TERRACE: 11 huse, 808 descendants, 10 lys (0 skygger), plan/brain/world-suite 163/18/66 checks, 0 fejl; offline plan 3172 (68 seeds), brain 38.
- Server Heartbeat 0,79 ms, physics 0,04 ms; klient p50 16,9 ms i forgrunden (66 ms-frames i samples er fokus-throttling ved vinduets kanter).
- Rolig start: `RoundActive` → første usikre hus 25,4 s (`CalmLeadSeconds 24` + 1 s evaluering). Lys ved indtræden i mørkt hus: CT 16,4→17,6, B 2,6→1,9, fog 180–900 → 70–380; tilbage til ro på gaden. Ramper 3,32 s / 5,25 s (ReduceFlashing).
- Exit: klient-drevet gang ind i triggeren → `Escaped` på 0,9 s; én tidlig miss (karakter droppet fra 2 studs højde) er grunden til server-sweepen.
- Kontrakt-doc `docs/LEVEL4_CONTRACTS_2026-09-21.md` har status-afsnit 22/9 (scripts findes; §1 er historie).

## I.4 Level 2 bue-mesh-pilot — tal (`artifacts/claude-20260922/level2-arch-mesh/MEASUREMENTS.md`)

Seed 1182081016 (resolved 1182604661), samme rundetilstand: descendants **71.214 → 55.444 (−22 %)**, `Texture` **42.051 → 29.103 (−31 %)**, Parts 25.223 → 22.221, +166 mesh-ribber, +1.328 usynlige fødder (4 pr. side, når 10,8 studs over gulvet — et hoppende hoved). Klient 60 Hz og server 1,2 ms begge veje. Kollision: stråler gennem åbningen misser, fod-stråler rammer hvor Part-ribberne ramte (12,09 mod 12,10), body-box i korridorcentrum = 0 kolliderende dele (den første version med kolliderende mesh gav 1 = hele ribben → navigatorernes `GetPartBoundsInBox` ville se en væg; forkastet). Live: pumpepar → Pool Slide spawnede på første probe, CHASE/MOVING, angreb og dræbte spilleren; ingen consolefejl. Familier på layoutet: `r13.20_vs1.90_fd1.50_a3.20_d2.20_s26` og `…fd1.80…` (bredde 34, DoorWidth 30 → radius 13,2; 26 segmenter).

**Blokering (ejer):** upload de to `.obj` (`artifacts/claude-20260922/level2-arch-mesh/`, 108 vertices/212 triangler, pivot = buecentrum = korridorcentrum + 1 stud op, X på tværs, Y op, Z langs, UV i 7-studs fliser) og sæt `Level 2 Configuration.Performance.ArchMeshRibAssets[key] = "rbxassetid://…"`. Først da kan den visuelle A/B laves (samme kamera som `level2-rib-closeup-A-parts.jpg`). At slå "Allow Mesh & Image APIs" til er **ikke** nok (klienten tegnede boksen selv i Studio, hvor API'et findes).

## I.5 Screenshots (`artifacts/claude-20260922/screens/`, native 1540×820)

Level 4: `level4-facade-after-seed101-intro.jpg` (samme kamera som Codex' `level4-facade-before.jpg`), `level4-anomaly-seed101-A1-drawncurtains.jpg`, `…B2-extrawindow.jpg` (+Z-facing), `…C2-reversedmailbox.jpg` (occupant-advarsel synlig), `…D1-wrongnumber.jpg`, `level4-neighbour-kill-card-seed202.jpg`.
Lobby/UI: `lobby-rail-wheel-dot-desktop.jpg`, `lobby-rewards-intro-card-desktop.jpg`, `wheel-collect-prize-desktop.jpg` (COLLECT PRIZE-hubben), `wheel-collected-desktop.jpg` (`1 POTION COLLECTED`, fanget i en burst 23/9; hub-loggen viser `COLLECTING` 18,60 s → `1 POTION/COLLECTED` 18,67 s → nedtælling 22,18 s, dvs. først efter serverens `Claimed=true`), `level1-death-card-after-retry-removal.jpg`, `lobby-after-death-no-retry-guide.jpg`, `lobby-first-entry-guide-still-works.jpg`.
Level 3: `level3-first-cd-prompt-desktop.jpg`, `level3-first-cd-prompt-touch.jpg`.
Level 2: `level2-corridor-A-part-ribs.jpg` / `level2-corridor-B-mesh-ribs.jpg` (tour shot 6), `level2-rib-closeup-A-parts.jpg` / `level2-rib-closeup-B-mesh.jpg` (samme kamera; B viser bounding-box-renderingen), `level2-rib-B-mesh-magenta-probe.jpg` (beviset), `level2-arch-mesh-probe-quad.jpg`.

## I.6 Asset-/rig-kontrakter til Codex

- **Level 4 facade** er stadig Parts/WedgeParts med `Level4_Placeholder`; alle navne fra kontrakt-doc §5 bevaret (`HouseNumber` m. `Level4_HouseNumber`, `PorchSignal`, `Mailbox` i `MailboxAssembly`, `AnomalySocket` + `Level4_Anomaly`). Nye konfigurationsknapper i `Level 4 Configuration.Lots`: `EavesOverhang 1.4`, `FasciaDepth 0.5`, `WindowWidth 3.0`, `WindowHeight 4.4`, `WindowFrame 0.35`, `WindowProud 0.3`, `FittingHeight 8.6`; farver `Trim/Fascia/Pane/Graphite/MailboxMetal/MailboxFlag/Curtain`. Dine at dreje; sig til, så de spejles.
- **Level 2 bue-mesh**: `.obj`-kilderne ovenfor er redigerbare (Blender ikke installeret her; genereret af `tools/level2_arch_rib_obj.py`, samme matematik som builderen). Kunstnerisk dom (flisejustering på soffitten, fase, bevel) er din efter upload.
- **PoolSlide-rig**: uændret; original kilde mangler fortsat (21/9 §5).

## I.7 Ejer-/Codex-beslutninger der er tilbage

1. Upload de to bue-`.obj` og sæt asset-id'er (I.4) — ellers forbliver `ArchMeshRibs=false` og pilotens gevinst ligger på hylden.
2. Rewards-intro for **veteraner**: koden viser kortet én gang for enhver profil med `CompletedLevels ≥ 1` og `RewardsIntroSeen ≠ true`, dvs. eksisterende spillere ser det én gang ved næste rolige lobby-øjeblik. Sig til hvis det kun skal være helt nye clears.
3. B3 multiplayer-runde (4–6 spillere) er ikke kørt; kun offline + solo.
4. Token Earner, C1–C3/D1–D3, PoolSlide-art: uændret backlog (21/9 §6–7).
5. Publicering af 22.–23/9-arbejdet (I.9) afventer ejerens ja.
6. Luau 0.737 skal hentes igen fra den officielle luau-lang-release (kræver ejerens ja til download), før de Python-baserede offline-suiter kan køres igen (I.0).

## I.8 Ikke verificeret (ærligt)

Fysisk telefon/tablet; rigtig teleport-retur (kun Studio-lokal lobby); to spillere ved første CD-bord (kun offline `HideOccupantCap`-logik uændret); dashboard-ingestion; DataStore-wheel-flow mod rigtig DataStore (Studio-profil er in-memory; UpdateAsync-disciplinen er kun offline-harness); UIRegression-udfald se I.1.

## I.9 Publicering

**Ikke publiceret.** Alt i del I ligger i Studio (Edit, `pull --audit` 168/168, 0 drift) og på `claude/trello-20260921`, men publicering til place `131311258779917` kræver ejerens udtrykkelige ja. Level 4 er dev-gated (`Level4GateAccess`/`Level4DevEnabled`) og følger med en publicering som dev-only, ikke som et level. Ved publicering gemmes Roblox' kvittering (versionsnummer fra Studio-loggen) her, og serverne genstartes ikke.

---

# Del II — 21. september 2026 (reference, uændret)

Skrevet løbende af Claude (al kode). Opgavegrundlag: `docs/CLAUDE_PROMPT_2026-09-21.md`.
Status-ord: **kodefærdig** · **verificeret i Studio** · **verificeret publiceret** · **mangler art** · **afventer data/hardware**.
**Publiceret: v1973** (2026-09-21 22:47 UTC, Studio-log `artifacts/claude-20260921/publish-log.txt`: `Place published … Add publish notes to v1973`). Alt i fase A og B nedenfor ligger i v1973. **Level 4 er kommet i Studio efter v1973 og er IKKE publiceret**; det er dev-gated og må ikke publiceres som et level.

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
| A3 PoolFoam overlap ([jecT8s86](https://trello.com/c/jecT8s86)) | **verificeret i Studio** for klynge om fælles mål og spawn-afstand (solo). Korridor-møde og flere spillere: kun offline-test | §3.3 |
| A4 Lag/render ([Zpj0Gkbb](https://trello.com/c/Zpj0Gkbb)) | målt på PC, skjulte tile-flader cullet (**verificeret i Studio**, ingen synlig ændring); den store gevinst kræver art-beslutning om hvælvingsbuerne; mobil **afventer hardware** | §3.4 |
| A5 Level 3 første CD + CD-reader ([6BVH4WmN](https://trello.com/c/6BVH4WmN)) | **verificeret i Studio** (solo, PC + alle simulerede touch-enheder i UIRegression). To spillere og fem afleveringer: ikke kørt | §3.5 |

### Fase B

| Kort | Status |
|---|---|
| B1 Shoptekster ([xQWVkwhw](https://trello.com/c/xQWVkwhw), [UNRk7Qy8](https://trello.com/c/UNRk7Qy8)) | tekst **kodefærdig og i Studio**; event-måling under B2 |
| B2 Analytics ([bIFdNWUf](https://trello.com/c/bIFdNWUf)) | **kodefærdig, verificeret i Studio** på ring-niveau (Studio sender bevidst intet). Dashboard-modtagelse: **afventer publiceret release**; data/kohorter: **afventer data**. Schema: `docs/ANALYTICS_SCHEMA_2026-09-21.md` |
| B3 Dødsårsag, råd og retry ([PR0ersiy](https://trello.com/c/PR0ersiy), [us5TWr9O](https://trello.com/c/us5TWr9O)) | **verificeret i Studio** (solo, PC): rigtig død → korrekt årsag + råd, retry-guide til det spillede level. Øvrige årsager kun via dev-seam/offline; nyspiller-forståelse: **afventer personer**. Queue-/briefing-/loadtid og "tilgivende første møde" pr. entity er **ikke lavet** (se §6) |
| B4 QA/marketing | **afventer personer/hardware**; se §6 |

### Fase C/D

Level 4 blokmodel + én fungerende prototype (`C4`, [Y2xXThBN](https://trello.com/c/Y2xXThBN)): **kodefærdig og verificeret i Studio solo** som dev-only runde (flag + DevAccess for alle deltagere; lobby-gaten siger stadig "coming soon"). §3.8 og `docs/LEVEL4_CONTRACTS_2026-09-21.md`. C1–C3 og D1–D3: **ikke påbegyndt** (§7).

## 2. Ændrede Studio-paths og commits (lokale commits på `claude/trello-20260921`)

| Commit | Indhold | Studio-paths |
|---|---|---|
| `7509fb9` | PoolSlide horisont-planlægning + request-tracing | `ServerScriptService.Level 2 Systems.Level 2 Pool Slide Controller`, `…Navigator` |
| `e4bc4a7` | L3 første CD i entry-rummet + CD-reader | `…Level 3 Systems.Level 3 Layout Generator`, `…Objective Controller`, `StarterPlayerScripts.Level 3 Reader Client`; test `tools/tests/test_level3_first_cd.py` |
| `390f5aa`, `f58e493` | PoolSlide-lyd: ejerskab + mund følger animeret bone | `ReplicatedStorage.Level 2 Entity Audio Bank`, `StarterPlayerScripts.Level 2 Entity Audio`, `…Level 2 Sound Controller`; tests `test_pool_slide_audio_states.py`, `test_spectate_audio_gates.py` |
| `0790135`, `521d80f` | PoolFoam separation + klynge-rettelse | `…Level 2 Pool Foam Controller`, `…Navigator` (ny `Sidestep`), `…Configuration` (blok `Separation`); test `test_pool_foam_separation.py` |
| `a1248c8` | L3 rumopslag i plan-koordinater; SlideContinuationSafety kaster ikke længere på forankret rod; UIRegression-række | `…Level 3 Objective Controller`, `ReplicatedStorage.SlideContinuationSafety`, `ReplicatedStorage.UIRegression` |
| `0a83253`, `afa3fb1` | Load-tids-readbacks (pcall'et) + måleartefakter | `…Level 2 Round Adapter`, `…Level 3 Round Adapter` |
| `60a8d4b` | Skjulte tile-flader cullet | `…Level 2 World Builder`, `…Level 2 Configuration` (`Performance.CullHiddenTileFaces`); test `test_level2_tile_face_culling.py` |
| `1c9ff51`, `e3891a4`, `a6aea0a` | Dødsårsag + råd på dødskortet, retry-guide i lobbyen | NY `ReplicatedStorage.DeathAdvice`; `ServerScriptService.GameManager`; ét `Mark`-kald før drabet i `Level 1 Systems.EntityKill`, `…MazeGenerator`, `Level 2 Pool Foam Controller`, `Level 2 Pool Slide Controller`, `Level 3 Mall Manager AI Controller`; `StarterPlayerScripts.RoundUI`, `…First Entry Guide`; tests `test_death_advice.py`, `test_retry_guide.py` |
| `5e775e6`, `72caec6` | Analytics (funnels + custom events) | NY `ServerScriptService.ZyntraAnalytics`; hooks i `GameManager`, `TeamObjectives`, `ZyntraMonetization`, `ZyntraDetectorService`, `StarterPlayerScripts.Shop Display Client`; test `test_zyntra_analytics.py`; `docs/ANALYTICS_SCHEMA_2026-09-21.md` |
| `86caa46`, `bcb32ce`, `29df626`, `7aba59a` | Level 4 The Quiet Suburbs, dev-only | NYE: `ServerScriptService.Level4Generator`, mappe `ServerScriptService.Level 4 Systems` med `Level 4 Configuration / Plan Generator / Neighbour Brain / World Builder / Objective Controller / Neighbour Controller / Round Adapter / Test Suite`, `StarterPlayerScripts.Level 4 Lighting Controller`, `…Level 4 Objective UI`. Ændrede: `GameManager` (`LEVEL4_DEV_GATE_20260921`-hunks, `ServerStorage.Level4DevStart`), `Round Completion Routing` (`DevCeiling/ClampLevelTo/NextLevelTo`), `Round Entry Client` (grænse 3→4), `RoundUI` (lys-ejerskab), `DeathAdvice` (`L4Neighbour`), `ZyntraAnalytics` (L4-tag); tests `test_level4_plan.py`, `test_level4_neighbour_brain.py` |
| `d8edb14` | Mirror af en ANDEN sessions Studio-ændringer (detector-visual/readout, shop-demo) | `ReplicatedStorage.ZyntraDetectorVisual`, `StarterPlayerScripts.ZyntraDetectorClient`, `…Shop Display Client` — ikke lavet her |
| `8e97018` | Shoptekster | `ReplicatedStorage.ZyntraConfig`, `StarterPlayerScripts.Shop Display Client`, `ServerScriptService.ZyntraMonetization` |

Branchen er pushet til GitHub (`origin/claude/trello-20260921`); draft-PR [#4](https://github.com/ERN-Studios/ERN-Roblox-Horror/pull/4) stacket på PR #3 (intet merget). Publicering: se §9.

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
Anden Studio-runde: spawn-groan (`Level 2 Slide Alert`) 2 s efter spawn, første periodiske `Level 2 Slide Mouth` 11 s senere under chase (interval 7–14 s), og efter et **reelt despawn** (modellen fjernet på serveren → `Active=false`, state `REMOVED`) kom den fjerne pipe-groan tilbage 36 s senere (pause 24–42 s) og spillede ~8 s.
Ikke verificeret: stream ud/ind, andet spawn i samme runde (controlleren spawner kun én gang pr. runde), lydniveauer/retning for øret, spectator-mix. Lyttetjekliste: se agentens rapport gengivet i §5 (lydkontrakt).

### 3.3 PoolFoam (A3)

Studio, seed `1182081016`, én pumpe (fase Foreshadow: fem aktive, ingen angreb), stillestående spiller: alle fem konvergerede på spilleren inden for et minut. Live-modellen er final art, bbox 5,17 × 11,05 × 4,0 → målt radius 2,59, kontakt 5,17, med padding 6,67. Uafhængig sampling (0,5 Hz): par-afstande 6,48–6,7 = præcis den polstrede kontaktafstand. Men controllerens egne readbacks viste korte reelle overlap: `MinSeparation` 3,2, `OverlapFrames` +1/s, `YieldCount` +2–3/s uden loft — "back-out"-reglen (til korridor-møder) fyrer kontinuerligt i en stillestående klynge og bakker gennem naboer. Rettelse (`521d80f`): ventetiden til back-out armeres kun når den med forkørselsret reelt er blokeret og vil forbi; hverken back-out eller release må krydse en anden krop (`Navigator:Retreat(maxDistance, isClear)`). Samme runde efter rettelsen: alle fem i ring om spilleren i 97 s → `OverlapFrames` 0, `YieldCount` 0, `MinSeparation` 6,41 (kontakt 5,17), uafhængig 10 Hz-sampling: 0 samples under kontakt, løbende min 6,62; passets pris 0,012–0,017 ms. Spawn: mindste parafstand mellem de fem 115,4 studs på denne seed. Naturlig runde med to pumper (120 s): min 8,99, 0 overlap. Ikke reproduceret i Studio: head-on i smal korridor (dækket af offline-test: 0 overlap, 10 begrænsede back-outs, forkørselsretten kommer igennem) og klynge der jager et bevægende mål (foams slipper et mål der går fra dem).
Før-tilstand: ingen separation overhovedet (alle dele forankrede, `CanCollide = false`, navigatoren ekskluderer hele runtime-mappen).

### 3.4 Lag (A4) — `artifacts/claude-20260921/level2-perf/MEASUREMENTS.md`

PC, Studio i forgrunden: klient 16,7 ms p50 / 18,4 p95 / 22,1 max (60 Hz-loft, 0 frames > 33 ms); server Heartbeat 0,98 ms i ro. Auditens "ca. 15 FPS" var baggrunds-throttling. Strukturel afviger: **44.923 af 74.654 verdens-descendants er `Texture`-instanser** (én pr. flade, seks som standard); 138–154 lys, alle med skygger; 21.261 dele med CastShadow. Streaming-radius/-mode kan ikke læses fra MCP-tråden (capability). Nye readbacks: `Level2_/Level3_LayoutSeconds`, `BuildSeconds`, `WorldDescendants`. Lavet (`60a8d4b`): Texture kun på flader en spiller kan se for hallvægge, korridorvægge, søjler og ring-buer (kontakt `Level 2 Configuration.Performance.CullHiddenTileFaces`; slået fra giver den gamle adfærd præcist). Målt: 44.923 → 42.051 Textures, 74.086 → 71.214 descendants. Fast kameratur (12 vinkler) + pixel-diff: 0,00–0,13 % forskel i de 9 stabile vinkler = samme støjgulv som to uændrede kørsler; ingen synlig ændring. **Hovedfundet**: korridorernes hvælvingsbuer (`Arch Rib`, `Arch Rib face`, `Corridor Arch Spandrel`) er 32.224 af 42.051 Textures (77 %) og 13.454 dele — cirka halvdelen af alle dele i Level 2. Hver bue er bygget af mange korte kassesegmenter med 2–3 tile-Textures hver; alle deres flader er synlige, så culling kan ikke røre dem. Det er her mobil-gevinsten ligger (se assetlisten).

### 3.5 Level 3 (A5)

Seed `1154781618` (pinned), solo: `Level3_EntryRoomId == Level3_FirstCDRoomId == L3_S1_R05`; præcis fem CD'er i fem forskellige rum; CD 1 ligger på bordet i første rum efter ankomstkorridoren. `Level3_Room` på spilleren: `Arrival` → `""` i korridoren (21 studs fra CD'en, én væg imellem → ingen tekst) → `L3_S1_R05` inde i rummet → readeren viser præcis `IN THIS ROOM` i `UIStyle.Color.Danger`, pulserende 0–0,40 transparens (stabil med `ReduceFlashing`). Pickup → `CARRIED`, position nil, readeren skifter straks til næste CD (`CD // ▮□□□□ 61m`). Død med CD i hånden → `DROPPED` på sidste sikre gulvposition med rum-id. Reader-panel: øverst til højre, 248 × 101 px ved 1539 × 809.
Fundet og rettet undervejs: rumopslaget sammenlignede verdenskoordinater med planens lokale rektangler (`WorldOrigin` 6200,24,0) — ingen spiller var nogensinde "i et rum". Offline-testen kunne ikke se det; første Studio-kørsel gjorde.
Observation til polish: alle fem CD'er ligger på rummets **skjulebord**, og både `COLLECT CD` og `HIDE UNDER TABLE` bruger E. Roblox viser den prompt man sigter på (verificeret: sigt på CD'en → COLLECT, sigt under bordet → HIDE). Det er eksisterende adfærd for alle CD'er, men for den garanterede første CD kan en ny spiller komme til at gemme sig i stedet for at samle op. Forslag: slå bordets hide-prompt fra mens dets CD er `WORLD` (kræver ændring i Hiding Controller; ikke lavet).
Touch/tablet: `UIRegression.Compact("ObjectiveCornerMatrix")` i play-session — 399 checks, alle Level 3-rækker (readeren i øverste højre safe-hjørne + readout passer i panelet) består på samtlige simulerede telefoner, tablets og desktops. De 14 fejl i kørslen er alle **Level 1**-rækker (`Level1Objectives is not visible …`, detector-readout på 568×320 og 667×375) i filer denne opgave ikke har rørt (PuzzleUI uændret siden baseline) — forældede rækker efter objective-feed-ændringen 20/9, bør ryddes op særskilt.
Ikke verificeret: to spilleres pickups, fem afleveringer + exit, fysisk enhed, spectator-visning.

### 3.6 Dødsårsag og retry (B3)

Serveren markerer spilleren på linjen før det autoritative drab (`DeathAdvice.Mark(player, key)`), GameManagers `hum.Died` tager mærket (≤ 3 s gammelt, ellers `Unknown`) og tilføjer nøglen **bagest** i de eksisterende payloads: `"death", name, position, causeKey` og `"partydown", 15, lastDeathName, causeKey`. Nøgler: `L1Entity`, `L1Pit`, `L2Foam`, `L2Slide`, `L3Manager`, `Unknown` (ingen opdigtet forklaring, intet råd). Al tekst ligger i `ReplicatedStorage.DeathAdvice` med kodehenvisning pr. regel.
Studio, Level 2, rigtig død til PoolSlide: payload `death(mikkelczar, (-570.6,3.8,-408.8), L2Slide)` + `partydown(15, mikkelczar, L2Slide)`; kortet viste `THE SLIDE STRUCK` / `The pool slide landed its swing.` / `NEXT TIME` / `Step behind it during the windup; its swing is locked forward.` Fundet og rettet i Studio: (1) et solo-dødsfald er også PARTY DOWN, hvis modal + skygge dækkede/dæmpede kortet i hele dets levetid — kortet løfter sig nu over skyggen, dokker øverst som titel + råd på lave viewports (< 620 px) og lever til modalen lukker; (2) retry-guiden pegede på Level 1 efter et Level 2-tab, fordi `cleanupActiveWorld` nulstiller `activeLevel` før hjemturen — den læser nu `lastRoundLevel` (verificeret: `RetryGuideLevel = 2`, billboard `TRY AGAIN · LEVEL 2` over Level 2-pladen med beam-kæde).
Ikke verificeret: de fire andre årsager ved rigtig død (kun dev-seam `player:SetAttribute("DevDeathCause", key)` i Studio + offline-test), teleport-stien (`RetryLevel` i ReturnToLobby-pakken) på publiceret server, telefon-layoutet af det dokkede kort på fysisk enhed.

### 3.7 Analytics (B2)

Studio-runde (ringen i `ServerStorage.ZyntraAnalyticsDebug`, `Mode = studio`, `Faults 0`, `Dropped 0`): `onboard 2 ProfileLoaded` → `onboard 3 RoundLoaded L2` → `onboard 4 RoundStarted L2` → `zq_round_start L2|returning|PC` → `onboard 5 FirstObjective L2` → `zq_objective_first` → `zq_first_death 23 L2|l2slide|returning` → `zq_round_outcome 39 L2|died|returning` → `retry 1 BackInLobby`. Enhedsklassen (`PC`/`Phone`/`Tablet`) meldes én gang af klienten som fast enum og bruges kun som segment. I Studio lander `Joined` efter `ProfileLoaded` (GameManager initialiserer langsommere end profilen loader), så trin 1 ses ikke i ringen dér; på en rigtig server kommer join før DataStore-svaret, og Roblox bagudfylder under alle omstændigheder tidligere trin.
Ikke verificeret: modtagelse i Creator Dashboard (kræver publiceret release), shop view/demo-events i en rigtig lobby-gennemgang, købsevents (ingen rigtig transaktion kørt).

### 3.8 Level 4 — The Quiet Suburbs (C4), dev-only

Start i Studio: `workspace:SetAttribute("Level4DevEnabled", true)`, evt. `Level4Seed`, `ServerStorage.Level4DevStart:Invoke()` (afviser `DISABLED`/`NOT_DEVELOPER`/`BUSY`/`RESERVED_SERVER`). Verificeret solo, seed 101 (variant 3 "CLOSE") og 202 (variant 1 "TERRACE"): plan 0,00 s, build 0,05–0,06 s, 535–548 descendants, 11 huse, 10 dynamiske lys (0 med skygge), 530 placeholder-dele; in-Studio-suite 66 checks / 0 fejl; tre signaler (1: 16 studs, ingen hold; 2–3: 10 studs, 1,2 s hold) → `BEACON`; tre kabinetkontroller **i rækkefølge 1→2→3** (2 før 1 afvises) → `EXIT_WARNING` (≈4 s) → `EXIT`; trigger-volumen ved busstoppestedet gav `Escaped=true`, `zq_round_outcome … escaped`, `onboard 6 FirstEscape L4`, completion-flow og lobbyretur uden efterladte instanser. Neighbour: `PATROL → INVESTIGATE` (støj ved signal 2) → `ALERT` (0,2 s efter sigtelinje på 12,7 studs) → `CHASE` (1,5 s) → drab 2,4 s; dødskort `THE NEIGHBOUR GOT YOU` med råd.
Fundet og rettet i Studio: Neighbour ignorerede `EntityPaused` (gik 200 studs og dræbte under pause); dets drab bar ingen dødsårsag; lys-klienten kastede ved hver sync (`ColorShiftTop` → `ColorShift_Top`); RoundUI lagde Level 1-nat over kvarteret (nu `Level4LightingOwnedByController`-håndtryk som Level 2/3); analytics-taggede Level 4 som `L0`.
Åbne observationer til polish/design: (1) `Level4_ExitPosition` ligger 3,5 studs foran trigger-volumen (spilleren skal gå ind i stoppestedet — fint i spil, men reader/pejling bør pege på volumen); (2) `Level4_UnsafeHouses ≥ 1` fra start gør lys-graden "danger" hele runden i variant 3 — den varme eftermiddag ses reelt kun når ingen huse er farlige; (3) `RetryGuideLevel = 4` efter et Level 4-tab peger på en bay der ikke findes (guiden tegner intet); (4) L3→L4 Continue virker kun i Studio, ikke over en rigtig teleport (`Routing.ArrivalPacket` clamper til `MaxLevel` — fejler sikkert). Ikke målt: 8–12 min spilletid, mobil, flere spillere, om Neighbour kan løbes fra, navmesh med `AgentRadius 2.7`. Ingen art/animation/lyd (slot-liste i kontrakterne).

## 4. Screenshots

`artifacts/claude-20260921/screens/` (native Studio-vindue, desktop 1540×820): `death-card-with-partydown-desktop.jpg` (rigtig død, dødskort + PARTY DOWN), `death-card-L2Slide-desktop.jpg` (dev-seam i lobbyen), `death-real-L2Slide-partydown-desktop.jpg` (før docking-rettelsen: kortet væk under modalen), `retry-guide-lobby.jpg`, `level4-death-neighbour-desktop.jpg`, `level4-blockout-main-street.jpg` (blokmodel fra servicepassagen). Level 2-kameraturen (12 vinkler × 3 kørsler) ligger i session-scratchpad uden for git. Level 3-readeren (`IN THIS ROOM`) er beskrevet i §3.5; touch-tiers er kun kørt i UIRegression, ikke fotograferet.

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

### Level 2 hvælvingsbuer som mesh (forslag; kræver ejer-/art-beslutning)

Mål: erstat de ~13.450 kassesegmenter + ~32.000 Textures med én MeshPart pr. bue (eller pr. korridorhvælving). Geometri i dag (`makeArchSpan` i `Level 2 World Builder`): elliptisk bue, `VerticalScale` 1,9 (`CorridorVaultVerticalScale`), ribbe-tværsnit `AxialDepth` 3,2 × `RadialDepth` 2,2 studs, segmentoverlap 0,9; tile-billedet er `TILE_TEXTURE` med 7 studs pr. flise og tint `TILE_TINT`, farve `TileWarm` (236,227,196). Leverance: én bue-mesh (UV med 7-studs fliser langs buen, separat materiale-ID ikke nødvendig), collision ikke nødvendig (ribberne er dekorative hvor `CanCollide=false`; hvælvingens collision ligger i `Vault Strip`). Når meshen findes, skifter jeg builderen (bag en kontakt) og måler igen med samme seed/kameratur. Forventet: ~71k → ~26k descendants.

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
5. **Level 2 hvælvingsbuer som mesh** (§5): 77 % af alle tile-Textures og ~halvdelen af alle dele. Ejer/art-beslutning; builder-ændring følger.
6. **UI-regression** (`RunAllSummary`, 2717 checks): 78 fejl i tre baner — 14 Level 1-rækker (`Level1Objectives is not visible …`, detector-readout på 568×320/667×375), 11 `Donate: exactly 9 of its card actions are reachable (8 reachable of 9 tagged, 1 stood down with a reason)`, 7 `BriefingExclusionMatrix` om store-opener under briefing. Ingen af dem rører filer denne opgave har ændret (PuzzleUI/ZyntraStore-opener/Donate er urørte), så de vurderes forældede efter 20/9-ændringerne — men det er ikke bevist mod baseline i Studio. Bør ryddes som egen opgave.
4. **PoolSlide-størrelse**: hvor meget større (tal), før korridor-fit genverificeres.

## 8. Instruktion til Codex

Lav polish, art og asset-feedback ud fra kontrakterne ovenfor. Har du brug for en kodeændring (nye attributnavne, en ekstra attachment-opslagssti, andre intervaller end dem der er knapper til), så skriv den som en konkret anmodning til Claude med fil/funktion og ønsket adfærd — ret ikke runtime-scripts direkte, så rollefordelingen og Studio-pariteten (154/154, 0 drift) bevares. Rene værdier i `Level 2 Entity Audio Bank`, `Level 2 Pool Slide Configuration` (de to reference-hastigheder) og `AnimationId`'er i templaten er dine at dreje på; sig til bagefter, så de bliver mirroret.

## 9. Release

**v1973 publiceret 2026-09-21 22:47 UTC** fra Studio (File → Publish, bekræftet `PublishSuccessful` + `Place published` i Studio-loggen; ingen servere genstartet). Indhold: fase A (A1–A5), B1, B2 (analytics), B3 (dødsårsag/retry). Før publicering: 156/156 scripts synkrone, editor==Source, ingen efterladte probe-instanser, `EntityPaused=false`, offline-suite 45/60 grønne hvor alle 15 røde også var røde på baseline (`06a0642`) på nær én, som var min egen og blev rettet inden publicering.

Efter v1973 er Level 4 (dev-only) landet i Studio (167 scripts). Det må gerne publiceres — en normal spiller kan ikke nå det (flag + DevAccess for alle deltagere; gate siger "coming soon") — men det er **ikke** gjort, og skal ikke annonceres som indhold. Anbefaling: publicér efter Codex' første polish-runde, samlet med eventuelle kode-tilbageløb.

Dashboard-verifikation af analytics kan først ske mod v1973-trafik (`docs/ANALYTICS_SCHEMA_2026-09-21.md` §8).
