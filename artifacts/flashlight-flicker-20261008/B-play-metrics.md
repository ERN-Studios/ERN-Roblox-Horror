# Stage B Play-metrics: L1, L4, PC, Touch og lobby

Alle otte captures har gyldigt JSON, genberegnet payload-SHA/DJB2/byteantal, transport/assembly/cleanup=true, Complete=true, RoundActive=true og Health=100 i alle frames. InRound=true og lygten er tændt gennem alle målinger, med korrekt SelectedLevel 1 eller 4.

## Level 1

| Capture | Frames | Målt slut-tid (s) | Bloom-prøver | Bloom Enabled / Intensity |
| --- | ---: | ---: | ---: | --- |
| B-L1-PC-high-reference | 361 | 6 | 101 | true / 1 |
| B-L1-PC-high-after | 360 | 6 | 98 | true / 0.8 |
| B-L1-phone-high-reference | 362 | 6.03333 | 101 | true / 1 |
| B-L1-phone-high-after | 359 | 5.98333 | 98 | true / 0.8 |

PC: faktisk TouchEnabled=false, 1919×1080. Telefon: faktisk TouchEnabled=true, 749×381 og ForceTouchUI=false i begge captures; det er Roblox Touch-emulering. Configens DeviceLabel/Label siger PC, fordi samme PC-probesource blev genbrugt. Alle fire aflæser render- og EditQualityLevel=Level21 samt EnableFRM=false.

PropertyEdges, EnabledEdges, ClipJumps, AllOriginResidualJumps, ExcludedOriginResidualJumps, HitSwitches og MissingMountFrames er 0 i alle fire captures. MaxResidualDelta, MaxClipDelta, MaxCameraDelta og MaxReconstructionError er også 0. MaxActualDelta er PC 0.00394→0.00389 studs og Touch 0.00420→0.00413 studs; dette er små ændringer i den normale lygtebevægelse, ikke observeret strobing.

Øjepositionen er præcist (-5, 6.23418, -13.51704), og samme 60° yaw-sweep køres. PC's første CFrame-komponentdelta er 0.01599, sidste 0; Touch's første er 0 og sidste 0.02741. Sampling-tiderne er forskellige, så rotationerne er ikke ens række-for-række. Målt slut-tid er sidste probe-time; faktisk tidsvindue mellem første og sidste frame er separat i JSON.

Scenemutationer: PC-reference 0/0, PC-efter 434 additions/0 removals; Touch-reference 0 additions/2 removals, Touch-efter 0/0. De nærliggende shadow-lights har samme paths og lysproperties, men hele scenen var ikke identisk. Alle frames har Focused=false, DevUnlimited=true og batteriproxy=1; ingen spectate, preview eller L3-blackout.

Reference og efter er begge optaget efter installationen: reference-proben holder midlertidigt native Bloom på 1 og restaurerer den igen; efter måler den installerede 0.8. Dette er en A/B-propertymåling, ikke en optagelse før kildeinstallationen.

## Level 4

| Capture | Frames | Målt slut-tid (s) | Reference-render Bloom | Timer-Bloom |
| --- | ---: | ---: | --- | --- |
| B-L4-PC-high-reference | 361 | 6.01667 | 361 prøver, alle 0.5 | 98×0.5, 1×0.4 |
| B-L4-PC-high-after | 361 | 6.0125 | — | 102×0.4 |
| B-L4-phone-high-reference | 363 | 6.0375 | 363 prøver, alle 0.5 | 99×0.5, 1×0.4 |
| B-L4-phone-high-after | 362 | 6.01667 | — | 102×0.4 |

Reference er en midlertidig render-hold på 0.5 ved Camera+3, verificeret i QA_ReferenceRenderBloom. L4-controlleren skriver fortsat den installerede 0.4 mellem render-phases, så timerens ene 0.4-prøve i hver reference skal medregnes; timeren er ikke konstant 0.5. Reference-sweeps blev kørt efter efter-sweeps i samme installerede Play-session.

Faktisk PC-viewport er 1413×556 med Touch=false; Touch-emulatoren er 749×381 med Touch=true og ForceTouchUI=false. Begge aflæser Level21/FRM=false. Alle frames har Health=100, InRound=true, SelectedLevel=4, lygte tændt, Focused=false, DevUnlimited=true og batteriproxy=1. Alle property-/Enabled-/clip-/residual-events samt MissingMountFrames er 0; scenemutationer er 0/0 i alle fire L4-captures.

Kameraernes øjepositioner afviger 0.00040 stud på PC og 0.00008 på Touch, så de er tæt på hinanden og ikke matematisk identiske. PC's første/sidste største rotationskomponentdelta er 0.00226/0.00226; Touch's er 0.00002/0.01137 med forskellig slutsampling. Samme sweep-parametre anvendes. MaxActualDelta/MaxRawDelta er PC 0.21368→0.20306 og Touch 0.17825→0.17079; MaxResidualDelta og MaxClipDelta er 0, så disse større rå bevægelser er ikke registrerede origin-/clip-spring.

## Lobby-billeder v2

B-lobby-image-verification.json er Complete=true med Level21/FRM=false. Begge v2-PNG findes. Originalbilledets request/return er 979/1235 ms (Intensity 1); 80%-billedets er 5470/5735 ms (Intensity 0.8), begge inden for deres respektive firesekundersvinduer i v2-kaldets 8 s. Den aktive native Bloom aflæses efter restoration til 0.800000011920929 med samme Size 24/Threshold 2; de andre tre oplistede Bloom-effects er disabled.

## Level 4-billeder v2

B-L4-visual-v2.txt er complete=true, errors=[], Level21/FRM=false, RoundActive/InRound=true og powerState=Off. Der er 479 render-observationer over 8 s med maxCameraDeviation=0 og ingen Bloom-additions/removals. Første firesekundersfase holder aktivt L4 Bloom på 0.5; anden holder den installerede 0.4000000059604645.

B-L4-image-verification.json og begge PNG findes: original request/return 1049/1249 ms, 80%-billede 5394/5584 ms, altså inden for de respektive firesekundersfaser. Native Lighting.Bloom er disabled her; Lighting.Level 4 Client Bloom er den aktive effekt med Size=30 og Threshold≈0.92.

## Kontrollerede controller-cases

B-controller-cases-valid.txt er et scoped runtime-kontrolkald, ikke fulde level-rounds. Lobby 0.8, L2 NORMAL 0.068, L2 EXIT_OPEN 0.088 og L3 LOCKED 0.064 blev målt med Enabled=true. Kaldets samlede ok=false skyldes assertion på L3 UNLOCKED: efter 1 s var Bloom disabled med bevaret 0.064. Cleanup=true er registreret.

Dette stemmer med tilsigtet completion: L3 blackoutRequested() 316–322 inkluderer exitUnlocked(); Heartbeat 1122–1135 kalder beginBlackout(), som annullerer tweens på 820 og går til completion-faden på 821–823. beginCompletionFade() slår Bloom fra på 537; ordinary blackout gør det samme på 826. Unlocked target 0.088 findes på 1034–1037, og unlock-signalet 1109–1111 kan starte graden, før completion overtager. **Unlocked 0.088 er Source/offline-verificeret og ikke Play-verificeret som aktivt target.** Ingen rettelse blev udledt af denne assertion.

Root-sessionens separate fysiske preview-kontrol målte L2 new-map default 0.4, GradeBloom=0.75→0.6 og restaureret default 0.4. L6 Playground målte egen Bloom enabled med 0.24, fjernet ved exit, og native base 0.8. Det er scoped preview/controller-QA, ikke fulde rounds.

StateSchema-feltet Focused betyder Character-attributten FlashlightFocused, altså lygtefokus. Det er ikke OS-/browser-vinduesfokus; disse sweeps bruger normal, ufokuseret lygte.

Ingen property-/origin-events blev observeret i disse korte L1/L4-sweeps. Alle Hits- og mateShafts-lister er tomme; væg-clipping og andre spilleres lys blev derfor ikke udøvet her. Tallene verificerer den lavere Bloom-setting og fravær af registrerede torch-propertyspring her; de kan ikke bevise en årsag til eller visuel løsning på den rapporterede flicker.
