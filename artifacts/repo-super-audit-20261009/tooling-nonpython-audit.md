# Supplerende tooling-audit: Lua/Luau, CMD og restore-shell

2026-10-09. Read-only: alle nedenstående filer er læst; ingen importer, uploads, probes, shell-restore eller branch-switch er kørt. Pluginet blev læst i core-audit. Scope `tooling` i repo-inventory indeholder **14 Lua/Luau-kilder inklusive pluginet**, ikke 14 ekstra filer under tools, samt én CMD og to restore-shells.

Disse er authoring-/testværktøjer, ikke automatisk aktive serverfeatures. Manglende gameplay-imports er ikke retirement-bevis. Fund nedenfor er statiske, konkrete failure-/overwrite-scenarier; de er ikke reproducerede asset- eller Studio-mutationer.

## Nye verificerbare fund

### X01 — P2: Level4 phased importer ændrer den eksisterende map før build er valideret færdigt

**Evidens:** `tools/level4_blender/place_phases.luau:65–78` destruerer den eksisterende maps øvrige children og door-geometry før første mesh-creation ved `:79–109`. Det nulstiller ikke `Level4PreviewReady` før clear; eksisterende true kan blive stående gennem et fejlet eller delvist build. `:329` sætter true til sidst, og `:334` rydder staging kun på success. Placements/rest kan også tilføje delvise children før en exception. `tools/level4_blender/place_driver.py:83–86` stopper ved ERROR, men foretager ikke rollback. Den gamle direkte placer destruerer den tidligere map ved `place.luau:384–385`; Level5-old-importer gør tilsvarende ved `tools/level5_import/place.luau:28–29` før sine mesh calls.

**Afgrænsning:** dette er en authoring-failure, ikke et normalt runtime-loop. Den current native Studio mangler den gamle Cinema Preview source-map, så L4-placers afviser den uden at nå clear, medmindre ejer først indlæser den dokumenterede backup. Når pipeline faktisk kan køre, er partial rebuild-problemet reelt i kontrolflowet.

**Mindste fix:** preflight source/model/data/scripts; markér map ikke-ready før første mutation; byg geometry i isoleret staging og commit kun efter validation, eller brug en konkret snapshot/rollback. Stage-job bør have version/generation og eksplicit failed status. **Risiko:** middel/høj ved importændring. **Test:** fake mesh-creation fejler på chunk2 og rest source-update fejler; gammel map er enten bevaret eller tydeligt unavailable, scripts/data matcher samme generation, retry skaber ingen dubletter. Kun i en disposable place-kopi.

### X02 — P2/P3: EditableMesh cleanup springes over ved build/upload-exception

**Evidens:** `tools/level4_blender/upload.luau:13–37`, `:50–64`; `tools/level5_import/upload.luau:13–32`, `:45–59`. em oprettes inde i build; en buffer/vertex/normal/face-exception før return efterlader caller uden em-reference. Efter return sker Destroy først efter CreateAssetAsync-loop. Hvis et CreateAssetAsync-kald kaster exception, går pcall til error-resultat uden at destroy em. En efterfølgende chunk kan blive behandlet med de tidligere engineresources stadig allokeret.

**Mindste fix:** en synlig em-reference pr. chunk og ubetinget Destroy i fælles cleanup efter pcall; build må også destroy sit partial em ved exception. **Risiko:** lav/middel; Destroy må ikke komme før et in-flight asset call er færdigt. **Test:** fixture failure under AddTriangle og under CreateAssetAsync; præcis ét Destroy pr. allokeret mesh. Ingen rigtig upload nødvendig.

### X03 — P2/P3: upload-success kan være uregistreret og derfor blive uploaded igen

**Evidens:** L4 `upload.luau:55–68` og L5 `upload.luau:50–63` opretter asset og sender derefter ID til loopback-serveren. Result-PostAsync er udenfor chunk-pcall og har ingen held-success retry; fejl dér stopper outer run. `tools/level4_blender/serve.py:13–19`, `:36–38` og L5 `serve.py:12–18`, `:35–37` bestemmer pending udelukkende fra result-loggen. Hvis upload lykkes, men registreringsrequesten aldrig lander, er samme chunk fortsat pending ved næste run og kan skabe et nyt group mesh-asset.

**Mindste fix:** behold success-ID i en recoverable lokal/Studio job-record og retry *registreringen*, ikke asset-creation; brug eksisterende content-hash/result-reuse som autoritativt resume-kontrakt. **Risiko:** middel; ingen automatisk sletning af allerede uploadede assets. **Test:** asset-success efterfulgt af result-request failure før server-modtagelse; resume registrerer samme ID og kalder CreateAssetAsync kun én gang. Failure efter serverens durable write skal også være idempotent.

### X04 — P3: Level4 lighting authoring-template er ældre end den aktive controller

**Evidens:** fuld diff af `tools/level4_blender/Level4LightingController.client.lua` mod den native-identiske `StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller.LocalScript.lua`. Tool-template mangler POWER_GRADES, Round State/powerState/starsAllowed, power-grade follow og spectate-target-character-logik. Runtime har disse aktive gameplay-adfærdstræk. README `tools/level4_blender/README.md:78–80` omtaler tool-filen som den installerede controller.

**Mindste fix:** mærk den som historisk source eller peg authoring-flow mod den aktuelle Studio-version efter reconciliation. **Risiko:** lav ved dokumentation/arkivering, høj hvis den gamle template overskriver controlleren. **Test:** ingen source-diff i runtime efter en authoring-import; power Off/PoweringUp/Failing/Finale og spectating virker. Der er ikke fundet en automatisk nutidig caller, som installerede den under denne audit; risikoen gælder geninstallation fra den dokumenterede source.

### X05 — P3: den dokumenterede rollback/source-path indeholder en kontrolkarakter

**Evidens:** `tools/level4_blender/README.md:125` indeholder U+0008 mellem `l4public` og `ackup` i `.rbxm`-stien. Det er ikke en almindelig backslash+b. Netop denne source-map skal indlæses for den fortsat afhængige L4-importer; copy/paste af reference kan derfor ikke bruges som den tilsigtede Windows-sti.

**Mindste fix:** ret dokumentationen til en eksisterende verificeret rollback-asset-path. **Risiko:** lav; ingen ændring af runtime. **Test:** kontrollér den resolved path før en senere import; ikke kun en visuel tekstkorrektion. Audit har ikke krævet eller åbnet filen udenfor repo.

## Authoring- og rollbackgrænser, som skal bevares

- `tools/level4_blender/place.luau` er både den gamle direkte importer **og helper-source til place_driver.py:28–34/place_phases.luau**. Hele filen kan ikke slettes, fordi den gamle execute/network-entryvej er pensioneret. Adskil delene før arkivering.
- `tools/level4_blender/upload.luau` læses også af `tools/level1_blender/import_assets.py:142` og `tools/level2_blender/import_kit.py:1182`, `:1253`. Det er et reelt tværgående authoring-library selv om det ikke require'es af gameplay.
- Native Studio har slettet Cinema Preview. README `:123–125` siger eksplicit, at backup indlæses midlertidigt før import og fjernes bagefter. CORE-033's repo-only map-scripts kan arkiveres som runtime mirror, men den tilhørende source/rollbackpakke må ikke forsvinde uden erstatning for importerens signage/light/exit references.
- PushDoors-template matcher den aktive native Workspace-kilde bortset fra en afsluttende blank linje. CORE-022 håndterer dens loop-optimering; der er ikke et ekstra tool/runtime drift-fund for den.
- `studio_compile_probe.luau` wrapper Source i en funktion og kræver kun wrapperen; original script body køres ikke. Den opretter midlertidige ModuleScripts og destruerer dem. Den er derfor en **midlertidig Studio-mutation**, selv om compile-checket ikke udfører spillets script-body. Wrapper-stage-fejl rapporteres separat og tæller ikke som pass. `studio_parity_probe.luau` er en read-only fingerprint-probe. Ingen af dem er kørt i denne supplerende audit.
- Begge Level3-playtests kræver disposable Studio Play og manipulerer world, seeds, spillere og AI-debug-state. De er ikke smoke-checks, man bør paste ind i en igangværende party. Hidden-chase tjekker andre aktive spillere først *efter* Build/flags; følg derfor dokumentets one-player-krav før kørsel. Outcome-probe har tidligt roster-check og mere omfattende final cleanup. Disse lifecycle-grænser beskrives her, ikke som nye production-bugs.
- HUD-harness er en aktiv offline fake engine; den dokumenterer selv manglende rendering/font/UIScale/list-padding/AutomaticSize. Den kan verificere state/contracts og enkelte geometrier, men ikke certificere et visuelt Roblox-render eller streaming/real scheduler. Fake Color3 kvantiserer og memoiserer; task.wait er no-op og tween Play anvender målet straks. De kendte modelgrænser er ikke dead-code-fund.
- `apply_to_studio.cmd` har en konkret Y/N-gate før Studio-push. Den henter/skifter dog den historiske hardcoded branch *før* denne gate; dette er allerede **T10** i repo-tools-storage-audit.md og gentages ikke som et nyt X-fund. Ved ny handoff skal den ikke bruges som generisk synkroniseringscommand.
- Begge restore-shells verificerer fragmenter og det sammensatte arkivs pinned SHA256 **før** tar-extraction, verificerer output bagefter, og sletter kun deres mktemp-workdir i trap. Ingen ukritisk cleanup af repo/output er fundet. De ekstraherer til det eksplicit valgte output og kan overskrive filer dér som almindelig restore; vælg derfor en separat stagingdestination ved et senere review. Der er ikke grundlag for at pensionere dem alene på dato/navn.

## Per-file coverage

| Fil | Linjer | Gennemgang |
|---|---:|---|
| plugin/MasterTuningPlugin.server.lua | 350 | Hele filen læst i core-audit; authoring API bevares. |
| tools/level4_blender/Level4LightingController.client.lua | 260 | Hele filen, diff mod native-identisk runtime; X04. |
| tools/level4_blender/PushDoors.server.lua | 160 | Hele filen, diff mod runtime; CORE-022. |
| tools/level4_blender/place.luau | 680 | Hele filen inklusive embedded flicker Source, templates, collision, signs/lights og script-installation; X01 og helper-dependency. |
| tools/level4_blender/place_phases.luau | 339 | Alle tre faser og success-stage-cleanup; X01. |
| tools/level4_blender/upload.luau | 85 | Hele filen inklusive placeholders, upload/retries/status og HttpEnabled restore; X02/X03. |
| tools/level5_import/place.luau | 135 | Hele gamle Quiet Suburbs importer; X01; ingen påstand om aktiv native Void-pipeline. |
| tools/level5_import/upload.luau | 80 | Hele filen, upload/retries/status og HttpEnabled restore; X02/X03. |
| tools/luna/player_pet_anim.luau | 120 | Hele pose-tree, alle keys og begge sequence builders; aktiv source-builder med appended harness. |
| tools/playtest_level3_hidden_chase.luau | 197 | Hele naturlige chase/patrol/skill-check-probe; disposable Play. |
| tools/playtest_level3_table_outcomes.luau | 304 | Hele deterministic engine-outcome-probe og final cleanup; disposable Play. |
| tools/studio_compile_probe.luau | 69 | Hele wrapper/stage/require/destroy/report-flow. |
| tools/studio_parity_probe.luau | 53 | Hele chunked dual-hash og instance-path inventory; read-only. |
| tools/tests/hud_harness.luau | 580 | Hele signals/value/instance/layout/scheduler/services/load fixture; kendte modelgrænser. |
| tools/apply_to_studio.cmd | 76 | Hele prerequisite/git/audit/confirmation/push flow; T10 eksisterende fund. |
| tools/restore-live-assets.sh | 37 | Hele fragment/archive/output checksum og temp cleanup. |
| tools/restore-slidemouth-assets.sh | 37 | Hele fragment/archive/output checksum og temp cleanup. |

Til dependency-validation er også de komplette korte place_driver.py og to serve.py læst samt relevante Level4/5 README-afsnit. Rootens separate Python-coverage er hele AST-read/parse af 258 Python-kilder; dette tillæg hævder ikke en fuld dynamisk authoring-regression eller sikker sletning af nogen af værktøjerne.
