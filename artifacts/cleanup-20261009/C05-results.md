# C05 – private UIRegression definitions

Den isolerede kandidat fjerner13 private, ubrugte definitions fra `ReplicatedStorage/UIRegression.ModuleScript.lua`: `setLongDispatchCue`, `briefingDevices`, `analyticalOverlap`, de fem `BRIEFING_*` datatabeller og de fem `DEV_*` constants. Den retter én stale rollback-kommentar. Netto73 linjer/2.823 bytes fjernes. De aktive `LONG_DISPATCH_CUE`, alle public lanes/aliases, owned setup/reset/restore og N01's glyph/margin/reentry-kontrakter beholdes.

Hele dependency-closure er gennemgået. De tre lokale funktioner har ingen callers; deres bodies køres derfor ikke af initializer. `BRIEFING_LANDSCAPE_ROWS` bruges kun af den fjernede `briefingDevices`, og `DEV_EYEBROW_BASE` kun af den fjernede `DEV_EYEBROW_KEYBOARD`. Andre fjernede navne har kun deres definition. Runtime og tools-søgningen finder ingen eksterne callers. De fjernede top-level initializers består af literals, tabeller, string concatenation og én immutable `Vector2.new(705,338)`. De kræver intet module, bygger ingen Instance og registrerer ingen event/remote/attribute-sideeffect.

Exact source-diff har ni afgrænsede regioner. Alle resterende source-linjer er byte-identiske, bortset fra den ene kommentar. Alle102 navngivne Fit/internal/UIRegression-declarations har uændrede signatures. Der er30 public UIRegression-exports; native probes sammenligner de faktiske keys, types og function arity/variadic flags.

| Port | Faktisk resultat | Evidens |
| --- | --- | --- |
| Authoritative før/full | 0 failures, alle21 scenarios; shared730/0; source/editor og alle lånte flags/lock gendannet | `B06-final-full.json` |
| Authoritative før/TouchTarget | 261/0; source/editor og alle lånte flags/lock gendannet | `B06-final-touch.json` |
| Candidate O0 compile | PASS | `C05-prepared.json` |
| Candidate offline shared | 105 checks PASS, real imported fixtures + production borrow/reset/restore | `C05-prepared.json` |
| Isoleret candidate native/full | 0 failures, alle21 scenarios; shared730/0; entire compact-report identisk med før | `B07-C05-full.json` |
| Isoleret candidate native/TouchTarget | 261/0; entire compact-report identisk med før | `B07-C05-touch.json` |
| Native API og cleanup | Alle30 public keys/type/arity identiske; workspace/player/lock drift[]; originale Source/editor uændrede; nye temporary ModuleScripts destrueret | Begge isolerede receipts |
| Installeret native CAS | Exact419→b57, ModuleScript og editor Source matcher; manifest opdateret | `B08-C05-native-install.json` |
| Frisk installeret native/full | 0 failures, alle21 scenarios; shared730/0; entire compact-report og API identiske med før; Source/editor og attr/lock bevaret | `B08-after-full.json` |
| Frisk installeret native/TouchTarget | 261/0; entire compact-report og API identiske med før; Source/editor og attr/lock bevaret | `B08-after-touch.json` |

Baseline SHA `419a7e3e003ba6d67746716f188f5c3e7359f5e4db4d8e097e3d8fcad0e73dad`; kandidat SHA `b57a2b848f7981d76225c5bb850cdcfb3de12743afadab674ee826d4747ccc64`. Kandidaten er kun afprøvet som en helt ny, tom, unparented ModuleScript; ingen LuaSourceContainer er clonet, og intet originalt script er overskrevet af proberne. Wrapper `run_C05_probe.py` har guards før, inde i empty-source staging og efter selv ved fejl; den bevarer fulde reports uden at miste failure details.

Status: gennemført. Root har installeret kandidaten med fresh Source/editor compare-and-swap og opdateret manifest; frisk Play består begge native efter-porte. Begge efter-reports og alle30 public API-definitioner er byte-identiske med før. Alle workspace/player/lock drift-lister er tomme, originale Source/editor er uændrede under tests, og de afsluttende tests kræver ingen temporary probe. Rollback-original er `.git/mongotv-cleanup-20261009/client-before/N01/UIRegression.C05.before.lua`. Root ejer scoped commit. Receipt-filnavne siger B07 af historiske wrappergrunde; cleanup-batchen er B08. Ingen gameplayfeature er fjernet, ingen performancegevinst er målt eller påstået, og intet er publiceret.
