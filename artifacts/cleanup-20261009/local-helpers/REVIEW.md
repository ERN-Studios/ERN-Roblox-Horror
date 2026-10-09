# LE-32 / LE-34: to afgrænsede lokale oprydninger

Status: **klar til root-review og frisk native CAS; endnu ikke implementeret**.
Forslag, før-kilder og receipt findes i [candidate-manifest.json](candidate-manifest.json).
`verify_local_helpers.py` har ikke skrevet produktionskilder, manifest eller Studio.

## LE-32 — privat `isStar`, Level 4 Light Director

- Præcis kilde: `ServerScriptService/Level 4 Systems/Level 4 Light Director.ModuleScript.lua:60-66`.
- Ændring: fjern kun den lokale funktionsdefinition og dens efterfølgende tomme linje.
- Bevis: `isStar` forekommer én gang, som privat definition; ingen kald, reference, capture eller API-eksport. Oprettelse af funktionsværdien kalder ikke dens krop. Ingen initializer, require, tags, Instances, forbindelser eller attributter fjernes.
- Afhængigheder bevares: `STAR_TAGS` med A/B/C bruges fortsat af `setStars`; CollectionService og Level 4 Configuration, zonelys/neon, emergency lights, `ClientEvent` Zones/PowerUp og alle `Level4_*` state/authoring-attributter er uændrede.
- Callers: `Level4RoundGenerator` kræver modulet og bruger `Start/Stop`; Objective Controller får LightDirector via sin eksisterende closure og bruger `PowerUp/SetEscalation/Finale`; Usher-flowet bruger det eksisterende zone-/lys-API. Ingen caller kan se den private lokal.
- Risiko/gevinst: lav risiko; fjerner syv ubrugte linjer og én privat closure. Ingen målt gameplay-/FPS-/hukommelsesgevinst påstås.
- Før/efter-testport: hele den aktuelle modulsource køres i offline Luau med engine services/task-clock som grænser. Samme tre zoner, marker-manglende center fallback, tre star-tags samt en fremmed tagged star testes gennem `Start → Off → PowerUp → On → Failing → Finale → Stop`, tom world/reset og gamle forsinkede transitions. Offentligt API, require/service-reads, objekter, properties, attributter og remote-payloads sammenlignes identisk. Uafhængig kontrol, som fjerner aktivt C-tag, fejler på den uændrede test.

## LE-34 — ubrugt `lampShade`-binding, Worn Party Visual Adapter

- Præcis kilde: `ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua:425`.
- Ændring: `local lampShade = devicePart(...)` bliver `devicePart(...)`. Kaldet, argumenterne, skærmens synlige shade og alle objekter bliver stående.
- Bevis: `lampShade` forekommer én gang; værdien læses/captures/eksporteres aldrig. `devicePart` har synlige Instance-/Parent-/property-sideeffekter og bliver kaldt præcis samme sted og én gang både før og efter. Initializer-sideeffekter og fejlpropagation bevares.
- Afhængigheder bevares: Round Adapter `VisualAdapter.Apply(manifest)`; Level 6 Kit Metadata/installer-kit, Dressing, Balloons, Crayon og Manager-familier. Constructorens `player.Model/playerCF`, ni display/support/lamp/shade Parts, housing-attributten og task SurfaceLight er uændrede; SurfaceLight er fortsat parentet til `taskLamp`.
- Authoring-værktøjer: `tools/level3_worn_party/prepare_studio_install.py`, de historiske authoring-payloads, finale-reader native-export/test og promotion-builders bevares. Ingen historisk installer-payload bruges som nuværende kilde eller geninstalleres.
- Risiko/gevinst: lav risiko; én unødvendig privat retur-binding fjernes. Ingen objekt-/feature-/performancegevinst påstås.
- Før/efter-testport: den nøjagtige aktuelle `devicePart`-definition og displayconstructor-blok køres ved Instance-grænsen med en ikke-triviel position/yaw. Hele property/parent/attribute-grafen sammenlignes før/efter, inklusive ni Parts og én SurfaceLight. Samme kontrollerede allocation-fejl på shade-kaldet skal propagere og efterlade samme otte allerede byggede Parts; owner-cleanup fjerner dem. Uafhængig kontrol, som faktisk fjerner shade-kaldet, fejler på objektkontrakten.

## Receipt og plan-entry

`verify_local_helpers.py` kørte **173 assertions**, **otte hele-source compile-porte**
(to kilder × før/efter × O0/O1) og **to semantiske negative kontroller** med Luau 0.737.
Alle bestod, og canonical source/manifest var byte-uændrede bagefter. Der er ingen
native/client/physics/streaming-/fuld installer-kit-test i denne receipt. Testporten
er passende for disse to private locals; den godkender ingen feature-fjernelse.

Foreslået prioritet: lavrisiko-batch efter fundamentet. Root skal før installation
genlæse de to native Sources + editor Sources, bruge præcis scoped CAS fra den
friske baseline, bevare class/properties/attributes og kontrollere efterfølgende
source/editor/manifest-parity samt den konkrete diff. Ved drift af symboler eller
source skal forslagene genvurderes. Gem de medfølgende før-kilder som rollback.

Andre LE-34-locals (`latchMode`, `safeRect.reservePerimeter`, breaker-position)
er særskilte kandidater og er **ikke del af denne receipt**. CORE-025's require-
initializers afventer rigtig full-builder/kit-test; CORE-037's delte attempt-counter
må ikke nulstilles i et aktivt autoritativt serverflow for at prøve en fixture.
