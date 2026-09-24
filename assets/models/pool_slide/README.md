# Pool Slide — større rig og walk/run v1

Dette er en **assetpakke til import/test**, ikke en ændring i det levende spil. Kilden blev genskabt fra den eksisterende Studio-template 23/9. `pool_slide_scaled_walk_run_v1.glb` er 1,20× større og bruger de samme 20 knoglenavne, mesh-UV'er, vertexfarver og skin-vægte. Den indeholder `Idle`, `Walk`, `Run`, `Attack`; Walk/Run er poleret med større ben- og armsving, fodled og vægtskift. `pool_slide_scaled_walk_run_v1.blend` er en redigerbar Blender 5.2.2-kopi.

- Model: 19.814 trekanter, 1 materiale, ingen teksturer. Statiske GLB-mål i studs: **13,83 bred × 14,40 høj × 4,76 dyb**. Sålen ligger 7,20 studs under pivot.
- Walk: 1,033 s loop. Foreløbig `WalkAnimationReferenceSpeed = 14.85` studs/s.
- Run: 0,633 s loop. Foreløbig `RunAnimationReferenceSpeed = 36.8` studs/s.
- Hastighederne er beregnet fra anklens bevægelse i Blender relativt til de gamle klip. De er **startværdier**, ikke bevis for fravær af fodglidning; justér i en aktiv Level 2-runde ved walk 10, chase 20 og enraged 32 studs/s.
- `Root` er in-place i Walk/Run, og første/sidste pose er identiske for alle kanaler.
- Idle/Attack er med, fordi deres translationsspor også skal skaleres med riggen. **Roblox-markøren `Contact` overføres ikke af glTF**. Hvis Attack-klippet genimporteres, læg `Contact` ved 0,50 s; ellers behold det nuværende Attack-asset og vurder den lidt mindre relative lunge visuelt.

[Kontaktark](pool_slide_walk_run_v1_contact_sheet.png), [skala-sammenligning](pool_slide_scale_comparison_v1.png), [Walk-loop](pool_slide_walk_v1.gif), [Run-loop](pool_slide_run_v1.gif) og [manifest](pool_slide_scaled_walk_run_v1_manifest.json) er til gennemgang. Renderingerne viser modellen, ikke gameplay-fit.

## Integration hos Claude

1. Gruppeejet Model-asset **95190427565492** er nu uploadet fra GLB via Open Cloud, men er ikke sat ind i Studio. Importér som **ny** template i `ServerStorage.Level2Assets`; bevar `RootPart`/pivot, `AnimationController/Animator`, de 20 knogler og navne. Sæt visuelle dele til `CanCollide = false`. Overtag ikke originalen før A/B er grøn.
2. Upload nye Walk/Run som Animation-assets ejet af **ERN Roblox Studios (gruppe 1039373905)** og indsæt ID'erne i templatens `Animations`-mappe. Overvej også skaleret Idle/Attack efter kontrol af `Contact`-markøren.
3. Brug referencehastighederne ovenfor som udgangspunkt; mål fodglidning i Studio ved de tre faktiske farter. Mål `AgentRadius`, `AgentHeight`, animeret envelope og `GroundOffset` i ny template. Controllerens grænser er radius ≤ 12 og højde ≤ 24.
4. Test passage og klipning på tre Level 2-layouts, to separate pumper → spawn, tredje pumpe → eskalation af samme entity, angreb ved `Contact`, spawnafstand ≥ 100 studs og mundlyd fra mundåbningen. Behold feature-gates slukket, indtil disse og mobil-ydelse er verificeret.

## Verifikation af pakken

Blender 5.2.2 importerede den færdige GLB i baggrundstilstand med 2 vægtede meshes, 20 knogler og 4 actions. Khronos glTF-validator via `@gltf-transform/cli validate` gav **0 fejl og 0 advarsler**; to informationslinjer fortæller blot, at UV'erne endnu ikke bruges af en tekstur. Se `pool_slide_scaled_walk_run_v1_validation.csv`.

Open Cloud Model-uploaden 24/9 blev godkendt og aktiv som asset **95190427565492** for gruppe 1039373905; SHA-256 og operationskvittering er i `pool_slide_upload_receipt.json`. Den downloadede Roblox-model er gemt som `pool_slide_uploaded_model_v1.rbxm`. Dens instance-klasser indeholder en `AnimationController`, men **ingen `Animation` eller `KeyframeSequence`**: GLB-importen har ikke oprettet brugbare Walk/Run-animation-ID'er. Animationerne skal derfor uploades særskilt før integration. Ingen Studio-ændring, publicering eller Meshy-kredit er brugt.

Pakken kan genskabes med `python tools/pool_slide_polish_glb.py <source.glb> <output.glb>`; scriptet bruger NumPy og kontrollerer kildens SHA-256, før det skriver noget.
