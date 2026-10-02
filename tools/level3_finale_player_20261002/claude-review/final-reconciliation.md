# Level 3 finale/player review reconciliation — 2026-10-02

## Scope and conclusion

Independent local source audit found no remaining material source blocker in the reviewed finale/player changes. This is source and mocked-check evidence, not native gameplay, multiplayer, device composition, physics, publication, or performance approval. Root owns fresh Studio Source/editor comparison, scoped installation, native checks, export, commit and publication. This reviewer made no Studio, runtime source or Git writes.

The original audit is `spawn-path-audit.md`. Both actual external reviews are complete; their raw responses and receipts remain unchanged. The external final response is explicitly excerpt-only and reports no provable contract violation, with eight conditional/hardening observations reconciled below.

## Actual external review receipts

Both executions used the existing `claude_review_long.py` runner, requested `opus` at `max`, reported `claude-opus-5-5`, exposed no tools, and used strict empty MCP configuration. Both exited 0, confirmed the owned child exited, and did not time out under the 900-second bound.

| Review | Elapsed seconds | Receipt | Prompt SHA256 |
|---|---:|---|---|
| Baseline | 525.370 | `baseline/receipt.json` | `ee0b1a372fd1e0d7bbb3c246a9171677a9ad61e29c8d4da320d5ce6655d15846` |
| Frozen final v2 | 398.846 | `final-delta/receipt.json` | `c1fdcffff22b29596dbc66e1546382319f2cb22d6bf6f7d2824c93b2a40affe6` |

`baseline-summary.md` preserves the concise baseline result. `final-delta/response.md` contains the 890-word final review. Full prompt/input manifests record the exact excerpt ranges. External review coverage does not extend to subsequent v3/v4 changes.

## Frozen source coverage

| Candidate | SHA256 | Coverage |
|---|---|---|
| Objective v2 | `4271bc4890412385b496aebd626e33336e913fbf90bf9646d378ae62a31d8e38` | Actual Claude final excerpts plus independent surrounding-source checks |
| AI v2 | `c78189234adcd884ef21371d5f4dfe0ebf7d54efbfc45c290f37a0e3ffeae490` | Actual Claude final excerpts plus independent spawn/navigation audit |
| Reader v2 | `b452be2e27d398c282ce8c2d26f3add7e78074a71a5d9799f086591a93c1fb9e` | Actual Claude final excerpts plus independent visibility/mode checks |
| AI v3 | `74e0238d0c20cd381e60baf5f8567c0882f84dcb0b29bb52deb51039edc87599` | Independently reviewed tiny v2→v3 overlap delta; not externally reviewed |
| Reader v3 | `153680c2b325030b0a57781c3fcce45a1b4fb2b17fc5eec933efffb74d346d05` | Independently reviewed tiny v2→v3 movement-bounds delta; not externally reviewed |
| Reader v4 | `fb853734db1bde20c2c0e61a69ccb37a01b5780816ad48c875337ecb1a30f2d6` | Independently reviewed tiny v3→v4 screen-coordinate delta; not externally reviewed |

All six hashes were independently recomputed from the candidate bytes.

## Final Claude condition dispositions

1. **Generation:** Adapter lines 677/681 passes the same round generation to Objective and Manager lifecycle; line 290 forwards it to Manager.Start. Objective lines 1287–1290 validates manifest/world generation and stores it at 1431. AI v3 lines 3626–3627 validates the same world generation. Stop does not create a new generation domain. No mismatch found.
2. **Deferral:** A nil result can mean no living records, missing hall, an uncrossed/rootless living life, or endpoint geometry obstruction. Adapter lines 295–301 retries every .35 seconds while its lifecycle token and hunt authority remain valid. There is no alternate spawn. Distinct reason telemetry is optional hardening; the existing Start warning is generic. A thrown Start error is a separate native asset-validation concern and does not enter this nil-result retry.
3. **Death latch:** Objective `dropDeadCharacter`, lines 928–955, clears the crossing table and character stamp before dropping inventory and is connected to Humanoid.Died. Replacement character identity also invalidates crossing. Same-character death/re-cross is covered by owner mocks. An exotic instantaneous in-place revive before deferred death observation is not established by these checks.
4. **Random declaration:** The finale return stores `Random = random` (AI v3 line 3456) for existing session behavior. It does not randomize the fixed spawn position; the endpoint remains exact.
5. **Flag order:** The only supplied local hunt-start listener is Adapter line 304 on the workspace hunt attribute, published after finale flags. No State hunt listener was found in ServerScriptService, ReplicatedStorage or StarterPlayer. Moving State publication is optional hardening. Cleanup lines 530–534 disconnects Manager lifecycle and stops Manager before Music/Objective clears flags.
6. **Missing target/root:** The caller guards missing root and clears player guide mode; a missing device position shows `CD PLAYER // LOCATING`. Geometry hides the separate pin immediately when its root becomes invalid. The in-panel readout may remain until the next existing update tick after an abrupt root loss; native lifecycle sequencing remains unverified.
7. **Toast:** Toast synchronously calls `UIDevice.SetInteractive(panel, false)` and hides the pin. UIDevice line 1841 immediately sets Visible. The per-frame panel visibility guard therefore prevents reappearance during the toast.
8. **Counts:** The caller clamps goal to at least one. Objective ModuleCount/ModuleProgress tracks inserted count, separately from collected-ever count. Completed insertion/unlock intentionally overrides stale replicated WORLD states; a dropped CD with incomplete insertion returns SCAN.

## Independent post-Claude deltas

AI v3 changes only the optional overlap filter and its finale call. It excludes all current Player.Character models, matching existing navigation exclusions, so dead/escaped/non-round current avatars cannot veto the endpoint. Ordinary spawn filtering is unchanged. Authored collidable geometry still blocks and retries the same endpoint. Detached corpse clones are not current avatars and remain geometry unless separately excluded; no such production clone was established by this audit.

Reader v3 caches the minimum Controls/Thumbstick/Jump top minus 54 pixels (46-pixel card plus 8-pixel gutter). A scene pin without a clear rectangle is hidden while the exact compass/distance remains. It removes the old short-screen fallback over the reader and adds no per-frame zone scan. Native touch composition is still a separate check.

Reader v4 preserves v3 and changes only projection to `WorldToScreenPoint` plus its explanatory comment. Root reported actual desktop evidence: viewport point (624.26,300.59), screen point (624.26,242.59), a 58-pixel topbar and GUI origin (0,0), so the v2 pin was 58 pixels too low. UIDevice's actual layout/AbsolutePosition space and LocalOffset lines 1704–1716 confirm screen coordinates followed by one GUI-origin subtraction. The v4 source follows that contract, retains depth/bearing/edge clamping, and adds no manual inset subtraction. Owner tests exercise the exact geometry against this observed point and a nonzero GUI origin. This corrects a native-discovered issue; post-install native pin alignment and real mobile composition remain root checks.

## Verification and remaining native matrix

Owner receipts report full AI/Objective compilation and 35 extracted-source scenarios/94 assertions (`artifacts/level3-finale-player-20261002/finale-mock-v3-receipt.json`), and full Reader v4 compilation plus 66 focused checks (`reader/verification-receipt.v4.json`; v3 had 63). The external reviewer did not run them. They do not prove real overlap, navigation, transport, replication, multiplayer or performance.

Native checks should cover last living participant at 49.9%/50%/50.1%; missing root; dead/escaped/leaver/spectator exclusion; protected final runner without damage; near/coincident endpoint players; authored blockage with no relocation; pause/unpause preserving the same rig; cleanup and second round; WORLD/DROPPED/CARRIED/INSERTED transitions; vertical/behind-camera bearing; toast/modal/hiding/spectate/teardown; and portrait/landscape movement-zone clearance. Missing character/humanoid cannot establish known living under the existing lifecycle, whereas a known living humanoid without root blocks admission. No CPU/memory or live multiplayer claim is made.
