# Bloom-dæmpning og lommelygte-QA

**Stage B er gennemført. Bloom-targets er sænket 20 % hos de fem aktive level-writers, og native Lighting.Bloom er sænket fra1 til0,8 for lobby, Level 1 og Level 5. Studio står i Edit, og låsen blev frigivet00:29:17 UTC /02:29:17 lokal tid. Ingen commit, push eller udgivelse.**

Dæmpningen er ejerens særskilt autoriserede tuning. En entydig årsag til den synlige flashlight-flicker er fortsat ikke bevist. Håndlygtens lys og HUD er ikke ændret.

## Installerede ændringer

| Område / aktiv Studio-writer | Før → efter |
| --- | --- |
| Native `Lighting.Bloom`: lobby, L1, L5; også inherited i L6 | Intensity1→0,8. Faktisk engine-landing0,8000000119; Enabled=true, Size24 og Threshold2 uændrede |
| `Level 2 Lighting Controller` | NORMAL0,085→0,068; EXIT_OPEN0,11→0,088 |
| `Level2BlenderPreviewButton` | Resolved GradeBloom/A2-value×0,8 én gang, efter attribute/default-resolution. Default0,5→0,4; model-overrides skaleres også |
| `Level 3 Lighting Controller` | Locked target0,08→0,064; unlocked target0,11→0,088 |
| `Level 4 Lighting Controller` | Init0,85→0,68; fælles final writer `current.Bloom×0,8`. Off0,5→0,4; On/Failing0,85→0,68; PoweringUp1,6→1,28; Finale1,1→0,88 |
| `Level 6 Playground Client` | Egen Bloom0,3→0,24, før effekten parentes |

Kun Bloom-intensitet er tunet. Size/Threshold, exposure/ambient og lygte-Brightness/Range/Angle/Shadows er ikke ændret. Dynamiske targets genlæses råt og skaleres én gang; tidligere skalerede effektværdier bliver ikke multipliceret igen.

Den friske all-source inventory havde ingen Source-readfejl. Den fandt en live-only Level 5 Lighting Controller uden Bloom-writes og den faktiske Level 6 Playground Client. Den gamle repo-fil Level 6 Lighting Controller er ikke brugt som patchmål. Lobby Tunnel Reach Client har kun en Bloom-kommentar.

FlashlightController blev drift-auditeret før writes og igen til sidst: Source/editor/repo matcher; hele SHA256 er uændret `b1b1322a39a3a9a493b265f9317f7ba530f8726d5a2b2dfb294d7b3826dcc3aa`. HUD B1/B2 er bevaret. Character models- og dev-tokens-scripts ligger uden for patchmålene og blev ikke skrevet.

L3 havde eksisterende Studio-drift i fixtures og ceiling-bounce, mens repo-filen var Git-clean. Den autoritative Studio-kilde blev først mirroret, og disse ændringer er bevaret. Manglende L5/L6-kilder blev også mirroret. CAS-installationen ændrede kun7 ejede hunks i5 aktive Studio-scripts plus den ene native property. Alle5 Studio- og repo-kandidater kompilerede med Luau0.737 -O0. Fresh Source/editor/class/Enabled/hash-CAS og native before-properties blev kontrolleret før writes og i callback. Installerede kilder blev genlæst fuldt; final Source/editor/repo-paritet er7/7.

## Faktisk Play-QA

Rigtige lobbyzoner og CreateParty-UI startede solo-rounds i Level 1 og Level 4. Lygten var tændt, Health100, InRound=true, RoundActive=true, fuldt batteri og dev-unlimited i alle8 fulde captures. PC og faktisk iPhone17Pro landscape-emulering blev anvendt. Telefon: TouchEnabled=true, ForceTouchUI=false, viewport749×381. RenderQuality og EditorQuality var Level21 med EnableFRM=false under hver måling og blev derefter restaureret.

| Seks sekunders high-graphics-sweep | Reference / installeret frames | Bloom reference → installeret | Torch property-/origin-events |
| --- | ---: | --- | ---: |
| L1 PC | 361 /360 | Native1→0,8 | 0 /0 |
| L1 telefon | 362 /359 | Native1→0,8 | 0 /0 |
| L4 PC | 361 /361 | Egen0,5→0,4 | 0 /0 |
| L4 telefon | 363 /362 | Egen0,5→0,4 | 0 /0 |

I alt2.889 frames. Alle transport-/assembly-/cleanup-checks og ProbeComplete bestod, uden afkortning af rå frame-data. Referencemålingerne er kontrollerede midlertidige overrides i den installerede Play-session, som restaureres igen; de er ikke kildeoptagelser før installationen. L4-reference holdt0,5 ved render-priority og verificerede alle render-prøver; timeren så også én0,4-prøve mellem controller/render-phases. Samme60 graders sweep-parametre bruges. Kameraerne er tæt på hinanden, men frame-timing og rotationer er ikke ens række-for-række. L1 havde enkelte scene-mutationer, så hele scenen var ikke identisk.

**Event-tallene måler lygte-properties og geometri, ikke pixel-flicker.** Ingen normal ray-hit eller holdkammerat blev udøvet i disse captures. Synlig flicker blev ikke reproduceret entydigt og kan ikke erklæres løst. Fuld analyse: [B-play-metrics.md](B-play-metrics.md), med byte/SHA/DJB2-valideret JSON.

Yderligere scoped runtime-kontroller:

- L2 NORMAL0,068 og EXIT_OPEN0,088 passer.
- Fysisk avatar inde i L2 new-map: default0,4 passer; midlertidig GradeBloom0,75 gav0,6 og efter attribute-restoration igen0,4. Det verificerer overrides og fravær af gentagen nedskalering.
- L3 locked target0,064 passer. Når ExitUnlocked sættes, afbryder den eksisterende completion-path tweenen og slår Bloom fra. Den aktive unlocked0,088 er Source/offline-verificeret, ikke Play-verificeret. L3's første cirka0,48 sekunders tween starter stadig fra dens eksisterende initværdi;20 % gælder targets.
- L6 preview-activation gav enabled Bloom0,24/Size24/Threshold2. Ved exit blev egen effekt fjernet, og native0,8 var aktiv igen.
- Fysisk avatar inde i L5 gav Level5LightingOwned=true og native Bloom enabled0,8/Size24/Threshold2, Health100.
- L4 reel3-glint virker efter ændringen:4 unikke lokale PointLights observeret, Range8/Shadows=false og normal fading. Dette omfatter en eksisterende burst; der er ingen glint-sourceændring.

Disse L2/L3/L5/L6-kontroller er scoped controller-/ownership-tests, ikke fulde gennemspillede rounds. L4's andre power-states og L2's A2-grading er Source-verificerede; de blev ikke alle udøvet i Play. Holdkammeraters lygter, fuldt shadow-budget, alle materialer og streaming som pixelårsag er fortsat åbne. Der er ingen gættet raycast-/shadow-fix.

## Sammenlignelige billeder

Begge billeder i hver serie bruger samme låste kamera, viewport og Level21/FRM=false. Hver capture-call ligger helt inden for sin verificerede4-sekunders fase; kameraDeviation=0 og ingen nye/fjernede BloomEffects. Originalværdien genskabes midlertidigt; den anden fase bruger installeret intensitet. Kamera/kvalitet/effekter restaureres i samme kald.

| Scene | Original | 20 % dæmpet |
| --- | --- | --- |
| Lobby: native1 vs0,8 | [Original](play/B-lobby-original-v2.png) | [Dæmpet](play/B-lobby-80pct-v2.png) |
| Level4 Off-state:0,5 vs0,4 | [Original](play/B-L4-original-high.png) | [Dæmpet](play/B-L4-80pct-high.png) |

Metadata: `play/B-lobby-image-verification.json` og `play/B-L4-image-verification.json`. Den første lobby-serie ramte slutgrænsen og er ikke godkendt til sammenligning; brug kun v2. Første controller-probe havde UTF-8 BOM og fejlede parsing før mutations; valid-retry-data bruges. Det første L1-reference-wrapper-forsøg blev afvist offline af transportkontrakten før Studio-kald.

## Filer og afslutning

Følgende produkt-mirrors/manifest er ændret af denne session:

- `StarterPlayer/StarterPlayerScripts/Level 2 Lighting Controller.LocalScript.lua`
- `StarterPlayer/StarterPlayerScripts/Level2BlenderPreviewButton.LocalScript.lua`
- `StarterPlayer/StarterPlayerScripts/Level 3 Lighting Controller.LocalScript.lua` — inkluderer autoritativ Studio-drift før vores ene hunk
- `StarterPlayer/StarterPlayerScripts/Level 4 Lighting Controller.LocalScript.lua`
- `StarterPlayer/StarterPlayerScripts/Level 6 Playground Client.LocalScript.lua` — ny autoritativ mirror, plus én Bloom-hunk
- `StarterPlayer/StarterPlayerScripts/Level 5 Lighting Controller.LocalScript.lua` — ny autoritativ audit-mirror, ingen Studio-sourceændring
- `studio-sync-manifest.json` — scoped mirror-paritet og to nye mirror-items; ingen bred sync af andre sessions filer

Native Lighting.Bloom-property findes ikke som en source-fil; before/after er i install-receipt og final Edit-audit. Se `bloom-stageB-reviewed/apply-receipt.json`, `B-authoritative-audit/`, `B-final-edit-audit/` og `B-release-receipt.json`.

Lås:00:09:35→00:29:17 UTC, knap20 minutter, før ETA00:34:35. Studio Edit er verificeret. Device blev reset til default; før sidste StopPlay var kvalitetsindstillinger Automatic, EnableFRM=true. Transport-attributter var0. Alle46 midlertidige probefiler/helperfiler er byte-verificeret arkiveret som dokumentation og fjernet; ingen debug-/probe-scripts er installeret. Køposten er fjernet, holder=null.

Console indeholder eksisterende sound-approval/missing-water-sound-advarsler, ingen observeret Bloom-controller runtime-fejl. De er ikke rettet uden for scope. Git-status er gemt før og efter; andres WIP er bevaret. Ingen commit, push eller udgivelse.

Stage A's tidligere diagnose og rå målinger er fortsat bevaret i `play/`, `analysis/`, `play-metrics.md` og de tidligere audit-/offline-artifacts. Stage A kunne vise en tvungen cirka0,3-stud raycast-origin-mekanisme, men ikke ejerens normale high-graphics-flicker. Det er derfor ikke brugt som begrundelse for et lygte-fix.
