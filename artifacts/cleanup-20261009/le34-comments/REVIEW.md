# LE-34 / B07: to gennemførte kommentarrettelser

Status: **gennemført i repo/Studio**, lokal commit **PENDING root**. Root har
installeret begge præcise kommentarlinjer med native Source/editor/CAS, bevaret
properties/attributes og opdateret scoped manifest. Verifieren foretager ingen
produktions-/manifest-/Studio-write. Oprindeligt proposal og før/kandidatkopier
er bevaret byte-identiske; øvrige LE-34-locals og sourcepacks er ikke rørt.

## Gennemførte planposter

| Fund / præcis lokation | Mindste ændring og aktuelt bevis | Dependencies/callers/remotes/attributes/tools | Risiko/gevinst | Før/efter-port / status |
|---|---|---|---|---|
| LE-34a: `ServerScriptService/Level 3 Systems/Level 3 Layout Generator.ModuleScript.lua:26`; native `ServerScriptService.Level 3 Systems.Level 3 Layout Generator`, ModuleScript | Kommentarens `2x4 room grid` → `2x5 room grid`. Aktive constants19–21 er ROOMS_PER_DISTRICT=10, GRID_ROWS=2, GRID_COLUMNS=5; assert30–34 kontrollerer10=2×5. Ingen constant/Generate/Validate ændres. | Round Adapter require16, Generate634, Validate312/637 og Version434; native Level3 Test Suite require6. Top-level Configuration, Level6 Kit Metadata og MasterConfiguration-requires, public API og alle attributes bevares. Authoring-tests: `test_level3_square_layout.py:226`, `test_level3_first_cd.py:287`. Ingen tool bruger den gamle kommentar som Python extraction-marker; historiske L3/L6 sourcekopier er beholdt. | Meget lav; retvisende authoringdokumentation. 0 byte-reduktion, ingen runtime/performancegevinst. | O0/O1 raw bytecode/instructions/constants/upvalues/proto metadata identiske før/efter. Root fresh native Source/editor/class/properties/attrs-CAS, exact landing og manifest PASS. Ny installeret compilerport PASS med bevarede originale beviser. **gennemført; lokal commit PENDING**. |
| LE-34b: `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua:1548`; native `ServerScriptService.Level 1 Systems.PuzzleManager`, Script | Kommentarens `exact one-box-per-player contract` → `exact ceil(n / 2) box count`. startPuzzle1341–1350 fryser InRound-party, clamp1..6 og boxCount=ceil(n/2); box-placement/fallback/assert1549–1565 følger boxCount. Ingen spawn/count/gameplaykode ændres. | Aktiv enabled Script/Legacy. startPuzzle via RoundActive-signal og initial flag; teardown via PostWinIntermissionActive/GenerateWorld; SelectedLevel-guard. PuzzleStatus/RoundStatus, TeamObjectives, NoiseRegistry, MasterConfiguration, InRound/circuit/puzzle/exit attributes og alle initializer-sideeffects bevares. `test_level1_team_prompts.py:20` læser script og bruger announceTeam-sektionsgrænser, ikke denne kommentar; ingen Python/Luau-toolreferencer til den gamle konkrete linje. | Meget lav; retvisende forklaring af eksisterende party-count. −6 bytes, ingen runtime/performancegevinst. | Samme før/efter compilerport samt root native Source/editor/class/Enabled/RunContext/properties/attrs-CAS, exact landing og manifest PASS. Ny installeret compilerport PASS med bevarede originale beviser. **gennemført; lokal commit PENDING**. |

## Konkret proposal og verifierbevis

`candidate-manifest.json` indeholder præcise før-/efterlinjer, unified diffs,
baseline og candidate SHA256, class/properties/attributes samt kandidatstier.
De to `.before.luau` og `.candidate.luau`-par er bytekopier af den aktuelle
mirror med kun den dokumenterede ene kommentarlinje ændret pr. fil.

- LayoutGenerator baseline LF SHA256:
  `0369a1f11fa20c90bee2fda67191bf58a6a543f1ce66ee554a4fd3c0dfcab594`;
  candidate `cf309386c0cd5aef85c3f8208ea28d51f2c8206d27019d86e4d58902f2cc325f`.
- PuzzleManager baseline LF SHA256:
  `605fb1c22a2d6a3f3128c4404f671c868570bdc02789239ce908ce66e3e3a645`;
  candidate `6cde618088f7aff94385e7348c830f07b597b011bb64640def7395b7a53b2ad7`.

Luau0.737 på begge faktiske fulde kilder, `-g0 -O0` og `-g0 -O1`:
**raw binary-identitet PASS**, text dumps med alle constants identiske og
samme proto-metadata: LayoutGenerator29 funktioner, PuzzleManager103 funktioner.
C08's bytecodeparser er genbrugt; der behøves ingen line-number-normalisering,
fordi kommentarrettelserne bevarer linecount. Alle initializer- og call-opcodes
er byte-identiske. Dette beviser den afgrænsede kommentarændrings compileradfærd;
det er ikke en ny Level1/Level3 gameplay-/multiplayer-/streaming-godkendelse.

Fire uafhængige negative controls (to kilder × to optimization levels) ændrer
kun en runtimekonstant: GRID_COLUMNS5→4 eller boxCount-divisor2→3. Alle fire
afvises af bytecode/dump-equality-oracle. Mutants og compilerinputs var kun i
OS-temp; canonical kilder og manifest blev hash-/bytegenkontrolleret uændrede
efter hele prøven. Ingen native calls blev kørt.

Den første proposal-port er historisk dokumenteret i `candidate-manifest.json`.
Den installerede efter-port rekonstruerer kun den unikke gamle kommentar i
memory og kræver current mirror/manifest/candidate-hash samt uændret class,
properties og attributes. Den skriver særskilt `installed-compiler-check.json`:
begge current efter-kilder matcher exact proposal; O0/O1 raw bytecode/proto/
constant/upvalue equality PASS; fire semantic negative controls afvises; alle
fem originale proposalbeviser forbliver byte-identiske. Ingen nye native calls.

Reproducer den installerede efter-port:

```powershell
python -X utf8 artifacts/cleanup-20261009/verify_LE34_comments.py --verify-installed --compiler C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe
```

Native receipts: `../B07-LayoutGenerator-native-install.json` og
`../B07-PuzzleManager-native-install.json` med exact før-/efterhashes og
editorMatches=true. `../B06-B07-installed-native-hashes.json` registrerer230
scripts/0 failures. Slutparity og lokal commit afsluttes af root; disse receipts
er ikke en publicering eller en Level1/Level3 gameplaycertificering. En større
edit kræver sin egen nye dependency-closure og testport.
