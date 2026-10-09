# Stage A: Play-metrik, 2026-10-08

Ingen sikker normal spillerreproduktion eller kontinuerlig pixelm?ling af flicker blev opn?et. De m?lte egne lys-egenskaber var stabile i de kontrollerede sweeps. En s?rskilt tvungen kamerakontakt beviste clearance-raycastens ~0,30-studs origin-hop, men den er ikke identisk med ejerens problem. Ingen produkt-script?ndring eller fix i Stage A.

`Complete=true` betyder, at proben gennemf?rte sit m?levindue; det er ikke et gameplay-/render-pass. Enabled/property/origin-events nedenfor er proxy-events, ikke antallet af synlige flicker-events. Root afsluttede Stage A i Edit/DeviceDefault kl. 21:29:50 UTC.

## Oprindelig survey: Automatic / lav automatisk kvalitet

Ejeren pr?ciserede senere, at problemet kun ses p? h?j grafik og mist?nker Bloom. De f?rste surveys k?rte Automatic, og det direkte l?ste AutoFRMLevel var 3. Disse surveys kan derfor ikke afvise high-only-problemet. Alle nedenst?ende captures havde batteri-proxy 1, DevUnlimited=true, FlashlightOn=true, fokus=false, levende/ikke spectate og korrekt SelectedLevel. De tre egne lys var t?ndt i hver frame; de to lokale replikerede egne lys var slukket.

| Capture | Frames | M?lt s | 1/mean(dt), fps | Lys-kanter Enabled/property | Origin >=0,15 stud |
|---|---:|---:|---:|---:|---:|
| [L1-PC-maze-far-before](play/L1-PC-maze-far-before.txt) | 90 | 6.02500 | 14.84 | 0/0 | 0 |
| [L1-PC-near-before](play/L1-PC-near-before.txt) | 90 | 5.98750 | 14.83 | 0/0 | 0 |
| [L1-phone-far-valid](play/L1-phone-far-valid.txt) | 90 | 5.98333 | 14.91 | 0/0 | 0 |
| [L1-phone-near-valid](play/L1-phone-near-valid.txt) | 91 | 6.01667 | 14.96 | 0/0 | 0 |
| [L4-PC-door-far-before](play/L4-PC-door-far-before.txt) | 90 | 5.95000 | 15.00 | 0/0 | 0 |
| [L4-PC-near-before](play/L4-PC-near-before.txt) | 90 | 5.97083 | 15.00 | 0/0 | 0 |
| [L4-phone-far-valid](play/L4-phone-far-valid.txt) | 90 | 5.96667 | 15.00 | 0/0 | 0 |
| [L4-phone-near-valid](play/L4-phone-near-valid.txt) | 90 | 5.96667 | 15.00 | 0/0 | 0 |

Samlet: 721 frames i otte hovedcaptures; 0 lys-property/Enabled-kanter, 0 origin-events og 0 clearance-ray-hits. N?r-positionerne var ikke clearance-kontakt og udelukker derfor ikke origin-hypotesen. Phone-valid har TouchEnabled=true og 749?381; root valgte iPhone 17 Pro landscape og gemte UI-sk?rmbilleder. Emulatoren er ikke fysisk telefon-GPU-verifikation.

`L1-PC-maze-far-before` mangler RoundActive i selve reporten; root l?ste RoundActive=true direkte kl. 21:10 f?r de senere n?r-tests. ?vrige hovedcaptures har RoundActive=true i metadata. De ekstra `L1-PC-far-before` (120 frames) og `L4-PC-far-before` (90 frames) havde ogs? 0 property/origin-events; f?rste L1-elevatorcapture mangler samtidig RoundActive-bevis og bruges ikke som hovedround-kvalifikation. `L1-phone-near-before` er udeladt fra telefonresultater: device-skift fejlede og TouchEnabled=false.

## H?j kvalitet og Bloom-intervention

QA_Rendering bekr?fter QualityLevel=Level21, EditQualityLevel=Level21 og EnableFRM=false under disse captures; originale Automatic/FRM-v?rdier blev gemt og root gendannede dem. L1-sweeps er afkortet til 1,5 s / 60? for at undg? MCP-resultatets 100 kB-clamp. De kan sammenlignes parvis, men er korte for en intermitterende fejl. L4-high-sweep var 6 s. FPS er callback-dt, ikke et CPU/GPU-benchmark.

| Capture | Frames / m?lt s | Bloom samples / Enabled / Intensity | mean-dt fps | Lys/origin proxy-events |
|---|---:|---|---:|---:|
| [L1-high-bloom-on-valid](play/L1-high-bloom-on-valid.txt) | 90 / 1.51667 | 25 / [True] / [1] | 59.42 | 0/0/0 |
| [L1-high-bloom-off-valid](play/L1-high-bloom-off-valid.txt) | 90 / 1.50000 | 25 / [False] / [1] | 59.27 | 0/0/0 |
| [L1-phone-high-bloom-on-valid](play/L1-phone-high-bloom-on-valid.txt) | 88 / 1.50417 | 25 / [True] / [1] | 57.50 | 0/0/0 |
| [L1-phone-high-bloom-off-valid](play/L1-phone-high-bloom-off-valid.txt) | 89 / 1.53333 | 24 / [False] / [1] | 57.41 | 0/0/0 |
| [L1-phone-high-bloom-held-off](play/L1-phone-high-bloom-held-off.txt) | 88 / 1.50833 | 88 / [False] / [1] | 56.72 | 0/0/0 |
| [L4-high-bloom-on](play/L4-high-bloom-on.txt) | 90 / 5.98333 | 98 / [True] / [0.5] | 15.00 | 0/0/0 |

Held-off-capturen har QA_BloomHeldEachRender=true. F?rste render-snapshot er [time=0, Enabled=false, Intensity=1]; samtlige 88 render-snapshots samt 24 ekstra loop-snapshots er false/1. ?vrige Blooms blev tvangsslukket, men reporten sampler kun den observerede Lighting.Bloom individuelt.

F?rste `L4-high-bloom-off` er en ugyldig OFF-kontrol: 11 samples false og 87 true; Bloom genaktiveres mellem t=0,63333 og 0,69583 s. Dens lommelygte-egenskaber var stadig stabile, men den m? ikke bruges til at konkludere om Bloom-off. Sk?rmbillederne on/off er enkeltbilleder, ikke kontinuerlig flicker-m?ling. De f?rste `L1-high-bloom-on/off` .txt-filer er clamped ved 100.015 bytes og udelades; kun `-valid` anvendes.

## Diagnostisk kontakt: clearance-mekanisme bekr?ftet

[L4-forced-contact-diagnostic](play/L4-forced-contact-diagnostic.txt): 90 frames / 5,9875 s, RoundActive=true, station?rt tvunget kamera (28864,29.7,100.45), avataren forblev l?ngere v?k. 0 Enabled/property-kanter, MaxReconstructionError=0, 0 scene/ancestry-mutationer. Det er en intervention, ikke en normal spillerstance eller synligt flicker-bevis.

| Frame / t | Ray-hit-skift | Residual-hop | Raw-step | Klassifikation |
|---|---|---:|---:|---|
| 2 / 0,12083 s | hit?miss | 0,30463 stud | 0,07208 stud | Excluded initial aim-settling |
| 7 / 0,45417 s | miss?hit | 0,30044 stud | 0,01332 stud | ClipJump |
| 39 / 2,58750 s | hit?miss | 0,30438 stud | 0,01288 stud | ClipJump |

Alle skift vedr?rer `Workspace.Level 4 Cinema Blender.Doors.Door_Service.Leaf`: Part, Plastic, Transparency=1, CanQuery=true, CanCollide=true, CastShadow=false. Denne collider kan flytte lygte-origin via raycasten uden selv at v?re en skyggekaster. Origin f?lger pr?cis den eksisterende clearance-formel; kausaliteten er klar for denne intervention. Det beviser ikke, at samme situation for?rsager ejerens high-only-flicker.

## Level 4-glimt

[L4-reel-glint](play/L4-reel-glint.txt) observerede u?ndret runtime ved `L4FilmReel_3.Canister`: emitterBefore=false, aktiv fra cirka 0,146 s. 50 snapshots over 2,996 s registrerede tre forskellige lokale glimtlys, Shadows=false, Range=8, peak Brightness=2,5 ved cirka 0,146 / 1,313 / 1,979 s. Det dokumenterer, at den eksisterende glimtlogik og lys-pulser k?rte med en m?lrettet runtime-camera; kontinuerlig pixelm?ling og wall/door-occlusion af glimtet er ikke dokumenteret af denne log.

## ?bent / begr?nsninger

- Der var kun ?n levende Player. Metadata viser egne/replikerede egne lys; holdkammerat- og multiplayer-QA er ikke udf?rt.
- Ingen fysisk telefon-GPU-test, ingen sikker normal spillerrepro og ingen f?r/efter-fix-sammenligning.
- Stabil Brightness/Enabled/origin udelukker ikke render-, shadow- eller Bloom-artefakter. Bloom on/off skal vurderes med samme sikre visuelle reproduktion; de her pixeldata er utilstr?kkelige.
- Stage B er en ny ejerautoriseret Bloom-tuningopgave. En moderat intensitetsreduktion m? beskrives som tuning, ikke som bevist flicker-fix.

Fuld analyse pr. capture ligger i `analysis/<label>.json`; r? `.txt` og `.mcp.json` er bevaret i `play/`. Ingen Studio/l?s eller runtime-mirror er ?ndret af analyse-agenten.
