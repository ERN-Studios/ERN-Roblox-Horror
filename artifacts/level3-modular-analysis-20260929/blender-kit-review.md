# Level 3: Blender-kit, mål og importkontrakt

Analyse og forslag, 29. september 2026. Der er ikke bygget eller importeret assets, ændret Studio eller kørt gameplay-/performance-test i denne delopgave.

## Anbefaling

Behold den eksisterende seedede rumgraf som første fundament. Byg et lille Blender-kit af faste indgangsdetaljer, vægfelter, lysarmaturer og møbelgrupper, som placeres på den nuværende variable rumskal. Det giver et synligt løft uden straks at skulle erstatte hele generatorens dimensionering, navigation og finale. Hele rum fra Blender er en mulig senere fase, men kræver en eksplicit politik for tilladte rumstørrelser.

Det tekniske kit kan understøtte både hvid/cyan/lime fra Aero House og den nuværende mall-/feststil. Den endelige materialeretning afventer ejerens valg. Ingen vandflader, akvarier eller springvand indgår. Foreslåede detaljer er tørre interiørelementer: afrundede vægfelter, servicepaneler, skilte, højttalere, planter eller festinventar afhængigt af stilvalget.

## Hvad den aktuelle Studio-kode kræver

Grundlaget er det verificerede Studio-snapshot i `studio-source/`, place `131311258779917`, universe `10559217407`, placeVersion `2403`. `studio-source-manifest.json` registrerer kildehashes og `editorMatches: true` for de læste scripts. Snapshot er et analysegrundlag; ved senere implementation skal live Source og editor-source læses igen. Checkout er omfattende beskidt, og denne checkout har ingen Git-remotes konfigureret; der kunne derfor ikke inspiceres en aktuel remote-historik fra den.

| Kontrakt | Aktuelt grundlag | Konsekvens for kittet |
| --- | --- | --- |
| 26 rum | 3 distrikter med hver 2 × 4 rum, plus Arrival og Exit | Begynd med rumdressing og åbningstyper, ikke en ny fri dungeon-generator. |
| Rumstørrelser | Configuration: W 65–85, D 57–74, H 11–13; generatoren trækker heltal | Et fast 72 × 64-rum kan ikke skaleres ind uden at forvrænge detaljer og flytte sockets. |
| Rumplacering | Delte kolonnecentre, varierende bredder og dybder, distrikter stablet langs Z | Halve studs kan opstå ved kanter/centre. En global 8-stud-snapning ville ændre det eksisterende layout. |
| Forbindelser | Kun lige, akseparallelle forbindelser; højst én centreret åbning på hver rumside | Ingen separat L-, T- eller X-korridor er nødvendig i første kit. Sving og forgreninger sker gennem rum. |
| Korridor | 14 fri bredde × 10,5 fri højde, vægge 1,5 tykke | Ydre bredde er 17. Portaldetaljer må ikke spise af de 14 × 10,5. |
| Gulv/loft | Gulvtop ligger ved lokal Y = 0; gulv er 1 tykt | Pivot på færdigt gulv, ikke modelgruppens bounding-box-center. |
| Rumloft | Loftets center er Y = H og tykkelsen 1 | Faktisk underside er H − 0,5; minimumsrummet har 10,5 fri højde. |
| Arrival | Layout.H er 12, men WorldBuilder tilsidesætter byggehøjden til 30; veståbning er 16 × 16,1 | Må ikke udskiftes med et standardrum eller standardportal. Den eksisterende slide-overgang er særskilt. |
| Exit | Layoutstandard 58 × 52, H 12, samt 560 lang finalekorridor | Finale og freightexit forbliver særskilte i første fase. |
| Navigation | Manager AgentRadius 5, PathAgentRadius 4, SweepRadius 5,25, AgentHeight 10 | Synlig geometri og kollisionsgeometri skal begge respektere det eksisterende frie volumen. |
| Gameplay | 5 CD-rum, 24 autoritative gemmeborde, særlige lyd-/lys-/exitmarkører | Et dekorativt prefab må ikke skabe ekstra prompts, mål eller gemmesteder. |

Kilder i snapshot: `Level 3 Configuration` linje 15–61 og 156–199; `Level 3 Layout Generator` linje 14–32, 63–137, 374–519; `Level 3 World Builder` linje 101–110, 168–211, 1368–1494.

### Heltalsintervallet er ikke et færdigt modulgrid

21 mulige bredder × 18 dybder × 3 højder giver allerede 1.134 mulige dimensionstripler ved standardkonfigurationen, før åbninger og dekorationer. MasterConfiguration kan ændre bredde, dybde, rækkeafstand og finalelængde ved næste generation. Generatorens egne clamps er smallere end nogle af panelets tilladte intervaller. En assetimport må derfor hverken antage konfigurationsstandarderne som alle fremtidige værdier eller stiltiende sætte masterindstillingerne tilbage.

**Første fase:** lad gulv, loft og vægudfyldning forblive parametriske Roblox-Parts. Giv Blender-detaljer faste dimensioner og placer dem i godkendte områder. En 8-stud bred vægkassette gentages et helt antal gange; eventuelle restmål bliver glatte, parametriske endefelter. Brug samme princip i korridorer. Små lister uden særlige detaljer kan have en særskilt dokumenteret strækakse. Døre, panelmønstre, møbler, tekst og buede profiler må ikke få forskellig skala på X/Y/Z.

**Senere, hvis hele præfabrikerede rum ønskes:** skift generatoren til et katalog af konkrete dimensioner, eksempelvis W ∈ {68, 76, 84}, D ∈ {60, 68}, H ∈ {11, 12, 13}. Alle ligger inden for de nuværende standardintervaller. Brug seks grundplaner, højdevarianter i vægopbygningen og åbne/lukkede sidefelter frem for et separat mesh for hver kombination. Det er et forslag, ikke en godkendt ændring. Masterpanelet skal samtidig filtrere kataloget eller vise en tydelig fejl, hvis ingen størrelser passer; der må ikke faldes tilbage til vilkårlig mesh-strækning. Seed-/generatorversion, layout-hash, tests og eksisterende møbeltilpasning skal følge denne ændring.

## Konkret eksport- og socketkontrakt

1. Én Blender-fil indeholder kittets masterobjekter. Hver eksportkollektion repræsenterer ét prefab og får et stabilt `asset_key` og en revision. Eksportér hvert unikt mesh én gang; placér efterfølgende kloner i Studio. Gem også kilde-`.blend`, teksturer og et eksportmanifest.
2. Projektkonventionen er 1 arbejdsenhed = 1 stud. Færdigt gulv ligger ved lokal højde nul. Assets modelleres ved korrekt størrelse, rotation/skala anvendes før eksport, og alle runtime-skalaer starter som 1. Et 1 × 1 × 1-kalibreringsobjekt og en asymmetrisk aksemarkør skal bevise enhed, orientering og spejling før produktion. Roblox dokumenterer understøttet GLTF/FBX-import og særskilte skaleringsindstillinger for FBX. [Blender til Studio](https://create.roblox.com/docs/art/blender)
3. Aftal aksekonverteringen én gang: i dette forslag modelleres +Z som op og +Y som frem i Blender; sidecarens Roblox-koordinater bruger +Y som op og −Z som frem. Punktkonverteringen er `(x, y, z) → (x, z, −y)`. Eksportprofil og sidecar skal bevise samme resultat; konverteringen må ikke blive anvendt både af exporteren og endnu en gang af importeren. Gem rotationsbasis/transform, ikke kun Euler-vinkler.
4. Prefabets pivot er på gulvet ved geometrisk plan-center; et vægpanel har pivot ved bund-center i væggens forbindelsesplan. Et helt standardrum har pivot `(0,0,0)` og side-sockets ved `(±W/2,0,0)` og `(0,0,±D/2)`. En korridorsektion har pivot midt på gulvet, og dens endesockets ligger ved `Z = ±L/2`. Socketposition betyder gulv-midte; aperturhøjde angives separat.
5. Blender-Empties navngives fx `SOCKET_N`, `SOCKET_S`, `SOCKET_CD`, `SOCKET_LIGHT`, `SOCKET_AUDIO`, `SOCKET_HIDE`. Hvert Empty har type, lokal transform, friareal og anvendelsesrolle i custom properties. De eksporteres til en JSON-sidecar af et senere eksportværktøj. Designet forudsætter **ikke**, at standardimporteren automatisk oversætter vilkårlige Empties eller custom properties til Roblox-objekter.
6. Et særskilt Studio-importtrin læser sidecaren, matcher objekter via stabile navne/keys, normaliserer pivot og opretter rigtige `Attachment`-instanser under en stabil BasePart. En lille usynlig, forankret `PrefabRoot` kan bruges, hvis prefabet mangler en passende root; den skal være uden collision, touch, query og skygge. `Attachment.CFrame` gemmer den lokale position/orientering. [Roblox Attachment](https://create.roblox.com/docs/reference/engine/classes/Attachment)
7. Rum-sockets peger udad med deres −Z-akse; en samling matcher position og modsat normal samt samme up-retning. For et generelt socket-match kan mål-pivot beskrives som `målSocketWorld × Yaw(180°) × inverse(kandidatSocketLocal)`. Første integrationsfase placerer stadig rum efter generatorens X/Z og bruger sockets til kontrol, ikke til selvstændigt at opfinde nye forbindelser.
8. Valider før et prefab kan bruges: dimensioner, pivot, unik key, påkrævede sockets, korrekt apertur, bounding boxes, kollisionsgrupper, materialer, ingen scripts, ingen uventede lys/prompts, og importeret skala. Foreslået måletolerance er 0,01 stud og 0,1°; det er et projektkrav som skal kalibreres, ikke en erklæring om importørens præcision.

Eksempel på planlagt sidecar-indhold, uden uploadede asset-ID'er:

```json
{
  "schema": 1,
  "asset_key": "L3.PortalSidePair.14x10_5",
  "revision": 1,
  "units": "stud",
  "space": "Roblox_YUp_NegZForward",
  "source_blend_sha256": "<hash>",
  "export_sha256": "<hash>",
  "scale_policy": "fixed",
  "pivot": "floor_center_in_wall_plane",
  "opening": {"width": 14, "height": 10.5, "wall_thickness": 1.5},
  "sockets": [{"name": "PORTAL", "type": "L3_PORTAL_14_10_5", "position": [0,0,0], "forward": [0,0,-1], "up": [0,1,0]}],
  "material_slots": ["L3_Trim_Main"],
  "collision_policy": "existing_shell",
  "roles": ["decoration_only"]
}
```

Det endelige importmanifest skal desuden registrere nøjagtig Studio-path, ClassName, MeshId, TextureID/SurfaceAppearance-map-ID'er, mesh-/teksturrevision, pivot, bounds, transforms, collision-/query-/shadow-indstillinger og kildefilernes hashes. Templatebiblioteket placeres versionsopdelt under `ServerStorage.Level3Assets`, så generatoren kun kloner allerede importerede assets. En assetspecifikation er ikke tilladelse til at overskrive eksisterende templates. En senere implementeringsopgave skal indlæse den friske Studio-baseline før hver ændring og bevare den fulde native place-backup.

### Eksisterende gameplaymarkører kræver en adapter

Den nuværende `Level 3 CD Table Socket` er en usynlig **BasePart**, og `makeModule()` bruger dens `CFrame`. Gemmebordets anchor, sight-occluder og tabletop-collider er også Parts med konkrete attributter; klient/server forventer deres nuværende funktion. Nye Attachments kan være authoring-data, men må ikke blot erstatte disse typer. Første fase bevarer de eksisterende Parts og lader en adapter beregne deres placering fra prefabets sockets. Korridorens scream-markører er allerede Attachments og skal fortsat ligge ved åbningerne med deres eksisterende attributter og Y = 4,2. CD'en placeres i dag på første relevante bord ved Y = 3,62 over bordgruppens gulvpivot.

## Mindste brugbare første kit

Et passende første leverancemål er cirka 10–12 unikke visuelle asset-definitioner plus et delt materialekit. Antallet er en scope-grænse, ikke et løfte om draw calls.

| Asset | Faste mål/kontrakt | Anvendelse |
| --- | --- | --- |
| Portalens sidedetaljer | Åbning 14 × 10,5; alle detaljer uden for frit volumen | Matcher alle almindelige forbindelser; ingen lavere dekorativ overligger. |
| Vægkassette, neutral | 8 bred × 8 høj; dybde højst 0,25 | Placér i felter uden døråbning; ender fyldes parametrisk. |
| Vægkassette, servicevariant | Samme footprint | Ventilation/låge som normalmap eller lav relief. |
| Lav væg-/sokkelliste | 8 lang; særskilt simpel restlængde | Sammenhængende formsprog uden at ændre rumstørrelser. |
| Korridorens dekorationssektion | Lokal længde 8; respekter 14 × 10,5 fri profil | Gentages på den eksisterende sammenhængende skal. Ingen dublerede gulve/lofter. |
| Loftarmatur | Ca. 4 × 0,25 × 1,5 | Visuelt mesh; eksisterende runtime-lys og blackoutkontrol bevares. |
| Højttaler/serviceboks | Ca. 1,5 × 1,5 × 0,6 | Nyt ydre omkring eksisterende lydplacering. |
| Skilte-/grafikpanel | Ca. 4 × 2 × 0,1 | Ét atlas eller materialefelt; ingen separat tekstur for hvert eksemplar. |
| Møbelvariant til eksisterende bordgruppe | Bordvisual 11,2 × 3,44 × 4,35; samlet gruppefodaftryk 11,2 × 10,8 | Ét nyt design skal først bestå gemme-/CD-/navigationstest. |
| Stol | Nuværende reference 2,55 × 4,3 × 2,58 | Bevar placering/facing mod bordet. |
| Tørt identitetselement A/B | Maks. ca. 6 × 6 grundplan og 8 højde | To tydelige rumvarianter; kun i validerede dekorationszoner. |

Mål med “ca.” er nye art-forslag, som skal greyboxes og godkendes mod den aktuelle geometry. Portal- og gameplaymål er derimod kompatibilitetskrav. Brug tre rumopstillinger med samme lille kit: sparsom ankomstfølelse, møbleret samlingsrum og et markant service-/udstillingsrum. Valg kan ske deterministisk ud fra `room.LocalSeed`, `ThemeId` og `Decor`, mens grafens seed bestemmer ruterne. Det gør variationen reproducerbar og holder artvalgene adskilt fra forbindelsesgenereringen.

Korridorvæggenes aktuelle længde er `L − 1,58`, mens gulvet får `L + 0,04` som tætning. Rumskallen ejer jambs og overligger. Bevar denne ejerskabsregel, og undgå at importere to synlige coplanare skaller oven i hinanden. Gentagne detaljer placeres inden for den allerede afkortede korridorskals længde; sidste rest dækkes med neutral overflade.

## Kollisions- og materialeregler

- Lad den parametriske skal bære kollision i første fase. Visuelle meshes er anchored, `CanCollide=false`, `CanTouch=false`; `CanQuery=false` hvor de ikke bruges til interaktion eller sight checks. Brug simple Parts til nødvendige gulve, vægge og møbelkollisioner. Brug ikke én samlet convex kollisionskrop for et rum med døråbninger. Roblox fremhæver usynlige simple kollisionsdele og billigere fidelity for dekorative meshes; collision geometry kan bruge hukommelse, selv når collision er slået fra. [Performance](https://create.roblox.com/docs/performance-optimization/improve), [CollisionFidelity](https://create.roblox.com/docs/reference/engine/enums/CollisionFidelity)
- Bevar tabletop-kolliderens 11 × 0,48 × 4,15 samt det eksisterende Manager-navexclusion-system, indtil en konkret møbelændring er afprøvet. Et større skab eller en plante ændrer både synlig passage, kollision og AI-routing; dekorativ status alene gør den ikke egnet til at stå i en rute.
- En rumindgang skal bevare sin 14 × 10,5 fri profil; ingen lister, stole eller skilte indenfor. Reservation af en central adgangsstribe fra aktive portalsockets og den eksisterende omkredsvej valideres mod alle dekorationsvarianter. Hold hide- og CD-interaktionsområdet frit for nye props.
- Start med én delt trim sheet på højst 1024² til arkitektur, én lille grafik-/skilteatlas og eksisterende eller delte gentagelige gulv/vægmaterialer. Det er et foreslået startbudget. Anvend normal-/roughnessdetaljer til fuger og skruer, hvor silhuetten ikke kræver geometri. Samme mesh og texture characteristics bør genbruge samme Roblox-ID'er; hele scenen skal ikke genimporteres for hver placering. [Roblox om instancing og texture reuse](https://create.roblox.com/docs/performance-optimization/improve)
- Brug få transparente flader, ingen gennemgående transparent glasvæg som standard, og undgå nye dynamiske lys pr. gentaget panel. Lad armaturmesh følge den eksisterende lyscontroller, så blackout slukker både lys og emissive/neon-lignende visualer. Begynd med `RenderFidelity=Automatic`, kontrollér derefter synlige silhuetter på målplatformen. [MeshPart](https://create.roblox.com/docs/reference/engine/classes/MeshPart)

## Faser og verifikation

1. **Kontraktprøve:** ét 14 × 10,5-portalpar, ét vægpanel og ét armatur. Eksportér kalibreringsobjekter og sidecar, importer i en isoleret testmodel, og kontrollér skala, pivot, normals, sockets og clearance. Ingen udskiftning af live world builder i denne fase.
2. **Vertikalt udsnit:** ét eksisterende rum på minimumsmål 65 × 57 × 11, et stort rum på 85 × 74 × 13 og en korridor med ikke-8-delelig længde. Bevar eksisterende nav, hide, CD og lighting controllers. Se det både belyst og i blackout fra spillerhøjde. Prøv indgangene med Manager og spillere, ikke kun med målestreger.
3. **Første kit:** udvid først efter udsnittet til de 10–12 definitioner og tre opstillinger. Brug kun verificerede kloner i ét distrikt. Visuel gentagelse skal vurderes langs en faktisk rute, især tre lige links og den lange finalekorridor; et enkelt flot stillbillede er ikke tilstrækkeligt.
4. **Hel seedet runde:** sammenlign uændret baseline og kit-version med samme seeds, samme master-overrides og samme 1-/6-spiller-scenarier. Medtag mindst 20 faste seeds samt min/max-dimensioner og en restlængde-case. Bevar 26 rum, fem CD'er, 24 gemmesteder, tilgængelig finale og den eksisterende determinisme.

**Servermålinger:** generationstid, peak antal Instances, hukommelse før/efter build, server frame-/script-tid under normal runde og aktiv jagt, antal path requests/failures/retries og fastkørsler. Test mindst tre reset/build-cyklusser og tjek, at round-owned tasks, connections og modeller frigives. Færre synlige Parts er ikke i sig selv dokumentation for mindre serverarbejde.

**Klientmålinger:** CPU frame time og GPU frame time hver for sig, draw calls, synlige triangles, texture-/mesh-/total memory og kamerarutens p50/p95 frame time. Brug samme kamerarute, grafikkvalitet, opløsning og målmaskine/telefon i A/B. Mål både varm cache og første indlæsning; prøv en rumforgrening, det mest møblerede rum, en lang korridor, blackout og sekvensens lysgenstart. 33,3 ms kan bruges som 30-FPS-rammebudget på den valgte svage målplatform, men intet bestået resultat kan udledes af denne analyse. Roblox skelner selv mellem serverarbejde og klientrendering. [Performance tools og arbejdsgang](https://create.roblox.com/docs/performance-optimization)

**Foreslået release-gate:** ingen tabte sockets/gaps eller blokerede ruter; ingen regression i autoritative mål/gemmesteder; ingen vedvarende vækst efter resets; og dokumenteret acceptabel p95 frame time på den aftalte målplatform. Materiale eller kit, som bryder blackout, Manager-clearance, CD-adgang eller streamingindlæsning, er en blocker. Et godkendt kildekode-review eller en Blender-render kan ikke erstatte disse checks.

Denne rapport har alene afklaret design og integrationsrisici. Assets, importværktøj, generatorændringer, gameplaytest, performance-resultater og publicering er endnu ikke udført.
