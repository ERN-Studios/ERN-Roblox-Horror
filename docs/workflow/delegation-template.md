# One bounded job

One owner and at most one helper across sessions, subagents and CLI jobs.
Use Opus Medium/Standard or gpt-6.1-sol Medium/Standard by default.
The helper does not start more agents or touch shared Studio.

```text
Goal: one concrete outcome.
Result: named files/artifact and a short evidence record.
Owner: session name/ID; helper role if used.
Studio owner: name/ID; helper cannot write/play/send keys/publish in Studio.
Checkout/branch: absolute path and branch.
Files/baseline: scoped paths, commit/hash/live source timestamp as relevant.
Observed: confirmed behaviour and relevant logs or measurements.
Attempted: relevant prior attempts and results.
Checks: proportional compile/offline/runtime/visual checks; pass conditions.
Boundaries: permitted files, work to preserve, no recursive delegation.
Checkpoint: save findings progressively; record remaining checks on a limit.
```

# Transfer Studio ownership

```text
Previous owner: name/ID, confirmed idle; known jobs finished or paused.
New owner: name/ID, tools verified.
Studio: instance, place/universe, Edit/Play mode.
Checkpoint: path, branch/HEAD, pending edits and exact baseline/readback evidence.
Next: one scoped edit/check; who verifies and publishes it.
```

Operator may use one helper if supported. Manually opened sessions also need coordination.
