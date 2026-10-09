# Lommelygte-flicker: QA-protokol

Status: offline forberedt. Ingen Play-observation eller visuel reproduktion endnu.

Studio er autoritativt. Kun sessionen `Flashlight flicker fix` må bruge Studio under sin tildelte lås. Ingen commit, push eller udgivelse. Første periode estimeret 25 minutter; fix/verifikation kræver en separat køpost, hvis årsagen er bevist.

1. Bekræft korrekt Studio/place/universe, Edit og frisk Source/editor-paritet for Controller, Sync, Profiles, Spectate og L4-klienterne. Eksportér den friske baseline med præcise paths, klasser og SHA256. Konflikt eller driftsforskel skal afklares før scripts ændres. En ældre repositorykopi må aldrig pushes.
2. Start en rigtig Play-session og en Level 1-runde via spillerens lobby-flow. Pausér entity via den eksisterende developerfunktion. Behold batteri/focus/profil konstant i hver måling; log tilsigtede batteriblink særskilt. Ingen ændring af gameplay til test i Edit.
3. Vælg faktiske vægge, hjørner/døre og mindst én række af små props. Gem præcise paths, positioner og materialer; CanCollide, CanQuery, CastShadow, Transparency og MeshPart RenderFidelity. Vælg én nær og én fjern position pr. sweep. Et objekt, som ikke findes, registreres som ikke testet.
4. Kør samme 8-sekunders venstre/højre sweep med fast kamerarotation/position og frame-probe efter MongoFlashlight. Registrér Enabled, Brightness, Range, Angle, Shadows og fuld CFrame for egne/mate/server-lys; camera/raw hand/clamp-hit, SpectateBattery-proxy, DevUnlimited/frisk charge, focus, FPS/dt, lysidentitet og synlige/streamede målobjekter. Proxien er ikke controllerens private batterilokal. Gem rå JSON, eventliste og screenshots/logs. Registrér synlig flicker separat; egenskabsspring er en proxy, ikke bevis for en ændring i renderet lys.
5. Gentag i en faktisk Level 4-runde ved væg/dør, hylder/små props og glas hvor det findes. Kontroller også en løs reel: glint tænder i korrekt kegle og skjules af væg/dør. Level 2 new-map preview og Level 3 er ekstra checks, når låsetiden tillader dem.
6. Gentag med Studio Device Simulator i telefonprofil, og registrér profil, faktisk viewport, input og grafikkvalitet. ForceTouchUI er alene UI-formfaktor og tæller ikke som emulatorkørsel eller fysisk telefon/GPU-test.
7. Brug en rigtig anden deltager til multiplayer-verifikation. En fremstillet karakter kan teste rendering-koden, men tæller ikke som ægte co-op. Log begge mate-renderveje (Head/MateBeamCore og ReplicatedFlashlight) særskilt. Undlad at bruge en falsk deltager som bevis for multiplayer.
8. Hvis flimren ses med uændrede properties og uden clamp-hit, gå videre til afgrænsede render-/shadow-/streamingdiagnoser. A/B af kun eget Shadows i Play må kun bruges som diagnose og skal restaureres i samme kald. Justér ikke lysstyrke/range/angle for at skjule symptomet. Ingen antagelse om et bestemt Roblox shadow-budget uden måling.
9. Stop Play, fjern prober/connections og verificér Edit før låsen slippes. Hvis årsagen ikke er entydig, stop uden fix og rapportér udelukkede forhold, mistanker og konkrete ubekræftede checks.

## Måling og tærskler

- Origin-event: vector-residualt hop >=0,15 studs i faktisk minus rå håndbevægelse, mens samme lysidentitet/profil/focus er aktiv; log tidsstempel og raycast-hit. Ekskludér kamera-/spawn-/respawn-/profilovergange fra den stationære sweep-score. Offline-testens >0,1-stud-positionsspring er en separat metric og må ikke indsættes som Play før/efter-resultat.
- Property-event: Enabled-kant eller ændring i Brightness/Range/Angle/Shadows uden forventet toggle, profil-/focus-/batteriovergang. Batteri 50 %/25 % kan give tilsigtede Enabled-blink; behold dem i rålog og kategorisér dem.
- Probe-summary tæller alle rå Enabled/property-kanter på alle observerede lys, inklusive legitime stateændringer. Disse summary-tal er ikke direkte tællere for uventede hændelser; rålog skal efterklassificeres per lys og sammenholdes med state/proxybatteri. Brug frisk charge/DevUnlimited i det kontrollerede sweep for at udelukke batteriadvarsler.
- Før/efter: samme world seed, målpaths, kamerabane, afstand, fokus, batteri, grafikkvalitet, formfaktor og deltagerantal. Antal events skal normaliseres til måletid og frame-antal; aldrig rapportér nul ved manglende data.
- Render-only flicker kan eksistere uden property-events. Per-frame property-log kan derfor hverken alene bevise eller udelukke den rapporterede bug.

## Hypoteser og beslutningskriterier

| Hypotese | Nødvendigt bevis |
| --- | --- |
| Eye-to-hand clamp hopper | Visuel hændelse tidsmæssigt sammenfaldende med clamp-/residual-event ved nærflade; fjernsweep uden clamp som kontrol |
| Shadow-konflikt | Konstant origin/properties, reproducerbar visuel forskel ved afgrænset shadow A/B og kendt grafikkvalitet/lysbestand |
| Parts/mesh/shadow-kant | Specifik part-/materiale-/mesh-/overlapafhængighed; synlige mål og properties bevaret |
| Streaming | Hændelse sammenfalder med faktisk target ancestry/indstreaming; samme sweep efter stabil streaming |
| Overshoot/flere writers | Uventet B/R/A/CFrame/Enabled-write uden legitim stateovergang; sammenlign frame-prioritet og lysidentitet |
| Lighting-model | Frisk LightingStyle/PrioritizeLightingQuality + grafikkvalitet og reproducérbar rendererafhængighed; gammel Technology-label er utilstrækkelig |
