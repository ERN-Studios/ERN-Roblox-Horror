# Prepared protection inventory transactions

Artifact only. Two full proposed copies and their immutable baselines are under
`proposed/` and `before/`. No runtime file, Roblox DataStore, account, Studio state
or published place was changed. Install only together with the reviewed
`PlayerProtection` service, all required damage/AI integrations and the later UI.
The separate Developer-tag Monetization artifact must be merged explicitly.

## Scope

An additive `Protection` object in the existing v4 player profile stores finite,
nonnegative integer `Charges` and `Revision`, plus one bounded `LastOperation`.
Existing profiles receive zero charges. Existing receipts, Robux support streams,
token rewards, settings, colors and pass ownership remain in their original paths.
Malformed existing inventory remains preserved and unavailable for repair; it is
never converted into an invented refund or wiped by unrelated profile writes.

`BuyProtection` atomically subtracts **5 tokens** and adds **one stored charge**.
`UseProtection` reserves one stored charge without charging tokens again. It
captures `PlayerProtection.GetContext` before waiting on the existing mutation
lock/DataStore, then calls `Activate` with that exact context only after a durable
reservation is confirmed. The server-private service starts the full **5 seconds**
at this point. Already-active, dead, escaped, replaced-character and expired-round
contexts cannot start an effect. The inventory does not heal or resurrect.

Roblox callbacks perform profile transformations only; no activation, remote,
timer or other gameplay effect occurs inside UpdateAsync. The existing
`mutateIdempotent` lock/retry mechanism is reused because this delta has a durable
operation identity. Ordinary unkeyed token/reward mutations keep their original
`mutate` path.

## Operation and recovery contract

The request's session nonce is the profile's **existing** dispatch session ID.
Every new item transaction/finalization also checks that existing claim's owner
and epoch in the current UpdateAsync profile. No extra lease mechanism is added.

One operation is identified by session ID, action kind and the expected revision
plus one. A new buy records `Bought`; a use records `Reserved`, then changes that
same record to `Consumed` or `Refunded`. A matching replay observes the status
before touching balance or charges. Another operation cannot replace an unresolved
local attempt or durable reservation. Every validation/overflow check precedes
balance, count or revision mutation.

The local attempt retains its original context and whether activation happened.
If finalization fails after activation, retry only resolves that same operation;
it never calls Activate again, clears the effect, refreshes its deadline or refunds
a locally known successful activation. An uncertain reserve response does not
start gameplay. A later retry resolves it before deciding whether the original
context is still valid. A failed context receives exactly one keyed charge refund.

The existing atomic load/lease claim refunds an older session's `Reserved`
operation once. It never restores an active effect. Refunds modify the current
callback profile, preserving concurrent token gifts and unrelated changes. A
superseded claimant cannot reclaim the newer owner's reservation. Player/session
cleanup removes private attempts and responses; a save still yielding cannot
recreate them after departure.

There is deliberately **no exactly-once promise across DataStore and gameplay**.
If an effect began but a crash prevented `Consumed` from being durably saved, the
next owner refunds that still-Reserved charge once. This can refund a partially or
fully delivered effect. The owner accepted this player-favorable compromise. The
same unavoidable cross-server gap includes a newer lease claiming/refunding after
an older reservation response was produced but before that old server receives
it; private life/context validation still fences character and round replacement.
No new session resumes an old effect. This should be measured natively with
deferred signals and disconnects before installation is accepted.

## Private client API

Use the existing `ZyntraAction` RemoteEvent:

```lua
ZyntraAction:FireServer("BuyProtection", {
    SessionNonce = profile.ProtectionSessionNonce,
    Revision = profile.ProtectionRevision,
    RequestNonce = "one-unique-value-for-this-UI-intention",
})
-- Same payload shape for "UseProtection".
```

`Revision` is the **expected current** revision, not a newly generated number.
Retry an unknown request with the same action, both nonces and revision. Never substitute
the newer displayed revision into a pending request. One shared UI controller
should own pending state across the store card and in-round HUD.

`RequestNonce` is a client-generated nonempty string of at most 64 characters.
It is transient acknowledgement correlation, not a new durable operation ID.
The new UI should always supply it, change it for a new intention after a terminal
response and preserve it while retrying an unknown outcome. The server accepts
omission for compatibility, but a client omitting it cannot distinguish a delayed
old rejection from a fresh intention at the same revision. A changed RequestNonce
cannot replace an existing pending request or cause another charge/activation.
It is echoed in Pending/LastResponse and never persisted in LastOperation/LastResult.

The existing private profile event and GetProfile result gain:

| Field | Meaning |
|---|---|
| `ProtectionCharges` | Current stored charges, zero for unavailable malformed inventory |
| `ProtectionRevision` | Current durable revision |
| `ProtectionSessionNonce` | Current server-issued existing session ID |
| `ProtectionAvailable` | Persistent, current, open profile with usable inventory; false in Studio |
| `ProtectionPending` | Exact original `{Action, SessionNonce, Revision, RequestNonce?}` command to retry, or nil |
| `ProtectionLastResult` | Last durable terminal command/result: `Bought`, `Consumed` or `Refunded` |
| `ProtectionLastResponse` | Correlated current-session acknowledgement with `Status` and optional `Reason` |

Response statuses `Bought`, `Consumed`, `Refunded` and `Rejected` settle the
matching UI request. `Pending` means processing/unknown and retains its exact
retry command. Only a safe preflight refusal or an authoritative read proving the
original revision is unchanged can produce `Rejected`. An overwritten operation
after an uncertain response cannot be falsely reported as rejected. Its old
session remains unavailable; the new session's profile resolves current inventory.
Different-command rejections never replace the existing `ProtectionPending` owner.

Reasons currently include `NeedFiveTokens`, `NoCharges`, `AlreadyActive`,
`RetryLater`, `AnotherActionPending`, `StaleRevision`, `ProfileUnavailable`,
`InventoryUnavailable`, `Processing`, `SaveUnconfirmed`, plus the service's
eligibility reasons (`Dead`, `NotInRound`, `RoundInactive`, etc.). Reason is a code;
existing message/tone arguments remain human-readable feedback.

The HUD reads `PlayerProtectionActive`, `PlayerProtectionExpiresAt` and
`Workspace:GetServerTimeNow()` only for display. None authorize use. The config
contains `ProtectionItem = {Key="EntityProtection", Name="Entity Protection",
TokenCost=5, DurationSeconds=5, Description=...}`. Token-product descriptions also
mention the new five-token charge alongside permanent upgrades.

## Validation and limits

Run `python artifacts/trello-20260909/protection-prepared/transactions/prepare.py`
to regenerate artifact copies/diff from immutable baselines. It never reads a new
runtime baseline over an existing one or writes a runtime file.

`test_transactions.py` executes the actual prepared state helpers, normalizer,
private DTO, action handler, both complete mutation functions and the actual atomic
load/lease-claim prefix. The complete reviewed PlayerProtection service is loaded
with deterministic fake Roblox clocks, life signals and timers. DataStore hosts
clone per attempt, can discard callbacks on conflict, lose a committed response,
yield for concurrent actions, fail all retries and allow a newer server claim.
The post-load accessibility/messaging scheduling and full remote bootstrap are
outside this fixture; the complete two files are separately compiled.

Coverage includes exact price/stock changes, duplicate and concurrent requests,
4-token and already-active refusals, finite integer/overflow guards, original
context after delayed/unknown saves, exact 4.99/5.00-second boundaries, all three
unknown commit stages, refund idempotence, actual mutate lock contention, token
gift conflicts, load retry/rejoin recovery, stale servers, closing/disconnect
cleanup, no fake Studio purchases, response identity and pending ownership.

Native installation, real persistence behavior and UI remain **unverified**.
This preparation did not contact DataStore APIs or buy anything. Review and final
test totals are recorded in `validation.json`: **215 actual transaction checks**,
**236 existing support receipt checks** against the proposed sources, and full
server/config compile. The independent critic re-ran the transaction checks,
compiled both complete files, verified the runtime baselines and rated this
bounded preparation **9/10** with no remaining code blocker.

Root additionally authorized only `client/ProtectionClient.proposed.lua` and its
`test_client.py` to adopt transient RequestNonce. Their prior artifact versions
are in `before-client/` and their exact delta is `client-contract.diff`. The
complete client module compiles and **51 actual-module checks** pass. They cover
new-intent GUID generation, unchanged unknown retries, an old rejection at the
same durable revision, and adoption of the server's original Pending RequestNonce.
Store/HUD/UIDevice files were not edited. Independent client-contract review also scored **9/10** after re-running all
51 checks; neither score accepts the whole item or a published feature.
