# N01 – native UI-baseline

Den native baseline afdækkede en faktisk Chevron-fejl: Roblox slår TextScaled fra, når TextWrapped sættes false. Den tidligere offline engine modellerede ikke koblingen. `paintCompass` beholder nu true/true på den ene glyph, så native font fallback passer i den uændrede importerede slot. Ingen gameplayfeature eller glyph-slot er fjernet eller flyttet.

QA måler den eksisterende shared-HUD reservation: ekstra 16px på touch/24px på PC inde i UIDevice's safe slot. Generic anchor har default 0. Independent safe containment, movement collisions, native-frame parity, hit bounds og text bounds beholdes. Begge shared callers, `Fit.bodyRoundHudMatrix` og `Fit.bodyTouchTargetMatrix`, sender samme margin. Den første candidate overså den anden caller; den præcise rettelse blev installeret og testes med den faktiske consumer-blok.

En separat TouchTarget-port viste en eksisterende fixture-lifecyclefejl: første devices afsluttende `PartyDownCard`-scenarie efterlod den fixture-ejede modal aktiv, så de næste otte device-rækker ikke kunne måle deres objective. `Fit.stageRoundObjective` nulstiller ikke disse flags. Per-device setup bruger nu den samme eksisterende `resetScenario(true)` før staging som `shared-objective`-scenariet. Den nulstiller fixture-ejede modal/result/party-down-flags, bevarer device overrides og in-round context og gendannes af den eksisterende borrow-port. Ingen assertions er fjernet eller svækket.

| Port | Faktisk resultat | Evidens |
| --- | --- | --- |
| Native baseline | 935 checks, 21 scenarios, 51 failures; shared matrix 730/50 | `baseline-native-ui.json` |
| Isoleret native TextLabel | Original setterrækkefølge false/false; reverse og scaled-only true/true, straks og efter wait | `N01-textlabel-property-probe.json` |
| Original runtime + korrigeret offline fixture | Reproducerer wide/tall fallback glyph-fejl | `N01-candidate.json` |
| Original QA + shared contract fixture | Reproducerer exact safe-slot-fejl | `N01-candidate.json` |
| Offline efter første N01 | shared 387 + stamina74; QA101; exit92; controller91/touch86/stamina74/POV63; basicHud185; O0 compile og diff-check pass | `N01-candidate.json` |
| Første native efter N01 | 935 checks/2 scenariofailures; shared matrix730/0, lock clear, Health100 | `B06-native-ui-after.json` |
| Isoleret parret QA før/current | Begge 0 failures; exact samme contracts, rectangles og 1413x577/inset58 context; residue[]; originale Source/editor bevaret og temporary probes destrueret | `B06-pair-before.json`, `B06-pair-current.json` |
| TouchTarget consumer før/efter | Manglende-margin caller fejler real consumer fixture; en-line rettelse passer QA103/O0 | `N01-touch-caller-candidate.json`, `B06-TouchTarget-native-install.json` |
| Frisk full native efter marginrettelse | 0 failures, alle21 scenarios; shared730/0, queue719/0, named lanes935/0; præcis context bevaret og lock clear | `B06-fresh-native-ui.json` |
| Native separat TouchTarget før fixture-reset | 261/8; kun otte manglende objectives efter første device; alle andre assertions bevaret | `B06-native-touch-target.json` |
| Isoleret før/reset TouchTarget | Før261/9 (én gammel anchor + otte missing), reset261/0; originale sources/editor uændrede, probes destrueret, attrs gendannet og lock clear | `B06-touch-before.json`, `B06-touch-reset.json` |
| Offline fixture reentry før/reset | Før reproducerer næste devices manglende objective; reset105 checks passer og bevarer ForceTouch/InRound | `N01-touch-lifecycle-candidate.json` |
| Native reset-installation | Exact UIRegression SHA419a7e3e… compare-and-swap | `B06-TouchReset-native-install.json` |
| Afsluttende frisk native full | 0 failures, alle21 scenarios; shared730/0; actual authoritative module, ingen probe; alle workspace/player/lock drift-lister tomme, Source/editor uændrede | `B06-final-full.json` |
| Afsluttende separat native TouchTarget | 261/0; actual authoritative module, ingen probe; alle workspace/player/lock drift-lister tomme, Source/editor uændrede | `B06-final-touch.json` |

Parret QA før/current bruger den samme aktuelle gameplay owner. Det beviser ingen forskel i de to scenariers QA-kode, men er ikke et isoleret runtime-før/efter place-test. Hiding målte det shared objective skjult og glyph bounds 9x12 inde i 16x12.727; result-scenariet målte korrekt full-screen kontrakt. Begge målte alle failure lists tomme og gendannede flags. Den friske full-port genafprøvede siden alle21 scenarier med0 fejl.

De første to efter-failures er bevaret som evidence: `hiding-plus-reader` og `round-win-fullscreen` var grønne i den præcise parrede test og efterfølgende friske fulde suite. Et mellemliggende fullcompact-run mistede sit resultat, fordi root-wrapperen kaldte den ikke-eksisterende `UI.LockState`; fejlen ligger i wrapperen og giver ingen konklusion om det run. `B06-full-ui-recheck.json` bevarer fejlsvaret. Den nye wrapper læser de eksisterende lock-attributter og bevarer hele compact-rapporten. Der er ikke ændret assertions for at skjule failures.

N01 er gennemført: de afsluttende friske native full- og separate TouchTarget-porte passer på den autoritative installerede kilde, og offline shared fixture passer105. Alle originals og nødvendige hashes er bevaret under `.git/mongotv-cleanup-20261009/client-before/N01`; root ejer fresh native CAS, manifest og scoped commit. C05 private helper-oprydning står fortsat urørt i produktionen og afventer kandidatens isolerede porte. Ingen FPS-, memory- eller andre performancegevinster er målt eller påstået, og intet er publiceret.
