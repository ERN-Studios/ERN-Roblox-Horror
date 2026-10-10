# S04 controlled absence V2 — artifact-only preparation

V2 fixes two bounded V1 trial defects. It does not approve deletion. Root owns the
single native execution after independent review and a fresh Edit preflight.

The exact V1 native completion is preserved in the V1 directory. It failed with
`Preview bake is server-only` before any selector phase or original Parent write.
Both fresh probes were destroyed, all 213 Sources/editor baselines stayed exact,
all five native forests stayed exact, and owned namespaces/connections were
released. No detach trial happened and no gameplay regression was demonstrated.

The second defect was discovered after V1 freeze. The core marks an attempt just
before the actual native setter hook. That hook may refuse at its lease or Parent
CAS before `entry.invoked=true`. V1's inverse eligibility could adopt a foreign
nil root in that case. V2 permits harmless disarming if the uninvoked root is still
its original ServerStorage child; otherwise it preserves the foreign nil state
and marks recovery pending. It never writes an inverse for that uninvoked root.

V2 separately records the real Edit IsClient/IsServer observations and supplies
an explicit **controlled server-data domain** to the read-only actual helper
factories. It tests the actual GetManifest client-domain rejection with no asset
lookup. This is a data-selector/absence test, not an actual server gameplay test.

Unchanged boundaries from V1 remain: exact current-purpose ledger rather than
the lost historical ledger; fresh empty ModuleScript probes returning uncalled
factories; all 213 native Source/editor/class/properties pins; exact five original
forests plus current R4/V2/elevator before/after; no Ensure, Build, Begin, instance
creation from helper bodies, listeners/tasks or AssetService writes; no yielding
API between first detach and final inverse; independent scoped inverse even if an
unrelated Source/event revokes the final pass; probe metadata ownership checks;
independent disconnect/cleanup and retained foreign work; no retry or follow-up
native call on unknown transport completion. No original Destroy, Source setter,
mode toggle or publication exists in the trial.

`trial-config.json` uses the fresh V1-before-parity-v2 native capture: SID
`b609b91a-e648-42ab-ba5f-a996912e9552`, catalog `81115530329fefcca83091e74379f63983ca0aa4b1da0b43bc64e653956623dd`,
213 scripts, 15 remotes, 52 storage roots and 417075 scene descendants. It uses a
new purpose-bound nonce. Native guards refuse changed baselines; this document
does not promise that other actors have stopped editing.

Completed offline gates:

- `offline-faults-v1.json`: actual unchanged core PASS 51 cases / 3018 checks;
  complete assembled source, core/fixture and both actual whole-source factories
  compile (5 units).
- `offline-native-boundaries-attempt-v1.json`: actual V1/V2 setParent,
  rollbackEligibility, B.environment and unique slices, unchanged core and whole
  current RuntimeBake body PASS 38 cases / 2070 checks. It reproduces the V1
  adoption counterexample and V2 preservation at roots 1, 3 and 5, lease refusal,
  immediate Parent CAS refusal, unrelated epoch refusal, harmless disarm and
  owned commit-then-error recovery. Domain nil/true/false cases preserve the
  actual whole-body rejection/selector boundary.
- `run-root-trial.py` without `--apply` verifies assembly and both offline receipt
  input hashes with zero native calls. The native validator requires exactly
  10 original Parent writes, 2 probes, 3 fresh selector phases and 21 controlled
  negatives (six missing/incomplete plus one actual-body client rejection per
  phase). It requires cleanup, original recovery and separate final guards.

These fixtures use table/metatable service and Parent boundaries. They do not
prove engine scheduling, actual Instance events, actual forest absence/recovery,
asset rendering, multiplayer, streaming, gameplay or reference absence.

Independent replay commands use new destinations (existing receipts are never
overwritten):

```powershell
python -B artifacts/cleanup-20261010/storage-authoring-port-v2/test-transaction.py --receipt artifacts/cleanup-20261010/clients-storage-authoring-peer-v2/offline-core-v1.json
python -B artifacts/cleanup-20261010/storage-authoring-port-v2/test-native-boundaries.py --receipt artifacts/cleanup-20261010/clients-storage-authoring-peer-v2/offline-boundaries-v1.json
```

Root-only native execution, after pinning the independent review (including the
exact assembled Source/config/driver), uses a fresh owned run directory:

```powershell
python -B artifacts/cleanup-20261010/storage-authoring-port-v2/run-root-trial.py --apply --studio-id CURRENT_SID --run-directory artifacts/cleanup-20261010/storage-authoring-port-v2/native-run-v1 --peer-review PEER_REVIEW --peer-sha256 EXACT_PEER_SHA
```

Even native PASS leaves `deletionApproved`, `referenceAbsenceCertified` and
`permanentRemoval` false. The compatible unreadable reflected Instance slots,
including protected WeldConstraint endpoints and StarterPlayer.PlaceAvatarRules,
remain a separate reference proof. No omission or protected-property read error
is treated as nil. No five-folder deletion is authorized by this executable.

All V1 code, pins, author/peer receipts and actual native failure remain byte
exact. Earlier V1 invocation-edge review recorded the then-pending completion;
the separate V2 actual-failure addendum records the later known completion.
