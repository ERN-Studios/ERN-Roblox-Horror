# B3: uafhængig offline-verifikation, 2026-10-09

Udført af Codex efter overdragelsen fra Claude. Produktkode, tests, Studio, Studio-lås og git-state er ikke ændret. Denne rapport er den eneste tilføjede repo-fil. Midlertidige baseline- og reproprogrammer blev kørt i automatisk ryddede Windows Temp-mapper. Der er hverken publiceret eller committed.

## Resultat

De fem B3-scripts kompilerer ved **Luau 0.737, `-O0`**. **15 suites består**, i alt **6187 Luau-checks** plus HUD-templatekontrollen med 0 findings. `test_round_hud_local` består nu også NoiseReporter-konstantkontrollen, der var expected-red før B3 phase 2.

**Én B3-layoutfejl er reproduceret:** på små PC-vinduer placeres stamina og GRACE for langt til højre. Alle de eksisterende B3-checks er grønne, fordi PC-placering kun dækkes ved 1920, 1366 og 1280 px. Ingen assertions er svækket.

Fire yderligere suites fejler eller kan ikke fuldføres. Deres fejl er dokumenteret nedenfor som allerede til stede i manifest-baselinen eller ved HEAD. De er ikke B3-regressioner.

Ingen live Studio-kontrol blev udført af denne verifikator. Rendering, rigtig input, faktisk CanvasGroup-clipping og multiplayer-spectating kræver fortsat den koordinerede Studio-QA.

## Afgrænsning og grundlag

Læst: `CLAUDE.md`, `_local/session-rules.md`, relevante offline/parallel-session-memorynoter, hele `b3/B3-DESIGN.md` inklusive kritik K1-K17, samt `hud-b3-phase2-wf_57ad49b8-90d.js`. Knowledge graph blev forespurgt; rapporten er fra 2026-09-16 og beskriver ikke de nye B3-elementer. Derfor er konklusionerne baseret på aktuelle scripts, tests og de rigtige Framewisp-dumps.

Verifikationen omfatter alle Python-suites under `tools/tests`, hvor søgningen `RoundHud|Round HUD|NoiseReporter|ProtectionHUD|UIRegression|UIDevice` ramte, plus briefens `test_spectator_vitals` og `test_hud_templates`.

Git HEAD under kontrollen: `1be05fc9f79d25392af772325303e3d3802b0ac1`. Source-hashes nedenfor blev registreret ved kompileringen; rapporten er et øjebliksbillede af et delt checkout.

## Kommandoer

Interpreter findes og blev kørt fra:

```text
C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/CodexTools/luau/0.737/luau.exe
```

For hver suite: `$env:LUAU_BIN='<ovenstående>'; python -B tools/tests/<suite>.py`. Templatekontrollen: `python -B artifacts/hud-final-20261008/tests/test_hud_templates.py`. Kompilering: `luau-compile.exe -O0 --null <fil>`.

## Kompilering

| Fil | Resultat | SHA256 på testet kilde |
|---|---|---|
| `ReplicatedStorage/RoundHud.ModuleScript.lua` | exit 0, -O0 | `2230d80c0aef760e4949638526d123c6cb9d195a84fe7c4ad5d2e55f171793e8` |
| `StarterPlayer/StarterPlayerScripts/Round HUD.LocalScript.lua` | exit 0, -O0 | `4aefae8c4dd44b502293bbbd98df982874c3268139703bdb7e42ac85fc9da29e` |
| `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua` | exit 0, -O0 | `e94ae1b6460ccbf11c334b146a107a66dffa60a49aa9682c3a0a107611b7e8a3` |
| `StarterPlayer/StarterPlayerScripts/ProtectionHUD.LocalScript.lua` | exit 0, -O0 | `795901a09d859556d2efeaf433c6d3fb592030dfa71f5ab171c32f3b110fc12c` |
| `ReplicatedStorage/UIRegression.ModuleScript.lua` | exit 0, -O0 | `1ee56c8a46280e8473f5e461bd3383e00621987c1e1f1604dcf8a2719c8a706a` |

## Suites

| Suite | Resultat |
|---|---|
| `test_round_hud` | PASS, 185 |
| `test_round_hud_local` | PASS, 460; MARKER_BOTTOM=54, MARKER_BOTTOM_TOUCH=22, KIT_RIGHT=544 matcher NoiseReporter |
| `test_controller_input` | PASS, 131 input + 86 B2 touch + 65 B3 stamina |
| `test_equipment_hud` | PASS, 750 |
| `test_flashlight_player_control` | PASS, 730 control + 226 PC-widget + 249 touch-cell |
| `test_lucky_wheel_client` | PASS, 657 |
| `test_speed_potion` | PASS, 498; briefens tidligere harnessfejl er løst |
| `test_touch_control_plan` | PASS, 545 |
| `test_ui_style` | PASS, 102 |
| `test_zyntra_detector_client` | PASS, 123 |
| `test_dev_free_respawn_offer` | PASS, 17+24 developer, 3+8 almindelig spiller |
| `test_friend_boost` | PASS, 845 |
| `test_level4_queue_choice` | PASS, 449 server + 20 client |
| `test_spectator_vitals` | PASS, 14 |
| `test_hud_templates` | PASS, 0 findings på HUD_PC/HUD_Touch/HUD_Screens; rigtige dumps, ikke synthetic fixture |
| `test_lobby_shop_display` | FAIL, `expected 8 product textures, found 10` |
| `test_round_exit_hold` | FAIL, nil function i `applyLayout` |
| `test_zyntra_store_compact` | FAIL, modals-fixture forventer 6, den rigtige liste har 8 |
| `test_push_repo_to_studio` | IKKE FULDENDT: 25 checks bestået; 2/18 scenarier udført; 16 ikke udført. Interpreterdetektion kalder et ikke-understøttet `--version`. Exit 1; ikke et pass. |

## Reproduceret B3-defekt: smal PC-layout

`NoiseReporter.LocalScript.lua:749-754`: `bar.Room` er sand for enhver non-touch-layout. Centrum er mindst `Safe.Left + KIT_RIGHT + 8 + BAR_HALF = Safe.Left + 712`. Med en 320 px bar bliver højrekanten mindst `Safe.Left + 872`, uden kontrol mod `Safe.Right`.

Uafhængigt reproprogram kørt over **den rigtige B3-section, RoundHud, ShopBinder og HUD_PC-dump** via `test_controller_input.b3_program()`. De eksisterende cases blev fjernet fra scratchprogrammet; kun setup og de nye vinduesbredder blev kørt. Procedure: sæt pointer-layout med `Safe={Left=0,Top=58,Right=width,Bottom=600}`, kald `setup({layout=layout})`, `S.Paint(0.5,false,true)`, `ctx:Advance(0.01)` og læs den monterede CanvasGroup.

| Safe-bredde | Centrum | Bar venstre/højre | Uden for Safe | Visible |
|---|---|---|---|---|
| 1920 | 960 | 800 / 1120 | 0 | true |
| 1366 | 712 | 552 / 872 | 0 | true |
| 1280 | 712 | 552 / 872 | 0 | true |
| 880 | 712 | 552 / 872 | 0 | true |
| 872 | 712 | 552 / 872 | 0 | true |
| 860 | 712 | 552 / 872 | 12 | true |
| 800 | 712 | 552 / 872 | 72 | true |
| 640 | 712 | 552 / 872 | 232 | true |

Grænsen er **872 px til rådighed i Safe**, ikke ubetinget 880 fysisk vinduesbredde; eventuelle insets flytter den fysiske grænse. Barens lave stamina-del kan derfor blive skjult i et smalt vindue.

`Round HUD.LocalScript.lua:141-143` bruger samme minimumscentrum til markeren. Et andet scratchprogram kørte **hele den rigtige Round HUD og den rigtige UIDevice** med 880/860/800/640x600 viewport, 58 px topbar og Reentry-GRACE i 10 sekunder. De gamle testcases blev ikke genkørt:

```text
PC880 Safe=[0,880] GRACE=[594,829] overflow=0 shown=true
PC860 Safe=[0,860] GRACE=[594,829] overflow=0 shown=true
PC800 Safe=[0,800] GRACE=[594,829] overflow=29 shown=true
PC640 Safe=[0,640] GRACE=[594,829] overflow=189 shown=true
```

Det kræver en eksplicit small-window-placering eller skjuleregel for begge elementer. En simpel højre-clamp alene kan flytte baren tilbage på B1's kitrække, så kitrække og bar skal vurderes sammen. Der er ikke foretaget nogen rettelse i denne read-only-verifikation.

## Touch-beslutningen

Phase 2-workflowens opgave-/reviewtekst siger fejlagtigt, at touch-baren skal skjules altid. `B3-DESIGN.md:60` (D9) og kritik K10 er mere specifikke: 160x13-baren **vises ved corridor >=168 px**, og skjules på smallere corridor; PC/pad bruger 320x26. Den aktuelle kode (`NoiseReporter:722,749`) og de beståede checks følger D9.

844x390: den reelle corridor er 191 px; bar vises og WINDED har 12 px tekstgulv. 667x375: corridor er 88 px; bar skjules, så RUN-stroken bærer tilstanden. Markerens short-GRACE og fallback til ModalArea på meget smalle telefoner er dækket af Round HUD-suite. Designnotens fortsatte owner TOUCH-QA er visuel afprøvning af den allerede specificerede adfærd.

K1/K2/K3/K5/K6/K7/K8/K11/K13/K17 er afprøvet i de eksisterende suites: nil/spectatetarget-skift, ingen gammel ReentryGrace, små phone-layouts, Level4CardOpen-skjul, markerens hug-width, LOUD-linger, gyldig hastighedsmatematik, fontbredde, fælles konstanter og Clear som bevarer boot-markeren. De fire `ChaseEdge*`-navne findes i `UIRegression.FULLSCREEN_OVERLAYS`; den aktuelle UIRegression skal stadig køres i Studio.

## Baselinebeviser for øvrige fejl

De tre kildebaserede fejl blev reproduceret i isolerede Temp-roots med de aktuelle suite-filer og **kun manifest-equal produktkilder**. For hver kopieret produktkilde blev SHA256 først kontrolleret mod `studio-sync-manifest.json`. Ingen B3-kilder indgik i disse fejlårsager.

1. **Lobby-display:** fire baselinekilder (ZyntraConfig, LobbyShopDisplay, Shop Display Client og TunnelLobbyBuilder), samme fejl ved `test_lobby_shop_display.py:118`. `LobbyShopDisplay` er også byte-identisk med HEAD, SHA `bd78855f31e75194e6a52bb3accc796aa26b739945904c9ee05cb91b5c7888f7`. Suite forventer otte texture-ID'er, baseline har ti. Ikke B3.
2. **Round exit:** to baselinekilder (Round Exit Client og UIStyle), samme nil-call i genereret fixture `applyLayout:801`. Manifest-equal Round Exit Client kalder `UIDevice.OverlapsMovementZone` ved kildelinje 262; fake UIDevice i suite har ingen sådan funktion. Testen er normaliseret identisk med HEAD (kun line endings afviger). Dette er en tidligere MOBILE_QA/harness-forskel, ikke B3.
3. **ZyntraStore:** otte baselinekilder (ZyntraStore, UIDevice, ShopData og de fem vindue-/chipclients), samme `expected 6, got 8` ved modals-fixture. `test_zyntra_store_compact.py:1105` forventer seks; manifest-equal UIDevice indeholder allerede otte screen-owning modal-attributter. Ikke B3.
4. **Push-suite:** `test_push_repo_to_studio.py` er byte-identisk med HEAD, SHA `5ad80a4c249568856d60f2cf7f8f616b67cf13cfb916c0db452f59095d8c8e6d`. `detect_luau` ved 216 kører `luau.exe --version`. Den faktisk installerede 0.737-interpreter svarer `Unrecognized option '--version'`, selv om den kører alle ovenstående Luau-suites korrekt. 16 fake-Studio-scenarier udføres derfor ikke. Ingen rigtig Studio blev kontaktet.

## Til koordinatorens Studio-QA

Kør B3 på de eksisterende PC/touch/pad-cases og tilføj **800x600 pointer** som repro/regression for smal PC. Vurder bar/marker sammen med B1-kit. Afprøv ægte sprint/drain/WINDED, crouch/LOUD uden bevægelse, Reentry-countdown, Level 1/3 chase, Level 2 uden edge, Level 4 keypad, to-player spectating, death og round-end. Kør de nye B3-rækker i UIRegression, herunder touch SNEAK og forced chase. Der er ingen publiceringstilladelse i dette arbejde.
