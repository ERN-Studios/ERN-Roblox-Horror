# S19: eksakt supplement på testejede native kopier

**Native setter-/recovery-porten er endnu ikke kørt.** Denne mappe gør næste afgrænsede port klar til Root. Den pensionerer, sletter eller ændrer ingen autoritativ Studio-instans. S04's fem pensionerede authoringpakker beholder deres manglende gameplay-/multiplayer-/streaming-porte.

Historisk rå genåbning fejlede 2/23 træer. Den fejl ændres ikke til PASS. Binary- og Lune-diagnostikken i `../storage-next-v1` afgrænser forskellen til fire `Bone.CFrame`-matricer; supplementet indeholder deres præcise 12 komponenter fra de komplette før-facts. Opskriften accepterer ingen tolerance, afrunding eller ændret historisk baseline.

## Frosne kilder

| Fil | Bytes | SHA-256 |
| --- | ---: | --- |
| `restoration-probe-v4.luau` | 29240 | `133436198c3b5a7338f9327beb8d8023c14203ee1dbb69372b2287d65b22c31b` |
| `capture-live-baseline.luau` | 8357 | `df846a007464c2f5bf11284b69eecf32b0c8ecaf4fe776481489483fc7095a2b` |
| `receiver.py` | 17682 | `4a70b5216d45321461aa9e0c482cefc6391b389ef92e2f905783a60d832267bc` |
| `restore-supplement.json` | 2511 | `0c83647db8c7a2c299834481c0d3b1032a97ca2aafe9aacf8091f2523392b7a1` |

`file-pins.json` fryser øvrige top-level-filer og de historiske inddata. Nye native executions skal ligge i deres egne nye undermapper. V1/V2/V3 prototyper er historiske og må ikke eksekveres. V3 havde en lokal scope-fejl: hjælperen læste global `supplement`, fordi den lokale variabel først blev deklareret senere. V4 forward-deklarerer variablen før hjælperen uden et senere shadow. V3 og fejlede testforsøg er bevaret.

## Udførte porte og deres grænser

- `copy-fault-proof.json`: faktisk V4 ownership-/setter-/to-genåbnings-/cleanup-kode udtrukket med dens rigtige deklarationsrækkefølge. PASS 20 scenarier, 30.282 assertions, 10 compile-enheder ved O0/O1. V3 er negativ kontrol med manglende global supplement: nul setters, 23 adopterede rødder ryddes op. V4's normale sti foretager otte testejede setters og rydder 46 rødder op. Fejl før commit, commit-then-throw i begge genåbninger, historisk mismatch, konstruktør-/setterforskel, DS-/serializerfejl, original aliases, identitetsændring, dublette targets og cleanupfejl i begge genåbninger afvises. Original Source/Parent/CFrame og identiteter kontrolleres. CFrame, serializer, reflection, scene og callbacks er eksplicitte fakes; hashing er rigtig. Assertions kan variere lidt med rækkefølgen i hash-tabeller før en forventet fejl.
- `receiver-fault-proof.json`: PASS 87 scenarier/50 assertions med den faktiske receiver og localhost HTTP. Tests bruger den pinnede gamle native binary/facts samt syntetiske Source-pins og completion-claims. Forkerte bytes, manglende dele, tvetydig JSON, ikke-endelige tal, forkerte typer/tællinger, ændrede outputkilder, tidlig completion og falske slutguards afvises. En transfer-kvittering har altid `passed=false` indtil en særskilt slutrapport. Disse tests indeholder ingen native kvittering.
- `lune-constructor-boundary-result-v1.json`: **FAIL**, 21/48 komponenter er ikke eksakt ens i Lune 0.10.5. Forskellene er bevaret enkeltvis. Ingen tolerance er anvendt, og denne test er ikke omdøbt til PASS.
- `readonly-constructor-native-result-v1.json`: Root udførte den separat pinnede, rent læsende native probe kl. 08:01:16Z. PASS 111 checks, fire historiske originaler/48 komponenter, eksakt `CFrame.new`, originaler uændrede, nul native objekter/setters/Source-/Parent-/shared-/mode-writes. Det beviser native matematik, ikke setter/recovery, gameplay eller arkivsletning.

Peer har uafhængigt genkørt V4's fault-port; resultat ligger i `../foundation-next-v1/storage-v4-fault-peer-v1.json`. Receiver-peer og eventuelle native resultater registreres særskilt af Root.

## Konkret Root-sekvens

1. Kontrollér frisk native Edit, PlaceId `131311258779917`, universe `10559217407`, Studio-id `1b603e69-7ae1-4572-b210-d5bf05c684ff`, eksisterende HTTP, ingen aktive gamle leases, ledger med præcis 73 `rootRefs` og 222 `scriptRefs`. Tag faktiske `#ServerStorage:GetChildren()` og `#game:GetDescendants()`; manifestets 15/228 rækker er ikke scenens census. Root målte 52/416284 kl. 08:11:50Z; de værdier kan kun bruges, hvis de stadig er aktuelle. Bevar Roots uafhængige, friske Source/Parent/userdata-guards for alle 213 aktuelle scripts.
2. Kontrollér `file-pins.json` før start. Start nedenstående receiver med den friske native census og en ny destination. Receiveren importerer aldrig MCP/Studio og starter med `/context` låst. Windows baggrundsstart skal være skjult. Ingen modeskift eller ændring af HTTP-properties for at få testen til at køre.

   ```powershell
   python -B artifacts/cleanup-20261010/storage-restoration-v1/receiver.py --dest artifacts/cleanup-20261010/storage-restoration-v1/native-v4-run-v1 --expected-live-roots 52 --expected-live-descendants 416284
   ```

3. Root læser den immutable executions `baseline-source.luau`, verificerer SHA/bytes og eksekverer den direkte gennem den eksisterende Studio MCP `execute_luau` med `datamodel_type=Edit`. Proben læser native Source/editor, class, Parent-identitet, Enabled/Disabled/RunContext/LinkedSource, attributes og tags for alle 213 scripts. Den sender `/baseline` selv, men genkontrollerer bagefter og efter release af alle watchers. Root gemmer den faktiske MCP-slutrapport eksklusivt og sender dens faktiske JSON til `POST http://127.0.0.1:18916/baseline-completion`. Ingen syntetiske/påtvungne PASS-fields. Kun en vellykket, valideret slutrapport låser `/context` op. Ved drift/Play/fejl bevares kvitteringen; ny gennemgang og ny destination kræves.
4. Root verificerer igen mode, alle relevante aktuelle native guards og de pinnede executions `probe-source.luau` bytes/SHA. Eksekvér kun V4 gennem samme Studio MCP, direkte kode uden cloned LuaSourceContainer/editor-staging. Proben beskytter hele aktuelle og held-originale identitetsmængde; kræver friske 213 Source-pins og byte-eksakt gammel held-native archive **før** DS. Den adopterer kun uparentede, ikke-originale kopier, anvender de fire eksakte setters, sammenligner hele læsbare skov/12 Sources/10 interne referencer og kræver raw binary SHA/bytes lig den gamle original. Den gentager DS, fire setters, hele skoven og raw serialization én gang. Setter-normalisering eller andet mismatch afviser porten.
5. V4 sender fire `/roundtrip/0..3` dele og `/finalize` før cleanup; den kvittering er udtrykkeligt før-slutrapport. Proben forsøger uafhængig cleanup af alle adopterede rødder også ved throw, genkontrollerer originale Sources/properties/Parent/raw binary, frigiver kun sin egen lease og returnerer først derefter sin faktiske rapport. Root gemmer den uændret som ny native completion og sender `POST /completion`. Receiveren kræver begge eksakte genåbninger, 46 adopterede/skabte/destruerede rødder, nul tilbage, otte forsøg/bekræftede setters, alle slutguards, de eksakte hash/counts og ingen normalisering. Ved fejl: behold pending; ingen original restoration, ingen lease-overskrivning, ingen automatisk udvidelse af setterlisten.
6. Kontrollér console, aktuel all213 parity/userdata, leases og native før/efter guards, samt receiverens særskilte `port-verdict.json`. En eventuel PASS gælder **rå RBXM plus dette eksakte supplement efter hver genåbning** i den afprøvede engine. Det gamle rå-arkiv-alene-resultat forbliver FAIL. Der gives ingen full-place-, eksternt asset-, gameplay-, multiplayer-, streaming-, performance-, native deletion- eller publish-godkendelse. Stop receiveren efter porten; originals/ledger fjernes ikke af denne opskrift.

## Reproducerbare offline commands

```powershell
python -B artifacts/cleanup-20261010/storage-restoration-v1/test-copy-faults.py --receipt <ny-json-i-cleanup-20261010>
python -B artifacts/cleanup-20261010/storage-restoration-v1/test-receiver.py --receipt <ny-json-i-cleanup-20261010>
python -B artifacts/cleanup-20261010/storage-restoration-v1/verify-file-pins.py
```

Ingen tests må overskrive eksisterende kvitteringer. Preparations er engangsgeneratorer med eksklusiv output; genkør ikke oven på historiske filer. Der er ingen målte gameplay/performancegevinster. Arbejdet i denne mappe foretog ingen Studio-kald, Source/manifest/index writes eller commits; den nævnte native matematikrapport blev udført og tilføjet særskilt af Root.
