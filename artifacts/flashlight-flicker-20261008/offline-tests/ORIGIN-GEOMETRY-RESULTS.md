# Offline-resultat: lygte-origin og mate-shaft

Dette er en syntetisk geometrimåling af den frosne checkout-baseline, **ikke en reproduktion af ejerens visuelle flicker**. Ingen Studio-kald, lås, runtime-mirror-redigering, commit eller udgivelse er udført af dette harness.

Kilde: `../offline-baseline/StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua`, rå SHA-256 `f0666fe69f40ecfaa843865aecd432b30830daeeeee8652c480e69b8308d6c04`. Runneren udtrækker de originale origin-linjer 152–170, mate-visual-linjer 851–857, ray-opsætning og de fire relevante offset/længde-konstanter. Hash og udtræksområder står også i `origin_geometry_metadata.json`.

## Måling

Kameraet flyttes 0,001 stud pr. frame med fast orientering. Ti små axis-aligned paneler ligger i rayens vej. Et event betyder et positionsspring over 0,1 stud; det er en algoritmisk tærskel, ikke en måling af pixelflimren. Fake-raycasten behandler querybare, ikke-kolliderende og transparente parts som eligible og respekterer descendant-eksklusionen. Det er en eksplicit fake-kontrakt, ikke en observeret Roblox-raycast.

| Sweep | Frames | Events >0,1 stud | Største positionsspring | Frames med håndretraction |
| --- | ---: | ---: | ---: | ---: |
| Egen origin, tom verden | 801 | 0 | 0,001 stud | 0 |
| Egen origin, tynde opaque/collidable paneler | 801 | 20 | 0,332998 stud | 320 |
| Egen origin, tynde transparente/noncollidable paneler | 801 | 20 | 0,332998 stud | 320 |
| Egen origin, samme paneler med `CanQuery=false` i fake | 801 | 0 | 0,001 stud | 0 |

Håndoffsettet i baseline er 0,463681 stud ved denne orientering. Et query-hit før 0,3 stud clampler origin helt ind til øjet; hit/no-hit-skift kan dermed flytte origin hele 0,463681 stud uden nogen ændring af lysstyrke/rækkevidde. Et isoleret nær-hånd-hit i harnesset gav 0,338318 stud retraction. Skift mellem hit og no-hit er diskret; der er ingen hysterese eller smoothing af hit-korrektionen i dette udtræk.

Mate-sweepet havde 1.101 frames og 20 shaft-endpoint-spring over 0,1 stud, maks. 39,001 stud, når rayen skiftede mellem et nært panel og default-reach 40. **Mate-koden retractor ikke origin og flytter ikke head-parented SpotLights.** Mate-origin fulgte kameraeksemplets konstante 0,001 stud pr. frame. Dette tester shaft/lens-visualet, ikke illumination.

## Filtre og egenskaber

- Egen origin-ray ekskluderer camera og egen character samt descendants. Andre characters ekskluderes ikke; i fake gav en anden character i rayens vej håndretraction.
- Mate-ray ekskluderer den pågældende mate-character og lens samt descendants. Den observerende spillers character ekskluderes ikke; den kunne afkorte shaften i fake.
- Ingen af de to udtrukne blokke undersøger hit-partens `Transparency`, `CanCollide` eller `CastShadow`. Med samme eligible hit-position er resultatet derfor identisk i disse property-cases.
- Fake-casen med `CanQuery=false` er et sanity-check af vores geometrimodel; den er ikke en live bekræftelse af Roblox query-regler.

## Kørsel og begrænsninger

Kør fra repo-roden: `python artifacts/flashlight-flicker-20261008/offline-tests/run_origin_geometry.py`. Runneren genererer harnesset i en `TemporaryDirectory`, som automatisk ryddes efter kørslen. Luau 0.737 kompilerede både den frosne fulde controller og det genererede harness med `-O0`. Run sluttede med exit 0 og 1.124 assertions; 1.101 af disse kontrollerer mate-origin frame for frame. Den rå log er `origin_geometry_results.txt`.

Hypotese 1 har en konkret mulig mekanisme i kildekoden: kameraets meget lille bevægelse kan give et betydeligt hit/no-hit-origin-spring. Det beviser hverken, at det sker i de faktiske Level 1/4-scener, eller at det giver ejerens intermitterende flicker. Der er ingen foreslået eller implementeret fix her.

Skygge-budget, render-artefakter, streaming, Lighting.Technology/LightingStyle og andre writers/loops er ikke testet af dette harness. `Enabled`, `Brightness`, `Range`, `Angle`, `Shadows`, CFrame-Lerp og pixeloutput måles ikke her. PC/telefon, multiplayer, før/efter-fix og Level 4-glimtet skal stadig verificeres i rigtig Play. Frosset checkout-source er ikke dokumentation for aktuel Studio-paritet.
