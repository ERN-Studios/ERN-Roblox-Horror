# N01 artifact wrapper: staging-failure ownership

Root's final review found that `run_native_gate.py` allocated/staged the N01
ModuleScript and checked landing before entering its protected call. An empty
baseline, UpdateSourceAsync or landing failure could therefore bypass Destroy
and the final authoritative Source/editor guard. The before tool is checkpointed
at `.git/mongotv-cleanup-20261009/tooling-before/run_native_gate.pre-finally.py`.
The identical bytes are retained in the non-executable
`run_native_gate.before.py.txt` archive. The test prefers that portable archive;
only its absence permits a local-checkpoint fallback. Both paths require the
exact recorded SHA256, so a fresh repository clone can reproduce the before
failure without `.git` task backups. The artifact-local `.gitattributes` marks
only this archive `-text`, preserving its raw bytes with Windows autocrlf too.

Only the N01 generated wrapper changed. It now puts allocation, Name/empty
baseline checks, staging callback, landing verification and require/measurement
inside xpcall. Cleanup and the final original identity/Source/editor check are
independent protected calls after that block. They run on success and error,
and both cleanup and guard errors are retained if both fail. A staging callback
also verifies the new probe's actual Source/editor empty baseline. A fresh
Instance.new ModuleScript remains the staging target; core024 and the rollback
tool were not changed. Success still returns the same report, failed count,
Level1-selected rows and total row count.

`test_native_gate_ownership.py` extracts and evaluates the actual Python
generated-code expression without importing or executing this MCP CLI. Real
Luau executes that wrapper with fake ScriptEditorService/Instance/require/JSON
boundaries and a tiny synthetic probe module. All allocated probes are
test-owned. This tests wrapper failure ownership; it does not execute actual
UIRegression gameplay or contact Studio.

The offline gate passed 23 scenarios / 275 assertions: success, initial editor
conflict, allocation/Name/empty Source/editor failures, staging before and after
callback, callback-current/probe/original Source/editor drift, staged Source/editor
mismatch, require/measurement/decode/encode failures, final original Source/editor/
identity drift, Destroy failure and simultaneous Destroy/original drift. Each
allocated probe receives exactly one Destroy attempt. The final guard runs even
if Destroy throws; such errors are reported rather than claimed as removal.

The exact before wrapper reproduces the staging leak (Destroy count zero).
Temporary no-cleanup and no-final-guard mutants are rejected. Both Python ASTs,
the actual generated Luau compile and scoped diff checks pass. Logs/hashes/counts
are retained in `native-gate-ownership.after.txt` and
`native-gate-ownership-checks.json`.

No Studio calls, runtime/manifest changes, publication or performance claims.
Native ScriptEditorService identity behavior is not certified by fake services.
The current user-owned Play session was untouched. Root owns final artifact
review, instruction/incident records and the local commit.
