# Fresh installation package

The owner authorized installation after Edit returned, and explicitly requested **no new backups**. This package contains exact read records and scoped proposals; it does not create a native place backup or modify Studio.

## Fresh baselines

- Connected place: 131311258779917; universe: 10559217407; Edit confirmed.
- L4 Director: `game.ServerScriptService["Level 4 Systems"]["Level 4 Light Director"]`, ModuleScript identity `42773`; Source/editor exact parity.
- Original Source SHA-256: `1F99331F1EB98DA35FA0A5E5F0C7EEEEC4205B377205B77876625E03EB698A9E`.
- Scoped candidate SHA-256: `5952C86FEB05085642A9FD27CCE02332C96DA3F7D3EBB09AB5D1AE46CBAFC861`.
- Fresh selector: 254 L4 lights, 620 ordinary L5 lights and 8 Water FX emitters. All 882 have no existing budget attributes.
- New ModuleScript and LocalScript names remain free at their proposed paths.
- Authored L4/L5/L6 maps remain in ServerStorage under the concurrent LevelWorldStorage workflow.

Read records include exact Instance identities, holder identities, duplicate-safe address steps and old attributes. None of this authorizes replacing a changed live baseline.

## Root-owned installation

1. Recheck the exact Director instance, Source and editor Source. Apply only the three reviewed scoped replacements to that fresh baseline, with the comparison repeated inside the source-write callback. Source before/after files are review aids.
2. Load the already reviewed selector module as a pure closure. Invoke `guarded_attribute_apply.luau` with `(game, decodedBatch, Selector, exactInstalledDirectorSource, "apply")` for batches 01–09. Each invocation verifies the fresh Director Source/editor and all metadata/identity baselines, then writes at most 100 objects without yielding. Attribute postchecks are inside the rollback-protected operation.
3. Install the reviewed budget module/client at the previously verified free paths. Staging/probes must use fresh empty ModuleScripts with empty Source/editor baselines; never clone a LuaSourceContainer. Verify authoritative originals before and after probes.
4. Run native contracts and actual route/state checks before claiming gameplay/performance validation or publishing. Actual routes are in `actual-level-routes.json`. Use accepted level entry and streaming/floor readiness; checkpoint coordinates are references, not blind teleport authorization.

The helper requires the freshly captured Director identity `42773`. If the place is reloaded or the instance is replaced, capture a new baseline and reconcile instead of weakening the identity guard.

## Rollback

`rollback-record.json` references the old values and batch identities. Invoke the same metadata helper with mode `"rollback"` while the exact patched Director Source remains verified, then reverse the scoped Director replacements against a fresh current baseline. Preserve/archive only the new task-owned module/client through the root's workflow. The helper never deletes objects.

The runtime rollback switch remains `workspace.SceneEffectBudgetDisabled = true`: it releases suppression using the current desired state, including darkness.

## Verification

Luau 0.741 compiles the new installation helper and scoped Director candidate. **10 offline guard assertions pass**, including authored false, nil restoration, pre-existing influence preservation, moved mounts/editor conflicts and partial-write error cleanup. The existing budget suite retains its 36 passing offline assertions.

The route policy counts are computed from the full authored inventory. For example, L5 checkpoint 0 keeps 80–90 of the 620 ordinary lights under entry/exit hysteresis, and selected later checkpoints keep 82–168. L4 selected zone viewpoints keep 89–169 of 254. These are structural policy counts, not measured client counts, render savings or FPS gains. Streaming and Roblox's engine culling also affect actual work.

Native probe, actual-level checks, device performance and publication are root-owned and have not been executed by this subtask. Dirty RoundUI, Poolrooms Ambience and concurrent cleanup files remain untouched.
