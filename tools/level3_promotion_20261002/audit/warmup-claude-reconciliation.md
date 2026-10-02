# Completed Claude warmup review and bounded reconciliation

Actual external review completed with canonical/assistant model
`claude-opus-5-5`, effort `max`, tools `[]`, strict empty MCP config,
elapsed 702.931 seconds, exit 0, no timeout and owned child exit confirmed.
Receipt: `admission/claude-review/retry/result/receipt.json`.
Visible verdict: `admission/claude-review/retry/result/response.md`.
The verdict is **uncertain**, explicitly says no proven blocker from its limited
input, and labels omitted-code concerns as conditional. This is not a clear
verdict or a whole-14-source review. The earlier 300-second attempt timed out
without a verdict and remains recorded separately.

The exact zero-context GM diff and complete helper were reviewed. Both source
hashes matched the parent's 14-source native Source/editor CAS install receipt
at 19:59:36Z. Full installed task hashes are recorded in the review input
manifest. Reported 27 scenarios/86 checks were explicitly offline mocks, with
no actual transport, multiplayer or performance claim.

## Confirmed material issue and minimal fix

Full-source reconciliation confirmed final cohort snapshots used a 120-second
MemoryStore TTL. The destination does not fetch that snapshot until after kit
warmup. When every source member Continues early with provisional packets, the
snapshot is the only final roster authority. A kit wait longer than 120 seconds
can therefore lose final cohort authority and strand admission until its 60s
watchdog rejects it. This is material for published Level 2 -> 3 continuation;
station packets already carry Final=true and do not demonstrate this problem.

Fresh Edit MCP read at 20:21:01Z confirmed correct place/universe and unchanged
installed GM Source/editor SHA256
`8e365508c1e42d9b50e28e8faa3d36ba72eb7b3ba667faf47e92d208262f0ef9`.
`admission/post-review/live-baseline.json` records the exact parity and class.

The minimal candidate changes only Level 3 snapshot expiration to
`Level3KitWarmup.TimeoutSeconds + 2 * Loading.TimeoutSeconds` (1320 seconds);
all other levels retain 120 seconds. Writer ownership, bounded 60s source write
retry, routing store names, packet authority, arrival evidence and admission
math are unchanged. Candidate SHA256:
`ac252224a6f7ed82ccfdbea950a063e4e3e8c70da53322bc912f89b8cab5ad88`.
Installer delta: `admission/post-review/candidate-manifest.json`.
Exact diff: `admission/post-review/GameManager.cohort-ttl.diff`.
This agent drafted only; the parent must fresh-CAS the current Source/editor.

The full candidate compiles. `post-review/test-cohort-ttl.luau` executes the
actual source cohort-writer fragment against a virtual expiring store and the
actual Loading/ Routing modules. Its 32 checks reproduce the old snapshot's
expiration at 130s, demonstrate final cohort availability/admission at 130s,
1200s and 1259s with the new TTL, preserve 120s expiry for Levels 1/2, retain a
single writer, and confirm the new TTL remains bounded. Receipt:
`admission/post-review/cohort-ttl-test-receipt.json`. No live MemoryStore or
published transport is claimed. No additional 15-minute external review was
started for this two-line TTL delta.

## Remaining conditional observations

- Reserved departure guard: retaining observed departure evidence is deliberate.
  Exact existing tracker code subtracts departed observed members and retains
  final authority after its carrier leaves. The completed mock covers early
  final carrier departure plus a later continuer and admits the remaining
  correct roster. Cancelling on any departure would reject that valid cohort.
  A completely empty destination still has a bounded shared wait so later
  source continuers may arrive; no live transport proof is asserted.
- Nil activeEntry at reserved boot: the single reserved admission coroutine has
  no loading attempt before Begin. `failedReservedEntry` is initially false and
  is changed only by failed-entry recovery. The existing late-PlayerAdded path
  may recover a late arrival after terminal failure; that predates warmup.
  No new reproducible overlapping warm recovery was established.
- Epoch cleanup: ordinary public station admission is serialized by one
  `runStation` coroutine. It cannot start a new admission on that object before
  the old `launchStation` returns. Host Cancel invalidates the epoch; reset then
  clears cancelRequested. Revision retirement removes the old object and a new
  bridge gets a distinct station object. Therefore no same-object newer busy
  admission being cleared was established. An old participant receiving a
  late lobbycancel across revision replacement remains a conditional existing
  integration edge, not a reproduced new warmup failure.
- L3-only session pin: valid source transfers reserve one fixed-level server.
  Pinning the original Level 3 session prevents cold completion switching it.
  A hypothetical non-Level-3 target later replaced by another Level 3 session
  is not pinned; if the kit is not ready, RoundAdapter's required ready-kit
  assertion fails safely rather than admitting an incomplete world. No actual
  legitimate cross-level reserved-session switch was established. The review
  did not verify the full unchanged transport provider.
- Latched Ensure error: terminal shared-job failure is deliberate in this
  version; it never duplicates/retries an uncancellable engine worker. Timeout
  permits a still-running worker to finish for future admissions. A completed
  Ensure error leaves this server's Level 3 unavailable; actual transient-error
  recovery is unverified. The public board's try-again wording is generic and
  is not evidence of successful retry. No new worker retry was introduced.
- Raw Level3KitError: helper replication contains up to 500 characters of the
  shared bake error. Supplied bake paths use generated geometry/asset-service
  errors; no credential or personal-data exposure was established. The value
  is diagnostic and has no reviewed client product display consumer. No
  hypothetical exposure change was made without an actual identified risk.

The external verdict remains uncertain; the confirmed TTL issue has a tested
minimal candidate. Other conditions are bounded/static reconciliation, not
claims of native transport or performance verification.
