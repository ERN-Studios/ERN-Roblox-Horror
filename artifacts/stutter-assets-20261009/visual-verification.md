The three visual changes were reconciled against fresh authoritative Studio Source/editor baselines and installed with guarded writes. The exact paths, classes, before/after SHA-256 values and scoped mirror exports are recorded in `shop-scan-native-install.json`, `dj-cache-native-install.json` and `level1-room-streaming-native-install.json`.

The first native write guard rejected the shop attempt before any write. A refreshed capture showed all three exported Source files were byte-for-byte equal to their first captures; regenerated candidate bytes also stayed equal. Subsequent native Source/editor verification is recorded by the successful install receipts. Equality of exported Source alone was not treated as evidence of editor parity.

The shop keeps its existing full census, but incomplete replication retries run at most twice a second. The census is skipped while this player is in a round or the lobby server has an active round; any already animated boxes restore immediately. This retains existing late-arrival recovery with up to 0.5 seconds additional discovery latency. It does not change purchases, cards, box poses, accessibility preferences or the server.

The DJ keeps one decoded catalogue per raw attribute value, including invalid or absent values. Its lighting scheduler restores and returns before catalogue access in reserved rounds or when the player is in a round. A changed catalogue still invalidates immediately when next read.

The renderer changes only the newly cloned 24-stud room models to `Atomic`. `MazeGenerator` is the sole `state:Rooms` caller (`ServerScriptService/Level 1 Systems/MazeGenerator.Script.lua:1932`). Its call is unchanged. `PuzzleManager` calls the renderer's other functions for fuse skins and exit apertures; those paths are unchanged. The whole maze, source kit, colliders, fixtures, assets and generation rules retain their properties. Atomic instance arrival does not by itself prove that its mesh/texture bytes have loaded.

Offline verification executes production fragments from the three canonical repository mirrors with primitives adapted from `tools/tests/test_lobby_shop_display.py`. It covers partial-stream scan limits, late boxes, motion formulas, both round gates, accessibility restoration, removal/reappearance, catalogue invalidation, invalid JSON containment, inactive lighting, lamp restoration and per-room scope. All three complete mirrored scripts compile and all 153 checks pass. Receipt: `visual-offline-receipt.json`.

Run the default canonical-mirror check with:

```powershell
python artifacts/stutter-assets-20261009/test_visual_candidates.py
```

The runner accepts `--luau` and `--compiler`, or `LUAU_BIN` and `LUAU_COMPILE_BIN`, when the binaries are outside PATH. Its optional existing local binary fallback requires no download. The default check does not read generated candidates or captured originals. Optional local `--candidate` and `--baseline` checks require the corresponding uncommitted manifest/captures; the captured originals previously failed all three regression assertions.

Native staging and verification:

1. Resolve the exact three authoritative instances and compare both Source and ScriptEditorService editor source to their capture, without writing them. Abort/reconcile any difference. Record original Source/editor during staging and after both success and failure.
2. Create a fresh `Instance.new("ModuleScript")` for each executable contract or compile probe. Verify Source and editor source are both exactly empty before ScriptEditorService staging. Never clone a LuaSourceContainer. Stage only the freshly verified source under test into the fresh object and verify that source afterward.
3. For the renderer, run `probe_renderer_native.luau`'s returned function with that fresh candidate module in Edit or Server. It creates four test-owned rooms from the actual current Level 1 kit, checks each room is Atomic and has a visible roof/floor, checks the whole probe maze remains Default, then cleans up and restores borrowed markers even on failure. This probe must not be represented as multiplayer/streaming/performance verification.
4. Destroy every staged probe module in an always-run cleanup, then recheck original Source/editor and the native object scope. A compilation check alone does not exercise scheduling or streaming.
5. In bounded Client Play, measure frame-time spikes during lobby arrival and Level 1 traversal, inspect original/new shop scan counts under partial replication, and record nearby room/roof arrival and real content fetch failures. Include a return to lobby and another round. Physical low-memory devices and published multiplayer remain a separate check unless actually run.

The offline receipt proves synthetic contracts and compilation. Native compilation and tiny actual-kit generation are recorded separately in `native-candidate-probes.json`; they do not prove gameplay, multiplayer, actual-asset download or device performance.
