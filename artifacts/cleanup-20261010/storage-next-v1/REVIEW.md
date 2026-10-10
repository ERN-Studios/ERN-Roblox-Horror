# Næste ServerStorage-batch — præcis restoration før yderligere sletning

**Anbefaling:** gennemfør den snævre S06-recovery-port med et eksakt supplement til fire `Bone.CFrame`-værdier. S04's fem native authoringpakker bliver stående, indtil deres faktiske R4/V2/elevator-porte består. Dette review har udført **nul Studio-kald og nul native-, Source-, manifest-, index- eller commit-writes**.

## Ny konstatering om S06

De to historiske native filer blev genkontrolleret direkte:

- Original: `external-storage-archive-v1/native.rbxm`, 2.739.764 bytes, SHA `139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca`.
- Native deserialization/reserialization: `external-storage-reopen-v1/roundtrip.rbxm`, samme byteantal, SHA `dbfb34d6dc742c50c4b743fd7a5fc0e374599f3b8c81ea1e8f5d6baa455eb121`.

Det lokale, eksakte chunk-check finder **283 chunks; header og 282 hele chunks er byte-identiske**. Kun `PROP`, klasse `Bone`, property `CFrame`, ændres: seks ukomprimerede bytes i chunk42. Ingen ændring er accepteret eller normaliseret. [Chunk-bevis](native-chunk-differences.json).

Lune0.10.5 blev derefter brugt som en separat lokal diagnostic-decoder. Sammenligningen af 14.079 decoded objekter og 151.983 properties finder præcis fire ændrede `R21`-matrixkomponenter:

| Root og præcist descendant-forløb | Original XML-tal | Reopened XML-tal |
|---|---:|---:|
| `TEMP_PipeEntityValidation/PipeEntity_LocalPreview/RootPart/Root/Hips/LeftUpperLeg` | 0.0000001889147 | 0.00000018891308 |
| Samme forløb, `RightUpperLeg` | 0.00000018896198 | 0.00000018895771 |
| `TrelloPoolSlideReleaseBackup_20260910/Level 2 Pool Slide Template/RootPart/Root/Hips/LeftUpperLeg` | 0.0000001889147 | 0.00000018891308 |
| Samme forløb, `RightUpperLeg` | 0.00000018896198 | 0.00000018895771 |

De numeriske XML-forskelle er henholdsvis -1,62e-12 og -4,27e-12. Der anvendes **ingen epsilon**. Originalt capture/transport er hashkontrolleret og uændret; mismatch findes mellem den native originalblob og den native copy-reserialization. Det er ikke et identificeret transportproblem. Dette diagnostic beviser heller ikke, at alle tidligere native readable forskelle er klassificeret: engine-getters og beregnede værdier kan have andre forskelle, selv når deres serialiserede chunks er identiske. Den komplette native readable port skal stadig bestå. [Decoded bevis](offline-differences.json).

Lune-XML kan udelade engine/private felter og er derfor ikke restoration-bevis. De to cirka25 MB XML-filer er regenererbare lokale mellemprodukter; de er ikke commitkandidater. De eksisterende native blobs, full-facts og failed native receipt bevares bytepræcist.

## Forberedt snæver candidate — V2

[restoration-supplement-probe-v2.luau](restoration-supplement-probe-v2.luau) er **27.000 bytes**, SHA `c9ae7a5f71fd836d8722eb77786c7c1a6ded062c0f8dbfd53387982a022a66ab`. Den er afledt af den aktuelle, ejerskabshærdede `tools/cleanup_20261009/external_storage_archive_reopen.luau`; authoritative tooling er ikke ændret. Den er **ikke kørt native** og må først anvendes efter nedenstående gates.

[restore-supplement.json](restore-supplement.json) er et eksakt udvalg af alle12 komponenter for netop de fire Bone.CFrame fra den 41.912.358-byte før-facts. Før-facts SHA er `b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33`; supplement SHA er `0c83647db8c7a2c299834481c0d3b1032a97ca2aafe9aacf8091f2523392b7a1`. Der er ikke afrundet eller ændret data.

Den forberedte recipe:

1. Beskyt alle current/held native originalidentiteter, Source/editor og metadata med den eksisterende S06-guard. Kræv korrekt Edit/place/universe, eksakt ledger og uændret native originalblob.
2. Deserialize det pinned arkiv til nye, adopterede, uparented testkopier; afvis original-, fremmede og overlappende identiteter. Gem det urettede readable resultat og reproducer det tidligere mismatch.
3. Find kun de fire pinned paths i current held-original slots og i de test-ejede kopier. Kræv `Bone` og `CFrame`, entydighed for disse fire og eksakt overensstemmelse mellem frisk original og historiske12 komponenter. Andre animationstræer må have gentagne Keyframe/Pose-navne.
4. Kræv, at `CFrame.new` genskaber alle12 komponenter eksakt. Sæt derefter kun `copy.CFrame` på den identificerede test-ejede Bone. Recheck ejerskab lige før setter og originalguards før/efter. Kræv både eksakt CFrame-lighed og alle12 komponenter efter setter. Constructor-/setter-normalisering er **FAIL/pending**, ikke et tolerance-pass. Setter-attempts registreres særskilt, så et commit-then-throw ikke beskrives som nul attempts.
5. Genkør hele23-træers readable/property/subtree-port, de12 Sources og de10 interne referencer; reserialisér og kræv **eksakt originalnative SHA/byteantal**. Ingen udvidelse til andre property-setters må ske automatisk.
6. Udfør et andet native reopen af den eksakte blob og gentag samme supplement-recipe. Kræv igen hele readable/reference-port og originalnative bytes. Forvent i alt46 test-ejede roots og otte copy-only setters, alle uafhængigt destrueret efter success eller throw. Original Source/editor/property/parent/nativeblob skal være uændrede efter cleanup og receipt-transfer.

Dette er en foreslået **arkiv-plus-supplement restoration-recipe**. Det rå arkiv alene forbliver en dokumenteret fejlet recovery. `restorationCertified` forbliver false i prototype-receipts; en eventuel senere pass skal beskrive den snævre recipe og den faktiske native execution, ikke omskrive den gamle fejl.

V1-prototypen er bevaret som unexecuted historik: dens bredere path-map ville afvise 276 legitime duplicate historiske Keyframe/Pose paths før setter. V2 mapper kun de fire pinned targets. Begge er compile-checked; intet native forsøg anvendte V1.

## Manglende gates før native candidate execution

- Separat immutable receiver på18916 med V2-context, pinned arkiv og supplement, ny outputdestination, aktuelle originale/source-counts, input guards og receipt efter final original-/cleanupguards. Den eksisterende18915-wrapper må ikke bruges med forkert schema eller uden supplement.
- Kør den **nye actual-source supplementhelper** med uafhængige fault-fixtures: irrelevant duplicate paths, duplicate target, historisk originaldiff, original-alias/foreign copy, constructor-diff, setter-diff, failure-before-write, commit-then-throw, originalguardthrow efter setter, anden deserialize/serialize-fejl og uafhængig cleanup-failure. Ingen originalidentitet må kunne få setter-/Destroy-eligibilitet.
- De genbrugte registration/adoption/cleanup-udsnit har bestået16 actual-source synthetic ownership-scenarier i begge kandidater: V1 registrerede4.235 assertions; V2 registrerede4.237. Hver preflight compilet otte O0/O1 enheder, herunder den komplette request. Dette tester ikke den nye constructor/setter eller et native engine-reopen. [Aktuelt V2-scope](offline-preflight-v2.json); [historisk V1-scope](offline-preflight.json).
- Root skal gennemgå den præcise nye request, verificere en frisk native baseline og bevare andre actors' Play/edits. Ved præcis mismatch: rens egne kopier, gem failure, bevar originals og fortsæt andre kandidater.

## S04: hvad der konkret kan flytte de fem pakker frem

S04's native arkiv og separate engine reopen er allerede bestået med 1.617 objekter/8.050.869 bytes og ti egne kopier ryddet. Det manglende er de aktive flows; en ny serializer løser ikke disse gates.

Lav to separate før/efter-ports, så et bestået lobby-scope kan dokumenteres uden at foregive, at Level1 er bestået:

- **R4/lobby:** frisk faktisk `RuntimeBake.GetManifest/Ensure` og full `Builder.Build`, faktisk mesh/PBR/colliders/lenses, support-board forbindelser, QueueBridge, queue/reentry/reset/fejl. Gentag i isoleret runtime med de fire gamle sourcepackages utilgængelige og ved manglende aktive R4-pakke; cold-cache kræver ny module/runtimeidentity. Relevant multiplayer/streaming forbliver separat.
- **Level1 V2/elevator:** `BlenderRoomRenderer.IsReady/Begin`, faktiske V2 room-masks/components samt elevator exterior/cabin/door, efterfølgende respawn/cleanup/rebuild. Gentag med gammelt Level1BlenderKit utilgængeligt og ved manglende/incomplete aktive V2/elevatorpakker. Bevar actual meshes/PBR/collision/queryparts, old texture inputs, receipts og shared helpers.

Kald ikke den current live `Builder.Build` som et harmløst cold-cache-probe: existing-preview-grenen starter DevBayAccessGuard, og support-board logic kan flytte den originale renderer med closure-held forbindelser. `RuntimeBake.Ensure` skriver det faste R4-kitnavn i ServerStorage og afviser et eksisterende sessionkit; live caches/kit må ikke force-cleares for at teste. Faktiske asset-build contracts med kontrolleret service/namespace-proxy kan reducere det manglende asset-scope, men er stadig ikke queue/gameplay-, multiplayer- eller streaming-pass.

Der er ingen ny produktbeslutning: ejeren har allerede pensioneret de gamle workflows. Pakkerne afventer tests, og en anden actors' Play må ikke stoppes. S04-fjernelse, S06-opaque/readable recovery, publicering og performanceforbedring er ikke gennemført eller godkendt af dette review.
