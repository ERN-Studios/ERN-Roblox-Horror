# C06 — Level4PreviewPrompt no-op identity branch

Status: **afventer test**. Denne delopgave har ikke kaldt Studio, installeret
runtimekode, skrevet manifest/index, committet eller ændret eksisterende
hovedrapporter. Root ejer frisk native binding, førport, scoped CAS/eksport og
installeret efterport. Ejerens og øvrige udvikleres Play-sessioner bevares.

Præcis kandidat er
`StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua`, den
femlinjede blok umiddelbart efter `if ok and allowed == true then return end`.
LF-kilden er 1.622 bytes, SHA256
`161206ea81938d5a10408bc85f6c2b027c37015cc51378b3d721cbb8323c4436`.
Kandidaten er 1.407 bytes, SHA256
`e024ae800bea7082e72a590e948c0b54e9db503db70ef24e50f51024726ad4d3`.
215 kildebytes forsvinder. Kandidaten matcher det tidligere individuelle C06
proof; den gamle sammensatte Loading-unit genbruges ikke.

Blokken læser LocalPlayer.UserId, sammenligner med den særlige preview-bruger
og skriver nil til to fraværende Level6 keys i en frisk, private plain PROMPTS
literal. Literalen har kun to Level4 keys; ingen shared table, metatable,
Level6 key-writer eller observer kan være til stede før denne blok. Det normale
Legacy LocalScript-klientmiljø har en LocalPlayer og en engine UserId scalar.
Conditionen og dens read har alene til formål at omgive de to no-op writes.
Et nil LocalPlayer eller en syntetisk UserId-getter, der kaster, er uden for
det normale Legacy LocalScript-klientdomæne og er ikke certificeret som
adfærdsækvivalent; condition-removal ville fjerne netop den fejlede read.
Ingen constructor, require, runtimefeature, API, event callback, filter,
dev-adgangsbeslutning eller prompt fjernes. Hele øvrige kilden er byte-identisk.
O0/O1 opcodes er **ikke** identiske, fordi den overflødige read/branch forsvinder;
en bytecode-identitet påstås derfor ikke.

## Dependency-closure

- Scriptets eneste services er Players og ReplicatedStorage. Det samme
  `WaitForChild("DevAccess", 10)` og samme `require(accessModule).IsAllowed`
  udføres fortsat. DevAccess initializer/public APIs bliver stående.
- `PROMPTS` er script-private. Den aktuelle `watching` weak-key table,
  `hide`, native Enabled-watchers, workspace DescendantAdded subscription
  og initial descendant-enumeration er helt uændrede. Ingen remote eller
  gameplayattribute læses eller skrives af dette clientfilter.
- L4 map preview-adgang er kosmetisk filtrering af to navngivne prompts.
  Server adgang/admission og de offentlige L4–L6 queueflows ændres ikke.
  Gamle server-preview-navne kan forekomme i historiske callers/comments;
  de er ikke slettebevis for aktivt clientfilter.
- De aktive Level6PreviewAccess/R4DevGateController/GameManager/DevAccess
  sources og deres aktuelle policy skal genlæses fra Roots friske native
  export. Sources er ikke ændringsmål. Root fandt ny concurrent native drift
  og 213 scripts mod den tidligere 212; gammel census eller metadata kan
  derfor ikke installeres som frisk baseline.
- `tools/level6_playground/release_level6.py` har et actual targeted PATCH,
  der fjerner de gamle Level6 PROMPTS entries. Den uændrede public-Level6
  kommentar matcher allerede-applied gate på både før- og kandidat-kilden;
  ingen Source write kaldes for denne targeted edit.
- `tools/level6_build/import/prepare_preview_patches.py` bygger fra et dateret
  20260930 native snapshot; `shared-candidates` og manifest er historiske
  proofinputs. `install_level6_gameplay.luau` kræver at de nye Level6 targets
  ikke eksisterer, og kræver senere præcis gammel shared Source/editor.
  Den actual installer-prefix afviser den eksisterende Level6PreviewAccess
  før HTTP eller Source writes. Daterede sourcepacks/guards rebaseres ikke.
- `tools/tests` bruger DevAccess/API/promptkontrakter; denne snævre ændring
  ændrer ikke de autoritative server predicates eller QA-public APIs.
  Historiske C06 before/candidate blobs og receipts forbliver immutable.

Den eksisterende graphify-graf blev queried som orientering. Den gav primært
historiske DevAccess snapshots og bruges ikke som nutidigt callerbevis.
Aktuelle tekst-/sourcekontroller og native Root exports bestemmer closure.

## Konkrete porte og begrænsninger

`proposal-v1/proposal.json` registrerer 24 O0/O1 compiles og fulde actual
client-source kontrakter: 12 cases og 455 assertions/version, 910 paired
assertions og yderligere 910 reentry assertions. Ordinary/special/developer/
special-developer/negativ Studio user, missing module, require-error,
IsAllowed-error, truthy string/number/table samt controlled enumeration-error
dækkes. Initiale enabled/disabled L4, public L5/L6, nonprompt namesake,
uvedkommende prompts, re-enable, distinct late prompts, detach/reparent og
partial initializer failure testes. To aktive semantic mutants afvises:
public-Level6 hiding og accept af truthy i stedet for boolean true.

Offline fixture modellerer engineevents; det er ikke native eventbevis. Den
staged native runner bruger actual test-ejede Folder/ProximityPrompt
instances og rigtige Enabled/DescendantAdded signals. Kun Players,
DevAccess/require/service-resultater og den test-ejede descendant-delivery
er kontrollerede boundaries. Tre bounded task.wait flushes følger hver
relevant property-/parentændring. Objekter parentes aldrig til game eller
den aktuelle workspace; actual gameplay og singleton-moduler køres ikke.
Der er strukturelt 399 wait-pulses/runner, 1.596 for de fire paired/reentry
runs og cirka 300 yderligere for semantic-negative paths. Ved 60 Hz svarer
det til cirka 32 sekunder plus staging/census guards. Det er en planlagt
scenariobudgetberegning, ingen målt native wall time eller performancegevinst.

Hver runner bygger nye objekter. Connections og kendte test-ejede instanser
ryddes på både success/failure; cleanup afviser foreign descendants eller
ændret identity. Fixture cleanup er ikke en ny produktions-cleanup-API eller
en påstand om LocalScript respawn/multiplayer/streaming cleanup. Reentry
betyder genkørsel af samme module runner med nye test-ejede objekter.

`authoring-gates-v1.json` registrerer 12 checks på actual release PATCH og
old installer-prefix mod kontrollerede boundary tables. Det certifierer de
afgrænsede preflights, ikke komplette import/release-workflows.
`ownership-gates-v1.json` registrerer 8 cases/20 checks på actual reused
late lease claim/release/guard-kode samt to compiles.

Native template genbruger S16's fresh `Instance.new("ModuleScript")`, exact
empty Source/editor, original Source/editor/properties/attributes/tags guards,
late no-yield lease claim, foreign ownership protection og efterfølgende
all-script census. Count og target/dependency identity kommer først fra en
frisk Root binding; gammel 212-count bruges aldrig som autoritet.

Root kan efter native→repo reconciliation binde før-/installeret koden uden
Studio-kald:

```powershell
python -B artifacts/cleanup-20261010/clients-next-v1/prepare_preview_probe.py --bind-native <fresh-native-rows.json> --destination artifacts/cleanup-20261010/clients-next-v1/native-binding-v1
```

Bindingen kræver komplet script-census match med dagens manifest, current
LF Sources og target/DevAccess class/properties/attributes/tags fra samme
metadatafile. Actual Root native-before genkontrollerer alt før staging.
Ved count, Source/editor, identity, metadata, mode, lease eller kontraktfejl
forbliver kandidaten afventende. Efter kun den femlinjede native CAS kræves
samme installerede efterport, konsistent scoped repo/manifest export, diff
og consolekontrol. Der publiceres ikke. Ingen gameplay, inputhardware,
multiplayer, streaming, reserved teleport, faktisk FPS/CPU/memory eller
fuld native asset restore certificeres af denne kandidat.

Risiko er lav for den dokumenterede no-op branch; gevinst er 215 færre
kildefilbytes og fjernelse af en vildledende special-preview kommentar.
Ingen FPS-, memory- eller CPUgevinst hævdes.
