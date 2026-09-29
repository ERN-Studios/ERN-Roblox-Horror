# Level 5 native QA startup failure — read-only analysis

No Studio mutations or further audio generation were performed for this investigation.

## Finding

The second failure is an entry-readiness timeout, not evidence of a failed Level 5 map build. At 2026-09-27 04:36:20 UTC, the stack reaches `Round Loading Runtime.AwaitReady` from `GameManager:2129`. That line is reached only after `ensureWorld`, character load, placement, and `attempt:Prepare` succeed. The subsequent `GameManager:1991` / `:1625` trace is the cleanup invoked by timeout recovery. Absence of the world after that recovery is not evidence that the world never existed.

`recoverFailedEntry` sets `LoadStage = WORLD_ERROR` for all entry failures, including `LOADING_TIMEOUT`. The displayed generic stage therefore overstates what is known. No fresh `GameManager: Level 5 generation failed` diagnostic occurs in these two attempts. Earlier generation errors in the long-lived log belong to previous work and must not be reused as evidence for this run.

## Evidence favoring environmental scheduling pressure

- The first run also times out Roblox CoreGui capture modules, Roblox StarterScript, and the Assistant command, not just game code.
- The second run produces a Studio MainThreadHangs warning at 04:36:29 UTC.
- A read-only host snapshot during this investigation reports 17,882.75 MB swap used out of 18,432 MB allocated; Studio RSS was approximately 86 MB at that snapshot. This supports heavy paging but is not a quantitative benchmark or proof of the precise readiness gate that failed.
- `Run`, `AwaitReady`, and client readiness polling yield on every loop; no tight infinite loop was found in those control paths.
- The server requires readiness acknowledgements newer than two seconds, while the client sends them at most twice per second. Long scheduling stalls can prevent a valid acknowledgement from committing before the shared 60-second entry deadline.

## Concrete code fragility, not proven as this incident's cause

`Round Entry Client` lines 112–116 permanently latches `AssetsReady = false` for a token when any avatar mesh/decal/texture preload fails. Repeated `entryprepare` for the same token returns after updating its deadline (lines 77–81), so it cannot retry that preload. A transient or unavailable cosmetic avatar asset can therefore block an otherwise healthy entry for the entire deadline.

The log contains wrap-deformer mesh-fetch warnings, but does not expose a failed asset id or this request's AssetsReady state. Do not claim that this fragility caused the observed Level 5 failure without client telemetry. Avoid changing shared loading behavior as a speculative fix during this Level 5 audio task.

## Safe targeted recovery

1. Save the working source/backup first. End only the agent-owned play session. Keep the normal ScriptTimeoutLength (10) and production readiness barrier intact.
2. Reduce agent-owned auxiliary load and allow memory pressure to settle. A fresh Studio process may be necessary after saving if the existing process keeps hanging; preserve any unrelated developer work. Do not repeatedly retry the same pressured process or increase production timeouts to disguise it.
3. Run exactly one ordinary developer Level 5 start. While its cover is still visible, collect a CLIENT-context readiness snapshot using the companion Lua snippet. Server reads cannot see the client-local UI/control/readiness attributes reliably.
4. Distinguish UI/control initialization, missing streamed collidable arrival ground, missing/failed avatar assets, and successful local acknowledgement. Compare with server loading state and acknowledgement age. Only change the gate for which a specific failing condition is captured.
5. If all local readiness checks succeed and a fresh token exists but the server fails under long main-thread stalls, treat the native QA session as environment-blocked. Pure puzzle and geometry checks remain separate evidence; they do not replace actual traversal or audible mix QA.

## Snapshot limitations

The snippet is read-only: it does not force acknowledgements, move characters, change attributes, reload assets, or bypass gameplay. It can inspect current asset fetch statuses but cannot recover the private AssetsReady latch or original request payload from the LocalScript. A later asset status Success cannot disprove an earlier latched failure. Capture before timeout cleanup; after cleanup the essential evidence is gone.

## Source references (baseline)

- `ServerScriptService/GameManager.Script.lua`: 1503–1555 ensureWorld; 1617–1630 cleanup; 1998–2042 failure recovery; 2044–2064 loading environment; 2079–2130 preparation/ack barrier.
- `ServerScriptService/Round Loading Runtime.ModuleScript.lua`: 49–54 timeout; 65–80 Run; 89–95 acknowledgement; 95–138 AwaitReady/Commit.
- `StarterPlayer/StarterPlayerScripts/Round Entry Client.LocalScript.lua`: 31–59 ground; 77–81 same-token path; 102–117 preload; 119–140 gates and ack.
- `StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua`: 971 controls ready.
- `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`: 6089 UI ready.
- `ServerScriptService/Level 5 Systems/Level 5 Round Adapter.ModuleScript.lua`: 233–260 cleanup and 261 onward Build.
