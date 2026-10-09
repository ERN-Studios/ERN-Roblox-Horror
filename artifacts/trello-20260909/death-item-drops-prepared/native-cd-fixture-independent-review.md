# Independent CD native sequences — 9/10 prepared fixture

Reviewed final files:

- `native-cd-before-pickup.server.luau`: `7ecca70036993b299ec2d53878f81732000d346342b480396680b334b8a2ecec`, independently compiled to 10 KB.
- `native-cd-b-pickup.server.luau`: `8b1c3bc53cf26c46f630c93fefb9290816d29bd59e6cbd1cecdd7b852124cd45`, independently compiled to 9 KB.

No remaining fixture blocker was found after the narrow readiness correction. Root caught the earlier server-only read of client-local RoundEntryControlsReady before execution; my initial review had missed that false-negative guard. The corrected live check uses the actual server RoundLoadingState='ready', a real unanchored HumanoidRootPart and living participant state. I verified that GameManager writes this workspace state and NoiseReporter writes the client-local controls attribute. The actual client input continues to check its own RoundEntryControlsReady. Independently undoing just this correction recovers both original reviewed file hashes byte-for-byte, preserving CRLF; no other behavior changed.

The first phase requires two genuine local clients, a fresh actual L3 world and zero counters. It selects a real WORLD source, verifies integer index/mask, and uses the reviewed channel's actual E input. Client/server count and mask, source CARRIED state and A owner -1 must agree before controlled death. After the actual same-character death, A's count/mask must clear, original collected count remains one, inserted remains zero and exactly one same-index drop must exist. The exact source/drop/helper/channel-run/world/token/character references are retained before staging B for visual inspection.

The second phase rejects stale context before using B's real prompt input. It requires B's matching mask/count, same source owner -2 and exact dropped model destruction, checks for any remaining dropped-CD models, and preserves collected1/inserted0. The state, owner and mask contracts were matched against the actual Objective Controller source. Full read-only snapshots and the retained channel are emitted in bounded UTF-8-safe chunks rather than falsely treating truncated single-line logs as complete.

These two small scripts perform controlled placement and A Health=0 through the reviewed helper; they never grant inventory, call DebugDrop, trigger item callbacks or write objective state. The score is for the diagnostic scripts, not native success. This is a single-disc identity case; five simultaneous corner drops, natural death, traversal and normal cleanup must not be inferred from it. Native execution and final feature acceptance remain root-owned.
