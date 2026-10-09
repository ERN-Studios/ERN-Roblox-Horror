# Final independent Switch-choice review — 9/10

**No remaining release blocker found for card rLDqjpE4/#65.** The prepared-code review and the actual two-client result-window test now support release of the exact reviewed change, after root's normal stopped-Edit source parity/whole-compile check. Publication itself is not yet claimed here.

The reviewed sources are GameManager `3d1b05993778f7640dcea4b51193cfe2cee0224552e8303bfd3dde991933d7db`, compact RoundUI `a851f6315bad4806698ab40627a9092955b1455a88b6da4f62ad95b9e65eb7f3`, and UIRegression `f2b4699c37ecd54eb98deda4d28fd42b07f3aa3cfb8bb27166432a8a77af3ae4`. The earlier independent review covers 76 server + 32 client + 19 actual CompletionContract checks, three specific negatives and four whole compiles, including the fixed delayed-departure cohort race. No source or gameplay correction was introduced during the native input diagnosis.

## Independently read native evidence

I parsed the frozen `native-switch/pointer-trial-final/messages.jsonl` (SHA-256 `008a655dbf7c80c6b2a7b39e9fac46e44c6f74dd05f9b584309a0811952faa93`) and its collector report: 1,298 complete messages / 3,642 chunks, no rejected messages, parsing issues or observed sequence gaps. These totals include historical runs; the acceptance below is restricted to **serial 7**, client A `7c5df6b7` / UserId −1, client B `79a7a591` / UserId −2, and server `2f91be47`. The extracted metrics are saved in `native-switch/pointer-trial-final/independent-serial7-analysis.json`.

The normal local two-player L1 session entered its actual result UI through a disclosed controlled PuzzleWon fixture, not a puzzle playthrough. A's input used the documented VirtualInput engine path against the measured actual buttons. The separately observed GuiButton Activated events occurred at server-synchronized times **1789048213.269106**, **1789048214.268467**, and **1789048215.267832** for Continue, Back to Lobby, and Continue respectively. This is three actual UI activations, not acceptance inferred from a successful API call.

| Accepted revision | A received at | B received at | Both actual UI rows |
| --- | --- | --- | --- |
| 2 | 1789048213.296830 | 1789048213.317021 | Player1 — CONTINUE |
| 3 | 1789048214.294406 | 1789048214.300519 | Player1 — LOBBY |
| 4 | 1789048215.295438 | 1789048215.316631 | Player1 — CONTINUE |

All packets retain serial 7. Both clients' following UI snapshots show the matching visible row with **TextFits=true**, and both action buttons remain active and fit at the actual 767×274 viewport. B remains deciding throughout. The independently extracted input log in `independent-serial7-input-events.json` confirms the three corresponding accepted server revisions and Completed=true; each move reaches the measured button's screen center with the actual 58-pixel inset.

Both win packets carry the same original deadline **1789048227.637087**. No new win/reset deadline appears during the switches. The server first reports loading at **1789048227.882016**, 0.244929 seconds after that deadline; both client loading events also occur afterward. The temporary Lobby selection does not cause an early return. Closed revision 5 preserves A's final Continue; B's unchanged deciding choice follows the normal automatic default. Both then receive normal L2 entry/release/start events. Later snapshots independently show both characters **100 HP, unanchored, InRound=true**, with each local client's actual UI-ready and controls-ready flags, ending/loading UI hidden. A confirms this by 1789048234.914098, B by 1789048234.799467.

## Scope and retained history

This proves both switch directions, peer display replication, preservation of the deadline, and final arrival using the last accepted Continue selection in two real local Studio clients. It is documented virtual mouse input, not three human physical clicks. Controlled objective completion and queue staging are setup; no complete-level playthrough is claimed. The existing compact/six-row native layout evidence remains applicable because this change preserves that geometry.

The native run ends with Continue for A and the automatic Continue default for B. A final mixed Continue/Lobby cloud split, live Teleport retry, concurrent disconnect timing, and the separate final-Lobby branch were not newly exercised here. Their unchanged transport behavior and explicit offline authority/cohort tests provide the bounded coverage; this successful scenario is not relabeled as those tests. There is no concrete remaining failure requiring another broad test matrix.

The serial-4 virtual send without Activated and serial-5 pre-down cursor-policy refusal remain preserved as failed/partial input-fixture attempts. Calibration and the corrected pointer fixture resolved the input harness issue without editing production. They are not counted as product passes.

Root owns the final exact-source audit, stopping the test session and mouse publication. No Studio, UI, runtime source, Trello or publication action was performed in this review.
