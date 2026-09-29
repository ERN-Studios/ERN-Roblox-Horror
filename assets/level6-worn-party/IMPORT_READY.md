# Level 6 — slidt 90'er-børnefest / mall backrooms

Dette er den færdige **offline-pakke til næste Studio-fase**. Arbejdet er stoppet før yderligere import, gameplay-test og udgivelse efter ejerens seneste besked. `Level6_FULL_Seed101.blend` er hele det byggede eksempelmap; spillet skal bruge de genanvendelige sektioner til at vælge nye stier ved hver runde. Oversigtsbilledet og seks rum-previews ligger ved siden af filerne.

## Leverance

| Fil | Formål |
| --- | --- |
| `Level6_FULL_Seed101.blend` og `Level6_FULL_Seed101_Overview.png` | Komplet 32-rums Blender-map (seed 101), med 37 forbindelser, 3.220 placerede instanser, ca. 1,09 mio. placerede visuelle trekanter, fem CD'er og én CD-afspiller. Play-ydelse er stadig utestet. |
| `Level6_WornParty_v2.blend` | Redigerbar kilde til 49 modulære sektioner, møbler og rekvisitter. |
| `Level6_ImportKit.blend` og `Level6_ReusableKit.fbx` | Standardimport af de 49 navngivne, UV-mappede mesh-assets til Studio. FBX-roundtrip: 48.712 trekanter fordelt på de **unikke** assets. Importens placeringer er kun et overskueligt asset-gitter, ikke det færdige level. |
| `textures/WornParty_Atlas1024.png`, `textures/WornParty_Atlas.png`, `exports-v2/`, `runtime-source/` | Farveatlas og verificerede mesh-payloads til den alternative runtime-bake. Atlas og eksportdata er hash-kontrolleret. |
| `previews-v2/` | Beige party hall, orange birthday rooms, red party maze, budget arcade, party supply store og maintenance workshop. |
| `tools/level6_build/gameplay-candidates/` | Kandidater til random layout, level-systemer, fem-CD-objective, skjul, Mall Manager, belysning, lyd og DEV-preview. |

Fem ElevenLabs-lyde til senere import ligger i `audio/` med originaler, rensede WAV/MP3-filer og [lyd-QA](audio/README.md). Arkadelydens uønskede højfrekvente sus i den stille passage blev sænket ca. 15 dB. Lokale lydfiler er endnu ikke Roblox-audio-asset-ID'er og skal først uploades/bindes i en senere Studio-fase.

## Hvad der allerede skete i Studio

Før stopbeskeden blev `ServerStorage.Level6BlenderSource` lagt i den åbne Edit-session med 49 kildemeshes, og en guardet installation rapporterede 19 nye Level 6-scripts samt fire afgrænsede ændringer i delte scripts. Om den Edit-tilstand blev gemt, er ikke efterkontrolleret. **Det er ikke et færdigt eller publiceret level.** Første Play stoppede, fordi EditableImage API dengang ikke var tilgængelig. Ejeren har siden oplyst, at Mesh/Image API nu er slået til; det er ikke efterprøvet i Studio i denne fase.

Den lokale v2-pakke har en rettet `Level 6 Kit Metadata` i forhold til den allerede installerede Studio-kopi. Den aktuelle lokale pakke må derfor ikke antages at være identisk med Studio. `artifacts/level6-build-20260930/offline-package-handoff.json` angiver de nøjagtige hashes og den ene nødvendige metadata-revision. En native backup fra **før** Level 6-ændringerne findes lokalt som `artifacts/level6-build-20260930/native-backup/BeforeLevel6-AuthoritativeStudio.rbxl` og `all-service-children.rbxm`. De komplette backupfiler holdes ude af Git, fordi de også indeholder hele spillets scripts og mulige hemmeligheder; `native-backup/source-manifest.json` registrerer stier, klasser og hashes uden selve kildekoden.

## Næste Studio-fase — først når ejeren beder om import

1. Forbind til eksisterende place `131311258779917` / universe `10559217407`. Læs den faktiske Studio-instans, både `Source` og editorens source, før nogen ændring. Studio er autoritativt; brug ikke et ældre repository-snapshot som basis.
2. Afstem den ene lokale metadata-revision mod den installerede `ServerScriptService.Level 6 Systems.Level 6 Kit Metadata` med frisk baseline og guardet skrivning. Genkør **ikke** førstegangsinstalleren på allerede eksisterende Level 6-scripts.
3. Kontrollér den af ejeren oplyste Mesh/Image API-indstilling. Vælg derefter enten at færdigbage de 49 runtime-templates fra den allerede installerede kilde eller importer det almindelige FBX-kit og atlas gennem Studio. Se `artifacts/level6-build-20260930/import-preview-handoff.json` for de forventede stier. Der er ikke gennemført en vellykket 49-mesh-bake eller Studio-FBX-import endnu.
4. Kør Play-test: DEV-døren i lobbyen, tilfældige ruter, alle fem CD'er og afspilleren, arcade- og serviceinteraktioner, kollisionsgulve/tyngdekraft, lys/lyd, skjul, Manager, blackout, escape og oprydning ved reset. Test også flere spillere, spawn-afstand, navigation/retry og server-CPU/hukommelse. Kildeinspektion alene tæller ikke som bestået gameplay-test.
5. Eksportér efter verificering den faktiske Studio-tilstand og native place-data til repository; gennemse staged diff og commit kun opgavens ændringer. Udgiv først, når kontrollerne er bestået og den aktuelle ejerscope tillader Studio-arbejde.

Offline-kontrollerne og begrænsningerne er dokumenteret i `artifacts/level6-build-20260930/`. Den oprindelige Level 3 og alle uvedkommende Studio-objekter skal bevares.
