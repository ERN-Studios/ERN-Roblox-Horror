# S20 / Exit installer V2: mutating transport boundary

V2 is a prepared transport-only correction to frozen V1. V1, its raw pins,
independent peer receipts and failure evidence remain unchanged. Source scope,
both hashes, exact 73-byte forward/reverse anchors, all 213 original guards,
native parser/factory staging/cleanup and bounded export are unchanged. The native
Luau template is byte-identical to V1. Read `../installer-v1/REVIEW.md` for the full
literal proof, closure, meaningful ports, rollback semantics and limits.

The concrete current `tools/sync_from_studio.py` implementation has this boundary:

- `_request` sends a JSON-RPC request and waits until its deadline. A timeout
  throws `StudioMcpError` without sending cancellation or awaiting tool completion.
- A later `_request` ignores and consumes messages whose ID differs from its own.
  A late original Source-CAS completion can therefore be discarded during recovery.
- `call` uses the default 60-second `_request` and also converts a **completed**
  `result.isError` into `StudioMcpError`. Its exception alone cannot distinguish
  that result from transport ambiguity.

V1 used `client.call` for apply/rollback but tracked pending outcomes only for
parser requests. After an apply timeout, V1 could start observation/recovery while
the first CAS was still running. Root and the independent peer identified this
blocker before native execution; no V1 production/native write was performed.

V2 uses one `mutating_request` path for **apply, rollback and compile**:

1. Record the operation, exact code SHA and 180-second deadline; set the pending
   flag immediately before the single `_request`.
2. Keep it set if `_request` throws, times out, or returns no actual completed
   `tools/call` result/content envelope. No cancellation, retry, observation or
   rollback is inferred from local files or elapsed time.
3. Once an actual tool result/content envelope arrives, clear the pending flag.
   Bound text to 20k and the saved response envelope to 24k. Preserve the completed
   response, operation/code provenance and `isError` before decoding/validation.
   A completed `isError` or malformed/oversized completed result remains eligible
   for the existing scoped observation/recovery, including commit-then-error.
4. If apply or rollback remains pending, make **no subsequent native call** and
   no local Source/manifest restoration. Preserve the checkpoint, currently
   observed mirror bytes, available diagnostics and `pendingNativeOperation`.
   Close only the local client transport; that does not certify Lua completion.
   Root must later establish fresh stable originals/Source/editor/lease evidence
   before reconciliation or another mutation.

The actual wrapper port retains all 46 V1 scenarios and adds eight scoped cases:
apply timeout before/after simulated commit, rollback timeout before/after commit,
oversized/malformed completed apply results, and completed rollback errors before
and after commit. The first four require the last
native call to be the pending CAS, exact pending operation recording, no repeated
CAS, and untouched local mirrors. Completed native errors, including the existing
commit-then-error case, still exercise the actual scoped recovery. All native
responses are controlled boundaries; the actual wrapper/filesystem/rollback and
the real bounded source-reader code execute.

A completed rollback `isError` is not itself evidence that native Source is back
to before. V2 makes a fresh target observation after that completed response,
without retrying the CAS. Exact before Source/editor is then exported through the
bounded reader with full-original guards before local restoration is allowed.
An observed candidate/foreign target or an unreadable restoration leaves local
mirrors intact and records the missing restoration evidence. The transport itself
can be known complete while restoration remains unverified; these are reported
separately.

## Independent delta replay

Every receipt destination must be new. No MCP/native/production/index call is
available in these offline entry points:

```powershell
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v2/test_apply_exit_literal_cleanup.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v2/peer-wrapper-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v2/test_exit_native_cas_guards.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v2/peer-native-guard-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v2/test_exit_parser_faults.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v2/peer-parser-faults-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v2/verify_exit_install_proposal.py --receipt-directory artifacts/cleanup-20261010/clients-exit-v1/installer-v2/peer-actual-helper-v1
```

V2 uses distinct immutable installation/checkpoint paths. Only after independent
review and Root's fresh scope decision may Root execute:

```powershell
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v2/apply_exit_literal_cleanup.py --apply
```

The two native factories remain uncalled; original/native/parser/CAS execution and
final parity/console/diff/commit are Root-owned. No gameplay, hardware,
multiplayer, streaming, reserved-server teleport, real-asset or performance pass
is claimed from the helper or parser ports.
