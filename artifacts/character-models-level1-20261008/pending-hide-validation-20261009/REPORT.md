Pending-hide-kandidatens GameManager og Visuals er kopieret fra final-candidate til artefaktmappen. Ingen production-source ændret af denne delopgave.

Offlinekontrol efter rootens installation:

- Collision: 49 server + 61 client = 110 checks passer.
- Marker/loading: 40 checks passer; 5/5 mutationer fanges.
- Tint/helper/cache: 15 checks passer.
- Partial replication/pending: 26 checks passer, inklusive øjeblikkelig hiding af late nested seam, overgang uden native-flash, bevarede originalværdier, femsekunders fallback uden hide/restore-oscillation, senere calibration recovery og oprydning ved fejl/udskiftning/leave.
- Isoleret feedback: 104 checks passer.
- Faktisk delt feedback: 104 checks passer.
- Faktisk delt round-loading-host: 98 checks passer.
- Alle tre pending-kandidater kompilerer Luau `--null -O0`.

295 fokuserede Luau-checks passer. Før-kandidaten med den gamle driver fejler præcist pending check 1, `partial rig waits pending`, med exit-kode 1; den nye driver passer de samme 26 checks. Baselinebeviset og alle logs er bevaret.

Alle tre kandidatfiler matcher de installerede mirrors både før og efter kørslen. Driverens hash er rootens bekræftede `f5d078e43ea5054252c621c86450867782f5fd504a1bb07c2e0205cfca89df84`; Visuals forbliver `f279e4816d991f37b336c381a25feccc0b6dfc829d683a9a97841f70d615e156`.

Eneste delte fil ændret er `tools/tests/test_level2_newmap_feedback.py`. Fire minimale fixture-hunks tilføjer pendingStates, DescendantAdded og faktisk pending-helper/timeout-ekstraktion. Ingen assertions er ændret eller svækket. Ved tilbagerulning af præcist disse fixture-hunks i hukommelsen fås den tidligere verificerede hash `7858a992c974b644534f70752a74abf5395e155eefce99e6577f059d7c47315c`, så alle øvrige/fremmede testændringer er dokumenteret bevaret.

`shared-test-pending-fixture.diff` viser den nøjagtige nye testdiff. `validation.json` indeholder kommandoer, exit-koder, checks, mutationer, logstier og hashbevis.

Ingen Studio-adgang; ingen ændring af lås/kø eller manifest; ingen commit/push. Rootens rigtige Play-QA vurderer engine-replikering og brugerens synlige resultat.
