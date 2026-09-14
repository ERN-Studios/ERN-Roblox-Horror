# Card #69 — Alert developers when an in-game purchase is completed

Status: **code complete, not operational.** Every step that needs a Discord
server, a Render account, the Creator Dashboard or a real purchase is
untouched and listed under *Not done* below.

## What was built

A verified purchase already lands in exactly one place: `ProcessReceipt` in
`ZyntraMonetization`, where `changed == true` means *this* call granted the
product for the first time. That is the only trigger. Everything downstream of
it is fire-and-forget:

```
ProcessReceipt (changed == true)
  -> pcall PurchaseAlerts.Notify(alert)      -- queue + task.spawn, never yields
       -> POST to the relay, bearer token    -- retries, rate limit, dedupe
            -> relay.py forwards a Discord embed to #dev-purchase-alerts
```

The relay exists because a Roblox game server **cannot** POST to discord.com:
Discord answers 403 to Roblox's `HttpService` user agent and the user agent
cannot be overridden. The relay is the smallest thing that bridges that, and it
is where the webhook URL lives — never in the place file, never on a client.

### Files

| File | Lines | What |
|---|---:|---|
| `ServerScriptService/PurchaseAlerts.ModuleScript.lua` | 182 | new. `Notify(alert)` — queue, worker, retries, rate limit, in-memory dedupe |
| `ServerScriptService/ZyntraMonetization.Script.lua` | +27 | the only edit: a guarded require at the top, a guarded call in `ProcessReceipt` |
| `tools/purchase_alert_relay/relay.py` | 184 | new. stdlib-only authenticated relay -> Discord webhook |
| `tools/purchase_alert_relay/README.md` | — | new. run/deploy, the wire contract, the owner-only prerequisites |
| `tools/tests/test_purchase_alerts.py` | — | new. the real module under a fake Roblox host in luau |
| `tools/tests/test_purchase_alert_relay.py` | — | new. the real relay over real HTTP against a fake Discord |

Nothing else was touched. No Studio, no git, no manifest, no graphify.

### The module

`PurchaseAlerts.Notify(alert)` takes `{PurchaseId, ProductId, ProductKey,
ProductName, Kind, RobuxSpent, PlayerName, UserId, IsStudio}`, returns nothing,
and is safe to call from a receipt:

- **Never yields the caller.** It appends to a queue and, if no worker is
  running, `task.spawn`s one. All HTTP happens on the worker thread.
- **Never throws.** The worker `pcall`s its own drain loop; `ProcessReceipt`
  `pcall`s the call as well.
- **Config resolved once, lazily.** `HttpService:GetSecret("ZYNTRA_PURCHASE_ALERT_URL")`
  and `…_TOKEN` first (the Secret is used directly as the `Url`, and via
  `secret:AddPrefix("Bearer ")` as the `Authorization` header — never read or
  concatenated in plain). Falls back to `ServerStorage.PurchaseAlertConfig`
  attributes `Endpoint` / `Token` for Studio and local testing. Neither
  configured: disabled for the life of the server after one warn,
  `[PurchaseAlerts] not configured; alerts disabled`, printing no value.
- **Payload** — `{purchaseId, productId, productKey, productName, kind, robux,
  playerName, userId, placeId, jobId, timestamp, test}`, `timestamp` from
  `DateTime.now():ToIsoDate()`, `test = true` in Studio. Username and userId
  are the only personal fields; no display name, no country, no IP, no
  balances.
- **Retries** on network error, 408, 429 and 5xx: at most 3 attempts, backoff
  2 s then 5 s (`RETRY_DELAYS` documents the 10 s third rung as the ceiling if
  `MAX_ATTEMPTS` is ever raised). Any other 4xx drops the alert with one warn
  that names the status code and nothing else.
- **`Http requests are not enabled`** disables the module for the rest of the
  server after one attempt — the state this place is in today.
- **Rate limit** 20 sends per rolling 60 s; queue capacity 50, oldest dropped
  with a running count in the warn.
- **Dedupe** by `PurchaseId` in memory, for the server's lifetime. The durable
  dedupe is unchanged: the profile's permanent `ReceiptIds` list, which is why
  the caller only ever calls `Notify` on a first-time grant.

`PurchaseAlerts._configure(deps)` is the test seam (HttpService, ServerStorage,
`wait`, `clock`, `spawn`, `warn`, `now`, placeId, jobId) and doubles as the
state reset. Production calls it once, argument-less, at the bottom of the
module — so the defaults have one definition.

### The receipt hook

27 lines in `ZyntraMonetization`, nothing else changed:

- top of file, next to the other requires: `script.Parent:FindFirstChild("PurchaseAlerts")`
  (not `WaitForChild` — a missing module must not block) then `pcall(require, …)`.
  A missing or throwing module leaves `PurchaseAlerts` nil.
- in `ProcessReceipt`, inside `if changed or alreadyGranted then`, after the
  re-entry `task.spawn` and before the `PurchaseGranted` return:
  `if changed and PurchaseAlerts then pcall(PurchaseAlerts.Notify, {…}) end`.

`changed` is the whole dedupe contract at this layer: a Roblox retry of an
already-granted PurchaseId takes the `alreadyGranted` path and alerts nothing.
Granting, the `ReceiptIds` write, the re-entry auto-use and the support-ranking
sync are untouched.

### The relay

`tools/purchase_alert_relay/relay.py`, standard library only.
`POST /` with `Authorization: Bearer $RELAY_TOKEN` (compared with
`hmac.compare_digest`), body capped at 8 KB.

| | |
|---|---|
| `200` | forwarded to Discord |
| `202` | `purchaseId` already seen — not forwarded again |
| `400` | unreadable body, or no `purchaseId` |
| `401` | wrong or missing token |
| `502` | Discord refused twice — the id is *not* remembered, so the game's retry works |

`GET /healthz` -> `200 ok`. Embed: **💰 NEW PURCHASE** with Product
(name + id), Price (`N Robux`, or `STUDIO TEST (0)` when `test`), Player
(name + userId), Time, Purchase ID, Place / Job. Optional `DEDUPE_FILE` keeps
forwarded PurchaseIds across restarts (last 5000). The webhook URL and the
token are never logged — logs carry method, path and status only.

## Tests

```sh
python tools/tests/test_purchase_alert_relay.py
python tools/tests/test_purchase_alerts.py     # needs LUAU_BIN or luau on PATH
```

Results on 2026-09-14 (Python 3.11.4, luau 0.737):

```
purchase alert relay: 30 checks passed
purchase alerts: 97 checks passed
```

`test_purchase_alert_relay.py` starts the real `relay.py` as a subprocess on a
free localhost port with an in-process fake Discord: bad token -> 401 and no
forward; valid -> 200 and the fake webhook received an embed whose six fields
carry the right product, price, player, time, PurchaseId and place/job;
duplicate purchaseId -> 202 with no second forward; Studio alert -> price reads
`STUDIO TEST (0)`; bad JSON, missing purchaseId and a wrong path -> 400/400/404
with no forward; Discord 500 -> relay 502 after two forward attempts and the id
is *not* remembered, so the same alert succeeds on the next try; the dedupe file
is written, survives a relay restart, and contains no rejected id; and no log
line from either relay process contains the token or the webhook URL.

`test_purchase_alerts.py` runs the **real module source** (verbatim, no copy)
under a fake Roblox host in luau, plus **the real `ProcessReceipt` hook block
sliced out of `ZyntraMonetization.Script.lua`** so the test breaks if either
file drifts: not configured -> disabled, exactly one warn, `Notify` neither
throws nor yields; configured -> one POST with `Content-Type: application/json`,
`Authorization: Bearer …` and all twelve payload fields; the Secrets path keeps
the URL an opaque Secret object and the header the `AddPrefix` result; duplicate
PurchaseId -> one POST; 500 then 200 -> 2 attempts with a 2 s fake wait; 429,
408 and 503 -> retried; 403 -> dropped with one warn naming only the status;
network throw -> 3 attempts, waits 2 s and 5 s, then one "not delivered" warn;
`Http requests are not enabled` -> disabled after the first attempt and silent
after; 21 notifies -> 20 sends inside the window, the 21st waits the full 60 s
and then sends; with a deferred `task.spawn`, `Notify` returns having done zero
network work on the calling thread; no warn on any failure path contains the
token, the endpoint or the relay host. The hook block itself: `changed` ->
exactly one alert carrying the receipt's own PurchaseId, `alreadyGranted` ->
none, Studio -> flagged `test:true` with `robux:0`, and a nil / empty /
exploding module produces no alert and cannot break the receipt.

Both Lua files compile: `luau-compile --binary` clean on
`PurchaseAlerts.ModuleScript.lua` and `ZyntraMonetization.Script.lua`.

### Two pre-existing failures found, not caused by this card

Both were already broken at `HEAD` — verified with `git show HEAD:…`, and
neither string appears anywhere in this card's diff:

- `tools/tests/test_support_product_receipts.py` slices on the marker
  `local function addSupporterTag`, which no longer exists in
  `ZyntraMonetization` (0 hits at HEAD). `ValueError: substring not found`.
- `tools/tests/test_token_grants.py` expects UserId `833029598`
  (Detective_Costeau) in the `DevAccess` allowlist; it is no longer there
  (0 hits at HEAD), so "each allowlisted UserId can grant to self" fails.

Worth their own card — they are stale markers in the tests, not faults in the
game code.

## Security model

| Value | Lives in | Reachable by |
|---|---|---|
| Discord webhook URL | the relay's environment on Render | the relay process only |
| Relay bearer token | Roblox Secret `ZYNTRA_PURCHASE_ALERT_TOKEN` + `RELAY_TOKEN` | the game server, the relay |
| Relay URL | Roblox Secret `ZYNTRA_PURCHASE_ALERT_URL` | the game server |
| Studio/local fallback | `ServerStorage.PurchaseAlertConfig` attributes | the server only — ServerStorage is never replicated |

No client ever sees any of it: no remote carries the endpoint, no attribute is
set on a player, no value is printed. A Roblox `Secret` cannot be read back into
a string by Lua at all — it can only be handed to `RequestAsync`. The module
logs status codes and its own state, never a URL, a token, a body, or an error
string (an error string can quote the URL, so the worker's catch-all warn omits
it deliberately). The relay compares the token in constant time and its logs
carry method, path and status only.

The alert contains a username and a userId because the card asks who bought
what; nothing else about the player travels.

## Not done — owner only

None of these were performed, and until all six are, `PurchaseAlerts` stays
disabled and warns once per server. Receipts, grants and dedupe are unaffected
either way. The full version with exact menu paths is in
`tools/purchase_alert_relay/README.md`.

1. **No Discord channel.** `#dev-purchase-alerts` does not exist. It must be
   created private: deny `@everyone` View Channel, allow the dev/admin role
   only — the alerts name players and the Robux they paid.
2. **No webhook.** Nothing was created in Discord and no webhook URL exists.
3. **No relay deployment.** `relay.py` has never run outside the test suite.
   It needs a Render Web Service (root `tools/purchase_alert_relay`, start
   `python relay.py`, health check `/healthz`, Starter plan — a free instance
   sleeps and would drop the first alert) with `RELAY_TOKEN` and
   `DISCORD_WEBHOOK_URL` set.
4. **No Roblox Secrets.** `ZYNTRA_PURCHASE_ALERT_URL` and
   `ZYNTRA_PURCHASE_ALERT_TOKEN` are not in the Creator Dashboard.
5. **HttpService is still off.** `Allow HTTP Requests` (Game Settings ->
   Security) was not changed. With it off the module disables itself after one
   attempt.
6. **No real purchase.** Nothing was bought, in Studio or in production. The
   card's done-when ends with one real cheap purchase and confirming exactly one
   alert in the channel — and that a Roblox receipt retry does not produce a
   second.

One more step for whoever lands this: **the ModuleScript instance does not
exist in Studio.** The repo file is `ServerScriptService/PurchaseAlerts.ModuleScript.lua`;
the sync tools cannot create new instances, so it has to be created in Studio
(`execute_luau` + `UpdateSourceAsync`) and then given a `studio-sync-manifest.json`
entry via `tools/studio_source_contract.py`. `ZyntraMonetization`'s edit is a
normal push, and it is safe to push *before* the module exists — the
`FindFirstChild` is nil-guarded.
