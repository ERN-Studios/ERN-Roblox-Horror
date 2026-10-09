# CORE-037: test-suite og shared attempt-counter

Status: **afventer test; ikke implementeret**. Alle Studio/runtime/cache/claims
er urørt af denne probe. `probe_core037.py` arbejder alene med actual sources
inden for offline engine-grænser og bevarer både rapporter og før-kilde.

Closure: GameManager og Suite kræver samme `Round Completion Routing` module-
table i samme servercache. `NewAttemptId` lukker over private `lastAttemptId`.
Suite.RunAll kalder `ResetAttemptIds` ved :2617; reset-hook ved Routing :774
sætter dette shared upvalue til nul. Et `table.clone(Routing)` ville **ikke**
isolere den private counter. Ingen aktuelle asserts kræver first-ID=1; de
assert'er correlation, samme packet og unikke/forskellige nye IDs.

Offline-forslag: fjern alene RunAll's reset-call, bevar Routing API og
GameManager/runtimekode uændret. Det er en mulig bounded løsning mod rewind,
ikke fuld test-cache-isolering: suiten allokerer stadig friske monotonic IDs.
Nuværende reset skal ikke testes på den autoritative shared runtimecache.

Offline-kildeprøven kører hele actual Routing + hele actual Suite + den
aktuelle GameManager-probeinitializer på *fake engine objects*. Ved 5.000
allerede allokerede IDs og to RunAll-runs: før-forslaget genbruger alle **128**
suite-IDs og næste ID er65; uden reset er genbrug0 og næste ID5129. Begge
rapporter er byte-identiske med **399 checks / 5 eksisterende failures**:

- fire Host source-shape failures: `sendWipedPartyHome` body settlement og result-honor, Studio-next-level release-call, partydown announcement/clear shape;
- Admission udfører60 checks men deklarerer59.

Disse er konstaterede fixture/source-shape-afvigelser, ikke bevis for fire
runtime-regressioner. Før/efter bevarer de fem failures synligt; de er ikke
fortiet eller ændret til PASS. Fire whole-source O0/O1 compile-porte består.
Fake `Host()` output er ikke en rigtig levende GameManager-/cache-/teleport-
godkendelse, selv om den aktuelle probe-body og Source-teksten læses i prøven.

Nødvendig native port: stages **nye Instance.new ModuleScripts** med exact
Source/editor/CAS-guards, isoleret Routing-upvalue/cache; aldrig LuaSourceContainer
Clone/SES på shared original. Before/after real native TeleportOptions og hele
Suite under samme fixture skal bevare check counts/branch reports/correlation,
og nødvendige Host-integration checks skal verificeres mod et faktisk kørende
host/read-only probe. Fresh native source-shape-checks skal afklare de fem
baseline-afvigelser først. Parallel synthetic production claims/counter holdes
uden for suite-isolation; suite-reset/genentry/duplicate/stale failure callback
må ikke rewinde/forveksle dem. Ingen real reserved-server teleport påstås; den
transportadfærd kræver Roblox-clienttest, hvis runtime-routing senere ændres.
