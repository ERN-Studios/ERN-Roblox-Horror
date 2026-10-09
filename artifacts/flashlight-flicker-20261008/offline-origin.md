# Offline: lommelygtens origin og måleplan

Der er **ingen Play- eller render-reproduktion i denne rapport og intet foreslået fix**. Jeg har kun læst det frosne checkout og lavet et midlertidigt probeudkast. Studio/låsen, runtime-mirror, Git-index, commits og udgivelse er ikke rørt.

## Kildegrundlag og fund

- Frossen fil: `offline-baseline/StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua`, raw SHA-256 `f0666fe69f40ecfaa843865aecd432b30830daeeeee8652c480e69b8308d6c04`. Live kilde/editor skal genlæses under Studio-låsen før enhver ændring.
- Den egne lysmontage skrives ét sted i `BindToRenderStep("MongoFlashlight", Camera + 2)`. Aim bruger `CFrame:Lerp` med `math.clamp(dt * 14, 0, 1)`, så denne alpha kan ikke overshoote. Kameraets faktiske CFrame og den forsinkede aim-rotation bruges sammen til raw hand.
- Origin-raycasten går **fra øje til hånd**, ikke ud langs hele lyskeglen. Ved vandret kamera er den `sqrt(0.25² + 0.25² + 0.3²) = 0.4636809` studs lang. Et fjernt objekt, der kun kommer ind i keglen, kan derfor ikke direkte rammes af denne raycast. Tæt på øjet kan skift mellem hit/miss give et origin-hop af denne størrelse.
- Ved hit tættere end 0.3 studs bliver montagepositionen præcis øjet. Ved hit 0.45 studs fra øjet bliver den 0.15 studs fra øjet. Det er en observerbar geometrisk diskontinuitet ved et hit/miss-skift, men det er **ikke bevis for synligt flicker** og ikke i sig selv en begrundelse for at ændre væg-clearance.
- `mateRay` flytter kun enden af `MateBeamShaft` (`MateBeamA1`), bredden og den dekorative lens-position. `MateBeamCore`/`MateBeamSpill` er parentet på holdkammeratens `Head`; deres origin flyttes ikke af `mateRay`. Et fælles eget/mate-problem skal derfor afprøves adskilt fra den egne clearance-raycast.
- Egen kerne har `Shadows=true`, egen spill/fill har `false`. Holdkammeratens lokale kerne har `true`; dennes spill og serverens replikerede core/spill har `false`. Samtidig rendering af mate-head og replikeret montage er relevant for den anden analyse, men ingen budgetpåstand er bevist her.
- Batteriet giver bevidste sluk/tænd-blink ved 50%/25%; `FlashlightOn` forbliver sand under advarslen. De skal holdes adskilt fra geometriske og renderrelaterede events. `SpectateBattery` er kun en periodisk replikeret proxy; det er ikke den private `battery`-lokal.
- Graphify blev læst, men grafen er bygget fra `a6551306` (2026-09-16), mens HEAD ved læsningen var `1be05fc9f79d25392af772325303e3d3802b0ac1`. Dens fund bruges derfor kun som vejvisning; ovenstående bygger på det frosne faktiske script.

## Bounded probe

Udkastet blev forberedt i `_local/flashlight-flicker/bounded-frame-probe.luau` og kompileret med Luau 0.737, `-O0 --null`: OK (16 KB bytecode). Den midlertidige fil er ryddet; tekstbilaget er bevaret i `PROBE-DRAFT.md`. Det er ikke kørt i Roblox. Efter frisk review kan det køres som **én Client `execute_luau`-call under den udtrykkeligt tildelte lås**, standard 8 sekunder, absolut højst 10 sekunder. Hele returnerede JSON-streng skal gemmes på disk; proben printer ikke den store log i Studio-console. Ingen `task.spawn` eller state på tværs af MCP-calls.

Proben verificerer live runtime-LocalScriptens klasse og `.Source`-konstanter/formel. Den stopper før sampling, hvis de afviger eller `.Source` ikke kan læses. Hvis sandboxen forbyder runtime-Source, må den tilpasses efter en frisk audit; fejl må ikke omgås ved blindt at stole på offline-filen.

Sampleren kører `Camera + 4`, efter egen montage er skrevet. Hver frame indeholder fuld camera/own CFrame, raw hand, faktisk origin, camera/raw/actual delta, clip distance og clip delta, genberegnet ray-hit samt alle observerede lys' Enabled/Brightness/Range/Angle/Shadows. Én holdkammerat, dennes head-lys/shaft og begge replikerede montager følger med. Nye instanser får nyt lokalt light-id og `FirstFrame`, også hvis navnet er det samme. Den logger round/focus/blackout/health, `FlashlightOn`, `DevUnlimited`, `SpectateBattery`, viewport og device-label.

Før/efter lister den skyggelys inden for 120 studs og scene-descendant-count. Under målingen tæller den scene additions/removals og ray-hit-instansens ancestry-kanter. Disse er scene-mutationsproxies, ikke bevis for streaming. `StreamingEnabled` læses sikkert og kan være `restricted`.

`ClipJumps >= 0.15 stud`, `EnabledEdges`, `PropertyEdges` og `HitSwitches` er **proxy-events**. De må aldrig rapporteres som antallet af synlige flicker-events. Origin-eventen bruger vector-residual-step `((actual-raw)-(previous.actual-previous.raw)).Magnitude`, ikke alene forskellen i clip-magnituder. Alle residual-events bevares i `AllOriginResidualJumps`; `ClipJumps` tæller kun samme mount-instans, stabilt fokus/level/blackout, tændt flag og små eye/raw-steps (0.02/0.05 studs). De øvrige events tælles som excluded og alle rå frames gemmes. Genberegnet origin skal matche den faktiske med lav `MaxReconstructionError`; høj fejl gør clip-målingen upålidelig (forkert formel, anden writer eller frame/scene-rækkefølge).

`Complete` kræver fejlfrie samples, mindst én frame, mindst 95% af målevinduet, ingen frames med manglende egen montage og ingen frame-cap. En 0-frame/no-mount-kørsel kan derfor ikke se godkendt ud. Sweep-driverens callback er selv pakket i `pcall` og fører fejl til den fælles cleanup.

## Samme sweep før/efter

1. Start rigtig round på Level 1; gentag senere i Level 4. Bevar de præcise marker/pose/retning til en eventuel eftertest. Vælg én væg/hjørne/dør og én række små objekter/glas; mål nær (clearance-ray kan berøre noget) og fjern (fx 3+ studs fra den nærmeste væg ved øjet).
2. Stabiliser kameraet og brug tændt normal WIDE-profil. Log batteri, hold `DevUnlimited=true` i det kontrollerede sweep for at udelukke tilsigtede batteriblink; gendan den tidligere attribut bagefter. En separat naturlig-batteriobservation skal bevare advarslerne.
3. Default `Sweep=false` er observation uden kameraskrivning. Først hvis denne virker og cleanup er bekræftet, kan `Sweep=true` bruges: 60° total yaw, sinus, center→venstre→center→højre→center på 8 sekunder, ingen translation/pitch. Samme eye, base CFrame og profil gentages tre gange. Gem Config + base camera CFrame som sammenligningsgrundlag.
4. Observer synlige lysdrop i video/screenshots med tid eller tydelig sweep-phase, og korrelér med proxy-events. Stationært eye og jævn yaw gør store clipDelta-ændringer langt mere fortolkelige end `mount.Position`-delta alene. Tilt/pitch og naturlig gang afprøves separat bagefter.
5. Minimumsmatrix: L1/PC/own, L1/telefonemulator/own, L1/PC/mate, L1/telefonemulator/mate og de samme fire i L4. Mate skal være en rigtig anden levende Player med tændt replikeret flag; kloning af Character er ikke multiplayer-verifikation. For mate-sweep skal spiller 2 faktisk dreje strålen hen over mål; main-clientens Scriptable sweep drejer kun den egne lygte.
6. En UI-attribut som `ForceTouchUI` tæller ikke som telefonemulator eller telefon-GPU. Angiv valgt Studio-device + viewport + TouchEnabled; emulatorens renderhardware er stadig værtens og kan ikke bevise ydelse på fysisk telefon.
7. Bevar en løs filmrulle i L4 som mål og verificér den eksisterende TORCH_GLINT visuelt, inklusive wall/door blocking. Den bounded sampler foretager ingen ændring af glimt-scriptet. En ekstra lokal glimtlys-event må ikke fejlagtigt tælles som lommelygte property-edge.

Hvis proxy-events er nul, men synlige drops stadig findes, er egne Enabled/Brightness/Range/Angle/origin-writers mindre sandsynlige i netop den måling. Det beviser ikke at shadow-budget, geometri, teknologi eller streaming er årsagen; næste diagnosticering skal holde aim/scene konstant og ændre én kontrolleret faktor ad gangen.

## Cleanup og offline-check

Sampler/driver unbindes, alle scene/ancestry-signals disconnectes, og den midlertidigt Scriptable camera gendannes inden samme call afsluttes, også ved sample/setup-fejl. Proben skaber ingen instance eller script. Efter en fejl skal owner-sessionen verificere kamera og callbacks før næste måling. Ingen ændring må efterlades i controllerens kildetekst. Ved tabt MCP-call kan automatisk finalizer ikke antages gennemført; stop Play under låsen.

Jeg nåede allerede at køre 11 ekstrakterede origin-matematikcases, før beskeden om tredje agents tilsvarende test kom. Log: `offline-origin-test.log` (exit 0). De beviser kun hit/no-hit-formlens resultater med simulerede hits; der er ingen engine-raycast eller rendering. Prototypetest, genereret harness og midlertidige probe-/koordinationsscripts er fjernet fra `_local/flashlight-flicker/`. Den reproducerbare test i `offline-tests/` er den samlede offline-test; dobbeltresultater tælles ikke som ekstra evidens. Probeudkastets tekstbilag afventer Play-QA og er aldrig installeret i spillet.
