# Round Loading Failed — automatic dismissal

Trello: ON6ZsrFJ. Scope is the loading-failure notice in RoundUI, plus a focused offline test. **Done: published v1818 on 9 September 2026 at 23:09:04.335 Danish time.** Root used the mouse through File → Publish to Roblox and confirmed the version in native Studio Output.

## Delivered behavior

- The first failure notice is visible for eight seconds. Both timeout and general failure use the same canonical wording when delivered through the remote or join-time player attribute.
- Returning to the lobby redisplays an unexpired notice without extending its deadline.
- A consumed incident remains recorded after its text expires. This prevents the actual GameManager cleanup replay (`lobby`, then `loadfailed` again) or the persistent attribute from reviving it.
- A new `loadinggame` starts a fresh attempt, so another identical failure receives its own eight seconds. `start` invalidates old timers and disarms delayed failure delivery until another attempt begins.
- A nil/cleared server attribute does not rearm or reset the current notice. Historical unchanged attribute values are consumed locally; the server attribute is not mutated.
- Expiry clears the label only if both its message revision and expected text still belong to this error. This protects new queue/status messages, even identical text, and the existing direct `MISSION BRIEF` label writer.
- The existing queue/escape message timers are unchanged.

Production file: `StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua`. Helpers and bookkeeping use the existing `entryState` table; no top-level locals were added.

Before snapshot: `loading-before.lua`. Exact diff: `round-loading-notice.diff`.

## Verification

```text
Compiled 5 KLOC into 165 KB bytecode
Round loading notice: 96 checks passed
```

Run `tools/tests/test_round_loading_notice.py` with `LUAU_BIN` pointing to the Luau interpreter. The test also invokes the sibling `luau-compile` executable on the entire RoundUI file, catching the project's 200-local limit.

The harness executes the actual message helpers, lobby/queue/loading/entry/start/failure event branches and complete attribute fallback. Only the clock, GUI fields and unrelated presentation functions are stand-ins. Scenarios cover attribute→remote, remote→attribute, initial attribute restoration, late cleanup replay, persistent history, late nil/category changes, lobby at 7.9 seconds, scheduler delay, retry before the old timer fires, identical error text under a new owner, direct briefing replacement, and successful-start disarming.

`git diff --check` found no whitespace errors. The pre-existing mixed-newline warning is unchanged.

Independent critic review: **9/10**, no required changes. The reviewer checked the exact diff, control flow and harness, reran all 96 checks and compiled the complete RoundUI. Root subsequently completed the native visibility/expiry checks below.

## Root-owned native verification and publication

After the scoped push, root confirmed **122/122 scripts compile** and a source audit of **122 matched, zero drift**. The actual Studio client UI received injected RoundStatus/attribute failure signals. Its notice disappeared after **8.000216 seconds**; stale cleanup replay did not revive it, and a newer queue message remained visible beyond the old failure timers. See [native evidence](round-loading-notice-native.json).

A subsequent normal Level 2 launch through the lobby reached `RoundLoadingState=ready`, `RoundActive=true`, `InRound=true`, 100 HP, unanchored character root, hidden loading UI and `controlsReady=true`. All disposable Play helpers were removed by stopping the session before publication.

**Test boundary:** the failure signals were deliberately injected to exercise the actual UI. This was not a newly induced world-build failure or a public multiplayer transport test. The broader transport acceptance work remains on Trello DIktjy8U.

Root then used the mouse through **File → Publish to Roblox**. Native Studio Output confirmed **v1818**, **2026-09-09 23:09:04.335 Danish time**. The card was updated with this evidence, moved to Done and marked complete.
